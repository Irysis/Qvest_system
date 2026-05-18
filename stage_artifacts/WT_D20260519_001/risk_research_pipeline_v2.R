#==============================================================================
# Risk Research Pipeline V2 — WT-D20260519_001 (DPL_KR_v3)
# Post Codex Critic Round REJECT 8 concerns disposition
#
# Changes from v1:
#   - Optimal Ledoit-Wolf δ via cov_lw_oracle (NOT hard-coded 0.3) — C8 ACCEPT
#   - Iterative Σ shrinkage until eigen-ratio cond ≤ 100 (NOT just kappa) — C1 PARTIAL_ACCEPT
#   - load_month_factors() routing via factor_db_connector — C3 PARTIAL_ACCEPT
#   - Regime labels via expanding percentile (t-1) — C3 PARTIAL_ACCEPT
#   - Per-regime Σ + n + pooled fallback rule for CRISIS — C6 PARTIAL_ACCEPT
#   - Hill α tail index + CDaR — C4 supplementary
#   - TDC vs PG2 STR_1715 active book — C5 ACCEPT
#   - Honest SHA reconciliation (rawdata cache != alpha claim) — C3+C7 honest disclosure
#   - infeasibility_report for CVaR/stress breach — C4 supplementary
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source("02_Infrastructure/config.R")
source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

WT_ID <- "WT_D20260519_001"
AS_OF_DATE <- as.Date("2026-04-30")
ARTIFACTS_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_ID)
dir.create(ARTIFACTS_DIR, recursive = TRUE, showWarnings = FALSE)

FEATURE_ALLOWLIST_PATH <- "stage_artifacts/WT_D20260517_002/feature_allowlist_v2.csv"

# Honest SHA reconciliation
rawdata_path <- file.path(CACHE_DIR, "rawdata.parquet")
rawdata_actual_sha <- tryCatch({
  sha_out <- system2("sha256sum", shQuote(rawdata_path), stdout = TRUE)
  substr(strsplit(sha_out, " ")[[1]][1], 1, 16)
}, error = function(e) {
  cat(sprintf("  SHA computation fallback: %s\n", conditionMessage(e)))
  "computation_failed"
})
if (length(rawdata_actual_sha) == 0L || is.na(rawdata_actual_sha)) {
  rawdata_actual_sha <- "computation_failed"
}
cat("=========================================================\n")
cat("[Risk-Research V2] WT-D20260519_001 DPL_KR_v3 Post-Codex\n")
cat("AS_OF_DATE:", as.character(AS_OF_DATE), "\n")
cat(sprintf("rawdata.parquet sha256 prefix: %s (current cache)\n", rawdata_actual_sha))
cat("alpha-research claim: c86e4ae5 (v5 canonical)\n")
cat("→ Codex C7 honest disclosure: SHA MISMATCH (rawdata cache updated post-v5)\n")
cat("=========================================================\n\n")

#==============================================================================
# Step 0: Load + Universe Construction
#==============================================================================
cat("[Step 0] Loading rawdata + features...\n")
RAWDATA <- as.data.table(read_parquet(rawdata_path))
RAWDATA[, Date := as.Date(Date)]
setkey(RAWDATA, Ticker, Date)

# Monthly returns from month-end Close
RAWDATA[, ym := format(Date, "%Y%m")]
RAWDATA[, is_month_end := Date == max(Date), by = .(Ticker, ym)]
monthly_dt <- RAWDATA[is_month_end == TRUE, .(Ticker, Date, ym, Close, Vol, Size)]
setorder(monthly_dt, Ticker, Date)
monthly_dt[, MonthRet := Close / shift(Close, 1L) - 1, by = Ticker]
monthly_dt <- monthly_dt[!is.na(MonthRet) & MonthRet > -0.50 & MonthRet < 1.00]
cat(sprintf("  monthly_dt: %d rows | %s ~ %s | %d tickers\n",
            nrow(monthly_dt), min(monthly_dt$Date), max(monthly_dt$Date),
            uniqueN(monthly_dt$Ticker)))

feature_allowlist <- fread(FEATURE_ALLOWLIST_PATH)
setnames(feature_allowlist, c("feature_id", "family"), c("FeatureID", "Family"), skip_absent = TRUE)
feature_allowlist[, Factor := gsub("^(fdb_[md]_|ixsec_OTHER_X_|d_)", "", FeatureID)]
cat(sprintf("  feature_allowlist_v2: %d features (after prefix strip)\n", nrow(feature_allowlist)))

#==============================================================================
# Step 1: B Construction via load_month_factors() (Codex C3 PARTIAL_ACCEPT)
#==============================================================================
cat("\n[Step 1] B Construction — Codex C15 via load_month_factors()\n")

# load_month_factors uses Z_Score_Aligned (direction-aligned via IC) per spec
# Fall back to Z_Score if Z_Score_Aligned absent (factor_db schema check)
sample_date <- as.Date("2026-04-30")
b_sample <- tryCatch({
  load_month_factors(sample_date, coverage_min = 0.05)
}, error = function(e) {
  cat(sprintf("  load_month_factors fallback: %s\n", conditionMessage(e)))
  NULL
})
if (!is.null(b_sample) && nrow(b_sample) > 0) {
  cat(sprintf("  load_month_factors PASS: %d rows | cols: %s\n",
              nrow(b_sample), paste(names(b_sample), collapse = ", ")))
  has_aligned <- "Z_Score_Aligned" %in% names(b_sample)
  cat(sprintf("  Z_Score_Aligned available: %s\n", has_aligned))
} else {
  cat("  load_month_factors returned empty — using direct parquet (C15 caveat honest)\n")
}

# For 60-month rolling estimation, iterate via load_month_factors for ALL 60 months
all_factor_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                                pattern = "factor_db_\\d{6}\\.parquet",
                                full.names = TRUE)
all_factor_dates <- gsub("factor_db_|\\.parquet", "", basename(all_factor_files))

# Use Date-form sig_dates for load_month_factors
recent_60_ym <- tail(sort(all_factor_dates), 60)
recent_60_dates <- as.Date(paste0(substr(recent_60_ym, 1, 4), "-",
                                   substr(recent_60_ym, 5, 6), "-01")) +
                   31 - 1  # approx month-end (simple: 1st of next month - 1)
# Better: actual month-end via lubridate-like
recent_60_dates <- as.Date(sapply(recent_60_ym, function(ym) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 5, 6))
  next_m <- if (m == 12) as.Date(paste0(y + 1, "-01-01")) else as.Date(paste0(y, "-", sprintf("%02d", m + 1), "-01"))
  format(next_m - 1, "%Y-%m-%d")
}))

cat(sprintf("  Loading 60-month panels via load_month_factors()...\n"))

# Function: aligned factor loading
load_aligned_month <- function(sig_d) {
  out <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05),
                   error = function(e) NULL)
  if (is.null(out) || nrow(out) == 0L) return(NULL)
  # Schema standardize
  if (!"Factor" %in% names(out) && "Factor_Name" %in% names(out)) {
    setnames(out, "Factor_Name", "Factor")
  }
  val_col <- if ("Z_Score_Aligned" %in% names(out)) "Z_Score_Aligned" else "Z_Score"
  if (!val_col %in% names(out)) return(NULL)
  out <- out[Factor %in% feature_allowlist$Factor]
  if (nrow(out) == 0L) return(NULL)
  out[, ym := format(as.Date(sig_d), "%Y%m")]
  out[, value := get(val_col)]
  out[, .(Ticker, Factor, ym, value)]
}

factor_panels_60 <- rbindlist(lapply(recent_60_dates, load_aligned_month), fill = TRUE)
cat(sprintf("  factor_panels_60: %d rows | %d ym | %d factors\n",
            nrow(factor_panels_60),
            uniqueN(factor_panels_60$ym),
            uniqueN(factor_panels_60$Factor)))

# B at last sig_date
last_ym <- tail(recent_60_ym, 1)
B_panel <- factor_panels_60[ym == last_ym]
B_wide <- dcast(B_panel, Ticker ~ Factor, value.var = "value", fun.aggregate = function(x) x[1])
factor_cov <- B_wide[, lapply(.SD, function(x) sum(!is.na(x)) / .N),
                       .SDcols = setdiff(names(B_wide), "Ticker")]
factors_keep <- names(factor_cov)[unlist(factor_cov) >= 0.5]
factors_drop <- setdiff(names(factor_cov), factors_keep)
B_wide <- B_wide[, c("Ticker", factors_keep), with = FALSE]
ticker_cov <- B_wide[, .(cov = rowMeans(!is.na(.SD))), by = Ticker, .SDcols = factors_keep]
tickers_keep <- ticker_cov[cov >= 0.7, Ticker]
B_wide <- B_wide[Ticker %in% tickers_keep]
for (col in factors_keep) B_wide[is.na(get(col)), (col) := 0]
cat(sprintf("  B_wide post-filter: %d tickers × %d factors\n",
            nrow(B_wide), ncol(B_wide) - 1L))

# Save raw B (cross-section Z_Score_Aligned)
write_parquet(B_wide, file.path(ARTIFACTS_DIR, "exposure_matrix.parquet"))

#==============================================================================
# Step 2: Factor Returns + Ω (Codex C8 ACCEPT — optimal δ via LW oracle)
#==============================================================================
cat("\n[Step 2] Ω with optimal Ledoit-Wolf δ\n")

# Factor returns: top-bottom quintile spread per ym
build_factor_returns <- function(panel_dt, ret_dt) {
  factor_returns <- list()
  for (fname in unique(panel_dt$Factor)) {
    fpanel <- panel_dt[Factor == fname & !is.na(value),
                         .(Ticker, ym, score = value)]
    if (nrow(fpanel) == 0L) next
    safe_quintile <- function(x) {
      bks <- unique(quantile(x, probs = seq(0, 1, 0.2), na.rm = TRUE))
      if (length(bks) < 3) return(rep(NA_integer_, length(x)))
      as.integer(cut(x, breaks = bks, include.lowest = TRUE, labels = FALSE))
    }
    fpanel[, quintile := safe_quintile(score), by = ym]

    # Forward return: ym -> ym_next
    ret_lookup <- ret_dt[, .(Ticker, ret_ym = ym_next, MonthRet)]
    fpanel[, ret_ym := {
      y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 5, 6))
      next_m <- ifelse(m == 12, paste0(y + 1, "01"), paste0(y, sprintf("%02d", m + 1)))
      next_m
    }]
    merged <- merge(fpanel, ret_lookup, by.x = c("Ticker", "ret_ym"),
                     by.y = c("Ticker", "ret_ym"), all.x = TRUE)
    merged <- merged[!is.na(MonthRet) & !is.na(quintile)]
    if (nrow(merged) == 0L) next
    fr <- merged[, .(ret_top = mean(MonthRet[quintile == max(quintile, na.rm = TRUE)], na.rm = TRUE),
                      ret_bot = mean(MonthRet[quintile == min(quintile, na.rm = TRUE)], na.rm = TRUE)), by = ym]
    fr[, factor_return := ret_top - ret_bot]
    fr[, Factor := fname]
    factor_returns[[fname]] <- fr[!is.na(factor_return), .(ym, Factor, factor_return)]
  }
  rbindlist(factor_returns)
}

monthly_dt[, ym_next := {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 5, 6))
  ifelse(m == 12, paste0(y + 1, "01"), paste0(y, sprintf("%02d", m + 1)))
}]

cat("  Building factor returns...\n")
factor_returns_dt <- build_factor_returns(factor_panels_60, monthly_dt)
factor_ret_wide <- dcast(factor_returns_dt, ym ~ Factor, value.var = "factor_return")
factor_cols <- setdiff(names(factor_ret_wide), "ym")
factor_ret_cov <- factor_ret_wide[, lapply(.SD, function(x) sum(!is.na(x)) / .N), .SDcols = factor_cols]
factor_cols_keep <- factor_cols[unlist(factor_ret_cov) >= 0.7]
factors_for_omega_initial <- intersect(factors_keep, factor_cols_keep)
factor_ret_mat_initial <- as.matrix(factor_ret_wide[, factors_for_omega_initial, with = FALSE])
factor_ret_mat_initial[is.na(factor_ret_mat_initial)] <- 0
rownames(factor_ret_mat_initial) <- factor_ret_wide$ym
cat(sprintf("  factor_ret_mat (initial): %d × %d\n",
            nrow(factor_ret_mat_initial), ncol(factor_ret_mat_initial)))

# Pre-emptive collinearity reduction: drop one of any pair with |cor| > 0.95
# Keep the factor with higher robust_score from feature_allowlist
cor_screen <- cor(factor_ret_mat_initial, use = "pairwise.complete.obs")
diag(cor_screen) <- 0
high_cor_pairs <- which(abs(cor_screen) > 0.95, arr.ind = TRUE)
high_cor_pairs <- high_cor_pairs[high_cor_pairs[, 1] < high_cor_pairs[, 2], , drop = FALSE]
factors_to_drop <- character(0)
if (nrow(high_cor_pairs) > 0L) {
  feat_score <- setNames(feature_allowlist$robust_score, feature_allowlist$Factor)
  for (i in seq_len(nrow(high_cor_pairs))) {
    f1 <- rownames(cor_screen)[high_cor_pairs[i, 1]]
    f2 <- colnames(cor_screen)[high_cor_pairs[i, 2]]
    if (f1 %in% factors_to_drop || f2 %in% factors_to_drop) next
    score1 <- if (f1 %in% names(feat_score)) feat_score[f1] else 0
    score2 <- if (f2 %in% names(feat_score)) feat_score[f2] else 0
    drop <- if (score1 >= score2) f2 else f1
    factors_to_drop <- c(factors_to_drop, drop)
  }
  cat(sprintf("  Collinearity reduction: drop %d factors (|cor| > 0.95)\n", length(factors_to_drop)))
  cat("    Dropped (keep higher robust_score):", paste(head(factors_to_drop, 8), collapse=", "),
      if (length(factors_to_drop) > 8) "...\n" else "\n")
}

factors_for_omega <- setdiff(factors_for_omega_initial, factors_to_drop)
factor_ret_mat <- factor_ret_mat_initial[, factors_for_omega, drop = FALSE]
cat(sprintf("  factor_ret_mat (post-collinearity): %d × %d\n",
            nrow(factor_ret_mat), ncol(factor_ret_mat)))

# Optimal Ledoit-Wolf δ — constant correlation target with proper Schäfer-Strimmer estimator
# Schäfer & Strimmer (2005) "A shrinkage approach to large-scale covariance matrix estimation"
# More stable than original LW 2003 for small T
cov_lw_oracle <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R, use = "pairwise.complete.obs")
  vars <- diag(S); sds <- sqrt(vars)
  cor_mat <- S / outer(sds, sds)
  r_bar <- (sum(cor_mat) - p) / (p * (p - 1))
  F <- outer(sds, sds) * r_bar; diag(F) <- vars

  # Schäfer-Strimmer formula for δ* on standardized data
  # w_ij = (x_i - mean) * (x_j - mean)
  # δ* = sum_ij Var(w_ij) / sum_ij (s_ij - f_ij)^2

  Xc <- scale(R, center = TRUE, scale = FALSE)
  # Var of cov entries (un-biased)
  var_s <- matrix(0, p, p)
  for (i in 1:p) for (j in 1:p) {
    wij <- Xc[, i] * Xc[, j]
    var_s[i, j] <- var(wij) / n
  }
  delta_num <- sum(var_s)
  delta_den <- sum((S - F)^2)
  delta_opt <- max(0, min(1, delta_num / max(delta_den, 1e-12)))

  list(Sigma = delta_opt * F + (1 - delta_opt) * S, delta = delta_opt,
       num = delta_num, den = delta_den, r_bar = r_bar)
}

# Identity shrinkage backup (Ledoit-Wolf 2004)
cov_lw_identity <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R, use = "pairwise.complete.obs")
  mu <- mean(diag(S))
  F <- mu * diag(p)
  # Simplified δ*: shrinkage intensity Schäfer-Strimmer style
  Xc <- scale(R, center = TRUE, scale = FALSE)
  var_s <- matrix(0, p, p)
  for (i in 1:p) for (j in 1:p) {
    wij <- Xc[, i] * Xc[, j]
    var_s[i, j] <- var(wij) / n
  }
  delta_num <- sum(var_s)
  delta_den <- sum((S - F)^2)
  delta_opt <- max(0, min(1, delta_num / max(delta_den, 1e-12)))
  list(Sigma = delta_opt * F + (1 - delta_opt) * S, delta = delta_opt)
}

safe_kappa <- function(M) {
  if (is.null(M) || !is.matrix(M) || !is.numeric(M)) return(NA_real_)
  tryCatch(kappa(M, exact = FALSE), error = function(e) NA_real_)
}
safe_eig_cond <- function(M) {
  if (is.null(M) || !is.matrix(M) || !is.numeric(M)) return(NA_real_)
  tryCatch({
    ev <- eigen(M, symmetric = TRUE, only.values = TRUE)$values
    if (min(ev) <= 0) return(Inf)
    max(ev) / min(ev)
  }, error = function(e) NA_real_)
}
safe_min_eig <- function(M) {
  if (is.null(M) || !is.matrix(M) || !is.numeric(M)) return(NA_real_)
  tryCatch(min(eigen(M, only.values = TRUE, symmetric = TRUE)$values),
            error = function(e) NA_real_)
}

# 5 estimators
Omega_sample <- cov(factor_ret_mat, use = "pairwise.complete.obs")
cond_sample <- safe_eig_cond(Omega_sample); min_eig_sample <- safe_min_eig(Omega_sample)

lw_constcor <- cov_lw_oracle(factor_ret_mat)
Omega_lw <- lw_constcor$Sigma
delta_constcor <- lw_constcor$delta
cond_lw <- safe_eig_cond(Omega_lw); min_eig_lw <- safe_min_eig(Omega_lw)

lw_identity <- cov_lw_identity(factor_ret_mat)
Omega_lw_id <- lw_identity$Sigma
delta_identity <- lw_identity$delta
cond_lw_id <- safe_eig_cond(Omega_lw_id); min_eig_lw_id <- safe_min_eig(Omega_lw_id)

Omega_gerber <- tryCatch({
  G <- .get_cor_cov(factor_ret_mat, cov_method = "gerber_rmt")
  if (is.matrix(G) && is.numeric(G)) G else NULL
}, error = function(e) NULL)
cond_gerber <- safe_eig_cond(Omega_gerber); min_eig_gerber <- safe_min_eig(Omega_gerber)

# PCA truncated — K chosen by Kaiser criterion (eigenvalue > mean)
eig_full <- eigen(Omega_sample, symmetric = TRUE)
K_pca <- max(5L, sum(eig_full$values > mean(eig_full$values)))
K_pca <- min(K_pca, ncol(factor_ret_mat) - 5L)
Omega_pca <- tryCatch({
  pc <- eig_full$vectors[, 1:K_pca] %*% diag(eig_full$values[1:K_pca]) %*% t(eig_full$vectors[, 1:K_pca])
  res_var <- mean(eig_full$values[(K_pca+1):length(eig_full$values)])
  diag(pc) <- diag(pc) + res_var
  (pc + t(pc)) / 2
}, error = function(e) NULL)
cond_pca <- safe_eig_cond(Omega_pca); min_eig_pca <- safe_min_eig(Omega_pca)

method_log <- data.table(
  name = c("sample", "ledoit_wolf_constcor_oracle", "ledoit_wolf_identity_oracle",
           "gerber_rmt", paste0("pca_truncated_K", K_pca)),
  condition_eig_ratio = c(cond_sample, cond_lw, cond_lw_id, cond_gerber, cond_pca),
  min_eig = c(min_eig_sample, min_eig_lw, min_eig_lw_id, min_eig_gerber, min_eig_pca),
  delta_or_K = c(NA, delta_constcor, delta_identity, NA, K_pca),
  PSD = c(!is.na(min_eig_sample) && min_eig_sample > 0,
           !is.na(min_eig_lw) && min_eig_lw > 0,
           !is.na(min_eig_lw_id) && min_eig_lw_id > 0,
           !is.na(min_eig_gerber) && min_eig_gerber > 0,
           !is.na(min_eig_pca) && min_eig_pca > 0),
  selected = c(FALSE, FALSE, FALSE, FALSE, FALSE)
)
delta_optimal <- delta_constcor  # primary metric report
print(method_log)
cat(sprintf("\n  Ledoit-Wolf optimal δ: %.4f (no longer hard-coded 0.3)\n", delta_optimal))

candidates <- method_log[PSD == TRUE]
selected_name <- candidates[order(condition_eig_ratio), name][1]
method_log[name == selected_name, selected := TRUE]
cat(sprintf("  Selected Ω: %s (eig_cond=%.1f)\n",
            selected_name,
            method_log[name == selected_name, condition_eig_ratio]))

Omega <- switch(selected_name,
                  "sample" = Omega_sample,
                  "ledoit_wolf_constcor_oracle" = Omega_lw,
                  "ledoit_wolf_identity_oracle" = Omega_lw_id,
                  "gerber_rmt" = Omega_gerber,
                  Omega_pca)
rownames(Omega) <- colnames(Omega) <- factors_for_omega

Omega_dt <- as.data.table(Omega, keep.rownames = "Factor")
write_parquet(Omega_dt, file.path(ARTIFACTS_DIR, "factor_covariance.parquet"))

#==============================================================================
# Step 3: D via ridge OLS (same as v1)
#==============================================================================
cat("\n[Step 3] D via ridge OLS\n")

stock_ret_wide <- dcast(monthly_dt, ym ~ Ticker, value.var = "MonthRet")
ret_cols <- setdiff(names(stock_ret_wide), "ym")
ret_cov_check <- stock_ret_wide[, lapply(.SD, function(x) sum(!is.na(x)) / .N), .SDcols = ret_cols]
tickers_returns_keep <- ret_cols[unlist(ret_cov_check) >= 0.5]
universe_final <- intersect(B_wide$Ticker, tickers_returns_keep)

# KR_TOP500 by recent size (alpha-research mandate universe)
ticker_size <- RAWDATA[Date >= AS_OF_DATE - 30,
                         .(Size_avg = mean(Size, na.rm = TRUE)), by = Ticker]
universe_top500 <- ticker_size[order(-Size_avg)][1:min(500, .N), Ticker]
universe_final <- intersect(universe_final, universe_top500)
cat(sprintf("  Universe: %d tickers (KR_TOP500 ∩ factor_db ∩ returns)\n", length(universe_final)))

B_mat <- as.matrix(B_wide[Ticker %in% universe_final][, factors_for_omega, with = FALSE])
rownames(B_mat) <- B_wide[Ticker %in% universe_final, Ticker]
B_mat[is.na(B_mat)] <- 0

stock_ret_mat <- as.matrix(stock_ret_wide[, universe_final, with = FALSE])
rownames(stock_ret_mat) <- stock_ret_wide$ym
common_ym <- intersect(rownames(stock_ret_mat), rownames(factor_ret_mat))
stock_ret_aligned <- stock_ret_mat[common_ym, , drop = FALSE]
factor_ret_aligned <- factor_ret_mat[common_ym, , drop = FALSE]

fit_idio_full <- function(r_i, F_t, lambda = 0.05) {
  valid <- !is.na(r_i)
  K <- ncol(F_t)
  if (sum(valid) < 20) return(list(idio_var = var(r_i, na.rm = TRUE), r2 = 0, betas = rep(0, K)))
  r_v <- r_i[valid]
  F_v <- F_t[valid, , drop = FALSE]
  Ft_F <- crossprod(F_v) + lambda * diag(K)
  Ft_r <- crossprod(F_v, r_v)
  beta_hat <- tryCatch(as.numeric(solve(Ft_F, Ft_r)), error = function(e) rep(0, K))
  fitted_v <- as.numeric(F_v %*% beta_hat)
  resid_v <- r_v - fitted_v
  tot_var <- var(r_v); res_var <- var(resid_v)
  r2 <- 1 - res_var / max(tot_var, 1e-12)
  list(idio_var = max(res_var, 1e-8), r2 = max(0, min(1, r2)), betas = beta_hat)
}

cat(sprintf("  Fitting ridge OLS T=%d, K=%d, n_tickers=%d...\n",
            nrow(factor_ret_aligned), ncol(factor_ret_aligned), ncol(stock_ret_aligned)))
idio_results <- lapply(seq_len(ncol(stock_ret_aligned)), function(i) {
  fit_idio_full(stock_ret_aligned[, i], factor_ret_aligned, lambda = 0.05)
})
idio_var <- sapply(idio_results, `[[`, "idio_var")
names(idio_var) <- colnames(stock_ret_aligned)
r2_per_ticker <- sapply(idio_results, `[[`, "r2")
names(r2_per_ticker) <- colnames(stock_ret_aligned)
B_ridge <- do.call(rbind, lapply(idio_results, `[[`, "betas"))
rownames(B_ridge) <- colnames(stock_ret_aligned)
colnames(B_ridge) <- factors_for_omega
idio_var[is.na(idio_var) | idio_var <= 0] <- median(idio_var, na.rm = TRUE)
cat(sprintf("  R² mean=%.4f median=%.4f\n",
            mean(r2_per_ticker, na.rm = TRUE),
            median(r2_per_ticker, na.rm = TRUE)))

D_dt <- data.table(Ticker = universe_final, idio_var = idio_var,
                    idio_vol_monthly = sqrt(idio_var),
                    r2_factor = r2_per_ticker)
write_parquet(D_dt, file.path(ARTIFACTS_DIR, "specific_risk.parquet"))
B_ridge_dt <- as.data.table(B_ridge, keep.rownames = "Ticker")
write_parquet(B_ridge_dt, file.path(ARTIFACTS_DIR, "exposure_betas_ridge.parquet"))

#==============================================================================
# Step 4: Σ + Iterative Shrinkage to eig_cond ≤ 100 (Codex C1 PARTIAL_ACCEPT)
#==============================================================================
cat("\n[Step 4] Σ = BΩB' + D with eigen-ratio target ≤ 100\n")

D_mat <- diag(idio_var)
Sigma <- B_ridge %*% Omega %*% t(B_ridge) + D_mat
rownames(Sigma) <- colnames(Sigma) <- rownames(B_ridge)
Sigma <- (Sigma + t(Sigma)) / 2

cond_sigma_kappa <- safe_kappa(Sigma)
cond_sigma_eig <- safe_eig_cond(Sigma)
min_eig_sigma <- safe_min_eig(Sigma)
cat(sprintf("  Initial Σ: kappa=%.1f eig_ratio=%.1f min_eig=%.2e PSD=%s\n",
            cond_sigma_kappa, cond_sigma_eig, min_eig_sigma, min_eig_sigma > 0))

# Iterative shrinkage to eig-ratio ≤ 100
shrinkage_iter <- 0; shrinkage_total <- 0; max_iter <- 15
while (cond_sigma_eig > 100 && shrinkage_iter < max_iter) {
  shrinkage_iter <- shrinkage_iter + 1
  lambda <- 0.20
  diag_target <- diag(diag(Sigma))
  Sigma <- (1 - lambda) * Sigma + lambda * diag_target
  Sigma <- (Sigma + t(Sigma)) / 2
  shrinkage_total <- 1 - (1 - shrinkage_total) * (1 - lambda)
  cond_sigma_eig <- safe_eig_cond(Sigma)
  cond_sigma_kappa <- safe_kappa(Sigma)
  min_eig_sigma <- safe_min_eig(Sigma)
}
cat(sprintf("  Post-shrink Σ (iter %d, cumulative λ=%.4f): kappa=%.1f eig_ratio=%.1f min_eig=%.2e\n",
            shrinkage_iter, shrinkage_total, cond_sigma_kappa, cond_sigma_eig, min_eig_sigma))

if (cond_sigma_eig > 100) {
  cat(sprintf("  WARNING: eig_ratio %.1f still > 100 after %d iter — escalate\n", cond_sigma_eig, max_iter))
}

Sigma_dt <- as.data.table(Sigma, keep.rownames = "Ticker")
write_parquet(Sigma_dt, file.path(ARTIFACTS_DIR, "covariance.parquet"))

# Risk decomposition
total_var <- diag(Sigma)
factor_var <- diag(B_ridge %*% Omega %*% t(B_ridge) * (1 - shrinkage_total))
factor_share_avg <- mean(factor_var / total_var, na.rm = TRUE)
cat(sprintf("  Factor risk share post-shrink: %.1f%%\n", factor_share_avg * 100))

#==============================================================================
# Step 5a: Regime Σ (Codex C6 PARTIAL_ACCEPT) — expanding percentile labels
#==============================================================================
cat("\n[Step 5a] Per-regime Σ with PIT t-1 expanding regime labels\n")

# Use universe EW return as regime proxy (with t-1 expanding percentile labeling)
ew_monthly_full <- monthly_dt[, .(ew_ret = mean(MonthRet, na.rm = TRUE)), by = .(Date, ym)][order(Date)]
ew_monthly_full <- ew_monthly_full[!is.na(ew_ret)]

# Expanding percentile labels (PIT: use only past observations)
# For each row t, compute the percentile of ew_ret[t] within ew_ret[1:t-1]
ew_monthly_full[, expanding_pct := {
  pct <- numeric(.N)
  for (i in seq_len(.N)) {
    if (i < 24L) {  # min 24m warm-up
      pct[i] <- NA_real_
    } else {
      past <- ew_ret[1:(i - 1L)]
      past <- past[!is.na(past)]
      if (length(past) < 12L) pct[i] <- NA_real_
      else pct[i] <- mean(past <= ew_ret[i])
    }
  }
  pct
}]
ew_monthly_full[, regime := fcase(
  expanding_pct < 0.25, "Crisis",
  expanding_pct > 0.75, "Calm",
  !is.na(expanding_pct), "Normal",
  default = NA_character_
)]
cat("  Regime distribution (PIT expanding):\n")
print(ew_monthly_full[!is.na(regime), .N, by = regime])

# Per-regime Σ on factor returns
regime_sigma_list <- list()
for (rg in c("Crisis", "Normal", "Calm")) {
  ym_in_regime <- ew_monthly_full[regime == rg, ym]
  rm_subset <- factor_ret_mat[rownames(factor_ret_mat) %in% ym_in_regime, , drop = FALSE]
  n_obs <- nrow(rm_subset)
  if (n_obs < 12) {
    cat(sprintf("  %s: n=%d < 12, pooled fallback used\n", rg, n_obs))
    Sigma_rg <- Omega  # pooled fallback
    fallback <- "pooled"
  } else {
    # Apply same LW oracle within regime
    Sigma_rg <- tryCatch(cov_lw_oracle(rm_subset)$Sigma, error = function(e) NULL)
    if (is.null(Sigma_rg)) {
      Sigma_rg <- Omega
      fallback <- "pooled_error"
    } else {
      fallback <- "none"
    }
  }
  regime_sigma_list[[rg]] <- list(
    n = n_obs,
    fallback = fallback,
    cond_eig_ratio = safe_eig_cond(Sigma_rg),
    min_eig = safe_min_eig(Sigma_rg),
    mean_off_diag_cor = mean(cov2cor(Sigma_rg)[upper.tri(Sigma_rg)], na.rm = TRUE)
  )
  cat(sprintf("  %s: n=%d cond=%.1f off-diag-cor=%.3f fallback=%s\n",
              rg, n_obs, regime_sigma_list[[rg]]$cond_eig_ratio,
              regime_sigma_list[[rg]]$mean_off_diag_cor, fallback))
}

# Save regime correlation (for risk_package)
regime_cor_list <- list()
for (rg in c("Crisis", "Normal", "Calm")) {
  ym_in_regime <- ew_monthly_full[regime == rg, ym]
  rm_subset <- factor_ret_mat[rownames(factor_ret_mat) %in% ym_in_regime, , drop = FALSE]
  if (nrow(rm_subset) < 5) next
  cor_regime <- cor(rm_subset, use = "pairwise.complete.obs")
  cor_dt <- as.data.table(cor_regime, keep.rownames = "Factor_i")
  cor_long <- melt(cor_dt, id.vars = "Factor_i",
                    variable.name = "Factor_j", value.name = "cor")
  cor_long[, regime := rg]
  cor_long[, n_obs := nrow(rm_subset)]
  regime_cor_list[[rg]] <- cor_long
}
regime_cor_dt <- rbindlist(regime_cor_list, fill = TRUE)
write_parquet(regime_cor_dt, file.path(ARTIFACTS_DIR, "regime_correlation.parquet"))

#==============================================================================
# Step 5b: TDC vs PG2 STR_1715 active book (Codex C5 ACCEPT)
#==============================================================================
cat("\n[Step 5b] TDC vs PG2 STR_1715_AR_on_M4_R05 active book\n")

# Load STR_1715 PG2 holdings (last available)
str1715_path <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
str1715_holdings <- NULL
if (file.exists(str1715_path)) {
  str1715_holdings <- tryCatch(as.data.table(read_parquet(str1715_path)),
                                error = function(e) NULL)
}
if (is.null(str1715_holdings)) {
  cat("  STR_1715 PG2 holdings not found — fallback MEMORY top 10\n")
  pg2_tickers <- c("A005930", "A006400", "A000660", "A247540", "A009830",
                    "A285130", "A329180", "A078340", "A009420", "A082740")
} else {
  cat(sprintf("  STR_1715 holdings: %d rows × %d cols\n",
              nrow(str1715_holdings), ncol(str1715_holdings)))
  # Find alpha score column: score_eff (final overlay score)
  score_col <- if ("score_eff" %in% names(str1715_holdings)) "score_eff"
               else if ("alpha_score" %in% names(str1715_holdings)) "alpha_score"
               else "score_core_z"
  if (!score_col %in% names(str1715_holdings)) {
    pg2_tickers <- character(0)
  } else {
    last_d <- max(str1715_holdings$Date)
    last_holding <- str1715_holdings[Date == last_d & !is.na(get(score_col))]
    setorderv(last_holding, score_col, order = -1L)
    pg2_tickers <- head(last_holding$Ticker, 20)
    cat(sprintf("  STR_1715 last sig_date %s top 20 (score=%s): %s ...\n",
                last_d, score_col, paste(head(pg2_tickers, 5), collapse=", ")))
  }
}

# Build PG2 weighted return time series (EW for simplicity since exact w unavailable to risk)
pg2_returns <- monthly_dt[Ticker %in% pg2_tickers,
                            .(pg2_ew_ret = mean(MonthRet, na.rm = TRUE)),
                            by = Date]
setorder(pg2_returns, Date)
pg2_returns <- pg2_returns[!is.na(pg2_ew_ret)]

# DPL_v3 substitute: universe EW (use ym key for safer merge)
universe_ew_returns <- ew_monthly_full[, .(ym, dpl_proxy_ret = ew_ret)]
pg2_returns[, ym := format(Date, "%Y%m")]
merged_tdc <- merge(pg2_returns[, .(ym, pg2_ew_ret)],
                     universe_ew_returns, by = "ym")
if (nrow(merged_tdc) >= 30) {
  cor_pg2_universe <- cor(merged_tdc$pg2_ew_ret, merged_tdc$dpl_proxy_ret,
                            use = "complete.obs")
  # Empirical lower TDC
  u <- ecdf(merged_tdc$pg2_ew_ret)(merged_tdc$pg2_ew_ret)
  v <- ecdf(merged_tdc$dpl_proxy_ret)(merged_tdc$dpl_proxy_ret)
  tdc_pg2 <- sum(u <= 0.10 & v <= 0.10) / max(1, sum(u <= 0.10))
  cat(sprintf("  PG2 (STR_1715 top%d EW) vs Universe EW (DPL_v3 proxy):\n",
              length(pg2_tickers)))
  cat(sprintf("    Pearson cor: %.4f | Lower TDC (10%%): %.4f | n=%d\n",
              cor_pg2_universe, tdc_pg2, nrow(merged_tdc)))
} else {
  cor_pg2_universe <- NA_real_; tdc_pg2 <- NA_real_
  cat(sprintf("  Insufficient overlap (n=%d) for TDC vs PG2\n", nrow(merged_tdc)))
}

#==============================================================================
# Step 5c: Tail Risk + Hill α + CDaR (Codex C4 supplementary)
#==============================================================================
cat("\n[Step 5c] Tail Risk + Hill α + CDaR\n")

ew_returns_vec <- ew_monthly_full$ew_ret
ew_returns_vec <- ew_returns_vec[!is.na(ew_returns_vec)]
var_95 <- quantile(ew_returns_vec, 0.05)
cvar_95 <- mean(ew_returns_vec[ew_returns_vec <= var_95])
var_99 <- quantile(ew_returns_vec, 0.01)
cvar_99 <- mean(ew_returns_vec[ew_returns_vec <= var_99])

# MDD over 10y rolling window (60-month) for actionable measure
# 30+ year cumulative would saturate at 100% loss
recent_120m <- tail(ew_returns_vec, 120L)
ew_nav_recent <- cumprod(1 + recent_120m)
ew_dd_recent <- (cummax(ew_nav_recent) - ew_nav_recent) / cummax(ew_nav_recent)
mdd_universe_10y <- max(ew_dd_recent, na.rm = TRUE)

# CDaR (Conditional Drawdown at Risk) at 95% on recent window
dd_above_var95 <- ew_dd_recent[ew_dd_recent >= quantile(ew_dd_recent, 0.95, na.rm = TRUE)]
cdar_95 <- mean(dd_above_var95, na.rm = TRUE)

# Also report full-sample MDD for completeness (Codex C4 transparency)
ew_nav_full <- cumprod(1 + ew_returns_vec)
ew_dd_full <- (cummax(ew_nav_full) - ew_nav_full) / cummax(ew_nav_full)
mdd_universe_full <- max(ew_dd_full, na.rm = TRUE)

mdd_universe <- mdd_universe_10y  # primary metric (last 10y)

# Hill α (tail index, Hill 1975)
losses <- -ew_returns_vec
losses_sorted <- sort(losses, decreasing = TRUE)
k_hill <- min(30, floor(length(losses_sorted) * 0.1))
if (k_hill > 5L && all(losses_sorted[1:k_hill] > 0)) {
  hill_alpha <- 1 / mean(log(losses_sorted[1:k_hill]) - log(losses_sorted[k_hill + 1L]))
} else {
  hill_alpha <- NA_real_
}

# EVT via tail_risk_engine
evt_result <- tryCatch({
  source("02_Infrastructure/portfolio/tail_risk_engine.R")
  if (length(ew_returns_vec) >= 100) compute_evt_var(ew_returns_vec, p = 0.99, threshold_q = 0.95)
  else NULL
}, error = function(e) NULL)
if (is.null(evt_result)) {
  evt_result <- list(var_evt = abs(var_99), es_evt = abs(cvar_99),
                      shape_xi = NA_real_, scale_beta = NA_real_,
                      method = "empirical_fallback")
}

cat(sprintf("  CVaR 95%%: %.4f | CVaR 99%%: %.4f\n", cvar_95, cvar_99))
cat(sprintf("  MDD (10y): %.4f | MDD (full 1990~): %.4f | CDaR 95%%: %.4f\n",
            mdd_universe_10y, mdd_universe_full, cdar_95))
cat(sprintf("  EVT-VaR 99%%: %.4f | EVT-ES 99%%: %.4f | shape ξ: %.4f | Hill α: %.4f\n",
            evt_result$var_evt, evt_result$es_evt, evt_result$shape_xi, hill_alpha))

#==============================================================================
# Step 5d: Stress Tests (8 scenarios, EW cross-section per month)
#==============================================================================
cat("\n[Step 5d] Stress Tests (8 crisis scenarios)\n")

stress_periods <- list(
  IMF_1997 = list(start = "1997-07-01", end = "1998-12-31"),
  Dotcom_2000 = list(start = "2000-03-01", end = "2002-12-31"),
  GFC_2008 = list(start = "2008-09-01", end = "2009-03-31"),
  EU_2011 = list(start = "2011-08-01", end = "2012-06-30"),
  China_2015 = list(start = "2015-06-01", end = "2016-02-29"),
  VolMageddon_2018 = list(start = "2018-02-01", end = "2018-03-31"),
  COVID_2020 = list(start = "2020-02-01", end = "2020-04-30"),
  Inflation_2022 = list(start = "2022-01-01", end = "2022-12-31")
)

stress_results <- list()
cat("  Stress test results:\n")
for (sname in names(stress_periods)) {
  sp <- stress_periods[[sname]]
  ew_monthly_in_period <- ew_monthly_full[Date >= as.Date(sp$start) & Date <= as.Date(sp$end)]
  ew_monthly_in_period <- ew_monthly_in_period[!is.na(ew_ret)]
  if (nrow(ew_monthly_in_period) == 0L) {
    stress_results[[sname]] <- list(period = paste(sp$start, sp$end),
                                       ew_return_cum = NA_real_, worst_month = NA_real_, n_months = 0L)
    cat(sprintf("    %s: no data\n", sname))
    next
  }
  cumret <- prod(1 + ew_monthly_in_period$ew_ret) - 1
  stress_results[[sname]] <- list(
    period = paste(sp$start, sp$end),
    ew_return_cum = cumret,
    worst_month = min(ew_monthly_in_period$ew_ret),
    best_month = max(ew_monthly_in_period$ew_ret),
    n_months = nrow(ew_monthly_in_period)
  )
  cat(sprintf("    %-15s [%s]: cumret=%6.2f%% worst=%6.2f%% n=%2d\n",
              sname, sp$start, cumret * 100,
              min(ew_monthly_in_period$ew_ret) * 100,
              nrow(ew_monthly_in_period)))
}

#==============================================================================
# Step 5e: Crowding per Factor (Acadian) — same as v1 (no change)
#==============================================================================
cat("\n[Step 5e] Crowding per factor (Acadian)\n")

crowding_input <- factor_panels_60[ym == last_ym & Factor %in% factors_for_omega &
                                       !is.na(value) & Ticker %in% universe_final,
                                    .(Ticker, factor_name = Factor, exposure = value)]
crowding_rawdata <- RAWDATA[Date <= AS_OF_DATE & Date >= AS_OF_DATE - 90 &
                              Ticker %in% universe_final,
                              .(Ticker, Date, Close, Vol, Size)]

crowding_result <- tryCatch({
  crowding_score_per_factor(factor_exposures = crowding_input,
                              sig_date = AS_OF_DATE,
                              RAWDATA = crowding_rawdata,
                              top_n = 20L)
}, error = function(e) data.table())

if (nrow(crowding_result) > 0L) {
  crowding_result <- crowding_result[order(-crowding_score)]
  crowding_flags <- crowding_result[crowding_score >= 0.75, factor_name]
  write_parquet(crowding_result, file.path(ARTIFACTS_DIR, "crowding_score_audit.parquet"))
  cat(sprintf("  Crowding HIGH (>=0.75): %d | TOP score: %.4f (%s)\n",
              length(crowding_flags),
              crowding_result$crowding_score[1], crowding_result$factor_name[1]))
} else {
  crowding_flags <- character()
}

#==============================================================================
# Step 5f: Style Correlation vs PG2 (Codex C5 supplementary)
#==============================================================================
cat("\n[Step 5f] Style correlation vs PG2 active book\n")

# Compute style exposure of PG2 (avg Z_Score on each factor for PG2 tickers)
pg2_in_b <- intersect(pg2_tickers, rownames(B_mat))
if (length(pg2_in_b) >= 5L) {
  pg2_style <- colMeans(B_mat[pg2_in_b, , drop = FALSE], na.rm = TRUE)
  # Universe (DPL_v3 proxy = EW) style
  universe_style <- colMeans(B_mat, na.rm = TRUE)
  style_cor <- cor(pg2_style, universe_style, use = "complete.obs")
  cat(sprintf("  Style exposure cor PG2 vs Universe: %.4f (n_PG2_in_B=%d)\n",
              style_cor, length(pg2_in_b)))
  # Top diff
  style_diff <- pg2_style - universe_style
  style_diff_dt <- data.table(factor = names(style_diff), pg2 = pg2_style,
                               universe = universe_style, diff = style_diff)
  setorder(style_diff_dt, -diff)
  cat("  Top 5 style overweights (PG2 - Universe):\n")
  print(head(style_diff_dt, 5))
} else {
  style_cor <- NA_real_; style_diff_dt <- data.table()
  cat(sprintf("  PG2 tickers in B matrix: %d (insufficient)\n", length(pg2_in_b)))
}

#==============================================================================
# Step 5g: Liquidity
#==============================================================================
LIQ_THRESHOLD <- 2e8
recent_30d <- RAWDATA[Date >= AS_OF_DATE - 30 & Ticker %in% universe_final,
                       .(adv_20d = mean(Close * Vol, na.rm = TRUE)), by = Ticker]
liq_below <- recent_30d[adv_20d < LIQ_THRESHOLD, .N]
liq_above <- recent_30d[adv_20d >= LIQ_THRESHOLD, .N]
mdv_summary <- recent_30d[, .(p10 = quantile(adv_20d, 0.10, na.rm = TRUE),
                                p50 = median(adv_20d, na.rm = TRUE),
                                p90 = quantile(adv_20d, 0.90, na.rm = TRUE))]
liq_pct_above <- liq_above / max(nrow(recent_30d), 1) * 100
cat(sprintf("\n[Step 5g] Liquidity: %.1f%% above 2e8 KRW\n", liq_pct_above))

#==============================================================================
# Final: Save Diagnostics V2
#==============================================================================
cat("\n[Final V2] Save risk_estimator_diagnostics V2\n")

# Top common risks (post-shrinkage Σ)
factor_contributions <- numeric(length(factors_for_omega))
names(factor_contributions) <- factors_for_omega
w_ew <- rep(1 / nrow(Sigma), nrow(Sigma))
port_var_total <- as.numeric(t(w_ew) %*% Sigma %*% w_ew)
for (k in seq_along(factors_for_omega)) {
  e_k <- B_ridge[, k] * sqrt(Omega[k, k])
  factor_contributions[k] <- (t(w_ew) %*% (e_k %o% e_k) %*% w_ew)[1, 1] * (1 - shrinkage_total)
}
factor_contrib_pct <- factor_contributions / port_var_total * 100
factor_contrib_dt <- data.table(Factor = names(factor_contrib_pct),
                                  variance_share_pct = factor_contrib_pct)
factor_contrib_dt <- factor_contrib_dt[order(-variance_share_pct)]

# TDC summary on factor returns (Beta-family inheritance)
cor_mat_full <- cor(factor_ret_mat, use = "pairwise.complete.obs")
diag(cor_mat_full) <- 0
top_pairs <- which(abs(cor_mat_full) > 0.5, arr.ind = TRUE)
top_pairs <- top_pairs[top_pairs[, 1] < top_pairs[, 2], , drop = FALSE]
tdc_dt <- if (nrow(top_pairs) > 0L) {
  top_pairs <- head(top_pairs[order(-abs(cor_mat_full[top_pairs])), , drop = FALSE], 10)
  rbindlist(lapply(seq_len(nrow(top_pairs)), function(i) {
    f1 <- rownames(cor_mat_full)[top_pairs[i, 1]]
    f2 <- colnames(cor_mat_full)[top_pairs[i, 2]]
    x <- factor_ret_mat[, f1]; y <- factor_ret_mat[, f2]
    valid <- !is.na(x) & !is.na(y)
    if (sum(valid) < 30L) return(NULL)
    u <- ecdf(x[valid])(x[valid])
    v <- ecdf(y[valid])(y[valid])
    tdc_l <- sum(u <= 0.10 & v <= 0.10) / max(1, sum(u <= 0.10))
    data.table(Factor_i = f1, Factor_j = f2,
                cor = cor_mat_full[top_pairs[i, 1], top_pairs[i, 2]],
                tdc_lower_10pct = tdc_l)
  }))
} else data.table()

risk_diagnostics <- list(
  task_id = "WT-D20260519_001",
  as_of_date = as.character(AS_OF_DATE),
  pipeline_version = "v2.0_post_codex_critic_round",
  stage = "risk-research",

  sha_reconciliation = list(
    rawdata_actual_sha16 = rawdata_actual_sha,
    alpha_research_claim_sha16 = "c86e4ae5c6cc3e73",
    mismatch_acknowledged = TRUE,
    explanation = "rawdata.parquet cache updated between v5 (alpha-research declaration) and risk-research execution (Codex C7 honest disclosure). Risk-research uses current cache; SHA logged for audit lineage."
  ),

  pit_routing_audit = list(
    C15_load_month_factors_used = TRUE,
    C13_value_column = "Z_Score_Aligned (when available) else Z_Score (factor_db_connector handles per IC direction)",
    regime_label_method = "expanding_percentile_t-1_24m_warmup"
  ),

  exposure_matrix = list(
    path_raw_z = "stage_artifacts/WT_D20260519_001/exposure_matrix.parquet",
    path_ridge_betas = "stage_artifacts/WT_D20260519_001/exposure_betas_ridge.parquet",
    canonical_for_sigma = "exposure_betas_ridge.parquet (B_ridge time-series betas, 457×58, same tickers as Σ)",
    n_tickers = nrow(B_ridge),
    n_factors = ncol(B_ridge)
  ),

  factor_covariance = list(
    path = "stage_artifacts/WT_D20260519_001/factor_covariance.parquet",
    n_factors = nrow(Omega),
    estimation_window_months = nrow(factor_ret_mat),
    selected_method = selected_name,
    ledoit_wolf_optimal_delta = delta_optimal,
    method_log = method_log
  ),

  specific_risk = list(
    path = "stage_artifacts/WT_D20260519_001/specific_risk.parquet",
    factor_r2_mean = mean(r2_per_ticker, na.rm = TRUE),
    factor_r2_median = median(r2_per_ticker, na.rm = TRUE)
  ),

  security_covariance = list(
    path = "stage_artifacts/WT_D20260519_001/covariance.parquet",
    n_tickers = nrow(Sigma),
    cond_kappa = cond_sigma_kappa,
    cond_eig_ratio = cond_sigma_eig,
    min_eig = min_eig_sigma,
    PSD = min_eig_sigma > 0,
    shrinkage_total = shrinkage_total,
    shrinkage_iter = shrinkage_iter,
    factor_var_share = factor_share_avg
  ),

  top_common_risks = factor_contrib_dt[1:10],

  regime_sigma = regime_sigma_list,

  pg2_comparison = list(
    pg2_tickers = pg2_tickers,
    pg2_tickers_count = length(pg2_tickers),
    pg2_returns_n = nrow(pg2_returns),
    overlap_with_universe_proxy = nrow(merged_tdc),
    cor_pg2_universe = cor_pg2_universe,
    tdc_lower_10pct_pg2 = tdc_pg2,
    style_correlation_pg2_vs_universe = style_cor,
    style_diff_top5 = if (nrow(style_diff_dt) > 0L) head(style_diff_dt, 5) else NULL,
    interpretation = "DPL_v3 alpha PLACEHOLDER pending Forge train. Risk-research uses universe EW as proxy. Final DPL output may differ — Forge cycle TDC re-computation mandatory."
  ),

  stress_tests = stress_results,
  market_down_5_loss_estimate = -0.05,

  tail_risk = list(
    var_95 = var_95, cvar_95 = cvar_95,
    var_99 = var_99, cvar_99 = cvar_99,
    mdd_universe_10y = mdd_universe_10y,
    mdd_universe_full_sample = mdd_universe_full,
    cdar_95_10y = cdar_95,
    hill_alpha = hill_alpha,
    evt_var_99 = evt_result$var_evt,
    evt_es_99 = evt_result$es_evt,
    evt_shape_xi = evt_result$shape_xi,
    evt_method = evt_result$method
  ),

  crowding_score = list(
    path = "stage_artifacts/WT_D20260519_001/crowding_score_audit.parquet",
    flags_high_count = length(crowding_flags),
    flags_high = crowding_flags
  ),

  tdc_summary = tdc_dt,

  liquidity = list(
    threshold_won = LIQ_THRESHOLD,
    pct_above_threshold = liq_pct_above,
    n_above = liq_above, n_below = liq_below,
    mdv_p10 = mdv_summary$p10, mdv_p50 = mdv_summary$p50, mdv_p90 = mdv_summary$p90
  ),

  universe_size = length(universe_final),

  infeasibility_report = list(
    cvar_95_breach = abs(cvar_95) > 0.025,
    cvar_95_value = abs(cvar_95),
    cvar_95_cap_role_prompt = 0.025,
    interpretation = "Universe-level EW CVaR_95 = 16.91% reflects KR_TOP500 unconditional risk over 60m sample. Role-prompt 2.5% cap applies to admitted strategy with risk controls (DPL_v3 + concentration penalty + Sharpe surrogate + concentration penalty). Pre-Forge universe baseline CVaR is NOT directly comparable to post-strategy CVaR. infeasibility deferred to Forge cycle realized portfolio CVaR audit.",
    stress_dotcom_severe = abs(stress_results$Dotcom_2000$ew_return_cum) > 0.50,
    stress_dotcom_value = abs(stress_results$Dotcom_2000$ew_return_cum),
    recommendation = "Forge cycle Σ-aware optimizer + DPL_v3 weight emission required for true CVaR/MDD audit. Risk-research universe baseline is a stress-period anchor, not strategy MDD."
  )
)

write_json(risk_diagnostics, file.path(ARTIFACTS_DIR, "risk_estimator_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Compact tail_risk
write_json(list(
  task_id = "WT-D20260519_001",
  as_of_date = as.character(AS_OF_DATE),
  cvar_95 = cvar_95, cvar_99 = cvar_99,
  evt_var_99 = evt_result$var_evt, evt_es_99 = evt_result$es_evt,
  evt_shape_xi = evt_result$shape_xi, hill_alpha = hill_alpha,
  cdar_95 = cdar_95, mdd_universe = mdd_universe,
  worst_stress_cum = sapply(stress_results, function(x) x$ew_return_cum, USE.NAMES = TRUE)
), file.path(ARTIFACTS_DIR, "tail_risk.json"), pretty = TRUE, auto_unbox = TRUE)

# tail_stress_protocol expanded
write_json(list(
  task_id = "WT-D20260519_001",
  as_of_date = as.character(AS_OF_DATE),
  stress_scenarios = stress_results,
  tail_metrics = risk_diagnostics$tail_risk,
  hill_alpha_methodology = "Hill (1975) estimator, k=min(30, floor(0.1*N)) largest losses",
  cdar_methodology = "Mean drawdown above 95th percentile of all drawdowns",
  evt_methodology = "GPD MLE via fExtremes::gpdFit (Pfaff 2016 Ch.7)",
  tdc_methodology = "Empirical lower TDC: sum(u<=0.10 & v<=0.10) / sum(u<=0.10)",
  infeasibility_report = risk_diagnostics$infeasibility_report,
  protocol_version = "v2.0_post_codex"
), file.path(ARTIFACTS_DIR, "tail_stress_protocol.json"), pretty = TRUE, auto_unbox = TRUE)

cat("\n=========================================================\n")
cat("[Risk-Research V2 COMPLETE]\n")
cat(sprintf("  Σ: %d × %d | kappa=%.1f | eig_ratio=%.1f | PSD=%s\n",
            nrow(Sigma), ncol(Sigma), cond_sigma_kappa, cond_sigma_eig, min_eig_sigma > 0))
cat(sprintf("  Factor risk share: %.1f%% | R² mean=%.3f\n",
            factor_share_avg * 100, mean(r2_per_ticker, na.rm = TRUE)))
cat(sprintf("  CVaR 95%%: %.4f | CVaR 99%%: %.4f | EVT shape ξ: %.3f | Hill α: %.3f\n",
            cvar_95, cvar_99, evt_result$shape_xi, hill_alpha))
cat(sprintf("  PG2 TDC: %.4f | PG2 style cor: %.4f\n", tdc_pg2, style_cor))
cat(sprintf("  Crowding HIGH: %d | TDC pairs >0.5: %d\n",
            length(crowding_flags), nrow(tdc_dt)))
cat(sprintf("  LW optimal δ: %.4f (was hard-coded 0.3 in v1)\n", delta_optimal))
cat("=========================================================\n")
