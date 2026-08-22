Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
result <- run_alpha_search(
  strategy_name      = "VOL_HURST_LowH",
  strategy_idea      = "RV(r^2) Hurst 횡단면 팩터: rolling 252일 R/S Analysis로 일별 실현변동성(r^2)의 Hurst H 추정, 낮은-H 종목 long. arXiv:2608.16749",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/factor_engine_vol_hurst.R",
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)
cat("\n=== VOL_HURST_LowH ===\n")
cat("grade:", result$grade, "\n")
cat("score:", result$score, "\n")
cat("pass:", result$pass, "\n")
cat("out_dir:", result$out_dir, "\n")