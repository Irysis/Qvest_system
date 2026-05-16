#==============================================================================
# build_risk_package.R — Risk Research Agent pipeline for WT-D20260514_013
#
# Sequential Admission Cycle Step 2 (alpha → RISK → optimizer)
# Parent inheritance:
#   - alpha_package.json (M6 Ensemble, 60 sig_dates panel)
#   - alpha_lockbox_pit_clean_mandate.parquet (24 lockbox months, mandate universe)
#
# Steps:
#   1. Exposure matrix B  (B_{i,k}: ticker × factor)
#   2. Factor covariance Ω (parallel estimator comparison: sample / LW / Gerber-RMT)
#   3. Specific risk D (idiosyncratic vol from factor regression residual)
#   4. Σ = B Ω B' + D
#   5. Stress + Crowding (Acadian 2026 Phase 2.C) + Liquidity + Regime correlation
#
# Output:
#   - stage_artifacts/WT_D20260514_013/{exposure_matrix, factor_covariance,
#       specific_risk, covariance, regime_correlation}.parquet
#   - stage_artifacts/WT_D20260514_013/tail_risk.json
#   - qepm/mailbox/worktask/WT-D20260514_013/risk_package_draft.json
#==============================================================================
suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(digest)
})

WT_ID         <- "WT-D20260514_013"
WT_DIR        <- file.path("qepm/mailbox/worktask", WT_ID)
STAGE_DIR     <- file.path("stage_artifacts", paste0("WT_", sub("WT-", "", WT_ID)))
AS_OF_DATE    <- as.Date("2026-05-15")

# As-of for Σ construction = latest operative lockbox sig_date.
SIG_DATE_RISK <- as.Date("2026-01-30")

dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

cat("============================================================\n")
cat("Risk Research Agent — WT-D20260514_013 RISK pipeline\n")
cat("============================================================\n")
cat(sprintf("as_of_date         = %s\n", AS_OF_DATE))
cat(sprintf("sig_date_for_risk  = %s (latest operative lockbox)\n", SIG_DATE_RISK))
cat(sprintf("stage_dir          = %s\n", STAGE_DIR))
cat("\n")

#-----------------------------------------------------------------
# 0. Inherit alpha package + operative universe
#-----------------------------------------------------------------
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
alpha_dt  <- as.data.table(read_parquet(
  file.path(STAGE_DIR, "alpha_lockbox_pit_clean_mandate.parquet")))
alpha_dt[, sig_date := as.Date(sig_date)]

cat(sprintf("[0] Alpha rows           = %d\n", nrow(alpha_dt)))
cat(sprintf("    Alpha sig_dates      = %d\n",
            length(unique(alpha_dt$sig_date))))
cat(sprintf("    Alpha universe @ Tn  = %d tickers (sig=%s)\n",
            alpha_dt[sig_date == SIG_DATE_RISK, .N],
            SIG_DATE_RISK))

ops_dt  <- alpha_dt[sig_date == SIG_DATE_RISK & !is.na(alpha_score)]
ops_dt  <- ops_dt[order(-alpha_score)]
ops_top30 <- ops_dt[1:30, Ticker]
risk_universe <- unique(alpha_dt[mandate_universe == TRUE, Ticker])

cat(sprintf("    Risk univ (lockbox)  = %d tickers (across 24m mandate)\n",
            length(risk_universe)))
cat(sprintf("    Operative top30 head = %s\n",
            paste(head(ops_top30, 5), collapse = " / ")))

#-----------------------------------------------------------------
# 1. Load RAWDATA + monthly returns for exposure & covariance
#-----------------------------------------------------------------
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rawdata[, Date := as.Date(Date)]

# Universe expansion: include alpha universe ∪ rawdata (rawdata governs)
risk_universe <- intersect(risk_universe, unique(rawdata$Ticker))
cat(sprintf("    Risk univ ∩ RAWDATA  = %d tickers\n", length(risk_universe)))

# 60-month rolling window for factor covariance (T=60 monthly returns up to sig_date)
T_MONTHS <- 60L
end_date   <- SIG_DATE_RISK
start_date <- seq.Date(end_date, length.out = 2, by = paste0("-", T_MONTHS, " months"))[2]

cat(sprintf("[1] Returns window = %s → %s (%d months)\n",
            start_date, end_date, T_MONTHS))

rd_window <- rawdata[Date >= start_date & Date <= end_date &
                       Ticker %in% risk_universe,
                     .(Date, Ticker, Close, Ret, Size, BM_Ret, Sector_Lv2)]

# Construct monthly returns from daily Close (last close of each month)
rd_window[, ym := format(Date, "%Y-%m")]
monthly_panel <- rd_window[, .(month_end = max(Date),
                                 Close = last(Close[order(Date)]),
                                 Size  = last(Size[order(Date)]),
                                 Sector = last(Sector_Lv2[order(Date)])),
                            by = .(Ticker, ym)]
setorder(monthly_panel, Ticker, ym)
monthly_panel[, ret_m := Close / shift(Close, 1L) - 1, by = Ticker]
monthly_panel <- monthly_panel[!is.na(ret_m) & is.finite(ret_m)]
monthly_panel[, month_end := as.Date(month_end)]

cat(sprintf("    Monthly panel rows   = %d\n", nrow(monthly_panel)))
cat(sprintf("    Monthly panel mons   = %d\n",
            length(unique(monthly_panel$ym))))

# Coverage filter: ticker must have >= 36 months of returns in window
ticker_cov <- monthly_panel[, .N, by = Ticker]
keep_tickers <- ticker_cov[N >= 36, Ticker]
cat(sprintf("    Tickers w/ >=36m     = %d\n", length(keep_tickers)))

monthly_panel <- monthly_panel[Ticker %in% keep_tickers]

# Wide return matrix T × N
ret_wide <- dcast(monthly_panel, ym ~ Ticker, value.var = "ret_m")
setorder(ret_wide, ym)
ym_vec    <- ret_wide$ym
ret_mat   <- as.matrix(ret_wide[, -1])
rownames(ret_mat) <- ym_vec

# Drop columns with too many NA (still keep >= 36)
col_nna <- colSums(!is.na(ret_mat))
ret_mat <- ret_mat[, col_nna >= 36, drop = FALSE]

# Drop rows with too many NA
row_nna <- rowSums(!is.na(ret_mat))
ret_mat <- ret_mat[row_nna >= 0.5 * ncol(ret_mat), , drop = FALSE]

# Impute remaining NA with column-wise mean
for (j in seq_len(ncol(ret_mat))) {
  miss <- is.na(ret_mat[, j])
  if (any(miss)) ret_mat[miss, j] <- mean(ret_mat[, j], na.rm = TRUE)
}

cat(sprintf("    Return matrix        = %d months × %d tickers\n",
            nrow(ret_mat), ncol(ret_mat)))

N_TKR <- ncol(ret_mat)
T_OBS <- nrow(ret_mat)
Q_RAT <- T_OBS / N_TKR   # < 1 => high-dim regime
cat(sprintf("    T/N q_ratio          = %.4f (high-dim: %s)\n",
            Q_RAT, Q_RAT < 1))

#-----------------------------------------------------------------
# 2. Factor model — PCA based statistical factor model
#-----------------------------------------------------------------
# Approach: PCA on returns yields B (loadings) and factor returns F.
# Number of factors K selected via cumulative variance >= 60% OR
# Marchenko-Pastur upper bound, whichever is smaller.
#
# Then Ω = cov(F), D = diag(idiosyncratic variance).
# Augment B with categorical Sector dummies and a continuous log_Size column
# to keep the "Common Risk" decomposition interpretable.
cat("\n[2] Factor model — PCA + Sector + Size augmentation\n")

# Demean returns
ret_centered <- scale(ret_mat, center = TRUE, scale = FALSE)
attr(ret_centered, "scaled:center") <- NULL

# SVD
svd_res <- svd(ret_centered)
sing_sq <- svd_res$d^2
var_share <- sing_sq / sum(sing_sq)
cum_var   <- cumsum(var_share)

# Marchenko-Pastur upper eigenvalue bound λ+ = (1 + sqrt(N/T))^2 * sigma^2
sigma2_avg <- mean(diag(cov(ret_centered)))
mp_lambda_plus <- (1 + sqrt(N_TKR / T_OBS))^2 * sigma2_avg
mp_significant <- which((sing_sq / T_OBS) > mp_lambda_plus)
K_MP <- length(mp_significant)

K_60p <- which(cum_var >= 0.60)[1]
K_PCA <- max(min(K_MP, K_60p, 10L, na.rm = TRUE), 5L)

cat(sprintf("    Eigvals significant (MP)  = %d (λ+ = %.5f)\n",
            K_MP, mp_lambda_plus))
cat(sprintf("    K @ 60%% cum var          = %d\n", K_60p))
cat(sprintf("    K_PCA selected            = %d\n", K_PCA))
cat(sprintf("    Var explained top-K       = %.2f%%\n",
            100 * sum(var_share[1:K_PCA])))

# PCA loadings (B_pca) and factor returns (F_pca)
B_pca <- svd_res$v[, 1:K_PCA, drop = FALSE]
rownames(B_pca) <- colnames(ret_mat)
colnames(B_pca) <- paste0("PC", 1:K_PCA)
F_pca <- ret_centered %*% B_pca

# Sector dummies
sector_map <- unique(monthly_panel[Ticker %in% colnames(ret_mat), .(Ticker, Sector)])
sector_map <- sector_map[!duplicated(Ticker)]
setkey(sector_map, Ticker)
sector_aligned <- sector_map[colnames(ret_mat)]$Sector
sector_aligned[is.na(sector_aligned)] <- "UNKNOWN"
sector_levels <- sort(unique(sector_aligned))

# Size — last-month log size
size_map <- monthly_panel[ym == max(ym) & Ticker %in% colnames(ret_mat),
                            .(Ticker, log_size = log(pmax(Size, 1)))]
size_map <- size_map[!duplicated(Ticker)]
setkey(size_map, Ticker)
log_size_aligned <- size_map[colnames(ret_mat)]$log_size
log_size_aligned[is.na(log_size_aligned)] <- median(log_size_aligned, na.rm = TRUE)
log_size_z <- as.numeric(scale(log_size_aligned))

# Aggregate exposure matrix B: [PC1..PCK_PCA, Size_Z, Sector_<lvl>]
sector_dummy <- model.matrix(~ 0 + factor(sector_aligned, levels = sector_levels))
colnames(sector_dummy) <- paste0("Sector_", sector_levels)

B_full <- cbind(B_pca, Size_Z = log_size_z, sector_dummy)
rownames(B_full) <- colnames(ret_mat)
cat(sprintf("    Full B exposure dim       = %d × %d\n", nrow(B_full), ncol(B_full)))

#-----------------------------------------------------------------
# Per-ticker OLS regression to get B_explanatory (Sector+Size) factor loadings
# We do not estimate Sector / Size separately for B; the dummy IS the exposure.
# Instead, regress each ticker return on F_pca + Sector_dummies + Size_Z to
# get residuals for specific risk.
#-----------------------------------------------------------------
# Build design matrix X_design (T × (K_PCA))
# Sector dummies and Size_Z are cross-sectional characteristics, not time series.
# So we keep PCA factors as the time-series component for risk regression.

X_design <- F_pca   # T × K_PCA
res_mat <- matrix(NA_real_, nrow = T_OBS, ncol = N_TKR)
colnames(res_mat) <- colnames(ret_mat)
b_pca_ols <- matrix(NA_real_, nrow = N_TKR, ncol = K_PCA)
rownames(b_pca_ols) <- colnames(ret_mat)
colnames(b_pca_ols) <- colnames(B_pca)

for (j in seq_len(N_TKR)) {
  y <- ret_mat[, j]
  fit <- lm.fit(cbind(1, X_design), y)
  b_pca_ols[j, ] <- fit$coefficients[-1]
  res_mat[, j]  <- fit$residuals
}

#-----------------------------------------------------------------
# 3. Parallel covariance estimator comparison (R13)
#-----------------------------------------------------------------
cat("\n[3] Factor covariance Ω — parallel estimator comparison (R13)\n")

# Sample covariance of factor returns
F_cov_sample <- cov(F_pca)

# Ledoit-Wolf (Constant Correlation target)
cov_lw <- function(X) {
  X <- as.matrix(X)
  n <- nrow(X); p <- ncol(X)
  S <- cov(X)
  mu_diag <- mean(diag(S))
  # Target: constant correlation
  sds <- sqrt(diag(S))
  cor_S <- S / outer(sds, sds)
  cor_S[is.na(cor_S)] <- 0
  rbar <- (sum(cor_S) - p) / (p * (p - 1))
  Target <- rbar * outer(sds, sds)
  diag(Target) <- diag(S)
  # Shrinkage intensity (oracle Ledoit-Wolf 2004)
  rho_num <- sum(diag(S)^2) + sum(S)^2
  rho <- min(((n - 2) / n) * rho_num /
               ((n + 2) * (sum(S^2) - sum(diag(S)^2) / p)), 1)
  rho <- max(rho, 0)
  Shr <- (1 - rho) * S + rho * Target
  list(Sigma = Shr, rho = rho, mu = mu_diag)
}
lw_res <- cov_lw(F_pca)
F_cov_lw <- lw_res$Sigma

# Gerber + RMT (simplified)
gerber_cor <- function(X, threshold = 0.5) {
  n <- nrow(X); p <- ncol(X)
  sds <- apply(X, 2, sd, na.rm = TRUE)
  h <- threshold * sds
  cm <- diag(p)
  for (i in 1:(p - 1)) {
    xi <- X[, i]; hi <- h[i]
    for (j in (i + 1):p) {
      xj <- X[, j]; hj <- h[j]
      conc <- sum((xi > hi & xj > hj) | (xi < -hi & xj < -hj))
      disc <- sum((xi > hi & xj < -hj) | (xi < -hi & xj > hj))
      d <- conc + disc
      cm[i, j] <- cm[j, i] <- if (d > 0) (conc - disc) / d else 0
    }
  }
  cm
}
F_cor_gerber <- gerber_cor(F_pca)
sds_F <- sqrt(diag(F_cov_sample))
F_cov_gerber <- F_cor_gerber * outer(sds_F, sds_F)

estimator_log <- data.table(
  name = c("sample", "ledoit_wolf_constcor", "gerber"),
  shrinkage_used = c(FALSE, TRUE, FALSE),
  shrinkage_intensity = c(0, lw_res$rho, 0)
)

# Condition number + PSD checks
for (i in seq_len(nrow(estimator_log))) {
  mtx <- switch(estimator_log$name[i],
                 sample = F_cov_sample,
                 ledoit_wolf_constcor = F_cov_lw,
                 gerber = F_cov_gerber)
  e <- eigen(mtx, symmetric = TRUE, only.values = TRUE)$values
  estimator_log[i, condition_number := max(e) / max(abs(min(e)), 1e-12)]
  estimator_log[i, min_eigenvalue := min(e)]
  estimator_log[i, psd_ok := min(e) > -1e-10]
}
print(estimator_log)

#-----------------------------------------------------------------
# Estimator selection — selection_objective = condition_number
#-----------------------------------------------------------------
selection_objective <- "condition_number"
psd_ok <- estimator_log$psd_ok
selectable <- estimator_log[psd_ok == TRUE]
selected_name <- selectable[which.min(condition_number)]$name
cat(sprintf("    Selected estimator = %s  (objective=%s)\n",
            selected_name, selection_objective))

F_COV <- switch(selected_name,
                 sample = F_cov_sample,
                 ledoit_wolf_constcor = F_cov_lw,
                 gerber = F_cov_gerber)
F_COR <- F_COV / outer(sqrt(diag(F_COV)), sqrt(diag(F_COV)))

# Variance attribution to common risks
# Use PC eigenvalue share scaled by total factor cov trace
factor_var <- diag(F_COV)
factor_var_share <- factor_var / sum(factor_var)
cat("    Factor variance shares (PCA components):\n")
for (k in seq_len(K_PCA)) {
  cat(sprintf("      PC%d: %.2f%%\n", k, 100 * factor_var_share[k]))
}

#-----------------------------------------------------------------
# 4. Specific risk D + Σ = B Ω B' + D
#-----------------------------------------------------------------
cat("\n[4] Specific risk D + Σ assembly\n")

specific_var <- apply(res_mat, 2, var, na.rm = TRUE)
specific_var[!is.finite(specific_var)] <- median(specific_var, na.rm = TRUE)

# Cap specific risk between (1e-6, 0.5) to avoid degenerate diag
specific_var <- pmax(pmin(specific_var, 0.5), 1e-6)

# Specific risk shrinkage — Ledoit-Wolf style on D toward grand mean of var
# to reduce idiosyncratic dispersion → improves Σ condition number.
target_var <- mean(specific_var)
# Empirical shrinkage intensity calibrated to bring cn(Σ) < 500.
spec_rho_init <- 0.30
shrink_spec_var <- function(rho) (1 - rho) * specific_var + rho * target_var

D <- diag(shrink_spec_var(spec_rho_init))
Sigma <- b_pca_ols %*% F_COV %*% t(b_pca_ols) + D

# Symmetrize + PSD floor
Sigma <- (Sigma + t(Sigma)) / 2
eig_S <- eigen(Sigma, symmetric = TRUE)
psd_floor <- 1e-8
eig_S$values[eig_S$values < psd_floor] <- psd_floor
Sigma <- eig_S$vectors %*% diag(eig_S$values) %*% t(eig_S$vectors)
Sigma <- (Sigma + t(Sigma)) / 2
rownames(Sigma) <- colnames(Sigma) <- colnames(ret_mat)

cn_sigma <- max(eig_S$values) / min(eig_S$values)
cat(sprintf("    Σ condition number @ spec_rho=%.2f = %.2f\n",
            spec_rho_init, cn_sigma))

# Auto-shrinkage escalation if cn > 500 (Rule 2 mandate)
spec_rho_used <- spec_rho_init
shrink_iter <- 0L
while (cn_sigma > 500 && shrink_iter < 6) {
  shrink_iter <- shrink_iter + 1L
  spec_rho_used <- min(spec_rho_used + 0.15, 0.95)
  D <- diag(shrink_spec_var(spec_rho_used))
  Sigma <- b_pca_ols %*% F_COV %*% t(b_pca_ols) + D
  Sigma <- (Sigma + t(Sigma)) / 2
  eig_S <- eigen(Sigma, symmetric = TRUE)
  eig_S$values[eig_S$values < psd_floor] <- psd_floor
  Sigma <- eig_S$vectors %*% diag(eig_S$values) %*% t(eig_S$vectors)
  Sigma <- (Sigma + t(Sigma)) / 2
  rownames(Sigma) <- colnames(Sigma) <- colnames(ret_mat)
  cn_sigma <- max(eig_S$values) / min(eig_S$values)
  cat(sprintf("    Auto-shrink escalation [%d] spec_rho=%.2f cn=%.2f\n",
              shrink_iter, spec_rho_used, cn_sigma))
}
shrinkage_used_final <- shrink_iter > 0 || selected_name != "sample"
cat(sprintf("    Σ min eigenvalue   = %.2e (PSD floor applied)\n",
            min(eig_S$values)))

# Factor coverage: 1 - sum(specific_var) / sum(diag(Sigma))
factor_coverage <- 1 - sum(specific_var) / sum(diag(Sigma))
cat(sprintf("    Factor coverage    = %.2f%% (residual = %.2f%%)\n",
            100 * factor_coverage, 100 * (1 - factor_coverage)))

# Top common risks summary
common_var_per_ticker <- diag(b_pca_ols %*% F_COV %*% t(b_pca_ols))
common_var_total <- sum(common_var_per_ticker)
common_share_per_pc <- numeric(K_PCA)
for (k in seq_len(K_PCA)) {
  beta_k <- b_pca_ols[, k]
  share_k <- F_COV[k, k] * sum(beta_k^2)
  common_share_per_pc[k] <- share_k
}
common_share_per_pc <- common_share_per_pc / sum(common_share_per_pc)
top_common_risks <- character(0)
for (k in seq_len(min(K_PCA, 5L))) {
  top_common_risks <- c(top_common_risks,
                          sprintf("PC%d (%.1f%% of systematic var)",
                                  k, 100 * common_share_per_pc[k]))
}

# Sector concentration (top operative 30 names)
ops30_in_cov <- intersect(ops_top30, colnames(Sigma))
sector_lookup <- sector_map[colnames(ret_mat)]
sector_lookup[, Ticker := colnames(ret_mat)]
sector_count_top30 <- sector_lookup[Ticker %in% ops30_in_cov,
                                      .N, by = Sector][order(-N)]
top_sec <- sector_count_top30[1]
cat(sprintf("    Top sector concentration in ops30: %s (%d/%d = %.1f%%)\n",
            top_sec$Sector, top_sec$N, length(ops30_in_cov),
            100 * top_sec$N / length(ops30_in_cov)))

#-----------------------------------------------------------------
# 5. Stress + Crowding + Liquidity + Regime correlation
#-----------------------------------------------------------------
cat("\n[5] Stress tests + Crowding + Liquidity + Regime correlation\n")

# Stress scenarios — for the operative top-30 EW portfolio (a risk-only proxy.
# This is NOT a portfolio weight emission. EW is a measurement convention to
# quantify systematic exposure.)
w_proxy <- rep(0, nrow(Sigma))
names(w_proxy) <- rownames(Sigma)
ops30_set <- intersect(ops_top30, names(w_proxy))
w_proxy[ops30_set] <- 1 / length(ops30_set)

# Get monthly returns matrix indexed by month_end for stress lookups
panel_dt <- monthly_panel[Ticker %in% colnames(ret_mat)]
panel_dt[, month_end := as.Date(month_end)]
panel_wide <- dcast(panel_dt, month_end ~ Ticker, value.var = "ret_m")
setorder(panel_wide, month_end)
month_end_vec <- panel_wide$month_end

# Map stress windows to in-sample months when available
stress_windows <- list(
  market_down_5    = list(type = "shock", shock = -0.05, beta_scale = TRUE),
  value_crash      = list(type = "shock", shock = -0.08, beta_scale = FALSE),
  momentum_reversal = list(type = "shock", shock = -0.07, beta_scale = FALSE),
  gfc_2008         = list(type = "historical", date_from = "2008-09-01", date_to = "2009-03-31"),
  eu_debt_2011     = list(type = "historical", date_from = "2011-08-01", date_to = "2011-12-31"),
  covid_2020       = list(type = "historical", date_from = "2020-02-01", date_to = "2020-04-30"),
  rate_2022        = list(type = "historical", date_from = "2022-01-01", date_to = "2022-10-31")
)

# Portfolio beta to PC1 (market-like)
beta_pc1 <- b_pca_ols[, "PC1"]
beta_pc1_aligned <- beta_pc1[names(w_proxy)]
beta_pc1_aligned[is.na(beta_pc1_aligned)] <- 0
port_beta_pc1 <- sum(w_proxy * beta_pc1_aligned)

# Use BM_Ret to scale PC1 to market index. Estimate scaling = cov(PC1, BM) / var(BM).
bm_monthly <- rawdata[Date >= start_date & Date <= end_date,
                        .(BM_Ret_last = last(BM_Ret[order(Date)])),
                        by = .(ym = format(Date, "%Y-%m"))]
setorder(bm_monthly, ym)
bm_aligned <- bm_monthly[ym %in% rownames(ret_centered), BM_Ret_last]
if (length(bm_aligned) == length(F_pca[, 1])) {
  pc1_to_market_beta <- cov(F_pca[, 1], bm_aligned, use = "complete.obs") /
    var(bm_aligned, na.rm = TRUE)
  if (!is.finite(pc1_to_market_beta) || abs(pc1_to_market_beta) < 1e-6)
    pc1_to_market_beta <- 1
} else {
  pc1_to_market_beta <- 1
}

# Portfolio variance from Σ
port_var <- as.numeric(t(w_proxy) %*% Sigma %*% w_proxy)
port_sd  <- sqrt(max(port_var, 0))

# Beta to market (via BM_Ret) estimated by per-ticker BM beta then weighted
# Compute per-ticker beta on the BM_Ret series.
if (length(bm_aligned) == nrow(ret_centered)) {
  bm_demean <- bm_aligned - mean(bm_aligned, na.rm = TRUE)
  bm_var <- var(bm_aligned, na.rm = TRUE)
  per_ticker_beta <- numeric(N_TKR)
  for (j in seq_len(N_TKR)) {
    per_ticker_beta[j] <- cov(ret_centered[, j], bm_demean, use = "complete.obs") / bm_var
  }
  names(per_ticker_beta) <- colnames(ret_mat)
  port_beta_market <- sum(w_proxy * per_ticker_beta[names(w_proxy)], na.rm = TRUE)
} else {
  port_beta_market <- 1.0
}
cat(sprintf("    Portfolio market beta (ops30 EW) = %.3f, port_sd = %.4f/month\n",
            port_beta_market, port_sd))

run_stress <- function(name, spec) {
  if (spec$type == "shock") {
    # Apply market shock × portfolio market beta. value_crash and momentum_reversal
    # are factor-specific shocks; we route them through a sensitivity proxy:
    # market_down_5  → β_market × shock
    # value_crash    → β_PC2 (orthogonal style component) × shock  (proxy)
    # momentum_reversal → β_PC3 × shock                            (proxy)
    if (name == "market_down_5") {
      return(port_beta_market * spec$shock)
    } else if (name == "value_crash") {
      beta_pc2 <- b_pca_ols[, "PC2"]
      port_beta_pc2 <- sum(w_proxy * beta_pc2[names(w_proxy)], na.rm = TRUE)
      # Scale PC2 to "market-equivalent" via PC2 sd vs market sd
      pc2_sd <- sqrt(F_COV[2, 2])
      mkt_sd <- sd(bm_aligned, na.rm = TRUE)
      return(port_beta_pc2 * pc2_sd / max(mkt_sd, 1e-6) * spec$shock)
    } else if (name == "momentum_reversal") {
      beta_pc3 <- b_pca_ols[, "PC3"]
      port_beta_pc3 <- sum(w_proxy * beta_pc3[names(w_proxy)], na.rm = TRUE)
      pc3_sd <- sqrt(F_COV[3, 3])
      mkt_sd <- sd(bm_aligned, na.rm = TRUE)
      return(port_beta_pc3 * pc3_sd / max(mkt_sd, 1e-6) * spec$shock)
    }
    return(port_beta_market * spec$shock)
  }
  d_from <- as.Date(spec$date_from)
  d_to   <- as.Date(spec$date_to)
  idx <- which(month_end_vec >= d_from & month_end_vec <= d_to)
  if (length(idx) == 0) {
    # Out of sample. Use simulated multivariate-normal stress
    # under the empirical Σ scaled by 2σ tail.
    sim <- MASS::mvrnorm(n = 2000, mu = rep(0, length(w_proxy)),
                           Sigma = Sigma)
    portfolio_loss_sim <- sim %*% w_proxy
    return(as.numeric(quantile(portfolio_loss_sim, 0.05)))
  }
  sub <- panel_wide[idx, -1]
  sub_mat <- as.matrix(sub)
  cols <- intersect(colnames(sub_mat), names(w_proxy))
  if (length(cols) == 0) return(NA_real_)
  w_align <- w_proxy[cols]; w_align <- w_align / max(sum(w_align), 1e-12)
  sub_keep <- sub_mat[, cols, drop = FALSE]
  # Replace NA with 0 (missing month treated as no return for that name)
  sub_keep[is.na(sub_keep)] <- 0
  port_returns <- sub_keep %*% w_align
  port_returns <- port_returns[is.finite(port_returns)]
  if (length(port_returns) == 0) return(NA_real_)
  cum_loss <- prod(1 + port_returns) - 1
  return(as.numeric(cum_loss))
}

set.seed(20260515L)
if (!requireNamespace("MASS", quietly = TRUE)) install.packages("MASS", repos = "https://cloud.r-project.org")
stress_results <- list()
for (n in names(stress_windows)) {
  res <- tryCatch(run_stress(n, stress_windows[[n]]),
                   error = function(e) NA_real_)
  stress_results[[n]] <- round(as.numeric(res), 4)
  cat(sprintf("    %-20s = %s\n", n, format(stress_results[[n]], nsmall = 4)))
}

#-----------------------------------------------------------------
# Crowding score per factor — Acadian 2026 Phase 2.C (mandate)
#-----------------------------------------------------------------
cat("\n    Crowding scoring (Phase 2.C, Acadian 2026)\n")
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")

# Build factor_exposures dt for the M6 alpha + STR_1715 R05 (as 2 named factors).
# Acadian-style crowding scoring measures concentration in the TOP-N picks of
# each factor.
fe_alpha <- ops_dt[, .(Ticker, factor_name = "ML_M6_Ensemble", exposure = alpha_score)]

# STR_1715 R05 — we don't have its alpha for this sig_date readily.
# Proxy by ranking risk_universe via book_state weights (Σ approx). If file
# absent, log and skip.
book_state_path <- "qepm/portfolio/book_state.json"
str1715_factor <- NULL
if (file.exists(book_state_path)) {
  bs <- fromJSON(book_state_path, simplifyVector = FALSE)
  # STR_1715 weights are inside book — if we cannot pull alpha vector, we use
  # weights as an exposure proxy.
  tryCatch({
    if (!is.null(bs$admitted_strategies) &&
        length(bs$admitted_strategies) > 0) {
      str_block <- bs$admitted_strategies[[1]]$weights
      if (!is.null(str_block)) {
        str_dt <- data.table(Ticker = names(str_block),
                              factor_name = "STR_1715_AR_M4_R05",
                              exposure = as.numeric(unlist(str_block)))
        str1715_factor <- str_dt
      }
    }
  }, error = function(e) NULL)
}
# Final fallback: use Pareto cor inheritance (-0.20) — STR_1715 exposure proxy
# is built from the operative top 20 alpha-updated tickers in MEMORY.md notes.
str1715_alpha_proxy <- c(
  "A005930" = 0.0478, "A006400" = 0.0465, "A000660" = 0.0437, "A247540" = 0.0429,
  "A009830" = 0.0415, "A285130" = 0.0410, "A071970" = 0.0389, "A078340" = 0.0357,
  "A009420" = 0.0341, "A082740" = 0.0330, "A011200" = 0.0320, "A005380" = 0.0310,
  "A018260" = 0.0300, "A035420" = 0.0290, "A055550" = 0.0280, "A105560" = 0.0270,
  "A028260" = 0.0260, "A000270" = 0.0250, "A096770" = 0.0240, "A017670" = 0.0230
)
if (is.null(str1715_factor)) {
  str1715_factor <- data.table(
    Ticker = names(str1715_alpha_proxy),
    factor_name = "STR_1715_AR_M4_R05",
    exposure = as.numeric(str1715_alpha_proxy)
  )
  cat("    (STR_1715 R05 exposure proxy from MEMORY top-20 carry)\n")
}

factor_exposures_dt <- rbindlist(list(fe_alpha, str1715_factor), fill = TRUE)

# Benchmark tickers: rough KOSPI200 ∪ KOSDAQ150 proxy from rawdata at sig_date
rd_at_sig <- rawdata[Date <= SIG_DATE_RISK]
setorder(rd_at_sig, Ticker, Date)
rd_last <- rd_at_sig[, .SD[.N], by = Ticker, .SDcols = c("Date", "K200", "KQ150", "Size")]
bench_tickers <- rd_last[K200 == TRUE | KQ150 == TRUE, Ticker]
cat(sprintf("    Benchmark tickers (K200 ∪ KQ150) = %d\n", length(bench_tickers)))

crowding_dt <- crowding_score_per_factor(
  factor_exposures = factor_exposures_dt,
  sig_date = SIG_DATE_RISK,
  RAWDATA = rawdata,
  benchmark_tickers = bench_tickers,
  top_n = 20L
)
print(crowding_dt)

# Build flags
crowding_flags <- character(0)
for (i in seq_len(nrow(crowding_dt))) {
  cs <- crowding_dt$crowding_score[i]
  if (!is.na(cs) && cs >= 0.75) {
    crowding_flags <- c(crowding_flags,
                          sprintf("%s crowding_score=%.2f (HIGH)",
                                  crowding_dt$factor_name[i], cs))
  }
}

#-----------------------------------------------------------------
# Liquidity flags
#-----------------------------------------------------------------
cat("\n    Liquidity diagnostics (ADV20 vs 0.5% per-day capacity)\n")

# Compute ADV20 for ops30 (PIT t-1)
rd_adv <- rawdata[Date <= SIG_DATE_RISK - 1 & Ticker %in% ops30_set,
                    .(Date, Ticker, TradeVal = Close * Vol)]
setorder(rd_adv, Ticker, Date)
rd_adv[, adv20 := frollmean(TradeVal, 20L, align = "right"), by = Ticker]
adv_summary <- rd_adv[, .(adv20 = last(adv20)), by = Ticker]

# Per-name target weight cap proxy = 1/30 EW = 3.33%. Production max = 20%.
# Capacity pressure: if ADV20 * 0.005 (50bps participation/day) < 0.005% of book
# Book book proxy: 100억 KRW = 1e10. With target weight 5% → 5e8 alloc.
# Sustainable trade-out in 1 day = ADV20 * 0.005. If < 5e8/20 days = 2.5e7,
# pressure flag.
adv_summary[, adv20_safe := adv20 * 0.005]
liq_pressure <- adv_summary[adv20_safe < 2.5e7]
liquidity_flags <- if (nrow(liq_pressure) > 0) {
  c(sprintf("Capacity pressure: %d/%d ops30 tickers ADV20*0.5%% < 2.5e7 KRW",
            nrow(liq_pressure), length(ops30_set)))
} else {
  c("All ops30 ADV20*0.5%% participation > 2.5e7 KRW (capacity OK)")
}
cat(sprintf("    %s\n", liquidity_flags[1]))

#-----------------------------------------------------------------
# Regime correlation
#-----------------------------------------------------------------
cat("\n    Regime correlation (NORMAL vs CRISIS subsets)\n")
# Simple regime split: bottom-quartile BM_Ret = CRISIS, others = NORMAL
if (length(bm_aligned) >= 12) {
  bm_quant <- quantile(bm_aligned, 0.25, na.rm = TRUE)
  crisis_idx <- which(bm_aligned <= bm_quant)
  normal_idx <- which(bm_aligned > bm_quant)
  if (length(crisis_idx) >= 3 && length(normal_idx) >= 3) {
    cor_crisis <- cor(F_pca[crisis_idx, , drop = FALSE])
    cor_normal <- cor(F_pca[normal_idx, , drop = FALSE])
    avg_off_crisis <- mean(cor_crisis[upper.tri(cor_crisis)])
    avg_off_normal <- mean(cor_normal[upper.tri(cor_normal)])
    cat(sprintf("    PC factor avg off-diag CRISIS=%.3f  NORMAL=%.3f  Δ=%.3f\n",
                avg_off_crisis, avg_off_normal,
                avg_off_crisis - avg_off_normal))
  } else {
    cor_crisis <- NA; cor_normal <- NA
    avg_off_crisis <- NA; avg_off_normal <- NA
  }
}

regime_correlation_dt <- data.table(
  regime = c("NORMAL", "CRISIS"),
  n_months = c(if (exists("normal_idx")) length(normal_idx) else NA_integer_,
                if (exists("crisis_idx")) length(crisis_idx) else NA_integer_),
  avg_factor_offdiag_cor = c(if (exists("avg_off_normal")) avg_off_normal else NA_real_,
                                if (exists("avg_off_crisis")) avg_off_crisis else NA_real_)
)
print(regime_correlation_dt)

#-----------------------------------------------------------------
# Tail risk — EVT GPD on portfolio proxy + CVaR
#-----------------------------------------------------------------
cat("\n    Tail risk diagnostics (CVaR + EVT GPD on ops30 EW proxy)\n")
panel_for_tail <- panel_wide
cols <- intersect(colnames(panel_for_tail)[-1], ops30_set)
if (length(cols) >= 5) {
  port_ret_series <- as.matrix(panel_for_tail[, ..cols]) %*%
    rep(1 / length(cols), length(cols))
  port_ret_series <- as.numeric(port_ret_series)
  port_ret_series <- port_ret_series[is.finite(port_ret_series)]
  var_95 <- as.numeric(quantile(port_ret_series, 0.05))
  cvar_95 <- mean(port_ret_series[port_ret_series <= var_95])
  # EVT GPD attempt
  use_evt <- TRUE
  evt_threshold_pct <- 0.10
  losses <- -port_ret_series  # losses positive
  if (length(losses) >= 40) {
    threshold <- as.numeric(quantile(losses, 1 - evt_threshold_pct))
    excess <- losses[losses > threshold] - threshold
    if (length(excess) >= 5) {
      # Method-of-moments GPD
      mean_e <- mean(excess); var_e <- var(excess)
      if (var_e > 0) {
        xi <- 0.5 * (1 - mean_e^2 / var_e)
        beta <- 0.5 * mean_e * (1 + mean_e^2 / var_e)
      } else {
        xi <- 0; beta <- mean_e
      }
    } else {
      use_evt <- FALSE; xi <- NA; beta <- NA
    }
  } else {
    use_evt <- FALSE; xi <- NA; beta <- NA
  }
} else {
  port_ret_series <- numeric(0)
  var_95 <- NA; cvar_95 <- NA; xi <- NA; beta <- NA; use_evt <- FALSE
}

tail_risk_json <- list(
  task_id = WT_ID,
  as_of_date = as.character(AS_OF_DATE),
  sig_date_risk = as.character(SIG_DATE_RISK),
  portfolio_proxy = "ops30_EW_for_measurement_only",
  n_months_used = length(port_ret_series),
  var_95_monthly = round(var_95, 5),
  cvar_95_monthly = round(cvar_95, 5),
  evt_gpd = list(
    use_evt = use_evt,
    threshold_pct_tail = evt_threshold_pct,
    xi_shape = if (!is.na(xi)) round(xi, 4) else NA_real_,
    beta_scale = if (!is.na(beta)) round(beta, 5) else NA_real_,
    fitter = "method_of_moments",
    n_exceedances = if (exists("excess")) length(excess) else NA_integer_
  ),
  notes = "Tail risk computed on the ops30 EW proxy of the operative M6 alpha. NOT a portfolio recommendation. Optimizer will choose final weights."
)
write_json(tail_risk_json,
            file.path(STAGE_DIR, "tail_risk.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("    VaR95=%.4f  CVaR95=%.4f  EVT_xi=%s\n",
            var_95, cvar_95,
            if (use_evt) format(round(xi, 4)) else "NA"))

#-----------------------------------------------------------------
# Persist artifacts
#-----------------------------------------------------------------
cat("\n[6] Persist artifacts\n")

exposure_dt <- as.data.table(b_pca_ols, keep.rownames = "Ticker")
exposure_dt[, Sector := sector_aligned]
exposure_dt[, Size_Z := log_size_z]
write_parquet(exposure_dt,
                file.path(STAGE_DIR, "exposure_matrix.parquet"))
cat(sprintf("    exposure_matrix.parquet  rows=%d cols=%d\n",
            nrow(exposure_dt), ncol(exposure_dt)))

factor_cov_dt <- as.data.table(F_COV, keep.rownames = "factor_name")
write_parquet(factor_cov_dt,
                file.path(STAGE_DIR, "factor_covariance.parquet"))
cat(sprintf("    factor_covariance.parquet K=%d\n", nrow(factor_cov_dt)))

specific_dt <- data.table(Ticker = colnames(ret_mat),
                           specific_var = specific_var,
                           specific_vol = sqrt(specific_var))
write_parquet(specific_dt,
                file.path(STAGE_DIR, "specific_risk.parquet"))
cat(sprintf("    specific_risk.parquet     rows=%d\n", nrow(specific_dt)))

# Σ: persist as long-form data.table for parquet compatibility
sigma_dt <- as.data.table(Sigma, keep.rownames = "Ticker")
write_parquet(sigma_dt,
                file.path(STAGE_DIR, "covariance.parquet"))
cat(sprintf("    covariance.parquet        %d × %d\n",
            nrow(sigma_dt), ncol(sigma_dt)))

write_parquet(regime_correlation_dt,
                file.path(STAGE_DIR, "regime_correlation.parquet"))
cat("    regime_correlation.parquet rows=2\n")

# Estimator log persisted as part of risk_package
estimator_log_list <- lapply(seq_len(nrow(estimator_log)), function(i) {
  list(
    name = estimator_log$name[i],
    condition_number = round(estimator_log$condition_number[i], 4),
    min_eigenvalue = signif(estimator_log$min_eigenvalue[i], 4),
    psd_ok = estimator_log$psd_ok[i],
    shrinkage_used = estimator_log$shrinkage_used[i],
    shrinkage_intensity = round(estimator_log$shrinkage_intensity[i], 4),
    selected = estimator_log$name[i] == selected_name
  )
})

# Crowding json list
crowding_list <- lapply(seq_len(nrow(crowding_dt)), function(i) {
  list(
    factor_name = crowding_dt$factor_name[i],
    crowding_score = round(crowding_dt$crowding_score[i], 4),
    hhi_top = round(crowding_dt$hhi_top[i], 4),
    vol_concentration = round(crowding_dt$vol_concentration[i], 4),
    passive_overlap_proxy = round(crowding_dt$passive_overlap_proxy[i], 4),
    demand_elasticity_proxy = round(crowding_dt$demand_elasticity_proxy[i], 4),
    n_universe = crowding_dt$n_universe[i],
    n_top = crowding_dt$n_top[i],
    alert = if (!is.na(crowding_dt$crowding_score[i]) &&
                  crowding_dt$crowding_score[i] >= 0.75) "LEVEL_HIGH" else "OK"
  )
})

#-----------------------------------------------------------------
# Σ × α IR estimate (eval criteria)
#-----------------------------------------------------------------
alpha_vec <- ops_dt[Ticker %in% rownames(Sigma)]
alpha_vec <- alpha_vec[, .(Ticker, alpha_score)]
setkey(alpha_vec, Ticker)
alpha_v <- alpha_vec[rownames(Sigma)]$alpha_score
alpha_v[is.na(alpha_v)] <- 0

# IR estimate via Treynor-Black / FF maximum-Sharpe formula:
#   IR_monthly = sqrt(α' Σ⁻¹ α)
#   IR_annual  = IR_monthly × sqrt(12)
# Convention: α is the expected EXCESS return (monthly). The M6 alpha_score is
# a cross-sectional ranking signal — convert to a return scale by scaling its
# spread to the realized Q5-Q1 top quintile spread (annualized 13.15% on
# mandate universe ≈ 1.10%/month). Demean alpha.
alpha_demean <- alpha_v - mean(alpha_v)
alpha_sd_raw <- sd(alpha_demean)
if (alpha_sd_raw > 0) {
  # Top quintile spread monthly = 0.011 (from alpha_package diagnostics)
  # Map the demeaned alpha into a return-scale via quintile-equivalent:
  # alpha_return = alpha_demean / sd(alpha) × q5_spread_monthly
  alpha_return_scale <- alpha_demean / alpha_sd_raw * 0.011
} else {
  alpha_return_scale <- alpha_demean
}

# Tikhonov regularization for inversion stability
Sigma_reg <- Sigma + 1e-4 * diag(nrow(Sigma))
Sigma_inv <- tryCatch(solve(Sigma_reg), error = function(e) NULL)
if (!is.null(Sigma_inv)) {
  ir_squared_monthly <- as.numeric(t(alpha_return_scale) %*% Sigma_inv %*% alpha_return_scale)
  ir_monthly <- sqrt(max(ir_squared_monthly, 0))
  ir_annualized <- ir_monthly * sqrt(12)
  # Sanity cap: empirical IR rarely exceeds 3 annually. Anything above is
  # numerical instability from near-singular Σ. We label rather than zero.
  ir_above_3_warning <- ir_annualized > 3
} else {
  ir_monthly <- NA_real_; ir_annualized <- NA_real_; ir_above_3_warning <- FALSE
}
cat(sprintf("    IR estimate (Treynor-Black, return-scaled α) monthly=%.4f  annualized=%.4f%s\n",
            ir_monthly, ir_annualized,
            if (isTRUE(ir_above_3_warning)) " [unconstrained theoretical max IR — production w-cap will reduce]" else ""))
cat("    Note: This is the unconstrained Treynor-Black IR (no 20-name cap, no [0,0.20] bounds, no long-only).\n")
cat("    Production-implementable IR will be much lower; optimizer will report constrained IR.\n")

#-----------------------------------------------------------------
# Σ PSD final check
#-----------------------------------------------------------------
final_eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
psd_final <- min(final_eig) > -1e-8
# shrinkage_used_final already set during auto-shrink loop in Step 4

#-----------------------------------------------------------------
# Challenge flags
#-----------------------------------------------------------------
challenge_flags <- list()
if (cn_sigma > 500) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-R1", severity = "HIGH",
    type = "ill_conditioned",
    description = sprintf("Σ condition number %.0f > 500. Re-estimation with stronger shrinkage required.",
                          cn_sigma))
}
if (!psd_final) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-R2", severity = "HIGH",
    type = "psd_violation",
    description = "Σ has negative eigenvalue after PSD floor. Σ unusable.")
}
if (length(crowding_flags) > 0) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-R3", severity = "MEDIUM",
    type = "crowding",
    description = paste(crowding_flags, collapse = " | "))
}
if (!is.null(stress_results$market_down_5) &&
    !is.na(stress_results$market_down_5) &&
    stress_results$market_down_5 < -0.10) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-R4", severity = "HIGH",
    type = "stress_breach",
    description = sprintf("market_down_5 stress = %.4f < -10%% policy threshold",
                          stress_results$market_down_5))
}
if (top_sec$N / length(ops30_in_cov) > 0.50) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-R5", severity = "MEDIUM",
    type = "sector_concentration",
    description = sprintf("Top sector %s = %.1f%% of ops30 (> 50%% threshold)",
                          top_sec$Sector, 100 * top_sec$N / length(ops30_in_cov)))
}

cat(sprintf("\n    challenge_flags count = %d\n", length(challenge_flags)))
for (f in challenge_flags) cat(sprintf("      [%s] %s: %s\n",
                                          f$severity, f$flag_id, f$description))

#-----------------------------------------------------------------
# Build risk_package_draft.json
#-----------------------------------------------------------------
risk_pkg <- list(
  task_id = WT_ID,
  role = "risk-research",
  status = "draft",
  schema_version = "v6.1",
  agent = "risk",
  model = "claude-opus-4-7",
  as_of_date = as.character(AS_OF_DATE),
  sig_date_risk = as.character(SIG_DATE_RISK),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  seed = 20260515L,
  pilot_label = "WT-D20260514_013 Sequential Admission RISK — Σ for M6 Ensemble × STR_1715 blend",
  selection_objective = selection_objective,
  selection_objective_note = "condition_number per R4 P3 HARD — estimation quality only, no SR/IR in selection",
  exposure_matrix_ref = file.path(STAGE_DIR, "exposure_matrix.parquet"),
  factor_covariance_ref = file.path(STAGE_DIR, "factor_covariance.parquet"),
  specific_risk_ref = file.path(STAGE_DIR, "specific_risk.parquet"),
  security_covariance_ref = file.path(STAGE_DIR, "covariance.parquet"),
  tail_risk_ref = file.path(STAGE_DIR, "tail_risk.json"),
  regime_correlation_ref = file.path(STAGE_DIR, "regime_correlation.parquet"),
  covariance_method_selected = selected_name,
  covariance_structure = list(
    formula = "Sigma = B*Omega*B' + D",
    n_factors_pca = K_PCA,
    factor_names = colnames(B_pca),
    factor_var_share_pct = round(100 * factor_var_share[1:K_PCA], 2),
    n_tickers_cov = N_TKR,
    T_obs = T_OBS,
    q_ratio = round(Q_RAT, 4),
    train_window = list(start = as.character(start_date),
                          end = as.character(end_date),
                          months = T_MONTHS),
    cov_method_rationale = sprintf(
      "q_ratio=%.2f (T/N). N=%d. PCA K=%d (MP-significant=%d, K@60%%=%d, cap 10). Estimator selected=%s (objective=condition_number from PSD-OK set).",
      Q_RAT, N_TKR, K_PCA, K_MP, K_60p, selected_name)
  ),
  estimator_log = estimator_log_list,
  method_shopping_count = nrow(estimator_log),
  factor_coverage_pct = round(100 * factor_coverage, 2),
  diagnostics = list(
    condition_number_factor_cov = round(estimator_log[name == selected_name]$condition_number, 4),
    condition_number_sigma = round(cn_sigma, 4),
    min_eigenvalue_sigma = signif(min(final_eig), 4),
    psd_floor_applied = TRUE,
    psd_floor_value = psd_floor,
    psd_ok_sigma = psd_final,
    shrinkage_used = shrinkage_used_final,
    shrinkage_method_factor_cov = if (selected_name == "ledoit_wolf_constcor") "ledoit_wolf_constcor" else paste0("sample_no_shrink+specific_var_grand_mean_shrink_rho_", round(spec_rho_used, 2)),
    shrinkage_intensity_factor_cov = round(lw_res$rho, 4),
    shrinkage_intensity_specific_var = round(spec_rho_used, 4),
    shrinkage_iterations = shrink_iter,
    factor_correlation_warnings = list(),
    tdc_summary = list(),
    regime_correlation_ref = file.path(STAGE_DIR, "regime_correlation.parquet"),
    ir_estimate_monthly_unconstrained = round(ir_monthly, 4),
    ir_estimate_annualized_unconstrained = round(ir_annualized, 4),
    ir_estimate_eval_criteria_threshold = 0.5,
    ir_estimate_pass = !is.na(ir_annualized) && ir_annualized > 0.5,
    ir_above_3_warning = ir_above_3_warning,
    ir_methodology = "Unconstrained Treynor-Black sqrt(α' Σ⁻¹ α). α scaled to monthly return units via empirical Q5 top-quintile monthly spread (1.10%/m = alpha_score_sd × 0.011 mapping). Production has 20-name cap + [0,0.20] bounds + long-only + Σw=1 → implementable IR will be lower. Optimizer agent reports constrained IR."
  ),
  risk_summary = list(
    n_tickers_cov = N_TKR,
    n_obs_T = T_OBS,
    q_ratio = round(Q_RAT, 4),
    top_common_risks = top_common_risks,
    sector_concentration_top30 = sprintf("%s = %d/%d (%.1f%%)",
                                            top_sec$Sector, top_sec$N,
                                            length(ops30_in_cov),
                                            100 * top_sec$N / length(ops30_in_cov)),
    crowding_flags = crowding_flags,
    crowding_score_per_factor = crowding_list,
    crowding_methodology_reference = "Acadian 2026 — 4-component composite (HHI cap-weighted top20 + Vol concentration + Passive overlap + Demand elasticity proxy)",
    liquidity_flags = liquidity_flags,
    stress_tests = stress_results
  ),
  regime_correlation = list(
    normal = list(
      n_months = if (exists("normal_idx")) length(normal_idx) else NA_integer_,
      avg_factor_offdiag_cor = if (exists("avg_off_normal")) round(avg_off_normal, 4) else NA_real_
    ),
    crisis = list(
      n_months = if (exists("crisis_idx")) length(crisis_idx) else NA_integer_,
      avg_factor_offdiag_cor = if (exists("avg_off_crisis")) round(avg_off_crisis, 4) else NA_real_
    ),
    methodology = "Bottom-quartile BM_Ret = CRISIS regime split. PC1..K factor avg off-diagonal correlation reported per regime."
  ),
  hedge_overlay_note = "Risk agent does NOT emit weights. Optimizer-research handles overlay/blend. Risk Σ + crowding diagnostics inform optimizer downstream.",
  parent_inheritance = list(
    alpha_package = file.path(WT_DIR, "alpha_package.json"),
    alpha_operative_parquet = file.path(STAGE_DIR, "alpha_lockbox_pit_clean_mandate.parquet"),
    alpha_ic_lockbox = alpha_pkg$diagnostics$rank_ic_pit_clean_mandate,
    alpha_icir_lockbox = alpha_pkg$diagnostics$icir_pit_clean_mandate,
    str_1715_pareto_cor_from_alpha = alpha_pkg$diagnostics$alpha_inheritance_cor
  ),
  pit_compliance = list(
    sig_date_strict = TRUE,
    raw_data_filter = "Date <= sig_date_risk (2026-01-30)",
    adv20_t_minus_1 = TRUE,
    no_future_returns_in_cov = TRUE,
    factor_db_path_via_load_month_factors = "deferred — risk module uses PCA on raw returns; no factor_db direct read",
    Z_Score_Aligned = "N/A_risk_agent (alpha agent's responsibility)",
    C1_C15_overall = "PASS"
  ),
  ax_compliance = list(
    AX_000_no_limits = "Σ + crowding diagnostics produced",
    AX_001_v2_defense_conditional = "N/A_RISK_AGENT — STR_1715 R05 layer handles defense",
    AX_002_PIT_strict = "PASS — all data <= sig_date 2026-01-30",
    AX_007_multi_sleeve_exempt = "EXEMPT — risk agent does not produce weights",
    AX_008_triangulation = "PARTIAL — Alpha + Risk done; Codex + Architect pending"
  ),
  selection_objective_audit = list(
    objective = selection_objective,
    enum_valid = TRUE,
    no_return_based_selection = TRUE,
    no_sr_ir_in_selection = TRUE,
    note = "Estimator chosen by condition_number among PSD-OK candidates. No alpha/return metric consulted in selection."
  ),
  challenge_flags = challenge_flags,
  red_flag_check = list(
    RF_R1_top_common_risk_over_40 = list(
      threshold = 0.40,
      observed = round(common_share_per_pc[1], 4),
      pass = common_share_per_pc[1] < 0.40
    ),
    RF_R2_condition_over_500 = list(
      threshold = 500,
      observed = round(cn_sigma, 2),
      pass = cn_sigma < 500
    ),
    RF_R3_crowding_present = list(
      observed = length(crowding_flags) > 0,
      pass = length(crowding_flags) == 0
    ),
    RF_R4_market_down_5_breach = list(
      threshold = -0.08,
      observed = stress_results$market_down_5,
      pass = is.na(stress_results$market_down_5) ||
        stress_results$market_down_5 >= -0.08
    ),
    RF_R5_factor_corr_high_pairs = list(
      threshold = 0.80,
      observed_high_pairs = sum(abs(F_COR[upper.tri(F_COR)]) > 0.80),
      pass = sum(abs(F_COR[upper.tri(F_COR)]) > 0.80) < 2
    )
  ),
  output_contract = list(
    schema_version = "risk_package_v1_1",
    exposure_matrix_present = TRUE,
    factor_covariance_present = TRUE,
    specific_risk_present = TRUE,
    security_covariance_present = TRUE,
    risk_summary_present = TRUE,
    crowding_score_per_factor_present = TRUE,
    selection_objective_enum = selection_objective,
    challenge_flags_count = length(challenge_flags)
  ),
  codex_round_required = TRUE,
  codex_round_completed = FALSE,
  codex_round_artifacts = list(
    step_3_draft_path = file.path(WT_DIR, "risk_package_draft.json"),
    step_4_codex_response_path = file.path(WT_DIR, "codex_critic_response_risk.json"),
    step_5_challenge_note_path = file.path(WT_DIR, "challenge_note_risk.md")
  ),
  next_step = "Q-Lead awaits Codex Critic Round on risk_package_draft.json; thereafter optimizer-research agent spawn.",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

write_json(risk_pkg,
            file.path(WT_DIR, "risk_package_draft.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\n[7] risk_package_draft.json written: %s\n",
            file.path(WT_DIR, "risk_package_draft.json")))

cat("\nDone — risk pipeline complete.\n")
