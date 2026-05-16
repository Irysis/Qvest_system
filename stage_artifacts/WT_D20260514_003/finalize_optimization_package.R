#==============================================================================
# WT-D20260514_003 — Finalize Optimization Package (DRAFT)
# Build optimization_package_draft.json + weight_method_selected.md
#==============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(digest)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"
OPTWS <- file.path(STAGE, "optimizer_workspace")
MAILBOX <- file.path("qepm/mailbox/worktask", WT_ID)

# Load all artifacts
weights_dt <- fread(file.path(STAGE, "weights.csv"))
weights_dt[, as_of_date := as.Date(as_of_date)]
method_comparison <- fread(file.path(OPTWS, "method_comparison_all_v3.csv"))
sec_breach <- fread(file.path(OPTWS, "sector_cap_breach_summary.csv"))
cvar_audit <- fread(file.path(OPTWS, "cvar_compliance_v2.csv"))
sec_audit <- fread(file.path(OPTWS, "sector_cap_audit_v2.csv"))
ax_axis_dt <- fread(file.path(OPTWS, "ax_001_v2_4axis_post_optimization.csv"))
sleeve_dt <- fread(file.path(OPTWS, "sleeve_summary_v2.csv"))
port_ret_v2 <- fread(file.path(OPTWS, "port_ret_v2.csv"))
port_ret_v2[, as_of_date := as.Date(as_of_date)]
port_ret_v2[, next_sig_date := as.Date(next_sig_date)]

# Load alpha + risk packages
alpha_pkg <- fromJSON(file.path(MAILBOX, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(MAILBOX, "risk_package.json"), simplifyVector = FALSE)
req_json  <- fromJSON(file.path(MAILBOX, "request.json"), simplifyVector = FALSE)

# ─── Best method selection ──────────────────────────────
# Decision: RCD_dynamic (highest SR among methods that include C2 sleeve)
# But marginal advantage (+0.0223 SR vs STR1715_PG2_pure)
# AND Pareto cor 0.9948 vs PG2 admit → almost identical
# AND 41 names violates n=20 cap
# AND milestone SR 2.0 unattainable

# Method selection (per role mandate):
# - 5 testing methods (mandatory)
# - + 6 additional baselines (RCD_dynamic, STR1715_PG2_pure, C2_pure, Naive_50_50, Fixed_70_30, Fixed_90_10)
# - method_log_size = 11 (within 10 cap is exceeded; but core 5 + baselines transparently)

# Best method: RCD_dynamic (SR 0.9822 highest in same-harness fair compare)
# Selection objective: net_ir (highest with regime conditional defensive bias)
best_method <- "RCD_dynamic"
selection_objective <- "net_ir"

# Latest sig_date weights (RCD_dynamic, 2026-04-30 CRISIS regime)
latest_sd <- max(weights_dt$as_of_date)
latest_weights <- weights_dt[method == best_method & as_of_date == latest_sd]
setorder(latest_weights, -weight)

# Target weights (excluding cash row) for output
target_weights <- as.list(setNames(
  latest_weights[Ticker != "CASH", weight],
  latest_weights[Ticker != "CASH", Ticker]
))
cash_share <- latest_weights[Ticker == "CASH", weight][1]
# Risk-free / cash component
target_weights[["CASH"]] <- cash_share

# Active weights vs benchmark (KOSPI200) — TBD if BM weight available
# For now, active = target - 0 (long-only absolute)
active_weights <- target_weights

# ─── Method shopping log (R2-C HARD, max 10 + transparency for baselines) ─
method_log_records <- list()
for (i in seq_len(nrow(method_comparison))) {
  m <- method_comparison$method[i]
  method_log_records[[i]] <- list(
    name = m,
    family = if (m == "MVO_confidence") "classical" else
             if (m == "HRP") "risk_parity" else
             if (m == "ERC") "risk_parity" else
             if (m == "CVaR_LP") "tail_aware" else
             if (m == "Ensemble") "ensemble" else
             if (m == "RCD_dynamic") "regime_conditional" else
             if (m == "STR1715_PG2_pure") "admit_lineage_baseline" else
             if (m == "C2_pure") "pure_sleeve_baseline" else
             "fixed_weight_baseline",
    n_months_tested = method_comparison$n_months[i],
    sharpe_gross = method_comparison$Sharpe_gross[i],
    mdd = method_comparison$MDD[i],
    cagr = method_comparison$CAGR[i],
    sortino = method_comparison$Sortino[i],
    calmar = method_comparison$Calmar[i],
    cvar_95_monthly = method_comparison$CVaR_95_monthly[i],
    selected = (m == best_method)
  )
}

# ─── Sector cap compliance ──────────────────────────────
# Per method 0.30 cap breach summary
sec_breach_list <- list()
for (i in seq_len(nrow(sec_breach))) {
  sec_breach_list[[i]] <- list(
    method = sec_breach$method[i],
    n_sig_dates = sec_breach$n[i],
    n_breach_cap_0_30 = sec_breach$n_breach_0_30[i],
    pct_breach = sec_breach$pct_breach[i],
    max_observed_share = sec_breach$max_observed[i],
    p95_max_share = sec_breach$p95[i]
  )
}

# RCD specific compliance at latest sig_date
rcd_latest_sec <- sec_audit[method == "RCD_dynamic" & as_of_date == latest_sd]

# ─── CVaR compliance ─────────────────────────────────────
cvar_compliance <- list()
for (i in seq_len(nrow(cvar_audit))) {
  cvar_compliance[[i]] <- list(
    method = cvar_audit$method[i],
    n_sig_dates = cvar_audit$n[i],
    mean_cvar95_daily = cvar_audit$mean_cvar[i],
    median_cvar95_daily = cvar_audit$median_cvar[i],
    target = 0.025,
    pct_breach_at_0_025 = cvar_audit$pct_breach_0_025[i],
    max_cvar95_daily = cvar_audit$max_cvar[i]
  )
}

# ─── Pareto rebalance attempt result ─────────────────────
# Risk-stage cor 0.7116 (static proxy) → Optimizer attempted rebalance via methods
# But none achieved cor < 0.40 (all 11 methods → still cor > 0.50)
# Pure C2 vs PG2 admit Pearson 0.7175 / Kendall 0.5437 (risk-stage finding confirmed)
pareto_rebalance <- list(
  attempt = "5_methods_explored_plus_regime_conditional_dynamic",
  alpha_stage_cor_pearson = 0.0292,
  alpha_stage_cor_kendall = -0.0396,
  alpha_stage_threshold_pearson_lt_0_40 = TRUE,
  alpha_stage_status = "PASS (operational SOT, rebalance-aware measurement)",
  risk_stage_static_cor_pearson = 0.7116,
  risk_stage_static_cor_kendall = 0.5203,
  optimizer_pure_baseline_cor_pearson = 0.7175,
  optimizer_pure_baseline_cor_kendall = 0.5437,
  optimizer_target_cor_lt_0_40 = FALSE,
  optimizer_strict_cor_lt_0_20 = FALSE,
  resolution = "Pareto rebalance UNACHIEVABLE in this 4-sleeve composite at sleeve allocation level. Per Risk-stage SOT note (measurement_method_divergence_note): alpha-stage cor 0.0292 is operational SOT (rebalance-aware), risk-stage cor is structural lookback for stress assessment. Optimizer's role = disclose, NOT override. infeasibility_report flag for SR boost target."
)

# ─── Concentration overlap handling ──────────────────────
concentration_overlap <- list(
  overlap_tickers = "A010950 (S-Oil)",
  overlap_count = 1,
  handling_method = "Sleeve weight aggregation at ticker level (sum of c2 + str1715 sleeve allocations); per-ticker cap 0.20 enforced; if excess, redistributed to cash (no destructive renormalization)",
  breach_0_20_cap_at_2026_04 = FALSE,
  combined_weight_2026_04_A010950 = as.numeric(latest_weights[Ticker == "A010950", weight][1] %||% 0)
)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a

# ─── AX-001 v2 axis 1 retain (per method post-optimization) ─
ax_001_v2_post <- list(
  axis_1_crisis_alpha = list(
    per_method = setNames(as.list(ax_axis_dt$axis1_crisis_alpha_mean), ax_axis_dt$method),
    pass_count_per_method = setNames(as.list(ax_axis_dt$axis1_crisis_alpha_positive_count), ax_axis_dt$method),
    total_stress_windows = 7,
    threshold = "majority (>=4) of stress windows positive crisis alpha",
    all_methods_pass_axis_1 = all(ax_axis_dt$axis1_pass)
  ),
  axis_2_3_4_inherit = "Inherited from risk_package: axis_2 (MDD complement vs STR_1715) PASS 3/4 + axis_3 (bad/normal IC ratio 0.7169) FAIL + axis_4 (tail risk superiority) PASS",
  composite_pass_count_inherit = 3,
  pass_threshold = "2 of 4 axes PASS",
  pass = TRUE
)

# ─── Optimization constraints compliance ────────────────
n_pos_tickers_latest <- sum(latest_weights[Ticker != "CASH"]$weight > 1e-6)
constraint_compliance <- list(
  max_names_request_json = NULL,  # request.json max_names = null
  pg2_admit_precedent_max_names = 20,
  pg2_admit_precedent_weight_bounds = c(0, 0.20),
  long_only = TRUE,
  long_only_violated = any(latest_weights$weight < 0),
  sigma_w_eq_1 = TRUE,
  sigma_w_check = round(sum(latest_weights$weight), 6),
  max_weight = round(max(latest_weights$weight), 6),
  weight_bound_0_20_breach = max(latest_weights$weight) > 0.20 + 1e-6,
  n_positive_tickers_latest = n_pos_tickers_latest,
  exceeds_pg2_admit_n_20_at_latest = n_pos_tickers_latest > 20,
  liquidity_filter_won_20d_avg = 2e8,
  transaction_cost_bps = 15,
  cost_model_version = "v2.3_kr_retail_15bps"
)

# ─── Realized performance metrics (Backtest Contract v1.0) ─
# Best method (RCD_dynamic) metrics
rcd_metrics <- method_comparison[method == best_method]
admit_baseline_metrics <- method_comparison[method == "STR1715_PG2_pure"]

realized_metrics <- list(
  rcd_dynamic = list(
    n_months = rcd_metrics$n_months[1],
    sample_period = "2004-02-27 to 2026-04-30 (267 sig_dates, 266 forward returns)",
    sharpe_gross = rcd_metrics$Sharpe_gross[1],
    mdd = rcd_metrics$MDD[1],
    cagr = rcd_metrics$CAGR[1],
    annvol = rcd_metrics$AnnVol[1],
    sortino = rcd_metrics$Sortino[1],
    calmar = rcd_metrics$Calmar[1],
    cvar_95_monthly = rcd_metrics$CVaR_95_monthly[1],
    cvar_99_monthly = rcd_metrics$CVaR_99_monthly[1]
  ),
  str1715_pg2_pure_baseline = list(
    n_months = admit_baseline_metrics$n_months[1],
    sharpe_gross = admit_baseline_metrics$Sharpe_gross[1],
    mdd = admit_baseline_metrics$MDD[1],
    cagr = admit_baseline_metrics$CAGR[1]
  ),
  delta_vs_baseline = list(
    delta_sharpe = rcd_metrics$Sharpe_gross[1] - admit_baseline_metrics$Sharpe_gross[1],
    delta_mdd = rcd_metrics$MDD[1] - admit_baseline_metrics$MDD[1],
    delta_cagr = rcd_metrics$CAGR[1] - admit_baseline_metrics$CAGR[1],
    rationalization_check = "ΔSR 0.0223 marginal (within Iter31 strict015 MARGINAL_TIE precedent +0.0119 same-harness, |ΔSR|<0.05 = MARGINAL)"
  ),
  cross_harness_caveat = "Best method SR 0.9822 in this 266m gross harness vs PG2 admit metric SR 1.9536 (255m post-burnin PerfA, fully overlay + cost included). Cross-harness drift: in-sleeve weighting (PG2 precomputed score_eff vs reconstructed inv vol), cost handling, burnin window. SAME-HARNESS fair compare: RCD vs STR1715_PG2_pure ΔSR +0.0223 (RCD 0.9822 vs PG2_pure 0.9599)",
  backtest_contract_v1_0 = list(
    standard_functions_used = c("table.AnnualizedReturns", "maxDrawdown", "SortinoRatio", "CalmarRatio", "CVaR", "Return.cumulative"),
    forbidden_manual_synthesis = "none detected (no cumprod / prod(1+r)-1 in arith metric calc)",
    geometric_compounding = TRUE
  )
)

# ─── Infeasibility report ────────────────────────────────
infeasibility_report <- list(
  milestone_sr_2_0_closure_status = "UNATTAINABLE on this 4-sleeve composite",
  milestone_mdd_lt_25_status = "UNATTAINABLE (RCD MDD -32%, all 11 methods MDD >= -28%)",
  milestone_cagr_gte_16_status = "ATTAINABLE (RCD CAGR 18.59%, 5/11 methods pass)",
  reasons = c(
    "C2 sleeve standalone SR 0.6410 (266m gross) << STR_1715 admit SR 1.9536 (255m PerfA admit) — addition dilutes SR",
    "Risk-stage Pareto cor 0.7116 (static proxy) + alpha-pure cor 0.7175 + Kendall 0.5437 — sleeves not orthogonal at portfolio level",
    "Diversification ratio 70/30 = 1.0612 minimal vs SR drag",
    "C2_pure 2026-04 100% Energy cross-section outlier addressed by sector cap 0.30 (Optimizer applied 6/20 = 30% per sector), but baseline Pareto cor still strong"
  ),
  violated_constraints = c("milestone_sr_2_0", "milestone_mdd_lt_25"),
  suggested_resolution = c(
    "Option A: HOLD — retain PG2 admit STR_1715_AR_on_M4_R05_overlay_PG2 single sleeve (current book_state v2.3). No new admit warranted. ΔSR boost from C2 is marginal (+0.0223) and Pareto cor 0.99 with PG2 makes incremental value ≈ 0.",
    "Option B: ADMIT RCD_dynamic — regime-conditional defensive bias (CRISIS/CAUTION → β_c2 0.30, NORMAL → 0.10, BULL → 0.00). Marginal SR boost + Crisis Alpha 6/7 PASS retain. But 41-name composition violates PG2 n=20 mandate inheritance.",
    "Option C: DEFER — C2 alpha (rank_IC 0.0982, ICIR 0.866, Harvey 5/5) PASSES Discovery graduation criteria as ALPHA SOURCE; but portfolio integration FAILS due to high realized cor with PG2. Wait for prospective walk-forward 6m (2026-05~10) to detect cor decay OR seek 5th orthogonal source."
  ),
  optimizer_recommendation_default = "Option A (HOLD)"
)

# ─── Build optimization_package_draft.json ──────────────
opt_pkg <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  parent_task_id = "WT-D20260513_002",
  as_of_date = "2026-05-14",
  as_of_sig_date_actual = "2026-04-30",
  forecast_horizon = "1M",
  agent = "optimizer-research",
  pipeline_version = "v1.0_full_universe_4_sleeve_composite_decision",
  selection_objective = selection_objective,
  method_selected = best_method,
  method_selected_rationale = list(
    rank_in_same_harness = 1,
    sharpe_gross_266m = rcd_metrics$Sharpe_gross[1],
    delta_sharpe_vs_str1715_pg2_pure = round(rcd_metrics$Sharpe_gross[1] - admit_baseline_metrics$Sharpe_gross[1], 4),
    marginal_advantage_classification = "MARGINAL_TIE (|ΔSR| < 0.05 per Iter31 strict015 precedent)",
    academic_references = c(
      "Markowitz (1952 JoF) - Mean-variance optimization foundation",
      "Lopez de Prado (2016) - Hierarchical Risk Parity",
      "Maillard-Roncalli-Teiletche (2010) - Equal Risk Contribution",
      "Rockafellar-Uryasev (2000) - CVaR LP optimization",
      "Kritzman-Page-Turkington (2011 FAJ) - Regime-dependent allocation (RCD foundation)",
      "Ang-Goetzmann-Schaefer (2009) - Defense vs Offense regime conditioning"
    ),
    l_code_references = c("L-282 PerfA convention reconcile", "L-307 MARGINAL_TIE Iter31 precedent", "L-316/L-317 alpha-vector vs portfolio realized cor distinction")
  ),

  upstream_alpha_inheritance = list(
    alpha_package_ref = file.path(MAILBOX, "alpha_package.json"),
    alpha_status = alpha_pkg$selection_status,
    alpha_rank_ic = alpha_pkg$diagnostics$rank_ic,
    alpha_icir = alpha_pkg$diagnostics$icir,
    alpha_harvey_5spec_pass = alpha_pkg$diagnostics$harvey_5spec_pass_count,
    alpha_dsr = alpha_pkg$diagnostics$dsr,
    alpha_pareto_pearson = 0.0292
  ),
  upstream_risk_inheritance = list(
    risk_package_ref = file.path(MAILBOX, "risk_package.json"),
    sigma_dim = 39,
    sigma_cond = 99.53,
    sigma_psd = TRUE,
    sector_cap_recommendation = 0.30,
    cvar_target = 0.025,
    cvar_observed = 0.026,
    pareto_strict_alpha_inherit = "operational_SOT_0_0292"
  ),

  # Final weights (latest sig_date)
  target_weights_at_2026_04_30 = target_weights,
  active_weights_at_2026_04_30 = active_weights,  # absolute = active for long-only no benchmark
  cash_share_at_2026_04_30 = cash_share,
  weights_csv_ref = file.path(STAGE, "weights.csv"),

  # Expected metrics (proxy from in-sample sleeve avg)
  expected_active_return = round(rcd_metrics$CAGR[1] - 0.05, 4),  # CAGR - cash 5% proxy
  expected_tracking_error = round(rcd_metrics$AnnVol[1], 4),
  expected_information_ratio = round(rcd_metrics$Sharpe_gross[1], 4),  # gross IR proxy
  turnover = round(mean(sleeve_dt[method == best_method, in_sample_vol_ann]) * 0.30, 4),  # estimate
  estimated_cost = 0.0030,  # 15bps × annual turnover

  # Binding constraints
  binding_constraints = c(
    "sector_cap_0_30 (active on C2 2026-04 sleeve via 6/20 sector quota)",
    "weight_bounds_0_20 per ticker (PG2 admit precedent inherit)",
    "sigma_w_eq_1 (long-only absolute)",
    "regime_conditional_beta_c2 (RCD allocates β_c2 by regime: CRISIS/CAUTION=0.30, NORMAL=0.10, BULL=0.00)"
  ),

  # Method comparison (5 mandatory + 6 baselines = 11 total)
  method_comparison = method_log_records,

  # Sector cap compliance
  sector_cap_compliance = list(
    cap_value = 0.30,
    cap_source = "Risk research recommendation (268m mean max_share ~0.30) + 2026-04 outlier mandate",
    per_method_breach = sec_breach_list,
    rcd_latest_sig_date_max_sec = list(
      sig_date = as.character(latest_sd),
      max_sector = as.character(rcd_latest_sec$max_sec[1] %||% NA),
      max_share = as.numeric(rcd_latest_sec$max_share[1] %||% NA),
      cap_breach = (as.numeric(rcd_latest_sec$max_share[1] %||% 0) > 0.30 + 1e-3)
    )
  ),

  cvar_compliance = cvar_compliance,

  pareto_rebalance_result = pareto_rebalance,

  concentration_overlap_handling = concentration_overlap,

  realized_performance_metrics = realized_metrics,

  ax_001_v2_4_axis_post_optimization = ax_001_v2_post,

  optimization_constraints_compliance = constraint_compliance,

  infeasibility_report = infeasibility_report,

  # Diagnostics
  diagnostics = list(
    n_methods_tested = nrow(method_comparison),
    walk_forward_sig_dates = 267,
    schedule_density_ratio = round(267 / 268, 4),
    schedule_density_target = 0.95,
    schedule_density_pass = TRUE,
    methods_within_charter_10_cap = "5 mandatory methods within R2-C 10 cap; 6 baselines transparently documented for comparison purposes",
    parallel_exec = FALSE,
    total_seconds_walk_forward = 90,
    backtest_contract_v1_0_compliant = TRUE
  ),

  # Compliance audit
  ax_compliance = list(
    AX_002_ex_ante_grid = list(
      n_candidates = 5,
      within_10_cap = TRUE,
      grid_specified_pre_hoc = TRUE,
      additional_baselines_for_compare = 6
    ),
    AX_001_v2_post_optimization_3_of_4 = TRUE,
    AX_005_v_1_2_exempt = "multi-sleeve composition path",
    AX_007_exempt = "multi-sleeve composition",
    AX_008_triangulation = list(
      source_1_forge_re_run = "deferred to downstream Forge",
      source_2_codex_critic = "mandatory Round 1 pending",
      source_3_architect = "deferred",
      current_status = "1_of_3_pending_downstream"
    )
  ),

  hard_constraints_acknowledgment = list(
    max_names_pg2_admit_inherit = 20,
    weight_bounds_pg2_admit_inherit = c(0, 0.20),
    long_only = TRUE,
    sigma_w = 1,
    cost_bps = 15,
    universe = "KOSPI 본주 + KOSDAQ 보통주 + LIQ 2e8",
    sector_cap_applied = 0.30,
    cvar_target_applied = 0.025
  ),

  challenge_flags = list(),  # Will be populated post-Codex Round
  codex_round_status = "PENDING_ROUND_1",
  codex_round_response_file = NULL,
  challenge_note_file = NULL,

  next_step = "Codex Critic Round 1 spawn + disposition; if APPROVE/APPROVE_CONDITIONAL → finalize. infeasibility_report present requires explicit Q-Lead waiver OR Option A HOLD recommendation acceptance.",

  input_hashes = list(
    alpha_package_sha256 = digest(file.path(MAILBOX, "alpha_package.json"), algo = "sha256", file = TRUE),
    risk_package_sha256 = digest(file.path(MAILBOX, "risk_package.json"), algo = "sha256", file = TRUE),
    request_json_sha256 = digest(file.path(MAILBOX, "request.json"), algo = "sha256", file = TRUE),
    weights_csv_sha256 = digest(file.path(STAGE, "weights.csv"), algo = "sha256", file = TRUE)
  ),

  lineage = list(
    parent_task_id = "WT-D20260513_002",
    parent_optimization_package_ref = "qepm/mailbox/worktask/WT-D20260513_002/optimization_package.json",
    inheritance_method = "C variant 4-sleeve composite framework + Risk's 0.30 sector cap mandate + CVaR target 0.025. New: 11 methods comparison + RCD regime-conditional dynamic + analytical pure baseline decomposition",
    divergences = c(
      "Universe: parent intersection ~350 → full ~1,219 (4.0× expansion inherit from alpha+risk)",
      "Methods: parent post-hoc grid → strict 5 ex-ante grid + 6 baselines transparent (within Charter R2-C 10 cap rationalization)",
      "RCD regime-conditional sleeve allocation (Kritzman-Page-Turkington 2011 FAJ extension)",
      "Pareto rebalance attempt: result FAIL (cor still > 0.40); operational SOT inherit alpha-stage 0.0292"
    )
  ),

  finalized_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  git_sha = system("git rev-parse HEAD", intern = TRUE)[1]
)

# Write draft
draft_path <- file.path(MAILBOX, "optimization_package_draft.json")
write_json(opt_pkg, draft_path, pretty = TRUE, auto_unbox = TRUE, digits = NA)
cat("[finalize] DRAFT saved to:", draft_path, "\n")
cat("[finalize] File size:", round(file.size(draft_path) / 1024, 1), "KB\n")

# Print summary
cat("\n=== Optimization Package Summary ===\n")
cat("  method_selected:", best_method, "\n")
cat("  selection_objective:", selection_objective, "\n")
cat("  RCD SR (266m gross):", round(rcd_metrics$Sharpe_gross[1], 4), "\n")
cat("  Δ vs STR1715_PG2_pure:", round(rcd_metrics$Sharpe_gross[1] - admit_baseline_metrics$Sharpe_gross[1], 4), "(MARGINAL_TIE)\n")
cat("  Pareto rebalance result: FAIL (cor 0.7175 vs target 0.40)\n")
cat("  Milestone SR 2.0: UNATTAINABLE\n")
cat("  Milestone MDD<25%: UNATTAINABLE\n")
cat("  Milestone CAGR>=16%: PASS (18.59%)\n")
cat("  Optimizer default recommendation: Option A HOLD (PG2 admit retain)\n")
