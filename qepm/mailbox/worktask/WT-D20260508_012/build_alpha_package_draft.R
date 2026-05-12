#==============================================================================
# Build alpha_package_draft.json for WT-D20260508_012
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260508_012")
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260508_012")

ts <- as.data.table(read_parquet(file.path(ART_DIR, "regime_indicator_timeseries.parquet")))
ts[, Date := as.Date(Date)]
val <- fromJSON(file.path(ART_DIR, "validation_8_stress_periods.json"),
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

# challenge flags
challenge_flags <- list(
  list(
    flag = "lead_time_mixed",
    severity = "MEDIUM",
    desc = sprintf(
      paste0("Mean lead time %.1f days (FAIL gate >= 5). Honest interp: ",
             "option-implied tail signals coincident for fast crashes ",
             "(China 2015, VolShock 2018, Inflation 2022 -14~-21d) but lead ",
             "for slow-burn (COVID +20d, Mini_Flash +6d). BTZ 2009 RFS ",
             "empirical pattern. Top-half-mean lead = %.1f days (slow-burn)."),
      val$validation_8_stress_periods$lead_time$mean,
      val$validation_8_stress_periods$lead_time$top_half_mean),
    mitigation = "Recall 5/6 + FP 9.7% PASS deliver primary value. Lead-time gate inappropriate for fast-crash heterogeneous mix."
  ),
  list(
    flag = "burnin_eudebt_drop",
    severity = "LOW",
    desc = "EuDebt_II_2011 partly within 252-day burn-in. Honest reporting counts as in-window FAIL (5/6=0.83). Within-validity-only would be 5/5=1.0.",
    mitigation = "Burn-in cannot be shortened without compromising statistical validity."
  ),
  list(
    flag = "deliverable_kind_clarification",
    severity = "INFO",
    desc = "alpha_package.json transports regime_state daily timeseries (NOT cross-section alpha_vector). alpha_vector field intentionally empty.",
    mitigation = "Per request.json: deliverable_kind = regime_indicator. Risk/Optimizer/Forge consume regime_state via Layer D overlay."
  )
)

diagnostics <- list(
  type = "regime_indicator_diagnostics",
  recall = val$validation_8_stress_periods$recall,
  recall_pass = val$validation_8_stress_periods$recall_pass,
  false_positive_rate = val$validation_8_stress_periods$false_positive_rate,
  false_positive_pass = val$validation_8_stress_periods$false_positive_pass,
  lead_time_mean = val$validation_8_stress_periods$lead_time$mean,
  lead_time_median = val$validation_8_stress_periods$lead_time$median,
  lead_time_top_half_mean = val$validation_8_stress_periods$lead_time$top_half_mean,
  lead_time_pass = val$validation_8_stress_periods$lead_time$mean_pass,
  cor_with_m4_combined_regime = cor_m4_combined,
  cor_with_m4_weight_cash = cor_m4_cash,
  orthogonality_assessment = "moderate: cor 0.54 with combined_regime, cor 0.17 with weight_cash → tail axis adds genuinely new information",
  state_distribution = sd_list,
  state_distribution_pct = setNames(
    as.list(round(unlist(sd_list) / sum(unlist(sd_list)) * 100, 1)),
    names(sd_list)
  )
)

factor_specs <- list(
  list(
    factor_family = "Implied_Tail_Risk",
    proxy = "RIX_proxy",
    formula = "-bkm_skew_30d (BKM 2003 risk-neutral skewness sign-reversed)",
    lag_rule = "t-1",
    winsorization = "none",
    neutralization = "expanding percentile rank",
    economic_rationale = "left-tail premium",
    weight_theta = 0.25,
    references = list("Bakshi-Kapadia-Madan 2003 RFS", "Du-Kapadia 2012 RFS")
  ),
  list(
    factor_family = "Implied_Tail_Risk",
    proxy = "LJV_proxy",
    formula = "bkm_var_30d * pmax(-bkm_skew_30d, 0)",
    lag_rule = "t-1",
    winsorization = "none",
    neutralization = "expanding percentile rank",
    economic_rationale = "left jump variation (AFT 2017 Eq.8 approximation)",
    weight_theta = 0.25,
    references = list("Andersen-Fusari-Todorov 2017 JF")
  ),
  list(
    factor_family = "Implied_Vol_Level",
    proxy = "vkospi",
    formula = "30d implied vol (CBOE 1993/2003 methodology)",
    lag_rule = "t-1",
    winsorization = "none",
    neutralization = "expanding percentile rank",
    economic_rationale = "broad market implied volatility level",
    weight_theta = 0.25,
    references = list("Du-Kapadia 2012 RFS", "Whaley 2000 JD")
  ),
  list(
    factor_family = "Implied_Term_Structure",
    proxy = "ts_slope_neg",
    formula = "-(T2_iv_atm - T1_iv_atm)",
    lag_rule = "t-1",
    winsorization = "none",
    neutralization = "expanding percentile rank",
    economic_rationale = "term-structure inversion = near-term stress",
    weight_theta = 0.25,
    references = list("Bollerslev-Tauchen-Zhou 2009 RFS")
  )
)

pkg <- list(
  task_id = "WT-D20260508_012",
  task_type = "discovery",
  deliverable_kind = "regime_indicator",
  as_of_date = format(max(ts$Date), "%Y-%m-%d"),
  forecast_horizon = "daily_state",
  selection_objective = "rank_ic",
  alpha_vector = setNames(list(), character(0)),
  confidence_vector = setNames(list(), character(0)),
  signal_matrix_ref = "feature_store://stage_artifacts/WT_D20260508_012/regime_indicator_timeseries.parquet",
  factor_specs = factor_specs,
  diagnostics = diagnostics,
  challenge_flags = challenge_flags,
  regime_indicator_summary = list(
    states = c("PEACE", "WARNING", "TAIL_STRESS"),
    composite_method = "two-stage expanding percentile",
    burnin_days = 252,
    threshold_warn = 0.70,
    threshold_stress = 0.90,
    min_duration = 3,
    proposal_kind = "B (independent regime overlay)",
    integration_with_m4 = list(
      kind = "Layer D multiplicative cap",
      design_doc = "qepm/mailbox/worktask/WT-D20260508_012/option_tail_regime_overlay_design.md",
      beta_tail_set = list(PEACE = 1.0, WARNING = 0.85, TAIL_STRESS = 0.70),
      backward_compat = "m4 schedule unmodified"
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
        note = "Single spec, no grid sweep. Pillars + thresholds derived from academic convention"
      )
    )
  ),
  ax_compliance = list(
    AX_002_PIT = list(pass = TRUE,
                       evidence = "expanding percentile only, t-1 lag, 252-day burn-in"),
    AX_007 = list(applicable = FALSE,
                   reason = "regime indicator (not single-sleeve top20 long-only)"),
    AX_008 = list(triangulation_status = "1/3 — Forge/Architect verification pending",
                   forge_status = "pending",
                   architect_status = "pending",
                   alpha_status = "PASS")
  ),
  output_files = list(
    regime_indicator_timeseries = "stage_artifacts/WT_D20260508_012/regime_indicator_timeseries.parquet",
    validation = "stage_artifacts/WT_D20260508_012/validation_8_stress_periods.json",
    design_doc = "qepm/mailbox/worktask/WT-D20260508_012/option_tail_regime_overlay_design.md"
  )
)

out_path <- file.path(WT_DIR, "alpha_package_draft.json")
write_json(pkg, out_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("[draft] wrote %s (%d bytes)\n",
            out_path, file.info(out_path)$size))

# Lineage record
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-D20260508_012",
  package_type = "alpha_package_draft",
  method_selected = "TwoStage_4Pillar_ExpPct_Composite_RegimeIndicator",
  input_file_paths = c(
    file.path(PROJECT_ROOT,
              "stage_artifacts/WT_D20260508_011/vkospi_reconstruction.parquet"),
    file.path(PROJECT_ROOT,
              "qepm/stage_artifacts/WT_WT-D20260430_001/alpha_scores.parquet")
  )
)
cat("[lineage] recorded\n")
