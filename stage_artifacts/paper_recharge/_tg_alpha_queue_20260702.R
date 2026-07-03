# alpha-search 큐 소비자 — 빈 큐 정직 보고 (2026-07-02 런)
suppressWarnings(suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R")))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "alpha-search 큐 가동 (팩터→모드)",
  relaxed = TRUE,
  force = TRUE,
  sections = list(
    list(type = "kv", emoji = "\U0001F4E5", heading = "큐 상태",
         kv = list(
           "타겟 날짜" = "2026-07-02",
           "미소비 testable" = "0편",
           "이번 런 실행" = "0편 (MAX_ALPHA=2)"
         )),
    list(type = "bullet", emoji = "\U0001F50E", heading = "사유(실측)",
         items = c(
           "오늘 라우터(0702) 신규 1건(2606.31251)=지수레벨 전략평가법(횡단면 종목신호 부재) → route=regime · n_factor_testable=0",
           "carried 8건은 0701에서 이미 소비 · alpha_search_queue_20260702.json 미생성(testable=0)",
           "전체 누적 testable = {2606.08569 p_index, 2606.04576 ReSGA size×tail} 2건뿐 · 둘 다 done·QUARANTINE(port_t -2.76 / -2.81, robustness FAIL)"
         )),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "조치",
         items = c(
           "batch_434 가드 준수 — 팩터 날조/합성 안 함 · uncertain→testable 자가승격 안 함",
           "L-code 적립 0 · quarantine append 0 · done 변동 0",
           "다음 소비는 tier-1이 신규 testable 적재 후 자동 가동"
         ))
  ),
  footer = "consumer no-op · book 불변 · governor 정지"
)
cat("TG_OK=", isTRUE(res$ok), "\n", sep = "")
