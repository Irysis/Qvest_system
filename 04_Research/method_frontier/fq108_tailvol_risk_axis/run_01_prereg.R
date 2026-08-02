# =============================================================================
# FQ-108 run_01: 사전등록(preregistration) — 측정 전 불변 기록
#   주제: 단기 꼬리-변동성(MAX5 계열 재료)의 **위험-축** 소비 판정.
#   질문: 현행 Σ/위험 추정(diag)에 단기 꼬리-변동성 항을 넣으면 익월 실현분산
#         예측이 개선되는가. (성과 SR/PORT_t 채점 아님 — 예측정확도 라운드)
#   lane: method_frontier (WT 경로 아님, alpha 산출물 없음/있어서도 안 됨)
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
LANE <- file.path(ROOT, "04_Research/method_frontier/fq108_tailvol_risk_axis")
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
dir.create(LANE, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
PRE_PATH <- file.path(LANE, "preregistration.json")

if (file.exists(PRE_PATH)) {
  cat("[prereg] 이미 존재 — 불변성 유지, overwrite 거부:", PRE_PATH, "\n")
  quit(save = "no", status = 0)
}

prereg <- list(
  id = "FQ-108",
  title = "단기 꼬리-변동성의 위험-축 소비 판정 (risk forecast accuracy A/B)",
  lane = "method_frontier",
  round_type = "independent_research_round_not_WT",
  agent = "risk-research",
  registered_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  parent_evidence = list(
    ranking_face = "WT-D20260802_010: MAX5 cap-w PORT_t -1.616 / EW-uni -2.274 (수익 전이 사망), 단 rank-IC +0.0474 t +4.41",
    filter_face  = "WT-D20260802_022: production rank-tilt 필터 ΔIR -0.1489 paired t -1.976 (승자 컷 기전)",
    risk_face    = "WT-D20260802_020: crash 발생률 lift +11.2pp (NW t 17.66) / boom +5.4pp (t 9.44) / CRISIS crash +10.1pp (t 3.89); 동일 63일창 vol과 cor 0.939",
    gap          = "발생률은 매우 잘 맞히는데 위험-축(분산 예측)에서 측정된 적이 한 번도 없다. D35_RealVol_63d 는 factor_registry 등재돼 있으나 factor_db 내부 4곳 외 소비자 0."
  ),
  pin_tag = "fq057_20260718_171024",
  pin_note = paste0(
    "FQ-057 P1/P1c vintage 상속 — 월간수익/스냅샷/유동성/일간수익 패널을 재빌드 없이 재사용. ",
    "Σ·bench·realized 머신러리가 P1/P1c와 bit-동일해야 arm 간 paired 무결 + 선행 라운드와 직접 비교 가능. ",
    "신규 입력은 factor_db(D35/D45/D05, load_month_factors 경유)와 rawdata-파생 63일 실현분산뿐."),
  metric_type = "risk_forecast_accuracy_diagnostic",
  selection_objective = "estimation_quality (QLIKE 예측손실 — R4 P3 준수; SR/IR/PORT_t/alpha 미사용)",
  capital_claim = FALSE, graduation_claim = FALSE, weight_proposal = FALSE,
  alpha_modification = FALSE,

  hypothesis = paste0(
    "H1(primary): 현행 Σ 대각(diag)을 단기 꼬리-변동성 항으로 보강하면 익월 실현분산 예측 QLIKE 손실이 ",
    "유의하게 감소한다. H0: 감소하지 않는다(증분 없음). ",
    "H2(secondary-흡수): 개선이 있다면 그것이 lw_nls(FQ-057 P1 ADOPT) 위의 '증분'인가, ",
    "아니면 lw_nls의 비선형 고유값 수축이 이미 흡수했는가. ",
    "H3(secondary-전이): 발생률(crash occurrence) 예측력이 2차 모멘트(분산) 예측력으로 전이되는가."),

  honest_posterior_at_registration = paste0(
    "★정직 posterior 명기: lw_nls가 이미 흡수했을 가능성이 실질적이다. FQ-057 P1 실측에서 lw_nls는 ",
    "총분산 채널 DM-t -5.9/-6.4로 linear LW를 크게 개선했고(P1c 실 book 재확인 -4.0), 그 개선의 상당부분이 ",
    "'대각(개별 분산)을 μI로 뭉개지 않는 것'에서 온다. D35의 정보가 대각 재보정과 중복이면 증분은 0에 가깝다. ",
    "그 경우 'D35는 신규 정보가 아니라 기존 추정기가 이미 포착' 이 정직한 결론이며 그것도 유효한 산출이다. ",
    "또한 load_month_factors 경유 Z_Score_Aligned는 횡단면 z(레벨 아님)이므로 ",
    "factor-DB 경로가 시험하는 것은 '횡단면 채널'뿐임을 사전에 인정한다 — 레벨 채널은 rawdata-파생 arm(F_sv63)으로 분리 측정한다."),

  design = list(
    base_sigma_estimators = list(
      lw_nls = "hrp_core .get_cor_cov('lw_nls') — FQ-057 NP3 등재 analytical NLS. PRIMARY(현행 대형-유니버스 권고본)",
      lw_linear = "hrp_core .get_cor_cov('ledoit_wolf') — incumbent, p>n에서 rho→1 로 Σ≈μI 퇴화. SECONDARY(흡수 분리용 대조)"),
    diagonal_treatments = list(
      A_base   = "현행 baseline — Σ 그대로. 예측분산 = w'Σw.",
      A2_recal = "교란통제 — 대각을 확장창 횡단면 회귀 log(RV_{i,t+1}) ~ 1 + log(diag Σ_i) 로 재보정만. '재보정 단독' 기여 격리.",
      B_d35    = "A2 + D35_RealVol_63d 정렬z (부호반전 → 높을수록 고변동). PRIMARY 처치.",
      C_d45    = "A2 + D45_Downside_Dev 정렬z (부호반전 → 높을수록 하방편차 큼). 꼬리 방향성.",
      D_max    = "A2 + D05_MaxRet 정렬z (부호반전 → 높을수록 복권형). MAX5 재료와 가장 가까운 등재 팩터.",
      F_sv63   = "A2 + log(63거래일 실현분산) [rawdata-파생, 레벨 보존]. 횡단면+레벨 양채널.",
      G_full   = "A2 + log(rv63) + D35 정렬z. 두 항 동시.",
      X_oracle = "★위반 주입 arm — 회귀에 홀딩월(t+1) 실현 log-RV 를 회귀변수로 주입(미래참조). 가드 발화 실증용, 판정 대상 아님."),
    sigma_rebuild = "Σ_new = D^(1/2) C D^(1/2); C = corr(Σ_base) 불변, D = diag(예측분산). 상관구조는 건드리지 않음 = 처치가 대각에 국한됨을 보장.",
    prediction_var = "v̂_i = exp(ŷ_i + s²/2) (로그정규 Jensen 보정, s² = 훈련잔차분산).",
    expanding_window = "월 t 회귀 훈련집합 = 홀딩월 ≤ t 인 (종목,월) 쌍 전부. 최소 24개월 누적 후에만 처치 arm 예측 발행 (PIT: 미래 쌍 절대 미사용).",
    cross_section_standardization = "회귀변수는 월별 횡단면 z (log diag는 raw log 유지 + z 병용은 하지 않음 — 단일 사양 고정)."
  ),

  portfolios = list(
    real_book_overlaid = list(
      role = "PRIMARY — 현 book active vector",
      def = "score_eff top-20 LinearTilt(λ=1.5, UB0.20) × invested(m4×β_R05), cash=1-invested. P1c와 동일 재구성.",
      production_parity_verified = TRUE,
      parity_basis = paste0("score_eff = alpha_scores_str1715_268m_cleanT1.parquet (meta label production_parity_verified; ",
        "production _recompute_alpha_asof.R 직접실행 대비 spearman 0.975~0.997, 4 sample months). ",
        "가중은 production forward_weights_R05_noLayer4.R 의 .tilt/.norm verbatim port(결정론적). ",
        "invested = period_returns_layer5_faith.csv (production materialized m4·β_R05). §7b 준수, 05_Production 무수정.")),
    ew_top25 = list(
      role = "CONTROL 대조",
      def = "elig 중 mom_12_1 z 상위 25종 동일가중 (P1 대조 정합, Σ-무관 비중).")
  ),
  weights_sigma_independent = TRUE,
  weights_sigma_independent_note = "두 포트 비중 모두 Σ·처치와 무관하게 결정 → 전 arm 완전 동일 비중, paired 검정 무결.",

  targets = list(
    total = "포트 총수익 분산 (w' Σ w)",
    te    = "active(포트-벤치) 분산 (a' Σ a)"),
  primary_cell = "portfolio=real_book_overlaid × target=total (FQ-057 P1c 확정: Σ 품질의 권위 채널은 총분산; TE 채널은 FORM-proxy 아티팩트였음)",

  realized_target = "익월(홀딩월 t+1) 실현 월간분산 = Σ_d r_d^2 (일간 제곱합). 포트/active 는 Return.portfolio 로 구성 후 계산.",

  loss_and_tests = list(
    primary_loss = "QLIKE = RV/h - ln(RV/h) - 1 (Patton 2011; 잡음 있는 변동성 proxy에 robust)",
    secondary_loss = "RMSE(vol) + Mincer-Zarnowitz b (calibration)",
    paired_test = "Diebold-Mariano, Newey-West HAC lag=3, 월별 QLIKE 차이. 음수 t = 좌항(처치) 우월."),

  decision_rules = list(
    wire_recommend = "DM t(B_d35 − A_base) <= -2.0 ∧ mean_qlike_diff < 0 → 배선 권고(risk_package 소비 지점 명시)",
    no_increment   = "|DM t| < 2.0 → 증분 없음 (D35는 신규 정보 아님 또는 검정력 부족 — 정직 서술)",
    degradation    = "DM t >= +2.0 → 열화 (배선 금지)",
    absorption_split = paste0("흡수 분리: Δ_nls = QLIKE(B_d35|lw_nls) − QLIKE(A_base|lw_nls), ",
      "Δ_lin = QLIKE(B_d35|lw_linear) − QLIKE(A_base|lw_linear). ",
      "Δ_lin << Δ_nls < 0 근방(즉 lw_linear에서만 큰 개선) → 'lw_nls가 이미 흡수' 판정. ",
      "양쪽 모두 유의 개선 → '독립 증분'."),
    confound_control = "B_d35 vs A2_recal 도 반드시 보고 — A_base 대비 개선이 '재보정 단독'인지 'D35 항'인지 분리. 배선 권고는 B vs A2_recal 도 t<=-2.0 일 때만 STRONG, 아니면 CONDITIONAL(재보정 자체가 레버).",
    transfer_test = "H3: 동일 종목-월 패널에서 (i) D35 상위분위의 crash 발생률 lift, (ii) log-RV 회귀에서 D35 계수의 FM-NW t + 증분 R². (i) 유의 ∧ (ii) 비유의 → '발생률→분산 전이 없음'.",
    small_n = "DM |t|<2 는 무판정(방향만). 단일 book 하위창은 검정력 제한."
  ),

  violation_injection = list(
    method = "X_oracle arm — 확장창 회귀에 홀딩월 t+1 의 실현 log-RV 를 회귀변수로 주입(미래참조).",
    expectation = "DM t(X_oracle − A_base) 가 크게 음수(하네스가 정확도 개선을 실제로 검출) — 발화하지 않으면 측정계 사망.",
    guard2 = "PIT 가드: load_month_factors 반환 attr('factor_db_asof_date') 가 리밸 월 t 이내 ∧ 월말 이하임을 월별 assert. 위반 시 hard stop (fail-closed).",
    guard3 = "훈련집합 필터 assert: max(훈련 홀딩월) <= t 를 월별 assert."
  ),

  selection_type = "chain",
  no_flip = TRUE,
  no_flip_note = "A/B/C 및 판정 문턱은 본 사전등록으로 고정. 측정 후 문턱·primary cell·arm 정의 변경 금지.",
  method_shopping_log = list(
    scope = "공분산 추정기(R2-C 상한 5) — 본 라운드는 2건(lw_nls, lw_linear), 둘 다 이미 .get_cor_cov 등재본. 신규 추정기 발굴 아님.",
    treatments_are_not_shopping = "대각 처치 7종(+주입 1종)은 사전등록된 A/B 설계축이지 estimator shopping 아님 — 최적 arm 선택으로 자본 주장 하지 않음."),

  role_boundary = paste0("Σ + 위험 예측 정확도 진단만. 포트는 진단 instrument. ",
    "alpha 시그널 추가/alpha_vector 수정/포트 비중 제안/종목 우열 판단 절대 금지. ",
    "본 라운드는 risk_package 를 발행하지 않으며 qepm/mailbox/worktask/ 에 쓰지 않는다."),
  hard_constraints = "종목 20(book)/25(EW 대조) · long-only · weight [0,0.20] · LIQ 2e8 · PIT C1~C15 · C15(팩터는 load_month_factors 경유, parquet 직접 load 금지)",
  R_discipline = ".R 파일 경유(-e 개행 금지) · setDTthreads(1) · Return.portfolio only · 05_Production/01_Literature read-only · r-portability 준수"
)

write_json(prereg, PRE_PATH, auto_unbox = TRUE, pretty = TRUE)
cat("[prereg] 사전등록 기록 완료 (불변):", PRE_PATH, "\n")
