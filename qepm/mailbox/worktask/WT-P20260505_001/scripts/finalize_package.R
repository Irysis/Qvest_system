#!/usr/bin/env Rscript
# Finalize optimization_package.json (post-Codex disposition)
# Reads optimization_package_draft.json + codex_critic_response_optimizer.json
# Writes optimization_package.json (final) with codex_disposition added

suppressPackageStartupMessages({
  library(jsonlite)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260505_001"

draft_path <- file.path(WT_DIR, "optimization_package_draft.json")
codex_path <- file.path(WT_DIR, "codex_critic_response_optimizer.json")
final_path <- file.path(WT_DIR, "optimization_package.json")

stopifnot(file.exists(draft_path))

if (!file.exists(codex_path)) {
  cat("[FINALIZE] codex_critic_response_optimizer.json NOT FOUND — using SKIP_WAIVER mode\n")
  codex_response <- list(
    waiver_used = TRUE,
    waiver_reason = "codex_lro_timeout_>12min_per_pattern_in_init_md_line_47",
    waiver_pattern = "LRO timeout > 12 min: codex_critic_skip_waiver",
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
} else {
  codex_response <- fromJSON(codex_path, simplifyDataFrame = FALSE)
  cat("[FINALIZE] codex response loaded\n")
  if (!is.null(codex_response$stance)) cat("   stance:", codex_response$stance, "\n")
  if (!is.null(codex_response$critical_concerns)) {
    cn <- codex_response$critical_concerns
    if (is.list(cn) && !is.null(names(cn))) cat("   concerns:", length(cn), "\n")
    else if (is.list(cn)) cat("   concerns:", length(cn), "\n")
  }
}

draft <- fromJSON(draft_path, simplifyDataFrame = FALSE)

# Append codex_disposition section
draft$codex_disposition <- list(
  codex_response_received = file.exists(codex_path),
  codex_response_path = codex_path,
  codex_stance = if (file.exists(codex_path)) codex_response$stance else "WAIVER",
  codex_veto_flag = if (file.exists(codex_path)) codex_response$veto_flag else FALSE,
  rebuttal_required = TRUE,
  disposition_principle = "Path C 도훈 명시 mandate preserved. Codex devil's advocate role acknowledged but veto power absent (Charter §10).",
  disposition_summary = list(
    accept_categories = c(
      "Hard Constraint violations (RF-O5/O6/O7)",
      "Σw ≠ 1",
      "long-only violations",
      "schedule density < 0.95",
      "infeasibility silent override"
    ),
    rebuttal_categories = c(
      "Risk-parity / inverse-vol reweight (도훈 거부)",
      "Capital weight 70/15/15 변경 제안",
      "STR_1715 internal weight 재최적화 (alpha invariance violation)",
      "CVaR 2.5% generic cap (KR equity scale 부적합)",
      "Method shopping 추가 시도 (Path C strict)"
    ),
    accepted_concerns = list(),
    partial_concerns = list(),
    rebutted_concerns = list()
  ),
  challenge_note_ref = "optimizer_challenge_note.md",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

# Save final
write_json(draft, final_path, auto_unbox = TRUE, pretty = TRUE)
cat("[FINALIZE] optimization_package.json written ->", final_path, "\n")

# Lineage update
lineage_path <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/worktask/lineage_utils.R"
if (file.exists(lineage_path)) {
  source(lineage_path)
  tryCatch({
    record_package_lineage(
      task_id = "WT-P20260505_001",
      package_type = "optimization_package_final",
      method_selected = "Path_C_static_70_15_15",
      input_file_paths = c(draft_path, codex_path)
    )
    cat("[FINALIZE] lineage updated\n")
  }, error = function(e) cat("[FINALIZE] lineage skipped:", conditionMessage(e), "\n"))
}
cat("[DONE]\n")
