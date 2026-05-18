# =========================================================================
# WT-D20260519_002 — Finalize: lineage record + challenge_review log
# =========================================================================
# Post optimization_package.json final emit:
#   (1) lineage_utils::record_package_lineage("WT-D20260519_002", "optimization_package", ...)
#   (2) wt_record_challenge_review("WT-D20260519_002", "optimizer", objection=FALSE, targets=...)
# =========================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(digest)
  library(data.table)
})

set.seed(20260424)

wt_root_proj <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(wt_root_proj)

# --- Load helpers ---
source("02_Infrastructure/worktask/lineage_utils.R")
source("02_Infrastructure/worktask/worktask_manager.R")

task_id <- "WT-D20260519_002"

# --- (1) lineage record ---
cat("\n=== Step 1: record_package_lineage ===\n")
input_files <- c(
  "qepm/mailbox/worktask/WT-D20260519_002/alpha_package.json",
  "qepm/mailbox/worktask/WT-D20260519_002/risk_package.json",
  "qepm/mailbox/worktask/WT-D20260519_002/request.json",
  "qepm/mailbox/worktask/WT-D20260519_002/codex_critic_response_optimizer.json",
  "qepm/mailbox/worktask/WT-D20260519_002/optimization_package_draft.json",
  "stage_artifacts/WT_D20260519_002/overlay_schedule.csv"
)

windows_list <- list(
  list(name = "full_history_strategy_A", start = "1990-01-01", end = "2026-05-31", n_months = 437),
  list(name = "S2_plus_strategy_B", start = "2001-01-01", end = "2026-05-31", n_months = 305),
  list(name = "S4_full_features_strategy_C", start = "2016-09-01", end = "2026-05-31", n_months = 117),
  list(name = "STR_1715_PG2_overlay_simulation_267m", start = "2004-02-01", end = "2026-04-01", n_months = 267)
)

extra_meta <- list(
  scope_class = "regime_sensor_overlay_policy_formal_waiver_charter_10_v18",
  codex_round_disposition = "REJECT_VETO_FALSE_7_concerns_1_ACCEPT_FULL_5_PARTIAL_ACCEPT_1_PARTIAL_REBUTTAL",
  qlead_escalate_fired = TRUE,
  qlead_escalate_basis = "HIGH+CRITICAL severity 6 >= 5 + Codex stance=REJECT veto_flag=False + 도훈 mandate 2026-05-18",
  forge_cycle_binding_count = 13,
  forge_cycle_binding_count_extension = "8 original (OPT1-OPT8) + 5 new from Codex C7 PARTIAL_ACCEPT (OPT9-OPT13)",
  to_total_yr_design_phase_empirical = 5.888,
  to_total_yr_cap = 6.0,
  to_cap_check_status = "PASS_MARGIN_0_112",
  total_cost_bps_yr_reproducible_tau_0_5 = 356.6,
  ax_008_status_optimizer_stage = "1_OF_3_PENDING_FORGE_AND_ARCHITECT_AFTER",
  overlay_schedule_emitted = TRUE,
  overlay_schedule_n_sig_dates = 267,
  method_shopping_log_separate_emitted = TRUE
)

result <- record_package_lineage(
  task_id = task_id,
  package_type = "optimization_package",
  method_selected = "Bear_Sensor_Overlay_Policy_v1_Path_B_Standalone_STR_1715_PG2_Layer_6_Default_tau_0_5_anti_flicker_1m_subject_to_Forge_Stage_4_CO1_CO13",
  input_file_paths = input_files,
  windows = windows_list,
  random_seed = 20260424,
  extra = extra_meta
)

cat("lineage record entry appended PASS\n")

# --- (2) challenge_review log ---
cat("\n=== Step 2: wt_record_challenge_review ===\n")
wt_record_challenge_review(
  task_id = task_id,
  from_agent = "optimizer",
  objection = FALSE,
  reason = NA,
  targets_reviewed = c(
    "alpha_package",
    "risk_package",
    "factor_specs",
    "downstream_integration_constraints",
    "STR_1715_PG2_lineage_session_80"
  )
)

cat("\n=== Finalize Complete ===\n")
cat("artifact_lineage.json appended + governance_log.json CHALLENGE_REVIEWED event appended\n")
