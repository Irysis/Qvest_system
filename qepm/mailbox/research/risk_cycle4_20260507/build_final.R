# ============================================================================
# Cycle 4 risk_package.json FINAL (post-Codex-Round disposition)
# 합리화 표현 6 정정 + cycle4_codex_concerns_disposition C1~C10 + Q-Lead escalate
# ============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- "qepm/mailbox/research/risk_cycle4_20260507"

# Load draft
draft <- fromJSON(file.path(OUT_DIR, "risk_package_draft.json"), simplifyVector=FALSE)

# Load codex response
codex <- fromJSON(file.path(OUT_DIR, "codex_critic_response_risk.json"), simplifyVector=FALSE)

# Load all artifacts (rebuild)
dcc_summary <- fread(file.path(OUT_DIR, "axis2_dcc_6src_summary.csv"))
regime_cor <- fread(file.path(OUT_DIR, "axis2_regime_cor_6src.csv"))
regime_pd <- fread(file.path(OUT_DIR, "axis2_regime_sigma_pd.csv"))
boot <- fread(file.path(OUT_DIR, "axis2_crisis_bootstrap_1000.csv"))
stress <- fread(file.path(OUT_DIR, "axis3_8stress_historical.csv"))
axis1_check <- fromJSON(file.path(OUT_DIR, "axis1_kospi200_options_check.json"))
axis3_summary <- fromJSON(file.path(OUT_DIR, "axis3_pre2010_summary.json"))

df_to_listrows <- function(dt) {
  lapply(seq_len(nrow(dt)), function(i) as.list(dt[i]))
}

# ============================================================================
# Compose FINAL package
# ============================================================================

final <- list(
  task_id = "RESEARCH_RISK_CYCLE4_20260507",
  research_type = "meta_self_research_qlead_ondemand_cycle4",
  as_of_date = "2026-05-08",
  version = "v2_post_codex_round_disposition",
  cycle = 4,

  # ============================================================================
  # Scope disclaimer (정직 retain)
  # ============================================================================
  scope_disclaimer = "Q-Lead 온디맨드 메타 리서치 사이클 4 (path: qepm/mailbox/research/risk_cycle4_20260507/). 사이클 3 Codex 8 HIGH/MEDIUM concerns 잔여 한계 보강 시도. 정식 WT alpha→risk pipeline 산출 X — alpha_scores.parquet / weights.csv / B Ω B'+D 종목별 decomposition / load_month_factors() Factor DB Q07 직접 / KRX VKOSPI 직접 / post-shrink Σ (Ledoit-Wolf direct + cn report) 모두 정식 lifecycle 의무. 본 cycle 4는 6-source DCC-GARCH per-regime + 위기 bootstrap + 8 stress periods historical extension 진단만, 정식 채택 / weight 결정 / strategy spawn 절대 X (Hook agent_role_guard 강제). 신규 source 정식 채택 결정은 후속 alpha-research → risk-research → optimizer-research lifecycle 의무.",

  # ============================================================================
  # Codex Round Status
  # ============================================================================
  codex_critic_round_status = list(
    stage = "post_codex_round_disposition",
    codex_response_path = "qepm/mailbox/research/risk_cycle4_20260507/codex_critic_response_risk.json",
    codex_stance = "REJECT",
    codex_veto = FALSE,
    codex_concerns_count = 10,
    codex_severity_distribution = list(HIGH = 7, MEDIUM = 3),
    challenge_note_path = "qepm/mailbox/research/risk_cycle4_20260507/risk_challenge_note.md",
    escalate_trigger = list(
      high_severity_5 = TRUE,
      ax_axiom_hard_fail_3 = TRUE,
      pit_hard_violation_new = FALSE,
      escalate_to_qlead = TRUE
    ),
    rationalization_corrections_count = 6
  ),

  # ============================================================================
  # 사이클 1+2+3 inheritance
  # ============================================================================
  context_cycle1_2_3_input = list(
    cycle1_path = "qepm/mailbox/research/risk_model_meta_20260507/risk_package.json",
    cycle2_path = "qepm/mailbox/research/risk_candidates_20260507/risk_package.json",
    cycle3_path = "qepm/mailbox/research/risk_cycle3_20260507/risk_package.json",
    cycle3_codex_stance = "REJECT (veto=false), 8 HIGH/MEDIUM concerns",
    cycle3_top_findings = list(
      best_combo_192m = "Hybrid + 10%×Defensive + 10%×Commodity + 5%×VRP = SR 1.997 / MDD -0.137 (post-2010 192m)",
      sr_target_gap = "Target 2.0 vs 1.997 = gap 0.003 (사이클 1 0.335에서 99.1% 좁힘)",
      vrp_proxy_validation = "cor_VIX_lag1_KOSPI_RV12m_lag1_level=0.5054, diff=0.1913 (KOSPI BM 12m RV 직접 측정 기반). cross-market proxy 한계 명시 retain",
      defensive_orthogonality = "cor 0.002 with AR (직교성 자격 확정)",
      vrp_ar_cor = "-0.345 (사이클 2 -0.155 대비 더 강한 음의 의존성)",
      diversification_ratio = "1.105 → 1.307 (+18%, Choueifaty-Coignard 2008)",
      bootstrap_crisis_pass_revised = "사이클 3 SR>0 criteria CRISIS regime 정의상 부적합 (SR<0 정의). 사이클 4 revised metrics: Defensive 15% MDD_relief 89.2% / VRP 15% vol_contract 72.8% / Commodity 15% MDD_relief 89.9%"
    )
  ),

  # ============================================================================
  # AXIS 1: KOSPI200 옵션 chain VRP direct (cycle 4 final)
  # ============================================================================
  axis_1_kospi200_options_check = list(
    purpose = "사이클 3 weakest_assumption 'VRP=US VIX 기반 합성, KOSPI200 IV 부재' 직접 보강. KRX OpenAPI cache 가용성 + acquisition path 점검. Codex C7 정확 인지: cor 0.505 level / 0.191 diff은 cross-market proxy 한계, KR-market implied volatility direct evidence X.",
    methodology = list(
      primary_check = "ls .cache/krx_iv_skew.parquet, .cache/krx_derivatives/, .cache/krx_options/",
      secondary_check = "rawdata.parquet 컬럼 직접 검사 (iv/IV/vkospi/skew prefix)",
      acquisition_path = "02_Infrastructure/data/data_collector_krx_options.R 존재 — KRX OpenAPI 인증 키 + 일일 cron 등록 필요 (본 메타 리서치 scope 외부)"
    ),
    data_availability = axis1_check$data_check,
    conclusion = list(
      data_available = FALSE,
      reason = "KOSPI200 옵션 chain cache 부재 (.cache/krx_iv_skew.parquet, krx_derivatives/, krx_options/ 모두 미생성). KRX OpenAPI 호출 통한 acquisition 가능 (data_collector_krx_options.R) 그러나 인증 키 + 일일 rate limit + 본 메타 리서치 scope 외부.",
      fallback = "사이클 3 US VIX proxy retain (4 sub-variants BKM/CW/BTZ/BCI). 사이클 3 cor_VIX_lag1_KOSPI_RV12m_lag1_level=0.5054, diff=0.1913 cross-market proxy 한계 정직 명시. **KR-market implied volatility direct evidence X** (Codex C7 ACCEPT).",
      recommendation = "정식 채택 시 (a) KRX OpenAPI 인증 키 발급 (b) data_collector_krx_options.R 일일 cron 등록 (c) 최소 5년 cache 누적 후 BKM/CW direct 산출 (d) US VIX vs KOSPI200 IV 정량 비교 후 retire 판단",
      literature_anchor = "Bakshi-Kapadia-Madan 2003 RFS (BKM model-free implied moments) + Bollerslev-Tauchen-Zhou 2009 RFS (VRP estimation은 동일 시장 implied vol + realized vol 의무, cross-market proxy 한계 명시) + Carr-Wu 2009 RFS (variance swap synthetic)"
    ),
    cycle3_vix_proxy_retain = list(
      cor_level = 0.5054,
      cor_diff = 0.1913,
      interpretation = "Level corr 0.51 cross-market proxy 한계 — KOSPI200 옵션 chain direct가 정식 의무. diff corr 0.19 weak — VIX-RV co-variation 차분 시 약화. KR-specific implied vol 부재 한계 정직 명시 retain. (이전 'medium-strength proxy acceptable' 표현 정정 — 합리화 위험 1건 제거)"
    ),
    artifact_json = "qepm/mailbox/research/risk_cycle4_20260507/axis1_kospi200_options_check.json"
  ),

  # ============================================================================
  # AXIS 2: 6-source DCC-GARCH per-regime + bootstrap (cycle 4 final)
  # ============================================================================
  axis_2_dcc_per_regime_bootstrap = list(
    purpose = "사이클 3 Codex C3 (Sigma audit sleeve-level Sample only) + C4 (no per-regime Sigma, no CRISIS bootstrap CI) 직접 보강. 6-source DCC-GARCH(1,1) + Student-t innovations + 4 regime 분리 + 1000 trial bootstrap revised metrics.",
    methodology = list(
      dcc_garch = "Engle (2002) JBES — DCC-GARCH(1,1) + multivariate Student-t innovations (rugarch + rmgarch). Univariate sGARCH(1,1) for each source.",
      per_regime_classification = "Hybrid bottom 10% = CRISIS / 10~40% = CAUTION / 40~70% = NORMAL / 70~100% = BULL (post-2015 6-source joint sample). **PIT-C5 caveat**: full-sample Hybrid quantile 분류 — diagnostic only, production overlay 시 t-1 expanding 의무 (정식 lifecycle scope, Codex C3 ACCEPT).",
      bootstrap = "1000 trials × 4 weights (0/5/10/15%) × 3 candidate. Resample CRISIS regime indices with replacement. Metric revision (Codex C4 직접 보강): SR<0 정의상 (CRISIS regime 자체 음수) → MDD_relief / vol_contract / SR_improvement 3-axis"
    ),
    sample = list(
      n_obs_post2015 = 135,
      sample_range = "2015-01 ~ 2026-03",
      regime_distribution = list(BULL=41, NORMAL=40, CAUTION=40, CRISIS=14),
      crisis_n_caveat = "CRISIS n=14는 통계 검증 충분 X (전통적 n≥30 standard 이하). bootstrap 1000 trial은 sample uncertainty quantification only — sample 자체 한계 해소 X. 정식 lifecycle EVT GPD parametric extension (Pfaff 2016 Ch.7) 의무 (Codex C4 ACCEPT_PARTIAL)."
    ),

    dcc_garch_6src_summary = df_to_listrows(dcc_summary),

    dcc_key_findings = list(
      ar_vrp_dynamic = "cor_static -0.345, cor_dcc_mean -0.235, cor_dcc_min -0.415, cor_dcc_max -0.087. 동적 변동성 ±0.11 — VRP의 hedge 강도 시간에 따라 변동",
      ar_kr10y_dynamic = "cor_static -0.122, cor_dcc_mean -0.102. KR10y 보수적 hedge retain",
      commodity_vrp_dynamic = "cor_static 0.215, cor_dcc_mean 0.189. 두 inflation hedge source 약한 동조",
      defensive_orthogonality_dynamic = "AR-Defensive cor_static 0.002, cor_dcc_mean 0.022. 직교성 dynamic regime에서도 retain (max 0.098 episode 발생)",
      dynamic_static_diff_max = "AR_VRP 0.110 (dynamic mean less negative than static — VRP hedge 강도 NORMAL/BULL regime에서 약화)"
    ),

    regime_cor_crisis_top8 = df_to_listrows(regime_cor[regime == "CRISIS"][order(-abs(cor_regime))][1:8]),

    crisis_regime_findings = list(
      ar_vrp_crisis = "AR-VRP CRISIS regime cor -0.461 (post-2015 -0.345 대비 더 강한 hedge — 위기 시 VRP의 hedge 강도 강화)",
      kr10y_defensive_crisis = "KR_10y-Defensive CRISIS cor -0.413 (flight-to-quality 두 source 양립 — 채권 + low-vol 모두 위기 자산 회피)",
      defensive_vrp_crisis = "Defensive-VRP CRISIS cor -0.386 (Defensive low-vol과 VRP convex payoff 양립)",
      ar_kr10y_crisis = "AR-KR10y CRISIS cor -0.382 (post-2015 -0.122 대비 강화 — 위기 시 채권 hedge 효과 증폭)",
      commodity_vrp_crisis = "Commodity-VRP CRISIS cor 0.811 (강한 동조 — 두 inflation/vol hedge가 위기 시 동조하는 위험 — production weight 시 BULL/CRISIS condition split or single source 권고)"
    ),

    regime_sigma_pd = df_to_listrows(regime_pd),
    regime_pd_findings = list(
      bull_pd = "BULL n=41 cn=64.2 PD",
      normal_pd = "NORMAL n=40 cn=128.5 PD",
      caution_pd = "CAUTION n=40 cn=84.8 PD",
      crisis_pd = "CRISIS n=14 cn=147.8 PD (작은 n에도 PD 유지 — eigenvalue 양수)",
      shrinkage_recommendation = "Pfaff 2016 Ch.7 hard threshold cn=500 미초과, prompt cn≤100 standard 적용 시 NORMAL 128/CRISIS 148 breach (Codex C2 PARTIAL_ACCEPT). 정식 lifecycle Ledoit-Wolf shrinkage 적용 후 cn 재계산 의무. 본 cycle 4는 sample-only diagnostic. **본 cycle 4 일반론적 cn≤100 standard 적용 시 shrinkage 의무**",
      pit_c5_caveat = "정식 채택 시 t-1 expanding regime 적용 시 cn 변동 가능, 본 cycle 4는 baseline diagnostic — PIT-C5 strict는 production overlay 시 의무 (Codex C3 ACCEPT_PARTIAL)"
    ),

    crisis_bootstrap_revised_metrics = df_to_listrows(boot),

    crisis_bootstrap_findings = list(
      criteria_revision_rationale = "사이클 3 'crisis pass rate' criteria SR>0 → CRISIS regime 정의상 SR<0 (Hybrid bottom 10%). 본 cycle 4 revised metrics: (a) SR improvement (vs baseline w=0) (b) vol contraction (c) MDD relief — defensive integration의 3-축 검증",
      defensive_15pct_winner = "Defensive 15%: SR_improve_pct 79.1% / vol_contract_pct 46.3% / MDD_relief_pct 89.2%. 3-axis 종합 가장 우월",
      vrp_15pct = "VRP 15%: SR_improve_pct 43.1% / vol_contract_pct 72.8% / MDD_relief_pct 89.5%. SR 개선 약하지만 vol/MDD 개선 강",
      commodity_15pct = "Commodity 15%: SR_improve_pct 56.5% / vol_contract_pct 66.0% / MDD_relief_pct 89.9%. 균형형",
      pass_rate_caveat = "사이클 3 reported 'VRP 100% / Defensive 90% / Commodity 85%' 는 SR>0 criteria 기준이며 사이클 4에서 정의 부적합 확인. 본 cycle 4 revised criteria가 학술 정합."
    ),

    artifacts_csv = c(
      "axis2_dcc_6src_timeseries.csv",
      "axis2_dcc_6src_summary.csv",
      "axis2_regime_cor_6src.csv",
      "axis2_regime_sigma_pd.csv",
      "axis2_crisis_bootstrap_1000.csv"
    )
  ),

  # ============================================================================
  # AXIS 3: Pre-2010 stress backfill (cycle 4 final)
  # ============================================================================
  axis_3_pre2010_stress_backfill = list(
    purpose = "사이클 3 Codex C2 (static full-sample combo diagnostics rather than walk-forward) + C4 (crisis_n=26 RF-R8) inheritance. AR strategy post-2005 시작 한계 (IMF 1997 + DotCom 2000 미경험) 정량 인지 + 8 stress periods BM extension.",
    methodology = list(
      bm_extension = "Benchmark daily 1990-01 ~ 2026-05 (8944 obs, 36.3 years). Monthly aggregation via prod(1+r)-1.",
      stress_periods = list(
        IMF_1997 = "1997-07 ~ 1998-06 (12m, Asian financial crisis)",
        DotCom_2000 = "2000-04 ~ 2001-12 (21m)",
        GFC_2008 = "2008-09 ~ 2009-03 (7m)",
        EuDebt_2011 = "2011-08 ~ 2011-12 (5m)",
        China_2015 = "2015-06 ~ 2015-09 (4m)",
        VolShock_2018 = "2018-01 ~ 2018-03 (3m)",
        COVID_2020 = "2020-02 ~ 2020-04 (3m)",
        Inflation_2022 = "2022-01 ~ 2022-12 (12m)"
      ),
      crisis_count = "BM bottom 10% threshold 적용. pre-2010 vs post-2010 카운트"
    ),
    bm_36year_extension = list(
      total_months = 437,
      pre_2010_months = 240,
      post_2010_months = 197,
      pre_2010_crisis_count = 36,
      post_2010_crisis_count = 8,
      crisis_count_ratio = 4.50,
      interpretation = "1990~2009 (20년) BM은 36 crisis month 보유. 2010~2026 (16년)는 8 month. ratio 4.50x. **Post-2010 sample은 명백한 crisis under-sampling** — 사이클 3 192m diagnostic은 4.50x crisis-poor sample (Codex C6 PARTIAL_REBUTTAL)."
    ),
    stress_8periods = df_to_listrows(stress),
    key_findings_axis3 = list(
      imf_1997_bm = "BM cumret -60.0% (12m). AR strategy 데이터 X (시작 2005-02). 한국 시장 가장 깊은 crisis.",
      dotcom_2000_bm = "BM cumret -19.4% (21m). AR strategy 데이터 X. 점진적 grind down.",
      gfc_2008_bm_ar_hyb = "BM -18.2% / AR -11.8% / Hybrid -8.2%. Hybrid가 AR보다 4pp + BM보다 10pp 우월. KR_10y defensive contribution.",
      eudebt_2011_resilient = "BM -14.4% but AR +9.6% / Hybrid +8.9%. AR strategy crisis alpha 입증.",
      china_2015_resilient = "BM -7.2% but AR +17.7% / Hybrid +12.8%. AR가 crisis alpha source.",
      volshock_2018_neutral = "BM -0.9% / AR +1.9% / Hybrid +1.3%. 단기 vol 충격 모두 통과.",
      covid_2020_double_loss = "BM -8.1% / AR -16.1% / Hybrid -11.5%. AR가 BM보다 더 손실 — high-momentum factor 역회전. Hybrid가 일부 완화.",
      inflation_2022_resilient = "BM -24.9% but AR -3.9% / Hybrid -3.9%. Long inflation regime AR + Hybrid 모두 견고."
    ),
    pre_2010_extension_caveat = list(
      ar_strategy_post_2010_only = TRUE,
      ar_imf_1997_observed = FALSE,
      ar_gfc_2008_observed = TRUE,
      candidate_post_2015_only = "TSMOM / Defensive / Commodity / VRP 모두 post-2015 가용 (또는 일부 post-2005). IMF 1997 / DotCom 2000 candidate 직접 검증 X.",
      bm_only_path = "Pre-2010 BM extension은 'KR market 일반 위기 응답 패턴' 진단만 제공. Candidate 직접 검증은 (a) 4 candidate 모두 pre-2010 historical proxy 재구축 (b) BM-correlation regime mapping 재현 (c) parametric EVT GPD CRISIS regime 시뮬레이션 (Pfaff 2016 Ch.7) 중 하나 의무.",
      acceptance_criterion = "정식 채택 시 4 candidate 중 최소 1건의 pre-2010 historical proxy 또는 EVT parametric extension 의무. Cycle 4는 BM-only baseline diagnostic."
    ),
    literature_anchor_axis3 = list(
      mandelbrot_1963 = "Mandelbrot B. (1963) JoB — Financial returns fat-tail distribution. Pre-2010 데이터 없는 EVT는 underestimate of tail.",
      pfaff_2016_ch7 = "Pfaff B. (2016) FRM Ch.7 — EVT POT method (threshold 80/90/95%). KR market 36-year BM tail (pre-2010 36 crisis vs post-2010 8 crisis) 시 fit이 더 robust.",
      lopez_de_prado_2018 = "Lopez de Prado M. (2018) AFML Ch.13 — meta-research는 hypothesis generation, walk-forward는 hypothesis testing. 본 cycle 4는 hypothesis generation 단계."
    ),
    artifacts = c("axis3_8stress_historical.csv", "axis3_pre2010_summary.json")
  ),

  # ============================================================================
  # cycle4_codex_concerns_disposition C1~C10
  # ============================================================================
  cycle4_codex_concerns_disposition = list(
    C1_canonical_artifacts_absence = list(
      severity = "HIGH",
      codex_text = "user-specified stage artifact dirs, weights.csv, alpha_scores.parquet, covariance.parquet absent. mailbox contains only meta-research artifacts.",
      cycle4_disposition = "ACCEPT",
      rebuttal_argument = "Q-Lead instruction 자체가 메타 리서치 scope (path: qepm/mailbox/research/). 정식 WT path는 qepm/mailbox/worktask/{WT_id}/. Codex가 정확히 식별 — approval-grade verification cannot be completed.",
      action = "research_type='meta_self_research_qlead_ondemand_cycle4' retain. scope_disclaimer 정직 명시 retain. 정식 lifecycle 권고 retain.",
      evidence = "Charter v1.7 §10 Role Card: meta-research는 own/inherit/exempt/optional 분류 자체 X. AX-002 process honesty 준수: 정식 lifecycle 보강 reference research 명시.",
      citations = list("Charter v1.7 §10 Role Card", "AX-002 process honesty")
    ),

    C2_post_shrink_sigma_absence = list(
      severity = "HIGH",
      codex_text = "Available sample regime covariances are PD, but NORMAL cond=128.45 and CRISIS cond=147.80 breach the prompt's cond<=100 standard. Shrinkage intensity, Ledoit-Wolf type, Gerber/RMT comparison, selection objective, and factor coverage R2 are absent.",
      cycle4_disposition = "PARTIAL_ACCEPT",
      rebuttal_argument = "사이클 1 (covariance_3src_5estimator_summary.csv) + 사이클 2 (covariance_4src_5estimator_summary.csv) 5 estimator 비교 inheritance. 사이클 4는 DCC dynamic / per-regime / bootstrap 차원 추가 — estimator shopping 무한 루프 회피. NORMAL cn=128 / CRISIS cn=148은 Pfaff 2016 Ch.7 hard threshold 500의 30% 수준이지만 prompt cn≤100 standard breach.",
      action = "정식 lifecycle 의무 (post-shrink Ledoit-Wolf direct + cn ≤ 100 report + factor coverage R²) retain. 사이클 1+2 estimator shopping inheritance 명시 강화.",
      evidence = "사이클 1 covariance_3src_5estimator_summary.csv (Sample/LW_identity/LW_constcor/Gerber-RMT/nonlinear_shrinkage) + 사이클 2 covariance_4src_5estimator_summary.csv 동일 5 estimator. 본 cycle 4 axis_2C regime_pd 모두 PD (BULL 64 / NORMAL 128 / CAUTION 85 / CRISIS 148).",
      citations = list("Ledoit-Wolf 2003 JEFAS", "Pfaff 2016 FRM Ch.7", "사이클 1+2 5 estimator log")
    ),

    C3_regime_sigma_grade = list(
      severity = "HIGH",
      codex_text = "BULL/NORMAL/CAUTION/CRISIS n are 41/40/40/14, labels use full-sample Hybrid quantiles, CRISIS has no pooled fallback or Sigma CI, no regime switch-rate audit.",
      cycle4_disposition = "PARTIAL_ACCEPT",
      rebuttal_argument = "**ACCEPT** (regime n + pooled fallback): CRISIS n=14 통계 검증 충분 X. pooled fallback 본 cycle 4 직접 산출 X. **PARTIAL REBUTTAL** (PIT-C5): 본 cycle 4는 diagnostic only — production overlay 의무 X. PIT-C5 strict는 production overlay 시 t-1 expanding 의무. Diagnostic post-2015 in-sample classification은 Hamilton 1989 ECMA Markov regime fitting standard.",
      action = "regime_pd_findings.pit_c5_caveat 명시 (정식 채택 시 t-1 expanding 의무). CRISIS n=14 통계 한계 정직 명시. EVT GPD parametric extension 권고.",
      evidence = "axis2_regime_sigma_pd.csv 4 regime × cn/min_eig/PD 모두 PD. axis2_crisis_bootstrap_1000.csv n_crisis=14 + B=1000.",
      citations = list("Hamilton 1989 ECMA Markov regime", "Pfaff 2016 FRM Ch.7 EVT POT", "L-274 STR_1715 PG2 regime window")
    ),

    C4_tail_risk_incomplete = list(
      severity = "HIGH",
      codex_text = "Inherited hybrid CVaR95 loss magnitude is about 6.6% versus the 2.5% cap, CDaR95 is absent, EVT VaR/ES is missing for several series, IMF_1997/DotCom_2000 have no AR/Hybrid/candidate observations.",
      cycle4_disposition = "PARTIAL_ACCEPT",
      rebuttal_argument = "ACCEPT: Hybrid CVaR95 6.6% > 2.5% cap 정확. PARTIAL REBUTTAL: 2.5% CVaR cap은 production-ready threshold (Charter §10), 메타 리서치는 baseline diagnostic. 사이클 1+2 tail metrics inheritance. IMF/DotCom AR observations 부재는 사이클 4 axis_3에서 정량 명시.",
      action = "정식 lifecycle 의무 (CVaR95 / CDaR95 / VaR99 / ES99 + EVT GPD parametric extension) retain. 사이클 1+2 tail inheritance 명시.",
      evidence = "사이클 1 bm_kospi_36yr_tail_fit.csv + 사이클 2 candidates_tail_risk_metrics.csv. 본 cycle 4 axis_3 8 stress periods.",
      citations = list("Pfaff 2016 FRM Ch.7", "Mandelbrot 1963 JoB")
    ),

    C5_pg2_crowding_absent = list(
      severity = "HIGH",
      codex_text = "TDC vs PG2 active book, HHI, style correlation against existing active exposure, family saturation absent. Internal Commodity-VRP CRISIS correlation is 0.8108.",
      cycle4_disposition = "ACCEPT_OUT_OF_SCOPE",
      rebuttal_argument = "ACCEPT: PG2 active book 직접 진단은 정식 lifecycle scope. Brunnermeier-Pedersen 2009 RFS — crowding은 production active book size + funding liquidity + market impact 3-axis. 본 cycle 4 6-source diagnostic은 candidate orthogonality only.",
      action = "Commodity-VRP CRISIS 0.811 finding은 'production weight 시 BULL/CRISIS condition split or single source' 권고 retain. 정식 lifecycle 시 PG2 active book × 6-source style correlation 의무.",
      evidence = "axis2_regime_cor_6src.csv 60 row (4 regime × 15 pair). Commodity-VRP CRISIS 0.811 row 1.",
      citations = list("Brunnermeier-Pedersen 2009 RFS", "L-219 family saturation")
    ),

    C6_termination_walk_forward = list(
      severity = "HIGH",
      codex_text = "Termination recommendation still relies on static full-sample combo diagnostics and a 192-month SR=1.997 path rather than walk-forward alpha→risk→optimizer recalculation. Repeats static-snapshot failure mode.",
      cycle4_disposition = "PARTIAL_ACCEPT",
      rebuttal_argument = "ACCEPT: 사이클 4 termination_recommendation은 사이클 3 static 192m diagnostic 인용. PARTIAL REBUTTAL: 사이클 4의 termination 권고 자체가 메타 리서치 종료 + 정식 lifecycle 권고 — walk-forward는 정식 lifecycle 의무. Lopez de Prado 2018 Ch.13 — meta-research는 hypothesis generation, walk-forward는 hypothesis testing.",
      action = "termination_recommendation 표현 정정: '사이클 5 spawn marginal value 작음' → '사이클 5는 메타 path 반복, 정식 lifecycle 진입이 walk-forward + post-shrink + WT artifacts + Architect 검증 의무 충족 path'. next_action 4 action retain.",
      evidence = "axis3_8stress_historical.csv 8 named periods. axis3_pre2010_summary.json crisis ratio 4.50x.",
      citations = list("Lopez de Prado 2018 AFML Ch.13", "L-119 정적 EW 팩터 블렌드 패턴")
    ),

    C7_vrp_us_vix_proxy = list(
      severity = "HIGH",
      codex_text = "VRP source remains a US VIX proxy despite no KOSPI200 options/VKOSPI cache and only VIX-KOSPI RV correlations of 0.505 in levels and 0.191 in differences.",
      cycle4_disposition = "ACCEPT",
      rebuttal_argument = "ACCEPT — Codex 정확. 본 cycle 4 axis_1 conclusion에서 정직 인정. 'medium-strength proxy acceptable' 표현은 합리화 위험 (정정). Bollerslev-Tauchen-Zhou 2009 RFS — VRP estimation은 동일 시장 implied vol + realized vol 의무.",
      action = "axis_1.cycle3_vix_proxy_retain.interpretation에서 'medium-strength proxy acceptable' → 'cross-market proxy 한계 명시 retain' 정정. KRX direct fetch 4-step 권고 retain.",
      evidence = "axis1_kospi200_options_check.json data_check 모든 cache 부재. acquisition_path 명시.",
      citations = list("Bollerslev-Tauchen-Zhou 2009 RFS", "Carr-Wu 2009 RFS variance swap")
    ),

    C8_defensive_q07_absent = list(
      severity = "MEDIUM",
      codex_text = "Defensive_LowVol_KR is still a return-volatility proxy, not Q07_Earnings_Stability or a multi-axis quality composite. AX-001 not cleared, AX-005 only gives exclusion.",
      cycle4_disposition = "PARTIAL_ACCEPT",
      rebuttal_argument = "ACCEPT: Defensive return-volatility BAB Frazzini-Pedersen 2014 proxy retain. AX-001 v2 'crisis_alpha + Core MDD relief + bad/normal IC ratio' 본 cycle 4 일부 axis 정량 (Defensive 15% MDD_relief 89.2%) 검증, 정식 lifecycle 시 완전 검증 의무. AX-005 v1.2 multi-sleeve EXCLUSION 자격 (necessary not sufficient).",
      action = "정식 alpha-research WT spawn 시 Q07 + multi-axis quality composite (Earnings_Stability + ROE_Stability + Asset_Turnover_Stability + Earnings_Quality 4-axis) 의무 명시 retain.",
      evidence = "axis2_crisis_bootstrap_1000.csv: r_defensive w=0.15 SR_improve_pct 79.1% / vol_contract_pct 46.3% / MDD_relief_pct 89.2%.",
      citations = list("Frazzini-Pedersen 2014 JFE BAB", "L-121 Q07 stress ICIR")
    ),

    C9_ar_concentration_mctv = list(
      severity = "MEDIUM",
      codex_text = "AR concentration is not resolved. Cycle 4 does not recompute marginal contribution to variance, while inherited cycle3 diagnostics reported mctv_AR about 0.98-1.00 for non-risk-parity combos.",
      cycle4_disposition = "ACCEPT",
      rebuttal_argument = "ACCEPT — Codex 정확. 본 cycle 4 axis_2 mctv 재계산 X. 70% AR weight 자체 dominant. Maillard-Roncalli-Teiletche 2010 JoPM — ERC portfolio 시 mctv_AR 0.50~0.60 가능.",
      action = "termination_recommendation.next_action_recommendation action_3에서 optimizer-research WT spawn 시 70/15/15 retain vs ERC re-balance 명시 retain.",
      evidence = "사이클 3 risk_package.json combo_192m_6source_full mctv_AR 0.987~1.001 inheritance. 본 cycle 4 산출 X.",
      citations = list("Maillard-Roncalli-Teiletche 2010 JoPM ERC", "L-484 종목레벨 score")
    ),

    C10_ax008_triangulation_incomplete = list(
      severity = "MEDIUM",
      codex_text = "AX-008 not satisfied: package reports partial/NA triangulation and no Architect verification, while previous Codex stance was REJECT. Termination decision cannot substitute for two independent PASS sources.",
      cycle4_disposition = "ACCEPT_RISK_RESEARCH_SCOPE_LIMITATION",
      rebuttal_argument = "ACCEPT — Codex 정확. AX-008 (Forge + Codex + Architect 2/3 PASS) 본 cycle 4 risk-research scope에서: Forge OK + Codex REJECT + Architect NA = 1.5/3 (PASS criteria 미충족). Architect 검증은 정식 lifecycle scope.",
      action = "termination_recommendation criteria_2 표현 정정 ('PARTIAL — risk-research scope 한계' → 'AX-008 미충족 (1/3 + Codex REJECT), 정식 lifecycle Architect 검증 의무'). 정식 lifecycle 권고 retain.",
      evidence = "사이클 1 codex REJECT + 사이클 2 codex REJECT + 사이클 3 codex REJECT + 사이클 4 codex REJECT — 4 cycles consecutive REJECT. Q-Lead escalate 의무.",
      citations = list("AX-008 verification triangulation", "사이클 1~4 codex 4 consecutive REJECT")
    )
  ),

  # ============================================================================
  # 합리화 표현 정정 6건 (Codex rationalization_red_flags 인지)
  # ============================================================================
  rationalization_corrections = list(
    correction_1 = list(
      original = "medium-strength proxy acceptable",
      corrected = "cor 0.505 level은 cross-market proxy 한계 — KOSPI200 옵션 chain direct가 정식 의무",
      location = "axis_1.cycle3_vix_proxy_retain.interpretation"
    ),
    correction_2 = list(
      original_pattern = "본 메타 리서치 scope 외부 / 정식 lifecycle scope (반복)",
      corrected = "정식 lifecycle 의무 명시 (메타 리서치 vs 정식 lifecycle 구분 retain, 표현 강화)",
      location = "various — partial retain"
    ),
    correction_3 = list(
      original = "CRISIS n=14 다소 작음 — bootstrap 1000 trial로 보강",
      corrected = "CRISIS n=14는 통계 검증 충분 X (전통적 n≥30 standard 이하). bootstrap 1000 trial은 sample uncertainty quantification only — sample 자체 한계 해소 X. 정식 lifecycle EVT GPD parametric extension 의무",
      location = "axis_2.sample.crisis_n_caveat"
    ),
    correction_4 = list(
      original = "CRISIS regime cn=147.8 < 500 (정식 hard threshold)",
      corrected = "Pfaff 2016 hard threshold cn=500 미초과, prompt cn≤100 standard 적용 시 NORMAL 128/CRISIS 148 breach",
      location = "axis_2.regime_pd_findings.shrinkage_recommendation"
    ),
    correction_5 = list(
      original = "부분 충족",
      corrected = "AX-001 v2 일부 axis 정량 검증, 정식 lifecycle 시 완전 검증 의무",
      location = "cycle4_codex_concerns_disposition.C8.rebuttal_argument"
    ),
    correction_6 = list(
      original = "사이클 5 spawn marginal value 작음",
      corrected = "사이클 5는 동일 메타 리서치 path 반복, 정식 alpha-research → risk-research → optimizer-research lifecycle 진입이 walk-forward + post-shrink + WT artifacts + Architect 검증 의무 충족 path",
      location = "termination_recommendation.decision_rationale.evidence_4_diminishing_return"
    )
  ),

  # ============================================================================
  # Termination Recommendation (cycle 4 final)
  # ============================================================================
  termination_recommendation = list(
    criteria_check = list(
      sr_boost_path_clear = list(
        requirement = "SR boost ≥ 0.20 path 명확 (단, 메타 리서치 reference only — 정식 lifecycle 의무 명시)",
        sr_standalone = 1.5854,
        sr_multi_combo_best_192m = 1.997,
        sr_boost_observed = 0.412,
        threshold = 0.20,
        pass = TRUE,
        evidence_cycle3 = "사이클 3 best combo 10DEF+10COM+5VRP SR 1.997 (192m post-2010 static diagnostic). target 2.0 gap 0.003. STR_1715 standalone SR 1.5854 → 0.412 boost. 0.20 threshold 2.06× margin. **Codex C6 PARTIAL_ACCEPT**: static 192m 진단은 메타 리서치 reference, walk-forward는 정식 lifecycle 의무.",
        caveat = "Static 192m SR 1.997는 walk-forward alpha→risk→optimizer recalculation X. 정식 lifecycle 시 walk-forward 검증 후 SR 변동 가능."
      ),
      ax_008_triangulation = list(
        requirement = "AX-008 Triangulation 2/3 PASS",
        cycle4_status = "1/3 (Forge OK + Codex REJECT + Architect NA)",
        forge = "PASS — run_cycle4.R + run_cycle4.log self-verification",
        codex = "REJECT (4 consecutive cycles 1~4 모두 REJECT)",
        architect = "NA (risk-research scope에서 architect 진단은 정식 lifecycle scope)",
        pass = FALSE,
        rationale = "AX-008 미충족. 정식 lifecycle Architect 검증 의무. 메타 리서치 종료 + 정식 alpha-research → risk-research → optimizer-research lifecycle 진입이 PASS criteria 충족 path."
      )
    ),
    decision = "TERMINATE_META_RESEARCH_RECOMMEND_FORMAL_LIFECYCLE",
    decision_rationale = list(
      evidence_1_sr_path = "SR boost 0.412 ≥ 0.20 threshold 2.06× margin (사이클 3 192m static diagnostic). 사이클 1 (gap 0.335) → 사이클 3 (gap 0.003) 99.1% 좁힘. **Static reference only — walk-forward 정식 lifecycle 의무**",
      evidence_2_codex_concerns = "사이클 1~4 4 consecutive Codex REJECT. 사이클 4 10 concerns (HIGH 7 + MEDIUM 3). 메타 리서치 scope 한계: Q07 direct + walk-forward + post-shrink Σ + KRX 옵션 + PG2 active book 모두 정식 lifecycle 의무. Codex 4 cycles 일관 진단 — 메타 리서치 path는 lifecycle 진입 의무 강화 evidence",
      evidence_3_data_limit = "KOSPI200 옵션 chain cache 부재 (axis_1) + AR strategy post-2010 only + 4 candidate post-2015 only (axis_3) 데이터 한계 본 cycle 4 단계에서 더 이상 해소 불가. KRX OpenAPI 인증 + 5년 cache 누적 의무는 정식 lifecycle scope",
      evidence_4_diminishing_return_corrected = "사이클 1 (gap 0.335 좁힘 0.50pp 정량) → 사이클 2 (gap 0.05 좁힘 0.285pp) → 사이클 3 (gap 0.003 좁힘 0.047pp) → 사이클 4 (gap 0.003 retain). **사이클 5는 동일 메타 리서치 path 반복** (Codex inheritance 동일 메타 진단 limitations). 정식 alpha-research → risk-research → optimizer-research lifecycle 진입이 walk-forward + post-shrink + WT artifacts + Architect 검증 의무 충족 path."
    ),
    next_action_recommendation = list(
      action_1 = "정식 alpha-research WT spawn — Q07 direct + multi-axis quality composite (Earnings_Stability + ROE_Stability + Asset_Turnover_Stability + Earnings_Quality 4-axis) + Defensive (BAB Frazzini-Pedersen 2014) factor specs 작성",
      action_2 = "정식 risk-research WT spawn — alpha_package 수신 후 종목 단위 BΩB'+D decomposition + post-shrink Σ (Ledoit-Wolf direct + Gerber/RMT 비교 + cn ≤ 100 report + factor coverage R²) + PG2 active book TDC + HHI + style correlation + 8 named stress periods CVaR/CDaR/VaR99/ES99 + EVT GPD parametric extension (Pfaff 2016 Ch.7)",
      action_3 = "정식 optimizer-research WT spawn — α̂ + Σ 수신 후 70/15/15 retain vs ERC re-balance vs 70/10/10/10 (STR_1715/Defensive/Commodity/VRP) 결정. SR > 2.0 / MDD < -25% / CAGR ≥ 16% target 검증. mctv_AR 0.98 → 0.50~0.60 ERC 적용",
      action_4_parallel = "KRX OpenAPI 인증 키 발급 + data_collector_krx_options.R 일일 cron 등록 (병렬 path) — 5년 누적 후 정식 BKM/CW VRP direct 재산출 (cycle 5+ 정식 lifecycle 통합)"
    ),
    pre_2010_extension_priority = list(
      priority = "MEDIUM",
      reason = "사이클 4 Axis 3에서 pre-2010 BM crisis 4.50x 정량 인지. AR strategy 자체 IMF 1997 / DotCom 2000 미경험 한계는 (a) 4 candidate parametric EVT GPD CRISIS 시뮬레이션 (Pfaff 2016 Ch.7) (b) AR strategy historical proxy 재구축 (alpha-research scope) 둘 중 하나로 해소 가능. 정식 lifecycle 시 우선순위 MEDIUM (mainly 충족 — KR market 동시기 BM 응답 패턴 진단)"
    )
  ),

  # ============================================================================
  # PIT C1~C15 audit (cycle 4 final)
  # ============================================================================
  pit_audit = list(
    C1 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "본 cycle 4 6-source DCC + per-regime + bootstrap은 static post-2015 sample. Walk-forward는 정식 lifecycle 의무 (Codex C6 PARTIAL_ACCEPT)"),
    C2 = list(status = "PASS", evidence = "vix_lag1 = shift(vix_eom, 1L) 사이클 3 inheritance retain. cycle 4 Axis 2 DCC 6-src는 입력 returns t-월 lag 적용"),
    C3 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "본 cycle 4 6-source DCC 동일 sample 적용 X. 정식 walk-forward time-varying Σ는 lifecycle 의무"),
    C4 = list(status = "NA", evidence = "재무제표 lag 본 cycle 4 scope 외 (returns 단위)"),
    C5 = list(status = "DIAGNOSTIC_ONLY", evidence = "사이클 4 axis 2 regime classification은 Hybrid bottom 10% threshold full-sample (PIT-C5 strict는 production overlay 시 t-1 expanding 의무, diagnostic only 명시) — Codex C3 ACCEPT_PARTIAL"),
    C9 = list(status = "PASS", evidence = "DD/VT lag 사이클 1+2+3 inheritance"),
    C11 = list(status = "PASS", evidence = "FRED VIX monthly EOM lag 1 month 적용. 보수적 (vs 1-day) — Codex C7 정확 인지: 1-month lag은 conservative for timing, but does not solve cross-market proxy validity issue"),
    C12 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "본 cycle 4 BΩB'+D 종목 단위 decomposition 직접 산출 X — 정식 lifecycle 의무 (Codex C1 ACCEPT)"),
    C13 = list(status = "PASS", evidence = "Z_Score_Aligned 본 cycle 4 scope X — return-level diagnostic"),
    C14 = list(status = "NA", evidence = "IC 접근 본 cycle 4 scope X"),
    C15 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "Factor DB Q07 직접 X — 정식 lifecycle 의무 (Codex C8 PARTIAL_ACCEPT). cycle 4 axis 2 axis 3 master_returns 사이클 2 inheritance + benchmark.parquet direct.")
  ),

  # ============================================================================
  # Red Flags
  # ============================================================================
  red_flags = list(
    RF_R8_acknowledged = list(
      severity = "HIGH",
      flag = "regime n insufficient (CRISIS n=14 post-2015 6-source) + n_BULL/NORMAL/CAUTION 41/40/40 < 100 prompt expectation",
      mitigation = "Bootstrap 1000 trial revised metrics (SR_improve / vol_contract / MDD_relief). 정식 lifecycle EVT GPD parametric extension (Pfaff 2016 Ch.7) 의무 명시 — Codex C3 ACCEPT_PARTIAL"
    ),
    RF_R6_acknowledged = list(
      severity = "MEDIUM",
      flag = "tail risk (CVaR/CDaR/Hill alpha/VaR99/ES99) 본 cycle 4 직접 산출 X. Hybrid CVaR95 6.6% > 2.5% cap (사이클 inheritance)",
      mitigation = "사이클 1 bm_kospi_36yr_tail_fit.csv + 사이클 2 candidates_tail_risk_metrics.csv inheritance. 본 cycle 4 axis 2D bootstrap MDD revised metric. 정식 lifecycle CVaR95 / CDaR95 / VaR99 / ES99 + EVT GPD 의무 — Codex C4 PARTIAL_ACCEPT"
    ),
    RF_R5_addressed_partial = list(
      severity = "LOW",
      flag = "factor pair cor > 0.8 (Commodity-VRP CRISIS 0.811)",
      mitigation = "CRISIS regime conditional 발견 — production weight 시 BULL/CRISIS condition split or Commodity OR VRP single source 권고. 정식 lifecycle 시 full PG2 active book × 6-source style correlation 의무"
    ),
    RF_R3_acknowledged = list(
      severity = "HIGH",
      flag = "PG2 active book TDC / HHI / style correlation / family saturation 본 cycle 4 직접 진단 X — Codex C5 ACCEPT_OUT_OF_SCOPE",
      mitigation = "정식 risk-research WT spawn 시 PG2 active book × 6-source 의무. 본 cycle 4는 candidate orthogonality only"
    ),
    RF_R2_acknowledged = list(
      severity = "MEDIUM",
      flag = "post-shrink Σ 부재 (cycle 4 sample only). NORMAL cn=128 / CRISIS cn=148 prompt cn≤100 standard breach — Codex C2 PARTIAL_ACCEPT",
      mitigation = "사이클 1+2 5 estimator 비교 inheritance. 정식 lifecycle Ledoit-Wolf direct + cn ≤ 100 report 의무"
    ),
    RF_R1_acknowledged = list(
      severity = "MEDIUM",
      flag = "AR concentration (mctv_AR 0.98+ 사이클 3 inheritance) — Codex C9 ACCEPT",
      mitigation = "정식 optimizer-research WT spawn 시 ERC re-balance — mctv_AR 0.50~0.60 가능 (Maillard-Roncalli-Teiletche 2010 JoPM)"
    )
  ),

  # ============================================================================
  # AX 공리 compliance
  # ============================================================================
  ax_axiom_compliance = list(
    ax_001_v2_conditional_metric = list(
      status = "PARTIAL_ACCEPT",
      evidence = "AX-001 v2 'crisis_alpha + Core MDD relief + bad/normal IC ratio' 일부 axis 정량 검증 (Defensive 15% MDD_relief 89.2% / VRP 15% MDD_relief 89.5% / Commodity 15% MDD_relief 89.9%). bad/normal IC ratio 본 cycle 4 직접 산출 X (정식 lifecycle 의무) — Codex C8 PARTIAL_ACCEPT"
    ),
    ax_002_process_honesty = list(
      status = "ACCEPT_DOCUMENT_LIMITATIONS",
      evidence = "본 cycle 4 scope_disclaimer + cycle4_codex_concerns_disposition + rationalization_corrections 6건 정직 명시. 메타 리서치 vs 정식 lifecycle 구분 retain. 합리화 표현 6건 정정 — Codex 4 consecutive REJECT 대응"
    ),
    ax_005_v1_2 = list(
      status = "EXCLUSION_NECESSARY_NOT_SUFFICIENT",
      evidence = "Defensive multi-sleeve EXCLUSION (4-sleeve hybrid 70/15/15 + 5%×Defensive) 자격 충족 — single-sleeve standalone 평가 X. 정식 채택 시 Q07 direct + multi-axis quality composite 의무"
    ),
    ax_007_methodological = list(
      status = "AWARE_NOT_VIOLATED",
      evidence = "본 cycle 4는 portfolio combination diagnostic — single-sleeve top20 long-only 구조 X. multi-sleeve hybrid (70/15/15 + candidate addition) 자체가 AX-007 예외 (multi-sleeve)"
    ),
    ax_008_verification_triangulation = list(
      status = "FAIL_INCOMPLETE",
      evidence = "1.5/3 (Forge OK + Codex REJECT + Architect NA). risk-research scope에서 Architect 진단은 정식 lifecycle scope. **Codex 4 consecutive cycles REJECT** — Q-Lead escalate 의무, 메타 리서치 종료 권고 — Codex C10 ACCEPT"
    )
  ),

  # ============================================================================
  # Q-Lead Escalate 보고
  # ============================================================================
  qlead_escalate = list(
    triggered = TRUE,
    trigger_criteria = list(
      high_severity_count = 7,
      high_severity_threshold = 5,
      ax_axiom_hard_fail_count = 3,
      ax_axiom_threshold = 3,
      pit_hard_violation_new = FALSE
    ),
    escalate_summary = "Codex 사이클 4 REJECT (veto=false) — HIGH 7 + MEDIUM 3 + AX-001/AX-002/AX-008 FAIL. 4 consecutive cycles (1~4) Codex REJECT 패턴. 메타 리서치 path 자체 한계 (Q07 direct + walk-forward + post-shrink Σ + KRX 옵션 + PG2 active book + Architect 검증 모두 정식 lifecycle 의무).",
    qlead_action_recommended = list(
      action_1 = "메타 리서치 cycle 4 종료 (TERMINATE)",
      action_2 = "정식 alpha-research WT spawn (Q07 + multi-axis quality + Defensive Frazzini-Pedersen factor specs)",
      action_3 = "정식 risk-research WT spawn (BΩB'+D + post-shrink Σ + PG2 crowding + EVT GPD)",
      action_4 = "정식 optimizer-research WT spawn (70/15/15 vs ERC vs 70/10/10/10)",
      action_5_parallel = "KRX OpenAPI 인증 + data_collector_krx_options.R cron 등록 (병렬 path, cycle 5+ 정식 lifecycle 통합)"
    )
  ),

  # ============================================================================
  # Artifacts manifest
  # ============================================================================
  artifacts_manifest = list(
    primary_csv = c(
      "axis1_kospi200_options_check.json",
      "axis2_dcc_6src_timeseries.csv",
      "axis2_dcc_6src_summary.csv",
      "axis2_regime_cor_6src.csv",
      "axis2_regime_sigma_pd.csv",
      "axis2_crisis_bootstrap_1000.csv",
      "axis3_8stress_historical.csv",
      "axis3_pre2010_summary.json"
    ),
    primary_json = c(
      "termination_check.json",
      "cycle4_log.json",
      "risk_package_draft.json",
      "codex_critic_response_risk.json"
    ),
    code = c(
      "run_cycle4.R",
      "build_draft.R",
      "build_final.R"
    ),
    challenge_note = "risk_challenge_note.md",
    inheritance = c(
      "사이클 1: qepm/mailbox/research/risk_model_meta_20260507/",
      "사이클 2: qepm/mailbox/research/risk_candidates_20260507/",
      "사이클 3: qepm/mailbox/research/risk_cycle3_20260507/"
    )
  )
)

# Write
write_json(final, file.path(OUT_DIR, "risk_package.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")

cat(sprintf("\nrisk_package.json (FINAL) written: %d bytes\n",
            file.info(file.path(OUT_DIR, "risk_package.json"))$size))
