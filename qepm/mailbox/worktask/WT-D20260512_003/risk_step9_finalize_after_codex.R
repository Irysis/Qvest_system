#==============================================================================
# Risk Step 9 (post-Codex): Write final risk_package.json + lineage_recorder
#
# Pre-requisite: codex_critic_response_risk.json arrived + risk_challenge_note.md updated
#
# Execution: AFTER Codex round complete + challenge_note disposition recorded.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(digest)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/worktask/lineage_utils.R")

WT <- "WT-D20260512_003"
WT_MAILBOX <- file.path("qepm/mailbox/worktask", WT)
OUT_DIR <- file.path("stage_artifacts", paste0("WT_", WT))

# Load draft + codex response
draft <- fromJSON(file.path(WT_MAILBOX, "risk_package_draft.json"), simplifyVector = FALSE)
codex_path <- file.path(WT_MAILBOX, "codex_critic_response_risk.json")
if (!file.exists(codex_path)) {
  stop("[Step9] codex_critic_response_risk.json missing — wait for Codex Round completion.")
}
codex <- fromJSON(codex_path, simplifyVector = FALSE)

# Append codex_round_summary into final package
codex_summary <- list(
  stance = codex$stance %||% "UNKNOWN",
  veto_flag = codex$veto_flag %||% FALSE,
  concerns_count = length(codex$critical_concerns %||% list()),
  severity_breakdown = local({
    sevs <- sapply(codex$critical_concerns %||% list(), function(c) c$severity %||% "UNKNOWN")
    as.list(table(sevs))
  }),
  weakest_assumption = codex$weakest_assumption %||% NA_character_,
  challenge_note_path = "qepm/mailbox/worktask/WT-D20260512_003/risk_challenge_note.md"
)
draft$codex_round_summary <- codex_summary

# Write final risk_package.json (no _draft suffix; PreToolUse hook verifies critic_response + draft exist)
final_path <- file.path(WT_MAILBOX, "risk_package.json")
write_json(draft, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[Step9] risk_package.json written (", round(file.info(final_path)$size / 1024, 1), "KB)\n")

# Record lineage (R11 GAP-2: write AFTER risk_package.json so file exists for hash)
record_package_lineage(
  task_id = WT,
  package_type = "risk_package",
  method_selected = "factor_model_8f",
  input_file_paths = c(
    file.path(WT_MAILBOX, "alpha_package.json"),
    file.path(OUT_DIR, "alpha_scores_new.parquet"),
    RAWDATA_CACHE
  ),
  windows = list(
    estimation_window = list(start = "2021-05-01", end = "2026-04-01", n_obs = 60L),
    alpha_window = list(start = "2004-01-01", end = "2026-04-01", n_obs = 268L)
  ),
  extra = list(
    selection_objective = "condition_number",
    n_assets = 237L,
    condition_number = 153.92,
    psd = TRUE,
    factor_coverage_r2_pct = 15.57,
    cost_axis_inherited = "incremental_3.5bps_qlead_mandate_20260512"
  )
)
cat("[Step9] lineage recorded (artifact_lineage.json updated).\n")
cat("[Step9] DONE.\n")
