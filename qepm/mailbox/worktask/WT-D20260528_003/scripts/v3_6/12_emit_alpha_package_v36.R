#==============================================================================
# Step 7 — Emit alpha_package_draft.json + alpha_scores.parquet v3.6
#
# v3.6 PIVOT final emission:
#   - 3 fix axes diagnostics
#   - Charter §5 Data Mining 정합: 3 cycles FAIL (v1, v3.5, v3.6) → TERMINATE 권고
#   - RF-A2 FAIL 정직 보고 (rationalization 금지)
#   - alpha_vector retain (downstream Risk/Optimizer가 받을 수 있으나 graduation FAIL)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6")
WT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_6")

cat("[Emit v3.6] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load all v3.6 outputs ----
cat("[1] Loading v3.6 outputs ...\n")
alpha_rw <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_regime_weighted_neut_v36.parquet")))
icir_dt <- as.data.table(read_parquet(file.path(OUT_DIR, "family_individual_ic_v36.parquet")))
three_way <- fromJSON(file.path(OUT_DIR, "three_way_ic_comparison_v36.json"))
validation <- fromJSON(file.path(OUT_DIR, "alpha_validation_v36.json"))
regime_diag <- fromJSON(file.path(OUT_DIR, "regime_classifier_diag_v36.json"))
sector_diag <- fromJSON(file.path(OUT_DIR, "sector_neutralize_diag_v36.json"))
state_weights <- as.data.table(read_parquet(file.path(OUT_DIR, "regime_family_weights_v36.parquet")))

# ---- 2. Build alpha_vector from last sig_date ----
cat("[2] Building alpha_vector + confidence_vector ...\n")
last_d <- max(alpha_rw$Date)
last_sub <- alpha_rw[Date == last_d, .(Ticker, alpha_rw)]
setorder(last_sub, -alpha_rw)

alpha_vector <- as.list(last_sub$alpha_rw)
names(alpha_vector) <- last_sub$Ticker
alpha_vector <- lapply(alpha_vector, function(x) round(x, 4))

# Confidence vector: based on cross-sectional rank stability across recent 3 sig_dates
recent_dates <- sort(unique(alpha_rw$Date), decreasing = TRUE)[1:3]
recent_dt <- alpha_rw[Date %in% recent_dates]
# Rank per Ticker per Date
recent_dt[, rank := frank(-alpha_rw), by = Date]
# CV of ranks per ticker (low CV → high confidence)
rank_stab <- recent_dt[, .(rank_cv = sd(rank, na.rm = TRUE) / mean(rank, na.rm = TRUE)), by = Ticker]
rank_stab[is.na(rank_cv), rank_cv := 1.0]
# Map to confidence [0, 1]: lower CV → higher confidence
max_cv <- max(rank_stab$rank_cv, na.rm = TRUE)
rank_stab[, conf := 1 - (rank_cv / max_cv) * 0.7]  # range ~[0.3, 1.0]
# Final confidence = product with per-Ticker non-missing flag in 3 sig_dates
n_present <- recent_dt[, .N, by = Ticker]
rank_stab <- merge(rank_stab, n_present, by = "Ticker", all.x = TRUE)
rank_stab[, conf_final := conf * (N / 3)]
rank_stab[, conf_final := pmax(pmin(conf_final, 1.0), 0.1)]

# Map to last_sub tickers only
conf_lookup <- rank_stab[Ticker %in% last_sub$Ticker, .(Ticker, conf_final)]
conf_lookup <- merge(last_sub[, .(Ticker)], conf_lookup, by = "Ticker", all.x = TRUE)
conf_lookup[is.na(conf_final), conf_final := 0.3]  # default for new tickers
confidence_vector <- as.list(round(conf_lookup$conf_final, 3))
names(confidence_vector) <- conf_lookup$Ticker

cat("  alpha_vector N:", length(alpha_vector), " | mean:", round(mean(unlist(alpha_vector)), 3), "\n")
cat("  confidence_vector N:", length(confidence_vector),
    " | range:", round(min(unlist(confidence_vector)), 2),
    "~", round(max(unlist(confidence_vector)), 2), "\n")

# ---- 3. Save alpha_scores parquet (multi-date) ----
cat("[3] Saving alpha_scores.parquet ...\n")
alpha_scores <- alpha_rw[, .(Date, Ticker, alpha_score = alpha_rw, alpha_confidence_proxy = 0.5)]
# Add confidence per Ticker (mapped)
conf_map <- conf_lookup[, .(Ticker, conf_final)]
alpha_scores <- merge(alpha_scores, conf_map, by = "Ticker", all.x = TRUE)
alpha_scores[is.na(conf_final), conf_final := 0.3]
alpha_scores[, alpha_confidence_proxy := conf_final]
alpha_scores[, conf_final := NULL]

write_parquet(alpha_scores, file.path(STAGE_DIR, "alpha_scores.parquet"))
write_parquet(alpha_scores, file.path(OUT_DIR, "alpha_scores_v36.parquet"))

# ---- 4. Per-state weight summary ----
cat("[4] Per-state weight summary ...\n")
fam_labels <- c("value", "quality", "momentum", "growth", "consensus", "low_vol", "size", "dividend")
state_weight_summary <- state_weights[!is.na(regime_state) & weight_source == "state_specific",
  c(lapply(.SD, function(x) round(mean(x, na.rm = TRUE), 3))),
  by = regime_state, .SDcols = fam_labels]
last_sig_weights <- state_weights[ym == format(last_d, "%Y-%m"), c("regime_state", fam_labels), with = FALSE]

# ---- 5. Build factor_specs (8 family with v3.6 metrics) ----
cat("[5] Building factor_specs ...\n")
factor_specs <- list()
for (k in seq_along(fam_labels)) {
  fam <- fam_labels[k]
  raw_sig <- paste0("F_", fam)
  neut_sig <- paste0("F_", fam, "_neut")

  raw_icir <- icir_dt[signal == raw_sig, icir]
  neut_icir <- icir_dt[signal == neut_sig, icir]
  retention <- three_way$per_family_sector_retention[[fam]]$retention_pct

  ws_last <- if (nrow(last_sig_weights) > 0L) last_sig_weights[[fam]][1] else NA_real_
  ws_avg <- if (nrow(state_weight_summary) > 0L) mean(state_weight_summary[[fam]], na.rm = TRUE) else NA_real_

  rationale_map <- list(
    value = "risk_premium", quality = "behavioral", momentum = "behavioral",
    growth = "behavioral", consensus = "behavioral", low_vol = "risk_premium",
    size = "risk_premium", dividend = "risk_premium"
  )
  ref_map <- list(
    value = "Fama-French 1993; Asness-Frazzini 2013 'Devil in HML'",
    quality = "Asness-Frazzini-Pedersen 2019 QMJ; Novy-Marx 2013",
    momentum = "Asness-Moskowitz-Pedersen 2014; Jegadeesh-Titman 1993",
    growth = "Lakonishok-Shleifer-Vishny 1994",
    consensus = "Bernard-Thomas 1989 PEAD; Stickel 1991",
    low_vol = "Ang-Hodrick-Xing-Zhang 2006; Frazzini-Pedersen 2014 BAB; Baker-Bradley-Wurgler 2011",
    size = "Banz 1981; Fama-French 1992 (v3.6 retain v1 bug fix)",
    dividend = "Boudoukh-Michaely-Richardson-Roberts 2007"
  )

  proxy_map <- list(
    value = "V12_Composite_Value",
    quality = "Q08_Composite_Quality",
    momentum = "M32_Composite_Mom_v2",
    growth = "GR07_Composite_Growth",
    consensus = "C19_Composite_Earnings",
    low_vol = "D01+D02+D03+D04 multi-proxy",
    size = "S01_Size",
    dividend = "V06+V11+V17 multi-proxy"
  )

  factor_specs[[k]] <- list(
    factor_family = fam,
    proxy = proxy_map[[fam]],
    formula = paste0("Z_aligned (load_month_factors PIT-safe) → sector dummy regression residual ",
                     "(per-Date per-family) → re-standardize cross-section"),
    lag_rule = "monthly Z via load_month_factors() PIT-safe Usable_Date <= sig_date",
    winsorization = "Z_aligned 3std + forward log return ±30%",
    neutralization = "sector_residual (Asness-Frazzini 2013 standard)",
    economic_rationale = rationale_map[[fam]],
    weight_theta_avg = round(ws_avg, 4),
    weight_theta_last_sig_d = round(ws_last, 4),
    raw_icir_unneut = round(raw_icir, 4),
    sector_neut_icir = round(neut_icir, 4),
    sector_retention_pct = round(retention, 1),
    references = list(ref_map[[fam]])
  )
}

# ---- 6. Method log (v1, v3.5, v3.6 cycle) ----
method_log <- list(
  list(name = "v1_6family_same_date_regime", icir = 0.0735, harvey_pass_3 = FALSE,
       selected = FALSE,
       reason = "Composite dilutes single family (64% dilution v1). REJECT Codex Round 1."),
  list(name = "v3.5_8family_composite_first_sector_unneut", icir = 0.3392,
       harvey_pass_3 = FALSE, selected = FALSE,
       reason = "ICIR 0.339 PASS but Harvey 1/5, sector retention 48.1% FAIL, composite < single low_vol 0.339 < 0.393. REJECT Codex Round 2."),
  list(name = "v3.6_sector_neut_composite_eqw", icir = 0.18,
       harvey_pass_3 = FALSE, selected = FALSE,
       reason = "Equal-weighted 8-family sector-neut composite. ICIR drops vs raw (sector exposure removed). RF-A2 FAIL (0.180 < single low_vol_raw 0.386)."),
  list(name = "v3.6_sector_neut_composite_regime_weighted_hmm4", icir = 0.224,
       harvey_pass_3 = FALSE, selected = TRUE,
       reason = "HMM 4-state regime-weighted composite, sector-neut basis. 80% state-specific (fallback 10.8% PASS), sector retention 67.8% PASS, but RF-A2 FAIL: 0.224 < best single F_low_vol_raw 0.386 / F_low_vol_neut 0.275."),
  list(name = "v3.6_diagnostic_single_low_vol_neut", icir = 0.2749,
       harvey_pass_3 = FALSE, selected = FALSE,
       reason = "Best sector-neut single family. Considered as alternative but lacks regime adaptation + diversification across 4 HMM states."),
  list(name = "v3.6_diagnostic_single_low_vol_raw", icir = 0.3862,
       harvey_pass_3 = FALSE, selected = FALSE,
       reason = "Best raw single family. RF-A2 reveals composite cannot beat. Caveat: 28.8% sector-driven (raw 0.386 → neut 0.275)."))

# ---- 7. Challenge flags ----
challenge_flags <- c(
  "RF_A2_CONFIRMED_v3_6_FINAL: Best single F_low_vol raw ICIR=0.3862 > composite_neut_regime_weighted ICIR=0.224 (42% dilution vs raw, 19% dilution vs neut). 3-way verdict ALL FAIL (eqw_neut 0.180 / regime_w 0.224 < single low_vol_raw 0.386 / single low_vol_neut 0.275).",
  "RF_A4_FIX_v3_6_PASS: Composite sector-neut retention 67.8% (>=50% threshold). Sector residualization (Asness-Frazzini 2013) successfully fixed v3.5 48.1%. Per-family detail: low_vol 71.2%, dividend 49.6%, consensus 101.4%, size 79.7%; value 25.7%/quality 49.2% (sector-driven), momentum 258.3%/growth 335.7% (sign flip artifact under neut, small base).",
  "REGIME_FIX_v3_6_PASS: HMM 4-state (Hamilton 1989, depmixS4) replaces v3.5 K-means 9-state. Fallback 10.8% (<30% threshold). Per-state persistence 0.965-0.983 (all >=0.85). Monthly counts: S1=8/S2=9/S3=25/S4=49 (S1/S2 sparse but only required >=8 for HMM identification — depmix EM convergence achieved).",
  "v3_6_HARVEY_REGRESSION: 0/5 t>3.0 at v3.6 (was 1/5 at v3.5). All 5 specs degraded post-sector-neut: A=1.95 (was 3.17), B=1.95, C=1.23 (was 2.83), D=0.05 (was 1.61), E=0.00 (was 2.80). Removing sector exposure exposed weak underlying alpha signal.",
  "v3_6_DSR_FAIL: DSR=0.0000 at n_trials=18 (full method search universe across 18 signals). Expected_max_SR under null=1.22, observed annualized SR=0.78, DSR_z=-8.71. Below 0.5 threshold by wide margin.",
  "v3_6_RANK_IC_FAIL: 0.0201 < 0.04 threshold. v3.5 0.0425 → v3.6 0.0201 (53% decline). Sector residualization removed major IC source.",
  "v3_6_AX001v2_FAIL: bad period (3 crisis dates) mean IC = -0.1232. crisis_alpha NEGATIVE (alpha REVERSED in bad regimes). Bad/normal ratio = -4.82 (negative ratio means alpha decorrelates crisis behavior — risk model contradicts).",
  "v3_6_MONOTONICITY_FAIL: 0.072 < 0.70 threshold. Decile spread (D10-D1)=0.003 essentially zero. Sector-neut alpha has no monotone decile signal.",
  "v3_6_TURNOVER_FAIL: 5.08 annual (top decile) > 3.0 threshold. Regime-driven family weights shift drastically across HMM states.",
  "CHARTER_5_DATA_MINING_3_CYCLES_FAIL: v1 FAIL + v3.5 FAIL + v3.6 FAIL = 3 cycles. Charter §5 Data Mining 방지 정합 — STR_1721 8-family composite regime engine paradigm 본질 의문. terminate 권고 발동.",
  "TERMINATE_RECOMMENDATION_RATIONALE: (1) sector exposure 제거 후 composite < single (RF-A2 ACCEPT, fix 불가); (2) Harvey 5-spec post-neut 광범위 붕괴 (0/5 strict, 0/5 medium); (3) AX-001 v2 crisis_alpha NEGATIVE (방어형 실패); (4) Rank IC 0.020 marginal. 3 fix axes 중 2건 PASS (sector retention + fallback) but graduation gate 5+ FAIL.",
  "ALTERNATIVE_SALVAGE_PATH_IF_NOT_TERMINATE: Single F_low_vol_neut deployment WT (sector-neut single-family low_vol, ICIR 0.275, retention 71.2%). 그러나 single sleeve top20 long-only = AX-007 violation (Single Sleeve 메커니즘 단절). EXCLUSION 4가지 (multi-sleeve / long-short / 50+ / ML sizing) 적용해야 가능.",
  "ALTERNATIVE_HYPOTHESIS_REDIRECT: STR_1721 family 폐기 후 다른 가설 — (a) ML-based factor selection (XGBoost/LightGBM weighted multi-family), (b) long-short F_low_vol_neut vs F_quality_neut, (c) cross-sectional residualization (industry + size + BM)."
)

# ---- 8. Build full alpha_package_draft.json ----
cat("[8] Building alpha_package_draft.json ...\n")
package <- list(
  task_id = "WT-D20260528_003",
  wt_type = "discovery",
  schema_version = "alpha_package_v1",
  as_of_date = "2026-05-28",
  signal_cutoff = "2023-12-22",
  forecast_horizon = "1M",
  universe = "KOSPI200",
  benchmark = "KOSPI200_total_return",
  hypothesis_title = "STR_1721 P4 Multi-Horizon Regime Engine + 8-Family Smart Beta Allocation (K200) v3.6 PIVOT",
  hypothesis_description = paste0(
    "v3.6 PIVOT spec (Q-Lead Option 1 mandate 2026-05-28). v3.5 → v3.6 fixes: ",
    "(1) Sector neutralization (Asness-Frazzini 2013 sector dummy regression residual, per-Date per-family); ",
    "(2) HMM 4-state via depmixS4 (Hamilton 1989) replacing K-means 9-state, walk-forward expanding fit; ",
    "(3) 3-way single vs composite vs regime-weighted composite RF-A2 verdict. ",
    "Result: 2 of 3 fix axes PASS (sector retention 48.1%->67.8%; fallback 54.2%->10.8%); ",
    "RF-A2 STILL FAIL (composite cannot beat best single low_vol). ",
    "Additional regression: Harvey 1/5->0/5 strict, ICIR 0.339->0.224, Rank IC 0.043->0.020, DSR 1.0->0.0, ",
    "AX-001 v2 crisis_alpha NEGATIVE. ",
    "Verdict: 3 cycles FAIL (v1+v3.5+v3.6) - Charter §5 Data Mining 방지 정합 TERMINATE 권고."
  ),
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260528_003_v3_6/alpha_scores.parquet",
  factor_specs = factor_specs,
  diagnostics = list(
    rank_ic = validation$rank_ic,
    icir = validation$icir,
    monotonicity = validation$monotonicity_correlation,
    subperiod_stability = validation$subperiod_stability_frac,
    turnover_proxy = validation$annual_top_decile_turnover,
    harvey_t_stat = validation$harvey_5_spec$A_raw_ic$t_nw_lag6,
    harvey_t_specs_pass_count = validation$harvey_n_pass_3,
    harvey_t_specs_pass_count_at_25 = validation$harvey_n_pass_25,
    harvey_5_spec_detail = validation$harvey_5_spec,
    deflated_sharpe_ratio = validation$dsr,
    post_neutralization_ic = validation$rank_ic,
    bad_normal_ic_ratio = validation$bad_normal_ic_ratio,
    bad_normal_ic_ratio_ax001v2 = validation$ax001_v2_pass,
    monotonicity_spread_d10_d1 = validation$decile_spread_d10_d1,
    three_way_verdict = list(
      best_single = three_way$best_single,
      equal_w_composite_raw = three_way$equal_w_composite_raw,
      equal_w_composite_neut = three_way$equal_w_composite_neut,
      regime_w_composite_neut = three_way$regime_w_composite_neut,
      rf_a2_overall_pass = three_way$rf_a2_overall_pass
    ),
    sector_neut_retention = list(
      composite_retention_pct = three_way$rf_a4_composite_retention_pct,
      rf_a4_pass = three_way$rf_a4_pass,
      per_family = three_way$per_family_sector_retention
    ),
    regime_diag = list(
      method = regime_diag$method,
      n_regimes = regime_diag$n_regimes,
      per_state_monthly_n = regime_diag$per_state_monthly_n,
      state_frequency = regime_diag$state_frequency,
      state_persistence = regime_diag$state_persistence,
      fallback_pct = three_way$fallback_pct,
      state_specific_pct = three_way$state_specific_pct,
      fallback_target_lt_30 = three_way$fallback_target_lt_30
    )
  ),
  selection_objective = "icir",
  alpha_discovery_count = 0,
  alpha_inheritance_cor = 0,
  graduation_summary = list(
    rank_ic = list(value = validation$rank_ic, threshold = 0.04, pass = validation$rank_ic >= 0.04),
    icir = list(value = validation$icir, threshold = 0.20, pass = validation$icir >= 0.20),
    subperiod_stability = list(value = validation$subperiod_stability_frac, threshold = 0.5,
                                pass = validation$subperiod_stability_frac >= 0.5),
    harvey_pass_3_5 = list(value = validation$harvey_n_pass_3, threshold = 3,
                            pass = validation$harvey_n_pass_3 >= 3),
    dsr = list(value = validation$dsr, threshold = 0.5, pass = validation$dsr >= 0.5),
    monotonicity = list(value = validation$monotonicity_correlation, threshold = 0.7,
                         pass = validation$monotonicity_correlation >= 0.7),
    bad_normal_ic_ratio = list(value = validation$bad_normal_ic_ratio, threshold = 0.5,
                                pass = validation$ax001_v2_pass),
    all_pass = FALSE
  ),
  red_flags = list(
    RF_A2 = TRUE,
    RF_A2_severity = "HIGH",
    RF_A4 = FALSE,
    RF_A4_fix_applied = TRUE,
    RF_A4_retention_pct = three_way$rf_a4_composite_retention_pct,
    harvey_pass_below_3 = TRUE,
    icir_passes_alone = TRUE,
    rank_ic_passes_alone = FALSE,
    subperiod_passes_alone = TRUE,
    dsr_fails_alone = TRUE,
    monotonicity_fails_alone = TRUE,
    crisis_alpha_negative = TRUE
  ),
  challenge_flags = challenge_flags,
  candidates_tried = 6,
  method_log = method_log,
  pit_compliance = list(
    C1_C8_full = TRUE,
    C9_regime_t_minus_1_strict = TRUE,
    C9_factor_data_t_minus_1 = "load_month_factors() with Usable_Date <= sig_d",
    C13_z_aligned_only = TRUE,
    C14_usable_date_filter = TRUE,
    C15_load_month_factors_used_for_factor_panel = TRUE,
    C15_macro_partial = paste0("MA07/RE_MRS read directly (macro composite Raw_Value, ",
                                "Ticker-aggregate single value per Date — load_month_factors() ",
                                "designed for cross-section Z assignment doesn't apply). ",
                                "Expanding-window z computed PIT-safe (past data only). Codex C6 MEDIUM PARTIAL acknowledged."),
    AX001v2_crisis_alpha = FALSE,
    AX001v2_crisis_alpha_detail = "bad period mean IC = -0.1232 (3 crisis dates), normal mean IC = 0.0256. v3.6 alpha REVERSES in crisis — risk-research must flag.",
    AX002_process_honesty = TRUE,
    AX005_AX007_compliance = "Score-based universe alpha vector; downstream Optimizer responsibility."
  ),
  axiom_compliance = list(
    AX_000_no_limits = TRUE,
    AX_001v2_defensive_conditional = paste0("FAIL: bad/normal IC ratio = -4.82 (negative). Crisis alpha REVERSED. AX-001 v2 condition not satisfied."),
    AX_002_process_honesty = paste0("Honest reporting of 3-cycle FAIL (v1+v3.5+v3.6). RF-A2 rationalization avoided. ",
                                     "Composite cannot beat single F_low_vol explicitly stated."),
    AX_005_AX_007_compliance = paste0("Long-only universe-wide alpha vector for downstream Optimizer. ",
                                       "AX-007 single sleeve top20 mechanism intentionally not invoked (alt salvage path noted in challenge flags).")
  ),
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  agent = "alpha-research-v3.6-pivot",
  archive_v1_reference = "qepm/mailbox/worktask/WT-D20260528_003/archive_v1/",
  archive_v3_5_reference = "qepm/mailbox/worktask/WT-D20260528_003/archive_v3_5/",
  v3_5_v3_6_fix_effectiveness = list(
    fix_1_sector_neutralization = list(
      target = "RF-A4 sector retention >= 50%",
      v3_5_baseline = 48.1,
      v3_6_result = three_way$rf_a4_composite_retention_pct,
      verdict = if (three_way$rf_a4_pass) "PASS" else "FAIL",
      method = "Asness-Frazzini 2013 sector dummy regression residual (per-Date per-family) + cross-section re-standardize"
    ),
    fix_2_regime_state_reduction = list(
      target = "Fallback < 30%, persistence >= 0.85",
      v3_5_baseline = list(fallback = 54.2, n_states = 9),
      v3_6_result = list(fallback = three_way$fallback_pct, n_states = 4,
                          persistence_range = "0.965-0.983"),
      verdict = if (three_way$fallback_target_lt_30) "PASS" else "FAIL",
      method = "Hamilton 1989 HMM via depmixS4 (PCA 6-d Gaussian, walk-forward expanding fit, refit 63d)",
      per_state_monthly_caveat = "S1=8 / S2=9 (target was n >= 30). Markov chain persistence high mitigates sparse-state risk."
    ),
    fix_3_single_vs_composite_3way = list(
      target = "RF-A2 composite >= best single",
      v3_5_baseline = list(best_single_icir = 0.3932, composite_icir = 0.3392, dilution_pct = 13.7),
      v3_6_result = list(
        best_single_raw = three_way$best_single$icir,
        composite_eqw_neut = three_way$equal_w_composite_neut$icir,
        composite_regime_w_neut = three_way$regime_w_composite_neut$icir
      ),
      verdict = if (three_way$rf_a2_overall_pass) "PASS" else "FAIL",
      interpretation = paste0("Sector neutralization revealed underlying alpha is weak: ",
                               "best single F_low_vol raw ICIR=0.386 (28.8% sector-driven, raw->neut 0.386->0.275); ",
                               "composite_regime_w_neut ICIR=0.224. ",
                               "Composite paradigm cannot beat best single, even on sector-controlled basis.")
    )
  ),
  final_graduation_status = list(
    status = "FAIL",
    pass_count = "2 of 9 metrics (ICIR 0.224 PASS, Subperiod stability 1.00 PASS)",
    fail_count = "7 of 9 metrics (Rank IC, Harvey, DSR, Monotonicity, AX-001 v2, Turnover, RF-A2)",
    reasoning = paste0("v3.6 PIVOT 3 fix axes: 2/3 PASS (sector retention + fallback) but ",
                        "RF-A2 STILL FAIL (composite cannot beat single low_vol_raw 0.386 nor low_vol_neut 0.275). ",
                        "Sector neutralization removed major IC source (v3.5 ICIR 0.339 -> v3.6 0.224, 34% decline), ",
                        "Harvey strict 1/5 -> 0/5 (full collapse), DSR 1.0 -> 0.0, ",
                        "AX-001 v2 crisis_alpha REVERSED (negative bad-period IC). ",
                        "Composite paradigm 본질 의문 — single F_low_vol dominates."),
    q_lead_recommendation_primary = "TERMINATE STR_1721 family (Charter §5 Data Mining 방지 정합: 3 cycles FAIL = v1 + v3.5 + v3.6).",
    q_lead_recommendation_secondary = paste0("If salvage attempted, redirect to: ",
      "(a) Long-short F_low_vol_neut vs F_quality_neut (ICIR 0.275 - (-0.065) = 0.340 spread, AX-007 long-short exception applies); ",
      "(b) ML-based dynamic factor selection (XGBoost/LightGBM weighted multi-family, ",
      "AX-007 ML sizing exception applies); ",
      "(c) Pure sector-neut single-family deployment with 50+ holdings (AX-007 diversification exception)."),
    alternative_terminate_path = "STR_1721 family terminated after 3 cycles; alternative hypothesis (long-short / ML / 50+ diversified) for new WT."
  ),
  codex_round = list(
    performed = "pending_post_emit",
    expected_action = "Codex Critic Round 5 stage flow auto-spawn on alpha_package_draft.json save"
  ),
  status = "GRADUATION_FAIL_PENDING_Q_LEAD_TERMINATE_DECISION"
)

# Write draft (PostToolUse Hook will auto-trigger Codex)
draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
writeLines(toJSON(package, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            draft_path)
cat("  Written:", draft_path, "\n")

# ---- 9. Lineage record (after draft write) ----
cat("[9] Recording artifact lineage ...\n")
tryCatch({
  source(file.path(BASE, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = "WT-D20260528_003",
    package_type = "alpha_package",
    method_selected = "v3.6_sector_neut_composite_regime_weighted_hmm4",
    input_file_paths = c(
      file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6/alpha_regime_weighted_neut_v36.parquet"),
      file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6/regime_labels_monthly_v36.parquet"),
      file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6/k200_factor_panel_sector_neut_v36.parquet"),
      file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6/alpha_validation_v36.json")
    )
  )
  cat("  Lineage recorded.\n")
}, error = function(e) {
  cat("  Lineage record error (non-fatal):", conditionMessage(e), "\n")
})

cat("\n[Emit v3.6] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
cat("Draft package:", draft_path, "\n")
cat("Alpha scores:", file.path(STAGE_DIR, "alpha_scores.parquet"), "\n")
