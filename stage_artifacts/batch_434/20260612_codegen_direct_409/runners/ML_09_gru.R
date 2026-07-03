#!/usr/bin/env Rscript
# Patched direct AlphaSearch runner for ML_09_gru
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "D01_IdioVol,D02_Beta,Q01_GPA,Q04_Piotroski_F,Q09_CFOA,Q07_Earnings_Stability,V01_BM,V03_CFP,V10_FCF_Yield,V11_Shareholder_Yield,M01_Mom_12_1,M07_IndMom")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1,1,1,1,1,1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "3")
Sys.setenv(FM_TOP_K = "6")
Sys.setenv(FM_LOOKBACK_MONTHS = "36")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "GRU 팩터 배분 — LSTM 대비 경량 RNN",
  strategy_idea = "GRU 팩터 배분 — LSTM 대비 경량 RNN patched blocked runner into executable PIT-safe AlphaSearch direct implementation patched factors=D01_IdioVol+D02_Beta+Q01_GPA+Q04_Piotroski_F+Q09_CFOA+Q07_Earnings_Stability+V01_BM+V03_CFP+V10_FCF_Yield+V11_Shareholder_Yield+M01_Mom_12_1+M07_IndMom; engine=fm; min_count=3; n=30; weight=equal; cov=sample; runner=/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/runners/ML_09_gru.R PATCHED_DIRECT_FM_FROM_PATCHED_DIRECT_FM_FROM_DIRECT_CODE_REQUIRED_ML_ENGINE",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_momentum.R",
  n_holdings = 30L,
  weight_method = "equal",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE,
  vol_target = 0.250000,
  vol_lookback = 60L,
  dd_brake = list(entry_pct = 0.120000, exit_pct = 0.350000),
  use_default_buffer = TRUE
)
saveRDS(res, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/ML_09_gru_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "ML_09_gru", res$grade %||% NA_character_, res$score %||% NA_real_, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/ML_09_gru_result.rds"))
