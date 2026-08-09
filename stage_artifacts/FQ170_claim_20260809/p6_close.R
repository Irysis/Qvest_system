#!/usr/bin/env Rscript
# p6_close.R — FQ-170 NP-2/NP-4 결과 등재 + 텔레그램 (라운드 최종)
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/FQ170_claim_20260809")

source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-170"); stopifnot(length(i) == 1)
Q$entries[[i]]$status <- "confirmed_with_bounds_20260809"
Q$entries[[i]]$np2_np4_result_20260809 <- paste0(
  "NP-2/NP-4 실측 완료(p5_np2np4) — 확립 규칙의 **경계 확정** (둘 다 정보성 negative). ",
  "[NP-2 처치-강건성 미재현 + 기전]: z_neutral(중립판, HUMP·argmax **D5**)에 고정 D8~D9 밴드 적용 시 ",
  "t +0.018(평평) — 실패가 아니라 **밴드 위치가 재료-종속**임의 실측. FQ-166 E3 가 이미 raw argmax D8 / ",
  "중립 argmax D5 로 혹 위치가 다름을 기록했고, 본 결과는 그 함의의 확인: 규칙의 올바른 일반형은 ",
  "'70~90분위 고정 밴드'가 아니라 **'그 재료의 혹 위치에서 소비'** — argmax-적응형 밴드는 미검증 셀",
  "(적합 파라미터 1개 추가 = 다중검정 부담 병기 의무). ",
  "[NP-2 추가 음성 대조 정상]: M01_PATHQ(MONOTONE_TOP) 밴드 적용 -6.16%p/yr t -2.216 — ",
  "MONOTONE 재료 2건(M26·M01) 모두 밴드가 해로움 = 형태-조건부성 재확인. ",
  "[NP-4 composite 경로 닫힘]: 밴드-Q01 active 와 컨센서스 3종 top-25 active 상관 = ",
  "C01_SUE +0.639 · C02_EPS_Chg_1m +0.567 · C04_ESBR +0.658 — 전 성분 |cor|>=0.30 미달. ",
  "book-marginal ΔIR 측정 자격 없음(어닝 계열 동족이라 직교 아님 — 예상 가능했던 결과의 실측 확정)."
)
Q$entries[[i]]$next_action <- paste0(
  "[NP-5] argmax-적응형 밴드 — trailing 프로파일에서 혹 위치를 추정해 밴드를 이동(적합 파라미터 1, ",
  "IS-only 추정 + 다중검정 병기). z_neutral D5-밴드 재검이 첫 검증 셀. ",
  "[NP-2 잔존] 진짜 계열 일반화 = FQ-171 census(타 세션 in-flight) 가 HUMP 판정한 신규 재료 대기 — 침범 금지. ",
  "[NP-3 잔존] INVERTED(D03) 대응 미측정. ",
  "[닫힌 경로] composite 성분(상관 미달)·고정 밴드의 처치-일반화(위치 종속)."
)
res <- write_frontier_queue(Q)
cat("[fq170-final] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
CH <- file.path(OUT, "charts")
p1 <- tg_chart_sweep(
  labels = c("단조형 M01 (음성대조)", "단조형 M26 (음성대조)", "혹형 중립판 (혹 위치 D5, 밴드 D8~D9)",
             "혹형 원판 (혹 위치 D8, 밴드 D8~D9)"),
  values = c(-6.16, -4.14, 0.05, 5.62),
  out_dir = CH, title = "밴드 규칙의 경계 — 형태만이 아니라 혹의 위치까지 맞아야 한다",
  value_label = "밴드 선별 − 상위25 (연 %p)", hline = 0,
  highlight = "혹형 원판 (혹 위치 D8, 밴드 D8~D9)", filename = "fq170_bounds.png")
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "형태 맞춤 선별 최종 — 규칙은 확립, 경계도 확정 (혹 위치까지 맞아야 작동)",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "밴드 규칙의 적용 범위를 실측 — 형태뿐 아니라 혹의 위치까지 재료마다 맞춰야 합니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "검증1: 같은 혹형이라도 혹 위치가 다른 판본에 고정 밴드를 쓰니 효과 0이었습니다",
           "해석: 실패가 아니라 규칙의 정확한 형태를 알아낸 것입니다 — 위치 맞춤이 핵심",
           "검증2: 단조형 두 번째 재료도 밴드가 해로웠습니다 — 형태 조건부성 재확인",
           "검증3: 이 신호는 기존 운용 신호들과 상관 0.57~0.66 으로 겹칩니다",
           "의미: 운용 편입 경로는 닫히고, 위치-적응형 규칙이 다음 검증 대상입니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "원판확립" = "혹 위치 D8 + 밴드 D8~D9 = +5.62%p (t 2.57)",
           "중립판"   = "혹 위치 D5 + 밴드 D8~D9 = +0.05%p (위치 불일치)",
           "음성대조" = "단조형 2건 모두 밴드 해로움 (-4.1 / -6.2%p)",
           "상관미달" = "기존 컨센서스 3종과 0.57~0.66 (기준 0.30)",
           "판정"     = "규칙 확립 + 경계 확정 — 자본 반영 없음")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "혹 위치를 자동 추정하는 적응형 밴드가 다음 검증 셀입니다 (중립판 D5 재검부터)",
           "타 세션의 형태 조사가 끝나면 새 혹형 재료로 일반화를 검증합니다",
           "판정: 전 결과 원장 적립 완료 — 실제 운용 반영 없음"))
  ),
  charts = p1,
  footer = "📚 FQ-170 최종 · p5_np2np4.json · metric_type=backtested_screen",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
