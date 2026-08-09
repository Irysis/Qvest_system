## WT-D20260809_001 P6 — 원장 환류 (frontier queue) + close_round
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p6] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
say("원장 read: 항목 %d", length(Q$entries))
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))

put <- function(id, fields) {
  i <- which(ids == id)
  if (!length(i)) { say("★%s 부재 — 건너뜀", id); return(invisible()) }
  for (k in names(fields)) Q$entries[[i]][[k]] <<- fields[[k]]
  say("  %s 갱신: %s", id, paste(names(fields), collapse = ", "))
}

## ── FQ-161: 전이 채널 분해 결과 반영 ────────────────────────────────────────
put("FQ-161", list(
  status = "transition_channels_decomposed_20260809",
  owner = "Q-Lead session 2026-08-09 (WT-D20260809_001 채널 분해 수행)",
  next_action = paste0(
    "WT-D20260809_001 판정 = D4_CHANNEL_UNIDENTIFIED (사전등록 3채널 단독 미발화) + **가법 분해 확정**. ",
    "사다리(cap-w·top25·283m): net 1.5441 → 비용제거 2.0407(+0.497) → EW-basis 2.8180(+0.777) [참조 rank-IC t 2.971]. ",
    "★신호는 전이된다 — 갭 대부분이 거래비용·벤치핸디캡 두 비-신호 채널로 회계된다. 단 둘 다 제거해도 2.818<2.95 라 '비용·벤치만 없으면 졸업'은 아님. ",
    "★CH-B(꼬리) 반증: decile 단조성 spearman +0.879(무필터 +0.964) · D10 연초과 +6.550%(t +2.822) · long_side_share 0.553. ",
    "인계 큐가 '검증 전'이라 표시한 기전 후보('rank-IC 가 고변동 꼬리 왜도를 못 봄')는 지지되지 않음. ",
    "★CH-C(breadth) 반증: PORT_t(50)−PORT_t(25) = +0.147. ",
    "★비용 레버 검정: staleness K∈{2,3,6} 전 위상 11셀 paired NW3 최대 |t| 0.858 — 전건 INCONCLUSIVE_UNDERPOWERED(필요 연 3.01~5.55% vs 관측 −2.70~2.00%). ",
    "회전율 11.74→3.73/yr(−68%)에서 비용절감 1.20%p 와 gross 손실 1.17%p 가 상쇄 — 보유기간은 공짜 레버 아님. ",
    "다음: ②필터면은 **여전히 유효 후보**(꼬리가 살아 있으므로) 이나 착수 전 M26 고유 diff sd 로 power 재계산 의무 유지. ",
    "우선순위는 ⑥선별라벨/composite(FQ-164) — D10 gross 실재를 book-marginal 로 옮기는 축."),
  result_ref = "stage_artifacts/WT_D20260809_001/alpha_validation.json (+ challenge_note.md)"
))

## ── FQ-090: 전이 레버 격리 — 본 라운드가 직접 응답 ──────────────────────────
put("FQ-090", list(
  status = "measured_turnover_lever_inconclusive_20260809",
  owner = "Q-Lead session 2026-08-09 (WT-D20260809_001 이 M26 위에서 격리 측정)",
  next_action = paste0(
    "★FQ-090 원 질문('회전율이 신호력과 독립적으로 PORT_t 를 움직이는가')에 M26 위에서 직접 응답: ",
    "동일 신호를 고정한 채 보유기간만 조작(점수 staleness K∈{1,2,3,6}, PIT 안전 — 오래된 정보만 사용). ",
    "회전율 11.74 → 9.17 → 6.62 → 3.73/yr 로 −68% 이동했으나 **paired NW3 차이는 11셀 전부 비유의**(최대 t 0.858). ",
    "기전: 비용 절감(1.76→0.56%p)과 gross 알파 손실(7.62→6.45%)이 거의 1:1 상쇄. ",
    "★★부수 확립 = **리밸 위상 추첨**. K=6 위상 6개 PORT_t 스프레드 1.291(0.841~2.133) · K=2 스프레드 0.816 · K=3 스프레드 0.141. ",
    "단일 위상 측정은 그만큼의 추첨 성분을 포함한다 — 단 K=1(월간 리밸)은 위상 자유도가 없으므로 **현행 월간 측정에는 비적용**(범위 제한 준수). ",
    "next_probe: ①부분-리밸 연산자(점수는 fresh, 교체 상한만 부과 — staleness 와 다른 축이라 비대칭 교환 가능) ②위상 스프레드의 분기-이상 주기 sleeve census."),
  result_ref = "stage_artifacts/WT_D20260809_001/alpha_validation.json §P2~P5"
))

## ── 신규 등재 ───────────────────────────────────────────────────────────────
newe <- list(
  list(
    id = "FQ-164", lane = "transition_wall",
    title = "부분-리밸 연산자 — 점수는 fresh 유지, 교체 상한만 부과 (staleness 와 직교하는 회전율 축)",
    hypothesis = paste0(
      "WT-D20260809_001 이 staleness(점수를 늙히는 축)에서 비용절감과 신호감쇠가 1:1 상쇄됨을 실측했다. ",
      "부분-리밸은 다른 축이다: 매월 fresh 점수로 재평가하되 **하위 k 개만 교체**(교체 상한 c). ",
      "상위 신선도는 보존한 채 경계 churn 만 잘라내므로 교환이 비대칭일 수 있다."),
    ev_rationale = "비용 채널이 회계로 확정됨(0.497 t · 연 1.76%p). staleness 축은 소진에 가깝고 이 축은 미측정. 저비용(기존 하네스 파라미터).",
    wall_check = "max 25 · long-only · [0,0.20] · Σw=1 · 유동성 2e8 불변 — 제약 조건 안 구성 축. 회전율 절감 주장은 |Δ보유명목|×15bps 실과금 기준. c grid 는 sweep 이므로 챔피언 선택 시 DSR HARD 적용.",
    data_gate = "없음 (동일 패널 재사용)",
    owner = "미배정 (WT-D20260809_001 NP-1)",
    status = "frontier_open",
    next_action = "①교체상한 c∈{3,5,10,25} paired A/B ②위상 자유도 없음(매월 재평가) 확인 ③paired NW3 로 차이 직접 검정 — 필요 효과 연 3.0~5.5% 바 선산출"
  ),
  list(
    id = "FQ-165", lane = "consumption_surface",
    title = "M26 소비면 ⑥ — D10 gross 실재를 book-marginal 로 옮기는 composite/선별라벨 축",
    hypothesis = paste0(
      "M26 D10(상위 decile ~24종) 연초과 +6.550%(t_NW3 +2.822, 283개월, gross)가 실재하고 순위-수익이 단조(+0.879)다. ",
      "standalone top-25 랭킹은 cap-w PORT_t 1.544 로 미달이나, book 기존 팩터와의 **결합**에서 book-marginal ΔIR 이 양일 수 있다 ",
      "— 기존 컨센서스 3종 대비 max spearman 0.215 로 재탕이 아니기 때문."),
    ev_rationale = "MAX5 선례(랭킹 −1.616 死 / 필터 ΔIR +0.169 生)가 '소비 경로가 판정을 바꾼다'를 실증. M26 은 재료 자격·단조성·PIT 강건성이 모두 확립된 상태라 결합 측정의 사전확률이 높다.",
    wall_check = "book-marginal ΔIR ≥ 0.05 (measurement-graduation §4). ★base 는 05_Production 현행 PG2 코드 파생만 권위(§7b) — 저장 패널 재사용 금지. base 강도가 판정을 뒤집은 실측 선례 있음.",
    data_gate = "없음",
    owner = "미배정 (WT-D20260809_001 NP-2 · FQ-161 소비면 ⑥)",
    status = "frontier_open",
    next_action = "①production PG2 base 재산출(parity 라벨) ②M26 성분 추가 book-marginal ΔIR ③|cor|<0.30 확인 ④착수 전 power 바 산출"
  ),
  list(
    id = "FQ-166", lane = "transition_wall",
    title = "전이 벽 채널 사다리의 일반화 — D03_EWMA · Q01_EB 에 동일 분해 적용",
    hypothesis = paste0(
      "M26 은 '신호는 전이되나 비용+벤치가 먹는' 구조였다(net 1.544 → gross 2.041 → EW 2.818). ",
      "그러나 같은 날 죽은 D03_EWMA(rank-IC Harvey-t +3.50 → PORT_t **−1.73**)·Q01_EB(IC t +2.21 → PORT_t −0.21)는 ",
      "PORT_t 가 **음수**라 같은 구조일 수 없다. 동일 사다리를 적용하면 전이 벽이 단일 현상인지 이질적 집합인지 판별된다."),
    ev_rationale = "병목 지도의 갭 귀속(잔여 갭 = ①재료)과 '3재료가 전부 ④에서 죽었다'는 관측 사이의 긴장을 해소하는 축. 세 재료 모두 패널이 이미 존재해 저비용.",
    wall_check = "진단 라운드 — 자본 주장 없음. 사다리 각 단은 canonical_screen_bt 계약 경유(반사실 0bps 는 counterfactual_diag 라벨 의무).",
    data_gate = "없음 (WT-D20260808_001/003 패널 재사용)",
    owner = "미배정 (WT-D20260809_001 NP-3)",
    status = "frontier_open",
    next_action = "①D03·Q01 에 net→gross→EW-basis 사다리 적용 ②M26 과 성분 크기 대조 ③음수 PORT_t 가 사다리 어느 단에서도 회복 안 되면 '이질적 벽' 확립 → 병목 지도 갭 귀속 재판정"
  )
)
for (e in newe) {
  if (e$id %in% ids) { say("★%s 이미 존재 — 등재 생략", e$id); next }
  Q$entries[[length(Q$entries) + 1L]] <- e
  say("  %s 신규 등재", e$id)
}
Q$updated <- "2026-08-09"

write_frontier_queue(Q)
say("원장 기록 완료 — 항목 %d", length(read_frontier_queue()$entries))

## ── close_round ─────────────────────────────────────────────────────────────
source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "WT-D20260809_001",
  verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "M26 의 IC→PORT_t 갭은 단일 채널이 아니라 가법 분해된다: 거래비용 +0.497 t(회계 검증 — turnover 11.74×15bps=연 1.76%p) ",
    "+ 벤치-측 핸디캡 +0.777 t. 신호 자체는 전이된다(decile 단조성 +0.879, D10 연초과 +6.550% t +2.822) — ",
    "따라서 '재료가 전이에서 죽는다'는 프레이밍이 M26 에는 맞지 않다. 다만 둘을 모두 제거한 2.818 도 HARD 2.95 미달이라 ",
    "비-신호 채널만으로 졸업이 설명되지도 않는다. 제약 조건 안 유일 레버인 보유기간은 비용절감과 신호감쇠를 1:1 교환해 순효과가 검출되지 않았다."),
  next_probes = c(
    "FQ-164 부분-리밸 연산자 — 점수는 fresh 유지하고 교체 상한 c 만 부과. staleness 와 직교하는 회전율 축이라 비대칭 교환 가능성이 남아 있다.",
    "FQ-165 소비면 ⑥ composite/선별라벨 — D10 gross +6.550%(t 2.822) 실재를 production PG2 base 위 book-marginal ΔIR 로 옮긴다.",
    "FQ-166 사다리 일반화 — D03_EWMA(PORT_t −1.73)·Q01_EB(−0.21)에 동일 분해 적용해 전이 벽이 단일 현상인지 판별.",
    "리밸 위상 스프레드의 범위 확정 — 분기 이상 주기를 쓰는 현행 sleeve census 후 위상 폭 측정(월간 리밸엔 비적용, 범위 제한 준수).",
    "lag1_retention 0.233 과 staleness gross 손실 −15%(K=1→6) 의 화해 — 두 추정량 차이를 직접 측정(현재는 이야기 수준)."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 측정 완료. cap-w PORT_t 1.544, HARD 미달(변동 없음)",
    "②유니버스 필터 — CH-B 단조성 확립으로 **여전히 유효 후보**. 착수 전 M26 고유 diff sd 로 power 재계산 의무 유지",
    "③오버레이/국면 입력 — 미측정",
    "④위험모델 — 미측정",
    "⑤monitoring — 미측정",
    "⑥선별 라벨/composite — FQ-165 로 승격(최우선)",
    "⑦타 모드(RAMP/FR) 이식 — 미측정"),
  frontier_update = "FQ-161 status=transition_channels_decomposed_20260809 · FQ-090 status=measured_turnover_lever_inconclusive_20260809 · FQ-164/165/166 신규 등재",
  live_trigger = paste0(
    "M26 standalone 자본 경로 부활 조건(경로-scoped): ①essence_score 권위 측정에서 oos_retention ≥ 0.5 ",
    "②벤치 핸디캡 감시(bench_handicap_watch)가 NORMALIZED 전환 ③FQ-164 부분-리밸에서 paired NW3 t ≥ 2.0 ",
    "— 셋 중 어느 것이든 발화하면 재측정한다. 본 라운드는 자격 판결이 아니다."),
  layer = "④construction/전이",
  evidence_refs = c(
    "stage_artifacts/WT_D20260809_001/alpha_validation.json",
    "stage_artifacts/WT_D20260809_001/challenge_note.md",
    "stage_artifacts/WT_D20260809_001/p1_arms.csv",
    "stage_artifacts/WT_D20260809_001/p4_k_curve_phase_averaged.csv",
    "stage_artifacts/WT_D20260809_001/p5_paired.csv",
    "stage_artifacts/WT_D20260808_002/alpha_validation.json")
)
say("=== P6 완료 ===")
