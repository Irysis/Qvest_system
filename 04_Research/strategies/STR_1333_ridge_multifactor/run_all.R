## STR_1333: Ridge Regularized Multi-Factor (FC_1c_Ridge, 20 factors)
## 핵심아이디어: 20개 후보 팩터를 expanding window Ridge(alpha=0)로 결합.
##   약한 signal까지 앙상블 흡수, 소수 강팩터 의존도 낮춤.
##   Kozak, Nagel & Santosh (2020): Ridge가 OOS에서 LASSO/OLS 지배.
## S4 Phase 1: EW baseline first, then Ridge comparison.
## PIT: C13(Z_Score_Aligned), C14(Usable_Date), C15(load_month_factors)
cat("=== STR_1333: Ridge Regularized Multi-Factor (20 factors) ===\n")
set.seed(1333); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME   <- "RidgeMultiFactor"
STRATEGY_ID     <- "STR_1333"
STRATEGY_FAMILY <- "ridge_multifactor"
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
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
    "02_Infrastructure"
  )
}

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(glmnet)
  library(jsonlite)
})

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# C15: load_month_factors() only
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

# Factor engine
source(file.path(SCRIPT_DIR, "factor_engine.R"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))

# ============================================================================
# Constants (v3.0 rules override contract)
# ============================================================================
N_HOLDINGS     <- 30L
COMMISSION     <- 0.0015
VOL_TARGET     <- 0.15
BUFFER_KEEP    <- 40L
BUFFER_ENTRY   <- 20L
MIN_TRAIN_MONTHS <- 36L

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

# IC history for S1 screening
ic_hist <- tryCatch(.load_ic_history(), error = function(e) NULL)
cat(sprintf("  IC history: %s\n",
            if (!is.null(ic_hist)) sprintf("%d rows", nrow(ic_hist)) else "NOT AVAILABLE"))

# ============================================================================
# Phase 2: Build Monthly Factor Panels + Forward Returns
# ============================================================================
cat("[Phase 2] Building monthly factor panels...\n")

fdb_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                        pattern = "^factor_db_\\d{6}\\.parquet$")
fdb_months <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", fdb_files))
cat(sprintf("  Factor DB: %d months (%s ~ %s)\n",
            length(fdb_months), fdb_months[1], tail(fdb_months, 1)))

factor_panels <- list()
forward_rets  <- list()
factor_cols_per_month <- list()
n_panel <- 0L

# L-534: Factor DB 1회 로드 → 메모리 캐싱 (루프 내 parquet 반복 로드 금지)
cat("  [L-534] Loading all Factor DB parquets once (20 factors only)...\n")
fdb_full_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                              pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_full_files, function(fp) {
  dt <- as.data.table(arrow::read_parquet(fp,
    col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage")))
  dt <- dt[Factor_Name %in% CANDIDATE_FACTORS & Coverage == TRUE]
  ym <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  dt[, sig_ym := ym][, Coverage := NULL]
  dt
}))

# Direction alignment (IC sign, C13)
ic_dir_dt <- tryCatch({
  ic_h <- .load_ic_history()
  ic_h[Factor_Name %in% CANDIDATE_FACTORS,
       .(Mean_IC = mean(IC, na.rm = TRUE)), by = Factor_Name][
    , ic_sign := fifelse(Mean_IC >= 0, 1L, -1L)]
}, error = function(e) NULL)

if (!is.null(ic_dir_dt) && nrow(ic_dir_dt) > 0) {
  FDB_ALL <- merge(FDB_ALL, ic_dir_dt[, .(Factor_Name, ic_sign)], by = "Factor_Name", all.x = TRUE)
  FDB_ALL[is.na(ic_sign), ic_sign := 1L]
  FDB_ALL[, Z_Score_Aligned := Z_Score * ic_sign]
  FDB_ALL[, c("Z_Score", "ic_sign") := NULL]
} else {
  setnames(FDB_ALL, "Z_Score", "Z_Score_Aligned")
}

setkey(FDB_ALL, sig_ym, Factor_Name, Ticker)
cat(sprintf("  FDB cached: %s rows, %d months\n",
            format(nrow(FDB_ALL), big.mark = ","), uniqueN(FDB_ALL$sig_ym)))

for (i in seq_along(fdb_months)) {
  ym <- fdb_months[i]
  sig_date <- as.Date(paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6), "-28"))

  # S1: IC screening at this signal date (C14: Usable_Date)
  active_factors <- screen_factors_by_ic(sig_date, ic_hist, ic_threshold = 0.02)

  # L-534: FDB_ALL에서 해당 월 필터 (parquet 로드 ZERO)
  fdt <- FDB_ALL[sig_ym == ym & Factor_Name %in% active_factors]
  if (nrow(fdt) == 0) next

  n_avail <- uniqueN(fdt$Factor_Name)
  if (n_avail < MIN_FACTOR_COUNT) next

  # Pivot to wide: Ticker x Factor
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Liquidity filter (C10: t-1 lagged AvgTV20)
  rawdata_month <- RAWDATA[format(Date, "%Y%m") == ym]
  if (nrow(rawdata_month) > 0) {
    liq <- rawdata_month[, .(AvgTV20 = mean(AvgTV20, na.rm = TRUE)), by = Ticker]
    liq_pass <- liq[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD, Ticker]
    fdt_wide <- fdt_wide[Ticker %in% liq_pass]
  }

  if (nrow(fdt_wide) < 50L) next

  # Forward return: next month
  if (i < length(fdb_months)) {
    next_ym <- fdb_months[i + 1]
    next_start <- as.Date(paste0(substr(next_ym, 1, 4), "-", substr(next_ym, 5, 6), "-01"))
    next_end   <- as.Date(paste0(substr(next_ym, 1, 4), "-", substr(next_ym, 5, 6), "-28")) + 5
    ret_data <- RAWDATA[Date >= next_start & Date <= next_end,
                        .(Fwd_Ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    forward_rets[[ym]] <- ret_data
  }

  fcols <- setdiff(names(fdt_wide), "Ticker")
  factor_panels[[ym]] <- fdt_wide
  factor_cols_per_month[[ym]] <- fcols
  n_panel <- n_panel + 1L
}
rm(FDB_ALL); gc(verbose = FALSE)

cat(sprintf("  Built %d monthly panels\n", n_panel))

# ============================================================================
# Phase 2b: Ridge Expanding Window + EW Baseline
# ============================================================================
cat(sprintf("[Phase 2b] Computing Ridge (min %d months) + EW baseline...\n",
            MIN_TRAIN_MONTHS))

train_pool   <- list()
ridge_scores <- list()
ew_scores    <- list()

months_list <- names(factor_panels)
n_ridge <- 0L; n_ew <- 0L

# Performance optimization: re-fit Ridge every 3 months, predict every month
REFIT_INTERVAL <- 3L
cached_train_dt <- NULL
cached_ridge_fit <- NULL
months_since_refit <- REFIT_INTERVAL  # force refit on first eligible month

for (t_idx in seq_along(months_list)) {
  ym_t <- months_list[t_idx]
  sig_d <- as.Date(paste0(substr(ym_t, 1, 4), "-", substr(ym_t, 5, 6), "-28"))

  # Accumulate training data (this month's factors + its forward return)
  if (!is.null(forward_rets[[ym_t]])) {
    panel_t <- factor_panels[[ym_t]]
    ret_t   <- forward_rets[[ym_t]]
    merged_t <- merge(panel_t, ret_t, by = "Ticker")
    if (nrow(merged_t) >= 30L) {
      train_pool[[ym_t]] <- merged_t
    }
  }

  # Current month panel for scoring
  panel_cur <- factor_panels[[ym_t]]
  if (is.null(panel_cur) || nrow(panel_cur) < 50L) next

  fcols <- factor_cols_per_month[[ym_t]]

  # --- EW baseline (always compute, S4 Phase 1) ---
  ew_dt <- compute_ew_scores(panel_cur, fcols)
  if (!is.null(ew_dt)) {
    ew_scores[[ym_t]] <- data.table(
      Date   = sig_d,
      Ticker = ew_dt$Ticker,
      Score  = ew_dt$EW_Score
    )
    n_ew <- n_ew + 1L
  }

  # --- Ridge (C1/C12: only after MIN_TRAIN_MONTHS accumulate) ---
  if (length(train_pool) >= MIN_TRAIN_MONTHS) {
    months_since_refit <- months_since_refit + 1L

    # Re-fit Ridge model every REFIT_INTERVAL months (expensive: rbindlist + cv.glmnet)
    if (months_since_refit >= REFIT_INTERVAL || is.null(cached_ridge_fit)) {
      cached_train_dt <- rbindlist(train_pool, fill = TRUE)
      ridge_result <- compute_ridge_scores(panel_cur, cached_train_dt, fcols, min_train = 300L)

      if (!is.null(ridge_result)) {
        cached_ridge_fit <- ridge_result$ridge_fit
        months_since_refit <- 0L

        ridge_scores[[ym_t]] <- data.table(
          Date   = sig_d,
          Ticker = ridge_result$scores$Ticker,
          Score  = ridge_result$scores$Ridge_Score
        )
        n_ridge <- n_ridge + 1L

        if (n_ridge %% 12 == 0) {
          cat(sprintf("  [%d/%d] %s: REFIT train=%d obs, %d factors, lambda=%.5f\n",
                      t_idx, length(months_list), ym_t,
                      ridge_result$n_train_obs, ridge_result$n_factors,
                      ridge_result$lambda_1se))
        }
      }
    } else if (!is.null(cached_ridge_fit)) {
      # Use cached model to predict (fast: just matrix multiply)
      common_cols <- intersect(fcols, colnames(cached_ridge_fit$glmnet.fit$beta))
      if (length(common_cols) >= 5L) {
        X_cur <- as.matrix(panel_cur[, ..common_cols])
        valid_cur <- complete.cases(X_cur)
        if (sum(valid_cur) >= 30L) {
          pred <- tryCatch(
            as.numeric(predict(cached_ridge_fit, newx = X_cur[valid_cur, , drop = FALSE],
                               s = "lambda.1se")),
            error = function(e) NULL
          )
          if (!is.null(pred)) {
            ridge_scores[[ym_t]] <- data.table(
              Date   = sig_d,
              Ticker = panel_cur$Ticker[valid_cur],
              Score  = pred
            )
            n_ridge <- n_ridge + 1L
          }
        }
      }
    }
  }

  if (t_idx %% 50 == 0) gc(verbose = FALSE)
}

cat(sprintf("[Phase 2b] Ridge: %d months | EW baseline: %d months\n", n_ridge, n_ew))

if (n_ew < 36) stop("[ABORT] EW baseline < 36 months. Insufficient data.")

# ============================================================================
# Phase 3: S4 Backtest -- EW Baseline First, Then Ridge
# ============================================================================
cat("\n[Phase 3] S4 Backtest: EW baseline first, then Ridge...\n")

FACTORS_EW <- rbindlist(ew_scores)
setorder(FACTORS_EW, Date, -Score)

cat("[Phase 3a] EW baseline (FC_1a) backtest: N=%d, EW, VT=%.2f, buffer=%d/%d...\n",
    N_HOLDINGS, VOL_TARGET, BUFFER_KEEP, BUFFER_ENTRY)
sim_ew <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_EW,
  n_holdings    = N_HOLDINGS,
  weight_method = "equal",
  commission    = COMMISSION,
  buffer_zone   = list(keep_n = BUFFER_KEEP, entry_n = BUFFER_ENTRY),
  vol_target    = VOL_TARGET,
  vol_lookback  = 60L
)

perf_ew <- summarise_perf(sim_ew$strategy_xts, "EW_Baseline")
cat(sprintf("  EW: CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_ew$CAGR, perf_ew$Sharpe, perf_ew$MDD))

# Ridge backtest
sim_ridge <- NULL; perf_ridge <- NULL
if (n_ridge >= 36) {
  FACTORS_RIDGE <- rbindlist(ridge_scores)
  setorder(FACTORS_RIDGE, Date, -Score)

  cat("[Phase 3b] Ridge (FC_1c) backtest: N=%d, EW, VT=%.2f, buffer=%d/%d...\n",
      N_HOLDINGS, VOL_TARGET, BUFFER_KEEP, BUFFER_ENTRY)
  sim_ridge <- run_monthly_simulation(
    RAWDATA, BM_DT, FACTORS_RIDGE,
    n_holdings    = N_HOLDINGS,
    weight_method = "equal",
    commission    = COMMISSION,
    buffer_zone   = list(keep_n = BUFFER_KEEP, entry_n = BUFFER_ENTRY),
    vol_target    = VOL_TARGET,
    vol_lookback  = 60L
  )

  perf_ridge <- summarise_perf(sim_ridge$strategy_xts, "Ridge_FC1c")
  cat(sprintf("  Ridge: CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
              perf_ridge$CAGR, perf_ridge$Sharpe, perf_ridge$MDD))
} else {
  cat("[Phase 3b] Ridge skipped: < 36 months of signals.\n")
}

perf_bm <- summarise_perf(sim_ew$bm_xts, "KOSPI")

# ============================================================================
# Phase 4: Performance Comparison + Best Model Selection
# ============================================================================
cat("\n[Phase 4] Performance comparison...\n")

use_ridge <- !is.null(perf_ridge) && !is.na(perf_ridge$Sharpe) &&
             perf_ridge$Sharpe > perf_ew$Sharpe
primary_label <- if (use_ridge) "Ridge" else "EW"
sim_primary   <- if (use_ridge) sim_ridge else sim_ew
perf_primary  <- if (use_ridge) perf_ridge else perf_ew

cat(sprintf("  Primary model: %s\n", primary_label))

if (!is.null(perf_ridge) && !is.na(perf_ridge$Sharpe)) {
  delta_sharpe <- perf_ridge$Sharpe - perf_ew$Sharpe
  delta_cagr   <- perf_ridge$CAGR - perf_ew$CAGR
  delta_mdd    <- perf_ridge$MDD - perf_ew$MDD
  cat(sprintf("  Delta(Ridge-EW): SR=%+.3f | CAGR=%+.2f%% | MDD=%+.1f%%\n",
              delta_sharpe, delta_cagr, delta_mdd))
} else {
  delta_sharpe <- NA_real_; delta_cagr <- NA_real_; delta_mdd <- NA_real_
}

perf_all <- rbind(perf_primary, perf_ew, perf_bm, fill = TRUE)
print(perf_all)

# ============================================================================
# Phase 5: Ridge Coefficient Analysis (latest month)
# ============================================================================
cat("\n[Phase 5] Ridge coefficient analysis...\n")
coef_dt <- NULL
if (use_ridge && length(train_pool) >= MIN_TRAIN_MONTHS) {
  tryCatch({
    last_train <- rbindlist(train_pool, fill = TRUE)
    last_panel <- factor_panels[[tail(months_list, 1)]]
    fcols_final <- intersect(
      setdiff(names(last_panel), "Ticker"),
      setdiff(names(last_train), c("Ticker", "Fwd_Ret"))
    )
    X_f <- as.matrix(last_train[, ..fcols_final])
    y_f <- last_train$Fwd_Ret
    valid_f <- complete.cases(X_f) & !is.na(y_f)
    X_f <- X_f[valid_f, , drop = FALSE]; y_f <- y_f[valid_f]
    q_lo <- quantile(y_f, 0.01); q_hi <- quantile(y_f, 0.99)
    y_f <- pmin(pmax(y_f, q_lo), q_hi)

    final_fit <- cv.glmnet(X_f, y_f, alpha = 0, nfolds = 5,
                            type.measure = "mse", standardize = FALSE)
    coefs <- as.matrix(coef(final_fit, s = "lambda.1se"))
    coef_dt <- data.table(
      Factor      = c("(Intercept)", fcols_final),
      Coefficient = round(as.numeric(coefs), 6)
    )
    coef_dt <- coef_dt[Factor != "(Intercept)"]
    coef_dt[, AbsCoef := abs(Coefficient)]
    setorder(coef_dt, -AbsCoef)
    coef_dt[, AbsCoef := NULL]
    cat("Top 10 Ridge coefficients (|coef| descending):\n")
    print(head(coef_dt, 10))
  }, error = function(e) cat("[Coef analysis] Error:", e$message, "\n"))
}

# ============================================================================
# Phase 6: Output + Charts + Hurdle Gate
# ============================================================================
cat("\n[Phase 6] Saving output + Hurdle...\n")
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(sim_primary, file.path(SCRIPT_DIR, "sim_result.rds"))
fwrite(perf_all, file.path(out_dir, "performance.csv"))

# Charts
tryCatch({
  generate_charts(sim_primary, output_dir = out_dir,
                  strategy_name = sprintf("%s: %s (%s)", STRATEGY_ID, STRATEGY_NAME, primary_label))
}, error = function(e) cat("[Charts]", e$message, "\n"))

# Analysis
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  FACTORS_PRIMARY <- if (use_ridge) rbindlist(ridge_scores) else FACTORS_EW
  run_analysis(sim_primary, FACTORS_PRIMARY, RAWDATA, BM_DT, out_dir,
               strategy_name = STRATEGY_ID)
}, error = function(e) cat("[Analysis]", e$message, "\n"))

# Hurdle Gate
hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(sim_result = sim_primary, strategy_name = STRATEGY_ID,
                  output_dir = out_dir)
}, error = function(e) { cat("[Hurdle]", e$message, "\n"); NULL })

# ============================================================================
# Phase 7: Telegram Report
# ============================================================================
cat("\n[Phase 7] Telegram report...\n")
tryCatch({
  grade_str <- if (!is.null(hurdle)) {
    hr <- hurdle$verdict %||% hurdle
    sprintf("Grade %s (%.1f)", hr$grade %||% "?", hr$total_score %||% 0)
  } else "N/A"

  msg_lines <- c(
    sprintf("\U0001F52C [Forge] %s Ridge Multi-Factor \uC644\uB8CC", STRATEGY_ID),
    "",
    "Method: FC_1c_Ridge (glmnet alpha=0, expanding window)",
    sprintf("Factors: 20\uD6C4\uBCF4 \uC911 IC>0.02 \uD544\uD130, N=%d, EW, VT=%.0f%%",
            N_HOLDINGS, VOL_TARGET * 100),
    "",
    "\U0001F4CA Performance:"
  )

  if (!is.null(perf_ridge) && !is.na(perf_ridge$Sharpe)) {
    msg_lines <- c(msg_lines,
      sprintf("  Ridge:  SR %.3f | CAGR %.2f%% | MDD %.1f%%",
              perf_ridge$Sharpe, perf_ridge$CAGR, perf_ridge$MDD))
  }
  msg_lines <- c(msg_lines,
    sprintf("  EW:     SR %.3f | CAGR %.2f%% | MDD %.1f%%",
            perf_ew$Sharpe, perf_ew$CAGR, perf_ew$MDD),
    sprintf("  KOSPI:  SR %.3f | CAGR %.2f%% | MDD %.1f%%",
            perf_bm$Sharpe, perf_bm$CAGR, perf_bm$MDD),
    ""
  )

  if (!is.na(delta_sharpe)) {
    msg_lines <- c(msg_lines,
      sprintf("\u0394Sharpe (Ridge-EW): %+.3f", delta_sharpe),
      sprintf("\u0394CAGR: %+.2f%% | \u0394MDD: %+.1f%%", delta_cagr, delta_mdd),
      sprintf("\U0001F3AF Primary: %s", primary_label),
      "")
  }

  if (!is.null(coef_dt) && nrow(coef_dt) > 0) {
    msg_lines <- c(msg_lines, "Top 5 Ridge \uACC4\uC218:")
    for (j in 1:min(5, nrow(coef_dt))) {
      msg_lines <- c(msg_lines, sprintf("  %s: %.5f",
                                         coef_dt$Factor[j], coef_dt$Coefficient[j]))
    }
    msg_lines <- c(msg_lines, "")
  }

  msg_lines <- c(msg_lines,
    sprintf("\U0001F3C6 %s", grade_str),
    "PIT: C13+C14+C15, expanding window, Z_Score_Aligned only"
  )

  tg_send(paste(msg_lines, collapse = "\n"))
  cat("[Phase 7] Telegram sent.\n")
}, error = function(e) cat("[Phase 7] Telegram error:", e$message, "\n"))

# Chart to Telegram
tryCatch({
  chart_files <- list.files(out_dir, pattern = "equity.*\\.png$", full.names = TRUE)
  if (length(chart_files) > 0) {
    tg_send_photo(chart_files[1], sprintf("%s equity curve", STRATEGY_ID))
  }
}, error = function(e) NULL)

# ============================================================================
# Phase 8: Judge Mailbox + QEPM
# ============================================================================
cat("[Phase 8] Judge mailbox + QEPM...\n")

tryCatch({
  judge_inbox <- file.path(PROJECT_ROOT, "qepm", "mailbox", "judge", "inbox")
  if (!dir.exists(judge_inbox)) dir.create(judge_inbox, recursive = TRUE, showWarnings = FALSE)
  if (!is.null(hurdle)) {
    msg <- list(
      strategy_id   = STRATEGY_ID,
      strategy_name = STRATEGY_NAME,
      family        = STRATEGY_FAMILY,
      timestamp     = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      primary_model = primary_label,
      delta_sharpe  = delta_sharpe,
      ridge_coefs   = if (!is.null(coef_dt)) as.list(head(coef_dt, 10)) else NULL,
      hurdle_result = hurdle,
      output_dir    = out_dir,
      request       = "validate"
    )
    msg_path <- file.path(judge_inbox,
                          paste0(STRATEGY_ID, "_validate_",
                                 format(Sys.time(), "%Y%m%d_%H%M%S"), ".json"))
    writeLines(toJSON(msg, auto_unbox = TRUE, pretty = TRUE), msg_path)
    cat(sprintf("[Judge Mailbox] Sent: %s\n", basename(msg_path)))
  }
}, error = function(e) cat("[Judge Mailbox]", e$message, "\n"))

if (isTRUE(QEPM_AUTO_COMMIT) && exists("hybrid_commit")) {
  tryCatch({
    hybrid_commit(strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
                  hurdle_result = hurdle, artifact_paths = list(out_dir))
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

# Cleanup
for (col in c("TradingValue", "AvgTV20", "YM"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
suppressWarnings(rm(train_pool, factor_panels, forward_rets, ridge_scores, ew_scores))
gc(verbose = FALSE)

cat(sprintf("\n=== %s Complete. Primary=%s ===\n", STRATEGY_ID, primary_label))
