setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "논문 라우터 v3 — 20260824",
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "paper_router_20260824",
  sections   = list(
    list(
      name = "라우팅 결과",
      body = "alpha 0 / optimizer 0 / risk 0 / regime 0 / skip 18 / redundant 15 (총 33편)\nmcp_discovery 33편 전량 기처리 또는 기발신"
    ),
    list(
      name = "redundant 15편",
      body = paste0(
        "done_queue 4: 2608.20020/16749/12283/14323\n",
        "이전라우트 11: opt 08/23 6 + risk 08/23 3 + alpha 08/20~22 1 + risk 08/20~22 1"
      )
    ),
    list(
      name = "infeasible 18편",
      body = "LLM/DeFi/보험수학/이론/intraday 계통 — KR RAWDATA로 구현 불가"
    ),
    list(
      name = "큐레이션 처리",
      body = "curated_health_20260824: 15편 전량 curated_routed.json 기등재 — 신규 없음"
    ),
    list(
      name = "mode_queue 20260824",
      body = "optimizer: 0 / risk: 0 / regime: 0 — 신규 dispatch 없음\nschema_version: paper_router_v2 (평면 형태)"
    ),
    list(
      name = "미해결 항목",
      body = paste0(
        "2608.12634 Price of Permission (alpha 08/20~22) — 3회 라우팅됐으나 handoff 미포함\n",
        "수동 확인 필요: alpha_search_handoff 필터링 기준 재검토"
      )
    )
  )
)

cat("Telegram sent OK\n")
