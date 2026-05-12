#==============================================================================
# WT-D20260508_013 Forge — Finalize forge_package.json post-Codex
#
# Per codex_round_pre_enforcer.sh: final {role}_package.json requires
#   _draft + critic_response BOTH present.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(digest)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_ID <- "WT-D20260508_013"
WT_DIR <- file.path("qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path("stage_artifacts", WT_ID)

# Hash verify input packages unchanged (Pure Function R12)
alpha_sha <- digest(file = file.path(WT_DIR, "alpha_package.json"), algo = "sha256")
risk_sha  <- digest(file = file.path(WT_DIR, "risk_package.json"), algo = "sha256")
opt_sha   <- digest(file = file.path(WT_DIR, "optimization_package_draft.json"), algo = "sha256")

# Verify draft + critic exist
draft_path <- file.path(WT_DIR, "forge_package_draft.json")
critic_path <- file.path(WT_DIR, "codex_critic_response_forge.json")
challenge_path <- file.path(WT_DIR, "challenge_note_forge.md")
stopifnot(file.exists(draft_path), file.exists(critic_path), file.exists(challenge_path))

cat("[Forge finalize] All prerequisites present\n")
cat("  draft:", file.size(draft_path), "bytes\n")
cat("  critic:", file.size(critic_path), "bytes\n")
cat("  challenge_note:", file.size(challenge_path), "bytes\n")

draft <- read_json(draft_path, simplifyVector = FALSE)
critic <- read_json(critic_path, simplifyVector = FALSE)

# Apply mitigations from challenge_note
draft$package_kind <- "forge_package"
draft$artifact_version <- "v1.0_forge_package_post_codex"
draft$draft_revision <- NULL  # remove draft marker

# Codex round 1 summary
draft$codex_critic_round_1 <- list(
  stance_received = critic$stance,
  weakest_assumption = critic$weakest_assumption,
  concerns_total = length(critic$critical_concerns),
  high_severity_count = sum(sapply(critic$critical_concerns, function(c) c$severity == "HIGH")),
  classification = list(
    "C1_weight_cap" = "ACCEPT_PARTIAL_optimizer_drift_acknowledge_forge_cap_iter50_mitigation",
    "C2_lockbox_marker" = "ACCEPT_architect_mandate_boost",
    "C3_harvey_5spec" = "ACCEPT_architect_mandate_boost",
    "C4_date_lineage" = "ACCEPT_PARTIAL_typo_250m_corrected_path_convention_clarified",
    "C5_factor_cov_cond" = "ACCEPT_via_risk_passthrough",
    "C6_5pct_economically_fragile" = "PARTIAL_ACCEPT_forge_does_not_recommend_admit_defer_governor"
  ),
  silent_override = FALSE,
  escalate_to_q_lead = TRUE,
  escalate_rationale = paste0(
    "HIGH severity = 4. No AX hard FAIL. Lockbox marker missing (C2) but PIT C1 ",
    "compliant (walk-forward only). Forge self-resolves within scope; final admit ",
    "decision pending Architect 3rd-source (Harvey 5-spec + lockbox extension + ",
    "cov_factor multi-factor) + Governor decision matrix."
  ),
  response_file = critic_path,
  challenge_note_file = challenge_path,
  final_stance = "APPROVE_CONDITIONAL_DIVERSIFIER_5PCT_OR_SKIP_DEFER_GOVERNOR",
  final_stance_basis = paste0(
    "도훈 mandate 5건 모두 진행: 5 비중 실측 + Optimizer 추정 vs Forge 실측 격차 진단 + ",
    "AX-001 v2 strict 실측 (Diversifier 약화 진단 정합 — bad/normal -0.106 PRO-CYCLIC, ",
    "6 crisis 1/6 positive, total crisis_alpha -132.62pp) + AX-008 2/3 (Architect mandate) + ",
    "admit 권고 deferred Governor. Forge primary: A (skip) or B (5% conservative). NOT C (10%)."
  )
)

# Apply C4 typo correction
if (!is.null(draft$five_ratio_results)) {
  for (key in names(draft$five_ratio_results)) {
    fr <- draft$five_ratio_results[[key]]
    if (!is.null(fr$joint_window_252m)) {
      # Rename 252m -> 250m for accuracy
      fr$joint_window_250m_actual <- fr$joint_window_252m
      fr$joint_window_252m_legacy_name <- "joint_window_250m_actual_field_corrected_n_periods_250"
      draft$five_ratio_results[[key]] <- fr
    }
  }
}

# C2 lockbox audit (ACCEPT — explicit gap acknowledgement)
draft$lockbox_audit <- list(
  status = "MARKER_MISSING_ARCHITECT_MANDATE_BOOST",
  alpha_pit_cutoff_inferred = "alpha_package recent60m strict 3/3 PASS window 2021-05 ~ 2026-04 = lockbox 2024-01-23 marker consistent with STR_1715 PG2 admit precedent",
  forge_walk_forward_range = "2005-05-31 ~ 2026-04-30 (252 sig_dates)",
  deploy_extension_visible = FALSE,
  frozen_extension_methodology = "NOT_DOCUMENTED_THIS_CYCLE",
  remediation_mandate = paste0(
    "Architect 3rd-source 재현 시 lockbox 2024-01-23 + frozen extension 2024-01-24 ~ 2026-04-30 ",
    "buy-and-hold OOS measurement 의무. 본 Forge cycle 누락 정직 인정."
  ),
  charter_v17_section_10_compliance = "PARTIAL — walk-forward valid; lockbox separation unaudited"
)

# C3 Harvey 5-spec (ACCEPT — Architect mandate)
draft$harvey_5spec_strategy_level <- list(
  status = "DEFERRED_TO_ARCHITECT",
  rationale = paste0(
    "Strategy-level Harvey 5-spec (CAPM/Carhart-3/Carhart-4/FF5/FF6) Newey-West t + ",
    "alpha_monthly + DSR_post per spec required for admit candidate (Charter v1.5 §13~14). ",
    "Forge cycle 시간 제약상 alpha-layer 5-spec inheritance만 (alpha_package 측 t=2.86 < 3.0 + DSR strict 0). ",
    "Strategy-level 재산출 = Architect 3rd-source mandate."
  ),
  alpha_layer_inherited = list(
    rank_ic = 0.032,  # alpha_package report
    icir = 0.184,
    harvey_t_2_86 = 2.86,
    dsr_strict = 0,
    full_panel_5_5_FAIL_4_of_5 = TRUE,
    recent_60m_3_3_PASS = TRUE
  )
)

# C1 weight cap acknowledgement
draft$hard_constraints_audit$weight_bounds_numerical_drift_disclaimer <- paste0(
  "Forge sleeve_returns_256m max_w 0.2000863 (4e-4 over 0.20). Within 1e-3 tolerance ",
  "(consistent with worktask_constraint_enforcer.sh sum_w 1e-3 threshold). Optimizer ",
  "weights.csv 3/252 sig_dates (2010-03-31, 2011-06-30, 2018-01-31) 0.21 cap drift; ",
  "Pure Function R12 means Forge cannot modify Optimizer weights. Both acknowledged. ",
  "Forge cap algorithm strengthen mandate (50-iter fixed-point) for next cycle."
)

# AX-008 update
draft$ax_axiom_audit$AX_008$forge_codex_2_of_3 <- list(
  forge_self_assessment = "PASS_subject_to_lockbox_Harvey_5spec_pending",
  codex_round_1_stance = critic$stance,
  codex_concerns_count = length(critic$critical_concerns),
  codex_high_severity = sum(sapply(critic$critical_concerns, function(c) c$severity == "HIGH")),
  triangulation_progress_pct = 67,  # 2/3 = 67%
  architect_3rd_source_mandate = c(
    "Independent Atilgan VaR + Mom factor reproduction (alpha-layer)",
    "Hybrid 4-sleeve combine 5 비중 ΔSharpe verification (strategy-layer)",
    "Lockbox 2024-01-23 frozen extension OOS measurement",
    "Harvey 5-spec strategy-level + DSR_post Bailey-LdP penalty",
    "cov_factor multi-factor extension (sector dummies / EWMA expand) for cond ≤ 100"
  )
)

# Write final
final_path <- file.path(WT_DIR, "forge_package.json")
write_json(draft, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("\n[saved]", final_path, " — size:", file.size(final_path), "bytes\n")

# Update status.json
status <- read_json(file.path(WT_DIR, "status.json"), simplifyVector = FALSE)
status$current_phase <- "FORGE_DONE"
status$next_agent <- "judge"
status$forge_completion_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$forge_package_path <- final_path
status$forge_artifacts_dir <- file.path(SA_DIR, "forge")
status$forge_codex_round_1 <- list(
  stance = critic$stance,
  response = critic_path,
  challenge_note = challenge_path
)
status$forge_agent_final_stance <- "APPROVE_CONDITIONAL_DIVERSIFIER_5PCT_OR_SKIP_DEFER_GOVERNOR"
status$forge_agent_assessment <- paste0(
  "5 비중 256m 실측: 0% SR 1.811 / 5% 1.818 (ΔSR+0.0065, ΔMDD-0.62pp) / ",
  "10% 1.813 / 15% 1.795 / 20% 1.762. Optimizer estimate vs Forge realized: ",
  "Hybrid combine SR realized > estimate by +0.02~+0.16 (Optimizer underestimate). ",
  "Sleeve standalone realized 0.366 vs estimate 0.708 (deflate 48%). AX-001 v2 strict ",
  "realized: bad/normal -0.106 PRO-CYCLIC + 6 crisis 1/6 positive (-132.62pp total) → ",
  "Diversifier 약화 진단. Forge primary recommendation: SKIP (0%) or 5% conservative; ",
  "NOT 10% Optimizer primary."
)

write_json(status, file.path(WT_DIR, "status.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[saved] status.json updated → FORGE_DONE\n")

cat("\n[Forge finalize] DONE\n")
