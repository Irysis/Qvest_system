suppressWarnings(suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R")))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "alpha-search 큐 가동 (팩터→모드)",
  relaxed = TRUE,
  force = TRUE,
  sections = list(
    list(emoji = "📭", heading = "큐 상태 (2026-06-26): 실행 0편",
         type = "bullet",
         items = c(
           "신규 testable 팩터 없음 — 가동 0편",
           "testable 누적 2건(2606.08569 p_index · 2606.04576 size×tail) 전부 소비완료(done)",
           "오늘 라우터(0626): alpha 라우팅 2편이나 둘 다 infeasible → 큐 미적재",
           "tier-2 recheck 0623~0626: testable 승격 0건")),
    list(emoji = "🔌", heading = "판정",
         type = "bullet",
         items = c(
           "마지막 고리(큐 소비자) 정상 가동·날조 없음",
           "상류(tier-1/2) testable 공급 시 즉시 alpha-search 5층 가동",
           "현재 공급 고갈(starved) — 알파 산출물 없음"))
  )
)
cat("TG_RESULT ok=", isTRUE(res$ok), "\n", sep="")
