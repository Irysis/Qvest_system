setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
run_alpha_search(
  strategy_name      = "within_sector_reversal_20260809",
  strategy_idea      = "섹터-중립 단기역전: 섹터 공통 드리프트 제거 후 종목-specific 역전 포착. arXiv:2608.05755 LSTM attribution 핵심 신호.",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_within_sector_reversal.R",
  n_holdings         = 25,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)
