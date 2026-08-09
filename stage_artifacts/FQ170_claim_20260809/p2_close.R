#!/usr/bin/env Rscript
# p2_close.R — FQ-170 결과 등재 + 텔레그램
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/FQ170_claim_20260809")

source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-170"); stopifnot(length(i) == 1)
Q$entries[[i]]$status <- "shape_conditional_consumption_confirmed_20260809"
Q$entries[[i]]$result <- paste0(
  "측정 완료 2026-08-09 (Q-Lead ba4a1c30, metric_type=canonical_screen_diag·gross·capital_claim=false). ",
  "사전등록 관문 4/4 통과 — **형태→소비면 대응이 가설에서 실측 확립으로 승격**. ",
  "①검정력: paired sd 3.050%/m → 필요 연 4.36%p < ex-ante 기대 5.46%p(FQ-166 기공개 분위 프로파일) PROCEED. ",
  "②주검정(Q01_EB=HUMP): top-25 연초과 **-2.60%** vs D8~D9 선별 **+3.02%** — diff +5.62%p/yr, t_NW3 +2.570. ",
  "상단절단이 음수를 양수로 뒤집는다. ",
  "③음성 대조(M26=MONOTONE_TOP): 같은 처치가 **-4.14%p/yr(t -1.95)** 로 해로움 — 형태-조건부성 확인",
  "(모든 재료에 이로운 처치가 아니라 HUMP 에만 이로움 = 대응의 핵심 검증). ",
  "④해상도: quintile Q4(60~80분위) 판본 +4.30%p/yr(t +1.63) 부호 일치 — 결론이 분위 해상도에 강건. ",
  "프레임 = WT-003 1급(유동성 adv>=2e8·전표본 282m·EW-유니버스 gross) 그대로 재사용."
)
Q$entries[[i]]$next_action <- paste0(
  "[NP-1] cap-w/net 전이 검증 — gross EW-유니버스 확립을 배포 프레임(cap-w·비용·top-25 슬롯)으로: ",
  "D8~D9 는 ~56종이라 25종 제약과 충돌 — 'D8~D9 내 상위 25' 재선별의 cap-w PORT_t 실측이 자본 경로 관문. ",
  "[NP-2] HUMP 계열 일반화 — Q01 1건 확립. 타 HUMP 재료(Q01_neutral 포함)와 신규 HUMP 판정 재료에 동일 A/B ",
  "(FQ-169 의 '1건 계열 일반화 금지' 규약 정합). ",
  "[NP-3] 상단-역전형(D03) 소비면 — INVERTED 형태의 대응(하위 절단? 역방향?)은 미측정 별도 셀."
)
res <- write_frontier_queue(Q)
cat("[fq170] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
CH <- file.path(OUT, "charts"); dir.create(CH, showWarnings=FALSE, recursive=TRUE)
p1 <- tg_chart_sweep(
  labels = c("혹형: 상위 25종 (관행)", "혹형: 중상단 선별 (형태 맞춤)",
             "단조형: 상위 25종 (관행)", "단조형: 중상단 선별 (잘못 적용)"),
  values = c(-2.60, 3.02, 6.56, 2.42),
  out_dir = CH, title = "형태를 보고 고르는 곳을 바꾸면 부호가 뒤집힌다",
  value_label = "연 초과수익 (%, 유니버스 대비)", hline = 0,
  highlight = "혹형: 중상단 선별 (형태 맞춤)", filename = "fq170_shape.png")
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "형태 맞춤 선별 확립 — 혹형 신호는 꼭대기가 아니라 중상단에서 벌린다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "분위 형태가 혹 모양인 신호는 상위 대신 중상단을 고르면 연 -2.6%가 +3.0%로 뒤집힙니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "배경: 신호마다 '점수 대 수익' 곡선 모양이 다르다는 게 어제 확립됐습니다",
           "검증: 혹 모양 신호에서 꼭대기 대신 중상단(70~90분위)을 골라봤습니다",
           "결과: 연 +5.6%p 개선, t값 2.57 — 사전 검정력 관문도 통과했습니다",
           "대조: 단조 모양 신호에 같은 처치를 하면 오히려 연 -4.1%p 손해입니다",
           "의미: '어디를 고를지'가 신호 형태에 달렸다는 대응 규칙이 확립됐습니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "혹형개선" = "상위25 -2.60% → 중상단 +3.02% (연, t값 2.57)",
           "음성대조" = "단조형은 같은 처치가 -4.14%p (기대대로 해로움)",
           "해상도"   = "5분위 판본도 +4.30%p 부호 일치",
           "검정력"   = "필요 4.36%p < 기대 5.46%p (착수 전 통과)",
           "한계"     = "총수익 기준 진단 — 자본 자격 아님")),
    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "비용·시가총액가중·25종 제약 반영 전 진단입니다",
           "중상단 선별은 약 56종이라 25종 제약과 충돌 — 재선별 검증이 다음 관문",
           "혹형 1개 재료 확립 — 계열 일반화는 별도 검증 대상입니다")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "배포 프레임(시총가중·비용·25종) 전이 검증을 등재했습니다",
           "다른 혹형 재료들로 일반화 검증을 등재했습니다",
           "판정: 자본 배정 없음 — 선별 규칙 지식으로 적립됩니다"))
  ),
  charts = p1,
  footer = "📚 FQ-170 · p1_topcut_ab.json · metric_type=canonical_screen_diag",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
