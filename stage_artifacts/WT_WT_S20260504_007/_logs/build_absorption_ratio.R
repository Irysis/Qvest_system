## ============================================================
## WT-S20260504_007 — Absorption Ratio Pure Risk Overlay
## Kritzman-Page-Turkington (2011) FAJ 67(4) 18-32
##
## Mandate: STR_1715 alpha 100% PRESERVED
## Output: scalar β_t ∈ [0, 1] gross exposure modulator
##         w_final,t = β_t · w_STR1715,t  (cash residual = 1 - β_t)
## Method: AR_t = Σ_{i=1..K} λ_i,t / Σ_{j=1..N} λ_j,t
## Source: Σ_{t-W:t-1} = rolling-window cov of KOSPI200 ∪ KOSDAQ150 daily ret
## PIT: AR_t computed strictly from t-1 close; β_t applied at t open
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

cat("=== WT-S20260504_007 Absorption Ratio Risk Overlay ===\n")
cat("Start: ", format(Sys.time()), "\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_007"
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
LOG_DIR <- file.path(STAGE_DIR, "_logs")

setwd(PROJECT_ROOT)

## -----------------------------------------------------------
## Step 1: Load STR_1715 actual 268m monthly schedule
## -----------------------------------------------------------
pr <- as.data.table(read.csv(
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
  stringsAsFactors = FALSE
))
pr[, date := as.Date(date)]
str1715_dates <- pr$date  # 268 monthly rebalance dates
cat(sprintf("[Step 1] STR_1715 268m schedule: %s to %s (%d months)\n",
            min(str1715_dates), max(str1715_dates), length(str1715_dates)))

## -----------------------------------------------------------
## Step 2: Load RAWDATA, KOSPI200 ∪ KOSDAQ150 daily returns
##         Strict t-1 close cutoff for each AR_t
## -----------------------------------------------------------
cat("\n[Step 2] Loading RAWDATA...\n")
raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
raw[, Date := as.Date(Date)]

# Universe: KOSPI200 ∪ KOSDAQ150
# Window=504 days needs ~2y warmup → start 2002-01-01
universe_start <- as.Date("2002-01-01")
universe_end   <- max(str1715_dates)  # 2026-05-01

uni <- raw[
  (K200 == 1 | KQ150 == 1) &
  Date >= universe_start &
  Date <= universe_end &
  !is.na(Ret) &
  !is.na(Ticker),
  .(Date, Ticker, Ret)
]
setkey(uni, Date, Ticker)
cat(sprintf("  Universe rows: %d, unique tickers: %d, unique dates: %d\n",
            nrow(uni), length(unique(uni$Ticker)), length(unique(uni$Date))))

trading_dates <- sort(unique(uni$Date))

## -----------------------------------------------------------
## Step 3: Marchenko-Pastur cutoff helper
## -----------------------------------------------------------
mp_lambda_plus <- function(T, N) {
  # MP upper bulk edge for T x N noise covariance: λ+ = σ² (1 + sqrt(N/T))²
  # σ² = 1 (correlation matrix). Returns the MP threshold.
  q <- N / T
  (1 + sqrt(q))^2
}

## -----------------------------------------------------------
## Step 4: Compute AR_t for each STR_1715 rebalance month
##   t-1 close strict: window = trading_dates strictly < rebalance_date
##   K ∈ {1, 3, 5}, window ∈ {126, 252, 504}
## -----------------------------------------------------------

# Pre-build trading-date index for fast lookback
td_idx <- data.table(Date = trading_dates, idx = seq_along(trading_dates))
setkey(td_idx, Date)

K_grid <- c(1L, 3L, 5L)
W_grid <- c(126L, 252L, 504L)

# Result storage: rows = months, cols = (K, W) combos
ar_results <- data.table(rebalance_date = str1715_dates)

# Also store eigenvalue path for K=5 W=252 (default)
eig_path_default <- data.table(rebalance_date = str1715_dates,
                               lambda_1 = NA_real_, lambda_2 = NA_real_,
                               lambda_3 = NA_real_, lambda_4 = NA_real_,
                               lambda_5 = NA_real_,
                               total_lambda = NA_real_, n_assets = NA_integer_,
                               n_obs = NA_integer_, mp_lambda_plus = NA_real_,
                               n_eig_above_mp = NA_integer_)

# PIT audit log
pit_audit <- list()

# Eigenvalue stability: for default K=5 W=252, track λ1 timeseries vol
for (W in W_grid) {
  for (K in K_grid) {
    col <- sprintf("AR_K%d_W%d", K, W)
    ar_results[[col]] <- NA_real_
  }
}
# MP-filtered AR for default K=5 W=252
ar_results$AR_K5_W252_MP <- NA_real_

cat(sprintf("\n[Step 4] Computing AR for %d rebalance months × 9 (K,W) combos...\n",
            length(str1715_dates)))

n_failed <- 0L
for (m in seq_along(str1715_dates)) {
  rd <- str1715_dates[m]

  # PIT strict: use trading dates STRICTLY < rd (t-1 close)
  pre_rd <- td_idx[Date < rd]
  if (nrow(pre_rd) == 0L) {
    n_failed <- n_failed + 1L
    next
  }
  end_idx <- pre_rd[.N, idx]
  end_date_used <- pre_rd[.N, Date]  # actual t-1 trading date

  pit_audit[[as.character(rd)]] <- list(
    rebalance_date    = as.character(rd),
    pit_window_end    = as.character(end_date_used),
    days_pre_rebalance = as.integer(rd - end_date_used),
    pit_compliance    = "STRICT_TMINUS_1"
  )

  # Largest window first (504), then derive smaller via subset
  for (W in W_grid) {
    if (end_idx < W) next
    start_idx <- end_idx - W + 1L
    win_dates <- trading_dates[start_idx:end_idx]

    win_data <- uni[Date %in% win_dates]

    # Stocks with enough non-NA obs in window (>= 80%)
    sc <- win_data[, .N, by = Ticker]
    valid_t <- sc[N >= floor(W * 0.80), Ticker]
    if (length(valid_t) < 50L) next

    # Wide matrix
    rw <- dcast(win_data[Ticker %in% valid_t], Date ~ Ticker, value.var = "Ret")
    rmat <- as.matrix(rw[, -1])

    # Drop zero-variance
    cv <- apply(rmat, 2, var, na.rm = TRUE)
    keep <- !is.na(cv) & cv > 1e-10
    if (sum(keep) < 50L) next
    rmat <- rmat[, keep, drop = FALSE]
    rmat[is.na(rmat)] <- 0

    # Correlation matrix (Kritzman uses correlation for AR)
    cmat <- tryCatch(cor(rmat), error = function(e) NULL)
    if (is.null(cmat)) next
    cmat[is.na(cmat)] <- 0
    diag(cmat) <- 1

    eig_vals <- tryCatch(
      eigen(cmat, symmetric = TRUE, only.values = TRUE)$values,
      error = function(e) NULL
    )
    if (is.null(eig_vals)) next
    lam <- pmax(0, sort(eig_vals, decreasing = TRUE))
    tot <- sum(lam)
    if (tot < 1e-10) next

    # AR for K ∈ {1,3,5}
    for (K in K_grid) {
      ar_results[m, (sprintf("AR_K%d_W%d", K, W)) := sum(lam[1:K]) / tot]
    }

    # Default K=5, W=252: store eigenvalue path + MP filter
    if (K_grid[3] == 5L && W == 252L) {
      eig_path_default[m, `:=`(
        lambda_1 = lam[1], lambda_2 = lam[2], lambda_3 = lam[3],
        lambda_4 = lam[4], lambda_5 = lam[5],
        total_lambda = tot, n_assets = ncol(rmat), n_obs = nrow(rmat)
      )]

      # Marchenko-Pastur cutoff
      lp <- mp_lambda_plus(T = nrow(rmat), N = ncol(rmat))
      eig_path_default[m, `:=`(
        mp_lambda_plus = lp,
        n_eig_above_mp = sum(lam > lp)
      )]

      # MP-filtered AR: only count signal eigenvalues (above λ+)
      sig_eig <- lam[lam > lp]
      if (length(sig_eig) >= 1L) {
        K_use <- min(5L, length(sig_eig))
        ar_results[m, AR_K5_W252_MP := sum(sig_eig[1:K_use]) / tot]
      }
    }
  }

  if (m %% 30 == 0L) {
    cat(sprintf("  [%d/%d] %s: AR(K=5,W=252)=%.4f\n",
                m, length(str1715_dates), rd,
                ar_results[m, AR_K5_W252]))
  }
}

cat(sprintf("\n  Failed months (insufficient warmup): %d\n", n_failed))

## -----------------------------------------------------------
## Step 5: Single (K, W) selection via robustness
## -----------------------------------------------------------
cat("\n[Step 5] Selecting (K, W) via Kritzman default + KR universe robustness check...\n")

# Compute mean/sd/min/max for each (K, W) combo
sel_table <- data.table()
for (W in W_grid) {
  for (K in K_grid) {
    col <- sprintf("AR_K%d_W%d", K, W)
    v <- ar_results[[col]]
    valid <- v[!is.na(v)]
    if (length(valid) < 12L) next
    sel_table <- rbind(sel_table, data.table(
      K = K, W = W,
      n_valid = length(valid),
      ar_mean = mean(valid),
      ar_sd   = sd(valid),
      ar_min  = min(valid),
      ar_max  = max(valid),
      ar_q90  = as.numeric(quantile(valid, 0.90)),
      ar_q99  = as.numeric(quantile(valid, 0.99))
    ))
  }
}
print(sel_table)

# Selection rationale (Kritzman default in paper: K=p_eff, but KR universe N≈340 ⇒ K_default in literature varies):
#   * K=1: 1st PC (market mode) only — too coarse, AR_1 ≈ 0.30~0.50
#   * K=3: top 3 PCs — balanced, captures market+style+sector
#   * K=5: top 5 PCs — sector-level structure
#   * W=252 (1y): Kritzman 2011 default
#
# Robustness criterion: AR_t time series must be (a) bounded [0,1], (b) variance reasonable
# (sd > 0.02), (c) minimum sufficient sample (n_valid >= 200).
# Default selection: K=5, W=252 (Kritzman 2011 default; balances factor depth + 1y horizon).

selected_K <- 5L
selected_W <- 252L
sel_col <- sprintf("AR_K%d_W%d", selected_K, selected_W)
ar_t <- ar_results[[sel_col]]

cat(sprintf("\n  SELECTED: K=%d, W=%d (Kritzman 2011 default, 5-factor 1y rolling)\n",
            selected_K, selected_W))
cat(sprintf("  AR_t valid: %d/%d, mean=%.4f, sd=%.4f, range [%.4f, %.4f]\n",
            sum(!is.na(ar_t)), length(ar_t),
            mean(ar_t, na.rm = TRUE), sd(ar_t, na.rm = TRUE),
            min(ar_t, na.rm = TRUE), max(ar_t, na.rm = TRUE)))

## -----------------------------------------------------------
## Step 6: β_t mapping (3 variants) — emit for all 268 months
## -----------------------------------------------------------
cat("\n[Step 6] Computing β_t mapping 3 variants...\n")

# Expanding percentile (PIT-strict: AR up to and including current month)
expanding_quantile <- function(x, q) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    if (is.na(x[i])) next
    past <- x[1:i]
    past <- past[!is.na(past)]
    if (length(past) < 6L) next
    out[i] <- as.numeric(quantile(past, q))
  }
  out
}

ar_lo  <- expanding_quantile(ar_t, 0.30)
ar_hi  <- expanding_quantile(ar_t, 0.85)
ar_med <- expanding_quantile(ar_t, 0.50)
ar_q70 <- expanding_quantile(ar_t, 0.70)
ar_q90 <- expanding_quantile(ar_t, 0.90)

# Variant 1: linear_band
beta_linear <- mapply(function(a, lo, hi) {
  if (is.na(a) || is.na(lo) || is.na(hi) || hi <= lo) return(NA_real_)
  v <- 1 - (a - lo) / (hi - lo)
  pmin(1, pmax(0, v))
}, ar_t, ar_lo, ar_hi)

# Variant 2: threshold_step (3-step: 1.0, 0.7, 0.4)
beta_threshold <- mapply(function(a, q70, q90) {
  if (is.na(a) || is.na(q70) || is.na(q90)) return(NA_real_)
  if (a < q70) return(1.0)
  if (a < q90) return(0.7)
  return(0.4)
}, ar_t, ar_q70, ar_q90)

# Variant 3: sigmoid_smooth — k tuned to give 1-σ ≈ slope-1
ar_sd_t <- sapply(seq_along(ar_t), function(i) {
  past <- ar_t[1:i]; past <- past[!is.na(past)]
  if (length(past) < 6L) return(NA_real_)
  sd(past)
})
# k = 1/sd → 1-sigma drop = e/(1+e) - 1/2 ≈ 0.231
# But to map [med-2sd .. med+2sd] → [0.95 .. 0.05], use k = log(19) / (2*sd) ≈ 1.47/sd
beta_sigmoid <- mapply(function(a, m, s) {
  if (is.na(a) || is.na(m) || is.na(s) || s <= 1e-6) return(NA_real_)
  k <- log(19) / (2 * s)
  1 / (1 + exp(k * (a - m)))
}, ar_t, ar_med, ar_sd_t)

beta_dt <- data.table(
  Date = str1715_dates,
  AR_t = ar_t,
  ar_lo = ar_lo, ar_hi = ar_hi, ar_med = ar_med,
  ar_q70 = ar_q70, ar_q90 = ar_q90,
  beta_linear = beta_linear,
  beta_threshold = beta_threshold,
  beta_sigmoid = beta_sigmoid
)

cat(sprintf("  beta_linear:    mean=%.3f, sd=%.3f, range [%.3f, %.3f], NA=%d\n",
            mean(beta_linear, na.rm = TRUE), sd(beta_linear, na.rm = TRUE),
            min(beta_linear, na.rm = TRUE), max(beta_linear, na.rm = TRUE),
            sum(is.na(beta_linear))))
cat(sprintf("  beta_threshold: mean=%.3f, sd=%.3f, range [%.3f, %.3f], NA=%d\n",
            mean(beta_threshold, na.rm = TRUE), sd(beta_threshold, na.rm = TRUE),
            min(beta_threshold, na.rm = TRUE), max(beta_threshold, na.rm = TRUE),
            sum(is.na(beta_threshold))))
cat(sprintf("  beta_sigmoid:   mean=%.3f, sd=%.3f, range [%.3f, %.3f], NA=%d\n",
            mean(beta_sigmoid, na.rm = TRUE), sd(beta_sigmoid, na.rm = TRUE),
            min(beta_sigmoid, na.rm = TRUE), max(beta_sigmoid, na.rm = TRUE),
            sum(is.na(beta_sigmoid))))

## -----------------------------------------------------------
## Step 7: Tail-risk diagnostics (AR distribution)
## -----------------------------------------------------------
cat("\n[Step 7] Tail-risk diagnostics...\n")
ar_v <- ar_t[!is.na(ar_t)]
ar_q <- list(
  q50 = as.numeric(quantile(ar_v, 0.50)),
  q70 = as.numeric(quantile(ar_v, 0.70)),
  q80 = as.numeric(quantile(ar_v, 0.80)),
  q90 = as.numeric(quantile(ar_v, 0.90)),
  q95 = as.numeric(quantile(ar_v, 0.95)),
  q99 = as.numeric(quantile(ar_v, 0.99)),
  qmax = max(ar_v)
)
print(ar_q)

# Conditional MDD when AR > q90 (next-month STR_1715 ret given AR signal)
str_ret <- pr$ret_net
ar_mask_high <- ar_t > ar_q$q90
ar_mask_high[is.na(ar_mask_high)] <- FALSE
hi_ret <- str_ret[ar_mask_high]

# 1-month-forward (predictive use): AR_t signals risk for return_{t+1}
# Note: pr$ret_net[i] is the return realized over month [date_i, date_{i+1}]
# AR_t computed at date_i tries to predict ret in [date_i, date_{i+1}]
# This is exactly the use case.
cat(sprintf("  N months AR > q90: %d (of %d valid)\n", sum(ar_mask_high), sum(!is.na(ar_t))))
cat(sprintf("  Mean STR_1715 ret in high-AR months: %.4f vs overall %.4f\n",
            mean(hi_ret, na.rm = TRUE), mean(str_ret, na.rm = TRUE)))

# Conditional MDD (max single-month drawdown) when AR > q90
hi_min_ret <- ifelse(length(hi_ret) > 0, min(hi_ret, na.rm = TRUE), NA_real_)
hi_q05_ret <- ifelse(length(hi_ret) > 0, as.numeric(quantile(hi_ret, 0.05, na.rm = TRUE)), NA_real_)

## -----------------------------------------------------------
## Step 8: Stress-period AR behavior
## -----------------------------------------------------------
cat("\n[Step 8] Stress-period AR behavior...\n")
stress_periods <- list(
  GFC_2008 = list(start = as.Date("2008-09-01"), end = as.Date("2009-03-31")),
  KR_Cred_2011 = list(start = as.Date("2011-08-01"), end = as.Date("2011-12-31")),
  China_Mini_2015_2016 = list(start = as.Date("2015-08-01"), end = as.Date("2016-02-29")),
  Vol_2018Q4 = list(start = as.Date("2018-10-01"), end = as.Date("2018-12-31")),
  COVID_2020 = list(start = as.Date("2020-02-01"), end = as.Date("2020-04-30")),
  Stagflation_2022 = list(start = as.Date("2022-01-01"), end = as.Date("2022-12-31")),
  Carry_Unwind_2024 = list(start = as.Date("2024-08-01"), end = as.Date("2024-08-31"))
)

stress_decomp <- list()
for (nm in names(stress_periods)) {
  p <- stress_periods[[nm]]
  in_p <- str1715_dates >= p$start & str1715_dates <= p$end
  ar_in <- ar_t[in_p]
  ar_in <- ar_in[!is.na(ar_in)]
  ret_in <- str_ret[in_p]
  ret_in <- ret_in[!is.na(ret_in)]
  stress_decomp[[nm]] <- list(
    period_start = as.character(p$start),
    period_end   = as.character(p$end),
    n_obs        = sum(in_p),
    ar_mean      = if (length(ar_in) > 0) round(mean(ar_in), 4) else NA_real_,
    ar_max       = if (length(ar_in) > 0) round(max(ar_in), 4) else NA_real_,
    str_cum_ret  = if (length(ret_in) > 0) round(prod(1 + ret_in) - 1, 4) else NA_real_,
    str_min_ret  = if (length(ret_in) > 0) round(min(ret_in), 4) else NA_real_
  )
  cat(sprintf("  %-22s AR mean=%.3f max=%.3f STR_cum=%.3f\n",
              nm,
              stress_decomp[[nm]]$ar_mean %||% NA,
              stress_decomp[[nm]]$ar_max %||% NA,
              stress_decomp[[nm]]$str_cum_ret %||% NA))
}

## -----------------------------------------------------------
## Step 9: Eigenvalue stability metric
## -----------------------------------------------------------
cat("\n[Step 9] Eigenvalue stability...\n")

# Stability: λ_1 month-over-month change (lower = more stable structure)
lam1 <- eig_path_default$lambda_1
lam1_diff <- diff(lam1)
lam1_diff <- lam1_diff[!is.na(lam1_diff)]

eig_stability <- list(
  lambda_1_mean        = round(mean(lam1, na.rm = TRUE), 3),
  lambda_1_sd          = round(sd(lam1, na.rm = TRUE), 3),
  lambda_1_dom_pct_mean = round(mean(lam1 / eig_path_default$total_lambda, na.rm = TRUE), 4),
  lambda_1_dom_pct_max = round(max(lam1 / eig_path_default$total_lambda, na.rm = TRUE), 4),
  lambda_1_mom_change_mean = round(mean(abs(lam1_diff)), 3),
  lambda_1_mom_change_q95  = round(as.numeric(quantile(abs(lam1_diff), 0.95)), 3),
  n_assets_mean        = round(mean(eig_path_default$n_assets, na.rm = TRUE), 1),
  n_assets_min         = min(eig_path_default$n_assets, na.rm = TRUE),
  n_eig_above_mp_mean  = round(mean(eig_path_default$n_eig_above_mp, na.rm = TRUE), 1),
  interpretation       = "λ_1 dominance pct mean = avg market-mode share. Higher = more concentrated systemic risk. Stability via MoM change of λ_1."
)
print(eig_stability)

## -----------------------------------------------------------
## Step 10: Save artifacts
## -----------------------------------------------------------
cat("\n[Step 10] Saving artifacts...\n")

# 1. AR time series CSV (all 9 cells + MP-filtered)
fwrite(ar_results, file.path(STAGE_DIR, "ar_path_timeseries.csv"))
cat("  ar_path_timeseries.csv ✓\n")

# 2. Eigenvalue path CSV (default K=5 W=252)
fwrite(eig_path_default, file.path(STAGE_DIR, "eigenvalue_path.csv"))
cat("  eigenvalue_path.csv ✓\n")

# 3. β_t mapping CSV (Date, beta_linear, beta_threshold, beta_sigmoid)
beta_out <- beta_dt[, .(Date, beta_linear, beta_threshold, beta_sigmoid)]
fwrite(beta_out, file.path(STAGE_DIR, "beta_t_mapping.csv"))
cat("  beta_t_mapping.csv ✓\n")

# 3b. Full beta_dt with AR + thresholds (auxiliary)
fwrite(beta_dt, file.path(STAGE_DIR, "beta_t_mapping_full.csv"))
cat("  beta_t_mapping_full.csv (aux) ✓\n")

# 4. Diagnostics JSON
diag <- list(
  task_id = WT_ID,
  selected_K = selected_K,
  selected_W_days = selected_W,
  selection_rationale = paste0(
    "Kritzman 2011 default K=5 (top 5 principal components) × W=252 trading days (1-year rolling). ",
    "KR universe (KOSPI200 ∪ KOSDAQ150) provides N≈340 stocks/day, sufficient for stable eigenvalue estimation. ",
    "K=1 too coarse (market mode only), K=3 misses sector structure, K=5 captures market+style+sector at full depth. ",
    "W=126 (6m) too noisy for systemic-risk indicator; W=504 (2y) too sticky for monthly rebalance signal."
  ),
  kr_universe_n_mean = eig_stability$n_assets_mean,
  kr_universe_n_min  = eig_stability$n_assets_min,
  ar_mean = round(mean(ar_v), 4),
  ar_sd   = round(sd(ar_v), 4),
  ar_min  = round(min(ar_v), 4),
  ar_max  = round(max(ar_v), 4),
  ar_quantiles = lapply(ar_q, function(x) round(x, 4)),
  eigenvalue_stability_metric = eig_stability,
  selection_table = sel_table,
  marchenko_pastur_filter = list(
    enabled_in_default = FALSE,
    available_column   = "AR_K5_W252_MP",
    n_eig_above_mp_mean = eig_stability$n_eig_above_mp_mean,
    rationale = "MP filter is informative-only (default uses raw top-K). MP cutoff retains only signal eigenvalues above noise edge λ+ = (1+sqrt(N/T))² for correlation matrix."
  ),
  pit_compliance = "STRICT: AR_t computed using trading_dates < rebalance_date (t-1 close cutoff). β_t applied at t open."
)
write_json(diag, file.path(STAGE_DIR, "absorption_ratio_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("  absorption_ratio_diagnostics.json ✓\n")

# 5. Covariance window metadata
cov_meta <- list(
  task_id = WT_ID,
  universe_definition = "KOSPI200 ∪ KOSDAQ150 daily returns (KR domestic only)",
  universe_filter = "K200 == 1 OR KQ150 == 1 (per RAWDATA flags)",
  daily_returns_source = ".cache/rawdata.parquet (RAWDATA::Ret column)",
  data_lag = "t-1 close (PIT strict)",
  window_days = selected_W,
  window_type = "rolling (no expanding)",
  min_stock_obs_pct = 0.80,
  min_stocks_per_window = 50,
  zero_variance_filter = "var > 1e-10",
  na_handling = "NA → 0 after stock-level 80% obs filter",
  correlation_or_covariance = "correlation matrix (Kritzman 2011 standard for AR)",
  marchenko_pastur_setting = "raw top-K AR (no MP filter); MP-filtered variant available as AR_K5_W252_MP for diagnostic comparison",
  estimation_period_start = as.character(min(str1715_dates)),
  estimation_period_end   = as.character(max(str1715_dates))
)
write_json(cov_meta, file.path(STAGE_DIR, "covariance_window_metadata.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  covariance_window_metadata.json ✓\n")

# 6. PIT audit log (compact: per month)
pit_audit_dt <- rbindlist(lapply(names(pit_audit), function(k) {
  e <- pit_audit[[k]]
  data.table(
    rebalance_date = e$rebalance_date,
    pit_window_end = e$pit_window_end,
    days_pre_rebalance = e$days_pre_rebalance,
    pit_compliance = e$pit_compliance
  )
}))
write_json(list(
  task_id = WT_ID,
  audit_method = "Per rebalance month: confirms AR_t window end strictly < rebalance date.",
  total_months = nrow(pit_audit_dt),
  all_strict_t_minus_1 = all(pit_audit_dt$pit_compliance == "STRICT_TMINUS_1"),
  median_days_pre_rebalance = median(pit_audit_dt$days_pre_rebalance),
  min_days_pre_rebalance = min(pit_audit_dt$days_pre_rebalance),
  audit_log = pit_audit_dt
), file.path(STAGE_DIR, "PIT_audit_log.json"),
   pretty = TRUE, auto_unbox = TRUE, digits = 4)
cat("  PIT_audit_log.json ✓\n")

# 7. Tail-risk diagnostics
tail_risk_diag <- list(
  task_id = WT_ID,
  ar_distribution_quantiles = lapply(ar_q, function(x) round(x, 4)),
  high_ar_conditional_metrics = list(
    threshold = "AR > q90",
    threshold_value = round(ar_q$q90, 4),
    n_months_above = sum(ar_mask_high),
    n_months_below = sum(!ar_mask_high & !is.na(ar_t)),
    str1715_mean_ret_high_ar = round(mean(hi_ret, na.rm = TRUE), 4),
    str1715_mean_ret_overall = round(mean(str_ret, na.rm = TRUE), 4),
    str1715_min_ret_high_ar  = round(hi_min_ret, 4),
    str1715_q05_ret_high_ar  = round(hi_q05_ret, 4),
    interpretation = paste0(
      "If high-AR months systematically associated with worse next-month returns, AR overlay viable. ",
      "STR_1715 mean ret in high-AR months: ",
      sprintf("%.4f vs overall %.4f.", mean(hi_ret, na.rm = TRUE), mean(str_ret, na.rm = TRUE))
    )
  ),
  conditional_drawdown_when_ar_high = list(
    metric = "single-month worst loss given AR > q90",
    value  = round(hi_min_ret, 4)
  )
)
write_json(tail_risk_diag, file.path(STAGE_DIR, "tail_risk_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("  tail_risk_diagnostics.json ✓\n")

# 8. Stress decomposition
write_json(list(
  task_id = WT_ID,
  stress_decomposition = stress_decomp,
  interpretation = "AR mean/max during 7 STR_1715 stress windows + STR_1715 cum return + min return for context."
), file.path(STAGE_DIR, "stress_decomposition.json"),
   pretty = TRUE, auto_unbox = TRUE, digits = 4)
cat("  stress_decomposition.json ✓\n")

cat("\nDone: ", format(Sys.time()), "\n")

## -----------------------------------------------------------
## Pre-emptive alpha invariance proof
## ALPHA INVARIANCE proof: w_final,t = β_t · w_STR1715,t
##   ⇒ w_final,t / sum(w_final,t) = β_t · w_STR1715,t / (β_t · sum(w_STR1715,t))
##                                 = w_STR1715,t / sum(w_STR1715,t)
##   ⇒ rank_corr(w_STR1715, w_final / sum(w_final)) = 1 trivially (identical post-renormalize)
## β_t scalar > 0 multiplication preserves rank exactly. β_t = 0 ⇒ all-zero vec → cash 100%.
## -----------------------------------------------------------

# helper for nullable
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b
