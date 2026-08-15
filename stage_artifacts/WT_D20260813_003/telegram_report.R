## WT-D20260813_003 텔레그램 보고 (v7 표준 5섹션 + 원칙 9 차트)
suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT_D20260813_003"

## 두 채널 분해 — 이득 vs 손실 vs 순효과
p1 <- tg_chart_sweep(
  labels = c("변동성 절감 이득", "수익 희생", "순효과"),
  values = c(0.790, -1.480, -0.691),
  out_dir = OUT,
  title = "연 기여도 분해 (%/년) — 이득보다 희생이 크다",
  hline = 0, highlight = 3L)

tg_agent_brief(
  agent = "Q-Lead",
  title = "변동성 조절 오버레이 정식 검증 — 예측은 맞았고 수익이 깎였습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "위험이 커질 때 주식을 줄이는 장치를 검증했습니다. 위험은 줄었지만 수익이 더 깎였습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 변동성이 커질 것 같으면 주식 비중을 줄이는 장치를 검증했습니다",
           "확인1: 변동성 예측 자체는 맞았습니다 (상관 0.72)",
           "확인2: 위험을 줄이는 효과도 진짜였습니다 (우연 대비 7배)",
           "그런데: 주식을 줄인 달에 시장이 올라서 수익을 더 많이 놓쳤습니다",
           "결론: 얻은 것 연 0.79% < 잃은 것 연 1.48% → 순손실 연 0.69%")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("변동성 절감" = "+0.79%/년",
                   "수익 희생" = "-1.48%/년",
                   "순효과" = "-0.69%/년",
                   "검증 기간" = "366개월",
                   "판정" = "성과 측정 전 기각")),

    list(type = "bullet", emoji = "🔬", heading = "가장 무거운 발견",
         items = c(
           "이 손익차를 통계적으로 확정하려면 약 404년치 자료가 필요합니다",
           "즉 월별 시장 자료로는 원리적으로 결론이 안 납니다",
           "과거 비슷한 시도 3건이 결론을 못 낸 구조적 이유가 이것입니다")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "성과 수치는 산출하지 않았습니다 — 관문에서 멈췄습니다",
           "현 운용은 변경 없습니다. 실제 자본과 무관합니다",
           "기각 범위는 '비율로 연속 조절' 형태에 한정됩니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "문턱형(특정 수준 넘을 때만 작동) 방식은 아직 안 봤습니다",
           "검정력 벽 우회 = 일별 자료 축 또는 위험모델 쪽으로 표면 이동",
           "확인된 변동성 예측 능력 자체는 다른 소비면에서 재활용합니다"))
  ),
  charts = p1,
  footer = "📚 WT-D20260813_003 · 사전등록 prereg_VT.json · 산출 vt_final.json"
)
cat("텔레그램 발송 완료\n")
