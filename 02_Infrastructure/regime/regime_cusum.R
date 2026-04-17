#==============================================================================
# Regime CUSUM Signal — Cumulative Sum Change-Point Detection
#
# Author: Q-Lead Agent
# Date:   2026-03-17
#
# DESIGN:
#   CUSUM monitors cumulative deviations of BM daily losses from an allowance.
#   When losses accumulate beyond threshold h, an alert fires (structural shift).
#   Monthly signal = count of alerts in last 20 trading days + continuous CUSUM level.
#
#   ALL inputs use data up to month_end ONLY. Zero lookahead.
#   Allowance k and threshold h use EXPANDING-WINDOW estimates (no full-sample).
#
# USAGE:
#   source("02_Infrastructure/regime_cusum.R")
#   cusum_dt <- compute_cusum_signal(month_ends)
#
# OUTPUT:
#   data.table(month_end, cusum_val, cusum_alert)
#   cusum_val   = CUSUM level at month_end (continuous, >= 0)
#   cusum_alert = binary: 1 if any alert fired in last 20 trading days, 0 otherwise
#==============================================================================

cat("[regime_cusum] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
}
if (!exists("CACHE_DIR")) {
  CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
}

#==============================================================================
# MAIN: compute_cusum_signal
#==============================================================================
compute_cusum_signal <- function(month_ends) {
  cat("[cusum] Computing CUSUM change-point signal...\n")

  # --- Load benchmark daily data ---
  bm_path <- file.path(CACHE_DIR, "benchmark.parquet")
  if (!file.exists(bm_path)) stop("[cusum] benchmark.parquet not found")

  bm <- as.data.table(read_parquet(bm_path))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  bm[, ret := BM_Close / shift(BM_Close, 1L) - 1]
  bm <- bm[!is.na(ret)]

  # --- Identify loss indicator: 1 if ret < 0, else 0 ---
  # We define "loss" as negative return (BM down-day)
  bm[, is_loss := fifelse(ret < 0, 1L, 0L)]

  # --- Compute CUSUM on daily data using expanding-window parameters ---
  # CUSUM_t = max(0, CUSUM_{t-1} + (loss_indicator_t - k_t))
  # k_t (allowance) = 0.5 * expanding_sd(ret up to t-1)
  # h_t (threshold) = 5 * expanding_sd(ret up to t-1)
  # When CUSUM_t > h_t, fire alert and reset to 0.

  n <- nrow(bm)
  cusum_vals   <- numeric(n)
  alert_flags  <- integer(n)

  # Minimum warmup: 252 trading days for stable expanding stats
  MIN_WARMUP <- 252L

  # Running stats for expanding window (Welford's algorithm)
  run_mean <- 0
  run_m2   <- 0
  run_n    <- 0L
  cusum_prev <- 0

  for (i in seq_len(n)) {
    r <- bm$ret[i]

    # Update running stats with previous day's return (t-1 data only)
    # We use data up to i-1 for parameter estimation (no same-day leakage)
    if (i > 1) {
      r_prev <- bm$ret[i - 1]
      run_n <- run_n + 1L
      delta <- r_prev - run_mean
      run_mean <- run_mean + delta / run_n
      delta2 <- r_prev - run_mean
      run_m2 <- run_m2 + delta * delta2
    }

    if (run_n < MIN_WARMUP) {
      cusum_vals[i]  <- 0
      alert_flags[i] <- 0L
      cusum_prev <- 0
      next
    }

    # Expanding-window sd (using data up to i-1)
    exp_sd <- sqrt(run_m2 / (run_n - 1))
    if (is.na(exp_sd) || exp_sd < 1e-10) exp_sd <- 0.01

    k <- 0.5 * exp_sd   # allowance
    h <- 5.0 * exp_sd   # threshold

    # Standardized loss: if return is negative, accumulate abs deviation; else decay
    # loss_t = max(0, -ret_t) = magnitude of loss (0 if positive return)
    loss_t <- max(0, -r)

    # CUSUM update
    cusum_new <- max(0, cusum_prev + (loss_t - k))

    # Check threshold
    if (cusum_new > h) {
      alert_flags[i] <- 1L
      cusum_new <- 0  # reset after alert
    } else {
      alert_flags[i] <- 0L
    }

    cusum_vals[i] <- cusum_new
    cusum_prev <- cusum_new
  }

  bm[, cusum := cusum_vals]
  bm[, alert := alert_flags]

  # --- Aggregate to month_end level ---
  # For each month_end, get:
  #   cusum_val   = CUSUM level on that date (or last available before)
  #   cusum_alert = any alert in last 20 trading days up to month_end

  # Rolling 20-day alert sum
  bm[, alert_20d := frollsum(alert, n = 20L, align = "right", na.rm = TRUE)]

  setkey(bm, Date)
  me_dt <- data.table(Date = as.Date(month_ends))
  setkey(me_dt, Date)
  joined <- bm[me_dt, roll = TRUE]

  result <- joined[, .(
    month_end   = Date,
    cusum_val   = cusum,
    cusum_alert = fifelse(!is.na(alert_20d) & alert_20d > 0, 1L, 0L)
  )]

  setorder(result, month_end)

  cat(sprintf("[cusum] Done: %d months, alert rate = %.1f%%, mean CUSUM = %.4f\n",
              nrow(result),
              mean(result$cusum_alert, na.rm = TRUE) * 100,
              mean(result$cusum_val, na.rm = TRUE)))

  result
}

cat("[regime_cusum] Loaded. Function: compute_cusum_signal(month_ends)\n")
