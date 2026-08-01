source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "팩터 심층 재검 (tier-2) — 20260802",
  relaxed    = TRUE,
  force      = TRUE,
  sections   = list(

    list(type = "summary", emoji = "📌",
         body = "오늘 큐 4건 중 3건은 이미 처리된 논문(중복), 신규 1건은 구현 불가 확정."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: tier-1이 uncertain으로 남긴 논문 후보를 깊게 정독해 테스트 가능/불가 판별",
           "방법: 전문 PDF 정독 + 팩터 DB 373종 대조 + KR 인프라 구현 가능성 점검",
           "결과: 신규 논문 1건 — 독점 데이터베이스 없이는 구현 불가로 확정",
           "의미: 오늘 백테스팅 큐에 추가되는 후보 없음, 인프라 제약 구조적"
         )),

    list(type = "kv", emoji = "📊", heading = "처리 결과",
         kv = list(
           "입력 총계"      = "4건",
           "중복 건너뜀"    = "3건 (기등재)",
           "신규 확정 기각" = "1건 (2607.26859)",
           "승격(testable)" = "0건"
         )),

    list(type = "bullet", emoji = "🔍", heading = "신규 기각 — ESG 소유그래프 위험 추론",
         items = c(
           "논문: No Data Is Not No Risk (RepRisk AG · 도쿄대)",
           "아이디어: 기업 소유구조 그래프 전파로 미보고 기업의 ESG 위험 추론",
           "기각 사유1: 학습 레이블이 RepRisk 독점 DB — KR에선 대체 불가",
           "기각 사유2: KR 350종목 기준 학습 양성 샘플 ~27건(필요 최소치 대비 절대 부족)",
           "기각 사유3: 논문 목표변수가 미래 위반 건수 — 주가 수익 예측력 전혀 없음",
           "부활 조건: FSC·FTC 제재 구조화 DB 5년치 이상 확보 시 재검토"
         )),

    list(type = "bullet", emoji = "🔁", heading = "중복 3건 요약",
         items = c(
           "2607.16450 (Hill 꼬리지수): 07-27 기각 + 경험적 QUARANTINE (PORT_t=0.77)",
           "2607.14174 (DART 감성): 07-26 승격→QUARANTINE (위험요인 섹션 구조 부재)",
           "2607.13968 (뉴스 감성): 07-27 기각 (시장 지수 논문, 종목별 팩터 아님)"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 액션",
         items = c(
           "오늘 백테스팅 큐 추가 없음 — 기존 큐 소진 대기",
           "FQ 등재: ESG 소유그래프는 독점 DB 확보 조건부로 frontier 보류",
           "next_probe: DART 제재 공시 구조화 가능성 별도 탐색(FQ-신규 후보)"
         ))
  )
)
