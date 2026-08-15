## WT-D20260813_005 (FQ-237) 텔레그램 보고 — v7 표준 5섹션 + 원칙 9 차트
suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT-D20260813_005"

p1 <- tg_chart_sweep(
  labels = c("기존 선별", "신규 선별(주)", "음성대조", "누출주입(검사용)"),
  values = c(0.9474, 0.9899, 0.3808, 3.4289),
  out_dir = OUT,
  title = "선별 방식별 실현 성과 (PORT_t) — 검사는 살아있고 신호가 약하다",
  hline = 2.95, highlight = 2L)

tg_agent_brief(
  agent = "Q-Lead",
  title = "고르는 기준을 바꿔봤습니다 — 방향은 맞는데 크기가 안 나옵니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "종목 고르는 기준을 소비 방식에 맞춰 바꿨습니다. 좋아지는 방향이나 우연과 구분이 안 됩니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "문제의식: 순위로 고르는데 실제로는 평균으로 돈을 법니다",
           "그 둘이 320개 팩터 중 38%에서 서로 어긋난다는 걸 오늘 쟀습니다",
           "시도: 고르는 기준을 '평균'으로 바꿔 소비 방식과 맞췄습니다",
           "결과: 연 1.86% 나아지는 방향이지만 통계적으로 우연과 구분 불가",
           "의미: 아이디어가 틀린 게 아니라 크기가 안 나온 것입니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("차이 검정" = "t 0.49 (기준 2.0)",
                   "연 개선폭" = "+1.86%",
                   "기존 선별" = "PORT_t 0.95",
                   "신규 선별" = "PORT_t 0.99",
                   "검증 기간" = "221개월")),

    list(type = "bullet", emoji = "🔬", heading = "이 결과가 믿을 만한 이유",
         items = c(
           "일부러 미래 정보 1개월을 넣으니 t가 0.49에서 4.16으로 뛰었습니다",
           "즉 잴 능력은 있는데 신호가 약한 것이지 장치 고장이 아닙니다",
           "신호를 한 달 늦추면 더 나빠집니다 — 약한 진짜 신호의 지문입니다")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "실제 자본과 무관합니다 — 전 방식이 자본 기준 2.95에 한참 못 미칩니다",
           "선별 계층 실험이지 편입 후보를 만드는 라운드가 아닙니다",
           "제가 만든 데이터 자산에서 결함 2건이 발견돼 별도 점검합니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "가장 강한 자기비판: 고를 때는 상위 20%인데 담을 때는 상위 7% — 정합이 절반만 됐습니다",
           "국면별로 나누면 평시에는 유의했습니다 (별도 사전등록 필요)",
           "실패 시 경로대로 재료 축(일별 자료)으로 넘어갑니다"))
  ),
  charts = p1,
  footer = "📚 WT-D20260813_005 · FQ-237 · 사전등록 PREREG_impl_lock.md"
)
cat("텔레그램 발송 완료\n")
