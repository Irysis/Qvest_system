# run_wt017_telegram.R — WT-017 완료 브리프 (tg_agent_brief 단일 진입점 + 차트)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

tab <- data.frame(
  지표 = c("현행 book PORT_t", "후보 PORT_t", "한계기여 paired t", "정보비율 차",
           "라벨 하락월 적중", "오라클(진단)"),
  값 = c("+6.18 (낙폭 -23.3%)", "+5.08 (낙폭 -23.3%)", "-1.85 (-2.38%/yr)", "-0.22",
         "10% (무작위 41%)", "낙폭 -9.2%로 절반"),
  stringsAsFactors = FALSE)

tg_agent_brief(
  agent = "Alpha",
  title = "WT-017 국면 라벨 overlay 소비 — 한계기여 없음 (FQ-115 부정)",
  sections = list(
    list(type = "summary",
         body = "국면 라벨을 현행 overlay 위 노출 축소로 소비 — 한계기여 없음, 점추정 유해"),
    list(type = "text", heading = "쉬운 설명", body = paste0(
      "'위기 경보가 켜지면 주식 비중을 더 줄인다'는 규칙을 현행 방어장치 위에 얹어 269개월 실측했습니다. ",
      "결과는 손해였습니다. 경보가 켜진 달의 시장은 평균적으로 크게 올랐고(연율 +90%), ",
      "실제 하락달 적중률은 10%로 동전던지기(41%)보다 낮았습니다.")),
    list(type = "table", heading = "핵심 실측 (269개월, 2004-01~2026-05 홀딩)", df = tab,
         notes = c("EW 기저 -2.04 / 라벨 한 달 지연 -2.57 / 비용반영 -1.87 — 전부 부정 방향 일관",
                   "하락월 판별력: fisher p=1.0 (깊은 하락 -8% 문턱에서도 p=0.196)")),
    list(type = "bullet", heading = "판정", items = list(
      "WT-015의 위기월 초과수익 +4.98%는 방어 성공이 아니라 라벨 우연으로 확정",
      "위기 라벨월 15건 = 2009·2020 반등월 + 2026 멜트업월 — 경보는 위기 '후'에 켜짐",
      "병목은 소비 경로가 아니라 라벨 품질 — 오라클 진단으로 overlay 소비면 자체는 유효",
      "PIT 가드 269개월 통과 + 위반 주입 시 차단 발화 실증 (동월 look-ahead 사고 lane 방어)",
      "측정 결함 2건 자체 적발·수리(가중 붕괴 지문 발화) — 재발 가드 배선",
      "자본 주장 없음 — overlay 변경은 도훈 수동 영역"
    )),
    list(type = "bullet", heading = "다음 단계", items = list(
      "라벨 엔진의 지연-지표 기전 규명 — 위기확률 연속값의 선행력 직접 실측",
      "실현-하락 nowcast 대체 라벨(트레일링 낙폭/변동성 규칙) 동일 스케줄 재측정",
      "부활 조건: 라벨 적중률 회복 시 재측정 + 7월 폭락월 포함 재판정"
    ))
  ),
  charts = c("stage_artifacts/WT_D20260802_017/wt017_chart_marginal.png")
)
cat("[wt017] telegram 발송 완료\n")
