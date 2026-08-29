source("02_Infrastructure/telegram/telegram_notify.R")
tg_agent_brief(
  agent = "AlphaSearch",
  title = "논문 라우팅 20260827+20260828",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = "paper_router_20260828",
  sections = list(
    list(header = "결과",
         body   = "27(21편): alpha2 opt2 risk4 regime1 skip12\n28(9편): alpha2 regime1 skip6\ntestable 4건"),
    list(header = "Testable 팩터",
         body   = "lead_lag_mcp_cluster conf0.55\nletf_closing_reversal conf0.65\nrank_diversity_momentum conf0.55\nxgb_tabnet_regime_ens conf0.55"),
    list(header = "산출",
         body   = "route_20260827/28.json\nmode_queue_27(o2 r4 g1) / mode_queue_28(g1)")
  )
)
