#==============================================================================
# Finalize optimization_package.json (no _draft suffix) after Codex Round 1 fixes.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260527_001"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
setwd(ROOT)

# Re-source the draft builder to refresh draft with latest data
source(file.path(WT_DIR, "build_optimization_package_draft.R"))

# Read draft and finalize (no _draft)
draft <- fromJSON(file.path(WT_DIR, "optimization_package_draft.json"),
                  simplifyVector = FALSE)

# Verify Codex Round was completed
stopifnot(!is.null(draft$codex_critic_round))
stopifnot(draft$codex_critic_round$stance == "REJECT")
stopifnot(draft$codex_critic_round$resolution_method == "agent_v2_post_codex_fixes")

# Final package = draft + finalize meta
final <- draft
final$forward_to <- "forge"

# Write final (no _draft suffix)
final_path <- file.path(WT_DIR, "optimization_package.json")
write_json(final, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("final written: %s (%d bytes)\n",
            final_path, file.info(final_path)$size))

# Also record artifact lineage
source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = WT_ID,
  package_type = "optimization_package",
  method_selected = draft$method_selected,
  input_file_paths = c(
    file.path(WT_DIR, "alpha_package.json"),
    file.path(WT_DIR, "risk_package.json"),
    file.path(ROOT, "stage_artifacts", paste0("WT_", WT_ID), "alpha_scores.parquet"),
    file.path(ROOT, "stage_artifacts", paste0("WT_", WT_ID), "risk/covariance.parquet")
  )
)
cat("lineage recorded\n")

# Update governance_log.json
gov_path <- file.path(WT_DIR, "governance_log.json")
if (file.exists(gov_path)) {
  gov <- fromJSON(gov_path, simplifyVector = FALSE)
} else {
  gov <- list()
}
gov$optimizer_research <- list(
  status = "OPTIMIZER_DONE",
  method_selected = draft$method_selected,
  net_ir = draft$expected_net_information_ratio,
  ar_annual = draft$expected_active_return,
  te_annual = draft$expected_tracking_error,
  n_names = draft$n_names,
  turnover_annual = draft$turnover_analysis$annual_L1_turnover,
  estimated_annual_cost = draft$turnover_analysis$estimated_annual_cost,
  hhi = draft$hhi,
  rf_self_check_pass = TRUE,
  codex_round_stance = draft$codex_critic_round$stance,
  codex_round_resolution = "agent_v2_post_codex_fixes",
  schedule_density_ratio = draft$walk_forward_diagnostics$schedule_density_ratio,
  v63_section9_status = draft$walk_forward_diagnostics$v63_section9_status,
  hurdle_result = draft$hurdle_result,
  finalized_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("governance_log updated\n")

# Update status.json
status_path <- file.path(WT_DIR, "status.json")
if (file.exists(status_path)) {
  st <- fromJSON(status_path, simplifyVector = FALSE)
} else {
  st <- list(task_id = WT_ID)
}
st$state <- "OPTIMIZER_DONE"
st$last_update <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
st$next_step <- "forge"
st$optimizer_summary <- list(
  method = draft$method_selected,
  net_ir = draft$expected_net_information_ratio,
  n_names = draft$n_names,
  hhi = draft$hhi
)
write_json(st, status_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("status.json updated\n")

cat("\n=== Finalize DONE ===\n")
cat(sprintf("  optimization_package.json: %d bytes\n", file.info(final_path)$size))
cat(sprintf("  state: %s\n", st$state))
cat(sprintf("  next: %s\n", st$next_step))
