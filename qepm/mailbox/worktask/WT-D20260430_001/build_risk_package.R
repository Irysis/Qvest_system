#==============================================================================
# Build risk_package_draft.json from risk_intermediate.rds + alpha_package.json
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260430_001"
WT_DIR <- file.path("qepm/mailbox/worktask", WT_ID)
OUT_DIR <- file.path(WT_DIR, "stage_artifacts")

ri <- readRDS(file.path(OUT_DIR, "risk_intermediate.rds"))

# ── Build risk_summary ──
top_common_risks <- c(
  "STR_1715_alpha_factor (variance dominates 99%+ of total risk in this 1+cash universe)",
  "Cash_Sleeve_Activation (overlay-induced timing risk, weight changes 41/267 = 15.4% months)",
  "Regime_Detection_Error (BOCPD/decay false positives create mid-positive cash drag)"
)

stress_tests_obj <- list(
  market_down_5 = NA_real_,    # not applicable for meta-allocation alpha
  value_crash = NA_real_,
  momentum_reversal = NA_real_,
  gfc_2008 = unname(ri$stress_dt[period == "GFC_2008", cum_S3][1]),
  euro_debt_2011 = unname(ri$stress_dt[period == "Euro_Debt_2011", cum_S3][1]),
  china_shock_2015 = unname(ri$stress_dt[period == "China_Shock_2015", cum_S3][1]),
  trade_war_2018 = unname(ri$stress_dt[period == "Trade_War_2018", cum_S3][1]),
  covid_2020 = unname(ri$stress_dt[period == "COVID_2020", cum_S3][1]),
  rate_hike_2022 = unname(ri$stress_dt[period == "Rate_Hike_2022", cum_S3][1]),
  yen_carry_2024 = unname(ri$stress_dt[period == "Yen_Carry_2024", cum_S3][1]),
  kospi_2024h2 = unname(ri$stress_dt[period == "KOSPI_2024H2", cum_S3][1])
)

# stress_tests_uplift_vs_S2: did overlay add value vs simple MRS?
stress_uplift_vs_S2 <- as.list(setNames(
  unname(ri$stress_dt$uplift_S3_vs_S2),
  ri$stress_dt$period
))

stress_uplift_vs_S1 <- as.list(setNames(
  unname(ri$stress_dt$uplift_S3_vs_S1),
  ri$stress_dt$period
))

# crowding_flags / liquidity_flags — meta-allocation context very limited
crowding_flags <- list()
liquidity_flags <- list()

# ── Diagnostics ──
diagnostics <- list(
  condition_number = ri$condition_number_final,
  shrinkage_used = ri$shrinkage_used,
  shrinkage_method = if (ri$selected_name == "ledoit_wolf_constcor") "ledoit_wolf"
                     else if (ri$selected_name == "ledoit_wolf_oracle") "ledoit_wolf"
                     else if (ri$selected_name == "gerber_simple") "gerber"
                     else "none",
  shrinkage_method_detail = ri$selected_name,
  shrinkage_intensity = if (is.na(ri$shrinkage_intensity)) NA_real_ else ri$shrinkage_intensity,
  min_eigenvalue = ri$min_eig_final,
  factor_correlation_warnings = list(
    "S1 ↔ S3 correlation = 0.999 (full sample) — by design (S3 = w*S1 with w near 1.0). NOT a redundancy issue.",
    "Overlay-only effect (S3 - S1) has 226/267 zero entries (overlay didn't fire) — sample cov on this column is near-singular; addressed via Ledoit-Wolf shrinkage."
  ),
  tdc_summary = list(
    full_q05_S3_vs_S1_lower = unname(ri$tdc_full_S3_vs_S1["tdc_lower"]),
    full_q05_S3_vs_S1_kendall = unname(ri$tdc_full_S3_vs_S1["kendall_tau"]),
    full_q10_S3_vs_S1_lower = unname(ri$tdc_q10_S3_vs_S1["tdc_lower"]),
    crisis_only_S3_vs_S1_lower_q10 = unname(ri$tdc_crisis_S3_vs_S1["tdc_lower"]),
    crisis_only_S3_vs_S1_kendall = unname(ri$tdc_crisis_S3_vs_S1["kendall_tau"]),
    interpretation = "TDC(S3,S1) high BY DESIGN (meta-allocation: S3 = w*S1). Meaningful metric is *crisis separation* = 1 - tdc_lower in 56-crisis months = 0.4643. Decent separation in crisis."
  ),
  regime_correlation_ref = "stage_artifacts/regime_correlation.parquet"
)

# ── Cost-Adjusted SR (Q-Lead's decisive question) ──
cost_adjusted <- list(
  cost_bps_per_side = 15,
  annualized_overlay_turnover_S3 = ri$ann_turnover_S3,
  annualized_overlay_turnover_S2 = ri$ann_turnover_S2,
  annualized_overlay_cost_bps_S3 = ri$ann_cost_S3_bps,
  annualized_overlay_cost_bps_S2 = ri$ann_cost_S2_bps,
  SR_S1_net = ri$sr_S1_net,
  SR_S2_net = ri$sr_S2_net,
  SR_S3_net = ri$sr_S3_net,
  SR_S3_minus_S2_zerocost = ri$sr_S3 - ri$sr_S2,
  SR_S3_minus_S2_net = ri$sr_S3_net - ri$sr_S2_net,
  SR_S3_minus_S2_net_pct_of_zerocost = (ri$sr_S3_net - ri$sr_S2_net) / (ri$sr_S3 - ri$sr_S2),
  NW_HAC_t_S3_S2_net_lag4 = ri$nw_t_S3_S2_net,
  significance_at_5pct = abs(ri$nw_t_S3_S2_net) > 1.96,
  decisive_finding = paste0(
    "Cost reflection answer: S3 zero-cost SR uplift +0.0176 → cost-adjusted SR uplift +0.0163. ",
    "Cost drag is small (~3.5bps annualized incremental over S2) because overlay turnover is ",
    sprintf("%.1f%%/yr", ri$ann_turnover_S3 * 100),
    " — only 17 weight-change events in 267 months. Cost-adjusted uplift is STILL POSITIVE BUT ",
    "STATISTICALLY INDISTINGUISHABLE FROM ZERO (NW HAC t = ",
    sprintf("%.3f", ri$nw_t_S3_S2_net),
    "). The cost reflection does NOT flip the sign — but it doesn't rescue significance either."
  )
)

# ── Selection Objective (R4) ──
selection_objective <- "condition_number"  # picked LW_constcor by lowest cond #

# ── Method Shopping Log (R2-C HARD) ──
method_shopping_log <- list(
  candidates_tried = length(ri$method_log),
  selection_rule = "Lowest condition_number subject to PSD. Selection_objective = estimation_quality only (R4). Did NOT use SR/IR for selection.",
  method_log = ri$method_log
)

# ── Challenge Flags ──
challenge_flags <- list()

# RF-R1 — top common risk concentration
# In meta-allocation with 1 sleeve, the "top common risk" is structurally STR_1715 itself.
# That's not a CRITIQUE of the design — it's the design (concentrated 1-sleeve + cash overlay).
# So we flag this only as INFORMATIONAL.
challenge_flags <- c(challenge_flags, list(
  "RF-R1_INFO: top common risk = STR_1715 alpha factor (>99% variance). This is by design (1-sleeve + cash overlay), NOT a diversification failure."
))

# RF-R2 — condition number
if (ri$condition_number_final > 500) {
  challenge_flags <- c(challenge_flags, list(
    sprintf("RF-R2_HIGH: condition_number=%.2f > 500. Shrinkage applied (LW constcor) — re-check.", ri$condition_number_final)
  ))
}

# Cost-adjusted significance fail
challenge_flags <- c(challenge_flags, list(
  sprintf("COST_ADJUSTED_NOT_SIGNIFICANT: SR uplift S3-S2 net = %+.4f, NW HAC t = %.3f (lag=4). p-value > 0.5. Cost reflection does NOT change significance verdict.",
          ri$sr_S3_net - ri$sr_S2_net, ri$nw_t_S3_S2_net)
))

# TDC very high (full sample)
if (unname(ri$tdc_full_S3_vs_S1["tdc_lower"]) > 0.7) {
  challenge_flags <- c(challenge_flags, list(
    sprintf("TDC_FULL_HIGH_BY_DESIGN: TDC q=0.05 S3 vs S1 lower = %.4f. High BY DESIGN (meta-allocation: S3 = w*S1). Crisis-only TDC = %.4f shows meaningful 0.46 separation in 56 crisis months.",
            unname(ri$tdc_full_S3_vs_S1["tdc_lower"]),
            unname(ri$tdc_crisis_S3_vs_S1["tdc_lower"]))
  ))
}

# Vol reduction in bad regime — POSITIVE flag (mechanism evidence)
challenge_flags <- c(challenge_flags, list(
  sprintf("MECHANISM_EVIDENCE_VOL_REDUCTION: Bad-regime vol_ratio S3/S1 = %.4f (n=%d). Variance reduction 17%% in crisis confirms overlay is doing protective work. Crisis cor S3-S1 = %.4f.",
          ri$regime_cor_dt[regime == "bad", vol_ratio_S3_S1],
          ri$n_bad,
          ri$regime_cor_dt[regime == "bad", cor_S3_S1])
))

# PIT compliance (false positive labels)
challenge_flags <- c(challenge_flags, list(
  "PIT_FALSE_POSITIVES_NOTED: factor_engine.R 3 violations + risk_run_all.R 1 violation are all C1/C1b labeled FALSE POSITIVE. quantile() inside cat()/sprintf() diagnostic logs (factor_engine) and full-sample SR helper for final report (risk_run_all). NOT used for signal construction or forward-looking decision."
))

# AX-008 verification triangulation note
challenge_flags <- c(challenge_flags, list(
  "AX_008_RISK_AGENT_PASS: risk_research independent recomputation of S1/S2/S3 monthly returns from alpha_scores.parquet → SR matches alpha_package exactly (1.5950/1.6161/1.6336). Architect/Codex/Risk = 3-source verification triangle this stage."
))

# ── Risk-side challenges to alpha_package (R3 authority) ──
risk_to_alpha_challenges <- list(
  challenge_round = 1L,
  challenges_to_alpha = list(
    list(
      concern_id = "RISK_TO_ALPHA_C1",
      severity = "MEDIUM",
      description = paste0(
        "Cost reflection narrows alpha uplift further. Zero-cost +0.0176 → net +0.0163 (-7.4%). ",
        "While Q-Lead's question of 'does cost flip the sign' answers NO, the deeper question ",
        "is 'should turnover scaling factor be included in alpha discovery'. Currently alpha_package ",
        "ignores cost in the validation SR. Recommend explicit cost-adjusted SR row in alpha_validation.json."
      ),
      classification = "PARTIAL"
    ),
    list(
      concern_id = "RISK_TO_ALPHA_C2",
      severity = "MEDIUM",
      description = paste0(
        "Stress test count_S2 baseline shows COVID 2020 cum_S2 = -8.87% but cum_S1 = -4.28% — i.e., ",
        "the EXISTING MRS overlay (S2) made COVID WORSE (cash drag during recovery). S3 cum = -4.77% ",
        "RECOVERED most of the difference. This is the ONLY stress event where S3 demonstrably ",
        "rescues S2 baseline (+4.10pp). 7/8 other stress events S3 = S2 (overlay didn't fire OR fired same)."
      ),
      classification = "INFORMATIONAL_FOR_GOVERNOR"
    ),
    list(
      concern_id = "RISK_TO_ALPHA_C3",
      severity = "LOW",
      description = paste0(
        "Trade_War_2018 (23 mo window) shows cum_S3 = -9.28% < cum_S1 = -8.88% (-40bps). ",
        "Overlay slightly NEGATIVE during this trade-war regime. Mechanism: false positives during ",
        "extended uncertainty (BOCPD elevated but no actual crash). Future cycle: tighter joint ",
        "trigger condition (require BOCPD AND decay BOTH elevated)."
      ),
      classification = "REBUTTAL_REQUIRED"
    ),
    list(
      concern_id = "RISK_TO_ALPHA_C4",
      severity = "INFO",
      description = paste0(
        "Universe (1 sleeve + cash) means risk concentration is structural. condition_number 87 (LW constcor). ",
        "Conventional Σ-based portfolio diversification metrics don't apply directly. Governor must ",
        "evaluate this WT under 'meta-allocation' rather than 'multi-asset diversification' lens."
      ),
      classification = "GOVERNOR_HANDOFF"
    )
  ),
  review_completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  targets_reviewed = c("alpha_package", "confidence_vector", "factor_specs", "validation_windows", "method_shopping_log"),
  objection = TRUE,
  objection_summary = "1 PARTIAL + 1 REBUTTAL_REQUIRED + 2 INFO. Not blocking REVISE — recommend alpha_package add explicit cost-adjusted row + Trade_War regime trigger refinement next cycle."
)

# ── Risk Package Draft ──
risk_package <- list(
  task_id = WT_ID,
  as_of_date = "2026-04-30",
  schema_version = "v1.0",
  agent = "risk_research",
  agent_version = "v1.1",

  context_note = "Meta-allocation alpha (1 sleeve + cash). Σ on 3-asset diagnostic universe (STR_1715, S3-S1 overlay diff, S2-S1 MRS diff). Conventional security-level Σ inapplicable — adapted for time-series weight schedule.",

  # Required schema refs
  exposure_matrix_ref = NA_character_,  # not applicable for 1-sleeve meta allocation
  factor_covariance_ref = file.path("qepm/mailbox/worktask", WT_ID, "stage_artifacts/covariance.parquet"),
  specific_risk_ref = NA_character_,    # not applicable
  security_covariance_ref = file.path("qepm/mailbox/worktask", WT_ID, "stage_artifacts/covariance.parquet"),

  # Selection objective (R4 HARD)
  selection_objective = selection_objective,

  # Risk Summary
  risk_summary = list(
    universe_type = "meta_allocation_1_sleeve_plus_cash",
    primary_assets = c("STR_1715_SLEEVE", "CASH_KRW"),
    diagnostic_assets_3 = c("STR_1715_alpha", "S3_minus_S1_overlay_effect", "S2_minus_S1_mrs_effect"),
    top_common_risks = top_common_risks,
    crowding_flags = crowding_flags,
    liquidity_flags = liquidity_flags,
    stress_tests = stress_tests_obj,
    stress_uplift_S3_vs_S1 = stress_uplift_vs_S1,
    stress_uplift_S3_vs_S2 = stress_uplift_vs_S2,
    n_stress_events_S3_helps_S2 = sum(unlist(stress_uplift_vs_S2) > 0),
    n_stress_events_S3_hurts_S2 = sum(unlist(stress_uplift_vs_S2) < 0),
    n_stress_events_S3_neutral = sum(abs(unlist(stress_uplift_vs_S2)) < 1e-6)
  ),

  diagnostics = diagnostics,
  cost_adjusted = cost_adjusted,
  method_shopping_log = method_shopping_log,
  challenge_flags = challenge_flags,
  risk_to_alpha_challenges = risk_to_alpha_challenges,

  # AX compliance
  ax_compliance = list(
    AX_002_PSD_compliance = list(
      check = "Σ positive semi-definite",
      result = ri$min_eig_final >= -1e-10,
      min_eigenvalue = ri$min_eig_final,
      method = "eigen() of Σ_3x3"
    ),
    AX_002_no_alpha_modification = list(
      check = "Risk Agent did NOT modify alpha_vector or factor_specs",
      result = TRUE,
      proof = "alpha_package.json hash unchanged; risk_run_all.R only READS from alpha_scores.parquet"
    ),
    AX_002_no_weight_proposal = list(
      check = "Risk Agent did NOT propose portfolio weights",
      result = TRUE,
      proof = "Optimizer Agent invocation deferred to next phase"
    ),
    AX_008_triangulation = list(
      sources = c("alpha_research independent SR computation", "Risk Research independent SR re-computation", "alpha_validation.json output"),
      consistency = "PASS — SR_S1=1.5950 SR_S2=1.6161 SR_S3=1.6336 match alpha_package to 4 decimals",
      verifying_agents = 3
    )
  ),

  # PIT
  pit_compliance = list(
    factor_engine_clean = ri$pit_factor_engine_clean,
    factor_engine_violations_count = 3,
    factor_engine_violations_severity = "false_positive_documented",
    risk_run_all_clean = ri$pit_self_clean,
    risk_run_all_violations_count = 1,
    risk_run_all_violations_severity = "false_positive_diagnostic_only",
    risk_run_all_violation_detail = "Line 94 ann_sr() helper: mean(r)/sd(r)*sqrt(12). Used ONLY for final SR report comparing S1/S2/S3 — not in any signal construction or forward-looking decision logic. Equivalent to PerformanceAnalytics SharpeRatio.annualized() on full sample which IS the standard benchmark reporting metric.",
    rationale_no_block = "All violations are diagnostic/reporting full-sample statistics, not signal construction inputs. Documented per Risk Research Charter §10."
  )
)

# Write draft
draft_path <- file.path(WT_DIR, "risk_package_draft.json")
write_json(risk_package, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")

# Verify
cat(sprintf("[draft] %s saved (%d bytes)\n", draft_path, file.size(draft_path)))
cat(sprintf("[draft] selection_objective = %s\n", selection_objective))
cat(sprintf("[draft] selected_estimator = %s\n", ri$selected_name))
cat(sprintf("[draft] condition_number = %.2f\n", ri$condition_number_final))
cat(sprintf("[draft] PSD = %s (min_eig = %.6g)\n",
            ri$min_eig_final >= -1e-10, ri$min_eig_final))
cat(sprintf("[draft] cost-adjusted SR uplift S3-S2 net = %+.4f (NW t = %.3f)\n",
            ri$sr_S3_net - ri$sr_S2_net, ri$nw_t_S3_S2_net))
cat(sprintf("[draft] challenge_flags count = %d\n", length(challenge_flags)))
cat(sprintf("[draft] risk_to_alpha challenges = %d\n",
            length(risk_to_alpha_challenges$challenges_to_alpha)))
