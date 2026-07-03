# alpha-search queue consumer — run 20260625 operator brief (queue drained, 0 executed)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent    = "AlphaSearch",
  title    = "alpha-search 큐 가동 (팩터에서 모드까지)",
  relaxed       = TRUE,
  force         = TRUE,
  decode_jargon = FALSE,
  smart_break   = FALSE,
  sections = list(
    list(emoji = "📊", heading = "런 요약 (20260625)", type = "text",
      body = paste0(
        "신규 testable 팩터가 없어 이번 런 자동실행 0편입니다. ",
        "누적 후보 2건은 직전 런에서 모두 소비 완료(done), ",
        "MAX_ALPHA 2 상한에도 대상이 없어 날조 없이 종료합니다.")),
    list(emoji = "📥", heading = "큐 상태", type = "bullet", items = c(
      "2606.08569 p_index 다운사이드 보험료 팩터 — 06-20 처리 완료(done)",
      "2606.04576 ReSGA 사이즈 꼬리위험 상호작용 — 06-21 처리 완료(done)",
      "route 신규 testable 0건, 20260625 신규 큐 파일 부재")),
    list(emoji = "⚠️", heading = "직전 처리분 verdict (참고)", type = "bullet", items = c(
      "2606.08569 quarantine: robustness와 fidelity FAIL, 실현 PORT_t NW lag3 마이너스 2.76",
      "2606.04576 quarantine: 양방향 모두 FAIL, POS 방향 PORT_t 마이너스 2.81",
      "두 건 모두 L-code 미적립이며 자본 미반영 상태로 정상 처리"))
  ),
  footer = "큐 소진 상태. 신규 적재 시 다음 런이 자동 소비합니다. batch_434 가드 준수, 날조 없음."
)
