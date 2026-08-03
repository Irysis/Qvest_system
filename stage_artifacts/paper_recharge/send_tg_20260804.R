source("02_Infrastructure/telegram/telegram_notify.R")

sections <- list(
  list(header = "실행 요약",
       body = "실행: 0편 / MAX_ALPHA: 2\n큐 n=0, recheck n=0\narXiv 8월 공백 (주말 제출분 미등재)"),
  list(header = "처리 결정",
       body = paste(
         "2607.01377 -> batch_434 QUARANTINE",
         "  (Kyle lambda = tick 데이터 미보유)",
         "2607.29583 -> skip (순수 이론)",
         "2607.24410 -> risk-research agent",
         "2607.18001 -> optimizer-research agent",
         sep = "\n"
       )),
  list(header = "FQ 확인",
       body = "FQ-002: IC t=1.97 리드 -> WT-013 대기 (QEPM)\nFQ-004: T1 감사의견 수집 완료 -> 재료별 필터 미측정"),
  list(header = "next_probe",
       body = paste(
         "FQ-002 WT-013: 계약금액/시총 분모 신규 라운드",
         "FQ-004: T1 감사의견 비적정 exclusion delta",
         "FQ 신규: CV_Vol (일별 거래량 변동계수)",
         sep = "\n"
       ))
)

tg_agent_brief(
  agent = "AlphaSearch",
  title = "alpha-search 큐 가동 (20260804) -- 실행 0편",
  sections = sections,
  relaxed = TRUE,
  force = TRUE
)
