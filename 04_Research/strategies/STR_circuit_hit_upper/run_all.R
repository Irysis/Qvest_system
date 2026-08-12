source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")
run_alpha_search(
  strategy_name      = "STR_AS_CIRCUIT_UPPER_21D",
  strategy_idea      = "가격제한(서킷브레이커) 시장에서 상한가 마감 후 잠재 초과수익 이월 효과: 최근 21거래일 상한가 근접 경험 비율이 높을수록 다음 달 양수 수익 예측 (Das 2026 arXiv:2608.08625)",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/strategies/STR_circuit_hit_upper/factor_engine.R",
  n_holdings    = 25L,
  weight_method = "equal",
  commission    = 0.0015,
  start_date    = "2005-01-01",
  universe      = "K200_KQ150",
  factor_analysis = TRUE
)
