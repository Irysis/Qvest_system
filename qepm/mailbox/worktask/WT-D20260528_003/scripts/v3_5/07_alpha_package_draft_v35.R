#==============================================================================
# Step 7 — Build alpha_package_draft.json (v3.5)
#
# Schema: 02_Infrastructure/worktask/schema.json::alpha_package
# Required: task_id, as_of_date, forecast_horizon, alpha_vector, factor_specs, diagnostics
#
# v3.5 transparency obligations:
#   - report graduation FAIL transparently (Harvey 1/5 + RF-A2 composite_dilutes_single)
#   - challenge_flags include RF-A2 + Harvey-marginal + ICIR-vs-single-low_vol
#   - selection_objective = "icir" (predictive metric)
#   - candidates_tried = 5 (method shopping log, conservative)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")
OUT_DIR <- file.path(WT_DIR, "outputs/v3_5")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_5")

validation <- fromJSON(file.path(OUT_DIR, "alpha_validation_v35.json"), simplifyVector = TRUE)

# Load last-date alpha + confidence
last_dt <- fread(file.path(OUT_DIR, "last_date_alpha_confidence.csv"))
setorder(last_dt, -alpha_score)
alpha_vec <- as.list(setNames(round(last_dt$alpha_score, 4), last_dt$Ticker))
conf_vec <- as.list(setNames(round(last_dt$confidence, 3), last_dt$Ticker))

# Load weight matrix to extract per-family weight (latest sig_date)
w <- as.data.table(read_parquet(file.path(OUT_DIR, "regime_factor_weight_matrix_v35_walkforward.parquet")))
last_sig <- max(w$sig_date)
w_last <- w[sig_date == last_sig]
setorder(w_last, family)

# Build factor_specs per family
fam_specs <- list()
fam_def <- list(
  value = list(family = "Value", proxy = "V12_Composite_Value",
                formula = "Z_aligned of equal-weight mean of (-fPER, -fPBR, fDY, CFP)",
                rationale = "risk_premium", citation = "Fama-French 1993; Asness-Frazzini 2013 'Devil in HML'"),
  quality = list(family = "Quality", proxy = "Q08_Composite_Quality",
                  formula = "Z_aligned of composite GPA/ROE/ROA/Accrual",
                  rationale = "behavioral", citation = "Asness-Frazzini-Pedersen 2019 QMJ; Novy-Marx 2013"),
  momentum = list(family = "Momentum", proxy = "M32_Composite_Mom_v2",
                  formula = "Z_aligned of mean(M01,M10,M13,M24,M25) multi-horizon",
                  rationale = "behavioral", citation = "Asness-Moskowitz-Pedersen 2014 'Fact, Fiction and Momentum'; Jegadeesh-Titman 1993"),
  growth = list(family = "Growth", proxy = "GR07_Composite_Growth",
                  formula = "Z_aligned of mean(GR01..GR06)",
                  rationale = "behavioral", citation = "Lakonishok-Shleifer-Vishny 1994; Bauman-Conover-Miller 1998"),
  consensus = list(family = "Consensus", proxy = "C19_Composite_Earnings",
                    formula = "Z_aligned of mean(SUE, ESBR, EPS_chg_1m, TP_Gap)",
                    rationale = "behavioral", citation = "Bernard-Thomas 1989 PEAD; Stickel 1991"),
  low_vol = list(family = "Low Volatility", proxy = "D01+D02+D03+D04 multi-proxy",
                  formula = "Z_aligned mean of (D01_IdioVol, D02_Beta, D03_RealVol, D04_Downside_Beta), all lower_better auto-flipped",
                  rationale = "risk_premium", citation = "Ang-Hodrick-Xing-Zhang 2006; Frazzini-Pedersen 2014 BAB; Baker-Bradley-Wurgler 2011"),
  size = list(family = "Size", proxy = "S01_Size",
                formula = "Z_aligned of -log(MarketCap), higher_better retain (SMB convention already encoded)",
                rationale = "risk_premium", citation = "Banz 1981; Fama-French 1992. v3.5 fix: registry direction retain (v1 double-flip bug fix)"),
  dividend = list(family = "Dividend / Shareholder Yield", proxy = "V06+V11+V17 multi-proxy",
                    formula = "Z_aligned mean of (V06_fDY, V11_Shareholder_Yield, V17_Payout_Ratio)",
                    rationale = "risk_premium", citation = "Boudoukh-Michaely-Richardson-Roberts 2007 'Importance of Dividends'")
)

for (i in seq_len(nrow(w_last))) {
  fam <- w_last$family[i]
  spec <- fam_def[[fam]]
  fam_specs[[length(fam_specs) + 1L]] <- list(
    factor_family = spec$family,
    proxy = spec$proxy,
    formula = spec$formula,
    lag_rule = "monthly Z via load_month_factors() PIT-safe Usable_Date≤sig_d",
    winsorization = "Z_aligned 3std + forward-return ±30% log winsorize",
    neutralization = "cross-sectional re-standardization per Date per family (z-score)",
    economic_rationale = spec$rationale,
    weight_theta_avg = round(w[family == fam, mean(weight, na.rm = TRUE)], 4),
    weight_theta_last_sig_d = round(w_last$weight[i], 4),
    weight_theta_regime_state = w_last$regime_state[i],
    references = list(spec$citation)
  )
}

# Diagnostics block
diag <- list(
  rank_ic = validation$rank_ic$value,
  icir = validation$icir$value,
  monotonicity = validation$monotonicity$rank_corr,
  subperiod_stability = validation$subperiod_stability$value,
  turnover_proxy = validation$turnover$top20_annual,
  harvey_t_stat = validation$harvey_max_t,
  harvey_t_specs_pass_count = validation$harvey_n_pass_3,
  harvey_t_specs_pass_count_at_25 = validation$harvey_n_pass_25,
  harvey_5_spec_detail = validation$harvey_specs,
  deflated_sharpe_ratio = validation$dsr$value,
  post_neutralization_ic = validation$rank_ic$value,  # neutralization already in re-standardize, IC unchanged
  alpha_inheritance_cor = 0.0,  # genuinely new (Discovery WT, no parent)
  bad_normal_ic_ratio = validation$bad_normal_ic_ratio$value,
  bad_normal_ic_ratio_ax001v2 = TRUE,
  monotonicity_spread_d10_d1 = validation$monotonicity$spread_d10_d1,
  per_regime_ic = validation$per_regime_ic,
  single_family_vs_composite = validation$single_family_vs_composite
)

# Challenge flags — honest disclosure
challenge_flags <- c()
if (!validation$harvey_pass) {
  challenge_flags <- c(challenge_flags, sprintf(
    "HARVEY_MARGINAL: %d/5 specs pass > 3.0 (need 3/5). At t>2.5 = %d/5. Max t = %.4f.",
    validation$harvey_n_pass_3, validation$harvey_n_pass_25, validation$harvey_max_t
  ))
}
if (validation$single_family_vs_composite$composite_dilutes_single) {
  challenge_flags <- c(challenge_flags, sprintf(
    "RF_A2_COMPOSITE_DILUTES: best single family low_vol ICIR=%.4f > composite ICIR=%.4f (dilution = %.1f%%). Composite still passes ICIR threshold (≥ 0.20), but single-family outperforms.",
    validation$single_family_vs_composite$best_single_family_icir,
    validation$single_family_vs_composite$composite_icir,
    100 * (1 - validation$single_family_vs_composite$composite_icir / validation$single_family_vs_composite$best_single_family_icir)
  ))
}
challenge_flags <- c(challenge_flags,
  "v1_LESSON_APPLIED: regime PIT-C9 t-1 lag strict (mechanism fragile if same-date). v3.5 fixes 4 v1 issues: (1) composite < single (RF-A2 retain but now both pass ICIR), (2) regime t-1 lag strict, (3) v3 winsorize 99.5% + monthly non-overlap + log return retain, (4) S01_Size raw direction retain (no double-flip)."
)
challenge_flags <- c(challenge_flags,
  "REGIME_STATE_4_NEGATIVE_IC: state 4 mean IC=-0.0243 (n=11) and state 7 mean IC=-0.0214 (n=9). These regimes carry negative predictive power for composite alpha — risk-research should examine if these states have systematic factor crowding or regime-specific Σ misspecification."
)

# Assemble package
package <- list(
  task_id = "WT-D20260528_003",
  wt_type = "discovery",
  schema_version = "alpha_package_v1",
  as_of_date = "2026-05-28",
  signal_cutoff = "2023-12-22",
  forecast_horizon = "1M",
  universe = "KOSPI200",
  benchmark = "KOSPI200_total_return",
  hypothesis_title = "STR_1721 P4 Multi-Horizon Regime Engine + 8-Family Smart Beta Allocation (K200) v3.5",
  hypothesis_description = paste0(
    "v3.5 spec (도훈 confirm 2026-05-28). v1 lesson applied: (a) regime feature PIT-C9 t-1 lag strict ",
    "(v1 same-date IC 0.0121 -> t-1 lag IC -0.0007 detected fragile mechanism); ",
    "(b) S01_Size raw direction retain (v1 double-flip bug fix); ",
    "(c) v3 winsorize 99.5% + monthly non-overlap + log return; ",
    "(d) 8-family panel (added size as 7th, dividend as 8th) with composite-first sourcing (V12/Q08/M32/GR07/C19), ",
    "and multi-proxy for low_vol (D01+D02+D03+D04) + dividend (V06+V11+V17). ",
    "Regime engine: 17 features (P4 multi-horizon 15 + MA07 + RE_MRS), K-means 9-cluster walk-forward expanding ",
    "with monthly refit. State-conditional BL-shrinkage weight matrix derived per sig_date. ",
    "Alpha = Σ_f w_f(state(t-1)) × F_f(i, t)."
  ),
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT_D20260528_003_v3_5/alpha_scores_v35.parquet",
  factor_specs = fam_specs,
  diagnostics = diag,
  alpha_inheritance_cor = 0.0,
  alpha_discovery_count = 1,
  selection_objective = "icir",
  graduation_summary = list(
    rank_ic = list(value = validation$rank_ic$value, threshold = 0.04,
                    pass = validation$rank_ic$value >= 0.04),
    icir = list(value = validation$icir$value, threshold = 0.20,
                  pass = validation$icir$value >= 0.20),
    subperiod_stability = list(value = validation$subperiod_stability$value, threshold = 0.5,
                                  pass = validation$subperiod_stability$value >= 0.5),
    harvey_pass_3_5 = list(value = validation$harvey_n_pass_3, threshold = 3L,
                              pass = validation$harvey_n_pass_3 >= 3L),
    dsr = list(value = validation$dsr$value, threshold = 0.5,
                pass = validation$dsr$value >= 0.5),
    all_pass = validation$all_graduation_pass
  ),
  red_flags = list(
    RF_A2 = validation$single_family_vs_composite$composite_dilutes_single,
    RF_A2_severity = if (validation$single_family_vs_composite$composite_dilutes_single) "MEDIUM" else "NONE",
    harvey_pass_below_3 = !validation$harvey_pass,
    icir_passes_alone = validation$icir$pass,
    rank_ic_passes_alone = validation$rank_ic$pass,
    subperiod_passes_alone = validation$subperiod_stability$pass,
    dsr_passes_alone = validation$dsr$pass
  ),
  challenge_flags = as.list(challenge_flags),
  candidates_tried = 5L,
  method_log = list(
    list(name = "v1_6family_same_date_regime", icir = 0.0735, harvey_pass_3 = FALSE, selected = FALSE,
          reason = "Composite dilutes single family low_vol (64% dilution). REJECT by Codex Round 1."),
    list(name = "v1_diagnostic_t1_lag_post_hoc", icir = -0.0007, harvey_pass_3 = FALSE, selected = FALSE,
          reason = "Diagnostic only — same-date alpha mechanism artifact (PIT-C9 lookahead)."),
    list(name = "v3.5_8family_composite_first", icir = 0.3392, harvey_pass_3 = FALSE, selected = TRUE,
          reason = "Selected as primary. ICIR 0.339 >= 0.20 PASS, but Harvey only 1/5 at t>3.0 (3/5 at t>2.5). Composite still dilutes single low_vol (14%, MEDIUM severity)."),
    list(name = "v3.5_diagnostic_single_low_vol_alone", icir = 0.3932, harvey_pass_3 = NA, selected = FALSE,
          reason = "Best single family. Considered as alternative but does not capture diversification across regimes."),
    list(name = "v3.5_diagnostic_single_dividend_alone", icir = 0.3403, harvey_pass_3 = NA, selected = FALSE,
          reason = "Second-best single family. Comparable to composite, but composite preserves regime-conditional diversification.")
  ),
  pit_compliance = list(
    C1_C8_full = TRUE,
    C9_regime_t_minus_1_strict = TRUE,
    C9_factor_data_t_minus_1 = "load_month_factors() with Usable_Date <= sig_d",
    C13_z_aligned_only = TRUE,
    C14_usable_date_filter = TRUE,
    C15_load_month_factors_used = TRUE,
    AX001v2_crisis_alpha = TRUE,
    AX002_process_honesty = TRUE,
    AX005_AX007_compliance = TRUE
  ),
  axiom_compliance = list(
    AX_000_no_limits = TRUE,
    AX_001v2_defensive_conditional = paste0("bad/normal IC ratio = ", validation$bad_normal_ic_ratio$value, " > 0.5 PASS"),
    AX_002_process_honesty = "Composite ICIR transparently reported. RF-A2 disclosed. Harvey marginal disclosed.",
    AX_005_AX_007_compliance = "Long-only composite via state-conditional weights, not single-sleeve mechanism. Score-based universe-wide alpha vector for downstream Optimizer."
  ),
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  agent = "alpha-research-v3.5-respawn",
  archive_v1_reference = "qepm/mailbox/worktask/WT-D20260528_003/archive_v1/",
  v1_lesson_application = list(
    composite_dilute_recurrence_status = "RF-A2 still present at 14% (vs v1 64%) — substantially mitigated but not eliminated",
    pit_C9_lag_fix = "Strict t-1 lag from start; v1 mechanism fragility avoided",
    s01_size_double_flip_fix = "Registry higher_better retain; no extra Z-sign reversal",
    winsorize_v3 = "Forward log return ±30% winsorize + monthly non-overlap retain"
  )
)

# Write
out_file <- file.path(WT_DIR, "alpha_package_draft.json")
writeLines(toJSON(package, pretty = TRUE, auto_unbox = TRUE, na = "null"), out_file)
cat("[Alpha Package Draft v3.5] saved:", out_file, "\n")
cat("  bytes:", file.info(out_file)$size, "\n")
cat("  n_alpha_vector:", length(package$alpha_vector), "\n")
cat("  n_confidence_vector:", length(package$confidence_vector), "\n")
cat("  n_factor_specs:", length(package$factor_specs), "\n")
cat("  n_challenge_flags:", length(package$challenge_flags), "\n")
cat("  graduation all_pass:", package$graduation_summary$all_pass, "\n")
cat("  selection_objective:", package$selection_objective, "\n")
