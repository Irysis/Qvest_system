## FIX_1341: BM+ESBR Weighted Sum + Defense Core
## Fix: pmin(Z[BM], Z[ESBR]) → 0.5*Z[BM]+0.5*Z[ESBR] 가중합산 전환
## Defense 비중 40→20%. Parent: STR_1341 (Grade F, CAGR 0.98%, Sharpe 0.083)
## PIT: C13(Z_Score_Aligned), C14(Usable_Date), C15(load_month_factors)
cat("=== FIX_1341: BM+ESBR Weighted Sum + Defense Core ===\n")
set.seed(1341); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME   <- "WeightedSumDefenseCore"
STRATEGY_ID     <- "FIX_1341"
STRATEGY_FAMILY <- "value_defense"
QEPM_AUTO_COMMIT <- TRUE

# ============================================================================
# Step 0: Path Resolution
# ============================================================================
SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    p <- sub("--file=", "", file_arg[1])
    p <- gsub("~+~", " ", p, fixed = TRUE)
    dirname(p)
  } else getwd()
})

INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight] ", e$message, "\n"))

# Factor DB connector (C15: load_month_factors() only)
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))

# ============================================================================
# Constants
# ============================================================================
LIQ_THRESHOLD  <- 2e8
N_HOLDINGS     <- 30L

# ============================================================================
# Phase 1: Load Data
# ============================================================================
cat("[Phase 1] Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_dates <- sort(unique(RAWDATA$Date))
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date
all_signal_dates <- sort(all_signal_dates)

# Factor DB available from ~2006-06
monthly_dates <- all_signal_dates[all_signal_dates >= as.Date("2006-06-01")]
cat(sprintf("  Monthly signal dates: %d (%s ~ %s)\n",
            length(monthly_dates), min(monthly_dates), max(monthly_dates)))

# Liquidity filter: t-1 lagged (C10)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# ============================================================================
# Phase 2: Factor Construction — Defense + BM*ESBR Synergy
# ============================================================================
cat("[Phase 2] Loading factor engine...\n")
source(file.path(SCRIPT_DIR, "factor_engine.R"))

factor_list <- list()
n_done <- 0L; n_skipped <- 0L

for (sig_d in monthly_dates) {
  sig_d <- as.Date(sig_d)

  # C15: load_month_factors()
  fdb <- tryCatch(
    load_month_factors(sig_d),
    error = function(e) NULL
  )
  if (is.null(fdb) || nrow(fdb) == 0) { n_skipped <- n_skipped + 1L; next }

  # RAWDATA snapshot with liquidity + sector
  rawdata_snap <- RAWDATA[Date == sig_d, .(Ticker, Sector, AvgTV20)]

  # Compute synergy + defense scores
  scored <- compute_synergy_defense_scores(sig_d, fdb, rawdata_snap)
  if (is.null(scored) || nrow(scored) < 20) { n_skipped <- n_skipped + 1L; next }

  factor_list[[length(factor_list) + 1L]] <- scored
  n_done <- n_done + 1L

  if (n_done %% 50 == 0) cat(sprintf("  [%d/%d] %s\n", n_done, length(monthly_dates), sig_d))
}

FACTORS <- rbindlist(factor_list)
if (nrow(FACTORS) == 0) stop("[STR_1341] FACTORS empty — no valid signal dates.")
setorder(FACTORS, Date, -Score)
cat(sprintf("[Phase 2] %d dates scored, %d skipped | %s factor rows\n",
            n_done, n_skipped, format(nrow(FACTORS), big.mark = ",")))

# Cleanup
for (col in c("TradingValue", "AvgTV20", "YM"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
suppressWarnings(rm(fdb, rawdata_snap, scored, factor_list))
gc(verbose = FALSE)

# ============================================================================
# Phase 3: Backtest — N=30, EW, VT=0.15, Buffer 40/20
# ============================================================================
cat("[Phase 3] Running backtest...\n")
sim <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings    = N_HOLDINGS,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 40L, entry_n = 20L),
  vol_target    = 0.15,
  vol_lookback  = 60L
)

# ============================================================================
# Phase 4: DD Brake (t-1 lagged, C2/C5)
# ============================================================================
cat("[Phase 4] DD Brake...\n")
strat_ret   <- as.numeric(sim$strategy_xts)
n_f         <- length(strat_ret)
strat_dates <- as.Date(index(sim$strategy_xts))

nav_vec <- cumprod(1 + strat_ret)
dd_vec  <- 1 - nav_vec / cummax(nav_vec)

DD_START <- 0.15; DD_FULL <- 0.35; DD_MIN_EXP <- 0.30
dd_exposure <- ifelse(dd_vec <= DD_START, 1.0,
                      ifelse(dd_vec >= DD_FULL, DD_MIN_EXP,
                             pmax(DD_MIN_EXP, 1.0 - (dd_vec - DD_START) / (DD_FULL - DD_START) * (1.0 - DD_MIN_EXP))))
dd_exp_lagged <- c(1.0, head(dd_exposure, -1))  # t-1 lag (C5)
after_dd <- strat_ret * dd_exp_lagged

# ============================================================================
# Phase 5: MRS Overlay (Regime Engine v7.1)
# ============================================================================
cat("[Phase 5] MRS Overlay (v7.1)...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
daily_regime <- build_daily_regime(strat_dates)

MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN_EXP <- 0.30
soft_mrs_exp <- numeric(n_f)
for (i in seq_len(n_f)) {
  mrs_val <- daily_regime[Date == strat_dates[i], MRS]
  if (length(mrs_val) == 0 || is.na(mrs_val)) mrs_val <- 0
  if (mrs_val < MRS_LOW)       soft_mrs_exp[i] <- 1.0
  else if (mrs_val >= MRS_HIGH) soft_mrs_exp[i] <- MRS_MIN_EXP
  else soft_mrs_exp[i] <- 1.0 - (mrs_val - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1.0 - MRS_MIN_EXP)
}
final_ret <- after_dd * soft_mrs_exp

# ============================================================================
# Phase 6: Final Assembly
# ============================================================================
cat("[Phase 6] Final assembly...\n")
combined_xts <- xts::xts(final_ret, order.by = strat_dates)
names(combined_xts) <- "Strategy"

sim$strategy_xts <- combined_xts
sim$bm_xts <- sim$bm_xts[strat_dates]
sim$DAILY_NAV_DT <- data.table(
  Date         = strat_dates,
  NAV          = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)

perf    <- summarise_perf(combined_xts, STRATEGY_ID)
bm_perf <- summarise_perf(sim$bm_xts, "KOSPI200")

cat(sprintf("\n  %s Results\n", STRATEGY_ID))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf$CAGR, perf$Sharpe, perf$MDD))
print(rbind(perf, bm_perf))

# ============================================================================
# Phase 7: Output + Analysis + Hurdle + Telegram
# ============================================================================
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
fwrite(rbind(perf, bm_perf), file.path(out_dir, "performance.csv"))

generate_charts(sim, output_dir = out_dir,
                strategy_name = sprintf("%s: %s", STRATEGY_ID, STRATEGY_NAME))

tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, out_dir,
               strategy_name = STRATEGY_ID)
}, error = function(e) cat("[Analysis]", e$message, "\n"))

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

# ---- Judge Mailbox: send hurdle result for validation ----
tryCatch({
  judge_inbox <- file.path(PROJECT_ROOT, "qepm", "mailbox", "judge", "inbox")
  if (dir.exists(judge_inbox) && !is.null(hurdle)) {
    msg <- list(
      strategy_id   = STRATEGY_ID,
      strategy_name = STRATEGY_NAME,
      family        = STRATEGY_FAMILY,
      timestamp     = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hurdle_result = hurdle,
      output_dir    = out_dir,
      request       = "validate"
    )
    msg_path <- file.path(judge_inbox, paste0(STRATEGY_ID, "_validate_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json"))
    writeLines(jsonlite::toJSON(msg, auto_unbox = TRUE, pretty = TRUE), msg_path)
    cat(sprintf("[Judge Mailbox] Sent validation request: %s\n", basename(msg_path)))
  }
}, error = function(e) cat("[Judge Mailbox]", e$message, "\n"))

if (isTRUE(QEPM_AUTO_COMMIT) && exists("hybrid_commit")) {
  tryCatch({
    hybrid_commit(strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
                  hurdle_result = hurdle, artifact_paths = list(out_dir))
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

cat(sprintf("\n[%s] Complete.\n", STRATEGY_ID))
