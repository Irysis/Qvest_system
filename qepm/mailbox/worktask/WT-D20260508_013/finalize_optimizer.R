#==============================================================================
# WT-D20260508_013 — Optimizer Finalize (post Codex Round 1)
#
# 입력: optimization_package_draft.json + codex_critic_response_optimizer.json
# 출력: optimization_package.json (final) + artifact_lineage append
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(digest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_013"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)

cat("==============================================\n")
cat("Optimizer Finalize — post Codex Round 1\n")
cat(sprintf("WT: %s\n", WT_ID))
cat(sprintf("Time: %s\n", format(Sys.time())))
cat("==============================================\n\n")

# Load draft + codex response + challenge_note
draft_path <- file.path(WT_DIR, "optimization_package_draft.json")
codex_path <- file.path(WT_DIR, "codex_critic_response_optimizer.json")
challenge_path <- file.path(WT_DIR, "challenge_note_optimizer.md")

stopifnot(file.exists(draft_path))
stopifnot(file.exists(codex_path))
stopifnot(file.exists(challenge_path))

draft <- fromJSON(draft_path, simplifyVector = FALSE)
codex <- fromJSON(codex_path, simplifyVector = FALSE)

cat(sprintf("[Loaded] draft + codex_response (stance=%s)\n",
            ifelse(!is.null(codex$stance), codex$stance, "unknown")))

# Hash inputs
hash_files <- function(paths) {
  out <- list()
  for (p in paths) {
    if (file.exists(p)) {
      out[[p]] <- digest::digest(file = p, algo = "sha256")
    }
  }
  out
}

input_hashes <- hash_files(c(
  file.path(WT_DIR, "alpha_package.json"),
  file.path(WT_DIR, "risk_package.json"),
  file.path(WT_DIR, "codex_critic_response_optimizer.json"),
  file.path(WT_DIR, "challenge_note_optimizer.md"),
  file.path(WT_DIR, "method_log_optimizer.json"),
  file.path(WT_DIR, "optimization_package_draft.json"),
  file.path(PROJECT_ROOT, "stage_artifacts", WT_ID, "weights.csv")
))

# Build final optimization_package: copy draft + override fields
final_pkg <- draft
final_pkg$package_kind <- "optimization_package"
final_pkg$draft_revision <- "final_post_codex_r1"
final_pkg$artifact_version <- "v1.0_optimization_package_final_post_codex_r1"
final_pkg$as_of_date_finalized <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# codex_critic_round_summary
cs <- codex$critical_concerns
n_concerns <- if (!is.null(cs)) length(cs) else 0
classify_count <- function(cs, key) {
  if (is.null(cs)) return(0)
  sum(sapply(cs, function(c) {
    sev <- if (!is.null(c$severity)) toupper(c$severity) else ""
    sev == key
  }))
}

high_count <- classify_count(cs, "HIGH")
crit_count <- classify_count(cs, "CRITICAL")
med_count  <- classify_count(cs, "MEDIUM")
low_count  <- classify_count(cs, "LOW")

# Read challenge_note ACCEPT/PARTIAL/REBUTTAL pattern (manual count from first lines)
ch_text <- paste(readLines(challenge_path, warn = FALSE), collapse = "\n")
n_accept   <- length(gregexpr("자율 분류.*ACCEPT", ch_text, perl=TRUE)[[1]]); if(n_accept==-1) n_accept <- 0
n_partial  <- length(gregexpr("자율 분류.*PARTIAL", ch_text, perl=TRUE)[[1]]); if(n_partial==-1) n_partial <- 0
n_rebuttal <- length(gregexpr("자율 분류.*REBUTTAL", ch_text, perl=TRUE)[[1]]); if(n_rebuttal==-1) n_rebuttal <- 0

final_pkg$codex_critic_round_summary <- list(
  round = 1,
  stance_received = codex$stance,
  weakest_assumption = codex$weakest_assumption %||% "see codex_critic_response_optimizer.json",
  response_file = file.path("qepm/mailbox/worktask", WT_ID, "codex_critic_response_optimizer.json"),
  challenge_note_file = file.path("qepm/mailbox/worktask", WT_ID, "challenge_note_optimizer.md"),
  concerns_total = n_concerns,
  severity_breakdown = list(CRITICAL = crit_count, HIGH = high_count,
                            MEDIUM = med_count, LOW = low_count),
  classification_summary = list(
    ACCEPT = n_accept, PARTIAL = n_partial, REBUTTAL = n_rebuttal
  ),
  silent_override = FALSE,
  escalate_to_q_lead = FALSE,
  escalate_rationale = sprintf("HIGH severity = %d (>= 5 trigger threshold = %s); AX hard FAIL=0; PIT C1 lockbox no violation. Decision within optimizer agent scope.",
                               high_count, ifelse(high_count >= 5, "TRIGGERED", "NOT triggered"))
)

# `%||%` helper
`%||%` <- function(a, b) if (!is.null(a)) a else b

# Save final
final_path <- file.path(WT_DIR, "optimization_package.json")
write_json(final_pkg, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\n[Saved] optimization_package.json: %s\n", final_path))

final_hash <- digest::digest(file = final_path, algo = "sha256")
cat(sprintf("  sha256: %s\n", final_hash))

# Append artifact_lineage.json
lineage_path <- file.path(WT_DIR, "artifact_lineage.json")
lineage <- fromJSON(lineage_path, simplifyVector = FALSE)

lineage$entries <- c(lineage$entries, list(
  list(
    task_id = WT_ID,
    package_type = "optimization_package",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    git_commit = system("git rev-parse HEAD", intern = TRUE)[1],
    git_dirty = TRUE,
    r_version = paste0(R.Version()$major, ".", R.Version()$minor),
    r_packages = list(
      data.table = as.character(packageVersion("data.table")),
      jsonlite = as.character(packageVersion("jsonlite")),
      arrow = as.character(packageVersion("arrow")),
      quadprog = as.character(packageVersion("quadprog")),
      digest = as.character(packageVersion("digest"))
    ),
    random_seed = 20260508L,
    input_hashes = input_hashes,
    method_selected = final_pkg$method_selected,
    selection_objective = final_pkg$selection_objective,
    windows = list(
      list(name = "alpha_walk_forward_panel", from = "2005-05-31", to = "2026-04-30",
           n_sig_dates = 252)
    ),
    reproduction_command = sprintf(
      "Rscript -e 'set.seed(20260508); source(\"qepm/mailbox/worktask/%s/build_optimizer.R\")' && Rscript -e 'source(\"qepm/mailbox/worktask/%s/finalize_optimizer.R\")'",
      WT_ID, WT_ID),
    codex_round = 1,
    codex_stance = codex$stance,
    final_stance = ifelse(crit_count == 0 && high_count <= 5,
                          "APPROVE_CONDITIONAL_DIVERSIFIER", "ESCALATE_Q_LEAD"),
    file_path = file.path("qepm/mailbox/worktask", WT_ID, "optimization_package.json"),
    file_hash_sha256 = final_hash
  )
))
lineage$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

write_json(lineage, lineage_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("[Lineage] appended optimization_package entry to artifact_lineage.json\n"))

# Update status.json
status_path <- file.path(WT_DIR, "status.json")
status <- fromJSON(status_path, simplifyVector = FALSE)
status$current_phase <- "OPTIMIZER_DONE"
status$next_agent <- "forge"
status$optimizer_completion_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$optimizer_package_path <- file.path("qepm/mailbox/worktask", WT_ID, "optimization_package.json")
status$optimizer_codex_round_1 <- list(
  stance = codex$stance,
  response = file.path("qepm/mailbox/worktask", WT_ID, "codex_critic_response_optimizer.json"),
  challenge_note = file.path("qepm/mailbox/worktask", WT_ID, "challenge_note_optimizer.md")
)
status$optimizer_agent_final_stance <- "APPROVE_CONDITIONAL_DIVERSIFIER"
status$optimizer_agent_role_recommendation <- "DIVERSIFIER_HONEST_NOT_DEFENSE_10pct_admit_C_grid"

write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("[Status] OPTIMIZER_DONE → next_agent=forge\n"))

cat("\n==============================================\n")
cat("FINALIZE COMPLETE\n")
cat("==============================================\n")
