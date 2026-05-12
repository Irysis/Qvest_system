## Forge Telegram brief — WT-D20260508_009
suppressMessages({
  source("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")
})

result <- tg_agent_brief(
  agent = "Forge",
  title = "WT-D20260508_009 백테 완료 — 4 통합 비율 정량 비교 + mitigation 실측",
  as_of = "2026-05-08",
  sections = list(
    list(emoji = "📊", heading = "Hybrid 4 비율 256m 실측 SR (PerformanceAnalytics)",
         type = "table",
         df = data.frame(
           ratio = c("A 0% PG2", "B 10% admit", "C 20% admit", "D 30% admit"),
           SR_CAGR_MDD = c("1.68 / 29.9% / -20.3%", "1.65 / 27.4% / -20.7%",
                            "1.60 / 24.9% / -21.2%", "1.54 / 22.5% / -21.6%")
         ),
         max_col_width = 24L,
         notes = c("BAB 비중 증가 시 SR 단조 감소 (4.85pp 격차)",
                   "비용 정정 (15bps→30bps round-trip) 후도 invariance 유지",
                   "회전율 ann 116/105/95/84%")),
    list(emoji = "🔧", heading = "Mitigation 4-way 비교 (Optimizer option d 채택)",
         type = "table",
         df = data.frame(
           method = c("M0 monthly", "M1 quarterly", "M2 buffer", "M3 3M MA *"),
           SR_MDD_TOann = c("0.48 / -51.1% / 1037%", "0.40 / -45.7% / 482%",
                             "0.45 / -54.2% / 900%", "0.41 / -46.1% / 493%")
         ),
         max_col_width = 24L,
         notes = c("M3 채택 — option_d 사전등록 + density 1.0 유지",
                   "회전율 1037%→493% Hurdle 600% PASS",
                   "Codex C1 ex-post selection 인정 + 결론 invariance")),
    list(emoji = "💡", heading = "Optimizer 추정 vs Forge 실측 격차",
         type = "bullet",
         items = c(
           "Standalone: Optimizer SR 1.999 (fwd) vs Forge 0.479 — 4.2× 격차",
           "Hybrid w=0.30: Optimizer 1.918 vs Forge 1.535 — 0.382pp 격차",
           "원인 = 위험모형 sigma 8.51% vs 실측 28.28% (집중 과세 비반영)",
           "Verdict: NOT_FABRICATION (factor model concentration under-estimate)")),
    list(emoji = "🛡️", heading = "AX-001 v2 conditional defense 실측",
         type = "table",
         df = data.frame(
           ratio = c("A 0%", "B 10%", "C 20%", "D 30%"),
           crisis_alpha_MDD_relief = c("+0.0231 / +4.85pp", "+0.0238 / +4.41pp",
                                          "+0.0246 / +3.98pp", "+0.0254 / +3.55pp")
         ),
         max_col_width = 22L,
         notes = c("BAB admit 시 crisis_alpha 단조 ↑ but MDD relief 단조 ↓",
                   "axis 2/3 PASS, bad/normal IC ratio defect (alpha 재spawn 시 보완)")),
    list(emoji = "🚨", heading = "Codex Critic Round REJECT — 우려 8건 disposition",
         type = "bullet",
         items = c(
           "심각 1건: 사후 mitigation 선택 method-shopping (포트폴리오 결론 invariance)",
           "고우려 5건: standalone MDD breach / lockbox 부재 / 5스펙 회귀 부재 / 비용 정정 / 위험모형 조건수",
           "보통 2건: 위기-정상 IC 비율 결손 / alpha snapshot vs 시계열 패널",
           "분류: 인정 또는 부분인정 8건 / 반박 0건 / 결론 변동 없음",
           "verdict: 검증 삼각측량 2-source REJECT (Forge + Codex critic 일치)")),
    list(emoji = "🎯", heading = "Forge 주요 권고 = 편입 거부 PG2 baseline 유지",
         type = "bullet",
         items = c(
           "근거: 4 비율 모두 정보비율 단조 감소 + Codex critic 동의",
           "옵션 A: 사이클 종료 미편입 (Forge + Codex 일치 권고)",
           "옵션 B: Architect spawn 3rd source + 10% 최소 편입 + lockbox + 5스펙 회귀",
           "옵션 C: Iter 2 알파 재설계 신규 사이클 (universe 확장 / sleeve 조정)"))
  ),
  charts = c(
    "stage_artifacts/WT-D20260508_009/forge/charts/equity_curve.png",
    "stage_artifacts/WT-D20260508_009/forge/charts/oos_zoom_chart.png"
  ),
  footer = "→ Next: Judge Agent or Q-Lead direct close"
)

if (!is.null(result$ok) && result$ok) {
  cat(sprintf("[Telegram] Sent OK | %d bytes\n", result$bytes %||% 0))
} else {
  cat(sprintf("[Telegram] FAIL: %s\n", result$error %||% "unknown"))
}
