#==============================================================================
# WT-D20260528_003 Hypothesis A — Step 5
# - Emit alpha_package_draft_A.json (Codex Round Step 1)
# - Conform to schema alpha_package_v1
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

WT_ID   <- "WT-D20260528_003"
OUT_DIR <- "stage_artifacts/WT_D20260528_003_overnight_A"
MBOX    <- file.path("qepm/mailbox/worktask", WT_ID)

payload   <- readRDS(file.path(OUT_DIR, "emit_payload.rds"))
validation <- fromJSON(file.path(OUT_DIR, "alpha_validation.json"),
                       simplifyVector = FALSE)
step1 <- validation$step1_summary
step2 <- validation$step2_summary
step3 <- validation$step3_summary

alpha_vector <- payload$alpha_vector
confidence_vector <- payload$confidence_vector

# ---- factor_specs (per Common Charter §3 factor_family vs proxy) ----
factor_specs <- list(
  list(
    factor_family = "Higher_Moment_Defense",
    proxy = "D43_Skewness",
    formula = "Negate(third central moment of daily returns over rolling window) — higher_better aligned (registry: negate left-skewness risk)",
    lag_rule = "Date <= sig_date (factor_db builder PIT)",
    winsorization = "Factor DB native (3sigma applied during build)",
    neutralization = "Sector_Lv2 OLS residual per sig_date (cross-section)",
    economic_rationale = "Boyer-Mitton-Vorkink 2010 idiosyncratic skewness anomaly hypothesis: positive skewness preference (lottery) leads to overpricing. KR retail-driven market test under K200∪KQ150 + 2e8 LIQ. Empirical result: hypothesis DISCONFIRMED in KR — bottom skewness decile outperforms top decile (monotonicity = -0.20).",
    weight_theta = unname(round(payload$w43, 4)),
    weight_source = "walk_forward_expanding_icir_pre_snapshot",
    references = c("Boyer-Mitton-Vorkink 2010 Idiosyncratic Volatility and Skewness", "Bali-Murray 2013 Tail Risk and Asset Prices"),
    icir_wf = step2$walk_forward_metrics$D43_neut_WF$icir,
    harvey_t_nw = step2$harvey_check$D43_neut_WF$t,
    selected = TRUE
  ),
  list(
    factor_family = "Higher_Moment_Defense",
    proxy = "D44_Kurtosis",
    formula = "Negate(fourth central moment of daily returns) — higher_better aligned (registry: negate fat-tail risk)",
    lag_rule = "Date <= sig_date (factor_db builder PIT)",
    winsorization = "Factor DB native",
    neutralization = "Sector_Lv2 OLS residual per sig_date",
    economic_rationale = "Bali-Murray 2013 kurtosis tail risk premium hypothesis: investors avoid fat-tail stocks → priced risk premium. Empirical result in KR: similar disconfirmation — monotonicity = -0.46 (stronger reversal than skewness).",
    weight_theta = unname(round(payload$w44, 4)),
    weight_source = "walk_forward_expanding_icir_pre_snapshot",
    references = c("Bali-Murray 2013 Tail Risk and Asset Prices", "Conrad-Dittmar-Ghysels 2013 Ex Ante Skewness and Expected Stock Returns"),
    icir_wf = step2$walk_forward_metrics$D44_neut_WF$icir,
    harvey_t_nw = step2$harvey_check$D44_neut_WF$t,
    selected = TRUE
  )
)

# ---- method_shopping_log (R2-C HARD ≤5) ----
method_log <- list(
  list(name = "D43_Skewness_raw",  rank_ic = step1$ic_summary$D43_raw$ic_mean,
       icir_wf = step2$walk_forward_metrics$D43_neut_WF$icir, selected = FALSE,
       note = "raw without sector neutralization"),
  list(name = "D44_Kurtosis_raw",  rank_ic = step1$ic_summary$D44_raw$ic_mean,
       icir_wf = step2$walk_forward_metrics$D44_neut_WF$icir, selected = FALSE,
       note = "raw without sector neutralization"),
  list(name = "D43_Skewness_neut", rank_ic = step1$ic_summary$D43_neut$ic_mean,
       icir_wf = step2$walk_forward_metrics$D43_neut_WF$icir, selected = TRUE,
       note = "sector-neutralized"),
  list(name = "D44_Kurtosis_neut", rank_ic = step1$ic_summary$D44_neut$ic_mean,
       icir_wf = step2$walk_forward_metrics$D44_neut_WF$icir, selected = TRUE,
       note = "sector-neutralized"),
  list(name = "Composite_WF (D43_neut+D44_neut)", rank_ic = step2$walk_forward_metrics$Composite_WF$ic_mean,
       icir_wf = step2$walk_forward_metrics$Composite_WF$icir, selected = TRUE,
       note = "walk-forward ICIR-weighted composite (alpha_vector emit)")
)

# ---- diagnostics ----
diagnostics <- list(
  rank_ic = step2$walk_forward_metrics$Composite_WF$ic_mean,
  rank_ic_d43_neut_full = step1$ic_summary$D43_neut$ic_mean,
  rank_ic_d44_neut_full = step1$ic_summary$D44_neut$ic_mean,
  icir = step2$walk_forward_metrics$Composite_WF$icir,
  icir_d43_neut_wf = step2$walk_forward_metrics$D43_neut_WF$icir,
  icir_d44_neut_wf = step2$walk_forward_metrics$D44_neut_WF$icir,
  monotonicity = step3$monotonicity$D43_neut,
  monotonicity_d44 = step3$monotonicity$D44_neut,
  subperiod_stability = step2$subperiod$stability_score_D43,
  subperiod_stability_d44 = step2$subperiod$stability_score_D44,
  harvey_t_stat = step2$harvey_check$Composite_WF$t,
  harvey_pass_count = step2$harvey_check$pass_count,
  harvey_threshold = step2$harvey_check$threshold,
  deflated_sharpe_pvalue = step2$dsr_pvalue,
  post_neutralization_ic_d43 = step3$sector_diagnostics$D43_post_neut_retention,
  post_neutralization_ic_d44 = step3$sector_diagnostics$D44_post_neut_retention,
  turnover_proxy_2way_annual = step3$turnover$annualized_2way,
  cost_adjusted_sr_ann = step3$turnover$cost_adjusted_sr_ann,
  bad_normal_ratio_d43 = step2$ax_001_v2_regime$bad_normal_ratio_D43,
  bad_normal_ratio_d44 = step2$ax_001_v2_regime$bad_normal_ratio_D44,
  multi_sleeve_vs_single_improvement_pct = step3$single_vs_multi$improvement_pct
)

# ---- challenge_flags ----
challenge_flags <- list(
  list(id = "MONO_COLLAPSE",  severity = "HIGH",
       detail = sprintf("D43_neut monotonicity = %.3f and D44_neut = %.3f. Decile 1 (low skewness) outperforms Decile 10 (high skewness). KR retail-driven lottery preference disconfirms Boyer-Mitton-Vorkink 2010.",
                        step3$monotonicity$D43_neut, step3$monotonicity$D44_neut),
       action_required = "Hypothesis itself disconfirmed in KR. No salvage via composite or multi-sleeve."),
  list(id = "RF-A2", severity = "MEDIUM",
       detail = sprintf("Multi-sleeve top10+10 SR_ann = +0.26 vs best single (D43 top20) SR_ann = +0.39 (improvement = %+.1f%%).",
                        step3$single_vs_multi$improvement_pct),
       action_required = "AX-007 avoidance via multi-sleeve fails — no mechanism uplift."),
  list(id = "RF-A3", severity = "HIGH",
       detail = sprintf("D43_neut subperiod p3 (2020-2023) ICIR=0.457 vs overall WF ICIR=0.229 (1.99x). Recent regime concentration suggests structural shift, not stable alpha."),
       action_required = "Future window check before any deployment."),
  list(id = "HARVEY_FAIL", severity = "HIGH",
       detail = sprintf("Harvey-Liu-Zhu Bonferroni adjusted t threshold = %.2f (n_trials=5). All 5 specs FAIL: D43_neut=%.2f / D44_neut=%.2f / D43_raw=%.2f / D44_raw=%.2f / Comp=%.2f",
                        step2$harvey_check$threshold,
                        step2$harvey_check$D43_neut_WF$t, step2$harvey_check$D44_neut_WF$t,
                        step2$harvey_check$D43_raw_WF$t,  step2$harvey_check$D44_raw_WF$t,
                        step2$harvey_check$Composite_WF$t),
       action_required = "Discovery certificate eligibility FAIL — harvey_t_specs_pass_count = 0 < 3."),
  list(id = "DSR_FAIL", severity = "HIGH",
       detail = sprintf("Deflated Sharpe Ratio p-value = %.3f < 0.5 graduation threshold (Bailey-Lopez de Prado 2014, n_trials=5).",
                        step2$dsr_pvalue),
       action_required = "After multi-testing adjustment, portfolio SR not distinguishable from null."),
  list(id = "TO_DISCIPLINE", severity = "MEDIUM",
       detail = sprintf("Annualized 2-way turnover %.2f exceeds Trend P6 Implementation Discipline cap 6.0/yr.",
                        step3$turnover$annualized_2way),
       action_required = "Bandbuffer/cooldown would be needed but not designed in this hypothesis."),
  list(id = "AX001_v2_SALVAGE", severity = "LOW",
       detail = sprintf("AX-001 v2 PASS partial: bad/normal IC ratio D43=%.2f, D44=%.2f (both > 1). Defense signal exists in crisis regimes only.",
                        step2$ax_001_v2_regime$bad_normal_ratio_D43, step2$ax_001_v2_regime$bad_normal_ratio_D44),
       action_required = "Could be considered as crisis-conditional defense overlay — but not as standalone alpha.")
)

# ---- alpha_package_draft_A ----
draft <- list(
  task_id = WT_ID,
  hypothesis_handle = "hypothesis_A",
  wt_type = "discovery",
  schema_version = "alpha_package_v1",
  as_of_date = "2026-05-28",
  signal_cutoff = "2023-12-22",
  forecast_horizon = "1M",
  rebalance_frequency = "monthly",
  universe = "KOSPI200 union KOSDAQ150 intersection (snapshot N=345 at 2023-11-30)",
  liquidity_floor_won_20d_avg = 2e8,
  benchmark = "KOSPI200_total_return",

  hypothesis_title = "STR_1723 Distribution Moments Pure (D43_Skewness + D44_Kurtosis) Multi-Sleeve",
  hypothesis_description = paste0(
    "Two-factor pure higher-moment hypothesis: D43_Skewness (Boyer-Mitton-Vorkink 2010) + D44_Kurtosis (Bali-Murray 2013) ",
    "as orthogonal defense single factors. AX-007 avoidance via multi-sleeve (10 D43 + 10 D44 = top 20 no-overlap). ",
    "PIT-clean strict: lockbox Date<=2023-12-22, walk-forward expanding ICIR weights (36m burn-in), sector neutralize per sig_date OLS residual, ",
    "liquidity 2e8 won 20d avg floor. Empirical verdict: hypothesis DISCONFIRMED — monotonicity reversal (D43=-0.20, D44=-0.46), ",
    "Harvey-Liu-Zhu 0/5 PASS, DSR p=0.38, multi-sleeve -33% vs best single (RF-A2 mechanism failure), ",
    "annualized 2-way turnover 6.98 > 6.0/yr. Salvage signals: AX-001 v2 PASS (bad/normal IC ratio D43=+3.61, D44=+7.41), ",
    "subperiod p3 (2020-23) ICIR D43=0.46 (regime concentration RF-A3). Recommendation: TERMINATE."
  ),

  selection_objective = "icir",
  n_trials = 5,
  parallel_exec = FALSE,
  rcpp_used = FALSE,

  alpha_vector = as.list(alpha_vector),
  confidence_vector = as.list(confidence_vector),
  signal_matrix_ref = file.path(OUT_DIR, "alpha_scores.parquet"),

  multi_sleeve = list(
    enabled = TRUE,
    sleeve_count = 2,
    sleeves = list(
      A_skewness = list(factor = "D43_Skewness", top_k = 10, members = payload$sleeve_A),
      B_kurtosis = list(factor = "D44_Kurtosis", top_k = 10, members = payload$sleeve_B)
    ),
    top20_combined = payload$multi_top20,
    overlap_with_parent_str1722_top20 = 7
  ),

  factor_specs = factor_specs,
  diagnostics = diagnostics,
  method_shopping_log = method_log,
  challenge_flags = challenge_flags,

  pit_assertions = validation$pit_assertions,
  graduation_criteria_check = validation$graduation_criteria_check,
  overall_verdict = validation$overall_verdict,
  recommendation = "TERMINATE",

  inheritance_check = list(
    parent_alpha_package = "WT-D20260528_003/alpha_package.json (STR_1722)",
    snapshot_sig_date_used = "2023-11-30",
    intersect_n = 20,
    spearman_corr = 0.508,
    top20_overlap = 7,
    inheritance_pass_under_0_95 = TRUE,
    note = "Distinct from parent STR_1722 (3-factor composite). cor=0.508 — meaningful new search direction, but search outcome FAIL."
  ),

  ax_007_check = validation$ax_007_check,
  ax_001_v2_check = validation$ax_001_v2_check,

  honest_assessment = validation$honest_assessment,

  research_philosophy_compliance = list(
    P1_factor_zoo_reduction = "PASS — economic_rationale documented for both factors (Boyer-Mitton-Vorkink 2010 / Bali-Murray 2013) + redundancy cluster checked (cor=0.34)",
    P2_cost_aware = "PARTIAL — TO 6.98/yr exceeds Trend P6, cost-adjusted SR_ann = +0.20 reported but not optimized into objective",
    P3_uncertainty_aware = "PASS — Bootstrap CI95, NW-HAC t, Harvey-LZ all reported. D43_neut CI excludes 0; D44_neut CI includes 0",
    P5_risk_model_handoff = "Not applicable in Alpha stage (Risk agent will handle)",
    P6_implementation_discipline = "FAIL — TO 6.98 > 6.0/yr cap",
    P7_attribution = "Diagnostics report decile spread + sector concentration but no factor/selection/cost decomposition computed"
  ),

  reproducibility = list(
    scripts = c(
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/01_load_and_validate.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/02_subperiod_and_wf.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/03_diagnostics_and_inheritance.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/04_alpha_vector_emit.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/05_emit_draft.R"
    ),
    artifacts = c(
      file.path(OUT_DIR, "panel_neut.rds"),
      file.path(OUT_DIR, "ic_per_sigdate.rds"),
      file.path(OUT_DIR, "ic_wf.rds"),
      file.path(OUT_DIR, "alpha_dt_sleeves.rds"),
      file.path(OUT_DIR, "port_ret.rds"),
      file.path(OUT_DIR, "alpha_scores.parquet"),
      file.path(OUT_DIR, "alpha_validation.json"),
      file.path(OUT_DIR, "step1_summary.json"),
      file.path(OUT_DIR, "step2_summary.json"),
      file.path(OUT_DIR, "step3_summary.json")
    )
  )
)

draft_path <- file.path(MBOX, "alpha_package_draft_A.json")
write_json(draft, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[Step 5] draft saved:", draft_path, "\n")
cat("  alpha_vector N =", length(alpha_vector), "\n")
cat("  factor_specs N =", length(factor_specs), "\n")
cat("  method_log N   =", length(method_log), "\n")
cat("  challenge_flags N =", length(challenge_flags), "\n")
cat("  Overall verdict =", draft$overall_verdict, "\n")
cat("  Recommendation =", draft$recommendation, "\n")
