# ============================================================================
# Cycle 8 build_final.R — risk_package.json finalize (post-Codex disposition)
# ============================================================================
# Step 5 v6.0 Codex Critic Round 5단계 흐름 마지막 단계
# (Step 1 draft + Step 2 codex auto-trigger + Step 3 review + Step 4 challenge_note + Step 5 final)
# ============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WORK <- file.path(ROOT, "qepm/mailbox/research/risk_cycle8_20260507")
setwd(WORK)

cat("Cycle 8 build_final.R start\n")

# Read draft
draft <- read_json(file.path(WORK, "risk_package_draft.json"))
cat(sprintf("Draft loaded: cycle=%d task_id=%s version=%s\n",
            draft$cycle, draft$task_id, draft$version))

# Read Codex response
codex <- read_json(file.path(WORK, "codex_critic_response_risk.json"))
cat(sprintf("Codex stance: %s, concerns: %d\n",
            codex$stance, length(codex$critical_concerns)))

# Update version and add codex disposition
draft$version <- "v2_post_codex_round_disposition_final"
draft$research_type <- "stambaugh_2015_3source_post_publication_retest_post_codex_disposition"

# Add codex disposition full status (replacing pre-codex stub)
draft$codex_critic_round_status <- list(
  stage = "post_codex_round_disposition_final",
  draft_path = "qepm/mailbox/research/risk_cycle8_20260507/risk_package_draft.json",
  codex_response_path = "qepm/mailbox/research/risk_cycle8_20260507/codex_critic_response_risk.json",
  challenge_note_path = "qepm/mailbox/research/risk_cycle8_20260507/risk_challenge_note.md",
  codex_stance = "REJECT",
  codex_veto = FALSE,
  codex_concerns_count = 8L,
  codex_severity_distribution = list(HIGH = 7L, MEDIUM = 1L),
  codex_weakest_assumption = codex$weakest_assumption,
  consecutive_codex_reject = "8 cycles (1+2+3+4+5+6+7+8) — meta path saturation 결정적 추가 evidence",
  disposition_summary = list(
    ACCEPT = c("C1", "C2", "C4", "C5", "C7", "C8"),
    PARTIAL_REBUTTAL = c("C3", "C6"),
    REBUTTAL_only = list(),
    self_correction_log = "C8 ACCEPT_via_creation - challenge_note 본 작성으로 No Silent Override 의무 직접 충족"
  ),
  rationalization_corrections_count = 0L,
  rationalization_corrections = list(),
  cycle8_codex_value = "C2 security-level Σ formal blocker retain confirm + C3 CRISIS n=7 small sample + C6 decay fragile partial-rebuttal Bayesian aggregate 정당화. 사이클 8 Stambaugh framework value (axis 1 retest + axis 2 copula + axis 3 forward) + Codex critic round 8th consecutive REJECT — formal lifecycle path forward 명백",
  rationalization_red_flags_codex_disposition = list(
    list(flag = "TERMINATE_BENEFICIAL_DECAY_FRAMEWORK_COMPLETE",
         disposition = "scope_disclaimer 메타 리서치 명시 + 정식 lifecycle path 권고 retain — 합리화 X"),
    list(flag = "framework saturated",
         disposition = "7 consecutive Codex REJECT + 8 cycle 누적 정량 — descriptive 사실"),
    list(flag = "Hybrid extreme tail diversification confirmed",
         disposition = "Student-t df=20.2 Gaussian limit + Clayton theta 0.077 — empirical evidence (axis 2) descriptive"),
    list(flag = "formal lifecycle scope",
         disposition = "formal_lifecycle_blocker_list 14 명시 + ACCEPT C1/C2/C4/C7 — 회피 X"),
    list(flag = "n=8 noise 가능성 → 확정 evidence",
         disposition = "small sample noise dominant evidence 정직 표기 + Student-t copula 추가 evidence + cycle 8 n=7 변화 정량"),
    list(flag = "AT_LIMIT_NO_FURTHER_ESTIMATOR_ADDITION",
         disposition = "R2-C 상한 5 init prompt 명시 — 정합")
  )
)

# Update termination_decision with Codex post-disposition
draft$cycle8_termination_decision$decision <- "TERMINATE_BENEFICIAL_DECAY_FRAMEWORK_COMPLETE_FORMAL_LIFECYCLE_OBLIGATION_INHERITED"
draft$cycle8_termination_decision$decision_post_codex <- "TERMINATE_BENEFICIAL — 8 codex concerns 5 ACCEPT + 2 PARTIAL_REBUTTAL + 1 ACCEPT_via_creation. consecutive 8 cycles Codex REJECT + 7 HIGH severity → formal lifecycle path forward 의무 결정적"

# formal_lifecycle_blocker_list cycle 8 신규 #15 추가 (C6 likelihood sigma sensitivity)
draft$cycle8_termination_decision$formal_lifecycle_blocker_list$blocker_15_NEW <-
  "Bayesian likelihood sigma 0.15 sensitivity analysis 부재 (Codex C6 PARTIAL_REBUTTAL) — 정식 lifecycle hierarchical Bayesian (각 source decay → meta-sigma estimation) 적용 의무"

# Add Q-Lead recommended actions reflect Codex
draft$cycle8_termination_decision$next_action_recommendation$action_6_codex_disposition_action <-
  "monitoring agent + 다음 risk-research lifecycle WT 모두 cycle 8 Codex disposition reflect — security-level Σ 5-estimator full compare + EVT-GPD MLE + 8 named stress + bootstrap CI all PIT regime fallback rules"

# Add q_lead_escalate update
draft$q_lead_escalate$trigger_criteria$consecutive_codex_reject <- 8L
draft$q_lead_escalate$trigger_criteria$cycle8_codex_severity_high <- 7L

draft$q_lead_escalate$escalate_summary <- paste0(
  "Cycle 8 Stambaugh 2015 RFS 3-source post-publication retest 정량 완료. ",
  "AR 36.9% / TSMOM 25.5% (mid-sample proxy) / KR10y 77.5% decay. ",
  "Welch t individually 미유의 (p>0.05) but Bayesian posterior μ=0.44 σ=0.08 95% CI [0.28, 0.60] 강한 aggregate signal. ",
  "Stambaugh 11-anomaly 56% base rate와 통계적 차이 미유의 (p=0.61) — typical published anomaly path. ",
  "3-source decay innovation 무상관 (max |cor| 0.15) + Student-t copula df=20.2 Gaussian limit + TDC ≈ 0 - Hybrid level diversification effective. ",
  "Hybrid 60m forward SR 1.71→1.36 (-20.3%). 도훈 SR 2.0 target gap 악화 0.29→0.64. ",
  "Codex 8 concerns disposition: ACCEPT 5 + PARTIAL_REBUTTAL 2 + ACCEPT_via_creation 1. ",
  "consecutive 8 cycles Codex REJECT — meta path saturation 결정적. ",
  "formal lifecycle path 진입 시점 적정 — TERMINATE_BENEFICIAL_DECAY_FRAMEWORK_COMPLETE."
)

# Add monitoring handoff extension JSON
monitoring_extension <- list(
  inheritance = "cycle 7 monitoring_handoff_alerts_20260507.json + cycle 8 acceleration thresholds 추가",
  cycle8_acceleration_thresholds = list(
    P3a_AR_acceleration_60m_sr = list(
      warning = 1.3032, critical = 0.9355,
      rationale = "Bayesian posterior μ/2 = warning, μ = critical (μ=0.4401)",
      current = 1.6709, status = "OK_above_warning"
    ),
    P3b_TSMOM_acceleration_60m_sr = list(
      warning = 0.4618, critical = 0.3315,
      rationale = "Bayesian posterior μ/2 = warning, μ = critical",
      current = 0.5921, status = "OK_above_warning"
    ),
    P3c_KR10y_acceleration_60m_sr = list(
      warning = 0.0551, critical = 0.0395,
      rationale = "Bayesian posterior μ/2 = warning, μ = critical",
      current = 0.0706, status = "OK_above_warning_but_already_severe_decay_inheritance"
    ),
    P3d_AR_reversal_test = list(
      condition = "12m forward SR_60m > 1.50",
      rationale = "Cycle 7 Mann-Kendall tau -0.27 p<0.001 → posterior 1σ rejection",
      check_date = "2027-03-31"
    )
  ),
  monitoring_frequency = "monthly_post_2026_06_01",
  next_check_date = "2026-06-30",
  citations = c("Stambaugh-Yu-Yuan 2015 RFS",
                "Hwang-Rubesam 2024 momentum disappearance",
                "Mann 1945 Econometrica",
                "Pettitt 1979 JRSS-C",
                "Gelman 2013 BDA3 ch.2")
)

write_json(monitoring_extension,
           file.path(WORK, "monitoring_handoff_extension_cycle8.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("Monitoring extension JSON saved\n")

# Add to draft
draft$monitoring_handoff_extension_path <-
  "qepm/mailbox/research/risk_cycle8_20260507/monitoring_handoff_extension_cycle8.json"

# Update artifacts manifest
draft$artifacts_manifest$primary_json <- c(
  draft$artifacts_manifest$primary_json,
  "monitoring_handoff_extension_cycle8.json",
  "risk_package.json",
  "codex_critic_response_risk.json"
)
draft$artifacts_manifest$challenge_note <-
  "risk_challenge_note.md (Codex 8 concerns 자율 분류 ACCEPT 5 + PARTIAL_REBUTTAL 2 + ACCEPT_via_creation 1)"
draft$artifacts_manifest$primary_json <- unique(draft$artifacts_manifest$primary_json)

# Drop draft-specific marker
draft$generated_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
draft$cycle8_summary_post_codex <- list(
  axis1_decay_count_positive = 3L,
  axis1_welch_significant_count = 0L,
  axis1_bayesian_posterior_mu = 0.4401,
  axis1_bayesian_posterior_sigma = 0.0795,
  axis1_stambaugh_compare_p_value = 0.613,
  axis2_max_pair_innovation_cor_abs = 0.1465,
  axis2_student_t_df = 20.206,
  axis2_max_tdc_lower = 0.0006,
  axis3_hybrid_60m_decay_pct = 0.2031,
  axis3_hybrid_60m_forward_sr = 1.3645,
  codex_disposition = list(
    ACCEPT = 5L, PARTIAL_REBUTTAL = 2L, ACCEPT_via_creation = 1L,
    REBUTTAL_only = 0L
  ),
  termination = "TERMINATE_BENEFICIAL_DECAY_FRAMEWORK_COMPLETE",
  formal_lifecycle_blocker_list_count = 15L
)

# Write final
write_json(draft, file.path(WORK, "risk_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")
cat(sprintf("risk_package.json finalized: version=%s\n", draft$version))

# Update aggregate dashboard with codex disposition
agg <- read_json(file.path(WORK, "cycle8_aggregate_summary.json"))
agg$codex_disposition <- list(
  stance = "REJECT",
  concerns = 8L,
  severity_HIGH = 7L,
  severity_MEDIUM = 1L,
  ACCEPT = 5L,
  PARTIAL_REBUTTAL = 2L,
  ACCEPT_via_creation = 1L
)
agg$consecutive_codex_reject <- 8L
agg$termination_decision <- "TERMINATE_BENEFICIAL_DECAY_FRAMEWORK_COMPLETE_FORMAL_LIFECYCLE_OBLIGATION_INHERITED"
agg$generated_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
write_json(agg, file.path(WORK, "cycle8_aggregate_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("Aggregate dashboard updated\n")

cat("Cycle 8 build_final.R done\n")
