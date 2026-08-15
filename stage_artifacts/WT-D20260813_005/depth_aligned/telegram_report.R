## FQ-237 깊이-정합 재측정 텔레그램 (v7 5섹션 + 원칙 9 차트)
suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT-D20260813_005/depth_aligned"

p1 <- tg_chart_sweep(
  labels = c("기존 선별", "신규(깊이 20%)", "신규(깊이 7.3%)", "음성대조"),
  values = c(0.9474, 0.9899, 1.7775, -0.2353),
  out_dir = OUT,
  title = "선별 깊이를 소비에 맞추자 성과가 움직였다 (PORT_t)",
  hline = 2.95, highlight = 3L)

tg_agent_brief(
  agent = "Q-Lead",
  title = "고르는 깊이를 담는 깊이에 맞췄더니 — 3.2배 움직였지만 문턱은 못 넘었습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "지난번 실험의 허점을 고쳤습니다. 성과가 크게 움직였으나 확신 문턱에는 못 미칩니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "지난번 허점: 고를 때는 상위 20%를 보고 담을 때는 상위 7%만 담았습니다",
           "수정: 고르는 기준도 상위 7%로 맞췄습니다 — 이게 원래 하려던 실험입니다",
           "결과: 성과 지표가 0.99에서 1.78로 올랐습니다 (기존 방식 0.95)",
           "그런데: 우연이 아닐 확신도가 1.57로 기준 2.0에 못 미칩니다",
           "판정: 틀렸다고도 맞다고도 할 수 없어 보류합니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("확신도" = "1.57 (기준 2.0)",
                   "성과 지표" = "1.78 (기존 0.95)",
                   "연 개선폭" = "+6.03% (직전 +1.86%)",
                   "음성대조" = "-0.24 (미개선 = 정상)",
                   "검증 기간" = "221개월")),

    list(type = "bullet", emoji = "🚩", heading = "가장 강한 반대 증거",
         items = c(
           "이득이 앞 구간에 몰려 있습니다 — 2020년 이후는 오히려 마이너스",
           "가장 좋았던 5개월을 빼면 확신도가 1.57에서 0.76으로 떨어집니다",
           "즉 소수 시점이 결과를 끌고 있어 안정적이라 보기 어렵습니다")),

    list(type = "bullet", emoji = "🔬", heading = "믿을 만한 근거와 자기정정",
         items = c(
           "미래 정보를 넣으면 확신도가 1.57에서 4.03으로 뜁니다 — 잴 능력은 있습니다",
           "저울(벤치마크)을 바꿔도 판정이 그대로입니다 — 기준 논쟁과 독립입니다",
           "'재료가 말랐다'고 쓴 초판 결론을 검증 후 철회했습니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "선별 방식은 기각이 아니라 보류 — 새 재료나 새 사전등록이 있을 때 재개",
           "위기 구간에서 손실이 사라진 점이 눈에 띕니다 (별도 검증 필요)",
           "주력은 일별 자료 축으로 이동합니다"))
  ),
  charts = p1,
  footer = "📚 WT-D20260813_005 depth_aligned · 사전등록 PREREG_depth.md"
)
cat("텔레그램 발송 완료\n")
