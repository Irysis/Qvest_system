PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 (tier-2) — 3건 처리, 1건 승격",
  relaxed = TRUE,
  force  = TRUE,
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "tier-2 논문 정독 3건 완료 — DART 위험요인 감성 1건 백테스팅 대상 승격, TDA·LLM 레짐 2건 확정 기각."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: tier-1이 불확실로 남긴 논문 3편을 전문 정독해 정밀 재판정했습니다",
           "방법: 논문 수식·데이터 요건·KR 구현 가능성을 직접 확인했습니다",
           "결과: 사업보고서 위험 섹션 감성 신호 1건 승격, 나머지 2건은 종목 횡단면 신호 없음으로 기각",
           "의미: 승격된 신호는 alpha-search 백테스팅 대기열에 등재됐습니다"
         )),
    list(type = "kv", emoji = "📊", heading = "재검 결과",
         kv = list(
           "입력"              = "3건",
           "승격 (testable)"  = "1건",
           "확정기각"          = "2건",
           "still_uncertain"  = "0건"
         )),
    list(type = "bullet", emoji = "✅", heading = "승격 — dart_risk_section_sentiment",
         items = c(
           "논문: 2607.14174 (How Much of a 10-K Matters?)",
           "신호: DART 사업보고서 위험요인 섹션 → Ke et al.(2020) 지도학습 어휘 → 종목별 감성 점수 p_hat",
           "KR: DART HTML 파싱 + mecab-ko 형태소 분석 + 수익률 레이블 지도학습",
           "PIT: 사업보고서 익년 3/31 적용 (C4 준수), 연간 1회 업데이트",
           "신규성: DART 텍스트 감성 팩터 레지스트리 373건 내 전무 (MA06는 시장 수익률 기반 매크로, 무관)"
         )),
    list(type = "bullet", emoji = "🚫", heading = "확정기각 2건",
         items = c(
           "2607.21170 (TDA 포트폴리오): 필수 4차원 = Refinitiv FinBERT 뉴스 감성 → KR 인프라 없음. 종목별 수익 예측 횡단면 신호 미존재, 군집화 메커니즘",
           "2606.15473 (LLM 베이지안 레짐): 시장 레짐 타이밍 (종목 횡단면 알파 없음) + OpenAI API 외부 의존 + SR 0.411 예시용 사례연구, 알파 생성 논문 아님"
         )),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "dart_risk_section_sentiment: 착수 전 DART 텍스트 파이프라인(HTML 파싱 + 섹션 추출) 구축 확인 필요",
           "tier-1 라우터 신규 가동 필요 (최신 route = 07-24, 2일 공백 — paper_router_run.sh)",
           "FQ-002 계약수주 magnitude / FQ-003 공매도잔고 / FQ-004 감사의견 — 비-return 원천 주력 유지"
         ))
  )
)
