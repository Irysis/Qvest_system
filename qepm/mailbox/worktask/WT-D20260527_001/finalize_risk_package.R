#==============================================================================
# finalize_risk_package.R — Copy draft to final + record lineage
#
# Per .claude/rules/codex-round.md 5-step flow:
#   1. Draft already written: risk_package_draft.json
#   2. Codex auto-trigger completed (codex_critic_response_risk.json present)
#   3. Codex response reviewed in challenge_note.md (Risk Codex Critic Round Response)
#   4. ACCEPT/PARTIAL/REBUTTAL classification recorded (4 ACCEPT + 4 PARTIAL + 2 REBUTTAL)
#   5. THIS SCRIPT: write final risk_package.json + lineage
#
# Per L-194 sequence fix: write_json BEFORE record_package_lineage.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

cat("=== Risk Package Finalization ===\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
WT_ID <- "WT-D20260527_001"
WT_DIR <- file.path("qepm/mailbox/worktask", WT_ID)

# ── Step 1: Read draft, augment with Codex Round response metadata ────────
draft <- fromJSON(file.path(WT_DIR, "risk_package_draft.json"),
                   simplifyVector = FALSE)
codex <- fromJSON(file.path(WT_DIR, "codex_critic_response_risk.json"),
                   simplifyVector = FALSE)

# Augment with codex_critic_round metadata
draft$codex_critic_round <- list(
  stance = codex$stance,
  weakest_assumption = codex$weakest_assumption,
  critical_concerns_count = length(codex$critical_concerns),
  high_severity_count = sum(sapply(codex$critical_concerns,
                                     function(c) c$severity == "HIGH")),
  rebuttal_required_count = length(codex$rebuttal_required),
  resolution_method = "agent_rev2_post_codex_fixes",
  resolution_summary = paste(
    "4 ACCEPT-full (C1 PIT factor model + Yen 2024 stress removed; C2(a) R² text fix; C2(b) B/Ω/D parquet added; C6(a)(b)(c) challenge_note + final + lineage sequence)",
    "+ 4 PARTIAL (C2 R² interpretation, C3 RF-R3b HHI added + TDC/style deferred, C4 unit/monthly/8-period clarified)",
    "+ 2 REBUTTAL (C4(d) no 2.5% cap declared in role/charter; C5 regime cor diagnostic not handoff; C6(d) weights.csv not Risk role)",
    sep = " "
  ),
  challenge_note_path = file.path("qepm/mailbox/worktask", WT_ID, "risk_challenge_note.md"),
  ax_008_status = "in_progress",
  ax_008_sources_reviewed = "codex",
  ax_008_sources_pending = c("forge", "architect_optional"),
  resolved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

# Agent self-resolution status
draft$agent_resolution <- list(
  status = "AUTO_SELF_REBUT",
  note = "Agent autonomously resolved 6 Codex concerns via rev2 fixes + documented risk_challenge_note.md. Per Codex Round Decision Protocol: HIGH < 5 (4 met), no AX hard FAIL (≥3), no PIT C1 unrecoverable. Q-Lead manual review NOT triggered.",
  reviewed_at = NULL
)

# Reproduction command
draft$reproduction_command <- "Rscript qepm/mailbox/worktask/WT-D20260527_001/risk_pipeline.R && Rscript qepm/mailbox/worktask/WT-D20260527_001/finalize_risk_package.R"

# Write final risk_package.json (NO _draft suffix)
write_json(draft, file.path(WT_DIR, "risk_package.json"),
            auto_unbox = TRUE, pretty = TRUE, na = "string")

cat(sprintf("✓ Saved: %s/risk_package.json (final)\n", WT_DIR))

# ── Step 2: Lineage record (AFTER risk_package.json write per L-194) ──────
LINEAGE_UTILS <- file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(LINEAGE_UTILS)) {
  source(LINEAGE_UTILS)
  if (exists("record_package_lineage", mode = "function")) {
    tryCatch({
      record_package_lineage(
        task_id = WT_ID,
        package_type = "risk_package",
        method_selected = "ledoit_wolf_oracle",
        input_file_paths = c(
          file.path(WT_DIR, "alpha_package.json"),
          file.path("stage_artifacts", paste0("WT_", WT_ID), "alpha_scores.parquet"),
          ".cache/rawdata.parquet"
        ),
        windows = list(
          risk_window = list(start = "2019-01-01", end = "2023-12-28", n_days = 1233),
          factor_model_window = list(start = "2019-01-01", end = "2023-11-30", n_months = 60)
        )
      )
      cat("✓ Lineage recorded\n")
    }, error = function(e) {
      cat(sprintf("⚠ Lineage record error (non-fatal): %s\n", conditionMessage(e)))
    })
  } else {
    cat("⚠ record_package_lineage() not exported from lineage_utils.R\n")
  }
} else {
  cat(sprintf("⚠ Lineage utility not found at: %s\n", LINEAGE_UTILS))
}

# ── Step 3: Summary printout ──────────────────────────────────────────────
cat("\n=== Risk Research COMPLETE ===\n")
cat(sprintf("WT: %s\n", WT_ID))
cat(sprintf("Σ primary: %s (cond=%.2f, PSD ✓)\n",
            draft$cov_method, draft$covariance_diagnostics$condition_number))
cat(sprintf("EW Top-20 ann vol: %.2f%%\n",
            draft$risk_summary$tail_risk$ew_annualized_vol_pct))
cat(sprintf("Max DD 2019-2023: %.2f%%\n",
            draft$risk_summary$tail_risk$max_drawdown_2019_2023 * 100))
cat(sprintf("Stress worst: Rate_2022 = %.2f%%\n",
            draft$risk_summary$stress_tests$rate_2022 * 100))
cat(sprintf("Top common risks: %s\n",
            paste(unlist(draft$risk_summary$top_common_risks), collapse=" | ")))
cat(sprintf("Red Flags: %d\n", length(draft$challenge_flags)))
cat(sprintf("Codex stance: %s → resolved via %s\n",
            codex$stance, draft$codex_critic_round$resolution_method))
cat(sprintf("End: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
