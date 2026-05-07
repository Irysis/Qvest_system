# ============================================================================
# Cycle 8 — Risk Telegram brief
# ============================================================================
# v6 SOT: tg_agent_brief() 단일 진입점, 4섹션 권장
# (summary / table / bullet / bullet)
# ============================================================================

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent = "Risk",
  title = "Risk Cycle 8 — Stambaugh 3-source 통합 retest TERMINATE",
  sections = list(
    list(type = "summary",
         body = "Stambaugh 2015 RFS post-publication 3-source 정량 완료. 종료 권고 — 정식 lifecycle 진입 시점."),
    list(type = "table", emoji = "🔬", heading = "3-source 감쇠율 (decay rate) 정량",
         df = data.frame(
           소스     = c("AR", "TSMOM", "KR10y"),
           감쇠율   = c("36.9%", "25.5%", "77.5%"),
           반감기   = c("190m", "64m", "159m")
         )),
    list(type = "bullet", emoji = "🛡️", heading = "베이지안 사후분포 + 미래 경로",
         items = c("Bayesian posterior μ=0.44 σ=0.08 95% CI [0.28, 0.60] — Stambaugh 11 anomaly base rate 0.56 within CI",
                   "Hybrid 60m 미래 SR 1.71→1.36 (-20.3% 감쇠) — 도훈 SR 2.0 목표 gap 0.29→0.64 악화",
                   "3-source 감쇠 혁신 무상관 (max |cor| 0.15) + Student-t copula 자유도 20.2 가우시안 한계 + TDC ≈ 0 — Hybrid 차원 분산 효과 유효",
                   "TSMOM 출판일(2012) 데이터 부재 → mid-sample 2018-12 proxy 사용 — Stambaugh 정식 framework 미충족 caveat")),
    list(type = "bullet", emoji = "🚩", heading = "리스크 신호 + Codex 처리",
         items = c("KR10y 감쇠 77.5% — 6/1 발효 시 15% 배분 critical (사이클 5 76% → 8 77.5% 정합)",
                   "AR Mann-Kendall tau -0.27 p<0.001 (사이클 7) + 사이클 8 pre/post 감쇠 36.9% 정합",
                   "Codex 8건 우려 (HIGH 7 + MEDIUM 1) — ACCEPT 5 + PARTIAL_REBUTTAL 2 + ACCEPT_via_creation 1. 합리화 표현 0건",
                   "consecutive 8 cycles Codex REJECT — meta path saturation 결정적. 정식 risk-research lifecycle WT 진입 의무"))
  )
)
