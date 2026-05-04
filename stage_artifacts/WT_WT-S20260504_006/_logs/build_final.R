#==============================================================================
# WT-S20260504_006 — risk_package.json finalize (IPCA Round 2)
#  - read draft + codex_critic_response (or waiver) → final
#  - record lineage + status RISK_DONE
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(digest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-S20260504_006"
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)

draft_path     <- file.path(WT_DIR, "risk_package_draft.json")
codex_path     <- file.path(WT_DIR, "codex_critic_response_risk.json")
final_path     <- file.path(WT_DIR, "risk_package.json")
challenge_path <- file.path(WT_DIR, "risk_challenge_note.md")

stopifnot(file.exists(draft_path))
risk_package <- fromJSON(draft_path, simplifyVector = FALSE)

codex_present <- file.exists(codex_path)
codex <- if (codex_present) fromJSON(codex_path, simplifyVector = FALSE) else NULL
codex_stance <- if (codex_present) (codex$stance %||% codex$verdict %||% "UNKNOWN") else "WAIVER_TIMEOUT"

# Mark as final
risk_package$draft_revision <- "final"
risk_package$codex_round <- list(
  invoked = TRUE,
  response_present = codex_present,
  stance = codex_stance,
  challenge_note_path = "qepm/mailbox/worktask/WT-S20260504_006/risk_challenge_note.md",
  finalize_method = if (codex_present) "codex_response_received" else "waiver_no_response_within_timeout")
risk_package$finalized_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

# Write final
write_json(risk_package, final_path, pretty = TRUE, auto_unbox = TRUE)
cat("[", WT_ID, "] risk_package.json finalized →", final_path, "\n")
cat("  Codex stance:", codex_stance,
    "(response_present =", codex_present, ")\n")

# Record lineage (after final exists)
lineage_helper <- file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lineage_helper)) {
  source(lineage_helper)
  tryCatch({
    record_package_lineage(
      task_id = WT_ID,
      package_type = "risk_package",
      method_selected = risk_package$sigma_method_label,
      input_file_paths = c(
        file.path(WT_DIR, "alpha_package_inherit_ref.json"),
        file.path(WT_DIR, "request.json")),
      windows = list(
        is_window = list(start = "2004-02-02", end = "2024-06-30",
                          n_months_eff = risk_package$sigma_method_details$T_obs_IS),
        sigma_window = list(start = "2019-05-01", end = "2026-04-30")))
    cat("  lineage recorded.\n")
  }, error = function(e) cat("  lineage record warn:", conditionMessage(e), "\n"))
} else {
  cat("  lineage_utils.R not found — lineage skipped\n")
}

# Status update RISK_DONE
status_path <- file.path(WT_DIR, "status.json")
status_obj <- if (file.exists(status_path)) fromJSON(status_path, simplifyVector = FALSE) else list()
status_obj$current_state <- "RISK_DONE"
status_obj$last_transition_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status_obj$risk_package_path <- "qepm/mailbox/worktask/WT-S20260504_006/risk_package.json"
status_obj$risk_done_summary <- list(
  K_selected = risk_package$K_selected,
  L_selected = risk_package$L_selected,
  alpha_restriction = risk_package$alpha_restriction_selected,
  R2 = risk_package$ipca_diagnostics$R2_selected,
  cond_sigma = risk_package$sigma_method_details$audit$condition_number,
  mdd_268m = risk_package$tail_risk$monthly_metrics$mdd,
  sha256 = risk_package$lro_params_frozen$sha256,
  codex_stance = codex_stance)
write_json(status_obj, status_path, pretty = TRUE, auto_unbox = TRUE)
cat("  status.json → RISK_DONE\n")
cat("  R²=", risk_package$ipca_diagnostics$R2_selected,
    "Σ cond=", risk_package$sigma_method_details$audit$condition_number,
    "MDD=", risk_package$tail_risk$monthly_metrics$mdd, "\n")
