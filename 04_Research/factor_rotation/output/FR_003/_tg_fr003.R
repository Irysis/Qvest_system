PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
D <- file.path(PROJECT_ROOT, "04_Research/factor_rotation/output/FR_003")
ch <- c(file.path(D, "FR_003_mc3_defensive_inversion.png"),
        Sys.glob(file.path(D, "*_equity_curve.png"))[1],
        Sys.glob(file.path(D, "*_drawdown.png"))[1])
ch <- ch[!is.na(ch) & file.exists(ch)]
tg_agent_brief(
  agent = "Q-Lead",
  title = "[2계층] 전략 로테이션 — FR_003 (등급 C)",
  sections = list(
    list(type="bullet", emoji="\U0001F3AF", heading="현재 리서치 상황",
         items=c("단계: 2계층 전략 로테이션 — 신규 리서치 1단위 (강화 0회차)",
                 "대상: 방어형 편입 경로 최초 발화 — 모듈 풀 15개에서 115개로",
                 "위치: 세 갈래 실측 — 처치 · 대조 · 시점정합 스트레스",
                 "직전 판정: 앞선 로테이션 2건 모두 등급 C · 표본외 유지율 음수")),
    list(type="summary", emoji="\U0001F4CC",
         body="Grade C · PORT_t 0.853 · Calmar 0.40 — 방어형 97건 편입이 전 축에서 유의하게 열세"),
    list(type="kv", emoji="\U0001F4CA", heading="핵심 비교 (처치 vs 대조)",
         kv=list("등급"="C vs C (둘 다 A 미달)",
                 "PORT_t"="0.853 vs 1.667",
                 "Calmar"="0.399 vs 0.692",
                 "OOS retention"="-0.521 vs +0.014",
                 "대응표본"="-0.192%/월 · NW3 t -2.054 · p 0.041")),
    list(type="kv", emoji="\U0001F50E", heading="기전 실측",
         kv=list("깊은 하락 초과"="+3.82%/월 vs 대조 +5.63%/월",
                 "포트 베타"="0.594 vs 0.549 (노출 축소 아님)",
                 "방어형 비중"="RISK_ON 0.585 > CRISIS 0.395 (역전)",
                 "축 전달"="방어형 비중 = 두수비중 r 0.9997 (무정보)")),
    list(type="bullet", emoji="\U0001F6A9", heading="리스크 / 주의",
         items=c("개별 방어성은 합산되지 않는다 — 40개 준균등에서 고유 성분이 상쇄",
                 "국면조건부 심사의 표본 하한이 희소국면 방어형을 먼저 탈락시킨다",
                 "측정 결함 수리 — 216개월 중 106개월 침묵 소실을 213개월로 교정",
                 "국면 축 미발화 — 신호를 한 달 더 늦춰도 성과 동일 (시점정합은 통과)")),
    list(type="bullet", emoji="\U000027A1", heading="다음 / 처분",
         items=c("처분: 장부 등록 없음 · 시점정합 심사 없음 (등급 A 확정 전 금지)",
                 "처분: 카탈로그 등재만 — 실제 자본 배정 아님 (리서치 시스템)",
                 "다음 축: 방어형을 개별 자산이 아니라 합성 슬리브 하나로 묶어 재측정",
                 "2계층 강화 원장 개시 — 다음 탐침 4건 적립 (교훈 코드 발행)")),
    list(type="text", emoji="\U0001F4DA", heading="근거 논문",
         body=paste0("Shu & Mulvey 2024 arXiv:2410.14841 (국면조건부 배분) · ",
                     "Shu-Yu-Mulvey 2024 arXiv:2402.05272 (거래지연 규약) · ",
                     "DeMiguel-Garlappi-Uppal 2009 (naive 앵커) · Ang-Chen-Xing 2006 (하방위험 축)"))
  ),
  charts = ch)
