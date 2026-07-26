PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 보충 QC — autorun 2건 신뢰도 정정",
  relaxed = TRUE,
  force  = TRUE,
  sections = list(
    list(type = "summary", emoji = "🔍",
         body  = "tier-2 큐 공백 중 autorun 대기 2건 사후 검증. 날조 아님 — 논문 메커니즘 명확. 단 tier-1 신뢰도 high→medium 정정 필요."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 오늘 자동 백테 대기 중인 논문 2편을 전문 정독해 팩터 근거를 재확인했습니다",
           "방법: 논문이 해당 팩터를 주식 종목 횡단면 수익 예측 신호로 직접 검정했는지 확인했습니다",
           "결과: 두 논문 모두 '팩터 메커니즘은 명확하나 주식 횡단면 수익 예측력은 직접 검정하지 않음'",
           "의미: 자동 백테는 계속 진행 가능. 단 결과 해석 시 '방향 미사전결정' 명시 필요"
         )),
    list(type = "kv", emoji = "📊", heading = "신뢰도 정정",
         kv = list(
           "vol_rank_stability (2607.19005)" = "high → medium (논문: 집합-레벨 Markov chain 진단. 횡단면 수익 검정 없음)",
           "spec_lowfreq_mass (2607.19497)"  = "high → medium (논문: TF 시스템 성과 귀속. 주식 횡단면 적용 안 함)",
           "날조 판정"                         = "없음 — 메커니즘·입력 논문에 명확. 재구성 정당.",
           "autorun 진행"                      = "가능 (방향 양방향 검정 + 중복 팩터 corr 포함 조건)"
         )),
    list(type = "bullet", emoji = "⚠️", heading = "alpha-search 실행 시 주의",
         items = c(
           "vol_rank_stability: 저변동성 팩터(D47/D48)와 corr 확인 필수 — low-vol anomaly 변종 가능성",
           "spec_lowfreq_mass: 모멘텀 팩터(M01_Mom6/M02_Mom12)와 corr 확인 필수 — 추세지속성=모멘텀 overlap 가능",
           "두 팩터 모두 direction empirical 양방향 검정 의무 (논문이 방향 주장 없음)",
           "횡단면 수익 예측력 = 신규 가설, 논문 근거 아님 — 보고 시 명시"
         )),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "autorun P1 vol_rank_stability + P2 spec_lowfreq_mass 백테 결과 대기",
           "dart_risk_section_sentiment: DART 텍스트 파이프라인 구축 후 alpha-search 착수",
           "FQ-004 P2: confound-controlled hard-distress composite 실측 가능 (비-return 원천 주력)"
         ))
  )
)
