# Judge Telegram Brief — WT-H20260513_001
# tg_agent_brief() 단일 진입점 사용 (v6 SOT)

suppressPackageStartupMessages({
  source(file.path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
                   "02_Infrastructure/telegram/telegram_notify.R"))
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-H20260513_001")

tg_agent_brief(
  agent = "Judge",
  title = "R05 꼬리위험 7단계 오버레이 5단계 — V2 안 조건부 admit 자격 (Architect 발동 요청)",
  charts = c(
    file.path(WT_DIR, "output/equity_curve.png"),
    file.path(WT_DIR, "output/oos_zoom_chart.png")
  ),
  sections = list(
    list(type = "text", emoji = "📚", heading = "연구 컨텍스트",
         body = paste(
           "[목적] STR_1715_AR_on_M4 위에 R05 꼬리위험 5단계 오버레이 추가.",
           "[방법] V1~V5 ex-ante 5변형 + V6 post-hoc 16그리드 백테스트.",
           "[결론] V2안 조건부 admit (샤프 1.9536, +0.205pp 점증).",
           sep = "\n"
         )),
    list(type = "kv", emoji = "📊", heading = "핵심 비교",
         kv = list(
           `2안 샤프지수` = "1.9536",
           `6안 샤프지수 (부적격)` = "2.0237",
           `기준 샤프지수` = "1.7486",
           `2안 최대낙폭` = "-24.81%",
           `2안 연복리수익률` = "41.50%",
           `다중검정 t값 2안 / 6안` = "6.77 / 7.01",
           `디플레이티드 샤프 N=5` = "Z=1.45 PASS",
           `봉인 후 엄격 샤프지수` = "2안 2.92 (n=11)",
           `표본내외 비율 2안` = "1.87배"
         )),
    list(type = "text", emoji = "⚖️", heading = "Judge 판정",
         body = paste(
           "S6 게이트 18/18 PASS (4 전제조건 충족 시).",
           "AX-001 v2: N/A 순수 오버레이 (Kritzman 2011).",
           "AX-008: 1/3 → 2/3 → 3/3 Architect 발동 필수.",
           sep = "\n"
         )),
    list(type = "text", emoji = "🤖", heading = "Codex 처분 (7건)",
         body = paste(
           "REJECT veto=false / HIGH 5 + MEDIUM 2.",
           "1 ACCEPT (Lockbox n=11 strict 재산출).",
           "4 PARTIAL (request 가중치 / Harvey FF5 / AX-008 / artifact).",
           "2 REBUTTAL_PRIMARY (DSR ex-ante + AX-001 v2 N/A).",
           sep = "\n"
         )),
    list(type = "text", emoji = "🎯", heading = "다음 단계",
         body = paste(
           "P1 Architect 독립 재현 발동 필수 (4-decimal).",
           "P2 KR FF5 + Carhart-4 회귀 (Architect).",
           "P3 가중치 한계 도훈 결정 ([0,0.15] vs [0,0.20]).",
           "P4 Lockbox strict 재산출 완료 (V2 샤프 2.92).",
           "V6안: DEFER 후 6개월 prospective.",
           sep = "\n"
         )),
    list(type = "text", emoji = "🔧", heading = "환경",
         body = paste(
           "📚 산출: judge_verdict.json + judge_challenge_note.md + judge_lockbox_audit_strict.json + Codex Round 5단계 ALL COMPLETE",
           "Codex 모델: gpt-5.5 + xhigh reasoning effort (taking 47초)",
           sep = "\n"
         ))
  )
)
