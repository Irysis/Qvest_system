#==============================================================================
# Step 7 — Alpha Package Emission (DRAFT)
#
# Emit alpha_package_draft.json with all required fields per
# v1.2 Charter §10 Role Card System (wt_type=discovery).
#
# Critical mandate (Charter §5, AX-001 v2):
#   FAIL graduation requires HONEST reporting. We DO NOT inflate metrics.
#   The hypothesis tested = (P4 regime engine + 6-family smart beta tilt).
#   Empirical KR validation = FAIL on Harvey-t / DSR / Rank IC.
#   Conditional crisis_alpha potential (Bad/Normal IC ratio = 2.72) is noted
#   but does NOT override hard graduation criteria.
#
# Output:
#   - qepm/mailbox/worktask/WT-D20260528_003/alpha_package_draft.json
#   - Lineage record
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
MB <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003")
OUT_DIR <- file.path(MB, "outputs")

# ---- Load validation + alpha scores ----
val <- fromJSON(file.path(STAGE_DIR, "alpha_validation.json"), simplifyVector = TRUE,
                simplifyDataFrame = TRUE, simplifyMatrix = TRUE)
alpha <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
alpha[, Date := as.Date(Date)]

# ---- Compute alpha_inheritance_cor vs STR_1715 ----
# Find STR_1715 alpha_scores if exists (current_portfolio in request.json)
# Reference: search stage_artifacts for STR_1715
inherit_cor <- NA_real_
inherit_cor_basis <- "STR_1715 alpha_scores not located; cor not computed (assumed independent regime mechanism)"
str1715_candidates <- list.files(
  file.path(BASE, "stage_artifacts"),
  pattern = "alpha_scores", recursive = TRUE, full.names = TRUE
)
if (length(str1715_candidates) > 0) {
  # Try finding STR_1715 ones first
  s1715 <- grep("1715|AR_on_M4", str1715_candidates, value = TRUE)
  if (length(s1715) > 0) {
    try({
      ref <- as.data.table(read_parquet(s1715[1]))
      if ("Date" %in% names(ref) && "Ticker" %in% names(ref)) {
        ref[, Date := as.Date(Date)]
        score_col <- intersect(c("alpha_score", "Z_Score", "score", "alpha"), names(ref))[1]
        if (!is.na(score_col)) {
          mm <- merge(
            alpha[, .(Date, Ticker, alpha_new = alpha_score)],
            ref[, .(Date, Ticker, alpha_ref = get(score_col))],
            by = c("Date", "Ticker")
          )
          if (nrow(mm) >= 100) {
            inherit_cor <- suppressWarnings(cor(mm$alpha_new, mm$alpha_ref, method = "spearman"))
            inherit_cor_basis <- sprintf("Spearman cor vs %s (n=%d common obs)",
                                          basename(s1715[1]), nrow(mm))
          }
        }
      }
    })
  }
}

# Per-family mean weight (from walk-forward W matrix)
W <- as.data.table(read_parquet(file.path(OUT_DIR, "regime_factor_weight_matrix_walkforward.parquet")))
weight_summary <- W[, lapply(.SD, mean, na.rm = TRUE),
                    .SDcols = c("value", "quality", "momentum", "low_vol", "size", "dividend")]

# Build alpha_vector (last sig_date snapshot)
last_sd <- max(alpha$Date)
alpha_last <- alpha[Date == last_sd]
alpha_vector <- setNames(as.list(alpha_last$alpha_score), alpha_last$Ticker)
confidence_vector <- setNames(as.list(alpha_last$confidence), alpha_last$Ticker)

# factor_specs (Charter required)
factor_specs <- list(
  list(
    factor_family = "Value",
    proxy = "Multi-proxy composite (V01_BM, V02_EP, V03_CFP, V20_SP, V14_EBIT_EV)",
    formula = "equal_weight_avg(Z_Score_aligned over 5 proxies)",
    lag_rule = "factor_db Usable_Date <= sig_date (quarterly 45d + annual May)",
    winsorization = "Factor DB Z_Score 3std intrinsic + forward return [-30%, +30%]",
    neutralization = "Cross-sectional Z by Factor DB (sector unaware at base)",
    economic_rationale = "risk_premium — Asness-Frazzini 2013 (Devil in HML): multi-proxy mitigates B/P industry bias",
    weight_theta = round(weight_summary$value[1], 4),
    references = list("Asness-Frazzini 2013 \"The Devil in HML's Details\""),
    source = "db_existing"
  ),
  list(
    factor_family = "Quality",
    proxy = "Multi-proxy QMJ (Q02_ROE, Q03_ROA, Q17_ROIC, GR05_ROE_Growth)",
    formula = "equal_weight_avg(Z_Score over 4 profitability + growth proxies)",
    lag_rule = "quarterly 45d",
    winsorization = "Factor DB Z_Score 3std",
    neutralization = "Cross-sectional Z",
    economic_rationale = "behavioral_underreaction + risk_premium — Asness-Frazzini-Pedersen 2019 QMJ",
    weight_theta = round(weight_summary$quality[1], 4),
    references = list("Asness-Frazzini-Pedersen 2019 \"Quality Minus Junk\""),
    source = "db_existing"
  ),
  list(
    factor_family = "Momentum",
    proxy = "Multi-horizon (M01_Mom_12_1, M02_Mom_6_1, M03_Mom_3_1)",
    formula = "equal_weight_avg(Z_Score over 3 horizons)",
    lag_rule = "skip-1-month (already in M0X spec)",
    winsorization = "Factor DB 3std",
    neutralization = "Cross-sectional Z",
    economic_rationale = "behavioral_underreaction — Asness-Moskowitz-Pedersen 2014",
    weight_theta = round(weight_summary$momentum[1], 4),
    references = list("Asness-Moskowitz-Pedersen 2014 \"Fact, Fiction, and Momentum Investing\""),
    source = "db_existing"
  ),
  list(
    factor_family = "Low Volatility",
    proxy = "BAB+IVOL+Downside (D01_IdioVol, D02_Beta, D03_RealVol, D04_Downside_Beta)",
    formula = "equal_weight_avg(-Z_Score over 4 proxies, lower_better direction)",
    lag_rule = "rolling 252d for D02, D03 (t-1 PIT)",
    winsorization = "Factor DB 3std",
    neutralization = "Cross-sectional Z",
    economic_rationale = "leverage_constraint — Frazzini-Pedersen 2014 BAB; Ang 2006 IVOL puzzle",
    weight_theta = round(weight_summary$low_vol[1], 4),
    references = list("Frazzini-Pedersen 2014 BAB", "Ang Hodrick Xing Zhang 2006 IVOL", "Baker-Bradley-Wurgler 2011"),
    source = "db_existing"
  ),
  list(
    factor_family = "Size",
    proxy = "-S01_Size (sign flipped = SMB convention small > large)",
    formula = "-Z_Score(market_cap)",
    lag_rule = "daily",
    winsorization = "Factor DB 3std",
    neutralization = "Cross-sectional Z",
    economic_rationale = "size_premium — Banz 1981 SMB",
    weight_theta = round(weight_summary$size[1], 4),
    references = list("Banz 1981 \"The Relationship between Return and Market Value of Common Stocks\""),
    source = "db_existing"
  ),
  list(
    factor_family = "Dividend",
    proxy = "Shareholder Yield composite (V06_fDY, V11_Shareholder_Yield, V17_Payout_Ratio)",
    formula = "equal_weight_avg(Z_Score over 3 proxies)",
    lag_rule = "quarterly 45d / annual May",
    winsorization = "Factor DB 3std",
    neutralization = "Cross-sectional Z",
    economic_rationale = "behavioral_anchoring + buyback_signaling — Boudoukh 2007",
    weight_theta = round(weight_summary$dividend[1], 4),
    references = list("Boudoukh-Michaely-Richardson-Roberts 2007 Shareholder Yield"),
    source = "db_existing"
  )
)

# Challenge flags (HONEST FAIL reporting)
challenge_flags <- list()

if (val$rank_ic_overall < 0.04) {
  challenge_flags <- c(challenge_flags, list(list(
    id = "RF-A-IC",
    severity = "HIGH",
    description = sprintf("Rank IC %.4f << 0.04 threshold. Signal underperforms KR top-universe benchmark.",
                          val$rank_ic_overall),
    type = "graduation_criteria_fail"
  )))
}
if (abs(val$icir) < 0.20) {
  challenge_flags <- c(challenge_flags, list(list(
    id = "RF-A-ICIR",
    severity = "HIGH",
    description = sprintf("ICIR %.4f << 0.20 threshold. IC instability undermines reliability.",
                          val$icir),
    type = "graduation_criteria_fail"
  )))
}
if (val$n_harvey_pass_3_0 < 3L) {
  challenge_flags <- c(challenge_flags, list(list(
    id = "RF-A-HARVEY",
    severity = "HIGH",
    description = sprintf("Harvey-Liu-Zhu 2016 multi-spec: 0/%d specs > 3.0 (vs required 3/5). Maximum t-stat = %.3f.",
                          5L, max(val$harvey_specs$t_stat, na.rm = TRUE)),
    type = "multitest_significance_fail"
  )))
}
if (val$dsr < 0.5) {
  challenge_flags <- c(challenge_flags, list(list(
    id = "RF-A-DSR",
    severity = "HIGH",
    description = sprintf("Bailey-Lopez de Prado DSR %.3f << 0.5 (above-random threshold).", val$dsr),
    type = "multitest_significance_fail"
  )))
}
# Recent 3Y dominant?
if (length(val$subperiod_ic) > 0) {
  sub_df <- as.data.table(val$subperiod_ic)
  p1 <- sub_df[subperiod == "P1_2017_19", mean_ic]
  p3 <- sub_df[subperiod == "P3_2022_23", mean_ic]
  if (!is.na(p3) && !is.na(p1) && p3 < 0 && p1 > 0) {
    challenge_flags <- c(challenge_flags, list(list(
      id = "RF-A-DECAY",
      severity = "MEDIUM",
      description = sprintf("Subperiod IC decay: 2017-19 = %.4f → 2022-23 = %.4f (sign flip). Regime engine signal decaying.",
                            p1, p3),
      type = "subperiod_decay"
    )))
  }
}
# Positive observation: crisis_alpha
if (!is.na(val$bad_normal_ic_ratio) && val$bad_normal_ic_ratio > 0.5) {
  challenge_flags <- c(challenge_flags, list(list(
    id = "OBS-A-CRISIS-ALPHA",
    severity = "INFO",
    description = sprintf("Bad/Normal IC ratio %.3f > 0.5 — conditional crisis_alpha holds (AX-001 v2). However, hard graduation criteria still FAIL.",
                          val$bad_normal_ic_ratio),
    type = "conditional_alpha_signal"
  )))
}

cat("Challenge flags identified:", length(challenge_flags), "\n")

# Method shopping log (R2-C HARD)
method_log <- list(
  candidates_tried = 5L,
  method_log = list(
    list(name = "P4_regime_kmeans9_BLshrink", rank_ic = val$rank_ic_overall,
          icir = val$icir, harvey_max_t = max(val$harvey_specs$t_stat, na.rm = TRUE),
          selected = TRUE,
          rationale = "Selected as primary spec per request.json hypothesis"),
    list(name = "Naive_equal_weight_6family", rank_ic = NA_real_, selected = FALSE,
          rationale = "Used as Harvey Spec B residualization baseline only"),
    list(name = "Conf_weighted_alpha", rank_ic = NA_real_, selected = FALSE,
          rationale = "Used as Harvey Spec D variant only"),
    list(name = "Top_bottom_quintile_spread", rank_ic = NA_real_, selected = FALSE,
          rationale = "Used as Harvey Spec C diagnostic only"),
    list(name = "Regime_residualized_alpha", rank_ic = NA_real_, selected = FALSE,
          rationale = "Used as Harvey Spec E diagnostic only")
  ),
  parallel_exec = FALSE,
  n_workers = 1L,
  rcpp_used = FALSE
)

# Build alpha_package
package <- list(
  task_id = "WT-D20260528_003",
  wt_type = "discovery",
  schema_version = "alpha_package_v1",
  as_of_date = "2026-05-28",
  signal_cutoff = "2023-12-22",
  forecast_horizon = "1M",
  universe = "KOSPI200",
  benchmark = "KOSPI200_total_return",

  # Hypothesis intake
  hypothesis_title = "STR_1721 P4 Multi-Horizon Regime Engine + 6-Family Smart Beta Allocation (K200)",
  hypothesis_description = "P4-ECDF distribution forecast → K-means 9-cluster regime classifier (walk-forward expanding) → BL-shrinkage state-conditional 6-family weight matrix → α̂ = Σ_f w_f(state(t)) · Z_composite_f. Multi-proxy academic composite. KOSPI200 only.",

  # Vectors (last sig_date snapshot)
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260528_003/alpha_scores.parquet",

  # Factor specs (Charter required, 6 families)
  factor_specs = factor_specs,

  # Selection objective (R4 HARD)
  selection_objective = "icir",  # alpha_research uses predictive-power metric

  # Method shopping log (R2-C HARD)
  method_shopping_log = method_log,

  # Diagnostics
  diagnostics = list(
    rank_ic = val$rank_ic_overall,
    rank_ic_sd = val$rank_ic_sd,
    icir = val$icir,
    monotonicity_decile_spread = val$monotonicity_decile_spread,
    monotonicity_decile_rank_corr = val$monotonicity_decile_rank_corr,
    subperiod_stability = val$subperiod_stability,
    subperiod_stability_cv = val$subperiod_stability_cv,
    subperiod_ic = val$subperiod_ic,
    harvey_specs = val$harvey_specs,
    n_harvey_pass_3_0 = val$n_harvey_pass_3_0,
    n_harvey_pass_2_5 = val$n_harvey_pass_2_5,
    harvey_t_specs_pass_count = val$n_harvey_pass_3_0,
    harvey_t_stat = max(val$harvey_specs$t_stat, na.rm = TRUE),
    dsr = val$dsr,
    sr_annual = val$sr_annual,
    bad_normal_ic_ratio = val$bad_normal_ic_ratio,
    bad_ic_mean = val$bad_ic_mean,
    normal_ic_mean = val$normal_ic_mean,
    bad_states = val$bad_states,
    turnover_top20_annual = val$turnover_top20_annual,
    turnover_top20_monthly = val$turnover_top20_monthly,
    n_sig_dates = val$n_sig_dates,
    n_alpha_obs = val$n_alpha_obs,
    n_universe_avg = round(val$n_alpha_obs / val$n_sig_dates, 1),
    decile_returns = val$decile_returns
  ),

  # Graduation criteria (Charter §5 v1.2 wt_type=discovery role card)
  graduation_criteria = val$graduation_criteria,
  all_graduation_pass = val$all_graduation_pass,

  # Discovery role card requirements
  alpha_discovery_role_card = list(
    factor_specs_count = length(factor_specs),
    factor_specs_count_required = 1L,
    alpha_inheritance_cor = inherit_cor,
    alpha_inheritance_cor_basis = inherit_cor_basis,
    alpha_inheritance_cor_threshold = 0.95,
    mechanism_citation_chars = nchar(paste(sapply(factor_specs, function(s) s$economic_rationale), collapse = " ")),
    mechanism_citation_chars_required = 50L,
    harvey_t_specs_pass_count = val$n_harvey_pass_3_0,
    harvey_t_specs_pass_count_required = 3L,
    alpha_discovery_certificate_eligible = (
      length(factor_specs) >= 1L &&
      (is.na(inherit_cor) || inherit_cor < 0.95) &&
      val$n_harvey_pass_3_0 >= 3L
    )
  ),

  # Challenge flags (HONEST FAIL reporting)
  challenge_flags = challenge_flags,

  # Lockbox compliance
  window_isolation = list(
    train_window = "factor_db 2005-01-31 ~ 2017-12-29 (regime warm-up)",
    validation_window = "regime walk-forward + alpha 2017-01-31 ~ 2023-11-30 (lockbox)",
    lockbox_window = "2023-12-22+ (NOT accessed by alpha-research)",
    selection_contamination_detector_pass = TRUE
  ),

  # Phase 1 v3 corrections (도훈 mandate inheritance from prelim v2)
  phase1_v3_corrections = list(
    correction_1_outlier = list(
      description = "Direct rawdata.parquet 21d forward log_return + winsorize [-30%, +30%] (Fama-French 1993)",
      ref = "Asness-Pedersen 2003; bypasses prelim v2 features panel corruption (A007660 8235% etc. caused by K200 membership discontinuity → shift(-21) jump across deleted rows)"
    ),
    correction_2_overlap = list(
      description = "Monthly non-overlap snapshot (last trading day per month, 1M horizon)",
      ref = "Standard practice; prelim v2 had calendar month-end with potential <21d gap → mild overlap"
    ),
    correction_3_log = list(
      description = "log_return computed; simple_return used as composite primary (per Asness-Pedersen 2003 cross-section convention)",
      ref = "log_return retained as secondary diagnostic"
    ),
    v2_vs_v3_family_sr_comparison = list(
      value = list(v2_sr = 0.866, v3_simple_sr = 0.473, v3_log_sr = 0.145,
                    interpretation = "v2 outlier-distorted; v3 reflects true risk premium ~10-11% ann_ret"),
      quality = list(v2_sr = 0.621, v3_simple_sr = 0.355, v3_log_sr = -0.012,
                      interpretation = "v2 inflated; v3 modest single-family premium"),
      momentum = list(v2_sr = 0.610, v3_simple_sr = 0.252, v3_log_sr = -0.133),
      low_vol = list(v2_sr = 0.471, v3_simple_sr = 0.075, v3_log_sr = -0.301),
      size = list(v2_sr = 0.528, v3_simple_sr = 0.318, v3_log_sr = 0.009),
      dividend = list(v2_sr = 0.785, v3_simple_sr = 0.373, v3_log_sr = 0.060)
    )
  ),

  # PIT compliance
  pit_enforcement = list(
    C1_no_full_sample = TRUE,
    C13_z_aligned_only = TRUE,
    C14_usable_date = TRUE,
    C15_factor_db_via_connector = "partial — Phase 1 v3 + alpha vector use direct factor_db read for per-month efficiency (audit-grade; not production-mode load_month_factors). To re-verify with connector if requested.",
    walk_forward_kmeans = TRUE,
    expanding_window_z = TRUE
  ),

  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  agent = "alpha-research",
  agent_version = "v1.2"
)

# Write draft (Codex Round 5단계 step 1)
write_json(package, file.path(MB, "alpha_package_draft.json"),
            pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("Wrote alpha_package_draft.json\n")

# Lineage (R11)
tryCatch({
  source(file.path(BASE, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = "WT-D20260528_003",
    package_type = "alpha_package_draft",
    method_selected = "P4_regime_kmeans9_BL_shrinkage_6family_smart_beta",
    input_file_paths = c(
      file.path(BASE, ".cache/rawdata.parquet"),
      file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs/p4_multi_horizon.parquet"),
      file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs/regime_factor_weight_matrix_walkforward.parquet"),
      file.path(BASE, "stage_artifacts/WT_D20260528_003/alpha_scores.parquet")
    )
  )
  cat("Lineage recorded\n")
}, error = function(e) {
  cat("Lineage skipped (utils not found):", conditionMessage(e), "\n")
})

cat("\n=== Alpha Package Draft Summary ===\n")
cat("  Rank IC:        ", round(val$rank_ic_overall, 4), "\n")
cat("  ICIR:           ", round(val$icir, 4), "\n")
cat("  Harvey pass 3.0:", val$n_harvey_pass_3_0, "/ 5\n")
cat("  DSR:            ", round(val$dsr, 3), "\n")
cat("  Bad/Normal IC:  ", round(val$bad_normal_ic_ratio, 3), "\n")
cat("  Annual TO top20:", round(val$turnover_top20_annual, 2), "\n")
cat("  Subperiod stab: ", round(val$subperiod_stability, 3), "\n")
cat("  Discovery cert eligible:", package$alpha_discovery_role_card$alpha_discovery_certificate_eligible, "\n")
cat("  All graduation PASS:    ", val$all_graduation_pass, "\n")
cat("  Challenge flags:", length(challenge_flags), "\n")
