source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")
run_alpha_search(
  strategy_name      = "T_RetAutoCorr_12M",
  strategy_idea      = "monthly return lag-1 autocorr cross-section: arxiv:2607.19497 Sepp-Lucic 2026 E[TF_return] ∝ autocorr rho+drift^2, stocks with positive 12m lag-1 monthly return autocorr have trend-following alpha",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/strategies/AS_T_RetAutoCorr_12M_20260802/factor_engine.R",
  n_holdings    = 20L,
  weight_method = "ivol",
  commission    = 0.0015,
  start_date    = "2005-01-01",
  universe      = "K200_KQ150",
  factor_analysis = TRUE
)
