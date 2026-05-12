suppressMessages({library(arrow); library(data.table); library(jsonlite)})
diag <- readRDS("stage_artifacts/WT_D20260508_008/wt008_full_diagnostics.rds")
ap <- diag$alpha_out
val <- fromJSON("stage_artifacts/WT_D20260508_008/alpha_validation.json")
ortho <- fromJSON("stage_artifacts/WT_D20260508_008/orthogonality_vs_hybrid.json")
add <- fromJSON("stage_artifacts/WT_D20260508_008/diagnostic_addendum.json")

ap2 <- as.data.table(ap)
alpha_vector <- as.list(setNames(round(ap2$alpha_hat, 8), ap2$Ticker))
conf_vector  <- as.list(setNames(round(ap2$confidence, 4), ap2$Ticker))

factor_specs <- list(
  list(
    factor_family = "Sector_Momentum",
    proxy = "M_SECTOR_12_1_VW",
    formula = "ret_sector_vw[t-12..t-2] product. cross-section rank within universe. PIT t signal -> t+1 stock alpha.",
    lag_rule = "monthly month-end signal; t-12 to t-2 (skip 1m). t+1 application. t-1 size weighting.",
    winsorization = "none (discrete sector ranks)",
    neutralization = "raw (no neutralization at sector level)",
    economic_rationale = "Asness-Frazzini-Moskowitz 2013 + Moskowitz-Grinblatt 1999. Industry-level continuation due to slow information diffusion + cyclical capital flows.",
    weight_theta = 1.0,
    references = c(
      "Asness, Moskowitz, Pedersen (2013) Value and Momentum Everywhere, JF 68(3)",
      "Moskowitz, Grinblatt (1999) Do Industries Explain Momentum?, JF 54(4)",
      "Hong, Torous, Valkanov (2007) Do industries lead stock markets?, JFE 83(2)"
    ),
    selection_objective = "rank_ic"
  )
)

diagnostics <- list(
  rank_ic = val$rank_ic,
  icir = val$icir,
  monotonicity = val$monotonicity_q1_q5,
  subperiod_stability = val$subperiod_stability,
  turnover_proxy = 4.0,
  harvey_t_stat = val$harvey_t_stat,
  harvey_t_alt_12_0 = val$harvey_t_12_0,
  harvey_t_alt_6_1 = val$harvey_t_6_1,
  post_neutralization_ic = val$rank_ic,
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
  n_obs_sector_level = val$n_obs_sector,
  n_obs_stock_level = val$n_obs_stock,
  n_sectors = val$n_sectors,
  n_stocks_alpha = val$n_stocks_alpha
)

challenge_flags <- list(
  list(
    flag_id = "RF-A-graduation-fail",
    severity = "HIGH",
    description = "Graduation criteria 4/5 FAIL: rank_ic=0.0243 (<0.04) / icir=0.0741 (<0.20) / harvey_t=1.66 (<3.0) / stock_NW_t=1.83 (<3.0).",
    economic_explanation = "한국 KOSPI200∪KOSDAQ150 시총 top1 sector (반도체) = 48.13%, top3 = 60.84%. Cross-section sector breadth 부족."
  ),
  list(
    flag_id = "RF-A1-research-saturation",
    severity = "MEDIUM",
    description = "evidence_summary STR_055/STR_191/STR_089 모두 prior insufficient. 본 WT가 4번째 동일 family 시도.",
    economic_explanation = "Sector momentum family는 한국 KSI Lv1 27 sectors universe에서 실증 saturation 상태."
  ),
  list(
    flag_id = "RF-A4-monotonicity-marginal",
    severity = "MEDIUM",
    description = "Q1 0.69%/m → Q5 1.16%/m, monotonicity 0.0047. Q3-Q4 inversion. Spread NW-t 1.21.",
    economic_explanation = "쿼인타일 평균 increasing이지만 tight하며 통계 유의성 약함."
  ),
  list(
    flag_id = "RF-A-MDD-catastrophic",
    severity = "HIGH",
    description = "Q5 portfolio MDD -65.82% / Q5-Q1 MDD -71.73%. Long-only top sector decile 한국 deployment 부적합.",
    economic_explanation = "한국 sector momentum은 IT/반도체 cycle dominance — 2000 닷컴, 2008 GFC, 2020 COVID에서 top sector concentration 자체가 위험."
  ),
  list(
    flag_id = "RF-A-orthogonality-vs-hybrid-not-decisive",
    severity = "MEDIUM",
    description = "Q5-Q1 spread vs BM cor = -0.0023 (직교) BUT signal 자체가 약함 (Harvey-t < 3.0). 직교성 ≠ 채택 근거.",
    economic_explanation = "BM 대비 직교성만 측정 가능. Hybrid 70/15/15 직접 직교성은 Risk agent 영역."
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
  )
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
  interpretation = "Discovery hurdle 5건 중 4건 FAIL (rank_ic / icir / harvey_t / stock_NW_t). 1건 PASS (DSR marginal post-deflation, subperiod stability marginal). Single-factor sector momentum at KSI Lv1 universe is empirically insufficient for KR market deployment. Honest empirical fail."
)

hypothesis_summary <- list(
  title = "Sector momentum cross-section alpha (KOSPI200 sectors)",
  mechanism = "Asness-Frazzini-Moskowitz 2013 JF + Moskowitz-Grinblatt 1999 JF 한국 KSI Lv1 27 sectors cross-section 12-1 momentum ranking. Sector value-weighted return computed at month-end, ranked, top decile sectors → constituent stock z-score scaled by historical IC.",
  universe = "KOSPI200 ∪ KOSDAQ150 (348 names @as_of)",
  sector_classification = "KSI Level 1 (27 sectors, RAWDATA Sector column)",
  period = "1991-04 ~ 2026-05 (422 monthly observations)",
  pit_compliance = "C1 rolling-only / C2 t-1 close → t+1 / C9 lagged Size weights / C10 K200/KQ150 universe / C13 raw / C14 usable_date <= sig_date / C15 RAWDATA direct (sector-level signal not in factor_db)"
)

inheritance_audit <- list(
  alpha_inheritance_cor_with_parent = NA,
  parent_str = "none (discovery)",
  n_factors = 1,
  discovery_count = 1
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
  inheritance_audit = inheritance_audit
)

draft_path <- "qepm/mailbox/worktask/WT-D20260508_008/alpha_package_draft.json"
write_json(alpha_package, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("alpha_package_draft.json saved at:", draft_path, "\n")
cat("File size:", file.info(draft_path)$size, "bytes\n")
cat("alpha_vector N:", length(alpha_vector), "\n")
cat("graduation overall_PASS:", graduation_eval$overall_PASS, " (", graduation_eval$pass_count, "/5)\n")
