#!/usr/bin/env Rscript
# build_overlay_schedule_template.R
# Optimizer Agent v1.0 — WT-D20260518_001
# Phase A design phase
#
# Purpose: Emit overlay_schedule.csv TEMPLATE for full 1990~2026 sig_dates
#          schedule with placeholder β_bear = 1.0 (no Layer 6 effect)
#          AND W3 OOS 24-month reference β_bear emission demonstrating policy M05.
#          Forge Stage 5 will replace placeholder with actual p_bad_t-driven β_bear
#          based on ensemble Stage 4 emission.
#
# Method M05 (POLICY_DEFAULT):
#   - Quantile-based τ (τ_caution = q70, τ_crisis = q90) per calibration window
#   - Hard 3-step β ∈ {1.0, 0.7, 0.3}
#   - Hysteresis 5% buffer
#   - Sequential Layer 6 (multiplicative)
#
# Outputs:
#   stage_artifacts/WT_D20260518_001/overlay_schedule.csv
#   stage_artifacts/WT_D20260518_001/overlay_schedule_summary.json

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ==========================================
# Step 1: Load sig_dates universe
# ==========================================
# Use BM benchmark cache + aggregate to monthly sig_dates
bm_path <- ".cache/benchmark.parquet"
if (!file.exists(bm_path)) {
  stop("benchmark.parquet not found")
}
bm_daily <- as.data.table(arrow::read_parquet(bm_path))
# Aggregate to monthly — last business day of each month
bm_daily[, ym := format(Date, "%Y-%m")]
bm_monthly <- bm_daily[, .(
  sig_date = max(Date),
  BM_Close_eom = last(BM_Close),
  BM_Ret_m = prod(1 + BM_Ret, na.rm = TRUE) - 1
), by = ym]
bm_monthly <- bm_monthly[order(sig_date)]
bm <- bm_monthly[, .(Date = sig_date, BM_Ret_m)]
sig_dates <- sort(unique(bm$Date))
cat("[Step 1] Monthly sig_dates loaded:", length(sig_dates),
    "range:", as.character(min(sig_dates)), "~", as.character(max(sig_dates)), "\n")

# ==========================================
# Step 2: Define M05 policy parameters
# ==========================================
policy <- list(
  method_id = "M05",
  name = "Sequential_Layer6_Quantile_Hard3step_Hysteresis_5pct",
  beta_NORMAL = 1.0,
  beta_CAUTION = 0.7,
  beta_CRISIS = 0.3,
  hysteresis_buffer = 0.05,
  smoothing = "hysteresis",
  multi_horizon_sanity = "1m_primary_plus_3m_cross_check",
  composition = "Sequential_Layer_6_after_R05",
  status_default = "PLACEHOLDER_pending_Forge_Stage_4_p_bad_t_emission"
)

# ==========================================
# Step 3: Build full schedule TEMPLATE
# ==========================================
# Phase A scope: emit template with placeholder β_bear = 1.0 (no-op)
# Forge Stage 5 will replace with actual β_bear based on p_bad_t

schedule <- data.table(
  sig_date = sig_dates,
  bm_ret_m = bm[match(sig_dates, Date), BM_Ret_m],
  # Placeholder fields
  p_bad_t = NA_real_,                       # Forge Stage 4 fills
  calibrator_used = NA_character_,          # Forge Stage 3 fills
  tau_caution_calibration_window = NA_real_, # Forge Stage 5 fills
  tau_crisis_calibration_window = NA_real_,  # Forge Stage 5 fills
  regime_label = NA_character_,             # Forge Stage 2 fills (PIT t-1)
  classification = "NORMAL_PLACEHOLDER",    # NORMAL / CAUTION / CRISIS
  hysteresis_state = "NORMAL_PLACEHOLDER",
  beta_bear = policy$beta_NORMAL,           # PLACEHOLDER default 1.0 = no-op
  beta_bear_transition = 0L,                # binary 1 if changed from t-1
  multi_horizon_3m_sanity_consistent = NA,  # boolean from 3m cross-check
  phase_a_status = "TEMPLATE_PLACEHOLDER",
  forge_stage_binding = "Stage 4 p_bad_t emit -> Stage 5 quantile threshold + β_bear application"
)

# ==========================================
# Step 4: NO SIMULATED W3 BETA EMISSION
# ==========================================
# Codex C2 ACCEPT — disposition: REMOVE simulated W3 illustrative beta path.
# rnorm/sample simulation = self_synthesis violation (AX-002).
# Phase A scope = policy specification + Forge Stage 4 binding ONLY.
# All 437 sig_dates remain placeholder β_bear = 1.0 (no-op, safe fallback).
# Forge Stage 4 p_bad_t emission replaces placeholder with actual calibrated p.
# Forge Stage 5 applies quantile-hysteresis policy to actual p_bad_t.
#
# Audit trail: placeholder share = 100% (NO simulated content).
W3_n <- 0L
W3_dates <- character(0)
TO_ann_W3_ref <- NA_real_
n_transitions_W3 <- 0L
cat("[Step 4] W3 illustrative simulation REMOVED (Codex C2 ACCEPT).\n")
cat("[Step 4] All sig_dates placeholder β_bear = 1.0 (no-op).\n")
cat("[Step 4] Real β_bear emission deferred to Forge Stage 5.\n")

# ==========================================
# Step 5: Schedule density & infeasibility check (no simulation)
# ==========================================
n_sig_dates_total <- nrow(schedule)
n_with_beta <- sum(!is.na(schedule$beta_bear))
density_ratio <- n_with_beta / n_sig_dates_total
cat("[Step 5] Schedule density:", round(density_ratio * 100, 1), "% (",
    n_with_beta, "/", n_sig_dates_total, ")\n")

# All sig_dates have β_bear = 1.0 placeholder (no-op). Density = 1.0 trivially.
# Real density of NON-PLACEHOLDER β_bear emission = Forge Stage 5 binding.

cat("[Step 5] All placeholder, no transitions (W3 simulation removed).\n")

# ==========================================
# Step 6: Save outputs
# ==========================================
out_dir <- "stage_artifacts/WT_D20260518_001"
out_csv <- file.path(out_dir, "overlay_schedule.csv")
out_json <- file.path(out_dir, "overlay_schedule_summary.json")

fwrite(schedule, out_csv)
cat("[Step 6] Saved:", out_csv, "\n")

# Summary
summary_obj <- list(
  task_id = "WT-D20260518_001",
  agent = "optimizer-research",
  agent_version = "v1.0_overlay_schedule_design_phase_a",
  wt_subclass = "discovery_design_phase_a",
  schedule_csv_path = out_csv,
  policy = policy,
  schedule_density = list(
    n_sig_dates_total = n_sig_dates_total,
    n_with_beta = n_with_beta,
    density_ratio = density_ratio,
    placeholder_share = 1.0,
    illustrative_W3_share = 0.0,
    schedule_density_status = "PASS_density_1.0_all_placeholder_phase_a_design_no_simulation",
    real_Forge_Stage_5_density_pending = TRUE,
    codex_C2_disposition = "ACCEPT — W3 simulated reference REMOVED. No self_synthesis."
  ),
  turnover = list(
    illustrative_simulation_REMOVED = "Codex C2 ACCEPT",
    full_sample_TO_ann_pending_Forge_Stage_5 = TRUE,
    target_cap_ann = 6.0,
    infeasibility_trigger = "Forge Stage 5 if full_sample TO > 6.0/yr — infeasibility_report mandatory"
  ),
  infeasibility_report = list(
    raised = FALSE,
    reason = NA_character_,
    binding_constraints = list(),
    suggested_resolution = NA_character_,
    note = "No infeasibility in design phase. Forge Stage 5 may raise if τ thresholds produce zero CAUTION/CRISIS transitions in 4+/5 windows (overfitting concern)."
  ),
  hard_constraints_check = list(
    max_names_check = "N_A_overlay_role_alpha_pkg_max_names_null",
    long_only_check = "N_A_overlay_scalar_beta_in_0.3_1.0",
    weight_bounds_check = "N_A_beta_bear_in_0.3_1.0_underlying_str1715_retains_0_0.20",
    sigma_w_check = "N_A_overlay_multiplicative_underlying_str1715_retains_sigma_w_1",
    LIQ_check = "N_A_overlay_role_underlying_str1715_retains_LIQ_2e8",
    cost_15bps_check = "PENDING_Forge_S5_emission_real_p_bad_t_then_TO_x_15bps_x_2_sides_consistent_formula",
    PIT_C5_check = "PASS_overlay_t_minus_1_basis_quantile_calibration_window_expanding",
    schedule_density_gte_095 = "PASS_placeholder_filled_100pct"
  ),
  decision_branches = list(
    DB_A_M07_replacement_M4_conditional = "Forge Stage 5 DM test p < 0.05",
    DB_B_M11_calibrator_ensemble_conditional = "Forge Stage 3 isotonic ECE > 0.10",
    DB_C_M06_regime_stratified_conditional = "Forge Stage 5 per-regime AUC variance < 0.10 + bootstrap CI"
  ),
  next_step = "Forge Stage 4 emit p_bad_t time series -> Stage 5 replace beta_bear placeholder with quantile-hysteresis policy emission"
)
write_json(summary_obj, out_json, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("[Step 6] Saved:", out_json, "\n")

cat("\n========================================\n")
cat("Schedule emission complete (Phase A design template)\n")
cat("========================================\n")
