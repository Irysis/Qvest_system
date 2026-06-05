#==============================================================================
# WT-D20260528_003 v3.7 — Step 7: Final alpha_package.json
#
# Codex Round 5-step complete:
#   1. draft created (Step 6)
#   2. PostToolUse codex auto-spawn → critic response received
#   3. Codex stance: REJECT (7 concerns)
#   4. challenge_note.md written (5 ACCEPT + 2 PARTIAL)
#   5. Final package emission with honest TERMINATE verdict
#
# PreToolUse `codex_round_pre_enforcer.sh` 통과 의무:
#   - alpha_package_draft.json: ✅ exists (Step 6)
#   - codex_critic_response_alpha.json: ✅ exists (Codex spawned)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_7")
MAIL_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")

cat("[Step 7: alpha_package final emission] === START ===\n")

# ---- 1. Load draft + critic response ----
draft <- fromJSON(file.path(MAIL_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)
critic <- fromJSON(file.path(MAIL_DIR, "codex_critic_response_alpha.json"), simplifyVector = FALSE)

cat("  Draft loaded:", file.size(file.path(MAIL_DIR, "alpha_package_draft.json")), "bytes\n")
cat("  Critic loaded:", file.size(file.path(MAIL_DIR, "codex_critic_response_alpha.json")), "bytes\n")
cat("  Codex stance:", critic$stance, "\n")
cat("  Codex n_concerns:", length(critic$critical_concerns), "\n\n")

# ---- 2. Append Codex Round adjudication to draft → final ----
final <- draft

# Add codex_round section
final$codex_round <- list(
  status = "completed",
  cycle = "v3.7 Round 1",
  codex_stance = critic$stance,
  codex_weakest_assumption = critic$weakest_assumption,
  codex_n_concerns_total = length(critic$critical_concerns),
  codex_n_high = sum(sapply(critic$critical_concerns, function(c) c$severity == "HIGH")),
  codex_n_medium = sum(sapply(critic$critical_concerns, function(c) c$severity == "MEDIUM")),
  codex_n_low = sum(sapply(critic$critical_concerns, function(c) c$severity == "LOW")),
  agent_adjudication = list(
    C1_PIT_Phase1_3_contamination = list(
      severity = "HIGH",
      status = "ACCEPT",
      evidence_path = "04_Research/decision_framework/factor_untapped/outputs/factor_db_untapped_icir_ranking.meta.json date_end=2026-02-28",
      action = "TERMINATE recommendation — upstream lineage lockbox violation hard"
    ),
    C2_Static_ICIR_weights = list(
      severity = "HIGH",
      status = "ACCEPT",
      evidence_path = "scripts/v3_7/04_alpha_vector_construct.R lines 47-50 — full-sample ICIR vector applied to all sig_dates",
      action = "TERMINATE — PIT C1 violation"
    ),
    C3_DSR_n_trials_underestimate = list(
      severity = "HIGH",
      status = "PARTIAL",
      evidence = "Actual research search: 269 + 38 + 8 + 18 = 333 trial; draft uses n_trials=18",
      action = "DSR re-calc estimate z = 4.7~4.9 (still pass), secondary issue"
    ),
    C4_AX001_bad_normal_monotonicity = list(
      severity = "HIGH",
      status = "ACCEPT",
      evidence = "draft validation own measurement: bad/normal -0.211, monotonicity -0.261, Harvey 2/5",
      action = "TERMINATE — graduation gate hard fail"
    ),
    C5_Liquidity_2e8_not_enforced = list(
      severity = "HIGH",
      status = "ACCEPT",
      evidence = "Codex measurement: top decile 340/7001 (4.86%) below 2e8 hard floor; v3.7 scripts no LIQ filter",
      action = "Conflict request.json 5e7 vs base 2e8 — base mandate prevails"
    ),
    C6_AX007_multi_sleeve = list(
      severity = "MEDIUM",
      status = "PARTIAL",
      evidence = "alpha_score = score-based, but draft reports top20 single-sleeve metric",
      action = "design intent acknowledged but unverified; moot given TERMINATE"
    ),
    C7_Artifact_missing = list(
      severity = "MEDIUM",
      status = "ACCEPT",
      evidence = "challenge_note.md / stage_artifacts base dir / risk-optimizer downstream artifacts missing",
      action = "challenge_note.md written this step; downstream is post-TERMINATE moot"
    )
  ),
  rationalization_self_grep = list(
    detected = critic$rationalization_red_flags,
    classified = list(
      "PENDING — triangulation requires Risk + Optimizer downstream" = "ACCEPT (real dep)",
      "Optimizer 단계에서 multi-sleeve 분리 가능" = "PARTIAL (design intent acknowledged unverified)",
      ".cache/rawdata.parquet Sector column (contemporaneous, PIT-OK)" = "ACCEPT (defensible)",
      "Score-based universe alpha vector; downstream Optimizer responsibility" = "PARTIAL (matches AX-007 boundary discussion)"
    )
  ),
  anticipation_gaps_acknowledged = c(
    "Phase 1/3 lineage PIT contamination",
    "Static weights as PIT C1 violation",
    "DSR n_trials scope (alpha-research-only vs full research)",
    "Liquidity 2e8 enforcement (request 5e7 vs base 2e8 conflict)"
  )
)

# Update honest_verdict
final$honest_verdict$codex_round_outcome <- "REJECT (7 concerns: 5 ACCEPT + 2 PARTIAL)"
final$honest_verdict$final_recommendation <- "TERMINATE STR_1722 family v3.7"
final$honest_verdict$alternative_if_dohoon_confirm <- "PIT-clean re-run path: Phase 1/3 cutoff-safe + per-sig_date expanding weights + LIQ 2e8 filter. Estimated 4-5 days. ICIR_neut weakening 75%+ probability (0.453 → 0.4~0.5)."
final$honest_verdict$decision_authority <- "Q-Lead (도훈 confirm) per Charter §5 Data Mining + AX-008 triangulation"

# Add graduation_certificate_eligibility
final$graduation_certificate_eligibility <- list(
  alpha_discovery_certificate_4_AND = list(
    alpha_inheritance_cor_lt_095 = list(value = "N/A (no parent for cor)", pass = TRUE),
    mechanism_citation_gt_50_chars = list(value = "all 3 factor specs have 80+ char rationale", pass = TRUE),
    factor_specs_gte_1 = list(value = 3, pass = TRUE),
    harvey_t_specs_pass_count_gte_3 = list(value = 2, pass = FALSE, blocker = TRUE)
  ),
  graduation_gates = list(
    rank_ic_gte_004 = list(value = 0.044, pass = TRUE),
    icir_gte_020 = list(value = 0.4531, pass = TRUE),
    subperiod_stability_gte_05 = list(value = 0.733, pass = TRUE),
    harvey_t_pass_3_gte_3 = list(value = 2, pass = FALSE, blocker = TRUE),
    deflated_sharpe_gte_05 = list(value = 5.13, pass = TRUE, caveat = "n_trials=18 (uncorrected); n_trials=333 estimate still PASS"),
    monotonicity_gte_07 = list(value = -0.261, pass = FALSE, blocker = TRUE),
    bad_normal_ratio_gte_05 = list(value = -0.211, pass = FALSE, blocker = TRUE, axiom_hard_fail = "AX-001 v2")
  ),
  certificate_issued = FALSE,
  certificate_reason = "3 critical gate FAIL + AX-001 v2 hard FAIL + 2 NEW PIT contamination (Phase1/3 + static weights)",
  pg1_admission_eligibility = "BLOCKED — passive deny via certifier hook (no alpha_discovery_certificate)"
)

# ---- 3. Write final ----
write_json(final, file.path(MAIL_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: alpha_package.json (", file.size(file.path(MAIL_DIR, "alpha_package.json")), "bytes)\n")

# ---- 4. alpha_validation.json (stage_artifacts) ----
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_WT-D20260528_003_v3_7")
dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)
alpha_val <- list(
  task_id = "WT-D20260528_003",
  schema_version = "alpha_validation_v1",
  validation_date = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  v_version = "v3.7",
  graduation_decision = "FAIL — TERMINATE recommendation",
  ic_diagnostics = final$diagnostics,
  graduation_evaluation = final$graduation_evaluation,
  graduation_certificate_eligibility = final$graduation_certificate_eligibility,
  codex_round_outcome = final$codex_round$codex_stance,
  honest_verdict = final$honest_verdict
)
write_json(alpha_val, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: stage_artifacts/.../alpha_validation.json\n")

# ---- 5. Lineage update ----
source(file.path(BASE, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-D20260528_003",
  package_type = "alpha_package_final",
  method_selected = "TOP3 composite (D22+D43+M22) post-Codex REJECT — TERMINATE recommendation",
  input_file_paths = c(
    file.path(MAIL_DIR, "alpha_package_draft.json"),
    file.path(MAIL_DIR, "codex_critic_response_alpha.json"),
    file.path(MAIL_DIR, "challenge_note.md")
  )
)
cat("  lineage updated\n")

cat("\n[Step 7] === FINAL EMITTED ===\n")
cat("  Codex stance: REJECT\n")
cat("  Final verdict: TERMINATE STR_1722 v3.7\n")
cat("  Decision authority: Q-Lead (도훈 confirm required)\n")
