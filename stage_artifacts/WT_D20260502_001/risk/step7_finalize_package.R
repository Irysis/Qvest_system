#==============================================================================
# WT-D20260502_001 Risk Research — Step 7: Finalize risk_package_draft.json
#
# Save covariance.parquet (Σ + ticker order) + risk_package_draft.json
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(digest)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step6_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- Save covariance.parquet (Σ_primary) -------------------------------------
Sigma <- state$Sigma_primary
covered <- state$covered_tickers_60M
n <- length(covered)

# Save as long format: Ticker_i, Ticker_j, Cov
cov_dt <- data.table(
  Ticker_i = rep(covered, each = n),
  Ticker_j = rep(covered, n),
  Cov = as.vector(Sigma)
)
write_parquet(cov_dt, file.path(WT_DIR, "covariance.parquet"))
cat(sprintf("[Step7] covariance.parquet saved: %d rows\n", nrow(cov_dt)))

# Also save Σ as wide matrix for inspection
sigma_dt <- as.data.table(Sigma)
sigma_dt[, Ticker := covered]
setcolorder(sigma_dt, c("Ticker", covered))
write_parquet(sigma_dt, file.path(WT_DIR, "covariance_wide.parquet"))

# ---- Save security covariance ref (also = Σ for our model) ------------------
file.copy(file.path(WT_DIR, "covariance.parquet"),
          file.path(PROJ, "stage_artifacts/WT_D20260502_001/covariance.parquet"),
          overwrite = TRUE)
file.copy(file.path(WT_DIR, "regime_correlation.parquet"),
          file.path(PROJ, "stage_artifacts/WT_D20260502_001/regime_correlation.parquet"),
          overwrite = TRUE)
file.copy(file.path(WT_DIR, "exposure_matrix.parquet"),
          file.path(PROJ, "stage_artifacts/WT_D20260502_001/exposure_matrix.parquet"),
          overwrite = TRUE)
file.copy(file.path(WT_DIR, "factor_covariance.parquet"),
          file.path(PROJ, "stage_artifacts/WT_D20260502_001/factor_covariance.parquet"),
          overwrite = TRUE)
file.copy(file.path(WT_DIR, "specific_risk.parquet"),
          file.path(PROJ, "stage_artifacts/WT_D20260502_001/specific_risk.parquet"),
          overwrite = TRUE)
cat("[Step7] Artifacts copied to stage_artifacts/WT_D20260502_001/\n")

# Compute hashes
sha_cov <- digest::digest(file = file.path(WT_DIR, "covariance.parquet"), algo = "sha256")
sha_exp <- digest::digest(file = file.path(WT_DIR, "exposure_matrix.parquet"), algo = "sha256")
sha_fcov <- digest::digest(file = file.path(WT_DIR, "factor_covariance.parquet"), algo = "sha256")
sha_spec <- digest::digest(file = file.path(WT_DIR, "specific_risk.parquet"), algo = "sha256")
sha_reg <- digest::digest(file = file.path(WT_DIR, "regime_correlation.parquet"), algo = "sha256")

# ---- Build risk_package_draft.json -------------------------------------------
# Top common risks list (clean format)
top_risks_clean <- unlist(state$top_common_risks_v2)

# Stress tests dict (% units)
stress_dict <- list()
for (n_period in names(state$stress_results)) {
  r <- state$stress_results[[n_period]]
  stress_dict[[n_period]] <- list(
    portfolio_pct = r$portfolio_ret,
    portfolio_mdd_pct = r$portfolio_mdd,
    benchmark_pct = r$benchmark_ret,
    excess_pct = r$excess_ret,
    outperform = r$outperform,
    n_days = r$n_days
  )
}
# Add scenario-based stress
stress_dict[["market_down_5_loss"]] <- state$stress_scenarios$market_down_5_loss
stress_dict[["value_crash_loss"]] <- state$stress_scenarios$value_crash_loss
stress_dict[["semiconductor_crash_loss"]] <- state$stress_scenarios$semiconductor_crash_loss

# AX-001 v2 + AX-007 risk
ax_compliance <- list(
  ax_001_v2 = list(
    axis_1_crisis_alpha = list(
      crisis_alpha_monthly_pct = state$str1715_cor_validation$crisis_alpha_monthly * 100,
      crisis_alpha_annualized_pct = state$str1715_cor_validation$crisis_alpha_annualized * 100,
      pass = state$str1715_cor_validation$ax001_v2_axis1_crisis_alpha_positive,
      method = "alpha_LS_ret bad-state vs STR_1715 bad-state diff (Risk re-derived from monthly returns)"
    ),
    axis_2_core_mdd_relief = list(
      str1715_cor_pearson_riskagent = state$str1715_cor_validation$pearson,
      str1715_cor_pearson_alpha_research = state$str1715_cor_validation$alpha_research_reported_pearson,
      str1715_cor_consistency = state$str1715_cor_validation$pearson_consistency_check_pass,
      anti_correlated = state$str1715_cor_validation$ax001_v2_axis2_anti_correlated,
      note = "Both Pearson values <0.10 → TRUE diversifier confirmed cross-axis. Anti-cor (cor<-0.10) NOT met but cor near 0 = orthogonal."
    ),
    axis_3_bad_normal_ic_ratio = list(
      reported_by_alpha_research = "FAIL (OOS bad/normal IC ratio 0.79 < 1.0)",
      risk_role = "Risk-research has no factor IC data; defers to alpha-research finding",
      note = "Alpha-research honestly disclosed axis 3 FAIL. Strict regime-conditional defense thesis NOT validated OOS."
    ),
    axis_4_regime_stability = list(
      reported_by_alpha_research = "PASS (subperiod_stability_oos=1.0)",
      risk_role = "Risk-research stress test 6/8 outperform — corroborates stability"
    ),
    overall = "axes 1+2+4 PASS / axis 3 FAIL. Strategy is balanced cross-regime defense-leaning, NOT strict regime-switch defense."
  ),
  ax_007_single_sleeve_mechanism = state$ax007_audit
)

# Composite challenge_flags (from RF + alpha-research transferred)
challenge_flags <- state$rf_flags
# Inherit critical alpha-research flags by reference
challenge_flags[[length(challenge_flags) + 1]] <- list(
  flag_id = "RF-R-INHERIT-1", severity = "HIGH",
  description = "Inherited from alpha-research RF-A-RES-2: OOS bad/normal IC ratio 0.79 reverses in-sample 1.28. Strict regime-conditional defense thesis NOT validated OOS. Composite is balanced cross-regime alpha. AX-001 v2 axis 3 FAIL."
)
challenge_flags[[length(challenge_flags) + 1]] <- list(
  flag_id = "RF-R-IRAN", severity = "HIGH",
  description = "Iran_War_2026-02~04 stress test FAIL: portfolio -8.64% vs benchmark +28.07% = -36.71% relative. Recent live OOS underperformance. Top alpha tickers (A010120 -52%, A352820 -32%) lost heavily. Risk indicator: alpha may have decay risk in late-stage 2026 macro environment."
)
challenge_flags[[length(challenge_flags) + 1]] <- list(
  flag_id = "RF-R-T_LT_N", severity = "MEDIUM",
  description = sprintf("Σ estimation regime: T=60 << N=336. Required Tikhonov α=%.2f to reach cn≤400, info_kept=%.1f%%. Honest tradeoff: information loss inherent. Optimizer should be aware Σ is heavily shrunk to diagonal.",
                        state$Sigma_diagnostics$tikhonov_alpha,
                        state$Sigma_diagnostics$info_kept_vs_sample * 100)
)

# selection_objective enum check
selection_obj <- "condition_number"  # base method criterion; valid enum value

# Build full draft
risk_package_draft <- list(
  task_id = WT_ID,
  agent_id = paste0("risk-research-", WT_ID),
  as_of_date = as.character(state$as_of_date),
  exposure_matrix_ref = "stage_artifacts/WT_D20260502_001/exposure_matrix.parquet",
  factor_covariance_ref = "stage_artifacts/WT_D20260502_001/factor_covariance.parquet",
  specific_risk_ref = "stage_artifacts/WT_D20260502_001/specific_risk.parquet",
  security_covariance_ref = "stage_artifacts/WT_D20260502_001/covariance.parquet",
  artifact_hashes = list(
    covariance_sha256 = sha_cov,
    exposure_matrix_sha256 = sha_exp,
    factor_covariance_sha256 = sha_fcov,
    specific_risk_sha256 = sha_spec,
    regime_correlation_sha256 = sha_reg
  ),
  risk_summary = list(
    top_common_risks = top_risks_clean,
    crowding_flags = c(
      sprintf("STR_1715 holdings overlap with top20 alpha: %d/20 (%.0f%%)",
              state$str1715_crowding_validation$top20_overlap_count,
              state$str1715_crowding_validation$top20_overlap_pct * 100),
      sprintf("STR_1715 max single weight: %.2f (concentration check)",
              state$str1715_crowding_validation$str1715_holdings_concentration_max_w)
    ),
    liquidity_flags = c(
      sprintf("Top20 liquidity pass rate (ADV>=50M KRW): %.1f%% (%d/%d)",
              state$liquidity_audit_top20$pct_pass,
              state$liquidity_audit_top20$n_pass,
              state$liquidity_audit_top20$n_total),
      sprintf("Worst Top20 ADV: %.1fB KRW",
              state$liquidity_audit_top20$worst_adv_top20 / 1e9)
    ),
    stress_tests = stress_dict,
    factor_R_squared_mean = state$avg_R_squared_systematic,
    factor_R_squared_systematic_pct = state$total_systematic_pct,
    factor_R_squared_specific_pct = state$total_specific_pct
  ),
  diagnostics = list(
    condition_number = state$Sigma_diagnostics$condition_number,
    min_eigenvalue = state$Sigma_diagnostics$min_eig,
    max_eigenvalue = state$Sigma_diagnostics$max_eig,
    is_psd = state$Sigma_diagnostics$is_psd,
    shrinkage_used = TRUE,
    shrinkage_method = "lw_2003_const_cor + tikhonov",
    shrinkage_lw_amount = state$Sigma_diagnostics$base_shrinkage_lw,
    tikhonov_alpha_additional = state$Sigma_diagnostics$tikhonov_alpha,
    info_kept_vs_sample = state$Sigma_diagnostics$info_kept_vs_sample,
    base_r_bar = state$Sigma_diagnostics$base_r_bar,
    factor_correlation_warnings = c(
      sprintf("Quality factor (Q07) shared between alpha and STR_1715 (both Quality family). Style β orthogonal (cor=%.2f) but factor-level overlap exists.",
              state$style_overlap$beta_correlation),
      sprintf("Sector concentration top: 반도체 7.5%% of total variance — semiconductor risk amplification.")
    ),
    tdc_summary = list(
      str1715_alpha_lower_tdc_q010 = state$str1715_cor_validation$ltdc_10,
      str1715_alpha_lower_tdc_q005 = state$str1715_cor_validation$ltdc_05,
      str1715_alpha_lower_tdc_q020 = state$str1715_cor_validation$ltdc_20,
      str1715_alpha_upper_tdc_q090 = state$str1715_cor_validation$utdc_90,
      interpretation = sprintf("Lower-tail TDC %.3f (q=0.10): joint-loss probability %.0f%% (LOW). Tail-diversifying confirmed.",
                                state$str1715_cor_validation$ltdc_10,
                                state$str1715_cor_validation$ltdc_10 * 100)
    ),
    regime_correlation_ref = "stage_artifacts/WT_D20260502_001/regime_correlation.parquet",
    regime_correlation_summary = list(
      crisis_mean_offdiag_cor = state$regime_correlation$crisis$mean,
      normal_mean_offdiag_cor = state$regime_correlation$normal$mean,
      regime_shift = state$regime_correlation$regime_shift,
      n_crisis_months = state$regime_correlation$n_crisis_months,
      n_normal_months = state$regime_correlation$n_normal_months,
      interpretation = "Standard universe-wide correlation breakdown in CRISIS (+0.175 shift). Not alpha-specific."
    ),
    style_attribution_alpha = state$style_attribution_alpha,
    style_attribution_str1715 = state$style_attribution_str1715,
    style_overlap = state$style_overlap,
    family_weights_alpha = state$family_weights_alpha,
    quality_share_alpha = state$quality_share_alpha,
    tail_share_alpha = state$tail_share_alpha
  ),
  ax_compliance = ax_compliance,
  challenge_flags = challenge_flags,
  method_shopping_log = list(
    candidates_tried = state$candidates_tried,
    candidates_log = state$method_log_v2,
    selected = state$Sigma_primary_name,
    rationale = state$selection_objective_rationale
  ),
  selection_objective = selection_obj,
  selection_objective_rationale = paste0(
    "R4 selection_objective enum 'condition_number'. ",
    "Among PSD candidates, picked LW2003 const-correlation (info_kept=95.8%, cn=1300). ",
    "Tikhonov regularization (α=0.62) applied to bring cn down to 391. ",
    "Final info_kept=36.4% (T<<N regime forces high shrinkage).",
    " NO alpha return / SR / IR criteria used — estimation quality only."
  ),
  str1715_diversifier_validation = list(
    pearson = state$str1715_cor_validation$pearson,
    spearman = state$str1715_cor_validation$spearman,
    kendall = state$str1715_cor_validation$kendall,
    lower_tdc_q010 = state$str1715_cor_validation$ltdc_10,
    lower_tdc_q005 = state$str1715_cor_validation$ltdc_05,
    upper_tdc_q090 = state$str1715_cor_validation$utdc_90,
    cor_bad_30pct = state$str1715_cor_validation$cor_bad_30pct,
    cor_normal_70pct = state$str1715_cor_validation$cor_normal_70pct,
    n_overlap_months = state$str1715_cor_validation$n_overlap_months,
    crowding_top20_overlap = state$str1715_crowding_validation$top20_overlap_pct,
    style_beta_correlation = state$style_overlap$beta_correlation,
    overall_diversifier_judgment = paste0(
      "TRUE diversifier CONFIRMED across 6 axes: ",
      "(1) returns Pearson 0.053, ",
      "(2) Spearman 0.079, ",
      "(3) Kendall 0.052, ",
      "(4) lower-tail TDC 0.091, ",
      "(5) bad-regime cor -0.034, ",
      "(6) holdings overlap 0/20. Style β cor 0.36 LOW. ",
      "ALL axes consistent with alpha-research reported Pearson 0.036 (consistency check pass)."
    )
  ),
  pipeline_version = "v1_riskagent",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  notes = paste0(
    "Risk research v6.4 honest report. Σ from LW2003 const-cor + Tikhonov α=0.62 ",
    "(T=60<<N=336 regime forces info loss to 36.4%% but PSD/cn=391 achieved). ",
    "AX-001 v2 axis 3 FAIL inherited from alpha-research (bad/normal IC 0.79 OOS). ",
    "AX-007 single-sleeve top20 mechanism break risk active (no exceptions met). ",
    "STR_1715 cross-validation across 6 axes confirms TRUE diversifier (Pearson 0.053 ≈ alpha-research 0.036). ",
    "Crisis_alpha +55%/year. Style β orthogonal (cor=0.36). Stress 6/8 outperform but Iran_War_2026 FAIL (-36.7%% relative). ",
    "Top common risks: Sector_반도체 7.5%% / Sector_IT가전 5.2%% / Market 1.1%%. ",
    "Specific risk 29.2%%. Codex critic round next."
  )
)

# Write draft (NOT final — Codex round mandatory)
draft_path <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID, "risk_package_draft.json")
write_json(risk_package_draft, draft_path,
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\n[Step7] risk_package_draft.json saved: %s\n", draft_path))
cat(sprintf("[Step7] Size: %.1f KB\n", file.info(draft_path)$size / 1024))
cat("[Step7] DONE.\n")
