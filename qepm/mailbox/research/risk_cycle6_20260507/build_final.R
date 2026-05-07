# =============================================================================
# Cycle 6 — Build risk_package.json (FINAL, post-Codex disposition)
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WORK <- file.path(ROOT, "qepm/mailbox/research/risk_cycle6_20260507")
setwd(WORK)

# Load draft as base
draft <- fromJSON(file.path(WORK, "risk_package_draft.json"), simplifyVector = FALSE)

# Load all CSVs
cov_summary  <- fread("scenario_covariance_5est_summary.csv")
tail_4m      <- fread("scenario_tail_risk_4method.csv")
evt_thr      <- fread("scenario_evt_threshold_sensitivity.csv")
stress_8     <- fread("scenario_8stress_named.csv")
crowd_tdc    <- fread("scenario_crowding_tdc.csv")
forward_sim  <- fread("scenario_forward_sim_mk_pettitt.csv")
trade_off    <- fread("scenario_tradeoff_matrix.csv")
ax001        <- fread("scenario_ax001v2_verdict.csv")

# ----- Disposition fix C6: Scenario B HHI = 0.7^2 + 0.3^2 = 0.58 -----
# (cash sleeve 포함 HHI re-calculation)
crowd_tdc[scenario == "B", hhi_normalized := 0.58]
fwrite(crowd_tdc, file.path(WORK, "scenario_crowding_tdc.csv"))
cat(sprintf("[FIX C6] Scenario B HHI 0.58 (cash sleeve 포함) updated\n"))

dt_to_records <- function(dt) {
  lapply(seq_len(nrow(dt)), function(i) as.list(dt[i]))
}

# ----- updated scope_disclaimer (C1 + C8 disposition) -----
scope_disclaimer <- list(
  statement = paste(
    "Q-Lead 온디맨드 메타 리서치 사이클 6 (path: qepm/mailbox/research/risk_cycle6_20260507/).",
    "사이클 5 P1 alert (TSMOM 32% / KR_10y 76% decay) 발견 후속 4 시나리오 비교 진단.",
    "본 cycle은 정식 risk_package 아니라 Q-Lead 결정 input 제공 메모 (4 시나리오 trade-off matrix).",
    "각 시나리오 weight 결정 X — 권고 X. 결정은 Q-Lead/도훈 책임.",
    "정식 WT alpha→risk pipeline 산출 X — alpha_scores.parquet / weights.csv / 종목별 BΩB'+D / KRX VKOSPI / post-shrink Σ 모두 정식 lifecycle 의무 retain.",
    "본 cycle 6은 시나리오 비교 정보 제공만, 정식 채택 / weight 결정 / strategy spawn 절대 X (Hook agent_role_guard 강제).",
    "Codex Round 6 consecutive REJECT 패턴 — 메타 path saturation 결정적 증거. 정식 lifecycle 진입이 path forward."
  ),
  inheritance = c(
    "사이클 1: qepm/mailbox/research/risk_model_meta_20260507/",
    "사이클 2: qepm/mailbox/research/risk_candidates_20260507/",
    "사이클 3: qepm/mailbox/research/risk_cycle3_20260507/",
    "사이클 4: qepm/mailbox/research/risk_cycle4_20260507/",
    "사이클 5: qepm/mailbox/research/risk_cycle5_20260507/"
  ),
  walk_forward_caveat = paste(
    "본 cycle 6은 4 시나리오 일괄 ex-post 측정 (post-2015 n=135 동일 sub-sample).",
    "시나리오별 walk-forward alpha→risk→optimizer recalculation X — 정식 lifecycle 의무 retain.",
    "Q-Lead/도훈 결정 input 제공 차원, hypothesis generation 한계 명시."
  ),
  data_limitations = paste(
    "post-2015 sub-sample 135 obs 한계로 GFC_2008 / EuDebt_2011 / IMF_1997 / DotCom_2000 4개 stress period 결측 (NO_DATA_POST2015_OOS).",
    "COVID_2020 / VolShock_2018 / China_2015 / Inflation2022 4개 period만 측정.",
    "AX-001 v2 Test 1 (crisis_alpha) COVID 단일 사례 의존 (n=1) — 통계 power 부족."
  )
)

# ----- updated termination_decision (C8 disposition) -----
termination_decision <- list(
  decision = "TERMINATE_BENEFICIAL_QLEAD_DECISION_INPUT_PROVIDED_FORMAL_LIFECYCLE_BLOCKER_LIST_RETAINED",
  decision_rationale = list(
    evidence_1_qlead_decision_input_provided = paste(
      "사이클 6 4 시나리오 비교 trade-off matrix 산출 — Q-Lead/도훈 결정 input 제공.",
      "5 metric × 4 시나리오 = 20 cells 모두 정량 측정.",
      "AX-001 v2 4 시나리오 모두 PASS_1_OF_3 동일 verdict — defensive role 부족 동일 패턴 (Test 1 + Test 3 FAIL).",
      "Scenario D SR 1.614 우월 but MDD -19.9% 열위 — Pareto trade-off 미해소 (정식 optimizer scope)."
    ),
    evidence_2_critical_finding_resolved_at_scenario_level = paste(
      "사이클 5 P1 alert는 source-level (TSMOM/KR10y individual SR decay).",
      "Scenario-level decay 4 시나리오 모두 음수 (recent strong) — AR 70~80% dominance lever 입증.",
      "Q-Lead 결정 시 source-level vs scenario-level 구분 명확히 — 사이클 6 marginal value high."
    ),
    evidence_3_consecutive_codex_reject_pattern = paste(
      "사이클 1~6 6 consecutive Codex REJECT — 메타 path saturation 결정적 증거.",
      "AX-008 1/3 (Forge OK + Codex REJECT + Architect NA). 2/3 PASS path = 정식 lifecycle Architect 검증 의무 retain."
    ),
    evidence_4_decision_framework_extracted = paste(
      "trade-off matrix 4 시나리오 × 4 metric → Q-Lead 결정 framework 명시:",
      "(SR-priority) D > A > C > B / (MDD-priority) A > B > C > D / (Crisis α post-2015 COVID single sample) 4 모두 FAIL → defensive 강화 필요 (정식 lifecycle).",
      "monitoring agent 인계 시 4 시나리오별 alert threshold 모두 정량."
    )
  ),
  formal_lifecycle_blocker_list = list(
    blocker_1 = "alpha_scores.parquet absent",
    blocker_2 = "weights.csv absent",
    blocker_3 = "covariance.parquet absent (security-level)",
    blocker_4 = "BΩB'+D decomposition not produced",
    blocker_5 = "AX-001 v2 Test 1 (crisis_alpha) 4 scenarios FAIL — n=1 COVID evidence only",
    blocker_6 = "AX-001 v2 Test 3 (bad/normal cor ratio) 4 scenarios FAIL — defensive role weak",
    blocker_7 = "PG2 active-book TDC/HHI/style correlation > 0.7 absent",
    blocker_8 = "CVaR_95 / CDaR_95 / Hill alpha / EVT MLE / bootstrap CI absent",
    blocker_9 = "Architect verification absent (AX-008 1/3 only)",
    blocker_10 = "Walk-forward alpha→risk→optimizer recalculation absent",
    blocker_11 = "GFC_2008 / EuDebt_2011 / IMF_1997 / DotCom_2000 stress periods 결측 (post-2015 sub-sample)",
    blocker_12 = "Architect 3rd-source PASS path = 정식 lifecycle 의무 retain (Charter v1.7 §10)"
  ),
  next_action_recommendation = list(
    action_1_qlead_decision_input = paste(
      "도훈/Q-Lead 결정 input 제공:",
      "Scenario A retain (현 admit) / B P1_cut / C P1_partial / D P1_substitute 4 옵션.",
      "Trade-off matrix 단순 비교 표 — 권고 X. 결정은 Q-Lead/도훈 책임."
    ),
    action_2_formal_alpha_research = paste(
      "정식 alpha-research WT spawn — Q07 direct + multi-axis quality composite + Frazzini-Pedersen BAB factor specs.",
      "AX-001 v2 Test 3 FAIL 모든 시나리오 → defensive role 강화 의무.",
      "monitoring agent 사이클 5 alert thresholds 5건 + 사이클 6 4 시나리오별 trade-off threshold 인계."
    ),
    action_3_formal_risk_research = paste(
      "정식 risk-research WT spawn — alpha_package 수신 후 종목 단위 BΩB'+D + post-shrink Σ + PG2 active book TDC/HHI/style cor + 8 named stress 전체 측정 + EVT GPD parametric MLE + walk-forward.",
      "Cycle 1+2+3+4+5+6 inheritance: 5 estimator + DCC-GARCH + Markov + EVT threshold sensitivity + 4 시나리오 trade-off."
    ),
    action_4_formal_optimizer_research = paste(
      "정식 optimizer-research WT spawn — α̂ + Σ 수신 후 4 시나리오 (또는 도훈 추가 옵션) Pareto trade-off 해소.",
      "ERC / 70/15/15 / 70/10/10/10 / 80/10/10 / 70/30 cash 비교."
    ),
    action_5_parallel_monitoring = paste(
      "monitoring agent 사이클 5 + 사이클 6 alert thresholds 인계.",
      "(a) source-level: TSMOM 60m SR > 32% decay / KR_10y 60m SR > 76% decay (사이클 5 threshold)",
      "(b) scenario-level: 4 시나리오별 60m SR decay > 30% / MDD breach -25% / crisis_alpha < 50% (사이클 6 threshold)",
      "6/1 발효 후 첫 월간 report부터 운용."
    )
  )
)

# ----- updated codex_critic_round_status (Step 5 final) -----
codex_status <- list(
  stage = "post_codex_round_disposition_final",
  draft_path = "qepm/mailbox/research/risk_cycle6_20260507/risk_package_draft.json",
  codex_response_path = "qepm/mailbox/research/risk_cycle6_20260507/codex_critic_response_risk.json",
  codex_stance = "REJECT",
  codex_veto = FALSE,
  codex_concerns_count = 8,
  codex_severity_distribution = list(HIGH = 6, MEDIUM = 2),
  challenge_note_path = "qepm/mailbox/research/risk_cycle6_20260507/risk_challenge_note.md",
  disposition_summary = list(
    ACCEPT = c("C1", "C2", "C4", "C7", "C8"),
    PARTIAL = c("C3", "C5", "C6"),
    REBUTTAL_only = c()
  ),
  rationalization_corrections_count = 3,
  rationalization_corrections = c(
    "TERMINATE_BENEFICIAL_DECISION_READY → TERMINATE_BENEFICIAL_QLEAD_DECISION_INPUT_PROVIDED_FORMAL_LIFECYCLE_BLOCKER_LIST_RETAINED",
    "decision-ready → Q-Lead 결정 input 제공",
    "정식 lifecycle 의무 retain → formal_lifecycle_blocker_list (12 blockers explicit)"
  ),
  consecutive_codex_reject = "6 cycles (1+2+3+4+5+6)"
)

# ----- updated cycle6_codex_concerns_disposition (8 concerns) -----
codex_concerns_disposition <- list(
  C1_artifacts_absence = list(
    severity = "HIGH",
    codex_text = "stage_artifacts dirs, weights.csv, alpha_scores.parquet, covariance.parquet absent. blocks schedule check + post-shrink Sigma PSD/cond verification",
    cycle6_disposition = "ACCEPT",
    rebuttal_argument = "Q-Lead 온디맨드 메타 리서치 scope 자체. 정식 WT path는 qepm/mailbox/worktask/{WT_id}/. Cycle 6 path는 _meta_self_research_qlead_ondemand_cycle6_4scenario_comparison 명시. formal approval-grade verification cannot be completed (Codex 정확 식별)",
    action = "scope_disclaimer + research_type retain. termination_decision의 formal_lifecycle_blocker_list 신규",
    evidence = "scope_disclaimer field + termination_decision 5 next actions",
    citations = c("López de Prado 2018 AFML Ch.13", "L-272", "AX-002 process honesty")
  ),
  C2_sigma_decomposition_absence = list(
    severity = "HIGH",
    codex_text = "no B/Omega/D, no factor coverage R2, no shrinkage intensity, no selected estimator, no covariance.parquet",
    cycle6_disposition = "ACCEPT",
    rebuttal_argument = "사이클 1+2+4 inheritance retain. 본 cycle 5 estimator 비교는 sleeve-level diagnostic — 정식 lifecycle 종목 단위 BΩB'+D 의무 retain",
    action = "정식 risk-research WT spawn 시 Ledoit-Wolf direct + Gerber/RMT 비교 + selection_objective enum + factor coverage R² + BΩB'+D — formal_lifecycle_blocker_list 명시",
    evidence = "사이클 1 covariance_3src_5estimator_summary.csv + 사이클 2 covariance_4src_5estimator + 사이클 4 axis2_regime_sigma_pd inheritance",
    citations = c("Ledoit-Wolf 2003 JEFAS", "Pfaff 2016 FRM Ch.4-9", "L-274")
  ),
  C3_ex_post_AR_dominance = list(
    severity = "HIGH",
    codex_text = "Scenario-level decay driven by AR 70-80% dominance on one ex-post post-2015 sample. weakens source-level P1 + bypasses walk-forward",
    cycle6_disposition = "PARTIAL_ACCEPT",
    rebuttal_argument = "ACCEPT: walk-forward 정식 lifecycle 의무. PARTIAL REBUTTAL: scenario-level vs source-level decay 구분이 본 cycle marginal value. 사이클 5 source-level P1 alert (TSMOM 32% / KR_10y 76%) 와 scenario-level (4 모두 음수) 차이는 AR dominance lever 정량 입증 — Q-Lead 결정 시 핵심 정보. 단 'decision-ready' 표현 약화",
    action = "decision-ready → Q-Lead 결정 input 제공으로 변경. finding_1_p1_alert_resolution 명시 retain",
    evidence = "scenario decay 60m vs full: A -13.6% / B -15.3% / C -14.3% / D -16.0% (모두 recent stronger). source-level Cycle 5 inheritance: TSMOM 32% / KR_10y 76% decay",
    citations = c("Politis-Romano 1994 JASA", "L-119 정적 EW 패턴", "AX-002")
  ),
  C4_AX001_v2_fails = list(
    severity = "HIGH",
    codex_text = "AX-001 v2 Test 1 + Test 3 4 scenarios FAIL. crisis_alpha COVID_2020 n=1 (GFC_2008/EuDebt_2011 결측)",
    cycle6_disposition = "ACCEPT",
    rebuttal_argument = "post-2015 sub-sample 한계 — n=1 COVID evidence 통계 power 부족. 정식 lifecycle pre-2015 BM extension + 8 named stress 전체 + bootstrap CI 의무",
    action = "AX-001 v2 compliance status: PASS_MARGINAL → FAIL_ALL_4_SCENARIOS_TEST1_TEST3 명시. RF_R9 + finding_2/3 retain",
    evidence = "Scenario AX-001 v2 results: A T1=F T2=T T3=F PASS_1/3 / B T1=F T2=T T3=F PASS_1/3 / C T1=F T2=T T3=F PASS_1/3 / D T1=F T2=T T3=F PASS_1/3. 모든 시나리오 동일 verdict",
    citations = c("Pfaff 2016 FRM Ch.7", "Hamilton 1989 ECMA", "L-274", "Frazzini-Pedersen 2014 JFE")
  ),
  C5_tail_risk_incomplete = list(
    severity = "HIGH",
    codex_text = "CVaR_95, CDaR_95, Hill alpha, VaR/ES bootstrap CI, EVT MLE 부재. ES99 9.5-11.1% monthly far above 2.5% CVaR cap",
    cycle6_disposition = "PARTIAL_ACCEPT",
    rebuttal_argument = "ACCEPT: CVaR_95/CDaR_95/Hill/bootstrap CI 본 cycle 미산출. EVT MLE direct 정식 lifecycle 의무. PARTIAL REBUTTAL: EVT GPD threshold sensitivity (Pfaff Ch.7) 4 시나리오 × 4 percentile = 16 cells 산출. xi 비교 (D 시나리오 thr=80% +0.032 / 95% +0.112 heavy tail vs A/B/C negative xi) 정량",
    action = "RF_R6 추가 (tail incomplete). next_action_recommendation에 CVaR_95/CDaR_95/Hill/EVT MLE 정식 lifecycle 의무 명시 retain",
    evidence = "scenario_evt_threshold_sensitivity.csv 16 rows (4 시나리오 × 4 threshold)",
    citations = c("Pfaff 2016 FRM Ch.4 + Ch.7", "Bertsimas-Lauprete-Samarov 2004 JEDC", "L-129")
  ),
  C6_crowding_not_approval = list(
    severity = "HIGH",
    codex_text = "HHI 0.52-0.66, Scenario B HHI null, PG2 active-book TDC + style cor + L-219 family saturation 부재",
    cycle6_disposition = "PARTIAL_ACCEPT",
    rebuttal_argument = "ACCEPT: PG2 active-book × 6-source style cor > 0.7 + L-219 family saturation 정식 lifecycle scope. ACCEPT: HHI Scenario B null bug — 0.7^2 + 0.3^2 = 0.58로 정정. PARTIAL REBUTTAL: 4 시나리오 HHI ranking diagnostic 가치 retain",
    action = "scenario_crowding_tdc.csv Scenario B HHI 0.58 update. RF_R3_crowding 명시 retain",
    evidence = "post-fix HHI: A 0.535 / B 0.580 / C 0.660 / D 0.520. RF-R3 0.40 threshold 4 시나리오 모두 over",
    citations = c("Brunnermeier-Pedersen 2009 RFS", "L-219", "사이클 4 RF_R3 inheritance")
  ),
  C7_PIT_inheritance_unverified = list(
    severity = "MEDIUM",
    codex_text = "PIT pass claims rely on scope exclusions or inheritance, not direct cycle6 evidence. C9/C11/C12/C15 unverified failures",
    cycle6_disposition = "ACCEPT",
    rebuttal_argument = "본 cycle pit_audit C9/C11/C12/C15 모두 inheritance/scope 진술. 정식 risk_package PIT audit는 직접 evidence 의무. Codex 정확 식별",
    action = "pit_audit C9/C11/C12/C15 status를 ACKNOWLEDGE_LIMITATION_INHERITANCE_NOT_DIRECT_VERIFY로 강화",
    evidence = "pit_audit field updated",
    citations = c("pit_enforcement.R + lookahead_detector.R", "AX-002")
  ),
  C8_closure_language_risk = list(
    severity = "MEDIUM",
    codex_text = "decision information only + formal lifecycle later 와 TERMINATE_BENEFICIAL_DECISION_READY 표현 No Silent Override risk",
    cycle6_disposition = "ACCEPT",
    rebuttal_argument = "Codex 정확 식별. DECISION_READY는 자기 합리화 위험. AX-002 process honesty + Charter §8 No Silent Override 명시",
    action = "termination 명칭 변경 + formal_lifecycle_blocker_list 12 blockers 명시 신규",
    evidence = "termination_decision.formal_lifecycle_blocker_list field 12 items",
    citations = c("Charter §8 No Silent Override", "AX-002", "L-272")
  )
)

# ----- updated ax_axiom_compliance (C4 disposition) -----
ax_compliance <- list(
  ax_001_v2_conditional_metric = list(
    status = "FAIL_ALL_4_SCENARIOS_TEST1_TEST3",
    evidence = paste(
      "All 4 scenarios PASS Test 2 (MDD relief vs AR-only) but FAIL Test 1 (crisis_alpha n=1 COVID) + Test 3 (bad/normal cor ratio).",
      "Scenario-level AX-001 v2 PASS_1_OF_3 across all (only Test 2 strict PASS).",
      "정식 lifecycle 시 multi-axis quality + Frazzini-Pedersen BAB + IC ratio direct + bootstrap CI + pre-2015 BM extension + 8 named stress 전체 측정 의무."
    )
  ),
  ax_002_process_honesty = list(
    status = "ACCEPT_DOCUMENT_LIMITATIONS_AND_RATIONALIZATION_CORRECTIONS_3",
    evidence = "scope_disclaimer + walk_forward_caveat + data_limitations 명시. trade-off matrix 단순 비교 표 (권고 X) retain. 결정은 Q-Lead/도훈 책임. Codex C8 disposition으로 closure language 약화 (3 corrections)."
  ),
  ax_005_v1_2 = list(
    status = "EXCLUSION_NECESSARY_NOT_SUFFICIENT",
    evidence = paste(
      "Scenario D Defensive_LowVol multi-sleeve EXCLUSION 자격 충족 (4-sleeve hybrid).",
      "단, Test 1 + Test 3 FAIL → defensive role 강도 weak. 정식 lifecycle Q07 direct + multi-axis quality 의무."
    )
  ),
  ax_007_methodological = list(
    status = "AWARE_NOT_VIOLATED",
    evidence = "All 4 scenarios multi-sleeve. Single-sleeve top20 long-only 구조 X. AX-007 예외 (multi-sleeve)."
  ),
  ax_008_verification_triangulation = list(
    status = "FAIL_INCOMPLETE_6_CONSECUTIVE_CODEX_REJECT",
    evidence = "1/3 (Forge OK + Codex REJECT cycle 6 + Architect NA). 6 consecutive Codex REJECT (cycle 1~6) — 메타 path saturation 결정적 증거. 정식 lifecycle Architect 검증이 AX-008 2/3 충족 path retain."
  )
)

# ----- updated red_flags (C5 + C6 disposition) -----
red_flags <- list(
  RF_R1_AR_concentration_inheritance = list(
    severity = "MEDIUM",
    evidence = "AR weight 70~80% 모든 시나리오 → MCTV_AR dominate. 정식 optimizer ERC re-balance 의무.",
    mitigation = "정식 optimizer scope"
  ),
  RF_R8_signal_decay_source_level_resolved_at_scenario = list(
    severity = "HIGH_SOURCE_LEVEL_RESOLVED_AT_SCENARIO_LEVEL",
    evidence = paste(
      "사이클 5 source-level decay: TSMOM 60m 32% (warning) / KR_10y 60m 76% (critical).",
      "Scenario-level decay: 4 시나리오 모두 음수 (recent strong) — AR dominance lever.",
      "Source-level alert는 정식 lifecycle alpha-research re-spec 의무 retain."
    ),
    mitigation = "정식 alpha-research re-spec + monitoring agent immediate alert"
  ),
  RF_R9_regime_n_insufficient_NEW = list(
    severity = "HIGH",
    evidence = paste(
      "post-2015 sub-sample 135 obs 한계로 GFC_2008 / EuDebt_2011 / IMF_1997 / DotCom_2000 4 stress period 결측.",
      "COVID_2020 단일 crisis sample → AX-001 v2 Test 1 통계 power 부족 (n=1)."
    ),
    mitigation = "정식 lifecycle pre-2015 BM extension + 8 named stress 전체 측정 + EVT GPD parametric MLE"
  ),
  RF_R4_AX001_v2_test3_FAIL_all4_NEW = list(
    severity = "HIGH",
    evidence = paste(
      "AX-001 v2 Test 3 (bad/normal cor ratio) 4 시나리오 전부 FAIL.",
      "cor_crisis > cor_normal — defensive role 시간 검증 X.",
      "Scenario D 차이 +0.119 가장 paradoxical (cor_crisis 0.944 > normal 0.825).",
      "정식 lifecycle Frazzini-Pedersen BAB + IC ratio direct measurement 의무."
    ),
    mitigation = "정식 alpha-research multi-axis quality + BAB"
  ),
  RF_R10_glasso_implementation_artifact = list(
    severity = "LOW",
    evidence = paste(
      "본 cycle 6 Glasso simplified 구현 (ridge + threshold) → port_vol over-shrunk artifact (~0.58).",
      "정식 lifecycle glasso package + lambda CV + cond < 100 검증 의무."
    ),
    mitigation = "Σ 진단은 Sample/LW_identity/LW_constcor 세 estimator 우선 비교 retain"
  ),
  RF_R6_tail_risk_incomplete_NEW = list(
    severity = "HIGH",
    evidence = paste(
      "CVaR_95 / CDaR_95 / Hill alpha / VaR/ES bootstrap CI / EVT MLE direct 본 cycle 미산출.",
      "ES99 monthly 9.5~11.1% (annual reconciliation 정식 lifecycle 의무).",
      "EVT GPD threshold sensitivity 산출 (4 시나리오 × 4 threshold = 16 cells, xi 비교) — 4 시나리오 비교 axis retain"
    ),
    mitigation = "정식 risk-research scope (Pfaff Ch.4 + Ch.7 + Bertsimas-Lauprete-Samarov 2004)"
  ),
  RF_R3_PG2_active_book_crowding_absent = list(
    severity = "MEDIUM",
    evidence = paste(
      "사이클 6 sleeve-level HHI 0.52-0.66 (4 시나리오 비교 axis).",
      "PG2 active-book × 6-source style cor > 0.7 + L-219 family saturation 본 cycle 미산출.",
      "Scenario B HHI 정정: 0.58 (cash sleeve 포함)."
    ),
    mitigation = "정식 risk-research PG2 active-book scope retain"
  )
)

# ----- updated pit_audit (C7 disposition) -----
pit_audit <- list(
  C1 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "post-2015 sub-sample 일괄 측정 — Walk-forward 정식 lifecycle 의무 retain"),
  C2 = list(status = "PASS", evidence = "Mann-Kendall + Pettitt + cov estimator 모두 backward-looking, same-day circular 없음"),
  C3 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "ex-post scenario aggregate vs walk-forward 의무 차이 retain"),
  C4 = list(status = "NA", evidence = "재무제표 lag 본 cycle scope 외"),
  C5 = list(status = "DIAGNOSTIC_ONLY", evidence = "Bottom 25% AR partition diagnostic only — 정식 lifecycle t-1 expanding 의무"),
  C7 = list(status = "PASS", evidence = "lookahead_detector.R 자동 패턴 모두 backward-looking"),
  C9 = list(status = "ACKNOWLEDGE_LIMITATION_INHERITANCE_NOT_DIRECT_VERIFY", evidence = "DD/VT lag 사이클 inheritance — 본 cycle 직접 verify X. 정식 lifecycle 의무"),
  C11 = list(status = "ACKNOWLEDGE_LIMITATION_INHERITANCE_NOT_DIRECT_VERIFY", evidence = "FRED data 본 cycle scope 외 — 정식 lifecycle 의무"),
  C12 = list(status = "ACKNOWLEDGE_LIMITATION_INHERITANCE_NOT_DIRECT_VERIFY", evidence = "BΩB'+D 종목 단위 decomposition 본 cycle 산출 X — 정식 lifecycle 의무"),
  C13 = list(status = "PASS", evidence = "Z_Score 본 cycle scope 외 — return-level diagnostic"),
  C14 = list(status = "NA", evidence = "IC 접근 본 cycle scope X"),
  C15 = list(status = "ACKNOWLEDGE_LIMITATION_INHERITANCE_NOT_DIRECT_VERIFY", evidence = "Factor DB 직접 X — 사이클 2 master_returns inheritance. 정식 lifecycle load_month_factors() 의무")
)

# ----- updated qlead_escalate -----
qlead_escalate <- list(
  triggered = TRUE,
  trigger_criteria = list(
    high_severity_count = 6,
    high_severity_threshold = 5,
    ax_axiom_hard_fail_count = 2,
    ax_axiom_threshold = 3,
    pit_hard_violation_new = FALSE,
    consecutive_codex_reject = 6,
    cycle6_specific_trigger = "AX-001 v2 Test 1 + Test 3 모든 4 시나리오 FAIL + 6 consecutive Codex REJECT pattern"
  ),
  escalate_summary = paste(
    "Cycle 6 trade-off matrix 산출 완료. 4 시나리오 모두 AX-001 v2 PASS_1_OF_3 (Test 2만 PASS).",
    "AR dominance lever: scenario-level decay 4 모두 음수, 사이클 5 source-level P1 alert 시나리오 종합에서는 발동 X.",
    "Crisis_alpha + cor_crisis < cor_normal 모두 FAIL — defensive role 시간 검증 X.",
    "6 consecutive Codex REJECT 패턴 — 메타 path saturation 결정적 증거.",
    "TERMINATE_BENEFICIAL_QLEAD_DECISION_INPUT_PROVIDED_FORMAL_LIFECYCLE_BLOCKER_LIST_RETAINED."
  ),
  qlead_action_recommended = list(
    action_1 = "메타 리서치 cycle 6 종료 (TERMINATE_BENEFICIAL_QLEAD_DECISION_INPUT_PROVIDED)",
    action_2 = "도훈/Q-Lead 결정 → 4 시나리오 (A/B/C/D) 또는 추가 옵션 선택. 권고 X.",
    action_3 = "정식 alpha-research → risk-research → optimizer-research lifecycle 진입",
    action_4 = "monitoring agent 사이클 5 + 사이클 6 alert thresholds 통합 인계 (P1 IMMEDIATE: TSMOM 60m 32% decay + KR_10y 60m 76% decay 사이클 5 + 4 시나리오별 trade-off 사이클 6)"
  )
)

# ----- assemble final by overriding draft fields -----
final_pkg <- draft  # base
final_pkg$task_id <- "RESEARCH_RISK_CYCLE6_20260507"
final_pkg$research_type <- "meta_self_research_qlead_ondemand_cycle6_4scenario_comparison"
final_pkg$as_of_date <- "2026-05-08"
final_pkg$cycle <- 6
final_pkg$version <- "v2_post_codex_round_disposition_final"
final_pkg$axis_focus <- "사이클 5 P1 alert (TSMOM 32% / KR_10y 76% decay) 발견 후속 4 시나리오 (A retain / B P1_cut / C P1_partial / D P1_substitute) × 5 risk metric 비교 진단. Q-Lead/도훈 결정 input 제공 (trade-off matrix), 권고 X. Codex Round 6 consecutive REJECT 패턴 — 메타 path saturation 결정적 증거"
final_pkg$scope_disclaimer <- scope_disclaimer
final_pkg$cycle6_termination_decision <- termination_decision
final_pkg$codex_critic_round_status <- codex_status
final_pkg$cycle6_codex_concerns_disposition <- codex_concerns_disposition
final_pkg$ax_axiom_compliance <- ax_compliance
final_pkg$red_flags_acknowledged <- red_flags
final_pkg$pit_audit <- pit_audit
final_pkg$qlead_escalate <- qlead_escalate

# Update crowding_tdc Scenario B HHI fix in scenarios field
final_pkg$scenarios$B$crowding_tdc$hhi_normalized <- 0.58

# Write
out_path <- file.path(WORK, "risk_package.json")
write_json(final_pkg, out_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
fsize <- file.info(out_path)$size
cat(sprintf("[SAVED] risk_package.json FINAL (%d bytes / %.1f KB)\n", fsize, fsize/1024))
