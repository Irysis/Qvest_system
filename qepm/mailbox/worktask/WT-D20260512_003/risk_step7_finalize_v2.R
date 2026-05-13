#==============================================================================
# Risk Step 7: Patch v2 — RF-R1 trigger + proper variance attribution
#
# Issue identified: F_QMJ contribution diagonal = 47.8% > 40% threshold.
# This is V5 failure axis (Q07 sleeve quality)! Add explicit RF-R1 flag.
# Also redo variance attribution: separate marginal vs total per-factor.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(digest)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")

OUT_DIR <- "stage_artifacts/WT_D20260512_003"
WT_MAILBOX <- "qepm/mailbox/worktask/WT-D20260512_003"

# Load current draft
risk_package <- fromJSON(file.path(WT_MAILBOX, "risk_package_draft.json"), simplifyVector = FALSE)

# Load Σ for proper attribution
res24 <- readRDS(file.path(OUT_DIR, "_risk_step24_results.rds"))
Sigma <- res24$results[[5]]$Sigma
B <- attr(Sigma, "B")
Omega <- attr(Sigma, "Omega")
D <- attr(Sigma, "D")

alpha_dt <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores_new.parquet")))
last_date <- max(alpha_dt$Date)
cur_top20 <- copy(alpha_dt[Date == last_date & !is.na(z_blend_composite)])
setorder(cur_top20, -z_blend_composite)
cur_top20 <- head(cur_top20, 20)
top20_tickers <- intersect(cur_top20$Ticker, rownames(B))
B_top20 <- B[top20_tickers, , drop = FALSE]
w_ew <- rep(1 / length(top20_tickers), length(top20_tickers))

# Portfolio factor exposure
b_p <- as.vector(t(w_ew) %*% B_top20)
names(b_p) <- colnames(B)

# Total monthly variance via factor structure
D_top <- D[top20_tickers]
spec_var <- sum(w_ew^2 * D_top, na.rm = TRUE)
contrib_mat <- outer(b_p, b_p) * Omega
factor_var <- sum(contrib_mat)
total_var <- factor_var + spec_var

# Per-factor MARGINAL contribution (mc): d_total_var / d_factor_loading
# = 2 * (Omega %*% b_p)[k] * b_p[k]
mc_factor <- as.vector(2 * (Omega %*% b_p) * b_p)
names(mc_factor) <- names(b_p)
# Normalize so factor margins sum to factor_var (Euler decomposition: sum of marginal*loading = total)
# Actually proper Euler: variance = sum_i b_i * (Sigma_F b)_i / 2 = 0.5 sum mc_factor
# Let's use the proper risk contribution: RC_i = b_p[i] * (Omega %*% b_p)[i] / total_var
rc_factor <- as.vector(b_p * (Omega %*% b_p)) / total_var * 100
names(rc_factor) <- names(b_p)
spec_rc <- spec_var / total_var * 100

# Now rc_factor + spec_rc sums to 100 (verify)
sum_check <- sum(rc_factor) + spec_rc
cat("[Step7] Proper Euler risk decomposition (% of total var):\n")
rc_dt <- data.table(
  factor = c(names(rc_factor), "SPECIFIC"),
  pct_of_total = round(c(rc_factor, spec_rc), 3)
)
setorder(rc_dt, -pct_of_total)
print(rc_dt)
cat(sprintf("[Step7] Euler sum check: %.4f%% (should be 100)\n", sum_check))

# Top 3 by Euler
top_common_risks_v2 <- rc_dt[1:3, paste0(factor, " (", round(pct_of_total, 1), "%)")]
top_factor_pct_v2 <- rc_dt[1, pct_of_total]
RF_R1_v2 <- top_factor_pct_v2 > 40
cat(sprintf("[Step7] RF-R1 (Euler): top = %s = %.1f%% — %s\n",
            rc_dt[1, factor], top_factor_pct_v2, ifelse(RF_R1_v2, "TRIGGERED", "OK")))

# Update risk_package
risk_package$risk_summary$top_common_risks <- as.list(top_common_risks_v2)
risk_package$risk_summary$top_factor_pct_of_total <- top_factor_pct_v2
risk_package$risk_summary$per_factor_contribution_euler <- as.list(setNames(
  round(c(rc_factor, spec_rc), 4),
  c(names(rc_factor), "SPECIFIC")
))
risk_package$risk_summary$variance_attribution_method <- "Euler risk contribution (b'(Σ_F b)) for factor terms + sum_i w_i^2 D_i for specific. Sums to 100% by construction."
# Keep diagonal for legacy
risk_package$risk_summary$per_factor_diagonal_legacy <- risk_package$risk_summary$per_factor_contribution
risk_package$risk_summary$per_factor_contribution <- NULL

# Add RF-R1 challenge flag (if triggered)
if (RF_R1_v2) {
  new_flag <- list(
    flag_id = "RF_R1_TOP_FACTOR_CONCENTRATION_V5_AXIS_OVERLAP",
    severity = "HIGH",
    disposition = "DOCUMENTED_FOR_OPTIMIZER",
    detail = sprintf(
      "Top factor risk concentration: %s = %.1f%% of total variance (Euler decomposition, threshold 40%%). CRITICAL OVERLAP: F_QMJ is the same quality/earnings-stability axis where V5 (defense_amplifier) STR_1715 Q07+M08+Q25 sleeve FAILED at SR -3.64 CAUTION / -2.61 CRISIS. Composite mitigates the failure via theta_defense down-weighting in CAUTION/CRISIS regimes (CAUTION SR swing +5.09 / CRISIS +5.35 vs V5) — i.e., the structural risk remains but the alpha-side weighting absorbs it. Optimizer should be aware: increasing top20 selection in BULL/NORMAL may re-concentrate F_QMJ exposure. HRP or risk parity weights inside top20 could reduce this single-factor dominance.",
      rc_dt[1, factor], top_factor_pct_v2),
    source = "risk_step7_euler_decomposition + V5_evidence_reference",
    sigma_evidence = list(
      top_factor = rc_dt[1, factor],
      top_factor_pct_total = rc_dt[1, pct_of_total],
      second_factor = rc_dt[2, factor],
      second_pct = rc_dt[2, pct_of_total],
      specific_pct = spec_rc,
      factor_loading_qmj = b_p["F_QMJ"],
      factor_loading_tail = b_p["F_TAIL"]
    ),
    v5_reference = list(
      v5_q07_sleeve_caution_sr = -3.642,
      v5_q07_sleeve_crisis_sr = -2.608,
      composite_caution_sr = risk_package$stress_decomposition$regime_decomposition_v5_comparison$composite_realized$CAUTION$sr_ann,
      composite_crisis_sr = risk_package$stress_decomposition$regime_decomposition_v5_comparison$composite_realized$CRISIS$sr_ann,
      mechanism = "alpha-layer theta_defense regime-conditional weighting absorbs Q07-sleeve risk without reducing factor exposure structurally"
    )
  )
  risk_package$challenge_flags[[length(risk_package$challenge_flags) + 1]] <- new_flag
}

# Add SR target gap flag (도훈 mandate SR 2.0+)
sr_target_gap_flag <- list(
  flag_id = "RISK_CONCERN_SR_TARGET_GAP_VS_DOHOON_MANDATE",
  severity = "MEDIUM",
  disposition = "ALPHA_TRADEOFF_FOR_QLEAD_AWARENESS",
  detail = sprintf(
    "Top20 EW Z-Composite full-sample SR = %.3f (267m). Dohoon mandate target SR 2.0+. Gap = %.3f. R05 composite NORMAL/BULL SR degradation vs V5 (SR -0.35 / -2.15) is alpha-design tradeoff for crisis hedge. Risk layer flags awareness — Optimizer may need non-EW weighting (HRP/MV) to recover SR.",
    (mean(risk_package$stress_decomposition$regime_decomposition_v5_comparison$composite_realized$NORMAL$ann_ret +
          risk_package$stress_decomposition$regime_decomposition_v5_comparison$composite_realized$BULL$ann_ret) /
     mean(risk_package$stress_decomposition$regime_decomposition_v5_comparison$composite_realized$NORMAL$ann_ret +
          risk_package$stress_decomposition$regime_decomposition_v5_comparison$composite_realized$BULL$ann_ret) +
     1),  # placeholder; use full sample below
    2.0 - 1.5),
  source = "risk_step7_dohoon_mandate_check"
)
# Compute actual full-sample SR from port_dt
port_dt <- as.data.table(read_parquet(file.path(OUT_DIR, "_risk_portfolio_returns.parquet")))
full_sr <- mean(port_dt$port_ret) / sd(port_dt$port_ret) * sqrt(12)
sr_target_gap_flag$detail <- sprintf(
  "Top20 EW Z-Composite full-sample SR = %.3f (267m). Dohoon mandate target SR 2.0+. Gap = %.3f. R05 composite NORMAL/BULL SR degradation vs V5 (SR -0.35 / -2.15) is alpha-design tradeoff for crisis hedge. Risk layer flags awareness — Optimizer may need non-EW weighting (HRP/MV) to recover SR.",
  full_sr, 2.0 - full_sr)
sr_target_gap_flag$full_sample_sr_ew <- full_sr
sr_target_gap_flag$full_sample_ann_ret <- mean(port_dt$port_ret) * 12
sr_target_gap_flag$full_sample_ann_vol <- sd(port_dt$port_ret) * sqrt(12)
risk_package$challenge_flags[[length(risk_package$challenge_flags) + 1]] <- sr_target_gap_flag

# Save updated draft
write_json(risk_package, file.path(WT_MAILBOX, "risk_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("\n[Step7] risk_package_draft.json v2 saved.\n")
cat("[Step7] Updated top_common_risks:", paste(top_common_risks_v2, collapse=" | "), "\n")
cat("[Step7] Total challenge flags:", length(risk_package$challenge_flags), "\n")
cat(sprintf("[Step7] Full-sample SR (EW): %.3f vs target 2.0 (gap %.3f)\n", full_sr, 2.0 - full_sr))
cat(sprintf("[Step7] Full-sample MDD: %.2f%% (target -25%%, %.2fpp ", risk_package$stress_decomposition$full_sample_mdd_composite_vs_v5$composite_mdd_pct,
            risk_package$stress_decomposition$full_sample_mdd_composite_vs_v5$composite_mdd_pct - 25))
cat(ifelse(risk_package$stress_decomposition$full_sample_mdd_composite_vs_v5$composite_mdd_pct < 25, "OK", "BREACH"), ")\n")
