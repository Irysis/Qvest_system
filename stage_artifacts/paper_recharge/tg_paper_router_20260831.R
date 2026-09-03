
# Paper Router v4 — 2026-08-31 텔레그램 발송

root <- Sys.getenv("QM_ROOT")
if (nchar(root) == 0) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/config.R"))
source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "[1계층] 논문 트리아지",
  relaxed = TRUE,
  glossary = TRUE,
  lock_scope = "paper_router_20260831",
  force = TRUE,

  sections = list(

    list(
      heading = "쉬운 설명",
      type    = "text",
      body    = paste0(
        "오늘 arxiv 신규 후보 243편 + 큐레이션 클래식 시드 11편(신규성 대조 후) 을 팩터 전략 ",
        "충실구현 관점으로만 트리아지했습니다(백테 미실행). 즉시 구현 가능(testable) 64건, ",
        "데이터 부재로 파이프라인 적재 40건, 이미 처리이력 있어 제외(redundant) 23건, ",
        "팩터 전략 범위 밖(skip) 127건입니다."
      )
    ),

    list(
      heading = "처리 요약",
      type    = "kv",
      kv      = list(
        "소스 합계"       = "arxiv 243 + curated 11(신규) = 254건",
        "testable"        = "64건 → route=replication 큐 적재",
        "data_pipeline_required" = "40건 (신규 35 + 기존 5 유지)",
        "redundant"       = "23건 (registry/처리이력 대조 일치)",
        "skip"            = "127건 (파생가격·마이크로구조·비주식·이론모델 등)"
      )
    ),

    list(
      heading = "팩터 후보 하이라이트",
      type    = "bullet",
      items   = c(
        "⭐⭐ regime_conditional_value_reversal (2511.12490) — 드리프트 국면조건부 가치+반전, 저자주장 OOS Sharpe 13",
        "⭐⭐ cardinality_constrained_factor_portfolio (1708.02424) — 기수제약 0-1 최적화, n≤25 하드게이트와 직접 정합",
        "⭐ v10 classic seed 8건 재트리아지 완료 — FF1992/BAB/AMP2013/TSMOM2012/BBW2011/GKX2020/Momentum Crashes/DeMiguel 1N (전량 testable, 데이터 전량 보유)",
        "⭐ HRP·Schur Complement·Topological Risk Parity·Minimal Drawdown 등 비중방법론 계열 다수 — 가격데이터만으로 재현 가능"
      )
    ),

    list(
      heading = "데이터 파이프라인 적재",
      type    = "bullet",
      items   = c(
        "신규 35건 적재 — 주요 축: 애널리스트 컨센서스·어닝콜 텍스트·ESG 평가·자사주매입 공시·공급망 네트워크·외국인 순매수",
        "기존 5건(20260830 적재분) 재확인만 — 중복 미적재"
      )
    ),

    list(
      heading = "redundant 처리",
      type    = "bullet",
      items   = c(
        "JT1993 모멘텀 — v10 파일럿 충실구현 grade F, 강화원장 L1 20/20 소진(exhausted)",
        "Novy-Marx 수익성/QMJ — paper_registry 기분석(analyzed) 계열과 동일논문"
      )
    ),

    list(
      heading = "산출물",
      type    = "kv",
      kv      = list(
        "라우팅 결과"     = "alpha_search_route_20260831.json",
        "데이터큐"        = "data_pipeline_queue.json (43건, +35)",
        "큐레이션 등재"   = "curated_routed.json 26건 (+11)",
        "다음 액션"       = "/alpha-search 로 큐 상단 1건 착수(대기 논문 대상)"
      )
    )

  ),

  footer = "v10 2계층 — 논문 수집=팩터전략 리서치 단일목적. 백테/등록 미실행."
)

cat("Telegram 발송 완료\n")
