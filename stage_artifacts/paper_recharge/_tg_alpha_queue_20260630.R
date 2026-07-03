# alpha-search 큐 소비자 — 빈 큐 정직 보고 (2026-06-30 런)
suppressWarnings(suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R")))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "alpha-search 큐 가동 (팩터→모드)",
  relaxed = TRUE,
  force = TRUE,
  sections = list(
    list(type = "kv", emoji = "\U0001F4E5", heading = "큐 상태",
         kv = list(
           "타겟 날짜" = "2026-06-30",
           "미소비 testable" = "0편",
           "이번 런 실행" = "0편"
         )),
    list(type = "bullet", emoji = "\U0001F50E", heading = "사유(실측)",
         items = c(
           "큐+route 전체에서 verdict=testable = {2606.08569, 2606.04576} 2건뿐, 둘 다 done·QUARANTINE 완료",
           "2606.08569 p-index: KR 양방향 못이김(LOW IR -0.62 / HIGH grade-F) → QUARANTINE(06-20)",
           "2606.04576 ReSGA size×tail: POS PORT_t -2.81·NEG screen-FAIL → QUARANTINE(06-21)",
           "최신 tier-1 큐(06-26) candidates=[] (신선 KR 횡단면 testable 알파 희귀)"
         )),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "조치",
         items = c(
           "batch_434 가드 준수 — 날조 금지, 팬터 합성 안 함",
           "다음 소비는 paper_recharge tier-1이 신규 testable 적재 후 가능"
         ))
  ),
  footer = "consumer no-op · book 불변 · governor 정지"
)
cat("TG_OK=", isTRUE(res$ok), "\n", sep = "")
