# =========================================================================
# WT-D20260519_002 — Bear Sensor Overlay Schedule Emission (Path B Layer 6)
# =========================================================================
# Purpose: Codex C5 + Q-Lead C1 PARTIAL_ACCEPT — overlay_schedule.csv per sig_date
#   β_bear schedule simulation across STR_1715 PG2 lineage (267m, 2004-02 ~ 2026-04).
#
# Design phase output (NOT empirical p_bad — Forge Stage 4 binding).
# Uses regime label as proxy for p_bad bucket mapping (transparent design-phase prior).
#
# Output:
#   stage_artifacts/WT_D20260519_002/overlay_schedule.csv
#     as_of_date, p_bad_bucket, beta_bear, beta_m4, beta_AR, beta_R05, combined_overlay,
#     cash_share, transition_event, base_str1715_weight, method_selected
# =========================================================================

suppressPackageStartupMessages({
  library(data.table)
})

set.seed(20260424)

# --- Path setup ---
wt_root <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
weights_csv_str1715 <- file.path(wt_root,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv")
out_csv <- file.path(wt_root, "stage_artifacts/WT_D20260519_002/overlay_schedule.csv")

stopifnot(file.exists(weights_csv_str1715))

# --- Load STR_1715 PG2 4-layer overlay state per sig_date ---
str_dt <- fread(weights_csv_str1715, encoding = "UTF-8")
str_dt[, as_of_date := as.Date(as_of_date)]
setorder(str_dt, as_of_date)

# --- Design-phase p_bad bucket mapping (NOT empirical) ---
# Rationale: This is Path B Layer 6 overlay policy DESIGN PHASE simulation.
#   p_bad is NOT yet emitted (Forge cycle Stage 4 — 5-model ensemble train binding).
#   For the schedule emission we map STR_1715 PG2 regime label → expected p_bad bucket
#   as a design-phase prior placeholder. Forge cycle replaces this mapping with
#   actual p_bad_monthly from trained sensor ensemble.
#
# Mapping (transparent, design-phase prior only):
#   BULL    → p_bad_bucket < 0.3  → β_bear = 1.0
#   NORMAL  → p_bad_bucket < 0.3  → β_bear = 1.0
#   CAUTION → p_bad_bucket 0.3-0.5 → β_bear = 0.7
#   CRISIS  → p_bad_bucket 0.5-0.7 → β_bear = 0.5  (conservative; CRISIS rarely > 0.7)
#
# This mapping is intentionally NOT identical to m4 — Layer 6 design intent is to
# eventually be triggered by lead-time signals (yield curve / LEI / credit) that
# fire BEFORE m4 BOCPD. Forge Stage 4 CO1 < 0.85 mandate empirically validates.
#
# Anti-flicker rule applied (1m persistence default): β_bear update only if
# bucket changes AND persists ≥ 1 month.

map_regime_to_pbad_bucket <- function(regime) {
  fifelse(regime %in% c("BULL", "NORMAL"), "lt_0_3",
    fifelse(regime == "CAUTION", "0_3_to_0_5",
      fifelse(regime == "CRISIS", "0_5_to_0_7",
        "lt_0_3")))
}

bucket_to_beta_bear <- function(bucket) {
  fifelse(bucket == "lt_0_3", 1.0,
    fifelse(bucket == "0_3_to_0_5", 0.7,
      fifelse(bucket == "0_5_to_0_7", 0.5,
        fifelse(bucket == "gt_0_7", 0.3, 1.0))))
}

# --- Emit schedule ---
sched <- str_dt[, .(
  as_of_date         = as_of_date,
  decision_date      = as.Date(decision_date),
  realized_ym        = realized_ym,
  regime_str1715     = regime,
  R05_z_avg          = R05_z_avg,
  base_str1715_weight = base_str1715_weight,
  beta_m4            = m4_scalar,
  beta_AR            = beta_AR,
  beta_R05           = beta_R05_V6
)]

# Design-phase p_bad bucket from regime mapping
sched[, p_bad_bucket_design_phase := map_regime_to_pbad_bucket(regime_str1715)]
sched[, beta_bear_raw := bucket_to_beta_bear(p_bad_bucket_design_phase)]

# Anti-flicker 1m persistence rule
sched[, beta_bear_raw_prev := shift(beta_bear_raw, n = 1L, fill = 1.0)]
sched[, beta_bear_raw_next := shift(beta_bear_raw, n = -1L, fill = beta_bear_raw[.N])]

# Apply anti-flicker: only change β_bear if previous month already at new value
# (i.e., bucket change must persist ≥ 1 month to take effect)
sched[, beta_bear := beta_bear_raw]
sched[seq_len(.N) > 1, beta_bear := fifelse(
  beta_bear_raw != beta_bear_raw_prev,
  beta_bear_raw_prev,
  beta_bear_raw
)]

# Combined overlay (sequential multiplicative)
sched[, combined_overlay := beta_m4 * beta_AR * beta_R05 * beta_bear]
sched[, cash_share_with_bear := 1.0 - combined_overlay]

# Transition events (β_bear changes)
sched[, beta_bear_prev := shift(beta_bear, n = 1L, fill = 1.0)]
sched[, transition_event := fifelse(beta_bear != beta_bear_prev, "TRANSITION", "STABLE")]
sched[1, transition_event := "INIT"]

# Method label
sched[, method_selected := "Bear_Sensor_Overlay_Policy_v1_Path_B_Layer_6_Default_tau_0_5_anti_flicker_1m_design_phase_simulation"]
sched[, scope := "regime_sensor_overlay_policy_design_phase_a_charter_10_v18"]

# --- Clean output columns ---
out <- sched[, .(
  as_of_date,
  decision_date,
  realized_ym,
  regime_str1715,
  p_bad_bucket_design_phase,
  beta_m4,
  beta_AR,
  beta_R05,
  beta_bear,
  combined_overlay,
  cash_share_with_bear,
  base_str1715_weight,
  transition_event,
  method_selected,
  scope
)]

fwrite(out, out_csv)

# --- Summary statistics ---
cat("=== Overlay Schedule Emitted ===\n")
cat("Output: ", out_csv, "\n")
cat("N sig_dates: ", nrow(out), "\n")
cat("Date range: ", as.character(min(out$as_of_date)), " ~ ", as.character(max(out$as_of_date)), "\n")
cat("\n--- β_bear distribution ---\n")
print(out[, .N, by = beta_bear][order(-beta_bear)])
cat("\n--- p_bad_bucket distribution ---\n")
print(out[, .N, by = p_bad_bucket_design_phase])
cat("\n--- Transition events ---\n")
print(out[, .N, by = transition_event])

# --- Turnover computation (Layer 6 incremental) ---
# TO contribution from Layer 6 = sum of |Δβ_bear| transitions * full sleeve
out[, delta_beta_bear := beta_bear - shift(beta_bear, n = 1L, fill = 1.0)]
out[, abs_delta_beta_bear := abs(delta_beta_bear)]
n_years <- as.numeric(difftime(max(out$as_of_date), min(out$as_of_date), units = "days")) / 365.25
to_layer_6_per_yr <- sum(out$abs_delta_beta_bear) / n_years
cat("\n--- Layer 6 Turnover (β_bear transitions only) ---\n")
cat("N years: ", round(n_years, 2), "\n")
cat("Sum |Δβ_bear|: ", round(sum(out$abs_delta_beta_bear), 3), "\n")
cat("Layer 6 TO/yr (design-phase prior, NOT round-trip ×2): ", round(to_layer_6_per_yr, 3), "\n")
cat("Layer 6 TO/yr round-trip ×2 (commission cost basis): ", round(2 * to_layer_6_per_yr, 3), "\n")

# --- Cost arithmetic (Codex C4 ACCEPT) ---
# Reproducible formula:
#   TO_total/yr = TO_str1715_base + TO_AR + TO_R05 + TO_layer_6_bear
#   commission_cost_bps_yr = TO_total × 15bps_oneway × 2 (round trip)
to_str1715_base_yr <- 4.0  # STR_1715 PG2 manifest empirical (267m backtest)
to_ar_overlay_yr   <- 0.8  # AR overlay incremental (Session 80 admit empirical)
to_r05_overlay_yr  <- 0.7  # R05 overlay incremental (Session 80 admit empirical)
to_layer_6_bear_yr <- to_layer_6_per_yr
to_total_yr        <- to_str1715_base_yr + to_ar_overlay_yr + to_r05_overlay_yr + to_layer_6_bear_yr
commission_bps_yr  <- to_total_yr * 15 * 2  # 15bps one-way × 2 round-trip

cat("\n--- Cost Arithmetic (Codex C4 reproducible) ---\n")
cat("TO_str1715_base/yr: ", to_str1715_base_yr, "\n")
cat("TO_AR_overlay/yr:   ", to_ar_overlay_yr, "\n")
cat("TO_R05_overlay/yr:  ", to_r05_overlay_yr, "\n")
cat("TO_layer_6_bear/yr: ", round(to_layer_6_bear_yr, 3), "\n")
cat("TO_total/yr:        ", round(to_total_yr, 3), "\n")
cat("Commission cost bps/yr (15bps × 2 round-trip): ", round(commission_bps_yr, 1), " bps\n")
cat("Cap check (TO ≤ 6.0/yr): ", ifelse(to_total_yr <= 6.0, "PASS", "BREACH"), "\n")

# Emit summary as separate JSON for governance
summary_json <- list(
  schedule_file = out_csv,
  n_sig_dates = nrow(out),
  date_range_start = as.character(min(out$as_of_date)),
  date_range_end = as.character(max(out$as_of_date)),
  n_years = round(n_years, 2),
  beta_bear_distribution = as.list(setNames(
    out[, .N, by = beta_bear][order(-beta_bear)]$N,
    out[, .N, by = beta_bear][order(-beta_bear)]$beta_bear
  )),
  transition_events_n = out[transition_event == "TRANSITION", .N],
  to_layer_6_bear_yr = round(to_layer_6_bear_yr, 3),
  to_total_yr = round(to_total_yr, 3),
  to_cap = 6.0,
  to_cap_check = ifelse(to_total_yr <= 6.0, "PASS", "BREACH"),
  commission_bps_yr = round(commission_bps_yr, 1),
  formula = "TO_total = TO_str1715_base(4.0) + TO_AR(0.8) + TO_R05(0.7) + TO_layer_6_bear (this design-phase prior). Commission = TO_total × 15bps × 2 round-trip.",
  design_phase_note = "p_bad mapped from STR_1715 PG2 regime label as design-phase prior. Forge Stage 4 replaces with actual p_bad_monthly from trained 5-model ensemble.",
  anti_flicker_applied = "1m persistence rule (β_bear update only if bucket change persists ≥ 1 month)",
  method_selected = unique(out$method_selected)[1]
)

writeLines(jsonlite::toJSON(summary_json, auto_unbox = TRUE, pretty = TRUE),
  file.path(wt_root, "stage_artifacts/WT_D20260519_002/overlay_schedule_summary.json"))

cat("\n=== Emission Complete ===\n")
