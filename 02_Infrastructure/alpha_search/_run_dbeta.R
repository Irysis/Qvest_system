# _run_dbeta.R — alpha-search 호출 래퍼 (Ang-Chen-Xing 2006 Downside Beta)
source("G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name      = "DownsideBeta_ACX2006",
  strategy_idea      = "하방위험 베타(Ang-Chen-Xing 2006): 하락장(rm<0) β⁻ 상위 decile long-only EW. 가격 only, 꼬리위험·방어 축. NLP·대체데이터 무사용.",
  factor_engine_path = "G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_dbeta.R",
  weight_method      = "equal",
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)
cat("\n[_run_dbeta] grade=", res$grade, " score=", res$score,
    " excess_cagr=", res$excess_cagr, " l_code=", res$l_code, "\n")
