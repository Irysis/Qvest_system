## WT-D20260822_006 (FQ-246) P6 — alpha_validation.json + alpha_package.json + lineage
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_006"; MB <- "qepm/mailbox/worktask/WT-D20260822_006"
P  <- readRDS(file.path(OUT,"p2_arms.rds")); V3 <- readRDS(file.path(OUT,"p3_verdict.rds"))
V4 <- readRDS(file.path(OUT,"p4_conduit.rds")); V5 <- readRDS(file.path(OUT,"p5_emit.rds"))
HY <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector=FALSE)
act <- P$act; c0 <- act$C0$act; BT <- P$BT
num <- function(x) as.numeric(x)
PRI <- V3$PRI; ORC <- V3$ORACLE

AV <- list(
  task_id = "WT-D20260822_006",
  round_id = "FQ-246_state_conditional_factor_selection_WT-D20260822_006_20260822",
  fq_ref = "FQ-246",
  produced_by = "alpha-research",
  produced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  metric_type = "canonical_screen",
  metric_type_note = paste("전 수치 = canonical_screen_bt() 표준 top-25 EW long-only 실측(15bps, contract build_benchmark_compare 경유).",
    "admission binding 아님 — graduation HARD 3종(PORT_t 2.95 · oos_retention 0.7 · calmar 0.64)은 forge-authoritative 값에만 적용된다.",
    "본 라운드 canonical 수치로 졸업 주장 금지."),
  prereg_ref = "stage_artifacts/WT-D20260822_006/PREREG.json (mean-blind 봉인, sealed_at 2026-08-22)",
  hypothesis_ref = "qepm/mailbox/worktask/WT-D20260822_006/alpha_hypothesis.json (alpha-hypothesis, verdict=designed) — mechanism/falsification/regime_scope 자구 승계, 재작성 없음",

  control_parity = list(
    C0_port_t_measured = num(BT$C0$portfolio_alpha_t_nw_lag3),
    C0_port_t_published_FQ244 = 0.94741072,
    delta = num(BT$C0$portfolio_alpha_t_nw_lag3 - 0.947410715815),
    verdict = "대조군 비트-동치 재현 — 선별 궤적·패널·top-N·비용·벤치 전부 FQ-244 자구 승계 확인"),

  power_precheck = list(
    principle = "검정력은 선언 상수가 아니라 직접 측정. 계약 기본 sd 0.0394 는 무작위 top-25 EW 쌍 척도이고 본 대조는 선별·결합을 공유하는 상태-조절 대조라 다른 양이다(실측 0.27~0.49 배).",
    MATERIAL_annual_pct = num(P$MATERIAL),
    MATERIAL_derivation = "C0 월평균 net active 0.003242 · NW3 SE 0.003422 · t 0.9474 → (2.95*SE − mean)*12*100",
    measured = P$PW,
    degeneracy_check = list(implied_t_own_all_arms = 2.000,
      note = "자기-diff sd 로 만든 바는 t 검정의 단위 번역 — 판정 문턱으로 쓰지 않고 효과크기 단위로만 해석. 독립 바 = implied_t_band 6.01~8.32.",
      preregistered = TRUE),
    nw_note = "nw_inflation 계열 실측 0.771~1.112 (가정 상수 1.25 미사용). paired diff AR1 = -0.0045 이라 NW 팽창이 애초에 발생하지 않는다.",
    target_persistence = list(paired_diff_AR1 = -0.0045,
      regressor_AR1 = list(u_agree = 0.6213, u_disp = 0.4376, u_bear = 0.5377),
      decision = "★대상 지속성을 먼저 재고 판정 — 성과 차 계열은 무자기상관이라 NW 보정 실질 무영향이나 병기, 반면 R1/F1 회귀변수(u)는 AR1 0.44~0.62 로 지속적이라 그 축의 기울기 t 는 NW lag-3 필수. 두 축에 같은 처방을 무비판 이식하지 않았다.")),

  transport_gate_R1 = c(V3$R1, list(
    interpretation = paste("★성과 판정 전에 답이 나왔다 — 완전예지 여유폭(연 +13.69%p) 이 두 관측 가능 상태축 어디에도 유의하게 종속되지 않는다",
      "(disagreement t +0.876 · dispersion t +0.384). 즉 여유폭이 실재한다는 것과 그것이 상태로 지목 가능하다는 것은 다른 명제이고, 본 라운드가 후자를 기각했다."))),

  primary = PRI,
  primary_note = "co-primary = T2_AGREE(축1 선택 강도) · T3_DISP(축2 계열 방향). argmax 챔피언 선발 없음 → sweep 미해당, DSR 게이트 비발동.",

  conduit_test = list(
    purpose = "null 이 '상태 부재' 인가 '규칙 형태가 상태를 성과로 못 옮김' 인가를 가른다 (FQ-244 LEAK1 양성대조 실패가 남긴 교훈의 일반화)",
    measured = V4$CON,
    verdict = paste("★두 가중-형 규칙 모두 전도성 확립 — 완전예지 상태를 넣으면 T2형 paired +3.45%p/yr(t 2.014) · T3형 +3.39%p/yr(t 2.466).",
      "⇒ T2_AGREE/T3_DISP 의 null 은 전도성 부재가 아니라 **상태 정보 부재** 다."),
    ceiling_finding = paste("★부수 확립(신규) — 완전예지 상태조차 이 가중-형 규칙을 통과하면 여유폭의 3.45/13.69 = **25.2%** 만 회수되고",
      "PORT_t 는 1.70~1.82 로 벽 2.95 에 미달한다. ORACLE_K(월별 단일 팩터 **하드 선택**)와 오라클-상태 **소프트 틸트** 사이의 격차가 여유폭의 약 3/4 다.",
      "즉 이 마디의 여유폭은 '소프트 가중' 형태로는 원리적으로 대부분 접근 불가하며, 접근하려면 이산 하드 선택이 필요하다."),
    T1_form_conduit_failed = list(arm="ORACLE_STATE_T1", t_nw3=num(V3$PC$t_nw3), port_t=num(V3$oracle_state_port_t),
      note="확신-첨예화(T1) 형태는 완전예지 상태로도 t 0.350 — 전도성 미확립. ⇒ T1_AGREE 의 null 은 상태 부재 증거로 쓰지 않는다(전도성 부재 라벨). FQ-244 LEAK1 미통과와 같은 계통.")),

  permutation_null = list(
    design = "상태 계열을 월 순서로 무작위 치환해 같은 규칙을 재실행(각 축 40회, canonical_screen_bt 실경로). 단일 셔플 대조의 운을 배제한다.",
    measured = V4$PERM,
    verdict = paste("★규칙-형태 자체가 비용을 만든다 — 셔플 상태의 paired t 평균 -1.06(축1) / -1.02(축2).",
      "관측 t 는 축1 62.5 백분위(one-sided p 0.375) · 축2 90.0 백분위(p 0.100) ⇒ 어느 축도 5% 수준에서 무작위 상태를 이기지 못한다.",
      "사전등록 R4 가 발화시킨 N1_SHUF_A 단일 draw(t -2.481)는 셔플 분포 하위 5% 근방의 불운한 draw 였고, 규칙-형태 비용의 정본은 분포 평균 -1.06 이다."),
    consequence = "arm-vs-C0 비교는 규칙-형태 비용을 포함한다. 상태 정보량의 정직한 척도는 arm-vs-셔플분포 백분위이며 그 값이 위와 같다."),

  falsification_measured = list(
    F1_direction_mediator = c(V4 = NULL, V3$F1, list(
      cluster_power_declaration = list(target_rho=0.40, n_clusters=13, n_obs=1105,
        critical_rho_at_clusters=0.5529427, required_clusters=25, verdict="NO_GO_CLUSTER_BINDS"),
      design_substitution = "★계약(cluster_power.R)이 계열-간 이질성 설계를 착수 금지시켰다(군집 13 < 필요 25, 관측 수를 늘려도 안 풀림). 지시대로 군집-내부에서 닫히는 월-단위 2군 IC 차 설계로 교체했다. 이것은 사후 변명이 아니라 봉인 전 기록이다.")),
    F2_mediator_movement = V3$F2,
    F2_note = "★봉인 전 사전 고정 — T1_AGREE(0.9231)·T3_BEAR(0.9231)는 문턱 0.90 초과라 NO_MEDIATOR_MOVEMENT 예약 라벨. 두 arm 의 null 은 기전 반증 증거로 쓰지 않는다. co-primary 2종은 모두 매개를 움직였다(0.724 / 0.852 = 월 6.9 / 3.7 종목 교체).",
    F3_agent_reality = V4$F3,
    F3_note = "★기전의 agent 는 실재한다 — 고분산 월에 개인 순매수 횡단면 집중(HHI)이 상승(cor +0.272, 표준화곱 NW3 t +1.776 ≥ 1.5). 상위 십분위 몫도 동방향(cor +0.191). 죽은 것은 agent 서술이 아니라 그 상태에서 '어느 팩터를 신뢰할지' 로의 전이다.",
    coherence = paste("★반증 축이 성과보다 먼저, 그리고 서로 다른 방향으로 답을 줬다: F3(agent 실재)와 conduit(규칙 전도성)는 통과했고",
      "R1(여유폭-상태 연결)과 F1(계열 방향 지목)은 기각됐다. 성과 null 은 이 조합이 예측하는 바와 정확히 정합한다 — 사후 해석이 아니다.")),

  negative_control = list(
    single_draw = PRI[contrast %in% c("N1_SHUF_A","N2_SHUF_D")],
    resolved_by = "permutation_null (40 draws/축) — 단일 draw 의 EFFECT_NEGATIVE 는 분포 하단 draw 로 확인. RULE_ARTIFACT 는 '규칙이 노이즈 하에서 평균 -1 t 의 비용을 만든다' 는 형태로 성립하며, 처치 해석을 무효화하지는 않는다(처치와 셔플을 같은 분포 위에서 비교했으므로)."),

  window_reachability = list(
    obligation = "PORT_t 2.95 미달 보고 시 그 창의 도달 가능 상한 병기 (mandate)",
    ORACLE_K = list(port_t_IKS200 = 4.64699909, paired_annual_pct = num(ORC[contrast=="ORACLE_K", ann_pct]),
      paired_t = num(ORC[contrast=="ORACLE_K", t_nw3]),
      note = "FQ-244 기측정 재현 — {K 중 고르기} 족 상한. 4.647 > 2.95."),
    ORACLE_FWD = list(port_t_IKS200 = 31.45062294, paired_annual_pct = num(ORC[contrast=="ORACLE_FWD", ann_pct]),
      paired_t = num(ORC[contrast=="ORACLE_FWD", t_nw3])),
    verdict = "창-도달가능성 확보 — 본 창에서 이 마디는 PORT_t 4.647 까지 도달 가능하다. 따라서 본 라운드의 null 을 '창이 좁아서' 로 설명할 수 없다."),

  headroom_recovery = list(
    denominator_annual_pct = num(ORC[contrast=="ORACLE_K", ann_pct]),
    measured = V3$REC,
    verdict = paste("여유폭 회수 실질 0 — 최선 arm T3_DISP 가 +0.27%p/yr(회수율 1.94%)이고 t 0.251, 셔플 분포 90 백분위(p 0.100).",
      "축1 arm 들은 음수 회수(-8.0 ~ -9.2%). ⇒ '여유폭의 일부라도 회수됐는가' 에 대한 답은 **아니오** 다.")),

  basis_three_way = list(measured = V3$BAS,
    invariance_note = "paired 판정은 basis 불변 (Δt ~ 1e-16). 수준값은 basis 에 크게 종속(C0 0.947 / 1.491 / 2.088).",
    benchmark_label_caveat = "★canonical_screen_bt 는 benchmark_id 를 'KOSPI200_total_return' 으로 하드코딩한다. 실제 넘긴 계열 = primary: .cache/benchmark.parquet(IKS200) / parent: stage_artifacts/WT-D20260822_002/p0_returns.rds$bench(K200∪KQ150 cap-w) / EW-유니버스: canonical_screen_bt 내부 diag_ew_universe."),

  robustness = list(liquidity_2e8 = V3$LIQ, subperiod = V3$SUB,
    subperiod_note = "★진단 병기만 — era 교락 + universe_exit_unrecorded_pre201512(편입만 기록·퇴출 미기록, 편향 하방/중립). 국면 주장 승격 금지.",
    top5_exclusion = V3$TOP5,
    top5_note = "상위 5개월 제외 시 전 arm 이 더 음수 — 관측된 소폭 양수(T3_DISP)는 소수 월 의존."),

  advisory_battery = V3$ADV,
  advisory_note = "★rank-IC 계열은 advisory (measurement-graduation §3). ic_t_nw3 4.43~5.59 로 전 arm 이 강한데 portfolio-alpha t 는 0.06~1.18 — IC→PORT_t 전이 벽의 교과서적 재현이며 Cycle 2 교훈(두 t 는 다른 양) 그대로다.",

  cost_awareness = list(cost_model_version = "v2.4_kr_retail_15bps",
    turnover_annual = V4$RED,
    note = "전 수치는 delta-based 15bps 차감 후 net. 회전율 증분 +0.07 ~ +1.06/yr. ★C0 자체 회전율 11.55/yr 로 Research Philosophy P6 권고(TO ≤ 11.0/yr)를 이미 상회 — 본 라운드가 만든 초과가 아니라 승계된 하네스 속성이며, 처치는 그것을 더 늘린다(자본 경로 진입 시 제약)."),

  ax001_v2 = list(measured = V5$AX,
    bad_months = 44, normal_months = 177, bad_definition = "벤치 월수익 하위 20%",
    note = "★가설의 regime_scope 는 holds_in 에 '위기-회복' 을 넣었는데 실측은 반대 방향이다 — T3_DISP 위기 alpha -1.99%p vs 정상 +0.83%p(위기 t -0.971). 유의하지 않으므로 국면 주장으로 승격하지 않되, 승계한 regime_scope 의 이 항목은 실측 미지지로 기록한다(재작성 아님)."),

  dsr_diagnostic = list(value = num(V4$dsr), n_trials = 4L,
    selection_type = "preregistered_arms_no_champion",
    gate_status = "비발동 — sweep 형 selection(열거 trial 에서 argmax/threshold-pick) 미해당. 수치는 진단용 기록.",
    note = "★argmax 로 챔피언을 뽑는 순간 sweep 재분류 + DSR 0.5 HARD 발동임을 사전등록에 명시했고, 본 라운드는 각 arm 독립 라벨을 유지했다."),

  redundancy = list(cor_active_vs_C0 = V4$RED,
    note = "처치 arm 의 active 계열이 C0 와 0.930~0.977 상관 — u=0 환원 설계의 직접 귀결(수준 틸트 0, 순수 상태-조절 성분만 차이). 신규 알파 원천이 아니라 기존 마디의 조절이므로 redundancy_cluster_id 는 C0 와 동일 클러스터."),

  verdict = "STATE_CONDITIONAL_SELECTION_POWERED_NULL_WITH_TRANSPORT_FAILURE",
  verdict_detail = paste(
    "성과-무관 횡단면 상태 2축(팩터 간 순위 불일치 · 수익 횡단면 분산) 조건부 팩터 선택은 C0 대비 개선 없음 —",
    "co-primary 2종 모두 POWERED_NULL_NO_MATERIAL_EFFECT(T2_AGREE -1.10%p/yr t -0.829 CI95 상단 +1.50 · T3_DISP +0.27%p/yr t +0.251 상단 +2.34, MATERIAL 8.22 배제).",
    "★그런데 이 라운드의 실질 산출은 성과 null 이 아니라 **성과 이전에 나온 두 개의 분리 판정**이다:",
    "(1) R1 수송 게이트 — 완전예지 여유폭(연 +13.69%p)이 관측 가능 상태축에 무관(t +0.876 / +0.384) ⇒ 여유폭의 실재와 지목 가능성은 다른 명제다.",
    "(2) 전도성 확립 — 완전예지 상태를 넣으면 같은 규칙이 t 2.01~2.47 을 낸다 ⇒ null 은 규칙 무력이 아니라 상태 정보 부재다.",
    "그리고 (3) 기전의 agent 는 실재한다(F3 고분산월 개인 순매수 집중 상승 t +1.78) — 죽은 고리는 agent 도 규칙도 아닌 '상태 → 어느 팩터를 신뢰할지' 의 전이다(F1 t 1.08, 순열 p 0.279).",
    "부수 확립(신규·이 라운드가 처음 잰 것): 완전예지 상태조차 **소프트 가중** 형태로는 여유폭의 25.2% 만 회수하고 PORT_t 1.70~1.82 로 벽 미달 —",
    "ORACLE_K 의 4.647 은 **이산 하드 선택**의 상한이며 소프트 틸트 족의 상한은 그보다 훨씬 낮다. 이는 후속 설계 공간을 좁힌다."),
  round_verdict = "CONFIG_SCOPED_NEGATIVE__STATE_AXIS_DOES_NOT_INDEX_FACTOR_HEADROOM",

  next_probe = list(
    list(id = "NP1", title = "이산 하드 선택 형태의 상한 재측정 (소프트 틸트 상한 3.45%p 의 형태 의존성)",
      rationale = "본 라운드 신규 실측 — 오라클 상태를 소프트 가중으로 흘리면 여유폭의 25.2% 만 나온다. ORACLE_K(하드 단일 선택)와의 격차 3/4 가 순수 형태 손실인지, 아니면 '하드 선택은 오라클 정보의 다른 부분을 쓴다' 인지 미분리. 오라클 상태 + argmax 하드 선택 arm 을 사전등록해 형태-손실을 정량 분리한다(오라클 arm 은 판정 대상 아닌 상한 눈금이므로 sweep 아님).",
      consumes = "본 라운드 p4_conduit.rds + FQ-244 p4_verdict.rds"),
    list(id = "NP2", title = "상태 아닌 **구조** 축 — 팩터별 유효 종목수·커버리지 이질이 슬롯 배분을 지배하는가",
      rationale = "R1 이 시간축 상태를 기각했으므로 남은 축은 팩터-횡단면 구조다. FQ-116 이 M3(커버리지 이질)를 tercile |t| 0.88 로 기각했으나 그것은 다른 팩터 풀(고정 5종)이었고, 본 풀(매월 재선별 K=5, 선별 이력 103종·13 계열)에서는 미측정. F2 에서 처치가 월 3.7~9.7 종목을 실제로 움직였다는 사실은 슬롯 배분이 여전히 살아있는 레버임을 뜻한다.",
      consumes = "본 라운드 alpha_scores.parquet + p1c_family.rds"),
    list(id = "NP3", title = "F3 양성의 독립 소비면 — 개인 순매수 집중을 팩터 선택이 아니라 **위험/모니터링 축**으로",
      rationale = "F3 는 통과했는데 팩터 선택으로의 전이만 실패했다(소비면 7종 체크리스트 ④⑤). 고분산×개인집중 월은 risk-research 의 crowding 진단과 monitoring tripwire 후보이며, 알파 선택면이 아닌 곳에서 소비 가능성이 미측정으로 남는다.",
      consumes = ".cache/investor_stock/investor_wide.parquet + 본 라운드 p4_conduit.rds$conc")),

  revival_conditions = list(
    state_axis_revival = "새 상태 후보가 ORACLE_K 여유폭 회귀에서 |t| ≥ 1.5 (R1 게이트)를 통과하면 본 축은 즉시 재개. 본 라운드는 축 2종(+강등 1종)만 기각했지 '상태 조건부 선택' 족을 기각하지 않았다(INV-7 config-scoped).",
    soft_tilt_ceiling_revival = "소프트 틸트 상한 3.45%p 는 본 규칙 2종(중심성·계열방향)에서 잰 값이다. 다른 가중 함수형이 오라클 상태로 더 높은 상한을 내면 형태-손실 진단은 갱신된다.",
    bear_prob_revival = "bear_prob 축은 성과-파생이라 사전에 강등했고 실측도 여유폭 회귀 t -1.354(부호 반대). DFA 아크의 위기-조건부 3배 우위는 여전히 소비면 후보이나 팩터 선택면에서는 재개 신호 없음."),

  falsification_format_note = "반증 조건에 처치 arm 의 PORT_t 는 등장하지 않는다(성과 동어반복 금지 준수). F1 의 rank-IC 는 처치 성과가 아니라 기전의 매개변수다."
)

write_json(AV, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat("[written] alpha_validation.json —", length(AV), "keys\n")
