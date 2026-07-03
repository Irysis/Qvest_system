#!/usr/bin/env Rscript
# Generated AlphaSearch runner for RC_58_mrs_thresh_sweep
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "D01_IdioVol,D02_Beta,M07_IndMom,Q04_Piotroski_F,V03_CFP")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "3")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "[진단] MRS Threshold Sweep — Low(10/12/15/18) × High(22/25/28/30) = 16조합",
  strategy_idea = "[진단] MRS Threshold Sweep — Low(10/12/15/18) × High(22/25/28/30) = 16조합 diagnostic/sweep spec; code or target artifacts must be prepared diagnostic/sweep spec; code or target artifacts must be prepared",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_combo.R",
  n_holdings = 30L,
  weight_method = "equal",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE
)
saveRDS(res, "stage_artifacts/batch_434/20260612_codegen_409/RC_58_mrs_thresh_sweep_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "RC_58_mrs_thresh_sweep", res$grade %||% NA_character_, res$score %||% NA_real_, "stage_artifacts/batch_434/20260612_codegen_409/RC_58_mrs_thresh_sweep_result.rds"))
