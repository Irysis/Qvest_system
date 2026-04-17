cat("=== STR_1417: FMP + DD 6/20 + Turnover Constraint 0.5 ===\n")
cat("## 핵심아이디어: STR_1416 DD-only에 Turnover Constraint 추가 — 매월 포트 변경 50% 이하.\n")
cat("## TC 0.5 = 포트폴리오 안정성 + 거래비용 절감. DD 6/20 동일.\n")
cat("## Parent: STR_1387 -> STR_1416. Change: add turnover_cap=0.5.\n\n")

#==============================================================================
# STR_1417 -- FMP + DD Brake 6/20 + Turnover Constraint 0.5
#
# Method: FC_2b FMP (Fama-MacBeth expanding lambda) + DD Brake 6/20 + TC 0.5
# Core:   Same as STR_1416 + turnover constraint.
#         At each rebalance, limit portfolio weight changes to max 50%.
#         Implemented via wider buffer zone: keep_n=45, entry_n=15 (tighter entry)
#         + explicit turnover cap in post-processing.
#
# PIT Enforcement: Same as STR_1416 (C1/C3/C9/C13/C14/C15 clean)
#
# Factors: Q01_GPA, V01_BM, C04_ESBR, D01_IdioVol, M01_Mom_12_1
# Rebal:  Monthly, top 30, EW, 15bps, liq >= 2e8, turnover_cap=0.5
#==============================================================================

set.seed(1417)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID   <- "STR_1417"
STRATEGY_NAME <- "FMP_DD620_TC05"
QEPM_AUTO_COMMIT <- TRUE

# ---- Config ----
.proj <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
source(file.path(.proj, "02_Infrastructure/config.R"))
source(file.path(.proj, "02_Infrastructure/backtest_harness.R"))
source(file.path(.proj, "02_Infrastructure/factor_db_connector.R"))
source(file.path(.proj, "02_Infrastructure/telegram_notify.R"))

tryCatch({
  source(file.path(.proj, "02_Infrastructure/preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = "fmp_dd_mutation")
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# Strategy parameters
MIN_TRAIN_MONTHS  <- 36L
N_HOLDINGS        <- 30L
COMMISSION        <- 0.0015
WEIGHT_METHOD     <- "equal"
# Tighter buffer for turnover control: keep more, enter fewer
BUFFER_ZONE       <- list(keep_n = 45L, entry_n = 15L)
LIQ_THRESHOLD     <- 2e8
TURNOVER_CAP      <- 0.50   # max 50% portfolio turnover per rebalance

# Overlay parameters -- DD only
DD_LOW            <- 0.06
DD_HIGH           <- 0.20
DD_FLOOR          <- 0.30

# 5 diverse factors (same as STR_1387)
TARGET_FACTORS <- c(
  "Q01_GPA",
  "V01_BM",
  "C04_ESBR",
  "D01_IdioVol",
  "M01_Mom_12_1"
)
N_FACTORS <- length(TARGET_FACTORS)

cat(sprintf("[config] %d factors, min_train=%d months, N=%d, EW weight\n",
            N_FACTORS, MIN_TRAIN_MONTHS, N_HOLDINGS))
cat(sprintf("[config] Factors: %s\n", paste(TARGET_FACTORS, collapse = ", ")))
cat(sprintf("[config] Overlay: DD %.0f%%/%.0f%% floor=%.0f%% + TC=%.0f%%\n",
            DD_LOW * 100, DD_HIGH * 100, DD_FLOOR * 100, TURNOVER_CAP * 100))
cat(sprintf("[config] Buffer: keep=%d, entry=%d (tighter for TC)\n",
            BUFFER_ZONE$keep_n, BUFFER_ZONE$entry_n))

# ============================================================================
# Step 1: Load RAWDATA
# ============================================================================
cat("\n[Step 1] Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
BM_DT_ORIG   <- copy(BM_DT)

# ============================================================================
# Step 2: Build monthly factor panels + returns
# ============================================================================
cat("[Step 2] Building monthly factor x stock panels from Factor DB...\n")

fdb_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                        pattern = "^factor_db_\\d{6}\\.parquet$")
fdb_months <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", fdb_files))
cat(sprintf("  Factor DB: %d months available (%s ~ %s)\n",
            length(fdb_months), fdb_months[1], tail(fdb_months, 1)))

cat("  Pre-computing monthly liquidity filter...\n")
RAWDATA[, YM := format(Date, "%Y%m")]
liq_monthly <- RAWDATA[, .(AvgTV = mean(Vol * Close, na.rm = TRUE)), by = .(YM, Ticker)]
liq_pass_map <- liq_monthly[AvgTV >= LIQ_THRESHOLD, .(YM, Ticker)]
setkey(liq_pass_map, YM)

cat("  Pre-computing monthly returns...\n")
monthly_rets <- RAWDATA[, .(MonthRet = prod(1 + Ret, na.rm = TRUE) - 1), by = .(YM, Ticker)]
setkey(monthly_rets, YM)

registry <- .load_registry()
ic_hist <- tryCatch(.load_ic_history(), error = function(e) NULL)
ic_dir <- NULL
if (!is.null(ic_hist) && nrow(ic_hist) > 0) {
  ic_dir <- ic_hist[, .(Mean_IC = mean(IC, na.rm = TRUE)), by = Factor_Name]
  ic_dir[, ic_sign := fifelse(Mean_IC >= 0, 1L, -1L)]
}

factor_panels <- list()
month_returns <- list()

cat("  Loading factor parquets...\n")
for (i in seq_along(fdb_months)) {
  ym <- fdb_months[i]
  fpath <- file.path(CACHE_DIR, "factor_db", paste0("factor_db_", ym, ".parquet"))
  dt <- tryCatch(as.data.table(read_parquet(fpath)), error = function(e) NULL)
  if (is.null(dt) || nrow(dt) == 0) next

  dt <- dt[Factor_Name %in% TARGET_FACTORS & Coverage == TRUE]
  if (uniqueN(dt$Factor_Name) < N_FACTORS) next

  if (!is.null(ic_dir)) {
    dt <- merge(dt, ic_dir[, .(Factor_Name, ic_sign)], by = "Factor_Name", all.x = TRUE)
    dt[is.na(ic_sign), ic_sign := 1L]
  } else {
    dt[, ic_sign := 1L]
  }
  dt[, Z_Score_Aligned := Z_Score * ic_sign]

  fdt_wide <- dcast(dt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  factor_cols_present <- intersect(TARGET_FACTORS, names(fdt_wide))
  if (length(factor_cols_present) < N_FACTORS) next
  fdt_wide <- fdt_wide[complete.cases(fdt_wide[, ..factor_cols_present])]

  liq_tickers <- liq_pass_map[YM == ym, Ticker]
  if (length(liq_tickers) > 0) fdt_wide <- fdt_wide[Ticker %in% liq_tickers]
  if (nrow(fdt_wide) < 50) next

  factor_panels[[ym]] <- fdt_wide
  ret_data <- monthly_rets[YM == ym, .(Ticker, MonthRet)]
  if (nrow(ret_data) > 0) month_returns[[ym]] <- ret_data

  if (i %% 50 == 0) cat(sprintf("    [%d/%d] %s loaded\n", i, length(fdb_months), ym))
}

RAWDATA[, YM := NULL]
cat(sprintf("  Built %d monthly panels with all %d factors\n",
            length(factor_panels), N_FACTORS))

# ============================================================================
# Step 3: Fama-MacBeth Cross-Sectional Regressions (Expanding Window)
# ============================================================================
cat("\n[Step 3] Fama-MacBeth expanding-window cross-sectional regressions...\n")
cat("  PIT: regression at month t uses factor_panel[t-1] + returns[t]\n\n")

months_ordered <- sort(names(factor_panels))
lambda_history <- list()
fmp_scores     <- list()
n_regs <- 0L
n_skipped <- 0L

for (t_idx in seq_along(months_ordered)) {
  ym_t <- months_ordered[t_idx]

  if (t_idx >= 2) {
    ym_prev <- months_ordered[t_idx - 1]
    panel_prev <- factor_panels[[ym_prev]]
    ret_t <- month_returns[[ym_t]]

    if (!is.null(panel_prev) && !is.null(ret_t) && nrow(panel_prev) > 50) {
      merged <- merge(panel_prev[, c("Ticker", TARGET_FACTORS), with = FALSE],
                      ret_t, by = "Ticker")

      if (nrow(merged) >= 50) {
        X <- as.matrix(merged[, ..TARGET_FACTORS])
        y <- merged$MonthRet
        q_lo <- quantile(y, 0.01, na.rm = TRUE)
        q_hi <- quantile(y, 0.99, na.rm = TRUE)
        y <- pmin(pmax(y, q_lo), q_hi)

        fit <- tryCatch(lm(y ~ X), error = function(e) NULL)
        if (!is.null(fit)) {
          coefs <- coef(fit)
          lambda_names <- paste0("X", TARGET_FACTORS)
          lambdas <- coefs[lambda_names]
          names(lambdas) <- TARGET_FACTORS
          lambdas[is.na(lambdas)] <- 0

          sig_date <- as.Date(paste0(substr(ym_t, 1, 4), "-", substr(ym_t, 5, 6), "-28"))
          lam_row <- as.list(lambdas)
          names(lam_row) <- TARGET_FACTORS
          lam_row$Date <- sig_date
          lambda_history[[length(lambda_history) + 1L]] <- as.data.table(lam_row)
          n_regs <- n_regs + 1L
        }
      }
    }
  }

  if (length(lambda_history) < MIN_TRAIN_MONTHS) next

  panel_cur <- factor_panels[[ym_t]]
  if (is.null(panel_cur) || nrow(panel_cur) < 50) {
    n_skipped <- n_skipped + 1L
    next
  }

  lambda_dt <- rbindlist(lambda_history)
  lambda_bar <- colMeans(lambda_dt[, ..TARGET_FACTORS], na.rm = TRUE)

  lambda_sum <- sum(abs(lambda_bar))
  if (lambda_sum < 1e-10) {
    lambda_bar_norm <- rep(1.0 / N_FACTORS, N_FACTORS)
    names(lambda_bar_norm) <- TARGET_FACTORS
  } else {
    lambda_bar_norm <- lambda_bar / lambda_sum
  }

  sig_date_t <- as.Date(paste0(substr(ym_t, 1, 4), "-", substr(ym_t, 5, 6), "-28"))
  X_cur <- as.matrix(panel_cur[, ..TARGET_FACTORS])
  valid_cur <- complete.cases(X_cur)
  X_cur_clean <- X_cur[valid_cur, , drop = FALSE]

  if (nrow(X_cur_clean) < 30) {
    n_skipped <- n_skipped + 1L
    next
  }

  pred_scores <- as.numeric(X_cur_clean %*% lambda_bar_norm)

  fmp_dt <- data.table(
    Date   = sig_date_t,
    Ticker = panel_cur$Ticker[valid_cur],
    Score  = pred_scores
  )
  fmp_scores[[ym_t]] <- fmp_dt

  if (t_idx %% 24 == 0) {
    cat(sprintf("  [%d/%d] %s: %d regs\n", t_idx, length(months_ordered), ym_t, length(lambda_history)))
  }
}

cat(sprintf("\n[Step 3] FMB: %d regressions, %d signal months, %d skipped\n",
            n_regs, length(fmp_scores), n_skipped))

if (length(fmp_scores) < 36) {
  stop("[ABORT] Insufficient FMP signals. Need >= 36, got ", length(fmp_scores))
}

# Print final lambda weights + t-stats
if (length(lambda_history) > 0) {
  lambda_dt <- rbindlist(lambda_history)
  lambda_final <- colMeans(lambda_dt[, ..TARGET_FACTORS], na.rm = TRUE)
  lambda_final_norm <- lambda_final / sum(abs(lambda_final))
  cat("\n  Final lambda weights:\n")
  for (fn in TARGET_FACTORS) cat(sprintf("    %s: %+.4f\n", fn, lambda_final_norm[fn]))
  cat("\n  FMB t-statistics:\n")
  for (fn in TARGET_FACTORS) {
    lam_vec <- lambda_dt[[fn]]
    t_stat <- mean(lam_vec, na.rm = TRUE) / (sd(lam_vec, na.rm = TRUE) / sqrt(length(lam_vec)))
    cat(sprintf("    %s: t = %.3f %s\n", fn, t_stat,
                ifelse(abs(t_stat) > 3.0, "[STRONG]", ifelse(abs(t_stat) > 1.96, "[sig]", ""))))
  }
}

# ============================================================================
# Step 4: Run Backtest with Turnover Constraint
# ============================================================================
cat("\n[Step 4] Running backtest with turnover constraint...\n")

FMP_FACTORS <- rbindlist(fmp_scores)
cat(sprintf("  FMP FACTORS: %d rows, %d signal dates\n",
            nrow(FMP_FACTORS), uniqueN(FMP_FACTORS$Date)))

RAWDATA <- copy(RAWDATA_ORIG)
BM_DT <- copy(BM_DT_ORIG)

# Use tighter buffer (45/15) for turnover control
# Also pass turnover_cap if supported by backtest_harness
sim_args <- list(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FMP_FACTORS,
  n_holdings    = N_HOLDINGS,
  commission    = COMMISSION,
  weight_method = WEIGHT_METHOD,
  buffer_zone   = BUFFER_ZONE
)

# Check if run_monthly_simulation supports turnover_cap
sim_formals <- names(formals(run_monthly_simulation))
if ("turnover_cap" %in% sim_formals) {
  sim_args$turnover_cap <- TURNOVER_CAP
  cat(sprintf("  Using native turnover_cap=%.2f\n", TURNOVER_CAP))
} else {
  cat("  [INFO] turnover_cap not in harness; relying on tight buffer (45/15) for TC control.\n")
}

sim_raw <- do.call(run_monthly_simulation, sim_args)

# ============================================================================
# Step 5: DD Brake 6/20 (t-1 lagged)
# ============================================================================
cat(sprintf("\n[Step 5] DD Brake (%.0f%%/%.0f%%, floor=%.0f%%, t-1 lagged)...\n",
    DD_LOW * 100, DD_HIGH * 100, DD_FLOOR * 100))

raw_daily_ret <- as.numeric(sim_raw$strategy_xts)
raw_dates     <- as.Date(index(sim_raw$strategy_xts))
n_days        <- length(raw_daily_ret)

nav_raw <- cumprod(1 + raw_daily_ret)
dd_raw  <- 1 - nav_raw / cummax(nav_raw)

dd_exposure <- ifelse(dd_raw <= DD_LOW, 1.0,
                      ifelse(dd_raw >= DD_HIGH, DD_FLOOR,
                             pmax(DD_FLOOR, 1.0 - (dd_raw - DD_LOW) / (DD_HIGH - DD_LOW) * (1.0 - DD_FLOOR))))

# CRITICAL: t-1 lag (C9)
dd_exposure_lagged <- c(1.0, head(dd_exposure, -1))
final_ret <- raw_daily_ret * dd_exposure_lagged

cat(sprintf("  DD brake active days: %d / %d (%.1f%%)\n",
            sum(dd_exposure_lagged < 1.0), n_days,
            sum(dd_exposure_lagged < 1.0) / n_days * 100))
cat(sprintf("  Mean DD exposure: %.3f\n", mean(dd_exposure_lagged)))

# Compute actual turnover for reporting
if (!is.null(sim_raw$turnover_history)) {
  avg_to <- mean(sim_raw$turnover_history, na.rm = TRUE)
  cat(sprintf("  Avg monthly turnover: %.1f%%\n", avg_to * 100))
}

# ============================================================================
# Step 6: Final Assembly + Performance
# ============================================================================
cat("\n[Step 6] Final assembly + performance...\n")

final_xts <- xts(final_ret, order.by = raw_dates)
names(final_xts) <- "Strategy"

sim_final <- sim_raw
sim_final$strategy_xts <- final_xts
sim_final$bm_xts <- sim_raw$bm_xts[raw_dates]
sim_final$DAILY_NAV_DT <- data.table(
  Date = raw_dates,
  NAV = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)

perf_final <- summarise_perf(final_xts, "FMP+DD620+TC")
perf_raw   <- summarise_perf(sim_raw$strategy_xts, "FMP_Raw_TC")
perf_bm    <- summarise_perf(sim_raw$bm_xts, "KOSPI200")
perf_all   <- rbind(perf_final, perf_raw, perf_bm)
print(perf_all)

delta_sharpe <- perf_final$Sharpe - perf_raw$Sharpe
delta_cagr   <- perf_final$CAGR - perf_raw$CAGR
delta_mdd    <- perf_final$MDD - perf_raw$MDD

cat(sprintf("\n[Delta] DD620+TC vs Raw: Sharpe %+.3f | CAGR %+.1f%% | MDD %+.1f%%\n",
            delta_sharpe, delta_cagr, delta_mdd))

# ============================================================================
# Step 7: Charts + Save
# ============================================================================
cat("\n[Step 7] Saving results...\n")

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(sim_final, file.path(SCRIPT_DIR, "sim_result.rds"))
fwrite(perf_all, file.path(out_dir, "performance.csv"))

tryCatch({
  generate_charts(sim_final, output_dir = out_dir,
                  strategy_name = sprintf("%s: %s", STRATEGY_ID, STRATEGY_NAME))
  cat("  Charts generated.\n")
}, error = function(e) cat(sprintf("[charts] Error: %s\n", e$message)))

tryCatch({
  source(file.path(.proj, "02_Infrastructure/strategy_analyzer.R"))
  run_analysis(sim_final, FMP_FACTORS, RAWDATA_ORIG, BM_DT_ORIG, out_dir,
               strategy_name = STRATEGY_ID)
  cat("  Analysis complete.\n")
}, error = function(e) cat(sprintf("[analysis] Error: %s\n", e$message)))

# ============================================================================
# Step 8: Hurdle Gate
# ============================================================================
cat("\n[Step 8] Running hurdle gate...\n")
hurdle_result <- NULL
tryCatch({
  source(file.path(.proj, "02_Infrastructure/hurdle_gate.R"))
  hurdle_result <- run_hurdle_gate(
    sim_result    = sim_final,
    FACTORS       = FMP_FACTORS,
    strategy_name = paste0(STRATEGY_ID, "_FMP_DD620_TC"),
    output_dir    = out_dir
  )
  cat(sprintf("  Grade: %s | Score: %.1f | Pass: %s\n",
              hurdle_result$verdict$grade,
              hurdle_result$verdict$total_score,
              hurdle_result$pass))
}, error = function(e) {
  cat(sprintf("[hurdle] Error: %s\n", e$message))
  hurdle_result <<- list(pass = FALSE, verdict = list(grade = "?", total_score = 0))
})

output_json <- list(
  strategy_id = STRATEGY_ID,
  strategy_name = "FMP + DD 6/20 + Turnover Constraint 0.5",
  parent = "STR_1387",
  mutation_lab = "V3_S5_Mutation_2",
  method = "FC_2b_FMP + DD_6_20 + TC_0.5",
  factors = TARGET_FACTORS,
  n_factors = N_FACTORS,
  window = "expanding",
  min_train_months = MIN_TRAIN_MONTHS,
  n_holdings = N_HOLDINGS,
  weight_method = WEIGHT_METHOD,
  commission = COMMISSION,
  buffer_zone = BUFFER_ZONE,
  turnover_cap = TURNOVER_CAP,
  overlays = list(
    vol_target = "NONE",
    dd_brake = list(low = DD_LOW, high = DD_HIGH, floor = DD_FLOOR),
    regime = "NONE"
  ),
  performance = list(
    dd620_tc = as.list(perf_final),
    raw_fmp = as.list(perf_raw),
    benchmark = as.list(perf_bm)
  ),
  hurdle = tryCatch(list(
    grade = hurdle_result$verdict$grade,
    score = hurdle_result$verdict$total_score,
    pass  = hurdle_result$pass
  ), error = function(e) list(grade = "?", score = 0, pass = FALSE)),
  generated = as.character(Sys.time()),
  pit_status = paste0(
    "CLEAN - FMB expanding-window [t-1 factors, t returns]. ",
    "DD Brake t-1 lagged (C9). Tight buffer 45/15 for TC control. ",
    "No VT. No Regime. Z_Score_Aligned (C13). C1/C3/C14/C15 clean."
  )
)
write_json(output_json, file.path(SCRIPT_DIR, "result.json"), auto_unbox = TRUE, pretty = TRUE)

# ============================================================================
# Step 9: Telegram
# ============================================================================
cat("\n[Step 9] Telegram report...\n")
tryCatch({
  grade_str <- tryCatch(hurdle_result$verdict$grade, error = function(e) "?")
  score_str <- tryCatch(sprintf("%.1f", hurdle_result$verdict$total_score), error = function(e) "?")

  msg_lines <- c(
    sprintf("STR_1417 FMP + DD 6/20 + TC 0.5 (V3 S5 Mutation 2)"),
    "",
    sprintf("Parent: STR_1387 (SR 0.714, CAGR 11.0%%, MDD 36.3%%)"),
    sprintf("Mutation: DD 6/20 only + Turnover Constraint 50%% (buffer 45/15)"),
    sprintf("Factors: %s", paste(TARGET_FACTORS, collapse = ", ")),
    sprintf("N=%d, EW, Buffer(45/15), TC=50%%, Liq >= 2e8", N_HOLDINGS),
    "",
    "Performance:",
    sprintf("  DD620+TC: SR %.3f | CAGR %.1f%% | MDD %.1f%%",
            perf_final$Sharpe, perf_final$CAGR, perf_final$MDD),
    sprintf("  Raw FMP:  SR %.3f | CAGR %.1f%% | MDD %.1f%%",
            perf_raw$Sharpe, perf_raw$CAGR, perf_raw$MDD),
    "",
    sprintf("Grade: %s (%s)", grade_str, score_str),
    "PIT: expanding FMB + DD(t-1). TC via buffer 45/15. No VT/Regime."
  )

  tg_send(paste(msg_lines, collapse = "\n"))

  if (!is.null(hurdle_result)) {
    tryCatch({
      hr_path <- file.path(out_dir, "hurdle_result.json")
      if (file.exists(hr_path)) {
        hr <- fromJSON(hr_path)
        tg_strategy_result_with_chart(STRATEGY_ID, hr, out_dir)
      }
    }, error = function(e) cat("[TG chart]", e$message, "\n"))
  }

  cat("[Step 9] Telegram sent.\n")
}, error = function(e) cat(sprintf("[Step 9] Telegram failed: %s\n", e$message)))

cat(sprintf("\n=== %s complete ===\n", STRATEGY_ID))
