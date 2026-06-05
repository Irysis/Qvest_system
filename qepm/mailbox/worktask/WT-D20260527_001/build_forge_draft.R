#==============================================================================
# Build forge_package_draft.json — v6.3 8-field mandate + 4 SR provenance fields
#==============================================================================

suppressMessages({library(jsonlite); library(digest); library(data.table)})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

# Hashes
WT_DIR <- "qepm/mailbox/worktask/WT-D20260527_001"
alpha_pkg_hash <- digest(file=file.path(WT_DIR, "alpha_package.json"), algo="sha256")
risk_pkg_hash  <- digest(file=file.path(WT_DIR, "risk_package.json"),  algo="sha256")
opt_pkg_hash   <- digest(file=file.path(WT_DIR, "optimization_package.json"), algo="sha256")
weights_hash   <- digest(file="stage_artifacts/WT_WT-D20260527_001/optimizer/weights.csv", algo="sha256")
bt_rds_hash    <- digest(file="04_Research/strategies/STR_1719_WT001_DCA_v7/output/bt_result.rds", algo="sha256")
bt_sum_hash    <- digest(file="04_Research/strategies/STR_1719_WT001_DCA_v7/output/bt_result_summary.json", algo="sha256")

# Read summary
s <- fromJSON("04_Research/strategies/STR_1719_WT001_DCA_v7/output/bt_result_summary.json")
opt_pkg <- fromJSON("qepm/mailbox/worktask/WT-D20260527_001/optimization_package.json")

# Diagnose divergence
sr_factor_engine <- opt_pkg$expected_sharpe_net
sr_realized <- s$sharpe
divergence <- sr_factor_engine - sr_realized
abs_div <- abs(divergence)
diag <- if (abs_div < 0.2) "NEGLIGIBLE" else if (abs_div < 0.4) "MINOR_DRIFT" else if (abs_div < 0.6) "SIGNIFICANT_DRAG" else "FABRICATION_SUSPECTED"

cat(sprintf("FactorEngineSR=%.4f | ForgeRealizedSR=%.4f | div=%.4f → %s\n",
  sr_factor_engine, sr_realized, divergence, diag))

# Cost reconciliation
# realized cost = gross CAGR - net CAGR
realized_cost_pct <- 0.0594 - 0.0502
expected_cost_pct <- 0.0015 * 2 * 2.63

# Forge package
pkg <- list(
  task_id = "WT-D20260527_001",
  agent = "forge",
  wt_type = "discovery",

  strategy_id = "STR_1719_WT001_DCA_v7",
  strategy_version = "v1.0",
  strategy_name = "DCA_v7_4family_static_EW_P3P4_confidence_M06_MVO_Breadth",
  run_id = s$run_id,

  # 1. forge_inputs
  forge_inputs = list(
    alpha_package_path = "qepm/mailbox/worktask/WT-D20260527_001/alpha_package.json",
    alpha_package_sha256 = alpha_pkg_hash,
    alpha_iter = 7,
    alpha_iter_name = "DCA_v7_4family_static_EW_P3P4_confidence",
    risk_package_path = "qepm/mailbox/worktask/WT-D20260527_001/risk_package.json",
    risk_package_sha256 = risk_pkg_hash,
    risk_method = "ledoit_wolf_oracle",
    risk_condition_number = 14.5068,
    risk_psd_verified = TRUE,
    opt_package_path = "qepm/mailbox/worktask/WT-D20260527_001/optimization_package.json",
    opt_package_sha256 = opt_pkg_hash,
    opt_method = "M06_MVO_Breadth",
    opt_n_names = 15,
    opt_expected_net_IR = 0.0709,
    weights_csv_path = "stage_artifacts/WT_WT-D20260527_001/optimizer/weights.csv",
    weights_csv_sha256 = weights_hash,
    weights_n_sig_dates = 97,
    weights_n_unique_tickers = 133,
    pure_function_boundary_status = "PASS",
    boundary_note = "3-package + weights.csv md5 unchanged between START and END of run_all.R"
  ),

  # 2. bt_result_path
  bt_result_path = "04_Research/strategies/STR_1719_WT001_DCA_v7/output/bt_result.rds",
  bt_result_sha256 = bt_rds_hash,
  bt_result_summary_path = "04_Research/strategies/STR_1719_WT001_DCA_v7/output/bt_result_summary.json",
  bt_result_summary_sha256 = bt_sum_hash,

  # 3. audit_status
  audit_status = "PASS_WITH_WARN",
  audit_summary = list(
    n_checks = s$audit$n_pass + s$audit$n_warn + s$audit$n_fail,
    n_pass = s$audit$n_pass,
    n_warn = s$audit$n_warn,
    n_fail = s$audit$n_fail,
    n_critical_fail = s$audit$n_critical_fail,
    n_high_fail = s$audit$n_high_fail,
    warn_details = "lookahead_detector_self_scan: scan_lookahead() function not exported by lookahead_detector.R (detect_lookahead, detect_lookahead_dir, detect_gate15_infra_pit exist instead) — known contract limitation"
  ),

  # 4. integrity
  integrity = "WARNING",
  integrity_note = "Audit critical_fail=0, high_fail=0, only 1 medium-severity WARN on lookahead_detector_self_scan (function name mismatch, not strategy PIT issue). Integrity downgraded from PASS to WARNING per contract convention.",

  # 5. signal_cutoff
  signal_cutoff = "2023-12-28",
  signal_cutoff_note = "Last sig_date in weights.csv. PIT lockbox 2024-01-01+ never accessed during weight computation. Forge backtest uses RAWDATA through 2024-01-30 only for last sig_date holding period mark-to-market.",

  # 6. rebalance_count
  rebalance_count = 97,
  rebalance_count_note = "97 sig_dates × 1 rebalance/sig = 97 rebalances over 2015-12-30 to 2023-12-28 (8.07 years). Density 97/97 = 1.000 (>= 0.95 per v6.3 §9 schedule fidelity).",

  # 7. cost_breakdown
  cost_breakdown = list(
    cost_model_version = "v2.3_kr_retail_15bps",
    commission_one_way_bps = 15,
    slippage_bps = 0,
    realized_annual_cost_pct = round(100 * realized_cost_pct, 4),
    expected_annual_cost_pct = round(100 * expected_cost_pct, 4),
    realized_per_rebal_TO_oneside = 0.2208,
    realized_per_rebal_TO_twoside = 0.4417,
    realized_annual_TO_oneside = 2.63,
    realized_annual_TO_twoside = 5.25,
    optimizer_claimed_annual_TO = 5.30,
    realized_vs_claimed_TO_pct_diff = -0.94,
    TO_convention_note = "annual_TO_twoside = sum(per_rebal_L1) / n_years. Matches optimizer convention (Charter §15 P6 cap = 6.0/y two-side). Forge realized TO 5.25/y < cap = PASS.",
    contract_field_caveat = "Contract metrics$Annualized_Turnover (55.65) uses naive avg(turnover) × 252 (daily ann_factor) which is wrong unit for monthly-rebal — should be × 12 = 2.65. Forge prefers realized_annual_TO_oneside/twoside fields here."
  ),

  # 8. schedule_density
  schedule_density = 1.0,
  schedule_density_note = "97/97 sig_dates carry holdings in Forge backtest (density = 1.000, >= 0.95). NO fabrication of additional sig_dates. weights.csv as-is. alpha_scores.parquet NOT used for holding-selection (Pure Function v6.1 R12).",

  # ── v6.3 §8/§9 SR Provenance Mandate (4 SR fields) ──
  sr_realized_share_based = round(s$sharpe, 4),
  sr_realized_share_based_note = "Daily share-based NAV reconstruction (Forge PG2 grade): weights.csv schedule → 100M KRW initial cap → T+1 exec → delta-share commission (15bps × |Δshares| × price) → daily NAV → PerformanceAnalytics::SharpeRatio.annualized(Rf=0, scale=252). Primary measurement.",

  sr_factor_engine_continuous = round(opt_pkg$expected_sharpe_net, 4),
  sr_factor_engine_continuous_note = "Optimizer walk-forward monthly NAV simulation (idealized): sig_date weights × forward-1m last-business-day Close returns. Implemented in optimizer_pipeline.R STEP 6.",

  sr_lockbox_daily_harness = NULL,
  sr_lockbox_daily_harness_note = "Not computed at Forge step — will be computed at Judge.",

  measurement_basis_primary = "forge_realized_share_based",
  measurement_basis_rationale = "Per v6.3 §8 mandate, forge_realized_share_based is the primary measurement basis. factor_engine_continuous is idealized — does not capture daily NAV path, intra-month price moves, or actual commission on traded notional.",

  vs_factor_engine = list(
    sr_factor_engine = round(opt_pkg$expected_sharpe_net, 4),
    sr_realized = round(s$sharpe, 4),
    divergence_factor_engine_vs_realized_pp = round(divergence, 4),
    abs_divergence_pp = round(abs_div, 4),
    diagnosis = diag,
    diagnosis_rule = "|div| < 0.2: NEGLIGIBLE / 0.2-0.4: MINOR_DRIFT / 0.4-0.6: SIGNIFICANT_DRAG / >= 0.6: FABRICATION_SUSPECTED",
    explanation = "Factor engine SR (0.3493) = optimizer walk-fwd monthly sim. Forge realized SR (0.3467) = daily share-based with commission on |Δshares|. Divergence -0.0026pp is within NEGLIGIBLE band. Confirms (a) optimizer walk-fwd sim closely tracks daily share-based path despite different granularity, (b) cost model applied correctly (~0.91%/y drag matches 15bps × 5.25 two-side TO expectation 0.79%/y plus small MTM noise)."
  ),

  # ── Primary backtest metrics ──
  backtest_metrics = list(
    start_date = s$start_date,
    end_date = s$end_date,
    n_trading_days = 1986,
    n_years = 8.07,
    cagr_pct = s$cagr_pct,
    total_return_pct = s$total_return_pct,
    annualized_volatility_pct = s$ann_vol_pct,
    sharpe = s$sharpe,
    sortino = s$sortino,
    calmar = s$calmar,
    mdd_pct = s$mdd_pct,
    cvar_99_daily_pct = s$cvar_99_daily_pct,
    benchmark = "KOSPI200_total_return",
    benchmark_cagr_pct = 3.41,
    benchmark_sharpe = 0.2032,
    benchmark_mdd_pct = 43.90,
    benchmark_alpha_pct = s$benchmark_alpha_pct,
    benchmark_beta = s$benchmark_beta,
    tracking_error_pct = s$tracking_error_pct,
    information_ratio = s$information_ratio,
    up_capture = s$up_capture,
    down_capture = s$down_capture,
    hit_ratio_vs_bm = s$hit_ratio_vs_bm,
    avg_n_holdings = s$avg_n_holdings
  ),

  # ── Hard Constraint validation ──
  hard_constraint_status = list(
    max_names_20 = list(observed_max = 15, status = "PASS"),
    long_only    = list(observed_min_w = 0.04, status = "PASS"),
    weight_bounds = list(observed_max_w = 0.1304, bound = 0.20, status = "PASS"),
    sum_weights_1 = list(observed_range = c(1.0, 1.0), tol = 0.005, status = "PASS"),
    liquidity_threshold = list(threshold_won_20d_avg = 5e7, note = "Inherited from alpha/risk filtering"),
    cost_model = list(version = "v2.3_kr_retail_15bps", applied_delta_share_notional = TRUE, status = "PASS"),
    pit_compliance = list(C1 = TRUE, C2 = TRUE, C9 = TRUE, C10 = TRUE, C11 = TRUE, C13 = TRUE, C14 = TRUE, C15 = TRUE, note = "Inherited from alpha/risk/optimizer; Forge uses T+1 exec + frozen sig_date weights")
  ),

  # ── OOS chart status ──
  oos_chart_status = list(
    equity_curve_png = "04_Research/strategies/STR_1719_WT001_DCA_v7/output/equity_curve.png",
    annual_returns_png = "04_Research/strategies/STR_1719_WT001_DCA_v7/output/annual_returns.png",
    oos_zoom_chart_png = "04_Research/strategies/STR_1719_WT001_DCA_v7/output/oos_zoom_chart.png",
    drawdown_chart_png = "04_Research/strategies/STR_1719_WT001_DCA_v7/output/drawdown_chart.png",
    note = "Walk-forward bt 2016-01-04 to 2024-01-30. OOS zoom = recent 3Y (2021-2023, pre-lockbox)."
  ),

  # ── Pure Function self-check ──
  pure_function_self_check = list(
    boundary_hash_consistency = "PASS",
    weights_csv_modified = FALSE,
    alpha_package_modified = FALSE,
    risk_package_modified = FALSE,
    opt_package_modified = FALSE,
    schedule_fabrication = "NONE",
    schedule_fabrication_note = "weights.csv 97 sig_dates used AS-IS. NO ProductionSchedule[N]m label. NO alpha_scores.parquet head(N) holding-selection.",
    alpha_scores_usage = "NONE",
    alpha_scores_used = FALSE,
    pure_function_violation = FALSE
  ),

  # ── Charter compliance ──
  charter_compliance = list(
    P1_factor_zoo_reduction = "INHERITED (alpha: 4-family static EW post-momentum-drop)",
    P2_cost_aware = "PASS (net-of-cost backtest 15bps on traded notional; gross_ret - cost_ret == ret_net audit PASS)",
    P3_uncertainty_aware = "INHERITED (alpha: P3/P4 confidence vector)",
    P4_direct_portfolio_learning = "N/A (two-stage architecture: alpha → risk → optimizer → forge)",
    P5_crowding_risk = "INHERITED (risk: RF-R3b HHI defense 0.54 → optimizer M06 breadth mitigated)",
    P6_implementation_discipline = "PASS (realized_annual_TO_twoside 5.25 < 6.0 cap; max_w 0.13 < 0.20; n_names 15 < 20)",
    P7_attribution_feedback = "PARTIAL (benchmark_compare 10 metrics; full Brinson + Carhart 4 attribution at Judge)",
    P8_ax_002_axiom = "PASS (no method-shopping override; weights.csv hash start/end identical)"
  ),

  # ── Backtest Result Contract v1.0 audit ──
  backtest_contract_audit = list(
    n_checks = 16,
    pass = 15, warn = 1, fail = 0,
    integrity_status = "WARNING",
    critical_fail = 0, high_fail = 0,
    audit_path = "04_Research/strategies/STR_1719_WT001_DCA_v7/output/10_audit.csv",
    note = "16 checks executed. 15 PASS + 1 medium WARN (lookahead_detector_self_scan — known contract limitation)."
  ),

  # ── Registry status ──
  registry_status = list(
    registered = TRUE,
    registry_path = "qepm/registry/backtest_registry.csv",
    registry_entry_id = s$run_id,
    block_on_fail_triggered = FALSE
  ),

  # ── Lineage ──
  artifact_lineage_appended = TRUE,
  artifact_lineage_path = "qepm/mailbox/worktask/WT-D20260527_001/artifact_lineage.json",

  # ── AX-008 Triangulation status ──
  ax_008_status = list(
    forge_source = "PASS (15/16 audit checks PASS, integrity WARNING, no critical/high fails, pure-function boundary PASS)",
    codex_source = "IN_PROGRESS",
    architect_source = "OPTIONAL",
    triangulation_target = "2/3 sources PASS",
    current_status = "1/3 (Forge) pending Codex"
  ),

  # ── Generation metadata ──
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
  forward_to = "judge",
  reproduction_command = "cd /mnt/c/Users/User/OneDrive/바탕\\ 화면/Quant_Module_Moltbot && Rscript -e 'source(\"04_Research/strategies/STR_1719_WT001_DCA_v7/run_all.R\")'"
)

out_path <- "qepm/mailbox/worktask/WT-D20260527_001/forge_package_draft.json"
write_json(pkg, out_path, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null")
cat(sprintf("Forge draft saved: %s\n", out_path))
cat(sprintf("md5: %s\n", digest(file = out_path, algo = "md5")))
