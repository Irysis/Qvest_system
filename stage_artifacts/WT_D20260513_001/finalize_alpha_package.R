#==============================================================================
# Finalize alpha_package.json — v2 PIT-clean + Codex Round 2 disposition.
# Status: MARGINAL_FAIL_NON_GRADUATING (graduation_criteria FAIL on rank_ic + monotonicity)
# challenge_flags populated honestly. Q-Lead escalation required.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART  <- file.path(BASE, "stage_artifacts/WT_D20260513_001")
MBOX <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260513_001")

draft <- fromJSON(file.path(MBOX, "alpha_package_draft.json"), simplifyVector = FALSE)

# Add finalize metadata + Codex round info
final <- draft
final$codex_round_status <- "REJECT_R1_REJECT_R2_DISPOSITION_FINAL"
final$codex_round_summary <- list(
  round1 = list(
    response_file = "codex_critic_response_alpha.json",
    stance = "REJECT",
    weakest = "SIG_DATES first-of-month → factor_date > sig_date in 138/267 dates",
    disposition = "v2 PIT-fix month-end strict applied; 0/268 leak"
  ),
  round2 = list(
    response_file = "codex_critic_response_alpha_round2.json",
    stance = "REJECT",
    weakest = "PIT-C2 same-day circular for D57 with same-month-end factor + close-to-close return",
    disposition = "Honest acceptance of 6 HIGH concerns; non-graduating exploratory submission"
  )
)

final$graduation_status <- list(
  status = "MARGINAL_FAIL_NON_GRADUATING_EXPLORATORY",
  graduation_criteria_5_gates = list(
    rank_ic_min_0_04 = list(measured = 0.0385, target = 0.04, pass = FALSE, gap = -0.0015),
    icir_min_0_20 = list(measured = 0.2113, target = 0.20, pass = TRUE, margin = 0.0113),
    subperiod_stability_min_0_5 = list(measured = 1.0, target = 0.5, pass = TRUE),
    harvey_t_min_3_0 = list(measured = 3.873, target = 3.0, pass = TRUE),
    dsr_min_0_5 = list(measured = 8.864, target = 0.5, pass = TRUE)
  ),
  monotonicity_additional_gate = list(
    measured = 0.25, target = 0.70, pass = FALSE, severity = "HARD_FAIL"
  ),
  pass_count = 4,
  fail_count = 2,
  overall = "FAIL single-sleeve graduation; exploratory evidence retained"
)

# Honest challenge_flags
final$challenge_flags <- list(
  list(
    flag_id = "ALPHA_RANK_IC_GATE_FAIL",
    severity = "HIGH",
    description = "rank_ic 0.0385 < 0.04 mandate by 0.0015. graduation_criteria.min_rank_ic FAIL.",
    silent_override_violation = "Selection rule fallback ('elig <- cmp[ortho_pass==TRUE & !is.na(rank_ic)]') applied without challenge_flag in v2 script. AX-002 violation explicit.",
    disposition = "ACCEPT FULL — non-graduating disclosure"
  ),
  list(
    flag_id = "ALPHA_MONOTONICITY_HARD_FAIL",
    severity = "HIGH",
    description = "monotonicity_q1_q5_concord = 0.25 vs target ≥ 0.70. Decile signal weak.",
    rationalization_attempted_round1 = "Estrada 2007 + Ang-Chen-Xing 2006 인용으로 'mid-quintile noise' 표현 시도",
    rationalization_codex_detected = "Round 2 RF auto-detect 4건: 'mid-quintile noise일 뿐 directional signal은 PASS'",
    disposition = "ACCEPT FULL — self-rationalization 인정, hard fail 사실"
  ),
  list(
    flag_id = "PIT_C2_SAME_DAY_CIRCULAR_SUSPECTED",
    severity = "HIGH",
    description = "D57 factor Date == sig_date (month-end) + forward return = P(next_me_close) / P(sig_me_close) → same-day close circularity 의심. Production 운용 시 t+1 next-business-day open execution lag 의무.",
    disposition = "ACCEPT FULL — forge 단계 t+1 lag 검증 의무 명시"
  ),
  list(
    flag_id = "HARVEY_5SPEC_FF_FAMILY_MISSING",
    severity = "HIGH",
    description = "5-spec multi-test required = CAPM/Carhart-3/Carhart-4/FF5/FF6 regression panel. v2 측정은 IC time-series stress panel (다른 시각). Codex R2 RF-A6 정확.",
    disposition = "ACCEPT FULL — Risk-research 단계 의무 이동"
  ),
  list(
    flag_id = "AX005_007_MULTI_SLEEVE_EXCEPTION_NOT_PROVEN",
    severity = "HIGH",
    description = "AX-005 v1.2 EXCLUSION = necessary not sufficient. multi-sleeve exception은 portfolio-level evidence 필요 (weights/cov/MDD/SR). 본 cycle alpha-research 단계에서 미입증.",
    disposition = "ACCEPT FULL — downstream Risk/Optimizer/Forge evidence 의무"
  ),
  list(
    flag_id = "LOCKBOX_SPLIT_MISSING",
    severity = "MEDIUM",
    description = "Pre-LB / Lockbox / Combined 3-way diagnostics split 미적용. 전기간 2004-2026 평가만 진행.",
    disposition = "ACCEPT — post-cycle 의무"
  ),
  list(
    flag_id = "SECTOR_NEUTRAL_POST_TEST_MISSING",
    severity = "MEDIUM",
    description = "D57_Down_Vol → sector dummies residualization 후 IC/ICIR 재측정 미진행.",
    disposition = "ACCEPT — Risk-research 단계 가능"
  )
)

# Patch pit_compliance to honest disclose
final$pit_compliance$C2_no_same_day_circular <- "SUSPECTED_VIOLATION — D57 same-month-end factor + close-to-close return. forge stage t+1 lag mandate."
final$pit_compliance$C1_rolling_only <- "PASS (factor_db monthly snapshot); but 2004-2026 full sample retained without Pre-LB/Lockbox split — disclosure"

# Q-Lead escalation flag
final$q_lead_escalation <- list(
  triggered = TRUE,
  trigger_rule = "HIGH severity concerns >= 5 (Codex Round 2: 5 HIGH)",
  honest_metrics = list(
    rank_ic = 0.0385, target = 0.04, status = "FAIL marginal",
    monotonicity = 0.25, target = 0.70, status = "FAIL hard",
    icir = 0.2113, target = 0.20, status = "PASS marginal",
    harvey_t = 3.873, target = 3.0, status = "PASS",
    dsr = 8.864, target = 0.5, status = "STRONG PASS",
    orthogonality = "STRICT PASS (cor 0.054 / -0.009 vs STR_1715)",
    pit_leakage = "0/268 v2 clean"
  ),
  options_for_dohun = list(
    option_A_abandon_low_vol = "Other family (deep value FF residual / quality multi-axis / behavioral flow) re-explore",
    option_B_exploratory_retain = "본 alpha를 Optimizer 4-sleeve composite의 4th sleeve로 portfolio-level admission 시도",
    option_C_other_lowvol_variant = "Sector-neutral / t+1 lag / FF3 residual decomposition 변형 재실험"
  ),
  recommendation = "Option B (exploratory retain) — ICIR/Harvey-t/DSR/Orthogonality 모두 PASS. signal 자체는 noise 아님. monotonicity weak는 portfolio-level mitigation 가능. 단 단독 graduation criteria FAIL 명시 + Optimizer/Risk 단계로 admission 판정 위임."
)

# Update version
final$version <- "v2_FINAL_post_codex_R2_REJECT_marginal_fail_disclosure"

# Write finalized (no _draft suffix)
write_json(final, file.path(MBOX, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("alpha_package.json (FINAL) written.\n")
cat("  graduation_status:", final$graduation_status$overall, "\n")
cat("  pass_count:", final$graduation_status$pass_count, "/ 5 gates +1 mono\n")
cat("  challenge_flags:", length(final$challenge_flags), "\n")
cat("  q_lead_escalation: triggered =", final$q_lead_escalation$triggered, "\n")
