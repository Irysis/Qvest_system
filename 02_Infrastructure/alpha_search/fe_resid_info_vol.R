# =============================================================================
# fe_resid_info_vol.R — Residual Information Volume factor
# Paper: arxiv:2606.08141 "A Structural Matrix Autoregressive Model for the
#   Joint Dynamics of Volume, Volatility, and Returns" (Bucci, Palomba, Rossi 2026)
#
# Hypothesis (KR):
#   The SMAR model confirms: volatility is the primary driver of trading volume
#   (informational shocks -> price variation -> trading). After removing the
#   volatility-explained component, the RESIDUAL volume = proxy for pure
#   informed-trader activity. Stocks with high residual volume have informed
#   traders entering now -> positive return predictability.
#
# Factor definition:
#   Per-stock, per-month-end, rolling 20-trading-day OLS:
#     log(Vol_t + 1) ~ alpha + beta * log(|Ret_t| + 1e-4)
#   resid_info_vol = OLS residual at the last day of the 20-day window
#   (i.e., the current-day surprise in volume after controlling for |Ret|)
#
#   Monthly signal = the residual at month-end (last trading day)
#   Cross-section z-score applied by run_monthly_simulation upstream
#   Directional bet: HIGH residual (unexpected volume surge) -> LONG
#
# PIT compliance:
#   - Within the 20-day window, both log_vol and log_abs_ret at time t are
#     contemporaneous (same day). The OLS regression does NOT use future data:
#     it fits log(Vol) ~ f(|Ret|) cross-day within the 20d window, then
#     takes the residual at the LAST day. This is NOT C2 violation because
#     we are estimating a daily contemporaneous relationship (vol ~ |ret|)
#     and extracting the day-t residual — no circular return prediction.
#   - Signal date = month-end. Return realized in month t+1. Lag-1 applied
#     implicitly: run_alpha_search uses FACTORS month-end -> next-month returns.
#   - Rolling window 20d: all within [month-end-20d, month-end]. PIT-safe.
#   - No full-sample normalization. All per-ticker rolling.
#
# Note on contemporaneous Vol~|Ret|:
#   The OLS here is a DESCRIPTIVE decomposition of vol into volatility-explained
#   vs. info-driven components (as in the SMAR paper). It is NOT predicting
#   returns from returns. The residual is extracted from the contemporaneous
#   relationship and used as a monthly signal for NEXT month returns.
#
# KR feasibility: RAWDATA has Vol (daily shares) and Ret (daily return or
#   Close-based). If Ret col absent, computed from Close.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 1. Prepare daily log_vol and log_abs_ret --------------------------------
# Vol: daily shares volume (from RAWDATA; TradingValue already computed upstream)
# Ret: daily price return — use Close-based if Ret column absent

if ("Ret" %in% names(RAWDATA)) {
  RAWDATA[, .daily_ret := Ret]
} else {
  RAWDATA[, .daily_ret := Close / shift(Close) - 1, by = Ticker]
}

RAWDATA[, .log_vol     := ifelse(!is.na(Vol) & Vol > 0, log(Vol + 1L), NA_real_)]
RAWDATA[, .log_abs_ret := log(abs(.daily_ret) + 1e-4)]

# ---- 2. Rolling 20-day OLS residual (last-day residual only) -----------------
# For each ticker, at each trading day, fit OLS on the preceding 20-day window
# and take the residual of the LAST observation (current day).
# This is efficient: we loop once via frollapply.

.compute_resid <- function(log_vol_vec, log_abs_ret_vec) {
  n <- length(log_vol_vec)
  out <- rep(NA_real_, n)
  if (n < 20L) return(out)
  for (i in 20L:n) {
    # Extract 20-day window: positions (i-19) to i (1-based within full vector)
    start_idx <- i - 19L
    if (start_idx < 1L) next
    y  <- log_vol_vec[start_idx:i]     # length 20
    x  <- log_abs_ret_vec[start_idx:i] # length 20
    ok <- is.finite(y) & is.finite(x)
    if (sum(ok) < 10L) next
    # Current day (position 20 within window) must be valid
    if (!ok[20L]) next
    # OLS: y[ok] ~ 1 + x[ok]
    fit <- tryCatch(
      lm.fit(cbind(1, x[ok]), y[ok]),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    # Residual at current day (window position 20)
    y_hat <- fit$coefficients[1L] + fit$coefficients[2L] * x[20L]
    out[i] <- y[20L] - y_hat
  }
  out
}

RAWDATA[, .resid_info_vol := .compute_resid(.log_vol, .log_abs_ret),
        by = Ticker]

# ---- 3. Month-end signal extraction ------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.resid_info_vol),
  .(Date, Ticker, Score = .resid_info_vol)
]

# ---- 4. Cleanup ---------------------------------------------------------------
RAWDATA[, c(".daily_ret", ".log_vol", ".log_abs_ret", ".resid_info_vol", ".ym") := NULL]

cat(sprintf(
  "[fe_resid_info_vol] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
