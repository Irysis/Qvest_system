source("02_Infrastructure/alpha_search/run_alpha_search.R")

result <- run_alpha_search(
  strategy_name      = "VOL_RANK_STABILITY",
  strategy_idea      = "변동성 순위(Markov chain) 지속성 팩터: 12개월 vol rank 안정성 높은 종목 매수 (Halperin 2026 arXiv:2607.19005)",
  factor_engine_path = normalizePath("02_Infrastructure/alpha_search/factor_engine_vol_rank_stability.R"),
  n_holdings         = 20L,
  weight_method      = "ivol",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE,
  tg_dry_run         = FALSE
)

cat("\n===== RESULT SUMMARY =====\n")
cat(sprintf("strategy_id: %s\n", result$strategy_id))
cat(sprintf("grade: %s | score: %.1f\n", result$grade, result$score %||% NA))
cat(sprintf("pass: %s\n", result$pass))
cat(sprintf("port_t: %.3f\n", result$notable %||% NA))
cat(sprintf("out_dir: %s\n", result$out_dir))
if (!is.null(result$l_code)) cat(sprintf("l_code: %s\n", result$l_code))
