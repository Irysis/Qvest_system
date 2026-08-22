# _run_macro_beta_mom.R — macro_beta_momentum 백테스트 실행 스크립트
# arXiv 2608.12283 pure-beta trigger KR 구현
# 실행: Rscript -e 'source("stage_artifacts/paper_recharge/_run_macro_beta_mom.R")'

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR",
                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(PROJ)

source(file.path(PROJ, "02_Infrastructure", "alpha_search", "run_alpha_search.R"))

result <- run_alpha_search(
  strategy_name      = "MacroBetaMom_60d_3factor",
  strategy_idea      = paste0(
    "arXiv 2608.12283 pure-beta trigger KR 구현: ",
    "각 종목의 rolling 60일 OLS 베타(Term_Spread/VIX/KRW_USD) × 20일 매크로 변화량 합으로 ",
    "매크로 환경 변화에 선행 반응하는 종목 상위 25개 long-only 월간 리밸런싱"
  ),
  factor_engine_path = file.path(PROJ,
    "stage_artifacts", "paper_recharge", "macro_beta_mom_engine.R"),
  n_holdings    = 25L,         # 논문 Russell 2000 기반 → KR max 25 (production constraint)
  weight_method = "equal",     # 논문 EW 기반
  commission    = 0.0015,      # 15bps one-way
  start_date    = "2005-01-01",
  universe      = "K200_KQ150",
  factor_analysis = TRUE
)

cat("\n=== run_alpha_search 결과 ===\n")
cat("strategy_id:", result$strategy_id %||% "N/A", "\n")
cat("grade:      ", result$grade %||% "N/A", "\n")
cat("score:      ", result$score %||% "N/A", "\n")
cat("pass:       ", result$pass %||% "N/A", "\n")
cat("out_dir:    ", result$out_dir %||% "N/A", "\n")
