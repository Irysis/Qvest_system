# =========================================================================
# WT-D20260519_002 — Forge Finalize: lineage record + challenge_review log
# =========================================================================
# Post forge_package.json final emit (post Codex Round Stage 5):
#   (1) lineage_utils::record_package_lineage("WT-D20260519_002", "forge_package", ...)
#   (2) wt_record_challenge_review("WT-D20260519_002", "forge", objection=TRUE)
#   (3) status.json phase transition OPTIMIZER_DONE → FORGE_DONE
# =========================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(digest); library(data.table)
})

set.seed(20260518)
wt_root_proj <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(wt_root_proj)

source("02_Infrastructure/worktask/lineage_utils.R")
source("02_Infrastructure/worktask/worktask_manager.R")

task_id <- "WT-D20260519_002"

# --- (1) lineage record ---
cat("\n=== Step 1: record_package_lineage(forge_package) ===\n")
input_files <- c(
  "qepm/mailbox/worktask/WT-D20260519_002/alpha_package.json",
  "qepm/mailbox/worktask/WT-D20260519_002/risk_package.json",
  "qepm/mailbox/worktask/WT-D20260519_002/optimization_package.json",
  "qepm/mailbox/worktask/WT-D20260519_002/architect_verification_package.json",
  "qepm/mailbox/worktask/WT-D20260519_002/forge_package_draft.json",
  "qepm/mailbox/worktask/WT-D20260519_002/codex_critic_response_forge.json",
  "qepm/mailbox/worktask/WT-D20260519_002/challenge_note_forge.md",
  "stage_artifacts/WT_D20260519_002/overlay_schedule.csv"
)

windows_list <- list(
  list(name="W1_2015_2017_OOS", start="2015-01-01", end="2017-12-31", n_months=36),
  list(name="W2_2018_2020_OOS", start="2018-01-01", end="2020-12-31", n_months=36),
  list(name="W3_2021_2022_OOS", start="2021-01-01", end="2022-12-31", n_months=24),
  list(name="W4_2023_2024_OOS", start="2023-01-01", end="2024-12-31", n_months=24),
  list(name="W5_2025_2026_OOS", start="2025-01-01", end="2026-04-30", n_months=16),
  list(name="path_b_267m_full_simulation", start="2004-02-01", end="2026-04-01", n_months=267)
)

extra_meta <- list(
  scope_class="regime_sensor_overlay_policy_forge_stage_4_empirical",
  forge_recommendation="LAYER_6_REJECT_HARD_FAIL_G1_RECALL_ZERO_AND_OPT9_TDC_GE_07_AND_SR_DRAG_ALL_TAU",
  g1_subgate_pass_count=0,
  g1_subgate_target=4,
  g1_subgate_status="HARD_FAIL",
  architect_uplift_auc=0.6117,
  architect_uplift_auc_target_06_pass=TRUE,
  architect_uplift_recall=0.0,
  architect_uplift_recall_target_06_pass=FALSE,
  opt9_tdc_empirical=0.75,
  opt9_decision_rule_trigger="REJECT_LAYER_6_TDC_GE_07",
  opt6_to_total_per_yr_tau05=5.86,
  opt6_pass=TRUE,
  opt4_rho_pbad_m4=-0.5373,
  opt4_pass=TRUE,
  opt11_dsr_z_L6_tau05=5.90,
  opt11_dsr_inheritance_note="DSR_inherited_from_L5_V2_baseline_not_bear_sensor_contribution",
  path_b_267m_l6_tau05_SR=1.8651,
  path_b_267m_l5_v2_baseline_SR=1.8861,
  path_b_delta_sr_tau05=-0.0210,
  path_b_delta_sr_tau07=-0.0069,
  path_b_mdd_unchanged_2481pct=TRUE,
  pure_function_audit_passed=TRUE,
  self_synthesis_used=FALSE,
  honest_substitutions_count=6,
  ax_008_status_forge_stage="REJECT_HARD_FAIL_HONEST"
)

result <- record_package_lineage(
  task_id=task_id,
  package_type="forge_package",
  method_selected="Bear_Sensor_Layer_6_Path_B_5model_ensemble_simple_avg_tau_sweep_267m_NAV_subject_to_G1_subgate_HARD_FAIL_TDC_REJECT",
  input_file_paths=input_files,
  windows=windows_list,
  random_seed=20260518,
  extra=extra_meta
)
cat("lineage record entry appended PASS\n")

# --- (2) challenge_review log (objection=TRUE — honest fail declaration) ---
cat("\n=== Step 2: wt_record_challenge_review ===\n")
wt_record_challenge_review(
  task_id=task_id,
  from_agent="forge",
  objection=TRUE,
  reason="Bear sensor v1.0 Layer 6 admit REJECT — multi-axis hard fail: G1 Recall=0 across all 4 windows + OPT9 TDC 0.75 GE 0.7 decision rule REJECT + Path B SR drag all τ schedules + MDD unchanged. Path A DPL_KR_v3 inject DEFER to WT-D20260519_001 Forge lifecycle. v2.0 cycle mandates: Platt scaling calibration (root cause) + cost-sensitive classifier + W3 feature drift stratified retrain + Phase B direct data collection.",
  targets_reviewed=c(
    "alpha_package_5model_ensemble_logistic_xgb_rf_lag_glm_ms",
    "risk_package_8_backbone_inherit_28pct_crowding",
    "optimization_package_overlay_policy_267m_design_phase_simulation",
    "architect_verification_partial_baseline_floor_044"
  )
)

cat("\n=== Forge Finalize Complete ===\n")
cat("artifact_lineage.json appended + governance_log.json CHALLENGE_REVIEWED event appended (objection=TRUE)\n")
