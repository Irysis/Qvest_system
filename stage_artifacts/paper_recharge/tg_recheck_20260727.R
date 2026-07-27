source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "팩터 심층 재검 (tier-2) — 신규 승격 없음, 기각 2건",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "오늘 uncertain 후보 3건 재검: 신규 승격 없음. 확정 기각 2건, 중복 스킵 1건."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 티어-1 라우터가 불확실로 남긴 논문 후보 3건을 전문 정독해 재심사했습니다",
           "방법: 논문 전문(각 9~11만자)을 읽고 종목별 수익 예측 신호 존재 여부를 확인했습니다",
           "결과: 2건은 종목 알파 신호 자체가 없는 논문으로 확정 기각",
           "의미: 오늘 신규로 백테스팅할 후보는 없습니다"
         )),
    list(type = "bullet", emoji = "❌", heading = "확정 기각 2건",
         items = c(
           "2607.16450 hill_tail_index_60d: ETF 포트폴리오 위험 진단 논문. 개별 종목 신호 없음. 경험적 실측 PORT_t 0.77 (기준 2.95 미달)",
           "2607.13968 news_sentiment_finbert_daily: 거시 뉴스 무드 지수 논문. 종목별 정보계수 수치 전무. Factiva 외부 데이터 필수"
         )),
    list(type = "kv", emoji = "📊", heading = "재검 결과",
         kv = list(
           "입력"            = "3건",
           "신규 승격"       = "0건",
           "확정 기각"       = "2건",
           "중복 스킵"       = "1건 (2607.14174 어제 testable)"
         )),
    list(type = "bullet", emoji = "➡️", heading = "다음 액션",
         items = c(
           "2607.14174 DART 위험요인 감성 팩터: alpha_search_queue_20260726 PENDING 상태 유지",
           "next_probe 후보: DART 공시문 FinBERT 파이프라인 독립 가설 FQ 등재 (2607.13968 방법론 이식)"
         ))
  )
)
