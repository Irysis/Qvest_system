source("02_Infrastructure/alpha_search/run_alpha_search.R")
r <- run_alpha_search(
  strategy_name = "STR_valmomqual_3way",
  strategy_idea = "value(BM)+momentum(12-1)+quality(GP) z-combo 3-way, multi-factor 통합 (AMP+QMJ)",
  factor_engine_path = file.path(getwd(), "02_Infrastructure/alpha_search/fe_valmomqual.R"),
  start_date = "2005-01-01",
  universe = "K200_KQ150",
  factor_analysis = TRUE,
  send_telegram = TRUE
)
cat("RUN_DONE grade:", r$grade, "score:", r$total_score, "id:", r$strategy_id, "\n")
