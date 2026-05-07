# =============================================================================
# Cycle 5 — Telegram brief (v6 SOT)
# =============================================================================

source("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Risk",
  title = "Risk Cycle 5 — PG2 사전 시뮬레이션 TERMINATE",
  sections = list(
    list(
      type = "summary",
      body = "PG2 70/15/15 6월 1일 발효 24일 전 시간 projecting forward simulation 5축 완료. TSMOM + KR_10y 60m SR decay 결정적 발견. 정식 lifecycle 진입 권고."
    ),
    list(
      type = "table",
      emoji = "🔬",
      heading = "5축 시간 projecting 핵심 결과",
      df = data.frame(
        축       = c("axis_1", "axis_4", "axis_5"),
        지표     = c("h12m 심각드리프트", "TSMOM 60m 감쇠", "AX-001 v2"),
        값       = c("64.7%", "32%", "PASS_MARGINAL")
      )
    ),
    list(
      type = "bullet",
      emoji = "🚩",
      heading = "P1 즉시 alert (이미 임계 돌파)",
      items = c(
        "TSMOM 60m 샤프지수 0.59 vs 전기간 0.87 = 32% 감쇠. 만-켄달 p<1e-9 + Pettitt 변화점 p<1e-12. Stambaugh-Yu-Yuan 2015 RFS publication 후 anomaly 감쇠 framework 정합 - 이미 경고 임계 30% 돌파",
        "KR_10y 채권 ETF 60m 샤프지수 0.07 vs 전기간 0.30 = 76% 감쇠. 만-켄달 p<1e-10 + Pettitt 변화점 p<1e-9. 이미 임계 임계 50% 돌파. 한국 통화정책 normalization 영향",
        "AX-001 v2 Test 3 marginal (위기 -0.485 vs 정상 -0.477 = 0.008 차이). 정식 alpha-research bootstrap CI + IC 비율 직접 측정 의무"
      )
    ),
    list(
      type = "bullet",
      emoji = "📊",
      heading = "monitoring 인계 5건 권고",
      items = c(
        "P1 TSMOM + KR_10y 60m 샤프지수 매월 측정 의무 (이미 경고 임계 돌파)",
        "P2 AX-001 v2 3-test 24개월 rolling 재검증 의무",
        "P3 BULL 진입 시 추적오차 별도 임계 (0.063 vs pooled 0.065)",
        "P4 실현 vs 예측 비율 매월 [0.5, 1.5] 임계 알람",
        "P5 DCC-GARCH 1-step pair 상관계수 0.50 초과 시 알람"
      )
    ),
    list(
      type = "bullet",
      emoji = "⚠️",
      heading = "Codex 사이클 5 검토",
      items = c(
        "REJECT (veto=false). HIGH 7 + MEDIUM 3. 사이클 1~5 5 consecutive REJECT 패턴",
        "메타 path saturation 결정적 증거. 정식 lifecycle 진입 권고: alpha-research + risk-research + optimizer-research WT spawn",
        "AX-008 검증 1/3 (Forge OK + Codex REJECT + Architect NA). 정식 lifecycle Architect 검증 의무"
      )
    )
  )
)

cat("Telegram brief sent.\n")
