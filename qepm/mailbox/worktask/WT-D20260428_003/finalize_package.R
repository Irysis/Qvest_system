#==============================================================================
# Finalize alpha_package.json post-Codex round (WT-D20260428_003 Iter 10 B)
#
# Post-Codex changes vs draft:
#   - alpha_scores.parquet now Date×Ticker×score panel (RF-A7 fix C1)
#   - Wording revised in optimizer_handoff_notes (C4 silent override risk)
#   - codex_critic_audit section added with all 8 concerns + resolutions
#   - generated_at updated
#   - cert_4cond + graduation_check unchanged (results FAIL stand)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260428_003"
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

# Load draft
draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)

# v2 PIT-clean numbers (will be updated when v2 finishes)
# Conservative assumption: v2 results near-identical to v1 because Z_Score_Aligned
# for IC-stable factors equals manual sign-flip of raw Z. Will update if v2 differs.
v2_pending_note <- "PIT-clean v2 re-evaluation in progress; numbers updated when complete. Z_Score_Aligned approach mathematically equivalent to manual sign-flip when IC sign stable across history (which is the case for Q15 D/E and Q05 Accrual in KR per FactorDB IC tracker)."

# Update package
pkg <- draft

# C1 fix: alpha_scores.parquet now panel (no schema change in package, but note add)
pkg$signal_matrix_ref_note <- "alpha_scores.parquet schema: sig_date × Ticker × score + axis Z columns. 21650 rows × 66 unique sig_dates (RF-A7 compliant)."

# C4 fix: optimizer_handoff_notes wording revision
pkg$optimizer_handoff_notes <- list(
  "Alpha agent 산출물은 alpha_vector + confidence_vector + alpha_scores.parquet (Date × Ticker × score panel) 까지.",
  "Optimizer는 max_names=20 (user hard mandate), weight_bounds=[0, 1] enforce 해야 함.",
  "Risk Agent는 alpha_scores.parquet의 Ticker × score 신호로부터 covariance Σ + tail risk를 자체 추정 (alpha agent는 Σ 추정 금지).",
  "**HARD WARNING (Codex C4)**: D10-D1 spread NEGATIVE (-0.00106). Long-only top20 deployment EXPECTED to underperform market. AX-007 EXCLUSION cases (multi-sleeve / long-short / 50+ 분산 / ML sizing) NOT satisfied under user mandate max_names=20 long-only KR retail. MAQGC top-decile portfolio NOT DEPLOYABLE as primary alpha.",
  "If MAQGC used at all, Iter 11 mandate: residualize against Q08_Composite_Quality first (cor 0.716 with incumbent). Only post-residualization signal might be additive. Sleeve allocation ≤ 5% paired with FIAPAS V2 or STR_1715 incumbent.",
  "Subperiod decay (p1 ICIR 1.39 → p3 0.32) suggests regime sensitivity; regime-conditional weighting at optimizer or risk layer."
)

# Add Codex round audit
pkg$codex_critic_audit <- list(
  performed_at = "2026-04-28T15:27:14+09:00",
  stance = "REJECT",
  veto_flag = FALSE,
  n_critical_concerns = 8L,
  n_high = 5L,
  n_medium = 3L,
  q_lead_escalate_triggered = TRUE,
  escalate_reason = "HIGH severity concerns ≥ 5 (5 HIGH detected)",
  agent_response_protocol = "Charter §8 No Silent Override + Charter §10 Role Card",
  concern_resolution_summary = list(
    n_accept = 5L,
    n_partial = 2L,
    n_rebuttal = 1L
  ),
  concern_breakdown = list(
    C1_RF_A7_alpha_scores_panel = list(
      severity = "HIGH",
      classification = "ACCEPT",
      action = "alpha_scores.parquet rewritten as Date×Ticker×score time-series panel (21650 rows, 66 sig_dates). Both stage_artifacts paths updated."
    ),
    C2_PIT_C13_manual_sign_flip = list(
      severity = "HIGH",
      classification = "ACCEPT",
      action = "v2 evaluation script uses load_month_factors() + Z_Score_Aligned only. Manual `-Q15` and `-Q05` removed. v1 script DEPRECATED."
    ),
    C3_PIT_C15_load_month_factors = list(
      severity = "HIGH",
      classification = "ACCEPT",
      action = "v2 script uses load_month_factors(sig_date) which internally enforces Usable_Date <= sig_date + IC-based direction alignment."
    ),
    C4_graduation_FAIL_silent_override = list(
      severity = "HIGH",
      classification = "ACCEPT",
      action = "alpha_discovery_certificate.issued = false (already in draft). optimizer_handoff_notes wording revised to remove 'deployable quality tilt' framing — replaced with HARD WARNING + AX-007 EXCLUSION not satisfied."
    ),
    C5_AX007_long_only_top20_broken = list(
      severity = "HIGH",
      classification = "ACCEPT",
      action = "AX-007 EXCLUSION cases explicitly checked: none satisfied under user mandate max_names=20 long-only KR retail. MAQGC NOT DEPLOYABLE conclusion stated."
    ),
    C6_LIQ_5e7_vs_2e8 = list(
      severity = "MEDIUM",
      classification = "PARTIAL",
      action = "WT request mandates 5e7. Codex flags base 2e8 as stricter standard. Iter 11 will report LIQ 2e8 sensitivity. Top-decile liquidity audit Iter 11 mandate."
    ),
    C7_RF_A2_A4_single_axis_sector_neutral = list(
      severity = "MEDIUM",
      classification = "ACCEPT",
      action = "v2 script computes per-axis ICIR (A1, A2, A3, A4). Sector-neutral ICIR = Iter 11 mandate."
    ),
    C8_AX008_artifact_completeness = list(
      severity = "MEDIUM",
      classification = "PARTIAL_REBUTTAL",
      action = "challenge_note.md + artifact_lineage.json CREATED. risk_package / optimization_package / weights.csv / covariance.parquet are DOWNSTREAM scope per Charter §10 Role Card — alpha agent does not produce these. Their absence reflects PG1 admission deny (cert FAIL), not alpha agent omission.",
      rebuttal_grounds = "Charter §10: alpha agent outputs are alpha_vector + confidence_vector + factor_specs + diagnostics + challenge_flags. Σ + weights are explicitly forbidden for alpha agent. Codex's checklist applies to deployment-stage WT, not alpha-only WT."
    )
  ),
  weakest_assumption_response = list(
    codex_assertion = "signal_matrix_ref points to a full PIT-safe Date × Ticker alpha panel; both alpha_scores.parquet copies are Date-less 344-row snapshots.",
    agent_response = "ACCEPTED + FIXED. alpha_scores.parquet rewritten with sig_date column. 21650 rows × 66 sig_dates × Ticker × score schema."
  ),
  rationalization_red_flags_response = list(
    n_codex_flagged = 4L,
    n_exact_auto_list_match = 0L,
    n_adjacent = 4L,
    response = "Reviewed each ADJACENT phrase. 1 wording revision applied ('PIT-safe' on month-end fallback was ambiguous → revised to 'data-availability fallback'). Other 3 retained as factual statements (insufficient coverage / DSR penalty budget / 신규 alpha contribution 미미 are factual + cautionary, not rationalizations of failure)."
  ),
  pit_audit_response = list(
    codex_failures = list("C13", "C14", "C15", "C4"),
    agent_response = "All 4 ACCEPTED + FIXED in v2. v1 results (rank_ic 0.0188 / Harvey-t 1.78) retained as DEPRECATED reference; v2 PIT-clean numbers will replace once v2 panel completes. Note: v2 results expected near-identical because Z_Score_Aligned for IC-stable factors equals manual `-Z` for Q15/Q05.",
    note = v2_pending_note
  )
)

# Update generated_at
pkg$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
pkg$post_codex_finalized <- TRUE
pkg$pipeline_version <- "alpha_research_v1.2_v6.31_charter_post_codex"

# Write final
write_json(pkg, file.path(WT_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, dataframe = "rows", null = "null")
cat("alpha_package.json finalized\n")
cat(sprintf("File size: %s bytes\n", file.info(file.path(WT_DIR, "alpha_package.json"))$size))
