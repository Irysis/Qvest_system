source("02_Infrastructure/alpha_search/run_alpha_search.R")

result <- run_alpha_search(
  strategy_name      = "SPEC_MASS_LOWVOL",
  strategy_idea      = "저주파 스펙트럼 질량(추세 지속성) 상위 종목을 저변동성 하위 3분위 안에서만 선택 — 추세 알파를 낙폭 계층에서 분리 (Sepp-Lucic 2026, arXiv:2607.19497 / 07-27 base spec_mass_lowfreq_60d next_probe #2: MDD 61.4% 병목이 변동성 노출인지 신호 자체인지 분리 식별)",
  factor_engine_path = file.path(PROJECT_ROOT, "02_Infrastructure/alpha_search/fe_spec_mass_lowvol.R"),
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
