## arm B 결과 텔레그램 (v7 표준 5섹션 + 원칙 9 차트: sweep 비교 + primary 표준 3종)
suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/fq233_probe0_20260813"

full <- readRDS(file.path(OUT, "armB_full.rds"))
p1 <- tg_chart_sweep(
  labels = c("q10", "q50(주)", "평균(대조)", "q90"),
  values = c(0.4371, 0.5140, 0.6039, 0.6061),
  out_dir = OUT, title = "표적별 실현 샤프지수 — 순위력과 역순",
  hline = NULL, highlight = 2L)
p2 <- tg_chart_pack(period_returns = as.data.frame(full$B$pr), out_dir = OUT,
  title = "arm B — 분위 표적 q50 (주 비교)",
  metrics_note = "total SR 0.514 · PORT_t -0.40 · MDD 55.9% · 198개월 (canonical_screen)")

tg_agent_brief(
  agent = "Q-Lead",
  title = "분포-표적 연구 2단계 — 예측은 좋아졌는데 수익은 안 따라왔습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "표적을 평균에서 중앙값으로 바꾸니 적중도는 4배 올랐지만 실제 수익은 안 늘었습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: '평균 수익' 대신 '중앙값 수익'을 맞히도록 학습시켰습니다",
           "결과1: 예측 적중도(정보계수)는 0.007에서 0.030으로 4배 올랐습니다",
           "결과2: 그런데 실제 수익률은 오히려 조금 낮았습니다",
           "이유: 상위 25종목이 버는 건 중앙값이 아니라 평균이기 때문입니다",
           "의미: 잘 맞히는 것과 잘 버는 것이 다른 문제임을 확인했습니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("샤프지수" = "0.514 (대조군 0.604)",
                   "차이 검정" = "t -1.25 (기준 ±2.0)",
                   "판정" = "차이 없음",
                   "정보계수" = "0.030 (대조군 0.007)",
                   "검증 기간" = "198개월")),

    list(type = "bullet", emoji = "🔍", heading = "가장 눈에 띈 것",
         items = c(
           "네 방식의 적중도 순위와 수익 순위가 정확히 반대였습니다",
           "적중도 1위(하위 분위)가 수익 꼴찌, 적중도 꼴찌가 수익 1위",
           "다만 표본이 4개뿐이라 관찰이지 입증은 아닙니다")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "실제 자본은 배정하지 않습니다 — 전부 기준 미달입니다",
           "수익 1위였던 방식으로 결론을 바꾸지 않았습니다",
           "성과를 보고 주 비교 대상을 고르면 통계가 오염됩니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "수익 1위였던 상위 분위 방식을 별도로 사전 등록해 정식 검증",
           "종목 고르는 기준 자체를 바꾸는 실험으로 연결 (FQ-237)",
           "이 단계에서 돈이 움직이는 변화는 없습니다"))
  ),
  charts = c(p1, p2),
  footer = "📚 사전등록 PREREG_armB_20260813.md · 산출 armB_result.json · FQ-233 Lane A"
)
cat("텔레그램 발송 완료\n")
