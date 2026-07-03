## Paper Router v2 — 텔레그램 브리핑 (2026-07-02). 외부 .R + source 패턴(인라인 멀티라인 -e 금지).
suppressWarnings(suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R")))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "리서치 소스 배분 + 팩터 마이닝 (2026-07-02)",
  as_of = "2026-07-02",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = "paper_router_20260702",
  sections = list(
    list(emoji = "📊", heading = "소스 배분 (arxiv 신규 1 / curated 신규 0)",
         type = "text",
         body = paste(
           "discovery 9건 중 8건 = 20260701 라우팅 재출현(180일 창). 신규 1건뿐.",
           "route(9건): opt 2·risk 1·regime 2·skip 4·alpha 0. testable 팩터 0.",
           "alpha autorun 0 (날조 금지 — batch_434 가드).", sep = "\n")),
    list(emoji = "🔭", heading = "신규 소스 verdict (팩터마이닝)",
         type = "bullet",
         items = c(
           "[NEW] GAMLSS/ZAGA 국면조건부 전략비교(2606.31251) → regime",
           "  ↳ 팩터 없음(지수-레벨 SVMP vs buy-hold 평가). RCMA discipline flag",
           "나머지 8건 = 20260701 라우팅 유지(재디스패치 X)")),
    list(emoji = "⚖️", heading = "큐 상태",
         type = "text",
         body = paste(
           "신규 큐 = regime 1건(31251, 분석 flag). opt/risk 신규 0.",
           "전일 큐는 dispatch.R 가 이미 소비.", sep = "\n")),
    list(emoji = "📥", heading = "산출",
         type = "text",
         body = paste(
           "alpha_search_route_20260702.json / mode_queue_20260702.json",
           "curated_routed last_run→20260702 (신규 0).", sep = "\n"))
  ),
  footer = "➡️ 오늘은 near-null day: 신규 횡단면 알파 0·testable 팩터 0. 정직 보고(합성 없음)."
)
cat("TG_OK=", isTRUE(res$ok), " bytes=", ifelse(is.null(res$bytes), NA, res$bytes),
    " err=", ifelse(is.null(res$error), "", as.character(res$error)), "\n", sep="")
