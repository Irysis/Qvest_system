## send_tg_r36.R — R36 monitoring 판정 텔레그램 (v7 · charts 의무)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_005"
charts <- file.path(OUT, c("01_form_safe_strength.png","02_top30_sample_vs_signal.png","03_safe_risk_reduction.png"))

tg_agent_brief(
  agent = "Alpha",
  title = "R36 insider 순매수 tripwire coverage 확장 — 3형태 측정 (WT-D20260715_005 · FQ-050)",
  sections = list(
    list(type="summary", emoji="📌",
      body="임원 순매수 안전신호 커버리지를 3방식으로 확장 — 감시 커버는 2배, 대형주 신호는 여전히 약함."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "시도: 임원 순매수=이후 안전 발견을 더 많은 종목·달에 적용되게 문턱 3방식으로 확장",
        "방법: 21년 실보유 데이터로 순매수 vs 나머지 이후 수익·하락 비교, 무작위·누출검사로 검증",
        "결과: 문턱 낮추면 감시 달 126→250개월 2배, 안전성 유지. 순매수 강도 지표도 유효",
        "그래서: 돈 넣는 신호 아님 — 감시 경보 문턱 확장 권고, 대형주 신호 약함은 명시")),
    list(type="kv", emoji="📊", heading="핵심 수치 (모니터링·자본 아님)",
      kv=list(
        "F0 기준(R33 재현)"="안전 gap t=3.36 · 126개월",
        "F2 완화(INS02≥0.5)"="gap t=4.25 · 250개월 · 표본 3.1배",
        "F3 연속(순매수강도)"="정보계수 t=4.12 · 신규 유효",
        "F1 정밀(recency 결합)"="gap t=3.17 — 무이득(배선 금지)",
        "대형주 TOP30 안전 t"="1.30~1.68 (전 형태 <2, 약함)")),
    list(type="bullet", emoji="🚩", heading="한계·주의 (정직 보고)",
      items=c(
        "완화는 종목당 신호 희석(연 12.4→9.0%) — t 상승은 표본효과이지 신호강화 아님",
        "대형주 상위30은 표본 3배 늘려도 안전 t값 2 미만 — 안전신호는 중형주 중심",
        "자본·비중 신호 아님 — 종목단 유지안전 라벨만 (포트 저변동 아님)")),
    list(type="bullet", emoji="➡️", heading="다음 단계",
      items=c(
        "대형주 신호 얇음 진단 — 표본부족인지 초대형주 신호소멸인지 판별",
        "순매수 강도·확산 두 지표 복합 안전신호 — 대형주 개선 여부 실측",
        "문턱 완화 배선은 감시 모듈 별도 태스크(부실경보 창구 확장)")),
    list(type="bullet", emoji="🧭", heading="판정",
      items=c(
        "자본 배정 아님 — 감시 경보장치 문턱 완화 권고(감시 커버 2배·현 북 활성화)",
        "대형주 안전 신뢰는 약함(한계 명시). 실계좌 변경 없음"))
  ),
  charts = charts
)
cat("[TG] R36 sent\n")
