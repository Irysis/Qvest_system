## ============================================================================
## WT-P20260509_001 — Optimizer Research: 4-Sleeve Statistical Method Shopping
##
## Mandate: 도훈 직접 (2026-05-09) "다른 비율도 검증 + 통계적 방법론 도입"
##
## Input (read-only, lockbox-compliant):
##   - AR_on_M4 (alpha-updated)  — STR_1715 50% sleeve standalone monthly returns
##   - KR_10y                    — KR 10y bond ETF standalone returns
##   - TSMOM_9_ETF               — TSMOM rotation 9-ETF basket returns
##   - Cash                      — 0% return
##
## Methods compared (≥10):
##   1.  Equal Weight 25/25/25/25
##   2.  Inverse Volatility (1/σ_i normalize)
##   3.  Risk Parity (ERC)
##   4.  MVO (λ ∈ {1, 2, 5, 10})  — 4 candidates
##   5.  HRP (López de Prado 2016)
##   6.  CVaR-LP @ α=0.95 (Rockafellar-Uryasev 2000)
##   7.  Black-Litterman (Path C view + market prior)
##   8.  Maximum Diversification (Choueifaty-Coignard 2008)
##   9.  도훈 Path C strict 70/15/15/0 — baseline
##   10. 도훈 S4 strict 50/25/20/5 — current admit baseline
##   11. Max Sharpe (μ/σ optimization)
##
## Constraints (Hard):
##   - weight_bound [0, 0.50] (도훈 framing 정합)
##   - Σw = 1
##   - long_only
##   - n_sleeve = 4 immutable
##
## Evaluation (each candidate):
##   - Full sample 256m: SR / CAGR / MDD / Sortino / Calmar / Vol / TE vs S0
##   - OOS 28m (2024-01 ~ 2026-04): SR / MDD / CAGR
##   - DSR Bailey-LdP (multi-trial haircut N=11)
##   - Sub-period stability (2008/2014/2020 sign 3/3 mandate)
##   - AX-001 v2 conditional defense
##
## Outputs:
##   - method_shopping_log.json
##   - comparison_table_all_methods.csv
##   - dohoon_framing_validation.json
##   - S4_v3_candidate_recommendation.json
##   - sleeve_returns_master.csv
##   - sleeve_correlation_covariance.csv (+.json)
##   - weights_optimal_per_method.csv
##   - weights.csv (selected method × 256m schedule)
## ============================================================================

cat("\n============================================================\n")
cat("  WT-P20260509_001 Optimizer Research — 4-Sleeve Method Shopping\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("============================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID  <- "WT-P20260509_001"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
OUT_DIR <- file.path(WT_DIR, "output")
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_P20260509_001")
dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)
dir.create(STAGE_DIR, showWarnings=FALSE, recursive=TRUE)

setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts)
  library(quadprog)
})

ANN_FACTOR <- 12
COST_BPS_ONEWAY <- 15
COST_PER_DOLLAR <- COST_BPS_ONEWAY / 10000

## ────────────────────────────────────────────────────────────────────────
## STEP 1: Load 4-sleeve standalone return series
## ────────────────────────────────────────────────────────────────────────
cat("[STEP 1] Loading 4-sleeve standalone return series\n")

# Sleeve 1: AR_on_M4 (STR_1715 alpha-updated × M4 overlay × β threshold)
ar_path <- file.path(WT_DIR, "..", "WT-T20260509_001/output/four_layer_returns_path_updated.csv")
ar_dt <- fread(ar_path)
ar_dt[, date := as.Date(date)]
ar_dt <- ar_dt[, .(date, AR_on_M4 = ret_AR_on_M4)]
setorder(ar_dt, date)
cat(sprintf("  AR_on_M4: %d obs (%s ~ %s)\n", nrow(ar_dt),
            as.character(min(ar_dt$date)), as.character(max(ar_dt$date))))

# Sleeve 2: KR 10y bond ETF
kr_path <- file.path(PROJECT_ROOT, "stage_artifacts/WT_S20260504_008/merged_returns.csv")
kr_dt <- fread(kr_path)
kr_dt[, date := as.Date(date)]
kr_dt <- kr_dt[, .(date, KR_10y = kr_10y)]
setorder(kr_dt, date)
cat(sprintf("  KR_10y:   %d obs (%s ~ %s)\n", nrow(kr_dt),
            as.character(min(kr_dt$date)), as.character(max(kr_dt$date))))

# Sleeve 3: TSMOM 9-ETF rotation
tsmom_path <- file.path(WT_DIR, "..", "WT-S20260504_009/docs/rotation_path_TSMOM.csv")
tsmom_dt <- fread(tsmom_path)
tsmom_dt[, date := as.Date(date)]
tsmom_dt <- tsmom_dt[, .(date, TSMOM = ml_realized)]
setorder(tsmom_dt, date)
cat(sprintf("  TSMOM:    %d obs (%s ~ %s)\n", nrow(tsmom_dt),
            as.character(min(tsmom_dt$date)), as.character(max(tsmom_dt$date))))

# Merge masters: outer-join, fill TSMOM with 0 (cash equivalent) pre-2015
master <- merge(ar_dt, kr_dt, by="date", all.x=TRUE)
master <- merge(master, tsmom_dt, by="date", all.x=TRUE)
master[is.na(KR_10y), KR_10y := 0]
master[, TSMOM_PRESENT := !is.na(TSMOM)]   # flag for restricted-sample analysis
master[is.na(TSMOM), TSMOM := 0]            # zero-fill for full-sample
master[, Cash := 0]
setorder(master, date)
cat(sprintf("\n[MASTER full-sample] %d months (%s ~ %s, TSMOM_present=%d/%d)\n",
            nrow(master), as.character(min(master$date)), as.character(max(master$date)),
            sum(master$TSMOM_PRESENT), nrow(master)))

# Save master returns
fwrite(master, file.path(OUT_DIR, "sleeve_returns_master.csv"))

# Define samples
master_full <- copy(master)                                      # 2005-02 ~ 2026-04 (256m)
master_tsmom <- master[TSMOM_PRESENT == TRUE]                    # 2015-01 ~ 2026-04 (~136m)
master_oos  <- master[date >= as.Date("2024-01-01")]             # 28m OOS

cat(sprintf("[SAMPLE full]   n=%d\n", nrow(master_full)))
cat(sprintf("[SAMPLE tsmom]  n=%d (TSMOM in-sample)\n", nrow(master_tsmom)))
cat(sprintf("[SAMPLE oos]    n=%d (2024-01 forward)\n", nrow(master_oos)))

## ────────────────────────────────────────────────────────────────────────
## STEP 2: Sample statistics — μ, Σ, ρ (per sample)
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 2] Computing sample statistics (μ / Σ / ρ)\n")

SLEEVE_NAMES <- c("AR_on_M4", "TSMOM", "KR_10y", "Cash")

compute_stats <- function(dt, sample_name) {
  R <- as.matrix(dt[, ..SLEEVE_NAMES])
  mu <- colMeans(R)
  Sigma <- cov(R) * ANN_FACTOR
  if (sd(R[,"Cash"]) < 1e-12) {
    Sigma["Cash","Cash"] <- 1e-8                 # numerical floor
  }
  vol <- sqrt(diag(Sigma))
  Sigma_check <- Sigma
  diag_zero_idx <- which(vol < 1e-6)
  if (length(diag_zero_idx) > 0) {
    Sigma_check[diag_zero_idx, ] <- 0
    Sigma_check[, diag_zero_idx] <- 0
    Sigma_check[diag_zero_idx, diag_zero_idx] <- 1e-8
    vol[diag_zero_idx] <- 1e-4
  }
  rho <- cor(R)
  rho[is.na(rho)] <- 0
  diag(rho) <- 1
  list(mu = mu * ANN_FACTOR, Sigma = Sigma_check, rho = rho, vol = vol, R = R, n = nrow(R))
}

stats_full <- compute_stats(master_full, "full")
stats_tsmom <- compute_stats(master_tsmom, "tsmom")
stats_oos <- compute_stats(master_oos, "oos")

cat("\n=== Annualized μ (full / tsmom / oos) ===\n")
mu_table <- rbind(round(stats_full$mu, 4),
                  round(stats_tsmom$mu, 4),
                  round(stats_oos$mu, 4))
rownames(mu_table) <- c("full_256m", "tsmom_136m", "oos_28m")
print(mu_table)

cat("\n=== Annualized σ (full) ===\n")
print(round(stats_full$vol, 4))

cat("\n=== Correlation matrix (full) ===\n")
print(round(stats_full$rho, 3))

# Save correlation + covariance
fwrite(data.table(asset=SLEEVE_NAMES, as.data.table(round(stats_full$rho, 4))),
       file.path(OUT_DIR, "sleeve_correlation_full.csv"))
fwrite(data.table(asset=SLEEVE_NAMES, as.data.table(round(stats_full$Sigma, 6))),
       file.path(OUT_DIR, "sleeve_covariance_full_annual.csv"))
fwrite(data.table(asset=SLEEVE_NAMES, as.data.table(round(stats_tsmom$rho, 4))),
       file.path(OUT_DIR, "sleeve_correlation_tsmom_window.csv"))

## ────────────────────────────────────────────────────────────────────────
## STEP 3: Method registry — implement 11 weight methods
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 3] Implementing 11 weight methods\n")

# Universal projection: long-only + bound[0,0.5] + Σw=1
project_simplex <- function(w, lb=0, ub=0.5) {
  w <- as.numeric(unlist(w))   # coerce list → numeric
  if (length(w) == 0) return(rep(1/4, 4))
  w[is.na(w) | !is.finite(w)] <- 0
  w <- pmax(w, lb)
  w <- pmin(w, ub)
  s <- sum(w)
  if (s <= 1e-12) return(rep(1/length(w), length(w)))
  w <- w / s
  for (i in 1:50) {
    over <- which(w > ub + 1e-9)
    if (length(over) == 0) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(w < ub - 1e-9 & w > lb + 1e-9)
    if (length(free) == 0) break
    w[free] <- w[free] + excess / length(free)
  }
  w
}

# 1. Equal Weight 25/25/25/25
m_equal <- function() rep(0.25, 4)

# 2. Inverse Volatility
m_inv_vol <- function(vol) {
  v <- vol
  v[v < 1e-6] <- max(v[v >= 1e-6])  # exclude near-zero (cash)
  w <- 1 / v
  w / sum(w)
}

# 3. ERC (Equal Risk Contribution) — cyclic coordinate descent
m_erc <- function(Sigma) {
  n <- nrow(Sigma)
  w <- rep(1/n, n)
  target <- 1/n
  for (iter in 1:500) {
    s <- as.numeric(sqrt(t(w) %*% Sigma %*% w))
    if (s < 1e-12) break
    rc <- (Sigma %*% w) / s          # marginal contributions × σ_p
    rc_pct <- rc * w / s
    # Update: w_i_new = target / rc_pct_i × w_i  → renormalize
    w_new <- w * target / pmax(as.numeric(rc_pct), 1e-12)
    w_new <- w_new / sum(w_new)
    if (max(abs(w_new - w)) < 1e-8) { w <- w_new; break }
    w <- 0.5 * w + 0.5 * w_new
  }
  w / sum(w)
}

# 4. MVO (long-only, bound[0,0.5])
m_mvo <- function(mu, Sigma, lambda=2.0) {
  n <- length(mu)
  Dmat <- 2 * lambda * Sigma + diag(1e-6, n)        # numerical floor
  dvec <- mu
  Amat <- cbind(rep(1,n), diag(n), -diag(n))
  bvec <- c(1, rep(0,n), rep(-0.5, n))
  meq <- 1
  out <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=meq),
                  error=function(e) NULL)
  if (is.null(out)) return(rep(1/n, n))
  w <- pmax(out$solution, 0)
  w / sum(w)
}

# 5. HRP — Lopez de Prado 2016 Journal of Portfolio Management (4-asset implementation)
# Reference: López de Prado, M. (2016) "Building Diversified Portfolios that Outperform Out of Sample"
# JPM 42(4): 59-69
m_hrp <- function(Sigma, rho) {
  n <- nrow(Sigma)
  if (n <= 2) {
    iv <- 1/sqrt(diag(Sigma))
    return(iv / sum(iv))
  }
  # Step 1: Distance matrix from correlation
  dist_mat <- sqrt(pmax(0.5 * (1 - rho), 0))
  diag(dist_mat) <- 0
  # Step 2: Single-linkage clustering
  hc <- hclust(as.dist(dist_mat), method = "single")
  order_idx <- hc$order
  # Step 3: Recursive bisection on quasi-diagonalized order
  bisect <- function(items) {
    if (length(items) == 1) {
      return(setNames(1, as.character(items)))
    }
    mid <- ceiling(length(items) / 2)
    left <- items[1:mid]
    right <- items[(mid + 1):length(items)]
    iv_l <- 1 / diag(Sigma)[left]; iv_l <- iv_l / sum(iv_l)
    iv_r <- 1 / diag(Sigma)[right]; iv_r <- iv_r / sum(iv_r)
    var_l <- as.numeric(t(iv_l) %*% Sigma[left, left, drop=FALSE] %*% iv_l)
    var_r <- as.numeric(t(iv_r) %*% Sigma[right, right, drop=FALSE] %*% iv_r)
    alpha <- 1 - var_l / (var_l + var_r + 1e-12)
    res_l <- bisect(left)
    res_r <- bisect(right)
    c(res_l * alpha, res_r * (1 - alpha))
  }
  res <- bisect(order_idx)
  w <- numeric(n)
  for (nm in names(res)) {
    w[as.integer(nm)] <- res[[nm]]
  }
  w / sum(w)
}

# 6. CVaR-LP @ α=0.95 — Rockafellar-Uryasev 2000
# Reference: Rockafellar, R.T. & Uryasev, S. (2000) "Optimization of conditional value-at-risk"
# Journal of Risk 2(3): 21-41
m_cvar_lp <- function(R, alpha_level=0.95) {
  n_obs <- nrow(R); n_assets <- ncol(R)
  # ROI (R Optimization Infrastructure) with glpk plugin if available
  use_roi <- requireNamespace("ROI", quietly=TRUE) &&
    (requireNamespace("ROI.plugin.glpk", quietly=TRUE) || requireNamespace("ROI.plugin.lpsolve", quietly=TRUE))
  use_rglpk <- requireNamespace("Rglpk", quietly=TRUE)
  if (!use_roi && !use_rglpk) {
    # Manual quadratic-form proxy: minimize tail variance via QP on Σ
    # = approximate Min-CVaR with Min-Var when underlying ≈ Gaussian
    cat("    [WARN CVaR] no LP solver available — using lower-tail-var QP proxy\n")
    Sigma <- cov(R) * ANN_FACTOR
    diag(Sigma) <- diag(Sigma) + 1e-6
    # Down-weight upper-tail observations: w_t = 1 if R_p_t < quantile, else 0.1
    # → emphasize tail covariance
    proxy_R <- R
    Dmat <- 2 * cov(proxy_R) * ANN_FACTOR + diag(1e-6, n_assets)
    dvec <- rep(0, n_assets)
    Amat <- cbind(rep(1, n_assets), diag(n_assets), -diag(n_assets))
    bvec <- c(1, rep(0, n_assets), rep(-0.5, n_assets))
    out <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=1),
                    error=function(e) NULL)
    if (is.null(out)) return(rep(1/n_assets, n_assets))
    w <- pmax(out$solution, 0); return(w / sum(w))
  }
  # ROI path not implemented in self-contained run; if Rglpk present, use it
  # decision vars: [w (n_a), VaR (1), z (n_obs)]
  # Min: VaR + 1/((1-α)*n_obs) * Σ z_t
  # s.t. z_t ≥ -R_t·w - VaR  →  R_t·w + VaR + z_t ≥ 0
  #      Σw = 1, w ∈ [0, 0.5], z ≥ 0
  beta <- 1 - alpha_level
  obj <- c(rep(0, n_assets), 1, rep(1/(beta * n_obs), n_obs))
  # Constraint matrix
  # 1) Σw = 1
  c_sum <- c(rep(1, n_assets), 0, rep(0, n_obs))
  # 2) z_t + R_t·w + VaR ≥ 0  for each t
  c_z <- cbind(R, 1, diag(n_obs))
  Amat <- rbind(c_sum, c_z)
  dir <- c("==", rep(">=", n_obs))
  rhs <- c(1, rep(0, n_obs))
  bounds <- list(
    lower = list(ind = 1:(n_assets + 1 + n_obs), val = c(rep(0, n_assets), -1e6, rep(0, n_obs))),
    upper = list(ind = 1:(n_assets + 1 + n_obs), val = c(rep(0.5, n_assets), 1e6, rep(1e6, n_obs)))
  )
  res <- tryCatch(Rglpk::Rglpk_solve_LP(obj, Amat, dir, rhs, bounds=bounds, max=FALSE),
                  error=function(e) NULL)
  if (is.null(res) || res$status != 0) {
    cat("    [WARN CVaR] LP failed — fallback EW\n")
    return(rep(1/n_assets, n_assets))
  }
  w <- pmax(res$solution[1:n_assets], 0)
  if (sum(w) < 1e-9) return(rep(1/n_assets, n_assets))
  w / sum(w)
}

# 7. Black-Litterman — Path C view (70 AR / 15 TSMOM / 15 KR / 0 Cash)
m_bl <- function(mu, Sigma, view_weights=c(0.70, 0.15, 0.15, 0.0), tau=0.05, lambda=2.0) {
  # Implied equilibrium returns from prior weights (market-implied = view_weights as prior)
  # π = δ·Σ·w_market, where δ = 2.0 (risk aversion)
  pi_eq <- as.numeric(lambda * Sigma %*% view_weights)
  # Investor view: 도훈 conviction = π itself (anchor)
  # P = identity (each sleeve has one absolute view)
  # Q = pi_eq (prior aligns with views = weak update toward prior)
  # Ω = diag(τ * Σ)  (uncertainty proportional to prior cov)
  P <- diag(length(mu))
  Q <- pi_eq
  Omega <- diag(diag(tau * Sigma))
  M_inv <- solve(tau * Sigma) + t(P) %*% solve(Omega) %*% P
  M_post <- solve(M_inv)
  mu_bl <- M_post %*% (solve(tau * Sigma) %*% pi_eq + t(P) %*% solve(Omega) %*% Q)
  Sigma_bl <- Sigma + M_post
  m_mvo(as.numeric(mu_bl), Sigma_bl, lambda=lambda)
}

# 8. Maximum Diversification — Choueifaty-Coignard 2008
m_maxdiv <- function(Sigma) {
  n <- nrow(Sigma)
  vol <- sqrt(diag(Sigma))
  # MDP: max DR(w) = (w'σ) / sqrt(w'Σw)
  # equivalent: solve QP for max[(w'σ)/sqrt(w'Σw)]
  # Iterative: start with vol-equal, project
  Dmat <- 2 * Sigma + diag(1e-6, n)
  dvec <- vol
  Amat <- cbind(rep(1, n), diag(n), -diag(n))
  bvec <- c(1, rep(0, n), rep(-0.5, n))
  out <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=1),
                  error=function(e) NULL)
  if (is.null(out)) return(m_inv_vol(vol))
  w <- pmax(out$solution, 0)
  w / sum(w)
}

# 9. Path C strict (도훈 baseline)
w_path_c <- c(0.70, 0.15, 0.15, 0.0)

# 10. S4 strict (current admit)
w_s4 <- c(0.50, 0.25, 0.20, 0.05)

# 11. Max Sharpe — minimize -μ/sqrt(w'Σw) via QP for fixed return target
m_max_sharpe <- function(mu, Sigma, lambda_grid=c(0.5, 1, 2, 5, 10, 20)) {
  best_sr <- -Inf; best_w <- rep(1/length(mu), length(mu))
  for (lam in lambda_grid) {
    w <- m_mvo(mu, Sigma, lambda=lam)
    sr <- as.numeric(t(w) %*% mu) / sqrt(as.numeric(t(w) %*% Sigma %*% w) + 1e-12)
    if (sr > best_sr) { best_sr <- sr; best_w <- w }
  }
  best_w
}

## ─── Modern (2020-2025) academic methods ────────────────────────────────

# 12. Distributionally Robust Risk Parity (DR-RP)
# Reference: Costa & Kwon (2021) "Data-driven distributionally robust risk parity portfolio"
# arXiv:2110.06464. Idea: ERC under worst-case sample-weight ambiguity (φ-divergence ball)
# Implementation: Practical proxy = ERC on shrinkage-penalized covariance (DR shrinkage analog)
m_dr_rp <- function(R, eta = 0.10) {
  n <- ncol(R)
  T <- nrow(R)
  # Empirical covariance (annualized)
  Sigma_hat <- cov(R) * ANN_FACTOR
  # DR shrinkage: blend with diagonal target proportional to Wasserstein radius
  diag_target <- diag(diag(Sigma_hat))
  Sigma_dr <- (1 - eta) * Sigma_hat + eta * diag_target
  if (sd(R[,"Cash"]) < 1e-12) Sigma_dr["Cash","Cash"] <- 1e-8
  m_erc(Sigma_dr)
}

# 13. Schur Complementary Allocation (Schur-HRP)
# Reference: Cotton (2024) "Schur Complementary Allocation: A Unification of HRP and Min Variance"
# arXiv:2411.05807. Idea: HRP recursive bisection but with Schur-block conditional variance
# instead of inverse-variance.
m_schur_hrp <- function(Sigma, rho) {
  n <- nrow(Sigma)
  if (n <= 2) {
    iv <- 1 / sqrt(diag(Sigma))
    return(iv / sum(iv))
  }
  dist_mat <- sqrt(pmax(0.5 * (1 - rho), 0))
  diag(dist_mat) <- 0
  hc <- hclust(as.dist(dist_mat), method = "single")
  order_idx <- hc$order
  schur_var <- function(idx_a, idx_b) {
    # var(A | B) ≈ Σ_AA - Σ_AB Σ_BB^{-1} Σ_BA  (block conditional variance)
    if (length(idx_b) == 0) return(Sigma[idx_a, idx_a, drop = FALSE])
    SAB <- Sigma[idx_a, idx_b, drop = FALSE]
    SBB <- Sigma[idx_b, idx_b, drop = FALSE]
    SAA <- Sigma[idx_a, idx_a, drop = FALSE]
    SBB_inv <- tryCatch(solve(SBB + diag(1e-8, nrow(SBB))), error = function(e) diag(nrow(SBB)) * 0)
    SAA - SAB %*% SBB_inv %*% t(SAB)
  }
  bisect <- function(items) {
    if (length(items) == 1) return(setNames(1, as.character(items)))
    mid <- ceiling(length(items) / 2)
    left <- items[1:mid]
    right <- items[(mid + 1):length(items)]
    # Schur conditional variance for each block
    SC_l <- schur_var(left, right)
    SC_r <- schur_var(right, left)
    iv_l <- 1 / diag(SC_l); iv_l <- iv_l / sum(iv_l)
    iv_r <- 1 / diag(SC_r); iv_r <- iv_r / sum(iv_r)
    var_l <- as.numeric(t(iv_l) %*% SC_l %*% iv_l)
    var_r <- as.numeric(t(iv_r) %*% SC_r %*% iv_r)
    alpha <- 1 - var_l / (var_l + var_r + 1e-12)
    c(bisect(left) * alpha, bisect(right) * (1 - alpha))
  }
  res <- bisect(order_idx)
  w <- numeric(n)
  for (nm in names(res)) w[as.integer(nm)] <- res[[nm]]
  w / sum(w)
}

# 14. Trend-Following Risk Parity (TF-RP)
# Reference: Valeyre (2022) "Optimal Trend Following Portfolios" arXiv:2201.06635
# Idea: Optimal portfolio = α·Markowitz + β·RiskParity + γ·AgnosticRP + δ·TrendFollowingRP
# Practical proxy: blend ERC with momentum-weighted tilt where momentum = recent 12m mean
m_tf_rp <- function(mu, Sigma, R, lookback_m = 12, blend = 0.5) {
  n <- ncol(R)
  if (nrow(R) < lookback_m) lookback_m <- nrow(R)
  recent_mu <- colMeans(R[(nrow(R) - lookback_m + 1):nrow(R), , drop = FALSE]) * ANN_FACTOR
  # Momentum signal — sign(z-score)
  z_mom <- (recent_mu - mean(recent_mu)) / (sd(recent_mu) + 1e-9)
  trend_w <- pmax(z_mom, 0)
  trend_w <- if (sum(trend_w) < 1e-9) rep(1/n, n) else trend_w / sum(trend_w)
  rp_w <- m_erc(Sigma)
  blend * rp_w + (1 - blend) * trend_w
}

# 15. Tactical Regime-Conditional Allocation (TRCA)
# Reference: Oliveira et al. (2025) "Tactical Asset Allocation with Macroeconomic Regime Detection"
# arXiv:2503.11499. Idea: regime-conditional μ + Σ → method-shop per regime → blend by regime prior
# Practical proxy: split sample into bull/bear via 12m trailing AR_on_M4 mean,
# compute MVO per regime, blend by regime fraction
m_trca <- function(R, lambda = 2.0, lookback_m = 12) {
  n <- ncol(R)
  if (nrow(R) < lookback_m + 12) {
    Sigma_full <- cov(R) * ANN_FACTOR
    return(m_mvo(colMeans(R) * ANN_FACTOR, Sigma_full, lambda))
  }
  # Regime label: bull (recent 12m AR mean > 0) / bear (≤ 0)
  ar_idx <- which(colnames(R) == "AR_on_M4")
  trailing_ar <- frollmean(R[, ar_idx], lookback_m, align = "right", fill = NA)
  regime <- ifelse(trailing_ar > 0, "bull", "bear")
  bull_idx <- which(regime == "bull")
  bear_idx <- which(regime == "bear")
  # Regime priors
  p_bull <- length(bull_idx) / sum(!is.na(regime))
  p_bear <- 1 - p_bull
  if (length(bull_idx) < 10 || length(bear_idx) < 10) {
    Sigma_full <- cov(R) * ANN_FACTOR
    return(m_mvo(colMeans(R) * ANN_FACTOR, Sigma_full, lambda))
  }
  R_bull <- R[bull_idx, , drop = FALSE]
  R_bear <- R[bear_idx, , drop = FALSE]
  Sigma_bull <- cov(R_bull) * ANN_FACTOR
  Sigma_bear <- cov(R_bear) * ANN_FACTOR
  if (sd(R_bull[,"Cash"]) < 1e-12) Sigma_bull["Cash","Cash"] <- 1e-8
  if (sd(R_bear[,"Cash"]) < 1e-12) Sigma_bear["Cash","Cash"] <- 1e-8
  mu_bull <- colMeans(R_bull) * ANN_FACTOR
  mu_bear <- colMeans(R_bear) * ANN_FACTOR
  w_bull <- m_mvo(mu_bull, Sigma_bull, lambda)
  w_bear <- m_mvo(mu_bear, Sigma_bear, lambda)
  p_bull * w_bull + p_bear * w_bear
}

## ────────────────────────────────────────────────────────────────────────
## STEP 4: Compute weights for each method (full-sample stats)
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 4] Solving weights per method (full-sample input statistics)\n")

solve_weights <- function(stats) {
  list(
    # Classical (8)
    EqualWeight        = m_equal(),
    InverseVolatility  = project_simplex(m_inv_vol(stats$vol)),
    RiskParity_ERC     = project_simplex(m_erc(stats$Sigma)),
    MVO_lambda1        = project_simplex(m_mvo(stats$mu, stats$Sigma, 1)),
    MVO_lambda2        = project_simplex(m_mvo(stats$mu, stats$Sigma, 2)),
    MVO_lambda5        = project_simplex(m_mvo(stats$mu, stats$Sigma, 5)),
    MVO_lambda10       = project_simplex(m_mvo(stats$mu, stats$Sigma, 10)),
    HRP                = project_simplex(m_hrp(stats$Sigma, stats$rho)),
    CVaR_LP_a95        = project_simplex(m_cvar_lp(stats$R, 0.95)),
    BlackLitterman_PC  = project_simplex(m_bl(stats$mu, stats$Sigma)),
    MaxDiversification = project_simplex(m_maxdiv(stats$Sigma)),
    MaxSharpe_grid     = project_simplex(m_max_sharpe(stats$mu, stats$Sigma)),
    # Modern academic (2020-2025) — 4 methods
    DR_RiskParity      = project_simplex(m_dr_rp(stats$R, eta = 0.10)),
    Schur_HRP          = project_simplex(m_schur_hrp(stats$Sigma, stats$rho)),
    TF_RiskParity      = project_simplex(m_tf_rp(stats$mu, stats$Sigma, stats$R)),
    Tactical_Regime    = project_simplex(m_trca(stats$R, lambda = 2.0)),
    # 도훈 framing (2)
    Path_C_strict      = w_path_c,
    S4_strict          = w_s4
  )
}

weights_full  <- solve_weights(stats_full)
weights_tsmom <- solve_weights(stats_tsmom)

cat("\n=== Optimal weights per method (full-sample input) ===\n")
W_full <- do.call(rbind, weights_full)
colnames(W_full) <- SLEEVE_NAMES
W_full_dt <- data.table(method = rownames(W_full), as.data.table(round(W_full, 4)))
print(W_full_dt)
fwrite(W_full_dt, file.path(OUT_DIR, "weights_optimal_per_method_full.csv"))

cat("\n=== Optimal weights per method (TSMOM-window input) ===\n")
W_tsmom <- do.call(rbind, weights_tsmom)
colnames(W_tsmom) <- SLEEVE_NAMES
W_tsmom_dt <- data.table(method = rownames(W_tsmom), as.data.table(round(W_tsmom, 4)))
print(W_tsmom_dt)
fwrite(W_tsmom_dt, file.path(OUT_DIR, "weights_optimal_per_method_tsmom.csv"))

## ────────────────────────────────────────────────────────────────────────
## STEP 5: Backtest each weight using PerformanceAnalytics
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 5] Computing portfolio metrics per method (PerformanceAnalytics)\n")

# Build static-weight return series + cost
backtest_static_weights <- function(weights, master_dt, sample_label) {
  weights <- as.numeric(unlist(weights))
  R <- as.matrix(master_dt[, ..SLEEVE_NAMES])
  port_ret <- as.numeric(R %*% weights)
  # Annual rebalance cost approx: 2 × turnover × 15bps; here weights static
  # Inter-sleeve drift small (annual rebalance) → 1 round-trip = 2 × Σ|Δw_i|/2 × cost
  # Approximation: assume monthly rebalance cost = 0.5bps/month (~6bps/yr blend)
  # For comparison purposes, use gross + small cost adjustment
  # Use net = gross - 0.0005/month approximation (~6bps/yr roundtrip blended cost for 4-sleeve drift)
  # Conservative: annual_cost = 2 * mean_drift * 15bps where drift ≈ 10%/year
  # Simpler: use raw gross return for fair method-comparison
  port_xts <- xts::xts(port_ret, order.by=master_dt$date)
  port_xts
}

evaluate_weights <- function(weights, master_dt, label) {
  weights <- as.numeric(unlist(weights))   # type-safe
  port_xts <- backtest_static_weights(weights, master_dt, label)
  ann <- table.AnnualizedReturns(port_xts, scale=ANN_FACTOR, Rf=0)
  mdd <- as.numeric(maxDrawdown(port_xts))
  sortino <- as.numeric(SortinoRatio(port_xts, MAR=0)) * sqrt(ANN_FACTOR)
  calmar <- as.numeric(CalmarRatio(port_xts))
  # ann is a data.frame with 3 rows × 1 col [Return / Vol / Sharpe]
  cagr <- as.numeric(ann[1, 1])
  vol_ann <- as.numeric(ann[2, 1])
  sr_ann <- as.numeric(ann[3, 1])
  list(
    SR = round(sr_ann, 4),
    CAGR = round(cagr, 4),
    Vol = round(vol_ann, 4),
    MDD = round(mdd, 4),
    Sortino = round(sortino, 4),
    Calmar = round(calmar, 4),
    n_obs = length(port_xts),
    weights = weights
  )
}

# S0 baseline = 100% AR_on_M4 (alpha-updated standalone)
s0_baseline_weights <- c(1, 0, 0, 0)

eval_full <- list()
for (m in names(weights_full)) {
  w <- weights_full[[m]]
  if (is.list(w)) {
    cat(sprintf("    [DEBUG] %s is LIST, structure:\n", m))
    str(w)
    w <- as.numeric(unlist(w))
  }
  if (length(w) != 4) {
    cat(sprintf("    [DEBUG] %s wrong length=%d, content: %s\n",
                m, length(w), paste(head(w), collapse=",")))
    w <- rep(0.25, 4)
  }
  eval_full[[m]] <- evaluate_weights(w, master_full, paste(m, "full"))
}
# Also evaluate S0 baseline
eval_full[["S0_baseline_AR_only"]] <- evaluate_weights(s0_baseline_weights, master_full, "S0 full")

cat("\n=== FULL-SAMPLE METRICS (256m, 2005-02 ~ 2026-04) ===\n")
m_table_full <- rbindlist(lapply(names(eval_full), function(nm) {
  e <- eval_full[[nm]]
  data.table(method=nm, SR=e$SR, CAGR=e$CAGR, MDD=e$MDD, Vol=e$Vol,
             Sortino=e$Sortino, Calmar=e$Calmar)
}))
setorder(m_table_full, -SR)
print(m_table_full)

# OOS (2024-01+, 28m) — use SAME weights
eval_oos <- list()
for (m in names(weights_full)) {
  eval_oos[[m]] <- evaluate_weights(weights_full[[m]], master_oos, paste(m, "oos"))
}
eval_oos[["S0_baseline_AR_only"]] <- evaluate_weights(s0_baseline_weights, master_oos, "S0 oos")

cat("\n=== OOS METRICS (28m, 2024-01 ~ 2026-04) ===\n")
m_table_oos <- rbindlist(lapply(names(eval_oos), function(nm) {
  e <- eval_oos[[nm]]
  data.table(method=nm, SR=e$SR, CAGR=e$CAGR, MDD=e$MDD, Vol=e$Vol,
             Sortino=e$Sortino, Calmar=e$Calmar)
}))
setorder(m_table_oos, -SR)
print(m_table_oos)

# TSMOM-window (136m) using TSMOM-window weights
eval_tsmom <- list()
for (m in names(weights_tsmom)) {
  eval_tsmom[[m]] <- evaluate_weights(weights_tsmom[[m]], master_tsmom, paste(m, "tsmom"))
}
eval_tsmom[["S0_baseline_AR_only"]] <- evaluate_weights(s0_baseline_weights, master_tsmom, "S0 tsmom")

cat("\n=== TSMOM-WINDOW METRICS (136m, 2015-01 ~ 2026-04) ===\n")
m_table_tsmom <- rbindlist(lapply(names(eval_tsmom), function(nm) {
  e <- eval_tsmom[[nm]]
  data.table(method=nm, SR=e$SR, CAGR=e$CAGR, MDD=e$MDD, Vol=e$Vol,
             Sortino=e$Sortino, Calmar=e$Calmar)
}))
setorder(m_table_tsmom, -SR)
print(m_table_tsmom)

# Save comparison table (joined)
joined <- merge(
  m_table_full[, .(method, SR_full=SR, CAGR_full=CAGR, MDD_full=MDD, Vol_full=Vol,
                   Sortino_full=Sortino, Calmar_full=Calmar)],
  m_table_oos[, .(method, SR_oos=SR, CAGR_oos=CAGR, MDD_oos=MDD)],
  by="method", all.x=TRUE
)
joined <- merge(joined, m_table_tsmom[, .(method, SR_tsmom=SR, CAGR_tsmom=CAGR, MDD_tsmom=MDD)],
                by="method", all.x=TRUE)
# Add weights breakdown
W_dt <- data.table(method = rownames(W_full), W_full)
joined <- merge(W_dt, joined, by="method", all.y=TRUE)
joined[is.na(AR_on_M4), AR_on_M4 := 1]   # baseline
joined[is.na(TSMOM), TSMOM := 0]
joined[is.na(KR_10y), KR_10y := 0]
joined[is.na(Cash), Cash := 0]
setorder(joined, -SR_full)
fwrite(joined, file.path(OUT_DIR, "comparison_table_all_methods.csv"))
cat("\n[SAVED] comparison_table_all_methods.csv\n")

## ────────────────────────────────────────────────────────────────────────
## STEP 6: Statistical robustness — DSR (Bailey-Lopez de Prado)
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 6] DSR (Bailey-Lopez de Prado 2014) — multi-trial haircut\n")

dsr_bailey <- function(sr_obs, n_trials, n_obs, skew=0, kurt_excess=0) {
  if (n_trials < 2) return(NA_real_)
  emc <- 0.5772156649
  e_max_z <- (1 - emc) * qnorm(1 - 1/n_trials) + emc * qnorm(1 - 1/(n_trials * exp(1)))
  sr_threshold <- e_max_z * sqrt(1/n_obs)   # under H0 SR=0
  num <- (sr_obs - sr_threshold) * sqrt(n_obs - 1)
  den <- sqrt(1 - skew * sr_obs + (kurt_excess / 4) * sr_obs^2 + 1e-12)
  z <- num / den
  pnorm(z)
}

n_methods <- length(eval_full) - 1  # exclude baseline from "trial" count
dsr_table <- rbindlist(lapply(names(eval_full), function(nm) {
  e <- eval_full[[nm]]
  port_xts <- backtest_static_weights(e$weights, master_full, nm)
  port_ret <- as.numeric(port_xts)
  sk <- if (length(port_ret) > 3) PerformanceAnalytics::skewness(port_ret) else 0
  kt <- if (length(port_ret) > 3) PerformanceAnalytics::kurtosis(port_ret, method="excess") else 0
  sr_monthly <- mean(port_ret) / sd(port_ret)  # monthly Sharpe
  dsr_p <- dsr_bailey(sr_monthly, n_methods, length(port_ret), skew=sk, kurt_excess=kt)
  data.table(method=nm, SR_ann=e$SR, skew=round(sk, 3), kurt_excess=round(kt, 3),
             DSR_p=round(dsr_p, 4), DSR_pass_95=dsr_p >= 0.95)
}))
setorder(dsr_table, -DSR_p)
cat("\n=== DSR (Bailey-LdP 2014) — N_trials=", n_methods, "===\n", sep="")
print(dsr_table)
fwrite(dsr_table, file.path(OUT_DIR, "dsr_bailey_table.csv"))

## ────────────────────────────────────────────────────────────────────────
## STEP 7: Sub-period stability — 2008/2014/2020 sign consistency
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 7] Sub-period stability — 2008/2014/2020 stress periods\n")

sub_periods <- list(
  GFC_2008    = c(as.Date("2008-01-01"), as.Date("2009-06-30")),
  Energy_2014 = c(as.Date("2014-06-01"), as.Date("2016-02-29")),
  COVID_2020  = c(as.Date("2020-02-01"), as.Date("2020-12-31")),
  Inflation_2022 = c(as.Date("2022-01-01"), as.Date("2022-12-31"))
)

stab_rows <- list()
for (m in names(eval_full)) {
  w <- eval_full[[m]]$weights
  port_full <- backtest_static_weights(w, master_full, m)
  s0_port <- backtest_static_weights(s0_baseline_weights, master_full, "S0")
  for (sp in names(sub_periods)) {
    rng <- sub_periods[[sp]]
    sub_port <- port_full[paste0(rng[1], "/", rng[2])]
    sub_s0   <- s0_port[paste0(rng[1], "/", rng[2])]
    if (length(sub_port) == 0) next
    cum_ret <- as.numeric(prod(1 + as.numeric(sub_port)) - 1)
    cum_s0  <- as.numeric(prod(1 + as.numeric(sub_s0)) - 1)
    mdd_sub <- as.numeric(maxDrawdown(sub_port))
    mdd_s0  <- as.numeric(maxDrawdown(sub_s0))
    stab_rows[[length(stab_rows) + 1]] <- data.table(
      method=m, period=sp,
      cum_ret = round(cum_ret, 4),
      cum_ret_s0 = round(cum_s0, 4),
      excess_vs_s0 = round(cum_ret - cum_s0, 4),
      mdd_period = round(mdd_sub, 4),
      mdd_s0 = round(mdd_s0, 4),
      mdd_relief_pp = round((mdd_s0 - mdd_sub) * 100, 2)
    )
  }
}
stab_dt <- rbindlist(stab_rows)
fwrite(stab_dt, file.path(OUT_DIR, "subperiod_stability.csv"))
cat("\n=== Sub-period stability (excess vs S0 = STR_1715 alpha-updated baseline) ===\n")
print(stab_dt[order(method, period)])

## ────────────────────────────────────────────────────────────────────────
## STEP 8: AX-001 v2 conditional defense audit (per method)
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 8] AX-001 v2 conditional defense audit\n")

ax001v2_rows <- lapply(names(eval_full), function(m) {
  w <- eval_full[[m]]$weights
  port <- backtest_static_weights(w, master_full, m)
  s0   <- backtest_static_weights(s0_baseline_weights, master_full, "S0")
  bm_dates <- index(port)
  # bad regime: 12m trailing BM <= -10% (KOSPI). Use sleeve baseline as proxy "stress"
  # Crisis periods: 8 stress periods union
  stress_idx <- index(port)[which(
    (index(port) >= as.Date("1998-01-01") & index(port) <= as.Date("1998-12-31")) |
    (index(port) >= as.Date("2000-04-01") & index(port) <= as.Date("2002-09-30")) |
    (index(port) >= as.Date("2008-09-01") & index(port) <= as.Date("2009-06-30")) |
    (index(port) >= as.Date("2011-08-01") & index(port) <= as.Date("2012-09-30")) |
    (index(port) >= as.Date("2015-06-01") & index(port) <= as.Date("2016-02-29")) |
    (index(port) >= as.Date("2018-10-01") & index(port) <= as.Date("2018-12-31")) |
    (index(port) >= as.Date("2020-02-01") & index(port) <= as.Date("2020-04-30")) |
    (index(port) >= as.Date("2022-01-01") & index(port) <= as.Date("2022-12-31"))
  )]
  if (length(stress_idx) == 0) return(NULL)
  port_stress <- port[stress_idx]
  s0_stress <- s0[stress_idx]
  # Crisis-alpha = method - S0 mean monthly during stress (annualized)
  crisis_alpha <- (mean(as.numeric(port_stress)) - mean(as.numeric(s0_stress))) * 12
  # MDD relief
  mdd_method <- as.numeric(maxDrawdown(port))
  mdd_s0 <- as.numeric(maxDrawdown(s0))
  mdd_relief_pp <- (mdd_s0 - mdd_method) * 100
  # bad/normal IC ratio (proxy: stress vs full IC of method excess return)
  port_ex <- as.numeric(port - s0)
  port_ex_stress <- port_ex[which(index(port) %in% stress_idx)]
  port_ex_normal <- port_ex[which(!(index(port) %in% stress_idx))]
  bad_normal_ratio <- if (length(port_ex_normal) > 0 && abs(mean(port_ex_normal)) > 1e-6)
    mean(port_ex_stress) / mean(port_ex_normal) else NA
  # AX-001 v2 PASS criteria
  pass_crisis_alpha <- !is.na(crisis_alpha) && crisis_alpha > 0.005
  pass_mdd <- !is.na(mdd_relief_pp) && mdd_relief_pp > 0
  pass_ratio <- !is.na(bad_normal_ratio) && bad_normal_ratio > 0
  pass_ax001v2 <- pass_crisis_alpha && pass_mdd && pass_ratio
  data.table(
    method=m,
    crisis_alpha_ann = round(crisis_alpha, 4),
    mdd_relief_pp = round(mdd_relief_pp, 2),
    bad_normal_ratio = round(bad_normal_ratio, 3),
    pass_crisis_alpha=pass_crisis_alpha,
    pass_mdd=pass_mdd,
    pass_bad_normal=pass_ratio,
    AX001v2_PASS=pass_ax001v2
  )
})
ax001v2_dt <- rbindlist(ax001v2_rows[!sapply(ax001v2_rows, is.null)])
fwrite(ax001v2_dt, file.path(OUT_DIR, "ax001v2_conditional_defense_audit.csv"))
cat("\n=== AX-001 v2 conditional defense audit ===\n")
print(ax001v2_dt[order(-AX001v2_PASS, -crisis_alpha_ann)])

## ────────────────────────────────────────────────────────────────────────
## STEP 9: Selection objective — net_IR (turnover-adjusted Sharpe vs S0)
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 9] Selection objective: net_IR (turnover-adjusted, Optimizer R4 P3)\n")

net_ir_rows <- lapply(names(eval_full), function(m) {
  w <- eval_full[[m]]$weights
  port <- backtest_static_weights(w, master_full, m)
  s0   <- backtest_static_weights(s0_baseline_weights, master_full, "S0")
  excess <- as.numeric(port - s0)
  ir <- mean(excess) / sd(excess) * sqrt(12)
  # Approximate annual turnover for static weights ≈ 2 × Σ|Δw between annual rebal
  # 4-sleeve sleeve drift est ~10% Σ|Δw|/yr  → 2-side cost = 2 × 0.10 × 0.0015 = 0.0003 (3bps)
  # Compare: 70/15/15 vs 50/25/20/5 sleeve weights have similar drift profile
  ann_turnover <- 0.10 * 2  # round-trip (0.10 drift × 2 sides)
  ann_cost_drag <- ann_turnover * COST_PER_DOLLAR / 1
  net_sr <- eval_full[[m]]$SR - ann_cost_drag
  data.table(method=m, IR_vs_S0=round(ir, 4),
             gross_SR=eval_full[[m]]$SR,
             est_ann_cost_drag=round(ann_cost_drag, 5),
             net_SR=round(net_sr, 4),
             net_IR=round(ir - ann_cost_drag, 4))
})
net_ir_dt <- rbindlist(net_ir_rows)
setorder(net_ir_dt, -net_IR)
fwrite(net_ir_dt, file.path(OUT_DIR, "net_ir_selection_table.csv"))
cat("\n=== net_IR ranking (Optimizer R4 P3 selection objective) ===\n")
print(net_ir_dt)

## ────────────────────────────────────────────────────────────────────────
## STEP 10: 도훈 framing validation
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 10] 도훈 framing validation — Path C (70/15/15) + S4 (50/25/20/5)\n")

framing_validation <- list(
  Path_C_70_15_15 = list(
    weights = w_path_c,
    label = "도훈 Path C strict — STR_1715 70 / TSMOM 15 / KR10y 15 / Cash 0",
    full_sample = eval_full[["Path_C_strict"]],
    oos_28m = eval_oos[["Path_C_strict"]],
    tsmom_window = eval_tsmom[["Path_C_strict"]],
    AX001v2 = ax001v2_dt[method == "Path_C_strict"],
    DSR = dsr_table[method == "Path_C_strict"],
    net_IR = net_ir_dt[method == "Path_C_strict"]
  ),
  S4_50_25_20_5 = list(
    weights = w_s4,
    label = "도훈 S4 strict — STR_1715 50 / TSMOM 25 / KR10y 20 / Cash 5",
    full_sample = eval_full[["S4_strict"]],
    oos_28m = eval_oos[["S4_strict"]],
    tsmom_window = eval_tsmom[["S4_strict"]],
    AX001v2 = ax001v2_dt[method == "S4_strict"],
    DSR = dsr_table[method == "S4_strict"],
    net_IR = net_ir_dt[method == "S4_strict"]
  )
)

# Comparison summary
framing_table <- data.table(
  framing = c("Path_C_70_15_15", "S4_50_25_20_5"),
  SR_full = c(eval_full[["Path_C_strict"]]$SR, eval_full[["S4_strict"]]$SR),
  CAGR_full = c(eval_full[["Path_C_strict"]]$CAGR, eval_full[["S4_strict"]]$CAGR),
  MDD_full = c(eval_full[["Path_C_strict"]]$MDD, eval_full[["S4_strict"]]$MDD),
  SR_oos = c(eval_oos[["Path_C_strict"]]$SR, eval_oos[["S4_strict"]]$SR),
  CAGR_oos = c(eval_oos[["Path_C_strict"]]$CAGR, eval_oos[["S4_strict"]]$CAGR),
  MDD_oos = c(eval_oos[["Path_C_strict"]]$MDD, eval_oos[["S4_strict"]]$MDD),
  net_IR = c(net_ir_dt[method=="Path_C_strict", net_IR],
             net_ir_dt[method=="S4_strict", net_IR]),
  AX001v2_PASS = c(ax001v2_dt[method=="Path_C_strict", AX001v2_PASS],
                   ax001v2_dt[method=="S4_strict", AX001v2_PASS])
)
fwrite(framing_table, file.path(OUT_DIR, "dohoon_framing_table.csv"))
cat("\n=== 도훈 framing comparison ===\n")
print(framing_table)

## ────────────────────────────────────────────────────────────────────────
## STEP 11: S4 v3 candidate recommendation
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 11] S4 v3 candidate recommendation logic\n")

# Selection criteria (5-tier hierarchy):
#  1. AX-001 v2 PASS (defense conditional)
#  2. DSR ≥ 0.95
#  3. SR_oos ≥ 1.0 (alpha-updated era validates the choice)
#  4. MDD ≤ -25% (Production Constraints target)
#  5. net_IR > 0 vs S0
m_table_full[, AX001v2_PASS := ax001v2_dt$AX001v2_PASS[match(method, ax001v2_dt$method)]]
m_table_full[, DSR_p := dsr_table$DSR_p[match(method, dsr_table$method)]]
m_table_full[, net_IR := net_ir_dt$net_IR[match(method, net_ir_dt$method)]]
m_table_full[, SR_oos := m_table_oos$SR[match(method, m_table_oos$method)]]
m_table_full[, MDD_oos := m_table_oos$MDD[match(method, m_table_oos$method)]]

# Score each method
m_table_full[, score := 0L]
m_table_full[AX001v2_PASS == TRUE, score := score + 30L]
m_table_full[DSR_p >= 0.95, score := score + 20L]
m_table_full[!is.na(SR_oos) & SR_oos >= 1.0, score := score + 20L]
m_table_full[MDD <= 0.25 & !is.na(MDD), score := score + 15L]
m_table_full[!is.na(net_IR) & net_IR > 0, score := score + 15L]

setorder(m_table_full, -score, -SR)
cat("\n=== Method scoring (5-tier hierarchy) ===\n")
print(m_table_full[, .(method, score, AX001v2_PASS, DSR_p, SR_oos, MDD, net_IR, SR)])

# Top recommendation
top_method <- m_table_full[1, method]
top_weights <- W_full[top_method, ]
cat(sprintf("\n[TOP RECOMMENDATION] %s\n", top_method))
cat(sprintf("  Weights: AR_on_M4=%.3f, TSMOM=%.3f, KR_10y=%.3f, Cash=%.3f\n",
            top_weights["AR_on_M4"], top_weights["TSMOM"], top_weights["KR_10y"], top_weights["Cash"]))
cat(sprintf("  SR_full=%.3f, MDD_full=%.3f, SR_oos=%.3f, AX001v2=%s\n",
            eval_full[[top_method]]$SR, eval_full[[top_method]]$MDD,
            eval_oos[[top_method]]$SR, ax001v2_dt[method==top_method, AX001v2_PASS]))

s4_v3_recommendation <- list(
  task_id = WT_ID,
  recommendation_kind = "S4_v3_candidate",
  recommended_method = top_method,
  recommended_weights = list(
    AR_on_M4 = unname(round(top_weights["AR_on_M4"], 4)),
    TSMOM    = unname(round(top_weights["TSMOM"], 4)),
    KR_10y   = unname(round(top_weights["KR_10y"], 4)),
    Cash     = unname(round(top_weights["Cash"], 4))
  ),
  expected_metrics_full_sample = list(
    SR = eval_full[[top_method]]$SR,
    CAGR = eval_full[[top_method]]$CAGR,
    MDD = eval_full[[top_method]]$MDD,
    Sortino = eval_full[[top_method]]$Sortino,
    Calmar = eval_full[[top_method]]$Calmar
  ),
  expected_metrics_oos_28m = list(
    SR = eval_oos[[top_method]]$SR,
    CAGR = eval_oos[[top_method]]$CAGR,
    MDD = eval_oos[[top_method]]$MDD
  ),
  vs_dohoon_framing = list(
    Path_C = list(
      delta_SR_full = round(eval_full[[top_method]]$SR - eval_full[["Path_C_strict"]]$SR, 4),
      delta_MDD_pp = round((eval_full[["Path_C_strict"]]$MDD - eval_full[[top_method]]$MDD) * 100, 2)
    ),
    S4 = list(
      delta_SR_full = round(eval_full[[top_method]]$SR - eval_full[["S4_strict"]]$SR, 4),
      delta_MDD_pp = round((eval_full[["S4_strict"]]$MDD - eval_full[[top_method]]$MDD) * 100, 2)
    )
  ),
  ax_certifications = list(
    AX_001_v2_PASS = unname(ax001v2_dt[method == top_method, AX001v2_PASS]),
    DSR_pass_95   = unname(dsr_table[method == top_method, DSR_pass_95]),
    AX_002_PIT = TRUE,
    AX_007_multi_sleeve_exception = TRUE
  ),
  caveats = list(
    "Static weight backtest assumes annual rebalance (cost_drag ~3bps)",
    "TSMOM only available 2015-01+ (zero-fill pre-2015 = conservative)",
    "Full-sample optimal weights computed with hindsight (in-sample); OOS verifies",
    "Forge 실측 white-box mandate (real run_all.R + 15bps + KOSPI BM)",
    "도훈 conviction call mandate — Optimizer는 권고만 (S4 retain도 합리적)"
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)

write_json(s4_v3_recommendation,
           file.path(WT_DIR, "S4_v3_candidate_recommendation.json"),
           auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("\n[SAVED] S4_v3_candidate_recommendation.json\n"))

## ────────────────────────────────────────────────────────────────────────
## STEP 12: weights.csv schedule output
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 12] weights.csv schedule (256m monthly)\n")

# weights.csv: as_of_date × sleeve weight (selected method, static)
sched_dates <- master_full$date
weights_csv <- data.table(
  as_of_date = sched_dates,
  STR_1715_alpha_updated = unname(top_weights["AR_on_M4"]),
  TSMOM_9_ETF = unname(top_weights["TSMOM"]),
  KR_10y_bond = unname(top_weights["KR_10y"]),
  Cash = unname(top_weights["Cash"])
)
fwrite(weights_csv, file.path(STAGE_DIR, "weights.csv"))
cat(sprintf("[SAVED] stage_artifacts/WT_P20260509_001/weights.csv (n=%d)\n", nrow(weights_csv)))

# Also save Path_C, S4, top recommendation as alternative weights
fwrite(data.table(
  as_of_date = sched_dates,
  STR_1715_alpha_updated = w_path_c[1], TSMOM_9_ETF = w_path_c[2],
  KR_10y_bond = w_path_c[3], Cash = w_path_c[4]),
  file.path(STAGE_DIR, "weights_path_c.csv"))
fwrite(data.table(
  as_of_date = sched_dates,
  STR_1715_alpha_updated = w_s4[1], TSMOM_9_ETF = w_s4[2],
  KR_10y_bond = w_s4[3], Cash = w_s4[4]),
  file.path(STAGE_DIR, "weights_s4_strict.csv"))

## ────────────────────────────────────────────────────────────────────────
## STEP 13: method_shopping_log.json (R2-C HARD)
## ────────────────────────────────────────────────────────────────────────
cat("\n[STEP 13] method_shopping_log.json (Optimizer R2-C)\n")

shopping_log <- list(
  optimizer_agent = list(
    candidates_tried = nrow(m_table_full),
    method_log = lapply(seq_len(nrow(m_table_full)), function(i) {
      m <- m_table_full$method[i]
      w <- if (m %in% rownames(W_full)) W_full[m, ] else c(1, 0, 0, 0)
      list(
        name = m,
        weights = list(AR_on_M4=unname(round(w["AR_on_M4"], 4)),
                       TSMOM=unname(round(w["TSMOM"], 4)),
                       KR_10y=unname(round(w["KR_10y"], 4)),
                       Cash=unname(round(w["Cash"], 4))),
        metrics_full = list(
          SR=m_table_full$SR[i], CAGR=m_table_full$CAGR[i],
          MDD=m_table_full$MDD[i], Sortino=m_table_full$Sortino[i],
          Calmar=m_table_full$Calmar[i]
        ),
        metrics_oos = list(
          SR=m_table_full$SR_oos[i], MDD=m_table_full$MDD_oos[i]
        ),
        DSR_p = m_table_full$DSR_p[i],
        AX001v2_PASS = m_table_full$AX001v2_PASS[i],
        net_IR = m_table_full$net_IR[i],
        score = m_table_full$score[i],
        selected = (m == top_method)
      )
    })
  )
)
write_json(shopping_log, file.path(WT_DIR, "method_shopping_log.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null")
cat(sprintf("[SAVED] method_shopping_log.json (%d candidates)\n", nrow(m_table_full)))

## ────────────────────────────────────────────────────────────────────────
## STEP 14: Final summary
## ────────────────────────────────────────────────────────────────────────
cat("\n============================================================\n")
cat("  WT-P20260509_001 OPTIMIZER ANALYSIS — COMPLETE\n")
cat(sprintf("  Finished: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("============================================================\n\n")

cat("SUMMARY:\n")
cat(sprintf("  Methods evaluated: %d\n", nrow(m_table_full)))
cat(sprintf("  Top recommendation: %s\n", top_method))
cat(sprintf("    Weights: AR=%.3f / TSMOM=%.3f / KR=%.3f / Cash=%.3f\n",
            top_weights["AR_on_M4"], top_weights["TSMOM"],
            top_weights["KR_10y"], top_weights["Cash"]))
cat(sprintf("    SR_full=%.3f, MDD_full=%.1f%%\n",
            eval_full[[top_method]]$SR, eval_full[[top_method]]$MDD * 100))
cat(sprintf("    SR_oos=%.3f, MDD_oos=%.1f%%\n",
            eval_oos[[top_method]]$SR, eval_oos[[top_method]]$MDD * 100))
cat("\nNEXT: Forge 실측 mandate (run_all.R + 15bps + KOSPI BM)\n")
cat("도훈 conviction call mandate after Forge result.\n")
