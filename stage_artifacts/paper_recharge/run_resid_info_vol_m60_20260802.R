source("02_Infrastructure/alpha_search/run_alpha_search.R")

result <- run_alpha_search(
  strategy_name      = "RESID_INFO_VOL_M60",
  strategy_idea      = "변동성으로 설명되지 않는 잔차 거래량의 60거래일 지속 수준이 높은 종목 매수 — 정보거래 활동의 일시적 서프라이즈가 아니라 지속 수준을 포착 (Bucci et al. 2026 SMAR, arXiv:2606.08141 / 07-27 base RESID_INFO_VOL next_probe P1: 회전율 트랩 분리 식별)",
  factor_engine_path = file.path(PROJECT_ROOT, "02_Infrastructure/alpha_search/fe_resid_info_vol_m60.R"),
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE,
  tg_dry_run         = FALSE
)

cat("\n===== RESULT SUMMARY =====\n")
cat(sprintf("strategy_id: %s\n", result$strategy_id))
cat(sprintf("grade: %s\n", as.character(result$grade)))
cat(sprintf("score: %s\n", as.character(result$score)))
cat(sprintf("pass: %s\n", as.character(result$pass)))
cat(sprintf("out_dir: %s\n", result$out_dir))
cat(sprintf("l_code: %s\n", as.character(result$l_code)))
