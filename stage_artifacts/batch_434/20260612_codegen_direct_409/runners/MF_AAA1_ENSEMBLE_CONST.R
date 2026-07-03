#!/usr/bin/env Rscript
# Generated direct AlphaSearch runner for MF_AAA1_ENSEMBLE_CONST
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "D01_IdioVol,D02_Beta,M07_IndMom,V03_CFP")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "4")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "구성법 앙상블 — EW+ScoreW+NCO+RP 4가지 구성법 평균",
  strategy_idea = "구성법 앙상블 — EW+ScoreW+NCO+RP 4가지 구성법 평균 Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_combo.R",
  n_holdings = 30L,
  weight_method = "nco",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE,
  use_default_buffer = TRUE
)
saveRDS(res, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_AAA1_ENSEMBLE_CONST_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "MF_AAA1_ENSEMBLE_CONST", res$grade %||% NA_character_, res$score %||% NA_real_, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_AAA1_ENSEMBLE_CONST_result.rds"))
