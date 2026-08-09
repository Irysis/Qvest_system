#!/usr/bin/env Rscript
# p10_close.R — NP-5 재설계판 결과 등재 + 텔레그램 (FQ-170 아크 최종)
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-170"); stopifnot(length(i) == 1)
Q$entries[[i]]$np5_result_20260809 <- paste0(
  "NP-5 재설계판 실측 완료(p9_np5, 교차 교훈 #1#2#3#6 전부 반영): 판정 = ",
  "**NEUTRAL_DEAD_EVEN_AT_HUMP** — 중립판은 자기 혹 위치(D4~D6 전체 EW)에서도 소비 가치 없음. ",
  "검사 유효성 선확립: 양성대조(raw D7~D9 전체 EW vs top-25) +4.68%p/yr t 2.119 재현 → 검사 유효. ",
  "주검정: z_neutral D4~D6 전체 EW vs top-25 = +1.98%p/yr t 0.747 미달 ∧ 동일폭 무작위 밴드 100 draw ",
  "q95(+2.59%p) 이내 — 위치를 맞춰도, top-edge 함정을 제거해도 안 삶. ",
  "★함의: 밴드 규칙의 소비 가치는 **raw 신호에 있고 중립화가 그것을 깎는다** — 오늘 세션 대주제",
  "('수확 가능한 구조는 순수화 이전의 성분에 있다': 폐지 풀=beta·Q01=raw)와 정합. ",
  "유효분위 실측: band 0.750/0.450(설계 정합)·top25 0.944 — 교훈#2 필드 검증 통과. ",
  "IN_PROGRESS 마커 해제."
)
na <- as.character(Q$entries[[i]]$next_action)[1]
Q$entries[[i]]$next_action <- sub("^\\[IN_PROGRESS ba4a1c30 NP-5재설계 [0-9:]+\\] ", "", na)
Q$entries[[i]]$next_action <- paste0(
  "[남은 셀] ①두 아크 라우팅 표 통합 — 전제 해소 선행(base 사후선택 = production PG2 재현 P1 · ",
  "INVERTED 표본 D03 1건) ②FQ-171 census(타 세션) 신규 HUMP 재료 일반화 — raw 판만(중립판 소비 가치 ",
  "없음 확정) ③INVERTED 필터 lane 은 3ccb658c 아크가 확립 — 그쪽 next_probe 따름. ",
  "[닫힌 경로 누적] composite 성분(상관 미달) · 고정 밴드 처치-일반화(위치 종속) · 중립판 소비(위치 무관 사망)."
)
res <- write_frontier_queue(Q)
cat("[np5-close] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
CH <- file.path(PROJ, "stage_artifacts/FQ170_claim_20260809/charts")
p1 <- tg_chart_sweep(
  labels = c("무작위 밴드 평균 (대조)", "중립판, 자기 혹 위치", "무작위 밴드 상위5% 선",
             "원판, 자기 혹 위치 (양성대조)"),
  values = c(0.87, 1.98, 2.59, 4.68),
  out_dir = CH, title = "위치를 맞춰도 중립판은 무작위와 구별되지 않는다",
  value_label = "밴드 − 상위25 (연 %p)", hline = 2.59, hline_label = "무작위 상위5% 선",
  highlight = "중립판, 자기 혹 위치", filename = "fq170_np5.png")
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "밴드 규칙 마지막 조각 — 소비 가치는 원판에 있고 중립화가 그것을 깎습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "중립화 판본은 자기 혹 위치에 밴드를 옮겨도 무작위와 구별되지 않음을 확정했습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "재설계: 병렬 세션이 잡아준 측정 함정을 제거하고 다시 쟀습니다",
           "관문: 원판 재현부터 확인 — +4.68%p (t 2.12) 로 검사 유효",
           "주검정: 중립판은 위치를 맞춰도 +1.98%p — 무작위 밴드 분포 안입니다",
           "결론: 밴드 규칙이 캐는 것은 원판 신호이고 중립화가 그걸 지웁니다",
           "정합: 오늘 하루의 대주제 — 수확 가치는 순수화 이전 성분에 있습니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "양성대조" = "원판 혹 위치 +4.68%p t 2.119 (검사 유효)",
           "주검정"   = "중립판 혹 위치 +1.98%p t 0.747 (미달)",
           "무작위"   = "동일폭 100회 mean +0.87 · 상위5% +2.59%p",
           "닫힘누적" = "composite·고정밴드 일반화·중립판 소비 3경로",
           "판정"     = "자본 반영 없음 — 원장 적립 완료")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "두 아크 라우팅 표 통합이 남은 상위 단위입니다 (전제 해소 선행)",
           "타 세션 형태 조사 완료 시 원판 기준으로만 일반화 검증합니다",
           "판정: 형태 아크 측정 단위 종료 — 모든 결과 원장 기록 완료"))
  ),
  charts = p1,
  footer = "📚 FQ-170 NP-5 재설계판 · p9_np5.json · metric_type=backtested_screen",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
