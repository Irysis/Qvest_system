#==============================================================================
# Build alpha_package_draft.json for WT-D20260428_003 Iter 10 B (MAQGC)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260428_003"

panel <- readRDS(file.path(WT_DIR, "alpha_panel.rds"))
asof <- panel[sig_date == as.Date("2023-10-31")][order(-alpha)]
top50 <- head(asof, 50)
av <- as.list(setNames(round(top50$alpha, 4), top50$Ticker))
cv <- as.list(setNames(round(1/(1+exp(-1.5*top50$alpha)), 4), top50$Ticker))

pkg <- list(
  task_id = "WT-D20260428_003",
  wt_type = "discovery",
  iter = 10L,
  iter_track = "B",
  iter_name = "MAQGC_Multi_Axis_Growth_Quality_Composite",
  agent = "alpha_research_v1.2",
  agent_model = "Opus 4.7 (1M context)",
  pg1_eligibility = "certificate_required",
  discovery_of = setNames(list(), character(0)),
  parent_iters_archived = list(
    STR_1631_SYN_05 = "WT-D20260425_010 (Iter 5 multi-sleeve composite)",
    STR_1701 = "WT-D20260426_004 (Iter 11 Linear Tilt)",
    STR_1715 = "WT-D20260427_016 (Iter 31 grid sweep — current PG2 100%)"
  ),
  baseline_pg2 = "STR_1715 100% (User OVERRIDE_006 mandate)",
  signal_as_of = "2023-10-31",
  signal_as_of_note = "Originally requested 2023-11-30; pipeline month-end mapping resulted in 2023-10-31 fallback (1M shift). Forward 1M return ends 2023-11-30 — PIT-safe.",
  forecast_horizon = "1M",
  rebalance_frequency = "monthly",
  selection_objective = "icir",
  hypothesis_title = "KR Multi-Axis Growth Quality Composite (MAQGC) — AFP 2019 QMJ KR-adapted",
  hypothesis_summary = paste(
    "Iter 10 B-track parallel discovery — family-orthogonal to FIAPAS",
    "(investor_flow / liquidity_diffusion / accrual). MAQGC family =",
    "quality_multi_axis × growth. AX-004 named EXCLUSION (multi-axis quality",
    "composite + multi-sleeve permitted) honored via 4-axis composite. Ex-ante",
    "4 axes pre-registered with sign +1 each: (A1) Profitability =",
    "z(GPA + ROIC + NetMargin), (A2) Growth = z(RevenueGrowth + EarningsGrowth +",
    "SustainableGrowth), (A3) Safety = z(-DebtToEquity + EarningsStability),",
    "(A4) CashFlowQuality = z(CFOA - Accrual). Composite = mean(A1..A4)",
    "equal-weight, no tuning. n_candidates_tried=3 (S1 ALL, S2 Prof+Safe,",
    "S3 Prof+Grow as alternative spec sweeps)."
  ),
  primary_variant = "S1_ALL_4axes_HONEST_RESULT_FAIL",
  alternative_variants_documented = list(
    S1_ALL_4axes = list(
      sign_axis = "all +1 ex-ante",
      mechanism_citation = paste(
        "Asness-Frazzini-Pedersen (2019 RAS) Quality Minus Junk multi-axis composite /",
        "Lakonishok-Shleifer-Vishny (1994 JF) growth quality contrarian /",
        "Sloan (1996 AR) accrual reliability inverse / Dechow-Dichev (2002 AR) earnings quality"
      ),
      diagnostics = list(
        rank_ic = 0.01883,
        ic_sd = 0.0994,
        icir = 0.6561,
        nw_t_lag3 = 1.7821,
        harvey_t_stat_pooled = 1.7821,
        monotonicity_rank_cor = 0.3455,
        d10_d1_spread = -0.00106,
        decile_max_at = 9L,
        subperiod_stability = 1.0,
        subperiod_ics = list(
          p1_2008_2014 = list(rank_ic = 0.0392, icir = 1.387, n_months = 27L),
          p2_2015_2019 = list(rank_ic = 0.00226, icir = 0.071, n_months = 22L),
          p3_2020_2023 = list(rank_ic = 0.00788, icir = 0.318, n_months = 17L)
        ),
        alpha_inheritance_cor_vs_Q08_proxy = 0.7155,
        n_months_evaluated = 66L,
        turnover_proxy_monthly = NA,
        dsr_pre = 0.656,
        dsr_post = 0.5872,
        n_candidates_tried = 3L
      ),
      result = "rank_ic=0.0188 / icir=0.656 / Harvey_t=1.78 / D10-D1 spread NEGATIVE / cert_4cond=3/4 PASS",
      verdict = paste(
        "FAIL — rank_ic 0.0188 < 0.04 graduation min, Harvey_t 1.78 < 3.0",
        "graduation min, D10-D1 spread NEGATIVE (decile 9=max, decile 10 reversion),",
        "subperiod severe decay (p1 ICIR 1.39 → p2 0.07 → p3 0.32). Multi-axis composite",
        "alpha exists in p1 but underwhelming since 2015 in KR; long-only top20 deployment",
        "risk HIGH (negative D10-D1 spread)."
      )
    ),
    S2_Prof_Safety = list(
      mechanism = "Drop Growth + CFQ axes; pure Profitability + Safety (AFP 2019 narrowed)",
      diagnostics = list(rank_ic = 0.00695, icir = 0.255, nw_t = 0.774),
      result = "FAIL — IC essentially zero. Safety axis (low D/E + earnings stability) dilutes profitability signal in KR."
    ),
    S3_Prof_Growth = list(
      mechanism = "Profitability + Growth only (omit Safety + CFQ)",
      diagnostics = list(rank_ic = 0.01573, icir = 0.466, nw_t = 1.208),
      result = "FAIL — Harvey_t 1.21 < 3.0 (closest spec to S1). Suggests profitability dominates, growth/CFQ marginally additive."
    )
  ),
  alpha_vector = av,
  confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts://WT_D20260428_003/alpha_scores.parquet",
  factor_specs = list(
    list(
      name = "S1_MAQGC_4axes_ALL",
      family = "quality_multi_axis × growth",
      axis_definitions = list(
        A1_Profitability = list(formula = "z(GPA + ROIC + NetMargin)/3", sign = "+1", citation = "AFP 2019 QMJ profitability axis"),
        A2_Growth = list(formula = "z(RevenueG + EarningsG + SustainableG)/3", sign = "+1", citation = "Lakonishok-Shleifer-Vishny 1994 contrarian growth quality"),
        A3_Safety = list(formula = "z(-D/E + EarningsStab)/2", sign = "+1", citation = "AFP 2019 safety axis (low leverage + stable earnings)"),
        A4_CashFlowQuality = list(formula = "z(CFOA - Accrual)/2", sign = "+1", citation = "Sloan 1996 accrual inverse / Dechow-Dichev 2002 earnings quality")
      ),
      composite = "mean(A1, A2, A3, A4) equal-weight ex-ante",
      rank_ic = 0.01883,
      icir = 0.6561,
      harvey_t = 1.7821,
      selected = TRUE
    ),
    list(
      name = "S2_Prof_Safety",
      family = "quality_multi_axis (narrow QMJ)",
      composite = "mean(A1, A3)",
      rank_ic = 0.00695,
      icir = 0.255,
      harvey_t = 0.774,
      selected = FALSE,
      source = "axis_pruning_alternative"
    ),
    list(
      name = "S3_Prof_Growth",
      family = "quality × growth (LSV1994 contrarian)",
      composite = "mean(A1, A2)",
      rank_ic = 0.01573,
      icir = 0.466,
      harvey_t = 1.208,
      selected = FALSE,
      source = "axis_pruning_alternative"
    )
  ),
  candidates_tried = list(
    list(name = "S1_MAQGC_4axes_ALL", rank_ic = 0.01883, t = 1.7821, selected = TRUE, source = "ex_ante_pre_registered"),
    list(name = "S2_Prof_Safety", rank_ic = 0.00695, t = 0.774, selected = FALSE, source = "axis_pruning"),
    list(name = "S3_Prof_Growth", rank_ic = 0.01573, t = 1.208, selected = FALSE, source = "axis_pruning")
  ),
  pit_compliance = list(
    C1 = "PASS — walk-forward only (per-month load via load_month_factors(sig_date))",
    C2 = "PASS — monthly forward return = close(month_end+1) / close(month_end) - 1",
    C3 = "PASS — per-month cross-sectional Z (no aggregate-then-apply)",
    C4 = "PASS — quarterly 45d / annual May enforced upstream by FactorDB",
    C5 = "N/A — no overlay used at alpha layer",
    C9 = "PASS — sig_date d → applied (d, d+1m] via month-end Close lead",
    C10 = "PASS — 20d AvgTV PIT t-30..t-1 one-sided + LIQ 5e7 floor (mandate)",
    C11 = "PASS — fundamental data lag enforced by FactorDB",
    C13 = "PASS — Z_Score_Aligned via FactorDB align_factor_direction (no manual flip)",
    C14 = "PASS — Usable_Date <= sig_date (FactorDB enforced)",
    C15 = "PASS — load_month_factors() / direct parquet via FactorDB pattern",
    note = "All 4 axes signs declared ex-ante BEFORE measurement (no method-shopping). Single primary spec S1 selected. S2/S3 retained as transparent alternative pruning record. n_candidates_tried=3 (DSR penalty budget ≤0.15 satisfied)."
  ),
  signal_processing_summary = list(
    sig_dates_processed_unique = 66L,
    sig_dates_processed_total_target = 191L,
    sig_dates_skipped_reason = "Insufficient factor coverage (< 7/10 axes available) for 125 months. Pre-2010 quarterly fundamental coverage thin in FactorDB.",
    universe_label = "KOSPI200_KOSDAQ150_intersection (K200 OR KQ150 == TRUE)",
    liquidity_floor_krw = 50000000L,
    coverage_min = 0.05,
    final_alpha_top_n = 50L,
    n_panel_rows_unique = 21650L,
    n_unique_tickers = 688L,
    asof_alpha_names = 50L,
    asof_alpha_universe_size_at_2023_10_31 = 344L
  ),
  optimizer_handoff_notes = list(
    "Alpha agent 산출물은 alpha_vector + confidence_vector + alpha_scores.parquet (full panel) 까지.",
    "Optimizer는 max_names=20 (user hard mandate), weight_bounds=[0, 1] enforce 해야 함.",
    "Risk Agent는 alpha_scores.parquet의 Ticker × score 신호로부터 covariance Σ + tail risk를 자체 추정 (alpha agent는 Σ 추정 금지).",
    "**WARNING**: D10-D1 spread NEGATIVE (-0.00106) — long-only top20 deployment carries risk of negative differential return. Optimizer should consider this signal as quality-tilt only, NOT as primary alpha source. Pairing with FIAPAS V2 (Iter 10 A) or STR_1701 incumbent recommended.",
    "Subperiod decay (p1 1.39 → p3 0.32 ICIR) suggests regime sensitivity; regime-conditional weighting at optimizer or risk layer recommended.",
    "Multi-axis quality 신호는 STR_1715 incumbent와 Q08_Composite_Quality 0.716 cor — 신규 alpha contribution 미미. Sizing 권고는 신호 보유 5-10% 이하."
  ),
  family_orthogonality = list(
    fiapas_family_avoided = c("investor_flow", "liquidity_diffusion", "accrual"),
    maqgc_family = c("quality_multi_axis", "growth"),
    cross_family_overlap = "minimal vs FIAPAS (accrual axis A4 uses Q05_Accrual fundamental quality, not flow-based; orthogonal to FIAPAS V2_F3 retail-accrual-MTC). HOWEVER vs Q08_Composite_Quality (parent quality proxy) cor 0.716 — quality-axis overlap with incumbent.",
    ax004_exclusion = "MULTI-AXIS COMPOSITE permitted by AX-004 EXCLUSION clause. 4-axis ex-ante pre-registered. Despite EXCLUSION, empirical IC remains weak in KR top342 universe — suggests EXCLUSION applies *eligibility* not *predictive power*."
  ),
  graduation_check = list(
    rank_ic_target = 0.04,
    rank_ic_actual = 0.01883,
    rank_ic_pass = FALSE,
    icir_target = 0.20,
    icir_actual = 0.656,
    icir_pass = TRUE,
    subperiod_target = 0.50,
    subperiod_actual = 1.00,
    subperiod_pass = TRUE,
    harvey_t_target = 3.0,
    harvey_t_actual = 1.7821,
    harvey_t_pass = FALSE,
    dsr_post_target = 0.50,
    dsr_post_actual = 0.5872,
    dsr_post_pass = TRUE,
    monotonicity_target = 0.80,
    monotonicity_actual = 0.3455,
    monotonicity_pass = FALSE,
    overall = "FAIL — rank_ic 0.019 < 0.04, Harvey_t 1.78 < 3.0, monotonicity 0.346 < 0.80 (D10-D1 negative spread). ICIR + subperiod + DSR PASS individually but composite graduation FAIL."
  ),
  cert_4cond_check = list(
    cond1_inheritance_cor_lt_095 = list(actual = 0.7155, target = 0.95, pass = TRUE, note = "vs Q08_Composite_Quality parent proxy. High but < 0.95 — composite shares quality-axis signal but distinct combination."),
    cond2_factor_specs_ge_1 = list(actual = 3L, target = 1L, pass = TRUE),
    cond3_mechanism_ge_50chars = list(actual_chars = 250L, target = 50L, pass = TRUE),
    cond4_harvey_pass_ge_3 = list(actual_count = 0L, target = 3L, pass = FALSE, breakdown = list(S1 = 1.78, S2 = 0.77, S3 = 1.21), note = "ALL 3 specs FAIL Harvey-t 3.0 threshold. Cannot certify multi-axis QMJ alpha in KR with current factor combination."),
    all_4cond_technical_pass = FALSE
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz="UTC"),
  pipeline_version = "alpha_research_v1.2_v6.31_charter"
)

write_json(pkg, file.path(WT_DIR, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, dataframe = "rows", null = "null")
cat("alpha_package_draft.json written\n")
cat(sprintf("Top 5: %s\n", paste(names(av)[1:5], collapse=", ")))
cat(sprintf("File size: %s bytes\n", file.info(file.path(WT_DIR, "alpha_package_draft.json"))$size))
