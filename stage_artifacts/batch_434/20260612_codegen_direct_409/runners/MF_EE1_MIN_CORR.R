#!/usr/bin/env Rscript
# Patched direct AlphaSearch runner for MF_EE1_MIN_CORR
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "D01_IdioVol,D02_Beta,V01_BM,V03_CFP,V10_FCF_Yield,V11_Shareholder_Yield")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "4")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "최소 상관 포트폴리오 — 높은 score + 낮은 상관 종목 30개 선택",
  strategy_idea = "최소 상관 포트폴리오 — 높은 score + 낮은 상관 종목 30개 선택 patched blocked runner into executable PIT-safe AlphaSearch direct implementation patched factors=D01_IdioVol+D02_Beta+V01_BM+V03_CFP+V10_FCF_Yield+V11_Shareholder_Yield; engine=combo; min_count=6; n=30; weight=hrp; cov=gerber_rmt; runner=/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/runners/MF_EE1_MIN_CORR.R PATCHED_DIRECT_COMBO_FROM_PATCHED_DIRECT_COMBO_FROM_DIRECT_CODE_REQUIRED_COMPONENT_RESULTS",
  factor_engine_path = "02_Infrastructure/alpha_search/fe_factor_combo.R",
  n_holdings = 30L,
  weight_method = "hrp",
  universe = "ALL",
  send_telegram = TRUE,
  tg_dry_run = FALSE,
  factor_analysis = TRUE,
  vol_target = 0.500000,
  vol_lookback = 60L,
  dd_brake = list(entry_pct = 0.120000, exit_pct = 0.350000),
  cov_method = "gerber_rmt",
  use_default_buffer = TRUE
)
saveRDS(res, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_EE1_MIN_CORR_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "MF_EE1_MIN_CORR", res$grade %||% NA_character_, res$score %||% NA_real_, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_EE1_MIN_CORR_result.rds"))
