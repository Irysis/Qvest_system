# _run_seasonality.R — alpha-search 호출 래퍼 (Heston-Sadka 2008 Return Seasonality)
source("G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name      = "Seasonality_HS2008",
  strategy_idea      = "계절성(Heston-Sadka 2008): 종목별 과거 same-calendar-month 평균수익 상위 decile long-only EW. 가격 only, momentum/value와 직교(달력 패턴). NLP·대체데이터 무사용.",
  factor_engine_path = "G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_seasonality.R",
  weight_method      = "equal",
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)
cat("\n[_run_seasonality] grade=", res$grade, " score=", res$score,
    " excess_cagr=", res$excess_cagr, " l_code=", res$l_code, "\n")
