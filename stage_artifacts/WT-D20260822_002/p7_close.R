## WT-D20260822_002 · P7 — 원장 갱신 (status / governance / FQ 큐 / L-code)
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p7_close.R")'

suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source("02_Infrastructure/config.R")
MBX <- "qepm/mailbox/worktask/WT-D20260822_002"
OUT <- "stage_artifacts/WT-D20260822_002"
NOW <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900")

cat("=== 1) status.json ===\n")
st <- list(task_id = "WT-D20260822_002", current_phase = "ALPHA_DONE", updated_at = NOW,
           blocker = NULL,
           verdict = "UNDERPOWERED_UNRESOLVED__selection_stat_not_a_lever",
           note = "co-primary 2건 모두 문턱 미달. (A) Pearson IC 선별 연 -0.60%p t -0.25 (절대 PORT_t 0.680 < 대조 0.947) · (B) 평균 스프레드 t 선별 연 +6.03%p t +1.57 (승계값 정확 복원, 이득은 KQ150 소급 투영 창 집중). FQ-233 부활조건 ① 미충족. risk-research 전이 없음.")
write_json(st, file.path(MBX, "status.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("  saved\n")

cat("\n=== 2) governance_log.json ===\n")
gl <- fromJSON(file.path(MBX, "governance_log.json"), simplifyVector = FALSE)
gl$events <- c(gl$events, list(
  list(timestamp = NOW, agent = "alpha-research", action = "PREREG_SEALED",
       summary = "stage_artifacts/WT-D20260822_002/PREREG.json 봉인 — arm 6종·co-primary 2건·K=5/W=36/top-25/15bps 고정·selection_type=chain·sweep 0. 완주 설계 4필드(terminal_form/alpha_bridge/transition_gates/consumption_gate_precheck) 포함."),
  list(timestamp = NOW, agent = "alpha-research", action = "ALPHA_DONE",
       summary = "FQ-237 재서열 판정: (A) SEL_PEARSON-SEL_RANK t -0.2533 (연 -0.60%p, CI [-5.27,+4.07]) · (B) SEL_MEANDEPTH-SEL_RANK t +1.5706 (연 +6.03%p, CI [-1.49,+13.55]) — 둘 다 UNDERPOWERED_UNRESOLVED(MDE 4.76/7.67%p > 사전문턱 3.0). 승계 재현 4/4. 반증 축1 미발화(Jaccard 0.25·rho 0.7675) · 축2 예측부호로 성립(t +6.29/+7.07). 위반주입 t +3.5731(검출력 실증). FQ-233 부활조건 ① 미충족."),
  list(timestamp = NOW, agent = "alpha-research", action = "SELF_ADVERSARIAL_DONE",
       summary = "challenge_note.md — concern 11건 (ACCEPT 6 / PARTIAL 4 / REBUTTAL 1). HIGH 2 (<5) 자동 escalate 미발화. Q-Lead 보고 4건: alpha-hypothesis 재설계 요청 2 · FQ-241 census 항목 추가 1 · 인프라 2(CF6 benchmark_id 하드코딩 · CF7 schema↔ast_verify escape 계약 위치 불일치) · 사전등록 템플릿 개선 제안 1."),
  list(timestamp = NOW, agent = "alpha-research", action = "NO_TRANSITION",
       summary = "transition_gates cond4(co-primary SUPPORTED >=1) 미충족 — risk-research 전이 요청하지 않는다. cond1 충족(alpha_scores 217,286행) · cond3 충족(반증 발화 0)."))
write_json(gl, file.path(MBX, "governance_log.json"), pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  events %d\n", length(gl$events)))

cat("\n=== 3) alpha_frontier_queue.json — FQ-237 갱신 (읽기→수정→쓰기→재읽기 확인) ===\n")
QP <- "06_Registry/alpha_frontier_queue.json"
q <- fromJSON(QP, simplifyVector = FALSE)
idx <- which(vapply(q$entries, function(e) identical(e$id, "FQ-237"), logical(1)))
stopifnot(length(idx) == 1L)
np <- c(
 "NP1 청정창(2015-07~, 133개월) 단독 사전등록 재판정 — (A)(B) 둘 다 청정창에서 음수 방향이라 '오염창 의존' 을 직접 시험할 수 있다. ★착수 전 133개월 MDE 를 먼저 잴 것(221개월에서 4.76~7.67%p 였으므로 더 넓어진다).",
 "NP2 병목이 한 마디 뒤로 이동 — 선별이 아니라 **결합 규칙** 교체. 근거: 평균-정합 선별이 합성 스코어의 Pearson IC 를 실제로 올렸는데(0.02201 t 3.18 -> 0.02536 t 3.77) top-25 전이는 오히려 하락(PORT_t 0.947 -> 0.680). ★ML 결합기 금지(v8.4 §6) — 폐형식 결합만.",
 "NP3 미검 교차 = '평균-정합 선별 x 브레드스 확대 소비' — WT-D20260821_002 는 소비만 바꿨고 본 라운드는 선별만 바꿨다.",
 "NP4 축소(shrinkage) 추정량 재서열 — (A) 점추정이 음수라 '정밀 코너' 서사와 어긋난다. 단일 사전등록값, 격자 금지.",
 "NP5 인프라 — canonical_screen_bt benchmark_id 하드코딩 제거 + schema<->ast_verify escape 계약 위치 통일(ALB-005 계통).")
q$entries[[idx]]$status <- "round_closed__selection_stat_not_a_lever__underpowered_scoped"
q$entries[[idx]]$owner <- paste0(q$entries[[idx]]$owner, " -> 2026-08-22 라운드 종료(WT-D20260822_002, alpha-research). 소유권 반납.")
q$entries[[idx]]$last_round <- "FQ237_RERANK_20260822"
q$entries[[idx]]$last_verdict <- "UNDERPOWERED_UNRESOLVED (co-primary 2/2) — 큰 레버는 배제, 작은 레버는 미결"
q$entries[[idx]]$last_closed_at <- NOW
q$entries[[idx]]$last_next_probe <- as.list(np)
q$entries[[idx]]$measured_facts_20260822 <- paste0(
 "[WT-D20260822_002 alpha-research 실측, metric_type=canonical_screen, n=221 홀딩월(2008-03~2026-07), 320팩터 풀, K=5, W=36, top-25 EW, 15bps] ",
 "(A) SEL_PEARSON - SEL_RANK paired NW3 t = -0.2533 (연 -0.603%p, 95% CI [-5.27, +4.07], MDE 4.764%p). ",
 "(B) SEL_MEANDEPTH - SEL_RANK t = +1.5706 (연 +6.027%p, CI [-1.49, +13.55], MDE 7.674%p) — WT-D20260813_005 값 정확 복원(Δ 4e-6). ",
 "절대 cap-w PORT_t: 대조 0.9474 / Pearson 0.6803 / meandepth 1.7775 (승계 재현 4/4, 최대 Δ 2.4e-5). ",
 "★1급 결과 = 개입은 표적 통계량을 실제로 개선했으나 전이는 안 됐다: 합성 스코어 Pearson IC 대조 0.02201(t 3.18) -> Pearson 선별 0.02536(t 3.77) 인데 PORT_t 는 0.947 -> 0.680. ",
 "⇒ IC->PORT_t 전이 벽은 '어느 IC 를 쓰느냐' 에 있지 않다(병목이 결합·소비 마디로 이동). ",
 "반증 축1 미발화(rank vs Pearson 선별 서열 rho 중앙 0.7675 · top-5 Jaccard 중앙 0.25 — 집합은 진짜로 갈린다). ",
 "반증 축2 예측부호(+)로 성립(gap ~ 왜도 b +0.0040 t_NW3 +6.29 / +0.0039 t +7.07) — 단 추정기 2종이 collinear +0.951(승계 주장 -0.011 과 불일치, 증거 1개로 세야 함). ",
 "위반주입(1개월 누출) t +3.5731 = 검출력 실증 · PIT 스트레스 LAG1 t +0.2800 · 음성대조 meddepth t -1.6211. ",
 "★★(B) 의 이득은 KQ150 소급 투영 창에 집중: 2010-02~2015-06 t +3.50(연 +29.06%p) vs 2015-07~ t -0.53(연 -1.87%p). era 교락과 분리 불가 -> 라벨 universe_backfill_inherited. |d| 상위 5개월 제외 시 t 1.5706 -> 0.7631. ",
 "3-basis: PORT_t IKS200 / parent cap-w / EW-유니버스 = 대조 0.947/1.491/2.088 · Pearson 0.680/1.106/1.915 · meandepth 1.777/2.176/2.973. 벤치 연복리 IKS200 8.947% vs parent 7.812%. ",
 "★paired 판정은 basis 불변(Δt ~ 1e-17) — 판정이 벤치 논쟁과 독립. ",
 "R1 유동성 2e8 적용판: 탈락 1.9%, paired (A) t -0.073 · (B) t +1.681 (결론 불변).")
q$entries[[idx]]$result_ref <- "qepm/mailbox/worktask/WT-D20260822_002/{alpha_package.json, challenge_note.md} + stage_artifacts/WT-D20260822_002/{PREREG.json, alpha_validation.json, alpha_scores.parquet}"
## FQ-233 부활조건 ① 판정 기록
jdx <- which(vapply(q$entries, function(e) identical(e$id, "FQ-233"), logical(1)))
if (length(jdx) == 1L)
  q$entries[[jdx]]$revival_condition_1_status <- paste0(
    "미충족 (2026-08-22, WT-D20260822_002). '평균-정합 선별 통계량 재서열에서 전이 양성' 관문을 사전등록으로 시험했고 ",
    "co-primary 2건 모두 t < +2.0 (Pearson -0.2533 · 평균스프레드 +1.5706). 관문은 열리지 않았다 — ",
    "분포-표적 자본화 경로는 INV-7 대로 닫힌 상태 유지. 부활조건 ②(rank 1-25 역-소비 사전등록)는 미착수로 잔존.")
q$updated <- format(Sys.Date(), "%Y%m%d")
write_json(q, QP, pretty = TRUE, auto_unbox = TRUE)
q2 <- fromJSON(QP, simplifyVector = FALSE)          # ★재읽기 확인 (consume_rule ③)
i2 <- which(vapply(q2$entries, function(e) identical(e$id, "FQ-237"), logical(1)))
cat(sprintf("  FQ-237 status=%s · next_probe %d건 · FQ-233 revival1 기록=%s\n",
            q2$entries[[i2]]$status, length(q2$entries[[i2]]$last_next_probe),
            !is.null(q2$entries[[which(vapply(q2$entries, function(e) identical(e$id,"FQ-233"), logical(1)))]]$revival_condition_1_status)))

cat("\n=== 4) L-code 적립 ===\n")
source("02_Infrastructure/axiom/lcode_emit.R")
res <- emit_lcode(
  mode = "qepm", strategy_id = "FQ237_RERANK_WT-D20260822_002", grade = "C",
  metric_type = "canonical_screen", construction_type = "selection_objective_replacement",
  family = "measurement_form", selection_type = "chain", record_type = "paired_experiment",
  lesson_text = paste0(
    "선별 목적함수를 rank-IC(Spearman)에서 평균-정합 통계량으로 바꿔도 long-only top-25 실현 전이는 개선되지 않는다. ",
    "n=221 홀딩월·320팩터 풀·K=5·W=36·15bps 에서 paired NW3 t = -0.2533(Pearson IC 선별, 연 -0.603%p) / +1.5706(top-25 평균 스프레드 t 선별, 연 +6.027%p), ",
    "둘 다 사전등록 문턱 ±2.0 미달이며 MDE(4.76/7.67%p)가 관심효과(3.0%p)를 넘어 라벨은 UNDERPOWERED_UNRESOLVED — ",
    "다만 (A)는 연 +4.07%p 이상 효과를 95%로 배제하므로 '큰 레버' 주장은 실측 배제됐다. ",
    "★핵심 = 개입이 표적 통계량을 실제로 개선했는데 전이가 안 됐다: 합성 스코어의 Pearson IC 가 0.02201(t 3.18)->0.02536(t 3.77)로 올랐는데 cap-w PORT_t 는 0.947->0.680 으로 내렸다. ",
    "IC->PORT_t 전이 벽은 '어느 IC 를 쓰느냐'에 있지 않고 그 뒤 마디(결합·이산 top-N 소비)에 있다. ",
    "부수 1: 선별 집합은 진짜로 갈린다(rank vs Pearson 서열 rho 중앙 0.7675, top-5 Jaccard 중앙 0.25) — null 이 '같은 집합' 탓이 아니다. ",
    "부수 2: (Pearson-Spearman) 격차는 횡단면 왜도와 강한 양의 연속 상호작용(t +6.29/+7.07) — 기전 전제는 성립하나 성과로 이어지지 않는다. ",
    "부수 3: 승계 조건부보류(WT-D20260813_005 t +1.57)의 이득이 KQ150 소급 투영 창(2010-02~2015-06 t +3.50, 연 +29.06%p)에 집중되고 청정창(2015-07~)에서는 t -0.53 — era 교락과 분리 불가하여 universe_backfill_inherited 까지만 라벨. ",
    "부수 4: paired 설계는 벤치 basis 에 불변(Δt ~1e-17)이나 절대 PORT_t 는 크게 종속(IKS200 1.777 / parent cap-w 2.176 / EW 2.973)."),
  mechanism_hypothesis = paste0(
    "선별층 기전 = 파이프라인이 trailing Spearman rank-IC 로 고르고 top-N 평균으로 소비하는 함수형 불일치. ",
    "본 라운드가 그 불일치를 직접 제거(소비함수와 같은 함수족으로 선별)했으나 전이 미개선 ⇒ 기전은 실재하나(격차-왜도 상호작용 t>6) 그것이 top-N 전이의 구속 마디는 아니다."),
  falsification_attempts = list(
    list(test = "반증 축1 — rank-IC 서열 vs Pearson 서열이 사실상 같은 집합을 고르는가(rho>=0.90 or Jaccard>=0.80)",
         result = "survived", effect_retained = "rho 중앙 0.7675 · Jaccard 중앙 0.2500 — 미발화(집합 분기 확인)"),
    list(test = "반증 축2 — (Pearson-Spearman) 격차가 횡단면 왜도와 무관한가(|t|<2.0 이면 비대칭-기원 기각)",
         result = "survived", effect_retained = "b +0.0040 t_NW3 +6.29 (월간CS) / +0.0039 t +7.07 (일간파생) — 예측 부호로 성립"),
    list(test = "위반 주입 — 선별 창에 홀딩월 자신을 넣으면 검출되는가(검출력 양성 대조)",
         result = "survived", effect_retained = "paired t +3.5731 (문턱 2.0 초과) — 장치 정상"),
    list(test = "PIT 스트레스 — 창을 한 칸 더 물리면 붕괴하는가(동월 누출 징후)",
         result = "survived", effect_retained = "LAG1 t +0.2800, base 대비 붕괴 없음"),
    list(test = "앵커 프레임 위반 주입 — 팩터를 자기 달 월초로 스탬프하면 지문이 발화하는가",
         result = "survived", effect_retained = "M04_Mom_1 -0.9423 재현(문서화 지문과 소수 4자리 일치) · 정상 프레임 0/13"),
    list(test = "유동성 하한 2e8 적용 시 결론이 뒤집히는가",
         result = "survived", effect_retained = "탈락 1.9% · paired (A) -0.073 / (B) +1.681 — 불변")),
  portfolio_alpha_t = 0.68033605, oos_retention = NULL, oos_months = 221L,
  core_reference = "qepm/mailbox/worktask/WT-D20260822_002/alpha_package.json",
  tags = c("FQ-237","FQ-233-revival-1","selection_objective","pearson_ic","transition_wall",
           "universe_backfill_inherited","chain","canonical_screen"),
  metrics = list(n_holding_months = 221L, n_factor_pool = 320L, K = 5L, W = 36L, top_n = 25L,
                 paired_t_A = -0.2533, paired_t_B = 1.5706, mde_A_annual_pct = 4.7639,
                 mde_B_annual_pct = 7.6744, port_t_control = 0.9474, port_t_pearson = 0.6803,
                 port_t_meandepth = 1.7775, injection_t = 3.5731, reproduction_passed = "4/4"))
cat(sprintf("  L-code: %s\n", res$l_code %||% "(emit 반환 확인)"))
str(res, max.level = 1)
