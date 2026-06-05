## ============================================================
## WT-D20260527_001 — Build FINAL alpha_package.json
## (no _draft suffix; requires _draft + codex_critic_response_alpha both existed)
##
## Adds:
##   - codex_critic_round: stance, weakest_assumption, resolution_method, agent_response
##   - qlead_resolution.status: AUTO_SELF_REBUT (per Charter §8 No Silent Override + .claude/rules/codex-round.md)
##   - challenge_note_ref: challenge_note.md path
##   - generated_at: now
##   - forward_to: risk-research
## ============================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(digest)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

WT_ID  <- "WT-D20260527_001"
WT_DIR <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)

draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
codex_path <- file.path(WT_DIR, "codex_critic_response_alpha.json")
challenge_note <- file.path(WT_DIR, "challenge_note.md")
final_path <- file.path(WT_DIR, "alpha_package.json")

stopifnot(file.exists(draft_path), file.exists(codex_path), file.exists(challenge_note))

draft <- fromJSON(draft_path, simplifyVector = FALSE)
codex <- fromJSON(codex_path, simplifyVector = FALSE)

# Merge codex resolution into final
draft$codex_critic_round <- list(
  stance = codex$stance,                # REJECT
  rationale = codex$stance_rationale,
  weakest_assumption = codex$weakest_assumption,
  critical_concerns_count = length(codex$critical_concerns),
  high_severity_count = sum(sapply(codex$critical_concerns, function(c) c$severity == "HIGH")),
  resolution_method = "agent_iter5_iter6_iter7_post_codex_fixes",
  resolution_summary = "5 ACCEPT (C1 P3 not used / C2 DB monthly IC pooled / C3 AX-007 unresolved / C5 PIT t-1 / C7 challenge_note absent) + 1 PARTIAL (C6 FF5 spec table) + 1 REBUTTAL (C4 monotonicity vs role gate — STR_1715 precedent 0.44, DCA 0.50, Charter graduation_criteria has no monotonicity threshold)",
  challenge_note_path = file.path("qepm/mailbox/worktask", WT_ID, "challenge_note.md"),
  ax_008_status = "in_progress",
  ax_008_sources_reviewed = c("codex"),
  ax_008_sources_pending = c("forge", "architect_optional"),
  resolved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

draft$qlead_resolution <- list(
  status = "AUTO_SELF_REBUT",
  note = "Agent autonomously rebutted Codex REJECT via Iter5-7 fixes + documented challenge_note.md. Q-Lead manual review optional but not triggered by automatic escalation criteria (5 HIGH concerns either ACCEPT or evidence-backed REBUTTAL/PARTIAL).",
  reviewed_at = NA
)

draft$forward_to <- "risk-research"
draft$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
draft$reproduction_command <- paste0(
  "cd /mnt/c/Users/User/OneDrive/바탕\\ 화면/Quant_Module_Moltbot && ",
  "Rscript qepm/mailbox/worktask/", WT_ID, "/alpha_pipeline.R && ",
  "Rscript qepm/mailbox/worktask/", WT_ID, "/finalize_alpha_package.R && ",
  "Rscript qepm/mailbox/worktask/", WT_ID, "/build_final_package.R"
)

# Write final
write_json(draft, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")
cat(sprintf("[OK] FINAL alpha_package.json written: %s\n", final_path))
cat(sprintf("     File size: %.1f KB\n", file.size(final_path) / 1024))

# Record final lineage
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "DCA_v7_4family_static_EW_P3P4_confidence (post-Codex REJECT fixes)",
  input_file_paths = c(
    "04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet",
    "04_Research/decision_framework/bearish_forecast_v3/03_models/p4_ecdf_final/all_predictions_extended.parquet",
    ".cache/rawdata.parquet",
    ".cache/factor_db/build_hash.txt",
    "qepm/mailbox/worktask/WT-D20260527_001/alpha_package_draft.json",
    "qepm/mailbox/worktask/WT-D20260527_001/codex_critic_response_alpha.json",
    "qepm/mailbox/worktask/WT-D20260527_001/challenge_note.md"
  ),
  windows = list(
    train = c("2013-01-01", "2018-12-31"),
    validation = c("2019-01-01", "2023-12-31"),
    lockbox = c("2024-01-01", "2026-04-30")
  ),
  random_seed = NULL,
  extra = list(
    iter = "7",
    codex_round = "REJECT_with_documented_resolution",
    graduation_criteria_pass_count = 5L,
    graduation_criteria_total = 5L
  )
)
cat("[OK] artifact_lineage.json appended (final alpha_package).\n")
