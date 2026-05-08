#==============================================================================
# WT-D20260508_002 Alpha v5 — alpha_package_v5_draft.json builder
#
# Honest empirical disposition: v4 lookahead-inflated IC 0.291 → v5 PIT-proper
# IC 0.019. v5 = DISCOVERY_FAIL_HONEST_PIT_PROPER.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})
options(warn = 1)

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_002"
WT_DIR <- file.path(PROJ, "qepm", "mailbox", "worktask", WT_ID)
ART_DIR <- file.path(PROJ, "stage_artifacts", "WT_D20260508_002")

cat("================================================================\n")
cat("WT-D20260508_002 Alpha v5 Package Builder\n")
cat("================================================================\n")

# Load Phase 3 cache
ph3 <- readRDS(file.path(WT_DIR, "phase3_cache.rds"))
diag_results <- ph3$diag_results
max20_results <- ph3$max20_results
dsr_log <- ph3$dsr_log
gate_summary <- ph3$gate_summary
best_model <- ph3$best_model
alpha_vec_export <- ph3$alpha_vec_export
conf_vec_export <- ph3$conf_vec_export
fwd_preds <- ph3$fwd_preds
raw_vs_neut <- ph3$raw_vs_neut
n_trials_views <- ph3$n_trials_views

# Load Phase 1 lineage
lineage_phase1 <- fromJSON(file.path(WT_DIR, "sig_date_window_lineage.json"), simplifyVector = FALSE)
gpu_report <- fromJSON(file.path(WT_DIR, "gpu_acceleration_report.json"), simplifyVector = FALSE)
multi_trial_log <- fromJSON(file.path(WT_DIR, "multi_trial_dsr_log.json"), simplifyVector = FALSE)

# Best diagnostics
best_d <- diag_results[[best_model]]
best_max20 <- max20_results[[best_model]]
best_dsr <- dsr_log[[best_model]]
best_gates <- gate_summary[[best_model]]

# Empirical disposition
op_pass_v5 <- best_gates$pass_all
empirical_status <- if (op_pass_v5) "DISCOVERY_PASS_PRELIMINARY_AGENT" else "DISCOVERY_FAIL_HONEST_PIT_PROPER"
finalize_label <- if (op_pass_v5) "DISCOVERY_PRELIM_PASS_PRE_CODEX" else "DISCOVERY_FAIL_PIT_PROPER_NO_ADMIT"

cat("\n[1] Empirical disposition:", empirical_status, "\n")
cat("    best_model:", best_model, "\n")
cat("    rank_IC:", round(best_d$rank_ic, 4), "\n")
cat("    ICIR:", round(best_d$icir, 3), "\n")
cat("    Harvey-t:", round(best_d$t_NW, 2), "\n")
cat("    sub_stab:", round(best_d$sub_stab, 2), "\n")
cat("    monotonicity:", round(best_d$monotonicity, 3), "\n")
cat("    max-20 SR_net:", round(best_max20$sr_net_ann, 3), "\n")
cat("    max-20 TO_ann:", round(best_max20$to_ann, 2), "\n")
cat("    DSR strict (N=560):", round(best_dsr$view_c_strict_n_trials_560$dsr, 3), "\n")
cat("    op_pass_v5:", op_pass_v5, "\n")

#--- Build factor_specs (1 spec for best model + reference list of all attempted) ---
factor_specs_list <- lapply(names(diag_results), function(m) {
  d <- diag_results[[m]]
  is_best <- (m == best_model)
  list(
    factor_family = "ML_Residual_CrossSection_KR_v5_PIT_proper",
    proxy = m,
    formula = paste0("ML residual prediction (target = R_i,t+1 - R_Hybrid,t+1) using model: ", m,
                     ". v5 PIT-proper (per-sig_date factor universe, t-1 universe filter, 2e8 KRW hard floor)."),
    lag_rule = "all features lag-1 (PIT C2-safe), factor universe per sig_date (PIT C1-safe)",
    winsorization = "y_train ±0.5 monthly",
    neutralization = if (m == "pred_ens_secneutral") "sector demean post-prediction" else "cross-section z-score post-prediction",
    economic_rationale = paste(
      "Cross-section per-name residual alpha after admitted Hybrid 70/15/15 explained variance.",
      "ML residual approach (Gu/Kelly/Xiu 2020 RFS framework adapted to KR top-342 universe).",
      "Sector-neutral track also computed (Codex C6 remediation)."
    ),
    weight_theta = if (is_best) 1.0 else 0.0,
    references = list(
      "Gu/Kelly/Xiu 2020 RFS — Empirical AP via ML",
      "Bryzgalova/Pelger/Zhu 2024 RFS — Forest Through the Trees",
      "Chen/Pelger/Zhu 2024 — Deep Learning AP (torch GPU MLP applied)",
      "Liu/Stambaugh/Yuan 2019 JFE — Size and Value in China (CH-3, KR proxy)",
      "Hou/Xue/Zhang 2015 RFS — q-factor model",
      "Lopez de Prado 2018 — Advances in Financial ML (CPCV)",
      "Lopez de Prado 2020 — ML for Asset Managers (multi-trial DSR)",
      "Bailey/Lopez de Prado 2014 JPM — Pseudo-Mathematics & Financial Charlatanism (DSR formula)",
      "Jensen/Kelly/Pedersen 2023 JF — Replication Crisis",
      "Avramov/Cheng/Metzker 2023 MS — ML vs Economic Restrictions",
      "Han/He/Rapach/Zhou 2024 — Stock Return Deep Learning"
    ),
    source = "ml_residual_alpha_v5_pit_rolling_python_gpu_torch_xgboost_cuda",
    selection_objective = "rank_ic",
    diagnostics = list(
      ic = round(d$rank_ic, 6),
      icir = round(d$icir, 4),
      t_NW = round(d$t_NW, 4),
      n = d$n_months,
      sub_stab = round(d$sub_stab, 4),
      monotonicity = round(d$monotonicity, 4)
    )
  )
})

#--- Diagnostics summary ---
diagnostics_top <- list(
  rank_ic = round(best_d$rank_ic, 6),
  icir = round(best_d$icir, 4),
  monotonicity = round(best_d$monotonicity, 4),
  subperiod_stability = round(best_d$sub_stab, 4),
  turnover_proxy = round(best_max20$to_ann, 4),
  harvey_t_stat = round(best_d$t_NW, 4),
  harvey_t_NW = round(best_d$t_NW, 4),
  deflated_sharpe_ratio = round(best_dsr$view_c_strict_n_trials_560$dsr, 4),
  deflated_sharpe_ratio_lenient = round(best_dsr$view_a_lenient_n_trials_7$dsr, 4),
  deflated_sharpe_ratio_cv = round(best_dsr$view_b_internal_cv_n_trials_40$dsr, 4),
  post_neutralization_ic = round(raw_vs_neut$post_neut_ic, 6),
  raw_ic_vs_neut_retention_pct = round(raw_vs_neut$neutral_retention * 100, 1),
  rf_a4_flag = raw_vs_neut$rf_a4_flag,
  n_obs = best_d$n_months,
  spec_count = length(diag_results),
  harvey_t_specs_pass_count = sum(sapply(diag_results, function(x) abs(x$t_NW) >= 3.0), na.rm = TRUE),
  rank_ic_sign = if (best_d$rank_ic > 0) "positive" else "negative",
  operational_alpha_pass = op_pass_v5,
  max20_sr_net_ann = round(best_max20$sr_net_ann, 4),
  max20_sr_gross_ann = round(best_max20$sr_gross_ann, 4),
  max20_to_ann = round(best_max20$to_ann, 4),
  max20_cagr_net = round(best_max20$cagr_net, 4)
)

#--- ML comparison ---
ml_comparison <- list(
  best_model = best_model,
  models_compared = names(diag_results),
  per_model_summary = lapply(names(diag_results), function(m) {
    d <- diag_results[[m]]
    mx <- max20_results[[m]]
    dsr_m <- dsr_log[[m]]
    dsr_strict_v <- if (!is.null(dsr_m) && !is.null(dsr_m$view_c_strict_n_trials_560$dsr)) {
      round(dsr_m$view_c_strict_n_trials_560$dsr, 3)
    } else NA
    list(model = m, rank_ic = round(d$rank_ic, 6), icir = round(d$icir, 3),
         t_NW = round(d$t_NW, 2), sub_stab = round(d$sub_stab, 2),
         monotonicity = round(d$monotonicity, 3),
         max20_sr_net_ann = if (!is.null(mx)) round(mx$sr_net_ann, 3) else NA,
         max20_to_ann = if (!is.null(mx)) round(mx$to_ann, 2) else NA,
         dsr_strict = dsr_strict_v)
  }),
  cv_method = "rolling_expanding_window_purged_1m",
  feature_count = 143,
  feature_categories = list(
    factor_db_z_aligned_pit_rolling = 137,  # union across sig_dates
    engineered_momentum_size_TV = 6
  ),
  gpu_acceleration = list(
    device = gpu_report$device,
    gpu_name = gpu_report$gpu_name,
    gpu_vram_gb = gpu_report$gpu_vram_gb,
    torch_cuda_available = gpu_report$torch_cuda_available,
    mlp_torch_real_gpu = gpu_report$mlp_torch_real,
    xgb_cuda = TRUE,
    v4_vs_v5 = gpu_report$v4_vs_v5_comparison,
    per_model_train_secs_summary = gpu_report$per_model_summary,
    cpu_vs_gpu_xgb_benchmark = gpu_report$xgb_cpu_vs_gpu_benchmark
  ),
  hybrid_construction = list(
    method = "real_str1715_returns_70 + tsmom_15 + bond_15",
    weights = list(str1715 = 0.70, tsmom = 0.15, bond = 0.15),
    str1715_source = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds",
    tsmom_signal = "BM_TSMOM_12m sign (long if positive, else 0)",
    bond_proxy = "0 (KR 10y bond data unavailable in this run; explicit limitation, not rationalization)"
  )
)

#--- challenge_flags (REAL — based on actual diagnostics) ---
challenge_flags <- list()
add_flag <- function(id, severity, msg) list(id = id, severity = severity, msg = msg)

if (best_d$rank_ic <= 0) {
  challenge_flags <- c(challenge_flags, list(add_flag("RANK_IC_NEGATIVE_OR_ZERO", "HIGH",
    paste0("rank_ic = ", round(best_d$rank_ic, 4), " <= 0 — alpha source absent or sign-inverted"))))
}
if (abs(best_d$rank_ic) < 0.04) {
  challenge_flags <- c(challenge_flags, list(add_flag("RANK_IC_BELOW_GATE", "HIGH",
    paste0("|rank_ic| = ", round(abs(best_d$rank_ic), 4),
           " < 0.04 graduation gate. PIT-proper IC is far below v4 inflated 0.291 — confirms Codex C1 lookahead diagnosis."))))
}
if (abs(best_d$icir) < 0.20) {
  challenge_flags <- c(challenge_flags, list(add_flag("ICIR_BELOW_GATE", "HIGH",
    paste0("|ICIR| = ", round(abs(best_d$icir), 3), " < Alpha Lab Gate 0.20"))))
}
if (abs(best_d$t_NW) < 3.0) {
  challenge_flags <- c(challenge_flags, list(add_flag("HARVEY_T_BELOW_3", "HIGH",
    paste0("Harvey-t (NW lag=6) = ", round(best_d$t_NW, 2), " < 3.0"))))
}
if (best_dsr$view_c_strict_n_trials_560$dsr < 0.5) {
  challenge_flags <- c(challenge_flags, list(add_flag("DSR_STRICT_BELOW_GATE", "HIGH",
    paste0("DSR strict (N=560) = ", round(best_dsr$view_c_strict_n_trials_560$dsr, 3),
           " < 0.5 Bailey-LdP gate. Multi-trial deflation is catastrophic across all 3 N_trials views."))))
}
if (best_max20$sr_net_ann <= 0) {
  challenge_flags <- c(challenge_flags, list(add_flag("MAX20_SR_NEGATIVE", "HIGH",
    paste0("max-20 SR_net = ", round(best_max20$sr_net_ann, 3),
           " <= 0. After 15bps cost on TO_ann=", round(best_max20$to_ann, 2),
           " the residual signal does not survive."))))
}
if (best_max20$to_ann > 6.0) {
  challenge_flags <- c(challenge_flags, list(add_flag("MAX20_TO_HURDLE_FAIL", "HIGH",
    paste0("max-20 TO_ann = ", round(best_max20$to_ann, 2),
           " > 6.0 Hurdle Gate v2.2 hard fail (Codex C3 confirmed for v5 too)."))))
}
challenge_flags <- c(challenge_flags, list(add_flag("V4_LOOKAHEAD_DIAGNOSED_AND_REMEDIATED", "MEDIUM",
  paste0("v4 IC=0.291 was inflated by 2024-12 factor universe lookahead (Codex C1). ",
         "v5 PIT-proper IC=", round(best_d$rank_ic, 4), " (", round(best_d$rank_ic / 0.291 * 100, 1),
         "% of v4). Codex's PIT diagnosis empirically confirmed."))))
challenge_flags <- c(challenge_flags, list(add_flag("PIVOT_MANDATE_HONEST_FAIL", "INFORMATIONAL",
  paste0("v5 = honest empirical FAIL after full Codex 8-concern remediation. ",
         "ML residual extraction on Hybrid 70/15/15 KR top-342 universe does not yield admittable alpha. ",
         "Recommended pivot: 4th orthogonal source via different mechanism (e.g., crisis-conditional defense, ",
         "low-frequency macro residual, alternative-data sentiment, RL state-space Avramov 2023)."))))

cat("\n[2] Challenge flags:", length(challenge_flags), "\n")
for (cf in challenge_flags) cat("    -", cf$severity, cf$id, "\n")

#--- empirical_disposition + operational_decision ---
empirical_disposition <- list(
  status = empirical_status,
  rationale = paste0(
    "v5 = post-Codex full remediation (8 concerns). PIT-proper IC=", round(best_d$rank_ic, 4),
    " ICIR=", round(best_d$icir, 3), " Harvey-t=", round(best_d$t_NW, 2),
    " max-20 SR_net=", round(best_max20$sr_net_ann, 3),
    " TO_ann=", round(best_max20$to_ann, 2),
    " DSR_strict=", round(best_dsr$view_c_strict_n_trials_560$dsr, 3),
    ". All graduation gates fail. Honest empirical FAIL — alpha source not present in PIT-proper signal. ",
    "Codex C1 lookahead diagnosis confirmed: v4 IC 0.291 → v5 IC ", round(best_d$rank_ic, 4),
    " (", round(best_d$rank_ic / 0.291 * 100, 1), "% retention)."
  ),
  graduation_proper_check = list(
    rank_ic_sign_aligned = best_d$rank_ic > 0,
    rank_ic_magnitude = round(abs(best_d$rank_ic), 4),
    rank_ic_magnitude_pass = abs(best_d$rank_ic) >= 0.04,
    icir_magnitude = round(abs(best_d$icir), 3),
    icir_magnitude_pass = abs(best_d$icir) >= 0.20,
    sub_stab = round(best_d$sub_stab, 2),
    sub_stab_pass = best_d$sub_stab >= 0.5,
    harvey_t_NW_magnitude = round(abs(best_d$t_NW), 2),
    harvey_t_NW_magnitude_pass = abs(best_d$t_NW) >= 3.0,
    dsr_strict_view_c = round(best_dsr$view_c_strict_n_trials_560$dsr, 3),
    dsr_strict_pass = best_dsr$view_c_strict_n_trials_560$dsr >= 0.5,
    max20_sr_net = round(best_max20$sr_net_ann, 3),
    max20_sr_net_pass = best_max20$sr_net_ann > 0,
    max20_to_ann = round(best_max20$to_ann, 2),
    max20_to_pass_hurdle = best_max20$to_ann <= 6.0,
    overall_pass = op_pass_v5
  )
)

operational_decision <- list(
  finalize_label = finalize_label,
  graduation_pass_signed = op_pass_v5,
  pg2_admit_eligibility = if (op_pass_v5) "ELIGIBLE_PENDING_CODEX" else "NOT_ELIGIBLE_HONEST_FAIL",
  next_action = if (op_pass_v5) "PROCEED_RISK_RESEARCH_AFTER_CODEX_REVIEW" else "TERMINATE_PIVOT_TO_4TH_SOURCE_VIA_DIFFERENT_MECHANISM",
  qlead_decision_required = !op_pass_v5,
  recommended_next_paths = list(
    "Crisis-conditional defense (AX-001 v2 — bad/normal IC ratio + crisis_alpha)",
    "Macro-residual long-horizon factor (FRED/ECOS × KOSPI residual, low TO design)",
    "RL state-space (Avramov-Cheng-Metzker 2023 economic restriction overlay)",
    "Alternative data sentiment (kr-news embeddings, retail flow non-conf entropy)",
    "Multi-frequency ensemble (daily-monthly bridge with regime conditioning)"
  )
)

#--- Caveats (v5 lineage) ---
caveats <- list(
  paste0("v5 attempt — full Codex 8-concern remediation cycle 5. ",
         "v4 IC 0.291 → v5 IC ", round(best_d$rank_ic, 4),
         " (", round(best_d$rank_ic / 0.291 * 100, 1), "% retention)."),
  "Codex C1 PIT C1 REMEDIATED: per-sig_date factor universe (top-80 by coverage at sig_date), no 2024-12 snapshot.",
  paste0("46/137 factors persistent >=95% sig_dates (high overlap), but 91 factors PIT-conditional (sig_date-specific). ",
         "Persistence is empirical, not assumed."),
  "Codex C2 PIT C2/C10 REMEDIATED: Universe/Admin/Size/Vol_KRW_20d at YM_features = YM_target - 1m. 2e8 KRW hard floor (5e7 relax 폐기).",
  "Codex C3 hurdle REMEDIATED: max-20 hard simulation. NO top-quintile sleeve. TO_ann measured per Hurdle Gate v2.2.",
  "Codex C4 multi-trial DSR REMEDIATED: 3 N_trials views (lenient N=7, CV N=40, strict N=560 per Bailey-LdP). All views catastrophic.",
  "Codex C5 forward as-of REMEDIATED: 2026-05 forward as-of prediction (348 tickers, no y_actual). Realized last month = 2026-04.",
  "Codex C6 sector-neutral REMEDIATED: pred_ens_secneutral track separate. post_neutralization_ic = 0.0124 (raw 0.0116, 106% retention — sector-neutral does not collapse signal).",
  "Codex C7 artifact_lineage REMEDIATED: sig_date_window_lineage.json + gpu_acceleration_report.json + multi_trial_dsr_log.json + dsr_strict_bailey_ldp.json.",
  "Codex C8 max_names=20 REMEDIATED: Σw=1, weights=1/20=0.05 each (within [0, 0.20]), long-only.",
  "GPU hardware ENABLED: torch 2.6.0+cu124 CUDA verified on RTX 4080 SUPER (17.17 GB VRAM). torch MLP REAL GPU train (v4 polynomial-EN substitute deprecated). XGBoost device='cuda' verified.",
  paste0("Multi-trial DSR severity: best model pred_xgb DSR_strict = ",
         round(best_dsr$view_c_strict_n_trials_560$dsr, 2),
         " (lenient N=7 = ", round(best_dsr$view_a_lenient_n_trials_7$dsr, 2),
         "; CV N=40 = ", round(best_dsr$view_b_internal_cv_n_trials_40$dsr, 2),
         "). All 3 views < 0.5 gate."),
  "Honest empirical disposition: v5 = DISCOVERY_FAIL_HONEST_PIT_PROPER. No silent override; pivot mandate to 4th source via different mechanism."
)

#--- Method log ---
safe_round_dsr <- function(dsr_m, view) {
  if (!is.null(dsr_m) && !is.null(dsr_m[[view]]) && !is.null(dsr_m[[view]]$dsr)) {
    round(dsr_m[[view]]$dsr, 4)
  } else NA
}

method_log <- lapply(names(diag_results), function(m) {
  d <- diag_results[[m]]
  mx <- max20_results[[m]]
  dsr_m <- dsr_log[[m]]
  list(
    name = m,
    rank_ic = round(d$rank_ic, 6),
    icir = round(d$icir, 4),
    t_NW = round(d$t_NW, 4),
    sub_stab = round(d$sub_stab, 4),
    monotonicity = round(d$monotonicity, 4),
    max20_sr_net = if (!is.null(mx)) round(mx$sr_net_ann, 4) else NA,
    max20_to_ann = if (!is.null(mx)) round(mx$to_ann, 4) else NA,
    dsr_strict = safe_round_dsr(dsr_m, "view_c_strict_n_trials_560"),
    dsr_cv = safe_round_dsr(dsr_m, "view_b_internal_cv_n_trials_40"),
    dsr_lenient = safe_round_dsr(dsr_m, "view_a_lenient_n_trials_7"),
    selected = (m == best_model)
  )
})

#--- Final alpha_package_v5_draft ---
alpha_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = "2026-05-08",
  forecast_horizon = "1M",
  alpha_vector = alpha_vec_export,
  confidence_vector = conf_vec_export,
  signal_matrix_ref = "stage_artifacts/WT_D20260508_002/alpha_scores_v5.parquet",
  factor_specs = factor_specs_list,
  diagnostics = diagnostics_top,
  ml_comparison = ml_comparison,
  classical_baseline = list(
    method = "RidgeCV (sklearn 13α grid, 5-fold CV)",
    rank_ic = round(diag_results$pred_ridge$rank_ic, 6),
    max20_sr_net = round(max20_results$pred_ridge$sr_net_ann, 4)
  ),
  naive_baseline = list(
    method = "cross_section_equal_weight_long_max20",
    sr_annual = NA  # NA: sr_naive computation not in v5 (v4 had it but we redirect attention to graduation gates)
  ),
  selection_objective = "rank_ic",
  alpha_inheritance_cor = list(),
  candidates_tried = length(diag_results),
  method_log = method_log,
  challenge_flags = challenge_flags,
  rcpp_used = FALSE,
  parallel_exec = TRUE,
  python_gpu_used = TRUE,
  python_venv = "/home/quant/.venvs/qvest_ml/bin/python",
  hypothesis_source = "alpha_agent_discovered",
  hypothesis_title = "ML residual cross-section alpha v5 — PIT-proper full Codex 8-concern remediation",
  hypothesis_description_short = paste0(
    "v5 5th sub-cycle. v4 8-concern Codex REJECT REVISE → v5 6-path remediation: ",
    "(P1) PIT-rolling factor universe per sig_date, (P2) t-1 universe + 2e8 hard floor, ",
    "(P3) Bailey-LdP multi-trial DSR 3 views, (P4) sector-neutral track, ",
    "(P5) forward 2026-05 as-of, (P6) max-20 hard simulation. ",
    "Python GPU venv enabled (torch CUDA 12.4 + xgboost CUDA on RTX 4080 SUPER). ",
    "Empirical: ", empirical_status, ". rank_IC=", round(best_d$rank_ic, 4),
    " (v4 0.291 → 6.6% PIT-proper retention). Codex C1 lookahead diagnosis empirically confirmed."
  ),
  v_history_summary = list(
    v1 = "alpha_package_draft 미산출 (작업 미완)",
    v2 = "alpha_package_draft 미산출 (작업 미완)",
    v3 = "Real STR_1715 + Z_aligned + MLP + China features. dcast 125M OOM/slow → killed",
    v4 = "v3 + per-month dcast memory optimization. IC 0.291 (LOOKAHEAD-INFLATED). Codex REJECT 8 concerns.",
    v5 = paste0("v4 8-concern full remediation. PIT-rolling factor universe + GPU. IC ", round(best_d$rank_ic, 4),
                " (", empirical_status, ").")
  ),
  caveats = caveats,
  empirical_disposition = empirical_disposition,
  operational_decision = operational_decision,
  alpha_geometry = "per_name_cross_section",
  per_name_alpha_matrix_required = TRUE,
  method_shopping_log_ref = "alpha_validation_v5.json::diag_per_model + max20_per_model + dsr_per_model_3views",
  pipeline_stage = "alpha_v5_pit_proper_pre_codex",
  pit_compliance_lineage = lineage_phase1$pit_compliance,
  forward_2026_05 = list(
    n_tickers = nrow(fwd_preds),
    sig_date = "2026-04-30",
    rationale = "Forward as-of 2026-05 prediction; no realized y_actual (2026-05 incomplete month per RAWDATA 2026-05-08 EOM).",
    deployment_caveat = paste0(
      "alpha_vector exported but operational_alpha_pass = FALSE. ",
      "DO NOT deploy this v5 alpha to PG2 — pivot mandate to 4th source via different mechanism."
    )
  ),
  multi_trial_dsr_views = multi_trial_log$n_trials_total_estimate
)

# Write draft
draft_path <- file.path(WT_DIR, "alpha_package_v5_draft.json")
writeLines(toJSON(alpha_package, pretty = TRUE, auto_unbox = TRUE, na = "null"), draft_path)
cat("\n[3] Wrote alpha_package_v5_draft.json (", file.info(draft_path)$size, "bytes)\n")

# Lineage record
tryCatch({
  source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package_v5_draft",
    method_selected = paste0("ml_residual_pit_proper_v5_best=", best_model),
    input_file_paths = c(
      ".cache/rawdata.parquet", ".cache/factor_db/factor_db_*.parquet",
      "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds",
      "stage_artifacts/WT_D20260508_002/predictions_v5_all_models.parquet"
    )
  )
  cat("  Lineage recorded\n")
}, error = function(e) cat("  Lineage record FAIL (non-fatal):", conditionMessage(e), "\n"))

cat("\n================================================================\n")
cat("alpha_package_v5_draft.json built. ", empirical_status, "\n")
cat("================================================================\n")
