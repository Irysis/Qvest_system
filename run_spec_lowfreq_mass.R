source("02_Infrastructure/alpha_search/run_alpha_search.R")
run_alpha_search(
  strategy_name      = "SPEC_LOWFREQ_MASS_v1",
  strategy_idea      = "수익률 FFT 파워 스펙트럼 저주파수 에너지 비율(f<=1/60)이 높은 종목 매수 — 장기 트렌드 지속성 강한 구조 (Sepp-Lucic 2026, arxiv:2607.19497)",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_spec_lowfreq_mass.R",
  n_holdings         = 20L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)
