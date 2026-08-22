## WT-D20260822_002 · P6 — alpha_package.json (AST v1.1 3층) 발행 + lineage
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p6_alpha_package.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260822_002"
MBX <- "qepm/mailbox/worktask/WT-D20260822_002"
P2 <- readRDS(file.path(OUT,"p2_arms.rds")); P3 <- readRDS(file.path(OUT,"p3_verdict.rds"))
P4 <- readRDS(file.path(OUT,"p4_diagnostics.rds")); P5 <- readRDS(file.path(OUT,"p5_inputs.rds"))
FV <- readRDS(file.path(OUT,"p0b_frame_verify.rds"))
HY <- fromJSON(file.path(MBX,"alpha_hypothesis.json"), simplifyVector = FALSE)
RES <- P2$RES; CP <- P3$CP; LBL <- P3$LBL; adv <- P5$adv; CONF <- P5$CONF
sel_of <- function(a) { L <- as.data.table(read_parquet(file.path(OUT,"alpha_vector_live_202608.parquet")))
  strsplit(L[arm == a, selected][1], "\\|")[[1]] }

esc <- function(arm, stat_desc) list(
  escape_type = "SPECIAL_OP",
  op_code_path = "stage_artifacts/WT-D20260822_002/p2_arms_and_gate.R::sel_t+pick (통계량 원자료 = stage_artifacts/WT-D20260813_005/s1_build_monthly_factor_stats.R · depth_aligned/d1_depth_stats.R · stage_artifacts/WT-D20260822_002/p1_pearson_stats.R)",
  walk_forward = TRUE,
  statistic = stat_desc,
  window_rule = "홀딩월 i 의 선별은 anchor < anchors[i] 인 실현 통계만 소비 (rows (i-36)..(i-1)). MIN_OBS=30 미만 팩터는 후보 제외(NA — 0 대입 금지).")

mkfac <- function(arm, stat_desc, role) list(
  factor_id = paste0("FQ237_", arm), arm = arm, role = role,
  ## ★escape 계약을 **두 곳에** 둔다: schema.json 은 `escape_contract` 하위를 요구하고
  ##   02_Infrastructure/ast/ast_verify.py:484 는 **노드 직속** op_code_path/walk_forward 를 읽는다.
  ##   두 계층이 서로 다른 자리를 보므로 한쪽만 채우면 다른 쪽이 FAIL_CONTRACT 를 낸다(challenge CF7).
  ##   스키마 leaf 분기는 additionalProperties 를 막지 않으므로 양쪽 충족이 가능하다.
  ast = list(op = "CS_ZSCORE", args = list(list(
    leaf = "SPECIAL_OP",
    op_code_path = esc(arm, stat_desc)$op_code_path,
    walk_forward = TRUE,
    escape_contract = esc(arm, stat_desc)))),
  ast_note = "★AST 는 walk-forward 선별을 정적 리프로 환원할 수 없다 — 선별 집합이 매월 바뀌므로 SPECIAL_OP escape 리프 + escape_contract 로 정직 산출한다(§4-1 FIELD 리프 위장 금지). CS_ZSCORE 는 소비 시 순위만 쓰이므로 단조변환(판정 불변) — 기록용.",
  selected_leaves_live_202608 = sel_of(arm),
  combination_within_factor = "선별 K=5 팩터의 Z_Score_Aligned 종목별 단순평균 (결측 제외, 0 대입 없음)",
  economic_rationale = "선별 통계량 교체가 top-N 평균 소비로 전이되는지를 시험하는 대조 설계. 팩터 자체의 근거는 factor DB registry 승계이며 본 라운드가 신규 팩터를 주장하지 않는다(Factor Zoo 축소 원칙 ① validation > discovery).",
  redundancy_cluster_id = "FQ237_SELECTION_STATISTIC",
  redundancy_note = "3 arm 은 의도된 동일-클러스터 대조군 — 재료(320팩터)·창(W=36)·K(5)·결합·비용·소비 깊이가 동일하고 **선별 통계량만** 다르다. 신규 팩터 추가가 아니다.",
  restatement_exposure = 0L)

FSPEC <- lapply(P5$FSPEC, function(s) s)
liveP <- as.data.table(read_parquet(file.path(OUT,"alpha_vector_live_202608.parquet")))[arm == "SEL_PEARSON"]
av_vec <- setNames(as.list(round(liveP$alpha_score, 6)), liveP$Ticker)
cf_vec <- setNames(as.list(round(CONF$confidence, 4)), CONF$Ticker)

pkg <- list(
  task_id = "WT-D20260822_002", round_id = "FQ237_RERANK_20260822", fq_ref = "FQ-237",
  as_of_date = "2026-08-22", forecast_horizon = "1M", spec_version = "ast_v1.1",
  produced_by = "alpha-research", produced_at = format(Sys.time(), "%Y-%m-%d"),
  prereg = "stage_artifacts/WT-D20260822_002/PREREG.json",
  wt_type = "discovery",

  pit = list(
    sig_date = "2026-07-31",
    decision_ts = "2026-08-01",
    note = "팩터 sig_date T = T월 말 관측 → 패널 anchor 는 T+1개월 스탬프. 홀딩월 수익은 anchor 부터 다음 anchor 까지. 선별 통계량은 anchor < 홀딩 anchor 인 **실현** 통계만 소비.",
    anchor_frame_verification = list(
      method = "위반 주입 — 팩터를 자기 달 월초로 스탬프하는 문서화된 결함을 실제로 넣고 지문이 발화하는지 실측",
      broken_frame_M04_Mom_1_mean_spearman_ic = FV$inject[fac == "M04_Mom_1", ic_broken],
      fixed_frame_M04_Mom_1_mean_spearman_ic  = FV$inject[fac == "M04_Mom_1", ic_fixed],
      documented_defect_signature = -0.9423,
      n_factors_over_abs_0_10_broken = FV$inject[abs(ic_broken) > 0.10, .N],
      n_factors_over_abs_0_10_fixed  = FV$inject[abs(ic_fixed)  > 0.10, .N],
      verdict = "결함 주입이 문서화된 지문 -0.9423 을 소수 4자리로 재현했고 정상 프레임은 0/13 — 앵커 검사에 실제 검출력이 있고 본 라운드 프레임은 정상.",
      advertised_fingerprint_caveat = "★라운드 mandate 가 지시한 지문 '+0.0170' 은 원천에서도 승계 패널에서도 재현되지 않는다(원천 재산출 +0.0053 · 패널 +0.0040). WT-D20260813_005 가 이미 그 이유를 실측했다 — 그 수치는 master_panel_FIXED.rds 라는 파생 자산의 국소 성질이고 그 파일은 원천 충실도가 낮다(M04_Mom_1 cor 0.3372). 지문의 **목적**(앵커 회귀 검출)은 위 위반 주입 + IC 프로파일 정상성으로 더 강하게 충족했다."),
    panel_fidelity = list(
      panel = "stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet",
      method = "독립 표본 13종에서 load_month_factors() 원천 재산출 월별 IC 계열과 패널 IC 계열의 상관",
      n_ge_0_99 = FV$fidelity[cor_ic >= 0.99, .N], n_total = nrow(FV$fidelity),
      median_cor = median(FV$fidelity$cor_ic), min_cor = min(FV$fidelity$cor_ic),
      seed = 20260822L),
    ic_profile_normality = list(n_factors = nrow(FV$profile),
      n_abs_mean_ic_over_0_10 = FV$profile[abs(mean_ic) > 0.10, .N],
      max_abs_mean_ic = max(abs(FV$profile$mean_ic), na.rm = TRUE),
      max_factor = FV$profile[which.max(abs(mean_ic)), fac])),

  hypothesis = list(
    inherited_from = "qepm/mailbox/worktask/WT-D20260822_002/alpha_hypothesis.json (alpha-hypothesis, model_tier=fable, verdict=designed)",
    inheritance_rule = "Charter 원칙 8 No Silent Override — mechanism/regime_scope 자구 그대로 승계. falsification 은 게이트 스키마(객체배열 + field_ref)로 형식만 재포장하고 원문을 falsification_inherited_verbatim 에 보존.",
    statement = HY$selected$hypothesis_description,
    mechanism = HY$selected$mechanism,
    falsification = list(
      list(field = "FDB-B7_ic_history_monthly",
           expectation = "[축 1 — 선별 분기] rank-IC t 서열 vs Pearson-IC t 서열의 월별 순위상관 중앙값 < 0.90 이고 top-5 선별집합 Jaccard 중앙값 < 0.80 이어야 한다. 그렇지 않으면 두 통계량이 같은 선별을 낳으므로 '통계량 불일치가 선별을 오도한다' 기전 자체가 기각된다(성과 무관 관측)."),
      list(field = "A1_RAWDATA_OHLCVS_daily",
           expectation = "[축 2 — 비대칭 기원] 월별 (Pearson IC − Spearman IC) 절대격차가 횡단면 왜도와 양(+)의 연속 상호작용을 보여야 한다. 추정기 2종(월간 횡단면 왜도 / 일간파생 월내 횡단면 왜도) 모두 |t| < 2.0 이면 비대칭-기원 기각."),
      list(field = "A4_benchmark_kospi200",
           expectation = "[basis 불변성] paired 설계에서 벤치가 차분에 상쇄되어 total-diff t 와 active-diff t 가 일치해야 한다 — 불일치하면 비교 구성이 짝지어지지 않았다는 뜻.")),
    falsification_inherited_verbatim = HY$selected$falsification,
    regime_scope = HY$selected$regime_scope,
    prereg_stance = HY$selected$design_frame$prereg_stance),

  factors = list(
    mkfac("SEL_RANK", "trailing NW3 t of monthly Spearman IC (승계 s1$FS$ic)", "control"),
    mkfac("SEL_PEARSON", "trailing NW3 t of monthly Pearson IC (본 라운드 p1$PS$ic_pe — 동일 표본 마스크 실증: n_obs 불일치 0셀 · Spearman 재산출 max|Δ| 0.000e+00)", "treatment_a_novel"),
    mkfac("SEL_MEANDEPTH", "trailing NW3 t of monthly (mean fwd | top-25 by z) − (mean fwd | all valid) (승계 D1$DS$meandepth)", "treatment_b_replication_bridge")),
  combination_rule = "z_score_aligned_equal_weight",
  verdict = "designed",

  self_pit_check = list(performed = TRUE,
    leaves_checked = list(
      list(leaf = "SPECIAL_OP (walk-forward 선별)", availability_rule = "선별 창이 홀딩 anchor 미만 실현 통계만 소비 — 코드 수준 강제(rows (i-W)..(i-1)) + 위반 주입 arm 으로 검출력 실증(t +3.5731)", restatement_prone = FALSE),
      list(leaf = "FDB-B1/B2 (factor DB Z_Score_Aligned)", availability_rule = "load_month_factors() 경유(C15) · 방향정렬은 연결자 PIT-safe expanding IC(C13/C14) · 재무 lag = 빌더 규약(C4)", restatement_prone = TRUE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily", availability_rule = "price t-1 close · 유동성 자 = adv20_t1 (liq_ruler=adv20_t1/input_daily 실측)", restatement_prone = FALSE),
      list(leaf = "A4_benchmark_kospi200", availability_rule = ".cache/benchmark.parquet 일별 → apply.monthly(Return.cumulative) → ym 조인 (덮개 100.0%)", restatement_prone = FALSE)),
    verdict = "clean",
    note = "PIT 스트레스(LAG1: 창을 한 칸 더 물림) t = 0.2800 으로 base 대비 붕괴 없음 — 동월 누출 징후 부재. 단 LAG1 은 (A) 처치의 t 가 애초에 0 근방이라 판별력이 제한적임을 명시한다."),

  alpha_vector = av_vec,
  confidence_vector = cf_vec,
  alpha_vector_note = "★live 2026-08 홀딩월 · arm = SEL_PEARSON(처치 a). **자본 추천이 아니다** — 본 라운드 판정은 이 arm 이 대조군을 개선하지 못했음을 보였다(아래 results). PREREG artifact_on_null 규약에 따라 다음 라운드가 같은 배관을 재사용하도록 발행한다. 전 arm 스코어 = stage_artifacts/WT-D20260822_002/alpha_scores.parquet.",
  signal_matrix_ref = "stage_artifacts/WT-D20260822_002/alpha_scores.parquet",
  factor_specs = FSPEC,

  selection_objective = "canonical_port_t",
  selection_objective_note = "★본 라운드는 성과로 후보를 고르지 않았다 — 처치 2종·비교쌍·문턱·K·W·깊이가 전부 측정 전 고정이고 argmax 가 없다(selection_type=chain, sweep_count=0). 이 필드는 '만약 골랐다면 무엇을 기준으로 하는가' 의 선언이며 canonical PORT_t(1급 실측)를 채택한다. arm **내부**의 팩터 선별 통계량(rank-IC / Pearson IC / 평균 스프레드)이 곧 본 라운드의 판정 대상이므로 이 필드와 혼동 금지.",

  diagnostics = list(
    canonical_port_t_nw_lag3 = RES$SEL_PEARSON$portfolio_alpha_t_nw_lag3,
    canonical_port_t_pvalue = RES$SEL_PEARSON$portfolio_alpha_t_pvalue,
    canonical_n_months = RES$SEL_PEARSON$n_months,
    canonical_port_t_control_rank = RES$SEL_RANK$portfolio_alpha_t_nw_lag3,
    canonical_port_t_treatment_b = RES$SEL_MEANDEPTH$portfolio_alpha_t_nw_lag3,
    rank_ic = adv[arm == "SEL_PEARSON", rank_ic],
    icir = adv[arm == "SEL_PEARSON", icir_monthly],
    harvey_t_stat = adv[arm == "SEL_PEARSON", harvey_t_rank_ic_nw3],
    monotonicity = adv[arm == "SEL_PEARSON", monotonicity],
    subperiod_stability = adv[arm == "SEL_PEARSON", subperiod_stability],
    turnover_proxy = RES$SEL_PEARSON$turnover_annual,
    post_neutralization_ic = NULL,
    post_neutralization_ic_note = "미산출 — 본 라운드는 승계 자구 유지를 위해 추가 중립화를 하지 않았다(alpha_bridge step6). 중립화판 추가는 변형 추가 = sweep 재분류라 사전등록이 금지했다.",
    metric_type = "canonical_screen",
    ic_vs_port_t_contrast = "★Cycle 2 교훈 재현: rank-IC Harvey-t 는 세 arm 전부 문턱 2.95 를 넘는다(대조 5.30 / 처치a 4.02 / 처치b 2.44)나 cap-w PORT_t 는 전부 미달(0.947 / 0.680 / 1.777). rank-IC t 와 portfolio-alpha t 를 명시 구분해 보고한다."),

  results = list(
    reproduction = list(passed = as.integer(sum(P2$rep_ok)), total = length(P2$rep_ok),
      coprimary_B_t_measured = CP$B$t_nw3, coprimary_B_t_prereg = 1.57062,
      note = "승계 arm 2종이 사전등록 값을 소수 4자리로 복원 — (b) 는 재판정이지 다른 실험이 아니다."),
    coprimary = list(
      A = list(contrast = "SEL_PEARSON − SEL_RANK", n = CP$A$n, annual_pct = CP$A$ann_pct,
               t_nw3 = CP$A$t_nw3, mde_annual_pct = LBL$A$mde,
               ci95_annual_pct = c(P4$ci[contrast=="A", ci95_lo], P4$ci[contrast=="A", ci95_hi]),
               label = LBL$A$label),
      B = list(contrast = "SEL_MEANDEPTH − SEL_RANK", n = CP$B$n, annual_pct = CP$B$ann_pct,
               t_nw3 = CP$B$t_nw3, mde_annual_pct = LBL$B$mde,
               ci95_annual_pct = c(P4$ci[contrast=="B", ci95_lo], P4$ci[contrast=="B", ci95_hi]),
               label = LBL$B$label)),
    controls = list(negative_control_meddepth_t = P3$AUX$NEG$t_nw3,
                    violation_injection_lookahead_t = P3$AUX$INJ$t_nw3,
                    pit_stress_lag1_t = P3$AUX$LAG1$t_nw3,
                    positive_control_basis = "기측정 양성에서 선택 — WT-D20260813_005 가 같은 통계 계열·같은 n=221 에서 누출 주입을 t 4.16/4.03 으로 검출. 본 라운드 신규 통계량(Pearson)에서도 t +3.5731 로 유지."),
    falsification_measured = list(
      axis1_fired = P2$axis1_fire,
      axis1_rho_median = median(P2$DIV$rho_rank_pearson, na.rm=TRUE),
      axis1_jaccard_median = median(P2$DIV$jac_rank_pearson, na.rm=TRUE),
      axis2_sign_predicted = "+", axis2a_b = P4$axis2$a$b, axis2a_t_nw3 = P4$axis2$a$t_nw,
      axis2b_b = P4$axis2$b$b, axis2b_t_nw3 = P4$axis2$b$t_nw,
      axis2_verdict = "예측 부호(+)로 강하게 성립 — 기전 전제(비대칭이 클수록 크기-정보와 순위-정보가 갈린다)는 실측 지지.",
      axis2_estimator_independence_contradiction = list(
        measured_cor = P4$axis2$cor_estimators,
        inherited_claim = -0.011,
        note = "★승계 설계가 왜도 추정기 2종을 '무상관(-0.011)' 이라 보고 축을 둘로 나눴는데, 본 라운드 정의에서는 +0.951 로 사실상 같은 축이다. 설계를 수정하지 않고(Charter 원칙 8) 불일치를 기록한다 — 두 축은 독립 증거 2개가 아니라 같은 증거 1개로 읽어야 한다."),
      axis3_basis_invariance = list(A_delta_t = CP$A$t_nw3 - CP$A$t_active_nw3,
                                    B_delta_t = CP$B$t_nw3 - CP$B$t_active_nw3),
      persistence_rule_applied = list(ar1_skew_monthly = P4$axis2$ar1$skew_m,
        ar1_skew_daily = P4$axis2$ar1$skew_d, ar1_gap = P4$axis2$ar1$gap,
        decision = "phi 전부 < 0.10 ⇒ Lane D 의 phi 0.95~0.99 placebo 팽창 caveat 해당 없음. ★무비판 이식 금지 규약대로 대상의 지속성을 먼저 재고 판정했다.")),
    basis_three_way = as.list(P4$basis3),
    basis_note = "★canonical_screen_bt 는 호출자가 넘긴 벤치에 라벨 'KOSPI200_total_return' 을 하드코딩한다. 본 라운드 primary 가 실제로 넘긴 것은 .cache/benchmark.parquet(build_index_cache.py Code-매칭 IKS200). 측정창 221개월 연복리 IKS200 8.947% vs parent(K200∪KQ150 cap-w) 7.812% — parent 가 1.135%p 열위(FQ-241 방향과 정합). 절대 PORT_t 는 basis 에 크게 종속(SEL_MEANDEPTH 1.777 / 2.176 / 2.973)하나 **paired 판정은 basis 불변**(Δt ~ 1e-17).",
    robustness = list(R1_liquidity_2e8 = as.list(P4$R1),
                      R1_paired_A_t = -0.0728, R1_paired_B_t = 1.6809,
                      R2_subperiod = "P3 §6 참조 — (B) 는 2015-07 이전 t 2.40(연 +17.97%p) / 이후 t -0.53(연 -1.87%p), KQ150 소급 투영 창(2010-02~2015-06)만 보면 t 3.50(연 +29.06%p). (A) 도 같은 방향(오염창 t 1.79 / 청정창 t -0.74).",
                      R3_top5_month_exclusion = "(A) -0.2533 → +0.3198 · (B) +1.5706 → +0.7631 — (B) 의 점추정 절반이 221개월 중 5개월에 실린다."),
    performance_table = as.list(P4$perf),
    advisory_battery = as.list(adv),
    dsr_diagnostic = as.list(P4$dsr)),

  labels = list(
    A = LBL$A$label, B = LBL$B$label,
    headline = "선별 통계량을 rank-IC 에서 평균-정합으로 바꾸는 개입은 top-25 실현 전이를 개선하지 못했다. 처치 (a) Pearson IC 는 점추정 연 -0.60%p (t -0.25) 로 대조군과 사실상 구분되지 않으며 절대 PORT_t 는 오히려 낮다(0.680 vs 0.947). 처치 (b) 평균 스프레드 t 는 연 +6.03%p (t +1.57) 로 승계값을 정확히 복원했으나 문턱 미달이고, 그 이득이 유니버스 결함 구간에 집중된다.",
    scope_statement = "라벨은 사전등록 문턱(연 3.0%p)에 대해 UNDERPOWERED 다 — (A) 는 연 4.76%p 이상 효과를, (B) 는 연 7.67%p 이상 효과를 배제하며 그 아래 구간은 미결. ★'효과 없음' 과 '미결' 을 구분해 기록한다.",
    not_claimed = list(
      "자본 자격 — graduation HARD 3종 판정을 하지 않았다(metric_type=canonical_screen)",
      "FQ-233 Lane A 판정 번복 — 본 라운드는 그 부활조건의 관문 시험이다",
      "선별 통계량 축의 구조적 판결 — 조건-scoped negative(K=5 · W=36 · 320팩터 풀 · top-25 EW)",
      "target_weights / 공분산 / 사전 최적화 — 산출 0")),

  fq233_revival_condition_1 = list(
    condition = "평균-정합 선별 통계량 재서열에서 전이 양성 시 (FQ-233 next_action)",
    met = FALSE,
    basis = "co-primary 2건 모두 t < +2.0 (A +(-0.2533) · B +1.5706). 관문은 열리지 않았다.",
    boundary = "★양성이었더라도 본 에이전트는 자본화를 주장하지 않는다 — 관문 개방 사실만 보고하고 자본 경로 진입은 Q-Lead·도훈 판정(PREREG consumption_gate_precheck)."),

  transition_gates_evaluated = list(
    cond1_alpha_discovery_count = "충족 — alpha_scores.parquet 217,286행 · 221개월 · 3 arm, live 2026-08 벡터 347종목",
    cond2_screening = "미평가 — hurdle_gate.R screen_pass 는 net_SR/CAGR 기준이며 본 라운드 arm 은 자본 후보가 아니다(선별층 실험). 참고 실측: SEL_PEARSON total net SR 0.5412 · CAGR 12.62% · MDD 50.6% · calmar 0.250.",
    cond3_falsification_fired = "축 1 미발화 · 축 2 미발화(예측 부호로 성립) — 0건",
    cond4_coprimary_supported = "미충족 — SUPPORTED 0건",
    decision = "NO_TRANSITION — risk-research 전이 요청하지 않는다. cond4 미충족."),

  role_boundary = list(weights_computed = FALSE, covariance_computed = FALSE,
    note = "α̂ 와 그 선별 통계량만. Σ/weight/사전최적화 없음. canonical_screen_bt 의 top-25 EW 는 고정 규격 스크리닝 장치이지 비중 결정이 아니다."),

  challenge_flags = list(
    list(id = "CF1", severity = "HIGH", flag = "라운드 mandate 가 지시한 앵커 지문 '+0.0170' 이 원천·패널 어디서도 재현되지 않음 — 지문의 출처 자산(master_panel_FIXED.rds)이 원천 충실도 결함. 대체 검사 2종(위반 주입 -0.9423 재현 · IC 프로파일 정상성 0/331)으로 목적 충족."),
    list(id = "CF2", severity = "HIGH", flag = "★(B) 의 이득이 KQ150 소급 투영 창에 집중 — 2010-02~2015-06 t 3.50(연 +29.06%p) vs 2015-07 이후 t -0.53(연 -1.87%p). era 교락과 분리 불가하므로 라벨은 universe_backfill_inherited 까지만(caused_by_contamination 미사용, FQ-241 규약 승계)."),
    list(id = "CF3", severity = "MEDIUM", flag = "승계 설계의 '왜도 추정기 2종 무상관(-0.011)' 이 본 라운드 정의에서 +0.951 — 반증 축 2 의 두 하위축은 독립 증거 2개가 아니다. 설계 재작성 대신 기록(Charter 원칙 8) + alpha-hypothesis 재설계 요청."),
    list(id = "CF4", severity = "MEDIUM", flag = "사전등록 MDE 문턱 연 3.0%p 가 이 결과량 스케일에서 구조적으로 도달 불가(implied_t_threshold = 2.000 = 문턱 재진술). 문턱을 사후 조정하지 않고 라벨을 UNDERPOWERED 로 두되 배제 구간을 수치로 명시."),
    list(id = "CF5", severity = "MEDIUM", flag = "request.json 의 유동성 하한 5e7 과 헌법 Production Constraints 2e8 이 불일치. primary 는 승계 재현을 위해 필터 미적용(WT005 자구), R1 에서 2e8 적용판 병기 — 결론 불변(A -0.073 · B +1.681)."),
    list(id = "CF6", severity = "LOW", flag = "canonical_screen_bt 가 benchmark_id 를 'KOSPI200_total_return' 으로 하드코딩 — 호출자가 무엇을 넘겼든 같은 라벨이 붙는다. 본 라운드는 3-basis 를 명시 병기해 우회했으나 라벨-실체 불일치는 인프라 항목."),
    list(id = "CF7", severity = "MEDIUM", flag = "★escape 계약의 위치가 두 계층에서 어긋난다 — schema.json #/definitions/ast_node 는 `escape_contract` 하위 객체를 요구하고 02_Infrastructure/ast/ast_verify.py:484 는 **노드 직속** op_code_path/walk_forward 를 읽는다. 스키마만 따르면 verifier 가 FAIL_CONTRACT(실측 재현), verifier 만 따르면 스키마 위반. 본 패키지는 양쪽을 동시에 채워 우회했다. schema 주석이 기록한 ALB-005(falsification 타입 불일치)와 같은 계통이며 미수리 잔존.")),

  next_probe = list(
    list(id = "NP1", probe = "청정창(2015-07~, 133개월) 단독 사전등록 재판정 — (A)(B) 둘 다 청정창에서 음수 방향이라 '오염창 의존' 가설이 직접 시험 가능하다. 단 133개월 MDE 를 먼저 재고 착수 여부를 판정할 것(본 라운드 221개월에서 4.76~7.67%p 였으므로 133개월에서는 더 넓어진다 — 착수 전 검정력이 설계를 바꾸는 자리).", why = "본 라운드가 만든 가장 큰 미해결 — 승계 (b) 의 조건부 보류가 유니버스 결함 구간에 실려 있다"),
    list(id = "NP2", probe = "선별 통계량이 아니라 **결합 규칙** 교체 — 본 라운드는 선별(어느 팩터를 고르나)만 바꾸고 결합(K개 단순평균)은 고정했다. 평균-정합 선별이 Pearson IC 를 실제로 개선했는데(composite Pearson IC 0.02536 t 3.77 vs 대조 0.02201 t 3.18) top-25 전이가 안 됐다는 것은 병목이 선별 다음 마디에 있다는 뜻이다. ★단 ML 결합기 금지(v8.4 §6) — 폐형식 결합만.", why = "본 라운드가 병목을 한 마디 뒤로 밀어 국소화했다"),
    list(id = "NP3", probe = "소비 깊이 K 가 아니라 **top-N 자체**의 함수형 — 선별을 평균-정합으로 맞춰도 소비가 top-25 이산 편입이면 경계 잡음이 남는다. WT-D20260821_002 가 브레드스 확대에서 powered null 을 냈으므로, 남은 미검 조합은 '평균-정합 선별 × 브레드스 확대 소비' 교차다.", why = "두 라운드가 각각 한 축만 바꿨고 교차는 미측정"),
    list(id = "NP4", probe = "선별 통계량의 **추정 창 W** 가 아니라 추정량 자체의 축소(shrinkage) — Pearson IC 선별이 대조군보다 낮은 PORT_t 를 낸 것은 Pearson 이 꼬리에 민감해 선별 자체가 잡음을 탄다는 가설과 정합한다(선별 자기-회전율은 오히려 낮았으므로 이 가설은 아직 반증되지 않았다). James-Stein 류 축소 IC 로 재서열. ★격자 금지 — 단일 사전등록값.", why = "(A) 의 점추정이 음수라는 사실이 '정밀 코너' 서사와 어긋나므로 기전 재검이 필요"),
    list(id = "NP5", probe = "인프라 — canonical_screen_bt 의 benchmark_id 하드코딩 제거(호출자 계열의 실제 출처를 라벨로 전파). basis 라벨-실체 불일치가 게이트 판정에 침투할 수 있다.", why = "CF6")),

  metric_type = "canonical_screen",
  metric_type_note = "canonical_screen_bt 실측(top-25 EW long-only · 15bps). forge-authoritative 아님 — graduation HARD 판정 근거로 쓸 수 없다.",
  selection_type = "chain", sweep_count = 0L,
  artifacts = list(
    prereg = "stage_artifacts/WT-D20260822_002/PREREG.json",
    alpha_scores = "stage_artifacts/WT-D20260822_002/alpha_scores.parquet",
    alpha_vector_live = "stage_artifacts/WT-D20260822_002/alpha_vector_live_202608.parquet",
    alpha_validation = "stage_artifacts/WT-D20260822_002/alpha_validation.json",
    challenge_note = "qepm/mailbox/worktask/WT-D20260822_002/challenge_note.md",
    scripts = c("p0_probe.R","p0b_frame_verify.R","p1_pearson_stats.R","p2_arms_and_gate.R",
                "p3_verdict.R","p4_diagnostics_emit.R","p5_emit_package.R","p6_alpha_package.R"))
)

write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 8, na = "null", null = "null")
cat(sprintf("[saved] %s (%.1f KB)\n", file.path(MBX,"alpha_package.json"),
            file.size(file.path(MBX,"alpha_package.json"))/1024))

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(task_id = "WT-D20260822_002", package_type = "alpha_package",
  method_selected = "FQ-237 재서열 3-arm paired (SEL_RANK control / SEL_PEARSON treatment-a / SEL_MEANDEPTH treatment-b), K=5 W=36 top-25 EW 15bps, chain",
  input_file_paths = c("stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet",
                       "stage_artifacts/WT-D20260813_005/s1_factor_month_stats.rds",
                       "stage_artifacts/WT-D20260813_005/depth_aligned/d1_depth_stats.rds",
                       "stage_artifacts/WT-D20260822_002/p1_pearson_stats.rds",
                       ".cache/benchmark.parquet"))
cat("[lineage] recorded\n")
