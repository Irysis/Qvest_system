# ============================================================================
# WT-D20260501_003 — finalize alpha_package.json + lineage
# ============================================================================
# After codex critic round + challenge_note.md, copy/transform draft into
# final alpha_package.json. Process codex concerns systematically.
# ============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260501_003"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)

cat("\n=== Finalize alpha_package.json — WT-D20260501_003 ===\n")
cat("Time:", as.character(Sys.time()), "\n\n")

draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"),
                  simplifyVector = FALSE)

# Load codex critic response
codex_path <- file.path(WT_DIR, "codex_critic_response_alpha.json")
if (file.exists(codex_path)) {
  codex <- fromJSON(codex_path, simplifyVector = FALSE)
  cat("Codex stance:", codex$stance, "\n")
  cat("Codex concerns count:", length(codex$critical_concerns), "\n")
} else {
  codex <- NULL
  cat("WARNING: codex_critic_response_alpha.json missing — finalize without codex round (review needed).\n")
}

# Final package = draft + codex_round attestation
final <- draft

# Add codex_round disposition
if (!is.null(codex)) {
  final$codex_round <- list(
    stance = codex$stance,
    veto_flag = codex$veto_flag %||% FALSE,
    weakest_assumption = codex$weakest_assumption %||% NA,
    critical_concerns_count = length(codex$critical_concerns),
    challenge_note_path = "challenge_note.md",
    response_path = "codex_critic_response_alpha.json"
  )
} else {
  final$codex_round <- list(
    stance = "PENDING",
    note = "Codex critic round not yet completed — finalize in absence."
  )
}

# Lifecycle update
final$lifecycle_label <- "discovery_v1_bayesian_factor_design_finalized"
final$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# Write final
write_json(final, file.path(WT_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, force = TRUE, na = "null")
cat("\nWrote alpha_package.json\n")

# Lineage
lineage_util_path <- file.path(PROJ_ROOT,
  "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lineage_util_path)) {
  source(lineage_util_path)
  if (exists("record_package_lineage")) {
    tryCatch({
      record_package_lineage(
        task_id = WT_ID,
        package_type = "alpha_package",
        method_selected = sprintf(
          "3-Pillar Bayesian (BHEQ + BOCPD + BSIC); main_composite=%s; ICIR=%.4f",
          draft$composite_vs_best_single$main_choice,
          draft$composite_vs_best_single$main_icir),
        input_file_paths = c(
          file.path(PROJ_ROOT, "qepm/stage_artifacts/WT_D20260501_003/alpha_scores.parquet"),
          file.path(PROJ_ROOT, "qepm/stage_artifacts/WT_D20260501_003/alpha_validation.json"),
          file.path(PROJ_ROOT, ".cache/factor_db/factor_ic_monthly.parquet"),
          file.path(PROJ_ROOT, ".cache/rawdata.parquet"))
      )
      cat("Lineage recorded.\n")
    }, error = function(e) cat("Lineage WARN:", e$message, "\n"))
  }
}

# helper for null-coalesce
`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1 && is.na(x))) y else x

cat("\n=== Final package ready ===\n")
cat("Path:", file.path(WT_DIR, "alpha_package.json"), "\n")
cat("Time:", as.character(Sys.time()), "\n\n")
