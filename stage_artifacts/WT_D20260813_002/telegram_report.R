## WT-D20260813_002 텔레그램 보고 (v7 표준 5섹션 + 원칙 9 차트)
suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT_D20260813_002"

## F1 판별력 비교 — 상태-baseline(MSM 0.7472) 대비
p1 <- tg_chart_sweep(
  labels = c("꼬리표적", "꼬리형태만", "변동성", "MSM(기존)", "BearProb"),
  values = c(0.7143, 0.5549, 0.7504, 0.7472, 0.6789),
  out_dir = OUT,
  title = "하방 꼬리월 판별력 (AUC) — 신규 표적이 기존을 못 넘음",
  hline = 0.5, highlight = 1L)

tg_agent_brief(
  agent = "Q-Lead",
  title = "국면예측 → 현금배분 정식 검증 — 기전 관문에서 기각",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "국면의 '꼬리'를 맞히는 새 방식이 기존 방식을 넘지 못해 성과 측정 전에 중단했습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 국면을 '좋다/나쁘다'가 아니라 '급락 위험'으로 예측해 현금 비중을 정하려 했습니다",
           "규율: 성과를 보기 전에 '정말 급락월을 맞히는가'부터 확인하도록 미리 정해뒀습니다",
           "결과: 새 방식 판별력 0.714로 기존 방식 0.747보다 낮았습니다",
           "원인: 판별력이 '꼬리 모양'이 아니라 그냥 '변동성 수준'에서 나왔습니다",
           "조치: 성과는 아예 재지 않고 중단했습니다 — 못 미친 게 아니라 안 잰 것입니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("신규 판별력" = "0.714 (AUC)",
                   "기존 MSM" = "0.747",
                   "꼬리형태만" = "0.555 (우연 수준)",
                   "격자 전수" = "20칸 중 승리 0칸",
                   "검증 기간" = "367개월 · 사건 37건")),

    list(type = "bullet", emoji = "🔍", heading = "얻은 것",
         items = c(
           "기존 방식이 새 방식을 정보적으로 이미 포함함을 확인했습니다",
           "네 예측기 전부 '방향'이 아니라 '변동폭'을 예측하고 있었습니다",
           "이것이 과거 오버레이 16건이 모두 실패한 이유에 처음으로 설명을 줍니다")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "성과 수치는 하나도 산출하지 않았습니다 — 인용 불가입니다",
           "실제 자본 배정과 무관합니다. 현 운용은 변경 없습니다",
           "이 판정은 '벤치 일수익 파생 꼬리 통계'에 한정됩니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "소비 형태를 변동폭에 맞춘 오버레이로 재과녁 (현금 아닌 변동성 목표)",
           "기존 국면엔진의 과거 재작성 문제를 제거한 판으로 재대조",
           "부활 조건: 옵션 IV·대차잔고 등 비-수익 원천의 꼬리 정보 확보 시"))
  ),
  charts = p1,
  footer = "📚 WT-D20260813_002 · 사전등록 prereg_F1.json · 산출 alpha_validation.json"
)
cat("텔레그램 발송 완료\n")
