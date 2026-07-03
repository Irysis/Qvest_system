#!/usr/bin/env Rscript
# Generated AlphaSearch runner for FM_14_half_life_fm
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "M01_Mom_12_1,M07_IndMom,M05_Trended_Mom,V01_BM,V03_CFP,V10_FCF_Yield,V11_Shareholder_Yield,D01_IdioVol")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1,1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "5")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "Half-Life FM — 팩터 수익률의 반감기로 FM 신뢰도 조절",
  strategy_idea = "Half-Life FM — 팩터 수익률의 반감기로 FM 신뢰도 조절 Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_combo.R",
  n_holdings = 30L,
  weight_method = "equal",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE
)
saveRDS(res, "stage_artifacts/batch_434/20260612_codegen_409/FM_14_half_life_fm_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "FM_14_half_life_fm", res$grade %||% NA_character_, res$score %||% NA_real_, "stage_artifacts/batch_434/20260612_codegen_409/FM_14_half_life_fm_result.rds"))
