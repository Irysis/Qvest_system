# ============================================================================
# Finalize alpha_package.json — v6.3.3 PreToolUse hook 통과 의무
# ============================================================================
# Inputs:
#   - alpha_package_draft.json (write 1차)
#   - codex_critic_response_alpha.json (REJECT 9 concerns)
#   - challenge_note.md (ACCEPT/PARTIAL/REBUTTAL 분류 처리)
# Output:
#   - alpha_package.json (final)
#   - artifact_lineage.json (R11 의무)
# ============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(digest)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260501_002"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
setwd(PROJ_ROOT)

# Load draft
pk <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"),
                simplifyVector = FALSE)

# Load codex critique
codex <- fromJSON(file.path(WT_DIR, "codex_critic_response_alpha.json"),
                   simplifyVector = FALSE)

# ---- Apply corrections per challenge_note.md ----

# C3 fix: signed theta caveat in pit_attestation
pk$pit_attestation$c13_z_score_aligned <- "CONDITIONAL — Z_Score_Aligned only (no manual sign flip), but signed walking-forward rolling theta preserves direction. theta_history.parquet has 470 negative theta rows (codex-verified). Charter §3 review pending: signed data-driven theta vs C13 manual flip equivalence. See challenge_note.md C3."

pk$pit_attestation$c13_signed_theta_caveat <- list(
  rolling_theta_method = "signed mean_ic (preserve sign), Bayesian shrinkage N/(N+12), L1-normalized",
  negative_theta_rows  = 470L,
  rationale            = "Universe-restricted (top-500 PIT liquidity) walking-forward IC sign may differ from full-universe expanding-window IC sign embedded in Z_Score_Aligned. Signed theta is data-driven, NOT manual.",
  codex_objection      = "470 negative theta rows + reverse direction is functionally equivalent to sign flip. PIT-C13 gray zone."
)

pk$pit_attestation$c15_factor_db_load <- "PARTIAL — load_month_factors() is exclusive entry for factor Z_Score_Aligned, BUT theta construction directly reads .cache/factor_db/factor_ic_monthly.parquet (codex-verified). Charter §3 c15 strict interpretation: FAIL. See challenge_note.md C3."

# C5 fix: liquidity_mandate_conflict
pk$liquidity_mandate_conflict <- list(
  request_floor_won_20d_avg   = 5e7,
  system_mandate_floor        = 2e8,
  mandate_violation           = TRUE,
  codex_historical_check      = list(
    dates_below_1e8           = 52L,
    dates_below_2e8           = 98L,
    total_dates               = 219L
  ),
  resolution                  = "request.json drives alpha; mandate enforcement deferred to Q-Lead. abort recommendation."
)

# C6 fix: ax_007 requires_downstream_proof
pk$ax_007_avoidance_strategy$requires_downstream_proof    <- TRUE
pk$ax_007_avoidance_strategy$alpha_vector_density_alone_insufficient <- TRUE
pk$ax_007_avoidance_strategy$satisfies_ax_007             <- "DEFERRED — alpha-vector breadth is necessary not sufficient. AX-007 4-exception proof must be at portfolio construction (Optimizer). Alpha hands off `ax_007_required = TRUE` flag only."

# C4 fix: RF-A3 challenge_flag 추가
recent3y_overfit <- list(
  id           = "ALPHA_CF_05_RF_A3_RECENT_OVERFIT",
  severity     = "MEDIUM",
  description  = "last36-month ICIR=0.3055 / full ICIR=0.1999 ratio=1.528 > 1.5 RF-A3 threshold (codex-verified). Recent 3-year regime ICIR materially above full-period — overfit suspicion.",
  honesty_note = "Not concealed. Reported as-is."
)
pk$challenge_flags <- c(pk$challenge_flags, list(recent3y_overfit))

# C2 fix: composite_vs_best_single recommendation
pk$composite_vs_best_single$recommendation <- "Composite FAILS RF-A2. Recommend ABORT this composite design. Pivot to D43_Skewness single-factor discovery WT (ICIR 0.2723, t-naive 4.04, mean_ic 0.0258)."

# C1 fix: graduation_criteria_check final
pk$graduation_criteria_check$graduation_recommendation <- "ABORT_HONEST_ALPHA_NOT_FOUND — 5/6 hard gates fail (rank_IC, ICIR, Harvey, DSR, monotonicity), composite < best single (RF-A2), C13 signed theta gray zone, AX-007 deferred, liquidity mandate conflict, RF-A3 recent overfit, RF-A4 sector-neutral untested. Codex REJECT (9 concerns, 6 HIGH, ax_008_status FAIL). Q-Lead auto-escalate triggered."

# C8 fix: rf_a4_sector_neutral_status
pk$diagnostics$rf_a4_sector_neutral_status <- "UNTESTED — rawdata.parquet.Sector available but neutralization not applied. Mutation candidate for follow-up WT."

# C9 fix: academic citations page-level promise (post-archive)
pk$factor_specs <- lapply(pk$factor_specs, function(fs) {
  fs$page_level_citation_status <- "paper-name only; page-level + KR-specific replication deferred to follow-up D43_Skewness single-factor WT"
  fs
})

# Codex round result + ACCEPT/PARTIAL/REBUTTAL summary
pk$codex_round <- list(
  stance                    = codex$stance,
  veto_flag                 = codex$veto_flag,
  stance_rationale          = codex$stance_rationale,
  weakest_assumption        = codex$weakest_assumption,
  critical_concerns_count   = list(
    HIGH    = sum(sapply(codex$critical_concerns, function(c) c$severity == "HIGH")),
    MEDIUM  = sum(sapply(codex$critical_concerns, function(c) c$severity == "MEDIUM")),
    total   = length(codex$critical_concerns)
  ),
  q_lead_auto_escalate      = TRUE,
  auto_escalate_reasons     = c(
    "HIGH severity concerns >= 5 (got 6)",
    "AX-007 + PIT-C13 + PIT-C15 hard FAIL",
    "Codex stance = REJECT"
  ),
  challenge_note_path       = "qepm/mailbox/worktask/WT-D20260501_002/challenge_note.md",
  disposition_summary       = list(
    ACCEPT    = c("C1", "C2", "C4", "C6", "C8"),
    PARTIAL   = c("C3", "C5", "C7", "C9"),
    REBUTTAL_only = c()
  ),
  rationalization_red_flags_detected = codex$rationalization_red_flags
)

# wt_type discovery role card check
pk$role_card_check <- list(
  wt_type                       = pk$wt_type,
  expected_role_card            = "discovery — neue alpha mechanism 발굴",
  alpha_inheritance_cor         = pk$diagnostics$alpha_inheritance_cor,
  alpha_inheritance_cor_below_threshold = pk$diagnostics$alpha_inheritance_cor < 0.95,
  factor_specs_count            = length(pk$factor_specs),
  factor_specs_meets_threshold  = length(pk$factor_specs) >= 1,
  harvey_t_specs_pass_count     = pk$diagnostics$harvey_t_specs_pass_count,
  harvey_t_specs_meets_threshold = pk$diagnostics$harvey_t_specs_pass_count >= 3,
  alpha_discovery_certificate_eligible = FALSE,
  certificate_decision_rationale = "Walking-forward composite ICIR 0.1999 < 0.20 + Codex REJECT + 5/6 graduation gates fail. Charter v1.7 §10 alpha_discovery_certificate criteria not met. PG1 admission auto-deny (passive)."
)

# Final meta
pk$meta$codex_round_completed <- TRUE
pk$meta$challenge_note_emitted <- TRUE
pk$meta$final_status <- "ABORT_RECOMMENDED — alpha not discovered under PIT-strict walking-forward. Codex REJECT triangulated."
pk$meta$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# Update generated timestamp
pk$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# Fix signal_matrix_ref bug (codex finding: stage_artifacts/... missing qepm prefix)
pk$signal_matrix_ref <- "qepm/stage_artifacts/WT_D20260501_002/alpha_scores.parquet"

# Write final alpha_package.json
final_path <- file.path(WT_DIR, "alpha_package.json")
write_json(pk, final_path, pretty = TRUE, auto_unbox = TRUE,
           na = "null", force = TRUE)

cat("\n==================================================\n")
cat("alpha_package.json written: ", final_path, "\n")
cat("Size: ", file.size(final_path), " bytes\n")
cat("==================================================\n\n")

# ---- R11 Lineage 의무 호출 ----
source(file.path(PROJ_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))

input_files <- c(
  file.path(PROJ_ROOT, ".cache/factor_db/factor_ic_monthly.parquet"),
  file.path(PROJ_ROOT, ".cache/rawdata.parquet"),
  file.path(PROJ_ROOT, ".cache/factor_db/build_hash.txt"),
  file.path(WT_DIR, "request.json"),
  file.path(WT_DIR, "alpha_package_draft.json"),
  file.path(WT_DIR, "codex_critic_response_alpha.json"),
  file.path(WT_DIR, "challenge_note.md")
)
input_files <- input_files[file.exists(input_files)]

record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "walking-forward composite (6-factor, rolling-12 IC theta, signed sign, Bayesian shrinkage λ=12) — REJECTED by codex, ABORT recommended",
  input_file_paths = input_files,
  windows = list(
    walking_forward_start = "2008-01-31",
    walking_forward_end   = "2026-04-30",
    n_sig_dates           = 220L,
    rolling_ic_window_months = 12L
  ),
  random_seed = 20260501002L,
  extra = list(
    codex_stance              = "REJECT",
    codex_concerns_high       = 6L,
    codex_concerns_total      = 9L,
    graduation_recommendation = "ABORT_HONEST_ALPHA_NOT_FOUND",
    q_lead_auto_escalate      = TRUE
  )
)

cat("\nLineage recorded.\n")
cat("Final hash: ",
    digest::digest(file = final_path, algo = "sha256"), "\n")
