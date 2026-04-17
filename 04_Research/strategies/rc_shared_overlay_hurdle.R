## RC Shared Overlay + Hurdle — DD Brake + MRS + Cash + Output
## Requires: sim, FACTORS, RAWDATA, BM_DT, regime_log_dt, STRATEGY_ID, STRATEGY_NAME
## Requires: INFRA_DIR, SCRIPT_DIR defined
## Optional: USE_DD_BRAKE (default TRUE), USE_MRS (default TRUE)

if (!exists("USE_DD_BRAKE")) USE_DD_BRAKE <- TRUE
if (!exists("USE_MRS")) USE_MRS <- TRUE

strat_ret <- as.numeric(sim$strategy_xts)
n_f <- length(strat_ret)
strat_dates <- as.Date(index(sim$strategy_xts))

# DD Brake (1-day lagged)
if (USE_DD_BRAKE) {
  cat("[Overlay] DD Brake...\n")
  nav_med <- cumprod(1 + strat_ret)
  dd_med  <- 1 - nav_med / cummax(nav_med)
  dd_exp <- ifelse(dd_med <= 0.04, 1.0,
                   ifelse(dd_med >= 0.35, 0.30,
                          pmax(0.30, 1.0 - (dd_med - 0.04) / 0.31 * 0.70)))
  dd_exp_lag <- c(1.0, head(dd_exp, -1))
  strat_ret <- strat_ret * dd_exp_lag
}

# MRS soft ramp
if (USE_MRS) {
  cat("[Overlay] MRS soft ramp...\n")
  source(file.path(REGIME_DIR, "regime_engine_daily.R"))
  daily_regime <- build_daily_regime(strat_dates)

  MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN_EXP <- 0.30
  mrs_exp <- numeric(n_f)
  for (i in seq_len(n_f)) {
    mrs_val <- daily_regime[Date == strat_dates[i], MRS]
    if (length(mrs_val) == 0 || is.na(mrs_val)) mrs_val <- 0
    if (mrs_val < MRS_LOW) mrs_exp[i] <- 1.0
    else if (mrs_val >= MRS_HIGH) mrs_exp[i] <- MRS_MIN_EXP
    else mrs_exp[i] <- 1.0 - (mrs_val - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1.0 - MRS_MIN_EXP)
  }
  strat_ret <- strat_ret * mrs_exp
}

# Cash overlay from regime_log_dt
if ("cash" %in% names(regime_log_dt) && any(regime_log_dt$cash > 0, na.rm = TRUE)) {
  cat("[Overlay] Cash allocation...\n")
  setkey(regime_log_dt, Date)
  cash_pct <- numeric(n_f)
  for (i in seq_len(n_f)) {
    d <- strat_dates[i]
    idx_r <- regime_log_dt[Date <= d, .N]
    if (idx_r > 0) {
      cv <- regime_log_dt[idx_r, cash]
      if (!is.na(cv)) cash_pct[i] <- cv
    }
  }
  strat_ret <- strat_ret * (1.0 - cash_pct)
  cat(sprintf("  Avg cash: %.1f%%\n", mean(cash_pct) * 100))
}

final_ret <- strat_ret

# Final Assembly
cat("[Final] Assembly...\n")
combined_xts <- xts(final_ret, order.by = strat_dates)
names(combined_xts) <- "Strategy"

sim$strategy_xts <- combined_xts
sim$bm_xts <- sim$bm_xts[strat_dates]
sim$DAILY_NAV_DT <- data.table(
  Date = strat_dates,
  NAV = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)

perf <- summarise_perf(combined_xts, STRATEGY_ID)
bm_perf <- summarise_perf(sim$bm_xts, "KOSPI200")

cat(sprintf("\n  %s Results\n", STRATEGY_ID))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf$CAGR, perf$Sharpe, perf$MDD))
print(rbind(perf, bm_perf))

# Output
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
fwrite(rbind(perf, bm_perf), file.path(out_dir, "performance.csv"))
fwrite(regime_log_dt, file.path(out_dir, "regime_log.csv"))

generate_charts(sim, output_dir = out_dir,
                strategy_name = sprintf("%s: %s", STRATEGY_ID, STRATEGY_NAME))

source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS, RAWDATA, BM_DT, out_dir,
             strategy_name = STRATEGY_ID)

hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_ID,
                  output_dir = out_dir)
}, error = function(e) { cat("Hurdle error:", e$message, "\n"); NULL })

tryCatch({
  if (!is.null(hurdle)) {
    hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
    tg_strategy_result_with_chart(STRATEGY_ID, hr, out_dir)
  }
}, error = function(e) cat("[TG]", e$message, "\n"))

cat(sprintf("\n[%s] Complete.\n", STRATEGY_ID))
