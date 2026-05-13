#==============================================================================
# WT-D20260512_003 Optimizer Step 7 — Post-Codex Finalize
#
# Inputs:
#   - optimization_package_draft.json
#   - codex_critic_response_optimizer.json (after Codex Round)
#   - optimizer_challenge_note.md (updated with Codex disposition)
#
# Output:
#   - optimization_package.json (final, no _draft suffix)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(digest); library(arrow)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step7] Post-Codex Finalize\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
mailbox <- file.path("qepm/mailbox/worktask", WT)
stage <- file.path("stage_artifacts", "WT_D20260512_003")

# Load draft
draft <- fromJSON(file.path(mailbox, "optimization_package_draft.json"),
                   simplifyVector = FALSE)

# Load Codex response
codex_path <- file.path(mailbox, "codex_critic_response_optimizer.json")
if (!file.exists(codex_path)) {
  stop(sprintf("[FAIL] Codex critic response not yet available: %s", codex_path))
}
codex <- fromJSON(codex_path, simplifyVector = FALSE)
cat(sprintf("Codex stance: %s | veto: %s | concerns: %d\n",
            codex$stance,
            codex$veto_flag,
            length(codex$critical_concerns)))

# Merge Codex into final package
draft$codex_round_summary <- list(
  stance = codex$stance,
  veto_flag = codex$veto_flag,
  total_concerns = length(codex$critical_concerns),
  weakest_assumption = codex$weakest_assumption,
  codex_response_path = codex_path,
  codex_response_sha256 = digest(file = codex_path, algo = "sha256"),
  challenge_note_path = file.path(mailbox, "optimizer_challenge_note.md")
)

# Severity counts
sev_counts <- table(sapply(codex$critical_concerns, function(c) c$severity %||% "MEDIUM"))
draft$codex_round_summary$severity_counts <- as.list(sev_counts)

# Mailbox final emit
final_path <- file.path(mailbox, "optimization_package.json")
write_json(draft, final_path, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

cat(sprintf("\n[Saved] %s\n", final_path))
cat(sprintf("SHA256: %s\n", digest(file = final_path, algo = "sha256")))

# Governance log
gov_path <- file.path(mailbox, "governance_log.json")
gov <- fromJSON(gov_path, simplifyVector = FALSE)
gov$events <- c(gov$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent = "optimizer",
  action = "OPTIMIZATION_PACKAGE_FINALIZED",
  summary = sprintf("method=%s | SR_net=%.4f | n_weights=%d | Codex stance=%s",
                     draft$method_selected,
                     draft$expected_information_ratio,
                     length(draft$target_weights),
                     codex$stance),
  codex_stance = codex$stance,
  codex_concerns_count = length(codex$critical_concerns),
  sha256 = digest(file = final_path, algo = "sha256")
)))
write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat(sprintf("[governance_log] %s updated\n", gov_path))

cat("[OPT-Step7] DONE\n")

`%||%` <- function(a, b) if (!is.null(a)) a else b
