suppressMessages({
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR")
  if (nchar(PROJECT_ROOT) == 0) PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
})

tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 (tier-2) — 3건 처리, 1건 승격",
  relaxed = TRUE,
  force = TRUE,
  sections = list(

    list(type = "summary", emoji = "📌",
         body = "오늘 uncertain 3편을 깊게 재검한 결과: 변동성 순위 지속성 1건 승격, 2건 확정 기각."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 1차 라우터가 '판단 유보'로 남긴 논문 3편을 전문 정독(최대 16만 자)했습니다",
           "방법: 신호 구현 가능 여부·기존 팩터 중복·KR 데이터 적합성을 항목별 점검했습니다",
           "결과: 변동성 순위의 마르코프 전이확률(Vol_Rank_Markov_Persistence) 1건을 백테스팅 대상으로 올렸습니다",
           "의미: 내일 alpha-search 백테스팅으로 실제 수익신호 존재 여부를 판정합니다"
         )),

    list(type = "kv", emoji = "📊", heading = "처리 결과 (3건)",
         kv = list(
           "✅ 승격(testable)" = "Vol_Rank_Markov_Persistence (2607.27461)",
           "❌ 기각 — 인프라 미보유" = "Market_Aligned_Sentiment_RL (2607.28127)",
           "❌ 기각 — 위험모델, 알파 아님" = "CD_DFM_Latent_Factor_Exposures (2607.24410)"
         )),

    list(type = "bullet", emoji = "🔬", heading = "승격 근거 — Vol_Rank_Markov_Persistence",
         items = c(
           "핵심: 변동성 순위 10분위 전이행렬 P^V에서 '다음 달에도 저변동성일 확률' 추출 → 상위 25종 선별",
           "예측력: 변동성 순위 log-likelihood gain +0.116 nats vs 수익률 순위 +0.007 (후자는 사실상 예측 불가)",
           "신규성: 레지스트리 21d/63d Volatility 수준값과 구별 — 전이확률 표현 미등재",
           "구현: 일별 Ret(RAWDATA)만으로 가능. PIT C1~C15 준수."
         )),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "5bps 기준 long-only 단독 in-sample(2018-2021) 샤프지수 0.03 vs 시장 0.70 — 대폭 열세. 15bps에서 마진 추가 압박",
           "논문 핵심 성과원 = market-neutral 롱숏 sleeve (QEPM long-only 불가). 단독 long-only는 보조 성과",
           "KR 저변동성 계열 과거 실적 약함(AX-001/DIST-AR-001 인접) — 반드시 KR 실측 선행",
           "FinSMART: 영어 뉴스 코퍼스+GPU GRPO 인프라 전무. DART 텍스트는 구조화 공시라 대체 불가",
           "CD-DFM: Stein 공분산 손실 최적화 논문 — IC/alpha 수치 0건. 알파 신호 전용은 날조에 해당"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 액션",
         items = c(
           "Vol_Rank_Markov_Persistence → alpha-search 백테스팅: KR K200∪KQ150, rolling 36M P^V 추정, cap-w PORT_t 및 cap-tier 분해 실측",
           "FinSMART next_probe ①: DART 공시 텍스트 zero-shot 감성 팩터 신규 FQ 등재 (multilingual BERT, 독립 가설)",
           "CD-DFM next_probe ①: characteristic-driven 공분산(재무 7종+sector) → risk-research Σ 추정기 대안 WT 가설 등재",
           "내일(20260805) arXiv 2026-08-01~04 신규 등재분 탐색 (월요일 제출분 화요일 등재 관례)"
         ))
  )
)
