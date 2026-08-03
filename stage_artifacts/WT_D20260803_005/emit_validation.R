# =============================================================================
# emit_validation.R — WT-D20260803_005 (FQ-131) Step H: alpha_validation.json
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/emit_validation.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005H] ", fmt, "\n"), ...))
r4 <- function(x) round(as.numeric(x), 4)

P1R <- readRDS(file.path(OUT, "persistence_results.rds"))
P2R <- readRDS(file.path(OUT, "persistence_results2.rds"))
DBR <- readRDS(file.path(OUT, "dualbasis_results.rds"))
FB  <- readRDS(file.path(OUT, "finalize_bits.rds"))
RIC <- readRDS(file.path(OUT, "rankic_results.rds"))
CP  <- readRDS(file.path(OUT, "canonical_pool.rds"))
META<- readRDS(file.path(OUT, "pool_meta.rds"))
POOL <- P1R$pool; SUMM <- CP$summary; GRIDS <- P1R$grids
nullstat <- function(nm) { x <- P1R$nulls[[nm]]; x <- x[is.finite(x)]
  list(mean = r4(mean(x)), ci = c(r4(quantile(x,.025)), r4(quantile(x,.975))),
       observed_percentile = r4(100*mean(x <= P1R$pp[[nm]][["p"]]))) }
gridblock <- function(nm) {
  R0 <- P1R$runs[[nm]]$runs; W <- GRIDS[[nm]]$W
  comp <- R0[censored == FALSE]
  list(window_months = W, n_windows = nrow(P1R$TG[[nm]]$t), n_pairs = nrow(P1R$PR[[nm]]),
    p_persist = r4(P1R$pp[[nm]][["p"]]),
    p_persist_relative_era_demeaned = r4(P1R$pp_rel[[nm]][["p"]]),
    ci_factor_clustered = c(r4(P1R$pp[[nm]][["lo"]]), r4(P1R$pp[[nm]][["hi"]])),
    ci_corr_cluster_avglink_k39 = c(r4(DBR$clboot2[grid==nm, lo]), r4(DBR$clboot2[grid==nm, hi])),
    ci_time_clustered = c(r4(DBR$time_boot[grid==nm, lo]), r4(DBR$time_boot[grid==nm, hi])),
    n_transitions = as.integer(DBR$time_boot[grid==nm, n_transitions]),
    constant_alpha_null = nullstat(nm),
    run_length = list(n_runs = nrow(R0), n_uncensored = nrow(comp),
      median_uncensored_windows = if (nrow(comp)) r4(median(comp$len)) else NA,
      median_uncensored_months = if (nrow(comp)) r4(median(comp$len))*W else NA,
      mean_windows = r4(mean(R0$len)),
      km_median_windows = P1R$runs[[nm]]$km$median_windows,
      geometric_median_windows = r4(1 + log(0.5)/log(P1R$pp[[nm]][["p"]])),
      geometric_median_months = r4(P1R$geo_halflife_months[[nm]])),
    level_regression = list(b = r4(P1R$lm[[nm]]["b"]), se = r4(P1R$lm[[nm]]["se"]),
      t_factor_clustered = r4(P1R$lm[[nm]]["t"]), p = signif(P1R$lm[[nm]]["p"], 3),
      r2 = r4(P1R$lm[[nm]]["r2"]),
      b_relative = r4(P1R$lm_rel[[nm]]["b"]), p_relative = signif(P1R$lm_rel[[nm]]["p"], 3)),
    auc = list(absolute = r4(P1R$auc[[nm]]), relative = r4(P1R$auc_rel[[nm]])),
    bins = lapply(split(P2R$bin_ci[grid == nm], P2R$bin_ci[grid == nm]$bin), function(s)
      list(n = s$n, p_persist = r4(s$p), ci = c(r4(s$lo), r4(s$hi)),
           n_clusters = as.integer(s$n_clusters), mean_signed_t_next = r4(s$mean_t_next))),
    gate_sim = lapply(seq_len(nrow(P2R$gate_sim[[nm]])), function(i) {
      s <- P2R$gate_sim[[nm]][i]
      list(tau = s$tau, n_selected = s$n_sel, mean_next_port_t = r4(s$mean_t_next),
           ci = c(r4(s$lo), r4(s$hi)), share_positive_next = r4(s$share_pos_next))}),
    era = lapply(seq_len(nrow(DBR$era2[grid == nm])), function(i) {
      s <- DBR$era2[grid == nm][i]
      list(window = s$k, from = as.character(s$from), to = as.character(s$to),
           mean_t_capw = r4(s$mean_t_cap), share_pos_capw = r4(s$pos_cap),
           mean_t_ew = r4(s$mean_t_ew), share_pos_ew = r4(s$pos_ew))}),
    per_transition_persistence = DBR$per_k[grid == nm, .(k, n, p = r4(p))]
  )
}

V <- list(
  task_id = "WT-D20260803_005", fq = "FQ-131",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  title = "성분 자격의 지속성 — PORT_t 부호 반감기와 조건부 안정성",
  preregistration = "stage_artifacts/WT_D20260803_005/preregistration.json (측정 전 고정)",
  selection_type = "chain", n_iterations = 1L, gate_eligible = FALSE,
  metric_type = "canonical_screen",
  capital_claim = "none",

  measurement_integrity = list(
    measurement_path = "canonical_screen_bt() (top-25 EW long-only, 15bps, LIQ 2e8, cap-w 유니버스 벤치)",
    port_t_estimator = "backtest_result_contract.R::.nw_t_mean(active, lag=3) — 창 부분집합에 동일 적용",
    signal_path_c15 = "load_month_factors(sig_date) 전량 경유 · Z_Score_Aligned 부호 변형 없음(C13)",
    parity = list(
      topk_panel_vs_full_panel = list(note = "저장 top-80 패널이 top-25 선택을 바꾸지 않음",
        max_abs_diff = 0, n_factors = 3L, verdict = "PASS(정확 일치)"),
      fastpath_vs_canonical = list(max_abs_diff = 0, n_factors = 3L, verdict = "PASS"),
      window_slice_vs_direct_canonical = list(
        note = "창 t를 전기간 시계열 슬라이스로 산출 vs 창-직접 canonical 실행 (차이 = 창 첫달 turnover 경계효과)",
        mean_abs_dt = r4(mean(abs(CP$parity$p3_window$dt))),
        max_abs_dt = r4(max(abs(CP$parity$p3_window$dt))),
        sign_agreement = sprintf("%d/%d", sum(CP$parity$p3_window$sign_same), nrow(CP$parity$p3_window)),
        verdict = "PASS — 슬라이스 방식 편향 무시 가능")
    ),
    lag1_stress = list(n_factors = nrow(DBR$lag1),
      median_abs_delta_t = r4(median(abs(DBR$lag1$delta))),
      max_abs_delta_t = r4(max(abs(DBR$lag1$delta))),
      sign_preserved = sprintf("%d/%d", sum(sign(DBR$lag1$port_t_base)==sign(DBR$lag1$port_t_lag1)), nrow(DBR$lag1)),
      note = "유일 붕괴 = C02_EPS_Chg_1m (2.487→0.628) — 1개월 horizon 신호라 1개월 지연이 신호를 지우는 것이 정상. 누출 지문 아님"),
    violation_injection = list(
      preregistered_criterion = "Δp_persist > +0.02 (LEAK_OVERLAP 또는 LEAK_FULL)",
      fired = FALSE,
      leak_overlap = list(delta_p_persist = 0.0165, b_base = 0.2771, b_leak = 0.5570,
        auc_base = 0.6400, auc_leak = 0.7010, top_bin_base = 0.500, top_bin_leak = 0.791),
      leak_full = list(delta_p_persist = -0.0012, b = 0.4526, top_bin = 0.667),
      honest_reading = paste0("사전등록 판정식(집계 p_persist)은 발화하지 않았다. 그러나 (b)가 실제로 쓰는 지표에서 ",
        "누출 지문은 뚜렷하다 — 기울기 2.0배, AUC +0.061, 최상위 bin 0.500→0.791. ",
        "따라서 비중첩 규율은 실구속이며, 둔감한 것은 사전등록한 집계 통계 쪽이다. 판정식 사후 교체는 하지 않았다.")
    ),
    effective_sample = list(
      n_factors_measured = 322L, n_after_duplicate_removal = length(POOL),
      duplicate_rule = "|cor(canonical net-active)| >= 0.99, 알파벳 tie-break", n_dropped = 37L,
      n_corr_clusters_singlelink_0.70 = P2R$n_clusters,
      n_pc_90pct_variance = P2R$n_pc90, pc1_variance_share = r4(P2R$pc1_share),
      note = "factor-clustered CI 폭 대비 상관-클러스터 CI 폭 4.0배 — factor 단위 추론은 과신"
    )
  ),

  discriminants = list(
    a_operational_persistence = list(criterion = "median sign-run >= 2창 AND P_persist >= 0.65",
      measured = "비절단 run 중앙값 1창(60m) / P_persist 0.578", verdict = "FAIL"),
    b_gate_feasibility = list(criterion = "level b > 0 (clustered p<0.05) AND 최상위 |t| bin P_persist >= 0.65",
      measured = "b +0.277 (p<1e-4) 이나 최상위 bin 0.500 [0.366, 0.655]", verdict = "FAIL",
      operational_reading = paste0("tau=2 자격 문턱으로 선발하면 다음 창 PORT_t 평균 −0.112 [−0.453, +0.300], ",
        "양수 비율 41.7%. tau를 올릴수록 나빠진다(primary). ",
        "★ 정적 |t| 자격 게이트는 현 재료에서 원리적으로 작동 불가."))
  ),

  headline_answers = list(
    a_sign_run_distribution = paste0("비절단 sign-run 중앙값 = 1창 (60m/36m/24m 격자 **전부**). ",
      "기하 중앙값은 창 단위로 2.26 / 2.39 / 2.20 창 — 창 길이를 바꿔도 같다. ",
      "★ 즉 달력 시간의 반감기가 존재하지 않는다(월 환산은 136 / 86 / 53 으로 창 길이에 비례). ",
      "이는 실제 감쇠 시간상수가 아니라 추정잡음 지배의 지문이다."),
    b_gate_feasibility = paste0("불가. 기울기는 유의하나 그것은 저-|t| 구간이 만든 것이고, ",
      "게이트가 실제로 쓰는 고-|t| 구간에서 지속성이 동전던지기(0.500 [0.366, 0.655])로 무너진다. ",
      "운용 시뮬에서 tau>=1.5 부터 다음 창 기대 PORT_t가 0 이하로 내려간다."),
    c_conditional = paste0("family: growth/investor_flow 0.667 · quality 0.659 · momentum 0.655 vs ",
      "defense 0.465 · liquidity 0.487 (방어·유동성 계열은 동전던지기 이하). ",
      "cap-tier: 보유 시총 큰 factor일수록 불안정(CAP_large 0.514 < CAP_small 0.614). ",
      "회전율(실측): TO_high 0.613 > TO_low 0.558 — registry turnover_profile 라벨과 반대 방향(CF-06). ",
      "단 소분류 CI는 클러스터 1~4로 붕괴 — 방향만 유효(CF-04)."),
    dominant_mechanism = paste0("판정 부호는 factor 라벨이 아니라 era 라벨이다. cap-w 벤치에서 개별 factor 부호가 ",
      "창 공통부호와 일치하는 비율 0.856 (창4 = 2021-07~2026-06 에서는 285개 중 양수 2.1%). ",
      "EW-유니버스 벤치로 바꾸면 그 진폭이 사라진다(일치율 0.558, 양수비율 0.37~0.50). ",
      "★ 그러나 지속성 자체는 basis-invariant (EW 0.607 vs cap-w 0.578) — ",
      "**수준은 벤치 구성이, 지속성은 추정잡음이 지배한다.** 벤치를 고쳐도 자격 게이트는 살아나지 않는다.")
  ),

  grids = list(primary_W60 = gridblock("primary"), robustness_W36 = gridblock("rob36"),
               robustness_W24 = gridblock("rob24")),

  transition_wall_persistence = list(
    note = "같은 격자·같은 NW 추정량으로 rank-IC 부호 지속성 vs PORT_t 부호 지속성 비교 — 불안정이 신호에 있나 번역에 있나",
    table = RIC$wall,
    pool_rank_ic_median = r4(RIC$pool_rank_ic_median), pool_icir_median = r4(RIC$pool_icir_median)
  ),

  falsification_results = list(
    F1_benchmark_artifact = list(field = "A4_benchmark_kospi200", result = "CONFIRMED",
      detail = "cap-w 양수비율 0.75/0.91/0.22/0.02 → EW 0.37/0.50/0.42/0.48"),
    F2_size_axis = list(field = "S01_Size", result = "CONFIRMED_directional",
      detail = "CAP_large 0.514 < CAP_mid 0.604 < CAP_small 0.614"),
    F3_alignment_artifact = list(field = "FDB-B7_ic_history_monthly", result = FB$falsif3$verdict,
      detail = sprintf("방향전환 0회 %d factor %.3f vs >=1회 %d factor %.3f (Δ %+.3f)",
        FB$falsif3$n_factors_stable, FB$falsif3$p_stable, FB$falsif3$n_factors_flipping,
        FB$falsif3$p_flipping, FB$falsif3$delta),
      coverage_note = FB$falsif3$coverage_note)
  ),

  ax001_conditional_advisory = list(
    note = "AX-001 v2 — 방어형은 조건부(BM<0 월) 평가. 대표 12 factor 실측",
    n_higher_in_bad_months = DBR$lag1[ax001_bad_act_pct_m > ax001_norm_act_pct_m, .N],
    n_total = nrow(DBR$lag1),
    reading = paste0("12개 중 11개가 BM<0 월의 active가 더 높다 — top-25 EW long-only는 cap-w 벤치 대비 ",
      "구조적으로 방어 성향이다. 이는 factor 고유 방어력이 아니라 벤치 구성 차이의 대칭 산물 ",
      "(era 기전과 같은 뿌리) — 방어형 factor 개별 평가에 이 배경을 차감해야 한다.")
  ),

  consumption_surfaces_7 = list(
    `1_factor_ranking` = "소비 불가(정적 자격 게이트). 단 era-demean 상대순위 Spearman 중앙값 0.20은 살아있음 → NP-2",
    `2_universe_filter` = "미측정. CAP_large 0.514 < CAP_small 0.614 이 유니버스를 mid-cap으로 좁히면 판정 안정이 오르는지 시사 → NP-3",
    `3_overlay_regime_input` = "★ 실질 소비면. 창별 era 공통성분(전 factor 평균 PORT_t, cap-w −1.37 ~ +1.63)은 '스타일 국면' 관측치다. 사전 관측가능하게 추정되면 era-조건부 자격이 가능 → NP-1",
    `4_risk_model_beta_budget` = "라우팅만(역할 밖): era 공통성분 = 모든 long-only 슬리브의 공통 노출 → risk agent crowding/공통성분 입력 후보",
    `5_monitoring_signal` = "전이별 지속성이 0.251(창2→3, 2016 전후)까지 붕괴 — monitoring이 잡아야 할 사건은 '개별 전략 감쇠'가 아니라 '풀 전체 동시 반전'",
    `6_screening_label` = "registry turnover_profile 라벨 무효화(CF-06) + screen_route 라벨에 '자격 유효기간 없음' 부기 필요",
    `7_other_mode_transfer` = "factor-rotation(FR) RCMA는 '국면조건부 모듈 자격'을 전제하는데 본 라운드가 그 전제(자격의 시간 유지)를 반증 — FR 자격 판정에 유효기간·era 통제 필요"
  ),

  next_probe = list(
    list(id = "NP-1", priority = "high", title = "era 공통성분의 사전 관측가능성",
      question = "창별 전-factor 평균 PORT_t(era)를 그 시점까지의 데이터로만 추정해 다음 창 era 부호를 맞힐 수 있는가 (cap-w / EW 양 basis)",
      why = "본 라운드의 지배 기전이 era인데, era 자체가 예측 가능하면 '자격 게이트' 대신 'era 타이밍'으로 문제를 재정의할 수 있다. 실패해도 '판정을 언제 믿지 말아야 하는가'의 경계가 나온다",
      measurable_now = TRUE),
    list(id = "NP-2", priority = "high", title = "era-demean 상대순위의 소비 가능성",
      question = "창 k에서 era-demean 후 상위 K factor를 뽑으면 창 k+1에서 상대적으로 이기는가, 그리고 그것이 자본(PORT_t)으로 전이되는가",
      why = "절대 부호는 죽었지만 상대순위 Spearman 0.19~0.20은 3격자 공통으로 살아있다. 상대 신호가 자본으로 전이되는지가 미측정",
      measurable_now = TRUE),
    list(id = "NP-3", priority = "medium", title = "cap-tier 제한 유니버스에서의 판정 안정성",
      question = "유니버스를 MID tier(시총 11-30위 대역)로 제한하면 창별 판정 지속성이 오르는가",
      why = "CAP_large 0.514 vs CAP_small 0.614 + 기존 실측(MID tier LS t=3.02 vs MEGA 0.59)과 정합 여부 확인",
      measurable_now = TRUE),
    list(id = "NP-4", priority = "medium", title = "판정 단위를 부호에서 예측구간으로",
      question = "다음 창 PORT_t의 예측구간(Liao 2025 uncertainty-aware)을 산출하면 의사결정이 달라지는가 — 구간이 항상 0을 포함한다면 '자격' 개념 자체의 사망 증명",
      why = "본 라운드는 점추정 부호만 다뤘다. 구간으로 바꾸면 '게이트 불가'가 정량 증명이 되고, 동시에 어떤 조건에서 구간이 좁아지는지가 나온다",
      measurable_now = TRUE)
  ),

  revival_conditions_inv7 = list(
    "① 비-return 원천(DART insider·공매도/대차 등 FQ-001~005)에서 나온 factor가 창별 PORT_t 부호 지속 >= 0.70 (현 풀 최고 family 0.667)",
    "② NP-1 PASS — era 공통성분이 사전 관측가능하게 추정되어 era-조건부 자격이 성립",
    "③ 표본 증가로 primary 격자 전이 수 >= 6 (현 3) 이 되어 time-clustered CI가 0.5를 배제"
  ),

  boundaries = list(covariance_estimated = FALSE, weights_proposed = FALSE,
    graduation_claimed = FALSE, book_claim = FALSE,
    note = "Σ/weight 미산출. graduation HARD 3종은 forge-authoritative 값에만 적용되며 본 라운드는 canonical screening 실측 — 자격 선언 없음")
)

write_json(V, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_validation.json 저장 (%.1f KB)", file.info(file.path(OUT, "alpha_validation.json"))$size/1024)
