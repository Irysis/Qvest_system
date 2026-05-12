#==============================================================================
# WT-D20260508_006 — Build FINAL alpha_package.json (post-Codex)
# Charter §8 No Silent Override: graduation FAIL 명시 + Codex disposition 통합
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(arrow)
  library(data.table)
})

WT_ID <- "WT-D20260508_006"
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
OUT_STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))

setwd(PROJECT_ROOT)

# Load all artifacts
draft <- fromJSON(file.path(OUT_WT_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)
codex <- fromJSON(file.path(OUT_WT_DIR, "codex_critic_response_alpha.json"), simplifyVector = FALSE)
extra <- fromJSON(file.path(OUT_STAGE_DIR, "ipca_extra_audits.json"), simplifyVector = FALSE)
robust <- fromJSON(file.path(OUT_STAGE_DIR, "ipca_robustness.json"), simplifyVector = FALSE)

# Forward (snapshot) alpha for finalize
alpha_dt <- as.data.table(read_parquet(file.path(OUT_STAGE_DIR, "alpha_scores.parquet")))
setorder(alpha_dt, Ticker)

alpha_vector <- as.list(round(alpha_dt$alpha_ipca, 6))
names(alpha_vector) <- alpha_dt$Ticker

# Confidence — suppress to <= 0.5 given OOS signal flip (Codex Q2)
# Final confidence: rescaled to [0.10, 0.50] given graduation FAIL
conf_raw <- alpha_dt$confidence
conf_supp <- pmin(conf_raw, 0.50)  # cap 0.50
conf_supp <- pmax(conf_supp, 0.10)  # floor 0.10
conf_vector <- as.list(round(conf_supp, 4))
names(conf_vector) <- alpha_dt$Ticker

# ---- Final challenge_flags (post-Codex remediation) ----
cflags <- list(
  list(severity = "HIGH", code = "GRAD_RANK_IC_FAIL",
       detail = "rank_ic=+0.0034 < 0.04 graduation threshold (180 periods)"),
  list(severity = "HIGH", code = "GRAD_ICIR_FAIL",
       detail = "ICIR=+0.0223 < 0.20 Alpha Lab Gate threshold"),
  list(severity = "HIGH", code = "GRAD_HARVEY_T_FAIL",
       detail = "|Harvey_t_NW|=0.226 < 3.0 multi-test threshold (NW lag=13)"),
  list(severity = "HIGH", code = "GRAD_SUBPERIOD_INSTABILITY",
       detail = "subperiod_stability=0.0; 2010-14 IC=+0.058 → 2015-19 IC=-0.008 → 2020-24 IC=-0.039 = monotonic signal decay"),
  list(severity = "HIGH", code = "VALIDATION_OOS_NEGATIVE",
       detail = "validation IC=-0.0455 / ICIR=-0.4093 (2023-2024, 24 periods)"),
  list(severity = "HIGH", code = "LOCKBOX_OOS_NEGATIVE",
       detail = "lockbox IC=-0.0271 / ICIR=-0.1941 (2025-01 ~ 2026-04, 16 periods, untouched during fit)"),
  list(severity = "HIGH", code = "RF-A1",
       detail = "Codex round corrected: subperiod_stability=0 < 0.50 triggers RF-A1 regardless of papers cited (5 papers cited but trigger condition independent)"),
  list(severity = "HIGH", code = "RF-A2",
       detail = sprintf(
         "Composite IPCA ICIR=+0.022 vs best single V01_BM ICIR=+0.210 = %.1f%% improvement (negative = IPCA dilutes single signals). Codex C5 resolved.",
         (abs(0.0223) - abs(0.2102)) / abs(0.2102) * 100)),
  list(severity = "HIGH", code = "RF-A4",
       detail = sprintf(
         "Sector-neutral ICIR=%+.4f / retention=%.1f%% (raw IC +0.0034 → sec-neutral -0.0025). cross-section signal fully sector-concentrated. Codex RF-A4 resolved.",
         extra$RF_A4_resolution$sec_neutral_ICIR,
         extra$RF_A4_resolution$retention_pct)),
  list(severity = "HIGH", code = "RF-A6",
       detail = sprintf(
         "DSR n_trials=5 was 0.559 → effective n_trials=40 (5 chars × 4 K × 2 spec) DSR=%.3f < 0.5. HLZ Bonferroni t-cutoff=%.3f vs observed=0.226 = 13× short. Codex RF-A6 resolved.",
         extra$RF_A6_resolution$DSR_n_eff,
         extra$RF_A6_resolution$HLZ_Bonferroni_t_cutoff)),
  list(severity = "HIGH", code = "RF-A7",
       detail = "alpha_scores_timeseries.parquet built: 64603 rows × 196 sig_dates × 742 tickers (Date×Ticker×score schema). Codex C1 resolved."),
  list(severity = "MEDIUM", code = "PREDICTOR_AUTOCOR_HIGH",
       detail = "max char median lag-1 autocor=0.933 > 0.93 (S01_Size 0.933, Q01_GPA 0.911, V01_BM 0.905). KR Size + Quality slow-moving."),
  list(severity = "INFO", code = "MONOTONICITY_FAIL",
       detail = "decile monotonicity in-sample +0.09 < 0.7 / lockbox -0.014 — alpha ranking does not produce monotonic decile spread"),
  list(severity = "INFO", code = "ORTHOGONALITY_PASS",
       detail = "vs WT-D20260508_004 reference cross-section alpha: pearson 0.05 / spearman 0.05 < 0.25 PASS. Genuinely different mechanism but does not redeem absolute negative IC.")
)

# ---- Final diagnostics ----
diag_obj <- list(
  rank_ic = 0.0034,
  icir = 0.0223,
  monotonicity = 0.09,
  subperiod_stability = 0,
  turnover_proxy = NA_real_,
  harvey_t_stat = 0.226,
  post_neutralization_ic = extra$RF_A4_resolution$sec_neutral_mean_IC,
  validation_mean_IC = -0.0455,
  validation_ICIR = -0.4093,
  lockbox_mean_IC = -0.0271,
  lockbox_ICIR = -0.1941,
  lockbox_LS_annualized_SR = 0.295,
  lockbox_monotonicity = -0.014,
  Bailey_LdP_DSR_n5 = 0.559,
  Bailey_LdP_DSR_n_eff_40 = extra$RF_A6_resolution$DSR_n_eff,
  HLZ_Bonferroni_t_cutoff_M40 = extra$RF_A6_resolution$HLZ_Bonferroni_t_cutoff,
  LS_annualized_SR_full = 0.501,
  train_R2 = 0.2387,
  sector_neutral_ICIR = extra$RF_A4_resolution$sec_neutral_ICIR,
  sector_neutral_IC_retention_pct = extra$RF_A4_resolution$retention_pct,
  best_single_factor = list(
    char = extra$C5_resolution$best_single_char,
    ICIR = extra$C5_resolution$best_single_ICIR,
    composite_vs_single_pct = extra$C5_resolution$composite_improvement_pct
  ),
  five_spec_summary = list(
    n_specs = 5L,
    n_specs_lock_IC_positive = extra$five_spec_summary$n_specs_lock_IC_positive,
    interpretation = extra$five_spec_summary$interpretation
  ),
  subperiod_breakdown = draft$diagnostics$subperiod_breakdown,
  predictor_autocor_lag1_summary = draft$diagnostics$predictor_autocor_lag1_summary
)

# ---- Codex disposition ----
codex_disposition <- list(
  codex_round = list(
    timestamp = codex$timestamp,
    model = codex$model,
    stance = codex$stance,
    veto_flag = codex$veto_flag,
    weakest_assumption = codex$weakest_assumption,
    n_critical_concerns = length(codex$critical_concerns),
    n_rebuttal_required = length(codex$rebuttal_required),
    n_rationalization_red_flags = length(codex$rationalization_red_flags)
  ),
  concerns_disposition = list(
    list(id = "C1", codex_severity = "HIGH", code = "RF-A7", action = "ACCEPT_RESOLVED",
         resolution = "alpha_scores_timeseries.parquet built (64603 rows × 196 sig_dates)"),
    list(id = "C2", codex_severity = "HIGH", code = "GRAD_FAIL_CONFIRM", action = "ACCEPT",
         resolution = "graduation FAIL confirmed; Risk/Optimizer downstream blocked"),
    list(id = "C3", codex_severity = "HIGH", code = "RF-A1", action = "ACCEPT",
         resolution = "RF-A1 = TRUE based on subperiod_stability=0 only; papers count rationalization removed"),
    list(id = "C4", codex_severity = "MEDIUM", code = "RF-A6", action = "ACCEPT_RESOLVED",
         resolution = "n_trials_eff=40 → DSR=0.217 (FAIL) + HLZ Bonferroni t-cutoff 3.02 vs observed 0.226"),
    list(id = "C5", codex_severity = "MEDIUM", code = "RF-A2", action = "ACCEPT_RESOLVED",
         resolution = "Composite IPCA ICIR +0.022 = 89% WORSE than best single V01_BM ICIR +0.210"),
    list(id = "C6_C7", codex_severity = "MEDIUM", code = "5_SPEC_REPORTING", action = "ACCEPT_RESOLVED",
         resolution = "5-spec regression: K=2,3,4,5 unrestricted + K=4 restricted; 1/5 lock_IC positive (only K=2 +0.006 essentially zero)"),
    list(id = "Q3_synthetic_test", codex_severity = "MEDIUM", code = "PARTIAL", action = "PARTIAL",
         resolution = "Synthetic test reproducible code path documented in challenge_note.md §1 Q3; not saved as standalone artifact (PARTIAL accept)")
  ),
  rationalization_red_flags_correction = list(
    list(rf = "RF1 invented RF-A1 exception", correction = "Removed; RF-A1 = TRUE (HIGH)"),
    list(rf = "RF2 RF-A4 by construction", correction = "Sector-neutral ICIR measured: -0.021 (retention -74%)"),
    list(rf = "RF3 bootstrap not needed too strong", correction = "DSR n_trials=40 + HLZ Bonferroni measured"),
    list(rf = "RF4 K counterfactual", correction = "K∈{2,3,4,5} sweep + K=4 restricted measured (5-spec regression)"),
    list(rf = "RF5 self-grep negation", correction = "Replaced with substantive Codex 9-concern disposition in challenge_note.md §1")
  ),
  ax_axiom_compliance = list(
    AX_001_v2 = "N/A (defense factor not applicable)",
    AX_002 = "Codex round procedure compliant; RF-A7 time-series alpha schema enforced",
    AX_003 = "Single V01_BM ICIR +0.21 > IPCA composite +0.022 = AX-003 KR Value EP_STANDALONE pattern reinforced (simple > composite)",
    AX_004 = "Q01_GPA ICIR +0.135 individually measurable but composite dilutes",
    AX_005_v1_2 = "N/A (not defense top20 long-only)",
    AX_007 = "N/A (alpha generation only, not single-sleeve translation)",
    AX_008 = "1/3 sources COMPLETE (Codex). Forge N/A (graduation FAIL blocks). Architect not invoked (discovery WT scope)."
  ),
  pit_c1_c15_audit = codex$pit_c1_c15_audit,
  agreement_summary = "Codex agrees with claude on directional negative finding. Disagrees on draft schema (RF-A7 time-series enforcement) and rationalization patterns. All 5 rebuttal_required items addressed."
)

# ---- Final graduation_assessment ----
fail_codes_final <- c("GRAD_RANK_IC_FAIL", "GRAD_ICIR_FAIL", "GRAD_HARVEY_T_FAIL",
                      "GRAD_SUBPERIOD_INSTABILITY", "VALIDATION_OOS_NEGATIVE",
                      "LOCKBOX_OOS_NEGATIVE", "RF-A1", "RF-A2", "RF-A4", "RF-A6",
                      "DSR_FAIL_n_eff_40", "MONOTONICITY_FAIL")
graduation_fail_final <- length(fail_codes_final)

interp_final <- paste0(
  "GRADUATION_FAIL_HONEST_NEGATIVE_DEEP — post-Codex remediation. ",
  "KPS 2019 IPCA framework (K=4 unrestricted, L=6 chars including CONST, T=156 train + 24 val + 16 lockbox) ",
  "applied to Korean cross-section. ",
  "graduation_fail_count = 12 (HIGH severity), 1 PASS (orthogonality vs WT_004 cor 0.05). ",
  "Codex 8 critical concerns + 5 rebuttal_required + 5 rationalization red flags ALL DISPOSITIONED. ",
  "Codex-driven extra audits decisive: ",
  "(a) Composite IPCA ICIR +0.022 = 89% WORSE than best single V01_BM ICIR +0.210 → IPCA dilutes individual char signals in KR. ",
  "(b) Sector-neutral IC -0.0025 / retention -74% → cross-section signal fully sector-concentrated. ",
  "(c) DSR n_trials=40 effective = 0.217 < 0.5; HLZ Bonferroni t-cutoff 3.02 vs observed 0.226 = 13× short. ",
  "(d) 5-spec regression (K=2,3,4,5 unrestricted + K=4 restricted): 1/5 positive lockbox IC (only K=2 +0.006 essentially zero) → algorithm/spec choice not the issue. ",
  "Causal mechanism: KR characteristic anomaly base rate decay (2015~) → Z'Z structure noise-dominated → Γ_α captures noise → composite < individual. ",
  "AX-003 (KR Value EP_STANDALONE failed) + AX-004 (KR quality_profitability single-signal long-only failed) patterns reinforced. ",
  "Risk/Optimizer agent spawn BLOCKED (Charter §8 No Silent Override)."
)

graduation_assessment <- list(
  pass_count = 1L,  # only orthogonality
  fail_count = graduation_fail_final,
  fail_codes = fail_codes_final,
  overall_decision = "GRADUATION_FAIL_HONEST_NEGATIVE_DEEP",
  interpretation = interp_final,
  next_action = "alpha_package.json finalized as honest negative discovery report. Risk/Optimizer agent spawn BLOCKED. Q-Lead receives telegram brief. Candidate AX-empirical entry: 'KR IPCA framework K∈{2,3,4,5} L=6 simple chars composite ICIR < individual char ICIR (89% dilution) — composite framework dilutes characteristic-level alpha in KR post-2015' (AX-006 candidate review Q3 2026)."
)

# ---- Final pkg ----
pkg <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  selection_objective = "icir",
  as_of_date = "2026-05-08",
  forecast_horizon = "1M",
  alpha_vector = alpha_vector,                # 324 stocks 2026-04-30 snapshot
  confidence_vector = conf_vector,            # capped at 0.50 due to OOS flip (Codex Q2)
  alpha_discovery_count = length(alpha_vector),
  signal_matrix_ref = paste0("file://", file.path(OUT_STAGE_DIR, "alpha_scores.parquet")),
  signal_matrix_timeseries_ref = paste0("file://", file.path(OUT_STAGE_DIR, "alpha_scores_timeseries.parquet")),
  signal_matrix_timeseries_metadata = list(
    rows = 64603L, sig_dates = 196L, tickers = 742L,
    coverage = "2010-01-31 ~ 2026-04-30 monthly",
    schema = "Date | YearMonth | Ticker | alpha_ipca | confidence | sig_date"
  ),
  factor_specs = draft$factor_specs,
  diagnostics = diag_obj,
  alpha_inheritance_cor = draft$alpha_inheritance_cor,
  challenge_flags = cflags,
  method_shopping_log = draft$method_shopping_log,
  window_isolation = draft$window_isolation,
  orthogonality_audit = draft$orthogonality_audit,
  forward_prediction = draft$forward_prediction,
  graduation_assessment = graduation_assessment,
  algorithm_metadata = draft$algorithm_metadata,
  references = draft$references,
  codex_disposition = codex_disposition,
  extra_audits = list(
    timeseries_alpha = extra$C1_resolution,
    best_single_factor_comparison = extra$C5_resolution,
    sector_neutral_audit = extra$RF_A4_resolution,
    multi_test_correction = extra$RF_A6_resolution,
    five_spec_regression = extra$five_spec_regression,
    five_spec_summary = extra$five_spec_summary,
    restricted_vs_unrestricted = robust$restricted_K4,
    K_sweep = robust$K_sweep_unrestricted
  ),
  saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  challenge_note_path = "qepm/mailbox/worktask/WT-D20260508_006/challenge_note.md",
  challenge_note_version = "v2.0_post_codex"
)

# ---- Write final ----
final_path <- file.path(OUT_WT_DIR, "alpha_package.json")
write_json(pkg, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[final] saved:", final_path, "\n")
cat("[final] alpha_discovery_count:", pkg$alpha_discovery_count, "\n")
cat("[final] graduation_fail_count:", graduation_fail_final, "\n")
cat("[final] decision:", graduation_assessment$overall_decision, "\n")
cat("[final] codex_stance:", codex$stance, "\n")
cat("[final] n_concerns_resolved:", length(codex_disposition$concerns_disposition), "\n")

# ---- Lineage record ----
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package",
    method_selected = "IPCA_ALS K=4 unrestricted L=6 (post-Codex remediation)",
    input_file_paths = c(
      "qepm/mailbox/worktask/WT-D20260508_006/alpha_package_draft.json",
      "qepm/mailbox/worktask/WT-D20260508_006/codex_critic_response_alpha.json",
      "stage_artifacts/WT_WT-D20260508_006/alpha_validation.json",
      "stage_artifacts/WT_WT-D20260508_006/ipca_robustness.json",
      "stage_artifacts/WT_WT-D20260508_006/ipca_extra_audits.json"
    )
  )
  cat("[lineage] recorded\n")
}, error = function(e) cat("[lineage] WARN:", conditionMessage(e), "\n"))
