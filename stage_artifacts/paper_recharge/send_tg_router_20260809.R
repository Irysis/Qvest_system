setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "논문 라우터 v2 — 20260809 배분 + AUTORUN 완료",
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "paper_router_20260809",
  sections = list(
    list(
      emoji   = "📋",
      heading = "배분 요약 (MAX_ALPHA=2, AUTORUN=1)",
      type    = "bullet",
      items   = c(
        "소스 A (arxiv): 33개 후보 (20260808과 동일 배치 — prev_report 동일)",
        "소스 B (curated): 15개 전부 기처리 → 오늘 신규 없음",
        "라우트: alpha 2 · optimizer 4 · risk 3 · regime 2 · skip 22",
        "팩터 후보 2개 발굴 / testable 1개 / autorun 실행 1건"
      )
    ),
    list(
      emoji   = "🔭",
      heading = "AUTORUN — within_sector_reversal (arXiv:2608.05755)",
      type    = "kv",
      kv      = list(
        "팩터"        = "signal_i = -(r_i - sector_avg_r) · 섹터-중립 단기역전",
        "판정"        = "QUARANTINE (Grade F) — L3 robustness FAIL",
        "SR / CAGR"   = "0.147 / 4.23%",
        "MDD / Calmar" = "60.43% / 0.07 (HARD FAIL)",
        "OOS retention" = "-0.49 (FAIL)",
        "IC"          = "+0.0271 (포지티브 비율 57.4%)",
        "FMB NW_t"    = "1.01 (미유의 — short-leg 신호 본질 시사)",
        "FF3 alpha"   = "-3.48%/yr (t=-1.21)",
        "스트레스"    = "GFC +9.3% · EuDebt +22.0% 우세 / COVID -3.5% · Rate -0.4% 열세",
        "기전"        = "섹터-중립 선형 처리 → 고변동 구간 비선형 동조 미제거. 고회전(968%/yr) 비용 부담"
      )
    ),
    list(
      emoji   = "📌",
      heading = "next_probe & FQ 등재",
      type    = "bullet",
      items   = c(
        "FQ-167: 저변동 국면 조건부(3분위 하단) — 섹터-중립 역전 × 변동성 필터",
        "FQ-168: 오버레이 리스크 신호 소비 — 스코어 하위 25% long 축소 트리거",
        "paper_exhausted: 2607.19497 closed (3회 QUARANTINE). FQ-153 Hurst 오버레이는 frontier_open 유지",
        "2608.05755: 1회 시도 (within_sector_reversal). industry_momentum 미시도 → paper NOT exhausted"
      )
    ),
    list(
      emoji   = "📦",
      heading = "mode_queue 배포 — optimizer/risk/regime 소비자용",
      type    = "bullet",
      items   = c(
        "optimizer ⭐: Policy-Distance Certificates (2608.05901) · Conformal Kelly (2608.01494, ⚠OOS FAIL)",
        "risk ⭐: Proper-score GAS filters (2608.02828) · AI Governance crowding (2608.02311)",
        "regime: Stationary Ambiguity (2608.04832) · TF Systems (2607.19497, paper_exhausted 기록)",
        "→ paper_research_dispatch.R 자동 소비 (morning_run)"
      )
    )
  )
)

cat("[send_tg_router_20260809] Done.\n")
