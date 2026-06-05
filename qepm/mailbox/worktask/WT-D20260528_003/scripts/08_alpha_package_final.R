#==============================================================================
# Step 7 (Final) — Alpha Package Final Emission
#
# Codex Round 5단계:
#   [1] alpha_package_draft.json — DONE
#   [2] codex_critic_response_alpha.json — DONE (REJECT)
#   [3] codex_revisions_round1.json — DONE (PARTIAL fix + diagnostic)
#   [4] challenge_note.md — DONE
#   [5] alpha_package.json (FINAL, no _draft) — THIS STEP
#
# Final alpha_package retains:
#   - Honest graduation FAIL reporting (Charter §8 No Silent Override)
#   - Codex Round outcomes (stance, concerns, agent classification)
#   - regime t-1 lag diagnostic (signal eliminated → mechanism absent)
#   - Single-family vs composite ICIR (dividend 0.21 > composite 0.07)
#   - Strategic pivot recommendation to Q-Lead
#
# Hook validation:
#   - codex_round_pre_enforcer.sh: draft + critic_response 둘 다 존재 ✓
#   - alpha_discovery_certificate eligibility: harvey_t_specs_pass_count = 0 < 3 → ineligible (passive deny per Charter §10)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
MB <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003")
OUT_DIR <- file.path(MB, "outputs")

# ---- Load draft + Codex response + revisions ----
draft <- fromJSON(file.path(MB, "alpha_package_draft.json"), simplifyVector = FALSE)
critic <- fromJSON(file.path(MB, "codex_critic_response_alpha.json"), simplifyVector = FALSE)
revisions <- fromJSON(file.path(OUT_DIR, "codex_revisions_round1.json"), simplifyVector = FALSE)

# ---- Final adjustments ----
final <- draft

# Add Codex Round outcome
final$codex_round <- list(
  round_number = 1L,
  stance = critic$stance,
  veto_flag = critic$veto_flag,
  stance_rationale = critic$stance_rationale,
  weakest_assumption = critic$weakest_assumption,
  n_critical_concerns = length(critic$critical_concerns),
  hard_block_triggered = FALSE,
  agent_classification = list(
    accept = list("C1_empirical_fail", "C2_composite_dilutes_dividend_single"),
    partial = list("C3_pit_c13_c15", "C4_pit_c9_lag", "C7_missing_months"),
    rebuttal = list("C5_ax008_stage_scope", "C6_ax005_007_judge_stage", "C8_liquidity_false_positive")
  ),
  q_lead_escalate_trigger = list(
    high_severity_count = 5L,
    threshold = 5L,
    trigger_fired = TRUE,
    rationale = "C1, C2, C3, C4, C5 HIGH severity. Strategic pivot recommended."
  ),
  rationalization_red_flags = critic$rationalization_red_flags,
  agent_rebuttal_for_each = list(
    C3_rebuttal_summary = "Z_Score_Aligned column 부재 시 학술 spec direction 사용 정합. align_factor_direction() IC-based override 가능하나 v3 학술 spec 채택. C15 production-mode connector 미사용은 deployment 시 의무 — discovery stage 비대상.",
    C5_rebuttal_summary = "alpha-research stage 단독 산출물 = alpha_package + scores + validation + challenge_note. risk_package + optimization_package + weights.csv는 다음 stage agent 책임. AX-008 triangulation은 stage 종료 시점 의미.",
    C6_rebuttal_summary = "Multi-axis composite (6 family × multi-proxy) = AX-005 EXCLUSION 첫 조건 충족. AX-007 EXCLUSION 4종 (multi-sleeve/long-short/50+/ML sizing) 은 judge stage portfolio Gate13 책임. discovery stage hard fail 아님.",
    C8_rebuttal_summary = "A009540 2017-04-28 = liq_pass FALSE (이미 universe 제외). A008560 2023-04-28 = 휴장일 (rawdata.parquet Date missing). Codex false positive."
  )
)

# Update graduation criteria with regime_lag1 (negative diagnostic finding)
final$diagnostics$regime_t_minus_1_lag_test <- list(
  test_description = "Apply 1 trading day lag to regime_state before alpha construction (PIT-C9 strict).",
  rank_ic_original = 0.0121,
  icir_original = 0.0735,
  rank_ic_lag1 = -0.0007,
  icir_lag1 = -0.0040,
  delta_ic = -0.0128,
  delta_icir = -0.0775,
  interpretation = "Signal eliminated under PIT-C9 strict. Implies original signal is data-mining artifact of same-date regime usage. Mechanism (P4 regime → factor weight tilt) does NOT generate forward predictive signal at t+1."
)

# Single-family vs composite (C2 ACCEPT)
final$diagnostics$single_family_vs_composite_icir <- list(
  description = "Compare per-family Z (direction-aligned single proxy composite) ICIR vs P4-weighted composite alpha_score ICIR.",
  composite_icir = 0.0735,
  composite_icir_lag1 = -0.0040,
  single_family_icir = list(
    value = 0.0776,
    quality = 0.0092,
    momentum = -0.1769,
    low_vol = -0.0256,
    size = 0.1633,
    dividend = 0.2081
  ),
  best_single_family = "dividend",
  best_single_family_icir = 0.2081,
  best_single_family_passes_threshold = TRUE,
  composite_dilutes_single_family = TRUE,
  rf_a2_confirmed = TRUE,
  interpretation = "Dividend single-family ICIR (0.2081) exceeds graduation threshold (0.20) and exceeds composite ICIR (0.0735) by 2.8x. Dynamic 6-family blending DILUTES rather than improves signal. Hypothesis mechanism not validated."
)

# Missing months audit (C7 PARTIAL)
final$diagnostics$missing_months_audit <- list(
  expected_months_2017_2023 = 84L,
  actual_months_alpha = 80L,
  missing_months = list("2018-03", "2020-06", "2022-10", "2023-12"),
  missing_2023_12_explanation = "SIGNAL_CUTOFF=2023-12-22 lockbox boundary (normal)",
  missing_others_explanation = "regime classifier walk-forward gap (centroid refit NA accumulation) OR K200+liquidity filter dropping below 100 names. Non-lockbox missing count = 3."
)

# Strategic pivot recommendation
final$strategic_recommendation <- list(
  status = "GRADUATION_FAIL",
  recommendation = "STRATEGIC_PIVOT_REQUIRED",
  rationale = "Empirical mechanism absent. Composite < dividend single. Regime t-1 lag → signal eliminated. Hypothesis (P4 regime → 6-family dynamic blend) not validated on KR KOSPI200 2017-2023 walk-forward.",
  pivot_options = list(
    option_a = list(
      label = "Archive + no follow-up",
      action = "Mark WT-D20260528_003 FAIL, no follow-up WT.",
      pros = "Conservative; preserves capital for higher-EV alternatives.",
      cons = "Investments in regime classifier + factor panel v3 not reused."
    ),
    option_b = list(
      label = "Dividend single-family WT",
      action = "Spawn new discovery WT with hypothesis: KR KOSPI200 dividend tilt (V06_fDY + V11_Shareholder_Yield + V17_Payout_Ratio) standalone alpha. ICIR baseline = 0.2081 (graduation gate PASS).",
      pros = "Established empirical signal. Direct path to deployment.",
      cons = "Single-family long-only top20 = AX-005/007 violation risk. Multi-sleeve + ML sizing mechanism design required pre-Gate13."
    ),
    option_c = list(
      label = "Regime overlay for STR_1715",
      action = "Apply 9-state regime classifier as cash overlay or sleeve rebalance gate for STR_1715 (current PG2). regime is independent input feature.",
      pros = "Reuses regime classifier work. STR_1715 admission state intact.",
      cons = "Overlay impact unverified; may not improve PG2 net of cost."
    )
  ),
  q_lead_decision_required = TRUE
)

# Discovery role card final (alpha_discovery_certificate_eligible = FALSE)
final$alpha_discovery_role_card$alpha_discovery_certificate_eligible <- FALSE
final$alpha_discovery_role_card$certificate_eligibility_reason <- "Harvey-t specs pass count = 0 < 3 required. Charter §10 v1.2 passive deny."

# Update built_at + version
final$built_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
final$codex_round_completed <- TRUE
final$challenge_note_path <- "qepm/mailbox/worktask/WT-D20260528_003/challenge_note.md"

# Add codex round outputs reference
final$codex_round_artifacts <- list(
  draft = "qepm/mailbox/worktask/WT-D20260528_003/alpha_package_draft.json",
  codex_response = "qepm/mailbox/worktask/WT-D20260528_003/codex_critic_response_alpha.json",
  revisions = "qepm/mailbox/worktask/WT-D20260528_003/outputs/codex_revisions_round1.json",
  challenge_note = "qepm/mailbox/worktask/WT-D20260528_003/challenge_note.md",
  final = "qepm/mailbox/worktask/WT-D20260528_003/alpha_package.json"
)

# Write final
write_json(final, file.path(MB, "alpha_package.json"),
            pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("Final alpha_package.json written.\n")

# Lineage record (final)
tryCatch({
  source(file.path(BASE, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = "WT-D20260528_003",
    package_type = "alpha_package",
    method_selected = "P4_regime_kmeans9_BL_shrinkage_6family_smart_beta_FAIL_strategic_pivot_required",
    input_file_paths = c(
      file.path(BASE, ".cache/rawdata.parquet"),
      file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs/p4_multi_horizon.parquet"),
      file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs/regime_factor_weight_matrix_walkforward.parquet"),
      file.path(BASE, "stage_artifacts/WT_D20260528_003/alpha_scores.parquet"),
      file.path(MB, "alpha_package_draft.json"),
      file.path(MB, "codex_critic_response_alpha.json"),
      file.path(MB, "challenge_note.md")
    )
  )
  cat("Lineage recorded (final)\n")
}, error = function(e) {
  cat("Lineage warning:", conditionMessage(e), "\n")
})

# Update status.json
status <- list(
  task_id = "WT-D20260528_003",
  current_phase = "ALPHA_DONE",
  phase = "alpha_complete_graduation_fail",
  status = "GRADUATION_FAIL",
  alpha_research_completed = TRUE,
  codex_round_completed = TRUE,
  codex_stance = "REJECT",
  graduation_pass = FALSE,
  strategic_pivot_recommended = TRUE,
  next_action = "Q_LEAD_REVIEW",
  last_updated = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
write_json(status, file.path(MB, "status.json"), pretty = TRUE, auto_unbox = TRUE)
cat("status.json updated\n")

cat("\n=== Alpha Package FINAL Summary ===\n")
cat("  graduation_pass:           ", final$all_graduation_pass, "\n")
cat("  codex_round_stance:        ", critic$stance, "\n")
cat("  challenge_flags_count:     ", length(final$challenge_flags), "\n")
cat("  discovery_cert_eligible:   ", final$alpha_discovery_role_card$alpha_discovery_certificate_eligible, "\n")
cat("  strategic_pivot_required:  ", final$strategic_recommendation$recommendation, "\n")
cat("  q_lead_escalate_triggered: ", final$codex_round$q_lead_escalate_trigger$trigger_fired, "\n")
cat("\n=== Codex Round 5 단계 완료 ===\n")
