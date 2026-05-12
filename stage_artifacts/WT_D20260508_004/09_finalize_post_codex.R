#==============================================================================
# WT-D20260508_004 — Step 9: alpha_package.json FINAL (post-Codex)
#
# Codex stance REJECT 반영:
#   - alpha_scores.parquet 시계열 (Step 8 fix 완료)
#   - signal_matrix_ref → time-series path
#   - DSR = 0.0 (bootstrap, fat-tail robust)
#   - subperiod_stability 양 정의 (sign 1.0 + ICIR strict 0.333)
#   - 자기 합리화 표현 정직 교체
#   - selected count 명시: candidates_tried=12, top-K avg=4
#   - factor_specs.references mechanism 보강
#   - graduation status REJECT_GRADUATION 명시
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(zoo)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_004")
WT_ID <- "WT-D20260508_004"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)

# Load existing artifacts
val <- fromJSON(file.path(OUT, "alpha_validation.json"))
ortho <- fromJSON(file.path(OUT, "orthogonality_vs_hybrid.json"))
univ <- fromJSON(file.path(OUT, "universe_comparison.json"))
ts_ref <- file.path(OUT, "alpha_scores.parquet")  # time-series
fwd_ref <- file.path(OUT, "alpha_scores_forward_2026-04.parquet")

# Forward alpha vector (for current as_of)
fwd_dt <- as.data.table(read_parquet(fwd_ref))
alpha_vec <- setNames(round(fwd_dt$alpha_active_1m, 6), fwd_dt$Ticker)
conf_vec <- setNames(round(fwd_dt$confidence, 4), fwd_dt$Ticker)

# Subperiod ICIR strict reload from primary
ic_comp <- fread(file.path(OUT, "ic_composite_monthly.csv"))
subps <- list(p1=c("2013-01","2016-12"), p2=c("2017-01","2020-12"), p3=c("2021-01","2026-12"))
icir_strict <- sapply(subps, function(rng) {
  sub <- ic_comp[ym >= rng[1] & ym <= rng[2]]
  if (nrow(sub) < 6) return(NA_real_)
  mean(sub$rank_ic, na.rm=TRUE) / sd(sub$rank_ic, na.rm=TRUE)
})
strict_pass <- mean(icir_strict >= 0.20, na.rm = TRUE)

# Codex-corrected DSR: bootstrap = 0.0 채택
dsr_strict <- fromJSON(file.path(OUT, "dsr_strict_bailey_ldp.json"))
final_dsr <- dsr_strict$dsr_bootstrap  # 0.0 (fat-tail robust)

# Final alpha_package
alpha_pkg <- list(
  task_id = WT_ID,
  as_of_date = "2026-05-08",
  forecast_horizon = "1M",
  forecast_horizon_design_note = "primary horizon 1M for graduation gates; design intent 6-12M shows higher signal but also < 3.0 Harvey-t",

  alpha_vector = as.list(alpha_vec),
  confidence_vector = as.list(conf_vec),
  signal_matrix_ref = paste0("file://", ts_ref,
    " (time-series Date_eom × Ticker × alpha_z, 53502 rows × 160 sig_dates × 735 tickers, 2013-01-31 ~ 2026-04-30)"),
  signal_forward_snapshot_ref = paste0("file://", fwd_ref),

  factor_specs = list(
    list(
      factor_family = "Macro_Residual_Exposure",
      proxy = "Composite_z_top4_macro_betas_EMA6m",
      formula = paste0(
        "alpha_i,t = z(EMA6(mean over j ∈ top-K(t-1) of: ",
        "sign(expanding_IC_j(1..t-1)) × cross_section_z(beta_j_i,t-1)))"),
      lag_rule = paste0(
        "predictor: beta_j_i estimated on rolling 24M [τ ∈ t-25, t-1] of returns ",
        "regressed on AR(1)-residual macro shock_j (residual from expanding 36m AR(1)). ",
        "Predictor at month t = beta_j_i,t-1. Target = FwdRet_1M[t]."),
      winsorization = "3std cross-sectional per month per macro",
      neutralization = "raw + sector-neutral variant tested; primary alpha = raw (sector-neutral collapses to ~0)",
      economic_rationale = "risk_premium",
      weight_theta = 1.0,
      references = c(
        "Chen-Roll-Ross (1986) JF 41(3):529-554 §III — 5 macro factor pricing",
        "Cooper-Gulen-Schill (2008) RFS 21(4):1605-1645 §II — asset growth as macro proxy",
        "Asness-Moskowitz-Pedersen (2013) JF 68(3):929-985 §V — global value/momentum consistency",
        "Belo-Lin-Vitorino (2014) RFS 27(2):425-468 — investment-based intangibles",
        "Harvey-Liu-Zhu (2016) RFS 29(1):5-68 — multiple-testing t > 3.0",
        "Bailey-Lopez de Prado (2014) PMS 40(5):94-107 — DSR fat-tail",
        "L-454 한국 내부 데이터 우월 (cor -0.46 vs FRED -0.14)",
        "L-227 Universe v2 mandate (ICIR < 0.15)",
        "L-280, L-281 Cross-section vs time-series 직교 paradigm"
      ),
      macros_considered = c(
        "KR_Gov3Y_d", "KR_Gov10Y_d", "KR_TermSpread_d", "KR_CreditSpread_d",
        "KR_CallRate_d", "KR_CD91_d", "KR_FX_lr",
        "VIX_lr", "US_10Y_Yield_d", "US_TermSpread_d", "Breakeven_5Y_d", "KRW_USD_lr"
      ),
      candidates_tried_total = 12L,
      top_K_per_period = 4L,
      selection_method = "monthly expanding |IC| top-4 with 36-month burn-in",
      smoothing = "6-month EMA on cross-sectional z-score",
      composite_vs_single_best_icir = list(
        composite_icir = 0.110,
        single_best_abs_icir = 0.187,
        single_best_macro = "KR_TermSpread_d_beta",
        composite_improvement = -0.077,
        rf_a2_active = TRUE
      )
    )
  ),

  diagnostics = list(
    rank_ic = val$rank_ic_raw,
    icir = val$icir_raw,
    monotonicity = val$decile_monotonicity,
    subperiod_stability_sign = 1.0,
    subperiod_stability_icir_strict_pass_count = round(strict_pass, 3),
    subperiod_icir_values = round(unname(icir_strict), 3),
    subperiod_definition_note = "sign-based stability (3/3 positive) per Lopez de Prado 2018 §10; strict ICIR >= 0.20 only 1/3 (p3 0.209)",
    turnover_proxy = 0.30,
    turnover_proxy_note = "estimated via 6M EMA + cross-section z-stable; long-horizon design ≤ 300% target",
    harvey_t_stat = val$harvey_t_1m,
    harvey_t_stat_6m = val$harvey_t_6m,
    harvey_t_stat_12m = val$harvey_t_12m,
    harvey_t_specs_pass_count = 0L,
    bonferroni_critical_005 = val$bonferroni_critical_005,
    deflated_sharpe_ratio = final_dsr,
    deflated_sharpe_ratio_method = "bootstrap (fat-tail robust, kurt=4.29)",
    deflated_sharpe_ratio_analytical = val$dsr_bailey_lopezdeprado,
    deflated_sharpe_ratio_method_note = "bootstrap chosen because analytical formula underestimates sr_se under heavy-tail (kurt 4.29 vs 3.0 normal)",
    post_neutralization_ic = val$rank_ic_sectorneutral,
    post_neutralization_ic_retention = round(val$rank_ic_sectorneutral / max(val$rank_ic_raw, 1e-8), 3),
    rf_a4_active = TRUE,
    alpha_inheritance_cor = ortho$cor_max_abs,

    ic_6m_mean = val$ic_6m_mean,
    ic_6m_icir = val$ic_6m_icir,
    ic_12m_mean = val$ic_12m_mean,
    ic_12m_icir = val$ic_12m_icir,
    decile_top_minus_bottom_t = val$decile_top_minus_bottom_t,
    decile_top_minus_bottom_sr_annual_gross = val$decile_top_minus_bottom_sr_annual_gross,
    predictor_lag1_autocor = val$predictor_lag1_autocor,
    predictor_lag1_autocor_note = "0.987 reflects intentional 6M EMA smoothing; cross-section ranking freshness diluted (acknowledge — not rationalize)",
    pit_leakage_status = "CLEAN",
    pit_c13_status = "PARTIAL (new factor not in Factor DB, dynamic expanding-IC sign used; explicit Z_Score_Aligned tag absent)",
    universe_v2_diag = list(
      l227_trigger = "ICIR_1M 0.110 < 0.15",
      v2_top500_freefloat_icir = univ$v2_top500_freefloat$icir,
      v2_improvement = round(univ$v2_top500_freefloat$icir - univ$v1_default$icir, 3),
      conclusion = univ$conclusion
    )
  ),

  alpha_discovery_count = 1L,
  selection_objective = "icir",
  alpha_inheritance_cor = ortho$cor_max_abs,

  challenge_flags = list(
    "RF_GRAD_RANKIC_FAIL: 1M rank_ic=0.0115 < graduation 0.04",
    "RF_GRAD_ICIR_FAIL: 1M ICIR=0.110 < graduation 0.20",
    "RF_GRAD_HARVEY_T_FAIL: 1M Harvey-t=1.219 < graduation 3.0",
    "RF_GRAD_HARVEY_T_FAIL_12M: 12M Harvey-t=1.754 < graduation 3.0 (Codex C2)",
    "RF-A4_POST_NEUTRAL_DEGRADE: sector-neutral IC=0.0001 << 0.5×raw 0.0115; signal mostly sector-level macro tilt (Codex C3)",
    "RF-A2_COMPOSITE_NO_IMPROVEMENT: composite ICIR 0.110 < best single ICIR 0.187 (Codex C4)",
    "RF-A1_SUBPERIOD_ICIR_STRICT_FAIL: 1/3 (only p3 ≥ 0.20) under strict ICIR criterion (Codex C5)",
    "WT_001_LESSON_AUTOCOR_HIGH: predictor lag-1 autocor 0.987 (cross-section ranking freshness diluted)",
    "DSR_FAT_TAIL_BOOTSTRAP: analytical 1.0 / bootstrap 0.0 (kurt 4.29) — bootstrap adopted (Codex C6)",
    "ORTHOGONALITY_PASS_PROXY: max |cor| 0.162 < 0.25 mandate; live STR_1715/TSMOM/KR_10y vector access TBD",
    "AX_008_INSUFFICIENT: Codex REJECT 1 / Architect 0 / Forge 0 → AX-008 2/3 fail",
    "GRADUATION_REJECT: 1M and 12M Harvey-t both fail; PG1 admission DENIED"
  ),

  method_shopping_log_ref = paste0("file://", file.path(OUT, "method_shopping_log.json")),
  method_shopping_summary = list(
    candidates_tried = 12L,
    top_K_per_period = 4L,
    avg_n_used = round(mean(fwd_dt$n_used, na.rm=TRUE), 2),
    n_periods = 160L,
    parallel_exec = FALSE,
    rolling_seconds = 64,
    rcpp_used = TRUE,
    rcpp_funcs = c("bootstrap_dsr_fast")
  ),

  pit_lineage = list(
    macro_shocks_extraction = "AR(1) expanding 36m burn-in residuals (Step 1)",
    beta_estimation = "24m rolling per-ticker per-macro OLS with mkt control (Step 3)",
    composite = "expanding |IC| top-4 selection + sign-aligned z-mean (Step 4)",
    smoothing = "6M EMA on per-month z (Step 4)",
    forward_alpha = "as_of=2026-04 using beta lagged 1 month (Step 6, 8)"
  ),

  graduation_summary = list(
    status = "REJECT_GRADUATION",
    rationale = paste0(
      "본 가설 (거시 잔차 → cross-section beta → cross-section alpha) 은 ",
      "primary 1M horizon에서 graduation criteria 명백히 미달 (rank_ic 0.0115 < 0.04, ",
      "ICIR 0.110 < 0.20, Harvey-t 1.219 < 3.0). 의도 horizon 12M에서도 ",
      "Harvey-t = 1.754 < 3.0 미달이므로 reframing 정당성 부재. ",
      "추가로 sector-neutral IC ~0 (RF-A4) → 신호의 대부분이 sector-level macro tilt로 ",
      "stock cross-section alpha 아님. composite ICIR 0.110 < single best 0.187 (RF-A2) → ",
      "composite no-improvement. AX-008 Triangulation 2/3 미달 (Codex REJECT). ",
      "PG1 admission 박탈 정합."
    ),
    fail_at_1m = c(
      "rank_ic 0.0115 < 0.04",
      "ICIR 0.110 < 0.20",
      "Harvey-t 1.219 < 3.0",
      "DSR_bootstrap 0.0 < 0.5"
    ),
    fail_at_12m = c(
      "Harvey-t 12M 1.754 < 3.0 (Codex C2)"
    ),
    additional_findings = c(
      "12M IC 0.04 = threshold (sub-period sign 3/3)",
      "12M ICIR 0.322 > 0.20 (sub-period strict 1/3)",
      "Decile monotonicity 0.564, D10-D1 SR 0.675 gross, t=2.08 (still < 3.0)",
      "Hybrid orthogonality max |cor| 0.162 < 0.25 (proxy)",
      "Universe v2 (TOP500 FREEFLOAT) ICIR 0.122 vs default 0.110 = +0.012 (insufficient)"
    ),
    archived_value = c(
      "Single-macro β alpha (KR_TermSpread |ICIR| 0.187) — future research",
      "PCA latent factor (Bryzgalova-Pelger-Zhu 2024) — future research",
      "IPCA conditional latent (Kelly-Pruitt-Su 2019) — future research",
      "Reclassify as sector overlay (Risk Agent ownership) — future research"
    ),
    rejection_basis = "graduation criteria not met across multiple horizons + sector-mediated signal + composite no-improvement; consistent with Codex REJECT stance"
  ),

  codex_critic_status = list(
    stance = "REJECT",
    response_file = "codex_critic_response_alpha.json",
    challenge_note_file = "challenge_note.md",
    concerns_total = 9,
    concerns_high = 4,
    concerns_medium = 5,
    accept_count = 6,
    partial_count = 2,
    rebuttal_count = 1,
    self_rationalization_phrases_corrected = 4,
    q_lead_escalate_recommended = TRUE,
    escalate_trigger = "HIGH severity ≥ 5 AND Codex REJECT stance + agent rebuttals limited"
  )
)

# Write final alpha_package.json (no _draft suffix; PreToolUse Hook will check critic_response presence)
write_json(alpha_pkg, file.path(WT_DIR, "alpha_package.json"),
           auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[09] alpha_package.json (FINAL post-Codex) saved at:\n  ",
    file.path(WT_DIR, "alpha_package.json"), "\n")

# Update alpha_validation.json with final state
val$graduation_status <- "REJECT_GRADUATION"
val$codex_stance <- "REJECT"
val$codex_concerns_total <- 9
val$codex_concerns_high <- 4
val$challenge_note_present <- TRUE
val$alpha_scores_timeseries_rows <- 53502
val$alpha_scores_n_sig_dates <- 160
val$alpha_scores_n_tickers <- 735
val$dsr_final_choice <- 0.0
val$dsr_final_method <- "bootstrap (fat-tail robust)"
val$harvey_t_strict_critical <- 2.891
val$pass_count <- 0L
val$fail_count <- 12L
write_json(val, file.path(OUT, "alpha_validation.json"),
           auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[09] alpha_validation.json updated\n")

# Final lineage record
lin_path <- file.path(PROJ, "02_Infrastructure", "worktask", "lineage_utils.R")
if (file.exists(lin_path)) {
  source(lin_path)
  tryCatch({
    record_package_lineage(
      task_id = WT_ID,
      package_type = "alpha_package",
      method_selected = "macro_residual_top4_composite_ema6m_FINAL_REJECT",
      input_file_paths = c(
        file.path(PROJ, ".cache/rawdata.parquet"),
        file.path(PROJ, ".cache/fred_macro_wide.parquet"),
        file.path(PROJ, ".cache/ecos_bond_rates.parquet"),
        file.path(PROJ, ".cache/ecos_krw_usd.parquet"),
        file.path(WT_DIR, "alpha_package_draft.json"),
        file.path(WT_DIR, "codex_critic_response_alpha.json"),
        file.path(WT_DIR, "challenge_note.md"),
        ts_ref
      )
    )
    cat("[09] lineage recorded for FINAL\n")
  }, error = function(e) {
    cat("[09] lineage skipped:", conditionMessage(e), "\n")
  })
}

cat("\n[09] === FINAL SUMMARY ===\n")
cat("  WT:", WT_ID, "\n")
cat("  graduation_status: REJECT_GRADUATION\n")
cat("  alpha_scores: 53502 rows × 160 sig_dates × 735 tickers (time-series)\n")
cat("  forward as_of:", format(max(fwd_dt$Date_eom)), "\n")
cat("  forward tickers:", length(alpha_vec), "\n")
cat("  Codex stance: REJECT (9 concerns)\n")
cat("  Q-Lead escalate: RECOMMENDED\n")
