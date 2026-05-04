## Build risk_package_draft.json from workspace
suppressPackageStartupMessages({
  library(jsonlite); library(data.table); library(digest)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID    <- "WT-S20260504_005"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
STAGE    <- file.path(BASE_DIR, "stage_artifacts", paste0("WT_", WT_ID))

ws <- readRDS(file.path(STAGE, "risk_workspace.rds"))

# Hashes for SHA freeze
sha <- function(p) digest(file=p, algo="sha256")

risk_pkg <- list(
  task_id = WT_ID,
  as_of_date = "2026-05-04",
  signal_as_of = "2026-05-01",
  forecast_horizon = "1M",
  parent_wt = "WT-P20260429_002",
  parent_alpha_package_sha = "34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984",

  sigma_method = "Factor_Beta_Hedge",
  selection_objective = "stress_robust",   # estimation-quality only — not alpha return based

  # Factor model spec
  factor_model = list(
    method = "PCA_latent_K5_IS_frozen",
    K_factors = 5L,
    factor_set_sources = c("PCA_latent_K5", "Statistical_factor_mimicking"),
    is_frozen_at = "2024-06-30",
    var_explained = unname(round(ws$var_explained, 4)),
    cumulative_var = round(sum(ws$var_explained), 4),
    pit_compliance = "C1 (rolling), C9 (sig_date d → applied next period), C13 (Z_Score_Aligned via score_eff inherited), no flip"
  ),

  # Cross-sectional regression
  regression = list(
    type = "rolling_cross_sectional_OLS",
    window_daily = 252L,
    method = "OLS_per_stock_with_intercept",
    n_sig_dates_with_fit = nrow(ws$diag_dt),
    R2_distribution = list(
      mean   = round(mean(ws$diag_dt$R2_mean, na.rm=TRUE), 4),
      median = round(median(ws$diag_dt$R2_mean, na.rm=TRUE), 4),
      p25    = round(quantile(ws$diag_dt$R2_mean, 0.25, na.rm=TRUE), 4),
      p75    = round(quantile(ws$diag_dt$R2_mean, 0.75, na.rm=TRUE), 4),
      min    = round(min(ws$diag_dt$R2_mean, na.rm=TRUE), 4),
      max    = round(max(ws$diag_dt$R2_mean, na.rm=TRUE), 4)
    ),
    R2_threshold_passed = mean(ws$diag_dt$R2_mean, na.rm=TRUE) >= 0.30,
    R2_threshold_note = "Mean=0.299 borderline (target≥0.30). 5 statistical PC explain ~30% of stock variance — single-market K=5 PCA limit. PCA captures common shock structure; idiosyncratic share large by design."
  ),

  # Loadings + beta path artifacts
  factor_loadings_ref = "stage_artifacts/WT_WT-S20260504_005/factor_loadings_B.parquet",
  exposure_matrix_ref = "stage_artifacts/WT_WT-S20260504_005/exposure_matrix.parquet",
  factor_returns_ref  = "stage_artifacts/WT_WT-S20260504_005/factor_returns.parquet",
  factor_covariance_ref = "stage_artifacts/WT_WT-S20260504_005/factor_covariance.parquet",
  specific_risk_ref   = "stage_artifacts/WT_WT-S20260504_005/specific_risk.parquet",
  security_covariance_ref = "stage_artifacts/WT_WT-S20260504_005/covariance.parquet",
  regime_correlation_ref  = "stage_artifacts/WT_WT-S20260504_005/regime_correlation.parquet",
  portfolio_beta_path_ref = "stage_artifacts/WT_WT-S20260504_005/portfolio_factor_beta.csv",
  hedge_target_path_ref   = "stage_artifacts/WT_WT-S20260504_005/hedge_target_path.csv",
  crisis_prone_factor_id_ref = "stage_artifacts/WT_WT-S20260504_005/crisis_prone_factor_id.json",
  regression_diagnostics_ref = "stage_artifacts/WT_WT-S20260504_005/regression_diagnostics.json",
  tail_risk_ref = "stage_artifacts/WT_WT-S20260504_005/tail_risk.json",
  lro_params_frozen_ref = "stage_artifacts/WT_WT-S20260504_005/lro_params_frozen.json",

  # Crisis-prone identification result
  crisis_prone_identification = list(
    primary_method = "highest_mean_drawdown_rank_across_6_crises",
    crisis_prone_k = ws$crisis_prone_k,
    crisis_prone_label = ws$crisis_prone_label,
    consistency_6of6 = TRUE,
    note = "F1 = highest variance PC (market-like). 6/6 crises agreement on worst-by-minDD. Statistical only — no named-factor heuristic."
  ),

  # Portfolio factor beta summary
  portfolio_beta_summary = local({
    bp <- ws$beta_path_dt
    crisis_col <- paste0("beta_F", ws$crisis_prone_k)
    list(
      n_dates = nrow(bp),
      crisis_prone_k = ws$crisis_prone_k,
      mean_beta_on_crisis_prone   = round(mean(bp[[crisis_col]], na.rm=TRUE), 4),
      median_beta_on_crisis_prone = round(median(bp[[crisis_col]], na.rm=TRUE), 4),
      sd_beta_on_crisis_prone     = round(sd(bp[[crisis_col]], na.rm=TRUE), 4),
      range_beta_on_crisis_prone  = round(range(bp[[crisis_col]], na.rm=TRUE), 4),
      finding = "Mean β_p,F1 = -0.046 < 0 → STR_1715 holdings already exhibit slight defensive loading on crisis-prone factor. Hedge intensity per period magnitude-proportional; many periods 'ALREADY_NEUTRAL'."
    )
  }),

  # Σ diagnostics
  sigma_estimation = list(
    method = "factor_model_BOmegaB_plus_D",
    factor_estimator = "PCA_latent_K5_full_sample_Omega",
    n_factors = 5L,
    n_tickers = nrow(ws$Sigma),
    ridge_lambda = 0,
    condition_number = round(ws$cond_num, 2),
    psd = TRUE,
    min_eigenvalue = signif(min(eigen(ws$Sigma, only.values=TRUE)$values), 6)
  ),

  # Tail risk
  tail_risk = ws$tail_risk_json,
  cvar_breach_flag = ws$tail_risk_json$cvar_breach_flag,
  cvar_breach_context = "STR_1715 actual 268m monthly CVaR_95=-0.1289 (threshold -0.10). Reflects pre-hedge concentration risk. Consistent with L-274 MDD=-32.05%. Hedge target = neutralize F1 crisis-prone exposure to mitigate concentration tail risk.",

  # LRO params frozen
  lro_params_frozen = ws$lro_frozen,

  # Method shopping log (R2-C HARD)
  method_shopping_log = list(
    candidates_tried = 1L,
    methods = list(
      list(
        name = "PCA_latent_K5_IS_frozen",
        type = "statistical_factor_extraction",
        condition_number = round(ws$cond_num, 2),
        var_explained = round(sum(ws$var_explained), 4),
        selected = TRUE,
        rationale = "Task spec mandates PCA latent K=5 (or factor analysis). PCA chosen for clarity and SVD numerical stability. Single candidate, no method shopping per spec."
      )
    ),
    note = "Task spec WT-S20260504_005 prescribes PCA latent K=5 IS-frozen + cross-sectional regression. Method exploration is bounded by spec — single estimator path. AX-002 SHA-frozen."
  ),

  # PIT compliance
  pit_compliance = list(
    C1_rolling_only = TRUE,
    C9_sig_date_lag = TRUE,
    C13_no_flip = TRUE,
    C14_usable_date_le_sig = TRUE,
    notes = "PCA IS-frozen at 2024-06-30 → OOS factor returns via projection only. Cross-sectional regression rolling 252d window per sig_date. Holdings reconstructed from alpha_scores at sig_date d → applied to next period."
  ),

  # AX axiom compliance
  axiom_assertions = list(
    AX_000 = "no limits — Factor_Beta_Hedge novel statistical approach explored",
    AX_001_v2 = "defense-like assessment via crisis-prone factor exposure quantile (Codex confirm rebalance — primary metric drawdown-based)",
    AX_002 = "factor_set + crisis_prone_k SHA-frozen at IS cutoff. lro_params_frozen.json sha256 recorded.",
    AX_008 = "Forge + Codex + Architect 2/3 PASS gate — Codex Critic Round mandatory next."
  ),

  # Diagnostics
  diagnostics = list(
    condition_number = round(ws$cond_num, 2),
    shrinkage_used = FALSE,
    shrinkage_method = "none (factor model + diagonal D PSD)",
    tdc_summary = list(note = "TDC not computed — task spec scope limited to factor regression. Available on request via regime_garch.R."),
    holdings_268m_reconstructed_n = nrow(ws$holdings_dt),
    holdings_268m_unique_dates = length(unique(ws$holdings_dt$Date)),
    holdings_268m_unique_tickers = length(unique(ws$holdings_dt$Ticker)),
    crisis_prone_finding = "F1 (PC1, market-like) is crisis-prone in 6/6 crises by minDD. STR_1715 already mean-negative β_p,F1 (-0.046). Hedge mostly ALREADY_NEUTRAL per period — mitigation via further reduction limited. Optimizer: target_beta = 0."
  ),

  risk_summary = list(
    top_common_risks = c(
      sprintf("PCA F1 (market-like) %.1f%% var", round(ws$var_explained[1]*100, 1)),
      sprintf("PCA F2 %.1f%% var", round(ws$var_explained[2]*100, 1)),
      sprintf("PCA F3-F5 cum %.1f%% var", round(sum(ws$var_explained[3:5])*100, 1))
    ),
    crowding_flags = list(),    # no fundamental factor crowding identified in PCA approach
    liquidity_flags = list(),   # liquidity floor 2e8 KRW enforced upstream
    stress_tests = list(
      crisis_prone_F1_mean_drawdown_across_crises = round(
        mean(sapply(ws$crisis_factor_perf, function(x) x$factor_minDD[1]), na.rm=TRUE), 4),
      monthly_VaR_95 = ws$tail_risk_json$VaR_95_monthly,
      monthly_CVaR_95 = ws$tail_risk_json$CVaR_95_monthly,
      monthly_CVaR_99 = ws$tail_risk_json$CVaR_99_monthly
    )
  ),

  # Challenge flags
  challenge_flags = list(
    list(severity = "MEDIUM",
         flag = "R2_borderline",
         detail = "Cross-sectional regression mean R²=0.299 is at threshold (target ≥0.30). 5 statistical PCs explain ~30% of stock-level variance. Idiosyncratic share large but expected for K=5 PCA on 443 KR equities."),
    list(severity = "MEDIUM",
         flag = "cvar_95_breach_pre_hedge",
         detail = "STR_1715 actual 268m monthly CVaR_95=-0.1289 vs hard threshold -0.10. Pre-hedge concentration tail. Recommendation_only WT — production weight not modified by this study."),
    list(severity = "LOW",
         flag = "crisis_prone_metric_disagreement",
         detail = "By-mean → F3 vs by-minDD → F1. Primary chosen = drawdown-based (F1, 6/6 agreement). Mean-based would pick F3 (sometimes positive in some crises). Drawdown more crisis-relevant."),
    list(severity = "LOW",
         flag = "iran_lmr_2026_in_sample_overlap",
         detail = "IRAN_LMR_2026 crisis window 2026-04-01~05-04 overlaps with PCA OOS projection but factor returns are projected (not refit). Statistical only.")
  ),

  # Optimizer handoff
  optimizer_handoff = list(
    instruction = "Optimizer must minimize |β_p,k_crisis| where k_crisis=F1 across the rebalance period, subject to long_only + Σw=1 + cap [0,0.20] + max_names ≤ 20. STR_1715 score_eff is INPUT ONLY (alpha ranking unchanged).",
    inputs = c(
      "exposure_matrix.parquet (latest holdings B)",
      "factor_loadings_B.parquet (per-period B for 268m)",
      "covariance.parquet (Σ for latest holdings)",
      "hedge_target_path.csv (β target = 0 per period)",
      "crisis_prone_factor_id.json (k_crisis=F1)"
    ),
    constraint_summary = "long_only: TRUE | Σw=1 | weight_bounds=[0,0.20] | max_names=20 | cash_overlay_iter31_active",
    not_modify = c("STR_1715 alpha ranking", "score_eff", "regime_state", "cash_overlay_pct"),
    objective_form = "min_w |B[:,k_crisis]^T w| OR min_w (B[:,k_crisis]^T w)^2 + ridge*||w - w_alpha||^2 (recommendation; optimizer chooses)"
  ),

  # Codex round (will be filled after critic response)
  codex_round = list(
    status = "PENDING_DRAFT",
    draft_path = "qepm/mailbox/worktask/WT-S20260504_005/risk_package_draft.json",
    expected_critic_path = "qepm/mailbox/worktask/WT-S20260504_005/codex_critic_response_risk.json",
    expected_challenge_note = "qepm/mailbox/worktask/WT-S20260504_005/risk_challenge_note.md"
  ),

  finalize_meta = list(
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    created_by = "risk-research_agent",
    state_machine_target = "RISK_DONE"
  ),

  inheritance_meta = list(
    parent_alpha_package_path = "qepm/mailbox/worktask/WT-P20260429_002/alpha_package.json",
    parent_alpha_package_sha = "34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984",
    no_new_alpha = TRUE,
    no_alpha_modify = TRUE,
    no_weights_proposed = TRUE,
    str_1715_production_dir_writes = 0
  )
)

# Write draft
write_json(risk_pkg, file.path(WT_DIR, "risk_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("Wrote: ", file.path(WT_DIR, "risk_package_draft.json"), "\n")
cat("Bytes: ", file.info(file.path(WT_DIR, "risk_package_draft.json"))$size, "\n")
