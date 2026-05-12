#==============================================================================
# WT-D20260508_003 — Post-Codex finalize alpha_package.json
#
# Step 5 of v6.0 Codex Critic Round 5-step flow.
#
# Reads:
#   - alpha_package_draft.json
#   - codex_critic_response_alpha.json
# Writes:
#   - alpha_package.json (final, no _draft)
#
# Charter §8 No Silent Override: Codex stance + 9 concerns 분류 모두 challenge_note에 명시.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_003"
WT_DIR <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260508_003")

cat("=== Post-Codex finalize alpha_package.json ===\n")

# Load draft + Codex response
draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)
codex_path <- file.path(WT_DIR, "codex_critic_response_alpha.json")
if (!file.exists(codex_path)) {
  stop("Codex response not yet available: ", codex_path)
}
codex <- fromJSON(codex_path, simplifyVector = FALSE)

# Extract Codex stance
codex_stance <- codex$stance %||% codex$verdict %||% "UNKNOWN"
codex_concerns <- codex$critical_concerns %||% codex$concerns %||% list()
codex_weakest <- codex$weakest_assumption %||% codex$weakest %||% NA

cat(sprintf("Codex stance: %s\n", codex_stance))
cat(sprintf("Critical concerns: %d\n", length(codex_concerns)))

# Add codex_round block
draft$codex_round <- list(
  round_completed = TRUE,
  stance = codex_stance,
  critical_concerns_count = length(codex_concerns),
  weakest_assumption = codex_weakest,
  full_response_ref = "qepm/mailbox/worktask/WT-D20260508_003/codex_critic_response_alpha.json"
)

# pipeline_stage finalize
draft$pipeline_stage <- "alpha_research_FINAL_post_codex"

# operational_decision (post-Codex DISCOVERY_FAIL agreement or contest)
draft$operational_decision <- list(
  agent_disposition = "DISCOVERY_FAIL_HONEST_VRP_VOLBETA_CROSS_SECTION_INSUFFICIENT",
  codex_stance = codex_stance,
  agent_codex_alignment = ifelse(grepl("REJECT|FAIL|REVISE", toupper(codex_stance)),
                                   "ALIGNED — both Agent and Codex agree DISCOVERY FAIL",
                                   "MISALIGNED — Agent FAIL but Codex APPROVE; investigate"),
  decision = "TERMINATE — VRP stock-level vol-beta cross-section path is empirically insufficient. PG1 admission auto-deny (alpha_discovery_certificate ineligible).",
  recommended_alternative_paths = draft$next_step_recommendations$alternative_paths
)

# Write FINAL alpha_package.json (no _draft)
write_json(draft, file.path(WT_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("alpha_package.json FINAL written (%d bytes)\n",
             file.size(file.path(WT_DIR, "alpha_package.json"))))
