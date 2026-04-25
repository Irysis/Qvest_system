#==============================================================================
# Iter 6 Risk — Finalize step
# 1) Promote risk_package_draft.json → risk_package.json
# 2) record_package_lineage(package_type="risk_package")  (R11 v6.1)
# 3) Update status.json: ALPHA_DONE → RISK_DONE
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260425_011"
OUT_DIR_MAIL <- file.path("qepm/mailbox/worktask", WT_ID)

draft <- read_json(file.path(OUT_DIR_MAIL, "risk_package_draft.json"))

# Step 1: Write final risk_package.json
final_path <- file.path(OUT_DIR_MAIL, "risk_package.json")
write_json(draft, final_path, pretty = TRUE, auto_unbox = TRUE)
cat("Wrote: ", final_path, "\n")

# Step 2: record_package_lineage  (CRITICAL: AFTER write_json)
source("02_Infrastructure/worktask/lineage_utils.R")

input_paths <- c(
  file.path(OUT_DIR_MAIL, "alpha_package.json"),
  ".cache/kr_factor_returns_v2.parquet",
  ".cache/rawdata.parquet",
  "stage_artifacts/WT_D20260425_007/regime_panel.parquet",
  "stage_artifacts/WT_D20260425_011/alpha_scores.parquet"
)

record_fn <- tryCatch(get("record_package_lineage"), error = function(e) NULL)

if (!is.null(record_fn)) {
  record_fn(
    task_id = WT_ID,
    package_type = "risk_package",
    method_selected = "factor_model_BOmegaB_plus_D__Omega_LedoitWolf_oracle__Iter6_Kelly_Overlay_compat",
    input_file_paths = input_paths,
    windows = list(
      train = list(start = "2002-08-01", end = "2023-10-01"),
      pit_cutoff = list(date = "2023-10-31")
    )
  )
  cat("[lineage] record_package_lineage() called\n")
} else {
  lineage_path <- file.path(OUT_DIR_MAIL, "artifact_lineage.json")
  lin <- read_json(lineage_path)
  git_state <- capture_git_state()
  r_env <- capture_r_env()
  hashes <- capture_input_hashes(input_paths)
  new_entry <- list(
    task_id = WT_ID,
    package_type = "risk_package",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    git_commit = git_state$git_commit,
    git_dirty = git_state$git_dirty,
    r_version = r_env$r_version,
    r_packages = r_env$r_packages,
    random_seed = 20260425L,
    input_hashes = hashes,
    method_selected = "factor_model_BOmegaB_plus_D__Omega_LedoitWolf_oracle__Iter6_Kelly_Overlay_compat",
    method_shopping_log_ref = NULL,
    windows = list(
      train = list(start = "2002-08-01", end = "2023-10-01"),
      pit_cutoff = list(date = "2023-10-31")
    ),
    reproduction_command = "Rscript -e 'set.seed(20260425); source(\"stage_artifacts/WT_D20260425_011/run_risk_iter6.R\"); source(\"stage_artifacts/WT_D20260425_011/finalize_risk_iter6.R\")'",
    file_path = "qepm/mailbox/worktask/WT-D20260425_011/risk_package.json",
    file_hash_sha256 = compute_file_hash(final_path)
  )
  lin$entries[[length(lin$entries) + 1]] <- new_entry
  lin$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  write_json(lin, lineage_path, pretty = TRUE, auto_unbox = TRUE)
  cat("[lineage] Appended risk_package entry to ", lineage_path, "\n")
}

# Step 3: Update status.json
status_path <- file.path(OUT_DIR_MAIL, "status.json")
status <- read_json(status_path)
status$current_phase <- "RISK_DONE"
status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$risk_pass <- TRUE
status$risk_method_selected <- "factor_model_BOmegaB_plus_D"
status$risk_omega_estimator <- "ledoit_wolf_oracle"
status$risk_sigma_cond <- 19.14
status$risk_sleeve_cor <- 0.597
status$risk_diversification_benefit_pct <- 9.15
status$risk_pooled_fallback_bound <- TRUE
status$risk_kelly_overlay_compat <- "PASS"
status$risk_iter6_vol_ratio <- 1.688
status$risk_summary_iter6 <- list(
  cond_post_shrink = 19.14,
  multi_sleeve_cor = 0.597,
  diversification_benefit_pct = 9.15,
  worst_stress_pct = -28.14,
  hill_alpha = 3.0,
  cvar_95_daily = -0.0308,
  evt_var_99 = 0.0546,
  kelly_overlay_compat = "PASS",
  vol_ratio_realized_to_target = 1.688,
  vol_scale_predicted = 0.592
)
write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE)
cat("[status] Updated to RISK_DONE\n")

cat("\n==== FINALIZE DONE ====\n")
cat("risk_package.json:    ", final_path, "\n")
cat("risk_challenge_note:  ", file.path(OUT_DIR_MAIL, "risk_challenge_note.md"), "\n")
cat("status:               RISK_DONE\n")
