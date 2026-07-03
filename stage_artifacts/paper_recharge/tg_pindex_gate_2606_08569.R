# Telegram brief — alpha-search 큐 가동 (p-index 2606.08569) 게이트 결과
suppressWarnings(suppressMessages({ library(data.table) }))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "alpha-search 큐 가동 (팩터→모드)",
  as_of = "2026-06-20",
  relaxed = TRUE, force = TRUE,
  sections = list(
    list(type = "text", emoji = "\U0001F4DA", heading = "큐 소비",
         body = paste0("testable 큐 1건 실행(상한 2). 논문 'p-index Approach'(2606.08569) — ",
                       "종목별 다운사이드 풋-보험료 횡단면 팩터. 방향은 LOW(저보험료 롱) 단일 사전확약 ",
                       "— 논문이 보고한 시장간 부호불안정 때문에 A/B 동시채점(스윕)은 회피.")),
    list(type = "kv", emoji = "\U0001F4C8", heading = "실측 성과 (LOW, 등급 C)",
         kv = list("연복리(초과)" = "3.4% (-8.2%p)", "샤프" = "0.20",
                   "정보비율" = "-0.62", "최대낙폭" = "56.7%", "회전율" = "연 734%")),
    list(type = "bullet", emoji = "\U0001F50E", heading = "5층 검증 verdict",
         items = c("L1 PIT: 통과(미래참조 없음)",
                   "L2 계약: 통과(audit WARNING·FAIL 0)",
                   "L3 견고성: ⚠️FAIL — 권위 essence(OOS·PORT_t) 미산출(등급C·screen 경로 부재), proxy OOS는 공허",
                   "L4 충실성(독립검증): ⚠️FAIL — 엔진은 p-index 레벨정렬이라 논문의 효율/모멘텀 2x2 명명전략과 불일치 + 원문 PDF 검증불가",
                   "L5 게이트: ⚠ QUARANTINE (실패축 robustness,fidelity / fail-closed)")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "결론·조치",
         items = c("양방향 long-only 모두 KR alpha 부재(HIGH도 등급F MDD66.7%) — 논문 SSE↔SP500 부호불안정 KR 재현",
                   "batch_434 날조 없음·PIT clean·KR 성립(옵션데이터 불요) 확인",
                   "QUARANTINE이므로 L-code 적립 보류(active 원장서 제외, 감사보존)",
                   "skip 없음 · 큐 소비 완료(queue_done)"))
  ),
  footer = "➡ 후속: 논문 2x2 효율전략 충실복제 + 전체 PDF 확보 후 인간검토")
)
cat(sprintf("[TG] ok=%s err=%s bytes=%s\n",
            isTRUE(res$ok), res$error %||% "none", res$bytes %||% "?"))
