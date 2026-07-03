## Paper-router v2 텔레그램 브리핑 — 2026-06-26 (외부 .R; 단일줄 source 호출용)
suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))

sections <- list(
  list(type = "summary", emoji = "\U0001F4E5",
       body = "arxiv 34편: alpha2 opt7 risk7 regime4 skip14 · testable 팩터 0 · curated 신규 0"),

  list(type = "bullet", heading = "\U0001F9EA alpha-search autorun (AUTORUN=1, MAX_ALPHA=2)",
       items = c(
         "실행 0건 — route=alpha∧kr_feasible 후보 0, testable 팩터 0 (날조 금지: skip)",
         "후보 #27 위상 이상치 점수=intraday 틱 필요 / #33 실적일 뉴스센티=대체데이터 → 둘 다 infeasible")),

  list(type = "bullet", heading = "\U0001F50D route 무관 발굴 팩터 (testable)",
       items = c(
         "testable 0건 — 이번 batch는 optimizer/risk/regime 방법론·LLM벤치·크립토·미시구조 위주",
         "충실 재구성으로도 KR 월간 long-only 단면 신규 신호 추출분 없음 (정직 보고)")),

  list(type = "bullet", heading = "\U0001F4CB optimizer/risk/regime 큐 적재 (후속 dispatch 소비)",
       items = c(
         "optimizer 7: BAVAR-BLED regime+fat-tail / Anticipatory Portfolio Opt / Asymmetry PRISM engine",
         "risk 7: Reverse Stress Testing multivariate / Forward SVaR GPR-HS / Universal VaR superadditivity",
         "regime 4: Continuous Cash-Overlay V-shape crash brake / Continuous HMM regime-conditional VaR"))
)

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "Research-Source Routing + Factor Mining (2026-06-26)",
  sections = sections,
  relaxed = TRUE,
  force = TRUE,
  lock_scope = "paper_router_20260626"
)
cat("TG_RESULT_OK=", isTRUE(res$ok %||% res), "\n", sep = "")
