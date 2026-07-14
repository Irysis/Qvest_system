setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")
CH <- "stage_artifacts/WT_D20260714_004/charts"
res <- tg_agent_brief(
  agent = "Alpha",
  title = "R28 (FQ-041) C06_TP_Gap 가지치기 검증 — CONFIG_SCOPED_NEGATIVE + look-ahead 발견",
  sections = list(
    list(type = "summary", emoji = "📌",
      body = "C06 제거는 PIT-clean 기준 book 개선 아님. 검증 중 저장 백테 패널의 1개월 factor look-ahead 발견 — Judge/PIT escalate."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
      items = c(
        "질문: 최약체로 지목된 C06(애널리스트 목표주가 갭)을 book에서 빼면 나아지나?",
        "방법: production 재계산 경로로 268개월을 C06 있는 판/없는 판으로 재구축·비교",
        "결과1: PIT-clean 기준 제거 효과 무의미(paired 0.85·1.13). live는 이미 C06 가중치 0 근처",
        "결과2(중요): 저장 과거 백테가 '같은 달 말' factor로 그 달 수익 맞춤 = 1개월 미래참조 정황",
        "결과2 여파: 과거 성적(PORT_t 5.3)이 약 2배 부풀려졌을 가능성",
        "안심: 알파는 진짜(다음달 예측 IC t=5.92)·live 신호는 깨끗(T-1). 부풀림은 과거 백테 국한")),
    list(type = "kv", emoji = "📊", heading = "C06 제거 효과 (제거판−유지판 paired, +면 도움)",
      kv = list(
        "정합 기준(직전월)" = "IS 0.85 / HO 1.13 → 미달",
        "실운용 경로(IC가중)" = "IS 0.30 → 사실상 무변화",
        "미래참조 기준(동월)" = "IS 3.34 / HO 2.03 → 오염 기준")),
    list(type = "kv", emoji = "🔎", heading = "look-ahead 발견 (factor 데이터 월만 바꾼 대조)",
      kv = list(
        "정합 성적값" = "PORT_t 3.06",
        "동월 성적값" = "PORT_t 6.38",
        "부풀림 배율" = "2.08~2.18배",
        "저장패널 재현도" = "0.913 (동월 factor)",
        "정상 예측 정보계수 t" = "5.92 (알파 진위)")),
    list(type = "bullet", emoji = "🚩", heading = "판정 (평문)",
      items = c(
        "C06 가지치기 = 자본 개선 미검증(CONFIG_SCOPED_NEGATIVE). book_state 무변경",
        "실제 book 변경은 별도 검증 + 도훈 승인 필요(성립해도 자동 아님)",
        "R26 IS-양성(2.45)=동월 look-ahead 아티팩트, holdout 붕괴(-0.60)=recon-proxy 아티팩트",
        "★HIGH: 저장 268m 백테 패널 look-ahead 의심 = Judge/PIT 검증 권고(확정 아님)")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
      items = c(
        "FQ-044 신규(escalate): Judge/PIT가 vintage seam 확정 + 진짜 admission PORT_t 재산출(~3.1)",
        "live NAV로 backtest 하회 대조 + production 재빌드 시 직전월(T-1) 통일",
        "C06는 이미 자동 저가중 → 명시 제거해도 무해(near no-op)",
        "L-AR-20260714_164238"))
  ),
  charts = c(
    file.path(CH,"01_equity_lookahead_c06.png"),
    file.path(CH,"02_porttsweep.png"),
    file.path(CH,"03_pairedt.png"),
    file.path(CH,"04_cum_c06_effect.png"))
)
cat("[tg] ok=", tryCatch(res$ok, error=function(e) NA), "\n")
