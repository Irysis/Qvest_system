# run_FQ110_dirA.R - FQ-110 방향A: JumpShare+ (jump momentum)
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source(file.path(PROJECT_ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))

FE_PATH <- file.path(PROJECT_ROOT,
  "stage_artifacts/alpha_search_FQ110/factor_engine_JumpShare.R")

res_A <- run_alpha_search(
  strategy_name      = "FQ110_JumpShare_A",
  strategy_idea      = "FQ-110: 12M top-5 jump_share direct factor. Direction A(+): high concentration = momentum. Bilateral frog-in-the-pan test.",
  factor_engine_path = FE_PATH,
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = FALSE
)

cat("\n===== DIRECTION A RESULT =====\n")
cat(sprintf("strategy_id: %s\n", res_A$strategy_id))
cat(sprintf("grade: %s\n", res_A$grade))
cat(sprintf("score: %.2f\n", res_A$score))
cat(sprintf("pass: %s\n", res_A$pass))
cat(sprintf("excess_cagr: %.4f\n", res_A$excess_cagr))
if (!is.null(res_A$hurdle_result) && !is.null(res_A$hurdle_result$metrics)) {
  m <- res_A$hurdle_result$metrics
  cat(sprintf("port_t: %.4f\n", m$port_t))
  cat(sprintf("oos_retention: %.4f\n", m$oos_retention))
  cat(sprintf("calmar: %.4f\n", m$calmar))
  cat(sprintf("sr: %.4f\n", m$sr))
  cat(sprintf("cagr: %.4f\n", m$cagr))
  cat(sprintf("mdd: %.4f\n", m$mdd))
  cat(sprintf("turnover: %.4f\n", m$turnover))
}
cat(sprintf("out_dir: %s\n", res_A$out_dir))
cat(sprintf("charts: %s\n", paste(res_A$charts, collapse=", ")))
cat("===== END DIRECTION A =====\n")

# save rds
saveRDS(res_A, file.path(PROJECT_ROOT, "stage_artifacts/alpha_search_FQ110/res_A.rds"))
cat("RDS saved.\n")
