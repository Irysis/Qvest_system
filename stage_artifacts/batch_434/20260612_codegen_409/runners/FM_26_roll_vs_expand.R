#!/usr/bin/env Rscript
# Generated AlphaSearch runner for FM_26_roll_vs_expand
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "M01_Mom_12_1,M07_IndMom,M05_Trended_Mom,L01_Amihud,L09_Amihud_20d,L10_Amihud_Ratio,L40_VWAP_Spread,D01_IdioVol")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1,1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "5")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "[진단] Rolling vs Expanding FM — 6m rolling FM vs expanding FM 비교",
  strategy_idea = "[진단] Rolling vs Expanding FM — 6m rolling FM vs expanding FM 비교 diagnostic/sweep spec; code or target artifacts must be prepared diagnostic/sweep spec; code or target artifacts must be prepared",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_combo.R",
  n_holdings = 30L,
  weight_method = "equal",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE
)
saveRDS(res, "stage_artifacts/batch_434/20260612_codegen_409/FM_26_roll_vs_expand_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "FM_26_roll_vs_expand", res$grade %||% NA_character_, res$score %||% NA_real_, "stage_artifacts/batch_434/20260612_codegen_409/FM_26_roll_vs_expand_result.rds"))
