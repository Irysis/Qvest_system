PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_alpha_search.R")
result <- run_alpha_search(
  strategy_name      = "STR_AS_FX_INTENSITY",
  strategy_idea      = "AWARE-FX 논문 FX exposure baseline 직접 대응: (|외화환산이익|+|외화환산손실|)/TotalAssets FX 노출 강도 지수 — 높은 FX 노출 기업의 헤징 프리미엄 long",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/factor_engine_FX_Intensity.R",
  n_holdings         = 25,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2016-04-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE
)
cat("\n==== RESULT ====\n")
cat("grade:", result$grade, "\n")
cat("score:", result$score, "\n")
cat("pass:", result$pass, "\n")
cat("out_dir:", result$out_dir, "\n")
if (!is.null(result$metrics)) {
  cat("CAGR:", result$metrics$CAGR, "\n")
  cat("Sharpe:", result$metrics$Sharpe, "\n")
  cat("MDD:", result$metrics$MDD, "\n")
}
