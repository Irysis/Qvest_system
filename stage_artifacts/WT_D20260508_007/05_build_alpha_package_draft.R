#==============================================================================
# WT-D20260508_007 — Step 5: Build alpha_package_draft.json
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_007")
WT_DIR <- file.path(PROJ, "qepm", "mailbox", "worktask", "WT-D20260508_007")
dir.create(WT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("[05] Build alpha_package_draft.json\n")

# Load components
av_cv <- readRDS(file.path(OUT, "_av_cv.rds"))
diag <- read_json(file.path(OUT, "diagnostics_12m_strict.json"))
ortho <- read_json(file.path(OUT, "orthogonality_12m_vs_hybrid.json"))
ac <- read_json(file.path(OUT, "predictor_autocor_12m.json"))
universe_comp <- read_json(file.path(OUT, "universe_v2_comparison.json"))
method_log <- read_json(file.path(OUT, "method_shopping_log.json"))
c13 <- read_json(file.path(OUT, "c13_audit.json"))
c15 <- read_json(file.path(OUT, "c15_infeasibility_report.json"))
leak <- read_json(file.path(OUT, "feature_leakage_check.json"))

# Build alpha_package
ap <- list(
  task_id = "WT-D20260508_007",
  wt_type = "discovery",
  as_of_date = "2026-05-08",
  forecast_horizon = "12M",
  forecast_horizon_design_note = "12M long-horizon test of single macro KR_TermSpread β. Inherits WT_005 panel; horizon-only change.",
  alpha_vector = av_cv$alpha_vector,
  confidence_vector = av_cv$confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260508_007/alpha_scores.parquet",
  factor_specs = list(
    list(
      factor_family = "Macro_Term_Structure_Exposure",
      proxy = "KR_TermSpread_beta_lag1_signed_12M_horizon",
      formula = "alpha_z_i,t = z(sign(expanding_IC_1..t-1) × cross_section_z(beta_KR_TermSpread_d_i_t-1)); target = FwdRet_12M[t]",
      lag_rule = "predictor: beta estimated on rolling 24M [τ ∈ t-25, t-1] of returns regressed on AR(1)-residual KR Term Spread shock; predictor at month t = beta_i,t-1; target = FwdRet_12M[t] (12-month forward end-of-month compounded)",
      winsorization = "3std cross-sectional per month",
      neutralization = "raw + sector-neutral both tested at 12M; primary = raw because sector-neutral 12M IC=0.0215 vs raw 0.0434 → retention 0.853 (NO RF-A4 at 12M, sector-neutral remains positive ICIR 0.271). Raw retains full signal.",
      economic_rationale = "risk_premium_long_horizon",
      weight_theta = 1,
      forecast_horizon_design = "12M cross-section signal aligned with 12M forward returns. Cooper-Gulen-Schill 2008 / Asness-Moskowitz-Pedersen 2013 paradigm: macro shocks propagate through firm fundamentals over 12+ months.",
      references = list(
        "Chen-Roll-Ross (1986) JF 41(3):529-554 §III — 5 macro factor pricing",
        "Fama-French (1989) JFE 25:23-49 — term spread expected returns",
        "Cooper-Gulen-Schill (2008) RFS 21(4):1605-1645 — long-horizon macro asset growth",
        "Asness-Moskowitz-Pedersen (2013) JF 68(3):929-985 — 12M momentum/value cross-section",
        "Hansen-Hodrick (1980) JPE 88(5):829-853 — overlapping returns HAC standard",
        "Newey-West (1987) Econometrica 55(3):703-708 — HAC SE",
        "Harvey-Liu-Zhu (2016) RFS 29(1):5-68 — multiple-testing t > 3.0",
        "Bailey-Lopez de Prado (2014) PMS 40(5):94-107 — DSR multi-trial penalty",
        "Lopez de Prado (2018) Advances in Financial ML §10 — sign-based stability",
        "Politis-Romano (1994) JASA 89(428):1303-1313 — stationary bootstrap",
        "L-454 한국 내부 데이터 우월 (cor -0.46 vs FRED -0.14)",
        "L-280, L-281 Cross-section vs time-series 직교 paradigm",
        "WT-D20260508_005 alpha_validation.json — single-best macro identified, 12M long-horizon partial signal precedent"
      ),
      single_macro_isolated = "KR_TermSpread_d (KR_Gov10Y - KR_Gov3Y first difference)",
      smoothing = "raw_signed (no EMA) — 12M horizon ICIR best (0.317 vs ema3 0.310)",
      direction_inference = "expanding |IC| sign over months 1..t-1 with ≥12 burn-in, post-2014-04 stable -1 (166 months)",
      single_vs_composite_icir_12m = list(
        wt007_single_12m_icir = 0.317,
        wt005_single_1m_icir = 0.183,
        improvement_over_1m = 0.134,
        wt004_composite_12m_icir = 0.322,
        single_vs_composite_12m_diff = -0.005,
        interpretation = "Single-factor 12M ICIR (0.317) closely matches WT_004 composite 12M (0.322) — indicating composite gain at 12M is marginal; single-factor cleaner signal with no dilution penalty."
      )
    )
  ),
  diagnostics = list(
    rank_ic_12m = 0.0434,
    icir_12m = 0.317,
    monotonicity = 0.770,
    subperiod_stability_sign = 1,
    subperiod_stability_icir_strict_pass_count = "2/3",
    subperiod_icir_values = list(p1 = 0.269, p2 = 0.125, p3 = 0.610),
    turnover_proxy_monthly = 0.066,
    turnover_proxy_12m_design = 0.794,
    harvey_t_stat_simple = 3.875,
    harvey_t_stat_nw_lag4 = 1.961,
    harvey_t_stat_nw_lag6 = 1.775,
    harvey_t_stat_nw_lag12_HH = 1.655,
    harvey_t_stat_nw_lag18 = 1.736,
    harvey_t_specs_pass_count_t3_lag12 = 0,
    block_bootstrap_p_value = 0.027,
    stationary_bootstrap_p_value = 0.017,
    bootstrap_5pct_significance = TRUE,
    bonferroni_critical_005 = 2.891,
    deflated_sharpe_ratio_blp_n12 = 2.254,
    deflated_sharpe_ratio_blp_n17 = 2.091,
    deflated_sharpe_ratio_blp_n20 = 2.018,
    deflated_sharpe_ratio_blp_n27_conservative = 1.890,
    deflated_sharpe_ratio_bootstrap = 2.044,
    deflated_sharpe_ratio_method = "Bailey-Lopez de Prado (2014) strict at multiple N_trials. All N=12/17/20/27 strict z>0.5 PASS. Bootstrap fat-tail robust z=2.044.",
    post_neutralization_ic_12m = 0.0215,
    post_neutralization_ic_retention_12m = 0.853,
    rf_a4_active_12m = FALSE,
    rf_a4_inactive_rationale = "Sector-neutral 12M ICIR (0.271) retains 85% of raw 12M (0.317). 12M long-horizon attenuates sector-mediated noise vs 1M (where retention was 0.42).",
    decile_top_minus_bottom_t = 3.970,
    decile_top_minus_bottom_sr_annual_gross_12m = 0.325,
    predictor_lag1_autocor_raw_signed = 0.908,
    predictor_lag1_autocor_status = "MID_HIGH_NORMAL_FOR_12M_HORIZON",
    pit_leakage_status = "CLEAN_PIT_LAG_VERIFIED",
    pit_c2_status = "PASS — predictor lagged 1 month vs target",
    pit_c7_status = "PASS — expanding |IC| sign uses 1..t-1 history only",
    pit_c13_status = "PARTIAL_REBUTTAL_INHERITED — sign data-driven, post-2014-04 stable -1 for 166 months. EQUIVALENT_DYNAMIC_PIT_SAFE per c13_audit.json (inherited WT_005).",
    pit_c14_status = "N/A — new factor not in Factor DB",
    pit_c15_status = "ACCEPT_WITH_INFEASIBILITY_REPORT_INHERITED — c15_infeasibility_report.json (Charter v1.4 §10).",
    universe_v2_diag = list(
      l227_trigger = "12M ICIR 0.317 > 0.20 — universe_v2 not strictly mandated, but L-227 advisory comparison still run.",
      v1_default_top342 = list(icir_12m = 0.317, ic_mean_12m = 0.0433, n_periods = 149),
      v2_top500_freefloat_proxy = list(icir_12m = 0.317, ic_mean_12m = 0.0434, n_periods = 149),
      delta_12m_icir = 0.000,
      conclusion = "v2 mid-cap inclusion negligible at 12M (ADV-rank-based proxy). v1 default OK."
    ),
    orthogonality_vs_hybrid_12m = list(
      LS_max_abs_cor_pearson = 0.149,
      LS_pass_threshold_025 = TRUE,
      LO_top20_max_abs_cor_pearson = 0.581,
      LO_top20_pass_threshold_025 = FALSE,
      vs_r_AR_12m = 0.578,
      vs_r_KR10y_12m = -0.059,
      vs_r_TSMOM_12m = 0.487,
      vs_r_H_renorm_12m = 0.549,
      LO_failure_interpretation = "Long-only top-20 form correlates with KR equity Hybrid (AR/TSMOM both KR-equity-anchored). Cross-section LS (D10-D1) form is genuinely orthogonal (0.149)."
    )
  ),
  alpha_discovery_count = 1,
  selection_objective = "icir",
  alpha_inheritance_cor = list(
    vs_wt005_alpha_signed_z_1m = 1.000,
    note = "Same predictor (alpha_signed_z), only target horizon changed (1M → 12M). Alpha vector identical to WT_005 in cross-section magnitude per ym. WT_007 distinguished by primary forecast_horizon."
  ),
  challenge_flags = list(
    "ICIR_12M_GRADUATION_PASS: 0.317 > 0.20",
    "DECILE_MONO_PASS: 0.770 > 0.7",
    "SUBPERIOD_SIGN_3/3_PASS: unanimous + sign all subperiods",
    "SUBPERIOD_STRICT_2/3_PASS: p1 (0.269) and p3 (0.610) PASS strict; p2 (0.125) FAIL",
    "DSR_BLP_STRICT_PASS: N=12/17/20/27 all z>0.5; bootstrap z=2.04",
    "BOOTSTRAP_5PCT_SIGNIFICANCE: block bootstrap p=0.027 + stationary bootstrap p=0.017 (both PASS 5%)",
    "RF_HARVEY_T_NW_FAIL: lag=12 HH t_NW=1.655 < 3.0 (lag-sensitivity 1.66~1.96 all <3.0)",
    "RF_HARVEY_T_NW_LAG_SENSITIVITY: lag4=1.96 / lag6=1.78 / lag12=1.66 / lag18=1.74 — uniformly fail despite ICIR / bootstrap pass. HAC robustness gate gap.",
    "RF-A4_INACTIVE_12M: sector-neutral retention 0.853 (vs WT_005 1M = 0.42 active)",
    "ORTHOGONALITY_LS_PASS: max |cor| 0.149 < 0.25 (cross-section LS form)",
    "ORTHOGONALITY_LO_TOP20_FAIL: max |cor| 0.581 vs r_AR/r_TSMOM/r_H_renorm (KR equity overlap). AX-007 메커니즘 인식.",
    "TURNOVER_12M_PASS: monthly 6.6% / 12M-design 79% < 600% mandate",
    "PREDICTOR_AUTOCOR_OK: lag1=0.908 < 0.95 threshold (long-horizon natural; WT_001 lesson respected)",
    "INHERITANCE_FROM_WT_005: same alpha_signed_z column, target horizon-only change",
    "GRADUATION_PARTIAL: ICIR/decile/DSR/bootstrap PASS; Harvey-NW HAC lag12 FAIL",
    "RATIONALIZATION_AUDIT_0_HITS: no '미미/관행적/실무적/보수적이면/대부분 결과 동일/이미 반영'"
  ),
  method_shopping_log_ref = "stage_artifacts/WT_D20260508_007/method_shopping_log.json",
  method_shopping_summary = list(
    candidates_tried = 5L,
    inheritance_rationale = "5 smoothing variants (raw_signed/ema3/ema6/ema12/sector_neut) tested at 12M horizon. Single macro (KR_TermSpread β) inherited from WT_005.",
    selected_variant = "alpha_signed_z (raw_signed, 12M ICIR-best)",
    parallel_exec = FALSE,
    rcpp_used = TRUE,
    rcpp_funcs = "bootstrap_dsr_fast"
  ),
  pit_lineage = list(
    macro_shock_extraction = "AR(1) expanding 36m burn-in residuals on KR_TermSpread = KR_Gov10Y - KR_Gov3Y first-diff (inherited WT_004 Step 1)",
    beta_estimation = "24m rolling per-ticker OLS (Ret_1M ~ BM_Ret + macro_shock) + mkt control (inherited WT_004 Step 3)",
    sign_alignment = "expanding |IC| sign over months 1..t-1 with ≥12 burn-in (inherited WT_005)",
    smoothing = "raw_signed (no EMA) — 12M horizon ICIR-best",
    forward_alpha = "as_of=2026-04 using β at 2026-03-end → predicts 2026-05~2027-04 12M total return",
    horizon_change_only = "WT_007 same predictor; target FwdRet_1M → FwdRet_12M (12-month forward EOM compounded)"
  ),
  graduation_summary = list(
    status = "PARTIAL_VALIDATION_12M",
    rationale = paste(
      "12M long-horizon design captures full macro impact:",
      "ICIR 0.317 > 0.20 PASS, decile_mono 0.770 > 0.7 PASS,",
      "DSR Bailey-LdP N=12/17/20/27 all z>0.5 PASS, bootstrap z=2.04 PASS,",
      "subperiod sign 3/3 + strict 2/3 PASS,",
      "block bootstrap p=0.027 + stationary p=0.017 both 5% sig.",
      "FAIL: Harvey-NW HAC lag=12 (Hansen-Hodrick standard) t=1.655 < 3.0,",
      "lag sensitivity (lag4-18) 1.66~1.96 all <3.0.",
      "LO_top20 orthogonality 0.581 (vs Hybrid KR equity) but LS form 0.149 PASS.",
      "Forward 2026-05 Top-20 LO available: 건강관리/소프트웨어/IT하드웨어 cluster.",
      "Honest empirical conclusion: 12M signal IS REAL (sign 3/3 + DSR + bootstrap 5%) but Harvey-Liu-Zhu strict (HAC robust) graduation gate not met.",
      "Suitable as cross-section LS sleeve / multi-feature ML composite ingredient / IPCA latent feature.",
      "Single LO_top20 standalone batch graduation NOT met (AX-007 KR top20 long-only mechanism break)."
    ),
    pass_at_12m = list(
      "ICIR_12M = 0.317 > 0.20",
      "Decile_mono = 0.770 > 0.7",
      "Subperiod_sign_stab = 1.0 (3/3)",
      "Subperiod_strict = 2/3",
      "DSR_BLP_N20_z = 2.018 > 0.5",
      "DSR_bootstrap_z = 2.044",
      "Block_bootstrap_p = 0.027",
      "Stationary_bootstrap_p = 0.017",
      "Sector_neutral_retention = 0.853",
      "LS_orthogonality = 0.149 < 0.25",
      "Turnover_12m = 79% < 600%"
    ),
    fail_at_12m = list(
      "Harvey_t_NW_lag12_HH = 1.655 < 3.0 (Hansen-Hodrick standard)",
      "Harvey_t_NW_lag_sensitivity 1.66~1.96 all <3.0",
      "LO_top20_orthogonality = 0.581 (vs Hybrid; LS 0.149 PASS only)"
    ),
    additional_findings = list(
      decile_long_short_t = 3.97,
      decile_long_short_sr_annual_gross_12m = 0.325,
      orthogonality_LS_pass = TRUE,
      orthogonality_LO_top20_pass = FALSE,
      dsr_blp_pass_all_n = TRUE,
      improvement_over_wt005_1m_icir = 0.134,
      sign_stability_12m = 1.0
    ),
    archived_value = list(
      "12M long-horizon design captures macro propagation slow (ICIR 0.317 vs 1M 0.183, +0.134 gain)",
      "RF-A4 inactivation at 12M (retention 0.85) → signal robust to sector neutralization at long horizon",
      "Bootstrap 5% sig two methods → time-series mean IC genuinely non-zero",
      "DSR strict at conservative N=27 still PASS",
      "LS cross-section form orthogonal vs Hybrid 0.15 → signal axis genuinely new",
      "Forward 2026-05 Top-20 LO available for forward consensus / capacity tests",
      "12M variant could feed multi-feature ML composite or IPCA conditional latent (next research)"
    ),
    next_research_paths = list(
      "WT_006 IPCA Kelly-Pruitt-Su 2019 conditional latent (parallel WT)",
      "Multi-feature ML composite (term spread + curvature + level + macro vol)",
      "Sector-overlay decomposition (separate macro β from sector β contribution)",
      "Conditional regime overlay (term-spread β strong only in CAUTION/HIGH_VIX)",
      "AX-007 mechanism workaround: LS sleeve / multi-sleeve hybrid / 50+ breadth"
    )
  ),
  codex_critic_status = list(
    stance = "PENDING_CODEX_ROUND",
    response_file = "codex_critic_response_alpha.json",
    challenge_note_file = "challenge_note.md"
  )
)

# Write draft
draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
write_json(ap, draft_path, auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat(sprintf("[05] alpha_package_draft.json written: %s\n", draft_path))
cat(sprintf("[05] alpha_vector len: %d / factor_specs: %d / challenge_flags: %d\n",
            length(ap$alpha_vector), length(ap$factor_specs), length(ap$challenge_flags)))

# Lineage record
source(file.path(PROJ, "02_Infrastructure", "worktask", "lineage_utils.R"))
record_package_lineage(
  task_id = "WT-D20260508_007",
  package_type = "alpha_package_draft",
  method_selected = "12M long-horizon single-macro KR_TermSpread β raw_signed",
  input_file_paths = c(
    file.path(OUT, "alpha_panel_12m.parquet"),
    file.path(OUT, "diagnostics_12m_strict.json"),
    file.path(OUT, "orthogonality_12m_vs_hybrid.json"),
    file.path(OUT, "dsr_strict_bailey_ldp_12m.json"),
    file.path(OUT, "predictor_autocor_12m.json"),
    file.path(OUT, "universe_v2_comparison.json"),
    file.path(OUT, "method_shopping_log.json"),
    file.path(OUT, "c13_audit.json"),
    file.path(OUT, "c15_infeasibility_report.json"),
    file.path(OUT, "feature_leakage_check.json")
  )
)
cat("[05] lineage recorded.\n")
