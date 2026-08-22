PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

lcode_dir <- file.path(PROJECT_ROOT, "stage_artifacts/l_code/alpha_search")
dir.create(lcode_dir, recursive = TRUE, showWarnings = FALSE)

run_id <- "20260821_074219_6672"
ts     <- format(Sys.time(), "%Y%m%d_%H%M%S")
fname  <- file.path(lcode_dir, paste0("l_code_ARFIMA_TSMOM_AS_", ts, ".json"))

lcode <- list(
  l_code_id    = paste0("L-AS-ARFIMA_TSMOM-", ts),
  strategy_id  = paste0("STR_AS_", run_id),
  research_mode = "alpha_search",
  created_at   = Sys.time(),
  tags         = c("VALIDATED_HARD_FAIL", "momentum", "variance_ratio", "trend_following",
                   "KR_longonly", "MDD_structural_fail"),
  verdict      = "FAIL",
  grade        = "F",
  score        = 37.6,

  # 핵심 실측치 (backtested, metric_type=backtested)
  key_metrics = list(
    CAGR           = 15.52,
    AnnVol         = 28.14,
    Sharpe         = 0.551,
    MDD            = 64.26,
    Calmar         = 0.242,
    IR             = 0.239,
    PORT_t_NW_lag3 = 1.21,
    PORT_t_pvalue  = 0.227,
    OOS_retention  = 0.57,
    IC             = -0.0033,
    ICIR           = -0.034,
    Turnover_Ann   = 229.9,
    BM_Corr        = 0.747,
    Alpha_Ann_pct  = 6.54
  ),

  # 실패 기전 (정직 분석)
  failure_mechanism = paste(
    "VR(3) 조건부 필터(VR>1)가 KR long-only 환경에서 모멘텀의 크래시 리스크를",
    "제거하지 못함. IC = -0.003 으로 VR 필터 후 신호 예측력이 사실상 0.",
    "PORT_t 1.21 < 2.95 (초과수익 통계 유의성 없음).",
    "55%+ 낙폭 에피소드 6회로 structural drawdown hard fail.",
    "OOS 유지율 0.57 < 0.70 — in-sample 성과가 out-of-sample로 전이되지 않음."
  ),

  # 논문 복제 충실도 메모
  paper_note = paste(
    "arXiv 2607.19497 핵심 이론(VR>1 = 추세 구간 = MOM 신호 유효)을 KR에 적용.",
    "원 논문은 선물/FX 시계열 추세추종 대상이나 본 검증은 개별주식 횡단면 적용.",
    "논문 원 context(시계열 추세추종)와 적용 context(횡단면 모멘텀)의 불일치가",
    "음성 결과의 구조적 원인일 가능성이 높음."
  ),

  # 소비 가능 표면 7종 체크리스트
  consumption_surface = list(
    factor_ranking      = "부적합 (IC -0.003, 순위력 없음)",
    universe_filter     = "조건부 가능: VR>1.3 이상 강필터 + 분위 상위 선별 시 재검토",
    overlay_regime      = "유망: VR 신호를 추세/평균회귀 국면 구분 오버레이로 이식 가능",
    risk_beta_budget    = "부적합 (beta 0.90, 위험 차별화 없음)",
    monitoring_signal   = "미검토",
    selection_label     = "부적합",
    cross_mode_porting  = "factor-rotation RCMA에서 위기 국면 조건부 소비 검토 가능"
  ),

  # 부활 조건 (INV-7)
  revival_conditions = c(
    "VR 임계값 >1.3~1.5 강필터 적용 후 IC가 양전환할 때",
    "원 논문 프로토콜(시계열 추세추종, 선물 유니버스)로 구현 전환 시",
    "VR 신호를 오버레이 레이어(현금 비중 조절)로 소비 구조 전환 시"
  ),

  # 다음 가설 (next_probe >= 2 — answer-principles §6 의무)
  next_probe = list(
    probe_1 = list(
      idea   = "VR 임계값 강화 실험: VR>1.3, VR>1.5 구간별 IC와 PORT_t 측정",
      rationale = "VR>1 기준이 너무 낮아 신호 오염이 많을 가능성. 강필터로 신호 순도 확인",
      priority  = "HIGH"
    ),
    probe_2 = list(
      idea   = "VR 신호 vs 순수 12-1 MOM A/B 비교 — VR 조건이 실제로 무언가를 추가하는지 확인",
      rationale = "VR 조건 없는 순수 12-1 MOM 대조군 대비 VR 조건부의 성과 차이를 분리",
      priority  = "MEDIUM"
    ),
    probe_3 = list(
      idea   = "VR 신호를 factor-rotation 오버레이 입력(국면 레이블)으로 소비",
      rationale = "standalone 불가이나 추세/평균회귀 국면 구분 신호로서의 소비 가능성 검토",
      priority  = "LOW"
    )
  ),

  out_dir   = file.path(PROJECT_ROOT, "stage_artifacts/alpha_search", run_id),
  chart_paths = list(
    equity_curve  = file.path(PROJECT_ROOT, "stage_artifacts/alpha_search", run_id, "equity_curve.png"),
    annual_returns = file.path(PROJECT_ROOT, "stage_artifacts/alpha_search", run_id, "annual_returns.png")
  )
)

jsonlite::write_json(lcode, fname, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[L-code] 적립 완료: %s\n", fname))
