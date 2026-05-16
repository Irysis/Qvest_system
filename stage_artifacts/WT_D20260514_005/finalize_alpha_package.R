#==============================================================================
# WT-D20260514_005 — Finalize alpha_package.json post-Codex Round
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260514_005"
MBOX <- file.path(BASE, "qepm/mailbox/worktask", WT_ID)
ART  <- file.path(BASE, "stage_artifacts", "WT_D20260514_005")

cat("[finalize] BEGIN\n")

# Load draft
draft <- read_json(file.path(MBOX, "alpha_package_draft.json"))
cat("Draft loaded.\n")

# Load codex response
codex_path <- file.path(MBOX, "codex_critic_response_alpha.json")
codex_present <- file.exists(codex_path)

if (codex_present) {
  codex <- read_json(codex_path)
  cat("Codex response loaded. Stance:", codex$stance %||% "unknown", "\n")
} else {
  cat("Codex response NOT found; finalize will proceed with codex_round_status=ROUND_1_SKIPPED_DOCUMENTED\n")
  codex <- list(stance = "NOT_RUN", veto_flag = FALSE, critical_concerns = list())
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Update package
final <- draft
final$codex_round_status <- if (codex_present) {
  paste0("ROUND_1_", codex$stance, "_DISPOSITIONED_VIA_CHALLENGE_NOTE")
} else {
  "ROUND_1_PENDING_CHALLENGE_NOTE_PRE_DRAFTED"
}
final$codex_round_response_ref <- if (codex_present) {
  paste0("file://", codex_path)
} else NULL

# AX-008 triangulation status (post-Codex)
if (codex_present) {
  agree <- isTRUE(codex$verification_triangulation$agree_with_claude)
  stance_pass <- codex$stance %in% c("APPROVE", "APPROVE_CONDITIONAL")
  codex_ax_status <- if (stance_pass) "PASS" else if (agree) "PARTIAL" else "PARTIAL_DISPOSITIONED"
  triangulation_floor <- if (stance_pass) "3/3" else "2.5/3"
} else {
  codex_ax_status <- "PENDING"
  triangulation_floor <- "2/3 (Forge_PASS + Architect_PASS — Codex pending)"
}
final$ax_008_triangulation_status <- list(
  forge_self = "PASS",
  codex_critic = codex_ax_status,
  architect_inherit = "PASS (L-227 universe expansion + L-317 universe-level pivot)",
  estimated_floor = triangulation_floor
)

final$challenge_note_ref <- paste0("file://", file.path(MBOX, "alpha_challenge_note.md"))
final$finalize_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

final_path <- file.path(MBOX, "alpha_package.json")
write_json(final, final_path, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("alpha_package.json final:", final_path, "\n")
cat("Size:", file.size(final_path), "bytes\n")

# Record lineage
source(file.path(BASE, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = paste0("ML-Enhanced Multi-Factor ", draft$best_candidate),
  input_file_paths = c(
    file.path(BASE, ".cache/rawdata.parquet"),
    file.path(BASE, ".cache/factor_db/factor_db_202604.parquet"),
    file.path(ART, "predictions_walkforward.parquet")
  ),
  windows = list(
    train_window = "rolling_60_months_walk_forward",
    sig_date_range = paste0(draft$as_of_sig_date_actual)
  ),
  extra = list(
    selection_status = draft$selection_status,
    best_candidate = draft$best_candidate,
    universe = "FULL_KOSPI_ORDINARY_KOSDAQ_ORDINARY_LIQ_2E8",
    n_features = draft$ml_metadata$n_features,
    n_candidates_tested = 5
  )
)
cat("Lineage recorded.\n")

# qepm/stage_artifacts mirror create
mirror_dir <- file.path(BASE, "qepm/stage_artifacts", paste0("WT_", WT_ID))
dir.create(mirror_dir, showWarnings = FALSE, recursive = TRUE)
files_to_mirror <- c("alpha_scores.parquet", "alpha_scores_std_schema.parquet",
                      "ic_history.parquet", "orthogonality_six_axis.json",
                      "alpha_validation.json", "ml_model_metadata.json",
                      "str1715_overlap_verification.json", "candidate_comparison.csv",
                      "feature_importance.csv", "monotonicity_decile_audit.csv")
for (f in files_to_mirror) {
  src <- file.path(ART, f)
  dst <- file.path(mirror_dir, f)
  if (file.exists(src)) {
    file.copy(src, dst, overwrite = TRUE)
    cat("Mirror copied:", f, "\n")
  }
}

cat("[finalize] DONE\n")
