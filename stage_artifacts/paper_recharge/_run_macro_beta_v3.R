# _run_macro_beta_v3.R — macro_beta_momentum 백테스트 (사전계산 parquet 경유)
# arXiv 2608.12283 | 실행: Rscript -e 'source("stage_artifacts/paper_recharge/_run_macro_beta_v3.R")'

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR",
                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(PROJ)

source(file.path(PROJ, "02_Infrastructure", "alpha_search", "run_alpha_search.R"))

result <- run_alpha_search(
  strategy_name = "MacroBetaMom_v3_precomputed",
  strategy_idea = paste0(
    "arXiv 2608.12283 macro-beta momentum KR: ",
    "rolling 60d OLS beta(Term_Spread/VIX/KRW_USD) x 20d macro change 합산. ",
    "Python pre-computed .cache/macro_beta_scores.parquet 경유(260 month-ends). ",
    "MA01-MA07 DB 정적 sensitivity 와 달리 동적(beta x delta_20d) 신호."
  ),
  factor_engine_path = file.path(PROJ,
    "stage_artifacts", "paper_recharge", "macro_beta_mom_engine_v3.R"),
  n_holdings    = 25L,
  weight_method = "equal",
  commission    = 0.0015,
  start_date    = "2005-01-01",
  universe      = "K200_KQ150",
  factor_analysis = TRUE
)

cat("\n=== MacroBetaMom_v3 결과 ===\n")
cat("strategy_id:", result$strategy_id %||% "N/A", "\n")
cat("grade:      ", result$grade %||% "N/A", "\n")
cat("score:      ", result$score %||% "N/A", "\n")
cat("pass:       ", result$pass %||% "N/A", "\n")
cat("out_dir:    ", result$out_dir %||% "N/A", "\n")

if (!is.null(result$metrics)) {
  m <- result$metrics
  cat("\n--- 주요 지표 ---\n")
  cat("Annualized SR:   ", m$AnnualizedSharpeRatio %||% "N/A", "\n")
  cat("CAGR:            ", m$CAGR %||% "N/A", "\n")
  cat("MaxDrawdown:     ", m$MaxDrawdown %||% "N/A", "\n")
  cat("PORT_t (NW):     ", m$portfolio_alpha_t_nw %||% "N/A", "\n")
  cat("OOS retention:   ", m$oos_retention %||% "N/A", "\n")
  cat("Calmar:          ", m$calmar %||% "N/A", "\n")
}
