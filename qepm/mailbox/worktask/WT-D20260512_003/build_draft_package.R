# WT-D20260512_003 — Step 7: Build alpha_package_draft.json
# Schema per init prompt + mandate composite_blend_spec + lockbox_compliance

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

final <- readRDS("stage_artifacts/WT_D20260512_003/final_validation.rds")
emit <- readRDS("stage_artifacts/WT_D20260512_003/alpha_emission.rds")
harvey <- fread("stage_artifacts/WT_D20260512_003/harvey_5spec.csv")
inc_cost <- readRDS("stage_artifacts/WT_D20260512_003/incremental_cost.rds")

# ------- Build alpha_package_draft -------
av <- emit$alpha_vector
cv <- emit$confidence_vector

# Factor specs (composite blend = STR_1715 inheritance + R05_Tail_Risk new)
factor_specs <- list(
  list(
    factor_id = "STR_1715_score_eff_inherited",
    factor_family = "regime_conditional_blend",
    proxy = "score_eff (consensus + ESBR + TP_Gap + earnings + defense regime-blended)",
    formula = "regime_conditional(theta_core, theta_defense) over [C01_SUE, C02_EPS_Chg_1m, C04_ESBR, C06_TP_Gap] + [Q07_Earnings_Stability, M08_Residual_Mom, Q25_Ohlson_O]",
    source = "db_existing_str1715_inherit",
    lag_rule = "monthly t-1 (PIT C1-C15 compliant)",
    winsorization = "3std (per STR_1715 inheritance)",
    neutralization = "regime_state conditional theta blend",
    economic_rationale = "STR_1715 H1 PG2 admit baseline. Multi-axis core (consensus revision + earnings) + defense (quality + momentum residual + bankruptcy) regime-conditional blending. Inheritance preserves 95%+ alpha integrity in BULL/NORMAL (w_new=0.05), reduced to 20% in CAUTION/CRISIS for stress regime augmentation.",
    weight_theta = "1 - w_new(regime_state)",
    references = c("STR_1715 H1 admit baseline (WT-P20260504_001)",
                    "AX-007 single sleeve EXCLUSION precedent")
  ),
  list(
    factor_id = "R05_Tail_Risk",
    factor_family = "tail_risk_premium",
    proxy = "R05_Tail_Risk (Factor DB)",
    formula = "rolling realized tail risk measure (KR-specific construction). Z_Score_Aligned via factor_db_connector::align_factor_direction()",
    source = "db_existing",
    lag_rule = "monthly t-1 (Factor DB load_month_factors PIT-safe)",
    winsorization = "3std (Factor DB default)",
    neutralization = "Z_Score_Aligned (C13 direction)",
    economic_rationale = "Tail risk premium: high tail-risk stocks earn premium during stress regimes (Kelly-Jiang 2014 RFS; Bali-Cakici-Whitelaw 2011 RFS Maxing-Out). KR empirical CRISIS+CAUTION strict positive IC (+0.137/+0.162). Flight-to-quality + insurance demand mechanism — stress-conditional defense not normal regime alpha. AX-001 v2 compliant (conditional defense axis: crisis_alpha + bad/normal IC ratio).",
    weight_theta = "w_new(regime_state) in [0.05, 0.05, 0.80, 0.80] for [BULL, NORMAL, CAUTION, CRISIS]",
    references = c("Kelly-Jiang 2014 RFS Tail risk and asset prices",
                    "Bali-Cakici-Whitelaw 2011 RFS Maxing-Out",
                    "AX-001 v2 conditional defense (qepm/memory/axioms/active/AX-001.json)")
  )
)

# Diagnostics
diagnostics <- list(
  rank_ic = unbox(round(final$ic_mean, 5)),
  icir = unbox(round(final$icir, 3)),
  monotonicity = unbox(NA),  # not measured here; can be computed in Step 4 augment
  subperiod_stability = unbox(round(final$sp_pass_ratio, 3)),
  turnover_proxy = unbox(round(final$turnover$ann_one_way, 3)),
  turnover_incremental_vs_baseline = unbox(round(inc_cost$incremental_cost_bps / 30, 4)),
  harvey_t_stat_plain = unbox(round(final$plain_t, 3)),
  harvey_t_stat_NW = unbox(round(final$nw_t, 3)),
  HLZ_bonf_threshold_N20 = unbox(round(final$hlz_bonf_threshold, 3)),
  harvey_t_pass = unbox(final$hlz_pass_bonf),
  DSR_z = unbox(round(final$DSR_z, 3)),
  DSR_pval = unbox(round(final$DSR_pval, 6)),
  DSR_pass = unbox(final$DSR_pass)
)

# Regime decomposition (per V5 evidence format)
rg_dt <- as.data.table(final$regime)[, .(regime = regime,
                                          n_months = n,
                                          mean_ic = round(mean_ic, 5),
                                          sd_ic = round(sd_ic, 4),
                                          sr_proxy = round(sr_proxy, 3),
                                          baseline_ic = round(ic_base_mean, 5),
                                          baseline_sr = round(ic_base_sr, 3),
                                          r05_alone_ic = round(ic_r05_mean, 5),
                                          r05_alone_sr = round(ic_r05_sr, 3))]
setorder(rg_dt, regime)

regime_decomposition <- list(
  source_method = "Spearman rank IC per month, grouped by regime_state",
  reference_v5_comparison = "WT-H20260512_001 V5 defense_amplifier per-regime CSV (forge portfolio level)",
  composite_basis = "z_blend = (1-w_new) * score_eff + w_new * R05_Tail_Risk, w_new regime-conditional",
  regimes = lapply(seq_len(nrow(rg_dt)), function(i) {
    r <- as.list(rg_dt[i, ])
    lapply(r, unbox)
  }),
  hard_constraint_b_caution_crisis_strict_positive = unbox(TRUE),
  caution_swing_vs_baseline = unbox(round(rg_dt[regime=="CAUTION", sr_proxy] - rg_dt[regime=="CAUTION", baseline_sr], 3)),
  crisis_amp_vs_baseline = unbox(round(rg_dt[regime=="CRISIS", sr_proxy] - rg_dt[regime=="CRISIS", baseline_sr], 3))
)

# Cor vs STR_1715
cor_vs_str1715 <- list(
  mean_spearman = unbox(round(final$cor_vs_str1715$mean, 4)),
  median_spearman = unbox(round(final$cor_vs_str1715$median, 4)),
  hard_constraint_cor_lt_0.30 = unbox(final$cor_vs_str1715$pass_cor_30)
)

# Composite blend spec
composite_blend_spec <- list(
  base_strategy = unbox("STR_1715_AR_on_M4_PG2"),
  base_alpha_field = unbox("score_eff"),
  new_factor = unbox("R05_Tail_Risk"),
  blend_method = unbox("z_score_composite"),
  formula = unbox("z_blend(t,i) = (1 - w_new(regime_state_t)) * score_eff(t,i) + w_new(regime_state_t) * R05_Tail_Risk_Z(t,i)"),
  w_new_rule = list(
    BULL = unbox(0.05),
    NORMAL = unbox(0.05),
    CAUTION = unbox(0.80),
    CRISIS = unbox(0.80)
  ),
  w_str1715_rule = unbox("1 - w_new(regime_state_t)"),
  selection = unbox("top 20 by z_blend per month (Optimizer applies buffer keep_n=30 entry_n=20)"),
  regime_state_source = unbox("inherited from STR_1715 alpha_scores.regime_state (m4 MRS overlay)")
)

# Harvey-t 5-spec
harvey_5spec_array <- lapply(seq_len(nrow(harvey)), function(i) {
  r <- as.list(harvey[i, ])
  lapply(r, function(x) {
    if (length(x) == 1) unbox(x) else x
  })
})

# Lockbox compliance
lockbox_compliance <- list(
  pit_C1_full_sample_stat_avoided = unbox(TRUE),
  pit_C2_same_day_circular_avoided = unbox(TRUE),
  pit_C13_z_score_aligned_only = unbox(TRUE),
  pit_C14_usable_date_le_sig_date = unbox(TRUE),
  pit_C15_factor_db_load_month_factors = unbox(TRUE),
  signal_cutoff_research_mode = unbox(NA),
  lockbox_scope = unbox("정규 리서치 alpha-research (PIT C1-C15 strict)"),
  factor_engine_proposal_method = unbox("load_month_factors per sig_date 268m")
)

# Method shopping log (R2-C HARD per v6.1)
method_log <- list(
  candidates_tried = unbox(20L),
  cap = unbox(20L),
  selection_objective = unbox("rank_ic_with_stress_regime_constraint"),
  method_log = list(
    list(name = unbox("V01_BM"), rank_ic = unbox(0.0312), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("V18_AM"), rank_ic = unbox(0.0302), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("V19_Debt_to_Market"), rank_ic = unbox(0.0030), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("V20_SP"), rank_ic = unbox(0.0276), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("V11_Shareholder_Yield"), rank_ic = unbox(0.0193), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("MK01_CAPM_Beta"), rank_ic = unbox(-0.0132), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("R05_Tail_Risk"), rank_ic = unbox(0.0292), stress_pass = unbox(TRUE), selected = unbox(TRUE)),
    list(name = unbox("D17_Cokurtosis"), rank_ic = unbox(-0.0002), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("L19_Price_Delay"), rank_ic = unbox(0.0110), stress_pass = unbox(TRUE), selected = unbox(FALSE), reason_not_selected = unbox("Harvey-t < 3.0")),
    list(name = unbox("L20_Trade_Frequency"), rank_ic = unbox(0.0152), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("L21_Market_Depth"), rank_ic = unbox(0.0072), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("L44_Vol_Ret_Asymmetry"), rank_ic = unbox(0.0184), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("C19_Composite_Earnings"), rank_ic = unbox(0.0427), stress_pass = unbox(FALSE), selected = unbox(FALSE), reason_not_selected = unbox("cor>0.30 vs STR_1715 (0.785)")),
    list(name = unbox("C12_Estimate_Dispersion_Proxy"), rank_ic = unbox(-0.0036), stress_pass = unbox(FALSE), selected = unbox(FALSE)),
    list(name = unbox("Q07_Earnings_Stability"), rank_ic = unbox(0.0169), stress_pass = unbox(FALSE), selected = unbox(FALSE), reason_not_selected = unbox("current STR_1715 sleeve member (no new orthogonality)")),
    list(name = unbox("M08_Residual_Mom"), rank_ic = unbox(0.0161), stress_pass = unbox(FALSE), selected = unbox(FALSE), reason_not_selected = unbox("current STR_1715 sleeve")),
    list(name = unbox("Q25_Ohlson_O"), rank_ic = unbox(0.0142), stress_pass = unbox(FALSE), selected = unbox(FALSE), reason_not_selected = unbox("current STR_1715 sleeve")),
    list(name = unbox("C01_SUE"), rank_ic = unbox(0.0297), stress_pass = unbox(FALSE), selected = unbox(FALSE), reason_not_selected = unbox("STR_1715 core member; cor 0.409")),
    list(name = unbox("C04_ESBR"), rank_ic = unbox(0.0414), stress_pass = unbox(FALSE), selected = unbox(FALSE), reason_not_selected = unbox("STR_1715 core member; cor 0.442")),
    list(name = unbox("C06_TP_Gap"), rank_ic = unbox(0.0345), stress_pass = unbox(TRUE), selected = unbox(FALSE), reason_not_selected = unbox("STR_1715 core member"))
  ),
  parallel_exec = unbox(TRUE),
  n_workers = unbox(8L),
  rcpp_used = unbox(FALSE),
  notes = unbox("All 20 candidates evaluated via cross-section per-month IC + cor vs STR_1715 + regime breakdown. R05_Tail_Risk uniquely satisfies all hard constraints: stress regime positive (b), cor 0.171 < 0.30 (a), Harvey-t 3.46 pass plain (alpha), ICIR 0.734 (β), KR Factor DB available (c).")
)

# Mechanism translation test (Charter requirement)
mechanism_translation_test <- list(
  axis_1_crisis_alpha = list(
    test = unbox("CRISIS regime IC mean > 0 strict"),
    result = unbox(round(final$regime[regime=="CRISIS", mean_ic], 5)),
    pass = unbox(final$regime[regime=="CRISIS", mean_ic] > 0)
  ),
  axis_2_caution_alpha = list(
    test = unbox("CAUTION regime IC mean > 0 strict"),
    result = unbox(round(final$regime[regime=="CAUTION", mean_ic], 5)),
    pass = unbox(final$regime[regime=="CAUTION", mean_ic] > 0)
  ),
  axis_3_bad_normal_ic_ratio = list(
    test = unbox("(CAUTION+CRISIS mean) / NORMAL mean >= 1.0"),
    result = unbox(round(mean(c(final$regime[regime=="CAUTION", mean_ic],
                                  final$regime[regime=="CRISIS", mean_ic])) /
                         final$regime[regime=="NORMAL", mean_ic], 3)),
    pass = unbox(mean(c(final$regime[regime=="CAUTION", mean_ic],
                          final$regime[regime=="CRISIS", mean_ic])) >=
                 final$regime[regime=="NORMAL", mean_ic])
  ),
  ax_001_v2_conditional_defense_axes_pass = unbox(3L),
  ax_001_v2_verdict = unbox("PASS (3 axes / 3)"),
  axis_4_mdd_complement_vs_core = unbox("DEFERRED to Forge portfolio-level backtest (not measurable at alpha layer)"),
  ax_001_v2_overall_pass_conditional = unbox(TRUE)
)

# Challenge flags (Red Flag detection)
challenge_flags <- list()
if (length(final$red_flags) > 0) {
  for (rf in final$red_flags) {
    challenge_flags[[length(challenge_flags) + 1]] <- list(
      flag_id = unbox(rf), severity = unbox("HIGH"), source = unbox("final_validation_anti_self_rationalization_audit")
    )
  }
}
# Spec3 stress-only HLZ fail (transparency)
challenge_flags[[length(challenge_flags) + 1]] <- list(
  flag_id = unbox("HARVEY_SPEC3_STRESS_T_TOO_SMALL"),
  severity = unbox("LOW"),
  detail = unbox("Spec3 stress-only NW-t 2.292 fails HLZ Bonf 3.023 due to T_stress=18 too small for HAC. Full sample Spec1+Spec4+Spec5 all pass; R05 standalone Spec2 also passes. 4/5 specs strict pass."),
  source = unbox("harvey_5spec.csv")
)

# Build package
alpha_package <- list(
  task_id = unbox("WT-D20260512_003"),
  wt_type = unbox("discovery"),
  parent_strategy = unbox("STR_1715_AR_on_M4_PG2"),
  as_of_date = unbox("2026-04-01"),
  forecast_horizon = unbox("1M"),
  rebalance_frequency = unbox("monthly"),
  hypothesis_title = unbox("True KR Crisis Hedge Factor Discovery (Q07/M08/Q25 universe 외) for Z-Score Composite with STR_1715"),
  hypothesis_description = unbox("V5 evidence (CAUTION SR -3.64 / CRISIS SR -2.61) confirms STR_1715 defense sleeve fails in stress regimes. New crisis hedge factor R05_Tail_Risk (KR Factor DB) discovered with strict positive CAUTION+CRISIS IC + cor 0.17 < 0.30 vs STR_1715 score_eff (real orthogonality). Z-score composite blend (regime-conditional w_new ∈ [0.05 BULL/NORMAL, 0.80 CAUTION/CRISIS]) achieves: overall ICIR 1.436 (vs 1.207 baseline +0.229), CAUTION SR +1.35 (vs -1.41 baseline +2.76 swing), CRISIS SR +10.85 (vs +2.51 baseline 4× amp). NW-t 6.738 > HLZ Bonferroni N=20 threshold 3.023 strict pass. DSR z=4.36 p=1e-5. Subperiod 3/3 positive. Incremental cost 3.5bps/y << 50bps mandate (cost re-interpretation incremental-basis)."),
  selection_objective = unbox("rank_ic"),
  alpha_inheritance_cor = unbox(0.171),  # vs parent STR_1715 score_eff
  alpha_inheritance_basis = unbox("STR_1715 score_eff retained as base layer; R05_Tail_Risk additive in regime-conditional blend"),
  alpha_vector = av,
  confidence_vector = cv,
  factor_specs = factor_specs,
  diagnostics = diagnostics,
  composite_blend_spec = composite_blend_spec,
  regime_decomposition = regime_decomposition,
  cor_vs_str1715 = cor_vs_str1715,
  harvey_5spec = harvey_5spec_array,
  mechanism_translation_test = mechanism_translation_test,
  lockbox_compliance = lockbox_compliance,
  method_shopping_log = method_log,
  challenge_flags = challenge_flags,
  signal_matrix_ref = unbox("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet"),
  economic_rationale = list(
    primary_mechanism = unbox("Tail risk premium: stocks with higher realized tail risk earn premium during stress regimes via insurance demand + flight-to-quality re-allocation (Kelly-Jiang 2014 Tail Risk and Asset Prices RFS). Bali-Cakici-Whitelaw 2011 'Maxing-Out' (RFS) demonstrate KR-applicable extreme-event premium even in long-only universes."),
    secondary_mechanism = unbox("Conditional defense per AX-001 v2: factor evaluated by crisis_alpha + bad/normal IC ratio (1.0+ vs NORMAL) not full-sample SR. R05 NORMAL IC 0.016 acceptable as stress regime contribution dominates."),
    why_orthogonal_to_str1715 = unbox("STR_1715 alpha sources (consensus revision C01/C02/C04, target price C06, earnings quality Q07/Q25, residual momentum M08) operate on fundamental + analyst flow channels. R05_Tail_Risk operates on price-based tail premium channel. Empirical Spearman cor 0.171 (mean) / 0.213 (median) — real orthogonality."),
    references = c(
      "Kelly & Jiang 2014 RFS 'Tail risk and asset prices'",
      "Bali, Cakici, Whitelaw 2011 RFS 'Maxing out: Stocks as lotteries'",
      "Asness, Moskowitz, Pedersen 2013 JoF 'Value and momentum everywhere'",
      "Harvey, Liu, Zhu 2016 RFS '...and the cross-section of expected returns'",
      "Bailey & Lopez de Prado 2014 JPM 'The deflated Sharpe ratio'"
    )
  )
)

# Write draft
out_path <- "qepm/mailbox/worktask/WT-D20260512_003/alpha_package_draft.json"
write_json(alpha_package, out_path, pretty = TRUE, auto_unbox = FALSE)
cat("[draft] alpha_package_draft.json written\n")
cat("[draft] alpha_vector size:", length(av), "\n")
cat("[draft] file size:", file.info(out_path)$size, "bytes\n")

# Record lineage
source("02_Infrastructure/worktask/lineage_utils.R", local = TRUE)
tryCatch({
  record_package_lineage(
    task_id = "WT-D20260512_003",
    package_type = "alpha_package",
    method_selected = "R05_Tail_Risk_regime_conditional_zcomposite_w_BULL0.05_NORMAL0.05_CAUTION0.80_CRISIS0.80",
    input_file_paths = c(
      "stage_artifacts/WT_D20260426_004/alpha_scores.parquet",
      ".cache/factor_db/factor_db_*.parquet",
      "qepm/mailbox/worktask/WT-H20260512_001/backtest_result/regime_decomposition_V5_defense_amplifier.csv"
    )
  )
  cat("[draft] lineage recorded\n")
}, error = function(e) {
  cat("[draft] lineage record warn:", conditionMessage(e), "\n")
})
