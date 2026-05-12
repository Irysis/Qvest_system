#==============================================================================
# WT-D20260508_007 — Step 4: Finalize 12M Alpha + Forward 2026-05 + Universe v2
#
# Outputs:
#   - alpha_scores.parquet (all sig_dates × all eligible tickers, 12M signal)
#   - alpha_scores_forward_2026-05.parquet (forward Top-20 LO + LS deciles)
#   - alpha_validation.json (full diagnostics summary)
#   - universe_v2_comparison.json (KR_TOP500_FREEFLOAT 12M ICIR comparison)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SRC  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_005")
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_007")

cat("[04] WT-D20260508_007 — Finalize 12M alpha + Forward 2026-05\n")

# Use full panel (incl. 2010-12 burn-in) for full alpha_scores; diagnostics use post-2013
panel_full <- as.data.table(read_parquet(file.path(SRC, "alpha_panel_single.parquet")))
panel_full <- panel_full[eligible == TRUE]
PRIMARY_COL <- "alpha_signed_z"  # raw_signed (12M ICIR-best)

# Output schema for alpha_scores.parquet
out_cols <- c("Ticker", "ym", "Date_eom", "Sector", "alpha_signed_z",
              "alpha_ema3_z", "alpha_ema6_z", "alpha_ema12_z", "alpha_sn",
              "beta_lag1", "FwdRet_12M", "FwdRet_6M", "FwdRet_1M",
              "ADV20_lag1", "Size_eom")
alpha_scores_full <- panel_full[, ..out_cols]
alpha_scores_full[, alpha_z := alpha_signed_z]  # primary col alias for downstream
alpha_scores_full[, forecast_horizon := "12M"]
write_parquet(alpha_scores_full, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("[04] alpha_scores.parquet: %d rows × %d cols (covers %d ym)\n",
            nrow(alpha_scores_full), ncol(alpha_scores_full),
            uniqueN(alpha_scores_full$ym)))

# ---- Forward 2026-05 (predicts May 2026 -> Apr 2027 12M) ----
forward_ym <- "2026-04"
fwd <- panel_full[ym == forward_ym & !is.na(alpha_signed_z)]
setorder(fwd, -alpha_signed_z)
cat(sprintf("[04] Forward signal at %s: %d eligible tickers\n", forward_ym, nrow(fwd)))

# Decile + Top-20 LO
fwd[, decile := as.integer(cut(alpha_signed_z,
                              quantile(alpha_signed_z, seq(0, 1, 0.1), na.rm = TRUE),
                              include.lowest = TRUE, labels = FALSE))]
fwd[, alpha_rank_desc := frank(-alpha_signed_z, na.last = "keep")]
fwd[, top20_LO_flag := alpha_rank_desc <= 20]

fwd_out <- fwd[, .(Ticker, ym, Date_eom, Sector, alpha_signed_z, alpha_z = alpha_signed_z,
                   alpha_ema3_z, alpha_ema6_z, alpha_ema12_z, alpha_sn,
                   beta_lag1, decile, alpha_rank_desc, top20_LO_flag,
                   ADV20_lag1, Size_eom)]
fwd_out[, forecast_horizon := "12M"]
fwd_out[, forecast_window := "2026-05_to_2027-04"]
write_parquet(fwd_out, file.path(OUT, "alpha_scores_forward_2026-05.parquet"))
cat(sprintf("[04] Forward Top-20 LO saved (predicts 12M from 2026-05)\n"))

cat("\n[04] Top 20 by alpha_signed_z (12M forward):\n")
print(fwd_out[top20_LO_flag == TRUE, .(Ticker, alpha_signed_z, beta_lag1, Sector)])

# ---- Universe v2 comparison: KR_TOP500_FREEFLOAT-like via Size_eom + ADV ----
# Approximate KR_TOP500: top 500 by ADV20_lag1 (proxy for free-float liquidity)
# For each month, restrict to top-500 instead of top-342 (default)
ic_v2 <- panel_full[!is.na(alpha_signed_z) & !is.na(FwdRet_12M) & ym >= "2013-01"]
# Per ym, compute ADV rank
ic_v2[, adv_rank := frank(-ADV20_lag1, na.last = "keep"), by = ym]

# Default v1 (top-342)
ic_v1_table <- ic_v2[adv_rank <= 342,
  .(rank_ic = cor(alpha_signed_z, FwdRet_12M, method = "spearman", use = "complete.obs"),
    n_used = sum(!is.na(alpha_signed_z) & !is.na(FwdRet_12M))),
  by = ym]
v1_ic_mean <- mean(ic_v1_table$rank_ic, na.rm = TRUE)
v1_icir <- v1_ic_mean / sd(ic_v1_table$rank_ic, na.rm = TRUE)

# v2 (top-500)
ic_v2_table <- ic_v2[adv_rank <= 500,
  .(rank_ic = cor(alpha_signed_z, FwdRet_12M, method = "spearman", use = "complete.obs"),
    n_used = sum(!is.na(alpha_signed_z) & !is.na(FwdRet_12M))),
  by = ym]
v2_ic_mean <- mean(ic_v2_table$rank_ic, na.rm = TRUE)
v2_icir <- v2_ic_mean / sd(ic_v2_table$rank_ic, na.rm = TRUE)

cat(sprintf("\n[04] Universe comparison (12M):\n"))
cat(sprintf("       v1_top342:  IC=%.4f, ICIR=%.3f, n_periods=%d\n",
            v1_ic_mean, v1_icir, nrow(ic_v1_table)))
cat(sprintf("       v2_top500:  IC=%.4f, ICIR=%.3f, n_periods=%d\n",
            v2_ic_mean, v2_icir, nrow(ic_v2_table)))
cat(sprintf("       delta_icir: %.3f\n", v2_icir - v1_icir))

universe_comp <- list(
  default_v1_top342 = list(
    icir_12m = v1_icir, ic_mean_12m = v1_ic_mean, n_periods = nrow(ic_v1_table)
  ),
  v2_top500_freefloat_proxy = list(
    icir_12m = v2_icir, ic_mean_12m = v2_ic_mean, n_periods = nrow(ic_v2_table),
    construction = "Approximated by top-500 by ADV20_lag1 (free-float liquidity proxy)"
  ),
  delta_icir = v2_icir - v1_icir,
  conclusion = if (v2_icir - v1_icir > 0.05) "V2_MID_CAP_MARGINAL_GAIN"
               else if (v2_icir - v1_icir > 0) "V2_MARGINAL_POSITIVE"
               else "V1_OK"
)
write_json(universe_comp, file.path(OUT, "universe_v2_comparison.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

# ---- Method shopping log ----
method_log <- list(
  candidates_tried = 5L,
  rationale = "5 smoothing variants × 1 macro factor (KR_TermSpread β) tested at 12M horizon. WT_005 inheritance.",
  method_log = list(
    list(name = "raw_signed_12M", icir_12m = 0.317, t_simple = 3.875, t_nw_lag12 = 1.655, selected = TRUE),
    list(name = "ema3_12M", icir_12m = 0.310, t_simple = 3.782, t_nw_lag12 = 1.622, selected = FALSE),
    list(name = "ema6_12M", icir_12m = 0.290, t_simple = 3.544, t_nw_lag12 = 1.522, selected = FALSE),
    list(name = "ema12_12M", icir_12m = 0.257, t_simple = 3.139, t_nw_lag12 = 1.302, selected = FALSE),
    list(name = "sector_neut_12M", icir_12m = 0.271, t_simple = 3.307, t_nw_lag12 = NA, selected = FALSE)
  ),
  selection_objective = "icir",
  parallel_exec = FALSE,
  rcpp_used = TRUE,
  rcpp_funcs = "bootstrap_dsr_fast"
)
write_json(method_log, file.path(OUT, "method_shopping_log.json"),
           auto_unbox = TRUE, pretty = TRUE)

# ---- Aggregate alpha_validation.json ----
diag <- read_json(file.path(OUT, "diagnostics_12m_strict.json"))
ortho <- read_json(file.path(OUT, "orthogonality_12m_vs_hybrid.json"))
ac <- read_json(file.path(OUT, "predictor_autocor_12m.json"))

alpha_validation <- list(
  task_id = "WT-D20260508_007",
  as_of_date = "2026-05-08",
  forecast_horizon = "12M",
  primary_variant = diag$primary_variant,
  primary_col = diag$primary_col,
  graduation_summary = list(
    rank_ic_12m = unlist(diag$ic_table)[grep("^ic_mean1", names(unlist(diag$ic_table)))][1],
    icir_12m = 0.317,
    icir_pass = TRUE,  # 0.317 > 0.20
    t_simple_12m = 3.875,
    harvey_t_nw_lag12_HH = 1.655,
    harvey_t_nw_lag4 = 1.961,
    harvey_t_nw_lag6 = 1.775,
    harvey_t_nw_lag18 = 1.736,
    harvey_t_pass_nw12 = FALSE,  # 1.655 < 3.0
    block_bootstrap_12m_blocks_p_value = 0.027,
    stationary_bootstrap_p_value = 0.017,
    bootstrap_significance = "PASS_5PCT_BOTH_BLOCK_AND_STATIONARY",
    subperiod_sign_stab = 1.0,
    subperiod_strict_pass = "2/3",  # p1 PASS, p2 FAIL, p3 PASS
    decile_monotonicity = 0.770,
    decile_monotonicity_pass = TRUE,  # > 0.7
    ls_d10_d1_t = 3.970,
    ls_sr_annual_gross_12m = 0.325,
    dsr_blp_n20_z = 2.018,
    dsr_blp_pass = TRUE,
    dsr_bootstrap_z = 2.044,
    sector_neutral_retention = 0.853,
    rf_a4_active = FALSE,
    turnover_proxy_monthly = 0.066,
    turnover_proxy_12m_design = 0.794,
    orthogonality_LS_max_abs_cor = 0.149,
    orthogonality_LS_pass = TRUE,
    orthogonality_LO_top20_max_abs_cor = 0.581,
    orthogonality_LO_top20_pass = FALSE,
    forecast_horizon_design = "12M cross-section signal evaluated against 12M forward returns. Long-horizon variant of WT_005 single macro KR_TermSpread β.",
    pit_lineage = "Inherited from WT_005 (24M rolling β + expanding |IC| sign, 12 burn-in)",
    predictor_autocor = ac$predictor_lag1_autocor,
    predictor_autocor_status = ac$status
  ),
  honest_empirical_assessment = list(
    pass = list(
      "ICIR_12M = 0.317 > 0.20 (graduation)",
      "Decile_monotonicity = 0.770 > 0.7",
      "DSR_BLP_strict_N20 = 2.018 > 0.5",
      "Subperiod_sign_3/3 unanimous +",
      "Sector_neutral_retention = 0.853 (RF-A4 inactive at 12M)",
      "Turnover_12m_design 79% < 600%",
      "Orthogonality_LS_max_cor = 0.149 < 0.25",
      "LS_D10-D1_t = 3.97 (annualized 12M scale)",
      "Block_bootstrap_p = 0.027 (5% sig)",
      "Stationary_bootstrap_p = 0.017 (5% sig)"
    ),
    fail = list(
      "Harvey_t_NW_lag12_HH = 1.655 < 3.0 (Hansen-Hodrick standard for 12M overlap)",
      "Harvey_t_NW_lag4_6_18 sensitivity: 1.96 / 1.78 / 1.74 (all <3.0)",
      "Subperiod_strict_ICIR≥0.20 = 2/3 (graduation requires 2/3 → meets threshold but tight)",
      "LO_top20_orthogonality vs Hybrid = 0.58 (long-only form correlates with KR equity Hybrid)"
    ),
    interpretation = paste(
      "12M long-horizon design captures full macro impact (ICIR 0.317).",
      "Sample-mean t (3.88) PASS but HAC-robust t (1.66) FAIL.",
      "Bootstrap-based significance both p<5% indicates the time-series mean IC is",
      "non-zero, but Harvey-Liu-Zhu strict (NW HAC robust) standard requires t>3.0.",
      "Conclusion: FORMAL_PARTIAL_VALIDATION_12M.",
      "12M signal is REAL and sign-stable across subperiods (3/3) and DSR-strict.",
      "But Harvey-t graduation gate not met under HAC robustness."
    ),
    next_research_paths = list(
      "Multi-feature ML composite (single-macro + curvature + level)",
      "IPCA Kelly-Pruitt-Su 2019 conditional latent (WT_006 ongoing)",
      "Sector overlay decomposition (separate macro β from sector β)",
      "Larger universe expansion (KR_TOP500 + 1e8 ADV) for 12M small-cap reach",
      "Conditional regime-overlay (term-spread β strong only in CAUTION/HIGH_VIX regime)"
    )
  ),
  ic_table = diag$ic_table,
  harvey_t_nw_sensitivity = diag$harvey_t_nw_lag_sensitivity,
  subperiod_stability = diag$subperiod_stability,
  decile_means = diag$decile_means,
  ls_d10_d1_12m = diag$ls_d10_d1_12m,
  dsr_strict = diag$dsr_strict,
  sector_neutral_check = diag$sector_neutral_check,
  turnover_proxy = diag$turnover_proxy,
  orthogonality_12m = list(
    cor_table = ortho$cor_table,
    max_abs_cor_per_port = ortho$max_abs_cor_per_port,
    vs_r_H_renorm_12m = ortho$vs_r_H_renorm_12m,
    conclusion = ortho$conclusion
  ),
  universe_comparison = universe_comp,
  method_shopping = method_log
)
write_json(alpha_validation, file.path(OUT, "alpha_validation.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

cat(sprintf("\n[04] alpha_validation.json saved.\n"))
cat(sprintf("[04] DONE. Honest empirical: ICIR PASS, Harvey-NW lag12 FAIL → PARTIAL_VALIDATION_12M.\n"))
