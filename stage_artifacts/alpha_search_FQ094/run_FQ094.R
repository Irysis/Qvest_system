## FQ-094 실행 스크립트
## Direction B: 저 월간수익 자기상관 long (평균회귀 종목 long)
## 근거: T_RetAutoCorr_12M Direction A PORT_t=-0.295(QUARANTINE) → 역방향 FQ-094
source("../../02_Infrastructure/alpha_search/run_alpha_search.R")

run_alpha_search(
  strategy_name      = "FQ094_RetAutoCorr_B",
  strategy_idea      = "12개월 월간수익 lag-1 자기상관 역방향(저 autocorr long) — 평균회귀 구간 종목 매수. Direction A(고 autocorr long) PORT_t=-0.295 역효과 확인 후 KR 구조 검증. FMB t=2.50* 신호력 존재, 방향 재검.",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search_FQ094/factor_engine_RetAutoCorr_B.R",
  n_holdings         = 25,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE
)
