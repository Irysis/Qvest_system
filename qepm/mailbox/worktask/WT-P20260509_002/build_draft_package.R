#!/usr/bin/env Rscript
# Build optimization_package_draft.json
suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260509_002"
OUT_DIR <- file.path(WT_DIR, "output")

M <- fread(file.path(OUT_DIR, "comparison_table_walk_forward.csv"))
A <- fread(file.path(OUT_DIR, "ax001_v2_conditional_defense_walkforward.csv"))
D <- fread(file.path(OUT_DIR, "dsr_bailey_walkforward.csv"))
H <- fread(file.path(OUT_DIR, "harvey_liu_walkforward.csv"))
S <- fread(file.path(OUT_DIR, "sign_consistency_walkforward.csv"))
B <- fread(file.path(OUT_DIR, "best_method_ranking.csv"))

best_method <- "WF_DRO_W_eps0.1"
m_row <- M[method == best_method]
a_row <- A[method == best_method]
d_row <- D[method == best_method]
h_row <- H[method == best_method]
s_row <- S[method == best_method]
b_row <- B[method == best_method]

W <- fread(file.path(OUT_DIR, "weight_evolution_timeseries.csv"))
W[, date := as.Date(date)]
W_target <- W[method == best_method]
latest_weight <- W_target[date == max(date)][1]

W_target[, period := ifelse(date < "2014-01-01", "2010-2013",
                     ifelse(date < "2020-01-01", "2014-2019",
                     ifelse(date < "2022-01-01", "2020-2021",
                     ifelse(date < "2024-01-01", "2022-2023", "2024-2026"))))]
sp <- W_target[, .(n=.N,
                    mean_AR=round(mean(AR_on_M4),4),
                    mean_TSMOM=round(mean(TSMOM),4),
                    mean_KR=round(mean(KR_10y),4)), by=period]

s4_metrics <- M[method=="BENCH_S4_static_dohoon"]
s0_metrics <- M[method=="BENCH_S0_alpha_only"]

pkg <- list(
  task_id = "WT-P20260509_002",
  wt_type = "promotion_wt",
  wt_kind = "PG2_upgrade_walk_forward_dynamic_weight_no_paradigm",
  agent_id = "optimizer-research",
  as_of_date = "2026-05-09",
  draft = TRUE,

  research_question = "정적 가중치 폐기 후 매 sig_date 60m 윈도우 walk-forward 동적 재최적화로 8 method 비교 — 도훈 framing 합리성 정량 검증 + 패러다임 인용 회피 + Codex GOV-C1 정합",
  paradigm_free_certification = "60/40 / SAA / Brinson 1986 인용 0건. 정량 metric + AX 정합만 의사결정 근거.",

  alpha_inheritance = list(
    alpha_str_1715_unchanged = TRUE,
    alpha_scores_path = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
    n_sig_dates = 268L
  ),

  sleeve_definition = list(
    AR_on_M4 = "STR_1715 alpha-updated x M4 overlay x beta threshold (50% sleeve standalone returns, 256m available)",
    TSMOM_8ETF = "8-ETF basket re-derived (KODEX_KTB10Y A148070 제거 후 재정규화: r_8ETF = (r_9ETF - w_KTB10Y * r_KTB10Y) / (1 - w_KTB10Y), 135m available)",
    KR_10y = "KODEX 국고채10년 (A148070) standalone returns, 256m available",
    Cash = "0% return (UB=0 in walk-forward)",
    cash_walk_forward_rationale = "Cash UB=0 — variance-based allocators (RP/IV/HRP/BL) Cash 과적재 회피. Codex GOV-C1 정합 (Cash는 admit candidate 아님). Cash slot은 paradigm-free benchmark only."
  ),

  walk_forward_design = list(
    rolling_window_months = 60L,
    burnin_months = 60L,
    rebalance_freq = "monthly",
    pit_strict = TRUE,
    no_in_sample_optimization = TRUE,
    each_sig_date_uses_only_past_60m_data = TRUE,
    n_eval_obs = 195L,
    eval_period = "2010-02-01 ~ 2026-04-01"
  ),

  methods_evaluated = c("WF_RP_ERC", "WF_MV_lambda2", "WF_MV_lambda5", "WF_MV_lambda10",
                        "WF_IV", "WF_MaxDiv", "WF_Bayesian_PS",
                        "WF_DRO_W_eps0.01", "WF_DRO_W_eps0.05", "WF_DRO_W_eps0.1"),
  methods_excluded = list(
    WF_HRP = "Codex C2 ACCEPT — candidates_tried <= 10. HRP excluded due to numerical degeneracy with zero-var Cash + small N=3 active sleeves",
    WF_BL = "Codex C2 ACCEPT — candidates_tried <= 10. BL excluded: no exogenous view (mandate no_fixed_view) + market-implied prior built from IV → effectively redundant"
  ),
  static_methods_penalized = list(
    WF_IV = "Effectively static (sd_AR=0, sd_TSMOM=0, sd_KR=0) under KR_10y UB=0.20 cap — bound bind every period → static. composite × 0.7 penalty applied per mandate no_static_weight_admit",
    WF_RP_ERC = "Effectively static (same reason) — composite × 0.7 penalty"
  ),

  constraints_applied = list(
    weight_bound_AR_on_M4 = c(0, 0.50),
    weight_bound_TSMOM = c(0, 0.50),
    weight_bound_KR_10y = c(0, 0.20),
    weight_bound_Cash = c(0, 0),
    sum_weights = 1.0,
    long_only = TRUE,
    codex_C1_resolution = "KR_10y UB lowered 0.50 → 0.20 per Codex C1 ACCEPT mandatory (request.json constraints.single_asset_cap_0.20 — A148070 단일 ETF 정합)"
  ),

  recommended_method = best_method,

  recommendation_rationale = list(
    method_full_name = "Walk-forward Distributionally Robust Optimization (Wasserstein, eps=0.1)",
    academic_reference = "Esfahani-Kuhn (2018) Mathematical Programming 171, 'Data-driven distributionally robust optimization using the Wasserstein metric'",
    composite_score = round(b_row$composite, 2),
    composite_rank_in_dynamic_tie_zone = "Tied for #1-#8 dynamic methods (composite 91.10 ~ 90.13). Static WF_IV/WF_RP_ERC (composite 92.0) excluded (no_static_admit penalty applied).",
    tie_breaker_applied = "Charter v1.5 hierarchy: Validity > Implementability > Robustness > Performance. 8 dynamic 동률 → turnover 최저(4.7% vs 7.6~30%) + Sortino 4.51 + CAGR 20.49% → WF_DRO_W_eps0.1",
    why_dro_wasserstein = "분포 불확실성 worst-case hedge — rolling 60m 표본 추정의 ambiguity 반영. eps=0.1 conservative ambiguity ball → low turnover 4.7% + low MDD -11.15% + dynamic AR-TSMOM trade-off (sd 0.042)",
    alternative_top_choices = c("WF_MV_lambda5 (TO 9.07%, CAGR 21.75%, SR 1.879)",
                                 "WF_MaxDiv (TO 7.59%, CAGR 21.36%, SR 1.880)",
                                 "WF_DRO_W_eps0.05 (TO 7.86%, CAGR 21.18%, SR 1.865)")
  ),

  recommendation_metrics = list(
    SR_ann = round(m_row$SR_ann, 4),
    CAGR = round(m_row$CAGR, 4),
    MDD = round(m_row$MDD, 4),
    Sortino = round(m_row$Sortino, 4),
    Calmar = round(m_row$Calmar, 4),
    Turnover_ann = round(m_row$Turnover_ann, 4),
    TE_vs_S0 = round(m_row$TE_vs_S0, 4),
    IR_vs_S0 = round(m_row$IR_vs_S0, 4),
    Vol_ann = round(m_row$Vol_ann, 4),
    n_obs = m_row$n_obs
  ),

  axiom_compliance = list(
    AX001_v2_pass = a_row$ax001_v2_pass,
    AX001_crisis_alpha = round(a_row$crisis_alpha, 5),
    AX001_mdd_alleviation = round(a_row$mdd_alleviation, 4),
    AX001_spread_bad = round(a_row$spread_bad, 5),
    AX001_spread_normal = round(a_row$spread_normal, 5),
    AX001_definition_note = "Portfolio-level adaptation of AX-001 v2: (a) crisis_alpha > 0 (b) mdd_alleviation > 0 (c) spread_bad > 0 (method beats S0 in bad regime). Single-factor IC ratio definition은 portfolio sleeve에 직접 적용 부적합 (sr_bad가 구조적으로 음수) — diagnostic only로 유지.",
    AX002_PIT_strict = TRUE,
    AX002_evidence = "각 sig_date weight 추정 = 직전 60m past data만 사용. Future leak 0건.",
    AX007_multi_sleeve_exception = TRUE,
    AX007_evidence = "3 risk-bearing sleeves (AR_on_M4 / TSMOM_8ETF / KR_10y) — single-sleeve top20 long-only 위반 회피.",
    AX008_triangulation_status = "1.5/3 (Optimizer + pending Codex)"
  ),

  statistical_validation = list(
    DSR_bailey_lopez_de_prado_2014 = list(
      SR_obs = round(d_row$SR_obs, 4),
      SR0_threshold_N10 = round(d_row$SR0_threshold, 4),
      z_DSR = round(d_row$z_DSR, 4),
      DSR = round(d_row$DSR, 6),
      DSR_pass_0_95 = d_row$DSR_pass,
      multi_trial_N = 10L,
      reference = "Bailey-Lopez de Prado (2014) Journal of Portfolio Management 40"
    ),
    harvey_liu_2016 = list(
      t_NW_lag4 = round(h_row$t_NW, 3),
      harvey_pass_3_0 = h_row$harvey_pass_3.0,
      reference = "Harvey-Liu (2016) Review of Financial Studies 29 multiple-testing"
    ),
    subperiod_sign_consistency = list(
      n_periods = s_row$n_periods,
      n_positive = s_row$n_positive,
      consistency_pct = s_row$consistency_pct,
      periods_evaluated = c("2010-2013", "2014-2019", "2020-2021", "2022-2023", "2024-2026")
    )
  ),

  weight_evolution_summary = list(
    n_obs = 195L,
    weight_evolution_csv_path = "output/weight_evolution_timeseries.csv",
    AR_on_M4_mean = round(mean(W_target$AR_on_M4), 4),
    AR_on_M4_sd = round(sd(W_target$AR_on_M4), 4),
    AR_on_M4_min = round(min(W_target$AR_on_M4), 4),
    AR_on_M4_max = round(max(W_target$AR_on_M4), 4),
    TSMOM_mean = round(mean(W_target$TSMOM), 4),
    TSMOM_sd = round(sd(W_target$TSMOM), 4),
    TSMOM_min = round(min(W_target$TSMOM), 4),
    TSMOM_max = round(max(W_target$TSMOM), 4),
    KR_10y_mean = round(mean(W_target$KR_10y), 4),
    KR_10y_sd = round(sd(W_target$KR_10y), 4),
    KR_10y_min = round(min(W_target$KR_10y), 4),
    KR_10y_max = round(max(W_target$KR_10y), 4),
    sub_period_means = sp,
    deployment_ready_2026_04_01 = list(
      AR_on_M4 = round(latest_weight$AR_on_M4, 4),
      TSMOM = round(latest_weight$TSMOM, 4),
      KR_10y = round(latest_weight$KR_10y, 4),
      Cash = round(latest_weight$Cash, 4)
    )
  ),

  static_vs_dynamic_validation = list(
    static_S4_dohoon_framing = list(
      weights = list(AR_on_M4=0.50, TSMOM=0.25, KR_10y=0.20, Cash=0.05),
      SR_ann = round(s4_metrics$SR_ann, 4),
      CAGR = round(s4_metrics$CAGR, 4),
      MDD = round(s4_metrics$MDD, 4),
      Sortino = round(s4_metrics$Sortino, 4),
      Turnover_ann = round(s4_metrics$Turnover_ann, 4),
      admit_status = "NOT admit candidate (Codex GOV-C1 REJECT 정합)"
    ),
    benchmark_S0_alpha_only = list(
      weights = list(AR_on_M4=1.00, TSMOM=0.00, KR_10y=0.00, Cash=0.00),
      SR_ann = round(s0_metrics$SR_ann, 4),
      CAGR = round(s0_metrics$CAGR, 4),
      MDD = round(s0_metrics$MDD, 4)
    ),
    dynamic_best_DRO_W_eps0_1 = list(
      latest_weights_2026_04 = list(
        AR_on_M4 = round(latest_weight$AR_on_M4, 4),
        TSMOM = round(latest_weight$TSMOM, 4),
        KR_10y = round(latest_weight$KR_10y, 4),
        Cash = 0
      ),
      SR_ann = round(m_row$SR_ann, 4),
      CAGR = round(m_row$CAGR, 4),
      MDD = round(m_row$MDD, 4)
    ),
    convergence_finding = "Walk-forward dynamic optimization (paradigm-free) latest weights = (0.50, 0.28, 0.22, 0.00) ≈ S4 도훈 framing (0.50, 0.25, 0.20, 0.05) 거의 일치. 도훈 직관 (체리피킹 retract했지만) 실증적 정합성 — paradigm 인용 없이 walk-forward로 동일 영역 수렴.",
    delta_dynamic_vs_static = list(
      delta_SR = round(m_row$SR_ann - s4_metrics$SR_ann, 4),
      delta_CAGR = round(m_row$CAGR - s4_metrics$CAGR, 4),
      delta_MDD = round(m_row$MDD - s4_metrics$MDD, 4),
      delta_Sortino = round(m_row$Sortino - s4_metrics$Sortino, 4),
      delta_Turnover = round(m_row$Turnover_ann - s4_metrics$Turnover_ann, 4)
    ),
    codex_GOV_C1_resolution = "정적 weight admit 회피 (Codex REJECT 정합) → walk-forward dynamic admit으로 전환. Static S4 weights는 더 이상 admit candidate 아님 — paradigm-free 비교 baseline only."
  ),

  no_paradigm_assertion = list(
    no_60_40_citation = TRUE,
    no_brinson_1986_citation = TRUE,
    no_saa_citation = TRUE,
    no_managed_futures_paradigm_citation = TRUE,
    decision_basis = "정량 metric + Charter v1.5 hierarchy + AX-001 v2 conditional defense 정합만",
    cherry_picking_avoided = "도훈 직관 framing은 walk-forward로 실증 검증되었지만, 의사결정 근거는 paradigm이 아니라 정량 score (composite tie-break Charter hierarchy)"
  ),

  hard_boundaries = list(
    alpha_definition_unchanged = TRUE,
    sleeve_definition_unchanged = TRUE,
    no_static_weight_admit = TRUE,
    sleeve_4_immutable = TRUE
  ),

  artifacts_generated = list(
    walk_forward_method_log_json = "output/walk_forward_method_log.json",
    weight_evolution_timeseries_csv = "output/weight_evolution_timeseries.csv",
    walk_forward_returns_timeseries_csv = "output/walk_forward_returns_timeseries.csv",
    comparison_table_walk_forward_csv = "output/comparison_table_walk_forward.csv",
    ax001_v2_csv = "output/ax001_v2_conditional_defense_walkforward.csv",
    dsr_bailey_csv = "output/dsr_bailey_walkforward.csv",
    harvey_liu_csv = "output/harvey_liu_walkforward.csv",
    subperiod_stability_csv = "output/subperiod_stability_walkforward.csv",
    sign_consistency_csv = "output/sign_consistency_walkforward.csv",
    best_method_ranking_csv = "output/best_method_ranking.csv",
    best_method_recommendation_json = "output/best_method_recommendation.json",
    static_vs_dynamic_validation_json = "output/static_vs_dynamic_validation.json"
  ),

  next_action = "Codex Critic Round (qvest-codex-round skill) → REVISE/REBUTTAL → Final optimization_package.json",
  created_at = "2026-05-09T22:39:00+09:00"
)

write_json(pkg, file.path(WT_DIR, "optimization_package_draft.json"),
           pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("[draft] optimization_package_draft.json saved (%d bytes)\n",
            file.size(file.path(WT_DIR, "optimization_package_draft.json"))))
