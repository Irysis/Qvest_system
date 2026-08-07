Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/alpha_search/run_alpha_search.R")

result <- run_alpha_search(
  strategy_name      = "SpectralPersistence_Hurst",
  strategy_idea      = "Hurst R/S 지수(rolling 252일) 기반 스펙트럼 지속성: H>0.5 종목(추세 지속)을 long — 수익률 저주파 스펙트럼 질량 초과가 추세추종 알파의 이론적 근거 (Sepp & Lucic arXiv:2607.19497)",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_spectral_persistence_hurst.R",
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
if (!is.null(result$notable)) {
  cat("notable :\n")
  for (nm in names(result$notable)) {
    cat(sprintf("  %-25s %s\n", nm, result$notable[[nm]]))
  }
}
