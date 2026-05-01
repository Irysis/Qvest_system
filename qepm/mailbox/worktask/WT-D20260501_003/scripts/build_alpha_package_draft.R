# ============================================================================
# WT-D20260501_003 — Build alpha_package_draft.json
# ============================================================================
# Reads stage_artifacts/WT_D20260501_003/{alpha_validation.json,
#   alpha_diagnostics_full.rds, alpha_scores.parquet} and builds
#   alpha_package_draft.json for codex critic round.
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260501_003"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJ_ROOT, "qepm/stage_artifacts/WT_D20260501_003")

cat("\n=== Build alpha_package_draft.json — WT-D20260501_003 ===\n")
cat("Time:", as.character(Sys.time()), "\n\n")

# Load diagnostics
diag <- readRDS(file.path(STAGE_DIR, "alpha_diagnostics_full.rds"))
val_obj <- fromJSON(file.path(STAGE_DIR, "alpha_validation.json"),
                    simplifyVector = FALSE)
panel <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))

cat("Loaded diagnostics. Main composite:", diag$main_choice,
    " ICIR:", round(diag$main_icir, 4), "\n")

# AS-OF
as_of <- diag$as_of
final_panel <- diag$final_panel
cat("AS-OF:", as.character(as_of), "  N:", nrow(final_panel), "\n\n")

# alpha_vector + confidence_vector
alpha_vec <- setNames(round(final_panel$alpha, 5), final_panel$Ticker)
conf_vec  <- setNames(round(final_panel$confidence, 4), final_panel$Ticker)

# Inheritance correlation: 002 vs current
inheritance_cor <- NA_real_
inh_status <- "no_predecessor_alpha_loaded"
tryCatch({
  pred_pkg <- fromJSON(file.path(PROJ_ROOT,
    "qepm/mailbox/worktask/WT-D20260501_002/alpha_package.json"),
    simplifyVector = TRUE)
  if (!is.null(pred_pkg$alpha_vector)) {
    pred_alpha <- unlist(pred_pkg$alpha_vector)
    common <- intersect(names(pred_alpha), names(alpha_vec))
    if (length(common) >= 30L) {
      inheritance_cor <- suppressWarnings(cor(
        pred_alpha[common], alpha_vec[common], method = "pearson"))
      inh_status <- sprintf("computed_n=%d", length(common))
    }
  }
}, error = function(e) {
  cat("Warning: predecessor alpha load failed:", e$message, "\n")
})

cat("Inheritance cor vs WT_002:", round(inheritance_cor, 4),
    " (", inh_status, ")\n\n")

# Load request
req <- fromJSON(file.path(WT_DIR, "request.json"), simplifyVector = FALSE)

# Build factor_specs (3-Pillar Bayesian)
factor_specs <- list(
  list(
    factor_family = "EarningsQuality_Bayesian",
    proxy = "BHEQ_HierarchicalPosterior",
    formula = "posterior_i_k = (1*data_i_k + 5*sector_mean_k) / (1+5); signal_i = mean_k(posterior_i_k - sector_mean_k)",
    components = c("Q07_Earnings_Stability", "C01_SUE",
                   "C09_Earnings_Surprise_Sq"),
    lag_rule = "quarterly 45d (DART) — load_month_factors PIT auto",
    winsorization = "implicit via Z_Score_Aligned (3std factor_db default)",
    neutralization = "sector hierarchical pooling (no explicit neutralization needed)",
    economic_rationale = "KR-specific earnings stability hierarchical-shrunk posterior. L-121 Q07 위기 IC empirical evidence. DART 분기 EPS noisy single observation → sector pooling extracts sector-relative quality signal cleanly.",
    weight_theta = "data-driven via P3 walking-forward Bayesian shrinkage IC",
    references = c("Gelman-Hill (2007) Hierarchical Models",
                   "Henry-Luo (2012) Bayesian methods in finance",
                   "L-121 Q07_Earnings_Stability KR-specific 위기 IC"),
    bayesian_method = "Normal-Normal hierarchical conjugate; sector grouping",
    prior_specification = list(
      form = "N(sector_mean_k, prior_strength=5)",
      rationale = "5-obs sector prior weight balances individual evidence in KR top-500 universe with 26 sectors",
      pit_safe = TRUE
    )
  ),
  list(
    factor_family = "RegimeChange_Bayesian",
    proxy = "BOCPD_ReversalTrigger",
    formula = "P(r_t <= 3 | x_{1:t-1}) * (-sign(cum_3m_ret)) on daily returns",
    components = c("daily returns 60d window", "Adams-MacKay 2007 forward filtering"),
    lag_rule = "t-1 strict (sequential update natural)",
    winsorization = "CS Z-score 3std post-signal",
    neutralization = "cross-sectional Z (no sector neutralization at signal level)",
    economic_rationale = "Bayesian Online Change Point posterior detects momentum exhaustion regime shift. High p(recent change) × negative recent momentum direction → reversal candidate. Adams-MacKay (2007) PIT-natural sequential update.",
    weight_theta = "data-driven via P3 walking-forward Bayesian shrinkage IC",
    references = c("Adams & MacKay (2007) Bayesian Online Changepoint Detection arXiv:0710.3742",
                   "Barroso & Santa-Clara (2015) Momentum risk-managed",
                   "Carhart (1997) momentum"),
    bayesian_method = "Online change point posterior (forward filter), Normal-InvGamma conjugate",
    prior_specification = list(
      form = "Normal-InvGamma conjugate; hazard rate = 1/30 (~30-day expected regime length)",
      rationale = "30-day matches monthly rebalance horizon. Conjugate priors enable closed-form recursion (no MCMC).",
      pit_safe = TRUE
    )
  ),
  list(
    factor_family = "MetaWeight_BayesianShrinkage",
    proxy = "BSIC_ThetaPosterior",
    formula = "theta_k(t) = max(0, posterior_mean_IC_k(t-1)) * n_k / (n_k + lambda); composite = sum_k theta_k * pillar_z_k",
    components = c("rolling-12 IC of BHEQ", "rolling-12 IC of BOCPD"),
    lag_rule = "walking-forward t-1 strict; IC up to sig_d - 1 month only",
    winsorization = "n/a (theta on IC posterior)",
    neutralization = "n/a (meta-weighting)",
    economic_rationale = "Half-normal posterior on rolling IC enforces theta >= 0. Resolves predecessor (WT_002) signed-theta PIT-C13 gray zone explicitly. Negative posterior IC = 'evidence against this pillar in current regime' → theta = 0 (drop), not flip. ML-style shrinkage (lambda=12) = 4th AX-007 exception.",
    weight_theta = "self-referential",
    references = c("Bailey-Lopez de Prado (2014) Deflated Sharpe",
                   "Harvey-Liu-Zhu (2016) Multi-test penalty",
                   "L-269 PIT-C13 signed-theta gray zone"),
    bayesian_method = "Half-normal shrinkage posterior, walking-forward",
    prior_specification = list(
      form = "Half-normal: theta >= 0 enforced via max(0, posterior_mean)",
      rationale = "Z_Score_Aligned itself is IC-positive direction guarantee. Half-normal posterior interprets negative IC as 'turn off', not flip — resolves PIT-C13 gray zone.",
      pit_safe = TRUE,
      lambda_shrink = 12
    )
  )
)

# graduation_check decision
gc <- val_obj$graduation_check
gc_pass_count <- sum(unlist(gc[grep("_pass$", names(gc), value = TRUE)]))
gc_pass_total <- length(grep("_pass$", names(gc), value = TRUE))
graduation_recommendation <- if (gc_pass_count >= 5L &&
                                 isTRUE(gc$icir_pass) &&
                                 isTRUE(gc$rank_ic_pass)) {
  "PROCEED_TO_RISK_AGENT"
} else if (gc_pass_count >= 3L) {
  "REVISE_OR_CHALLENGE"
} else {
  "ABORT_HONEST_ALPHA_NOT_FOUND"
}

cat("Graduation gate pass count:", gc_pass_count, "/", gc_pass_total,
    "  recommendation:", graduation_recommendation, "\n\n")

# Challenge flags self-detected
challenge_flags <- list()
if (!isTRUE(val_obj$composite_vs_best_single$composite_beats_best)) {
  challenge_flags <- c(challenge_flags, list(list(
    flag_id = "ALPHA_CF_01_RF_A2",
    severity = "MEDIUM",
    description = "Composite ICIR does not exceed best single Pillar (RF-A2). honest report: composite ICIR = ",
    detail = sprintf("%.4f vs best single (%s) = %.4f, improvement_pct = %.2f%%",
                     val_obj$composite_vs_best_single$main_icir,
                     val_obj$composite_vs_best_single$best_single_name,
                     val_obj$composite_vs_best_single$best_single_icir,
                     val_obj$composite_vs_best_single$improvement_pct)
  )))
}
if (!isTRUE(gc$icir_pass)) {
  challenge_flags <- c(challenge_flags, list(list(
    flag_id = "ALPHA_CF_02_ICIR_BELOW_GATE",
    severity = "HIGH",
    description = sprintf("Main composite ICIR %.4f < Alpha Lab Gate 0.20",
                          gc$icir_value)
  )))
}
if (!isTRUE(gc$harvey_t_pass)) {
  challenge_flags <- c(challenge_flags, list(list(
    flag_id = "ALPHA_CF_03_HARVEY_T_BELOW_3",
    severity = "HIGH",
    description = sprintf("NW-t %.4f < Harvey-Liu-Zhu 3.0 threshold",
                          gc$harvey_t_value)
  )))
}
if (!isTRUE(gc$dsr_pass)) {
  challenge_flags <- c(challenge_flags, list(list(
    flag_id = "ALPHA_CF_04_DSR_BELOW_HALF",
    severity = "HIGH",
    description = sprintf("DSR %.4f < 0.50 (Bailey-Lopez de Prado)",
                          gc$dsr_value)
  )))
}
if (!isTRUE(gc$monotonicity_pass)) {
  challenge_flags <- c(challenge_flags, list(list(
    flag_id = "ALPHA_CF_05_MONOTONICITY_BROKEN",
    severity = "HIGH",
    description = sprintf("Decile monotonicity Spearman corr %.4f < 0.80",
                          gc$monotonicity_value)
  )))
}
# Liquidity mandate audit (request 5e7 vs system mandate 2e8)
challenge_flags <- c(challenge_flags, list(list(
  flag_id = "ALPHA_CF_06_LIQUIDITY_MANDATE_CONFLICT",
  severity = "MEDIUM",
  description = "request.json liquidity_floor = 5e7, system mandate (CLAUDE.md) = 2e8. request followed but Q-Lead override required."
)))

# selection_objective (R4 P3 enum) — predictive power only
selection_objective <- "icir"

# wt_type role card adherence
role_card_check <- list(
  wt_type = req$wt_type,
  role = "discovery — new alpha mechanism Bayesian factor design",
  expected_output_compliance = list(
    factor_specs_count = length(factor_specs),
    alpha_inheritance_cor_threshold = 0.95,
    alpha_inheritance_cor_actual = inheritance_cor,
    alpha_inheritance_cor_passes = !is.na(inheritance_cor) && inheritance_cor < 0.95,
    mechanism_citation_chars = sum(sapply(factor_specs, function(s) nchar(s$economic_rationale))),
    harvey_t_specs_pass_count = val_obj$composite_diagnostics$harvey_t_specs_pass_count,
    harvey_t_specs_pass_count_threshold = 3L
  ),
  alpha_discovery_certificate_eligibility = list(
    factor_specs_count_geq_1 = length(factor_specs) >= 1,
    inheritance_lt_0_95 = !is.na(inheritance_cor) && inheritance_cor < 0.95,
    mechanism_citation_geq_50 = sum(sapply(factor_specs, function(s) nchar(s$economic_rationale))) >= 50,
    harvey_specs_geq_3 = val_obj$composite_diagnostics$harvey_t_specs_pass_count >= 3L
  )
)

# Final assembly
draft_pkg <- list(
  task_id = WT_ID,
  wt_type = req$wt_type,
  lifecycle_label = "discovery_v1_bayesian_factor_design",
  as_of_date = as.character(as_of),
  forecast_horizon = "1M",
  rebalance_frequency = "monthly",
  hypothesis_title = "Bayesian Factor Design — 3-Pillar PIT-Native (BHEQ + BOCPD + BSIC)",
  hypothesis_summary = "Bayesian inference 산출물(posterior mean / probability)을 cross-sectional alpha로 변환. 3-Pillar: (P1) Bayesian Hierarchical Earnings Quality posterior_i - sector_mean = sector-relative earnings quality. (P2) Bayesian Online Change Point Detection (Adams-MacKay 2007) per-ticker P(recent_change) * (-sign(recent_momentum)) = momentum exhaustion / reversal trigger. (P3) Half-normal posterior shrinkage IC (theta >= 0 enforced) walking-forward composite — resolves predecessor (WT_002) signed-theta PIT-C13 gray zone. Bayesian sequential update natural PIT-clean. Predecessor 9 issues 사전 차단: walking-forward strict / panel format / Z_Score_Aligned only / theta>=0 / composite>best-single / AX-007 ML sizing 4th branch / liquidity 5e7 request follows / Sigma honest defer / challenge_note + stage_artifacts.",
  selection_objective = selection_objective,
  alpha_vector = as.list(alpha_vec),
  confidence_vector = as.list(conf_vec),
  signal_matrix_ref = paste0("stage_artifacts/WT_D20260501_003/alpha_scores.parquet"),
  factor_specs = factor_specs,
  bayesian_method_chosen = "3-Pillar Bayesian: BHEQ (Normal-Normal hierarchical) + BOCPD (Adams-MacKay 2007 online change point) + BSIC (half-normal shrinkage IC)",
  prior_specification = val_obj$prior_specification,
  posterior_update_rule = val_obj$posterior_update_rule,
  mcmc_or_vi_diagnostics = list(
    method = "All conjugate / closed-form (no MCMC, no VI required)",
    BHEQ = "Normal-Normal conjugate analytical",
    BOCPD = "Forward filtering recursion (exact Bayesian inference)",
    BSIC = "Half-normal posterior analytical (max(0, mean) shrinkage)",
    convergence = "n/a — closed-form posteriors",
    rationale = "Conjugate priors chosen specifically to avoid MCMC/VI cost + ensure deterministic PIT-safe execution at every sig_d"
  ),
  diagnostics = list(
    rank_ic = val_obj$composite_diagnostics$mean_ic,
    icir = val_obj$composite_diagnostics$icir,
    monotonicity = val_obj$composite_diagnostics$monotonicity_corr,
    subperiod_stability = val_obj$composite_diagnostics$subperiod_stability,
    turnover_proxy = NA,
    harvey_t_stat = val_obj$composite_diagnostics$nw_t,
    deflated_sharpe = val_obj$composite_diagnostics$deflated_sharpe,
    sr_observed = val_obj$composite_diagnostics$sr_observed,
    n_months = val_obj$composite_diagnostics$n_months,
    n_trials = val_obj$composite_diagnostics$n_trials,
    harvey_t_specs_pass_count = val_obj$composite_diagnostics$harvey_t_specs_pass_count,
    walking_forward_attestation = TRUE,
    bayesian_posterior_pit_clean = TRUE,
    sig_dates_count = val_obj$n_sig_dates,
    alpha_inheritance_cor = inheritance_cor,
    alpha_inheritance_status = inh_status
  ),
  per_pillar_diagnostics = val_obj$per_pillar_diagnostics,
  composite_vs_best_single = val_obj$composite_vs_best_single,
  graduation_criteria_check = list(
    gates = gc,
    pass_count = gc_pass_count,
    pass_total = gc_pass_total,
    graduation_recommendation = graduation_recommendation
  ),
  pit_attestation = val_obj$pit_attestation,
  ax_007_avoidance_strategy = val_obj$ax_007_avoidance_strategy,
  liquidity_mandate_audit = val_obj$liquidity_mandate_audit,
  role_card_check = role_card_check,
  method_shopping_log = list(
    candidates_tried = 4L,
    candidates_max = 5L,
    methods = list(
      list(name = "BHEQ_Pillar1_alone", icir = val_obj$per_pillar_diagnostics$BHEQ_Pillar1$icir, selected = FALSE),
      list(name = "BOCPD_Pillar2_alone", icir = val_obj$per_pillar_diagnostics$BOCPD_Pillar2$icir, selected = FALSE),
      list(name = "EW_Combined_P1_P2", icir = val_obj$per_pillar_diagnostics$EW_Combined$icir, selected = (val_obj$composite_vs_best_single$main_choice == "ew_combined")),
      list(name = "P3_Bayesian_Shrunk_P1_P2", icir = val_obj$per_pillar_diagnostics$P3_Bayesian$icir, selected = (val_obj$composite_vs_best_single$main_choice == "p3_bayesian"))
    ),
    parallel_exec = FALSE,
    n_workers = 1L,
    rcpp_used = FALSE,
    rolling_seconds = NA
  ),
  challenge_flags = challenge_flags,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  generated_by = "Alpha-Research Opus 4.7 (1M)"
)

write_json(draft_pkg, file.path(WT_DIR, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, force = TRUE, na = "null")
cat("\nWrote alpha_package_draft.json\n")
cat("File size:", file.size(file.path(WT_DIR, "alpha_package_draft.json")), "bytes\n")
cat("Tickers in alpha_vector:", length(alpha_vec), "\n")
cat("Composite ICIR:", round(diag$main_icir, 4), "\n")
cat("Best single:", val_obj$composite_vs_best_single$best_single_name,
    "ICIR:", round(val_obj$composite_vs_best_single$best_single_icir, 4), "\n")
cat("Composite > best:", val_obj$composite_vs_best_single$composite_beats_best, "\n")
cat("Graduation pass:", gc_pass_count, "/", gc_pass_total, "\n")
cat("Recommendation:", graduation_recommendation, "\n")

cat("\n=== Draft built. Time:", as.character(Sys.time()), "===\n")
