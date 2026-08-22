## alpha_package.json 발행 (WT-D20260821_001 / FQ-235 Lane C)
## 수치는 전부 측정 산출물에서 읽는다 — 손타이핑 금지.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
OUT <- "stage_artifacts/WT-D20260821_001"; MB <- "qepm/mailbox/worktask/WT-D20260821_001"
R    <- fromJSON(file.path(OUT, "laneC_result.json"),      simplifyVector = FALSE)
ADV  <- fromJSON(file.path(OUT, "laneC_adversarial.json"), simplifyVector = FALSE)
META <- fromJSON(file.path(OUT, "laneC_score_meta.json"),  simplifyVector = FALSE)
HYP  <- fromJSON(file.path(MB,  "alpha_hypothesis.json"),  simplifyVector = FALSE)

num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
arm_stats <- function(tag) {
  a <- R$linear_arms[[tag]]; d <- META$diag[[c(L_mean="s_mean", L_q50="s_q50", L_q90="s_q90")[[tag]]]]
  n <- num(d$n_months)
  list(arm = tag,
       ## ── 신호력(진단, advisory) ──
       rank_ic_mean = num(d$rank_ic_mean), icir = num(d$icir), rank_ic_n_months = n,
       rank_ic_harvey_t = num(d$icir) * sqrt(n),
       ## ── 포트폴리오 실현(1급) ── ★rank-IC t 와 명확히 구분(qvest-alpha-style Cycle 2 교훈)
       total_net_sr = num(a$total_sr), portfolio_alpha_t_nw_lag3 = num(a$port_t),
       portfolio_alpha_t_pvalue = num(a$port_t_p), active_ir = num(a$active_ir),
       alpha_annualized = num(a$alpha_annualized),
       cagr = num(a$cagr), mdd = num(a$mdd), calmar = num(a$calmar),
       turnover_annual = num(a$turnover), n_months = num(a$n_months),
       dsr_diagnostic = num(R$dsr_diag_n_trials_1[[tag]]))
}
arms <- lapply(c("L_mean","L_q50","L_q90"), arm_stats); names(arms) <- c("L_mean","L_q50","L_q90")

pkg <- list(
  wt_id = "WT-D20260821_001", round_id = "WT_D20260821_001_LANEC", fq = "FQ-235 Lane C",
  agent = "alpha-research", produced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  prereg = "stage_artifacts/WT-D20260821_001/PREREG_WT_D20260821_001.md (측정 전 발행·고정)",
  metric_type = "canonical_screen", selection_type = "chain",
  role_boundary = "α̂(스코어)만. 공분산·weight·사전최적화 없음.",

  ## ── 가설층: alpha-hypothesis(fable) 발행분 **그대로 승계**. 재작성·재해석 없음 ──
  hypothesis = list(
    source = "qepm/mailbox/worktask/WT-D20260821_001/alpha_hypothesis.json",
    inherited_verbatim = TRUE, designed_by = HYP$designed_by, verdict_at_design = HYP$verdict,
    hypothesis_title = HYP$selected$hypothesis_title,
    hypothesis_description = HYP$selected$hypothesis_description,
    support_criterion = HYP$selected$support_criterion,
    mechanism = HYP$selected$mechanism,
    falsification = HYP$selected$falsification,
    regime_scope = HYP$selected$regime_scope,
    challenge_flags = HYP$challenge_flags,
    note = "Charter 원칙 8 No Silent Override — 본 에이전트는 위 4층을 수정하지 않았다."),

  ## ── ⑤ AST 리프 ──
  ast = list(leaf_class = META$ast_leaf$class, train_window_end = META$ast_leaf$train_window_end,
             train_leaves = META$ast_leaf$train_leaves, note = META$ast_leaf$note,
             escape_leaf_justification = paste("선형 arm 은 학습 산출 스코어이므로 FIELD 가 아니라",
               "escape 리프 MODEL_SCORE 로 등록한다(사전등록 §9). 저장 패널의 FIELD 위장 없음.")),

  frame = R$frame,
  linear_arms = arms,
  ml_reference_recorded = R$ml_reference,
  ranking_8arm = R$ranking_8arm,

  ## ── 사전등록 판정 (기계 규칙이 정한 것만) ──
  verdicts = list(P1 = R$P1, P2 = R$P2, F1 = R$F1, F2 = R$F2, F3 = R$F3,
                  regime_interaction_c = R$regime_interaction_c,
                  overall_machine = R$overall_verdict),

  ## ── 판정 서술 (해석 — 기계 판정과 분리) ──
  reading = list(
    headline = paste("음성 대조는 **확립되지 않았다**. P1 등가는 3쌍 전부 UNDERPOWERED(미결)이고,",
                     "P2(표적 서열 재현)는 FAIL(ρ = -0.50)이며, F1 은 등록 기준으로 FAIL 이다.",
                     "확정 가능한 서술은 '연 6.0~9.7%p 이상의 용량 효과는 부재' 까지이며,",
                     "'용량은 중요하지 않다' 로 확장하지 않는다."),
    p1_reading = paste("3쌍 |t| < 2.0 (mean -0.27 / q50 -0.48 / q90 +1.59)이나 관측 효과가 전부 MDE 미만.",
      "★라벨은 sd 선택에 강건: 계열 자신 sd 기준(9.68/6.05/7.56%p)과 계약 외부 기준 sd 0.0394 기준",
      "(7.57/6.52/7.59%p) 어느 쪽에서도 관측(-1.32/-1.45/+6.00%p)이 밑돈다.",
      "⚠계약이 스스로 mean 쌍을 INCONCLUSIVE_BAR_RESTATES_T 로 신고했다(implied_t 2.00)",
      "— 계열 자신 sd 로 만든 바는 t 검정의 재진술이라, 판정은 외부 기준 sd 축을 근거로 읽는다.",
      "armC_power_addendum(MDE 연 9.25%p)의 예측이 그대로 재현됐다 — top-25 이산 선별이 해상도를 붕괴시킨다."),
    p2_reading = paste("선형 서열 mean > q50 > q90 vs ML 서열 q90 > mean > q50 — ρ = -0.50.",
      "표적 서열은 모델 계열을 건너 전이되지 않았다. 기하 결정론에 **불리한** 실측이다.",
      "단 n=3·arm 비독립이라 관찰이지 검정이 아니며, 사후 재현 검사라 secondary 로 격하돼 있었다."),
    f1_reading = paste("등록 기준 FAIL (J̄_T 0.1879 < J̄_M 0.2071, gap -0.0191, NW3 t -2.32).",
      "★그러나 적대검증에서 pooled J̄_M 이 **반대 방향 두 부분모집단의 평균**임이 실측됐다:",
      "ML 내부 0.1412 vs LINEAR 내부 0.2730 (1.93배). T 를 ML 내부와 대비하면 +0.0468 (t +7.08)로",
      "**표적 축 군집이 강하게 확인**되고, LINEAR 내부와 대비하면 -0.0850 (t -7.24)이다.",
      "기전: 사전등록 §2.1(3) 이 세 선형 arm 에 동일 설계행렬 + 동일 유지열 K_m 을 강제해",
      "손실만 다르게 만들었다 — 선형 arm 끼리 닮는 것은 설계가 강제한 결과다.",
      "⇒ 등록 판정(FAIL)은 유지하되, pooled 기준선은 기전 해석의 근거로 쓸 수 없다."),
    f2_reading = paste("3쌍 전부 |t| < 2.0 → 등록 기준 PASS(꼬리 식별 등가). 단 3쌍 전부 UNDERPOWERED 라",
      "'ML 의 꼬리 우위 부재'를 종결로 쓰지 않는다. q50 쌍 t -1.82 가 문턱에 가장 가깝다.",
      "C2(EVT) 부활 신호는 발화하지 않았다."),
    f3_reading = paste("PASS — rho_LIN -0.2851 vs rho_ML -0.3753, |Δ| 0.0901 ≤ 0.25, 부호 일치.",
      "왜도 ↔ (q50-mean) gap 연결이 선형 계열에서도 같은 부호·유사 크기로 재현됐다",
      "⇒ 이 연결은 GBM 특유 산물이 아니라 **데이터 성질**이다. 기하 가설의 함의 1건이 살아남았다.",
      "이 라운드에서 기하 가설을 지지하는 유일한 등록-기준 통과 관측이다."),
    regime_reading = paste("§7(c) 연속 상호작용: mean slope -0.00672 (t -1.88, p 0.061) ·",
      "q50 -0.00286 (t -1.10) · q90 +0.00425 (t +1.53). 어느 쌍도 |t| ≥ 2.0 아님.",
      "부호는 regime_scope 의 'crisis 에서 용량 효과' 예측과 오히려 반대 방향(mean 쌍에서 위기 확률이",
      "높을수록 ML-linear 가 더 음수)이나 유의하지 않다 — 경계 주장은 미검증으로 남는다."),
    variance_observation = ADV$variance_decomposition_L_mean_vs_ML_mean,
    what_this_round_does_not_claim = list(
      "자본 자격 — 없음(사전등록 §9). graduation HARD 3종 판정 대상 아님.",
      "'선형이 GBM 보다 낫다' — 주장 안 함. paired 평균 차는 전부 비유의.",
      "'용량 효과 부재' 종결 — 주장 안 함. 검정력 미달로 미결.",
      "방향(family) 판결 — 없음(INV-7). 본 config(월간 횡단면·324피처·top-25 EW·198개월)에 한정.")),

  adversarial = ADV,

  ## ── 사전등록 규율: 어긋날 뻔한 지점 정직 기재 (§10) ──
  prereg_discipline_notes = list(
    list(item = "벤치 캐시 vintage 이동", detail = R$frame$benchmark_vintage_incident,
         handling = paste("parity 의 hard 축을 사전등록 §3 이 1급으로 지정한 ret_net 계열의",
           "비트 동일성으로 옮겼다(스칼라 2개 tol 1e-6 → 198개월 전 계열 정확 일치 = **강화**).",
           "벤치 의존 스칼라는 전 arm 을 현 vintage 로 재측정해 단일 기준으로 통일했고,",
           "08-13 vintage 를 지어내지 않았다(절단으로 재구성 불가함을 실측 확인)."),
         near_miss = "여기서 문턱을 느슨히 했으면 프레임 드리프트를 통과시킬 뻔했다."),
    list(item = "합성 패딩월 2026-09-01", detail = R$measurement_window_fix,
         near_miss = paste("F1/F2 초회 산출이 199개월을 써서 전 arm 에 hit=0 가짜 달을 먹었다.",
           "영향은 4번째 소수점이고 라벨 전환은 없었지만, 발견 못 했으면 조용히 남았을 결함이다.")),
    list(item = "R 구문 오류 2건(top-level if/else 줄바꿈)",
         detail = "선행 세션 중단 시점의 미완성 코드. 판정 로직 변경 없이 괄호로 감싸 수리.",
         near_miss = "스펙 변경 아님 — 배관 수리."),
    list(item = "F1 기준선 분해는 사후(post-hoc)",
         detail = paste("ML 내부 기준선 대비 T 가 +0.0468 (t +7.08)로 부호가 뒤집히지만,",
           "이 대비는 사전등록되지 않았다. 따라서 **등록 판정 FAIL 을 번복하지 않고**",
           "재등록 next_probe 의 근거로만 쓴다(§10 측정 후 문턱 변경 금지)."),
         near_miss = paste("★이 지점이 본 라운드 최대 유혹이었다 — 분해가 가설에 유리하므로",
           "'사실은 F1 이 통과'로 서술하고 싶어진다. 그건 사후 기준선 선택이다. 거부했다.")),
    list(item = "F1 역방향 유의성(t -2.32)은 등록된 판정 규칙이 아님",
         detail = "F1 은 단측(≥ +0.05 ∧ t ≥ +2.0)으로만 등록됐다. 역방향 유의는 서술적 증거로만 취급."),
    list(item = "경고월 민감도는 사후 라벨 진단",
         detail = ADV$warned_month_sensitivity$reading),
    list(item = "부분 산출물 재사용 판단",
         detail = paste("laneC_scores.parquet(68,451행·199개월·전 값 유한·전 값 상이·월별 N 317~352·",
           "월 연속 결번 0)와 laneC_score_meta.json·laneC_conditioning.rds 가 스코어 스크립트의",
           "**말미 3개 산출물 전부**이고 동일 타임스탬프(09:06)라 완주 증거로 판단 → **재사용**.",
           "재실행하지 않았다. 사전등록은 이미 고정본이 있어 **재작성 없이 승계**했다."))),

  ## ── qvest-alpha-style 출력 의무 항목 ──
  style_compliance = list(
    factor_zoo = list(
      economic_rationale = paste("승계(hypothesis.mechanism): KR 개인 복권형 수요가 salient 특성에만",
        "지불해 비-salient 상방 후보가 방치되고, 기관은 TE·유동성·집중도 mandate 로 그 분산 바스켓을",
        "못 담는다. 본 라운드는 이 원천을 **새로 발굴하지 않고**, 그 회수량을 정하는 것이 학습기 용량인지",
        "표적 범함수인지를 가리는 **검증 라운드**다(Validation > Discovery)."),
      redundancy_cluster_id = "FQ233_LANEA_324F_TOP25EW__CONTROL_ARMS",
      redundancy_note = paste("신규 팩터를 추가하지 않았다. 세 arm 은 기존 Lane A 패널(dedup 324)의",
        "재-추정이며 자본 후보가 아니다 — factor zoo 순증 0.")),
    cost_aware = list(
      basis = "전 수치 net-of-cost 15bps one-way (canonical_screen_bt 내부 delta-based 과금)",
      gross_only_reported = FALSE,
      turnover_annual = lapply(arms, function(a) a$turnover_annual),
      note = "gross 단독 보고 없음. total_net_sr·active_ir 전부 비용 차감 후."),
    uncertainty_aware = list(
      point_vs_interval = paste("점추정 대신 **최소검출효과(MDE)**를 전 판정에 병기해",
        "미결(UNDERPOWERED)과 종결(POWERED_NULL)을 분리했다 — P1 3쌍·F2 3쌍 전부."),
      subperiod_axis = paste("분포 축 = ①paired NW lag-3 t ②MDE 이중 sd(계열/외부 기준)",
        "③국면 연속 상호작용(§7c). rank-IC harvey-t 는 advisory 로만 기재."),
      rank_ic_vs_portfolio_alpha_separated = TRUE,
      cycle2_lesson_instance = paste("★본 라운드가 그 교훈의 새 실례다: L_q50 은 rank-IC harvey-t +3.49",
        "(2.95 초과)인데 PORT_t -0.14 · active IR -0.03. 반대로 L_mean 은 rank-IC harvey-t +1.96 인데",
        "PORT_t +1.10 으로 8 arm 중 최고. 8-arm 전체에서 rank-IC 순위 vs total SR 순위 Spearman -0.21.",
        "⇒ rank-IC 로 선별했으면 정확히 거꾸로 골랐다."))),

  ## ── 적용 불가 항목: 조작하지 않고 사유 명시 ──
  not_applicable = list(
    ax001_v2_defense_ratio = paste("적용 대상 아님 — 본 라운드는 defense family 주장을 하지 않는다.",
      "세 arm 은 표적 범함수 대조군이며 방어형 역할(expected_role)을 선언하지 않았다.",
      "crisis_alpha/bad-normal IC ratio 를 산출하면 없는 역할 주장을 만드는 것이라 산출하지 않는다.",
      "국면 축은 §7(c) 연속 상호작용으로만 보고했다."),
    correlation_vs_admitted_book = paste("산출하지 않음 — 사전등록 §9 에 따라 어느 arm 도 편입 후보가",
      "아니고 book-marginal 심사를 요청하지 않는다. admitted 대비 상관은 admission 판정용 지표이므로,",
      "자본 트랙에 올리지 않는 대조군에 대해 산출하면 승격 의도로 오독될 수 있다."),
    graduation_hard_3 = paste("판정 대상 아님(사전등록 §9). 참고로 관측치는 전 arm 이 미달이다",
      "— PORT_t 최고 L_mean +1.10 ≪ 2.95, calmar 최고 0.339 < 0.64."),
    dsr_gate = "selection_type=chain — DSR HARD 부적용. 수치는 진단으로만 기재(사전등록 §8).")
)

## ── 연속성: next_probe (≥2 의무) + 부활 조건(INV-7) ──
pkg$next_probe <- list(
  list(id = "NP1", title = "F1 기준선 재등록 — 계열-대칭 대비",
       rationale = paste("pooled J̄_M 이 공유 K_m 이 만든 선형 내부 동질성(ML 내부의 1.93배)에",
         "오염됐음이 실측됐다(t +7.08 vs -7.24 로 부호가 갈린다)."),
       design = paste("F1 을 (a) ML 내부 기준선 (b) 계열별 z 정규화 후 대비 (c) 각 선형 arm 에",
         "**독립 pivot** 을 허용해 K_m 공유를 푼 변형 — 3안 중 하나로 측정 전 1회 고정해 재등록.",
         "(c) 는 §2.1(3) 의 '손실만 다르게' 통제와 상충하므로 상충 자체를 사전등록에 명시할 것."),
       gate = "재등록 사전등록 발행 후에만 착수. 본 라운드 판정 번복 금지."),
  list(id = "NP2", title = "해상도 회복 — 이산 선별 전 단계에서 대비",
       rationale = paste("MDE 연 6.0~9.7%p 의 원인은 top-25 이산 선별이 스코어 차이를 증폭시켜",
         "paired diff sd 를 월 3.7~5.0% 로 키우는 것(armC_power_addendum 기전 재현)."),
       design = paste("동일-표적 쌍 대비를 **선별 이전** 축에서 사전등록: 월별 스코어 순위상관",
         "(Spearman) 또는 중첩-가중 대비. 이 축은 sd 가 훨씬 작아 같은 198개월로 powered null 도달 가능.",
         "착수 전 required_effect_size.R 로 MDE 를 재산출해 실제로 도달하는지 확인할 것(선-검정력)."),
       gate = "required_effect_size.R 선통과 의무."),
  list(id = "NP3", title = "q90 쌍 표적 검정 — 유일하게 문턱에 근접한 쌍",
       rationale = paste("q90 쌍만 +6.00%p/yr (t +1.59)이고 경고월 제외 시 +7.49%p (t +1.85)로",
         "문턱에 접근한다. 나머지 두 쌍은 |t| < 0.5 로 방향성조차 없다."),
       design = "q90 단일 쌍에 대해 창 연장 또는 NP2 축으로 검정력을 확보한 사전등록 1회 측정.",
       gate = "단일 쌍 사후 선택이므로 재등록 시 selection_type 재판정 필요(chain 자격 재확인)."),
  list(id = "NP4", title = "변동성 경로 축 — GBM 이 산 것이 분산인가",
       rationale = paste("L_mean vs ML_mean 은 월평균 차가 비유의(t -0.27)인데 월 sd 는 ML 이 1.16배,",
         "MDD 64.0% vs 48.9%. 용량이 평균을 못 올리고 분산만 올렸을 가능성."),
       design = "paired 대비의 결과량을 수익이 아니라 실현 변동성/최대낙폭으로 두고 사전등록.",
       gate = "사전등록 신규 발행 — 본 라운드에서 관찰만 하고 판정하지 않았다.")
)
pkg$revival_conditions_inv7 <- list(
  capacity_effect = paste("NP2/NP3 의 고-검정력 설계에서 어느 쌍이든 paired |t| ≥ 2.0 이면",
    "'용량 효과 실재'로 뒤집히고 사전등록 §7 가정 분해 (a)(b)(c) 가 의무 발화한다."),
  c2_evt = paste("F2 위배(ML 꼬리 우위)가 powered 로 관측되면 C2(EVT) 부활.",
    "본 라운드는 발화하지 않았다(3쌍 등가·단 미결). 부활 시 required_effect_size.R + cluster_power.R",
    "선통과가 명시 관문(가설 falsification 조건부 관문 승계)."),
  scope_note = paste("본 라운드의 어떤 negative 도 방향(family) 판결이 아니다 —",
    "config-scoped(월간 횡단면·324피처·무정칙 선형·top-25 EW·198개월)."),
  frontier_note = "미검 축: 일별 해상도·선별 이전 대비·분산 결과량·q90 단독 고검정력."
)
pkg$capital_claim <- "없음 — 대조군 확립 라운드(사전등록 §9). book_state 미접근, admission 미요청."
pkg$overall_verdict <- "PARTIAL__NEGATIVE_CONTROL_NOT_ESTABLISHED__P1_UNDERPOWERED_P2_FAIL_F1_CONFOUNDED"

write_json(pkg, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           digits = 8, na = "null")
cat(sprintf("발행: %s\n", file.path(MB, "alpha_package.json")))
v <- fromJSON(file.path(MB, "alpha_package.json"))
cat(sprintf("검증 재읽기 OK — top keys %d · overall = %s\n", length(names(v)), v$overall_verdict))
