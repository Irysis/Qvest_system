# run_vol_rank_markov.R
# 실행: cd to project root, then Rscript -e 'source("run_vol_rank_markov.R")'
#
# 대상: 2607.27461 Vol_Rank_Markov_Persistence
# impl_sketch: 월말 trailing 21d rv → 횡단면 10분위 → rolling 36M P^V 추정
#              → π^V_i = P^V[decile_i, {1,2}] → 상위 25종 EW 월간 리밸 15bps

# Project root resolution
if (nchar(Sys.getenv("CLAUDE_PROJECT_DIR")) > 0) {
  root <- Sys.getenv("CLAUDE_PROJECT_DIR")
} else if (nchar(Sys.getenv("QM_ROOT")) > 0) {
  root <- Sys.getenv("QM_ROOT")
} else {
  root <- getwd()
}
setwd(root)

source(file.path(root, "02_Infrastructure", "alpha_search", "run_alpha_search.R"))

result <- run_alpha_search(
  strategy_name      = "Vol_Rank_Markov_Persistence",
  strategy_idea      = paste0(
    "Vol Markov chain: rolling 36M pooled transition matrix P^V across 10 vol deciles. ",
    "Signal = P^V[decile_i, {1,2}] = prob of reaching lowest-vol 2 deciles next month. ",
    "Top-25 EW long-only KR. Source: Halperin (2026) arXiv:2607.27461."
  ),
  factor_engine_path = file.path(
    root, "02_Infrastructure", "alpha_search",
    "factor_engine_vol_rank_markov_persistence.R"
  ),
  n_holdings     = 25L,
  weight_method  = "ew",
  commission     = 0.0015,
  start_date     = "2005-01-01",
  universe       = "K200_KQ150",
  factor_analysis = TRUE
)

cat("\n===== Vol_Rank_Markov_Persistence RESULT =====\n")
cat(sprintf("strategy_id : %s\n", result$strategy_id))
cat(sprintf("grade       : %s\n", result$grade))
cat(sprintf("score       : %.1f\n", result$score))
cat(sprintf("pass        : %s\n", result$pass))
cat("\n")
print(result$metrics)
