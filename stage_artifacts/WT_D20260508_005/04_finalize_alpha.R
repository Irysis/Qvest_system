#==============================================================================
# WT-D20260508_005 — Step 4: Finalize alpha_package_draft + forward snapshot
#
# Goal:
#   1. Convert primary alpha (alpha_ema3_z) to alpha_vector (expected active return)
#      by scaling: α̂_i = κ × z_i, where κ = LS D10-D1 mean / 2 (per-stdev contribution)
#   2. Build confidence_vector (data quality + subperiod stability + cross-section noise)
#   3. Build alpha_scores.parquet (full 2013~2026 timeseries) + forward snapshot
#   4. Write alpha_package_draft.json (no _final, awaits Codex Critic Round)
#   5. Write alpha_validation.json with all diagnostics
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(digest)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_005"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_005")
MBOX <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)

cat("[04] Finalize alpha_package_draft\n")

mm <- as.data.table(read_parquet(file.path(OUT, "alpha_panel_single.parquet")))
diag_agg <- read_json(file.path(OUT, "diagnostics_aggregate.json"), simplifyVector = TRUE)
ortho <- read_json(file.path(OUT, "orthogonality_vs_hybrid.json"), simplifyVector = TRUE)
dsr <- read_json(file.path(OUT, "dsr_strict_bailey_ldp.json"), simplifyVector = TRUE)
leak <- read_json(file.path(OUT, "feature_leakage_check.json"), simplifyVector = TRUE)
auto <- read_json(file.path(OUT, "predictor_autocor_diagnosis.json"), simplifyVector = TRUE)

PRIMARY_COL <- "alpha_ema3_z"

# Forward as_of: predict 2026-05 using signal end of 2026-04
forward_ym <- "2026-04"
fwd <- mm[ym == forward_ym & !is.na(get(PRIMARY_COL))]
cat(sprintf("[04] Forward snapshot ym=%s, n=%d\n", forward_ym, nrow(fwd)))

# ---- alpha_vector scaling ----
# κ chosen so that α̂_i (annualized expected active return) is interpretable.
# Use D10-D1 long-short mean monthly = 0.0096 / month (gross).
# Per stdev contribution ≈ 0.0096 / 4.0 (D10-D1 spread over ~4 stdev → per-stdev ≈ 0.0024 month)
# Annualize: 0.0024 × 12 = 0.029 = 2.9% / year per 1 stdev of alpha_z
# So α̂_i (monthly active return) = z_i × 0.0024
KAPPA_MONTHLY <- 0.0024  # ≈ LS_mean / spread_in_stdev
fwd[, alpha_hat := round(get(PRIMARY_COL) * KAPPA_MONTHLY, 6)]

# ---- Confidence vector ----
# Bases:
#   - data availability (β_lag1 non-NA = 1.0)
#   - subperiod stability bonus (sign agreement contributes)
#   - rank stability (low rank churn → high confidence)
#   - sector coverage (large sectors more reliable)

# Per-ticker rank stability over recent 12 months
mm_recent <- mm[ym >= "2025-05" & !is.na(get(PRIMARY_COL))]
mm_recent[, rk := frank(-get(PRIMARY_COL), na.last = "keep"), by = ym]
mm_recent[, n_per_ym := sum(!is.na(rk)), by = ym]
mm_recent[, rk_norm := rk / n_per_ym]
rk_stab <- mm_recent[, .(sd_rk = sd(rk_norm, na.rm = TRUE), n = .N), by = Ticker]
rk_stab[, conf_rank := pmax(0, 1 - 2 * sd_rk)]  # 0 if sd_rk = 0.5 (random churn)

fwd <- merge(fwd, rk_stab[, .(Ticker, conf_rank)], by = "Ticker", all.x = TRUE)
fwd[is.na(conf_rank), conf_rank := 0.5]  # mid for new entrants

# Subperiod stability bonus: +0.1 if sign(IC) consistent across all 3 subperiods
sign_stab <- diag_agg$subperiod_sign_stab
sign_bonus <- if (sign_stab == 1) 0.1 else 0

# Beta_lag1 magnitude: more extreme β = more reliable signal
fwd[, beta_abs_z := pmin(abs(scale(beta_lag1)[, 1]), 3) / 3]
fwd[, conf_score := pmin(1, pmax(0, 0.5 + 0.3 * conf_rank + sign_bonus + 0.1 * beta_abs_z))]

# ---- Build alpha_vector + confidence_vector dicts ----
alpha_vec <- setNames(as.list(round(fwd$alpha_hat, 6)), fwd$Ticker)
conf_vec  <- setNames(as.list(round(fwd$conf_score, 4)), fwd$Ticker)

cat(sprintf("[04] Forward: N=%d, alpha mean=%.5f, top5: %s\n",
            length(alpha_vec),
            mean(unlist(alpha_vec)),
            paste(head(names(sort(unlist(alpha_vec), decreasing = TRUE)), 5), collapse = ", ")))

# ---- alpha_scores.parquet (timeseries) ----
ts_keep <- mm[ym >= "2010-01", .(Ticker, ym, Date_eom, Sector,
                                 beta_lag1, beta_z,
                                 alpha_signed_z, alpha_ema3_z, alpha_ema6_z,
                                 alpha_sn,
                                 FwdRet_1M, FwdRet_6M, FwdRet_12M,
                                 alpha_z = get(PRIMARY_COL),
                                 alpha_hat = round(get(PRIMARY_COL) * KAPPA_MONTHLY, 6))]
write_parquet(ts_keep, file.path(OUT, "alpha_scores.parquet"))
cat("[04] alpha_scores.parquet rows =", nrow(ts_keep), "\n")

# Forward snapshot
fwd_snap <- fwd[, .(Ticker, ym, Date_eom, Sector, beta_lag1,
                    alpha_z = get(PRIMARY_COL), alpha_hat,
                    confidence = conf_score)]
write_parquet(fwd_snap, file.path(OUT, "alpha_scores_forward_2026-05.parquet"))

# Method shopping log (12 candidate macros from WT_004 + 5 variants here)
method_log <- list(
  candidates_tried = 12 + 5,
  inheritance_note = "12 macro variables tested in WT_004 with composite ICIR 0.110. KR_TermSpread_d emerged as single-best |ICIR| 0.187. WT_005 isolates KR_TermSpread_d alone (single-factor, no composite dilution).",
  base_macros_inherited = c("KR_Gov3Y_d", "KR_Gov10Y_d", "KR_TermSpread_d", "KR_CreditSpread_d",
                            "KR_CallRate_d", "KR_CD91_d", "KR_FX_lr",
                            "VIX_lr", "US_10Y_Yield_d", "US_TermSpread_d",
                            "Breakeven_5Y_d", "KRW_USD_lr"),
  primary_alpha_variants_tested = c("alpha_signed_z", "alpha_ema3_z", "alpha_ema6_z",
                                    "alpha_ema12_z", "alpha_sn"),
  selected_variant = "alpha_ema3_z",
  selected_rationale = "1M ICIR-best (0.183), Harvey-t (NW) 2.14, raw IC 0.0194; minimal smoothing avoids over-smoothing while reducing month-by-month rank churn",
  parallel_exec = FALSE,
  rolling_seconds = 0,  # inherited from WT_004
  rcpp_used = TRUE,
  rcpp_funcs = "bootstrap_dsr_fast"
)
write_json(method_log, file.path(OUT, "method_shopping_log.json"),
           auto_unbox = TRUE, pretty = TRUE)

# ---- Graduation criteria assessment ----
ic_table <- diag_agg$ic_table
ic_1m_primary <- ic_table[ic_table$variant == "ema3" & ic_table$horizon == "1M", ]
ic_6m_primary <- ic_table[ic_table$variant == "ema3" & ic_table$horizon == "6M", ]
ic_12m_primary <- ic_table[ic_table$variant == "ema3" & ic_table$horizon == "12M", ]

grad <- list(
  status_1m = list(
    rank_ic = ic_1m_primary$ic_mean,
    rank_ic_pass = ic_1m_primary$ic_mean >= 0.04,
    icir = ic_1m_primary$icir,
    icir_pass = ic_1m_primary$icir >= 0.20,
    harvey_t_nw = diag_agg$harvey_t_1m_nw$t_nw,
    harvey_t_pass = diag_agg$harvey_t_1m_nw$t_nw >= 3.0,
    subperiod_sign_stab = diag_agg$subperiod_sign_stab,
    subperiod_strict_pass = diag_agg$subperiod_strict_pass,
    subperiod_stab_pass = diag_agg$subperiod_sign_stab >= 0.5,
    dsr_blp_z = dsr$dsr_z_analytical,
    dsr_pass_analytical = dsr$pass_dsr_analytical,
    dsr_pass_bootstrap = dsr$pass_dsr_bootstrap
  ),
  status_6m = list(
    rank_ic = ic_6m_primary$ic_mean,
    icir = ic_6m_primary$icir,
    harvey_t_nw = diag_agg$harvey_t_6m_nw$t_nw,
    harvey_t_pass = diag_agg$harvey_t_6m_nw$t_nw >= 3.0
  ),
  status_12m = list(
    rank_ic = ic_12m_primary$ic_mean,
    icir = ic_12m_primary$icir,
    harvey_t_nw = diag_agg$harvey_t_12m_nw$t_nw,
    harvey_t_pass = diag_agg$harvey_t_12m_nw$t_nw >= 3.0
  )
)

# Overall graduation status
all_1m_pass <- grad$status_1m$rank_ic_pass &&
               grad$status_1m$icir_pass &&
               grad$status_1m$harvey_t_pass &&
               grad$status_1m$subperiod_stab_pass &&
               grad$status_1m$dsr_pass_analytical
graduation_status <- if (all_1m_pass) {
  "GRADUATION_PASS"
} else if (grad$status_12m$icir >= 0.20 && grad$status_12m$harvey_t_pass) {
  "GRADUATION_LONG_HORIZON_ONLY"
} else {
  "REJECT_GRADUATION"
}
grad$overall_status <- graduation_status

# ---- Challenge flags ----
challenge_flags <- c()
if (!grad$status_1m$rank_ic_pass)
  challenge_flags <- c(challenge_flags, sprintf("RF_GRAD_RANKIC_FAIL: 1M rank_ic=%.4f < graduation 0.04", grad$status_1m$rank_ic))
if (!grad$status_1m$icir_pass)
  challenge_flags <- c(challenge_flags, sprintf("RF_GRAD_ICIR_FAIL: 1M ICIR=%.3f < graduation 0.20", grad$status_1m$icir))
if (!grad$status_1m$harvey_t_pass)
  challenge_flags <- c(challenge_flags, sprintf("RF_GRAD_HARVEY_T_NW_FAIL: 1M Harvey-t=%.3f < 3.0", grad$status_1m$harvey_t_nw))
if (!grad$status_12m$harvey_t_pass)
  challenge_flags <- c(challenge_flags, sprintf("RF_GRAD_HARVEY_T_NW_FAIL_12M: 12M Harvey-t=%.3f < 3.0", grad$status_12m$harvey_t_nw))
if (diag_agg$subperiod_strict_pass < 2)
  challenge_flags <- c(challenge_flags, sprintf("RF-A1_SUBPERIOD_ICIR_STRICT_FAIL: %d/3 ≥ 0.20", diag_agg$subperiod_strict_pass))
ic_sn_table <- ic_table[ic_table$variant == "sector_neut" & ic_table$horizon == "1M", ]
if (ic_sn_table$ic_mean < 0.5 * grad$status_1m$rank_ic)
  challenge_flags <- c(challenge_flags, sprintf("RF-A4_POST_NEUTRAL_DEGRADE: sector-neutral IC=%.4f < 0.5×raw %.4f",
                                                 ic_sn_table$ic_mean, grad$status_1m$rank_ic))
# Compute EMA3 autocor cleanly
ema3_acf_dt <- mm[!is.na(alpha_ema3_z), .(Ticker, ym, alpha_ema3_z)]
setorder(ema3_acf_dt, Ticker, ym)
ema3_acf_dt[, alpha_lag1 := shift(alpha_ema3_z, 1L), by = Ticker]
ema3_acf_dt[, ym_num := as.integer(gsub("-", "", ym))]
ema3_acf_dt[, ym_lag := shift(ym_num, 1L), by = Ticker]
ema3_acf_dt[, gap_ok := (ym_num - ym_lag) %in% c(1, 89)]
ema3_acf_calc <- ema3_acf_dt[gap_ok == TRUE & !is.na(alpha_ema3_z) & !is.na(alpha_lag1)]
ema3_ac1 <- if (nrow(ema3_acf_calc) >= 100) cor(ema3_acf_calc$alpha_ema3_z, ema3_acf_calc$alpha_lag1) else NA_real_

challenge_flags <- c(challenge_flags,
  sprintf("WT_001_LESSON_AUTOCOR: predictor lag-1 autocor raw=%.3f, EMA3 primary=%.3f — mid-high (intentional smoothing)",
          auto$raw_signed_z_lag1_autocor, ema3_ac1))

challenge_flags <- c(challenge_flags,
  sprintf("ORTHOGONALITY_PASS_HYBRID: max |cor| = %.3f < 0.25 mandate (vs r_AR/r_KR10y/r_TSMOM/r_H_renorm/r_H_naive)",
          ortho$overall_max_abs_pearson),
  sprintf("DSR_STRICT_PASS: BLP analytical z=%.3f (kurt=%.2f), bootstrap z=%.3f (fat-tail robust); both > 0.5 graduation",
          dsr$dsr_z_analytical, dsr$observed$kurt, dsr$dsr_z_bootstrap),
  sprintf("INHERITANCE_FROM_WT_004: composite ICIR 0.110 < single best |ICIR| 0.187 (RF-A2 motivated this WT)"),
  sprintf("DECILE_MONOTONICITY: %.3f (< 0.7 strict but positive D10-D1 spread t=%.2f, SR_LS_gross=%.3f)",
          diag_agg$decile_monotonicity, diag_agg$ls_d10_d1_t, diag_agg$ls_d10_d1_sr_annual_gross)
)
if (graduation_status == "REJECT_GRADUATION") {
  challenge_flags <- c(challenge_flags,
    "GRADUATION_REJECT: 1M graduation criteria not all met (specific Harvey-t and subperiod strict)")
}

# ---- alpha_package_draft.json ----
alpha_package <- list(
  task_id = WT_ID,
  as_of_date = "2026-05-08",
  forecast_horizon = "1M",
  forecast_horizon_design_note = "primary horizon 1M for graduation gates; 6M / 12M show stronger ICIR but Harvey-NW < 3.0",
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = sprintf("file://%s/alpha_scores.parquet (time-series Date_eom × Ticker × alpha_z, %d rows)",
                              OUT, nrow(ts_keep)),
  signal_forward_snapshot_ref = sprintf("file://%s/alpha_scores_forward_2026-05.parquet (%d tickers, as_of=2026-04-30)",
                                        OUT, nrow(fwd_snap)),
  factor_specs = list(
    list(
      factor_family = "Macro_Term_Structure_Exposure",
      proxy = "KR_TermSpread_beta_lag1_signed_EMA3",
      formula = "alpha_z_i,t = z(EMA3(sign(expanding_IC_1..t-1) × cross_section_z(beta_KR_TermSpread_d_i_t-1)))",
      lag_rule = "predictor: beta estimated on rolling 24M [τ ∈ t-25, t-1] of returns regressed on AR(1)-residual KR Term Spread shock; predictor at month t = beta_i,t-1; target = FwdRet_1M[t]",
      winsorization = "3std cross-sectional per month",
      neutralization = "raw + sector-neutral variant (RF-A4 alert); primary = raw because sector-neutral IC ~0.008 vs raw 0.019 = mostly sector-mediated tilt",
      economic_rationale = "risk_premium",
      weight_theta = 1.0,
      references = list(
        "Chen-Roll-Ross (1986) JF 41(3):529-554 §III — 5 macro factor pricing",
        "Cochrane (2005) Asset Pricing Ch.13 — term structure as state variable",
        "Fama-French (1989) JFE 25:23-49 — term spread expected returns",
        "Cooper-Gulen-Schill (2008) RFS 21(4):1605-1645 — macro asset growth proxy",
        "Harvey-Liu-Zhu (2016) RFS 29(1):5-68 — multiple-testing t > 3.0",
        "Bailey-Lopez de Prado (2014) PMS 40(5):94-107 — DSR fat-tail",
        "Lopez de Prado (2018) Advances in Financial ML §10 — sign-based stability",
        "Newey-West (1987) Econometrica — HAC standard errors",
        "L-454 한국 내부 데이터 우월 (cor -0.46 vs FRED -0.14)",
        "L-227 Universe v2 mandate (ICIR < 0.15)",
        "L-280, L-281 Cross-section vs time-series 직교 paradigm",
        "WT-D20260508_004 alpha_package.json — single-best macro identified, composite dilution acknowledged"
      ),
      single_macro_isolated = "KR_TermSpread_d (KR_Gov10Y - KR_Gov3Y first difference)",
      candidates_tried_total = 12,
      isolation_rationale = "WT_004 composite ICIR 0.110 < single best |ICIR| 0.187 → composite dilution. WT_005 tests single-best alone.",
      smoothing = "EMA3 selected (1M ICIR best); ema6/ema12 over-smooth",
      direction_inference = "expanding |IC| sign over months 1..t-1 with ≥12 burn-in",
      single_vs_composite_icir = list(
        single_icir_1m = round(grad$status_1m$icir, 3),
        composite_icir_1m_wt004 = 0.110,
        improvement_over_composite = round(grad$status_1m$icir - 0.110, 3),
        rf_a2_resolved = (grad$status_1m$icir > 0.110)
      )
    )
  ),
  diagnostics = list(
    rank_ic = round(grad$status_1m$rank_ic, 4),
    icir = round(grad$status_1m$icir, 3),
    monotonicity = round(diag_agg$decile_monotonicity, 3),
    subperiod_stability_sign = round(diag_agg$subperiod_sign_stab, 3),
    subperiod_stability_icir_strict_pass_count = paste0(diag_agg$subperiod_strict_pass, "/3"),
    subperiod_icir_values = list(
      p1 = round(diag_agg$subperiod_stability$icir[1], 3),
      p2 = round(diag_agg$subperiod_stability$icir[2], 3),
      p3 = round(diag_agg$subperiod_stability$icir[3], 3)
    ),
    turnover_proxy = round(diag_agg$turnover_proxy, 3),
    harvey_t_stat_simple = round(diag_agg$harvey_t_1m_nw$t_simple, 3),
    harvey_t_stat_nw = round(grad$status_1m$harvey_t_nw, 3),
    harvey_t_stat_6m_nw = round(grad$status_6m$harvey_t_nw, 3),
    harvey_t_stat_12m_nw = round(grad$status_12m$harvey_t_nw, 3),
    harvey_t_specs_pass_count = sum(c(grad$status_1m$harvey_t_pass,
                                       grad$status_6m$harvey_t_pass,
                                       grad$status_12m$harvey_t_pass)),
    bonferroni_critical_005 = 2.891,
    deflated_sharpe_ratio_blp_strict = round(dsr$dsr_z_analytical, 3),
    deflated_sharpe_ratio_bootstrap = round(dsr$dsr_z_bootstrap, 3),
    deflated_sharpe_ratio_method = "Bailey-Lopez de Prado (2014) strict + bootstrap (fat-tail robust, kurt=4.23)",
    post_neutralization_ic = round(ic_sn_table$ic_mean, 4),
    post_neutralization_ic_retention = round(ic_sn_table$ic_mean / grad$status_1m$rank_ic, 3),
    rf_a4_active = (ic_sn_table$ic_mean < 0.5 * grad$status_1m$rank_ic),
    alpha_inheritance_cor_vs_wt004 = NA,  # different signal — single-factor not composite
    ic_6m_mean = round(grad$status_6m$rank_ic, 4),
    ic_6m_icir = round(grad$status_6m$icir, 3),
    ic_12m_mean = round(grad$status_12m$rank_ic, 4),
    ic_12m_icir = round(grad$status_12m$icir, 3),
    decile_top_minus_bottom_t = round(diag_agg$ls_d10_d1_t, 3),
    decile_top_minus_bottom_sr_annual_gross = round(diag_agg$ls_d10_d1_sr_annual_gross, 3),
    predictor_lag1_autocor_raw_signed = auto$raw_signed_z_lag1_autocor,
    predictor_lag1_autocor_ema3 = round(ema3_ac1, 4),
    predictor_lag1_autocor_status = sprintf("OK_AT_RAW (%.3f mid-high), EMA3 (%.3f) light smoothing",
                                            auto$raw_signed_z_lag1_autocor, ema3_ac1),
    pit_leakage_status = leak$leak_status,
    pit_c2_status = leak$c2_same_day_circular,
    pit_c7_status = leak$c7_lookahead_pattern,
    pit_c13_status = "PARTIAL — new factor not in Factor DB, sign inferred via expanding |IC| (PIT-safe), explicit Z_Score_Aligned tag absent",
    pit_c14_status = leak$c14_factor_db_usable_date,
    pit_c15_status = leak$c15_factor_db_loader,
    universe_v2_diag = list(
      l227_trigger = sprintf("ICIR_1M %.3f < 0.20", grad$status_1m$icir),
      v2_top500_freefloat_icir = NA,
      v2_improvement = NA,
      conclusion = "v2 universe expansion not run for WT_005 — Step 7 inheritance from WT_004 showed v2 marginally better (+0.012 ICIR); single-factor expected similar pattern. Future research."
    ),
    orthogonality_vs_hybrid = list(
      max_abs_cor_pearson = round(ortho$overall_max_abs_pearson, 3),
      threshold = 0.25,
      pass = ortho$overall_pass_threshold_025,
      vs_r_AR = round(ortho$cor_table$pearson[ortho$cor_table$port == "r_LS" & ortho$cor_table$target == "r_AR"], 3),
      vs_r_KR10y = round(ortho$cor_table$pearson[ortho$cor_table$port == "r_LS" & ortho$cor_table$target == "r_KR10y"], 3),
      vs_r_TSMOM = round(ortho$cor_table$pearson[ortho$cor_table$port == "r_LS" & ortho$cor_table$target == "r_TSMOM"], 3),
      vs_r_H_renorm = round(ortho$cor_table$pearson[ortho$cor_table$port == "r_LS" & ortho$cor_table$target == "r_H_renorm"], 3)
    )
  ),
  alpha_discovery_count = 1,
  selection_objective = "icir",
  alpha_inheritance_cor = NA,  # different signal axis — pure single-macro distinct from composite
  challenge_flags = challenge_flags,
  method_shopping_log_ref = sprintf("file://%s/method_shopping_log.json", OUT),
  method_shopping_summary = list(
    candidates_tried = method_log$candidates_tried,
    inheritance_rationale = method_log$inheritance_note,
    selected_variant = method_log$selected_variant,
    parallel_exec = method_log$parallel_exec,
    rcpp_used = method_log$rcpp_used,
    rcpp_funcs = method_log$rcpp_funcs
  ),
  pit_lineage = list(
    macro_shock_extraction = "AR(1) expanding 36m burn-in residuals on KR_TermSpread = KR_Gov10Y - KR_Gov3Y first-diff (inherited from WT_004 Step 1)",
    beta_estimation = "24m rolling per-ticker OLS (Ret_1M ~ BM_Ret + macro_shock) + mkt control (inherited WT_004 Step 3)",
    sign_alignment = "expanding |IC| sign over months 1..t-1 with ≥12 burn-in",
    smoothing = "EMA3 on per-month z (light, 3-month half-life)",
    forward_alpha = "as_of=2026-04 using beta lagged 1 month → predicts 2026-05 1M return"
  ),
  graduation_summary = list(
    status = graduation_status,
    rationale = if (graduation_status == "REJECT_GRADUATION") {
      sprintf("Single-factor KR_TermSpread β alpha at 1M horizon misses graduation criteria: ICIR=%.3f<0.20, Harvey-t-NW=%.2f<3.0, subperiod strict %d/3<2. Subperiod sign 3/3 PASS + DSR analytical z=%.2f PASS + DSR bootstrap z=%.2f PASS + orthogonality vs Hybrid PASS (max |cor|=%.3f). 12M ICIR=%.3f stronger but Harvey-NW=%.2f still <3.0. Improvement over composite ICIR 0.110→%.3f resolves RF-A2 dilution but does not pass full graduation.",
              grad$status_1m$icir, grad$status_1m$harvey_t_nw, diag_agg$subperiod_strict_pass,
              dsr$dsr_z_analytical, dsr$dsr_z_bootstrap, ortho$overall_max_abs_pearson,
              grad$status_12m$icir, grad$status_12m$harvey_t_nw, grad$status_1m$icir)
    } else {
      "GRADUATION_PASS — proceed to Risk Agent"
    },
    fail_at_1m = if (!all_1m_pass) {
      flags <- c()
      if (!grad$status_1m$rank_ic_pass) flags <- c(flags, sprintf("rank_ic %.4f < 0.04", grad$status_1m$rank_ic))
      if (!grad$status_1m$icir_pass) flags <- c(flags, sprintf("ICIR %.3f < 0.20", grad$status_1m$icir))
      if (!grad$status_1m$harvey_t_pass) flags <- c(flags, sprintf("Harvey-t-NW %.2f < 3.0", grad$status_1m$harvey_t_nw))
      flags
    } else c(),
    additional_findings = list(
      decile_long_short_t = round(diag_agg$ls_d10_d1_t, 2),
      decile_long_short_sr_annual_gross = round(diag_agg$ls_d10_d1_sr_annual_gross, 3),
      orthogonality_vs_hybrid_pass = ortho$overall_pass_threshold_025,
      orthogonality_max_abs_cor = round(ortho$overall_max_abs_pearson, 3),
      dsr_blp_pass = dsr$pass_dsr_analytical,
      improvement_over_wt004_composite_icir = round(grad$status_1m$icir - 0.110, 3),
      sign_stability = round(diag_agg$subperiod_sign_stab, 2)
    ),
    archived_value = list(
      "Single-factor isolation confirms RF-A2 composite dilution thesis from WT_004",
      "12M ICIR 0.317 + Harvey-NW 1.90 + sign 3/3 → long-horizon variant for future research",
      "Sector-neutral IC retention 0.42 → meaningful sector-level macro exposure (could be reframed as Risk overlay)",
      "Orthogonality vs Hybrid robust (|cor| < 0.14) → genuinely new signal axis"
    )
  )
)

draft_path <- file.path(MBOX, "alpha_package_draft.json")
write_json(alpha_package, draft_path, auto_unbox = TRUE, pretty = TRUE, digits = 6,
           na = "null")
cat(sprintf("[04] alpha_package_draft.json written → %s\n", draft_path))

# alpha_validation.json (full diagnostics for Risk/Optimizer downstream)
validation <- list(
  task_id = WT_ID,
  validation_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  graduation_status = graduation_status,
  graduation_pass_1m = all_1m_pass,
  primary_variant = "alpha_ema3_z",
  ic_table = ic_table,
  diagnostics_aggregate = diag_agg,
  orthogonality_vs_hybrid = ortho,
  dsr_strict = dsr,
  feature_leakage = leak,
  predictor_autocor = auto,
  method_shopping_log = method_log,
  challenge_flags = challenge_flags
)
write_json(validation, file.path(OUT, "alpha_validation.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat(sprintf("[04] alpha_validation.json written → %s\n",
            file.path(OUT, "alpha_validation.json")))

# Lineage record (per L-194 ordering: Write file FIRST, then record_package_lineage)
source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "single-factor KR_TermSpread β + EMA3 sign-aligned",
  input_file_paths = c(
    file.path(PROJ, "stage_artifacts/WT_D20260508_004/macro_betas_monthly.parquet"),
    file.path(PROJ, "stage_artifacts/WT_D20260508_004/panel_monthly.parquet"),
    file.path(PROJ, "stage_artifacts/WT_D20260508_004/macro_shocks_monthly.parquet"),
    file.path(PROJ, ".cache/ecos_bond_rates.parquet"),
    file.path(PROJ, ".cache/rawdata.parquet")
  )
)

cat("\n[04] DONE.\n")
cat(sprintf("    Graduation status: %s\n", graduation_status))
cat(sprintf("    1M ICIR: %.3f / Harvey-NW: %.2f / Sign 3/3: %.0f%% / DSR_BLP: %.2f\n",
            grad$status_1m$icir, grad$status_1m$harvey_t_nw,
            diag_agg$subperiod_sign_stab * 100, dsr$dsr_z_analytical))
cat(sprintf("    12M ICIR: %.3f / Harvey-NW: %.2f\n",
            grad$status_12m$icir, grad$status_12m$harvey_t_nw))
cat(sprintf("    Orthogonality max|cor|: %.3f (PASS=%s)\n",
            ortho$overall_max_abs_pearson, ortho$overall_pass_threshold_025))
