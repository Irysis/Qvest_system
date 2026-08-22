Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/alpha_search/run_alpha_search.R")

result <- run_alpha_search(
  strategy_name      = "DFA_RegimeSignals_StockCast",
  strategy_idea      = "동적 팩터 배분—국면 스위칭 신호 (논문명 기반 전략명, 도훈 2026-08-21 개명. 원논문 'Dynamic Factor Allocation Leveraging Regime-Switching Signals', Shu & Mulvey, JPM 51(3) 2025 / arXiv:2410.14841) BL 팩터 비중의 종목 전파: 팩터별 Sparse Jump Model 국면 → Black-Litterman 팩터 비중(보정 회계 M0-roll TE3, FQ-239 v5) → Score_i = Σ_f w_f·Z_f,i (V12/S01/M09/Q08/D03/GR07). 차별점(INV-7): 6월 stock25 음수는 동월-결함 상태 위 실측 — 본 런은 보정 상태·신규 vintage·하네스 공식 채점. 구명 SHUMULVEY 계열 승계",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_dfa_regimesignals_bl.R",
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)

cat("\n=== [AlphaSearch] 최종 결과 ===\n")
cat("grade   :", result$grade,   "\n")
cat("score   :", result$score,   "\n")
cat("pass    :", result$pass,    "\n")
cat("out_dir :", result$out_dir, "\n")
if (!is.null(result$notable)) { for (nm in names(result$notable)) cat(sprintf("  %-25s %s\n", nm, result$notable[[nm]])) }
