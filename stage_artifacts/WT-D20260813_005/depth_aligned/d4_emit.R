## WT-D20260813_005 후속 · D4 — 산출물 발행 (validation + package + lineage)
##
## ★직전 라운드(Q5)의 mailbox alpha_package.json 은 **덮어쓰지 않는다** (사후 개작 금지, PREREG §9).
##   본 라운드 산출은 depth_aligned/alpha_package_depth.json 으로 별도 발행.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/depth_aligned/d4_emit.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
OUT  <- "stage_artifacts/WT-D20260813_005"
DOUT <- file.path(OUT, "depth_aligned")
MB   <- "qepm/mailbox/worktask/WT-D20260813_005"

D1 <- readRDS(file.path(DOUT, "d1_depth_stats.rds"))
D2 <- readRDS(file.path(DOUT, "d2_result.rds"))
D3 <- readRDS(file.path(DOUT, "d3_diagnostics.rds"))
RES <- D2$RES; PR <- D2$PR; DG <- D3$DG; live <- D3$live
HYP <- fromJSON(file.path(MB, "alpha_hypothesis.json"), simplifyVector = FALSE)$selected

pt <- function(a) RES[[a]]$portfolio_alpha_t_nw_lag3
ir <- function(a) RES[[a]]$net_sr
PRIMARY_T <- PR$OBJ_MEAN_DEPTH$t; THRESH <- 2.0
VERDICT <- if (is.finite(PRIMARY_T) && PRIMARY_T >= THRESH) "SUPPORTED" else "NOT_SUPPORTED"

## ── 라우팅: 부모 지시의 두 분기 중 어느 쪽도 성립하지 않는 제3 결과를 정직 라벨 ──────────
depth_gap  <- PRIMARY_T - PR$OBJ_MEAN_Q5$t                # 점추정 이동
depth_direct_t <- D2$depth_vs_q5$nw3_t                    # DEPTH vs Q5 직접 paired
branch <- if (VERDICT == "SUPPORTED") "A_depth_is_driver_supported" else
          if (abs(depth_gap) < 0.3) "B_depth_not_driver_route_material" else
                                    "C_depth_moves_estimate_but_below_threshold"

VAL <- list(
  task_id = "WT-D20260813_005", round = "depth_aligned (FQ-237 P4)",
  produced_by = "alpha-research", produced_at = format(Sys.time()),
  prereg_ref = "stage_artifacts/WT-D20260813_005/depth_aligned/PREREG_depth.md (측정 착수 전 봉인)",
  prior_round_ref = "stage_artifacts/WT-D20260813_005/alpha_validation.json (Q5 판정 — 불변)",
  selection_type = "chain", selection_objective = "canonical_port_t",

  design = list(
    single_change = "선별 목적함수의 상위 버킷 깊이 Q5(20%, 월 ~68종) → top-25(절대 개수, 중앙 7.27%)",
    depth_D = D1$D_DEPTH, depth_frac_median = D1$depth_frac_median,
    derived_not_tuned = "D=25 는 소비 top_n=25 에서 파생. 깊이 스윕 0회 (스윕 시 sweep+DSR HARD 재선언 의무).",
    K = D2$K, trailing_window_months = D2$W, top_n = D2$TOPN, cost_bps_oneway = D2$COST,
    n_factors_material = 320, combination = "z_score_aligned_equal_weight",
    normalization_held_constant = "전 arm NW lag-3 t — '깊이' 축만 격리",
    n_holding_months = 221, period = "2008-03-01 ~ 2026-07-01",
    universe = "KOSPI200 ∪ KOSDAQ150 (패널 승계, 월중앙 344종목)",
    benchmark = "IKS200 (.cache/benchmark.parquet 일별 → apply.monthly(Return.cumulative), ym 키)",
    basis = "net_sr = active SR (= IR), total SR 아님. 1급 축 = paired 월별 active NW3 t + canonical PORT_t(cap-w)."),

  change_reached_output = list(
    cor_q5_vs_depth_cellwise = D1$change_reached_output$cor_q5_depth,
    sd_q5 = D1$change_reached_output$sd_q5, sd_depth = D1$change_reached_output$sd_depth,
    sd_ratio = D1$change_reached_output$sd_depth / D1$change_reached_output$sd_q5,
    sign_split_vs_rankic = list(depth = D1$sign_split$depth, q5 = D1$sign_split$q5, n = 320),
    jaccard_depth_vs_q5_selection_median = median(D2$jaccard$depth_q5),
    note = "깊이 변경이 코드에만 있고 산출에 없는 경우를 배제 — 셀 상관 0.823·sd 1.393배·선별집합 Jaccard 중앙 0.25"),

  frame_reproduction = list(
    rule = "깊이만 바꿨으므로 직전 arm 은 소수점까지 재현되어야 한다 (PREREG §6)",
    obj_rank_port_t = list(got = pt("OBJ_RANK"), prereg = 0.94741),
    obj_rank_ir     = list(got = ir("OBJ_RANK"), prereg = 0.22811),
    obj_mean_q5_port_t = list(got = pt("OBJ_MEAN_Q5"), prereg = 0.98991),
    obj_mean_q5_paired_t = list(got = PR$OBJ_MEAN_Q5$t, prereg = 0.49298),
    pass = D2$frame_repro$pass),

  primary_endpoint = list(
    definition = "paired 월별 active 차이 (OBJ_MEAN_DEPTH − OBJ_RANK) NW lag-3 t",
    nw3_t = PRIMARY_T, threshold = THRESH, verdict = VERDICT,
    n = PR$OBJ_MEAN_DEPTH$n, mean_monthly = PR$OBJ_MEAN_DEPTH$mean,
    annualized_pct = 100*12*PR$OBJ_MEAN_DEPTH$mean),

  three_way_comparison = list(
    OBJ_RANK       = list(role="base",             paired_nw3_t = NA, capw_port_t = pt("OBJ_RANK"),      active_sr_ir = ir("OBJ_RANK")),
    OBJ_MEAN_Q5    = list(role="보조 대조(직전)",   paired_nw3_t = PR$OBJ_MEAN_Q5$t,    capw_port_t = pt("OBJ_MEAN_Q5"),    active_sr_ir = ir("OBJ_MEAN_Q5")),
    OBJ_MEAN_DEPTH = list(role="primary(신규)",     paired_nw3_t = PRIMARY_T,           capw_port_t = pt("OBJ_MEAN_DEPTH"), active_sr_ir = ir("OBJ_MEAN_DEPTH")),
    depth_effect_point = depth_gap,
    depth_vs_q5_direct_paired = list(mean = D2$depth_vs_q5$mean, nw3_t = depth_direct_t,
      interpretation = "깊이가 점추정을 3.2배(월 +0.00155→+0.00502) 옮겼으나, DEPTH−Q5 자체의 직접 paired t 는 +1.18 로 두 arm 을 추론 강도로 구분하지 못한다. '깊이가 드라이버' 는 방향 수준 진술이지 검정된 진술이 아니다.")),

  falsification = list(
    axis1_set_divergence = list(jaccard_median = median(D2$jaccard$depth_rank),
      jaccard_mean = mean(D2$jaccard$depth_rank), reject_if = "> 0.8", fired = D2$falsification$ax1_fired,
      note = "중앙 0.0 — 깊이-정합 선별은 rank 선별과 거의 겹치지 않는다(기전이 작동할 물리적 여지 최대)"),
    axis2_skew_profile = list(
      inherited_quintile_slope = list(mean_diff = mean(D2$ss_grp$d_slope, na.rm=TRUE), nw3_t = D2$falsification$ax2_slope_t,
        predicted = "음 (rank-단독 군이 더 음의 왜도기울기)", direction_ok = TRUE),
      depth_native_top25_skew = list(mean_diff = mean(D2$ss_grp$d_top, na.rm=TRUE), nw3_t = D2$falsification$ax2_top_t,
        predicted = "양 (depth-단독 군의 상위25 왜도가 더 큼)", direction_ok = TRUE),
      fired = D2$falsification$ax2_fired,
      note = "두 축 모두 예측 방향 + |t|>2 — 깊이-정합 선별이 실제로 우측꼬리-두꺼운 팩터를 고른다는 기전이 구조 관측으로 확인됨(성과와 독립)"),
    axis3_negative_control = list(objmed_depth_paired_nw3_t = PR$OBJ_MED_DEPTH$t,
      objmed_depth_capw_port_t = pt("OBJ_MED_DEPTH"), reject_if = ">= +2.0", fired = D2$falsification$ax3_fired,
      note = "같은 깊이의 중앙값 선별은 오히려 악화(paired −1.62, PORT_t −0.24). 특이성 강함 — 개선은 '깊이 자체'가 아니라 '깊이+평균' 조합에 특이적")),

  stability_cost_test = list(turnover_ratio_depth_over_rank = D2$to_ratio, threshold = 1.5,
    self_overlap_jaccard_median = lapply(D2$selfj, function(x) median(x, na.rm=TRUE)),
    verdict = "미발화 — 회전율 배율 1.003 (불안정 비용 가설 기각)"),

  detection_power = list(
    design = "PREREG §5 — 선별창에 홀딩월 자신을 포함시킨 위반 주입 arm 실측",
    lookahead_port_t = pt("LOOKAHEAD_DEPTH"), clean_port_t = pt("OBJ_MEAN_DEPTH"),
    delta_port_t = D2$detection$delta_port_t,
    lookahead_paired_t = PR$LOOKAHEAD_DEPTH$t, clean_paired_t = PRIMARY_T,
    delta_paired_t = PR$LOOKAHEAD_DEPTH$t - PRIMARY_T,
    lag1_port_t = pt("LAG1_DEPTH"), lag1_paired_t = PR$LAG1_DEPTH$t,
    monotone_lag_response = D2$detection$monotone,
    verdict = "판별력 있음 — 1개월 누출이 PORT_t 를 +1.78, paired t 를 +2.46 이동. 직전 라운드(+2.44/+3.66)와 같은 자릿수. 따라서 NOT_SUPPORTED 는 장치의 무능이 아니다.",
    caveat = "주입 효과가 직전보다 다소 작다(PORT_t Δ 2.44→1.78) — clean arm 자체가 높아진 만큼 상대 여유가 줄었다. 절대 판별력은 유지."),

  robustness = list(
    positive_month_share = DG$robustness$pos_share,
    median_monthly = DG$robustness$median,
    subperiod = DG$robustness$subperiod,
    influence_leave_out_top_k = DG$robustness$influence,
    top3_month_share_of_cumulative = DG$robustness$top3_share,
    finding = "★본 라운드 최대 반대 증거: 이득이 전반부에 몰려 있다 — sp1(2008-2014) 월 +0.0118 t 1.88 / sp2 +0.0039 t 0.67 / sp3(2020+) −0.0012 t −0.32. 상위 3개월이 누적차의 37.7%, 상위 5개월 제거 시 t 1.571→0.763. 꼬리-구동 기전이므로 소수 월 집중은 기전 정합이기도 하나, 최근 6.5년 이득 부재는 정합으로 설명되지 않는다."),

  advisory = DG$advisory, dsr = DG$dsr, dual_basis = DG$dual_basis,
  regime_advisory = c(DG$regime_advisory, list(
    q5_comparison = "직전 Q5 arm 은 crisis 에서 t −2.77 로 크게 손해였는데 깊이-정합 arm 은 +0.21(중립). 사전등록 regime_scope 의 'crisis 약화' 와 정합하되 방향은 '역전'이 아니라 '소멸'. advisory — 판정 축 아님.")),
  ax001_v2 = DG$ax001_v2, family_composition = DG$family_composition, live = DG$live,

  method_shopping_log = list(candidates_tried = 4,
    method_log = list(
      list(name = "OBJ_RANK (base, rank-IC 선별)",              port_t = pt("OBJ_RANK"),       selected = FALSE),
      list(name = "OBJ_MEAN_DEPTH (primary, top-25 평균 선별)", port_t = pt("OBJ_MEAN_DEPTH"), selected = TRUE),
      list(name = "OBJ_MEAN_Q5 (보조 대조, 직전 라운드 재현)",  port_t = pt("OBJ_MEAN_Q5"),    selected = FALSE),
      list(name = "OBJ_MED_DEPTH (negative control)",           port_t = pt("OBJ_MED_DEPTH"),  selected = FALSE)),
    note = "LOOKAHEAD_DEPTH / LAG1_DEPTH 는 후보가 아니라 검사 판별력 대조군 — 선택 풀 제외. 깊이·K·W 스윕 0회."),

  capital_eligibility = list(
    capw_port_t = pt("OBJ_MEAN_DEPTH"), hard_gate = 2.95, eligible = FALSE,
    note = "screening 실측(metric_type=canonical_screen). 자본 판정 권위는 forge build_bt_result + essence_score + discovery_graduation_gate. EW-유니버스 대비 2.9734 는 dual-basis 진단(비바인딩) — cap-w 판정 불변."),

  routing = list(
    branch = branch,
    verdict = paste0(VERDICT, " (primary t ", sprintf("%+.4f", PRIMARY_T), " < 문턱 +2.0)"),
    parent_rule_check = "부모 지시의 두 분기 중 어느 쪽도 그대로 성립하지 않는다: (i) t ≥ +2.0 아님 → '깊이 정합이 드라이버' 확립 불가. (ii) OBJ_MEAN_DEPTH ≈ OBJ_MEAN_Q5 도 아님(0.4930 → 1.5706, PORT_t 0.99 → 1.78, IR 0.27 → 0.49) → '깊이는 드라이버 아님' 도 이 데이터가 지지하지 않는다. 따라서 '선별 통계량 교체는 레버 아님' 을 여기서 확정하지 않는다.",
    destination = "Q-Lead 판단 — 재료 축(FQ-234 일별) 라우팅은 유효하되, 선별 축은 '기각'이 아니라 '조건부 보류'로 표기 요청",
    forbidden = "계열 확대 금지 (INV-7) — 깊이/K/W 격자 스윕, 문턱 사후 조정, 부기간 선택 금지",
    next_probe = list(
      "P1 (시간 구조 진단, 최우선): 이득이 sp1 집중·sp3 소멸인 기전을 가른다. 후보 2: (a) 복권형 왜도 구조 자체의 감쇠 — 320종 팩터-레벨 skewtop·왜도기울기의 연도별 추세를 직접 측정(성과 아님, 구조 관측이므로 본 데이터로 적법) (b) 선별 재료의 감쇠 — 같은 기간에 rank arm 도 함께 약화됐는지 분해. (a)가 참이면 기전은 살아 있고 연료가 마른 것, (b)가 참이면 프레임 공통 감쇠. 판정 축 아님(진단).",
      "P2 (깊이 + 국면의 교차, 새 사전등록 필수): crisis 에서 Q5 −2.77 → DEPTH +0.21 로 손실이 소멸했다. '깊이 정합이 crisis 취약성을 제거한다'는 별개 가설이며 본 라운드 데이터로 판정 금지(사후선택). 착수 전 primary·문턱·국면 라벨 규약 봉인 요구.",
      "P3 (재료 축 — 부모 라우팅 승계): FQ-234 일별 축. 월간으로 접으면 비대칭이 소멸한다는 v8.4 진단과, 본 라운드가 보인 '깊을수록 갈림 증가'(부호 갈림 43.8%→48.1%, sd 1.39배)가 같은 방향을 가리킨다 — 재료의 해상도를 올리면 깊이 효과가 커질 여지.",
      "P4 (결합층 감쇠 — 직전 P5 승계, 미소진): K=5 EW 결합이 단일 팩터의 상위-깊이 우위를 희석하는 크기는 여전히 미측정. K=1 또는 선별통계 가중 결합으로 감쇠분만 분리."),
    revival_condition = "선별 축 재도전 조건: (a) P1 에서 왜도 구조 감쇠가 아니라 프레임 공통 감쇠로 판명되거나, (b) P3 재료 축이 갈림이 더 큰 패널을 제공하거나, (c) P2 가 새 사전등록 하에 국면 조건부로 양성. 그 전까지 이 프레임(월간·return-파생 320종·top-25 EW·pooled)에서 깊이/통계량 변형 추가 탐색 금지."),

  challenge_flags = list(
    "CF1 primary NOT_SUPPORTED — paired NW3 t +1.5706 < 사전등록 문턱 +2.0. 문턱 사후 조정 없음.",
    "CF2 깊이 효과는 방향 수준 — DEPTH vs Q5 직접 paired t +1.1753 로 두 arm 을 추론 강도로 구분 못 함. '깊이가 드라이버' 를 확정 진술로 쓰지 말 것.",
    "CF3 ★시간 구조 — sp3(2020-01~) 월평균 −0.0012 (t −0.32). 최근 6.5년 이득 부재. 전기간 +1.57 은 sp1(t 1.88) 기여.",
    "CF4 꼬리 집중 — 상위 3개월이 누적차의 37.7%, 상위 5개월 제거 시 t 0.763. 기전(꼬리 구동)과 정합이나 견고성 약점.",
    "CF5 자본 자격 아님 — cap-w PORT_t 1.7775 << 2.95. EW-유니버스 2.9734 는 dual-basis 진단(비바인딩), 자본 판정 아님.",
    "CF6 승계 자산 결함 계승 — master_panel_FIXED.rds 는 원천 재현 실패(직전 라운드 실측 27종 중 cor>=0.99 8종). 본 라운드는 '재료 정의(320종 팩터 집합)' 만 승계하고 통계는 lane_a 원천에서 전부 재산출. 결함 자체는 미수리(보고 대상).",
    "CF7 라이브 α̂ 스케일 창-민감 (전기간 +0.005990 / 10y +0.001330 / 5y +0.005566). 배포 근거로 쓰지 말 것 — 본 라운드는 NOT_SUPPORTED.",
    "CF8 부모 라우팅 두 분기 미성립 — 제3 결과. '선별 통계량 교체는 레버 아님' 확정은 이 데이터가 지지하지 않는다(routing.parent_rule_check).")
)
write_json(VAL, file.path(DOUT, "alpha_validation_depth.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("발행: %s/alpha_validation_depth.json\n", DOUT))

## ── alpha_package_depth.json (AST v1.1 3층 — 직전 라운드 규약 계승) ─────────────────
live_sel <- DG$live$selected_factors
fund_pat <- "^(GR|Q|V|AC|XF|LL|B|E|F)"        # 재무-파생 = restatement_prone
leaves <- lapply(live_sel, function(f) list(
  leaf = paste0("factor_registry:", f),
  availability_rule = if (grepl("^L", f)) "fixed: price/volume t-1 (C10)" else "fixed: quarterly 45d / annual 익년 3-31 (C4)",
  restatement_prone = !grepl("^(L|M|D|S|R|C)", f)))
n_rest <- sum(vapply(leaves, function(x) isTRUE(x$restatement_prone), logical(1)))
PKG <- list(
  task_id = "WT-D20260813_005", round = "depth_aligned (FQ-237 P4)",
  as_of_date = "2026-08-13", forecast_horizon = "1M", spec_version = "ast_v1.1",
  pit = list(cutoff_rule = "홀딩월 T 의 선별은 anchor < T 인 실현 통계만 소비 (trailing 36개월)",
             panel_truncation = "anchor <= 2026-07-01 (미완료 홀딩월 2건 격리)",
             injection_test = "LOOKAHEAD_DEPTH(1개월 누출) PORT_t 3.5604 vs clean 1.7775 — 검사 판별력 실증"),
  hypothesis = list(statement = HYP$hypothesis_description, mechanism = HYP$mechanism,
                    falsification = HYP$falsification$observable, regime_scope = HYP$regime_scope,
                    inheritance_note = "alpha_hypothesis.json 무수정 승계 (Charter 원칙 8). 본 라운드는 ⑤AST + Step 1~7 만 수행."),
  factors = list(list(factor_id = "F1_selstat_meandepth_composite",
    ast = list(leaf = "SPECIAL_OP", escape_contract = list(escape_type = "SPECIAL_OP",
      op_code_path = "stage_artifacts/WT-D20260813_005/depth_aligned/d2_walkforward_depth.R::sel_topK + build_scores (선별 통계 원자료 = d1_depth_stats.R::month_depth)",
      walk_forward = TRUE)),
    role = "core_signal", restatement_exposure = n_rest)),
  combination_rule = "z_score_aligned_equal_weight", verdict = "designed",
  self_pit_check = list(performed = TRUE, leaves_checked = c(leaves, list(list(
      leaf = "SPECIAL_OP", availability_rule = "walk-forward 선별 — 홀딩월 T 의 선별은 anchor < T 인 실현 통계만 소비",
      restatement_prone = FALSE))),
    verdict = "clean",
    evidence = "①위반 주입 대조: 선별창에 홀딩월 자신 포함 시 PORT_t 1.7775→3.5604, paired t 1.5706→4.0282 (판별력 실증). ②LAG1(T−2) 1.1854 < clean 1.7775 < LOOKAHEAD 3.5604 단조 lag-반응 = 약한 실신호 지문. ③m_* full-sample 선별입력 0 — 전 통계 trailing 재산출. ④합성 스코어→forward IC 전 arm 양수(앵커 규약 정상)."),
  alpha_vector = setNames(as.list(round(live$alpha_hat, 6)), live$Ticker),
  confidence_vector = setNames(as.list(round(live$conf, 4)), live$Ticker),
  signal_matrix_ref = "stage_artifacts/WT-D20260813_005/depth_aligned/alpha_scores_depth.parquet",
  factor_specs = lapply(live_sel, function(f) list(
    factor_family = sub("[0-9_].*", "", f), proxy = f,
    formula = "Z_Score_Aligned (factor DB registry) — walk-forward 선별 K=5 의 종목별 단순평균",
    lag_rule = if (grepl("^L", f)) "price/volume t-1 (C10)" else "quarterly 45d / annual 익년 3-31 (C4)",
    winsorization = "factor DB 표준 (registry 경유)", neutralization = "none (선별층 실험 — 중립화는 진단으로만 산출)",
    economic_rationale = "복권형 우상단 왜도 하에서 소비 형태(top-25 EW 평균)와 같은 깊이·같은 함수형으로 선별 — 순위 통계가 버리는 우측 꼬리 정보를 선별 단계에서 보존",
    weight_theta = 1/length(live_sel),
    references = list("Harvey-Liu-Zhu 2016 (다중검정)", "Jensen-Kelly-Malamud-Pedersen 2022 (cost-aware)", "R32/R33 내부 실측"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = pt("OBJ_MEAN_DEPTH"),
    canonical_port_t_base_rank = pt("OBJ_RANK"), canonical_port_t_prior_q5 = pt("OBJ_MEAN_Q5"),
    canonical_n_months = RES$OBJ_MEAN_DEPTH$n_months,
    primary_paired_nw3_t = PRIMARY_T, primary_threshold = THRESH, primary_verdict = VERDICT,
    rank_ic = DG$advisory$OBJ_MEAN_DEPTH$rank_ic, icir = DG$advisory$OBJ_MEAN_DEPTH$icir,
    harvey_t_stat = DG$advisory$OBJ_MEAN_DEPTH$harvey_t,
    monotonicity = DG$advisory$OBJ_MEAN_DEPTH$monotonicity,
    subperiod_stability = DG$advisory$OBJ_MEAN_DEPTH$subperiod$stability,
    post_neutralization_ic = DG$advisory$OBJ_MEAN_DEPTH$post_neutralization_ic,
    turnover_proxy = RES$OBJ_MEAN_DEPTH$turnover_annual,
    net_active_sr_ir = ir("OBJ_MEAN_DEPTH"), alpha_annualized = RES$OBJ_MEAN_DEPTH$alpha_annualized,
    dsr_trials1 = DG$dsr$OBJ_MEAN_DEPTH$dsr_trials1, dsr_trials4 = DG$dsr$OBJ_MEAN_DEPTH$dsr_trials4,
    metric_type = "canonical_screen"),
  selection_objective = "canonical_port_t",
  challenge_flags = VAL$challenge_flags)
write_json(PKG, file.path(DOUT, "alpha_package_depth.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("발행: %s/alpha_package_depth.json (직전 mailbox alpha_package.json 은 불변)\n", DOUT))

## ── lineage (package write 직후 — L-194 순서 규약) ────────────────────────────────
src <- tryCatch({ source("02_Infrastructure/worktask/lineage_utils.R"); TRUE }, error = function(e) FALSE)
if (src && exists("record_package_lineage")) {
  tryCatch({
    record_package_lineage(task_id = "WT-D20260813_005", package_type = "alpha_package_depth",
      method_selected = "walk-forward 선별 K=5 · 목적함수 = trailing top-25 평균 활성 스프레드 NW3 t (깊이-정합)",
      input_file_paths = c("stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet",
                           "stage_artifacts/WT-D20260813_005/s1_factor_month_stats.rds",
                           "stage_artifacts/WT-D20260813_005/depth_aligned/d1_depth_stats.rds",
                           ".cache/benchmark.parquet"))
    cat("lineage 기록 완료\n") }, error = function(e) cat(sprintf("lineage 기록 실패(비치명): %s\n", conditionMessage(e))))
} else cat("lineage_utils 미가용 — 기록 생략\n")

cat(sprintf("\n★판정: %s (primary %+.4f / 문턱 %.1f) · branch=%s\n", VERDICT, PRIMARY_T, THRESH, branch))
