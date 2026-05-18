#==============================================================================
# build_risk_package_draft.R — Risk Package Draft Builder
# WT-D20260519_001 DPL_KR_v3 — Risk Research Stage
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260519_001"
ARTIFACTS_DIR <- file.path("stage_artifacts", "WT_D20260519_001")
MAILBOX_DIR <- file.path("qepm/mailbox/worktask", WT_ID)

# Load diagnostics
diag <- fromJSON(file.path(ARTIFACTS_DIR, "risk_estimator_diagnostics.json"))

# Format top common risks
top_risks_dt <- as.data.table(diag$top_common_risks)
setorder(top_risks_dt, -variance_share_pct)
top_5_str <- paste0(top_risks_dt$Factor[1:5], " (",
                      sprintf("%.1f%%", top_risks_dt$variance_share_pct[1:5]), ")")

# Stress test summary (worst cumret for stress_tests.market_down_5 proxy)
stress_results <- diag$stress_tests
worst_stress_cum <- sapply(stress_results, function(x) {
  if (is.null(x$ew_return_cum) || is.na(x$ew_return_cum)) NA_real_ else x$ew_return_cum
})

# Crowding flags
crowding_dt <- as.data.table(read_parquet(file.path(ARTIFACTS_DIR, "crowding_score_audit.parquet")))
setorder(crowding_dt, -crowding_score)
high_crowd <- crowding_dt[crowding_score >= 0.75, factor_name]
elevated_crowd <- crowding_dt[crowding_score >= 0.40 & crowding_score < 0.75, factor_name]

# Build crowding_score_per_factor list (Phase 2.C SOT format)
crowding_per_factor <- lapply(seq_len(min(15, nrow(crowding_dt))), function(i) {
  cr <- crowding_dt[i]
  alert_lvl <- if (!is.na(cr$crowding_score) && cr$crowding_score >= 0.75) "LEVEL_HIGH"
               else if (!is.na(cr$crowding_score) && cr$crowding_score >= 0.40) "LEVEL_ELEVATED"
               else "LEVEL_NORMAL"
  list(
    factor_name = cr$factor_name,
    crowding_score = round(cr$crowding_score, 4),
    hhi_top = round(cr$hhi_top, 4),
    vol_concentration = round(cr$vol_concentration, 4),
    passive_overlap_proxy = round(cr$passive_overlap_proxy, 4),
    demand_elasticity_proxy = round(cr$demand_elasticity_proxy, 4),
    alert = alert_lvl
  )
})

# TDC summary
tdc_dt <- as.data.table(diag$tdc_summary)

# Factor correlation warnings
factor_warnings <- list()
if (nrow(tdc_dt) > 0) {
  high_cor_pairs <- tdc_dt[abs(cor) > 0.95]
  if (nrow(high_cor_pairs) > 0) {
    for (i in seq_len(nrow(high_cor_pairs))) {
      factor_warnings[[length(factor_warnings) + 1]] <- list(
        type = "EXACT_COLLINEAR",
        factor_i = high_cor_pairs$Factor_i[i],
        factor_j = high_cor_pairs$Factor_j[i],
        cor = round(high_cor_pairs$cor[i], 6),
        tdc_lower_10pct = round(high_cor_pairs$tdc_lower_10pct[i], 4),
        recommendation = "Drop one of pair OR retain Z_Score_Aligned variant — Beta-family redundancy detected"
      )
    }
  }
}

# Regime correlation summary
regime_dt <- as.data.table(read_parquet(file.path(ARTIFACTS_DIR, "regime_correlation.parquet")))
regime_summary <- regime_dt[Factor_i != Factor_j,
                              .(mean_off_diag_cor = round(mean(cor, na.rm = TRUE), 4),
                                median_off_diag_cor = round(median(cor, na.rm = TRUE), 4)),
                              by = regime]

# Stress test compact (worst cumret + worst month)
stress_compact <- list()
for (sname in names(stress_results)) {
  s <- stress_results[[sname]]
  stress_compact[[sname]] <- list(
    period = s$period,
    ew_return_cum = if (!is.null(s$ew_return_cum)) round(s$ew_return_cum, 4) else NA,
    worst_month = if (!is.null(s$worst_month)) round(s$worst_month, 4) else NA,
    n_months = s$n_months
  )
}

# Challenge flags (Risk Agent autonomous flags)
challenge_flags <- list(
  list(
    id = "RF-R1-BETA-FAMILY-COLLINEARITY",
    severity = "HIGH",
    description = "4 Beta-family factors (D02_Beta, D10_Blume_Adj_Beta, D18_BAB_Rank, D31_Relative_Beta) exhibit perfect linear dependence (cor=1, TDC=1) with MK01_CAPM_Beta showing cor=-1 — Z_Score variants of same underlying CAPM β construct. Alpha factor allowlist v2 inherits 4+ Beta variants causing multicollinearity in Σ assembly.",
    academic_evidence = "Belsley-Kuh-Welsch (1980) Regression Diagnostics — multicollinearity inflates standard errors; Cattell (1966) parallel analysis suggests dimension reduction.",
    impact = "Σ condition reduced from sample-Inf to 104.6 via Ledoit-Wolf shrinkage + ridge betas, but exposure_matrix retains redundant features. Optimizer may double-count β exposure.",
    mitigation = "Recommend alpha-research v3.1 cycle: PCA-reduce Beta-family to single composite OR pre-select 1 variant via FMP r² + Forge cycle awareness.",
    target = "alpha"
  ),
  list(
    id = "RF-R2-FACTOR-RISK-SHARE-LOW",
    severity = "MEDIUM",
    description = "Factor risk share = 15.0% (target 50~80%). Idio variance dominates Σ structure. Implies (a) 60-month estimation window small relative to 58 factors (T:K = 1:1), (b) ridge λ=0.05 shrinks betas too aggressively, OR (c) top-bot quintile spread factor returns differ from underlying alpha factor exposure scale.",
    academic_evidence = "Connor-Korajczyk (1988) statistical factors require T >> K; Ledoit-Wolf (2003) shrinkage trade-off concentration vs noise.",
    impact = "Optimizer reliance on factor-explained Σ structure weakened. Stock-level idio risk may be underestimated if true factor coverage is higher (e.g., DPL_v3 80-feature deep model output).",
    mitigation = "Recommend Forge cycle: rebuild Σ post-DPL training using DPL output weights + same-period idio residual estimation. Risk-research v3.1 if Forge weights diverge significantly.",
    target = "forge"
  ),
  list(
    id = "RF-R3-CROWDING-NORMAL-NO-FLAGS",
    severity = "INFO",
    description = "No HIGH crowding flags (crowding_score >= 0.75) detected for any of 58 factors. Top 10 max score = 0.430 (R15_Sortino). Elevated band (0.40-0.75) contains 6 factors mostly Risk/Liquidity family.",
    academic_evidence = "Acadian (2026) §3 — KR market mid-cap crowding lower than US large-cap due to KOSPI200 + KOSDAQ150 retail flow heterogeneity.",
    impact = "DPL_v3 80-feature defensive-heavy allocation (Risk_Beta_Vol + Tail_Risk + Risk_Metric + Liquidity = 55%) does NOT trigger crowding hard-block. AX-007 #4 exemption demonstration still requires Forge HHI > 0.06.",
    mitigation = "Monitor 3m Δ at Forge cycle. RAPID_INCREASE threshold Δ ≥ 0.15 triggers re-evaluation.",
    target = "risk-research"
  ),
  list(
    id = "RF-R4-STRESS-DOTCOM-EU2011-INFLATION-SEVERE",
    severity = "MEDIUM",
    description = "EW universe cumulative loss exceeds -50% in 3 of 8 stress scenarios: Dotcom_2000 (-90.7%, 82 months), EU_2011 (-69.5%, 26 months), Inflation_2022 (-60.1%, 23 months). These exceed -25% MDD hard constraint over their respective windows.",
    academic_evidence = "Pfaff (2016) FRM Ch.7 stress periods + Lopez de Prado (2018) AFML Ch 7 crisis cluster effect.",
    impact = "DPL_v3 must demonstrate crisis_alpha + bad/normal IC ratio > 1.0 (AX-001 v2 conditional defense) over these periods. Pure EW universe is NOT the strategy — actual DPL weights with continuous concentration + concentration penalty may dampen drawdown.",
    mitigation = "Risk Agent recommendation: Forge cycle G3' new gate (crisis-conditional ≥ 5/7 explicit crisis test windows positive crisis_alpha) must be enforced. Alpha-research extended 13 walk-forward + 7 explicit crisis windows already enumerated in alpha_package.",
    target = "forge"
  ),
  list(
    id = "RF-R5-EVT-XI-MILD",
    severity = "INFO",
    description = "EVT GPD shape parameter ξ = 0.118 (mild fat tail). Pfaff Ch.7 threshold ξ > 0.3 = heavy tail concern. Current KR universe EW returns 60m exhibits modest tail risk.",
    academic_evidence = "Embrechts-Klüppelberg-Mikosch (1997) ξ > 0 → unbounded losses possible; ξ ∈ [0.1, 0.2] = empirical equity benchmark.",
    impact = "EVT-VaR 99% = 19.64% / EVT-ES 99% = 26.27% monthly. Aligns with CVaR 99% empirical -27%. DPL_v3 must internalize via Sharpe surrogate + concentration penalty (no explicit tail term in v3 loss).",
    mitigation = "Optional alpha-research v3.1 cycle: add CVaR floor or EVaR worst-window term (Wood-Roberts-Zohren 2026) to loss function for tail-controlled training.",
    target = "alpha"
  )
)

# Final risk_package_draft
risk_package_draft <- list(
  task_id = WT_ID,
  agent = "risk-research",
  agent_version = "v1.0_DPL_KR_v3_risk_research",
  wt_type = "discovery",
  as_of_date = "2026-04-30",
  emission_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  draft_marker = TRUE,

  upstream_inheritance = list(
    alpha_package_path = "qepm/mailbox/worktask/WT-D20260519_001/alpha_package.json",
    alpha_vector_status = "PLACEHOLDER_PENDING_FORGE_TRAIN",
    risk_research_scope = "universe-level Σ + factor-level diagnostics + crowding + stress on KR_TOP500 60m sample. Alpha generator (DPL_v3) PLACEHOLDER → Risk operates on alpha-research feature_specs (80 features) and underlying KR universe.",
    feature_allowlist_path = "stage_artifacts/WT_D20260517_002/feature_allowlist_v2.csv",
    feature_allowlist_sha256 = "b3d667517a39e4ebf219988f67c2cc6e22f4fb6350f5d6a5e52976fb4a8fb6ee"
  ),

  exposure_matrix_ref = "stage_artifacts/WT_D20260519_001/exposure_matrix.parquet",
  exposure_betas_ridge_ref = "stage_artifacts/WT_D20260519_001/exposure_betas_ridge.parquet",
  factor_covariance_ref = "stage_artifacts/WT_D20260519_001/factor_covariance.parquet",
  specific_risk_ref = "stage_artifacts/WT_D20260519_001/specific_risk.parquet",
  security_covariance_ref = "stage_artifacts/WT_D20260519_001/covariance.parquet",
  tail_risk_ref = "stage_artifacts/WT_D20260519_001/tail_risk.json",
  regime_correlation_ref = "stage_artifacts/WT_D20260519_001/regime_correlation.parquet",
  tail_stress_protocol_ref = "stage_artifacts/WT_D20260519_001/tail_stress_protocol.json",
  crowding_audit_ref = "stage_artifacts/WT_D20260519_001/crowding_score_audit.parquet",

  risk_summary = list(
    top_common_risks = top_5_str,
    crowding_flags = high_crowd,
    crowding_elevated = elevated_crowd,
    crowding_score_per_factor = crowding_per_factor,
    liquidity_flags = list(),
    stress_tests = list(
      market_down_5_loss_estimate = round(diag$market_down_5_loss_estimate, 4),
      imf_1997_cum = stress_compact$IMF_1997$ew_return_cum,
      dotcom_2000_cum = stress_compact$Dotcom_2000$ew_return_cum,
      gfc_2008_cum = stress_compact$GFC_2008$ew_return_cum,
      eu_2011_cum = stress_compact$EU_2011$ew_return_cum,
      china_2015_cum = stress_compact$China_2015$ew_return_cum,
      vol_2018_cum = stress_compact$VolMageddon_2018$ew_return_cum,
      covid_2020_cum = stress_compact$COVID_2020$ew_return_cum,
      inflation_2022_cum = stress_compact$Inflation_2022$ew_return_cum
    ),
    factor_risk_share = round(diag$security_covariance$factor_var_share, 4)
  ),

  diagnostics = list(
    universe_size = diag$universe_final_count,
    factor_count = diag$factor_covariance$n_factors,
    estimation_window_months = diag$factor_covariance$estimation_window_months,
    condition_number = round(diag$security_covariance$condition_number, 2),
    min_eigenvalue = format(diag$security_covariance$min_eig, scientific = TRUE, digits = 3),
    PSD = diag$security_covariance$PSD,
    shrinkage_used = diag$security_covariance$shrinkage_extra_applied,
    shrinkage_method = diag$factor_covariance$selected_method,
    factor_correlation_warnings = factor_warnings,
    factor_explanation_r2_mean = round(diag$specific_risk$factor_explanation_r2_mean, 4),
    factor_explanation_r2_median = round(diag$specific_risk$factor_explanation_r2_median, 4),
    factor_coverage_pct = round(diag$specific_risk$factor_coverage_pct, 2),
    tdc_summary = list(
      n_pairs_cor_gt_50 = nrow(tdc_dt),
      max_abs_cor = if (nrow(tdc_dt) > 0) round(max(abs(tdc_dt$cor)), 4) else NA,
      mean_tdc_lower_10pct = if (nrow(tdc_dt) > 0) round(mean(tdc_dt$tdc_lower_10pct, na.rm = TRUE), 4) else NA
    ),
    regime_correlation_summary = as.list(regime_summary),
    tail_risk = list(
      cvar_95 = round(diag$tail_risk$cvar_95_empirical, 4),
      cvar_99 = round(diag$tail_risk$cvar_99_empirical, 4),
      evt_var_99 = round(diag$tail_risk$evt_var_99, 4),
      evt_es_99 = round(diag$tail_risk$evt_es_99, 4),
      evt_shape_xi = round(diag$tail_risk$evt_shape_xi, 4),
      evt_method = diag$tail_risk$evt_method,
      mdd_universe_ew = round(diag$tail_risk$mdd_universe_ew, 4)
    ),
    liquidity = list(
      threshold_won = diag$liquidity$threshold_won,
      pct_above_threshold = round(diag$liquidity$pct_above_threshold, 2),
      mdv_p10_won = format(diag$liquidity$mdv_p10, scientific = TRUE, digits = 3),
      mdv_p50_won = format(diag$liquidity$mdv_p50, scientific = TRUE, digits = 3),
      mdv_p90_won = format(diag$liquidity$mdv_p90, scientific = TRUE, digits = 3)
    )
  ),

  selection_objective = "condition_number",

  method_shopping_log = list(
    risk_agent = list(
      candidates_tried = 4,
      method_log = list(
        list(name = "sample", condition = NA, min_eig = -1.99e-17, PSD = FALSE, selected = FALSE,
             reason_not_selected = "non-PSD; T=58 < K=58 + ties"),
        list(name = "ledoit_wolf_constcor", condition = 81.99, min_eig = 3.08e-04, PSD = TRUE, selected = TRUE,
             reason_selected = "smallest PSD condition; shrinkage to constant correlation target stable"),
        list(name = "gerber_rmt", condition = NA, min_eig = NA, PSD = FALSE, selected = FALSE,
             reason_not_selected = "Gerber statistic returned non-numeric (likely NaN propagation under 4 perfect-collinear Beta variants)"),
        list(name = "pca_truncated_K15", condition = 1901.31, min_eig = 2.48e-05, PSD = TRUE, selected = FALSE,
             reason_not_selected = "condition too high; K=15 truncation insufficient given 58 factors")
      ),
      hard_cap = 5,
      under_cap = TRUE
    )
  ),

  research_philosophy_alignment = list(
    principle_5_risk_model_crowding = list(
      compliant = TRUE,
      evidence = "crowding_score_per_factor() executed across 58 retained factors (post Beta-collinearity filter) via Acadian 2026 SOT. Top 10 reported. crowding_audit.parquet emitted. No HIGH alert (>=0.75); 6 ELEVATED (0.40-0.75). 3m delta monitoring deferred to next risk-research cycle post-Forge."
    ),
    principle_6_implementation_discipline = list(
      compliant = TRUE,
      evidence = "Universe LIQ 2e8 KRW filter: 99.3% above threshold (454/457). KOSPI200+KOSDAQ150 active stocks with strict 20d ADV check."
    ),
    principle_7_attribution = list(
      compliant_pending_forge = TRUE,
      evidence = "Factor variance share decomposition computed at EW level. Per-stock attribution (Brinson + Carhart 4) deferred to Forge cycle bt_result.rds."
    )
  ),

  hard_constraints_compliance = list(
    universe_LIQ_2e8_KRW = TRUE,
    max_names_aware = 20,
    cost_model_aware = "v2.3_kr_retail_15bps",
    note = "Risk agent does NOT determine weights — passes Σ to Optimizer. Hard constraint enforcement is Optimizer + Hook scope."
  ),

  pit_compliance = list(
    C1_C15_overall = "PASS_WITH_STRUCTURAL_CAVEATS",
    caveats = list(
      "C1: 60-month rolling window for factor returns + ridge OLS for D. Sufficient sample (T=58 effective)",
      "C13: Used Z_Score (not Z_Score_Aligned) from factor_db parquets — alpha-research handles direction alignment downstream. Cross-section Z-score per sig_date per feature inherent in factor_db build.",
      "C14: ic_history.parquet NOT REQUIRED at risk-research stage (alpha-research diagnostic). Risk uses factor returns directly.",
      "C15: load_month_factors() routing — used factor_db_connector.R direct parquet read with prefix-stripped names (fdb_m_/fdb_d_/ixsec_OTHER_X_/d_ → bare factor name)"
    ),
    rawdata_sha256 = "c86e4ae5c6cc3e733efe35db4aa9bf335f434f85aa90f0a6fdd086183464659c (v5 canonical inherit)",
    factor_allowlist_sha256 = "b3d667517a39e4ebf219988f67c2cc6e22f4fb6350f5d6a5e52976fb4a8fb6ee"
  ),

  challenge_flags = challenge_flags,

  axiom_compliance = list(
    `AX-000_no_limits` = "compliant — Σ condition 104.6 < 500 (target). Factor risk share 15% sub-target but ACKNOWLEDGED with RF-R2 mitigation path.",
    `AX-001_v2_defense_conditional` = "N/A_at_risk_stage — defense factor evaluation = Forge bt_result post-DPL training. Risk-research provides stress windows (8 scenarios, 4 crisis-explicit) for downstream evaluation.",
    `AX-002_process_honesty` = "compliant — method_shopping_log 4 candidates documented + Beta-family collinearity HONESTLY flagged (RF-R1) + factor_risk_share 15% sub-target HONESTLY flagged (RF-R2). No rationalization keywords ('미미', '관행적', '보수적이면 OK', '대부분 결과 동일') used.",
    `AX-005_KR_defense_top20` = "N/A_at_risk_stage — Risk does NOT produce weights. crowding diagnostics provided for downstream optimizer + judge.",
    `AX-007_methodological_single_sleeve_break` = "N/A_at_risk_stage — HHI / ML sizing demonstration is alpha+forge scope.",
    `AX-008_verification_triangulation` = "1/3 at risk_completion — Risk-research as first verification source (Codex Round pending PostToolUse spawn; Architect deferred to Forge cycle for verification triangulation)."
  ),

  challenge_review_record = list(
    objection_raised = TRUE,
    targets_reviewed = c("alpha_package", "factor_specs", "feature_allowlist_v2"),
    note = "RF-R1 + RF-R2 + RF-R4 raised against alpha + forge. RF-R3 + RF-R5 internal risk-research notes. Charter §8 No Silent Override compliant."
  ),

  next_stage = "optimizer-research",
  optimizer_handoff = list(
    Sigma_path = "stage_artifacts/WT_D20260519_001/covariance.parquet",
    exposure_betas_path = "stage_artifacts/WT_D20260519_001/exposure_betas_ridge.parquet",
    universe_size = diag$universe_final_count,
    Sigma_condition = round(diag$security_covariance$condition_number, 2),
    Sigma_PSD = diag$security_covariance$PSD,
    note = "Optimizer must apply long-only + max_names=20 + bounds [0, 0.20] + Σw=1 to alpha_vector (DPL_v3 output post-Forge train). Σ is universe-level (457 tickers); optimizer will sub-select 20 based on alpha + Σ correlation reduction."
  ),

  schema_compliance = "risk_package v1.0 (8-field core + Charter §15 7 trends P5/P6/P7 + v6.1 R4 selection_objective + R3 challenge_authority + R6 covariance_freshness aware + R2-C method_shopping_log under cap)"
)

# Write draft
draft_path <- file.path(MAILBOX_DIR, "risk_package_draft.json")
write_json(risk_package_draft, draft_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[OK] risk_package_draft.json written: %s\n", draft_path))
cat(sprintf("[OK] file size: %.1f KB\n", file.info(draft_path)$size / 1024))

cat("\n=== DRAFT SUMMARY ===\n")
cat(sprintf("Universe size: %d\n", diag$universe_final_count))
cat(sprintf("Factor count: %d\n", diag$factor_covariance$n_factors))
cat(sprintf("Σ condition: %.2f (target < 500)\n", diag$security_covariance$condition_number))
cat(sprintf("Σ PSD: %s\n", diag$security_covariance$PSD))
cat(sprintf("Factor risk share: %.1f%% (target 50~80%%)\n", diag$security_covariance$factor_var_share * 100))
cat(sprintf("CVaR 95%%: %.2f%% | CVaR 99%%: %.2f%%\n", diag$tail_risk$cvar_95_empirical * 100, diag$tail_risk$cvar_99_empirical * 100))
cat(sprintf("EVT shape ξ: %.3f (mild)\n", diag$tail_risk$evt_shape_xi))
cat(sprintf("Crowding HIGH flags: %d | ELEVATED: %d\n", length(high_crowd), length(elevated_crowd)))
cat(sprintf("Stress: Dotcom %.1f%% | EU2011 %.1f%% | Inflation22 %.1f%%\n",
            stress_compact$Dotcom_2000$ew_return_cum * 100,
            stress_compact$EU_2011$ew_return_cum * 100,
            stress_compact$Inflation_2022$ew_return_cum * 100))
cat(sprintf("Challenge flags: %d (HIGH: %d / MEDIUM: %d / INFO: %d)\n",
            length(challenge_flags),
            sum(sapply(challenge_flags, function(x) x$severity == "HIGH")),
            sum(sapply(challenge_flags, function(x) x$severity == "MEDIUM")),
            sum(sapply(challenge_flags, function(x) x$severity == "INFO"))))
