# =============================================================================
# fe_vol_adj_volume_surprise.R — Vol-adjusted volume surprise factor
# Paper: 2606.08141 "A Structural Matrix Autoregressive Model for the Joint
#        Dynamics of Volume, Volatility, and Returns"
#
# Signal: Residual from AR(1)+realized_vol model for log trading volume
#   Model (rolling 252d OLS): log_vol_t ~ a + b*log_vol_{t-1} + c*realized_vol_{t-1}
#   Residual = unexpected volume after controlling for vol-driven baseline
#
# Hypothesis: vol drives volume; residual = information-driven component.
#   Paper finding: "volatility is the primary driver of trading activity;
#   informational shocks are predominantly incorporated through price variability."
#   Positive surprise → information event → return momentum OR mean-reversion.
#   Direction: positive residual (unexpected volume surge) tested as positive signal.
#
# PIT: log_vol_t uses TradingValue (20d avg or daily). Lagged inputs (t-1). Rolling OLS.
#   All window data is prior to month-end signal date.
#
# KR feasibility: RAWDATA has TradingValue (daily). Standard market microstructure data.
# Universe: K200_KQ150 (applied by run_alpha_search upstream)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- log trading volume ----
# Use TradingValue as volume proxy (KRW trading value, available in RAWDATA)
# Suppress small/zero values to avoid -Inf
RAWDATA[, .log_vol := ifelse(TradingValue > 0, log(TradingValue), NA_real_)]

# ---- Realized vol (21d rolling SD of daily returns) ----
RAWDATA[, .daily_ret := Close / shift(Close) - 1, by = Ticker]
RAWDATA[, .realized_vol := frollapply(.daily_ret, 21L, sd, fill = NA, align = "right"), by = Ticker]

# ---- Rolling 252d OLS residual at each month-end ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

.vol_surprise_engine <- function(log_vol_vec, realized_vol_vec) {
  # Compute rolling 252d OLS residuals at every position
  # PIT: at position i, we fit OLS on window [i-251, i] using LAGGED inputs.
  #   y  = log_vol[i-251 : i]
  #   x1 = log_vol[i-252 : i-1]  (lag-1 of y within window)
  #   x2 = realized_vol[i-252 : i-1]
  # Residual for position i = y[i] - y_hat[i], using the current-period
  #   predictor values x1[i]=lv_lag[i] and x2[i]=rv_lag[i].
  # lm.fit is fitted on (ok subset of) full 252-row window; prediction is for
  #   the last row only (position i, index 252 within the window).
  n <- length(log_vol_vec)
  resid_score <- rep(NA_real_, n)
  # Not enough data for even one 252-day window
  if (n < 252L) return(resid_score)
  # Build lag vectors once (PIT: only prior-day data used as predictors)
  lv_lag  <- c(NA_real_, log_vol_vec[-n])
  rv_lag  <- c(NA_real_, realized_vol_vec[-n])
  for (i in 252L:n) {
    idx <- (i - 251L):i
    y  <- log_vol_vec[idx]
    x1 <- lv_lag[idx]
    x2 <- rv_lag[idx]
    ok <- is.finite(y) & is.finite(x1) & is.finite(x2)
    if (sum(ok) < 30L) next
    # Current row within window is position 252 (= last element)
    cur_ok <- ok[252L]
    if (is.na(cur_ok) || !cur_ok) next
    # OLS: fit on all valid rows in window
    fit <- tryCatch(
      lm.fit(cbind(1, x1[ok], x2[ok]), y[ok]),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    # Predict for current row (252nd position = index i in original vec)
    y_cur   <- y[252L]
    x1_cur  <- x1[252L]
    x2_cur  <- x2[252L]
    beta    <- fit$coefficients
    y_hat   <- beta[1L] + beta[2L] * x1_cur + beta[3L] * x2_cur
    resid_score[i] <- y_cur - y_hat
  }
  resid_score
}

RAWDATA[, .Score := .vol_surprise_engine(.log_vol, .realized_vol),
        by = Ticker]

# ---- FACTORS output (month-end only) ----
FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.Score),
  .(Date, Ticker, Score = .Score)
]

# Cleanup
RAWDATA[, c(".log_vol", ".daily_ret", ".realized_vol", ".ym", ".Score") := NULL]

cat(sprintf("[fe_vol_adj_volume_surprise] FACTORS rows=%d | signal dates=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))
