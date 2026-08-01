source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")

result <- run_alpha_search(
  strategy_name      = "T_RetAutoCorr_12M",
  strategy_idea      = "월간 수익률 lag-1 자기상관(12m 롤링) 횡단면 신호 — 추세 지속 종목 매수. arxiv:2607.19497 Sepp&Lucic 2026, 저주파 스펙트럼 질량 = 양의 자기상관 우위를 KR long-only 종목 단면으로 이식.",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/strategies/AS_T_RetAutoCorr_20260802/factor_engine.R",
  n_holdings         = 20L,
  weight_method      = "equal",
  universe           = "K200_KQ150",
  start_date         = "2005-01-01",
  commission         = 0.0015,
  factor_analysis    = TRUE
)

cat("\n[AutoRun] strategy_id =", result$strategy_id, "\n")
cat("[AutoRun] grade       =", result$grade, "\n")
cat("[AutoRun] score       =", result$score, "\n")
cat("[AutoRun] pass        =", result$pass, "\n")
