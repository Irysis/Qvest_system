source("02_Infrastructure/alpha_search/run_alpha_search.R")
run_alpha_search(
  strategy_name      = "RESID_INFO_VOL",
  strategy_idea      = "변동성 대비 초과 거래량(OLS 잔차)이 높은 종목 = 정보가 있는 투자자 진입 신호 -> 미래 수익률 양의 예측력 (Bucci et al. 2026 SMAR 모델 KR 적용)",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_resid_info_vol.R",
  n_holdings    = 25L,
  weight_method = "equal",
  commission    = 0.0015,
  start_date    = "2005-01-01",
  universe      = "K200_KQ150",
  factor_analysis = TRUE
)
