#!/usr/bin/env Rscript
# Generated direct AlphaSearch runner for EVO_1048_dd_vt_overlay
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "D01_IdioVol,D02_Beta,M07_IndMom,V01_BM,V03_CFP,V10_FCF_Yield,V11_Shareholder_Yield")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "7")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "Evolution: STR_1048 v2 + vol_target + DD start 0.08 → MDD 32%→25%",
  strategy_idea = "Evolution: STR_1048 v2 + vol_target + DD start 0.08 → MDD 32%→25% Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_combo.R",
  n_holdings = 30L,
  weight_method = "equal",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE,
  vol_target = 0.150000,
  vol_lookback = 60L,
  dd_brake = list(entry_pct = 0.080000, exit_pct = 0.200000),
  use_default_buffer = TRUE
)
saveRDS(res, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/EVO_1048_dd_vt_overlay_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "EVO_1048_dd_vt_overlay", res$grade %||% NA_character_, res$score %||% NA_real_, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/EVO_1048_dd_vt_overlay_result.rds"))
