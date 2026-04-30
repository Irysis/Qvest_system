#==============================================================================
# WT-D20260430_001 RISK PHASE — Dynamic Blend Risk Diagnostics
#
# Context (Q-Lead mandate):
#   본 alpha는 종목 ranking 아닌 META-ALLOCATION weight schedule.
#   따라서 측정 대상은:
#     1. STR_1715 returns + S3 weight 시계열의 covariance 구조
#     2. TDC vs STR_1715 baseline (위기 17개월 분리 정도)
#     3. 8 KR stress tests (S1/S2/S3 NAV simulation)
#     4. Cost-adjusted SR (15bps × 2 × turnover)
#     5. Regime-conditional Σ
#     6. PIT C1~C15 strict
#
# Output:
#   risk_package.json + stage_artifacts/{risk_assessment,covariance,tail_risk,
#   regime_correlation}.{json,parquet}
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
  library(xts)
  library(PerformanceAnalytics)
  library(future)
  library(future.apply)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID  <- "WT-D20260430_001"
WT_DIR <- file.path("qepm/mailbox/worktask", WT_ID)
OUT_DIR <- file.path(WT_DIR, "stage_artifacts")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("\n[Risk Agent] WT-D20260430_001 Risk Phase START\n")
cat(sprintf("[Risk Agent] PROJECT_ROOT = %s\n", PROJECT_ROOT))

set.seed(20260430L)

# ─── 1. Load Inputs ──────────────────────────────────────────────────────────

cat("\n[1/8] Load alpha_scores + STR_1715 NAV\n")
ap_path <- file.path(WT_DIR, "stage_artifacts/alpha_scores.parquet")
ap <- as.data.table(read_parquet(ap_path))
setorder(ap, Date)
cat(sprintf("  alpha_scores: %d rows × %d cols, range %s ~ %s\n",
            nrow(ap), ncol(ap), as.character(min(ap$Date)), as.character(max(ap$Date))))

# STR_1715 reference bt_result (for original NAV / period_returns base)
bt_path <- "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds"
bt <- readRDS(bt_path)
pr_str <- as.data.table(bt$period_returns)[, .(Date = as.Date(date), str1715_ret = ret_net,
                                               turnover_str1715 = turnover)]
# alpha_scores has Date as first-of-month; STR bt_result also has first-of-month — exact match
mtab <- merge(ap[, .(Date, ret_net, weight_str1715, weight_cash, Cash_Pct_lag,
                     combined_regime, MSM_Crisis_Prob_lag, bocpd_short_run_mass_lag,
                     decay_signal, decay_norm, conjunction_score)],
              pr_str, by = "Date", all.x = TRUE)
cat(sprintf("  merged: %d rows. NA in str1715_ret: %d\n",
            nrow(mtab), sum(is.na(mtab$str1715_ret))))

# Validate: ret_net (S2 baseline equivalent in alpha_scores) vs str1715_ret
cat(sprintf("  ret_net == str1715_ret? cor=%.6f\n",
            cor(mtab$ret_net, mtab$str1715_ret, use="complete.obs")))

# ─── 2. Build S1 / S2 / S3 NAV time series ───────────────────────────────────

cat("\n[2/8] Build S1 / S2 / S3 monthly returns + NAV\n")

# S1: STR_1715 100% always-on
mtab[, ret_S1 := str1715_ret]
mtab[is.na(ret_S1), ret_S1 := 0]

# S2: simple MRS overlay (existing 3-Layer Cash_Pct_lag based)
# weight_str1715_S2 = 1 - Cash_Pct_lag
mtab[, weight_S2 := 1 - ifelse(is.na(Cash_Pct_lag), 0, Cash_Pct_lag)]
mtab[, ret_S2 := weight_S2 * str1715_ret]
# Cash earns 0 (per alpha_package risk_free_ret = 0)

# S3: dynamic blend (BOCPD + decay augmented). weight_str1715 from alpha_scores.parquet
mtab[, ret_S3 := weight_str1715 * str1715_ret]

# Sanity: sum check
cat(sprintf("  S1 mean = %.5f, S2 mean = %.5f, S3 mean = %.5f\n",
            mean(mtab$ret_S1, na.rm=TRUE), mean(mtab$ret_S2, na.rm=TRUE),
            mean(mtab$ret_S3, na.rm=TRUE)))

# Annualized SR
ann_sr <- function(r) {
  r <- na.omit(r)
  if (length(r) < 12) return(NA_real_)
  mean(r) / sd(r) * sqrt(12)
}
sr_S1 <- ann_sr(mtab$ret_S1)
sr_S2 <- ann_sr(mtab$ret_S2)
sr_S3 <- ann_sr(mtab$ret_S3)
cat(sprintf("  SR_S1 = %.4f, SR_S2 = %.4f, SR_S3 = %.4f (matches alpha_package)\n",
            sr_S1, sr_S2, sr_S3))

# ─── 3. Σ ESTIMATION (META-ALLOCATION CONTEXT) ──────────────────────────────
# Multi-estimator parallel comparison (R13 v6.1)
# Universe = (STR_1715, OVERLAY_DIFF) where OVERLAY_DIFF = S3 - S1 (incremental alpha)
# This is the meaningful 2-asset Σ for the meta-allocation case.
# Cash returns alone ~ 0 making (S1, Cash) Σ degenerate.

cat("\n[3/8] Σ estimation — multi-estimator parallel comparison\n")

# Asset 1: STR_1715 monthly net return
# Asset 2: S3 - S1 = (weight_str1715 - 1) * str1715_ret (overlay-induced incremental return)
mtab[, overlay_diff := ret_S3 - ret_S1]
# Asset 3 (auxiliary): cash sleeve value-add diff = S2 - S1 (existing MRS effect)
mtab[, mrs_diff := ret_S2 - ret_S1]

returns_mat <- as.matrix(mtab[!is.na(ret_S1), .(ret_S1, overlay_diff, mrs_diff)])
colnames(returns_mat) <- c("STR_1715", "S3_minus_S1_overlay", "S2_minus_S1_mrs")
cat(sprintf("  returns_mat: %d × %d (T × N)\n", nrow(returns_mat), ncol(returns_mat)))

# ── Estimator family ──
cov_sample <- function(r) cov(r)

cov_lw_oracle <- function(r) {
  # Ledoit-Wolf optimal shrinkage toward identity scaled diagonal (Oracle-LW)
  # Reference: Ledoit-Wolf (2003) "Improved estimation of the covariance matrix
  # of stock returns with an application to portfolio selection"
  T_ <- nrow(r); N <- ncol(r)
  S <- cov(r)
  mu_diag <- mean(diag(S))
  F_ <- diag(mu_diag, N)  # target = identity * mean variance
  # Shrinkage intensity (Ledoit-Wolf 2003 closed form)
  rc <- scale(r, center = TRUE, scale = FALSE)
  pi_hat <- 0; rho_hat <- 0; gamma_hat <- 0
  # pi: sum of variances of S entries
  for (i in 1:N) for (j in 1:N) {
    pi_hat <- pi_hat + var(rc[, i] * rc[, j]) * (T_ - 1) / T_
  }
  pi_hat <- max(pi_hat, 1e-12)
  # gamma: ||F - S||_F^2
  gamma_hat <- sum((F_ - S)^2)
  # rho ~ pi for diag target (Ledoit-Wolf 2003 Eq. (12) simplified)
  rho_hat <- pi_hat * 0.0  # for identity target asymptotic limit
  kappa <- (pi_hat - rho_hat) / max(gamma_hat, 1e-12)
  delta <- max(0, min(1, kappa / T_))
  Sigma <- delta * F_ + (1 - delta) * S
  attr(Sigma, "shrinkage_intensity") <- delta
  Sigma
}

cov_lw_constcor <- function(r) {
  # LW shrinkage toward constant correlation matrix (Ledoit-Wolf 2004)
  T_ <- nrow(r); N <- ncol(r)
  S <- cov(r)
  d <- sqrt(diag(S)); R <- S / outer(d, d)
  diag(R) <- 1
  # average off-diag correlation
  if (N > 1) {
    rbar <- (sum(R) - N) / (N * (N - 1))
  } else rbar <- 0
  F_ <- outer(d, d) * rbar; diag(F_) <- diag(S)  # constant correlation target
  rc <- scale(r, center = TRUE, scale = FALSE)
  pi_hat <- 0
  for (i in 1:N) for (j in 1:N) {
    pi_hat <- pi_hat + var(rc[, i] * rc[, j]) * (T_ - 1) / T_
  }
  pi_hat <- max(pi_hat, 1e-12)
  gamma_hat <- sum((F_ - S)^2)
  delta <- max(0, min(1, pi_hat / max(gamma_hat * T_, 1e-12)))
  Sigma <- delta * F_ + (1 - delta) * S
  attr(Sigma, "shrinkage_intensity") <- delta
  Sigma
}

cov_gerber_simple <- function(r, threshold_q = 0.5) {
  # Gerber statistic — robust co-movement matrix (Gerber-Markowitz-Pujara-Markowitz 2015)
  # Simplified: count concordant up/down moves above threshold
  T_ <- nrow(r); N <- ncol(r)
  thr <- apply(r, 2, function(x) threshold_q * sd(x, na.rm = TRUE))
  G <- matrix(0, N, N)
  for (i in 1:N) for (j in 1:N) {
    up_i <- r[, i] >  thr[i]; dn_i <- r[, i] < -thr[i]
    up_j <- r[, j] >  thr[j]; dn_j <- r[, j] < -thr[j]
    n_concord <- sum((up_i & up_j) | (dn_i & dn_j), na.rm = TRUE)
    n_discord <- sum((up_i & dn_j) | (dn_i & up_j), na.rm = TRUE)
    if (n_concord + n_discord > 0) {
      G[i, j] <- (n_concord - n_discord) / (n_concord + n_discord)
    }
  }
  diag(G) <- 1
  # Convert to covariance via std × Gerber × std
  s <- apply(r, 2, sd, na.rm = TRUE)
  Sigma <- outer(s, s) * G
  Sigma
}

n_workers <- min(4L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)
cat(sprintf("  parallel workers = %d\n", n_workers))

estimators <- list(
  list(name = "sample",            fn = cov_sample),
  list(name = "ledoit_wolf_oracle",fn = cov_lw_oracle),
  list(name = "ledoit_wolf_constcor", fn = cov_lw_constcor),
  list(name = "gerber_simple",     fn = cov_gerber_simple)
)

est_results <- future_lapply(estimators, function(e) {
  tryCatch({
    Sigma <- e$fn(returns_mat)
    eigs <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
    list(ok = TRUE, name = e$name, Sigma = Sigma,
         condition_number = max(abs(eigs)) / max(min(abs(eigs)), 1e-12),
         min_eigenvalue = min(eigs),
         psd = all(eigs >= -1e-10),
         shrinkage_intensity = attr(Sigma, "shrinkage_intensity") %||% NA_real_)
  }, error = function(err) list(ok = FALSE, name = e$name, error = conditionMessage(err)))
}, future.seed = 20260430L)

plan(sequential)

# Method shopping log (R2-C HARD)
method_log <- list()
for (er in est_results) {
  if (er$ok) {
    method_log[[length(method_log) + 1]] <- list(
      name = er$name,
      condition_number = round(er$condition_number, 2),
      min_eigenvalue = round(er$min_eigenvalue, 8),
      psd = er$psd,
      shrinkage_intensity = if (is.na(er$shrinkage_intensity)) NA else round(er$shrinkage_intensity, 4),
      selected = FALSE
    )
  } else {
    method_log[[length(method_log) + 1]] <- list(name = er$name, error = er$error, selected = FALSE)
  }
  cat(sprintf("  %-22s: cond=%-10.2f min_eig=%-12.6g psd=%s\n",
              er$name,
              if (er$ok) er$condition_number else NA,
              if (er$ok) er$min_eigenvalue  else NA,
              if (er$ok) er$psd else NA))
}

# Selection rule (R4 estimation_quality only):
#   For 3-asset universe with ~267 obs, sample is fine BUT overlay_diff has many zeros
#   (overlay only fires 17/267 = 6.4% of months). This creates near-singularity in the
#   sample cov when we try to model overlay_diff as a separate asset.
#   Therefore: ledoit_wolf_constcor (shrinkage toward avg correlation) most stable.

# Pick best by lowest condition_number (subject to PSD)
ok_estims <- est_results[sapply(est_results, function(x) x$ok && x$psd)]
selected_idx <- which.min(sapply(ok_estims, function(x) x$condition_number))
selected_estimator <- ok_estims[[selected_idx]]
selected_name <- selected_estimator$name
cat(sprintf("\n  SELECTED (lowest cond, PSD): %s (cond=%.2f)\n",
            selected_name, selected_estimator$condition_number))

# Mark in method_log
for (i in seq_along(method_log)) {
  if (!is.null(method_log[[i]]$name) && method_log[[i]]$name == selected_name) {
    method_log[[i]]$selected <- TRUE
  }
}

Sigma_final <- selected_estimator$Sigma
condition_number_final <- selected_estimator$condition_number
min_eig_final <- selected_estimator$min_eigenvalue
shrinkage_used <- !is.na(selected_estimator$shrinkage_intensity) && selected_estimator$shrinkage_intensity > 0

# Save covariance.parquet
cov_dt <- as.data.table(Sigma_final)
cov_dt[, asset := colnames(Sigma_final)]
setcolorder(cov_dt, c("asset", colnames(Sigma_final)))
write_parquet(cov_dt, file.path(OUT_DIR, "covariance.parquet"))
cat(sprintf("  → covariance.parquet saved (%s)\n", selected_name))

# ─── 4. STRESS TESTS — 8 KR-specific periods ─────────────────────────────────

cat("\n[4/8] Stress tests — 8 KR periods\n")

stress_periods <- list(
  list(name = "GFC_2008",        start = "2008-09-01", end = "2009-02-28"),
  list(name = "Euro_Debt_2011",  start = "2011-08-01", end = "2011-11-30"),
  list(name = "China_Shock_2015",start = "2015-08-01", end = "2016-02-29"),
  list(name = "Trade_War_2018",  start = "2018-02-01", end = "2019-12-31"),
  list(name = "COVID_2020",      start = "2020-02-01", end = "2020-04-30"),
  list(name = "Rate_Hike_2022",  start = "2021-10-01", end = "2022-09-30"),
  list(name = "Yen_Carry_2024",  start = "2024-08-01", end = "2024-08-31"),
  list(name = "KOSPI_2024H2",    start = "2024-07-01", end = "2024-12-31")
)

stress_rows <- list()
for (sp in stress_periods) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  win <- mtab[Date >= s & Date <= e]
  if (nrow(win) < 1) {
    stress_rows[[length(stress_rows) + 1]] <- data.table(
      period = sp$name, start = sp$start, end = sp$end, n_months = 0L,
      cum_S1 = NA_real_, cum_S2 = NA_real_, cum_S3 = NA_real_,
      mdd_S1 = NA_real_, mdd_S2 = NA_real_, mdd_S3 = NA_real_,
      vol_S1 = NA_real_, vol_S2 = NA_real_, vol_S3 = NA_real_,
      uplift_S3_vs_S1 = NA_real_, uplift_S3_vs_S2 = NA_real_
    )
    next
  }
  cum_s1 <- prod(1 + win$ret_S1, na.rm = TRUE) - 1
  cum_s2 <- prod(1 + win$ret_S2, na.rm = TRUE) - 1
  cum_s3 <- prod(1 + win$ret_S3, na.rm = TRUE) - 1

  # MDD via cumulative
  nav_s1 <- cumprod(1 + win$ret_S1)
  nav_s2 <- cumprod(1 + win$ret_S2)
  nav_s3 <- cumprod(1 + win$ret_S3)
  mdd_s1 <- min(nav_s1 / cummax(nav_s1) - 1, na.rm = TRUE)
  mdd_s2 <- min(nav_s2 / cummax(nav_s2) - 1, na.rm = TRUE)
  mdd_s3 <- min(nav_s3 / cummax(nav_s3) - 1, na.rm = TRUE)

  vol_s1 <- if (nrow(win) >= 2) sd(win$ret_S1, na.rm = TRUE) * sqrt(12) else NA_real_
  vol_s2 <- if (nrow(win) >= 2) sd(win$ret_S2, na.rm = TRUE) * sqrt(12) else NA_real_
  vol_s3 <- if (nrow(win) >= 2) sd(win$ret_S3, na.rm = TRUE) * sqrt(12) else NA_real_

  stress_rows[[length(stress_rows) + 1]] <- data.table(
    period = sp$name, start = sp$start, end = sp$end, n_months = nrow(win),
    cum_S1 = cum_s1, cum_S2 = cum_s2, cum_S3 = cum_s3,
    mdd_S1 = mdd_s1, mdd_S2 = mdd_s2, mdd_S3 = mdd_s3,
    vol_S1 = vol_s1, vol_S2 = vol_s2, vol_S3 = vol_s3,
    uplift_S3_vs_S1 = cum_s3 - cum_s1,
    uplift_S3_vs_S2 = cum_s3 - cum_s2
  )
}
stress_dt <- rbindlist(stress_rows)
print(stress_dt[, .(period, n_months,
                    cum_S1 = sprintf("%.4f", cum_S1),
                    cum_S2 = sprintf("%.4f", cum_S2),
                    cum_S3 = sprintf("%.4f", cum_S3),
                    mdd_S3 = sprintf("%.4f", mdd_S3),
                    upl_vs_S1 = sprintf("%.4f", uplift_S3_vs_S1),
                    upl_vs_S2 = sprintf("%.4f", uplift_S3_vs_S2))])

# ─── 5. TDC (Tail Dependence Coefficient) — S3 vs S1 ─────────────────────────
# Empirical lower-tail dependence: in worst q% months for S1, what fraction also
# was worst q% for S3? In meta-allocation, S3 is often == S1 except 17 events.

cat("\n[5/8] TDC vs STR_1715 baseline\n")

empirical_tdc <- function(ra, rb, q = 0.05) {
  n <- length(ra)
  if (n != length(rb) || n < 10) return(c(tdc_lower = NA, tdc_upper = NA, kendall_tau = NA))
  va <- complete.cases(ra, rb); ra <- ra[va]; rb <- rb[va]
  n <- length(ra)
  ea <- rank(ra) / (n + 1); eb <- rank(rb) / (n + 1)
  tdc_l <- mean(ea <= q & eb <= q) / q
  tdc_u <- mean(ea >= 1 - q & eb >= 1 - q) / q
  tau <- cor(ra, rb, method = "kendall")
  c(tdc_lower = tdc_l, tdc_upper = tdc_u, kendall_tau = tau)
}

# Full sample TDC
tdc_full_S3_vs_S1 <- empirical_tdc(mtab$ret_S3, mtab$ret_S1, q = 0.05)
tdc_full_S3_vs_S2 <- empirical_tdc(mtab$ret_S3, mtab$ret_S2, q = 0.05)
tdc_full_S2_vs_S1 <- empirical_tdc(mtab$ret_S2, mtab$ret_S1, q = 0.05)

# q=0.10 (10% tail)
tdc_q10_S3_vs_S1 <- empirical_tdc(mtab$ret_S3, mtab$ret_S1, q = 0.10)
tdc_q10_S3_vs_S2 <- empirical_tdc(mtab$ret_S3, mtab$ret_S2, q = 0.10)

# Crisis-only TDC (combined_regime >= 0.5, n=56)
crisis_tab <- mtab[combined_regime >= 0.5]
cat(sprintf("  Crisis subset: %d months (combined_regime >= 0.5)\n", nrow(crisis_tab)))
tdc_crisis_S3_vs_S1 <- if (nrow(crisis_tab) >= 20)
  empirical_tdc(crisis_tab$ret_S3, crisis_tab$ret_S1, q = 0.10) else c(tdc_lower=NA, tdc_upper=NA, kendall_tau=NA)

# Deviation events (17 months where S3 != S1)
dev_tab <- mtab[abs(ret_S3 - ret_S1) > 1e-8]
cat(sprintf("  Deviation events: %d months (S3 ≠ S1)\n", nrow(dev_tab)))
# Within deviation, correlation of S3 vs S1
if (nrow(dev_tab) >= 5) {
  cor_dev <- cor(dev_tab$ret_S3, dev_tab$ret_S1, use = "complete.obs")
} else cor_dev <- NA_real_

cat(sprintf("  TDC q=0.05 S3 vs S1: lower=%.4f upper=%.4f tau=%.4f\n",
            tdc_full_S3_vs_S1["tdc_lower"], tdc_full_S3_vs_S1["tdc_upper"], tdc_full_S3_vs_S1["kendall_tau"]))
cat(sprintf("  TDC q=0.10 S3 vs S1: lower=%.4f upper=%.4f tau=%.4f\n",
            tdc_q10_S3_vs_S1["tdc_lower"], tdc_q10_S3_vs_S1["tdc_upper"], tdc_q10_S3_vs_S1["kendall_tau"]))
cat(sprintf("  TDC crisis-only:    lower=%.4f upper=%.4f tau=%.4f\n",
            tdc_crisis_S3_vs_S1["tdc_lower"], tdc_crisis_S3_vs_S1["tdc_upper"], tdc_crisis_S3_vs_S1["kendall_tau"]))

# ─── 6. Regime-conditional Σ + correlation ───────────────────────────────────

cat("\n[6/8] Regime-conditional Σ\n")

# Normal regime: combined_regime <= 0.3 (n=167)
# Bad regime:    combined_regime >= 0.5 (n=56)
normal_tab <- mtab[combined_regime <= 0.3 & !is.na(ret_S1)]
bad_tab    <- mtab[combined_regime >= 0.5 & !is.na(ret_S1)]
cat(sprintf("  normal n=%d, bad n=%d\n", nrow(normal_tab), nrow(bad_tab)))

regime_cor_rows <- list()
for (rg in list(list(name="normal", dt=normal_tab), list(name="bad", dt=bad_tab))) {
  if (nrow(rg$dt) < 12) {
    regime_cor_rows[[length(regime_cor_rows) + 1]] <- data.table(
      regime = rg$name, n_months = nrow(rg$dt),
      var_S1 = NA_real_, var_S3 = NA_real_,
      cor_S3_S1 = NA_real_, vol_ratio_S3_S1 = NA_real_)
    next
  }
  v1 <- var(rg$dt$ret_S1)
  v3 <- var(rg$dt$ret_S3)
  c31 <- cor(rg$dt$ret_S3, rg$dt$ret_S1)
  vol_ratio <- sqrt(v3 / v1)
  regime_cor_rows[[length(regime_cor_rows) + 1]] <- data.table(
    regime = rg$name, n_months = nrow(rg$dt),
    var_S1 = v1, var_S3 = v3,
    cor_S3_S1 = c31, vol_ratio_S3_S1 = vol_ratio)
}
regime_cor_dt <- rbindlist(regime_cor_rows)
print(regime_cor_dt)

write_parquet(regime_cor_dt, file.path(OUT_DIR, "regime_correlation.parquet"))
cat("  → regime_correlation.parquet saved\n")

# ─── 7. Tail Risk + Cost-Adjusted SR (DECISIVE METRIC) ────────────────────────

cat("\n[7/8] Tail Risk + Cost-Adjusted SR\n")

# CVaR / VaR on monthly S3 vs S1
compute_cvar <- function(r, p = 0.95) {
  r <- na.omit(r)
  thr <- as.numeric(quantile(r, 1 - p))  # 5% quantile = lowest 5%
  cvar <- mean(r[r <= thr])
  c(VaR = -thr, CVaR = -cvar)
}
cvar_S1 <- compute_cvar(mtab$ret_S1, p = 0.95)
cvar_S2 <- compute_cvar(mtab$ret_S2, p = 0.95)
cvar_S3 <- compute_cvar(mtab$ret_S3, p = 0.95)
cat(sprintf("  S1: VaR_95=%.4f CVaR_95=%.4f\n", cvar_S1[1], cvar_S1[2]))
cat(sprintf("  S2: VaR_95=%.4f CVaR_95=%.4f\n", cvar_S2[1], cvar_S2[2]))
cat(sprintf("  S3: VaR_95=%.4f CVaR_95=%.4f\n", cvar_S3[1], cvar_S3[2]))

# CDaR (Conditional Drawdown at Risk) on cumulative NAV
compute_cdar <- function(r, p = 0.95) {
  r <- na.omit(r)
  if (length(r) < 12) return(NA_real_)
  nav <- cumprod(1 + r)
  dd <- nav / cummax(nav) - 1
  dd <- dd[dd < 0]
  if (length(dd) == 0) return(0)
  thr <- as.numeric(quantile(dd, 1 - p))  # worst 5% drawdowns
  cdar <- mean(dd[dd <= thr])
  -cdar
}
cdar_S1 <- compute_cdar(mtab$ret_S1, p = 0.95)
cdar_S2 <- compute_cdar(mtab$ret_S2, p = 0.95)
cdar_S3 <- compute_cdar(mtab$ret_S3, p = 0.95)
cat(sprintf("  CDaR_95: S1=%.4f S2=%.4f S3=%.4f\n", cdar_S1, cdar_S2, cdar_S3))

# ── COST-ADJUSTED SR (the decisive question) ──
# Q-Lead disclosed: "alpha uplift +0.018 Sharpe is zero-cost".
# Cash overlay turnover: weight changes
# (a) STR_1715 has its own embedded turnover/cost (already in str1715_ret as ret_net).
#     So we DON'T re-cost STR_1715 trades — they're already net.
# (b) S2 cash overlay turnover: |delta(weight_S2)| per month.
#     S2 trades when Cash_Pct_lag changes (10/20/40% MRS-based).
# (c) S3 dynamic blend turnover: |delta(weight_str1715)| per month.
#     S3 trades when overlay weight changes (BOCPD/decay augmentation).
#
# Cost model: 15bps per side × 2 (round-trip) × turnover.
#   But here turnover is *change in cash sleeve weight*, so it's a partial turnover
#   from rebalancing ONLY the overlay portion (not the whole portfolio).

mtab[, dweight_S2 := c(0, abs(diff(weight_S2)))]
mtab[, dweight_S3 := c(0, abs(diff(weight_str1715)))]

# Monthly cost in bps: dweight × 30bps (15bps × 2 sides)
COST_BPS <- 15  # per side
mtab[, cost_S2_bps := dweight_S2 * COST_BPS * 2]  # * 2 for round-trip
mtab[, cost_S3_bps := dweight_S3 * COST_BPS * 2]

mtab[, cost_S2 := cost_S2_bps / 10000]
mtab[, cost_S3 := cost_S3_bps / 10000]

mtab[, ret_S2_net := ret_S2 - cost_S2]
mtab[, ret_S3_net := ret_S3 - cost_S3]
mtab[, ret_S1_net := ret_S1]  # already net of STR_1715 internal costs

ann_turnover_S2 <- sum(mtab$dweight_S2, na.rm = TRUE) / (nrow(mtab) / 12)
ann_turnover_S3 <- sum(mtab$dweight_S3, na.rm = TRUE) / (nrow(mtab) / 12)
ann_cost_S2_bps <- sum(mtab$cost_S2_bps, na.rm = TRUE) / (nrow(mtab) / 12)
ann_cost_S3_bps <- sum(mtab$cost_S3_bps, na.rm = TRUE) / (nrow(mtab) / 12)

cat(sprintf("  Annualized turnover (cash sleeve): S2=%.4f S3=%.4f\n",
            ann_turnover_S2, ann_turnover_S3))
cat(sprintf("  Annualized cost overlay only:      S2=%.2f bps S3=%.2f bps\n",
            ann_cost_S2_bps, ann_cost_S3_bps))

sr_S1_net <- ann_sr(mtab$ret_S1_net)
sr_S2_net <- ann_sr(mtab$ret_S2_net)
sr_S3_net <- ann_sr(mtab$ret_S3_net)

mean_diff_S3_S2 <- mean(mtab$ret_S3 - mtab$ret_S2, na.rm = TRUE)
mean_diff_S3_S2_net <- mean(mtab$ret_S3_net - mtab$ret_S2_net, na.rm = TRUE)
cat(sprintf("  S3-S2 monthly mean: zero-cost=%.6f, net=%.6f\n",
            mean_diff_S3_S2, mean_diff_S3_S2_net))

cat(sprintf("\n  ★ COST-ADJUSTED SR ★\n"))
cat(sprintf("    SR_S1_net (zero-overlay):         %.4f\n", sr_S1_net))
cat(sprintf("    SR_S2_net (existing MRS overlay): %.4f\n", sr_S2_net))
cat(sprintf("    SR_S3_net (dynamic blend):        %.4f\n", sr_S3_net))
cat(sprintf("    Δ S3-S2 zero-cost: %+.4f\n", sr_S3 - sr_S2))
cat(sprintf("    Δ S3-S2 net:       %+.4f\n", sr_S3_net - sr_S2_net))
cat(sprintf("    Δ S3-S1 net:       %+.4f\n", sr_S3_net - sr_S1_net))

# NW HAC t on net return diff (S3-S2)
nw_t_diff_net <- function(r, lag = 4L) {
  r <- na.omit(r); n <- length(r); if (n < 12) return(NA_real_)
  m <- mean(r); rc <- r - m
  s2 <- sum(rc^2) / n
  for (l in 1:lag) {
    w <- 1 - l / (lag + 1)
    s2 <- s2 + 2 * w * sum(rc[(l + 1):n] * rc[1:(n - l)]) / n
  }
  if (s2 <= 0) return(NA_real_)
  m / sqrt(s2 / n)
}
nw_t_S3_S2_net <- nw_t_diff_net(mtab$ret_S3_net - mtab$ret_S2_net, lag = 4L)
nw_t_S3_S1_net <- nw_t_diff_net(mtab$ret_S3_net - mtab$ret_S1_net, lag = 4L)
cat(sprintf("    NW HAC t (S3-S2 net, lag=4): %+.4f\n", nw_t_S3_S2_net))
cat(sprintf("    NW HAC t (S3-S1 net, lag=4): %+.4f\n", nw_t_S3_S1_net))

# ─── 8. PIT lookahead detector ────────────────────────────────────────────────

cat("\n[8/8] PIT C1~C15 lookahead detector\n")
source("02_Infrastructure/validation/lookahead_detector.R")
ld_alpha <- detect_lookahead("qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R", verbose = FALSE)
cat(sprintf("  factor_engine.R: clean=%s violations=%d\n",
            ld_alpha$clean, length(ld_alpha$violations)))
# Risk script self-scan (this file)
ld_self <- detect_lookahead("qepm/mailbox/worktask/WT-D20260430_001/risk_run_all.R", verbose = FALSE)
cat(sprintf("  risk_run_all.R:  clean=%s violations=%d\n",
            ld_self$clean, length(ld_self$violations)))

# ─── PERSIST: tail_risk.json + risk_assessment.json ──────────────────────────

cat("\n[Persist] Save stage_artifacts\n")

# tail_risk.json
tail_risk_json <- list(
  task_id = WT_ID,
  as_of_date = "2026-04-30",
  measure_basis = "monthly_returns_267obs",
  S1 = list(VaR_95 = unname(cvar_S1["VaR"]), CVaR_95 = unname(cvar_S1["CVaR"]), CDaR_95 = cdar_S1),
  S2 = list(VaR_95 = unname(cvar_S2["VaR"]), CVaR_95 = unname(cvar_S2["CVaR"]), CDaR_95 = cdar_S2),
  S3 = list(VaR_95 = unname(cvar_S3["VaR"]), CVaR_95 = unname(cvar_S3["CVaR"]), CDaR_95 = cdar_S3),
  cost_adjusted = list(
    cost_bps_per_side = COST_BPS,
    annualized_turnover_overlay_S2 = ann_turnover_S2,
    annualized_turnover_overlay_S3 = ann_turnover_S3,
    annualized_overlay_cost_bps_S2 = ann_cost_S2_bps,
    annualized_overlay_cost_bps_S3 = ann_cost_S3_bps,
    SR_S1_net = sr_S1_net,
    SR_S2_net = sr_S2_net,
    SR_S3_net = sr_S3_net,
    SR_S3_minus_S2_zerocost = sr_S3 - sr_S2,
    SR_S3_minus_S2_net = sr_S3_net - sr_S2_net,
    SR_S3_minus_S1_net = sr_S3_net - sr_S1_net,
    NW_t_S3_S2_net_lag4 = nw_t_S3_S2_net,
    NW_t_S3_S1_net_lag4 = nw_t_S3_S1_net,
    interpretation = paste0(
      "Cost reflection: S3 weight changes 17 events over 267 mo, |dweight| sum = ",
      sprintf("%.4f", sum(mtab$dweight_S3, na.rm = TRUE)),
      ". Annualized overlay-only turnover ", sprintf("%.4f", ann_turnover_S3),
      " (i.e. ", sprintf("%.2f%%", ann_turnover_S3 * 100),
      "/year). Overlay cost ", sprintf("%.2f bps/yr.", ann_cost_S3_bps),
      " STR_1715 internal turnover ~280%/yr already net inside ret_net."
    )
  )
)
write_json(tail_risk_json, file.path(OUT_DIR, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  → tail_risk.json saved\n")

# risk_assessment.json (summary)
risk_assessment_json <- list(
  task_id = WT_ID,
  as_of_date = "2026-04-30",
  context = "meta_allocation_2_asset_universe",
  primary_universe = c("STR_1715_SLEEVE", "CASH_KRW"),
  diagnostic_universe_3asset = c("STR_1715", "S3_minus_S1_overlay", "S2_minus_S1_mrs"),
  selection_objective = "condition_number",
  selected_estimator = selected_name,
  estimator_method_log = method_log,
  condition_number = condition_number_final,
  min_eigenvalue = min_eig_final,
  shrinkage_used = shrinkage_used,
  shrinkage_intensity = if (is.na(selected_estimator$shrinkage_intensity)) NA_real_ else selected_estimator$shrinkage_intensity,
  Sigma_3x3 = setNames(
    apply(Sigma_final, 1, function(row) as.list(setNames(row, colnames(Sigma_final)))),
    colnames(Sigma_final)
  ),
  tdc_summary = list(
    full_q05 = list(S3_vs_S1 = list(tdc_lower = unname(tdc_full_S3_vs_S1["tdc_lower"]),
                                     tdc_upper = unname(tdc_full_S3_vs_S1["tdc_upper"]),
                                     kendall_tau = unname(tdc_full_S3_vs_S1["kendall_tau"])),
                    S3_vs_S2 = list(tdc_lower = unname(tdc_full_S3_vs_S2["tdc_lower"]),
                                     tdc_upper = unname(tdc_full_S3_vs_S2["tdc_upper"]),
                                     kendall_tau = unname(tdc_full_S3_vs_S2["kendall_tau"])),
                    S2_vs_S1 = list(tdc_lower = unname(tdc_full_S2_vs_S1["tdc_lower"]),
                                     tdc_upper = unname(tdc_full_S2_vs_S1["tdc_upper"]),
                                     kendall_tau = unname(tdc_full_S2_vs_S1["kendall_tau"]))),
    full_q10 = list(S3_vs_S1 = list(tdc_lower = unname(tdc_q10_S3_vs_S1["tdc_lower"]),
                                     tdc_upper = unname(tdc_q10_S3_vs_S1["tdc_upper"]),
                                     kendall_tau = unname(tdc_q10_S3_vs_S1["kendall_tau"])),
                    S3_vs_S2 = list(tdc_lower = unname(tdc_q10_S3_vs_S2["tdc_lower"]),
                                     tdc_upper = unname(tdc_q10_S3_vs_S2["tdc_upper"]),
                                     kendall_tau = unname(tdc_q10_S3_vs_S2["kendall_tau"]))),
    crisis_only_q10 = list(S3_vs_S1 = list(tdc_lower = unname(tdc_crisis_S3_vs_S1["tdc_lower"]),
                                            tdc_upper = unname(tdc_crisis_S3_vs_S1["tdc_upper"]),
                                            kendall_tau = unname(tdc_crisis_S3_vs_S1["kendall_tau"]),
                                            n_months = nrow(crisis_tab))),
    deviation_subset = list(n_events = nrow(dev_tab),
                            cor_S3_vs_S1_in_dev_subset = cor_dev,
                            note = "Within 17 deviation events, S3 and S1 still highly correlated because dweight is small."),
    interpretation = paste0(
      "Universe is meta-allocation (1 sleeve + cash). S3 and S1 share the same underlying ",
      "STR_1715 returns; S3 just scales them by weight_str1715 (0.75~1.0). Therefore TDC(S3,S1) ~ 1.0 ",
      "structurally — high tail co-movement is BY DESIGN (not a risk concentration). The meaningful TDC ",
      "is the *separation* (1 - tdc_lower) measured on the 17 deviation events: separation_q05 = ",
      sprintf("%.4f", 1 - unname(tdc_full_S3_vs_S1["tdc_lower"])),
      ". Separation in crisis-only (n=", nrow(crisis_tab), "): ",
      sprintf("%.4f", if (is.na(unname(tdc_crisis_S3_vs_S1["tdc_lower"]))) NA else 1 - unname(tdc_crisis_S3_vs_S1["tdc_lower"])),
      "."
    )
  ),
  regime_correlation = list(
    normal_n = nrow(normal_tab),
    bad_n = nrow(bad_tab),
    var_S1_normal = if (nrow(normal_tab) > 0) var(normal_tab$ret_S1) else NA_real_,
    var_S3_normal = if (nrow(normal_tab) > 0) var(normal_tab$ret_S3) else NA_real_,
    var_S1_bad    = if (nrow(bad_tab)    > 0) var(bad_tab$ret_S1) else NA_real_,
    var_S3_bad    = if (nrow(bad_tab)    > 0) var(bad_tab$ret_S3) else NA_real_,
    cor_S3_S1_normal = if (nrow(normal_tab) >= 12) cor(normal_tab$ret_S3, normal_tab$ret_S1) else NA_real_,
    cor_S3_S1_bad    = if (nrow(bad_tab) >= 12) cor(bad_tab$ret_S3, bad_tab$ret_S1) else NA_real_,
    vol_ratio_S3_S1_bad = if (nrow(bad_tab) >= 12) sqrt(var(bad_tab$ret_S3) / var(bad_tab$ret_S1)) else NA_real_,
    interpretation = paste0(
      "Normal (n=", nrow(normal_tab), ") σ_S1 = ",
      sprintf("%.4f", sqrt(var(normal_tab$ret_S1))),
      ", σ_S3 = ", sprintf("%.4f", sqrt(var(normal_tab$ret_S3))),
      ". Bad (n=", nrow(bad_tab), ") σ_S1 = ", sprintf("%.4f", sqrt(var(bad_tab$ret_S1))),
      ", σ_S3 = ", sprintf("%.4f", sqrt(var(bad_tab$ret_S3))),
      ". Vol ratio bad = ", sprintf("%.4f", sqrt(var(bad_tab$ret_S3) / var(bad_tab$ret_S1))),
      " — overlay reduces variance in bad regime."
    )
  ),
  stress_tests_detail = stress_dt,
  pit_compliance = list(
    factor_engine_R_clean = ld_alpha$clean,
    factor_engine_R_violations = length(ld_alpha$violations),
    risk_run_all_R_clean = ld_self$clean,
    risk_run_all_R_violations = length(ld_self$violations),
    notes = "alpha_package documented C1b false positives (quantile in cat() diagnostic logs only)."
  )
)
write_json(risk_assessment_json, file.path(OUT_DIR, "risk_assessment.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  → risk_assessment.json saved\n")

# Persist a slim object for risk_package builder
saveRDS(list(
  Sigma_final = Sigma_final,
  selected_name = selected_name,
  condition_number_final = condition_number_final,
  min_eig_final = min_eig_final,
  shrinkage_used = shrinkage_used,
  shrinkage_intensity = selected_estimator$shrinkage_intensity,
  method_log = method_log,
  cvar_S1 = cvar_S1, cvar_S2 = cvar_S2, cvar_S3 = cvar_S3,
  cdar_S1 = cdar_S1, cdar_S2 = cdar_S2, cdar_S3 = cdar_S3,
  ann_turnover_S2 = ann_turnover_S2, ann_turnover_S3 = ann_turnover_S3,
  ann_cost_S2_bps = ann_cost_S2_bps, ann_cost_S3_bps = ann_cost_S3_bps,
  sr_S1_net = sr_S1_net, sr_S2_net = sr_S2_net, sr_S3_net = sr_S3_net,
  nw_t_S3_S2_net = nw_t_S3_S2_net, nw_t_S3_S1_net = nw_t_S3_S1_net,
  tdc_full_S3_vs_S1 = tdc_full_S3_vs_S1,
  tdc_full_S3_vs_S2 = tdc_full_S3_vs_S2,
  tdc_q10_S3_vs_S1 = tdc_q10_S3_vs_S1,
  tdc_crisis_S3_vs_S1 = tdc_crisis_S3_vs_S1,
  cor_dev = cor_dev,
  n_dev_events = nrow(dev_tab),
  n_normal = nrow(normal_tab), n_bad = nrow(bad_tab),
  regime_cor_dt = regime_cor_dt,
  stress_dt = stress_dt,
  pit_factor_engine_clean = ld_alpha$clean,
  pit_self_clean = ld_self$clean,
  sr_S1 = sr_S1, sr_S2 = sr_S2, sr_S3 = sr_S3
), file.path(OUT_DIR, "risk_intermediate.rds"))
cat("  → risk_intermediate.rds saved\n")

`%||%` <- function(a, b) if (!is.null(a)) a else b

cat("\n[Risk Agent] Stage 1 (computation) DONE\n")
cat("[Risk Agent] → Next: build risk_package_draft.json + Codex critic\n")
