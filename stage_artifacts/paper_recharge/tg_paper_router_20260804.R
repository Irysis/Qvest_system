## 논문 라우터 v2 텔레그램 발송 — 20260804
source("02_Infrastructure/config.R")
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent    = "AlphaSearch",
  title    = "리서치 소스 배분 + 팩터 마이닝 (20260804)",
  relaxed  = TRUE,
  force    = TRUE,
  lock_scope = "paper_router_20260804",
  sections = list(

    ## §1 연구 컨텍스트 ----
    list(type = "text", emoji = "📚", heading = "연구 컨텍스트",
         body = paste(
           "[목적] 오늘 수집한 arxiv 논문 40편을 리서치 모드별로 배분하고,",
           "숨은 팩터 후보를 발굴해 alpha-search 소스로 연결함.",
           "[내용] 논문별 route 분류(alpha/optimizer/risk/regime/skip) + 팩터 추출 오버레이.",
           "[결과] testable 팩터 2건 발굴, alpha-search 에이전트 2개 자동 착수."
         )),

    ## §2 배분 결과 ----
    list(type = "bullet", emoji = "🗂️", heading = "route별 배분 (40편)",
         items = c(
           "alpha     2편: FinSMART 감성RL · AWARE-FX 공시",
           "optimizer 2편: Three Matrices · 이중시간척도 드리프트",
           "risk      1편: CD-DFM 특성→공분산",
           "regime    2편: 추세추종 스펙트럼 · 군집행동",
           "skip     33편: crypto · 옵션 · 순수이론 등",
           "curated   신규 0건 (15건 전부 기처리)"
         )),

    ## §3 팩터 후보 ----
    list(type = "bullet", emoji = "🔬", heading = "팩터 후보 발굴 (route 무관 오버레이)",
         items = c(
           "✅ [testable] Spectral_LowFreq_Momentum (출처: regime 논문 2607.19497) — FFT로 개별 종목 월간 수익률의 저주파 스펙트럼 파워 비중 계산 → 추세 강도 랭킹. DB 미보유 신규.",
           "✅ [testable] FX_Hedging_Disclosure_Score (출처: alpha 논문 2607.27611) — DART 사업보고서에서 외환 헤징 공시 강도 NLP 점수화 → 환율 안정성 프리미엄. 텍스트 팩터 DB 미보유.",
           "❓ [uncertain] Vol_Rank_Markov (출처: optimizer 2607.27461) — iVol DB와 중복 가능성으로 보류.",
           "❓ [uncertain] MACD_Drift_Estimator (출처: optimizer 2607.01705) — MACD와 유사 가능성으로 보류."
         )),

    ## §4 쉬운 설명 ----
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 오늘 수집된 40편 논문을 어느 연구 모드에 쓸지 분류했습니다.",
           "방법: 논문마다 '이게 종목 고르기 신호인가(alpha), 비중 결정법인가(optimizer), 위험 측정인가(risk), 타이밍인가(regime)'를 판단했습니다.",
           "결과: 즉시 테스트 가능한 새 팩터 2건을 발굴해 백테스팅(과거 모의 운용)을 자동으로 시작했습니다.",
           "의미: 성공하면 KR 주식 200종목 중 25개를 고르는 새 기준이 생깁니다."
         )),

    ## §5 AUTORUN 착수 ----
    list(type = "bullet", emoji = "🚀", heading = "alpha-search AUTORUN 착수 (2편)",
         items = c(
           "① Spectral_LowFreq_Momentum — '저주파 스펙트럼 모멘텀': 가격 데이터를 주파수 분해해서 장기 추세 강한 종목 선별. 에이전트 실행 중.",
           "② FX_Hedging_Disclosure_Score — 'FX 헤징 공시': DART 사업보고서의 환위험 관리 공시를 점수화. 에이전트 실행 중.",
           "결과 도착 시 각 전략별 2차트 + 성과 요약 별도 발송 예정."
         )),

    ## §6 모드 큐 ----
    list(type = "bullet", emoji = "📋", heading = "optimizer/risk/regime 모드 큐 (5편)",
         items = c(
           "[optimizer] Three Matrices (2607.27461) — Markov chain 변동성 랭크 전이 + 잔차거리 분산화. α̂ 고정 A/B 대상.",
           "[optimizer] 이중시간척도 드리프트 (2607.01705) — MACD가 잠재 드리프트 최적 필터임을 수학 증명.",
           "[risk] CD-DFM (2607.24410) — 재무 특성→비선형 인코더→전향적 공분산 추정(Stein loss). Σ 추정 방법론 후보.",
           "[regime] 추세추종 스펙트럼 (2607.19497) — closed-form 샤프지수 + 저주파 파워 = 추세 강도. spectral momentum 팩터 별도 alpha 처리.",
           "[regime] 군집행동 (2607.27063) — 중국 A주 CSAD/LSV herding indicator. KR 국면 입력 신호 가능성."
         ))
  )
)
