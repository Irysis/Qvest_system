#==============================================================================
# WT-D20260528_003 Hypothesis A — Step 7: Emit final alpha_package_A.json
# - Applies Codex critic revisions (R1: t-1 liq / R2: nneg weights / R3: fwd_1m quarantine
#   / R4: A-specific lineage / R5: AX-001 NON_SUFFICIENT downgrade)
# - Verdict unchanged: TERMINATE
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

# Load revised payloads
payload_t1 <- readRDS(file.path(OUT_DIR, "emit_payload_t1.rds"))
draft <- fromJSON(file.path(MBOX, "alpha_package_draft_A.json"), simplifyVector = FALSE)

# Codex response
codex <- fromJSON(file.path(MBOX, "codex_critic_response_alpha_A.json"),
                  simplifyVector = FALSE)

# ---- Re-build challenge_flags with Codex disposition ----
challenge_flags <- list(
  list(id = "MONO_COLLAPSE", severity = "HIGH",
       detail = "D43_neut monotonicity = -0.200 / D44_neut = -0.455. Decile 1 (low skew) outperforms Decile 10 (high skew). Hypothesis disconfirmed in KR retail market.",
       codex_disposition = "ACCEPT",
       action_taken = "Final verdict TERMINATE retained."),
  list(id = "RF-A2", severity = "MEDIUM",
       detail = "Multi-sleeve 10+10 SR_ann=+0.26 vs D43 single top20 SR_ann=+0.39 (improvement -33.3%). Composite WORSE than best single.",
       codex_disposition = "ACCEPT",
       action_taken = "AX-007 exception claim downgraded from 'structurally attempted' to 'attempted but not earned'."),
  list(id = "RF-A3", severity = "HIGH",
       detail = "D43_neut p3 (2020-2023) ICIR=0.457 vs overall WF ICIR=0.229 (1.99x). Recent regime concentration.",
       codex_disposition = "ACCEPT",
       action_taken = "Not used to support deployment claim."),
  list(id = "HARVEY_FAIL", severity = "HIGH",
       detail = "Harvey-Liu-Zhu Bonferroni threshold t=2.58 (n_trials=5). All specs FAIL: D43_neut_t-1=2.22, D44_neut_t-1=1.70, Composite_nneg=1.98.",
       codex_disposition = "ACCEPT",
       action_taken = "alpha_discovery_certificate eligibility blocked. n_trials_dispute: Codex argues parallel A/B/C + parent search → n_trials > 5. UNRESOLVED, raises threshold further."),
  list(id = "DSR_FAIL", severity = "HIGH",
       detail = "Deflated SR p-value = 0.376 < 0.5 threshold (Bailey-Lopez de Prado 2014, n_trials=5).",
       codex_disposition = "ACCEPT",
       action_taken = "Verdict TERMINATE."),
  list(id = "TO_DISCIPLINE", severity = "MEDIUM",
       detail = "Annualized 2-way turnover 6.98 > 6.0/yr cap (Trend P6 Implementation Discipline).",
       codex_disposition = "ACCEPT",
       action_taken = "No cooldown/buffer designed in this hypothesis."),
  list(id = "PIT_C10_FIXED", severity = "MEDIUM",
       detail = "Original draft used same-day TV_20d (Close*Vol incl. sig_date) for liquidity filter — PIT-C10 violation.",
       codex_disposition = "ACCEPT (Codex C2)",
       action_taken = "FIXED in step6 — TV_20d_lag = mean over Date<sig_date (20 prior days). Removed mean 0.1 ticker/sig_date. ICIR/SR change within MC noise."),
  list(id = "PIT_C13_FIXED", severity = "HIGH",
       detail = sprintf("Original draft allowed walk-forward expanding ICIR weights to flip sign (D44 w_44_wf negative in %d/141 sig_dates = 39%%). PIT-C13 violation.",
                        payload_t1$neg_44_count),
       codex_disposition = "ACCEPT (Codex C3)",
       action_taken = "FIXED in step6 — w = pmax(ir, 0) nonneg clamp. Numerical impact on composite ICIR small (D44 weight magnitude was small); structural fix is governance-required."),
  list(id = "FWD_1M_QUARANTINE", severity = "MEDIUM",
       detail = "Original draft signal_matrix_ref included fwd_1m in alpha_scores.parquet — label leakage into deployable artifact.",
       codex_disposition = "ACCEPT (Codex C6 implication)",
       action_taken = "FIXED — alpha_scores_clean.parquet (no fwd_1m) + alpha_validation_panel.parquet (audit-only, fwd_1m quarantined)."),
  list(id = "AX001_DOWNGRADE", severity = "LOW",
       detail = "AX-001 v2 salvage based on 11 bad months only. No Core-relative MDD comparison and no realized crisis portfolio alpha computed.",
       codex_disposition = "PARTIAL ACCEPT (Codex C4)",
       action_taken = "Claim downgraded from 'PASS partial' to 'weak, non_sufficient'. Standalone defense alpha claim WITHDRAWN — possible crisis-conditional overlay only."),
  list(id = "GOVERNANCE_A_SPECIFIC", severity = "MEDIUM",
       detail = "Root challenge_note.md + artifact_lineage.json refer to STR_1722 (parent). qepm/stage_artifacts is stale v3.6 context.",
       codex_disposition = "ACCEPT (Codex C6)",
       action_taken = "FIXED — challenge_note_A.md emitted (separate from STR_1722). alpha_package_A.json emitted (this file). A-specific lineage record appended after write per L-194 ordering.")
)

# ---- factor_specs (revised) ----
factor_specs <- list(
  list(
    factor_family = "Higher_Moment_Defense",
    proxy = "D43_Skewness",
    formula = "Negate(third central moment of daily returns) — higher_better aligned via registry. Sector-Lv2 neutralized per sig_date.",
    lag_rule = "Factor_Date <= sig_date (Factor DB builder PIT)",
    winsorization = "Factor DB native (3sigma)",
    neutralization = "Sector_Lv2 OLS residual per sig_date (cross-section)",
    economic_rationale = "Boyer-Mitton-Vorkink 2010 idiosyncratic skewness anomaly hypothesis: positive-skew (lottery) preference predicts overpricing and lower future returns. KR test under K200∪KQ150 + 2e8 LIQ. Empirical result: hypothesis DISCONFIRMED in KR — bottom skewness decile outperforms top decile (monotonicity = -0.20).",
    weight_theta = unname(round(payload_t1$w43, 4)),
    weight_source = "walk_forward_expanding_icir_pre_snapshot_NONNEGATIVE_CLAMPED",
    references = c("Boyer-Mitton-Vorkink 2010 Idiosyncratic Volatility and Skewness", "Bali-Murray 2013 Tail Risk and Asset Prices"),
    icir_wf_t1 = round(payload_t1$d43_icir_t1, 3),
    harvey_t_nw_t1 = round(payload_t1$d43_t_t1, 2),
    selected = TRUE
  ),
  list(
    factor_family = "Higher_Moment_Defense",
    proxy = "D44_Kurtosis",
    formula = "Negate(fourth central moment of daily returns) — higher_better aligned via registry. Sector-Lv2 neutralized per sig_date.",
    lag_rule = "Factor_Date <= sig_date",
    winsorization = "Factor DB native",
    neutralization = "Sector_Lv2 OLS residual per sig_date",
    economic_rationale = "Bali-Murray 2013 kurtosis tail risk premium hypothesis: fat-tail aversion → priced risk premium. KR result: monotonicity = -0.46, stronger reversal than skewness. Walk-forward weight required nonneg clamp in 55/141 sig_dates (signal direction structurally unstable).",
    lag_rule_detail = "Factor DB Usable_Date <= sig_date",
    neutralization_detail = "Sector_Lv2 OLS residual cross-section",
    weight_theta = unname(round(payload_t1$w44, 4)),
    weight_source = "walk_forward_expanding_icir_pre_snapshot_NONNEGATIVE_CLAMPED",
    references = c("Bali-Murray 2013 Tail Risk and Asset Prices", "Conrad-Dittmar-Ghysels 2013 Ex Ante Skewness and Expected Stock Returns"),
    icir_wf_t1 = round(payload_t1$d44_icir_t1, 3),
    harvey_t_nw_t1 = round(payload_t1$d44_t_t1, 2),
    sign_flip_violations_pre_clamp_pct = round(100 * payload_t1$neg_44_count / 141, 1),
    selected = TRUE
  )
)

# ---- diagnostics (revised) ----
diagnostics <- list(
  rank_ic_composite_wf_nneg = 0.0128,
  rank_ic_d43_neut_t1 = round(payload_t1$d43_icir_t1 * sd(c(0.0178, NA), na.rm=TRUE), 4),
  rank_ic_d44_neut_t1 = round(payload_t1$d44_icir_t1 * sd(c(0.0086, NA), na.rm=TRUE), 4),
  icir_composite_wf_nneg = round(payload_t1$composite_icir_nneg, 3),
  icir_d43_neut_t1 = round(payload_t1$d43_icir_t1, 3),
  icir_d44_neut_t1 = round(payload_t1$d44_icir_t1, 3),
  monotonicity_d43 = -0.200,
  monotonicity_d44 = -0.455,
  subperiod_stability_d43 = 1.00,
  subperiod_stability_d44 = 0.67,
  harvey_t_stat_composite_nneg = round(payload_t1$composite_t_nneg, 2),
  harvey_threshold = round(payload_t1$harvey_threshold, 2),
  harvey_pass_count_t1 = payload_t1$harvey_pass,
  harvey_t_dispute_codex = "Codex argues n_trials should reflect parallel A/B/C + parent STR_1722 search → effective n_trials > 5, threshold > 2.58",
  deflated_sharpe_pvalue = 0.376,
  portfolio_mean_er_monthly = round(payload_t1$portfolio_mean_er, 4),
  portfolio_sd_monthly = round(payload_t1$portfolio_sd, 4),
  portfolio_sr_ann_t1 = round(payload_t1$portfolio_sr_ann, 2),
  portfolio_t_nw_t1 = round(payload_t1$portfolio_t_nw, 2),
  portfolio_n_months = payload_t1$portfolio_n,
  post_neutralization_ic_d43 = 0.81,
  post_neutralization_ic_d44 = 0.65,
  turnover_proxy_2way_annual = 6.98,
  cost_15bps_drag_monthly = 0.0009,
  cost_adjusted_sr_ann = 0.20,
  ax_001_v2_bad_normal_ratio_d43 = 3.61,
  ax_001_v2_bad_normal_ratio_d44 = 7.41,
  ax_001_v2_bad_months_n = 11,
  ax_001_v2_claim_strength = "weak_non_sufficient",
  multi_sleeve_vs_single_improvement_pct = -33.3
)

# ---- graduation criteria check (revised) ----
graduation_check <- list(
  min_rank_ic_geq_004 = list(threshold = 0.04, actual = 0.0128, PASS = FALSE),
  min_icir_geq_020 = list(threshold = 0.20, actual = round(payload_t1$composite_icir_nneg, 3), PASS = (payload_t1$composite_icir_nneg >= 0.20)),
  min_subperiod_stability_geq_050 = list(threshold = 0.50, actual = 1.00, PASS = TRUE),
  min_harvey_t_stat_geq_30 = list(threshold = 3.0, actual_max = round(max(payload_t1$d43_t_t1, payload_t1$composite_t_nneg), 2), PASS = FALSE),
  min_dsr_geq_05 = list(threshold = 0.5, actual = 0.376, PASS = FALSE),
  monotonicity_geq_07 = list(threshold = 0.7, actual = -0.20, PASS = FALSE)
)

n_pass <- sum(sapply(graduation_check, function(g) isTRUE(g$PASS)))

# ---- alpha_package_A (final) ----
final_pkg <- list(
  task_id = WT_ID,
  hypothesis_handle = "hypothesis_A",
  wt_type = "discovery",
  schema_version = "alpha_package_v1",
  as_of_date = "2026-05-28",
  signal_cutoff = "2023-12-22",
  forecast_horizon = "1M",
  rebalance_frequency = "monthly",
  universe = "KOSPI200 union KOSDAQ150 intersection (snapshot N=345 at 2023-11-30, t-1 liquidity filter)",
  liquidity_floor_won_20d_avg = 2e8,
  liquidity_pit_lag = "t-1 (TV_20d_lag = mean over Date<sig_date)",
  benchmark = "KOSPI200_total_return",

  hypothesis_title = "STR_1723 Distribution Moments Pure (D43_Skewness + D44_Kurtosis) Multi-Sleeve — TERMINATED",
  hypothesis_description = paste0(
    "Two-factor pure higher-moment hypothesis: D43_Skewness (Boyer-Mitton-Vorkink 2010) + D44_Kurtosis (Bali-Murray 2013). ",
    "Multi-sleeve 10+10 design as AX-007 mechanical avoidance. PIT-strict (lockbox Date<=2023-12-22, t-1 liquidity, ",
    "walk-forward expanding ICIR with nonneg clamp, sector neutralize per sig_date). Codex critic REJECT-accepted ",
    "4 fixes (C10 t-1 liq, C13 nonneg weight, fwd_1m quarantine, A-specific lineage) and 1 downgrade (AX-001 salvage to weak). ",
    "Empirical verdict: hypothesis DISCONFIRMED — monotonicity reversal (D43=-0.20, D44=-0.46), Harvey 0/3 (t<2.58), ",
    "DSR p=0.376, multi-sleeve -33% vs best single. Recommendation: TERMINATE."
  ),

  selection_objective = "icir",
  n_trials = 5,
  n_trials_dispute = "Codex C7 argues effective n_trials > 5 due to parallel A/B/C + parent STR_1722 search; would raise Harvey threshold further. Unresolved but does not affect TERMINATE verdict.",
  parallel_exec = FALSE,
  rcpp_used = FALSE,

  alpha_vector = as.list(payload_t1$alpha_vector),
  confidence_vector = as.list(payload_t1$confidence_vector),
  signal_matrix_ref = file.path(OUT_DIR, "alpha_scores_clean.parquet"),
  validation_panel_audit_only = file.path(OUT_DIR, "alpha_validation_panel.parquet"),

  multi_sleeve = list(
    enabled = TRUE,
    sleeve_count = 2,
    sleeves = list(
      A_skewness = list(factor = "D43_Skewness", top_k = 10, members = payload_t1$sleeve_A),
      B_kurtosis = list(factor = "D44_Kurtosis", top_k = 10, members = payload_t1$sleeve_B)
    ),
    overlap_with_parent_str1722_top20 = "7/20 (35%)",
    rf_a2_trigger = TRUE,
    rf_a2_detail = "Multi-sleeve SR_ann=+0.25 vs D43 single top20 SR_ann=+0.39 (-36%)"
  ),

  factor_specs = factor_specs,
  diagnostics = diagnostics,

  method_shopping_log = list(
    list(name = "D43_neut_t1", icir = round(payload_t1$d43_icir_t1, 3), selected = TRUE),
    list(name = "D44_neut_t1", icir = round(payload_t1$d44_icir_t1, 3), selected = TRUE),
    list(name = "Composite_WF_nneg", icir = round(payload_t1$composite_icir_nneg, 3), selected = TRUE),
    list(name = "D43_single_top20", note = "diagnostic only", selected = FALSE),
    list(name = "D44_single_top20", note = "diagnostic only", selected = FALSE)
  ),

  challenge_flags = challenge_flags,

  pit_assertions = list(
    factor_load = "load_month_factors() via factor_db_connector — align_factor_direction PIT-safe (Usable_Date <= sig_date)",
    sig_date_cutoff = "Date <= 2023-12-22 (alpha-research lockbox per .claude/rules/lockbox-scope.md)",
    walk_forward = "Expanding ICIR weights with pmax(ir, 0) NONNEG clamp + 36m burn-in (PIT-C13 compliant)",
    liquidity = "TV_20d_lag = frollmean(shift(TV, 1, 'lag'), 20) per Ticker (PIT-C10 t-1, NOT same-day)",
    sector_neutralize = "OLS residual per sig_date (cross-section, no time leak)",
    forward_return = "Next month-end close / current month-end close - 1 (audit-only, quarantined in alpha_validation_panel.parquet)",
    fwd_1m_quarantine = "alpha_scores_clean.parquet excludes fwd_1m — only Z43_neut, Z44_neut, alpha_score, alpha_score_z",
    pit_clean = TRUE,
    c1_c15_assertion = list(
      C1 = "PASS (expanding rolling, no full-sample stats)",
      C10 = "PASS (t-1 liquidity, fixed from draft)",
      C13 = "PASS (Z_Score_Aligned + nonneg WF weights, fixed from draft)",
      C14 = "PASS (Usable_Date <= sig_date via align_factor_direction PIT-safe v2.0)",
      C15 = "PASS (load_month_factors() only, no direct parquet read)"
    )
  ),

  graduation_criteria_check = graduation_check,
  graduation_pass_count = sprintf("%d/6", n_pass),
  overall_verdict = "FAIL",
  recommendation = "TERMINATE",

  codex_critic_round = list(
    stance = codex$stance,
    rationale = codex$stance_rationale,
    weakest_assumption = codex$weakest_assumption,
    critical_concerns_disposed = length(codex$critical_concerns),
    accepted_concerns = c("C1", "C2", "C3", "C5", "C6", "C7"),
    partial_accept_concerns = c("C4"),
    rebuttal_concerns = character(0),
    rebuttal_items_completed = c("R1_t1_liquidity", "R2_nonneg_weights", "R3_fwd_1m_quarantine", "R4_A_specific_governance"),
    rebuttal_items_not_possible_in_alpha_stage = c("R5_core_mdd_crisis_realized_alpha"),
    challenge_note_path = file.path(MBOX, "challenge_note_A.md"),
    response_path = file.path(MBOX, "codex_critic_response_alpha_A.json")
  ),

  inheritance_check = list(
    parent_alpha_package = "WT-D20260528_003/alpha_package.json (STR_1722 — 3-factor composite incl. D43)",
    snapshot_sig_date = "2023-11-30",
    intersect_n = 20,
    spearman_corr = 0.508,
    top20_overlap = 7,
    inheritance_pass_under_0_95 = TRUE,
    note = "Distinct search direction from STR_1722 (excluded D22 and M22, restricted to 2 higher-moment factors). New search outcome FAIL — terminates this branch."
  ),

  ax_007_check = list(
    structure = "multi_sleeve",
    sleeve_count = 2,
    per_sleeve_size = 10,
    avoidance_attempt = TRUE,
    avoidance_earned = FALSE,
    rf_a2_evidence = "Multi-sleeve SR_ann +0.25 vs D43 single top20 SR_ann +0.39 (-36%)",
    verdict = "AX-007 mechanism break NOT resolved by multi-sleeve structure"
  ),

  ax_001_v2_check = list(
    bad_normal_ratio_d43 = 3.61,
    bad_normal_ratio_d44 = 7.41,
    bad_months_n = 11,
    normal_months_n = 130,
    claim_strength = "weak_non_sufficient",
    salvage_path = "crisis_conditional_overlay_only_NOT_standalone",
    core_mdd_comparison = "NOT_COMPUTED (requires Risk/Optimizer/Forge handoff)",
    realized_crisis_portfolio_alpha = "NOT_COMPUTED (requires Forge backtest)",
    standalone_defense_claim = "WITHDRAWN"
  ),

  research_philosophy_compliance = list(
    P1_factor_zoo_reduction = "PASS — economic_rationale documented + redundancy_cluster cor=0.34",
    P2_cost_aware = "PARTIAL — TO 6.98/yr exceeds Trend P6 cap 6.0; cost-adjusted SR_ann reported (+0.20) but not optimized into objective",
    P3_uncertainty_aware = "PASS — Bootstrap CI95, NW-HAC t, Harvey-LZ reported. D43_neut CI excludes 0; D44_neut CI includes 0; composite t<threshold",
    P5_risk_model_handoff = "Not applicable — TERMINATE recommendation means no Risk stage spawn",
    P6_implementation_discipline = "FAIL — TO 6.98 > 6.0/yr cap",
    P7_attribution_feedback = "Decile spread + sector concentration reported; full Brinson-Carhart not computed (would require Forge backtest)"
  ),

  honest_assessment = list(
    one_sentence_verdict = "Distribution moments pure multi-sleeve FAILS graduation (2/6) with hypothesis itself disconfirmed in KR: monotonicity reverses (Boyer-Mitton-Vorkink lottery preference flips), composite WORSE than best single (RF-A2), Harvey 0/3, DSR p=0.376, AX-001 salvage insufficient (11 bad months only).",
    primary_failure_modes = c(
      "Monotonicity collapse: D43 -0.20 / D44 -0.46 (bottom decile outperforms top — KR retail lottery preference flips Boyer-Mitton-Vorkink 2010 baseline)",
      "Harvey-Liu-Zhu 0/3 PASS (max t=2.22 < threshold 2.58 Bonferroni n_trials=5; effective n_trials may be higher per Codex C7)",
      "Multi-sleeve RF-A2: -33% SR vs best single (AX-007 avoidance structurally attempted but not empirically earned)",
      "Cost-adjusted SR_ann = +0.20 (near-zero net alpha after 15bps cost @ TO=6.98)",
      "DSR p-value = 0.376 (post multi-testing, indistinguishable from null)",
      "Annualized 2-way turnover 6.98 > 6.0/yr (Trend P6 Implementation Discipline)"
    ),
    salvage_signals = c(
      "AX-001 v2 partial signal: bad regime IC D43=+0.044 vs normal +0.012 (ratio +3.61); D44 ratio +7.41 — but on 11 bad months only, not sufficient for standalone claim",
      "D43_neut WF Bootstrap CI95 [+0.0042, +0.0253] excludes 0 (statistical significance at α=0.05 single-test)",
      "Cross-corr D43-D44 neut mean = 0.34 (orthogonal-ish — design valid in concept, just outcome fails)",
      "Subperiod p3 (2020-23) ICIR D43=0.46 — recent regime strong but RF-A3 concentration"
    ),
    interpretation = paste(
      "Boyer-Mitton-Vorkink 2010 idiosyncratic skewness anomaly predicts low future returns for positive-skew (lottery) stocks.",
      "In KR retail-dominated K200∪KQ150 universe, the prediction REVERSES — low-skewness (stable, less lottery-like) stocks outperform.",
      "Similar reversal for Bali-Murray 2013 kurtosis tail premium — KR fat-tail aversion is weak.",
      "Cross-section IC is weakly positive (0.018, 0.009) but does not translate to portfolio top20 alpha because the decile structure is non-monotonic.",
      "Multi-sleeve AX-007 avoidance failed: combining D43 top10 + D44 top10 underperformed D43 single top20 by 36%.",
      "Conclusion: hypothesis disconfirmed in this universe. D43_Skewness shows weak partial validity only as crisis-conditional defense factor, not as standalone alpha."
    ),
    recommendation_detail = paste(
      "TERMINATE this hypothesis.",
      "Do NOT spawn Risk/Optimizer/Forge for hypothesis_A.",
      "Possible follow-on: hypothesis D43 stand-alone single sleeve top20 has SR_ann +0.39 (Harvey t=1.23, still FAIL).",
      "More productive: explore long-short or 50+ name expansion (AX-007 exception 2 or 3) if D43 is to be pursued."
    )
  ),

  reproducibility = list(
    scripts = c(
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/01_load_and_validate.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/02_subperiod_and_wf.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/03_diagnostics_and_inheritance.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/04_alpha_vector_emit.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/05_emit_draft.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/06_codex_revisions.R",
      "qepm/mailbox/worktask/WT-D20260528_003/scripts/overnight_A/07_emit_final.R"
    ),
    artifacts = c(
      file.path(OUT_DIR, "panel_t1.rds"),
      file.path(OUT_DIR, "ic_wf_t1.rds"),
      file.path(OUT_DIR, "alpha_t1.rds"),
      file.path(OUT_DIR, "port_t1.rds"),
      file.path(OUT_DIR, "alpha_scores_clean.parquet"),
      file.path(OUT_DIR, "alpha_validation_panel.parquet"),
      file.path(OUT_DIR, "step1_summary.json"),
      file.path(OUT_DIR, "step2_summary.json"),
      file.path(OUT_DIR, "step3_summary.json"),
      file.path(OUT_DIR, "alpha_validation.json")
    ),
    challenge_note = file.path(MBOX, "challenge_note_A.md"),
    codex_response = file.path(MBOX, "codex_critic_response_alpha_A.json")
  )
)

# ---- Write final ----
final_path <- file.path(MBOX, "alpha_package_A.json")
write_json(final_pkg, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[Step 7] FINAL alpha_package_A.json saved:", final_path, "\n")
cat("  alpha_vector N =", length(final_pkg$alpha_vector), "\n")
cat("  challenge_flags N =", length(final_pkg$challenge_flags), "\n")
cat("  graduation PASS =", n_pass, "/ 6\n")
cat("  Overall verdict =", final_pkg$overall_verdict, "\n")
cat("  Recommendation =", final_pkg$recommendation, "\n")

# ---- L-194 lineage record (after write) ----
source("02_Infrastructure/worktask/lineage_utils.R")
tryCatch({
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package_A",  # A-specific lineage
    method_selected = "Distribution Moments Pure multi-sleeve (D43_neut + D44_neut, nneg WF weights, t-1 liquidity)",
    input_file_paths = c(
      file.path(OUT_DIR, "alpha_scores_clean.parquet"),
      file.path(MBOX, "alpha_package_draft_A.json"),
      file.path(MBOX, "codex_critic_response_alpha_A.json"),
      file.path(MBOX, "challenge_note_A.md")
    )
  )
  cat("  lineage A-specific entry recorded\n")
}, error = function(e) {
  cat("  lineage record warning:", conditionMessage(e), "\n")
})

cat("\n[Step 7 DONE]\n")
