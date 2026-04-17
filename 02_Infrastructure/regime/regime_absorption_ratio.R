#==============================================================================
# Regime Absorption Ratio Signal
#
# Measures market synchronization via PCA of cross-sectional stock returns.
# High Absorption Ratio = eigenvalues concentrated in few factors = systemic risk.
# Reference: Kritzman, Li, Page & Rigobon (2010) "Principal Components as a
#   Measure of Systemic Risk"
#
# Zero lookahead: at each month_end, uses only trailing 63 trading days.
# Expanding window z-score for comparability across time.
#
# USAGE:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/regime_absorption_ratio.R")
#   ar <- compute_absorption_ratio()
#
# Author: Q-Lead Agent
# Date:   2026-03-17
#==============================================================================

cat("[regime_absorption_ratio] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

#------------------------------------------------------------------------------
# compute_absorption_ratio
#
# At each month_end:
#   1. Load RAWDATA daily returns for [month_end - 63 trading days, month_end]
#   2. Filter stocks with at least 50 days of non-NA returns in the window
#   3. Compute cross-sectional correlation matrix
#   4. Eigendecompose
#   5. AR = sum(top k eigenvalues) / sum(all eigenvalues)
#      where k = 15 (fixed; for large cross-sections per Kritzman et al. 2010)
#   6. Z-score AR using expanding window
#
# Returns: data.table(month_end, absorption_ratio, ar_z)
#------------------------------------------------------------------------------
compute_absorption_ratio <- function(month_ends = NULL, lookback = 63L,
                                     min_stocks = 50L, min_days_pct = 0.80,
                                     n_components = 15L) {

  cat("[absorption_ratio] Loading RAWDATA...\n")
  raw_path <- file.path(CACHE_DIR, "RAWDATA.parquet")
  if (!file.exists(raw_path)) stop("[absorption_ratio] RAWDATA.parquet not found")

  raw <- as.data.table(read_parquet(raw_path))
  raw[, Date := as.Date(Date)]

  # Normalize column name: some versions use 'Ticker' instead of 'Code'
  if (!"Code" %in% names(raw) && "Ticker" %in% names(raw)) {
    setnames(raw, "Ticker", "Code")
  }

  # We only need Date, Code, Ret
  raw <- raw[!is.na(Ret) & !is.na(Code), .(Date, Code, Ret)]
  setorder(raw, Date)

  # Get trading dates
  trading_dates <- sort(unique(raw$Date))

  # Default month_ends: calendar month-ends that exist in our data range
  if (is.null(month_ends)) {
    bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
    bm[, Date := as.Date(Date)]
    max_date <- max(bm$Date)

    fom_seq <- seq.Date(ANALYSIS_START_DATE, max_date, by = "month")
    month_ends <- sort(unique(as.Date(sapply(fom_seq, function(d) {
      as.Date(format(d, "%Y-%m-01")) - 1
    }), origin = "1970-01-01")))
    latest_me <- as.Date(format(max_date + 1, "%Y-%m-01")) - 1
    if (latest_me <= max_date) {
      month_ends <- sort(unique(c(month_ends, latest_me)))
    }
    month_ends <- month_ends[month_ends >= ANALYSIS_START_DATE - 1]
  }

  month_ends <- sort(as.Date(month_ends))
  cat(sprintf("[absorption_ratio] %d month-ends, lookback=%d days\n",
              length(month_ends), lookback))

  # Pre-index trading dates for fast lookback window calculation
  td_idx <- data.table(Date = trading_dates, idx = seq_along(trading_dates))
  setkey(td_idx, Date)

  ar_values <- rep(NA_real_, length(month_ends))

  for (m in seq_along(month_ends)) {
    me <- month_ends[m]

    # Find last trading date <= month_end
    avail <- td_idx[Date <= me]
    if (nrow(avail) == 0) next
    end_idx <- avail[.N, idx]

    if (end_idx < lookback) next  # not enough history
    start_idx <- end_idx - lookback + 1L

    window_dates <- trading_dates[start_idx:end_idx]

    # Get returns in this window
    window_data <- raw[Date %in% window_dates]
    if (nrow(window_data) == 0) next

    # Filter stocks with enough observations
    min_days <- floor(length(window_dates) * min_days_pct)
    stock_counts <- window_data[, .N, by = Code]
    valid_stocks <- stock_counts[N >= min_days, Code]

    if (length(valid_stocks) < min_stocks) next

    # Build return matrix: dates x stocks
    ret_wide <- dcast(window_data[Code %in% valid_stocks],
                      Date ~ Code, value.var = "Ret")
    date_col <- ret_wide$Date
    ret_mat <- as.matrix(ret_wide[, -1])

    # Remove stocks with zero variance
    col_vars <- apply(ret_mat, 2, var, na.rm = TRUE)
    keep <- !is.na(col_vars) & col_vars > 1e-10
    if (sum(keep) < min_stocks) next
    ret_mat <- ret_mat[, keep]

    # Replace remaining NAs with 0 (missing days)
    ret_mat[is.na(ret_mat)] <- 0

    # Correlation matrix (more stable than covariance for AR)
    corr_mat <- tryCatch({
      cor(ret_mat, use = "pairwise.complete.obs")
    }, error = function(e) NULL)
    if (is.null(corr_mat)) next

    # Fix any NAs in correlation (can happen with constant columns)
    corr_mat[is.na(corr_mat)] <- 0
    diag(corr_mat) <- 1

    # Eigendecompose (only need eigenvalues)
    eig <- tryCatch({
      eigen(corr_mat, symmetric = TRUE, only.values = TRUE)
    }, error = function(e) NULL)
    if (is.null(eig)) next

    lambdas <- pmax(0, eig$values)  # ensure non-negative
    total_var <- sum(lambdas)
    if (total_var < 1e-10) next

    # Fixed k = n_components (default 15) top eigenvalues
    # Kritzman et al. (2010): AR = variance explained by top k PCs / total
    # For large cross-sections (p >> 100), fixed k gives meaningful variation
    p <- length(lambdas)
    k <- min(n_components, p)

    # Absorption Ratio
    top_k_var <- sum(sort(lambdas, decreasing = TRUE)[1:k])
    ar_values[m] <- top_k_var / total_var

    if (m %% 50 == 0) {
      cat(sprintf("  [%d/%d] %s: AR=%.4f (k=%d/%d stocks=%d)\n",
                  m, length(month_ends), me, ar_values[m], k,
                  length(lambdas), ncol(ret_mat)))
    }
  }

  # Expanding-window z-score of AR
  ar_z <- rep(NA_real_, length(month_ends))
  min_ar_obs <- 12L  # need 12 months for meaningful z-score

  for (i in seq_along(ar_values)) {
    if (is.na(ar_values[i])) next
    past <- ar_values[1:i]
    past <- past[!is.na(past)]
    if (length(past) < min_ar_obs) next
    m_ar <- mean(past)
    s_ar <- sd(past)
    if (!is.na(s_ar) && s_ar > 1e-8) {
      ar_z[i] <- (ar_values[i] - m_ar) / s_ar
    }
  }

  result <- data.table(
    month_end        = month_ends,
    absorption_ratio = round(ar_values, 4),
    ar_z             = round(ar_z, 4)
  )

  # Summary stats
  valid <- result[!is.na(absorption_ratio)]
  cat(sprintf("\n[absorption_ratio] Done. %d/%d months computed.\n",
              nrow(valid), nrow(result)))
  cat(sprintf("  AR range: [%.4f, %.4f], mean=%.4f\n",
              min(valid$absorption_ratio), max(valid$absorption_ratio),
              mean(valid$absorption_ratio)))
  cat(sprintf("  ar_z range: [%.2f, %.2f]\n",
              min(result$ar_z, na.rm = TRUE), max(result$ar_z, na.rm = TRUE)))

  # Print crisis snapshots
  crisis_dates <- as.Date(c("2008-08-31", "2020-01-31"))
  for (cd in crisis_dates) {
    cd <- as.Date(cd, origin = "1970-01-01")
    row <- result[month_end == cd]
    if (nrow(row) == 0) {
      row <- result[month_end <= cd][.N]
    }
    if (nrow(row) > 0) {
      cat(sprintf("  %s: AR=%.4f, ar_z=%.2f\n",
                  row$month_end, row$absorption_ratio, row$ar_z))
    }
  }

  result
}

cat("[regime_absorption_ratio] Loaded. Function: compute_absorption_ratio()\n")
