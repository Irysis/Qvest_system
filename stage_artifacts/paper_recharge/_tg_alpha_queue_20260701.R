# alpha-search 큐 소비자 — 빈 큐 정직 보고 (2026-07-01 런)
suppressWarnings(suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R")))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "alpha-search 큐 가동 (팩터→모드)",
  relaxed = TRUE,
  force = TRUE,
  sections = list(
    list(type = "kv", emoji = "\U0001F4E5", heading = "큐 상태",
         kv = list(
           "타겟 날짜" = "2026-07-01",
           "미소비 testable" = "0편",
           "이번 런 실행" = "0편 (MAX_ALPHA=2)"
         )),
    list(type = "bullet", emoji = "\U0001F50E", heading = "사유(실측)",
         items = c(
           "오늘 라우터(0701) deep-route 7건 verdict = redundant×4 / infeasible×2(AI_Beta·ESG) / uncertain×1(BodyTail_Leg) → testable 0건",
           "alpha_search_queue_20260701.json 미생성(testable=0) · tier-2 recheck testable 승격 0건",
           "전체 누적 testable = {2606.08569 p_index, 2606.04576 ReSGA size×tail} 2건뿐, 둘 다 done·QUARANTINE 완료"
         )),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "조치",
         items = c(
           "batch_434 가드 준수 — 날조 금지, 팩터 합성 안 함 (uncertain→testable 자가승격 안 함)",
           "L-code 적립 0 · quarantine append 0 · done 변동 0",
           "다음 소비는 tier-1이 신규 testable 적재 후 자동 가동"
         ))
  ),
  footer = "consumer no-op · book 불변 · governor 정지"
)
cat("TG_OK=", isTRUE(res$ok), "\n", sep = "")
