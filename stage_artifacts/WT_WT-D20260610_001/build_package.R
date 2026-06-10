# Build alpha_package_draft.json + alpha_validation.json from _computed_metrics.json
suppressMessages({library(jsonlite); library(data.table)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT <- file.path(root, "stage_artifacts/WT_WT-D20260610_001")
MB  <- file.path(root, "qepm/mailbox/worktask/WT-D20260610_001")
dir.create(MB, showWarnings = FALSE, recursive = TRUE)
m <- fromJSON(file.path(OUT, "_computed_metrics.json"))

# ---- factor_specs (6 value legs + R05 tilt) ----
fs <- list(
  list(factor_family="Value", proxy="EP (V02_EP)", formula="trailing earnings / market_cap (Z_Score_Aligned, higher=cheaper)",
       lag_rule="quarterly 45d / annual May", winsorization="3std (DB builder)", neutralization="none (cross-sectional Z)",
       economic_rationale="risk_premium", weight_theta=1/6, references=c("Basu 1977","Fama-French 1992")),
  list(factor_family="Value", proxy="EBIT/EV (V14_EBIT_EV)", formula="EBIT / enterprise_value (Z_Score_Aligned)",
       lag_rule="quarterly 45d / annual May", winsorization="3std", neutralization="none",
       economic_rationale="risk_premium", weight_theta=1/6, references=c("Loughran-Wellman 2011","Gray-Vogel 2012")),
  list(factor_family="Value", proxy="EV/EBITDA (V07_EV_EBITDA)", formula="enterprise_value / EBITDA (Z_Score_Aligned flips so cheaper=higher)",
       lag_rule="quarterly 45d / annual May", winsorization="3std", neutralization="none",
       economic_rationale="risk_premium", weight_theta=1/6, references=c("Loughran-Wellman 2011")),
  list(factor_family="Value", proxy="SP (V20_SP)", formula="sales / price (Z_Score_Aligned)",
       lag_rule="quarterly 45d / annual May", winsorization="3std", neutralization="none",
       economic_rationale="risk_premium", weight_theta=1/6, references=c("OShaughnessy 2011")),
  list(factor_family="Value", proxy="EV/Sales (V13_EV_Sales)", formula="enterprise_value / sales (Z_Score_Aligned flips so cheaper=higher)",
       lag_rule="quarterly 45d / annual May", winsorization="3std", neutralization="none",
       economic_rationale="risk_premium", weight_theta=1/6, references=c("OShaughnessy 2011")),
  list(factor_family="Value", proxy="BM (V01_BM)", formula="book_value / market_cap (Z_Score_Aligned)",
       lag_rule="annual May", winsorization="3std", neutralization="none",
       economic_rationale="risk_premium", weight_theta=1/6, references=c("Fama-French 1992","Rosenberg-Reid-Lanstein 1985")),
  list(factor_family="Risk/Tail", proxy="Tail_Risk (R05_Tail_Risk) tilt 0.5x", formula="value_composite_z + 0.5 * R05_Tail_Risk_Z_Score_Aligned",
       lag_rule="price t-1 (60d tail estimation)", winsorization="3std", neutralization="none",
       economic_rationale="risk_premium", weight_theta=0.5, references=c("Ang-Hodrick-Xing-Zhang 2006","Bali-Cakici-Whitelaw 2011"))
)

# ---- challenge_flags (honest red flags) ----
cf <- c(
  "RF-A3-INV: alpha NOT recent-concentrated — it is recent-DEPLETED. pre-2017 active t=2.95 / post-2017 active t=-0.24 (value decay, cohort-wide).",
  "GRADUATION-FAIL: portfolio_alpha_t_nw_lag3=2.33 < 2.95 HARD gate (full-period). Does NOT clear deployment graduation as standalone.",
  "OOS-RETENTION-FAIL: oos_retention_v2=-0.072 (splits -0.07/+0.05/-0.09) << 0.5. decay-pattern (not strategy-specific overfit — KR value premium collapse post-2017).",
  "TURNOVER-HIGH: 16.3x/yr annual (vs research_philosophy guideline 11/yr). Net 15bps already applied; capacity OK but TO discipline flag.",
  "MDD-HIGH: absolute sleeve net MDD=-57.4% (single-sleeve top-25 long-only beta~1, expected — MDD is overlay-stage lever per measurement-graduation §6, not module-stage).",
  "PRIOR-RECORD-DIVERGENCE: reconstruction 2017+ active t=-0.24 CONTRADICTS prior scouting record (+1.41). Reconstruction faithful on ABSOLUTE SR (0.78 vs prior 0.81) but prior 2017+ positive claim NOT reproduced on full universe.",
  "RECON-LIMIT: _census_v2 original artifacts absent on this machine. Spec re-built from memory description (6 value legs equal-weight + 0.5x R05). Cross-validation against original NOT possible."
)

draft <- list(
  task_id = "WT-D20260610_001",
  as_of_date = "2026-06-10",
  forecast_horizon = "1M",
  alpha_vector = m$alpha_vector,
  confidence_vector = m$confidence_vector,
  signal_matrix_ref = "feature_store://stage_artifacts/WT_WT-D20260610_001/alpha_scores.parquet",
  factor_specs = fs,
  diagnostics = list(
    rank_ic = m$rank_ic,
    icir = m$icir,
    monotonicity = m$monotonicity,
    subperiod_stability = m$subperiod_stability,
    turnover_proxy = m$turnover_annual,
    harvey_t_stat = m$ic_t_stat,
    harvey_t_specs_pass_count = 0L,
    deflated_sharpe_ratio = m$dsr_chain_diagnostic,
    post_neutralization_ic = m$rank_ic,
    alpha_inheritance_cor = 0.0,
    # ---- authoritative real-computation metrics (metric_type=canonical_screen) ----
    metric_type = "canonical_screen",
    portfolio_alpha_t_nw_lag3 = m$portfolio_alpha_t_nw_lag3,
    portfolio_alpha_t_pvalue = m$portfolio_alpha_t_pvalue,
    information_ratio = m$information_ratio,
    net_sr_active = m$net_sr,
    abs_sleeve_net_sr = 0.784,
    abs_sleeve_cagr = 0.251,
    abs_sleeve_mdd = -0.574,
    alpha_annualized = m$alpha_annualized,
    oos_retention_v2 = m$oos_retention_v2,
    oos_retention_pattern = "decay (cohort-wide value premium collapse post-2017, not strategy-specific overfit)",
    port_alpha_t_2017plus = m$port_alpha_t_2017plus,
    port_alpha_t_pre2017 = 2.953,
    cor_vs_book_ret_orig_net = m$cor_book_net,
    cor_vs_book_ret_orig_active = m$cor_book_active,
    n_months = m$n_months,
    mean_monthly_universe = m$mean_monthly_universe
  ),
  alpha_discovery_count = 1L,
  selection_objective = "rank_ic",
  challenge_flags = cf,
  method_shopping_log = list(
    candidates_tried = 1L,
    selection_type = "chain",
    n_trials_cumulative = 1L,
    method_log = list(list(name="value6_eqw_plus_0.5xR05", rank_ic=m$rank_ic, selected=TRUE)),
    note = "Single-spec re-construction (no variant search). DSR gate not applicable (chain). DSR=0.97 reported diagnostic only."
  )
)
write_json(draft, file.path(MB, "alpha_package_draft.json"), pretty=TRUE, auto_unbox=TRUE, digits=8)
cat("[draft] written:", file.path(MB, "alpha_package_draft.json"), "\n")

# ---- alpha_validation.json ----
val <- list(
  task_id = "WT-D20260610_001",
  as_of_date = "2026-06-10",
  metric_type = "canonical_screen",
  metric_type_note = "All performance numbers via canonical_screen_bt() (contract build_benchmark_compare, NW lag-3). NOT forge-authoritative (admission binding = forge build_bt_result).",
  universe = list(label="KR_ALL_LIQ2E8", liq_min_won_20d=2e8, mean_monthly_names=m$mean_monthly_universe,
                  note="full-universe (NOT KOSPI200 union KOSDAQ150). factor parquet universe-agnostic; LIQ>=2e8 t-PIT filter applied at consumer layer."),
  period = list(start=m$date_start, end=m$date_end, n_months=m$n_months,
                start_rationale="2005-01 standard (value/BM data from 2002-08, 36m IC burn-in)"),
  authoritative_metrics = list(
    portfolio_alpha_t_nw_lag3 = m$portfolio_alpha_t_nw_lag3,
    portfolio_alpha_t_pvalue = m$portfolio_alpha_t_pvalue,
    information_ratio = m$information_ratio,
    net_sr_active = m$net_sr,
    abs_sleeve_net_sr = 0.784,
    abs_sleeve_cagr = 0.251,
    abs_sleeve_mdd = -0.574,
    alpha_annualized = m$alpha_annualized,
    turnover_annual = m$turnover_annual
  ),
  advisory_diagnostics = list(
    rank_ic = m$rank_ic, icir = m$icir, ic_t_stat = m$ic_t_stat, n_ic_months = m$n_ic_months,
    monotonicity = m$monotonicity, quintile_mean_fwd = m$quintile_mean_fwd,
    subperiod_stability = m$subperiod_stability, subperiod_ic = m$subperiod_ic,
    note = "rank-IC family ADVISORY per WS2 (long-only realized alpha != cross-sectional rank power). portfolio_alpha_t is authoritative."
  ),
  graduation_gate = list(
    portfolio_alpha_t_nw_HARD = 2.95, actual = m$portfolio_alpha_t_nw_lag3, pass = (m$portfolio_alpha_t_nw_lag3 >= 2.95),
    oos_retention_HARD = 0.7, oos_band_lo = 0.5, actual_oos = m$oos_retention_v2,
    oos_pass = (m$oos_retention_v2 >= 0.7), oos_status = "fail (<0.5, evidence-irrelevant)",
    dsr_gate_applicable = FALSE, dsr_reason = "selection_type=chain (single-spec reconstruction). DSR diagnostic-only.",
    verdict = "DOES NOT clear deployment graduation as standalone. Full-period PORT_t 2.33<2.95 + OOS retention fail."
  ),
  oos_retention_v2 = list(
    value = m$oos_retention_v2, splits = m$oos_splits, split_fractions = c(0.55,0.65,0.75),
    method = "essence_score v2: anchored 3-split median of active-IR(ann) OOS/IS",
    pattern_label = "decay",
    pattern_rationale = "Pre-2017 active t=2.95 (active SR 0.85), post-2017 active t=-0.24 (active SR -0.08). Cohort-wide KR/global value premium collapse 2017-2020, not strategy-specific overfit. screen_route eligible (DPL_FEATURE / FR_RCMA), NOT capital graduation.",
    escalation_evidence = list(
      trailing36_port_t = m$trailing36_port_t,
      placebo_p = NA,
      book_marginal_note = "orthogonal (cor -0.035) but trailing PORT_t negative -> band escalation NOT met (oos<0.5 anyway, escalation moot)."
    )
  ),
  orthogonality_vs_book = list(
    book_base = "STR_1715_AR_on_M4_R05_overlay_PG2 period_returns_layer5.csv ret_orig",
    n_overlap = m$n_book_overlap,
    cor_net = m$cor_book_net, cor_active = m$cor_book_active,
    threshold = 0.30, orthogonal = (abs(m$cor_book_net) < 0.30),
    note = "Strongly orthogonal (|cor| 0.035 << 0.30). Matches prior record (0.005~0.03). Fundamental value = genuine orthogonal axis vs STR_1715 momentum/defense book."
  ),
  prior_record_comparison = list(
    source = "memory reference-str1715-structure / census Cycle 5/9 (proxy/scouting, _census_v2 absent this machine)",
    prior = list(sleeve_SR=0.808, CAGR=0.32, oos_retention=0.601, cor_vs_vanilla=c(0.005,0.03), port_t_2017plus=1.41, port_t_2017plus_restricted_universe=-0.74),
    reconstruction = list(abs_sleeve_SR=0.784, CAGR=0.251, oos_retention_v2=m$oos_retention_v2, cor_vs_book=m$cor_book_net, port_t_2017plus=m$port_alpha_t_2017plus),
    divergence_finding = "ABSOLUTE SR/orthogonality REPRODUCED (SR 0.78 vs 0.81, cor -0.035 vs 0.005-0.03). But 2017+ active t=-0.24 CONTRADICTS prior +1.41 claim and oos_retention -0.07 vs 0.601. The prior scouting OOS/2017+ figures are NOT reproduced under full-universe real-computation. Most likely prior figures were proxy-level (top-quintile EW inline cost) inflating recent-period alpha; canonical_screen top-25 net shows value decay. This divergence is itself a first-class finding (per WT mandate: do NOT adjust spec to match)."
  ),
  pit_compliance = list(
    C13 = "Z_Score_Aligned only (no NEGATE/FLIP). PASS.",
    C14 = "IC direction via Usable_Date<=sig_date expanding window (load_month_factors PIT-safe). PASS.",
    C15 = "All factors via load_month_factors() (no direct parquet load). PASS.",
    C4  = "fundamental lag quarterly 45d / annual May embedded in factor DB builder. PASS.",
    C1  = "expanding-window IC direction (no full-sample). PASS.",
    forward_return = "month-end Close[t] -> Close[t+1], contiguous months only (gap_ok), realized forward. No same-day circularity.",
    lockbox = "alpha regular-research stage. SIGNAL_CUTOFF applies; data through 2026-05 factor DB / 2026-06-10 RAWDATA. No lockbox/paper-trade window accessed."
  ),
  reconstruction_limitation = "_census_v2 original artifacts ABSENT on this machine (per WT request). Spec re-built from memory description. Cross-validation against original impossible. Reported honestly per Common Charter principle 4/8."
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=8)
cat("[validation] written:", file.path(OUT, "alpha_validation.json"), "\n")

# alpha_hypothesis.json
hyp <- list(
  task_id="WT-D20260610_001",
  hypothesis_title="Full-universe VALUE sleeve formal forge (book-marginal re-verification)",
  composite="EP + EBIT/EV + EV/EBITDA + SP + EV/Sales + BM (equal-weight Z) + 0.5*R05_Tail_Risk tilt",
  factor_map=list(EP="V02_EP", EBIT_EV="V14_EBIT_EV", EV_EBITDA="V07_EV_EBITDA", SP="V20_SP", EV_Sales="V13_EV_Sales", BM="V01_BM", tail="R05_Tail_Risk"),
  rebalance="monthly", selection="top-25 EW long-only", universe="KR_ALL_LIQ2E8",
  selection_type="chain", n_trials=1,
  economic_rationale="Value risk-premium (cheap fundamentals earn return premium) with tail-risk tilt toward distressed-but-surviving names. Orthogonal to STR_1715 momentum/defense book.",
  redundancy_cluster_id="VALUE_composite_KR (clusters with any standalone value sleeve; orthogonal to STR_1715 book)",
  outcome="Absolute SR reproduced (0.78); value decay post-2017 confirmed; graduation gate NOT cleared standalone; orthogonality strong."
)
write_json(hyp, file.path(OUT, "alpha_hypothesis.json"), pretty=TRUE, auto_unbox=TRUE)
cat("[hypothesis] written\n")
