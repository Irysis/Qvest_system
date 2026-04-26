# =============================================================================
# WT-D20260426_006 — Finalize alpha_package.json (after Codex round)
# =============================================================================
# 순서: alpha_package_draft.json → Codex round → finalize alpha_package.json
#       → record_package_lineage (L-194 fix 순서)
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(digest); library(arrow); library(data.table)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260426_006"
WT_DIR_TAG   <- "WT_D20260426_006"
WT_MAIL_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_DIR_TAG)
DRAFT_PATH   <- file.path(WT_MAIL_DIR, "alpha_package_draft.json")
FINAL_PATH   <- file.path(WT_MAIL_DIR, "alpha_package.json")
CODEX_PATH   <- file.path(WT_MAIL_DIR, "codex_critic_response_alpha.json")

setwd(PROJECT_ROOT)

cat("=== Finalize Alpha Package (post-Codex) ===\n")
cat("WT:", WT_ID, "\n")

stopifnot(file.exists(DRAFT_PATH))
draft <- fromJSON(DRAFT_PATH, simplifyVector = FALSE)

# Codex response 통합
if (file.exists(CODEX_PATH)) {
  codex <- tryCatch(fromJSON(CODEX_PATH, simplifyVector = FALSE),
                    error = function(e) NULL)
  if (!is.null(codex)) {
    draft$codex_critic_round <- list(
      rounds_executed = codex$rounds_executed %||% 1L,
      final_stance = codex$verdict %||% codex$stance %||% "UNKNOWN",
      weakest_assumption = codex$weakest_assumption %||% "unknown",
      critical_concerns_count = length(codex$critical_concerns %||% list()),
      response_artifact = "codex_critic_response_alpha.json"
    )
    cat("[CODEX] integrated. stance=", draft$codex_critic_round$final_stance, "\n")
  } else {
    cat("[CODEX] response unparseable — proceed with draft\n")
  }
} else {
  cat("[CODEX] response not present — proceed with draft (Codex round optional in Discovery WT)\n")
  draft$codex_critic_round <- list(
    rounds_executed = 0L,
    final_stance = "NOT_RUN",
    note = "Codex round skipped or pending"
  )
}

# Step 1: write final alpha_package.json (L-194 fix: write FIRST)
write_json(draft, FINAL_PATH, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[1] alpha_package.json saved → %s\n", FINAL_PATH))

# Step 2: record lineage (L-194 fix: AFTER write)
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))

input_files <- c(
  file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID, "request.json"),
  file.path(PROJECT_ROOT, ".cache/rawdata.parquet"),
  file.path(PROJECT_ROOT, ".cache/kr_factor_returns_v2.parquet"),
  file.path(ARTIFACT_DIR, "alpha_scores.parquet"),
  file.path(ARTIFACT_DIR, "alpha_validation.json"),
  file.path(WT_MAIL_DIR, "factor_engine_proposal.R"),
  file.path(WT_MAIL_DIR, "alpha_challenge_note.md"),
  file.path(WT_MAIL_DIR, "s0_record.json")
)
input_files <- input_files[file.exists(input_files)]

setwd(PROJECT_ROOT)
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "M06_XGB_LGBM_ensemble (XGBoost 5-seed + LightGBM 3-seed rank-mean) + 309F_NonRE_top40 MI prefilter + KR_FF5_v2_lagged + regime_pct expanding",
  input_file_paths = input_files,
  windows = list(
    train_validation_window = list(start = "2003-01-01", end = "2024-01-22"),
    lockbox_window = list(start = "2024-01-23", end = "2026-01-23", sealed = TRUE)
  ),
  random_seed = 20260426006L,
  extra = list(
    parent_iters = list("STR_1656_MLRA_M05", "STR_1701_WT004_Iter11"),
    iter_name = "STR_1656_M06_PG2_conditional_ML_diversifier"
  )
)

cat("\n=== FINALIZE COMPLETE ===\n")
cat("alpha_package.json:", FINAL_PATH, "\n")
cat("artifact_lineage.json appended.\n")
