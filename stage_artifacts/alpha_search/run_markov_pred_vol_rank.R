source("02_Infrastructure/alpha_search/run_alpha_search.R")

result <- run_alpha_search(
  strategy_name      = "Markov_PredVolRank",
  strategy_idea      = "Markov 전이행렬 기대 분위 예측: E_next=sum_j(j*P[i,j]), Score=-E_next. arXiv:2607.27461 Halperin 2026",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/factor_engine_markov_pred_vol_rank.R",
  n_holdings         = 25L,
  weight_method      = "ew",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE,
  tg_dry_run         = FALSE
)

cat("\n=== RESULT SUMMARY ===\n")
cat("strategy_id:", result$strategy_id, "\n")
cat("grade:", result$grade, "\n")
cat("score:", result$score, "\n")
cat("pass:", result$pass, "\n")
cat("out_dir:", result$out_dir, "\n")
if (!is.null(result$notable)) cat("notable:", result$notable, "\n")
