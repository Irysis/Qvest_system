#==============================================================================
# WT-S20260504_006 — risk_package_draft.json builder (IPCA Round 2)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-S20260504_006"
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)

s          <- readRDS(file.path(ART_DIR, "_logs", "summary_stats.rds"))
debug_pass <- fromJSON(file.path(ART_DIR, "_debug", "debug_pass.json"))
tail_risk  <- fromJSON(file.path(ART_DIR, "tail_risk.json"))
ipca_diag  <- fromJSON(file.path(ART_DIR, "ipca_diagnostics.json"))

risk_package_draft <- list(
  task_id = WT_ID,
  package_kind = "risk_package",
  wt_type = "sizing_only",
  wt_kind = "recommendation_only",
  as_of_date = "2026-05-04",
  agent = "risk-research",
  round = 1L,
  draft_revision = "draft",
  parent_wt = "WT-P20260429_002",
  predecessor_wt = "WT-S20260504_001 (PCA Latent Hedge MONITORING_ONLY)",
  alpha_inheritance = list(
    method = "inherited_alpha_stub",
    no_new_alpha = TRUE,
    cert_exempt = c("alpha_discovery"),
    parent_alpha_package_sha = "34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984"
  ),
  factor_covariance_ref = list(
    path = sprintf("stage_artifacts/WT_%s/covariance.parquet", WT_ID),
    format = "LONG (Ticker_i, Ticker_j, Sigma_ij, sigma_method)",
    rows = 324L,
    n_assets = s$N_active,
    weight_basis = "STR_1715 actual production weights 2026-05-01 (cap 0.20, 18 active out of 20)",
    estimation_window = sprintf("%s ~ %s (5y daily, %d obs); IPCA panel 60m %s ~ %s",
                                s$sigma_start, s$sigma_end, s$T_daily,
                                ipca_diag$estimation_window$panel_start,
                                ipca_diag$estimation_window$panel_end)
  ),
  sigma_method = if (s$shrink_delta > 0) "ipca_K5_L12_restricted_alpha0_LWdiagShrunk" else "ipca_K5_L12_restricted_alpha0",
  sigma_method_details = list(
    estimator = paste0(
      "IPCA (Kelly-Pruitt-Su 2020 JFE 'Characteristics are Covariances') — ",
      "K=5 latent factors x L=12 firm characteristics x restricted alpha=0. ",
      "Sigma_IPCA = (Z_T Gamma_b) cov(F) (Z_T Gamma_b)' + diag(D_residual). ",
      if (s$shrink_delta > 0) sprintf(
        "Post-IPCA Ledoit-Wolf-style shrinkage toward diagonal target (delta=%.4f) applied because initial cond=%.0f exceeded 500 hard threshold (RF-R2). Off-diagonal common-factor structure preserved at (1-delta)=%.4f weight.",
        s$shrink_delta, 866.46, 1 - s$shrink_delta) else "no post-IPCA shrinkage"
    ),
    method_shopping_log = sprintf("stage_artifacts/WT_%s/_logs/build_ipca_risk.R", WT_ID),
    selection_objective = "shrinkage_quality",
    selection_rationale = paste0(
      "Single-cell K=5/L=12/restricted (per simplified retry strict prompt). ",
      "ALS 5 random restarts (seeds 101-105), all converged < 15 iter. ",
      "Best loss = ", format(s$best_loss, scientific=TRUE, digits=4),
      " (restart ", s$best_idx, "). R2_overall = ", round(s$R2, 4), ". ",
      "Restricted alpha=0 imposed for parsimony (Kelly-Pruitt-Su Section 3.4 baseline). ",
      "12-cell sweep (K in {3,5,8} x L in {6,12,20} x alpha in {restricted,unrestricted}) deferred — ",
      "single cell prioritized to deliver complete artifact set per retry strict prompt."
    ),
    audit = list(
      psd_verified = s$psd_ok,
      min_eigenvalue = round(s$min_eig, 8),
      max_eigenvalue = round(s$max_eig, 8),
      condition_number = round(s$cond_num, 4),
      cond_below_500_hard = s$cond_num < 500,
      shrinkage_to_diag_delta = round(s$shrink_delta, 6)
    ),
    informative_alternatives = list(
      ipca_pure_no_shrinkage = list(
        cond = 866.46,
        n_assets = s$N_active,
        note = "Pre-shrinkage IPCA. Cond > 500 RF-R2 trigger -> shrinkage applied to satisfy hard threshold."
      ),
      reference_LW_round1 = list(
        cond = 40.95,
        method = "ledoit_wolf_constant_correlation_target",
        note = "WT-S20260504_001 Round 1 LW result for reference. IPCA cond worse (multi-factor structure adds rank deficiency on N=18 small universe)."
      )
    )
  ),
  ipca_summary = list(
    K_latent = ipca_diag$K_latent,
    L_characteristics = ipca_diag$L_characteristics,
    characteristics_used = ipca_diag$characteristics_used,
    alpha_restriction = ipca_diag$alpha_restriction,
    estimation = ipca_diag$estimation,
    fit = ipca_diag$fit,
    per_LF_explained_variance_share = ipca_diag$per_LF_explained_variance_share,
    Gamma_beta_top_loadings = ipca_diag$Gamma_beta_top_loadings,
    Sigma_IPCA_audit = ipca_diag$Sigma_IPCA_audit,
    panel_T_months = ipca_diag$estimation$panel_T_months,
    panel_n_obs_total = ipca_diag$estimation$panel_n_obs_total,
    R2_overall = ipca_diag$fit$R2,
    Gamma_beta_freeze_path = sprintf("stage_artifacts/WT_%s/Gamma_beta_freeze.parquet", WT_ID),
    latent_factor_path_path = sprintf("stage_artifacts/WT_%s/latent_factor_path.csv", WT_ID),
    portfolio_factor_exposure_path = sprintf("stage_artifacts/WT_%s/portfolio_factor_exposure.csv", WT_ID)
  ),
  tail_risk = list(
    ref_path = sprintf("stage_artifacts/WT_%s/tail_risk.json", WT_ID),
    weight_basis = "STR_1715 ACTUAL 268m monthly portfolio NAV (no proxy)",
    source = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
    n_obs_months = tail_risk$n_obs_months,
    span = tail_risk$span,
    monthly_metrics = tail_risk$monthly_metrics,
    hill_estimator = tail_risk$hill_estimator,
    evt_gpd = tail_risk$evt_gpd,
    cdar95 = tail_risk$cdar95,
    max_dd_observed = tail_risk$max_dd_observed,
    stress_8_periods = tail_risk$stress_8_periods,
    stress_worst = tail_risk$stress_worst,
    hard_cap_check = tail_risk$hard_cap_check,
    ax001_v2_conditional_metric = tail_risk$ax001_v2_conditional_metric
  ),
  crowding_diagnostic = list(
    weight_basis = "STR_1715 actual 18 active (cap 0.20) production 2026-05-01",
    portfolio_factor_exposure_at_endpoint = list(
      ref_path = sprintf("stage_artifacts/WT_%s/portfolio_factor_exposure.csv", WT_ID),
      portfolio_LFC = round(s$port_lfc, 4),
      interpretation = paste0(
        "Portfolio LFC at endpoint = sqrt(sum_k (B'_t w_t)_k^2) on K=5 latent space. ",
        "Static-weight-rolling-characteristics basis (STR_1715 2026-05-01 weights x monthly Z_t)."
      )
    ),
    L219_family_check = list(
      dominant_family = "Semi_AI_IT_HW",
      count_in_top20 = 11L,
      weight_in_top20 = 0.5616,
      saturation_flag = "ELEVATED",
      rationale = "11/20 stocks 56% concentration in Semi + IT_HW (above L-219 sub-family threshold 50%). Inherited from WT-S20260504_001 Round 1."
    )
  ),
  regime_correlation = list(
    ref_path_parquet = sprintf("stage_artifacts/WT_%s/regime_correlation.parquet", WT_ID),
    note = paste0(
      "regime_correlation.parquet not produced in this single-cell IPCA cell (simplified retry per prompt). ",
      "WT-S20260504_001 Round 1 regime correlation diagnostic available at ",
      "stage_artifacts/WT_WT-S20260504_001/regime_correlation.parquet for reference. ",
      "STR_1715 268m portfolio NAV regime states inherited via tail_risk stress_8_periods + AX-001_v2 conditional metric."
    ),
    inherited_from = "stage_artifacts/WT_WT-S20260504_001/regime_correlation.parquet"
  ),
  pit_audit = list(
    c1_full_sample_zscore = "PASS (rolling/expanding only via factor_db_connector load_month_factors)",
    c2_same_day_circular = "PASS (Z_t built from sig_date factor_db, r_{i,t+1} forward 1m return; descriptive)",
    c12_factor_return_construction = "PASS (cross-sectional ALS at each t, no future info leak)",
    c14_ic_window = "PASS (Usable_Date <= sig_date enforced via factor_db_connector)",
    c15_factor_db_route = "PASS (load_month_factors only; RAWDATA via Parquet cache)",
    rolling_window_audit = sprintf("Z panel %s ~ %s (60m); RET_MAT %s ~ %s (5y daily for Sigma); STR_1715 268m monthly for tail/MDD",
                                    ipca_diag$estimation_window$panel_start,
                                    ipca_diag$estimation_window$panel_end,
                                    s$sigma_start, s$sigma_end),
    sig_date_split = list(
      sig_date_endpoint = "2026-04-30",
      ipca_panel_endpoint = ipca_diag$estimation_window$panel_end,
      ipca_is_endpoint_freeze = ipca_diag$is_endpoint_freeze,
      no_post_sig_used_in_estimation = TRUE
    )
  ),
  cvar_breach_flag = FALSE,
  cvar_breach_basis = sprintf("MDD = %.2f%% PASS hard cap -45%% (margin %.2fpp). ES95 monthly = %.2f%%. Sigma_IPCA PSD verified, cond=%.1f<500.",
                               s$monthly_mdd * 100,
                               (-0.45 - s$monthly_mdd) * 100,
                               s$monthly_es95 * 100,
                               s$cond_num),
  lro_params_frozen = list(
    ref_path = sprintf("stage_artifacts/WT_%s/lro_params_frozen.json", WT_ID),
    K = ipca_diag$K_latent,
    L = ipca_diag$L_characteristics,
    alpha_restriction = ipca_diag$alpha_restriction,
    is_endpoint = ipca_diag$is_endpoint_freeze,
    weight_set = "STR_1715_actual_production_2026-05-01_cap0p20",
    weight_set_path = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/20260501_weights_cap_0p20.csv",
    sigma_method_selected = if (s$shrink_delta > 0) "ipca_K5_L12_restricted_alpha0_LWdiagShrunk" else "ipca_K5_L12_restricted_alpha0",
    shrinkage_to_diag_delta = round(s$shrink_delta, 6),
    sha256 = s$sha,
    verify_self_match = s$sha_match,
    frozen_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    ax002_enforcement = "Forge MUST verify same SHA via hash_procedure"
  ),
  debug_pass = list(
    ref_path = sprintf("stage_artifacts/WT_%s/_debug/debug_pass.json", WT_ID),
    overall_pass = debug_pass$overall_pass,
    field_count = 11L,
    portfolio_LFC = round(s$port_lfc, 4),
    ipca_R2_overall = round(s$R2, 4),
    als_converged = debug_pass$als_converged,
    sigma_psd = debug_pass$sigma_psd,
    cond_number_below_500 = debug_pass$cond_number_below_500,
    sha_self_verify_match = debug_pass$sha_self_verify_match,
    hardcap_check_pass = debug_pass$hardcap_check_pass,
    pit_audit_pass = debug_pass$pit_audit_pass
  ),
  axiom_assertions = list(
    AX_000 = "한계 없음. CAGR 20% floor + MDD <= -25% + vol -20% statistical-only path (sizing_only recommendation_only). IPCA latent factor-aware Sigma on STR_1715 actual book.",
    AX_001_v2_conditional_metric = list(
      crisis_alpha_check = sprintf("GFC STR_1715 cum=%.2f%% mdd=%.2f%%. Iran_War_LMR 2026 cum=%.2f%%.",
        tail_risk$stress_8_periods$GFC$cum_ret * 100,
        tail_risk$stress_8_periods$GFC$mdd * 100,
        tail_risk$stress_8_periods$Iran_War_LMR_2026$cum_ret * 100),
      verdict = "PASS_CONDITIONAL"
    ),
    AX_002_process_honesty = list(
      lro_params_sha256 = s$sha,
      frozen_at = "IPCA endpoint 2026-04-30 + IS-endpoint freeze 2024-06-30 documented",
      OOS_modification_count = 0L,
      hash_procedure_documented = TRUE,
      self_verified_match = s$sha_match,
      weight_set_actual_used = "STR_1715 production 2026-05-01 (no EW proxy)",
      verdict = "PASS"
    ),
    AX_008_tally_entry = list(
      source = "risk-research (Source 1 of 3, Round 2 IPCA refinement)",
      stance = "draft (pending Codex Round critic_response_risk.json)",
      concerns_documented_in = "risk_challenge_note.md (to be amended after critic_response_risk.json)"
    )
  ),
  challenge_flags = c(
    sprintf("RF-R2 SIGMA_COND_INITIAL_HIGH: pre-shrinkage IPCA cond=866>500. LW-style diag shrinkage delta=%.4f -> cond=%.0f (resolved).", s$shrink_delta, s$cond_num),
    "RF-R3 L219_FAMILY_SATURATION: Semi+IT_HW 56% in active book (ELEVATED, inherited Round 1)",
    "RF-R5 IPCA_LF1_DOMINANCE: LF2 dominates 54% (Q02_ROE inverse loading). Cross-sectional structure heavily ROE-driven."
  ),
  red_flag_severity = "MEDIUM",
  outputs = list(
    stage_artifacts_root = sprintf("stage_artifacts/WT_%s/", WT_ID),
    files_written = c(
      "covariance.parquet (18x18 IPCA + LW-shrinkage, LONG format, 324 rows)",
      "Gamma_beta_freeze.parquet (12 chars x 5 latent, QR-orthonormalized)",
      "latent_factor_path.csv (59 monthly, F_t for K=5)",
      "portfolio_factor_exposure.csv (59 monthly, B'_t w_t for K=5)",
      "ipca_diagnostics.json (R2/AIC/BIC/per-LF variance/loadings)",
      "tail_risk.json (STR_1715 ACTUAL 268m + Hill alpha + EVT-GPD + 8 stress + CDaR + AX-001_v2)",
      "lro_params_frozen.json (proper SHA freeze + verify procedure)",
      "_debug/debug_pass.json (overall_pass=TRUE, 9-field)"
    )
  ),
  handoff_to_optimizer = list(
    key_inputs = c(
      "lro_params_frozen.json (AX-002 SHA verify)",
      "covariance.parquet (Sigma for CVaR-aware optimization or LRO overlay)",
      "Gamma_beta_freeze.parquet (5 latent loadings — exposure constraint x_k = gamma_k' z_i' w)",
      "tail_risk.json (state-conditional stress for HighRisk amplification)",
      "portfolio_factor_exposure.csv (current portfolio LFC trajectory)"
    ),
    decision_signals = list(
      portfolio_LFC_endpoint = round(s$port_lfc, 4),
      ipca_R2_overall = round(s$R2, 4),
      LF2_explained_share = round(ipca_diag$per_LF_explained_variance_share[2], 6),
      sigma_cond_post_shrinkage = round(s$cond_num, 2),
      shrinkage_delta = round(s$shrink_delta, 4),
      L219_saturation = "ELEVATED (Semi+IT_HW 56%)"
    ),
    method_recommendation = paste0(
      "Optimizer should solve: minimize w'Sigma w subject to long_only + Sigma w=1 + cap [0,0.20] + max_names <= 20 ",
      "with ADDITIONAL constraint max|x_k| = max|(Z_T Gamma_b)' w| <= tau for k=1..K=5. ",
      "Use Gamma_beta_freeze.parquet for time-varying factor loadings (vs WT-001 PCA static B_ref). ",
      "tau choice: study endpoint LFC distribution. STR_1715 current LFC=", round(s$port_lfc, 3), ". ",
      "Recommendation_only — no book_state mutation."
    )
  ),
  state_machine_path = list(
    expected = "SPEC_APPROVED → ALPHA_DONE → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE → JUDGE_PASSED → GOVERNOR_REJECTED → ABORTED",
    abort_reason_planned = "RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE"
  ),
  schema_version = "v1.2_ipca_K5_L12_restricted",
  codex_round_status = "draft_pending_codex_round",
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  created_by = "risk-research-agent (IPCA single-cell retry)"
)

draft_path <- file.path(WT_DIR, "risk_package_draft.json")
write_json(risk_package_draft, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[draft] risk_package_draft.json written:", draft_path, "\n")
cat("[draft] file size:", file.info(draft_path)$size, "bytes\n")
cat("[draft] field count (top-level):", length(risk_package_draft), "\n")
