#!/usr/bin/env Rscript
# Generated direct AlphaSearch runner for MF_CCC1_FACTOR_QUALITY
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "Q01_GPA,Q04_Piotroski_F,Q09_CFOA,Q07_Earnings_Stability")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "4")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "팩터 품질 필터 — IC/ICIR/Turnover 3축으로 팩터 자체의 품질 관리",
  strategy_idea = "팩터 품질 필터 — IC/ICIR/Turnover 3축으로 팩터 자체의 품질 관리 diagnostic/sweep spec; code or target artifacts must be prepared diagnostic/sweep spec; code or target artifacts must be prepared",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_combo.R",
  n_holdings = 30L,
  weight_method = "equal",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE,
  use_default_buffer = TRUE
)
saveRDS(res, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_CCC1_FACTOR_QUALITY_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "MF_CCC1_FACTOR_QUALITY", res$grade %||% NA_character_, res$score %||% NA_real_, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_CCC1_FACTOR_QUALITY_result.rds"))
