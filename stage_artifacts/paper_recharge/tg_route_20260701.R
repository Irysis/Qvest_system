## Paper Router v2 — 텔레그램 브리핑 (2026-07-01). 외부 .R + source 패턴(인라인 멀티라인 -e 금지).
suppressWarnings(suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R")))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "리서치 소스 배분 + 팩터 마이닝 (2026-07-01)",
  as_of = "2026-07-01",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = "paper_router_20260701",
  sections = list(
    list(emoji = "📊", heading = "소스 배분 (arxiv 40 / curated 0 신규)",
         type = "text",
         body = paste(
           "route: alpha 1 · optimizer 8 · risk 8 · regime 5 · skip 18.",
           "팩터후보 7건 flag — testable 0 (전부 redundant/infeasible).",
           "오늘 batch = 포트구성·리스크·LLM·이론 편중, 신규 횡단면 알파 0.",
           "alpha-search autorun 0 (날조 금지 — batch_434 가드 준수).", sep = "\n")),
    list(emoji = "🔭", heading = "팩터 마이닝 verdict (route 무관)",
         type = "bullet",
         items = c(
           "Roll Implied Spread (Liquidity Audit) → REDUNDANT (L08_Roll_Spread 기등재, 유동성 44팩터 포화)",
           "Hurst/rough-vol GL (Efficient Market States) → REDUNDANT (Hurst 모멘텀 06-21 FALSIFIED)",
           "Trend Strength (Critical Phenomena) → REDUNDANT (모멘텀 M 32팩터)",
           "Vol·Volume·Return SMAR → REDUNDANT (L32/L44/CR02/D-vol군)",
           "AI Beta (AI Premium) → INFEASIBLE (OpenRouter 토큰소비 alt-data)",
           "ESG TODIMSort → INFEASIBLE (KR ESG 데이터 부재)")),
    list(emoji = "⚖️", heading = "Optimizer 큐 (α̂ 고정 A/B 후속)",
         type = "bullet",
         items = c(
           "Decision Geometry of Covariance Estimation for GMVP under Heavy Tails",
           "MVO in Ambiguous Markets with Learning (ambiguity-averse)",
           "BAVAR + Elliptical Black-Litterman (regime + heavy-tail)",
           "Benchmarking Deep TS Models for Equity Portfolios (배포-조정 constrained layer)",
           "외 4: RL risk-sensitive·Which Portfolios·Anticipatory·ESG 2-stage")),
    list(emoji = "🛡️", heading = "Risk·Regime 큐 (분석 flag)",
         type = "bullet",
         items = c(
           "risk: Hidden Dependence Tail Risk·Tempered Skew-t·SMAR·Forward SVaR(GPR-HS) 외",
           "regime: Continuous Cash-Overlay Filters (※max-cash combine 06-26 FALSIFIED)",
           "regime: Leakage-Aware Macro Nowcast Factor Ranking (PIT-aware 매크로→팩터 타이밍)",
           "regime: Continuous HMM heavy-tail + regime-VaR")),
    list(emoji = "📥", heading = "산출",
         type = "text",
         body = paste(
           "alpha_search_route_20260701.json / mode_queue_20260701.json",
           "curated_routed last_run→20260701 (신규 0).", sep = "\n"))
  ),
  footer = "➡️ paper_research_dispatch.R 가 optimizer/risk/regime 큐 소비"
)
cat("TG_OK=", isTRUE(res$ok), " bytes=", ifelse(is.null(res$bytes), NA, res$bytes),
    " err=", ifelse(is.null(res$error), "", as.character(res$error)), "\n", sep="")
