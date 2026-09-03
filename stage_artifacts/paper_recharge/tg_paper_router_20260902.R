
# Paper Router v4 — 2026-09-02 텔레그램 발송

root <- Sys.getenv("QM_ROOT")
if (nchar(root) == 0) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/config.R"))
source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "[1계층] 논문 트리아지",
  relaxed = TRUE,
  glossary = TRUE,
  lock_scope = "paper_router_20260902",
  force = TRUE,

  sections = list(

    list(
      heading = "쉬운 설명",
      type    = "text",
      body    = paste0(
        "오늘 arxiv 재크롤 243건 전량이 과거 이력 paper_key 와 일치 — 고정 쿼리 재검색 구조상 ",
        "동일 상위-관련도 논문 재부상. 진짜 신규 0건. 큐레이션 CSV 는 경로 부재로 처리 0건."
      )
    ),

    list(
      heading = "처리 요약",
      type    = "kv",
      kv      = list(
        "소스 합계"   = "arxiv 243 + curated 0(CSV 부재)",
        "testable"    = "0건",
        "redundant"   = "243건 (과거 alpha_search_route_*.json 이력 + paper_registry.json + queue_done paper_key 대조 전량 일치)",
        "data_pipeline_required" = "0건",
        "skip(내용)"  = "0건 (모두 이력 대조로 판정 — 신규 내용판정 불필요)"
      )
    ),

    list(
      heading = "인프라 관찰",
      type    = "bullet",
      items   = c(
        "paper_registry.json 이 MCP 재발견 항목에 정규화 paper_key(axv:...)를 여전히 채우지 않음 — 어제(20260901) 세션과 동일 병리, 미수정",
        "config/paper_recharge_sources.csv 경로 자체가 이 세션 트리에서 확인 안 됨 — curated 소스 신규 유입 없음(별도 확인 필요, harness 쓰기 범위 밖)"
      )
    ),

    list(
      heading = "산출물",
      type    = "kv",
      kv      = list(
        "라우팅 결과"   = "alpha_search_route_20260902.json",
        "데이터큐"      = "data_pipeline_queue.json (변동 없음)",
        "다음 액션"     = "/alpha-search 로 강화원장 L1 active entry 우선 확인 → 없으면 큐 상단 1건 착수(오늘 신규 후보 없음)"
      )
    )

  ),

  footer = "v10 2계층 — 논문 수집=팩터전략 리서치 단일목적. 백테/등록 미실행."
)

cat("Telegram 발송 완료\n")
