#!/usr/bin/env Rscript
# Patched direct AlphaSearch runner for ML_18_vae
args0 <- commandArgs(FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) "")
root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), "../../../.."), winslash = "/", mustWork = FALSE) else ""
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
setwd(root)
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
Sys.setenv(FACTOR_NAMES = "CR02_Volume_Concentration,CR08_Volume_Price_Divergence,CR04_Ownership_Concentration,D43_Skewness,D44_Kurtosis,D47_CVaR_5pct,R03_CVaR_95,INV01_Foreign_NetBuy_20d")
Sys.setenv(FACTOR_WEIGHTS = "1,1,1,1,1,1,1,1")
Sys.setenv(FACTOR_MIN_COUNT = "3")
Sys.setenv(FM_TOP_K = "6")
Sys.setenv(FM_LOOKBACK_MONTHS = "36")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name = "VAE 잠재 팩터 — Variational Autoencoder로 잠재 팩터 추출 후 scoring",
  strategy_idea = "VAE 잠재 팩터 — Variational Autoencoder로 잠재 팩터 추출 후 scoring patched blocked runner into executable PIT-safe AlphaSearch direct implementation patched factors=CR02_Volume_Concentration+CR08_Volume_Price_Divergence+CR04_Ownership_Concentration+D43_Skewness+D44_Kurtosis+D47_CVaR_5pct+R03_CVaR_95; engine=fm; min_count=3; n=30; weight=equal; cov=sample; runner=/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/runners/ML_18_vae.R PATCHED_DIRECT_FM_FROM_PATCHED_DIRECT_FM_FROM_DIRECT_CODE_REQUIRED_ML_ENGINE",
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
saveRDS(res, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/ML_18_vae_result.rds")
cat(sprintf("[codegen-runner] DONE %s grade=%s score=%s -> %s\n",
            "ML_18_vae", res$grade %||% NA_character_, res$score %||% NA_real_, "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/ML_18_vae_result.rds"))
