
# Paper Router v4 — 2026-09-01 텔레그램 발송

root <- Sys.getenv("QM_ROOT")
if (nchar(root) == 0) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/config.R"))
source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "[1계층] 논문 트리아지",
  relaxed = TRUE,
  glossary = TRUE,
  lock_scope = "paper_router_20260901",
  force = TRUE,

  sections = list(

    list(
      heading = "쉬운 설명",
      type    = "text",
      body    = paste0(
        "오늘 arxiv MCP 재크롤 243건 중 242건이 어제(20260831) 이전 라우팅 이력과 paper_key 로 ",
        "그대로 일치했습니다 — 30개 고정 쿼리를 매일 재검색하는 구조라 상위-관련도 논문이 ",
        "그대로 재부상한 것입니다. 진짜 신규는 1건뿐이고, 큐레이션 클래식 시드 26건은 전량 ",
        "기처리(20260822) 확인됐습니다."
      )
    ),

    list(
      heading = "처리 요약",
      type    = "kv",
      kv      = list(
        "소스 합계"   = "arxiv 243 + curated 0(신규, 26건 전량 기처리)",
        "testable"    = "1건 → route=replication",
        "redundant"   = "242건 (과거 alpha_search_route_*.json 이력 paper_key 대조 일치)",
        "data_pipeline_required" = "0건",
        "skip(내용)"  = "0건 (모두 이력 대조로 판정 — 신규 내용판정 불필요)"
      )
    ),

    list(
      heading = "신규 후보",
      type    = "text",
      body    = "⭐ Volatility Cointegration Overlay (2509.23533) — 종목·지수 변동성 공적분(HVR/DVR) + VECM 예측, 일별 OHLCV 만으로 재구성 가능한 리스크오버레이 축"
    ),

    list(
      heading = "인프라 관찰",
      type    = "bullet",
      items   = c(
        "paper_registry.json 이 MCP 재발견 항목에 정규화 paper_key(axv:...)를 채우지 않음(null 또는 title-hash) — 스펙상 1차 대조(paper_key/duplicate_of)만으로는 이 중복을 못 잡음",
        "오늘은 과거 alpha_search_route_*.json 전체 이력 대조로 보강해서 잡음 — registry 정규화는 별도 인프라 항목(이 세션에서 미수정, harness 쓰기 범위 밖)"
      )
    ),

    list(
      heading = "산출물",
      type    = "kv",
      kv      = list(
        "라우팅 결과"   = "alpha_search_route_20260901.json",
        "데이터큐"      = "data_pipeline_queue.json (변동 없음)",
        "다음 액션"     = "/alpha-search 로 강화원장 L1 active entry 우선 확인 → 없으면 큐 상단 1건(대기 replication 후보) 착수"
      )
    )

  ),

  footer = "v10 2계층 — 논문 수집=팩터전략 리서치 단일목적. 백테/등록 미실행."
)

cat("Telegram 발송 완료\n")
