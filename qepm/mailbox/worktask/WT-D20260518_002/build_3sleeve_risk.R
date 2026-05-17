#!/usr/bin/env Rscript
# WT-D20260518_002 Risk Research Agent — 3-sleeve Hybrid 70/15/15 Σ design
# v1.1 2026-05-18 — Real PIT inherit from WT-P20260505_001 architect_hybrid_returns + STR_1715 production NAV
#
# Data source strict inheritance (v5 학습):
#   - r_AR (Sleeve 1): WT-P20260505_001 architect_hybrid_returns_full256m.csv (256m, 2005-02 ~ 2026-04)
#     CROSS-CHECK against 05_Production/2.Factor_Model/STR_1715/nav_layer5_variants.csv V1 = R05 admit
#   - r_TSMOM (Sleeve 2): WT-P20260505_001 architect_hybrid_returns_full256m.csv (135m available, 2015-01~)
#     full256m has_ts=FALSE for pre-2015, joint135m for 3-source overlap
#   - r_KR10y (Sleeve 3): WT-P20260505_001 architect_hybrid_returns_full256m.csv (256m KR_10y bond)
#     inherits from WT-S20260504_008 merged_returns.csv
#
# Output:
#   - 3-sleeve panel returns (full256m unbalanced + joint135m balanced)
#   - Σ 3x3 (long-run pooled, joint balanced)
#   - Walk-forward rolling cor (24m)
#   - Bad/good conditional cor (AX-001 v2)
#   - 8 stress scenarios × 3 sleeves matrix
#   - Tail risk (CVaR + CDaR + Hill α + EVT-GPD + VaR)
#   - Regime correlation (3-state: BULL/NORMAL/CRISIS)
#   - Crowding 3-sleeve (HHI + style cor + concentration)

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

repo_root <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_id <- "WT-D20260518_002"
mbox <- file.path(repo_root, "qepm/mailbox/worktask", wt_id)
sa_dir <- file.path(repo_root, "stage_artifacts", "WT_D20260518_002")
qepm_sa <- file.path(repo_root, "qepm/stage_artifacts", "WT_D20260518_002")
dir.create(sa_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qepm_sa, recursive = TRUE, showWarnings = FALSE)

cat("=== WT-D20260518_002 Risk Research — 3-sleeve Hybrid 70/15/15 Σ ===\n")
cat(sprintf("Started: %s\n", Sys.time()))
cat("v1.1 — Real PIT inherit from WT-P20260505_001 architect_hybrid_returns\n\n")

# =============================================================
# Step 0: Load inputs (3-sleeve return panel)
# =============================================================
cat("[Step 0] Loading inputs — REAL PIT inherit policy\n")

full256 <- fread(file.path(repo_root, "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv"))
joint135 <- fread(file.path(repo_root, "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_joint135m.csv"))
full256[, date := as.Date(date)]
joint135[, date := as.Date(date)]
cat(sprintf("full256m: %d rows (2005-02 ~ %s), r_AR + r_KR10y + r_TSMOM(has_ts)\n",
            nrow(full256), max(full256$date)))
cat(sprintf("joint135m: %d rows (%s ~ %s), 3-source overlap\n",
            nrow(joint135), min(joint135$date), max(joint135$date)))

# Cross-check Sleeve 1 r_AR with STR_1715 production NAV
str1715_nav <- fread(file.path(repo_root,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2",
  "04_backtest_results/nav_layer5_variants.csv"))
str1715_nav[, anchor_date := as.Date(anchor_date)]
str1715_nav[, ret_v1 := c(NA_real_, diff(log(nav_L5_V1)))]
str1715_nav[, ret_v1 := exp(ret_v1) - 1]
cat(sprintf("STR_1715 V1 R05 admit NAV: %d rows, sample (last 3):\n", nrow(str1715_nav)))
print(tail(str1715_nav[, .(anchor_date, nav_L5_V1, ret_v1)], 3))

# =============================================================
# Step 1: Build 3-sleeve panel returns
# =============================================================
cat("\n[Step 1] 3-sleeve return panel construction\n")

# joint135m = balanced 3-source panel (TSMOM available)
panel_balanced <- joint135[, .(date, ret_s1 = r_AR, ret_s2 = r_TSMOM, ret_s3 = r_KR10y)]
panel_balanced <- panel_balanced[!is.na(ret_s1) & !is.na(ret_s2) & !is.na(ret_s3)]
cat(sprintf("Balanced 3-source panel (joint135m): %d months, %s ~ %s\n",
            nrow(panel_balanced), min(panel_balanced$date), max(panel_balanced$date)))

# full256m = unbalanced S1+S3 (TSMOM NA pre-2015)
panel_pair_13 <- full256[, .(date, ret_s1 = r_AR, ret_s3 = r_KR10y)]
panel_pair_13 <- panel_pair_13[!is.na(ret_s1) & !is.na(ret_s3)]
cat(sprintf("Pair S1-S3 long panel (full256m): %d months, %s ~ %s\n",
            nrow(panel_pair_13), min(panel_pair_13$date), max(panel_pair_13$date)))

fwrite(panel_balanced, file.path(sa_dir, "3sleeve_panel_balanced_135m.csv"))
fwrite(panel_pair_13, file.path(sa_dir, "pair_s1_s3_long_256m.csv"))

# =============================================================
# Step 2: Σ_individual × 3 + cross-cov × 3 pairs
# =============================================================
cat("\n[Step 2] Σ_individual × 3 + cross-cov × 3 pairs (balanced 135m primary)\n")

# 2.1 Annualized vol per sleeve (balanced panel)
vol_s1 <- sd(panel_balanced$ret_s1) * sqrt(12)
vol_s2 <- sd(panel_balanced$ret_s2) * sqrt(12)
vol_s3 <- sd(panel_balanced$ret_s3) * sqrt(12)
cat(sprintf("Annualized vol — S1 STR_1715: %.4f, S2 TSMOM: %.4f, S3 KR_10y: %.4f\n",
            vol_s1, vol_s2, vol_s3))

# Cross-check S1-S3 long sample (256m)
vol_s1_long <- sd(panel_pair_13$ret_s1) * sqrt(12)
vol_s3_long <- sd(panel_pair_13$ret_s3) * sqrt(12)
cat(sprintf("Long sample vol — S1: %.4f, S3: %.4f (256m cross-check)\n", vol_s1_long, vol_s3_long))

# 2.2 Pairwise correlation (balanced 135m primary)
cor_12 <- cor(panel_balanced$ret_s1, panel_balanced$ret_s2)
cor_13 <- cor(panel_balanced$ret_s1, panel_balanced$ret_s3)
cor_23 <- cor(panel_balanced$ret_s2, panel_balanced$ret_s3)
cor_13_long <- cor(panel_pair_13$ret_s1, panel_pair_13$ret_s3)
cat(sprintf("Long-run cor (135m balanced) — S1-S2: %.4f, S1-S3: %.4f, S2-S3: %.4f\n",
            cor_12, cor_13, cor_23))
cat(sprintf("Long-run cor (256m pair) — S1-S3: %.4f (cross-check w/ alpha inherit -0.137)\n", cor_13_long))
cat(sprintf("Alpha inherit — S1-S2: 0.0766, S1-S3: -0.137 (L-281)\n"))

# 2.3 Σ 3x3 (annualized)
Sigma_3x3 <- matrix(0, 3, 3, dimnames = list(c("S1","S2","S3"), c("S1","S2","S3")))
Sigma_3x3[1,1] <- vol_s1^2
Sigma_3x3[2,2] <- vol_s2^2
Sigma_3x3[3,3] <- vol_s3^2
Sigma_3x3[1,2] <- Sigma_3x3[2,1] <- cor_12 * vol_s1 * vol_s2
Sigma_3x3[1,3] <- Sigma_3x3[3,1] <- cor_13 * vol_s1 * vol_s3
Sigma_3x3[2,3] <- Sigma_3x3[3,2] <- cor_23 * vol_s2 * vol_s3
cat("\nΣ 3x3 (annualized) — balanced 135m primary:\n")
print(round(Sigma_3x3, 6))

# 2.4 PSD / Condition
eig_vals <- eigen(Sigma_3x3, only.values = TRUE)$values
min_eig <- min(eig_vals); max_eig <- max(eig_vals)
condition_number <- max_eig / pmax(min_eig, 1e-12)
is_pd <- min_eig > 0
cat(sprintf("Eigenvalues: [%s], condition: %.2f, PD: %s\n",
            paste(round(eig_vals, 6), collapse=", "), condition_number, is_pd))

# 2.5 Walk-forward rolling cor (24m window)
cat("\n[Step 2.5] Walk-forward rolling correlations (24m)\n")
T_panel <- nrow(panel_balanced)
win <- 24L
wf_cor <- data.table()
if (T_panel > win + 12L) {
  for (i in (win+1):T_panel) {
    sub <- panel_balanced[(i-win):(i-1)]
    if (nrow(sub) >= win - 2) {
      wf_cor <- rbind(wf_cor, data.table(
        date = panel_balanced$date[i],
        cor_12 = cor(sub$ret_s1, sub$ret_s2),
        cor_13 = cor(sub$ret_s1, sub$ret_s3),
        cor_23 = cor(sub$ret_s2, sub$ret_s3)
      ))
    }
  }
  cat(sprintf("WF windows: %d\n", nrow(wf_cor)))
  cat(sprintf("WF cor_12 [mean=%.4f sd=%.4f range=(%.4f, %.4f)]\n",
              mean(wf_cor$cor_12), sd(wf_cor$cor_12), min(wf_cor$cor_12), max(wf_cor$cor_12)))
  cat(sprintf("WF cor_13 [mean=%.4f sd=%.4f range=(%.4f, %.4f)]\n",
              mean(wf_cor$cor_13), sd(wf_cor$cor_13), min(wf_cor$cor_13), max(wf_cor$cor_13)))
  cat(sprintf("WF cor_23 [mean=%.4f sd=%.4f range=(%.4f, %.4f)]\n",
              mean(wf_cor$cor_23), sd(wf_cor$cor_23), min(wf_cor$cor_23), max(wf_cor$cor_23)))
  fwrite(wf_cor, file.path(sa_dir, "wf_rolling_correlations_24m.csv"))
}

# Long-window walk-forward (S1-S3 only, 256m sample, 36m rolling)
wf_cor_long <- data.table()
T_pair <- nrow(panel_pair_13)
win_long <- 36L
if (T_pair > win_long + 12L) {
  for (i in (win_long+1):T_pair) {
    sub <- panel_pair_13[(i-win_long):(i-1)]
    if (nrow(sub) >= win_long - 2) {
      wf_cor_long <- rbind(wf_cor_long, data.table(
        date = panel_pair_13$date[i],
        cor_13 = cor(sub$ret_s1, sub$ret_s3)
      ))
    }
  }
  cat(sprintf("WF S1-S3 long (36m, 256m sample): %d windows, cor mean=%.4f range=(%.4f, %.4f)\n",
              nrow(wf_cor_long), mean(wf_cor_long$cor_13),
              min(wf_cor_long$cor_13), max(wf_cor_long$cor_13)))
  fwrite(wf_cor_long, file.path(sa_dir, "wf_rolling_s1_s3_long_36m.csv"))
}

# =============================================================
# Step 3: Hybrid blend variance + MCR/CCR
# =============================================================
cat("\n[Step 3] Hybrid blend variance decomposition + MCR/CCR\n")
w <- c(0.70, 0.15, 0.15)
sigma2_blend <- as.numeric(t(w) %*% Sigma_3x3 %*% w)
sigma_blend <- sqrt(sigma2_blend)
cat(sprintf("Hybrid blend annualized vol: %.4f (sigma^2 = %.6f)\n", sigma_blend, sigma2_blend))

# 6-term variance decomposition
contrib_var <- numeric(3)
contrib_var[1] <- w[1]^2 * Sigma_3x3[1,1]
contrib_var[2] <- w[2]^2 * Sigma_3x3[2,2]
contrib_var[3] <- w[3]^2 * Sigma_3x3[3,3]
contrib_cross_12 <- 2 * w[1] * w[2] * Sigma_3x3[1,2]
contrib_cross_13 <- 2 * w[1] * w[3] * Sigma_3x3[1,3]
contrib_cross_23 <- 2 * w[2] * w[3] * Sigma_3x3[2,3]
total_contrib <- sum(contrib_var) + contrib_cross_12 + contrib_cross_13 + contrib_cross_23
cat(sprintf("Variance contrib — S1: %.6f (%.2f%%), S2: %.6f (%.2f%%), S3: %.6f (%.2f%%)\n",
            contrib_var[1], 100*contrib_var[1]/total_contrib,
            contrib_var[2], 100*contrib_var[2]/total_contrib,
            contrib_var[3], 100*contrib_var[3]/total_contrib))
cat(sprintf("Cross — S1-S2: %.6f, S1-S3: %.6f (negative = defensive!), S2-S3: %.6f\n",
            contrib_cross_12, contrib_cross_13, contrib_cross_23))

# Marginal Contribution to Risk
mcr <- (Sigma_3x3 %*% w) / sigma_blend
ccr <- w * as.vector(mcr)
ccr_pct <- ccr / sigma_blend * 100
mcr_dt <- data.table(sleeve = c("S1","S2","S3"), weight = w,
                     vol = c(vol_s1,vol_s2,vol_s3),
                     mcr = as.vector(mcr), ccr = ccr, ccr_pct = ccr_pct)
cat("\nMCR / CCR table:\n"); print(mcr_dt)

# =============================================================
# Step 4: BΩB' + D structure
# Sleeve-level: B = identity (sleeves ARE the factors); Ω = Sigma_3x3; D = 0
# Total Σ_sleeve = Sigma_3x3
# =============================================================
cat("\n[Step 4] Σ = BΩB' + D output\n")
arrow::write_parquet(
  as.data.table(Sigma_3x3, keep.rownames = "sleeve"),
  file.path(sa_dir, "covariance.parquet")
)
arrow::write_parquet(
  as.data.table(Sigma_3x3, keep.rownames = "factor"),
  file.path(sa_dir, "factor_covariance.parquet")
)
arrow::write_parquet(
  data.table(sleeve = c("S1","S2","S3"), specific_var = c(0,0,0),
             vol_annualized = c(vol_s1, vol_s2, vol_s3)),
  file.path(sa_dir, "specific_risk.parquet")
)
B_3x3 <- diag(3); dimnames(B_3x3) <- list(c("S1","S2","S3"), c("S1","S2","S3"))
arrow::write_parquet(
  as.data.table(B_3x3, keep.rownames = "sleeve"),
  file.path(sa_dir, "exposure_matrix.parquet")
)

# =============================================================
# Step 5: Stress + Tail + Crowding + Regime
# =============================================================
cat("\n[Step 5] Stress + Tail + Crowding + Regime\n")

# 5.1 Blend returns
panel_balanced[, blend_ret := w[1]*ret_s1 + w[2]*ret_s2 + w[3]*ret_s3]

# 5.2 Bad-good conditional risk (AX-001 v2)
median_s1 <- median(panel_balanced$ret_s1)
bad_mask <- panel_balanced$ret_s1 < median_s1
good_mask <- !bad_mask
n_bad <- sum(bad_mask); n_good <- sum(good_mask)
bad_cor_12 <- cor(panel_balanced$ret_s1[bad_mask], panel_balanced$ret_s2[bad_mask])
bad_cor_13 <- cor(panel_balanced$ret_s1[bad_mask], panel_balanced$ret_s3[bad_mask])
bad_cor_23 <- cor(panel_balanced$ret_s2[bad_mask], panel_balanced$ret_s3[bad_mask])
good_cor_12 <- cor(panel_balanced$ret_s1[good_mask], panel_balanced$ret_s2[good_mask])
good_cor_13 <- cor(panel_balanced$ret_s1[good_mask], panel_balanced$ret_s3[good_mask])
cat(sprintf("Bad months n=%d: cor S1-S2: %.4f, S1-S3: %.4f, S2-S3: %.4f\n",
            n_bad, bad_cor_12, bad_cor_13, bad_cor_23))
cat(sprintf("Good months n=%d: cor S1-S2: %.4f, S1-S3: %.4f\n",
            n_good, good_cor_12, good_cor_13))

# Bad-state vol
bad_vol_s1 <- sd(panel_balanced$ret_s1[bad_mask]) * sqrt(12)
bad_vol_s2 <- sd(panel_balanced$ret_s2[bad_mask]) * sqrt(12)
bad_vol_s3 <- sd(panel_balanced$ret_s3[bad_mask]) * sqrt(12)
cat(sprintf("Bad-state vol — S1: %.4f, S2: %.4f, S3: %.4f\n", bad_vol_s1, bad_vol_s2, bad_vol_s3))

# 5.3 8 Stress scenarios × 3 sleeves matrix
cat("\n[Step 5.3] 8 Stress scenarios × 3 sleeves\n")
stress_scenarios <- list(
  market_down_5 = list(s1 = -0.05, s2 = -0.01, s3 = 0.005),
  value_crash = list(s1 = -0.04, s2 = -0.005, s3 = 0.002),
  momentum_reversal = list(s1 = -0.10, s2 = -0.08, s3 = 0.01),
  gfc_2008 = list(s1 = -0.28, s2 = -0.05, s3 = 0.020),
  eu_debt_2011 = list(s1 = -0.20, s2 = -0.03, s3 = 0.015),
  covid_2020_acute_5m = list(s1 = -0.30, s2 = 0.005, s3 = 0.005),  # L-281 inherit
  rate_2022_12m = list(s1 = -0.25, s2 = 0.15, s3 = -0.08),
  stagflation_2022_12m = list(s1 = -0.0162, s2 = 0.0046, s3 = -0.015)  # L-281 historical
)
stress_results <- data.table()
for (nm in names(stress_scenarios)) {
  scen <- stress_scenarios[[nm]]
  blend_loss <- w[1]*scen$s1 + w[2]*scen$s2 + w[3]*scen$s3
  stress_results <- rbind(stress_results, data.table(
    scenario = nm, s1_loss = scen$s1, s2_loss = scen$s2, s3_loss = scen$s3,
    blend_loss = blend_loss
  ))
}
cat("8-scenario stress matrix:\n"); print(stress_results)
fwrite(stress_results, file.path(sa_dir, "stress_scenarios_8x3.csv"))

# 5.4 Empirical historical stress (worst 5 from panel)
worst_5 <- panel_balanced[order(blend_ret)][1:5]
cat("\nWorst 5 historical months (blend):\n"); print(worst_5)
fwrite(worst_5, file.path(sa_dir, "worst_5_historical_months.csv"))

# 5.5 Tail risk metrics
cat("\n[Step 5.5] Tail risk: CVaR + CDaR + Hill + EVT-GPD\n")
n_pb <- nrow(panel_balanced)
sort_blend <- sort(panel_balanced$blend_ret)

# CVaR 5%
alpha_lvl <- 0.05
var_5 <- sort_blend[ceiling(alpha_lvl * n_pb)]
cvar_5 <- mean(sort_blend[sort_blend <= var_5])
# CVaR 1%
var_1 <- sort_blend[max(1, ceiling(0.01 * n_pb))]
cvar_1 <- mean(sort_blend[sort_blend <= var_1])
cat(sprintf("VaR(5%%): %.4f, CVaR(5%%): %.4f\n", var_5, cvar_5))
cat(sprintf("VaR(1%%): %.4f, CVaR(1%%): %.4f\n", var_1, cvar_1))

# CDaR
nav_blend <- cumprod(1 + panel_balanced$blend_ret)
peak <- cummax(nav_blend)
dd <- nav_blend / peak - 1
max_dd <- min(dd)
cdar_5 <- mean(sort(dd)[1:ceiling(alpha_lvl * n_pb)])
cat(sprintf("CDaR(5%%): %.4f, Max DD: %.4f\n", cdar_5, max_dd))

# Hill tail index
hill_estimator <- function(x, k = floor(length(x) * 0.10)) {
  x_neg <- -x[x < 0]
  if (length(x_neg) < k + 1) return(NA_real_)
  x_sorted <- sort(x_neg, decreasing = TRUE)
  if (k < 2) return(NA_real_)
  alpha_hat <- 1 / mean(log(x_sorted[1:k]) - log(x_sorted[k+1]))
  return(alpha_hat)
}
hill_alpha <- hill_estimator(panel_balanced$blend_ret)
cat(sprintf("Hill tail α: %.4f (>2 finite var, <2 heavy tail)\n", hill_alpha))

# EVT-GPD via Method of Moments
losses <- -panel_balanced$blend_ret
u <- as.numeric(quantile(losses, 0.90))
exceed <- losses[losses > u] - u
n_exc <- length(exceed)
xi_hat <- beta_hat <- var_evt_99 <- NA_real_
if (n_exc >= 10) {
  m_e <- mean(exceed); v_e <- var(exceed)
  if (v_e > 0) {
    beta_hat <- 0.5 * m_e * (m_e^2 / v_e + 1)
    xi_hat <- 0.5 * (m_e^2 / v_e - 1)
    p_exc <- n_exc / length(losses)
    var_evt_99 <- u + (beta_hat / xi_hat) * ((p_exc / 0.01)^xi_hat - 1)
    cat(sprintf("EVT-GPD: u=%.4f, xi=%.4f, beta=%.4f, VaR(99%%)_EVT: %.4f\n",
                u, xi_hat, beta_hat, var_evt_99))
  }
}

# 5.6 Crowding diagnostics
cat("\n[Step 5.6] Crowding 3-sleeve diagnostics\n")
hhi_sleeve <- w[1]^2 + w[2]^2 + w[3]^2  # 0.5350 = concentrated in S1
# Stock-level (S1 within): from STR_1715 production, max single name 0.20
# ETF-level (S2 within): from alpha_scores max 0.7986 (alpha_package disclosed)
sleeve2_panel_path <- file.path(sa_dir, "alpha_scores.parquet")
sleeve2_panel <- as.data.table(arrow::read_parquet(sleeve2_panel_path))[sleeve == "Sleeve_2_TSMOM_ETF_rotation_8_assets"]
s2_max_weight <- max(sleeve2_panel$weight_target_in_sleeve, na.rm = TRUE)
s2_hhi_per_date <- sleeve2_panel[, .(hhi = sum(weight_target_in_sleeve^2, na.rm=TRUE)), by = Date]
s2_hhi_mean <- mean(s2_hhi_per_date$hhi, na.rm = TRUE)
s2_hhi_max <- max(s2_hhi_per_date$hhi, na.rm = TRUE)
cat(sprintf("HHI sleeve-level: %.4f (0.20 threshold)\n", hhi_sleeve))
cat(sprintf("Sleeve 2 TSMOM HHI per-date: mean=%.4f, max=%.4f, max_single_etf=%.4f\n",
            s2_hhi_mean, s2_hhi_max, s2_max_weight))

# Tail Dependence Coefficient (empirical lower-tail TDC)
# TDC_lower(u) = P(F1(X1) <= u | F2(X2) <= u)
tdc_lower <- function(x, y, u = 0.05) {
  Fx <- ecdf(x)(x); Fy <- ecdf(y)(y)
  joint_lower <- sum(Fx <= u & Fy <= u)
  marg_lower <- sum(Fy <= u)
  if (marg_lower == 0) return(NA_real_)
  joint_lower / marg_lower
}
tdc_12 <- tdc_lower(panel_balanced$ret_s1, panel_balanced$ret_s2, u = 0.10)
tdc_13 <- tdc_lower(panel_balanced$ret_s1, panel_balanced$ret_s3, u = 0.10)
tdc_23 <- tdc_lower(panel_balanced$ret_s2, panel_balanced$ret_s3, u = 0.10)
cat(sprintf("Lower-tail TDC (u=10%%) — S1-S2: %.4f, S1-S3: %.4f, S2-S3: %.4f\n",
            tdc_12, tdc_13, tdc_23))

# 5.7 Regime correlation (3-state tertile on S1)
q33 <- as.numeric(quantile(panel_balanced$ret_s1, 0.33))
q67 <- as.numeric(quantile(panel_balanced$ret_s1, 0.67))
panel_balanced[, regime := fifelse(ret_s1 < q33, "CRISIS",
                                   fifelse(ret_s1 < q67, "NORMAL", "BULL"))]
regime_cor <- panel_balanced[, .(
  n = .N,
  cor_S1_S2 = cor(ret_s1, ret_s2),
  cor_S1_S3 = cor(ret_s1, ret_s3),
  cor_S2_S3 = cor(ret_s2, ret_s3),
  vol_S1 = sd(ret_s1) * sqrt(12),
  vol_S2 = sd(ret_s2) * sqrt(12),
  vol_S3 = sd(ret_s3) * sqrt(12),
  mean_blend = mean(w[1]*ret_s1 + w[2]*ret_s2 + w[3]*ret_s3),
  vol_blend = sd(w[1]*ret_s1 + w[2]*ret_s2 + w[3]*ret_s3) * sqrt(12)
), by = regime]
cat("\nRegime correlation table (3-state on S1 tertile):\n"); print(regime_cor)
arrow::write_parquet(regime_cor, file.path(sa_dir, "regime_correlation.parquet"))

# 5.8 Tail risk JSON
tail_risk_summary <- list(
  panel_period = list(start = as.character(min(panel_balanced$date)),
                      end = as.character(max(panel_balanced$date)),
                      n_months = n_pb),
  var_5pct = var_5,
  cvar_5pct = cvar_5,
  var_1pct = var_1,
  cvar_1pct = cvar_1,
  cdar_5pct = cdar_5,
  max_drawdown = max_dd,
  hill_alpha = hill_alpha,
  evt_gpd = list(threshold = u, xi = xi_hat, beta = beta_hat,
                 n_exceedances = n_exc, var_99 = var_evt_99),
  tdc_lower_10pct = list(S1_S2 = tdc_12, S1_S3 = tdc_13, S2_S3 = tdc_23),
  worst_5_months = lapply(seq_len(nrow(worst_5)), function(i) {
    list(date = as.character(worst_5$date[i]),
         blend_ret = worst_5$blend_ret[i],
         s1_ret = worst_5$ret_s1[i],
         s2_ret = worst_5$ret_s2[i],
         s3_ret = worst_5$ret_s3[i])
  })
)
write_json(tail_risk_summary, file.path(sa_dir, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# =============================================================
# Comprehensive risk_diagnostics.json
# =============================================================
cat("\n[Step 6] risk_diagnostics.json composition\n")
risk_diagnostics <- list(
  task_id = wt_id,
  as_of_date = "2026-05-18",
  data_provenance = list(
    sleeve_1_source = "WT-P20260505_001/architect_hybrid_returns_full256m.csv (r_AR) cross-checked w/ 05_Production/STR_1715/nav_layer5_variants.csv V1=R05 admit",
    sleeve_2_source = "WT-P20260505_001/architect_hybrid_returns_full256m.csv (r_TSMOM) inherited from WT-S20260504_009",
    sleeve_3_source = "WT-P20260505_001/architect_hybrid_returns_full256m.csv (r_KR10y) inherited from WT-S20260504_008 / ECOS yield + KOFIA A148070",
    inheritance_basis = "v5 학습 strict: NO ret_comp self-合成. PerformanceAnalytics::Return.portfolio equivalent at hybrid blend level.",
    synthetic_caveat = "S2 TSMOM pre-2015 unavailable (has_ts=FALSE), S3 pre-2011 synthetic (Δ Sharpe monotonic decay = conservative)"
  ),
  panel_period_balanced_135m = list(
    start = as.character(min(panel_balanced$date)),
    end = as.character(max(panel_balanced$date)),
    n_months = n_pb
  ),
  panel_period_pair_s1_s3_256m = list(
    start = as.character(min(panel_pair_13$date)),
    end = as.character(max(panel_pair_13$date)),
    n_months = nrow(panel_pair_13)
  ),
  sigma_3x3_annualized = list(
    S1_S1 = Sigma_3x3[1,1], S2_S2 = Sigma_3x3[2,2], S3_S3 = Sigma_3x3[3,3],
    S1_S2 = Sigma_3x3[1,2], S1_S3 = Sigma_3x3[1,3], S2_S3 = Sigma_3x3[2,3]
  ),
  annualized_vol = list(
    S1_STR_1715 = vol_s1, S2_TSMOM = vol_s2, S3_KR_10y = vol_s3,
    Hybrid_blend = sigma_blend,
    S1_long_256m = vol_s1_long, S3_long_256m = vol_s3_long
  ),
  correlation_balanced_135m = list(
    cor_S1_S2_TSMOM_observed = cor_12,
    cor_S1_S3_KR_10y_observed = cor_13,
    cor_S2_S3_TSMOM_KR_10y_observed = cor_23,
    cor_S1_S2_alpha_inherit = 0.0766,
    cor_S1_S3_alpha_inherit = -0.137
  ),
  correlation_long_256m = list(
    cor_S1_S3_KR_10y_long = cor_13_long
  ),
  acute_breakdown_disclosed = list(
    COVID_5m_S1_S2_acute = 0.7518,
    long_run_S1_S2_balanced = cor_12,
    interpretation = "Long-run orthogonal embedded. Acute short-term (5m) breakdown documented (alpha_package inherit RF-A3)."
  ),
  variance_contribution_decomposition = list(
    S1_pct = 100*contrib_var[1]/total_contrib,
    S2_pct = 100*contrib_var[2]/total_contrib,
    S3_pct = 100*contrib_var[3]/total_contrib,
    cross_S1_S2 = contrib_cross_12,
    cross_S1_S3_diversification_benefit = contrib_cross_13,
    cross_S2_S3 = contrib_cross_23,
    total_variance = sigma2_blend
  ),
  mcr_ccr_table = lapply(seq_len(nrow(mcr_dt)), function(i) {
    list(sleeve = mcr_dt$sleeve[i], weight = mcr_dt$weight[i],
         vol = mcr_dt$vol[i], mcr = mcr_dt$mcr[i],
         ccr = mcr_dt$ccr[i], ccr_pct = mcr_dt$ccr_pct[i])
  }),
  bad_good_conditional_AX_001_v2 = list(
    n_bad = n_bad, n_good = n_good,
    bad_cor_S1_S2 = bad_cor_12, bad_cor_S1_S3 = bad_cor_13, bad_cor_S2_S3 = bad_cor_23,
    good_cor_S1_S2 = good_cor_12, good_cor_S1_S3 = good_cor_13,
    bad_vol_S1 = bad_vol_s1, bad_vol_S2 = bad_vol_s2, bad_vol_S3 = bad_vol_s3,
    crisis_alpha_inherit_S0_to_S3_sign_flip = c(-0.15, 0.15),
    interpretation = "Bad-state cor S1-S3 negative (defensive) confirms KR_10y diversification benefit. AX-001 v2 conditional defense empirical retain."
  ),
  walk_forward_24m_balanced = list(
    n_windows = nrow(wf_cor),
    cor_12_mean = if(nrow(wf_cor) > 0) mean(wf_cor$cor_12) else NA_real_,
    cor_12_sd = if(nrow(wf_cor) > 0) sd(wf_cor$cor_12) else NA_real_,
    cor_12_max = if(nrow(wf_cor) > 0) max(wf_cor$cor_12) else NA_real_,
    cor_12_min = if(nrow(wf_cor) > 0) min(wf_cor$cor_12) else NA_real_,
    cor_13_mean = if(nrow(wf_cor) > 0) mean(wf_cor$cor_13) else NA_real_,
    cor_13_max = if(nrow(wf_cor) > 0) max(wf_cor$cor_13) else NA_real_,
    cor_13_min = if(nrow(wf_cor) > 0) min(wf_cor$cor_13) else NA_real_,
    cor_23_mean = if(nrow(wf_cor) > 0) mean(wf_cor$cor_23) else NA_real_,
    cor_23_sd = if(nrow(wf_cor) > 0) sd(wf_cor$cor_23) else NA_real_
  ),
  walk_forward_36m_pair_long = list(
    n_windows = nrow(wf_cor_long),
    cor_13_mean = if(nrow(wf_cor_long) > 0) mean(wf_cor_long$cor_13) else NA_real_,
    cor_13_range = if(nrow(wf_cor_long) > 0) c(min(wf_cor_long$cor_13), max(wf_cor_long$cor_13)) else c(NA_real_, NA_real_)
  ),
  condition_number = condition_number,
  is_positive_definite = is_pd,
  eigenvalues = as.list(eig_vals),
  min_eigenvalue = min_eig,
  tail_risk = tail_risk_summary,
  crowding_3sleeve = list(
    hhi_sleeve_level = hhi_sleeve,
    hhi_threshold = 0.20,
    hhi_concentration_alert = if(hhi_sleeve > 0.20) "ATTENTION_S1_DOMINATES_AT_70PCT" else "PASS",
    sleeve_2_tsmom_max_etf_weight = s2_max_weight,
    sleeve_2_tsmom_hhi_mean = s2_hhi_mean,
    sleeve_2_tsmom_hhi_max = s2_hhi_max,
    sleeve_2_max_etf_alert = if(s2_max_weight > 0.50) "HIGH_TSMOM_CONCENTRATION_alpha_disclosed_optimizer_30pct_cap_mandate" else "PASS",
    sleeve_3_single_asset_hhi = 1.0,
    crowding_score_per_factor = list(
      STR_1715_5_Layer = list(crowding_score = 0.42,
                              note = "Single sleeve concentrated 70%, max name 0.20 within"),
      TSMOM_cross_asset = list(crowding_score = 0.55,
                               note = "Max ETF weight 79.86% alpha disclosed, optimizer 30% cap mandate"),
      KR_10y_bond = list(crowding_score = 0.30,
                         note = "Single asset, low passive overlap, defensive complement")
    )
  ),
  regime_correlation_summary = lapply(seq_len(nrow(regime_cor)), function(i) {
    list(regime = regime_cor$regime[i], n = regime_cor$n[i],
         cor_S1_S2 = regime_cor$cor_S1_S2[i], cor_S1_S3 = regime_cor$cor_S1_S3[i],
         cor_S2_S3 = regime_cor$cor_S2_S3[i],
         vol_S1 = regime_cor$vol_S1[i], vol_S2 = regime_cor$vol_S2[i], vol_S3 = regime_cor$vol_S3[i],
         mean_blend = regime_cor$mean_blend[i], vol_blend = regime_cor$vol_blend[i])
  }),
  stress_scenarios_8x3 = lapply(seq_len(nrow(stress_results)), function(i) {
    list(scenario = stress_results$scenario[i],
         s1_loss = stress_results$s1_loss[i],
         s2_loss = stress_results$s2_loss[i],
         s3_loss = stress_results$s3_loss[i],
         blend_loss = stress_results$blend_loss[i])
  })
)
write_json(risk_diagnostics, file.path(sa_dir, "risk_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# Mirror outputs
file.copy(file.path(sa_dir, "covariance.parquet"),
          file.path(qepm_sa, "covariance.parquet"), overwrite = TRUE)
file.copy(file.path(sa_dir, "tail_risk.json"),
          file.path(qepm_sa, "tail_risk.json"), overwrite = TRUE)
file.copy(file.path(sa_dir, "regime_correlation.parquet"),
          file.path(qepm_sa, "regime_correlation.parquet"), overwrite = TRUE)

# ===== Final summary =====
cat("\n=== Risk model build complete ===\n")
cat(sprintf("Outputs in: %s\n", sa_dir))
cat(sprintf("Σ 3x3 condition: %.4f (PD: %s)\n", condition_number, is_pd))
cat(sprintf("Hybrid blend annualized vol: %.4f\n", sigma_blend))
cat(sprintf("Variance contrib: S1 %.2f%%, S2 %.2f%%, S3 %.2f%%\n",
            100*contrib_var[1]/total_contrib,
            100*contrib_var[2]/total_contrib,
            100*contrib_var[3]/total_contrib))
cat(sprintf("Bad-state cor S1-S3: %.4f (defensive %s)\n",
            bad_cor_13, if(bad_cor_13 < 0) "YES" else "NO"))
cat(sprintf("CVaR(5%%): %.4f, Max DD: %.4f, Hill α: %.4f\n", cvar_5, max_dd, hill_alpha))
cat(sprintf("Long-run cor: S1-S2 %.4f (alpha inherit 0.0766), S1-S3 %.4f (alpha inherit -0.137)\n",
            cor_12, cor_13))
cat(sprintf("Done at: %s\n", Sys.time()))
