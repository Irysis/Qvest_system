## WT-D20260809_003 P5 — 원장 환류 + close_round
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
say("원장 read: 항목 %d", length(Q$entries))

i <- which(ids == "FQ-166")
Q$entries[[i]]$status <- "shape_heterogeneity_established_20260809"
Q$entries[[i]]$owner  <- "Q-Lead session 2026-08-09 (WT-D20260809_003 수행)"
Q$entries[[i]]$next_action <- paste0(
  "★E1 발화 = **HETEROGENEOUS_WALL 확립**. 동일-행 프레임(69,282행·282개월·decile·유동성필터)에서 5 arm 이 3형태로 갈림: ",
  "MONOTONE_TOP = M26(sp +0.879, D10 +6.82%) · M01_PATHQ(+0.770, D10 +10.47%) / ",
  "HUMP = Q01_EB(+0.188, argmax D8, top −3.41%) · Q01_neutral(+0.127, argmax D5) / ",
  "상단-역전형 = D03_EWMA(sp **−0.685**, argmax D3, top −5.12%). ",
  "★★E3 **미발화(중요한 음성)** — Q01 raw 와 중립판이 **둘 다 HUMP** ⇒ WT-003 의 혹은 중립화 산물이 아니라 **Q01 자체 성질**. 중립화 귀속 서술 금지. ",
  "★★★부수 확립 = **rank-IC ↔ 평균 프로파일 구조적 괴리 기전**. D03 은 rank-IC +0.0322(t +3.00, 5재료 중 최강)인데 decile 평균은 하향. ",
  "부호 규약 아님(P2 로 확인). 기전: 중앙값 프로파일 **+0.503**(평균 −0.685와 반대) · (평균−중앙값) 격차 spearman **−0.988** · 왜도 −0.842 · sd D1 0.1838 vs D10 0.0784(2.34배). ",
  "저변동 이상현상이 **중앙값·순위에선 성립**(D10 중앙값 +1.65 vs D1 −11.25)하나 **평균에선 역전**(D10 +8.25 vs D1 +11.84) — 고변동 우편향이 평균을 들어올린다. top-25 EW 는 평균을 벌므로 PORT_t −1.73. ",
  "★인계 큐가 '검증 전'이라 못박은 기전 후보는 **살아 있었다 — 재료를 M26 에 잘못 붙였을 뿐**(M26 에선 기각, D03 에선 지지). ",
  "⚠한정: E4(시대 조건부)는 post2015 검정력과 미분리 · 형태 class 는 해상도 민감(인용 시 해상도·창 병기 의무) · 형태→소비면 대응은 **가설**(미측정).")
Q$entries[[i]]$result_ref <- "stage_artifacts/WT_D20260809_003/alpha_validation.json (+ challenge_note.md)"

new <- list(
  list(id = "FQ-167", lane = "measurement_integrity",
    title = "rank-IC 왜도-취약성 전수 — vol/tail 계열 8종에서 평균/순위 괴리 스크린",
    hypothesis = paste0(
      "WT-D20260809_003 이 D03_EWMA 단독에서 rank-IC(+3.00)와 decile 평균(−0.685) 의 구조적 괴리를 기전과 함께 확립했다. ",
      "기전이 '신호 x 수익왜도 상관' 이라면 vol/tail 계열 전반에 같은 취약성이 있어야 한다. ",
      "vol/tail 8종(FQ-108d 대상)에 대해 spearman(dec,mean) vs spearman(dec,median) 부호 일치를 전수 스크린한다."),
    ev_rationale = "저비용(동일 패널·동일 코드). 결과가 계열-wide 면 rank-IC 기반 재료 자격 판정의 적용 경계를 실측으로 그을 수 있다 — measurement-graduation §2 의 ADVISORY 강등에 기전 근거가 붙는다.",
    wall_check = "진단 라운드 — 자본 주장 없음. ★1건 관측을 계열 전체로 일반화하지 않기 위한 라운드이므로, 결과가 D03 단독이면 그 자체가 판정(일반화 금지 확립)이다.",
    data_gate = "없음",
    owner = "미배정 (WT-D20260809_003 NP-1 · challenge_note W-5)",
    status = "frontier_open",
    next_action = "①vol/tail 8종 decile 평균·중앙값 프로파일 산출 ②부호 갈림 여부 표 ③갈리는 재료의 왜도·sd 프로파일 대조 ④갈리는 재료 목록을 factor_registry 라벨로 노출 제안"),
  list(id = "FQ-168", lane = "consumption_surface",
    title = "형태별 소비면 대응의 실측 — HUMP 재료의 중간분위 소비가 실제로 작동하는가",
    hypothesis = paste0(
      "WT-D20260809_003 이 형태 3종을 확립했고 형태→소비면 대응(MONOTONE_TOP=상단 랭킹 / HUMP=중간분위·상단절단 / 상단-역전형=랭킹 역효과)을 제안했다. ",
      "그러나 **각 형태에서 실제 소비면 성과를 잰 적이 없다** — 대응은 현재 가설이다. ",
      "Q01_EB(HUMP, argmax D8) 에서 '상단 절단' 형태(D8~D9 선별)가 top-25 대비 cap-w PORT_t 를 개선하는지 직접 검정한다."),
    ev_rationale = "형태 진단을 라운드 1번 절차로 제도화하려면 대응이 실측으로 뒷받침돼야 한다. 안 그러면 그럴듯한 분류학만 남는다.",
    wall_check = "max 25 · long-only · [0,0.20] · Σw=1 · 유동성 2e8 불변. 분위 선택은 sweep 이므로 챔피언 선택 시 DSR HARD 적용. ★착수 전 required_effect 바 산출 의무 — 분위 선택은 표본을 쪼개므로 검정력이 급감한다.",
    data_gate = "없음 (merged_panel.rds 재사용)",
    owner = "미배정 (WT-D20260809_003 NP-2 · challenge_note W-4)",
    status = "frontier_open",
    next_action = "①착수 전 검정력 바 산출, 미달이면 형태 폐기 ②Q01 D8~D9 선별 vs top-25 paired NW3 ③M26(MONOTONE_TOP) 음성 대조 ④해상도 불변성 확인"))
for (e in new) { if (e$id %in% ids) { say("★%s 존재 — 생략", e$id); next }
  Q$entries[[length(Q$entries) + 1L]] <- e; say("  %s 신규 등재", e$id) }
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("원장 기록 완료 — 항목 %d", length(read_frontier_queue()$entries))

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "WT-D20260809_003",
  verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "동일-행 프레임에서 5재료가 3형태로 갈린다 — 전이 벽은 단일 현상이 아니다. ",
    "핵심 기전은 통계 선택에 있다: rank-IC 는 수익 **순위**를 써서 이상치에 둔감하고 PORT_t·decile 평균은 **원수익**을 써서 꼬리에 지배된다. ",
    "신호가 수익 왜도와 상관되면 둘이 구조적으로 갈리며, D03_EWMA 가 그 실례다 — 저변동 이상현상이 중앙값·순위에선 성립(D10 +1.65 vs D1 −11.25)하나 ",
    "평균에선 역전(D10 +8.25 vs D1 +11.84)한다. 고변동 종목의 우편향이 평균을 들어올리기 때문이며, top-25 EW 는 평균을 벌므로 rank-IC +3.00 이 PORT_t −1.73 으로 뒤집힌다. ",
    "Q01 의 혹은 중립화 산물이 아니라 재료 자체 성질이다(raw·중립판 둘 다 HUMP)."),
  next_probes = c(
    "FQ-167 rank-IC 왜도-취약성 전수 — vol/tail 8종에서 평균/순위 부호 일치 스크린. D03 단독이면 '일반화 금지' 확립 자체가 판정.",
    "FQ-168 형태별 소비면 대응 실측 — Q01(HUMP)의 상단절단(D8~D9)이 top-25 대비 개선하는지. 대응은 현재 가설이며 미측정.",
    "형태 규칙의 해상도-불변 재설계 — 현 규칙(argmax 위치+spearman 문턱)이 5분위/10분위에서 class 를 바꾼다. 상단 k% 초과의 연속 함수형으로.",
    "E4 검정력 분리 — post2015 class 변화가 형태 변화인지 표본 부족인지. 분위 수를 줄여 검정력을 맞춘 재측정.",
    "프레임 통일 대가 측정 — 동일-행 조인이 W1 의 20.3%를 떨어뜨렸다. 유니버스 축을 따로 통제해 WT-003 원값과의 차이를 귀속."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 형태가 랭킹 적합성을 결정. 상단-역전형(D03)은 랭킹 자체가 역효과",
    "②유니버스 필터 — HUMP 재료는 상단 절단 형태가 후보(FQ-168 에서 실측)",
    "③오버레이 — 미측정",
    "④위험모델 — D03 왜도 프로파일은 tail 채널 입력 후보(FQ-108c 인접)",
    "⑤monitoring — 평균/순위 괴리를 상시 지표로 노출하는 안(FQ-167 산출물)",
    "⑥선별 라벨 — 형태 class 를 factor_registry 라벨로 노출 제안",
    "⑦타 모드 — RAMP/FR 의 성분 선별에 형태 사전진단 이식"),
  frontier_update = "FQ-166 status=shape_heterogeneity_established_20260809 · FQ-167/168 신규 등재",
  live_trigger = paste0(
    "형태 분류를 규약으로 제도화하는 조건: ①FQ-168 에서 형태→소비면 대응이 최소 1건 실측 지지 ",
    "②형태 통계가 해상도-불변으로 재설계 ③FQ-167 에서 적용 경계(어느 계열에 위험한가) 확정. ",
    "그 전까지 형태는 **진단 어휘**이지 게이트가 아니다."),
  layer = "④construction/전이 + 측정무결성",
  evidence_refs = c(
    "stage_artifacts/WT_D20260809_003/alpha_validation.json",
    "stage_artifacts/WT_D20260809_003/challenge_note.md",
    "stage_artifacts/WT_D20260809_003/p1_shape_summary.csv",
    "stage_artifacts/WT_D20260809_003/p3_decile_detail.csv",
    "stage_artifacts/WT_D20260809_001/alpha_validation.json"))
say("=== P5 완료 ===")
