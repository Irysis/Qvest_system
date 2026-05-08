#==============================================================================
# build_alpha_package_final.R
# WT-D20260508_002 — Build alpha_package.json final (POST-CODEX REJECT disposition)
#
# Source: alpha_package_draft.json + codex_critic_response_alpha.json + challenge_note
# Output: alpha_package.json (FINAL, agent_agree_with_codex=TRUE, DISCOVERY_FAIL_REJECTED)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(data.table)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_002"
WT_DIR <- file.path(PROJ, "qepm", "mailbox", "worktask", WT_ID)

cat("Building alpha_package.json final (POST-CODEX REJECT disposition)...\n")

# Load draft + codex response
draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)
codex <- fromJSON(file.path(WT_DIR, "codex_critic_response_alpha.json"), simplifyVector = FALSE)

# Build final package — REJECTED disposition
final <- draft

# Override empirical_disposition + operational_decision
final$empirical_disposition <- list(
  status = "DISCOVERY_FAIL_REJECTED_AGENT_AGREES_CODEX",
  rationale = paste(
    "Codex GPT-5.5 + xhigh REJECT (8 critical concerns + 3 rationalization auto-flags + AX-008 FAIL).",
    "4 HIGH (C1 PIT-C1 factor pre-selection, C2 PIT-C10 universe same-month filter, C3 turnover 805%>600% hard fail, C4 multi-trial DSR under-corrected) + 4 MEDIUM (C5-C8) all ACCEPT/PARTIAL by agent.",
    "AX-002 + AX-007 + AX-008 all FAIL post-Codex.",
    "Auto-escalate trigger: AX hard FAIL >=3 + PIT-C1 violation found.",
    "Empirical op_pass=TRUE invalidated due to PIT violation -> IC inflation suspected.",
    "WT_001 precedent consistent (honest FAIL despite empirical strong signal)."
  ),
  graduation_proper_check = list(
    rank_ic_sign_aligned = TRUE,
    rank_ic_magnitude = 0.2909,
    rank_ic_magnitude_pass = TRUE,
    icir_magnitude = 2.436,
    icir_magnitude_pass = TRUE,
    sub_stab = 1,
    sub_stab_pass = TRUE,
    harvey_t_NW_magnitude = 17.40,
    harvey_t_NW_magnitude_pass = TRUE,
    dsr_single_test = 17.76,
    dsr_strict_multi_trial_estimated = 13.65,
    dsr_pass_strict = TRUE,
    operational_alpha_test_long_sr_net = 2.448,
    operational_alpha_test_pass = TRUE,
    turnover_ann = 8.0518,
    turnover_hard_fail_600pct = TRUE,
    pit_c1_violation = TRUE,
    pit_c10_violation = TRUE,
    overall_pass_pit_corrected = FALSE,
    overall_pass_naive_empirical = TRUE,
    decision_authoritative_pit_corrected = "FAIL"
  ),
  empirical_strength_caveat = paste(
    "rank_ic 0.291 / ICIR 2.44 / Harvey-t 17.40 / Long_Net_SR 2.45 are anomalously strong vs Gu-Kelly-Xiu 2020 RFS US large-cap baseline OOS IC 0.04-0.10 (3-7x).",
    "PIT violation (factor pre-selection 2024-12 + universe same-month filter) suggests inflation.",
    "True PIT-rework v5 expected to attenuate IC by 30-60% (KR market L-228 empirical)."
  )
)

final$operational_decision <- list(
  finalize_label = "DISCOVERY_FAIL_REJECTED_AGENT_AGREES_CODEX",
  graduation_pass_signed = FALSE,
  pg2_admit_eligibility = "NOT_ELIGIBLE",
  next_action = "TERMINATE_CURRENT_ATTEMPT_PIT_REWORK_v5_OR_PIVOT_MANDATE",
  qlead_decision_required = TRUE,
  qlead_escalate_summary = paste(
    "본 WT 4번째 직교 source 정식 발굴 path 2차 시도. Codex REJECT 정합 8 concern (4 HIGH + 4 MEDIUM) + auto-rationalization 3건.",
    "Empirical IC 0.291 / SR 2.45 매력적이나 PIT C1+C10 violation으로 무효.",
    "WT_001 (VRP overlay FAIL) 정합 패턴 — KR top universe alpha discovery 자체 한계 (L-228) 또는 정직 PIT-rework v5 의무.",
    "본 WT는 DISCOVERY_FAIL 종결 + 후속 WT (PIT-rework v5 또는 alternate path 4종) Q-Lead 결정 의무."
  ),
  pivot_recommendations = list(
    list(
      priority = 1L,
      name = "PIT_rework_v5_ml_residual",
      desc = paste(
        "Factor selection rolling sliding window (every sig_date 시점 별 coverage 측정) +",
        "universe t-1 filter + 2e8 floor restore + TO penalty hard cap (turnover<=600%) +",
        "strict multi-trial Bailey-LdP DSR + sector-neutral ICIR rerun + forward 2026-05 as-of signal +",
        "Honest MLP fabrication 정정 (polynomial Ridge 명시 또는 torch CUDA build install)."
      ),
      estimated_effort = "1 alpha-research WT cycle (~1-2h ML rerun + diagnostics)"
    ),
    list(
      priority = 2L,
      name = "VKOSPI_direct_via_KRX_OpenAPI_carry_from_WT001",
      desc = "WT_001 priority 1 carry. KRX OpenAPI direct fetch (data_collector_krx_options.R + krx_derivatives_collector.R 인프라 가용). VRP US VIX proxy 대체.",
      estimated_effort = "data fetch ~3-5h + 1 alpha-research WT cycle"
    ),
    list(
      priority = 3L,
      name = "Defensive_LowVol_KR_multi_sleeve_EXCLUSION",
      desc = "AX-005 v1.2 EXCLUSION-required (single-sleeve top20 standalone fail L-136/140/165/166). 50/30/20 split Q07 + low-beta + drawdown-conditional.",
      estimated_effort = "1 alpha-research WT cycle, infrastructure existing"
    ),
    list(
      priority = 4L,
      name = "Commodity_Gold_Copper_KR_ETF",
      desc = "KODEX 골드/구리 ETF allocation (cycle 2 cor_hybrid 0.023 + crisis_alpha 40%). 인플레 hedge orthogonal.",
      estimated_effort = "1 alpha-research WT cycle"
    ),
    list(
      priority = 5L,
      name = "IPCA_latent_factor_Kelly_Pruitt_Su_2019_JFE",
      desc = "Instrumented PCA characteristics-loadings. Kelly-Pruitt-Su 2019 JFE mechanism. Cross-section per-name latent factor.",
      estimated_effort = "1 alpha-research WT cycle (research + implementation)"
    )
  )
)

# Override codex_round block
final$codex_round <- list(
  round_executed = TRUE,
  stance_received = "REJECT",
  veto_flag = FALSE,
  critical_concerns_count = 8L,
  severity_HIGH_count = 4L,
  severity_MEDIUM_count = 4L,
  weakest_assumption = codex$weakest_assumption,
  rationalization_red_flags_codex_detected = list(
    "conservative; minimal impact for residual extraction",
    "GPU benefit minimal",
    "interpret t_NW conservatively"
  ),
  challenge_note_path = "qepm/mailbox/worktask/WT-D20260508_002/challenge_note_alpha-research.md",
  disposition_summary = list(
    ACCEPT_HIGH = list(
      "C1 PIT-C1 factor pre-selection 2024-12 coverage backward leakage",
      "C2 PIT-C10 universe/liquidity/Admin same-month filter + 2e8->5e7 relax",
      "C3 turnover_ann 8.05 > 600% hard fail + top-quintile sleeve != max_20 portfolio",
      "C4 multi-trial DSR under-corrected (single-test variant)"
    ),
    ACCEPT_MEDIUM = list(
      "C5 alpha_vector 2026-04 realized != 2026-05 forward signal",
      "C6 RF-A4 sector-neutral rerun missing (post_neutralization_ic self-copy)",
      "C8 MLP torch fabrication (USE_MLP=FALSE polynomial Ridge substitute, claim mismatch)"
    ),
    PARTIAL = list(
      "C4 strict DSR haircut estimated 13.65 still PASS, but caveat insufficient",
      "C7 lineage FAIL agent responsibility, covariance.parquet expected at Risk stage"
    ),
    REBUTTAL = list()
  ),
  ax_002_post_disposition = "FAIL_C1_PIT_violation_C8_fabrication_3_rationalization",
  ax_007_post_disposition = "FAIL_TO_805pct_hard_fail_top_quintile_sleeve_not_max20",
  ax_008_post_disposition = "FAIL_alpha_only_lineage_fail_risk_opt_missing",
  rationalization_red_flags_self_check = 0L,
  agent_agree_with_codex_majority = TRUE,
  agent_agree_with_codex_full_8_concerns = TRUE,
  qlead_escalate_required = TRUE,
  qlead_escalate_trigger = list(
    "AX_axiom_hard_FAIL_count_3 (AX-002 + AX-007 + AX-008)",
    "PIT_C1_violation_found (C1 + C2)"
  )
)

# Update challenge_flags with Codex findings
final$challenge_flags <- list(
  list(
    id = "GPU_R_BINDINGS_UNAVAILABLE",
    severity = "LOW_INFORMATIONAL",
    msg = "R torch::cuda_is_available()=FALSE; xgboost device='cuda' fell back to CPU. Hardware (RTX 4080 SUPER 16GB) verified but R packages CPU-only build. 16-core CPU 병렬 used as compensation."
  ),
  list(
    id = "PIT_C1_FACTOR_PRESELECTION",
    severity = "HIGH",
    msg = "Codex C1 ACCEPT — top80 factor selection at 2024-12 coverage applied backward 2008-2026. Backward leakage. Mandates rolling sliding-window factor selection in v5+."
  ),
  list(
    id = "PIT_C10_UNIVERSE_SAME_MONTH",
    severity = "HIGH",
    msg = "Codex C2 ACCEPT — universe/liquidity/Admin filter uses target-month YM. Vol_KRW_20d tail(Close*Vol,20) same-month. Liquidity floor relaxed 2e8 -> 5e7."
  ),
  list(
    id = "TURNOVER_805PCT_HARD_FAIL",
    severity = "HIGH",
    msg = "Codex C3 ACCEPT — pred_ens turnover_ann=8.0518 (~805% annual) > 600% Hurdle Gate v2.2 hard fail. Top-quintile sleeve != max_20 constrained portfolio. weights.csv missing."
  ),
  list(
    id = "DSR_MULTI_TRIAL_UNDER_CORRECTED",
    severity = "HIGH",
    msg = "Codex C4 ACCEPT_PARTIAL — DSR=17.76 single-test variant. Strict Bailey-LdP haircut N_trials~480, T=136 -> DSR_strict~13.65 (still PASS). Caveat insufficient."
  ),
  list(
    id = "ALPHA_VECTOR_REALIZED_NOT_FORWARD",
    severity = "MEDIUM",
    msg = "Codex C5 ACCEPT — alpha_vector exported = 2026-04 target-month prediction with realized y_actual present. as_of_date 2026-05-08 forward signal not provided."
  ),
  list(
    id = "SECTOR_NEUTRAL_ICIR_MISSING",
    severity = "MEDIUM",
    msg = "Codex C6 ACCEPT — RF-A4 audit missing. post_neutralization_ic = rank_ic self-copy bug. Sector-neutral ICIR 50% decline test not run."
  ),
  list(
    id = "LINEAGE_AND_STAGE_ARTIFACTS_MISSING",
    severity = "MEDIUM",
    msg = "Codex C7 PARTIAL — artifact_lineage.json write FAIL. stage_artifacts/WT_WT-D20260508_002 dir absent. covariance.parquet expected at Risk stage (out-of-scope for alpha)."
  ),
  list(
    id = "MLP_TORCH_FABRICATION",
    severity = "MEDIUM",
    msg = "Codex C8 ACCEPT — v4 line 311 USE_MLP=FALSE (WSL2 torch bus error). Polynomial Ridge degree=2 substitute. factor_specs[5] proxy=pred_mlp + reference Chen-Pelger-Zhu 2024 Deep Learning AP = misrepresentation."
  ),
  list(
    id = "AUTO_RATIONALIZATION_CODEX_DETECTED",
    severity = "LOW",
    msg = "Codex auto-detected 3 phrases: 'conservative; minimal impact / GPU benefit minimal / interpret t_NW conservatively'. All ACCEPT, replaced with quantitative measurements in final challenge_note."
  )
)

# Update method_log to honest pred_mlp = polynomial Ridge label
for (i in seq_along(final$method_log)) {
  if (final$method_log[[i]]$name == "pred_mlp") {
    final$method_log[[i]]$honest_implementation <- "polynomial_ridge_top10_degree2_substitute (USE_MLP=FALSE due to WSL2 torch bus error)"
    final$method_log[[i]]$claim_correction <- "Chen-Pelger-Zhu 2024 reference REVOKED — actual mechanism != deep learning"
  }
}

# Update factor_specs to honest pred_mlp label
for (i in seq_along(final$factor_specs)) {
  if (final$factor_specs[[i]]$proxy == "pred_mlp") {
    final$factor_specs[[i]]$honest_implementation <- "polynomial_ridge_top10_degree2_substitute"
    final$factor_specs[[i]]$claim_correction <- "Chen-Pelger-Zhu 2024 Deep Learning AP reference REVOKED for this method"
  }
}

# Append PIT-corrected diagnostics estimate to top-level diagnostics
final$diagnostics$pit_corrected_estimates <- list(
  rank_ic_naive_empirical = 0.2909,
  rank_ic_pit_corrected_estimate_low = 0.087,
  rank_ic_pit_corrected_estimate_high = 0.20,
  rank_ic_pit_corrected_estimate_method = "Apply L-228 KR PIT violation deflation 30-60% to naive rank_ic (factor pre-selection + universe same-month combined)",
  dsr_strict_multi_trial = 13.65,
  dsr_strict_method = "DSR_obs / (1 + sqrt(2*ln(N_trials)/T)) where N_trials=480 (factor prefilter + 6 ML model + ~5 hyperparam grid + ensemble), T=136"
)

# Update top-level fields
final$hypothesis_description_short <- paste(
  "Cross-section per-name forward-return residual prediction (target = R_i - R_Hybrid).",
  "5 effective ML methods (Ridge / ElasticNet / XGBoost / RandomForest / Polynomial Ridge ensemble; MLP claim REVOKED due to torch CUDA build absence).",
  "v4 empirical IC 0.291 / Long_Net_SR 2.45 PASS but Codex REJECT 8 concerns (PIT-C1 factor pre-selection + PIT-C10 universe same-month + TO 805% hard fail + multi-trial DSR + 4 medium).",
  "Honest disposition: DISCOVERY_FAIL_REJECTED_AGENT_AGREES_CODEX. PIT-rework v5 mandate or pivot."
)

final$alpha_geometry <- "per_name_cross_section"
final$per_name_alpha_matrix_required <- TRUE

# Write final
final_path <- file.path(WT_DIR, "alpha_package.json")
writeLines(toJSON(final, pretty = TRUE, auto_unbox = TRUE, na = "null"), final_path)
cat("  Wrote final:", final_path, "\n")

# Verify
fp_size <- file.size(final_path)
cat("  File size:", fp_size, "bytes\n")

# Quick validation
fp_load <- fromJSON(final_path, simplifyVector = FALSE)
cat("\n--- Final package summary ---\n")
cat("task_id:", fp_load$task_id, "\n")
cat("alpha_vector len:", length(fp_load$alpha_vector), "\n")
cat("factor_specs count:", length(fp_load$factor_specs), "\n")
cat("empirical_disposition$status:", fp_load$empirical_disposition$status, "\n")
cat("operational_decision$finalize_label:", fp_load$operational_decision$finalize_label, "\n")
cat("operational_decision$pg2_admit_eligibility:", fp_load$operational_decision$pg2_admit_eligibility, "\n")
cat("codex_round$stance_received:", fp_load$codex_round$stance_received, "\n")
cat("codex_round$qlead_escalate_required:", fp_load$codex_round$qlead_escalate_required, "\n")
cat("challenge_flags count:", length(fp_load$challenge_flags), "\n")
cat("\n=== alpha_package.json FINAL DONE ===\n")
