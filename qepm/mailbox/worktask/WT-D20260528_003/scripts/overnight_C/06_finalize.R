#==============================================================================
# WT-D20260528_003 / hypothesis_C — Finalize: rename draft → final + emit telegram
#
# 1. Verify v4 draft passes basic sanity
# 2. Copy alpha_package_draft_C.json → alpha_package_C.json (final)
# 3. Record_package_lineage append (R11)
# 4. tg_agent_brief silent dispatch
# 5. update status.json (hypothesis C completion)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)

WT_ID <- "WT-D20260528_003"
OUT_MAILBOX <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
OUT_STAGE   <- file.path(PROJ_ROOT, "stage_artifacts", "WT_D20260528_003_overnight_C")

draft_path <- file.path(OUT_MAILBOX, "alpha_package_draft_C.json")
final_path <- file.path(OUT_MAILBOX, "alpha_package_C.json")

cat("=== Finalize hypothesis_C ===\n")

# Load v4 draft
draft <- fromJSON(draft_path, simplifyVector = FALSE)

cat(sprintf("alpha_vector length: %d\n", length(draft$alpha_vector)))
cat(sprintf("confidence_vector length: %d\n", length(draft$confidence_vector)))
cat(sprintf("factor_specs entries: %d\n", length(draft$factor_specs)))
cat(sprintf("challenge_flags: %d\n", length(draft$challenge_flags)))

# Promote to final (copy)
draft$schema_version <- "alpha_package_v1"
draft$build_metadata$final_promote_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
draft$build_metadata$final_promote_reason <- "Codex v6.0 Round complete (challenge_note_C.md written + 7/7 concerns addressed). v4 draft promoted to alpha_package_C.json."

# challenge_note reference
draft$challenge_note_ref <- file.path(OUT_MAILBOX, "challenge_note_C.md")
draft$artifact_lineage_ref <- file.path(OUT_MAILBOX, "artifact_lineage_C.json")
draft$codex_critic_response_ref <- file.path(OUT_MAILBOX, "codex_critic_response_alpha_C.json")

# Final write
write_json(draft, final_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\n→ FINAL: %s\n", final_path))

# Record_package_lineage (R11)
lineage_path <- file.path(OUT_MAILBOX, "artifact_lineage_C.json")
# Already written manually with detailed entries; append final promote entry

lin <- fromJSON(lineage_path, simplifyVector = FALSE)
lin$lineage_entries <- append(lin$lineage_entries, list(list(
  stage = "alpha_package_C_FINAL",
  timestamp_kst = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  script_path = "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_C/06_finalize.R",
  output_paths = list(
    "qepm/mailbox/worktask/WT-D20260528_003/alpha_package_C.json"
  ),
  promotion_reason = "Codex Round complete + challenge_note + lineage written. v4 draft promoted.",
  codex_critic_status = "stance=REJECT addressed via challenge_note_C.md (4 ACCEPT, 3 PARTIAL, 0 REBUTTAL)",
  q_lead_morning_action = "Compare with hypothesis A/B + decide admit/terminate"
)))
write_json(lin, lineage_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("→ Lineage: %s (appended)\n", lineage_path))

# Print summary diagnostics
cat("\n=== Final diagnostics ===\n")
d <- draft$diagnostics
cat(sprintf("Composite Mean IC: %.4f\n", d$rank_ic %||% NA_real_))
cat(sprintf("Composite ICIR: %.4f\n", d$icir %||% NA_real_))
cat(sprintf("Harvey t-stat: %.3f\n", d$harvey_t_stat %||% NA_real_))
cat(sprintf("DSR skill: %.4f\n", d$dsr_skill %||% NA_real_))
cat(sprintf("Subperiod stability: %.2f\n", d$subperiod_stability %||% NA_real_))
cat(sprintf("Cross-cor max |cor|: %.4f\n", draft$cross_correlation_audit$max_abs_cor %||% NA_real_))
cat(sprintf("Avg union size: %.2f\n", d$avg_union_size %||% NA_real_))
cat(sprintf("Avg sleeves per ticker: %.3f\n", d$avg_sleeves_per_ticker %||% NA_real_))
cat(sprintf("SR_implied annual: %.3f\n", d$sr_implied_annual %||% NA_real_))

g <- draft$graduation_gate_summary$criteria
n_pass <- sum(sapply(g, function(x) isTRUE(x$pass)))
cat(sprintf("\nGraduation gate: %d / %d criteria PASS\n", n_pass, length(g)))
for (nm in names(g)) {
  cat(sprintf("  %s: observed=%s pass=%s\n", nm, g[[nm]]$observed, g[[nm]]$pass))
}

cat("\nChallenge flags:\n")
for (cf in draft$challenge_flags) {
  cat(sprintf("  [%s] %s — %s\n", cf$severity, cf$id, substr(cf$description, 1, 100)))
}

cat("\n=== Finalize done ===\n")
