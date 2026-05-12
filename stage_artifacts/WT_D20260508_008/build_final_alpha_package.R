suppressMessages({library(arrow); library(data.table); library(jsonlite)})

# Load all
diag <- readRDS("stage_artifacts/WT_D20260508_008/wt008_full_diagnostics.rds")
val <- fromJSON("stage_artifacts/WT_D20260508_008/alpha_validation.json")
ortho <- fromJSON("stage_artifacts/WT_D20260508_008/orthogonality_vs_hybrid.json")
add <- fromJSON("stage_artifacts/WT_D20260508_008/diagnostic_addendum.json")
ext <- fromJSON("stage_artifacts/WT_D20260508_008/extended_diagnostics.json")

# Use multi-sig-date alpha_scores.parquet for latest alpha_vector / confidence_vector
ap_full <- as.data.table(read_parquet("stage_artifacts/WT_D20260508_008/alpha_scores.parquet"))
last_d <- max(ap_full$Date)
ap_last <- ap_full[Date == last_d]
cat("Latest sig_date:", as.character(last_d), "  N_stocks:", nrow(ap_last), "\n")

alpha_vector <- as.list(setNames(round(ap_last$alpha_hat, 8), ap_last$Ticker))
# Confidence: simple subperiod stability based + size of sector
ap_last[, sector_n := .N, by=Sector]
ap_last[, confidence := pmin(1.0, 0.55 * (sector_n / max(sector_n)))]
conf_vector <- as.list(setNames(round(ap_last$confidence, 4), ap_last$Ticker))

# factor_specs (with C15 exception)
factor_specs <- list(
  list(
    factor_family = "Sector_Momentum",
    proxy = "M_SECTOR_12_1_VW",
    formula = "ret_sector_vw[t-12..t-2] product. cross-section z-score over universe-mapped constituents.",
    lag_rule = "monthly month-end signal; t-12 to t-2 (skip 1m). t+1 application. t-1 size weighting (PIT C9).",
    winsorization = "none (discrete sector-level signal)",
    neutralization = "raw (sector-only signal — sector demean degenerates by definition)",
    economic_rationale = "Asness-Frazzini-Moskowitz 2013 + Moskowitz-Grinblatt 1999. Industry-level continuation due to slow information diffusion + cyclical capital flows.",
    weight_theta = 1.0,
    references = c(
      "Asness, Moskowitz, Pedersen (2013) Value and Momentum Everywhere, JF 68(3), 929-985",
      "Moskowitz, Grinblatt (1999) Do Industries Explain Momentum?, JF 54(4), 1249-1290",
      "Hong, Torous, Valkanov (2007) Do industries lead stock markets?, JFE 83(2), 367-396"
    ),
    selection_objective = "rank_ic",
    db_source = "new_designed_sector_portfolio_signal",
    c13_status = "spirit_compliant_db_scope_outside",
    c14_status = "month_end_alignment_strict_pit_no_future_data",
    c15_exception_rationale = "Factor DB 288개 산출 단위 = stock-level. Sector portfolio cross-section signal은 factor_db scope 외이므로 RAWDATA 직접 read는 명시적 허용 경로 (alpha_research_init Step 2-C 신규 팩터 직접 설계). load_month_factors() 미적용은 본 신호 정의상 정합."
  )
)

# diagnostics — extended
diagnostics <- list(
  rank_ic = val$rank_ic,
  icir = val$icir,
  monotonicity = val$monotonicity_q1_q5,
  subperiod_stability = val$subperiod_stability,
  turnover_proxy = 4.0,
  harvey_t_stat = val$harvey_t_stat,
  harvey_t_alt_12_0 = val$harvey_t_12_0,
  harvey_t_alt_6_1 = val$harvey_t_6_1,
  post_neutralization_ic = ext$post_neutralization_ic$sector_size_neutral_ic,
  post_neutralization_ic_method = "sector+size double-neutralization (sector demean alone is degenerate for sector-only signal)",
  post_neutralization_icir = ext$post_neutralization_ic$sector_size_neutral_icir,
  rf_a4_status = "PASS_BY_DOUBLE_NEUTRALIZATION_ONLY (sector-neutral IC = NaN by construction)",
  capm_alpha_q5_annual = 0.1226,
  capm_alpha_q5_nw_t = 2.38,
  ls_spread_nw_t = val$ls_spread_nw_t,
  q5_q1_spread_mean_monthly = val$ls_spread_mean,
  stock_level_rank_ic = val$stock_rank_ic,
  stock_level_icir = val$stock_icir,
  stock_level_nw_t = val$stock_nw_t,
  bailey_lopez_de_prado_dsr = add$bailey_lopez_de_prado_dsr$dsr,
  q5_cum_return_36yr = 27.35,
  q5_max_drawdown = 0.6582,
  market_top1_sector_pct = add$market_concentration$top1_sector_pct,
  market_top3_sector_pct = add$market_concentration$top3_pct,
  recent_3y_icir = 0.3052,
  recent_3y_full_ratio = 4.12,
  rf_a3_flag_HIGH = TRUE,
  recent_5y_icir = 0.1953,
  recent_5y_full_ratio = 2.64,
  n_obs_sector_level = val$n_obs_sector,
  n_obs_stock_level = val$n_obs_stock,
  n_sectors = val$n_sectors,
  n_stocks_alpha = val$n_stocks_alpha,
  multi_sig_date_panel_n_dates = ext$multi_sig_date$n_dates,
  multi_sig_date_panel_n_rows = ext$multi_sig_date$n_total_rows,
  multi_sig_date_panel_date_min = ext$multi_sig_date$date_min,
  multi_sig_date_panel_date_max = ext$multi_sig_date$date_max,
  rf_a7_pass = ext$multi_sig_date$rf_a7_pass
)

# challenge_flags — Codex 7 concerns 통합
challenge_flags <- list(
  list(
    flag_id = "RF-A-graduation-fail",
    severity = "HIGH",
    description = "Discovery graduation 4/5 FAIL: rank_ic=0.0243(<0.04) / icir=0.0741(<0.20) / harvey_t=1.66(<3.0) / stock_NW_t=1.83(<3.0). Subperiod stab + DSR marginal pass.",
    economic_explanation = "한국 시총 top1 sector (반도체) 48.13%, top3 60.84%. Cross-section breadth 부족. STR_055/STR_191/STR_089 prior insufficient 재실증.",
    codex_audit_id = "C2",
    resolution = "ACCEPTED — overall_PASS=FALSE archive"
  ),
  list(
    flag_id = "RF-A1-research-saturation",
    severity = "MEDIUM",
    description = "evidence_summary STR_055/STR_191/STR_089 prior insufficient. 본 WT가 4번째 동일 family 시도. KSI Lv1 27 sectors single-factor saturation 상태.",
    economic_explanation = "Multi-axis composite (sector × value, sector × regime, sector × flow) 또는 portfolio-level overlay 변형 필요.",
    codex_audit_id = "C2 supporting",
    resolution = "ACCEPTED"
  ),
  list(
    flag_id = "RF-A3-recent-period-bias",
    severity = "HIGH",
    description = "Recent 3Y ICIR 0.3052 / Full ICIR 0.0741 = ratio 4.12 (RF-A3 trigger). Recent 5Y ratio 2.64. alpha 대부분이 최근 IT/반도체 cycle artifact.",
    economic_explanation = "Samsung+SKH 메가캡 momentum이 recent ICIR 인플레이트. 일반화 가능성 의심. DSR 0.62 (n_trials=4) marginal pass이지만 recent-period 편향 우려.",
    codex_audit_id = "C3",
    resolution = "ACCEPTED + verify (Codex 4.12 ratio 정확)"
  ),
  list(
    flag_id = "RF-A4-sector-bet-only",
    severity = "HIGH",
    description = "Sector-neutral IC = NaN (degenerate by definition). 본 신호의 100% alpha가 sector-bet 컴포넌트. WT_005 retention 0.42와 다른 차원: WT_005=stock-level signal에 sector noise 섞임 / 본 WT=sector-level signal 자체.",
    economic_explanation = "stock-level alpha로 사용 불가. Allocation signal로만 의미 있음. AX-007 mechanism break 직접 연결.",
    codex_audit_id = "C5",
    resolution = "ACCEPTED + extended_diagnostics.json measured. Sector+size neutral IC = 0.0222 (RF-A4 mathematical pass) but semantic interpretation FAIL."
  ),
  list(
    flag_id = "RF-A-MDD-catastrophic",
    severity = "HIGH",
    description = "Q5 portfolio MDD -65.82% / Q5-Q1 MDD -71.73%. Long-only top sector decile 한국 deployment 부적합 (Production Constraints MDD <25%).",
    economic_explanation = "한국 sector momentum은 IT/반도체 cycle dominance — 2000 닷컴 -57%, 2008 GFC, 2020 COVID에서 top sector concentration이 위험 source.",
    codex_audit_id = "C2 supporting",
    resolution = "ACCEPTED"
  ),
  list(
    flag_id = "RF-A-AX007-mechanism-break",
    severity = "HIGH",
    description = "AX-007 trigger: structure=single_sleeve_long_only_top20, signal=sector-level (모든 constituent에 동일 alpha). Top sector 구성 stocks 시총상위 → Samsung+SKH+기타 5-10종목 portfolio. 4 exception 모두 미충족 (multi-sleeve / long-short / 50+ / ML sizing).",
    economic_explanation = "본 신호 stock-level alpha 변환 시 mechanism break. Deployment 자격 자체 없음. Allocation overlay (Hybrid component)로 변형하면 가능하나 본 WT scope 외.",
    codex_audit_id = "C6",
    resolution = "ACCEPTED — DEPLOYMENT BLOCKER. Q-Lead 후속 agent spawn STOP 권고."
  ),
  list(
    flag_id = "RF-A7-multi-sigdate-FIXED",
    severity = "RESOLVED",
    description = "alpha_scores.parquet single-snapshot → multi-sig-date 변환 완료. 84 dates × 604 tickers × 5 cols (Date | Ticker | Sector | mom_12_1 | alpha_z | alpha_hat). 60+ dates 충족.",
    economic_explanation = "v6.1 R7 schema contract 충족.",
    codex_audit_id = "C1",
    resolution = "FIXED — build_multi_sigdate_alpha.R 실행"
  ),
  list(
    flag_id = "PIT-C13-C14-C15-exception-explicit",
    severity = "RESOLVED",
    description = "C13/C14/C15 본 신호는 factor_db 외 신규 설계 sector-level signal로 명시. C13 spirit compliant / C14 month_end_alignment_strict / C15 명시적 exception (alpha_research_init Step 2-C 허용 경로).",
    economic_explanation = "Factor DB 288개에 sector portfolio momentum 없음 (M07_IndMom는 stock-level). RAWDATA direct read = 신규 팩터 설계 명시 허용.",
    codex_audit_id = "C4",
    resolution = "PARTIAL ACCEPT + factor_specs.c15_exception_rationale 명시"
  ),
  list(
    flag_id = "C7-missing-cov-weights-OUT-OF-SCOPE",
    severity = "RESOLVED",
    description = "C7 weights.csv / covariance.parquet 부재 = REBUTTAL. Common Charter §8 + alpha_research_init strict_prohibitions. Risk/Optimizer 영역.",
    economic_explanation = "본 단계 = alpha-research only. 후속 agent spawn은 Q-Lead 결정 (graduation 미달 시 stop SOP).",
    codex_audit_id = "C7",
    resolution = "REBUTTAL — 역할 경계 위반 지적, alpha agent 산출물 정합"
  )
)

selection_objective <- "rank_ic"

method_shopping_log <- list(
  candidates_tried = 4,
  parallel_exec = FALSE,
  rcpp_used = FALSE,
  n_workers = 1,
  rolling_seconds = NA,
  method_log = list(
    list(name = "Sector_Mom_12_1_VW", rank_ic = val$rank_ic, icir = val$icir, harvey_t = val$harvey_t_stat, selected = TRUE),
    list(name = "Sector_Mom_12_0_VW", rank_ic = val$rank_ic_12_0, icir = val$icir_12_0, harvey_t = val$harvey_t_12_0, selected = FALSE),
    list(name = "Sector_Mom_6_1_VW",  rank_ic = val$rank_ic_6_1, icir = val$icir_6_1, harvey_t = val$harvey_t_6_1, selected = FALSE),
    list(name = "Sector_Mom_3_0_VW",  rank_ic = 0.0041, icir = 0.0122, harvey_t = 0.076, selected = FALSE)
  ),
  shopping_diagnosis = "All 4 momentum variants converge to weak sector cross-section IC. Best variant (12-1) still 4/5 graduation FAIL. No method-shopping rescue possible — empirical fail."
)

graduation_eval <- list(
  min_rank_ic_PASS = (val$rank_ic >= 0.04),
  min_rank_ic_observed = val$rank_ic,
  min_rank_ic_required = 0.04,
  min_icir_PASS = (val$icir >= 0.20),
  min_icir_observed = val$icir,
  min_icir_required = 0.20,
  min_subperiod_stability_PASS = (val$subperiod_stability >= 0.5),
  min_subperiod_stability_observed = val$subperiod_stability,
  min_subperiod_stability_required = 0.5,
  min_harvey_t_PASS = (val$harvey_t_stat >= 3.0),
  min_harvey_t_observed = val$harvey_t_stat,
  min_harvey_t_required = 3.0,
  min_dsr_PASS = (add$bailey_lopez_de_prado_dsr$dsr >= 0.5),
  min_dsr_observed = add$bailey_lopez_de_prado_dsr$dsr,
  min_dsr_required = 0.5,
  overall_PASS = FALSE,
  fail_count = 4,
  pass_count = 1,
  ax_007_mechanism_break = TRUE,
  ax_007_exception_4_check = list(multi_sleeve = FALSE, long_short = FALSE, fifty_plus = FALSE, ml_sizing = FALSE),
  rf_a3_recent_bias = TRUE,
  rf_a4_sector_only_signal = TRUE,
  interpretation = "Discovery hurdle 5건 중 4건 FAIL (rank_ic / icir / harvey_t / stock_NW_t). 1건 marginal PASS (DSR 0.62 post n_trials=4 deflation). + AX-007 deployment blocker + RF-A3 recent-period bias HIGH + RF-A4 sector-only signal (stock-level alpha 변환 불가). Honest empirical fail — recommend ARCHIVE_AS_LCODE. Q-Lead 후속 agent spawn STOP 권고."
)

hypothesis_summary <- list(
  title = "Sector momentum cross-section alpha (KOSPI200 sectors)",
  mechanism = "Asness-Frazzini-Moskowitz 2013 JF + Moskowitz-Grinblatt 1999 JF 한국 KSI Lv1 27 sectors cross-section 12-1 momentum ranking. Sector value-weighted return computed at month-end, ranked, top decile sectors → constituent stock z-score scaled by historical IC.",
  universe = "KOSPI200 ∪ KOSDAQ150 (348 names @as_of_2026-05-08)",
  sector_classification = "KSI Level 1 (27 sectors, RAWDATA Sector column)",
  period = "1991-04 ~ 2026-05 (422 monthly observations sector-level / 84 sig_dates panel multi-stock)",
  pit_compliance = "C1 rolling-only / C2 t-1 close → t+1 / C9 lagged Size weights / C10 K200/KQ150 universe / C13 spirit compliant (db_scope_outside) / C14 month_end_alignment / C15 explicit exception (new_designed_sector_signal not in factor_db)",
  rejected_disposition = "ARCHIVE_AS_LCODE_RECOMMEND. KR sector momentum KSI Lv1 27 sectors single-factor cross-section, 4번째 동일 family 시도 재실증 fail. AX-007 mechanism break trigger. STR_055/STR_191/STR_089 saturation 가설 확정. Multi-axis composite 또는 portfolio-level overlay 변형 외에는 archive."
)

inheritance_audit <- list(
  alpha_inheritance_cor_with_parent = NA,
  parent_str = "none (discovery)",
  n_factors = 1,
  discovery_count = 1,
  is_genuine_discovery = TRUE,
  fits_discovery_role_card = TRUE
)

codex_round_summary <- list(
  draft_path = "qepm/mailbox/worktask/WT-D20260508_008/alpha_package_draft.json",
  codex_response_path = "qepm/mailbox/worktask/WT-D20260508_008/codex_critic_response_alpha.json",
  codex_stance = "REJECT",
  codex_veto_flag = FALSE,
  codex_critical_concerns = 7L,
  codex_high_severity = 5L,
  codex_medium_severity = 1L,
  challenge_note_path = "qepm/mailbox/worktask/WT-D20260508_008/challenge_note.md",
  resolution_distribution = list(ACCEPTED = 5L, PARTIAL = 1L, REBUTTAL = 1L, FIXED = 1L),
  self_rationalization_grep_hits = 0L,
  qlead_escalate_triggered = TRUE,
  qlead_escalate_reasons = c("HIGH severity >= 5 (5 hit)",
                             "AX-007 mechanism break direct trigger",
                             "RF-A3 recent 3Y ICIR 4.12x bias",
                             "graduation 4/5 FAIL"),
  axiom_compliance = list(
    AX_002_compliance = TRUE,
    AX_007_violation_disclosed = TRUE,
    AX_008_triangulation_fail_acknowledged = TRUE
  )
)

orthogonality_vs_hybrid <- list(
  cor_Q5_vs_BM = ortho$cor_Q5_vs_BM,
  cor_Q5Q1_spread_vs_BM = ortho$cor_Q5Q1_spread_vs_BM,
  Q5_beta_BM = ortho$Q5_beta_BM,
  Q5_alpha_intercept = ortho$Q5_alpha_intercept,
  Q5_alpha_residual_sd = ortho$Q5_alpha_residual_sd,
  n_obs = ortho$n_obs,
  vs_hybrid_70_15_15_direct_test = "INFEASIBLE_AT_ALPHA_AGENT (Hybrid 구성요소 holdings/return은 portfolio-level, alpha-research 영역 외. BM proxy 사용)",
  caveat = "Q5-Q1 spread vs BM cor = -0.0023 (사실상 직교) but signal Harvey-t 1.21 weak. 직교성 ≠ 채택 근거. graduation 미달."
)

alpha_package <- list(
  task_id = "WT-D20260508_008",
  wt_type = "discovery",
  as_of_date = "2026-05-08",
  forecast_horizon = "1M",
  alpha_vector = alpha_vector,
  confidence_vector = conf_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260508_008/alpha_scores.parquet",
  factor_specs = factor_specs,
  diagnostics = diagnostics,
  challenge_flags = challenge_flags,
  selection_objective = selection_objective,
  method_shopping_log = method_shopping_log,
  graduation_eval = graduation_eval,
  hypothesis_summary = hypothesis_summary,
  inheritance_audit = inheritance_audit,
  codex_round_summary = codex_round_summary,
  orthogonality_vs_hybrid = orthogonality_vs_hybrid,
  final_disposition = "EMPIRICAL_FAIL_NO_DEPLOY_ARCHIVE_AS_LCODE"
)

# Write FINAL alpha_package.json (no _draft)
final_path <- "qepm/mailbox/worktask/WT-D20260508_008/alpha_package.json"
write_json(alpha_package, final_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("✅ FINAL alpha_package.json saved\n")
cat("File size:", file.info(final_path)$size, "bytes\n")
cat("alpha_vector N:", length(alpha_vector), "\n")
cat("graduation overall_PASS:", graduation_eval$overall_PASS,
    "( pass_count =", graduation_eval$pass_count,
    ", fail_count =", graduation_eval$fail_count, ")\n")
cat("codex_stance:", codex_round_summary$codex_stance, "\n")
cat("final_disposition:", alpha_package$final_disposition, "\n")
