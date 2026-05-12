#==============================================================================
# WT-D20260508_003 — Finalize alpha_package_draft.json
#
# Add: ml_comparison results + empirical_disposition (DISCOVERY_FAIL_HONEST)
#      + lockbox separate metric + crisis anti-hedge summary
# Then: trigger Codex Critic Round (5-step flow obligatory)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_003"
WT_DIR <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260508_003")

cat("=== Finalizing alpha_package_draft.json ===\n")

# Load existing draft
draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)

# Load ML results
ml_results <- fromJSON(file.path(STAGE_DIR, "ml_comparison_results.json"), simplifyVector = FALSE)

# Load DSR
dsr_results <- fromJSON(file.path(STAGE_DIR, "dsr_strict_bailey_ldp.json"), simplifyVector = FALSE)

# Load crisis
crisis_results <- fromJSON(file.path(STAGE_DIR, "crisis_anti_hedge_diagnosis.json"), simplifyVector = FALSE)

# Load autocor
autocor_results <- fromJSON(file.path(STAGE_DIR, "predictor_autocor_diagnosis.json"), simplifyVector = FALSE)

# Load alpha_validation
alpha_val <- fromJSON(file.path(STAGE_DIR, "alpha_validation.json"), simplifyVector = FALSE)

# ─── Add ml_comparison block ─────────────────────────────────────────────
draft$ml_comparison <- list(
  methods_tested = c("XGBoost_GPU_hist_CUDA", "XGBoost_CPU_hist", "OLS_Fama_MacBeth_baseline"),
  validation_period = "2015-01 ~ 2019-12",
  data_split_policy = "R2 Window Isolation HARD: lockbox 2020~2026.04 NOT used for selection",

  xgboost_gpu_validation_ic = ml_results$xgboost_gpu$validation_mean_monthly_ic,
  xgboost_gpu_validation_icir = ml_results$xgboost_gpu$validation_icir,
  xgboost_gpu_pos_pred_pct_validation = ml_results$xgboost_gpu$validation_pos_pred_pct,
  xgboost_gpu_naive_long_bias_validation = ml_results$xgboost_gpu$validation_naive_long_bias_detected,
  xgboost_gpu_lockbox_pos_pred_pct = ml_results$xgboost_gpu$lockbox_pos_pred_pct,

  fama_macbeth_validation_ic = ml_results$fama_macbeth_baseline$validation_mean_monthly_ic,
  fama_macbeth_validation_icir = ml_results$fama_macbeth_baseline$validation_icir,

  ml_vs_classical_winner = ml_results$ml_vs_classical$winner,
  ml_vs_classical_verdict = ml_results$ml_vs_classical$verdict,

  time_series_cv_mean_ic = ml_results$time_series_cv$mean_pooled_ic,
  time_series_cv_std_ic = ml_results$time_series_cv$std_pooled_ic,
  time_series_cv_stability = ml_results$time_series_cv$stability_assessment,

  wt_001_naive_long_bias_redetection = ml_results$wt_001_trap_redetection$trap_status,
  wt_001_feature_leakage_redetection = "OK_NO_TARGET_LEAKAGE_DETECTED (0/9 features at risk)",

  gpu_speedup_factor = 1.3,
  gpu_speedup_note = "Panel size moderate (80K rows / 9 features); GPU advantage minimal but verified hardware ready"
)

# ─── Add classical_baseline (R4 P3 selection objective check) ──────────
draft$classical_baseline <- list(
  method = "OLS_Fama_MacBeth_per_month_cross_section",
  validation_ic = ml_results$fama_macbeth_baseline$validation_mean_monthly_ic,
  validation_icir = ml_results$fama_macbeth_baseline$validation_icir,
  fm_avg_coefs = ml_results$fama_macbeth_baseline$fm_avg_coefs,
  fm_feature_names = ml_results$fama_macbeth_baseline$fm_feature_names,
  interpretation = "Fama-MacBeth marginally beats XGBoost CUDA on validation IC (0.025 vs -0.008), but both fail 0.04 graduation hurdle. Classical baseline simpler + interpretable but does not unlock alpha."
)

# ─── Add naive_baseline (predict mean = naive long benchmark) ────────────
draft$naive_baseline <- list(
  method = "naive_long_only_top_decile_alpha_F5",
  description = "Universe top decile by alpha_F5 (equal-weight), monthly rebal, 15bps cost",
  sr_long_only_top_decile = dsr_results$factors$alpha_F5$sr_long_only_top_decile,
  context = "If alpha_F5 has any cross-sectional differentiation, top decile should outperform bottom decile."
)

# ─── DSR strict block ────────────────────────────────────────────────────
draft$dsr_strict <- list(
  method = "Bailey-Lopez_de_Prado_2014_DSR_with_skew_kurt_correction",
  n_trials = 5L,
  trial_count_rationale = "4 sub-variants (BKM/CW/BTZ/BCI) + 1 composite (F5) = 5 trials",
  per_factor_dsr_z = lapply(c("alpha_BKM_sn", "alpha_CW_sn", "alpha_BTZ_sn", "alpha_BCI_sn", "alpha_F5"), function(fc) {
    list(factor = fc,
         dsr_z = dsr_results$factors[[fc]]$dsr_bailey_ldp_z,
         dsr_pass = dsr_results$factors[[fc]]$dsr_pass)
  }),
  all_pass = FALSE,
  rationale = "All 5 factors fail Bailey-LdP DSR (z all negative). Multi-trial haircut amplifies the negative SR."
)

# ─── Subperiod stability detail ─────────────────────────────────────────
draft$subperiod_breakdown_headline <- alpha_val$alpha_F5$subperiod_breakdown
draft$lockbox_separate_metric_alpha_F5 <- list(
  rank_ic = alpha_val$alpha_F5$lockbox_rank_ic,
  icir = alpha_val$alpha_F5$lockbox_icir,
  n_months = alpha_val$alpha_F5$lockbox_n_months,
  policy = "R2 Window Isolation HARD: separate report only, NOT used for selection"
)

# ─── Crisis anti-hedge summary ──────────────────────────────────────────
draft$crisis_anti_hedge_summary <- list(
  diagnosis = "WT_001 cycle 7 finding: cor(VRP, AR)=+0.6438 in CRISIS regime → anti-hedge. Re-tested at stock-level cross-section.",
  finding = "Stock-level cross-section LS-BM cor in crisis regime is small (0.027~0.095) — anti-hedge NOT severe at stock level.",
  per_factor_LS_BM_crisis_cor = lapply(c("alpha_BKM_sn", "alpha_CW_sn", "alpha_BTZ_sn", "alpha_BCI_sn", "alpha_F5"), function(fc) {
    list(factor = fc, cor_LS_BM_crisis = crisis_results$factors[[fc]]$cor_LS_BM_crisis,
         cor_LS_BM_normal = crisis_results$factors[[fc]]$cor_LS_BM_normal)
  }),
  caveat_vs_wt_001_difference = "WT_001 cycle 7 measured cor(VRP_signal_timeseries, AR_portfolio_returns) — portfolio-level. Current measurement is cor(LS_decile_spread, KOSPI_BM_Ret) per regime — stock-level. Different objects: VRP-level anti-hedge does NOT directly transfer to stock-level cross-section."
)

# ─── Empirical disposition (DISCOVERY_FAIL_HONEST) ─────────────────────
draft$empirical_disposition <- list(
  status = "DISCOVERY_FAIL_HONEST_VRP_VOLBETA_CROSS_SECTION_INSUFFICIENT_DIFFERENTIATION",
  rationale = paste(
    "All 5 factor specs fail graduation_criteria thresholds:",
    "rank_IC_IS=0.014~0.014 < 0.04 hurdle (FAIL all 5);",
    "ICIR_IS=0.135~0.158 < 0.20 Alpha Lab Gate (FAIL all 5);",
    "Harvey-NW t=1.4~1.6 < 3.0 multi-testing (FAIL all 5);",
    "Bailey-LdP DSR z all negative (FAIL all 5);",
    "harvey_t_specs_pass_count=0/5 (alpha_discovery_certificate insufficient).",
    sep = " "
  ),
  honest_empirical_observations = list(
    "VRP 4 sub-variants are portfolio-level 1D timeseries by construction. Stock-level vol-beta cross-section inherits VRP's strong autocorrelation (β autocor 0.948~0.955 vs WT_001 portfolio-level 0.404 — 2.4x stronger).",
    "Stock-level cross-section variance from vol-beta is dominated by size/sector/market-β collinearity, not VRP-specific differentiation.",
    "Fama-MacBeth (validation IC 0.025) marginally beats XGBoost CUDA (validation IC -0.008), but both fail 0.04 hurdle.",
    "XGBoost validation pos_pred_pct 99.5% = naive long bias (WT_001 v3 trap re-detected — feature signal-to-noise too low for ML uplift).",
    "TimeSeriesCV mean IC -0.0052 (cross-validated negative) = no robust generalization.",
    "Crisis anti-hedge (WT_001 cycle 7 portfolio-level concern) NOT severe at stock-level cross-section (LS-BM cor 0.027~0.095).",
    "alpha_F5 composite ICIR 0.159 is the best of 5 but still fails 0.20 gate. Equal-weight ensemble does not rescue weak parents."
  ),
  why_path_failed_honest = paste(
    "Variance Risk Premium is fundamentally a PORTFOLIO-LEVEL signal (vol seller earns premium from holding the entire vol surface).",
    "Stock-level vol-beta cross-section attempts to differentiate per-name VRP exposure but struggles because:",
    "(a) 36m rolling β is too slow-moving (autocor 0.95) — signal is mostly persistent noise;",
    "(b) Per-stock vol-beta is dominated by market-β / size-β collinearity, not VRP-specific exposure;",
    "(c) KOSPI options chain absent → KR VRP proxy via VIX (cor 0.505) limits idiosyncratic differentiation;",
    "(d) The economic mechanism (option seller earns premium) does NOT naturally transfer to long-only equity cross-section.",
    "This is consistent with academic VRP literature: VRP is harvested via DERIVATIVE positions (variance swaps, delta-hedged options), not via stock-level long-only portfolios.",
    sep = " "
  ),
  graduation_proper_check = list(
    rank_ic_pass = FALSE,
    icir_pass = FALSE,
    harvey_t_pass = FALSE,
    dsr_pass = FALSE,
    sub_stab_pass = TRUE,  # 0.67 > 0.5 (sign-aware would care about IC sign — F5 has 2/3 positive)
    overall_pass = FALSE,
    operational_alpha_test_pass = FALSE,
    naive_dominates = TRUE  # naive top-decile SR_LO 0.137 > LS SR -0.030
  ),
  alpha_discovery_certificate_eligibility = list(
    factor_specs_count = 5L,
    factor_specs_min = 1L,
    factor_specs_pass = TRUE,
    alpha_inheritance_cor = 0.0,
    alpha_inheritance_max = 0.95,
    alpha_inheritance_pass = TRUE,
    mechanism_citation_chars_min = 50L,
    mechanism_citation_pass = TRUE,
    harvey_t_specs_pass_count = 0L,
    harvey_t_specs_pass_min = 3L,
    harvey_t_specs_pass = FALSE,
    overall_certificate_eligible = FALSE,
    rationale = "alpha_discovery_certificate INSUFFICIENT: harvey_t_specs_pass_count=0 < min=3. PG1 admission auto-deny."
  )
)

# ─── Next step recommendations (post-FAIL) ─────────────────────────────
draft$next_step_recommendations <- list(
  primary_recommendation = "VRP 4 sub-variants stock-level vol-beta cross-section path TERMINATE (DISCOVERY FAIL).",
  alternative_paths = list(
    "Path-A: VRP regime-conditional × existing KR factor cross-section (e.g., Q07 Earnings_Stability × VRP regime gating). However this risks alpha-research scope overlap (regime gating is risk/optimizer territory). Q-Lead decision required.",
    "Path-B: VRP as PORTFOLIO OVERLAY only (cycle 3 multi-source sleeve add path: +5VRP DR=1.307 / SR=1.997). This is OPTIMIZER ROLE, not alpha-research. Deferred to optimizer-research pending source discovery.",
    "Path-C: Direct KOSPI200 options chain integration — KRX OpenAPI infrastructure mandate. Multi-month infra investment. Then BKM/CW computable directly from KR options without VIX proxy.",
    "Path-D: Vol-of-vol cross-section (separate factor zoo) — different mechanism, would require new WT_004."
  ),
  immediate_q_lead_decision = "Recommend wt_advance to FAIL_TERMINAL OR escalate to architect for VRP role redefinition (alpha vs overlay).",
  axiom_implication = "AX-005 v1.2 (KR defense single-sleeve fail) generalizes to VRP single-sleeve fail at stock-level. AX-007 (single overlay ticker mechanism break) reinforced — VRP cross-section requires multi-sleeve OR derivative position, not equity long-only top-N."
)

# ─── pipeline_stage update ─────────────────────────────────────────────
draft$pipeline_stage <- "alpha_research_draft_codex_round_pending"

# ─── Write enriched draft ──────────────────────────────────────────────
write_json(draft, file.path(WT_DIR, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("Enriched alpha_package_draft.json written.\n")
cat(sprintf("File size: %d bytes\n", file.size(file.path(WT_DIR, "alpha_package_draft.json"))))

cat("\nSummary:\n")
cat(sprintf("  empirical_disposition.status: %s\n", draft$empirical_disposition$status))
cat(sprintf("  graduation_proper_check.overall_pass: %s\n", draft$empirical_disposition$graduation_proper_check$overall_pass))
cat(sprintf("  alpha_discovery_certificate_eligible: %s\n", draft$empirical_disposition$alpha_discovery_certificate_eligibility$overall_certificate_eligible))
cat(sprintf("  challenge_flags count: %d\n", length(draft$challenge_flags)))
cat(sprintf("  next: Codex Critic Round trigger\n"))
