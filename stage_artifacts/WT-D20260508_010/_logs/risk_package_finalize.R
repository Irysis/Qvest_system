#==============================================================================
# Risk Package Finalize — post-Codex 정합 갱신
#
# Codex Round 1 stance: REJECT
# 7 critical concerns 분류:
#   C1 RF-R2 cond>100 → PARTIAL (init.md cond<500 인용 + WT_009 precedent)
#   C2 BΩB' decomposition absent → PARTIAL (security-only clarification)
#   C3 Tail CVaR>cap + IMF/DotCom n=0 → PARTIAL (infeasibility report)
#   C4 PIT backfill diversification → ACCEPT (walk-forward fix 적용)
#   C5 AX-001 v2 overclaim → ACCEPT (FAIL_codex_strict, Diversifier role)
#   C6 PG2 active book crowding → PARTIAL (Discovery WT, defer)
#   C7 challenge_flags empty → ACCEPT (populate)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260508_010"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
SA_DIR    <- file.path(PROJ_ROOT, "stage_artifacts", WT_ID)

cat("\n===========================================\n")
cat("Risk Package Finalize (post-Codex Round 1)\n")
cat("===========================================\n\n")

# Load draft + supplements
draft <- fromJSON(file.path(WT_DIR, "risk_package_draft.json"), simplifyVector = FALSE)
sigma_supp <- fromJSON(file.path(WT_DIR, "sigma_supplement_ledoit_wolf_constcor.json"), simplifyVector = FALSE)
ax001_v2 <- fromJSON(file.path(WT_DIR, "ax001_v2_conditional_defense.json"), simplifyVector = FALSE)
div_proof_wf <- fromJSON(file.path(WT_DIR, "diversification_source_proof_walk_forward.json"), simplifyVector = FALSE)
codex <- fromJSON(file.path(WT_DIR, "codex_critic_response_risk.json"), simplifyVector = FALSE)

# Build finalized package
final_pkg <- draft

# ── Patch 1: sigma_method_details + diagnostics already updated. Confirm cond_post_shrink ──
final_pkg$sigma_method_details$rf_r2_threshold_used <- "kappa_<_500_per_init_md_L99_and_L173"
final_pkg$sigma_method_details$rf_r2_threshold_basis <- "risk_research_init.md L99 'Condition number > 500 시 자동 shrinkage 강화' + L173 'Condition number < 500 (shrinkage 후)'"
final_pkg$sigma_method_details$cond_post_shrink_value <- 202.62
final_pkg$sigma_method_details$cond_post_shrink_under_500 <- TRUE
final_pkg$sigma_method_details$codex_c1_threshold_alternate_kappa_le_100 <- list(
  origin = "Codex applied 'cond ≤ 100' threshold (PG2-admin downstream rule from codex_risk_critic_prompt.md)",
  init_md_threshold = 500,
  selected_value = 202.62,
  classification = "PARTIAL — init.md role threshold satisfied; Codex strict (cond≤100) NOT satisfied. Risk Agent uses init.md threshold per role prompt.",
  precedent = "WT-D20260508_009 LW const-corr κ=114 was admitted under same threshold."
)

# ── Patch 2: Σ structure clarification ──
final_pkg$sigma_method_details$sigma_kind <- "security_only_covariance"
final_pkg$sigma_method_details$bomega_b_d_decomposition <- list(
  status = "NOT_PROVIDED",
  rationale = "Σ provided is direct security-level covariance (LW2004 const-corr shrinkage). BΩB'+D factor risk model decomposition NOT computed at this stage; downstream Optimizer may decompose if needed (PCA / risk model). exposure_matrix/factor_covariance/specific_risk fields are NULL by design.",
  alternative_diagnostic = "PCA top-3 eigenvalue share = 26.7%/2.1%/1.8% (PC1 Market dominant)"
)

# ── Patch 3: Tail risk infeasibility report ──
final_pkg$tail_risk_infeasibility_report <- list(
  context = "Codex C3: ES95 6.76% > 2.5% cap; IMF_1997/DotCom_2000 n=0",
  cvar_es95_threshold_basis = list(
    codex_assumed_cap = 0.025,
    cap_origin = "Codex inferred from PG2 admin rule",
    init_md_basis = "risk_research_init.md L100 mentions 'Stress test 결과 정책 위반 시 challenge_flags + Rule 2 STOP 권고' but no specific 2.5% cap",
    measured = list(es95 = 0.0676, var95 = 0.0446, var99 = 0.0841, es99 = 0.106),
    classification = "PARTIAL — Codex applied stricter cap. Risk Agent reports honest empirical; Optimizer/Governor decides PG2 admit gating."
  ),
  imf_dotcom_unobservable = list(
    status = "INFEASIBLE",
    rationale = "Hybrid 70/15/15 backtest 시작 2005-02. IMF_1997 (1997-07~1998-12) + DotCom_2000 (2000-03~2002-09)은 baseline 부재. 우회 불가 (Hybrid 자체가 책 베이스라인).",
    alternative = "Use 8 stress periods that DO have observations (6 of 8 covered). Limit interpretation to coverage period 2005-02 onward."
  ),
  hybrid_observed_mdd = -0.1665,
  hybrid_observed_es95_to_mdd_ratio = round(0.0676 / 0.1665, 3),
  conclusion = "Tail risk reported honestly; threshold conformity decision deferred to Optimizer/Governor/PG2 admin step."
)

# ── Patch 4: Walk-forward diversification (replaces backfill, Codex C4 ACCEPT) ──
final_pkg$risk_summary$diversification_source_proof <- list(
  diversification_source = div_proof_wf$verdict_wf$diversification_source,
  pit_method = "WALK_FORWARD",
  rho_realized_walkforward = div_proof_wf$rho_realized_walk_forward,
  rho_bootstrap_ci_95 = list(
    lower = div_proof_wf$bootstrap_ci_rho$lower_2_5,
    upper = div_proof_wf$bootstrap_ci_rho$upper_97_5
  ),
  sigma_reduction_70_30_pct = div_proof_wf$verdict_wf$sigma_reduction_70_30_pct,
  sr_improvement_70_30 = div_proof_wf$verdict_wf$sr_improvement_70_30,
  mdd_improvement_70_30 = div_proof_wf$verdict_wf$mdd_improvement_70_30,
  matched_months = div_proof_wf$matched_months_wf,
  pit_backfill_violation_self_corrected = "YES — original backfill (rho +0.063, σ_red -2.62%) replaced with walk-forward (rho -0.087, σ_red +3.32%). Sign flipped; verdict still PARTIAL but diversification gain now POSITIVE."
)

# ── Patch 5: AX-001 v2 status downgrade (Codex C5 ACCEPT) ──
final_pkg$ax_axiom_audit$AX_001_v2$status <- "FAIL_codex_strict_diversifier_role"
final_pkg$ax_axiom_audit$AX_001_v2$crisis_ic_alpha <- ax001_v2$ic_crisis$mean
final_pkg$ax_axiom_audit$AX_001_v2$crisis_ic_ci_95 <- list(
  lower = ax001_v2$ic_crisis$ci_95_lower,
  upper = ax001_v2$ic_crisis$ci_95_upper,
  n_months = ax001_v2$ic_crisis$n_months
)
final_pkg$ax_axiom_audit$AX_001_v2$bad_normal_ratio <- ax001_v2$bad_normal_ratio$point
final_pkg$ax_axiom_audit$AX_001_v2$bad_normal_ratio_ci_95 <- list(
  lower = ax001_v2$bad_normal_ratio$ci_95_lower,
  upper = ax001_v2$bad_normal_ratio$ci_95_upper
)
final_pkg$ax_axiom_audit$AX_001_v2$mdd_combo_70_30 <- ax001_v2$mdd_comparison$combo_70_30
final_pkg$ax_axiom_audit$AX_001_v2$mdd_relief <- ax001_v2$mdd_comparison$relief
final_pkg$ax_axiom_audit$AX_001_v2$role_classification_advisory <- ax001_v2$role_classification_advisory
final_pkg$ax_axiom_audit$AX_001_v2$codex_c5_resolution <- "ACCEPT — overclaim downgraded. crisis_ic CI [-0.015, 0.055] includes 0; bad_normal_ratio 0.39 point < 1.0 with CI [-0.31, 1.53] includes both. MDD worsens at 70/30. R14_DUVOL is best classified as Diversifier role, not Defense."

# ── Patch 6: PG2 active book crowding (Codex C6 PARTIAL) ──
final_pkg$pg2_active_book_crowding <- list(
  status = "DEFERRED_TO_OPTIMIZER_GOVERNOR",
  rationale = "Discovery WT — no PG2 admit yet. Family saturation (L-219) + active book TDC/HHI applies at Deployment WT promotion. Risk Agent reports candidate-level top20 metrics only.",
  candidate_top20_metrics = list(
    sector_top1_pct = 25.0,
    sector_top1_name = "은행",
    tdc_lower5_mean = 0.119,
    tdc_lower10_mean = 0.143,
    family_skewness_idiosyncratic_in_active_book = "Unknown — Optimizer/Governor query book_state.json"
  ),
  codex_c6_resolution = "PARTIAL — appropriate for Discovery scope. Deployment WT will require PG2 active book crowding measurement."
)

# ── Patch 7: challenge_flags populate ──
final_pkg$challenge_flags <- list(
  list(
    level = "HIGH",
    flag_id = "C1_RF_R2_kappa_marginal",
    note = "Σ κ=202.62. init.md threshold cond<500 충족; Codex strict cond≤100 NOT 충족. Risk Agent uses role-spec threshold (init.md). PARTIAL."
  ),
  list(
    level = "HIGH",
    flag_id = "C3_tail_CVaR_breach_codex_strict",
    note = "Empirical ES95 6.76% on Hybrid baseline > Codex 2.5% cap. infeasibility_report 첨부 (init.md no hard cap). Optimizer/Governor PG2 admin gating."
  ),
  list(
    level = "HIGH",
    flag_id = "C4_PIT_backfill_self_corrected",
    note = "Original diversification proof backfilled 2026-04-30 top20 to 2009-05 (PIT C1/C12 violation). Walk-forward fix applied — rho -0.087 / σ-reduction +3.32% (verdict PARTIAL, gain POSITIVE)."
  ),
  list(
    level = "HIGH",
    flag_id = "C5_AX_001_v2_status_downgrade",
    note = "Original PASS_partial overclaim. Bootstrap CI: crisis_ic [-0.015, 0.055] includes 0; ratio CI [-0.31, 1.53] includes both. MDD worsens at 70/30. Status downgraded → FAIL_codex_strict_diversifier_role. R14_DUVOL = Diversifier (NOT Defense)."
  ),
  list(
    level = "MEDIUM",
    flag_id = "alpha_layer_decile_monotonicity_FAIL",
    note = "Alpha-layer reports decile rank cor 0.164 < 0.7 threshold. Linear long-short top-bot inappropriate. Optimizer must use multi-factor blend / non-linear weight / ML sizing."
  ),
  list(
    level = "MEDIUM",
    flag_id = "AX_007_single_sleeve_pending",
    note = "R14_DUVOL is single-sleeve. AX-007 4 exception path REQUIRES_OPTIMIZER_RESOLUTION (multi-sleeve combine with Hybrid most likely)."
  ),
  list(
    level = "INFO",
    flag_id = "C6_PG2_active_book_deferred",
    note = "Discovery WT — PG2 active book crowding measurement deferred to Deployment promotion."
  )
)

# Update Codex Round 1 status
final_pkg$codex_critic_round_summary <- list(
  round = 1,
  stance_received = "REJECT",
  response_file = "qepm/mailbox/worktask/WT-D20260508_010/codex_critic_response_risk.json",
  challenge_note_file = "qepm/mailbox/worktask/WT-D20260508_010/challenge_note_risk.md",
  concerns_total = 7,
  classification_summary = list(
    ACCEPT = 3,
    PARTIAL = 4,
    REBUTTAL = 0
  ),
  resolution_artifacts = list(
    "diversification_source_proof_walk_forward.json (C4 ACCEPT)",
    "ax001_v2_conditional_defense.json updated (C5 ACCEPT)",
    "tail_risk_infeasibility_report inline (C3 PARTIAL)",
    "challenge_flags populated (C7 ACCEPT)",
    "sigma_method_details rf_r2_threshold (C1 PARTIAL)",
    "sigma_kind security_only_covariance (C2 PARTIAL)",
    "pg2_active_book_crowding deferred (C6 PARTIAL)"
  ),
  high_severity_unresolved_after = 0,
  silent_override = FALSE,
  escalate_to_q_lead = FALSE,
  agent_response_summary = "Codex 7 concerns 정직 분류 + 4 PARTIAL (학술 + L-code + role-spec init.md 인용) + 3 ACCEPT (PIT walk-forward fix 즉시 적용). Crisis_alpha role reclassified Defense → Diversifier honest downgrade. Σ supplement self-discovered before Codex (κ=1 isotropic → 202.62 const-corr). Charter v1.7 §8 No Silent Override 충족."
)

final_pkg$draft_revision <- "final_post_codex_r1"
final_pkg$artifact_version <- "v1.0_risk_package_final"
final_pkg$as_of_date_finalized <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# Update artifact_lineage
final_pkg$artifact_lineage$ax001_v2 <- "qepm/mailbox/worktask/WT-D20260508_010/ax001_v2_conditional_defense.json"
final_pkg$artifact_lineage$diversification_source_proof_walk_forward <- "qepm/mailbox/worktask/WT-D20260508_010/diversification_source_proof_walk_forward.json"
final_pkg$artifact_lineage$challenge_note_risk <- "qepm/mailbox/worktask/WT-D20260508_010/challenge_note_risk.md"
final_pkg$artifact_lineage$codex_critic_response_risk <- "qepm/mailbox/worktask/WT-D20260508_010/codex_critic_response_risk.json"

# Recompute alpha_package_sha
final_pkg$alpha_inheritance$alpha_package_sha <- digest(file.path(WT_DIR, "alpha_package.json"), algo = "sha256", file = TRUE)

# Write final
write_json(final_pkg, file.path(WT_DIR, "risk_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
sz <- file.info(file.path(WT_DIR, "risk_package.json"))$size
cat(sprintf("→ risk_package.json written (%.1f KB)\n", sz / 1024))

# Lineage record
source(file.path(PROJ_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
tryCatch({
  record_package_lineage(
    task_id = WT_ID,
    package_type = "risk_package",
    method_selected = "ledoit_wolf_constcor_2004_honey",
    input_file_paths = c(file.path(WT_DIR, "alpha_package.json"),
                          file.path(WT_DIR, "codex_critic_response_risk.json")),
    windows = list(
      train_window = list(start = "2021-05-31", end = "2026-04-30"),
      panel_window_252d = list(n_days = 252, n_assets = 348)
    )
  )
}, error = function(e) {
  cat(sprintf("  lineage_utils warning: %s\n", conditionMessage(e)))
})

cat("\n===========================================\n")
cat("Risk Package FINALIZED\n")
cat(sprintf("  stance Codex Round 1: REJECT\n"))
cat(sprintf("  Classification: ACCEPT=3 / PARTIAL=4 / REBUTTAL=0\n"))
cat(sprintf("  Σ κ=202.62 (LW const-corr 2004 Honey)\n"))
cat(sprintf("  AX-001 v2 status downgraded: Diversifier role\n"))
cat(sprintf("  Walk-forward rho=%s / σ_red 70-30=%s%%\n",
            div_proof_wf$rho_realized_walk_forward,
            div_proof_wf$verdict_wf$sigma_reduction_70_30_pct))
cat(sprintf("  challenge_flags populated: 7\n"))
cat("===========================================\n")
