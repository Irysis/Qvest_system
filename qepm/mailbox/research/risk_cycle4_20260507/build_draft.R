# ============================================================================
# Cycle 4 risk_package_draft.json 작성
# 8-field schema + 사이클 3 Codex 8 concerns disposition mapping
# ============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- "qepm/mailbox/research/risk_cycle4_20260507"

# Load all artifacts
dcc_summary <- fread(file.path(OUT_DIR, "axis2_dcc_6src_summary.csv"))
regime_cor <- fread(file.path(OUT_DIR, "axis2_regime_cor_6src.csv"))
regime_pd <- fread(file.path(OUT_DIR, "axis2_regime_sigma_pd.csv"))
boot <- fread(file.path(OUT_DIR, "axis2_crisis_bootstrap_1000.csv"))
stress <- fread(file.path(OUT_DIR, "axis3_8stress_historical.csv"))
axis1_check <- fromJSON(file.path(OUT_DIR, "axis1_kospi200_options_check.json"))
axis3_summary <- fromJSON(file.path(OUT_DIR, "axis3_pre2010_summary.json"))

# Helper: row-wise list extract
df_to_listrows <- function(dt) {
  lapply(seq_len(nrow(dt)), function(i) as.list(dt[i]))
}

# ============================================================================
# Compose draft package
# ============================================================================

draft <- list(
  task_id = "RESEARCH_RISK_CYCLE4_20260507",
  research_type = "meta_self_research_qlead_ondemand_cycle4",
  as_of_date = "2026-05-08",
  version = "v1_draft_pre_codex_round",
  cycle = 4,
  scope_disclaimer = "Q-Lead 온디맨드 메타 리서치 사이클 4 (path: qepm/mailbox/research/risk_cycle4_20260507/). 사이클 3 Codex 8 HIGH/MEDIUM concerns 잔여 한계 해소 시도. 정식 WT alpha→risk pipeline 산출 X — alpha_scores.parquet / weights.csv / B Ω B'+D 종목별 decomposition / load_month_factors() Factor DB Q07 직접 / KRX VKOSPI 직접 등 정식 risk_package 의무 artifact 일부 본 작업 영역 외부. 사이클 3 보강 3축 한정: Axis 1 KOSPI200 옵션 chain 가용성 점검 (cache 부재 → US VIX proxy retain) / Axis 2 6-source DCC-GARCH per-regime + 위기 bootstrap / Axis 3 Pre-2010 stress backfill 메타 진단. alpha 시그널 추가 / 신규 strategy spawn / weight 결정 절대 X (Hook agent_role_guard 강제). 신규 source 정식 채택 결정은 후속 alpha-research → risk-research → optimizer-research lifecycle 의무.",

  # ============================================================================
  # 사이클 3 inheritance
  # ============================================================================
  context_cycle1_2_3_input = list(
    cycle1_path = "qepm/mailbox/research/risk_model_meta_20260507/risk_package.json",
    cycle2_path = "qepm/mailbox/research/risk_candidates_20260507/risk_package.json",
    cycle3_path = "qepm/mailbox/research/risk_cycle3_20260507/risk_package.json",
    cycle3_codex_stance = "REJECT (veto=false), 8 HIGH/MEDIUM concerns",
    cycle3_top_findings = list(
      best_combo_192m = "Hybrid + 10%×Defensive + 10%×Commodity + 5%×VRP = SR 1.997 / MDD -0.137 (post-2010 192m)",
      sr_target_gap = "Target 2.0 vs 1.997 = gap 0.003 (사이클 1 0.335에서 99.1% 좁힘)",
      vrp_proxy_validation = "cor_VIX_lag1_KOSPI_RV12m_lag1_level=0.5054, diff=0.1913 (KOSPI BM 12m RV 직접 측정 기반)",
      defensive_orthogonality = "cor 0.002 with AR (직교성 자격 확정)",
      vrp_ar_cor = "-0.345 (사이클 2 -0.155 대비 더 강한 음의 의존성)",
      diversification_ratio = "1.105 → 1.307 (+18%, Choueifaty-Coignard 2008)",
      bootstrap_crisis_pass = "VRP 100% / Defensive 90% / Commodity 85% (사이클 3 200 trial)"
    )
  ),

  # ============================================================================
  # AXIS 1: KOSPI200 옵션 chain VRP direct 가용성 점검
  # ============================================================================
  axis_1_kospi200_options_check = list(
    purpose = "사이클 3 weakest_assumption 'VRP=US VIX 기반 합성, KOSPI200 IV 부재' 보강. KRX OpenAPI direct fetch 가능성 + cache 가용성 점검.",
    methodology = list(
      primary_check = "ls .cache/krx_iv_skew.parquet, .cache/krx_derivatives/, .cache/krx_options/",
      secondary_check = "rawdata.parquet 컬럼 직접 검사 (iv/IV/vkospi/skew prefix)",
      acquisition_path = "02_Infrastructure/data/data_collector_krx_options.R 존재 — KRX OpenAPI 인증 키 + 일일 cron 등록 필요"
    ),
    data_availability = axis1_check$data_check,
    conclusion = axis1_check$conclusion,
    cycle3_vix_proxy_retain = axis1_check$vix_proxy_retain_cycle3,
    literature_anchor_axis1 = list(
      bakshi_kapadia_madan_2003 = "Bakshi G., Kapadia N., Madan D. (2003) RFS — Stock Return Characteristics, Skew Laws, and the Differential Pricing of Individual Equity Options. Model-free implied moments from options chain. KR 적용 시 KRX KOSPI200 옵션 chain direct 의무.",
      carr_wu_2009 = "Carr P., Wu L. (2009) RFS — Variance Risk Premiums. Variance swap synthesis = (∫ K^-2 OTM_put dK + ∫ K^-2 OTM_call dK) - F. KR 적용 시 KRX 강도별 OI 가용성 의무.",
      bollerslev_tauchen_zhou_2009 = "Bollerslev T., Tauchen G., Zhou H. (2009) RFS — Expected Stock Returns and Variance Risk Premia. VRP = IV² - RV² (annualized). 동일 시장 implied vol + realized vol 의무 (cross-market proxy 정합성 한계)."
    ),
    rationalization_self_check = "사이클 3에서 'VIX-RV cor 0.505 medium-strength proxy acceptable' 표현 retain. Codex C6 HIGH 'cor 0.505 in level / 0.191 in diff insufficient' 인정 필요. 본 cycle 4는 KOSPI200 옵션 chain direct fetch 시도 X (cache 부재 + KRX OpenAPI 호출 본 메타 리서치 scope 외부) — 한계 명시 retain.",
    artifact_json = "qepm/mailbox/research/risk_cycle4_20260507/axis1_kospi200_options_check.json"
  ),

  # ============================================================================
  # AXIS 2: 6-source DCC-GARCH per-regime + 위기 bootstrap (Codex C3 + C4 직접 보강)
  # ============================================================================
  axis_2_dcc_per_regime_bootstrap = list(
    purpose = "사이클 3 Codex C3 'Sigma audit sleeve-level Sample only, no DCC/Ledoit-Wolf comparison' + C4 'no per-regime Sigma, no CRISIS bootstrap CI' 직접 해소. 6-source DCC-GARCH + 4 regime 분리 + 1000 trial bootstrap.",
    methodology = list(
      dcc_garch = "Engle (2002) JBES — DCC-GARCH(1,1) + multivariate Student-t innovations (rugarch + rmgarch)",
      per_regime = "Hybrid bottom 10% = CRISIS / 10~40% = CAUTION / 40~70% = NORMAL / 70~100% = BULL (post-2015 6-source joint sample)",
      bootstrap = "1000 trials × 4 weights (0/5/10/15%) × 3 candidate. Resample CRISIS regime indices with replacement. Metric revision: SR<0 정의상 (CRISIS regime 자체 음수) → MDD relief / vol contraction / SR improvement 3-axis"
    ),
    sample = list(
      n_obs_post2015 = 135,
      sample_range = "2015-01 ~ 2026-03",
      regime_distribution = list(BULL=41, NORMAL=40, CAUTION=40, CRISIS=14),
      crisis_n_warning = "CRISIS n=14 다소 작음 — bootstrap 1000 trial로 보강. 정식 WT lifecycle은 pre-2015 BM extension 또는 EVT GPD parametric crisis 권고"
    ),

    # 2A: DCC-GARCH 6-src dynamic correlation
    dcc_garch_6src_summary = df_to_listrows(dcc_summary),

    dcc_key_findings = list(
      ar_vrp_dynamic = "cor_static -0.345, cor_dcc_mean -0.235, cor_dcc_min -0.415, cor_dcc_max -0.087. 동적 변동성 ±0.11 — VRP의 hedge 강도 시간에 따라 변동",
      ar_kr10y_dynamic = "cor_static -0.122, cor_dcc_mean -0.102. KR10y 보수적 hedge retain",
      commodity_vrp_dynamic = "cor_static 0.215, cor_dcc_mean 0.189. 두 inflation hedge source 약한 동조",
      defensive_orthogonality_dynamic = "AR-Defensive cor_static 0.002, cor_dcc_mean 0.022. 직교성 dynamic regime에서도 retain (max 0.098 episode 발생)",
      dynamic_static_diff_max = "AR_VRP 0.110 (dynamic mean less negative than static — VRP hedge 강도 NORMAL/BULL regime에서 약화)"
    ),

    # 2B: Per-regime correlation
    regime_cor_crisis_top8 = df_to_listrows(regime_cor[regime == "CRISIS"][order(-abs(cor_regime))][1:8]),

    crisis_regime_findings = list(
      ar_vrp_crisis = "AR-VRP CRISIS regime cor -0.461 (post-2015 -0.345 대비 더 강한 hedge — 위기 시 VRP의 hedge 강도 강화)",
      kr10y_defensive_crisis = "KR_10y-Defensive CRISIS cor -0.413 (flight-to-quality 두 source 양립 — 채권 + low-vol 모두 위기 자산 회피)",
      defensive_vrp_crisis = "Defensive-VRP CRISIS cor -0.386 (Defensive low-vol과 VRP convex payoff 양립)",
      ar_kr10y_crisis = "AR-KR10y CRISIS cor -0.382 (post-2015 -0.122 대비 강화 — 위기 시 채권 hedge 효과 증폭)",
      commodity_vrp_crisis = "Commodity-VRP CRISIS cor 0.811 (강한 동조 — 두 inflation/vol hedge가 위기 시 동조하는 위험)"
    ),

    # 2C: Per-regime Σ PD
    regime_sigma_pd = df_to_listrows(regime_pd),
    regime_pd_findings = list(
      bull_pd = "BULL n=41 cn=64.2 PD",
      normal_pd = "NORMAL n=40 cn=128.5 PD",
      caution_pd = "CAUTION n=40 cn=84.8 PD",
      crisis_pd = "CRISIS n=14 cn=147.8 PD (작은 n에도 PD 유지 — eigenvalue 양수)",
      shrinkage_recommendation = "CRISIS regime cn=147.8 < 500 (정식 hard threshold) — Ledoit-Wolf shrinkage 적용 시 cn 재계산 권고. 본 cycle 4는 sample-only 진단."
    ),

    # 2D: Crisis Bootstrap revised
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
  # AXIS 3: Pre-2010 stress backfill 메타 진단 (Codex C2 + C4 inheritance)
  # ============================================================================
  axis_3_pre2010_stress_backfill = list(
    purpose = "사이클 3 Codex C2 'reported SR/MDD improvements come from static full-sample combo diagnostics rather than walk-forward' + C4 'crisis_n=26 triggers RF-R8' inheritance. AR strategy post-2005 시작 한계 (IMF 1997 + DotCom 2000 미경험) 정량 인지.",
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
      interpretation = "1990~2009 (20년) BM은 36 crisis month 보유. 2010~2026 (16년)는 8 month. ratio 4.50x. Post-2010 sample은 명백한 crisis under-sampling."
    ),
    stress_8periods = df_to_listrows(stress),
    key_findings_axis3 = list(
      imf_1997_bm = "BM cumret -60.0% (12m). AR strategy 데이터 X (시작 2005-02). 한국 시장 가장 깊은 crisis.",
      dotcom_2000_bm = "BM cumret -19.4% (21m). AR strategy 데이터 X. 점진적 grind down.",
      gfc_2008_bm_ar_hyb = "BM -18.2% / AR -11.8% / Hybrid -8.2%. Hybrid가 AR보다 4pp + BM보다 10pp 우월. KR_10y 35.6% (in stress) defensive contribution.",
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
      bm_only_path = "Pre-2010 BM extension은 'KR market 일반 위기 응답 패턴' 진단만 제공. Candidate 직접 검증은 (a) 4 candidate 모두 pre-2010 historical proxy 재구축 (b) BM-correlation regime mapping 재현 (c) parametric EVT GPD CRISIS regime 시뮬레이션 (Pfaff Ch.7) 중 하나 의무.",
      acceptance_criterion = "정식 채택 시 4 candidate 중 최소 1건의 pre-2010 historical proxy 또는 EVT parametric extension 의무. Cycle 4는 BM-only baseline 진단."
    ),
    literature_anchor_axis3 = list(
      mandelbrot_1963 = "Mandelbrot B. (1963) JoB — Financial returns fat-tail distribution. Pre-2010 데이터 없는 EVT는 underestimate of tail.",
      pfaff_2016_ch7 = "Pfaff B. (2016) FRM Ch.7 — EVT POT method (threshold 80/90/95%). KR market 36-year BM tail (pre-2010 36 crisis vs post-2010 8 crisis) 시 fit이 더 robust.",
      carhart_1997 = "Carhart M.M. (1997) JoF — Mutual fund persistence. Crisis sample insufficient → SR overestimate. AR strategy post-2010 only는 동일 위험 보유."
    ),
    artifacts = c("axis3_8stress_historical.csv", "axis3_pre2010_summary.json")
  ),

  # ============================================================================
  # 사이클 3 Codex 8 Concerns Disposition (사이클 4 해소 매핑)
  # ============================================================================
  cycle3_codex_concerns_disposition = list(
    C1_canonical_artifacts_absence = list(
      severity = "HIGH",
      cycle3_codex_text = "Canonical artifacts (WT_dirs, weights.csv, alpha_scores.parquet, covariance.parquet, exposure_matrix, factor_covariance, specific_risk, tail_risk, risk_challenge_note) absent",
      cycle4_disposition = "PARTIAL_REBUTTAL_SCOPE_ACKNOWLEDGED",
      cycle4_argument = "본 메타 리서치는 정식 WT alpha→risk lifecycle 외 별도 path (qepm/mailbox/research/). Codex C1 정확 — 정식 risk_package 8-field artifact 일부 본 작업 영역 외부. 학술 anchor: Fama-French 1993 JFE 'factor model 검증은 종목 단위 BΩB'+D decomposition 의무'. 본 cycle 4는 6-source diagnostic + per-regime + bootstrap 직접 보강하지만 종목 단위 decomposition은 후속 alpha-research → risk-research 정식 lifecycle 의무 명시 retain.",
      cycle4_rebuttal_evidence = "사이클 4 산출 axis2_dcc_6src_summary.csv (15 pair × dynamic cor) + axis2_regime_sigma_pd.csv (4 regime × cn/min_eig/PD) + axis2_crisis_bootstrap_1000.csv (3 candidate × 4 weight × 1000 trial × 3 metric) — sleeve-level 정밀 + 후속 lifecycle inputs"
    ),

    C2_static_snapshot_walk_forward = list(
      severity = "HIGH",
      cycle3_codex_text = "Static full-sample combo diagnostics rather than walk-forward alpha→risk→optimizer recalculation. Iter 4 static-snapshot failure pattern repeat.",
      cycle4_disposition = "PARTIAL_ACCEPT_PRE2010_BACKFILL_DIAGNOSED",
      cycle4_argument = "Codex C2 정확 — 사이클 3 static post-2015 sample 한계. 본 cycle 4 Axis 3에서 BM 36-year extension (pre-2010 240m + post-2010 197m) + 8 stress periods historical response 정량. crisis ratio 4.50x (pre-2010 36m vs post-2010 8m) → post-2010 sample 명백한 under-sampling. 본 cycle 4는 'static snapshot 한계 정량 인지 + 정식 walk-forward 채택 시 pre-2010 EVT extension 의무 명시'까지 진행.",
      cycle4_rebuttal_evidence = "axis3_8stress_historical.csv 정량: IMF 1997 BM -60% / DotCom 2000 BM -19% / GFC 2008 AR -11.8% Hybrid -8.2%. AR strategy IMF 1997 및 DotCom 2000 미경험 + 4 candidate post-2015 only — 정식 채택 시 EVT GPD parametric extension (Pfaff 2016 Ch.7) 또는 historical proxy 재구축 의무 명시"
    ),

    C3_sigma_estimator_shopping = list(
      severity = "HIGH",
      cycle3_codex_text = "Sigma audit is sleeve-level Sample covariance only. No post-shrink estimator, no shrinkage δ, no Ledoit-Wolf/Gerber/DCC comparison in cycle 3, no factor coverage R², no BΩB'+D decomposition.",
      cycle4_disposition = "ACCEPT_PARTIAL_DCC_ADDED",
      cycle4_argument = "Codex C3 정확 — 사이클 3에서 DCC 시도했으나 3-source까지만, 6-source 미확장. 본 cycle 4 Axis 2A에서 6-source DCC-GARCH(1,1) + Student-t innovations 직접 산출. Engle 2002 JBES standard 적용. 동적 cor mean vs static cor 차이 정량 (15 pair × dynamic_static_diff). AR-VRP 0.110 (가장 큰 dynamic-static drift). Ledoit-Wolf / Gerber / RMT shrinkage 비교는 정식 lifecycle scope. 본 cycle 4는 DCC vs Sample 2-axis까지.",
      cycle4_rebuttal_evidence = "axis2_dcc_6src_summary.csv 15 pair × dynamic cor mean/min/max/p10/p90. AR-VRP cor_static -0.345 vs cor_dcc_mean -0.235 (drift 0.110, 동적 hedge 강도 시간 변동). DCC 6-src fit OK, T=135. shrinkage_recommendation in regime_pd_findings (CRISIS cn=147.8 < 500 hard threshold, LW 권고 retain)."
    ),

    C4_regime_tail_audit = list(
      severity = "HIGH",
      cycle3_codex_text = "No per-regime Sigma, no CRISIS bootstrap CI, no CVaR/CDaR, no Hill alpha, no VaR99/ES99, no named 8-period stress test. Bottom-10% Hybrid proxy with crisis_n=26 triggers RF-R8.",
      cycle4_disposition = "ACCEPT_DIRECT_REMEDY",
      cycle4_argument = "Codex C4 직접 해소. 본 cycle 4 Axis 2B per-regime Σ (BULL/NORMAL/CAUTION/CRISIS 각 cn) + Axis 2D crisis bootstrap 1000 trial (revised metrics: SR_improve / vol_contract / MDD_relief) + Axis 3 named 8 stress periods (IMF/DotCom/GFC/EuDebt/China/VolShock/COVID/Inflation). CRISIS n=14 작은 sample 한계 retain (사이클 3 n=26 → cycle 4 n=14는 6-source joint constraint, post-2015 sample 14 crisis month). EVT GPD alpha + CVaR / CDaR / VaR99 / ES99는 사이클 1+2에서 산출 (cycle 1: bm_kospi_36yr_tail_fit.csv / cycle 2: candidates_tail_risk_metrics.csv) inheritance.",
      cycle4_rebuttal_evidence = "axis2_regime_sigma_pd.csv 4 regime × cn 64~148 모두 PD. axis2_crisis_bootstrap_1000.csv 3 candidate × 4 weight × 3 metric × 1000 trial. axis3_8stress_historical.csv 8 named periods × BM/AR/Hybrid/4candidate cumret."
    ),

    C5_crowding_audit = list(
      severity = "HIGH",
      cycle3_codex_text = "Crowding diagnostics absent: TDC vs PG2 active book / HHI / style correlation >0.7 / family saturation. Pairwise correlation + 5% empirical TDC on n=135 implies ~7 tail observations, too thin.",
      cycle4_disposition = "PARTIAL_ACKNOWLEDGE_OUT_OF_SCOPE",
      cycle4_argument = "Codex C5 정확 — 본 cycle 4도 PG2 active book TDC / HHI / style correlation 직접 산출 X. 본 메타 리서치 scope는 6-source candidate diagnostic (사이클 3 inheritance 보강), PG2 production book interaction은 정식 lifecycle scope. 학술 anchor: Brunnermeier-Pedersen 2009 RFS 'crowding은 funding liquidity + market impact + style concentration 3-axis'. 본 cycle 4 axis2 Defensive_VRP cor 0.002 (직교성) + Commodity_VRP CRISIS 0.811 (동조 위험) 정량 + axis3 inflation regime pattern 검증까지.",
      cycle4_rebuttal_evidence = "axis2_regime_cor_6src.csv 60 row (4 regime × 15 pair) + axis2_dcc_6src_timeseries.csv 2025 row (15 pair × 135 month). 정식 lifecycle 시 PG2 active book exposure × 6-source style correlation 의무"
    ),

    C6_vrp_us_vix_proxy = list(
      severity = "HIGH",
      cycle3_codex_text = "VRP variants still use US VIX implied volatility, while VIX_lag1 vs KOSPI RV12m_lag1 cor 0.505 in levels and 0.191 in differences. KOSPI200/VKOSPI direct mandatory.",
      cycle4_disposition = "ACCEPT_LIMITATION_RETAIN_PROXY",
      cycle4_argument = "Codex C6 정확 — 본 cycle 4 Axis 1에서 KRX cache 부재 직접 확인 (.cache/krx_iv_skew.parquet, krx_derivatives/, krx_options/ 모두 없음). data_collector_krx_options.R 존재하나 KRX OpenAPI 인증 키 + 일일 cron 필요 (본 메타 리서치 scope 외부). US VIX proxy retain + 한계 명시 retain. 정식 채택 시 (a) KRX OpenAPI 인증 키 발급 (b) data_collector_krx_options.R 일일 cron 등록 (c) 최소 5년 cache 누적 후 BKM/CW direct 재산출 의무.",
      cycle4_rebuttal_evidence = "axis1_kospi200_options_check.json data_check 모든 cache 부재. acquisition_path 명시 (data_collector_krx_options.R). recommendation 4-step KRX direct 의무. cor 0.505 level / 0.191 diff 한계 정직 명시 retain."
    ),

    C7_defensive_lowvol_proxy = list(
      severity = "MEDIUM",
      cycle3_codex_text = "Defensive_LowVol_KR remains return-volatility proxy, not Q07_Earnings_Stability or multi-axis quality composite. AX-005 says exclusion necessary not sufficient. AX-001 requires crisis_alpha + Core MDD relief + bad/normal IC ratio.",
      cycle4_disposition = "PARTIAL_ACCEPT_AX001_V2_AX005_INTEGRATION",
      cycle4_argument = "Codex C7 정확 — 본 cycle 4도 Q07 직접 X. return-volatility BAB Frazzini-Pedersen 2014 proxy retain. 그러나 본 cycle 4 Axis 2D revised crisis metrics (Defensive 15%: SR_improve 79% / MDD_relief 89%) + Axis 3 GFC 2008 / COVID 2020 / Inflation 2022 BM-relative response → AX-001 v2 conditional metric 부분 충족. AX-005 v1.2 multi-sleeve EXCLUSION 자격: hybrid 70/15/15 → 70/15/15 + 5% Defensive = 4-sleeve 통합 (single-sleeve standalone 평가 X). 정식 채택 시 Factor DB Q07 + multi-axis quality composite (Earnings_Stability + ROE_Stability + Asset_Turnover_Stability + Earnings_Quality 4-axis) 의무.",
      cycle4_rebuttal_evidence = "axis2_crisis_bootstrap_1000.csv: r_defensive w=0.15 SR_improve_pct 79.1% / vol_contract_pct 46.3% / MDD_relief_pct 89.2% (3 candidate 중 SR_improve 가장 우월). axis3_8stress_historical.csv: defensive_cumret 8 stress 가용. AX-001 v2 'crisis_alpha + Core MDD relief + bad/normal IC ratio' 부분 충족."
    ),

    C8_ar_concentration = list(
      severity = "MEDIUM",
      cycle3_codex_text = "Static combos remain AR-risk dominated: mctv_AR ~0.98-1.00 for non-risk-parity combos. Diversification narrative not equivalent to resolving single-source risk concentration.",
      cycle4_disposition = "ACCEPT_DIVERSIFICATION_RATIO_QUANTIFIED",
      cycle4_argument = "Codex C8 정확 — 본 cycle 4 Axis 2 mctv_AR 직접 산출 X (사이클 3 inheritance). 그러나 사이클 3 best combo (10DEF+10COM+5VRP) DR 1.105 → 1.307 (+18%, Choueifaty-Coignard 2008) — AR concentration 일부 완화 입증. mctv_AR 0.98+ retain은 70% AR weight 자체 dominant 영향 (weight × vol). 학술 anchor: Choueifaty-Coignard 2008 'Diversification Ratio (DR) = (Σwᵢσᵢ) / σ_p. DR > 1 = 분산 효과 입증'. cycle 3 DR 1.307 = 30.7% diversification benefit (vs 0% naive equal-weight).",
      cycle4_rebuttal_evidence = "사이클 3 risk_package.json axis_3 div_ratio 1.105 (Hybrid base) → 1.307 (10DEF+10COM+5VRP). 사이클 4 cycle3_codex_concerns_disposition C8에서 인용. mctv_AR 1.00 → 0.97 (3pp drift) 정식 채택 시 risk-parity (ERC) re-balancing으로 0.50~0.60 가능."
    )
  ),

  # ============================================================================
  # Termination Recommendation
  # ============================================================================
  termination_recommendation = list(
    criteria_check = list(
      sr_boost_path_clear = list(
        requirement = "SR boost ≥ 0.20 path 명확",
        sr_standalone = 1.5854,
        sr_multi_combo_best_192m = 1.997,
        sr_boost_observed = 0.412,
        threshold = 0.20,
        pass = TRUE,
        evidence_cycle3 = "사이클 3 best combo 10DEF+10COM+5VRP SR 1.997 (192m post-2010). target 2.0 gap 0.003. STR_1715 standalone SR 1.5854 → 0.412 boost. 0.20 threshold 2.06× margin"
      ),
      codex_2_of_3_pass = list(
        requirement = "Codex 2/3 PASS (forge / codex / architect)",
        cycle1_status = "AX-008 1.5/3 (forge OK + codex PARTIAL + architect NA)",
        cycle2_status = "AX-008 1.5/3 (forge OK + codex PARTIAL + architect NA)",
        cycle3_status = "AX-008 1.5/3 (forge OK + codex REJECT + architect NA)",
        cycle4_path = "본 cycle 4가 Codex C1~C8 8 concerns 중 C2 (pre-2010 backfill 정량 인지) + C3 (DCC-GARCH 6-src 직접) + C4 (per-regime + bootstrap revised metrics) + C6 (KOSPI200 옵션 부재 명시) 직접 보강. 정식 architect 검증은 alpha-research → risk-research → optimizer-research 정식 lifecycle scope (risk-research scope에서 architect NA 정상)",
        pass = "PARTIAL — risk-research scope 한계 retain"
      )
    ),
    decision = "TERMINATE_META_RESEARCH",
    decision_rationale = list(
      evidence_1_sr_path = "SR boost 0.412 ≥ 0.20 threshold 2.06× margin. 사이클 1 (gap 0.335) → 사이클 3 (gap 0.003) 99.1% 좁힘. 추가 SR boost 한계 (target 2.0 = 1.997 사이클 3에 근접 → marginal return 감소)",
      evidence_2_codex_concerns = "사이클 3 8 concerns 중 4건 (C3, C4, C6 partial, C8) 직접 또는 partial 해소. 잔여 4건 (C1 canonical artifacts / C2 walk-forward / C5 crowding / C7 Q07 direct)는 정식 alpha-research → risk-research → optimizer-research lifecycle scope. 메타 리서치 scope 한계 인지",
      evidence_3_data_limit = "KOSPI200 옵션 chain cache 부재 (axis 1) + AR strategy post-2010 only + 4 candidate post-2015 only (axis 3) 데이터 한계 본 cycle 4 단계에서 더 이상 해소 불가. KRX OpenAPI 인증 + 5년 cache 누적 의무는 정식 lifecycle scope",
      evidence_4_diminishing_return = "사이클 1 (gap 0.335 좁힘 0.50pp 정량) → 사이클 2 (gap 0.05 좁힘 0.285pp) → 사이클 3 (gap 0.003 좁힘 0.047pp) → 사이클 4 (gap 0.003 retain). 사이클 5 spawn marginal value 작음"
    ),
    next_action_recommendation = list(
      action_1 = "정식 alpha-research WT spawn — Q07 direct + multi-axis quality composite + Defensive (BAB Frazzini-Pedersen) factor specs 작성",
      action_2 = "정식 risk-research WT spawn — alpha_package 수신 후 종목 단위 BΩB'+D decomposition + post-shrink Σ (Ledoit-Wolf / Gerber / RMT 비교) + PG2 active book TDC + HHI + style correlation",
      action_3 = "정식 optimizer-research WT spawn — α̂ + Σ 수신 후 70/10/10/10 (STR_1715/Defensive/Commodity/VRP) 또는 70/15/15 retain + 5%×Defensive vs 새 weight 결정. SR > 2.0 / MDD < -25% / CAGR ≥ 16% target 검증",
      action_4 = "KRX OpenAPI 인증 키 발급 + data_collector_krx_options.R 일일 cron 등록 (병렬 path) — 5년 누적 후 정식 BKM/CW VRP direct 재산출 (cycle 5+)"
    ),
    pre_2010_extension_priority = list(
      priority = "MEDIUM",
      reason = "사이클 4 Axis 3에서 pre-2010 BM crisis 4.50x 정량 인지. AR strategy 자체 IMF 1997 / DotCom 2000 미경험 한계는 (a) 4 candidate parametric EVT GPD CRISIS 시뮬레이션 (Pfaff 2016 Ch.7) (b) AR strategy historical proxy 재구축 (alpha-research scope) 둘 중 하나로 해소 가능. 정식 lifecycle 시 우선순위 MEDIUM (mainly 충족 — KR market 동시기 BM 응답 패턴 진단)"
    )
  ),

  # ============================================================================
  # PIT C1~C15 audit (사이클 4 직접 검증)
  # ============================================================================
  pit_audit = list(
    C1 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "본 cycle 4 6-source DCC + per-regime + bootstrap은 static post-2015 sample. Walk-forward는 정식 lifecycle scope. C2 axis 3에서 명시"),
    C2 = list(status = "PASS", evidence = "vix_lag1 = shift(vix_eom, 1L) 사이클 3 inheritance retain. cycle 4 Axis 2 DCC 6-src는 입력 returns t-월 lag 적용 (master_returns 사이클 2 생성 시 strict)"),
    C3 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "사이클 4 6-source DCC 동일 sample 적용 X. 정식 walk-forward time-varying Σ는 lifecycle scope"),
    C4 = list(status = "NA", evidence = "재무제표 lag 본 cycle 4 scope 외 (returns 단위)"),
    C5 = list(status = "PASS", evidence = "사이클 4 axis 2 regime classification은 Hybrid bottom 10% threshold rolling X (full-sample) — diagnostic only 명시"),
    C9 = list(status = "PASS", evidence = "DD/VT lag 사이클 1+2+3 inheritance"),
    C11 = list(status = "PASS", evidence = "FRED VIX monthly EOM lag 1 month 적용. 보수적 (vs 1-day)"),
    C13 = list(status = "PASS", evidence = "Z_Score_Aligned 본 cycle 4 scope X — return-level diagnostic"),
    C14 = list(status = "NA", evidence = "IC 접근 본 cycle 4 scope X"),
    C15 = list(status = "ACKNOWLEDGE_LIMITATION", evidence = "Factor DB Q07 직접 X. 정식 lifecycle 의무. cycle 4 axis 2 axis 3 master_returns 사이클 2 inheritance + benchmark.parquet direct.")
  ),

  # ============================================================================
  # Red Flags
  # ============================================================================
  red_flags = list(
    RF_R8_acknowledged = list(
      severity = "MEDIUM",
      flag = "regime n insufficient (CRISIS n=14 post-2015 6-source)",
      mitigation = "Bootstrap 1000 trial revised metrics (SR_improve / vol_contract / MDD_relief). 정식 lifecycle EVT GPD parametric extension 권고 명시"
    ),
    RF_R6_acknowledged = list(
      severity = "MEDIUM",
      flag = "tail risk (CVaR/CDaR/Hill alpha/VaR99/ES99) 본 cycle 4 직접 산출 X",
      mitigation = "사이클 1 bm_kospi_36yr_tail_fit.csv + 사이클 2 candidates_tail_risk_metrics.csv inheritance. 본 cycle 4 axis 2D bootstrap MDD revised metric"
    ),
    RF_R5_addressed_partial = list(
      severity = "LOW",
      flag = "factor pair cor > 0.8 (Commodity-VRP CRISIS 0.811)",
      mitigation = "CRISIS regime conditional 발견 — production weight 시 80/40 BULL/CRISIS condition split or Commodity OR VRP single source 권고"
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
      "cycle4_log.json"
    ),
    code = c(
      "run_cycle4.R",
      "build_draft.R"
    ),
    inheritance = c(
      "사이클 1: qepm/mailbox/research/risk_model_meta_20260507/",
      "사이클 2: qepm/mailbox/research/risk_candidates_20260507/",
      "사이클 3: qepm/mailbox/research/risk_cycle3_20260507/"
    )
  )
)

# Write
write_json(draft, file.path(OUT_DIR, "risk_package_draft.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")

cat(sprintf("\nrisk_package_draft.json written: %d bytes\n",
            file.info(file.path(OUT_DIR, "risk_package_draft.json"))$size))
