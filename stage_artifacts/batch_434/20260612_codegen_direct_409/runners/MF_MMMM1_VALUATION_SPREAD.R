#!/usr/bin/env Rscript
# Generated direct AlphaSearch runner for MF_MMMM1_VALUATION_SPREAD
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "V01_BM,V03_CFP,V10_FCF_Yield,V11_Shareholder_Yield,L01_Amihud,L09_Amihud_20d,L10_Amihud_Ratio,L40_VWAP_Spread,CR02_Volume_Concentration,CR08_Volume_Price_Divergence")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1,1,1,1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "10")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "팩터 밸류에이션 스프레드 — 팩터 long/short 밸류에이션 차이로 crowding 측정",
  strategy_idea = "팩터 밸류에이션 스프레드 — 팩터 long/short 밸류에이션 차이로 crowding 측정 Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_combo.R",
  n_holdings = 30L,
  weight_method = "equal",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE,
  use_default_buffer = TRUE
)
saveRDS(res, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_MMMM1_VALUATION_SPREAD_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "MF_MMMM1_VALUATION_SPREAD", res$grade %||% NA_character_, res$score %||% NA_real_, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_MMMM1_VALUATION_SPREAD_result.rds"))
