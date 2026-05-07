# =============================================================================
# Cycle 6 — Telegram brief (도훈 결정 input 4 시나리오 비교 표)
# =============================================================================

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent = "Risk",
  title = "Risk Cycle 6 — PG2 4 시나리오 비교 진단 완료",
  sections = list(
    list(type = "summary",
         body = "사이클 5 P1 alert 후속 4 시나리오 비교 진단 완료. 도훈 결정 input 제공."),

    list(type = "table", emoji = "📊", heading = "4 시나리오 비교",
         df = data.frame(
           시나리오 = c("A retain", "B P1cut", "C P1part", "D P1subst"),
           샤프 = c("1.51", "1.45", "1.48", "1.61"),
           낙폭 = c("-15.7%", "-17.6%", "-18.4%", "-19.9%")
         )),

    list(type = "kv", emoji = "🔬", heading = "공리 검증 (AX-001 v2)",
         kv = list("Test 1 위기알파" = "4 모두 FAIL (n=1 COVID)",
                   "Test 2 낙폭완화" = "4 모두 PASS",
                   "Test 3 위기상관" = "4 모두 FAIL (cor_crisis>normal)",
                   "전체 평결" = "4 모두 PASS_1_OF_3")),

    list(type = "bullet", emoji = "🚩", heading = "핵심 발견",
         items = c("사이클 5 P1 alert는 source 단독 (TSMOM 32% / 국채 76% decay)",
                   "시나리오 종합 decay 4개 모두 음수 (recent stronger)",
                   "AR 70~80% dominance lever 정량 입증",
                   "Pareto trade-off: SR 우월(D) vs MDD 우월(A) 미해소",
                   "위기알파 검증 통계 power 부족 (n=1 COVID 단일)")),

    list(type = "bullet", emoji = "➡️", heading = "도훈 결정 input",
         items = c("샤프 우선: D > A > C > B",
                   "낙폭 우선: A > B > C > D",
                   "위기알파: 4 모두 FAIL → 정식 lifecycle 강화 의무",
                   "Codex 6 consecutive REJECT → 메타 path saturation",
                   "TERMINATE 권고 / 정식 alpha-research 진입"))
  ),
  footer = "📚 SOT: qepm/mailbox/research/risk_cycle6_20260507/risk_package.json"
)
