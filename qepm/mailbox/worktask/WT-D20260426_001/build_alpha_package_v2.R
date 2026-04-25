#==============================================================================
# WT-D20260426_001 — alpha_package.json v2 (post-Codex REJECT, sign-flip removed,
# Bailey-LdP DSR, sector-neutral IC, honest verdict ALPHA_NOT_GRADUATING).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260426_001"
ART   <- file.path("stage_artifacts", "WT_D20260426_001")
WT    <- file.path("qepm/mailbox/worktask", WT_ID)

alpha_ts <- read_parquet(file.path(ART, "alpha_scores.parquet")) |> setDT()
diag_v2  <- readRDS(file.path(ART, "alpha_diagnostics_v2.rds"))
diag_orig <- readRDS(file.path(ART, "alpha_diagnostics.rds"))   # Pre-flip (full universe top70 filter)

as_of <- as.character(max(alpha_ts$sig_date, na.rm = TRUE))

# Latest snapshot for vectors (sig_date 2023-11-01)
latest <- alpha_ts[sig_date == max(sig_date, na.rm = TRUE)]
latest <- latest[!is.na(alpha)]
alpha_vec <- as.list(setNames(round(latest$alpha, 6), latest$Ticker))
conf_vec  <- as.list(setNames(round(latest$confidence, 4), latest$Ticker))

# 5-spec from original diag (computed pre-flip; spec values do not depend on
# flip — Harvey t was -7.43 etc. Honest reporting: as-is values are negative)
spec_orig <- diag_orig$spec_summary
spec_records <- lapply(seq_len(nrow(spec_orig)), function(i) {
  list(name = spec_orig$name[i],
       n = as.integer(spec_orig$n[i]),
       mean_ic_as_is = round(spec_orig$mean_ic[i], 4),   # raw Factor DB-aligned (not flipped)
       icir_as_is = round(spec_orig$icir[i], 3),
       harvey_t_as_is = round(spec_orig$harvey_t[i], 2),
       gate_pass_at_3_pos = spec_orig$harvey_t[i] > 3.0,
       gate_pass_at_3_abs = abs(spec_orig$harvey_t[i]) > 3.0)
})

method_log <- list(
  list(name = "S1_full_4axis_AS_IS",
       rank_ic = -0.0511, icir = -0.481, harvey_t = -7.43,
       selected = TRUE,
       interpretation = "Factor DB IC-aligned default. OOS IC negative — alpha not graduating."),
  list(name = "S2_liquidity_only_3axis", rank_ic = -0.0105, icir = -0.149,
       harvey_t = -2.31, selected = FALSE),
  list(name = "S3_amihud_ncskew_2axis", rank_ic = -0.0546, icir = -0.468,
       harvey_t = -7.23, selected = FALSE),
  list(name = "S4_3_axis_ex_PSG", rank_ic = -0.0539, icir = -0.507,
       harvey_t = -7.84, selected = FALSE),
  list(name = "S5_amihud_only", rank_ic = -0.032, icir = -0.461,
       harvey_t = -7.13, selected = FALSE)
)

factor_specs <- list(
  list(factor_family = "Liquidity_Risk", proxy = "L01_Amihud",
       formula = "abs(Ret_d)/(Vol_d * Close_d) (Amihud 2002)",
       lag_rule = "monthly t-1 via load_month_factors()",
       winsorization = "3std", neutralization = "none",
       economic_rationale = "Amihud 2002 illiquidity premium hypothesis. Factor DB IC-aligned direction in KR universe yields OOS negative IC — implies forward 1M reversal.",
       weight_theta = 0.25,
       references = c("Amihud (2002) JFE","Pastor-Stambaugh (2003) JPE")),
  list(factor_family = "Liquidity_Risk", proxy = "L11_Kyle_Lambda",
       formula = "Kyle 1985 lambda regression",
       lag_rule = "monthly t-1", winsorization = "3std", neutralization = "none",
       economic_rationale = "Kyle 1985 price impact premium. Multi-axis liquidity diversification (3 of 4 axes liquidity).",
       weight_theta = 0.25, references = c("Kyle (1985) Econometrica")),
  list(factor_family = "Liquidity_Risk", proxy = "L12_PS_Gamma",
       formula = "Pastor-Stambaugh 2003 gamma proxy",
       lag_rule = "monthly t-1", winsorization = "3std", neutralization = "none",
       economic_rationale = "PS 2003 traded liquidity factor proxy.",
       weight_theta = 0.25, references = c("Pastor-Stambaugh (2003) JPE")),
  list(factor_family = "Tail_Risk", proxy = "R13_NCSKEW",
       formula = "Chen-Hong-Stein 2001 negative coskewness",
       lag_rule = "monthly t-1", winsorization = "3std", neutralization = "none",
       economic_rationale = "CHS 2001 tail-risk premium. Cross-family axis (1 of 4) breaks single-family pattern.",
       weight_theta = 0.25, references = c("Chen-Hong-Stein (2001) JFE"))
)

diagnostics_obj <- list(
  rank_ic                    = diag_v2$rank_ic_as_is,
  icir                       = diag_v2$icir_as_is,
  harvey_t_stat              = diag_v2$harvey_t_as_is,
  monotonicity               = -1.00,                # absolute monotonicity 1.00 (full inverse)
  abs_monotonicity           = 1.00,
  subperiod_stability        = 1.00,                 # all 3 subperiods same-sign (all negative)
  turnover_proxy             = 0.45,
  post_neutralization_ic     = diag_v2$sector_neutral_ic,
  post_neutralization_retention = diag_v2$ic_retention_post_neutral,
  ff5_alpha_ann_top10pct     = -0.157,               # raw (not flipped)
  ff5_alpha_t_top10pct       = -3.64,
  five_spec_pass_at_3_abs    = 4L,                   # |t| > 3 in 4 of 5
  five_spec_pass_at_3_pos    = 0L,                   # positive t > 3 in 0 of 5
  q1_strategy_sr_ann         = diag_v2$q1_strategy_sr_ann,
  q1_strategy_dsr_blp        = diag_v2$q1_strategy_dsr_blp,
  q10_strategy_sr_ann        = diag_v2$q10_strategy_sr_ann,
  q10_strategy_dsr_blp       = diag_v2$q10_strategy_dsr_blp,
  tdc_active_vs_str1700      = diag_orig$tdc_active,
  xs_corr_to_str1700_mean    = diag_orig$xs_corr_mean,
  hard_liquidity_floor_kr    = "TV_avg >= 2e8 KRW",
  rows_after_strict_floor    = diag_v2$rows_post_strict_floor
)

# 9-gate validation (HONEST, post-Codex)
hurdle_checks <- list(
  rank_ic_ge_0_04_pos        = diag_v2$rank_ic_as_is >= 0.04,
  rank_ic_abs_ge_0_04        = abs(diag_v2$rank_ic_as_is) >= 0.04,
  icir_ge_0_20_pos           = diag_v2$icir_as_is >= 0.20,
  icir_abs_ge_0_20           = abs(diag_v2$icir_as_is) >= 0.20,
  monotonicity_abs_ge_0_70   = TRUE,    # |mono|=1
  subperiod_stab_ge_0_50     = TRUE,    # 3/3 same-sign (negative)
  harvey_t_pos_gt_3_0        = diag_v2$harvey_t_as_is > 3.0,
  harvey_t_abs_gt_3_0        = abs(diag_v2$harvey_t_as_is) > 3.0,
  five_spec_pass_4of5_pos    = FALSE,   # 0/5 positive
  five_spec_pass_4of5_abs    = TRUE,    # 4/5 |t|>3
  tdc_lt_0_30                = diag_orig$tdc_active < 0.30,
  xs_corr_lt_0_30            = abs(diag_orig$xs_corr_mean) < 0.30,
  n_sig_dates_ge_60          = uniqueN(alpha_ts$sig_date) >= 60,
  dsr_blp_q1_ge_0_5          = diag_v2$q1_strategy_dsr_blp >= 0.5,
  dsr_blp_q10_ge_0_5         = diag_v2$q10_strategy_dsr_blp >= 0.5,
  dsr_blp_either_ge_0_5      = (diag_v2$q1_strategy_dsr_blp >= 0.5) ||
                                (diag_v2$q10_strategy_dsr_blp >= 0.5)
)

ax_compliance <- list(
  AX_003 = list(status = "EXCLUSION_PASS",
                rationale = "No value family factor used."),
  AX_004 = list(status = "EXCLUSION_PASS",
                rationale = "No quality_profitability factor."),
  AX_005 = list(status = "EXCLUSION_PASS",
                rationale = "No MK01_CAPM_Beta. Liquidity premium != low-beta."),
  AX_007 = list(status = "EXCEPTION_1_DECLARED_NOT_VERIFIED",
                rationale = "Multi-sleeve mandate declared but Optimizer/Forge artifacts must verify. Single-sleeve top20 deployment FORBIDDEN."),
  AX_001_v2 = list(status = "NA",
                   rationale = "core_complement role, not defense."),
  AX_002 = list(status = "PASS",
                rationale = "Sign-flip removed (Codex C1 conceded). As-is alpha reported. No silent override.")
)

challenge_flags <- list(
  list(id = "DIRECTION-AS-IS",
       severity = "INFO",
       note = "alpha = composite of L01+L11+L12+R13 weighted by factor_db IC-aligned Z_Score_Aligned. NO MANUAL FLIP. Forward 1M IC = -0.051 (negative). Decile spread monotonic Q1>Q10."),
  list(id = "ALPHA-NOT-GRADUATING",
       severity = "HIGH",
       note = "Honest verdict: rank_IC=-0.051 (negative). Q1 long DSR_BLP=0.082, Q10 long DSR_BLP=0.022. Neither side passes DSR>=0.5. KR Liquidity_Risk+Tail_Risk composite does not yield long-only graduable alpha. Lesson: archive."),
  list(id = "RF-A1-PASS",
       severity = "INFO",
       note = "All 3 subperiods same-sign (all negative). RF-A1 PASS in absolute sense."),
  list(id = "RF-A4-MEASURED",
       severity = "INFO",
       note = "Sector-neutral IC = -0.029, retention 65.9% — sector residual still negative."),
  list(id = "RF-A5-LIQ-FLOOR",
       severity = "INFO",
       note = "Hard floor TV>=2e8 applied. Rows reduced 446137 → 326513 (73%)."),
  list(id = "RF-A6-DSR-FAIL",
       severity = "HIGH",
       note = "Bailey-LdP DSR formal computation. Q1 PSR 0.9998 (probability), DSR 0.082; Q10 DSR 0.022. Both < 0.5 hurdle."),
  list(id = "TDC-LOW",
       severity = "INFO",
       note = "TDC_active=0.12 < 0.30 — orthogonal to STR_1700. Sequential Admission diversification PASSES, but alpha quality fails."),
  list(id = "AX-007-DEFER",
       severity = "MEDIUM",
       note = "Multi-sleeve mandate not verified at alpha stage. Risk/Optimizer/Forge to verify."),
  list(id = "PROCESS-HONESTY-OVERRIDE",
       severity = "HIGH",
       note = "Initial finalize_alpha_iter7.R applied composite sign-flip — Codex C1 [PIT-C13] flagged as FLIP_SIGN equivalent. v2 reverses the flip. Honest verdict: alpha not graduating."),
  list(id = "RECOMMEND-ARCHIVE",
       severity = "INFO",
       note = "Recommend archive as L-code lesson: 'KR Liquidity_Risk(L01+L11+L12) + Tail_Risk(R13) 4-axis composite, factor_db IC-aligned default, OOS top-universe long-only IC = -0.051, no graduable direction. Forward research: regime-conditional sleeve, single-axis L01 short-list, or alternative cross-family (Growth + Investor_Flow residualized).'")
)

alpha_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = as_of,
  forecast_horizon = "1M",
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = paste0("stage_artifacts://WT_D20260426_001/alpha_scores.parquet"),
  selection_objective = "icir",
  factor_specs = factor_specs,
  diagnostics = diagnostics_obj,
  hurdle_checks_honest = hurdle_checks,
  spec_test_5way_as_is = spec_records,
  ax_axiom_compliance = ax_compliance,
  cross_family_check = list(
    str1700_family = c("Analyst_Consensus","Quality_Earnings",
                       "Momentum_Residual","Distress"),
    iter7_family   = c("Liquidity_Risk","Tail_Risk"),
    overlap_count  = 0L,
    sequential_admission_threshold_tdc = 0.30,
    measured_tdc = round(diag_orig$tdc_active, 3),
    sequential_admission_passed_diversity = TRUE,
    alpha_quality_passed = FALSE
  ),
  alpha_agent = list(
    candidates_tried = 5L,
    method_log = method_log,
    parallel_exec = TRUE, n_workers = 8L,
    rolling_seconds = 130.3,
    rcpp_used = FALSE
  ),
  fair_comparison_note = list(
    period_start = "2004-01-01", period_end = "2023-11-01",
    n_sig_dates = 239L,
    str1700_period_match = TRUE,
    note = "Same-period STR_1700 baseline."
  ),
  codex_round_alpha = list(
    file = "codex_critic_response_alpha.json",
    codex_stance = "REJECT",
    codex_critical_concerns_count = 6L,
    alpha_response_stance = "PARTIAL",
    actions_taken = c(
      "C1 [PIT-C13]: Composite sign-flip REMOVED. alpha as-is.",
      "C2 [DSR]: Bailey-LdP DSR proper formula applied. Q1=0.082, Q10=0.022. Both < 0.5.",
      "C3 [AX-007]: Multi-sleeve mandate declared. Verification deferred to Optimizer/Forge.",
      "C4 [Liquidity]: Hard TV>=2e8 floor applied. 326k rows.",
      "C5 [Sector-neutral]: Measured IC=-0.029, retention 0.66.",
      "C6 [Artifacts]: alpha-stage limitation acknowledged."
    ),
    final_verdict = "ALPHA_NOT_GRADUATING — recommend archive as L-code lesson."
  ),
  challenge_flags = challenge_flags,
  governance_note = paste(
    "Iter 7 Cross-family Liquidity+Tail composite as-is from Factor DB IC-aligned",
    "default has OOS rank_IC=-0.051 (negative) over 239 months KR universe.",
    "DSR_BLP fails on both Q1 and Q10 long-only strategies.",
    "Codex REJECT addressed: sign-flip removed, formal DSR computed,",
    "sector-neutral IC measured, hard liquidity floor applied.",
    "Honest verdict: alpha NOT graduating. TDC=0.12 (cross-family diversity",
    "architecturally PASSES) but alpha quality fails.",
    "Lesson recommended for archive."
  ),
  honest_verdict = diag_v2$honest_verdict,
  schema_version = "alpha_package.v1",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

out_path <- file.path(WT, "alpha_package.json")
write_json(alpha_package, out_path, pretty = TRUE, auto_unbox = TRUE, digits = 8)
cat("[v2] alpha_package.json saved:", out_path, "\n")

# Lineage append
ll_path <- "02_Infrastructure/worktask/lineage_utils.R"
if (file.exists(ll_path)) {
  source(ll_path)
  inputs <- c(
    "stage_artifacts/WT_D20260425_011/alpha_scores.parquet",
    "02_Infrastructure/factor_db/factor_registry.json",
    ".cache/rawdata.parquet",
    ".cache/kr_factor_returns_v2.parquet"
  )
  inputs <- inputs[file.exists(inputs)]
  tryCatch({
    record_package_lineage(
      task_id          = WT_ID,
      package_type     = "alpha_package_v2",
      method_selected  = "L01+L11+L12+R13_AS_IS_NOFLIP_partial_response_to_codex",
      input_file_paths = inputs
    )
    cat("[v2] Lineage v2 recorded.\n")
  }, error = function(e) cat("[v2] Lineage skipped:", conditionMessage(e), "\n"))
}

# Update alpha_validation.json
val <- list(
  task_id = WT_ID,
  hurdle_checks = hurdle_checks,
  ax_compliance_summary = list(
    AX_003 = "EXCLUSION_PASS",
    AX_004 = "EXCLUSION_PASS",
    AX_005 = "EXCLUSION_PASS",
    AX_007 = "EXCEPTION_1_DECLARED",
    AX_002 = "PASS",
    PIT_C13 = "PASS_v2 (sign-flip removed per Codex)"
  ),
  honest_verdict = "ALPHA_NOT_GRADUATING",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(val, file.path(ART, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("[v2] alpha_validation.json updated\n")
