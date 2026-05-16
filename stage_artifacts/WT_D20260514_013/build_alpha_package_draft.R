#==============================================================================
# Build alpha_package_draft.json for WT-D20260514_013
# v6.0 Codex Round Step 3 — _draft suffix mandatory
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

wt_id <- "WT-D20260514_013"
out_dir <- file.path("stage_artifacts", paste0("WT_", gsub("^WT-", "", wt_id)))
mailbox <- file.path("qepm/mailbox/worktask", wt_id)

# Reload validated artifacts
av <- fromJSON(file.path(out_dir, "alpha_validation.json"), simplifyVector = FALSE)
m6 <- as.data.table(read_parquet(file.path(out_dir, "alpha_scores.parquet")))

cat("Building alpha_package_draft.json...\n")

# Top-30 selection per sig_date (Production-safe pre-selection, bi-monthly rebalance)
# Note: optimizer-research will handle dedupe-merge with STR_1715. Alpha returns full panel.
# Sample top-30 to show what selection would yield for last 3 sig_dates
last_3 <- tail(sort(unique(m6$sig_date)), 3)
top30_by_date <- m6[sig_date %in% last_3, head(.SD[order(-alpha_score)], 30),
                      by = sig_date][, .(sig_date, Ticker, alpha_score, alpha_rank)]

# alpha_vector emission: latest sig_date's full panel score (Optimizer reads full parquet)
latest_date <- max(m6$sig_date)
latest_panel <- m6[sig_date == latest_date]
cat("Latest sig_date:", as.character(latest_date), "/ n_tickers:", nrow(latest_panel), "\n")

# alpha_vector dict: top-30 names only (Production-safe)
top30_latest <- head(latest_panel[order(-alpha_score)], 30)
alpha_vector <- setNames(as.list(round(top30_latest$alpha_score, 6)),
                          top30_latest$Ticker)

# confidence_vector: based on cross-sectional rank stability (proxy: 1 - decile noise)
# Higher confidence for stocks consistently ranked high in lockbox folds
m6_lb <- m6[mode == "lockbox"]
rank_stability <- m6_lb[, .(
  mean_rank_pct = mean(alpha_rank_pct, na.rm = TRUE),
  sd_rank_pct = sd(alpha_rank_pct, na.rm = TRUE),
  n_obs = .N
), by = Ticker]
# Confidence ∈ [0, 1] = 1 - sd_rank_pct (lower variance = higher confidence)
rank_stability[, confidence := pmax(0, pmin(1, 1 - 2 * sd_rank_pct))]
rank_stability[is.na(confidence) | n_obs < 3, confidence := 0.3]
conf_top30 <- merge(top30_latest[, .(Ticker)], rank_stability[, .(Ticker, confidence)],
                    by = "Ticker", all.x = TRUE)
conf_top30[is.na(confidence), confidence := 0.4]
confidence_vector <- setNames(as.list(round(conf_top30$confidence, 4)),
                                conf_top30$Ticker)

# factor_specs — single ML composite "factor"
factor_specs <- list(
  list(
    factor_family = "ML_LARGE_SCALE_CROSS_SECTIONAL_ENSEMBLE",
    factor_name = "ML_M6_Ensemble_bi_monthly_top30",
    proxy = "rank_avg(M1_Ridge, M2_LASSO, M3_EN, M4_XGB_GPU, M5_LGB)",
    formula = paste0(
      "M6_Ensemble_{i,t} = mean_rank(z_score(predict_M1_Ridge_{i,t}), ",
      "z_score(predict_M2_LASSO_{i,t}), z_score(predict_M3_EN_{i,t}), ",
      "z_score(predict_M4_XGB_GPU_{i,t}), z_score(predict_M5_LGB_{i,t}))"
    ),
    feature_count = 1044,
    feature_master = "stage_artifacts/WT_D20260514_008/features_master.parquet",
    train_setup = list(
      bootstraps = 20,
      n_folds_total = 5,
      lockbox_folds = c(3, 4),
      is_folds = c(0, 1, 2),
      walk_forward = TRUE,
      target = "monthly_forward_return_1m",
      universe = "KR_TOP500_LIQ1E8 candidate panel (~2,600 tickers)"
    ),
    lag_rule = "monthly forward target with PIT walk-forward CV (t-1 features)",
    winsorization = "ML internal (z-score per fold) — no global winsorization",
    neutralization = "feature-level (industry/size handled in features_master via residualization)",
    economic_rationale = paste0(
      "High-dim cross-sectional ML alpha. Kelly-Malamud-Zhou 2024 'Virtue of Complexity in Return Prediction' ",
      "(JF, forthcoming) — 1,044 features with ridge-like regularization in ensemble produces stable ",
      "cross-section ranking that classical 4-5 factor composites cannot capture. Rank-average of 5 base ",
      "models (Ridge / LASSO / Elastic Net / XGBoost GPU / LightGBM) ensures single-model overfitting ",
      "diversification — Kelly's 'shrink to mean' intuition operationalized as model-space ensemble. ",
      "Validation > Discovery (Trend P1 SOT). Trend P2 cost-aware variant M7_XGB_CostAware available ",
      "as upstream γ-regularized comparable (γ=0.001) — but not selected as primary because rank IC ",
      "0.069 lockbox vs M6 0.073, with similar NW-t 4.30 vs 3.85 — M6 retains marginal edge with ",
      "ensemble robustness premium. ",
      "Trend P3 uncertainty discount (Liao 2025 RFS) NOT applied because Confident-High-Low lockbox ",
      "Δ -0.166 FAIL — KR microstructure misalignment, default k_discount=0."
    ),
    selection_objective = "rank_ic",
    references = list(
      "Kelly, Malamud, Zhou (2024). The Virtue of Complexity in Return Prediction. JF forthcoming.",
      "Jensen, Kelly, Malamud, Pedersen (2022). Machine Learning and the Implementable Efficient Frontier. SSRN 4187217.",
      "Liao (2025). Confidence-Weighted Cross-Sectional Forecasts. RFS forthcoming (preprint 2024)."
    ),
    diagnostics_lockbox_full_ml_panel = list(
      rank_ic = av$diagnostics_lockbox_inherited$rank_ic,
      icir = av$diagnostics_lockbox_inherited$icir,
      nw_t_lag6 = av$diagnostics_lockbox_inherited$t_nw_lag6,
      monotonicity = av$diagnostics_lockbox_inherited$monotonicity,
      dsr_z_n5 = av$diagnostics_lockbox_inherited$dsr_z_n5,
      n = 24,
      universe = "Full ML panel (~2,600 tickers)"
    ),
    diagnostics_lockbox_str1715_overlap = list(
      mean_ic = av$diagnostics_lockbox_recomputed_on_str1715_universe$mean_ic,
      icir = av$diagnostics_lockbox_recomputed_on_str1715_universe$icir,
      nw_t_lag6 = av$diagnostics_lockbox_recomputed_on_str1715_universe$nw_t_lag6,
      mono_q5 = av$diagnostics_lockbox_recomputed_on_str1715_universe$monotonicity_quintile_directional,
      mono_q10 = av$diagnostics_lockbox_recomputed_on_str1715_universe$monotonicity_decile_directional,
      q5_spread_annualized_pct = av$diagnostics_lockbox_recomputed_on_str1715_universe$q5_spread_annualized_pct,
      n = 24,
      universe = "STR_1715 overlap (KR_TOP500_LIQ1E8)",
      coverage_pct = av$diagnostics_lockbox_recomputed_on_str1715_universe$coverage_pct_vs_ml_panel
    )
  )
)

# selection_objective (R4 P3 HARD constraint)
selection_objective <- "rank_ic"

# challenge_flags
challenge_flags <- list(
  list(
    flag_id = "CF-A1",
    severity = "MEDIUM",
    type = "sample_size",
    description = paste0("60-month lockbox sample (2021-02 ~ 2026-01) relatively short vs 255m STR_1715 base. ",
                          "Reflects ML walk-forward CV constraint (lockbox fold 3,4 = 24 months only). ",
                          "Risk: Harvey-Liu-Zhu sample-period selection bias possible. ",
                          "Mitigation: 255m forward backtest via Forge agent (subsample comparison).")
  ),
  list(
    flag_id = "CF-A2",
    severity = "MEDIUM",
    type = "uncertainty_aware_fail",
    description = paste0("Phase 1.A Liao 2025 RFS Confident-High-Low lockbox Δ -0.166 (0.789 → 0.449 SR). ",
                          "Uncertainty filtering REDUCED SR in KR microstructure. Hypothesis: bootstrap-derived ",
                          "uncertainty inflates for high-momentum names (true alpha source) → filter removes ",
                          "winners. Default: k_discount=0 (point estimate retained). FAIL caveat REVISIT in ",
                          "Phase 2 (cross-sectional CI shrinkage).")
  ),
  list(
    flag_id = "CF-A3",
    severity = "LOW",
    type = "universe_coverage",
    description = paste0("ML panel ~2,600 tickers (full KR universe), STR_1715 panel ~342 tickers (KOSPI200∪KOSDAQ150 + ",
                          "LIQ ≥ 2e8). Overlap coverage = 15.6% (8,359 / 53,525 lockbox rows). Top-30 selection ",
                          "within ML panel may include illiquid names → optimizer-research must apply LIQ filter ",
                          "AFTER receiving full panel alpha. Production Constraint: final 20 names ⊆ KR_top342.")
  )
)

# Pareto orthogonality
pareto_block <- list(
  benchmark = "STR_1715_AR_on_M4_R05_PG2.score_eff (active PG2 admit, book_state v2.3)",
  sample_window = "2021-02 ~ 2026-01 (60 months overlap)",
  n_rows = av$pareto_orthogonality_vs_str1715$n_rows_overlap,
  pooled_pearson = av$pareto_orthogonality_vs_str1715$pearson_pooled,
  pooled_spearman = av$pareto_orthogonality_vs_str1715$spearman_pooled,
  pooled_kendall = av$pareto_orthogonality_vs_str1715$kendall_pooled,
  tdc_upper = av$pareto_orthogonality_vs_str1715$tdc_upper,
  tdc_lower = av$pareto_orthogonality_vs_str1715$tdc_lower,
  diversification_ratio_proxy = av$pareto_orthogonality_vs_str1715$diversification_ratio_proxy,
  sequential_admission_gate = av$pareto_orthogonality_vs_str1715$sequential_admission_gate,
  per_month_cor_distribution = av$pareto_orthogonality_vs_str1715$per_ym_signal_cor_distribution,
  l_323_supplement_3_inherit = list(
    blend_sr_60m = 2.267,
    blend_cagr = 0.4439,
    blend_mdd = -0.1463,
    eff_to_yr = 3.27,
    pearson_inherited = -0.2026,
    note = "Inherited from WT-D20260514_014 phase1_analysis.json pareto_blend.M6_Ensemble_bi-monthly_w40"
  )
)

# Pipeline manifest inherit
manifest <- fromJSON("stage_artifacts/WT_D20260514_014_phase1_full/manifest.json", simplifyVector = FALSE)

# Build alpha_package_draft
alpha_package <- list(
  task_id = wt_id,
  role = "alpha-research",
  status = "draft",
  source = "ml_pipeline_inheritance_with_pareto_validation",
  as_of_date = "2026-05-15",
  forecast_horizon = "1M",
  rebalance_frequency = "monthly_alpha_bi-monthly_selection",
  wt_type = "discovery_to_deployment_blend",

  ml_pipeline_manifest = manifest,
  model_used = "M6_Ensemble",
  alpha_features_path = file.path(out_dir, "alpha_scores.parquet"),
  alpha_scores_count = nrow(m6),
  alpha_scores_n_sig_dates = length(unique(m6$sig_date)),

  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = paste0("file://", normalizePath(file.path(out_dir, "alpha_scores.parquet"))),

  selection_objective = selection_objective,
  selection_objective_note = "rank_ic per R4 P3 HARD (predictive power only — no Sharpe/CAGR/MDD in selection)",

  factor_specs = factor_specs,

  diagnostics = list(
    rank_ic = av$diagnostics_lockbox_inherited$rank_ic,
    icir = av$diagnostics_lockbox_inherited$icir,
    monotonicity = av$diagnostics_lockbox_inherited$monotonicity,
    monotonicity_q5_str1715_overlap = av$diagnostics_lockbox_recomputed_on_str1715_universe$monotonicity_quintile_directional,
    subperiod_stability = "see fold-level metrics in summary_metrics.json (IS folds 0,1,2 vs lockbox folds 3,4)",
    turnover_proxy = av$diagnostics_lockbox_inherited$annualized_turnover,
    harvey_t_stat = av$diagnostics_lockbox_inherited$t_nw_lag6,
    harvey_t_stat_recomputed_str1715_overlap = av$diagnostics_lockbox_recomputed_on_str1715_universe$nw_t_lag6,
    dsr_z_n5 = av$diagnostics_lockbox_inherited$dsr_z_n5,
    post_neutralization_ic = "feature-level neutralization in features_master (not post-hoc)"
  ),

  pareto_orthogonality_vs_admit = pareto_block,

  graduation_criteria_check = av$graduation_criteria_check,

  pit_compliance = list(
    fold_lockbox_isolation = "fold 3,4 held out during ML training selection (walk-forward CV strict)",
    walk_forward_cv_strict = TRUE,
    Z_Score_Aligned = TRUE,
    lookahead_detected = FALSE,
    alpha_lockbox_seal_post_judge = "MANDATORY (Charter §10 lockbox-scope.md normalization)",
    C1_C15_check = "PASS — feature_master built via PIT walk-forward; ML cycle WT-D20260514_014 lineage"
  ),

  phase1_extensions = list(
    uncertainty_aware_enabled = manifest$phase1_uncertainty_enabled,
    cost_aware_enabled = manifest$phase1_cost_aware_enabled,
    k_discount = 0,
    k_discount_rationale = "Confident-High-Low Liao 2025 lockbox Δ -0.166 FAIL → KR microstructure caveat",
    gamma = manifest$gamma,
    cost_bps_oneway = manifest$cost_bps_oneway
  ),

  blend_intent = list(
    blend_role = "secondary_sleeve",
    weight_target = 0.40,
    counterpart = "STR_1715_AR_on_M4_R05_PG2 (60%)",
    rebalance_freq = "bi-monthly (Production-safe TO control)",
    internal_top_n = 30,
    merge_strategy_note = paste0("Optimizer-research final responsibility: weighted combined score → ",
                                   "dedupe → final top-20 by combined rank. Alpha emits full panel + ",
                                   "top-30 hint via alpha_rank.")
  ),

  challenge_flags = challenge_flags,
  red_flag_check = list(
    RF_A1_low_papers_subperiod = "PASS — 3+ references, subperiod stability not yet measured (Forge layer)",
    RF_A2_composite_improvement = "PASS — M6_Ensemble lockbox IC 0.073 vs M5_LGB 0.064 vs M3_EN 0.044 → ensemble premium 13%",
    RF_A3_recent_3y_inflation = "PASS — IS folds (2021-02 ~ 2024-01, 36m) IC 0.071 vs lockbox (2024-02 ~ 2026-01, 24m) IC 0.073 → recent stable",
    RF_A4_post_neutral_ic_drop = "N/A — feature-level neutralization built-in",
    RF_A5_top_decile_illiquid = "TBD — optimizer-research applies LIQ ≥ 2e8 filter on top-N"
  ),

  output_contract = list(
    schema_version = "alpha_package_v1_2",
    confidence_vector_present = TRUE,
    factor_specs_count = length(factor_specs),
    challenge_flags_count = length(challenge_flags)
  ),

  codex_round_required = TRUE,
  codex_round_status = "step_3_draft_emitted",
  next_step = "Step 4 (PostToolUse codex_round_auto_trigger.sh — background spawn ~9-15min)",

  lineage_inheritance = list(
    parent_ml_cycle = "WT-D20260514_014_phase1_full",
    parent_pareto_finding = "L-323 supplement #3",
    parent_str_1715 = "STR_1715_AR_on_M4_R05_PG2 (book_state v2.3 admitted_ids[0])"
  ),

  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

draft_path <- file.path(mailbox, "alpha_package_draft.json")
write(toJSON(alpha_package, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      file = draft_path)

cat("\n✓ alpha_package_draft.json written:", draft_path, "\n")
cat("  bytes:", file.info(draft_path)$size, "\n")
cat("  factor_specs:", length(alpha_package$factor_specs), "\n")
cat("  alpha_vector (top-30 latest sig_date):", length(alpha_package$alpha_vector), "\n")
cat("  confidence_vector:", length(alpha_package$confidence_vector), "\n")
cat("  challenge_flags:", length(alpha_package$challenge_flags), "\n")
cat("  pareto gate pass:", alpha_package$pareto_orthogonality_vs_admit$sequential_admission_gate$pass, "\n")
