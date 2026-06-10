source("02_Infrastructure/alpha_search/run_alpha_search.R")
r <- run_alpha_search(
  strategy_name      = "STR_valmom_AMP2013",
  strategy_idea      = "value(BM)+momentum(12-1) z-combo, AMP 2013 완전복제",
  factor_engine_path = file.path(getwd(), "02_Infrastructure/alpha_search/fe_valmom.R"),
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE
)
cat("RUN_DONE run_id=", basename(r$out_dir), " grade=", r$grade, " score=", r$score, "\n", sep = "")
