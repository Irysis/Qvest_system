`%||%` <- function(a,b) if(!is.null(a)) a else b
MUTATION_CONFIG <- list(
  strategy_id = "STR_1519",
  mutation_id = "M1",
  factors = c("M25_Earnings_Mom_Streak"),
  weighting = "equal",
  overlay_dd = NULL,
  overlay_regime = FALSE,
  sector_neutral = TRUE,
  smoothing_months = 0L,
  rebalance = "monthly",
  ivol_weight = FALSE,
  n_holdings = 30L,
  commission = 0.0015
)
source(file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure/s5_mutation_runner.R"))
cat(sprintf("RESULT: %s/%s Grade=%s Score=%.1f SR=%.3f CAGR=%.1f%% MDD=%.1f%%\n",
    MUTATION_RESULT$strategy_id, MUTATION_RESULT$mutation_id,
    MUTATION_RESULT$grade, MUTATION_RESULT$score,
    MUTATION_RESULT$sharpe, MUTATION_RESULT$cagr, MUTATION_RESULT$mdd))
rm(list=setdiff(ls(), c("%||%"))); gc(verbose=FALSE)
