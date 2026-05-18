#==============================================================================
# Risk Research Pipeline — WT-D20260519_001 (DPL_KR_v3)
#
# Risk Agent autonomous research per risk_research_init.md
#
# 5-step pipeline:
#   Step 1: Exposure Model B (80 features × universe × 436 sig_dates)
#   Step 2: Factor Covariance Ω (parallel estimator comparison)
#   Step 3: Specific Risk D (residual idio variance)
#   Step 4: Security Covariance Σ = BΩB' + D
#   Step 5: Stress + Crowding + Tail Risk + Regime Correlation
#
# Scope:
#   - alpha_vector PLACEHOLDER (Forge cycle pending) → universe-level Σ estimation
#   - 80 features from feature_allowlist_v2 (sha256 b3d667...) family-balanced
#   - 436 sig_dates 1990~2026 per 도훈 mandate extension
#
# Output:
#   - stage_artifacts/WT_D20260519_001/covariance.parquet (security Σ at as_of_date 2026-05-19)
#   - stage_artifacts/WT_D20260519_001/factor_covariance.parquet
#   - stage_artifacts/WT_D20260519_001/exposure_matrix.parquet
#   - stage_artifacts/WT_D20260519_001/specific_risk.parquet
#   - stage_artifacts/WT_D20260519_001/tail_risk.json
#   - stage_artifacts/WT_D20260519_001/regime_correlation.parquet
#   - stage_artifacts/WT_D20260519_001/risk_estimator_diagnostics.json
#   - stage_artifacts/WT_D20260519_001/tail_stress_protocol.json
#   - stage_artifacts/WT_D20260519_001/crowding_score_audit.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# Path setup
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source("02_Infrastructure/config.R")
source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")

WT_ID <- "WT_D20260519_001"
AS_OF_DATE <- as.Date("2026-04-30")  # last available rawdata sig_date
ARTIFACTS_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_ID)
dir.create(ARTIFACTS_DIR, recursive = TRUE, showWarnings = FALSE)

FEATURE_ALLOWLIST_PATH <- "stage_artifacts/WT_D20260517_002/feature_allowlist_v2.csv"

cat("=========================================================\n")
cat("[Risk-Research] WT-D20260519_001 DPL_KR_v3 Risk Pipeline\n")
cat("AS_OF_DATE:", as.character(AS_OF_DATE), "\n")
cat("=========================================================\n\n")

#==============================================================================
# 0. Load rawdata + feature allowlist
#==============================================================================
cat("[Step 0] Loading rawdata.parquet + feature_allowlist_v2.csv...\n")

RAWDATA_PATH <- file.path(CACHE_DIR, "rawdata.parquet")
stopifnot(file.exists(RAWDATA_PATH))
RAWDATA <- as.data.table(read_parquet(RAWDATA_PATH))
RAWDATA[, Date := as.Date(Date)]
setkey(RAWDATA, Ticker, Date)

cat(sprintf("  RAWDATA: %d rows × %d cols | %s ~ %s | %d tickers\n",
            nrow(RAWDATA), ncol(RAWDATA),
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# Compute monthly returns from daily Close
RAWDATA[, MonthEnd := as.Date(format(Date, "%Y-%m-01"))]
RAWDATA[, MonthEnd := MonthEnd + 31]  # rough month end
RAWDATA[, MonthEnd := as.Date(format(MonthEnd, "%Y-%m-01")) - 1]

# Use last day of month per ticker per month
RAWDATA[, is_month_end := Date == max(Date), by = .(Ticker, format(Date, "%Y-%m"))]
monthly_dt <- RAWDATA[is_month_end == TRUE, .(Ticker, Date, Close, Vol, Size)]
setorder(monthly_dt, Ticker, Date)
monthly_dt[, MonthRet := Close / shift(Close, 1L) - 1, by = Ticker]
monthly_dt <- monthly_dt[!is.na(MonthRet)]
# Filter zombie data: single-month return > 100% or < -50% likely data error / IPO / delisting
monthly_dt <- monthly_dt[MonthRet > -0.50 & MonthRet < 1.00]
cat(sprintf("  monthly_dt: %d rows | %s ~ %s | %d tickers\n",
            nrow(monthly_dt), min(monthly_dt$Date), max(monthly_dt$Date),
            uniqueN(monthly_dt$Ticker)))

feature_allowlist <- fread(FEATURE_ALLOWLIST_PATH)
setnames(feature_allowlist, c("feature_id", "family"), c("FeatureID", "Family"), skip_absent = TRUE)
# Strip fdb_m_ / fdb_d_ / ixsec_OTHER_X_ / d_ prefix to match factor_db Factor_Name
feature_allowlist[, Factor := gsub("^(fdb_[md]_|ixsec_OTHER_X_|d_)", "", FeatureID)]
cat(sprintf("  feature_allowlist_v2: %d features (after prefix strip)\n", nrow(feature_allowlist)))
print(feature_allowlist[, .N, by = Family][order(-N)])

#==============================================================================
# Step 1: Exposure Model B Construction
#==============================================================================
cat("\n[Step 1] Exposure Matrix B Construction\n")

# Load factor_db for AS_OF_DATE (and a sample of recent sig_dates for stability)
source("02_Infrastructure/factor_db/factor_db_connector.R")

# Sample sig_dates: 12 most recent (1Y rolling window for B estimation)
all_factor_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                                pattern = "factor_db_\\d{6}\\.parquet",
                                full.names = TRUE)
all_factor_dates <- gsub("factor_db_|\\.parquet", "", basename(all_factor_files))
recent_dates <- tail(sort(all_factor_dates), 12)
cat(sprintf("  Recent 12 sig_dates: %s ~ %s\n", recent_dates[1], tail(recent_dates, 1)))

# Load factor_db for each recent date - extract 80 allowed features
load_one_month <- function(ym_in) {
  fpath <- file.path(CACHE_DIR, "factor_db", paste0("factor_db_", ym_in, ".parquet"))
  if (!file.exists(fpath)) return(NULL)
  dt <- as.data.table(read_parquet(fpath))
  if ("Factor_Name" %in% names(dt)) setnames(dt, "Factor_Name", "Factor")
  # Filter to allowlist
  dt <- dt[Factor %in% feature_allowlist$Factor]
  if (nrow(dt) == 0L) return(NULL)
  dt[, ym := ym_in]
  dt
}

cat("  Loading 12 months factor_db (filter to 80 features)...\n")
factor_panels <- rbindlist(lapply(recent_dates, load_one_month), fill = TRUE)
if (nrow(factor_panels) == 0L) {
  cat("  WARNING: No factor data loaded. Fallback to last available month.\n")
} else {
  cat(sprintf("  factor_panels: %d rows × %d cols | %d unique factors | %d tickers\n",
              nrow(factor_panels), ncol(factor_panels),
              uniqueN(factor_panels$Factor), uniqueN(factor_panels$Ticker)))
}

# Use last sig_date for B (current portfolio exposure)
last_ym <- tail(recent_dates, 1)
B_panel <- factor_panels[ym == last_ym]
cat(sprintf("  Last sig_date %s: %d rows | %d factors | %d tickers\n",
            last_ym, nrow(B_panel), uniqueN(B_panel$Factor), uniqueN(B_panel$Ticker)))

# Pivot to Ticker × Factor matrix (exposure matrix B)
# Use Z_Score_Aligned if available, else Z_Score
val_col <- if ("Z_Score_Aligned" %in% names(B_panel)) "Z_Score_Aligned" else
           if ("Z_Score" %in% names(B_panel)) "Z_Score" else
           names(B_panel)[!names(B_panel) %in% c("Ticker", "Factor", "Date", "ym", "Universe", "Sector")][1]
cat(sprintf("  Using value column: %s\n", val_col))

B_wide <- dcast(B_panel, Ticker ~ Factor, value.var = val_col, fun.aggregate = function(x) x[1])
cat(sprintf("  B_wide: %d tickers × %d factors\n", nrow(B_wide), ncol(B_wide) - 1L))

# Coverage check: drop factors with >50% NA
factor_cov <- B_wide[, lapply(.SD, function(x) sum(!is.na(x)) / .N), .SDcols = setdiff(names(B_wide), "Ticker")]
factors_keep <- names(factor_cov)[unlist(factor_cov) >= 0.5]
factors_drop <- setdiff(names(factor_cov), factors_keep)
cat(sprintf("  Factors with coverage >= 50%%: %d (drop %d)\n", length(factors_keep), length(factors_drop)))
if (length(factors_drop) > 0L) {
  cat("    Dropped factors (low coverage):", paste(head(factors_drop, 5), collapse=", "),
      if (length(factors_drop) > 5) "...\n" else "\n")
}
B_wide <- B_wide[, c("Ticker", factors_keep), with = FALSE]

# Drop tickers with too many NA features
ticker_cov <- B_wide[, .(cov = rowMeans(!is.na(.SD))), by = Ticker, .SDcols = factors_keep]
tickers_keep <- ticker_cov[cov >= 0.7, Ticker]
B_wide <- B_wide[Ticker %in% tickers_keep]
cat(sprintf("  B_wide after ticker filter (cov>=70%%): %d tickers × %d factors\n",
            nrow(B_wide), ncol(B_wide) - 1L))

# Fill remaining NA with cross-section median (already Z-score so 0)
for (col in factors_keep) {
  B_wide[is.na(get(col)), (col) := 0]
}

# Save exposure matrix
write_parquet(B_wide, file.path(ARTIFACTS_DIR, "exposure_matrix.parquet"))
cat(sprintf("  Saved: exposure_matrix.parquet (%d × %d)\n", nrow(B_wide), ncol(B_wide)))

#==============================================================================
# Step 2: Factor Covariance Ω — Parallel Estimator Comparison
#==============================================================================
cat("\n[Step 2] Factor Covariance Ω Estimation (parallel)\n")

# Build factor returns: monthly cross-section mean of Z_Score_Aligned × forward return proxy
# Simpler: factor returns as factor_t-1 - factor_t mean Z (rebalance-style)
# For Σ purposes use direct factor exposure time series cross-correlation in returns space

# Strategy: extract factor scores per (ym, Ticker, Factor), then compute factor portfolio returns
# For computational tractability: use top-bottom quintile spread per sig_date as factor return

cat("  Loading factor_db panels for 60-month window for factor returns...\n")
recent_60 <- tail(sort(all_factor_dates), 60)
factor_panels_60 <- rbindlist(lapply(recent_60, load_one_month), fill = TRUE)
cat(sprintf("  factor_panels_60: %d rows | %d sig_dates\n",
            nrow(factor_panels_60), uniqueN(factor_panels_60$ym)))

# Merge with monthly_dt for forward return
monthly_dt[, ym := format(Date, "%Y%m")]
monthly_dt[, ym_next := format(Date + 30, "%Y%m")]

# Build factor portfolio returns: top quintile - bottom quintile
build_factor_returns <- function(panel_dt, ret_dt) {
  # panel_dt: factor scores at sig_date ym
  # ret_dt: returns at ym+1
  factor_returns <- list()
  for (fname in unique(panel_dt$Factor)) {
    fpanel <- panel_dt[Factor == fname, .(Ticker, ym, score = get(val_col))]
    if (nrow(fpanel) == 0L) next

    # Per ym: quintile split (handle ties)
    safe_quintile <- function(x) {
      bks <- quantile(x, probs = seq(0, 1, 0.2), na.rm = TRUE)
      bks <- unique(bks)
      if (length(bks) < 3) return(rep(NA_integer_, length(x)))
      as.integer(cut(x, breaks = bks, include.lowest = TRUE, labels = FALSE))
    }
    fpanel[, quintile := safe_quintile(score), by = ym]

    # Forward return: monthly return at ym+1
    ret_lookup <- ret_dt[, .(Ticker, ret_ym = ym_next, MonthRet)]
    merged <- merge(fpanel, ret_lookup, by.x = c("Ticker", "ym"), by.y = c("Ticker", "ret_ym"),
                     all.x = TRUE)
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

cat("  Building factor returns (top-bottom quintile spread)...\n")
factor_returns_dt <- build_factor_returns(factor_panels_60, monthly_dt)
cat(sprintf("  factor_returns_dt: %d rows | %d factors\n",
            nrow(factor_returns_dt), uniqueN(factor_returns_dt$Factor)))

# Pivot to wide for Ω estimation
factor_ret_wide <- dcast(factor_returns_dt, ym ~ Factor, value.var = "factor_return")
factor_cols <- setdiff(names(factor_ret_wide), "ym")
cat(sprintf("  factor_ret_wide: %d sig_dates × %d factors\n",
            nrow(factor_ret_wide), length(factor_cols)))

# Filter factors with sufficient coverage in returns space
factor_ret_cov <- factor_ret_wide[, lapply(.SD, function(x) sum(!is.na(x)) / .N), .SDcols = factor_cols]
factor_cols_keep <- factor_cols[unlist(factor_ret_cov) >= 0.7]
cat(sprintf("  Factors with returns coverage >= 70%%: %d\n", length(factor_cols_keep)))

# Filter B_wide to only keep factors in factor_cols_keep (for Σ assembly later)
factors_for_omega <- intersect(factors_keep, factor_cols_keep)
cat(sprintf("  Factors retained for Ω: %d (B ∩ returns coverage)\n", length(factors_for_omega)))

factor_ret_mat <- as.matrix(factor_ret_wide[, factors_for_omega, with = FALSE])
factor_ret_mat[is.na(factor_ret_mat)] <- 0
rownames(factor_ret_mat) <- factor_ret_wide$ym

cat(sprintf("  factor_ret_mat: %d × %d\n", nrow(factor_ret_mat), ncol(factor_ret_mat)))

# Estimator comparison — 4 methods
cat("\n  Estimator comparison (4 methods)...\n")

safe_kappa <- function(M) {
  if (is.null(M) || !is.matrix(M) || !is.numeric(M)) return(NA_real_)
  tryCatch(kappa(M, exact = FALSE), error = function(e) NA_real_)
}
safe_min_eig <- function(M) {
  if (is.null(M) || !is.matrix(M) || !is.numeric(M)) return(NA_real_)
  tryCatch(min(eigen(M, only.values = TRUE, symmetric = TRUE)$values), error = function(e) NA_real_)
}

# Method 1: Sample
Omega_sample <- cov(factor_ret_mat, use = "pairwise.complete.obs")
cond_sample <- safe_kappa(Omega_sample)
min_eig_sample <- safe_min_eig(Omega_sample)

# Method 2: Ledoit-Wolf (constant correlation target)
.cov_lw_constcor <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R, use = "pairwise.complete.obs")
  vars <- diag(S)
  sds <- sqrt(vars)
  cor_mat <- S / outer(sds, sds)
  r_bar <- (sum(cor_mat) - p) / (p * (p - 1))
  F <- outer(sds, sds) * r_bar
  diag(F) <- vars
  # Optimal shrinkage intensity (simplified)
  delta <- min(1, max(0, 0.3))  # default moderate shrinkage
  delta * F + (1 - delta) * S
}
Omega_lw <- tryCatch(.cov_lw_constcor(factor_ret_mat), error = function(e) NULL)
cond_lw <- safe_kappa(Omega_lw)
min_eig_lw <- safe_min_eig(Omega_lw)

# Method 3: Gerber + RMT
Omega_gerber <- tryCatch({
  if (exists(".get_cor_cov")) {
    G <- .get_cor_cov(factor_ret_mat, cov_method = "gerber_rmt")
    if (is.matrix(G) && is.numeric(G)) G else NULL
  } else {
    NULL
  }
}, error = function(e) NULL)
cond_gerber <- safe_kappa(Omega_gerber)
min_eig_gerber <- safe_min_eig(Omega_gerber)

# Method 4: PCA truncated (top K eigenvalue)
Omega_pca <- tryCatch({
  eig_full <- eigen(Omega_sample, symmetric = TRUE)
  K_pca <- min(15, ncol(factor_ret_mat))
  pc <- eig_full$vectors[, 1:K_pca] %*% diag(eig_full$values[1:K_pca]) %*% t(eig_full$vectors[, 1:K_pca])
  res_var <- mean(eig_full$values[(K_pca+1):length(eig_full$values)])
  diag(pc) <- diag(pc) + res_var
  (pc + t(pc)) / 2
}, error = function(e) NULL)
cond_pca <- safe_kappa(Omega_pca)
min_eig_pca <- safe_min_eig(Omega_pca)

safe_PSD <- function(x) !is.na(x) && x > 0
method_log <- data.table(
  name = c("sample", "ledoit_wolf_constcor", "gerber_rmt", "pca_truncated"),
  condition = c(cond_sample, cond_lw, cond_gerber, cond_pca),
  min_eig = c(min_eig_sample, min_eig_lw, min_eig_gerber, min_eig_pca),
  PSD = c(safe_PSD(min_eig_sample), safe_PSD(min_eig_lw),
           safe_PSD(min_eig_gerber), safe_PSD(min_eig_pca)),
  selected = c(FALSE, FALSE, FALSE, FALSE)
)
print(method_log)

# Selection objective: condition_number (R4 P3)
# Select the method with smallest condition number AND PSD
candidates <- method_log[PSD == TRUE]
selected_name <- candidates[order(condition), name][1]
method_log[name == selected_name, selected := TRUE]
cat(sprintf("\n  Selected method: %s (condition=%.1f, min_eig=%.2e)\n",
            selected_name,
            method_log[name == selected_name, condition],
            method_log[name == selected_name, min_eig]))

Omega <- switch(selected_name,
                  "sample" = Omega_sample,
                  "ledoit_wolf_constcor" = Omega_lw,
                  "gerber_rmt" = Omega_gerber,
                  "pca_truncated" = Omega_pca)
rownames(Omega) <- colnames(Omega) <- factors_for_omega

# Save factor_covariance
Omega_dt <- as.data.table(Omega, keep.rownames = "Factor")
write_parquet(Omega_dt, file.path(ARTIFACTS_DIR, "factor_covariance.parquet"))
cat(sprintf("  Saved: factor_covariance.parquet (%d × %d)\n", nrow(Omega_dt), ncol(Omega_dt) - 1L))

#==============================================================================
# Step 3: Specific Risk D
#==============================================================================
cat("\n[Step 3] Specific Risk D (idiosyncratic variance)\n")

# Build stock return panel for last 60m
stock_ret_wide <- dcast(monthly_dt[Date >= as.Date(paste0(substr(min(recent_60), 1, 4), "-",
                                                            substr(min(recent_60), 5, 6), "-01"))],
                         ym ~ Ticker, value.var = "MonthRet")
ret_cols <- setdiff(names(stock_ret_wide), "ym")
# Coverage filter: only tickers with >=70% data
ret_cov_check <- stock_ret_wide[, lapply(.SD, function(x) sum(!is.na(x)) / .N), .SDcols = ret_cols]
tickers_returns_keep <- ret_cols[unlist(ret_cov_check) >= 0.5]
cat(sprintf("  Tickers with returns coverage >= 50%%: %d\n", length(tickers_returns_keep)))

# Universe for security covariance: tickers in B_wide ∩ tickers_returns_keep
universe_final <- intersect(B_wide$Ticker, tickers_returns_keep)
cat(sprintf("  Final universe (B ∩ returns): %d tickers\n", length(universe_final)))

# Limit to top 500 by recent market cap (LIQ proxy) for KR_TOP500
ticker_size <- RAWDATA[Date >= AS_OF_DATE - 30, .(Size_avg = mean(Size, na.rm = TRUE)), by = Ticker]
universe_top500 <- ticker_size[order(-Size_avg)][1:min(500, .N), Ticker]
universe_final <- intersect(universe_final, universe_top500)
cat(sprintf("  Universe filtered to TOP500 by Size: %d tickers\n", length(universe_final)))

# Realign B_wide to universe_final
B_mat <- as.matrix(B_wide[Ticker %in% universe_final][, factors_for_omega, with = FALSE])
rownames(B_mat) <- B_wide[Ticker %in% universe_final, Ticker]
B_mat[is.na(B_mat)] <- 0
cat(sprintf("  B_mat: %d × %d\n", nrow(B_mat), ncol(B_mat)))

# Compute stock-level residual: r_i = B_i %*% f + e_i
# e_i = r_i - B_i %*% f (over 60 months window)
stock_ret_mat <- as.matrix(stock_ret_wide[, universe_final, with = FALSE])
rownames(stock_ret_mat) <- stock_ret_wide$ym

# Align factor_ret_mat ym ↔ stock_ret_mat ym
common_ym <- intersect(rownames(stock_ret_mat), rownames(factor_ret_mat))
cat(sprintf("  Common sig_dates for residual estimation: %d months\n", length(common_ym)))

stock_ret_aligned <- stock_ret_mat[common_ym, , drop = FALSE]
factor_ret_aligned <- factor_ret_mat[common_ym, , drop = FALSE]

# Proper time-series OLS per ticker: r_i,t = α + Σ_k β_i,k × f_k,t + e_i,t
# Use fitted ridge (lambda small) to handle collinearity. Then compute residual variance + R²
# B_mat (N×K) is Z-score exposures at LAST sig_date. Use time-series fit for D estimation.

# Approach: For each ticker, fit OLS regression r_i ~ factor_ret_mat
# Since K=58 and T=60, near-singular → use Ridge
fit_idio_var <- function(r_i, F_t, lambda = 0.05) {
  valid <- !is.na(r_i)
  if (sum(valid) < 20) return(list(idio_var = var(r_i, na.rm = TRUE), r2 = 0))
  r_v <- r_i[valid]
  F_v <- F_t[valid, , drop = FALSE]
  Ft_F <- crossprod(F_v) + lambda * diag(ncol(F_v))
  Ft_r <- crossprod(F_v, r_v)
  beta_hat <- tryCatch(solve(Ft_F, Ft_r), error = function(e) NULL)
  if (is.null(beta_hat)) return(list(idio_var = var(r_v, na.rm = TRUE), r2 = 0))
  fitted_v <- as.numeric(F_v %*% beta_hat)
  resid_v <- r_v - fitted_v
  tot_var <- var(r_v)
  res_var <- var(resid_v)
  r2 <- 1 - res_var / max(tot_var, 1e-12)
  list(idio_var = max(res_var, 1e-8), r2 = max(0, min(1, r2)))
}

cat("  Fitting ridge OLS per ticker for idio variance + R² + betas (T=", nrow(factor_ret_aligned),
    ", K=", ncol(factor_ret_aligned), ")...\n", sep = "")

# Updated fit: also return betas
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
  tot_var <- var(r_v)
  res_var <- var(resid_v)
  r2 <- 1 - res_var / max(tot_var, 1e-12)
  list(idio_var = max(res_var, 1e-8), r2 = max(0, min(1, r2)), betas = beta_hat)
}

idio_results <- lapply(seq_len(ncol(stock_ret_aligned)), function(i) {
  fit_idio_full(stock_ret_aligned[, i], factor_ret_aligned, lambda = 0.05)
})
idio_var <- sapply(idio_results, `[[`, "idio_var")
names(idio_var) <- colnames(stock_ret_aligned)
r2_per_ticker <- sapply(idio_results, `[[`, "r2")
names(r2_per_ticker) <- colnames(stock_ret_aligned)

# Time-series beta estimates → replace B for Σ assembly
B_ridge <- do.call(rbind, lapply(idio_results, `[[`, "betas"))
rownames(B_ridge) <- colnames(stock_ret_aligned)
colnames(B_ridge) <- factors_for_omega
cat(sprintf("  B_ridge: %d × %d (time-series ridge betas)\n", nrow(B_ridge), ncol(B_ridge)))

# Sanitize
idio_var[is.na(idio_var) | idio_var <= 0] <- median(idio_var, na.rm = TRUE)
cat(sprintf("  Factor explanation R² (ridge OLS λ=0.05): mean=%.3f median=%.3f (target > 0.20)\n",
            mean(r2_per_ticker, na.rm = TRUE),
            median(r2_per_ticker, na.rm = TRUE)))
factor_coverage_pct <- mean(r2_per_ticker, na.rm = TRUE) * 100

D_dt <- data.table(Ticker = universe_final, idio_var = idio_var,
                    idio_vol_monthly = sqrt(idio_var),
                    r2_factor = r2_per_ticker)
write_parquet(D_dt, file.path(ARTIFACTS_DIR, "specific_risk.parquet"))
cat(sprintf("  Saved: specific_risk.parquet (%d tickers)\n", nrow(D_dt)))

# Save B_ridge for Σ reproducibility
B_ridge_dt <- as.data.table(B_ridge, keep.rownames = "Ticker")
write_parquet(B_ridge_dt, file.path(ARTIFACTS_DIR, "exposure_betas_ridge.parquet"))
cat(sprintf("  Saved: exposure_betas_ridge.parquet (%d × %d)\n", nrow(B_ridge_dt), ncol(B_ridge_dt)))

#==============================================================================
# Step 4: Security Covariance Σ = BΩB' + D
#==============================================================================
cat("\n[Step 4] Security Covariance Σ = BΩB' + D\n")

D_mat <- diag(idio_var)
# Use B_ridge (time-series betas) for proper Σ = BΩB' + D
# B_mat (Z_Score cross-section exposures) kept for crowding diagnostics
Sigma <- B_ridge %*% Omega %*% t(B_ridge) + D_mat
rownames(Sigma) <- colnames(Sigma) <- rownames(B_ridge)
Sigma <- (Sigma + t(Sigma)) / 2  # symmetrize

cond_sigma <- kappa(Sigma)
min_eig_sigma <- min(eigen(Sigma, only.values = TRUE, symmetric = TRUE)$values)
cat(sprintf("  Σ: %d × %d | condition=%.1f | min_eig=%.2e | PSD=%s\n",
            nrow(Sigma), ncol(Sigma), cond_sigma, min_eig_sigma,
            ifelse(min_eig_sigma > 0, "TRUE", "FALSE")))

# Iterative shrinkage toward diagonal until condition <= 500 (or 5 attempts)
shrinkage_extra_applied <- FALSE
shrinkage_total_lambda <- 0
shrinkage_iter <- 0
while (cond_sigma > 500 && shrinkage_iter < 5) {
  shrinkage_iter <- shrinkage_iter + 1
  shrinkage_lambda <- 0.20  # 20% per iteration
  diag_target <- diag(diag(Sigma))
  Sigma <- (1 - shrinkage_lambda) * Sigma + shrinkage_lambda * diag_target
  Sigma <- (Sigma + t(Sigma)) / 2
  cond_sigma <- safe_kappa(Sigma)
  min_eig_sigma <- safe_min_eig(Sigma)
  shrinkage_total_lambda <- 1 - (1 - shrinkage_total_lambda) * (1 - shrinkage_lambda)
  cat(sprintf("  Shrinkage iter %d (λ=%.2f, cumulative=%.2f): condition=%.1f | min_eig=%.2e\n",
              shrinkage_iter, shrinkage_lambda, shrinkage_total_lambda, cond_sigma, min_eig_sigma))
  shrinkage_extra_applied <- TRUE
}
if (cond_sigma > 500) {
  cat(sprintf("  WARNING: condition still > 500 after %d iters (%.1f)\n", shrinkage_iter, cond_sigma))
}

# Save covariance
Sigma_dt <- as.data.table(Sigma, keep.rownames = "Ticker")
write_parquet(Sigma_dt, file.path(ARTIFACTS_DIR, "covariance.parquet"))
cat(sprintf("  Saved: covariance.parquet (%d × %d)\n", nrow(Sigma_dt), ncol(Sigma_dt) - 1L))

# Risk decomposition: factor risk vs idio
total_var <- diag(Sigma)
factor_var <- diag(B_ridge %*% Omega %*% t(B_ridge))
idio_var_actual <- diag(D_mat)
factor_share_avg <- mean(factor_var / total_var, na.rm = TRUE)
cat(sprintf("  Factor risk share: %.1f%% (target > 50%%, < 80%%)\n", factor_share_avg * 100))

#==============================================================================
# Step 5a: Top Common Risks (PCA on Σ)
#==============================================================================
cat("\n[Step 5a] Top Common Risks (factor variance share)\n")

# Compute factor variance contribution to total portfolio variance
# Assume EW portfolio for diagnostic
w_ew <- rep(1 / nrow(Sigma), nrow(Sigma))
port_var_total <- as.numeric(t(w_ew) %*% Sigma %*% w_ew)

# Per-factor contribution
factor_contributions <- numeric(length(factors_for_omega))
names(factor_contributions) <- factors_for_omega
for (k in seq_along(factors_for_omega)) {
  e_k <- B_ridge[, k] * sqrt(Omega[k, k])
  factor_contributions[k] <- (t(w_ew) %*% (e_k %o% e_k) %*% w_ew)[1, 1]
}
factor_contrib_pct <- factor_contributions / port_var_total * 100
factor_contrib_dt <- data.table(Factor = names(factor_contrib_pct),
                                  variance_share_pct = factor_contrib_pct)
factor_contrib_dt <- factor_contrib_dt[order(-variance_share_pct)]
cat("  Top 10 factor variance contributions:\n")
print(factor_contrib_dt[1:10])

#==============================================================================
# Step 5b: Stress Tests — 8 Crisis Scenarios
#==============================================================================
cat("\n[Step 5b] Stress Tests — 8 Crisis Scenarios\n")

# Define 8 stress periods (matching alpha-research crisis windows)
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
for (sname in names(stress_periods)) {
  sp <- stress_periods[[sname]]
  monthly_in_period <- monthly_dt[Date >= as.Date(sp$start) & Date <= as.Date(sp$end)]
  if (nrow(monthly_in_period) == 0L) {
    stress_results[[sname]] <- list(period = paste(sp$start, sp$end),
                                       ew_return = NA_real_,
                                       worst_month = NA_real_,
                                       n_months = 0L)
    next
  }
  # Equal-weight universe return (approximate stress shock)
  ew_returns <- monthly_in_period[, .(ew_ret = mean(MonthRet, na.rm = TRUE)), by = Date]
  cumret <- prod(1 + ew_returns$ew_ret, na.rm = TRUE) - 1
  worst <- min(ew_returns$ew_ret, na.rm = TRUE)
  stress_results[[sname]] <- list(period = paste(sp$start, sp$end),
                                     ew_return = cumret,
                                     worst_month = worst,
                                     n_months = nrow(ew_returns))
}

# Fix stress: aggregate at monthly EW level (not stock-level rows)
# Issue: monthly_in_period contains many tickers per month → cumret prod over stock rows
# Solution: avg by Date first → monthly EW returns → cumprod
stress_results <- list()
for (sname in names(stress_periods)) {
  sp <- stress_periods[[sname]]
  monthly_in_period <- monthly_dt[Date >= as.Date(sp$start) & Date <= as.Date(sp$end)]
  if (nrow(monthly_in_period) == 0L) {
    stress_results[[sname]] <- list(period = paste(sp$start, sp$end),
                                       ew_return_cum = NA_real_,
                                       worst_month = NA_real_,
                                       best_month = NA_real_,
                                       n_months = 0L)
    next
  }
  # Cross-section EW per Date (month)
  ew_monthly <- monthly_in_period[, .(ew_ret = mean(MonthRet, na.rm = TRUE)), by = Date][order(Date)]
  ew_monthly <- ew_monthly[!is.na(ew_ret)]
  cumret <- if (nrow(ew_monthly) > 0) prod(1 + ew_monthly$ew_ret) - 1 else NA_real_
  stress_results[[sname]] <- list(
    period = paste(sp$start, sp$end),
    ew_return_cum = cumret,
    worst_month = if (nrow(ew_monthly) > 0) min(ew_monthly$ew_ret) else NA_real_,
    best_month = if (nrow(ew_monthly) > 0) max(ew_monthly$ew_ret) else NA_real_,
    n_months = nrow(ew_monthly)
  )
}

cat("  Stress test results (EW cross-section per month):\n")
for (sname in names(stress_results)) {
  r <- stress_results[[sname]]
  cat(sprintf("    %s [%s]: cumret=%.2f%% worst=%.2f%% best=%.2f%% n=%d\n",
              sname, r$period,
              ifelse(is.na(r$ew_return_cum), NA_real_, r$ew_return_cum * 100),
              ifelse(is.na(r$worst_month), NA_real_, r$worst_month * 100),
              ifelse(is.na(r$best_month), NA_real_, r$best_month * 100),
              r$n_months))
}

# Market down -5% scenario (linear approximation)
sigma_mkt <- sqrt(mean(diag(Sigma)))  # mean monthly stock vol
market_down_5_loss <- -0.05  # absolute -5% market shock applied to EW
# Quick beta-based approx via factor "market" if present
if ("fdb_m_D02_Beta" %in% factors_for_omega) {
  avg_beta <- mean(B_mat[, "fdb_m_D02_Beta"], na.rm = TRUE)
  market_down_5_loss <- avg_beta * (-0.05)
}

#==============================================================================
# Step 5c: Tail Risk (EVT-VaR, CVaR, CDaR via PerformanceAnalytics)
#==============================================================================
cat("\n[Step 5c] Tail Risk (CVaR, EVT-VaR on EW portfolio)\n")

# EW portfolio monthly returns
ew_port_ret <- monthly_dt[Ticker %in% universe_final, .(ew_ret = mean(MonthRet, na.rm = TRUE)), by = Date]
setorder(ew_port_ret, Date)

# CVaR 95% empirical
ew_returns_vec <- ew_port_ret$ew_ret
ew_returns_vec <- ew_returns_vec[!is.na(ew_returns_vec)]
var_95 <- quantile(ew_returns_vec, 0.05)
cvar_95 <- mean(ew_returns_vec[ew_returns_vec <= var_95])
var_99 <- quantile(ew_returns_vec, 0.01)
cvar_99 <- mean(ew_returns_vec[ew_returns_vec <= var_99])

# Max drawdown
ew_nav <- cumprod(1 + ew_returns_vec)
ew_dd <- (cummax(ew_nav) - ew_nav) / cummax(ew_nav)
mdd_universe <- max(ew_dd, na.rm = TRUE)

# EVT-VaR (try tail_risk_engine)
evt_result <- tryCatch({
  source("02_Infrastructure/portfolio/tail_risk_engine.R")
  if (length(ew_returns_vec) >= 100) {
    compute_evt_var(ew_returns_vec, p = 0.99, threshold_q = 0.95)
  } else {
    NULL
  }
}, error = function(e) {
  cat(sprintf("  EVT-VaR error: %s — fallback to empirical\n", conditionMessage(e)))
  NULL
})

if (!is.null(evt_result)) {
  cat(sprintf("  EVT-VaR (99%%): %.4f | EVT-ES: %.4f | shape ξ=%.3f | method=%s\n",
              evt_result$var_evt, evt_result$es_evt, evt_result$shape_xi, evt_result$method))
} else {
  evt_result <- list(var_evt = abs(var_99), es_evt = abs(cvar_99),
                      shape_xi = NA_real_, scale_beta = NA_real_,
                      method = "empirical_fallback")
}

cat(sprintf("  CVaR 95%%: %.4f | CVaR 99%%: %.4f | MDD: %.4f\n",
            cvar_95, cvar_99, mdd_universe))

#==============================================================================
# Step 5d: Crowding Score per Factor (Acadian 2026)
#==============================================================================
cat("\n[Step 5d] Crowding Score per Factor (Acadian 2026)\n")

# Build factor_exposures for crowding_score_per_factor()
# Per factor, top 20 stocks by exposure
crowding_input <- B_panel[Factor %in% factors_for_omega & !is.na(get(val_col)) & Ticker %in% universe_final,
                            .(Ticker, factor_name = Factor, exposure = get(val_col))]
cat(sprintf("  crowding_input: %d rows × %d factors\n",
            nrow(crowding_input), uniqueN(crowding_input$factor_name)))

# Use most recent rawdata up to AS_OF_DATE
crowding_rawdata <- RAWDATA[Date <= AS_OF_DATE & Date >= AS_OF_DATE - 90 & Ticker %in% universe_final,
                              .(Ticker, Date, Close, Vol, Size)]
cat(sprintf("  crowding_rawdata: %d rows | %d tickers\n",
            nrow(crowding_rawdata), uniqueN(crowding_rawdata$Ticker)))

crowding_result <- tryCatch({
  crowding_score_per_factor(
    factor_exposures = crowding_input,
    sig_date = AS_OF_DATE,
    RAWDATA = crowding_rawdata,
    benchmark_tickers = NULL,
    top_n = 20L
  )
}, error = function(e) {
  cat(sprintf("  crowding error: %s\n", conditionMessage(e)))
  data.table()
})

if (nrow(crowding_result) > 0L) {
  crowding_result <- crowding_result[order(-crowding_score)]
  cat("  Top 10 most crowded factors:\n")
  print(crowding_result[1:10, .(factor_name, crowding_score, hhi_top, vol_concentration,
                                   passive_overlap_proxy, demand_elasticity_proxy)])

  crowding_flags <- crowding_result[crowding_score >= 0.75, factor_name]
  cat(sprintf("\n  HIGH crowding flags (>=0.75): %d factors\n", length(crowding_flags)))

  # Save crowding audit
  write_parquet(crowding_result, file.path(ARTIFACTS_DIR, "crowding_score_audit.parquet"))
  cat("  Saved: crowding_score_audit.parquet\n")
} else {
  crowding_flags <- character()
  cat("  WARNING: crowding_score_per_factor returned empty result\n")
}

#==============================================================================
# Step 5e: Regime Correlation (split by KOSPI sub-period returns)
#==============================================================================
cat("\n[Step 5e] Regime Correlation (Crisis vs Normal vs Calm)\n")

# Use BM_Ret if available to define regime per month, else fallback to universe ew
if ("BM_Ret" %in% names(RAWDATA)) {
  bm_monthly <- RAWDATA[, .(BM_ret = mean(BM_Ret, na.rm = TRUE)), by = .(MonthEnd = format(Date, "%Y%m"))]
  setnames(bm_monthly, "MonthEnd", "ym")
} else {
  bm_monthly <- ew_port_ret[, .(BM_ret = ew_ret), by = .(ym = format(Date, "%Y%m"))]
}

bm_monthly[, regime := fcase(
  BM_ret < quantile(BM_ret, 0.25, na.rm = TRUE), "Crisis",
  BM_ret > quantile(BM_ret, 0.75, na.rm = TRUE), "Calm",
  default = "Normal"
)]
cat("  Regime distribution:\n")
print(bm_monthly[, .N, by = regime])

# Compute factor cov per regime
regime_cov_list <- list()
for (rg in c("Crisis", "Normal", "Calm")) {
  ym_in_regime <- bm_monthly[regime == rg, ym]
  if (length(ym_in_regime) < 10) {
    cat(sprintf("  %s: insufficient samples (%d) — skip\n", rg, length(ym_in_regime)))
    next
  }
  rm_subset <- factor_ret_mat[rownames(factor_ret_mat) %in% ym_in_regime, , drop = FALSE]
  if (nrow(rm_subset) < 5) next
  cor_regime <- cor(rm_subset, use = "pairwise.complete.obs")
  cor_dt <- as.data.table(cor_regime, keep.rownames = "Factor_i")
  cor_long <- melt(cor_dt, id.vars = "Factor_i", variable.name = "Factor_j", value.name = "cor")
  cor_long[, regime := rg]
  regime_cov_list[[rg]] <- cor_long
}

regime_cor_dt <- rbindlist(regime_cov_list, fill = TRUE)
if (nrow(regime_cor_dt) > 0L) {
  write_parquet(regime_cor_dt, file.path(ARTIFACTS_DIR, "regime_correlation.parquet"))
  cat(sprintf("  Saved: regime_correlation.parquet (%d rows)\n", nrow(regime_cor_dt)))

  # Avg correlation shift Crisis vs Normal
  cor_summary <- regime_cor_dt[Factor_i != Factor_j,
                                .(mean_cor = mean(cor, na.rm = TRUE),
                                  median_cor = median(cor, na.rm = TRUE)),
                                by = regime]
  cat("  Mean off-diagonal factor correlations by regime:\n")
  print(cor_summary)
}

#==============================================================================
# Step 5f: TDC (Tail Dependence Coefficient) — Joe-Clayton empirical
#==============================================================================
cat("\n[Step 5f] Tail Dependence Coefficient (factor pair)\n")

# Compute empirical lower TDC for top factor pairs
compute_tdc_lower <- function(x, y, q = 0.05) {
  x_clean <- !is.na(x) & !is.na(y)
  x <- x[x_clean]; y <- y[x_clean]
  if (length(x) < 30) return(NA_real_)
  u <- ecdf(x)(x)
  v <- ecdf(y)(y)
  threshold <- q
  tdc <- sum(u <= threshold & v <= threshold) / max(1, sum(u <= threshold))
  return(tdc)
}

# Top 5 factor pairs by absolute correlation
cor_mat_full <- cor(factor_ret_mat, use = "pairwise.complete.obs")
diag(cor_mat_full) <- 0
top_pairs <- which(abs(cor_mat_full) > 0.5, arr.ind = TRUE)
top_pairs <- top_pairs[top_pairs[, 1] < top_pairs[, 2], , drop = FALSE]
if (nrow(top_pairs) > 0L) {
  top_pairs <- head(top_pairs[order(-abs(cor_mat_full[top_pairs])), , drop = FALSE], 10)
  tdc_results <- list()
  for (i in seq_len(nrow(top_pairs))) {
    f1 <- rownames(cor_mat_full)[top_pairs[i, 1]]
    f2 <- colnames(cor_mat_full)[top_pairs[i, 2]]
    tdc <- compute_tdc_lower(factor_ret_mat[, f1], factor_ret_mat[, f2], q = 0.10)
    tdc_results[[i]] <- data.table(Factor_i = f1, Factor_j = f2,
                                      cor = cor_mat_full[top_pairs[i, 1], top_pairs[i, 2]],
                                      tdc_lower_10pct = tdc)
  }
  tdc_dt <- rbindlist(tdc_results)
  cat("  Top 10 factor pairs by abs cor + TDC:\n")
  print(tdc_dt)
} else {
  tdc_dt <- data.table()
  cat("  No factor pairs with |cor| > 0.5\n")
}

#==============================================================================
# Step 5g: Liquidity Concentration Audit
#==============================================================================
cat("\n[Step 5g] Liquidity Concentration (20d ADV ≥ 2e8 KRW filter)\n")

LIQ_THRESHOLD <- 2e8
recent_30d <- RAWDATA[Date >= AS_OF_DATE - 30 & Ticker %in% universe_final,
                       .(adv_20d = mean(Close * Vol, na.rm = TRUE)), by = Ticker]
liq_below <- recent_30d[adv_20d < LIQ_THRESHOLD, .N]
liq_above <- recent_30d[adv_20d >= LIQ_THRESHOLD, .N]
cat(sprintf("  Universe LIQ ≥ 2e8 KRW: %d / %d (%.1f%%)\n",
            liq_above, nrow(recent_30d), liq_above / max(nrow(recent_30d), 1) * 100))
cat(sprintf("  Below threshold: %d tickers\n", liq_below))

# Universe MDV stats
mdv_summary <- recent_30d[, .(p10 = quantile(adv_20d, 0.10, na.rm = TRUE),
                                p50 = median(adv_20d, na.rm = TRUE),
                                p90 = quantile(adv_20d, 0.90, na.rm = TRUE))]
cat(sprintf("  ADV (won) p10=%.2e p50=%.2e p90=%.2e\n",
            mdv_summary$p10, mdv_summary$p50, mdv_summary$p90))

#==============================================================================
# Compile Diagnostics + Final Output
#==============================================================================
cat("\n[Final] Compile diagnostics + save risk_estimator_diagnostics.json\n")

risk_diagnostics <- list(
  task_id = "WT-D20260519_001",
  as_of_date = as.character(AS_OF_DATE),
  pipeline_version = "v1.0",
  stage = "risk-research",

  exposure_matrix = list(
    path = "stage_artifacts/WT_D20260519_001/exposure_matrix.parquet",
    n_tickers = nrow(B_mat),
    n_factors = ncol(B_mat),
    factors_kept = factors_for_omega,
    factors_dropped_low_coverage_count = length(factors_drop),
    note = "B_mat (Z_Score exposures cross-section) used for crowding/exposure dashboard. B_ridge (time-series ridge betas) used for Σ assembly per Step 3-4."
  ),

  factor_covariance = list(
    path = "stage_artifacts/WT_D20260519_001/factor_covariance.parquet",
    n_factors = nrow(Omega),
    estimation_window_months = nrow(factor_ret_mat),
    selected_method = selected_name,
    method_log = method_log,
    factor_returns_construction = "top_minus_bottom_quintile_spread_per_sig_date"
  ),

  specific_risk = list(
    path = "stage_artifacts/WT_D20260519_001/specific_risk.parquet",
    n_tickers = nrow(D_dt),
    factor_explanation_r2_mean = mean(r2_per_ticker, na.rm = TRUE),
    factor_explanation_r2_median = median(r2_per_ticker, na.rm = TRUE),
    factor_coverage_pct = factor_coverage_pct
  ),

  security_covariance = list(
    path = "stage_artifacts/WT_D20260519_001/covariance.parquet",
    n_tickers = nrow(Sigma),
    condition_number = cond_sigma,
    min_eig = min_eig_sigma,
    PSD = min_eig_sigma > 0,
    factor_var_share = factor_share_avg,
    shrinkage_extra_applied = shrinkage_extra_applied
  ),

  top_common_risks = factor_contrib_dt[1:10],

  stress_tests = stress_results,
  market_down_5_loss_estimate = market_down_5_loss,

  tail_risk = list(
    var_95_empirical = var_95,
    cvar_95_empirical = cvar_95,
    var_99_empirical = var_99,
    cvar_99_empirical = cvar_99,
    mdd_universe_ew = mdd_universe,
    evt_var_99 = evt_result$var_evt,
    evt_es_99 = evt_result$es_evt,
    evt_shape_xi = evt_result$shape_xi,
    evt_method = evt_result$method
  ),

  crowding_score = list(
    path = "stage_artifacts/WT_D20260519_001/crowding_score_audit.parquet",
    flags_high_count = length(crowding_flags),
    flags_high_factors = crowding_flags,
    top_5 = if (nrow(crowding_result) > 0L) crowding_result[1:5, .(factor_name, crowding_score)] else NULL
  ),

  regime_correlation = list(
    path = "stage_artifacts/WT_D20260519_001/regime_correlation.parquet",
    regime_summary = if (exists("cor_summary")) cor_summary else NULL
  ),

  tdc_summary = tdc_dt,

  liquidity = list(
    threshold_won = LIQ_THRESHOLD,
    pct_above_threshold = liq_above / max(nrow(recent_30d), 1) * 100,
    mdv_p10 = mdv_summary$p10,
    mdv_p50 = mdv_summary$p50,
    mdv_p90 = mdv_summary$p90
  ),

  universe_final_count = length(universe_final)
)

write_json(risk_diagnostics,
           file.path(ARTIFACTS_DIR, "risk_estimator_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Saved: risk_estimator_diagnostics.json\n")

# tail_stress_protocol.json (separate stress + tail summary)
tail_stress_protocol <- list(
  task_id = "WT-D20260519_001",
  as_of_date = as.character(AS_OF_DATE),
  stress_scenarios_count = 8,
  stress_scenarios = stress_results,
  tail_metrics = risk_diagnostics$tail_risk,
  tdc_summary = tdc_dt,
  protocol_version = "v1.0",
  references = c(
    "Pfaff (2016) FRM Ch.7 EVT/GPD",
    "Acerbi-Tasche (2002) CVaR axiomatic",
    "Lopez de Prado (2018) AFML Ch 7"
  )
)
write_json(tail_stress_protocol,
           file.path(ARTIFACTS_DIR, "tail_stress_protocol.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Saved: tail_stress_protocol.json\n")

# tail_risk.json (compact version for risk_package)
tail_risk_compact <- list(
  task_id = "WT-D20260519_001",
  as_of_date = as.character(AS_OF_DATE),
  cvar_95 = cvar_95,
  cvar_99 = cvar_99,
  evt_var_99 = evt_result$var_evt,
  evt_es_99 = evt_result$es_evt,
  evt_shape_xi = evt_result$shape_xi,
  mdd_universe_ew = mdd_universe,
  worst_stress = sapply(stress_results, function(x) x$worst_month, USE.NAMES = TRUE)
)
write_json(tail_risk_compact, file.path(ARTIFACTS_DIR, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Saved: tail_risk.json\n")

cat("\n=========================================================\n")
cat("[Risk-Research Pipeline COMPLETE]\n")
cat(sprintf("  Universe: %d tickers | Factors: %d | Sigma cond: %.1f\n",
            nrow(Sigma), ncol(Omega), cond_sigma))
cat(sprintf("  CVaR 95%%: %.4f | CVaR 99%%: %.4f | MDD universe: %.4f\n",
            cvar_95, cvar_99, mdd_universe))
cat(sprintf("  Crowding HIGH flags: %d | TDC pairs > 0.5: %d\n",
            length(crowding_flags), nrow(tdc_dt)))
cat("=========================================================\n")
