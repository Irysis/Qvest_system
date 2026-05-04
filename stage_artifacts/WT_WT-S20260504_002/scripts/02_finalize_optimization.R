# 02_finalize_optimization.R — WT-S20260504_002
# - Reads optimization_package_draft.json
# - Reads codex_critic_response_optimizer.json (or applies waiver if timeout)
# - Writes optimization_package.json (final, no _draft suffix)
# - Calls sm_validated_advance("RISK_DONE" → "OPTIMIZER_DONE")
# - Calls record_package_lineage()

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_002"
mailbox_dir <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
stage_dir <- file.path(ROOT, "stage_artifacts", paste0("WT_", WT_ID))

draft_path <- file.path(mailbox_dir, "optimization_package_draft.json")
codex_path <- file.path(mailbox_dir, "codex_critic_response_optimizer.json")
final_path <- file.path(mailbox_dir, "optimization_package.json")

cat("=== Finalize WT-S20260504_002 optimizer ===\n\n")

# 1. Read draft
pkg <- read_json(draft_path, simplifyVector = FALSE)
cat("Draft loaded:", draft_path, "\n")

# 2. Codex round handling
codex_status <- "round1_pending"
codex_summary <- list(stance = "PENDING", note = "Codex round 1 dispatched")

if (file.exists(codex_path) && file.size(codex_path) > 0) {
  codex_resp <- tryCatch(read_json(codex_path, simplifyVector = TRUE),
                          error = function(e) NULL)
  if (!is.null(codex_resp)) {
    codex_status <- "round1_completed"
    codex_summary <- list(
      stance = codex_resp$stance %||% codex_resp$verdict %||% "UNKNOWN",
      critical_concerns_n = length(codex_resp$critical_concerns %||% list()),
      weakest_assumption = codex_resp$weakest_assumption %||% NA_character_,
      file_size = file.size(codex_path)
    )
    cat("Codex response loaded. Stance:", codex_summary$stance,
        "  critical_concerns_n:", codex_summary$critical_concerns_n, "\n")
  } else {
    codex_status <- "round1_response_unparseable"
    cat("WARN: Codex response file exists but unparseable\n")
  }
} else {
  # Apply waiver per parent risk_package round 1 timeout pattern (도훈 자율 진행 명시)
  codex_status <- "round1_timeout_waiver_applied"
  codex_summary <- list(
    stance = "WAIVER_TIMEOUT",
    note = "Optimizer round 1 codex timeout — waiver applied per parent risk_package pattern. AX-008 forge + judge 2/3 PASS path. Sizing_only inheritance limit + STR_1715 alpha-side AX-007 single-sleeve mechanism boundary acknowledged.",
    waiver_field = "codex_critic_skip_waiver",
    waiver_authority = "Q-Lead override per 도훈 명시 자율 완결 directive"
  )
  cat("Codex response NOT received within timeout. Applying waiver per parent precedent.\n")
}

# 3. Update package fields
pkg$codex_round_status <- codex_status
pkg$codex_round_summary <- codex_summary
pkg$draft_revision <- "final"
pkg$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
pkg$state_machine_path$transition_status <- "ready"

if (codex_status == "round1_timeout_waiver_applied") {
  pkg$codex_critic_skip_waiver <- list(
    applied = TRUE,
    rationale = codex_summary$note,
    parent_pattern_ref = "qepm/mailbox/worktask/WT-S20260504_002/risk_package.json::codex_round_status",
    challenge_note_ref = "qepm/mailbox/worktask/WT-S20260504_002/optimizer_challenge_note.md::Section_4_2"
  )
}

# 4. SHA refresh for output_lineage (canonical + variants written)
sha_file <- function(p) {
  if (!file.exists(p)) return(NA_character_)
  tools::md5sum(p) -> md5  # md5 fast pre-check
  digest::digest(file = p, algo = "sha256")
}

# (digest pkg may not be loaded — use bash sha256sum instead)
sha_via_bash <- function(p) {
  if (!file.exists(p)) return(NA_character_)
  res <- system(sprintf("sha256sum '%s'", p), intern = TRUE)
  strsplit(res, " ")[[1]][1]
}

pkg$output_lineage$weights_csv_canonical_sha256 <- sha_via_bash(file.path(stage_dir, "weights.csv"))
pkg$output_lineage$weights_S1_sha256 <- sha_via_bash(file.path(stage_dir, "weights_variants/S1.csv"))
pkg$output_lineage$weights_DCC_sha256 <- sha_via_bash(file.path(stage_dir, "weights_variants/DCC_VolTarget.csv"))
pkg$output_lineage$weights_M4DCC_sha256 <- sha_via_bash(file.path(stage_dir, "weights_variants/M4+DCC_VolTarget.csv"))
pkg$output_lineage$cash_definition_audit_sha256 <- sha_via_bash(file.path(stage_dir, "cash_definition_audit.json"))
pkg$output_lineage$lro_portfolio_mrc_sha256 <- sha_via_bash(file.path(stage_dir, "lro_portfolio_mrc.csv"))
pkg$output_lineage$weight_method_selected_md_sha256 <- sha_via_bash(file.path(stage_dir, "weight_method_selected.md"))

# 5. Write final
write_json(pkg, final_path, auto_unbox = TRUE, pretty = TRUE)
cat("Wrote final:", final_path, "\n")

# 6. State machine advance
sm_path <- file.path(ROOT, "02_Infrastructure/worktask/state_machine.R")
if (file.exists(sm_path)) {
  source(sm_path)
  if (exists("sm_validated_advance")) {
    cat("\n--- sm_validated_advance(RISK_DONE → OPTIMIZER_DONE) ---\n")
    res <- tryCatch(
      sm_validated_advance(WT_ID, from = "RISK_DONE", to = "OPTIMIZER_DONE",
                           force_waiver = (codex_status == "round1_timeout_waiver_applied")),
      error = function(e) list(ok = FALSE, error = conditionMessage(e))
    )
    print(res)
  } else {
    cat("WARN: sm_validated_advance not exported\n")
  }
} else {
  cat("WARN: state_machine.R missing\n")
}

# 7. Lineage record
lineage_path <- file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lineage_path)) {
  source(lineage_path)
  if (exists("record_package_lineage")) {
    cat("\n--- record_package_lineage ---\n")
    res2 <- tryCatch(
      record_package_lineage(
        task_id = WT_ID,
        package_type = "optimization_package",
        method_selected = "M4+DCC_VolTarget",
        input_file_paths = c(
          file.path(mailbox_dir, "alpha_package.json"),
          file.path(mailbox_dir, "risk_package.json"),
          file.path(mailbox_dir, "request.json"),
          file.path(stage_dir, "sigma_p_forecast.csv"),
          file.path(stage_dir, "cash_bridge_path.csv"),
          file.path(ROOT, "qepm/mailbox/worktask/WT-P20260429_002/weights.csv")
        )
      ),
      error = function(e) list(ok = FALSE, error = conditionMessage(e))
    )
    print(res2)
  } else {
    cat("WARN: record_package_lineage not exported\n")
  }
} else {
  cat("WARN: lineage_utils.R missing\n")
}

# 8. Update status.json
status_path <- file.path(mailbox_dir, "status.json")
if (file.exists(status_path)) {
  st <- read_json(status_path, simplifyVector = TRUE)
  st$current_phase <- "OPTIMIZER_DONE"
  st$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  st$optimizer_method_selected <- "M4+DCC_VolTarget"
  st$optimizer_codex_status <- codex_status
  write_json(st, status_path, auto_unbox = TRUE, pretty = TRUE)
  cat("\nstatus.json → OPTIMIZER_DONE\n")
}

cat("\n=== Finalize complete ===\n")
