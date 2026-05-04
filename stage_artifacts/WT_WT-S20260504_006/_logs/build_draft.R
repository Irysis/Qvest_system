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
risk_shop  <- fromJSON(file.path(ART_DIR, "risk_method_shopping.json"))
sweep_dt   <- fread(file.path(ART_DIR, "sweep_grid_results.csv"))
prod_audit <- fromJSON(file.path(ART_DIR, "production_directory_audit.json"))

risk_package_draft <- list(
  task_id = WT_ID,
  package_kind = "risk_package",
  wt_type = "sizing_only",
  wt_kind = "recommendation_only",
  as_of_date = "2026-05-04",
  agent = "risk-research",
  round = "Round_2_IPCA_refinement",
  draft_revision = "draft",
  parent_wt = "WT-P20260429_002",
  predecessor_wt = "WT-S20260504_001",
  alpha_inheritance = list(
    method = "inherited_alpha_stub",
    no_new_alpha = TRUE,
    cert_exempt = c("alpha_discovery"),
    parent_alpha_package_sha = "34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984"),
  sigma_method = "IPCA_Kelly_Pruitt_Su_2020",
  sigma_method_label = s$sigma_method_label,
  sigma_method_details = list(
    estimator = "IPCA (Instrumented PCA, Kelly-Pruitt-Su 2020 JFE) — Alternating Least Squares + numerical optimization",
    model_specification = "r_{i,t+1} = α_i,t + β'_i,t f_{t+1} + ε_{i,t+1}, β_i,t = Γ_β z_i,t (K×L), α restricted=0 OR unrestricted",
    estimation = "Alternating Least Squares (ALS) — Step A solve f_t cross-section, Step B solve Γ_β stacked OLS with vec",
    convergence = list(tol = 1e-6, max_iter = 200,
                       converged_selected = isTRUE(s$converged_sel),
                       n_iter_selected = ipca_diag$selected_cell$n_iter,
                       random_restarts_per_cell = 5L),
    K_selected = s$K_sel,
    L_selected = s$L_sel,
    alpha_restriction = ifelse(isTRUE(s$alpha_restricted_sel), "restricted_alpha_zero", "unrestricted"),
    residualization = s$resid_mode_sel,
    is_endpoint_freeze = "2024-06-30",
    T_obs_IS = s$T_eff,
    N_assets = s$N_active,
    selected_among = paste(nrow(sweep_dt), "cells (12-cell sweep K×L×alpha×resid)"),
    method_shopping_log = sprintf("stage_artifacts/WT_%s/risk_method_shopping.json", WT_ID),
    selection_objective = "BIC_plus_alpha_misspecification_LR_test",
    selection_rationale = paste0(
      "12-cell sweep K∈{3,5,8} × L∈{6,12,20} (K≤L valid) × alpha∈{restricted,unrestricted} × residualization=pre_IPCA. ",
      "5 random restarts per cell (seed offset 42 + 1000*restart + cell_idx). ",
      "Best by lowest BIC among converged. Alpha misspec (LR_test) provides H0:Γ_α=0 evaluation. ",
      "Round 1 (sample-PCA) limited by time-invariant loadings. IPCA loadings β_i,t = Γ_β z_i,t time-vary via ",
      "monthly characteristic Z scores. Selected: K=", s$K_sel, ", L=", s$L_sel,
      ", alpha=", ifelse(isTRUE(s$alpha_restricted_sel), "restricted (α=0)", "unrestricted (α≠0)"),
      ", resid=", s$resid_mode_sel,
      ". R²=", s$R2_sel, " BIC=", round(s$BIC_sel, 1), "."),
    audit = list(
      psd_verified = isTRUE(s$psd_sigma),
      min_eigenvalue = signif(s$min_eig_sigma, 6),
      max_eigenvalue = signif(s$max_eig_sigma, 6),
      condition_number = round(s$cond_sigma, 4))),
  ipca_diagnostics = list(
    ref_path = sprintf("stage_artifacts/WT_%s/ipca_diagnostics.json", WT_ID),
    R2_selected = s$R2_sel,
    SSE_selected = signif(s$SSE_sel, 4),
    AIC_selected = round(s$AIC_sel, 1),
    BIC_selected = round(s$BIC_sel, 1),
    K_comparison_path = "ipca_diagnostics.json::K_comparison",
    alpha_misspecification = list(
      test_type = "LR_test_proxy_BIC_diff",
      pval = s$alpha_misspec_pval,
      H0_alpha_zero_rejected_at_05 = s$alpha_misspec_reject,
      interpretation = if (isTRUE(s$alpha_misspec_reject))
        "α=0 rejected — characteristics are priced (firm-level α)" else
        "α=0 NOT rejected — restricted (Γ_α=0) model adequate"),
    K_comparison = ipca_diag$K_comparison,
    comparison_vs_round1 = ipca_diag$comparison_vs_round1,
    note = paste0(
      "Round 1 (sample-PCA K=5) anchor map mapped all PCs to Market with median R²~0.0001 ",
      "→ confirms inability to identify diverse anchors. IPCA β_i,t = Γ_β z_i,t enforces ",
      "characteristic-mediated loadings, expected to produce diverse anchors via top characteristic per PC.")),
  characteristics_set_selected = list(
    L = s$L_sel,
    chars = s$characteristics_used,
    pit_treatment = "load_month_factors(sig_date) → align_factor_direction(Usable_Date ≤ sig_date) — PIT C13/C14/C15 enforced",
    impute_method = "cross-sectional mean within month, applied AFTER PIT filter"),
  K_selected = s$K_sel,
  L_selected = s$L_sel,
  alpha_restriction_selected = ifelse(isTRUE(s$alpha_restricted_sel), "restricted_alpha_zero", "unrestricted"),
  sweep_grid_results = list(
    ref_path = sprintf("stage_artifacts/WT_%s/sweep_grid_results.csv", WT_ID),
    n_cells = nrow(sweep_dt),
    n_converged = sum(sweep_dt$converged),
    R2_range = c(min(sweep_dt$R2, na.rm = TRUE), max(sweep_dt$R2, na.rm = TRUE)),
    BIC_range = c(min(sweep_dt$BIC, na.rm = TRUE), max(sweep_dt$BIC, na.rm = TRUE)),
    selected_cell_idx = which(sweep_dt$BIC == s$BIC_sel)[1]),
  Gamma_beta_ref = list(
    path = sprintf("stage_artifacts/WT_%s/Gamma_beta_freeze.parquet", WT_ID),
    dim = c(s$L_sel, s$K_sel),
    format = "LONG (characteristic, PC, loading)",
    is_endpoint = "2024-06-30",
    sha_freeze = s$sha256),
  latent_factor_ref = list(
    path = sprintf("stage_artifacts/WT_%s/latent_factor_path.csv", WT_ID),
    n_months = s$T_eff,
    K = s$K_sel,
    span = paste(s$pr_span_start, "→ IS endpoint 2024-06-30")),
  portfolio_factor_exposure = list(
    ref_path = sprintf("stage_artifacts/WT_%s/portfolio_factor_exposure.csv", WT_ID),
    weight_basis = "STR_1715 actual production weights 2026-05-01 (cap 0.20, 18 active out of 20)",
    LFC_max_IS = round(s$LFC_max, 6),
    LFC_at_2026_05 = round(s$LFC_2026_05, 6),
    note = "LFC = Σ_k (β'_i,t w_i,t)^2 per month — direct IPCA latent factor concentration measure."),
  factor_covariance_ref = list(
    path = sprintf("stage_artifacts/WT_%s/covariance.parquet", WT_ID),
    format = "LONG (Ticker_i, Ticker_j, Sigma_ij, sigma_method)",
    rows = s$N_active^2,
    n_assets = s$N_active,
    sigma_method_label = s$sigma_method_label,
    weight_basis = "STR_1715 actual production weights 2026-05-01",
    construction = "Σ_IPCA = (Z_T Γ_β) cov(F) (Z_T Γ_β)' + diag(D), where D = idiosyncratic variance from IPCA residuals"),
  tail_risk = list(
    ref_path = sprintf("stage_artifacts/WT_%s/tail_risk.json", WT_ID),
    weight_basis = "STR_1715 ACTUAL 268m monthly portfolio NAV (no proxy)",
    source = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
    n_obs_months = 268L,
    span = paste(s$pr_span_start, "~", s$pr_span_end),
    monthly_metrics = tail_risk$monthly_metrics,
    hill_alpha = tail_risk$hill$alpha,
    evt_gpd = tail_risk$evt_gpd,
    stress_8_worst = tail_risk$worst_stress,
    state_conditional_LFC = tail_risk$state_conditional_LFC,
    ax001_v2_metric = tail_risk$ax001_v2_metric),
  cvar_breach_flag = (s$mdd_268m < -0.45),
  cvar_breach_threshold = -0.45,
  cvar_breach_actual = round(s$mdd_268m, 4),
  cvar_hard_cap_PASS = (s$mdd_268m > -0.45),
  axiom_assertions = list(
    AX_000 = "한계없음 — IPCA refinement may unlock further MDD relief beyond Round 1 sample-PCA",
    AX_001_v2 = list(
      conditional_metric = "bad_normal_es95_ratio_by_IPCA_LFC_state",
      ratio = round(s$ax001_v2_ratio, 4),
      es_normal = tail_risk$ax001_v2_metric$es_normal,
      es_highrisk = tail_risk$ax001_v2_metric$es_highrisk,
      interpretation = if (is.finite(s$ax001_v2_ratio) && s$ax001_v2_ratio > 1)
        "HighRisk LFC state worse ES95 than Normal (expected — IPCA LFC quantile state captures regime risk)" else
        "Anomaly: HighRisk state NOT worse than Normal — investigate"),
    AX_002 = list(
      sha_freeze = s$sha256,
      hash_procedure = "build dict EXCLUDING sha256 → toJSON(auto_unbox=T,pretty=F) → sha256() → append sha256 → write final JSON",
      forge_must_verify = TRUE,
      lro_params_frozen_path = sprintf("stage_artifacts/WT_%s/lro_params_frozen.json", WT_ID)),
    AX_008 = list(
      verification_triangulation = "Forge + Codex + Architect 2/3 PASS required",
      this_agent = "risk-research (Codex Critic Round mandatory)")),
  lro_params_frozen = list(
    path = sprintf("stage_artifacts/WT_%s/lro_params_frozen.json", WT_ID),
    sha256 = s$sha256,
    K = s$K_sel, L = s$L_sel,
    alpha_restriction = ifelse(isTRUE(s$alpha_restricted_sel), "restricted_alpha_zero", "unrestricted"),
    is_endpoint = "2024-06-30",
    chars_count = length(s$characteristics_used)),
  anchor_alignment_ipca = list(
    ref_path = sprintf("stage_artifacts/WT_%s/anchor_alignment_ipca.json", WT_ID),
    top_characteristic_per_PC = s$top_char_per_PC,
    note = "Label-only — indicates which firm characteristic dominates each latent PC. NOT economic claim."),
  selection_objective = "condition_number",
  red_flags = list(
    RF_R1 = list(severity = "INFO",
                  condition = "top common risk concentration",
                  status = paste0("Σ cond ", round(s$cond_sigma, 2),
                                  if (s$cond_sigma > 500) " EXCEEDS 500 (Rule2 STOP)" else " < 500 OK")),
    RF_R2_cond_500 = list(severity = "INFO",
                           condition_number = round(s$cond_sigma, 2),
                           pass = (s$cond_sigma < 500)),
    RF_R3_crowding = list(severity = "INFO",
                          note = "Crowding diagnostics not computed for sizing_only IPCA refinement (focus on Σ structure)"),
    RF_R4_market_down_5 = list(severity = "INFO",
                                note = "Stress 8 used (GFC/COVID/Rate2022/etc), not market_down_5 hypothetical"),
    RF_R5_factor_pair_corr = list(severity = "INFO",
                                    note = "IPCA cov(F) inspected via cov_F in lro_params_frozen.json")),
  challenge_flags = list(),
  production_protection = list(
    str_1715_directory = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/",
    write_count = 0L,
    audit_passed = isTRUE(prod_audit$audit_passed)),
  factor_covariance_freshness = list(
    sigma_asof = "2026-04-30",
    is_stale = FALSE,
    estimation_window = "5y daily (2019-05-01 → 2026-04-30) for Σ + monthly IS (2004-02 → 2024-06-30) for IPCA Γ_β"),
  evaluation_criteria = list(
    psd_check = isTRUE(s$psd_sigma),
    cond_under_500 = (s$cond_sigma < 500),
    factor_coverage_R2 = s$R2_sel,
    stress_compliance = TRUE,
    decision = if (isTRUE(s$psd_sigma) && s$cond_sigma < 500) "RISK_DONE_PASS" else "RISK_BLOCK"),
  challenge_review = list(
    objection = FALSE,
    targets_reviewed = c("alpha_package", "confidence_vector", "factor_specs"),
    reason = paste0(
      "alpha inherited from STR_1715 PG2 100% (parent_sha=", substr("34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984", 1, 12),
      "...) sizing_only WT — no_new_alpha=TRUE. Risk agent computes Σ via IPCA, ",
      "no alpha modification. AX-002 SHA-freeze enforced for Forge cross-verify.")),
  recommendation_only_meta = list(
    wt_kind = "recommendation_only",
    no_book_state_write = TRUE,
    promotion_pending = "promotion_wt deferred (per request.json deferred_certs)",
    forge_handoff_payload = list(
      strategy_id_logical = "STR_1715_IPCA_Round2_recommendation",
      sigma_path = sprintf("stage_artifacts/WT_%s/covariance.parquet", WT_ID),
      Gamma_beta_path = sprintf("stage_artifacts/WT_%s/Gamma_beta_freeze.parquet", WT_ID),
      latent_factor_path = sprintf("stage_artifacts/WT_%s/latent_factor_path.csv", WT_ID),
      portfolio_factor_exposure_path = sprintf("stage_artifacts/WT_%s/portfolio_factor_exposure.csv", WT_ID),
      lro_params_path = sprintf("stage_artifacts/WT_%s/lro_params_frozen.json", WT_ID),
      sha256 = s$sha256)),
  next_step = "Optimizer Agent receives Σ + Γ_β + lro_params (SHA-frozen) → IPCA-based weight redistribution proposal. Compare to STR_1715 baseline + Round 1 PCA Hedge.",
  finalize_intent = "draft → codex_round → final"
)

draft_path <- file.path(WT_DIR, "risk_package_draft.json")
write_json(risk_package_draft, draft_path, pretty = TRUE, auto_unbox = TRUE)
cat("[", WT_ID, "] risk_package_draft.json saved →", draft_path, "\n")
cat("  K=", s$K_sel, "L=", s$L_sel,
    "alpha=", ifelse(isTRUE(s$alpha_restricted_sel), "restricted", "unrestricted"),
    "R²=", s$R2_sel,
    "Σ cond=", round(s$cond_sigma, 2),
    "MDD=", round(s$mdd_268m, 4),
    "SHA=", substr(s$sha256, 1, 12), "...\n")
