# =============================================================================
# fe_hill_tail_index.R — Hill tail index cross-sectional factor
# Paper: 2607.16450 "Portfolio Optimization under Heavy Tails and Asymmetric
#        Volatility: Evidence from Taiwan-Exposed ETFs"
#
# Signal: Hill estimator tail index per stock (rolling 252d)
#   alpha_hill = 1 / mean(log(X_1) - log(X_2), ..., log(X_{k-1}) - log(X_k))
#   where X_1 >= X_2 >= ... = sorted |daily_ret| descending, k = floor(sqrt(252))=15
#   Factor = NEGATIVE of alpha_hill → fatter tail = lower alpha_hill = higher rank
#
# Hypothesis: stocks with fatter tails (lower Hill index) have higher extreme
#   downside risk and earn a risk premium OR are subsequently avoided (direction uncertain).
#   Testing both: "fatter tail → higher future return" (risk premium) via negative alpha_hill.
#   Direction "ambiguous" — paper uses Hill index as RISK measure, not return predictor.
#
# PIT: rolling 252d window ending prior month-end, all past data.
#   No same-day circular reference. LiqPass already filtered.
#
# KR feasibility: RAWDATA has daily Close → can compute |daily_ret|. Standard price data.
# Universe: K200_KQ150 (applied by run_alpha_search upstream)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- Daily return ----
RAWDATA[, .ret := Close / shift(Close) - 1, by = Ticker]
RAWDATA[, .abs_ret := abs(.ret)]

# ---- Hill tail index: rolling 252d window ----
# k = floor(sqrt(252)) = 15  (tail threshold order statistic)
.K_HILL <- floor(sqrt(252L))   # = 15

.hill_engine <- function(x) {
  # x = vector of |daily_ret| for rolling window (may have NAs)
  x <- x[is.finite(x) & x > 0]
  if (length(x) < .K_HILL + 5L) return(NA_real_)
  xs <- sort(x, decreasing = TRUE)          # descending
  # Hill estimator: alpha_hill = 1 / mean(log(X_j) - log(X_{k+1})) for j=1..k
  x_k_plus1 <- xs[.K_HILL + 1L]
  if (x_k_plus1 <= 0) return(NA_real_)
  diffs <- log(xs[seq_len(.K_HILL)]) - log(x_k_plus1)
  if (any(!is.finite(diffs)) || mean(diffs) <= 0) return(NA_real_)
  alpha_hill <- 1 / mean(diffs)
  # Factor = -alpha_hill  (fatter tail = lower alpha_hill = higher score)
  -alpha_hill
}

# Monthly window: compute per ticker at each month-end
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# For each ticker, compute rolling Hill score at month-ends using past 252 trading days
.compute_hill <- function(dt) {
  # dt = single ticker's RAWDATA slice, ordered by Date
  dates <- dt$Date
  abs_rets <- dt$.abs_ret
  n <- nrow(dt)
  scores <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (!dates[i] %in% .month_ends) next
    start_i <- max(1L, i - 251L)   # up to 252 days including today
    window_vals <- abs_rets[start_i:i]
    scores[i] <- .hill_engine(window_vals)
  }
  scores
}

RAWDATA[, .Score := .compute_hill(.SD), by = Ticker, .SDcols = c("Date", ".abs_ret")]

# ---- FACTORS output ----
FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.Score),
  .(Date, Ticker, Score = .Score)
]

# Cleanup
RAWDATA[, c(".ret", ".abs_ret", ".ym", ".Score") := NULL]

cat(sprintf("[fe_hill_tail_index] k=%d | FACTORS rows=%d | signal dates=%d\n",
            .K_HILL, nrow(FACTORS), uniqueN(FACTORS$Date)))
