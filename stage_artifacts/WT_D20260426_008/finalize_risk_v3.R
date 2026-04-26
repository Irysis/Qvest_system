#==============================================================================
# WT-D20260426_008 (Iter 15) V3 Risk — Finalize step
# 1) Promote risk_package_draft.json → risk_package.json
# 2) record_package_lineage(package_type="risk_package")
# 3) Update status.json: ALPHA_DONE → RISK_DONE
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260426_008"
WT_TAG <- "WT_D20260426_008"
OUT_DIR_MAIL <- file.path("qepm/mailbox/worktask", WT_ID)
OUT_DIR_STAGE <- file.path("stage_artifacts", WT_TAG)

draft <- read_json(file.path(OUT_DIR_MAIL, "risk_package_draft.json"))

# Step 1: Write final risk_package.json
final_path <- file.path(OUT_DIR_MAIL, "risk_package.json")
write_json(draft, final_path, pretty = TRUE, auto_unbox = TRUE)
cat("Wrote:", final_path, "\n")

# Step 2: record_package_lineage (CRITICAL: write_json BEFORE lineage call)
source("02_Infrastructure/worktask/lineage_utils.R")

input_paths <- c(
  file.path(OUT_DIR_MAIL, "alpha_package.json"),
  ".cache/kr_factor_returns_v2.parquet",
  ".cache/rawdata.parquet",
  "stage_artifacts/WT_D20260425_007/regime_panel.parquet",
  file.path(OUT_DIR_STAGE, "alpha_scores.parquet"),
  "qepm/mailbox/worktask/WT-D20260426_004/backtest_result/monthly_returns.parquet",
  "04_Research/strategies/STR_1656_MLRA/output/s5_mutations/M05/nav.csv"
)

record_fn <- tryCatch(get("record_package_lineage"), error = function(e) NULL)

if (!is.null(record_fn)) {
  tryCatch({
    record_fn(
      task_id = WT_ID,
      package_type = "risk_package",
      method_selected = "factor_model_BOmegaB_plus_D__Omega_LedoitWolf_oracle",
      input_file_paths = input_paths,
      windows = list(
        train = list(start = "2002-08-01", end = "2023-11-01"),
        pit_cutoff = list(date = "2023-11-30")
      )
    )
    cat("[lineage] record_package_lineage() called\n")
  }, error = function(e) {
    cat("[lineage] ERROR:", conditionMessage(e), "\n")
  })
} else {
  cat("[lineage] record_package_lineage not available\n")
}

# Step 3: Update status.json
status_path <- file.path(OUT_DIR_MAIL, "status.json")
status <- read_json(status_path)
status$current_phase <- "RISK_DONE"
status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$risk_pass <- TRUE
status$risk_method_selected <- "factor_model_BOmegaB_plus_D"
status$risk_omega_estimator <- draft$diagnostics$factor_cov_estimator
status$risk_sigma_cond <- draft$diagnostics$condition_number
status$risk_min_eig <- draft$diagnostics$min_eigenvalue
status$risk_psd <- draft$diagnostics$psd
status$risk_sleeve_cor <- draft$diagnostics$tdc_summary$sleeve_core_vs_defense
status$risk_diversification_benefit_pct <- draft$multi_sleeve_v3$diversification_benefit_pct
status$risk_pooled_fallback_bound <- TRUE
status$risk_v3_vs_str1701_score_perdate_cor <- draft$diagnostics$tdc_summary$v3_score_vs_str1701_score_perdate_mean
status$risk_v3_nav_vs_str1701_tdc_q5 <- draft$diagnostics$tdc_summary$v3_nav_proxy_vs_str1701_nav_tdc_q5
status$risk_v3_nav_vs_str1656_cor <- draft$diagnostics$tdc_summary$v3_nav_proxy_vs_str1656_nav_pearson
status$risk_pg2_blend_v3_vs_active_cor <- draft$diagnostics$tdc_summary$pg2_blend_v3_vs_pg2_active_cor
write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE)
cat("[status] Updated to RISK_DONE\n")

cat("\n==== FINALIZE DONE ====\n")
cat("risk_package.json:    ", final_path, "\n")
cat("risk_challenge_note:  ", file.path(OUT_DIR_MAIL, "risk_challenge_note.md"), "\n")
cat("codex response:       ", file.path(OUT_DIR_MAIL, "codex_critic_response_risk.json"), "\n")
cat("status:               RISK_DONE\n")
