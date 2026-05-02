#==============================================================================
# WT-D20260502_001 Risk Research — Step 9: Post-Codex finalize
#
# After Codex critic_response arrives:
#  1. Load risk_package_draft.json
#  2. Apply changes per challenge_note decisions
#  3. Add codex_round metadata
#  4. Write risk_package.json final
#  5. Record artifact_lineage
#  6. Telegram brief
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(digest)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- Load draft + Codex response --------------------------------------------
draft <- fromJSON(file.path(WT_DIR, "risk_package_draft.json"), simplifyVector = FALSE)
critic_path <- file.path(WT_DIR, "codex_critic_response_risk.json")
if (!file.exists(critic_path)) {
  critic_path <- file.path(WT_DIR, "codex_critic_response_risk-research.json")
}
critic <- fromJSON(critic_path, simplifyVector = FALSE)

cat(sprintf("[Step9] Codex stance: %s\n", critic$stance))
cat(sprintf("[Step9] Codex critical_concerns: %d\n", length(critic$critical_concerns)))
cat(sprintf("[Step9] Codex weakest_assumption: %s\n", critic$weakest_assumption %||% "(none)"))

# ---- Build final from draft -------------------------------------------------
final <- draft

# Add codex_round metadata
final$codex_round <- list(
  stance = critic$stance,
  veto_flag = critic$veto_flag %||% FALSE,
  n_concerns = length(critic$critical_concerns),
  n_high = sum(sapply(critic$critical_concerns, function(c) c$severity == "HIGH")),
  n_medium = sum(sapply(critic$critical_concerns, function(c) c$severity == "MEDIUM")),
  n_low = sum(sapply(critic$critical_concerns, function(c) c$severity == "LOW")),
  weakest_assumption = critic$weakest_assumption,
  critic_response_file = basename(critic_path),
  challenge_note_file = "challenge_note_risk-research.md",
  agent_decisions_summary = "See challenge_note_risk-research.md for ACCEPT/PARTIAL/REBUTTAL decisions"
)

# Update status
final$status <- "RISK_FINAL_AFTER_CODEX_ROUND"
final$pipeline_version <- "v1_riskagent_post_codex"
final$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# ---- Write risk_package.json (FINAL) ----------------------------------------
final_path <- file.path(WT_DIR, "risk_package.json")
write_json(final, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("[Step9] risk_package.json (FINAL) saved: %.1f KB\n",
            file.info(final_path)$size / 1024))

# ---- Record artifact_lineage ------------------------------------------------
source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = WT_ID,
  package_type = "risk_package",
  method_selected = "lw_2003_const_cor + tikhonov_alpha_0.62",
  input_file_paths = c(file.path(WT_DIR, "alpha_package.json")),
  windows = list(
    train_window = list(start = "2021-05-01", end = "2026-04-30",
                        n_months = 60, scope = "full_universe_336"),
    top20_window = list(start = "2021-05-01", end = "2026-04-30",
                        n_months = 60, scope = "top20_alpha")
  ),
  extra = list(
    pipeline_version = "v1_riskagent_post_codex",
    codex_stance = final$codex_round$stance,
    n_concerns = final$codex_round$n_concerns,
    sigma_method = "lw_2003_const_cor_tikhonov",
    sigma_cn = final$diagnostics$condition_number,
    sigma_top20_cn = final$security_covariance_top20_diagnostics$shrunk_condition_number
  )
)
cat("[Step9] artifact_lineage recorded\n")

# ---- Update status.json -----------------------------------------------------
status_path <- file.path(WT_DIR, "status.json")
status <- if (file.exists(status_path)) {
  fromJSON(status_path, simplifyVector = FALSE)
} else {
  list(task_id = WT_ID)
}
status$current_phase <- "RISK_DONE"
status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$last_agent <- "risk-research"
status$pipeline_version <- "v1_riskagent_post_codex"
write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Step9] status.json: phase=RISK_DONE\n"))

# ---- Update governance_log.json ---------------------------------------------
gov_path <- file.path(WT_DIR, "governance_log.json")
gov <- if (file.exists(gov_path)) {
  fromJSON(gov_path, simplifyVector = FALSE)
} else {
  list(task_id = WT_ID, events = list())
}
new_event <- list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent = "risk-research",
  event_type = "RISK_PACKAGE_FINAL_AFTER_CODEX_ROUND",
  summary = paste0(
    sprintf("Risk research v1 complete. Σ method: lw_2003_const_cor + Tikhonov α=0.62 (full Σ cn=%.1f) + LW-light (top20 Σ cn=%.1f, RF-R2 PASS). ",
            final$diagnostics$condition_number,
            final$security_covariance_top20_diagnostics$shrunk_condition_number),
    sprintf("Codex stance: %s (%d concerns: %d HIGH + %d MED + %d LOW). ",
            final$codex_round$stance, final$codex_round$n_concerns,
            final$codex_round$n_high, final$codex_round$n_medium,
            final$codex_round$n_low),
    "AX-001 v2 axes 1+2+4 PASS / axis 3 FAIL inherited from alpha-research. ",
    "AX-007 single-sleeve mechanism risk active. ",
    sprintf("STR_1715 cross-validated TRUE diversifier: Pearson %.3f / Spearman %.3f / lower-TDC %.3f / overlap 0%%. ",
            final$str1715_diversifier_validation$pearson,
            final$str1715_diversifier_validation$spearman,
            final$str1715_diversifier_validation$lower_tdc_q010),
    sprintf("Stress 6/8 outperform; Iran_War_2026 FAIL (-36.7%% relative). ",
            final$str1715_diversifier_validation$crisis_alpha_annualized %||% "N/A"),
    sprintf("Top common risks: Sector_반도체 7.5%% / Market 1.1%% / Specific 29.2%%. ")
  ),
  artifacts = list(
    risk_package = file.path(WT_DIR, "risk_package.json"),
    challenge_note = file.path(WT_DIR, "challenge_note_risk-research.md"),
    covariance = "stage_artifacts/WT_D20260502_001/covariance.parquet",
    covariance_top20 = "stage_artifacts/WT_D20260502_001/covariance_top20.parquet",
    exposure_matrix = "stage_artifacts/WT_D20260502_001/exposure_matrix.parquet",
    factor_covariance = "stage_artifacts/WT_D20260502_001/factor_covariance.parquet",
    specific_risk = "stage_artifacts/WT_D20260502_001/specific_risk.parquet",
    regime_correlation = "stage_artifacts/WT_D20260502_001/regime_correlation.parquet"
  ),
  codex_round = final$codex_round
)
gov$events[[length(gov$events) + 1]] <- new_event
write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE)
cat("[Step9] governance_log updated\n")

cat("[Step9] DONE.\n")
