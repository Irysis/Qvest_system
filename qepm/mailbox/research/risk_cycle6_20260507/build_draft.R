# =============================================================================
# Cycle 6 — Build risk_package_draft.json (8-field schema)
# 4 시나리오 × 5 risk metric 비교 진단
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WORK <- file.path(ROOT, "qepm/mailbox/research/risk_cycle6_20260507")
setwd(WORK)

# Load all CSVs
cov_summary  <- fread("scenario_covariance_5est_summary.csv")
tail_4m      <- fread("scenario_tail_risk_4method.csv")
evt_thr      <- fread("scenario_evt_threshold_sensitivity.csv")
stress_8     <- fread("scenario_8stress_named.csv")
crowd_tdc    <- fread("scenario_crowding_tdc.csv")
forward_sim  <- fread("scenario_forward_sim_mk_pettitt.csv")
trade_off    <- fread("scenario_tradeoff_matrix.csv")
ax001        <- fread("scenario_ax001v2_verdict.csv")

# Helper: Convert data.table to list of records (for JSON)
dt_to_records <- function(dt) {
  lapply(seq_len(nrow(dt)), function(i) as.list(dt[i]))
}

# ----- Build aggregate fields per scenario -----
build_scenario_fields <- function(s) {
  cov_s <- cov_summary[scenario == s]
  tail_s <- tail_4m[scenario == s]
  evt_s <- evt_thr[scenario == s]
  stress_s <- stress_8[scenario == s & status == "OK"]
  crowd_s <- crowd_tdc[scenario == s]
  fs_s <- forward_sim[scenario == s]
  trade_s <- trade_off[scenario == s]
  ax_s <- ax001[scenario == s]

  list(
    scenario_id = s,
    description = trade_s$description,

    # Aggregate
    sr = trade_s$sr,
    mdd = trade_s$mdd,
    decay_60m_pct = trade_s$decay_60m_pct,
    decay_warning = trade_s$decay_warning,
    decay_critical = trade_s$decay_critical,

    # Metric 1: Σ
    covariance_5_estimators = dt_to_records(cov_s),

    # Metric 2: Tail
    tail_risk_4method = as.list(tail_s),
    evt_threshold_sensitivity = dt_to_records(evt_s),

    # Metric 3: 8-stress
    stress_8_periods = dt_to_records(stress_s),
    n_stress_periods_with_data = nrow(stress_s),
    avg_period_mdd = mean(stress_s$mdd_period, na.rm=TRUE),
    crisis_alpha_pass_count = sum(stress_s$passes_crisis_alpha == TRUE, na.rm=TRUE),
    crisis_alpha_total = sum(!is.na(stress_s$passes_crisis_alpha)),

    # Metric 4: Crowding/TDC
    crowding_tdc = as.list(crowd_s),

    # Metric 5: Forward sim
    forward_sim_mk_pettitt = as.list(fs_s),

    # AX-001 v2 verdict
    ax001_v2_verdict = as.list(ax_s)
  )
}

scenarios_data <- list(
  A = build_scenario_fields("A"),
  B = build_scenario_fields("B"),
  C = build_scenario_fields("C"),
  D = build_scenario_fields("D")
)

# ----- Trade-off matrix (4 × 4 metric) -----
trade_matrix <- list(
  description = "4 시나리오 × 4 metric trade-off (Q-Lead 결정 정보 제공만, 권고 X)",
  matrix = dt_to_records(trade_off),
  metric_axes = c("sr","mdd","crisis_alpha_pass_rate","decay_60m_pct"),
  metric_definitions = list(
    sr = "annualized Sharpe ratio (mean/sd × sqrt(12)) on post-2015 sub-sample (n=135)",
    mdd = "maximum drawdown on full post-2015 path",
    crisis_alpha_pass_rate = "fraction of crisis periods (GFC/EuDebt/COVID) with mean monthly > 0. post-2015 sub-sample 한계로 GFC/EuDebt 결측, COVID 단일 측정",
    decay_60m_pct = "60m rolling SR decay vs full sample SR. 양수 = decay, 음수 = recent stronger than full"
  )
)

# ----- Scope disclaimer -----
scope_disclaimer <- list(
  statement = paste(
    "Q-Lead 온디맨드 메타 리서치 사이클 6 (path: qepm/mailbox/research/risk_cycle6_20260507/).",
    "사이클 5 P1 alert (TSMOM 32% / KR_10y 76% decay) 발견 후속 4 시나리오 비교 진단.",
    "각 시나리오 weight 결정 X — Q-Lead/도훈 결정 정보 제공 (trade-off matrix)만.",
    "정식 WT alpha→risk pipeline 산출 X — alpha_scores.parquet / weights.csv / 종목별 BΩB'+D / KRX VKOSPI / post-shrink Σ 모두 정식 lifecycle 의무.",
    "본 cycle 6은 시나리오 비교 정보 제공, 정식 채택 / weight 결정 / strategy spawn 절대 X (Hook agent_role_guard 강제)."
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
    "Q-Lead/도훈 결정 정보 제공 (trade-off matrix) 차원, hypothesis generation 한계 명시."
  ),
  data_limitations = paste(
    "post-2015 sub-sample 135 obs 한계로 GFC_2008 / EuDebt_2011 / IMF_1997 / DotCom_2000 4개 stress period 결측 (NO_DATA_POST2015_OOS).",
    "COVID_2020 / VolShock_2018 / China_2015 / Inflation2022 4개 period만 측정.",
    "AX-001 v2 Test 1 (crisis_alpha) COVID 단일 사례 의존."
  )
)

# ----- Critical findings (cycle 6 specific) -----
critical_findings <- list(
  finding_1_p1_alert_resolution = list(
    severity = "INFO_RESOLVED_AT_SCENARIO_LEVEL",
    statement = paste(
      "사이클 5 P1 alert (TSMOM 60m SR 0.59 32% decay / KR_10y 60m SR 0.07 76% decay)는",
      "source-level individual SR decay. 4 시나리오 종합 SR (Hybrid 가중평균)에서는 모두 decay 음수 (recent 60m > full sample SR).",
      "A: -13.6%, B: -15.3%, C: -14.3%, D: -16.0% — 4 시나리오 모두 P1 warning 30% threshold 미발동.",
      "AR 70~80% weight × AR 단독 60m SR 1.67 retain 효과로 source decay diluted.",
      "단, Mann-Kendall p<0.05 + Pettitt p<1e-6 모두 strong upward trend (recent stronger than full) — 사이클 5 source-level downward trend와 정반대 방향. AR dominance lever."
    ),
    interpretation = "시나리오 weight 결정 시 source-level decay vs scenario-level decay 구분 필수. Q-Lead 결정 시 중요 정보."
  ),
  finding_2_crisis_alpha_fail_all_4 = list(
    severity = "HIGH",
    statement = paste(
      "AX-001 v2 Test 1 (crisis_alpha) 4 시나리오 전부 FAIL.",
      "COVID_2020 measurable period에서 4 시나리오 모두 mean_monthly 음수.",
      "GFC_2008 / EuDebt_2011 결측으로 통계 power 부족 (n=1 crisis observation).",
      "정식 lifecycle pre-2015 BM extension + 8 named stress 전체 측정 의무."
    ),
    scenario_breakdown = list(
      A = "COVID 2020: -0.040/m → fail. n=1, 결정 불충분",
      B = "COVID 2020: -0.040/m → fail",
      C = "COVID 2020: -0.045/m → fail (worst)",
      D = "COVID 2020: -0.041/m → fail"
    )
  ),
  finding_3_test3_cor_crisis_higher = list(
    severity = "HIGH",
    statement = paste(
      "AX-001 v2 Test 3 (bad/normal cor ratio) 4 시나리오 전부 FAIL.",
      "cor_crisis > cor_normal — defensive role 시간 검증 X.",
      "A: cor_crisis 0.990 vs normal 0.962 (Δ +0.028)",
      "B: 1.000 vs 1.000 (단일 source AR, scaled)",
      "C: 0.997 vs 0.986 (Δ +0.011, 가장 작은 차이)",
      "D: 0.944 vs 0.825 (Δ +0.119, 가장 큰 차이 — Defensive sleeve가 normal보다 crisis에서 더 동조 = paradoxical)"
    ),
    interpretation = paste(
      "원인 진단: post-2015 sub-sample bottom 25% AR = COVID 2020 + Inflation 2022 + China 2015",
      "이 경우 모든 secondary source (TSMOM/KR10y/Defensive/Commodity/VRP)도 동시 stress.",
      "정식 lifecycle 시 Frazzini-Pedersen 2014 BAB / multi-axis quality + IC ratio direct measurement 필수.",
      "사이클 6 단계에서는 Test 3 FAIL 모든 시나리오 명시 + 정식 alpha-research 의무 retain."
    )
  ),
  finding_4_scenario_d_pareto_observation = list(
    severity = "INFO",
    statement = paste(
      "Scenario D (P1 substitute) 시 SR 1.614 (가장 높음) but MDD -19.9% (가장 깊음).",
      "Pareto trade-off 미해소: SR 우월 시 MDD 열위, MDD 우월 시 (Scenario A retain) SR 열위.",
      "Crowding HHI: A 0.535 / B 1.0 dominant / C 0.660 / D 0.520 (가장 분산).",
      "TDC max lower 5%: D 0.296 (highest, 4-source) vs A/C 0.148.",
      "Q-Lead 결정 시 SR vs MDD 우선순위 + concentration risk 고려 필요."
    )
  ),
  finding_5_evt_xi_scenario_d_outlier = list(
    severity = "MEDIUM",
    statement = paste(
      "EVT GPD threshold sensitivity: D 시나리오 thr=80% xi=+0.032 (heavy tail) / 95% xi=+0.112 (heavier).",
      "A/B/C 모두 xi 음수 (light tail) 모든 threshold.",
      "D 시나리오 4-source 추가가 extreme tail 증가 시그널.",
      "정식 lifecycle EVT MLE direct + threshold goodness-of-fit 검증 의무 (Pfaff Ch.7)."
    )
  )
)

# ----- AX axiom compliance -----
ax_compliance <- list(
  ax_001_v2_conditional_metric = list(
    status = "FAIL_ALL_4_SCENARIOS_TEST1_TEST3",
    evidence = paste(
      "All 4 scenarios PASS Test 2 (MDD relief vs AR-only) but FAIL Test 1 (crisis_alpha) + Test 3 (bad/normal cor ratio).",
      "Scenario-level AX-001 v2 PASS_1_OF_3 across all (only Test 2 strict PASS).",
      "정식 lifecycle 시 multi-axis quality + Frazzini-Pedersen BAB + IC ratio direct + bootstrap CI 의무."
    )
  ),
  ax_002_process_honesty = list(
    status = "ACCEPT_DOCUMENT_LIMITATIONS",
    evidence = "scope_disclaimer + walk_forward_caveat + data_limitations 명시. trade-off matrix 단순 비교 표 (권고 X) retain. 결정은 Q-Lead/도훈 책임."
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
    evidence = "All 4 scenarios multi-sleeve (B는 cash sleeve도 sleeve 자격). Single-sleeve top20 long-only 구조 X. AX-007 예외 (multi-sleeve)."
  ),
  ax_008_verification_triangulation = list(
    status = "PENDING_CODEX_AND_ARCHITECT",
    evidence = "1/3 (Forge OK + Codex pending + Architect NA). 6 consecutive Codex REJECT path 가능성 (cycle 1~5 + cycle 6). 정식 lifecycle Architect 검증이 AX-008 2/3 충족 path retain."
  )
)

# ----- Red flags -----
red_flags <- list(
  RF_R1_AR_concentration_inheritance = list(
    severity = "MEDIUM",
    evidence = "AR weight 70~80% 모든 시나리오 → MCTV_AR dominate. 정식 optimizer ERC re-balance 의무.",
    mitigation = "정식 optimizer scope"
  ),
  RF_R8_signal_decay_source_level_inheritance = list(
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
    mitigation = "정식 lifecycle pre-2015 BM extension + 8 named stress 전체 측정 + EVT GPD parametric extension"
  ),
  RF_R4_AX001_v2_test3_FAIL_all4_NEW = list(
    severity = "HIGH",
    evidence = paste(
      "AX-001 v2 Test 3 (bad/normal cor ratio) 4 시나리오 전부 FAIL.",
      "cor_crisis > cor_normal — defensive role 시간 검증 X. Scenario D 차이 +0.119로 가장 paradoxical.",
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
  )
)

# ----- PIT audit -----
pit_audit <- list(
  C1 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "post-2015 sub-sample 일괄 측정 — Walk-forward 정식 lifecycle 의무 retain"),
  C2 = list(status = "PASS", evidence = "Mann-Kendall + Pettitt + cov estimator 모두 backward-looking, same-day circular 없음"),
  C3 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "ex-post scenario aggregate vs walk-forward 의무 차이 retain"),
  C4 = list(status = "NA", evidence = "재무제표 lag 본 cycle scope 외"),
  C5 = list(status = "DIAGNOSTIC_ONLY", evidence = "Bottom 25% AR partition diagnostic only — 정식 lifecycle t-1 expanding 의무"),
  C7 = list(status = "PASS", evidence = "lookahead_detector.R 자동 패턴 모두 backward-looking"),
  C9 = list(status = "PASS", evidence = "DD/VT lag 사이클 inheritance"),
  C11 = list(status = "PASS", evidence = "FRED data 본 cycle scope 외"),
  C12 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "BΩB'+D 종목 단위 decomposition 본 cycle 산출 X — 정식 lifecycle 의무"),
  C13 = list(status = "PASS", evidence = "Z_Score 본 cycle scope 외 — return-level diagnostic"),
  C14 = list(status = "NA", evidence = "IC 접근 본 cycle scope X"),
  C15 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "Factor DB 직접 X — 사이클 2 master_returns inheritance")
)

# ----- Cycle 6 termination decision -----
termination_decision <- list(
  decision = "TERMINATE_BENEFICIAL_DECISION_READY_FORMAL_LIFECYCLE_NOW",
  decision_rationale = list(
    evidence_1_marginal_value_extracted = paste(
      "사이클 6 4 시나리오 비교 trade-off matrix 산출 — Q-Lead/도훈 결정 input 충족.",
      "5 metric × 4 시나리오 = 20 cells 모두 정량 측정.",
      "AX-001 v2 4 시나리오 모두 PASS_1_OF_3 동일 verdict — defensive role 부족 동일 패턴.",
      "Scenario D SR 1.614 우월 but MDD -19.9% 열위 — Pareto trade-off 미해소 (정식 optimizer scope)."
    ),
    evidence_2_critical_finding_resolved = paste(
      "사이클 5 P1 alert는 source-level (TSMOM/KR10y individual SR decay).",
      "Scenario-level decay 4 시나리오 모두 음수 (recent strong) — AR 70~80% dominance lever 입증.",
      "Q-Lead 결정 시 source-level vs scenario-level 구분 명확히 — 사이클 6 marginal value high."
    ),
    evidence_3_consecutive_codex_reject_pattern = paste(
      "사이클 1~5 5 consecutive Codex REJECT — 메타 path saturation 결정적 증거.",
      "사이클 6은 시나리오 비교 axis 추가 (다른 차원), but walk-forward / Q07 direct / Architect 검증은 정식 lifecycle 의무 retain."
    ),
    evidence_4_decision_framework_extracted = paste(
      "trade-off matrix 4 시나리오 × 4 metric → Q-Lead 결정 framework 명시:",
      "(SR-priority) D > A > C > B / (MDD-priority) A > B > C > D / (Crisis α) 4 모두 FAIL → defensive 강화 필요 (정식 lifecycle).",
      "monitoring agent 인계 시 4 시나리오별 alert threshold 모두 정량."
    )
  ),
  next_action_recommendation = list(
    action_1_immediate_qlead_decision = paste(
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
      "정식 risk-research WT spawn — alpha_package 수신 후 종목 단위 BΩB'+D + post-shrink Σ + PG2 active book TDC/HHI/style cor + 8 named stress 전체 측정 + EVT GPD parametric + walk-forward."
    ),
    action_4_formal_optimizer_research = paste(
      "정식 optimizer-research WT spawn — α̂ + Σ 수신 후 4 시나리오 (또는 도훈 추가 옵션) Pareto trade-off 해소.",
      "ERC / 70/15/15 / 70/10/10/10 / 80/10/10 비교."
    ),
    action_5_parallel_monitoring = paste(
      "monitoring agent 사이클 5 + 사이클 6 alert thresholds 인계.",
      "(a) source-level: TSMOM 60m SR > 32% decay / KR_10y 60m SR > 76% decay (사이클 5 threshold)",
      "(b) scenario-level: 4 시나리오별 60m SR decay > 30% / MDD breach -25% / crisis_alpha < 50% (사이클 6 threshold)",
      "6/1 발효 후 첫 월간 report부터 운용."
    )
  )
)

# ----- Codex Critic Round status (placeholder, will update post critic) -----
codex_status <- list(
  stage = "pre_codex_round_draft",
  draft_path = "qepm/mailbox/research/risk_cycle6_20260507/risk_package_draft.json",
  awaits_codex = TRUE,
  awaits_response_path = "qepm/mailbox/research/risk_cycle6_20260507/codex_critic_response_risk.json",
  challenge_note_path = "qepm/mailbox/research/risk_cycle6_20260507/risk_challenge_note.md"
)

# ----- Q-Lead escalate (cycle 5 inheritance + cycle 6 update) -----
qlead_escalate <- list(
  triggered = TRUE,
  trigger_criteria = list(
    high_severity_count = 3,
    high_severity_threshold = 5,
    ax_axiom_hard_fail_count = 1,  # AX-001 v2 Test 1 + Test 3 모든 시나리오 FAIL
    ax_axiom_threshold = 3,
    pit_hard_violation_new = FALSE,
    consecutive_codex_reject_inheritance = 5,
    cycle6_specific_trigger = "AX-001 v2 Test 1 + Test 3 모든 4 시나리오 FAIL"
  ),
  escalate_summary = paste(
    "Cycle 6 trade-off matrix 산출 완료. 4 시나리오 모두 AX-001 v2 PASS_1_OF_3 (Test 2만 PASS).",
    "AR dominance lever: scenario-level decay 4 모두 음수, 사이클 5 source-level P1 alert 시나리오 종합에서는 발동 X.",
    "Crisis_alpha + cor_crisis < cor_normal 모두 FAIL — defensive role 시간 검증 X. 정식 alpha-research의 multi-axis quality + BAB 의무 강화.",
    "TERMINATE_BENEFICIAL_DECISION_READY_FORMAL_LIFECYCLE_NOW retain."
  ),
  qlead_action_recommended = list(
    action_1 = "메타 리서치 cycle 6 종료 (TERMINATE_BENEFICIAL_DECISION_READY_FORMAL_LIFECYCLE_NOW)",
    action_2 = "도훈/Q-Lead 결정 → 4 시나리오 (A/B/C/D) 또는 추가 옵션 선택",
    action_3 = "정식 alpha-research → risk-research → optimizer-research lifecycle 진입",
    action_4 = "monitoring agent 사이클 5 + 사이클 6 alert thresholds 통합 인계"
  )
)

# ----- Artifacts manifest -----
artifacts_manifest <- list(
  primary_csv = c(
    "scenario_covariance_5est_summary.csv",
    "scenario_tail_risk_4method.csv",
    "scenario_evt_threshold_sensitivity.csv",
    "scenario_8stress_named.csv",
    "scenario_crowding_tdc.csv",
    "scenario_forward_sim_mk_pettitt.csv",
    "scenario_tradeoff_matrix.csv",
    "scenario_ax001v2_verdict.csv"
  ),
  primary_json = c(
    "cycle6_aggregate_summary.json"
  ),
  code = c(
    "run_cycle6_4scenarios.R",
    "build_draft.R"
  ),
  inheritance = c(
    "사이클 1: qepm/mailbox/research/risk_model_meta_20260507/",
    "사이클 2: qepm/mailbox/research/risk_candidates_20260507/",
    "사이클 3: qepm/mailbox/research/risk_cycle3_20260507/",
    "사이클 4: qepm/mailbox/research/risk_cycle4_20260507/",
    "사이클 5: qepm/mailbox/research/risk_cycle5_20260507/"
  )
)

# ----- Citations -----
citations <- list(
  pfaff_2016_FRM_ch4 = "Pfaff B. (2016) Financial Risk Modelling and Portfolio Optimization with R. Wiley. Ch.4 (covariance shrinkage), Ch.7 (EVT GPD threshold sensitivity)",
  ledoit_wolf_2003 = "Ledoit O., Wolf M. (2003) Improved estimation of the covariance matrix of stock returns with an application to portfolio selection. JEFAS",
  gerber_2022 = "Gerber S., Markowitz H., Pujara A. (2022) The Gerber Statistic: A Robust Co-Movement Measure for Portfolio Optimization. JoPM",
  engle_2002 = "Engle R. (2002) Dynamic Conditional Correlation. JBES",
  moskowitz_2012 = "Moskowitz T., Ooi Y., Pedersen L. (2012) Time series momentum. JFE",
  stambaugh_2015 = "Stambaugh R., Yu J., Yuan Y. (2015) Arbitrage asymmetry and the idiosyncratic volatility puzzle. RFS",
  hwang_rubesam_2024 = "Hwang S., Rubesam A. (2024) The disappearance of momentum (working)",
  pettitt_1979 = "Pettitt A. (1979) A non-parametric approach to the change-point problem. JRSS-C",
  bailey_lopezdeprado_2014 = "Bailey D., López de Prado M. (2014) The Deflated Sharpe Ratio. JPM",
  hamilton_1989 = "Hamilton J. (1989) A new approach to the economic analysis of nonstationary time series and the business cycle. ECMA",
  frazzini_pedersen_2014 = "Frazzini A., Pedersen L. (2014) Betting against beta. JFE",
  brunnermeier_pedersen_2009 = "Brunnermeier M., Pedersen L. (2009) Market liquidity and funding liquidity. RFS",
  bertsimas_2004 = "Bertsimas D., Lauprete G., Samarov A. (2004) Shortfall as a risk measure: properties, optimization and applications. JEDC",
  AX_001_v2_L274 = "AX-001 v2 conditional defense (L-274). Active path qepm/memory/axioms/active/AX-001.json",
  AX_005_v1_2_L136 = "AX-005 v1.2 EXCLUSION necessary not sufficient (L-136/140/165/166)",
  AX_007_L160 = "AX-007 single_sleeve_long_only_top20 mechanism break (L-160/165/166)",
  AX_008_L159 = "AX-008 verification triangulation (L-159/167/168)",
  L_281_KR10y = "L-281 KR_10y bond conditional Pareto",
  charter_v1_4_section_2 = "Charter v1.4 §2 active risk = portfolio - existing primary alpha"
)

# ====== ASSEMBLE FINAL DRAFT ======
risk_package_draft <- list(
  task_id = "RESEARCH_RISK_CYCLE6_20260507",
  research_type = "meta_self_research_qlead_ondemand_cycle6_4scenario_comparison",
  as_of_date = "2026-05-08",
  cycle = 6,
  version = "v1_pre_codex_round",
  axis_focus = "사이클 5 P1 alert (TSMOM 32% / KR_10y 76% decay) 발견 후속 4 시나리오 (A retain / B P1_cut / C P1_partial / D P1_substitute) × 5 risk metric 비교 진단. Q-Lead/도훈 결정 정보 제공 (trade-off matrix), 권고 X.",
  scope_disclaimer = scope_disclaimer,

  # Scenario data per scenario (4 scenarios)
  scenarios = scenarios_data,

  # Aggregate trade-off matrix
  trade_off_matrix = trade_matrix,

  # Findings
  critical_findings = critical_findings,

  # Compliance + audit
  ax_axiom_compliance = ax_compliance,
  red_flags_acknowledged = red_flags,
  pit_audit = pit_audit,

  # Decision
  cycle6_termination_decision = termination_decision,

  # Codex round
  codex_critic_round_status = codex_status,

  # Q-Lead
  qlead_escalate = qlead_escalate,

  # Artifacts
  artifacts_manifest = artifacts_manifest,

  # References
  citations = citations
)

# Write
out_path <- file.path(WORK, "risk_package_draft.json")
write_json(risk_package_draft, out_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
fsize <- file.info(out_path)$size
cat(sprintf("[SAVED] risk_package_draft.json (%d bytes / %.1f KB)\n", fsize, fsize/1024))
