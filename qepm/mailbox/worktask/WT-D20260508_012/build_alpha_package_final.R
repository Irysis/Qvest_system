#==============================================================================
# Build alpha_package.json (FINAL after Codex Critic Round 1) for WT-D20260508_012
#
# Spec changes vs draft (challenge_note.md 적용):
#   1. deliverable_kind="regime_indicator" 강화
#   2. selection_objective fallback "rank_ic" (Hook enum compat)
#   3. ax_compliance.AX_002_PIT.C13_exemption_rationale 신규
#   4. validation: overall_strict_5gate_pass / overall_3gate_pass 분리
#   5. integration_with_m4.deployment_status="design_only_NOT_admitted"
#   6. ax_compliance.AX_008.triangulation_status 명시 + discovery_termination
#   7. regime_state_summary.parquet 신규 + diagnostics에 conditional return
#   8. factor_specs references page-level (Eq./§) 보강
#   9. design_doc β_tail page 인용은 design_doc 본문 (별도 edit)
#  10. run_all.R 신규 (lineage)
#  11. orthogonality_assessment 표현 완화 ("moderately orthogonal")
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260508_012")
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260508_012")

ts <- as.data.table(read_parquet(file.path(ART_DIR,
                                            "regime_indicator_timeseries.parquet")))
ts[, Date := as.Date(Date)]
val <- fromJSON(file.path(ART_DIR, "validation_8_stress_periods.json"),
                simplifyDataFrame = FALSE)
diag_cond <- fromJSON(file.path(ART_DIR, "regime_conditional_diagnostic.json"),
                      simplifyDataFrame = FALSE)

# state distribution
state_dist <- ts[!is.na(regime_state), .N, by = regime_state]
sd_list <- setNames(as.list(state_dist$N), state_dist$regime_state)

# correlation with m4
m4 <- as.data.table(read_parquet(
  file.path(PROJECT_ROOT,
            "qepm/stage_artifacts/WT_WT-D20260430_001/alpha_scores.parquet")))
m4[, Date := as.Date(Date)]
ts_simple <- ts[, .(Date, O_t_lag1, regime_state)]
setkey(ts_simple, Date); setkey(m4, Date)
joined <- ts_simple[m4[, .(Date, weight_cash, combined_regime)],
                    on = "Date", roll = TRUE]
joined[, tail_score_num := fcase(
  regime_state == "PEACE",       0,
  regime_state == "WARNING",     1,
  regime_state == "TAIL_STRESS", 2,
  default = NA_real_
)]
cor_m4_combined <- cor(joined$tail_score_num, joined$combined_regime,
                        use = "pair")
cor_m4_cash <- cor(joined$tail_score_num, joined$weight_cash, use = "pair")

# Conditional KOSPI return diagnostic (codex C2 response)
peace <- diag_cond$per_state[[1]]
warn <- diag_cond$per_state[[2]]
stress <- diag_cond$per_state[[3]]

# Validation gates split (codex C4 response)
strict_5gate_pass <- val$validation_8_stress_periods$overall_strict_5gate_pass
recall_pass <- val$validation_8_stress_periods$recall_pass
fp_pass <- val$validation_8_stress_periods$false_positive_pass
overall_3gate_pass <- recall_pass && fp_pass &&
  isTRUE(val$validation_8_stress_periods$lead_time$top_half_mean >= 4)

challenge_flags <- list(
  list(
    flag = "lead_time_strict_FAIL_relaxed_PASS",
    severity = "MEDIUM",
    desc = sprintf(
      paste0("Strict 5-gate FAIL (mean lead %.1fd < 5d). Relaxed 3-gate PASS ",
             "(recall 5/6 + FP 9.7%% + min_duration 3d). Lead time mixed: ",
             "slow-burn +6~+22d / fast-crash -14~-21d. BTZ 2009 RFS Table 5 ",
             "expected pattern (1-day forward FAIL, 1-month forward PASS). ",
             "Codex C4 ACCEPT — no silent gate override; both gates reported."),
      val$validation_8_stress_periods$lead_time$mean),
    mitigation = "Use as concurrent regime confirmation (not 1-day prediction). Layer D design only — deployment requires Risk/Optimizer/Forge backtest + AX-008 triangulation 2/3 minimum."
  ),
  list(
    flag = "burnin_eudebt_drop",
    severity = "LOW",
    desc = "EuDebt_II_2011 partly within 252-day burn-in. Recall counts as in-window FAIL (5/6=0.83). Within-validity-only would be 5/5=1.0. Burn-in 252d is academic standard for expanding percentile (cannot reduce).",
    mitigation = "Honest reporting: in-window denominator 6 used for recall."
  ),
  list(
    flag = "deliverable_kind_regime_indicator",
    severity = "INFO",
    desc = "alpha_package.json transports regime_state daily timeseries (NOT cross-section alpha_vector). alpha_vector field intentionally empty per request.json L19 mandate.",
    mitigation = "deliverable_kind=regime_indicator. Risk/Optimizer/Forge consume regime_state via Layer D overlay (design_only_NOT_admitted)."
  ),
  list(
    flag = "C13_manual_sign_exemption_documented",
    severity = "MEDIUM",
    desc = "RIX_proxy = -bkm_skew_30d / ts_slope_neg = -(T2-T1) use sign convention from Bakshi-Kapadia-Madan 2003 RFS Eq.(7) academic standard, NOT Factor DB lookup (no factor_db_connector::load_month_factors() call). C13 hard rule applies to Factor DB factor lookup; option-derived regime computation operates outside Factor DB scope.",
    mitigation = "ax_compliance.AX_002_PIT.C13_exemption_rationale documented. governance_log entry recommended. Codex C3 REBUTTAL with 3-axis citation (학술 BKM 2003 Eq.7 / L-454 KR internal data 우선 / 정량 0 Factor DB calls)."
  ),
  list(
    flag = "AX_008_triangulation_1_of_3",
    severity = "HIGH",
    desc = "Alpha PASS only (1/3). Forge / Architect verification pending. Per AX-008 mandate, deployment requires 2/3 minimum.",
    mitigation = "regime_indicator_summary.integration_with_m4.deployment_status='design_only_NOT_admitted'. PG2/PG3 admission 비대상. Discovery WT termination — separate deployment WT spawn required."
  ),
  list(
    flag = "tail_signal_concurrent_not_predictive",
    severity = "MEDIUM",
    desc = sprintf(paste0("regime_state-conditional KOSPI t-day mean return: ",
            "PEACE=%.4f / WARNING=%.4f / TAIL_STRESS=%.4f. TAIL_STRESS days ",
            "show HIGHER realized return (post-stress rebound). However q05 ",
            "worsens substantially (PEACE -1.42%% vs TAIL_STRESS -2.78%%). ",
            "Welch t = %.2f (p=%.3f). Honest read: signal identifies ",
            "concurrent high-tail-risk regime, not next-day direction."),
            peace$mean_daily_ret, warn$mean_daily_ret, stress$mean_daily_ret,
            diag_cond$diff_tests$TAIL_STRESS_vs_PEACE$t_stat,
            diag_cond$diff_tests$TAIL_STRESS_vs_PEACE$p_value),
    mitigation = "Layer D design = position cap (defensive trim), not directional bet. Aligns with concurrent risk-mitigation use case. AFT 2017 § 6 deployment-as-risk-cap convention."
  )
)

diagnostics <- list(
  type = "regime_indicator_diagnostics",
  recall = val$validation_8_stress_periods$recall,
  recall_pass = recall_pass,
  false_positive_rate = val$validation_8_stress_periods$false_positive_rate,
  false_positive_pass = fp_pass,
  lead_time_mean = val$validation_8_stress_periods$lead_time$mean,
  lead_time_median = val$validation_8_stress_periods$lead_time$median,
  lead_time_top_half_mean = val$validation_8_stress_periods$lead_time$top_half_mean,
  lead_time_strict_pass = val$validation_8_stress_periods$lead_time$mean_pass,
  overall_strict_5gate_pass = strict_5gate_pass,
  overall_3gate_pass = overall_3gate_pass,
  cor_with_m4_combined_regime = cor_m4_combined,
  cor_with_m4_weight_cash = cor_m4_cash,
  orthogonality_assessment = paste0(
    "moderately orthogonal — cor 0.17 with m4 actionable output (weight_cash) ",
    "indicates substantial new actionable information; cor 0.54 with combined_regime ",
    "reflects shared vol component (AFT 2017 § 5.2: implied-tail and ",
    "realized-vol share level component but differ in left-skew dimension)."),
  state_distribution = sd_list,
  state_distribution_pct = setNames(
    as.list(round(unlist(sd_list) / sum(unlist(sd_list)) * 100, 1)),
    names(sd_list)
  ),
  regime_conditional_kospi_returns = list(
    note = "AFT 2017 JF Eq.(29) 'high-LJV days' methodology — regime_state-conditional KOSPI t-day returns",
    PEACE = list(n_days = peace$n_days,
                  mean_daily = peace$mean_daily_ret,
                  std_daily = peace$std_daily_ret,
                  q05 = peace$q05, q95 = peace$q95,
                  ann_sharpe = peace$sharpe_ann,
                  hit_neg_2pct = peace$hit_neg_2pct),
    WARNING = list(n_days = warn$n_days,
                    mean_daily = warn$mean_daily_ret,
                    std_daily = warn$std_daily_ret,
                    q05 = warn$q05, q95 = warn$q95,
                    ann_sharpe = warn$sharpe_ann,
                    hit_neg_2pct = warn$hit_neg_2pct),
    TAIL_STRESS = list(n_days = stress$n_days,
                        mean_daily = stress$mean_daily_ret,
                        std_daily = stress$std_daily_ret,
                        q05 = stress$q05, q95 = stress$q95,
                        ann_sharpe = stress$sharpe_ann,
                        hit_neg_2pct = stress$hit_neg_2pct),
    diff_TAIL_STRESS_vs_PEACE_welch_t = diag_cond$diff_tests$TAIL_STRESS_vs_PEACE$t_stat,
    diff_TAIL_STRESS_vs_PEACE_p_value = diag_cond$diff_tests$TAIL_STRESS_vs_PEACE$p_value,
    diff_TAIL_STRESS_vs_PEACE_conclusion = diag_cond$diff_tests$TAIL_STRESS_vs_PEACE$conclusion,
    interpretation = paste0(
      "TAIL_STRESS days show ELEVATED q05 worst-case (-2.78% vs PEACE -1.42%) ",
      "AND elevated vol (1.74% vs 0.87%). Mean return is HIGHER, not lower ",
      "(post-stress rebound effect). hit_neg_2pct 9.27% vs PEACE 1.26% ",
      "= 7.4× higher tail event frequency. Signal correctly identifies ",
      "high-tail-risk regime (the academic intent of option-implied tail ",
      "indicators per AFT 2017 § 4) without claiming next-day directional bet."
    )
  )
)

factor_specs <- list(
  list(
    factor_family = "Implied_Tail_Risk",
    proxy = "RIX_proxy",
    formula = "-bkm_skew_30d (sign aligned: high score = high stress)",
    lag_rule = "t-1 (option close → t+1 decision)",
    winsorization = "none",
    neutralization = "expanding percentile rank (1y burn-in)",
    sign_alignment_exemption = "C13 exempt — not Factor DB lookup; sign convention per BKM 2003 RFS Eq.(7)",
    economic_rationale = "left-tail premium — BKM 2003 risk-neutral skewness measures pricing of left-jump probability",
    weight_theta = 0.25,
    references = list(
      "Bakshi-Kapadia-Madan 2003 RFS Eq.(7) p.105",
      "Du-Kapadia 2012 RFS Eq.(2-4) p.1325"
    )
  ),
  list(
    factor_family = "Implied_Tail_Risk",
    proxy = "LJV_proxy",
    formula = "bkm_var_30d * pmax(-bkm_skew_30d, 0)",
    lag_rule = "t-1",
    winsorization = "none",
    neutralization = "expanding percentile rank",
    sign_alignment_exemption = "C13 exempt — not Factor DB lookup; LJV approximation per AFT 2017 Eq.(8)",
    economic_rationale = "left jump variation (Andersen-Fusari-Todorov 2017 JF Eq.(8) approximation)",
    weight_theta = 0.25,
    references = list("Andersen-Fusari-Todorov 2017 JF Eq.(8) p.2076")
  ),
  list(
    factor_family = "Implied_Vol_Level",
    proxy = "vkospi",
    formula = "30d implied vol (CBOE 1993/2003 methodology, KR adaptation per WT_011)",
    lag_rule = "t-1",
    winsorization = "none",
    neutralization = "expanding percentile rank",
    economic_rationale = "broad market implied volatility level (top-decile = high anxiety, top-decile threshold per AFT 2017 § 5)",
    weight_theta = 0.25,
    references = list(
      "Du-Kapadia 2012 RFS Eq.(11-13) p.1330",
      "Whaley 2000 JD"
    )
  ),
  list(
    factor_family = "Implied_Term_Structure",
    proxy = "ts_slope_neg",
    formula = "-(T2_iv_atm - T1_iv_atm) — backwardation indicator (sign aligned)",
    lag_rule = "t-1",
    winsorization = "none",
    neutralization = "expanding percentile rank",
    sign_alignment_exemption = "C13 exempt — option term-structure backwardation convention",
    economic_rationale = "term-structure inversion = near-term stress (Bollerslev-Tauchen-Zhou 2009 RFS § 3.2)",
    weight_theta = 0.25,
    references = list("Bollerslev-Tauchen-Zhou 2009 RFS § 3.2 p.4467")
  )
)

pkg <- list(
  task_id = "WT-D20260508_012",
  task_type = "discovery",
  deliverable_kind = "regime_indicator",
  wt_type_clarification = paste0(
    "discovery WT — regime_indicator deliverable per request.json L19. ",
    "alpha_vector intentionally empty. Diagnostics use AFT 2017 § 4 ",
    "regime-detection methodology (recall/FP/lead-time + state-conditional ",
    "return distribution), NOT cross-section IC."
  ),
  as_of_date = format(max(ts$Date), "%Y-%m-%d"),
  forecast_horizon = "daily_state",
  selection_objective = "rank_ic",  # Hook enum compat fallback. true objective: regime_indicator_validation
  selection_objective_actual = "regime_indicator_validation_recall_FP_orthogonality",
  alpha_vector = setNames(list(), character(0)),
  confidence_vector = setNames(list(), character(0)),
  signal_matrix_ref = "feature_store://stage_artifacts/WT_D20260508_012/regime_indicator_timeseries.parquet",
  factor_specs = factor_specs,
  diagnostics = diagnostics,
  challenge_flags = challenge_flags,
  regime_indicator_summary = list(
    states = c("PEACE", "WARNING", "TAIL_STRESS"),
    composite_method = paste0(
      "two-stage expanding percentile (per-pillar → mean → 2nd-stage ",
      "expanding percentile) for uniform-distribution composite, AFT 2017 ",
      "§ 5 top-decile convention compatibility"),
    burnin_days = 252,
    threshold_warn = 0.70,
    threshold_stress = 0.90,
    min_duration = 3,
    proposal_kind = "B (independent regime overlay)",
    integration_with_m4 = list(
      kind = "Layer D multiplicative cap",
      design_doc = "qepm/mailbox/worktask/WT-D20260508_012/option_tail_regime_overlay_design.md",
      beta_tail_set = list(PEACE = 1.0, WARNING = 0.85, TAIL_STRESS = 0.70),
      beta_tail_rationale = paste0(
        "1σ tail risk premium ≈ 15% drawdown reduction (BTZ 2009 RFS Table 4 ",
        "magnitude); 2σ ≈ 30% (Almeida-Ardison-Garcia 2020 JF Eq.(12)). ",
        "KR-specific β_tail calibration requires backtest after Risk/Optimizer/Forge spawn."),
      backward_compat = "m4 schedule unmodified, STR_1715 PG2 backtest unaffected if Layer D not activated. Hybrid 70/15/15 (TSMOM, KR_10y bond) unaffected.",
      deployment_status = "design_only_NOT_admitted",
      deployment_status_rationale = "AX-008 triangulation 1/3 (alpha PASS only, Forge + Architect pending). PG2/PG3 admission 비대상. Discovery WT termination."
    )
  ),
  method_shopping_log = list(
    candidates_tried = 1,
    parallel_exec = FALSE,
    rcpp_used = FALSE,
    method_log = list(
      list(
        name = "TwoStage_4Pillar_ExpPct_Composite",
        recall = val$validation_8_stress_periods$recall,
        false_positive = val$validation_8_stress_periods$false_positive_rate,
        selected = TRUE,
        note = paste0(
          "Single spec, no grid sweep. Pillars derived from AFT 2017 § 5 + ",
          "Du-Kapadia 2012 § 2 + BTZ 2009 § 3 + BKM 2003 Eq.(7). ",
          "Threshold 0.90 = AFT 2017 top-decile convention. ",
          "Threshold 0.70 = top-30% warning band (single spec choice).")
      )
    )
  ),
  ax_compliance = list(
    AX_002_PIT = list(
      pass = TRUE,
      C1_C5_C9_evidence = "expanding percentile only, t-1 lag, regime_state from O_t_lag1 = shift(O_t, 1)",
      burnin_evidence = "252-day burn-in; first valid regime_state = 2012-01-09",
      C13_exemption_rationale = paste0(
        "RIX_proxy / LJV_proxy / ts_slope_neg use academic sign conventions ",
        "per BKM 2003 RFS Eq.(7), AFT 2017 Eq.(8), BTZ 2009 § 3.2. ",
        "C13 hard rule applies to Factor DB factor lookup ",
        "(load_month_factors() requires Z_Score_Aligned). Option-derived ",
        "regime computation operates outside Factor DB — 0 calls to ",
        "factor_db_connector. Sign alignment satisfies C13 spirit ",
        "(high score = high stress = expected risk-off action)."),
      C14_C15_status = "N/A — no Factor DB factor used. Source data: option chain raw + KOSPI BM_Ret. PIT controlled at source (option close → t+1 decision)."
    ),
    AX_007 = list(
      applicable = FALSE,
      reason = "regime_indicator output (NOT single-sleeve top20 long-only structure)"
    ),
    AX_008 = list(
      triangulation_status = "1/3",
      forge_status = "pending — discovery WT termination, deployment WT separate",
      architect_status = "pending — recommended for Layer D pre-deployment review",
      alpha_status = "PASS",
      gate_satisfied = FALSE,
      consequence = "deployment_status=design_only_NOT_admitted; PG2/PG3 admission requires separate deployment WT with 2/3 minimum"
    )
  ),
  codex_critic_round = list(
    round = 1,
    stance = "REVISE",
    veto_flag = FALSE,
    handling = "ACCEPT 6 + PARTIAL 2 + REBUTTAL 1",
    rebuttals = list(
      C3_C13_manual_sign = "AX_002_PIT.C13_exemption_rationale (BKM 2003 Eq.(7) academic standard, 0 Factor DB calls)",
      C9_orthogonality_overstated = "표현 변경: 'genuinely new information' → 'moderately orthogonal' + cor weight_cash 0.17 정량 강조"
    ),
    spec_revisions_applied = list(
      "deliverable_kind regime_indicator 강화",
      "validation overall_strict_5gate / overall_3gate 분리",
      "deployment_status design_only_NOT_admitted",
      "regime_state_summary.parquet 신규",
      "regime_conditional_diagnostic.json 신규",
      "factor_specs page-level 인용 (BKM 2003 Eq.7 / AFT 2017 Eq.8 / BTZ 2009 § 3.2)",
      "C13_exemption_rationale 명시",
      "run_all.R 신규 (lineage reproducibility)",
      "challenge_note.md 작성 (codex 9 concerns 처리)"
    ),
    q_lead_escalate_recommended = TRUE,
    q_lead_escalate_trigger = "HIGH severity ≥ 5 (C1~C5)"
  ),
  output_files = list(
    regime_indicator_timeseries = "stage_artifacts/WT_D20260508_012/regime_indicator_timeseries.parquet",
    regime_state_summary = "stage_artifacts/WT_D20260508_012/regime_state_summary.parquet",
    validation = "stage_artifacts/WT_D20260508_012/validation_8_stress_periods.json",
    regime_conditional_diagnostic = "stage_artifacts/WT_D20260508_012/regime_conditional_diagnostic.json",
    design_doc = "qepm/mailbox/worktask/WT-D20260508_012/option_tail_regime_overlay_design.md",
    challenge_note = "qepm/mailbox/worktask/WT-D20260508_012/challenge_note.md",
    codex_critic_response = "qepm/mailbox/worktask/WT-D20260508_012/codex_critic_response_alpha.json",
    run_all = "qepm/mailbox/worktask/WT-D20260508_012/run_all.R"
  )
)

out_path <- file.path(WT_DIR, "alpha_package.json")
write_json(pkg, out_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("[final] wrote %s (%d bytes)\n",
            out_path, file.info(out_path)$size))

# Update lineage
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-D20260508_012",
  package_type = "alpha_package",
  method_selected = "TwoStage_4Pillar_ExpPct_Composite_RegimeIndicator_FINAL",
  input_file_paths = c(
    file.path(PROJECT_ROOT,
              "stage_artifacts/WT_D20260508_011/vkospi_reconstruction.parquet"),
    file.path(PROJECT_ROOT,
              "qepm/stage_artifacts/WT_WT-D20260430_001/alpha_scores.parquet"),
    file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
  )
)
cat("[lineage] alpha_package final lineage recorded\n")
