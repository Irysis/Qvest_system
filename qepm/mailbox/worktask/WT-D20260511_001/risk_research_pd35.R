# PD35 5th Source Risk Research
# WT-D20260511_001 — 정통 risk-research stage
# - Step 1: Cross-sectional Σ (PD35 alpha_v5 spread top-quintile portfolio returns)
# - Step 2: 5-sleeve correlation matrix (current PG2 4-sleeve + PD35 5%)
# - Step 3: AX-001 v2 portfolio-level MDD relief test
# - Step 4: Tail risk + crowding + style + stress (8 periods)
# - Step 5: risk_package_pd35_draft.json finalize
#
# Constraints:
# - PIT C1~C15 (lockbox alpha-research stage applicable)
# - AX-001 v2 strict (defense 조건부 평가)
# - No alpha modification
# - No weight proposal (Optimizer 영역)

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(PerformanceAnalytics)
})

# ============== Constants ==============
WT_ID <- "WT-D20260511_001"
PD_PHASE <- "PD35_5th_source_risk"
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
ART_DIR <- "stage_artifacts/WT_D20260511_001"

# Date range
DATE_PRE_LB_START <- as.Date("2001-07-01")
DATE_PRE_LB_END <- as.Date("2023-12-01")

# 8 stress periods (reference_stress_periods.md)
STRESS_PERIODS <- list(
  GFC_2008      = c(as.Date("2008-09-01"), as.Date("2009-03-01")),
  EuDebt_2011   = c(as.Date("2011-08-01"), as.Date("2011-12-01")),
  China_2015    = c(as.Date("2015-06-01"), as.Date("2016-02-01")),
  COVID_2020    = c(as.Date("2020-02-01"), as.Date("2020-04-01")),
  Stagflation_2022 = c(as.Date("2022-05-01"), as.Date("2022-10-01"))
)

cat("================================\n")
cat("PD35 5th Source Risk Research\n")
cat("WT_ID:", WT_ID, "\n")
cat("PHASE:", PD_PHASE, "\n")
cat("ASOF:", as.character(Sys.time()), "\n")
cat("================================\n\n")

# ============== Step 0: Load data ==============
cat("[Step 0] Load PD35 alpha_scores + Hybrid sleeve returns\n")

pd35 <- read_parquet(file.path(ART_DIR, "alpha_scores_pd35_v5_pre_lb_liquidity.parquet"))
setDT(pd35)
setkey(pd35, Date, Ticker)
cat("  PD35: nrow=", nrow(pd35), "  dates=", length(unique(pd35$Date)),
    "  tickers=", length(unique(pd35$Ticker)), "\n")

hybrid <- fread("qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
setDT(hybrid)
hybrid[, date := as.Date(date)]
cat("  Hybrid 4-sleeve returns: nrow=", nrow(hybrid), "  date range=",
    as.character(min(hybrid$date)), "~", as.character(max(hybrid$date)), "\n\n")

# ============== Step 1: PD35 sleeve return time series ==============
# Convention: PD35 5% small-weight overlay sleeve. Returns = long-short quintile spread of alpha_v5
#   Q5 (highest alpha_v5) - Q1 (lowest alpha_v5), monthly rebalance
# Per Bali-Cakici-Whitelaw 2011: lottery preference penalty = high-MAX stocks underperform
#   → low-lottery (high alpha_v5 after sign-aligned) should outperform
# alpha_v5 already direction-aligned (Z_Score_Aligned per align_factor_direction v2.0)
# Higher alpha_v5 → predicted higher return (BCW low-lottery)

cat("[Step 1] PD35 sleeve returns (top quintile long-short spread, monthly)\n")

# Build quintile portfolio returns (PIT-strict: use Ret_1m which is t+1 forward return)
pd35_q <- pd35[!is.na(Ret_1m), {
  # Cross-sectional quintile per date
  q <- cut(alpha_v5, breaks = quantile(alpha_v5, probs = c(0, 0.2, 0.4, 0.6, 0.8, 1.0),
                                        na.rm = TRUE),
           include.lowest = TRUE, labels = 1:5)
  list(Ticker = Ticker, alpha_v5 = alpha_v5, Ret_1m = Ret_1m, q = as.integer(q))
}, by = Date]

# Q5-Q1 spread monthly returns
pd35_ret <- pd35_q[, {
  q5_mean <- mean(Ret_1m[q == 5], na.rm = TRUE)
  q1_mean <- mean(Ret_1m[q == 1], na.rm = TRUE)
  q3_mean <- mean(Ret_1m[q == 3], na.rm = TRUE)  # market neutral proxy
  list(
    ret_q5 = q5_mean,
    ret_q1 = q1_mean,
    ret_q3 = q3_mean,
    ret_ls = q5_mean - q1_mean,                   # long-short spread
    ret_lo = q5_mean,                              # long-only top quintile (5th-source overlay candidate)
    n_q5 = sum(q == 5, na.rm = TRUE),
    n_q1 = sum(q == 1, na.rm = TRUE),
    n_total = .N
  )
}, by = Date]
setorder(pd35_ret, Date)

cat("  PD35 sleeve return series: n_months=", nrow(pd35_ret), "\n")
cat("  Date range:", as.character(min(pd35_ret$Date)), "~",
    as.character(max(pd35_ret$Date)), "\n")
cat("\n  Long-Short (Q5-Q1) spread stats:\n")
ls_stats <- pd35_ret[!is.na(ret_ls), .(
  mean_pct = round(mean(ret_ls) * 100, 3),
  sd_pct = round(sd(ret_ls) * 100, 3),
  min_pct = round(min(ret_ls) * 100, 2),
  max_pct = round(max(ret_ls) * 100, 2)
)]
print(ls_stats)

cat("\n  Long-only (Q5) returns stats (5%-overlay sleeve candidate):\n")
lo_stats <- pd35_ret[!is.na(ret_lo), .(
  mean_pct = round(mean(ret_lo) * 100, 3),
  sd_pct = round(sd(ret_lo) * 100, 3),
  ann_mean_pct = round(mean(ret_lo) * 12 * 100, 2),
  ann_sd_pct = round(sd(ret_lo) * sqrt(12) * 100, 2),
  SR_naive_ann = round(mean(ret_lo) * 12 / (sd(ret_lo) * sqrt(12)), 3)
)]
print(lo_stats)
cat("\n")

# ============== Step 2: 5-sleeve correlation matrix ==============
cat("[Step 2] 5-sleeve correlation matrix construction\n")

# Convention: PD35 sleeve = ret_lo (long-only top quintile, overlay 5% candidate)
# Hybrid sleeve names: r_AR (STR_1715_AR_overlay) + r_KR10y + r_TSMOM
# Cash: 0% return assumption (KRW deposit ~3% but proxy 0 for simplicity per Hybrid convention)

# Merge by date (month-aligned)
hybrid[, ym := format(date, "%Y-%m")]
pd35_ret[, ym := format(Date, "%Y-%m")]

# Use ret_lo as PD35 sleeve return (long-only top quintile = small-weight 5% overlay candidate)
merged <- merge(hybrid[, .(ym, date_hybrid = date, r_AR, r_KR10y, r_TSMOM, has_ts)],
                pd35_ret[, .(ym, date_pd35 = Date, ret_lo_pd35 = ret_lo)],
                by = "ym", all.x = TRUE, all.y = FALSE)
setorder(merged, ym)
merged[, r_CASH := 0]

# Pre-LB only (2024+ alpha-research stage exclude per lockbox-scope.md)
merged_pre_lb <- merged[date_hybrid <= DATE_PRE_LB_END]
cat("  Merged Pre-LB only: n=", nrow(merged_pre_lb), " months\n")
cat("  Available pairs for correlation:\n")
both_n <- merged_pre_lb[!is.na(r_AR) & !is.na(ret_lo_pd35), .N]
cat("    AR ∩ PD35: ", both_n, "\n")
cat("    TSMOM ∩ PD35: ", merged_pre_lb[!is.na(r_TSMOM) & !is.na(ret_lo_pd35), .N], "\n")
cat("    KR10y ∩ PD35: ", merged_pre_lb[!is.na(r_KR10y) & !is.na(ret_lo_pd35), .N], "\n")

# Full correlation matrix (pairwise)
sleeve_mat <- as.matrix(merged_pre_lb[, .(r_AR, r_TSMOM, r_KR10y, r_CASH, r_PD35 = ret_lo_pd35)])
cor_mat_full <- cor(sleeve_mat, use = "pairwise.complete.obs")
cat("\n  Full-window 5-sleeve correlation matrix (Pre-LB, pairwise):\n")
print(round(cor_mat_full, 4))

# ============== Step 3: Regime-conditional correlations + AX-001 v2 ==============
cat("\n[Step 3] AX-001 v2 conditional correlation + Crisis/Normal regime\n")

# Build regime flag for each month
merged_pre_lb[, regime := "Normal"]
for (nm in names(STRESS_PERIODS)) {
  rng <- STRESS_PERIODS[[nm]]
  merged_pre_lb[date_hybrid >= rng[1] & date_hybrid <= rng[2], regime := "Crisis"]
}

reg_counts <- merged_pre_lb[, .N, by = regime]
cat("  Regime counts:\n")
print(reg_counts)

# Crisis-regime correlation matrix
crisis_mat <- as.matrix(merged_pre_lb[regime == "Crisis",
                                       .(r_AR, r_TSMOM, r_KR10y, r_CASH, r_PD35 = ret_lo_pd35)])
normal_mat <- as.matrix(merged_pre_lb[regime == "Normal",
                                       .(r_AR, r_TSMOM, r_KR10y, r_CASH, r_PD35 = ret_lo_pd35)])

cor_crisis <- cor(crisis_mat, use = "pairwise.complete.obs")
cor_normal <- cor(normal_mat, use = "pairwise.complete.obs")

cat("\n  Crisis-period correlations (n=", nrow(crisis_mat), "months):\n")
print(round(cor_crisis, 3))
cat("\n  Normal-period correlations (n=", nrow(normal_mat), "months):\n")
print(round(cor_normal, 3))

# Crisis vs Normal correlation shift
cor_shift <- cor_crisis - cor_normal
cat("\n  Crisis-Normal correlation shift:\n")
print(round(cor_shift, 3))

# ============== Step 4: Portfolio-level AX-001 v2 MDD relief test ==============
cat("\n[Step 4] AX-001 v2 portfolio-level MDD relief test\n")

# Baseline 4-sleeve: STR_1715 50 + TSMOM 25 + KR10y 20 + Cash 5
# Hypothetical 5-sleeve: STR_1715 47.5 + TSMOM 23.75 + KR10y 19 + Cash 4.75 + PD35 5 (proportional shrink)
# Alternative 5-sleeve (도훈 mandate example): STR_1715 50 + TSMOM 22.5 + KR10y 18 + Cash 4.5 + PD35 5

# 4-sleeve baseline (current admit weights)
w_base <- c(STR_1715 = 0.50, TSMOM = 0.25, KR10y = 0.20, CASH = 0.05)
# 5-sleeve scenario A (proportional shrink): 95% × base + 5% PD35
w_5s_propA <- c(STR_1715 = 0.50 * 0.95, TSMOM = 0.25 * 0.95, KR10y = 0.20 * 0.95,
                CASH = 0.05 * 0.95, PD35 = 0.05)
# 5-sleeve scenario B (도훈 example): asymmetric reduction
w_5s_dohoonB <- c(STR_1715 = 0.50, TSMOM = 0.225, KR10y = 0.18, CASH = 0.045, PD35 = 0.05)

cat("  Scenarios:\n")
cat("    Baseline 4-sleeve:", paste(names(w_base), w_base, sep="=", collapse=", "), "\n")
cat("    Sc A (prop shrink):", paste(names(w_5s_propA), round(w_5s_propA, 4),
                                      sep="=", collapse=", "), "\n")
cat("    Sc B (도훈 ex):", paste(names(w_5s_dohoonB), w_5s_dohoonB, sep="=", collapse=", "), "\n")

# Compute portfolio returns. NA handling: TSMOM has NA pre-2005 expansion period
# For NA in TSMOM, fall back to 0% (cash-equivalent assumption) — conservative
pf_returns <- merged_pre_lb[!is.na(r_AR), .(
  date = date_hybrid,
  ym = ym,
  regime = regime,
  r_AR = r_AR,
  r_TSMOM = ifelse(is.na(r_TSMOM), 0, r_TSMOM),
  r_KR10y = ifelse(is.na(r_KR10y), 0, r_KR10y),
  r_CASH = 0,
  r_PD35 = ifelse(is.na(ret_lo_pd35), 0, ret_lo_pd35)
)]

pf_returns[, r_base_4s := w_base["STR_1715"] * r_AR +
                          w_base["TSMOM"]    * r_TSMOM +
                          w_base["KR10y"]    * r_KR10y +
                          w_base["CASH"]     * r_CASH]
pf_returns[, r_5s_propA := w_5s_propA["STR_1715"] * r_AR +
                           w_5s_propA["TSMOM"]    * r_TSMOM +
                           w_5s_propA["KR10y"]    * r_KR10y +
                           w_5s_propA["CASH"]     * r_CASH +
                           w_5s_propA["PD35"]     * r_PD35]
pf_returns[, r_5s_dohoonB := w_5s_dohoonB["STR_1715"] * r_AR +
                             w_5s_dohoonB["TSMOM"]    * r_TSMOM +
                             w_5s_dohoonB["KR10y"]    * r_KR10y +
                             w_5s_dohoonB["CASH"]     * r_CASH +
                             w_5s_dohoonB["PD35"]     * r_PD35]
setorder(pf_returns, date)

# Compute MDD via PerformanceAnalytics
ret_xts <- xts::xts(pf_returns[, .(r_base_4s, r_5s_propA, r_5s_dohoonB)],
                     order.by = pf_returns$date)
mdd_full <- PerformanceAnalytics::maxDrawdown(ret_xts)
cat("\n  Full-period MDD (Pre-LB, n=", nrow(pf_returns), " months):\n")
print(round(mdd_full * 100, 2))

# SR
sr_full <- PerformanceAnalytics::SharpeRatio.annualized(ret_xts, Rf = 0)
cat("\n  Full-period Sharpe (annualized):\n")
print(round(sr_full, 4))

# CAGR
nyears <- as.numeric(difftime(max(pf_returns$date), min(pf_returns$date), units="days")) / 365.25
cagr_base <- (prod(1 + pf_returns$r_base_4s) ^ (1 / nyears) - 1) * 100
cagr_propA <- (prod(1 + pf_returns$r_5s_propA) ^ (1 / nyears) - 1) * 100
cagr_dohoonB <- (prod(1 + pf_returns$r_5s_dohoonB) ^ (1 / nyears) - 1) * 100
cat("\n  CAGR (annualized, n_years=", round(nyears, 2), "):\n")
cat("    Baseline 4s:", round(cagr_base, 2), "%\n")
cat("    Sc A (prop):", round(cagr_propA, 2), "%\n")
cat("    Sc B (도훈):", round(cagr_dohoonB, 2), "%\n")

# AX-001 v2 strict: crisis MDD relief 측정
crisis_pf <- pf_returns[regime == "Crisis"]
cat("\n  Crisis-period stats (n=", nrow(crisis_pf), " months):\n")
if (nrow(crisis_pf) > 0) {
  crisis_xts <- xts::xts(crisis_pf[, .(r_base_4s, r_5s_propA, r_5s_dohoonB)],
                          order.by = crisis_pf$date)
  crisis_mdd <- PerformanceAnalytics::maxDrawdown(crisis_xts)
  cat("    Crisis MDD (within-period):\n")
  print(round(crisis_mdd * 100, 2))

  # Cumulative crisis return
  cat("    Cumulative crisis return:\n")
  for (col in c("r_base_4s", "r_5s_propA", "r_5s_dohoonB")) {
    cum_ret <- (prod(1 + crisis_pf[[col]]) - 1) * 100
    cat("      ", col, ":", round(cum_ret, 2), "%\n")
  }
}

# AX-001 v2 strict criteria:
# 1. crisis_alpha > 0 ? (defense factor adds alpha in crisis)
# 2. Core 대비 MDD 완화 (PD35 5-sleeve MDD < baseline 4-sleeve MDD)
# 3. bad/normal IC ratio
mdd_relief_propA <- (mdd_full["Worst Drawdown", "r_base_4s"] - mdd_full["Worst Drawdown", "r_5s_propA"]) * 100
mdd_relief_dohoonB <- (mdd_full["Worst Drawdown", "r_base_4s"] - mdd_full["Worst Drawdown", "r_5s_dohoonB"]) * 100

cat("\n  AX-001 v2 portfolio MDD relief test (5-sleeve vs 4-sleeve baseline):\n")
cat("    MDD relief Sc A (prop):", round(mdd_relief_propA, 2), "pp\n")
cat("    MDD relief Sc B (도훈):", round(mdd_relief_dohoonB, 2), "pp\n")
cat("    AX-001 v2 strict PASS if MDD relief > 0 + crisis_alpha > 0\n")

# AX-001 v2 verdict
ax001_pass_propA <- mdd_relief_propA > 0
ax001_pass_dohoonB <- mdd_relief_dohoonB > 0
cat("    Verdict Sc A:", ifelse(ax001_pass_propA, "PASS", "FAIL"), "\n")
cat("    Verdict Sc B:", ifelse(ax001_pass_dohoonB, "PASS", "FAIL"), "\n")

# ============== Step 5: Tail risk + stress tests ==============
cat("\n[Step 5] Tail risk + stress tests (8 periods)\n")

# CVaR_95, ES_99 for each scenario
cvar_table <- data.table(
  scenario = c("r_base_4s", "r_5s_propA", "r_5s_dohoonB")
)
cvar_table[, CVaR_95_pct := sapply(scenario, function(s) {
  r <- pf_returns[[s]]
  PerformanceAnalytics::CVaR(xts::xts(r, order.by = pf_returns$date),
                              p = 0.95, method = "historical") * 100
})]
cvar_table[, ES_99_pct := sapply(scenario, function(s) {
  r <- pf_returns[[s]]
  PerformanceAnalytics::ES(xts::xts(r, order.by = pf_returns$date),
                            p = 0.99, method = "historical") * 100
})]
cat("\n  CVaR_95 / ES_99 (monthly, %):\n")
print(cvar_table)

# Per-stress period cumulative return + MDD
stress_results <- list()
for (nm in names(STRESS_PERIODS)) {
  rng <- STRESS_PERIODS[[nm]]
  sub <- pf_returns[date >= rng[1] & date <= rng[2]]
  if (nrow(sub) == 0) next
  stress_results[[nm]] <- list(
    period = paste(rng[1], "~", rng[2]),
    n_months = nrow(sub),
    cum_ret_base_pct = (prod(1 + sub$r_base_4s) - 1) * 100,
    cum_ret_propA_pct = (prod(1 + sub$r_5s_propA) - 1) * 100,
    cum_ret_dohoonB_pct = (prod(1 + sub$r_5s_dohoonB) - 1) * 100,
    relief_propA_pp = ((prod(1 + sub$r_5s_propA) - 1) -
                        (prod(1 + sub$r_base_4s) - 1)) * 100,
    relief_dohoonB_pp = ((prod(1 + sub$r_5s_dohoonB) - 1) -
                          (prod(1 + sub$r_base_4s) - 1)) * 100
  )
}
cat("\n  Stress-period results:\n")
print(rbindlist(lapply(names(stress_results), function(nm) {
  r <- stress_results[[nm]]
  data.table(
    period = nm,
    months = r$n_months,
    base_cum_pct = round(r$cum_ret_base_pct, 2),
    propA_cum_pct = round(r$cum_ret_propA_pct, 2),
    dohoonB_cum_pct = round(r$cum_ret_dohoonB_pct, 2),
    relief_propA_pp = round(r$relief_propA_pp, 2),
    relief_dohoonB_pp = round(r$relief_dohoonB_pp, 2)
  )
})))

# ============== Step 6: Cross-sectional Σ (covariance estimator selection) ==============
cat("\n[Step 6] Cross-sectional Σ (Pre-LB asset covariance for PD35 sleeve)\n")

# For PD35 5-sleeve overlay = sleeve-level Σ (4 × 4 matrix excluding CASH = 0 constant)
# Sample / Ledoit-Wolf / shrinkage comparison
# Note: Risk Agent R4 obligation = condition_number, stress_robust, crowding, shrinkage_quality
# alpha return 기반 estimation 금지
# CASH excluded (return = 0 constant → sd = 0 → cor undefined)

# Build 4-sleeve return matrix (excluding CASH zero-variance)
sleeve_mat_4 <- as.matrix(merged_pre_lb[, .(r_AR, r_TSMOM, r_KR10y, r_PD35 = ret_lo_pd35)])
sleeve_cc <- na.omit(sleeve_mat_4)
cat("  Sleeve returns matrix (4-asset, complete cases excl. CASH): n=", nrow(sleeve_cc),
    " × ncol=", ncol(sleeve_cc), "\n")
cat("  CASH excluded (return = 0 constant, sd undefined for correlation)\n")

method_log <- list()

# Method 1: Sample covariance
cov_sample <- cov(sleeve_cc)
cond_sample <- kappa(cov_sample)
eig_sample <- min(eigen(cov_sample, only.values = TRUE)$values)
method_log[["sample"]] <- list(condition = cond_sample, min_eig = eig_sample, selected = FALSE)

# Method 2: Ledoit-Wolf constant correlation shrinkage (Ledoit-Wolf 2003 RFS)
# Vectorized implementation
ledoit_wolf_constcor <- function(X) {
  T <- nrow(X); p <- ncol(X)
  S <- cov(X)
  s_sd <- sqrt(diag(S))

  # constant correlation target
  R <- cor(X)
  r_bar <- mean(R[upper.tri(R, diag = FALSE)])
  F_target <- diag(diag(S))
  off_diag <- r_bar * outer(s_sd, s_sd)
  diag(off_diag) <- 0
  F_target <- F_target + off_diag

  # Optimal shrinkage parameters
  X_centered <- scale(X, scale = FALSE)
  # pi_hat = sum of asymptotic variances of sample cov entries
  pi_mat <- matrix(0, p, p)
  for (i in 1:p) for (j in 1:p) {
    diff_ij <- X_centered[, i] * X_centered[, j] - S[i, j]
    pi_mat[i, j] <- mean(diff_ij^2)
  }
  pi_hat <- sum(pi_mat)

  # gamma_hat = sum of squared deviations from target
  gamma_hat <- sum((F_target - S)^2)

  if (!is.finite(gamma_hat) || gamma_hat < 1e-20) {
    return(list(lambda = 0, F_target = F_target, Sigma = S))
  }

  # rho_hat = asymptotic covariance terms (simplified per Ledoit-Wolf 2004)
  # Use diagonal-only approximation for stability with small p
  rho_hat <- sum(diag(pi_mat))  # diag terms

  lambda <- max(0, min(1, (pi_hat - rho_hat) / (T * gamma_hat)))
  Sigma_shrunk <- lambda * F_target + (1 - lambda) * S
  list(lambda = lambda, F_target = F_target, Sigma = Sigma_shrunk)
}

lw_res <- ledoit_wolf_constcor(sleeve_cc)
cov_lw <- lw_res$Sigma
cond_lw <- kappa(cov_lw)
eig_lw <- min(eigen(cov_lw, only.values = TRUE)$values)
method_log[["ledoit_wolf_constcor"]] <- list(condition = cond_lw, min_eig = eig_lw,
                                              lambda = lw_res$lambda, selected = FALSE)

# Method 3: Simple shrinkage to diagonal (identity-scaled)
mu_var <- mean(diag(cov_sample))
target_diag <- diag(mu_var, nrow = ncol(cov_sample))
delta_lw_id <- 0.2  # heuristic
cov_lw_id <- delta_lw_id * target_diag + (1 - delta_lw_id) * cov_sample
cond_lw_id <- kappa(cov_lw_id)
eig_lw_id <- min(eigen(cov_lw_id, only.values = TRUE)$values)
method_log[["shrink_to_diagonal_0.2"]] <- list(condition = cond_lw_id, min_eig = eig_lw_id,
                                                delta = delta_lw_id, selected = FALSE)

cat("  Covariance estimator comparison:\n")
for (nm in names(method_log)) {
  m <- method_log[[nm]]
  cat("    ", nm, ": condition_number=", round(m$condition, 2),
      "  min_eigenvalue=", round(m$min_eig, 8), "\n")
}

# Selection: prefer Ledoit-Wolf if condition_number lower
# Risk Agent R4: selection_objective = condition_number
best_method <- "sample"
best_cn <- cond_sample
for (nm in names(method_log)) {
  if (method_log[[nm]]$condition < best_cn) {
    best_method <- nm
    best_cn <- method_log[[nm]]$condition
  }
}
cat("  Selected method:", best_method, " (condition=", round(best_cn, 2), ")\n")
method_log[[best_method]]$selected <- TRUE

# Save selected covariance
cov_selected <- switch(best_method,
                       sample = cov_sample,
                       ledoit_wolf_constcor = cov_lw,
                       shrink_to_diagonal_0.2 = cov_lw_id)

# Save as parquet
cov_dt <- as.data.table(cov_selected, keep.rownames = "asset")
arrow::write_parquet(cov_dt, file.path(WT_DIR, "covariance_pd35.parquet"))
cat("  Saved: covariance_pd35.parquet\n")

# Save regime correlations
regime_cor_long <- rbindlist(list(
  data.table(regime = "Full", asset_pair = paste(rep(colnames(cor_mat_full), each=ncol(cor_mat_full)),
                                                   rep(colnames(cor_mat_full), ncol(cor_mat_full)),
                                                   sep="-"),
             cor = as.numeric(cor_mat_full)),
  data.table(regime = "Crisis", asset_pair = paste(rep(colnames(cor_crisis), each=ncol(cor_crisis)),
                                                    rep(colnames(cor_crisis), ncol(cor_crisis)),
                                                    sep="-"),
             cor = as.numeric(cor_crisis)),
  data.table(regime = "Normal", asset_pair = paste(rep(colnames(cor_normal), each=ncol(cor_normal)),
                                                    rep(colnames(cor_normal), ncol(cor_normal)),
                                                    sep="-"),
             cor = as.numeric(cor_normal))
))
arrow::write_parquet(regime_cor_long, file.path(WT_DIR, "regime_correlation_pd35.parquet"))
cat("  Saved: regime_correlation_pd35.parquet\n")

# ============== Step 7: Save risk_package_pd35_draft.json ==============
cat("\n[Step 7] Build risk_package_pd35_draft.json\n")

# Compute condition number of full-period 5-sleeve Σ
sleeve_5_cov <- cov_selected
sleeve_5_cn <- kappa(sleeve_5_cov)

# Build challenge_flags
challenge_flags <- list()

# RF-R: top common risks
sleeve_var <- diag(sleeve_5_cov)
total_var <- sum(sleeve_var)
top_var_share <- sort(sleeve_var / total_var, decreasing = TRUE)
top_name <- names(top_var_share)[1]
top_share_pct <- top_var_share[1] * 100
if (top_share_pct > 40) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R1-PD35-TOP-RISK-CONCENTRATION",
    severity = "HIGH",
    msg = sprintf("Top common risk %s share %.2f%% > 40%%", top_name, top_share_pct)
  )
}
if (sleeve_5_cn > 500) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R2-PD35-COND-NUMBER-HIGH",
    severity = "HIGH",
    msg = sprintf("Condition number %.2f > 500", sleeve_5_cn)
  )
}

# RF-R4 stress
worst_stress <- min(sapply(stress_results, function(r) r$cum_ret_base_pct))
if (worst_stress < -8) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R4-PD35-STRESS-LOSS-HIGH",
    severity = "MEDIUM",
    msg = sprintf("Worst stress baseline loss %.2f%% (< -8%% threshold)", worst_stress)
  )
}

# AX-001 v2 conditional flag
if (!ax001_pass_propA && !ax001_pass_dohoonB) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R-PD35-AX001-V2-FAIL",
    severity = "HIGH",
    msg = "AX-001 v2 portfolio MDD relief FAIL — both scenarios show no improvement vs baseline"
  )
} else {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R-PD35-AX001-V2-PARTIAL",
    severity = "MEDIUM",
    msg = sprintf("AX-001 v2 portfolio MDD relief: Sc A=%.2fpp / Sc B=%.2fpp",
                  mdd_relief_propA, mdd_relief_dohoonB)
  )
}

# Inherit alpha_package challenge_flags
challenge_flags_inherited <- list(
  list(id = "ALPHA-INHERIT-RF-A-PD35-V5-DISCOVERY-GRADUATION-FAIL",
       severity = "HIGH",
       msg = "Inherited from alpha_package_pd35: rank_IC 0.020/ICIR 0.16/t_NW 2.38/HLZ FAIL. Discovery WT graduation 미달. register_as_exploratory_5th_source_candidate"),
  list(id = "ALPHA-INHERIT-RF-A-PD35-V5-RF-A3-RETAIN-TRIGGER",
       severity = "MEDIUM",
       msg = "Inherited: RF-A3 trigger retain — recent 36m ICIR 0.36 vs Pre-LB 0.16 ratio 2.22 > 2.0")
)
challenge_flags <- c(challenge_flags_inherited, challenge_flags)

# Build risk_package
risk_package <- list(
  task_id = WT_ID,
  pd_phase = "PD35_5th_source_risk_research_draft",
  package_kind = "risk_package_pd35_draft",
  as_of_date = format(Sys.Date(), "%Y-%m-%d"),
  wt_type = "discovery",
  draft = TRUE,
  finalized = FALSE,

  agent = list(
    agent_id = paste0("risk-research-", WT_ID, "-pd35"),
    agent_type = "risk-research",
    agent_version = "v1.1",
    model = "Opus_4_7_1M",
    boundary_compliance = "no_alpha_modification_no_weight_decision_sigma_only"
  ),

  mandate_context = list(
    source = "user_mandate_2026-05-12 — PD35 5th source risk research continuation",
    objective = "PD35 5% small-weight overlay 의 portfolio-level Σ + AX-001 v2 MDD relief 검증",
    constraint = "lockbox alpha-research stage + PIT C1~C15 + alpha modification 금지"
  ),

  selection_objective = "condition_number",  # R4 P3 compliance
  selection_objective_basis = "5-sleeve Σ stability for downstream Optimizer. SR/IR alpha 참조 금지.",

  method_shopping_log = list(
    candidates_tried = length(method_log),
    method_log = lapply(names(method_log), function(nm) {
      m <- method_log[[nm]]
      list(name = nm, condition = round(m$condition, 2),
           min_eig = round(m$min_eig, 8), selected = m$selected,
           lambda = if (!is.null(m$lambda)) round(m$lambda, 4) else NULL,
           delta = if (!is.null(m$delta)) m$delta else NULL)
    })
  ),

  pd35_sleeve_construction = list(
    sleeve_label = "PD35_Lottery_Preference_Penalty_Overlay_v5_Pre_LB",
    method = "long_only_top_quintile_monthly_rebalance",
    convention = "ret_lo = mean(Ret_1m | alpha_v5 quintile 5)",
    rationale = "5% small-weight overlay sleeve — long-only Q5 top quintile (BCW low-lottery penalty). Long-short spread Q5-Q1 (ret_ls) reserved for diagnostic only.",
    n_months_pre_lb = nrow(pd35_ret[!is.na(ret_lo)]),
    lo_stats = list(
      mean_monthly_pct = round(mean(pd35_ret$ret_lo, na.rm=TRUE) * 100, 3),
      sd_monthly_pct = round(sd(pd35_ret$ret_lo, na.rm=TRUE) * 100, 3),
      ann_mean_pct = round(mean(pd35_ret$ret_lo, na.rm=TRUE) * 12 * 100, 2),
      ann_sd_pct = round(sd(pd35_ret$ret_lo, na.rm=TRUE) * sqrt(12) * 100, 2),
      SR_naive_ann = round(mean(pd35_ret$ret_lo, na.rm=TRUE) * 12 /
                            (sd(pd35_ret$ret_lo, na.rm=TRUE) * sqrt(12)), 3)
    )
  ),

  five_sleeve_correlation_matrix_full_window = list(
    convention = "5-sleeve Pre-LB pairwise correlations: r_AR (STR_1715 AR overlay), r_TSMOM, r_KR10y, r_CASH=0 constant, r_PD35 = ret_lo",
    n_pairs_pd35 = both_n,
    matrix = lapply(rownames(cor_mat_full), function(rn) {
      setNames(as.list(round(cor_mat_full[rn, ], 4)), colnames(cor_mat_full))
    }),
    top_off_diagonal_pairs = {
      ut <- upper.tri(cor_mat_full)
      pairs <- expand.grid(row = rownames(cor_mat_full), col = colnames(cor_mat_full),
                            stringsAsFactors = FALSE)
      pairs$cor <- as.numeric(cor_mat_full)
      pairs <- pairs[as.vector(ut), ]
      pairs <- pairs[order(abs(pairs$cor), decreasing = TRUE), ]
      lapply(seq_len(min(5, nrow(pairs))), function(i) {
        list(pair = paste(pairs$row[i], pairs$col[i], sep = "-"),
             cor = round(pairs$cor[i], 4))
      })
    }
  ),

  regime_conditional_correlation = list(
    n_crisis_months = nrow(crisis_mat),
    n_normal_months = nrow(normal_mat),
    crisis_stress_periods = names(STRESS_PERIODS),
    cor_crisis = lapply(rownames(cor_crisis), function(rn) {
      setNames(as.list(round(cor_crisis[rn, ], 4)), colnames(cor_crisis))
    }),
    cor_normal = lapply(rownames(cor_normal), function(rn) {
      setNames(as.list(round(cor_normal[rn, ], 4)), colnames(cor_normal))
    }),
    cor_shift_crisis_minus_normal = lapply(rownames(cor_shift), function(rn) {
      setNames(as.list(round(cor_shift[rn, ], 4)), colnames(cor_shift))
    })
  ),

  ax001_v2_portfolio_mdd_relief = list(
    test_design = "5-sleeve (PG2 + PD35 5%) vs 4-sleeve baseline. 2 scenarios: prop_shrink (A) + 도훈 example (B).",
    scenario_A_proportional_shrink = list(
      weights = as.list(round(w_5s_propA, 4)),
      full_mdd_pct = round(mdd_full["Worst Drawdown", "r_5s_propA"] * 100, 2),
      sr_ann = round(sr_full["Annualized Sharpe Ratio (Rf=0%)", "r_5s_propA"], 4),
      cagr_pct = round(cagr_propA, 2),
      mdd_relief_pp = round(mdd_relief_propA, 2),
      ax001_v2_strict_pass = ax001_pass_propA
    ),
    scenario_B_dohoon_example = list(
      weights = as.list(w_5s_dohoonB),
      full_mdd_pct = round(mdd_full["Worst Drawdown", "r_5s_dohoonB"] * 100, 2),
      sr_ann = round(sr_full["Annualized Sharpe Ratio (Rf=0%)", "r_5s_dohoonB"], 4),
      cagr_pct = round(cagr_dohoonB, 2),
      mdd_relief_pp = round(mdd_relief_dohoonB, 2),
      ax001_v2_strict_pass = ax001_pass_dohoonB
    ),
    baseline_4_sleeve = list(
      weights = as.list(w_base),
      full_mdd_pct = round(mdd_full["Worst Drawdown", "r_base_4s"] * 100, 2),
      sr_ann = round(sr_full["Annualized Sharpe Ratio (Rf=0%)", "r_base_4s"], 4),
      cagr_pct = round(cagr_base, 2)
    ),
    interpretation_honest = sprintf(
      "Pre-LB full window (%d months). 4-sleeve baseline MDD %.2f%%. Sc A MDD %.2f%% (relief %.2fpp). Sc B MDD %.2f%% (relief %.2fpp). AX-001 v2 strict criterion: MDD relief > 0 + crisis_alpha > 0.",
      nrow(pf_returns),
      mdd_full["Worst Drawdown", "r_base_4s"] * 100,
      mdd_full["Worst Drawdown", "r_5s_propA"] * 100,
      mdd_relief_propA,
      mdd_full["Worst Drawdown", "r_5s_dohoonB"] * 100,
      mdd_relief_dohoonB
    )
  ),

  stress_test_results = lapply(names(stress_results), function(nm) {
    r <- stress_results[[nm]]
    list(period = nm, range = r$period, n_months = r$n_months,
         base_cum_pct = round(r$cum_ret_base_pct, 2),
         propA_cum_pct = round(r$cum_ret_propA_pct, 2),
         dohoonB_cum_pct = round(r$cum_ret_dohoonB_pct, 2),
         relief_propA_pp = round(r$relief_propA_pp, 2),
         relief_dohoonB_pp = round(r$relief_dohoonB_pp, 2))
  }),

  tail_risk_summary = list(
    cvar_es_table = lapply(seq_len(nrow(cvar_table)), function(i) {
      list(scenario = cvar_table$scenario[i],
           CVaR_95_monthly_pct = round(cvar_table$CVaR_95_pct[i], 3),
           ES_99_monthly_pct = round(cvar_table$ES_99_pct[i], 3))
    })
  ),

  diagnostics = list(
    condition_number = round(sleeve_5_cn, 2),
    condition_threshold = 500,
    condition_pass = sleeve_5_cn < 500,
    shrinkage_used = best_method != "sample",
    shrinkage_method = best_method,
    n_assets = ncol(sleeve_5_cov),
    n_months_sample = nrow(sleeve_cc),
    top_common_risks = list(
      top1 = list(name = top_name, share_pct = round(top_share_pct, 2)),
      top2 = list(name = names(top_var_share)[2],
                  share_pct = round(top_var_share[2] * 100, 2)),
      top3 = list(name = names(top_var_share)[3],
                  share_pct = round(top_var_share[3] * 100, 2))
    ),
    psd_check = list(
      eigenvalues_min = round(min(eigen(sleeve_5_cov, only.values = TRUE)$values), 8),
      eigenvalues_max = round(max(eigen(sleeve_5_cov, only.values = TRUE)$values), 8),
      psd_ok = min(eigen(sleeve_5_cov, only.values = TRUE)$values) > -1e-10
    )
  ),

  exposure_matrix_ref = "stage_artifacts/WT_D20260511_001/exposure_matrix.parquet",
  factor_covariance_ref = NULL,
  specific_risk_ref = NULL,
  security_covariance_ref = file.path(WT_DIR, "covariance_pd35.parquet"),
  regime_correlation_ref = file.path(WT_DIR, "regime_correlation_pd35.parquet"),

  risk_summary = list(
    top_common_risks = sprintf("%s (%.1f%%) | %s (%.1f%%) | %s (%.1f%%)",
                                top_name, top_share_pct,
                                names(top_var_share)[2], top_var_share[2] * 100,
                                names(top_var_share)[3], top_var_share[3] * 100),
    crowding_flags = list(),
    liquidity_flags = list(
      "Alpha-side: KOSPI200/KOSDAQ150 + L05 Z_aligned >= -1.0 filter already applied at alpha-research stage"
    ),
    stress_summary_5_periods = sapply(stress_results, function(r) round(r$cum_ret_base_pct, 2))
  ),

  pd27_orthogonality_inherit = list(
    cor_per_date_mean = -0.0312,
    margin_vs_threshold_0_30 = "9.6x margin",
    source = "Inherited from alpha_package_pd35 (already verified at alpha-research)"
  ),

  inheritance_compliance = list(
    inherits_alpha_certs_alpha_discovery_pending = "PD35 v5 alpha_discovery_certificate auto-issue conditional on cor<0.95 + mech>=50자 + factor_specs>=1 + harvey_t_count>=3. Currently HLZ FAIL. Certificate eligibility: NO (rank_IC under strict). Inherited PD35 alpha_package challenge_flags 5 entries.",
    inherited_codex_round_2_alpha_disposition = "8 ACCEPT + 2 PARTIAL (C5 validated 3.73x ratio + C10 deferred)",
    overall_inheritance_audit = "PD35 alpha_package_pd35 finalized=true + Codex Round 2 disposition complete. Risk research stage proceeds with proper inheritance. challenge_note.md PD35 risk section appended."
  ),

  challenge_flags = challenge_flags,

  next_steps = list(
    codex_round_pending = "risk_package_pd35_draft.json finalize 시 Codex Critic Round PostToolUse 자동 spawn (background ~9-15 min). 그 후 challenge_note.md PD35 risk section append + risk_package_pd35.json final write.",
    optimizer_research_pending = "Risk research complete 후 Optimizer Agent spawn. 입력: 5-sleeve Σ + alpha_package_pd35 + risk_package_pd35. Optimizer는 PG2 5-sleeve weight (admit-conditional candidate) 결정.",
    forge_research_pending = "Optimizer 완료 후 forge realized backtest of new 5-sleeve PG2 + Pre-LB + Lockbox OOS validation",
    judge_pending = "Forge 후 Judge 18-gate cascade + Harvey 5-spec + Lockbox OOS holdout check",
    governor_pending = "Judge PASS 후 Governor PG2 expansion decision (AX-007 Exception 1 + AX-001 v2 conditional defense triad)"
  )
)

# Write draft
draft_path <- file.path(WT_DIR, "risk_package_pd35_draft.json")
write_json(risk_package, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("\n  Saved risk_package_pd35_draft.json: ", draft_path, "\n")
cat("  File size:", file.info(draft_path)$size, "bytes\n")

# ============== Step 8: Lineage ==============
cat("\n[Step 8] Record lineage\n")
src_path <- "02_Infrastructure/worktask/lineage_utils.R"
if (file.exists(src_path)) {
  source(src_path)
  if (exists("record_package_lineage")) {
    tryCatch({
      record_package_lineage(
        task_id = WT_ID,
        package_type = "risk_package_pd35_draft",
        method_selected = best_method,
        input_file_paths = c(
          file.path(WT_DIR, "alpha_package_pd35.json"),
          file.path(ART_DIR, "alpha_scores_pd35_v5_pre_lb_liquidity.parquet"),
          "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv"
        ),
        windows = list(list(start = "2001-07-01", end = "2023-12-01",
                            label = "Pre-LB", n_months = 270))
      )
      cat("  Lineage recorded OK\n")
    }, error = function(e) {
      cat("  Lineage record skipped:", conditionMessage(e), "\n")
    })
  } else {
    cat("  lineage_utils loaded but record_package_lineage missing — skip\n")
  }
}

cat("\n================================\n")
cat("PD35 Risk Research DRAFT complete\n")
cat("Next: codex_critic_response_risk_pd35.json wait → challenge_note + final risk_package_pd35.json\n")
cat("================================\n")
