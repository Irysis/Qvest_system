setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "논문 라우터 v2 — 20260809 배분 완료",
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "paper_router_20260809",
  sections = list(
    "📋 배분 요약" = paste0(
      "• 소스 A (arxiv): 33개 후보 (20260808과 동일 배치)\n",
      "• 소스 B (curated): 15개 전부 기처리 → 신규 없음\n",
      "• 라우트 분류: alpha 2 · optimizer 4 · risk 3 · regime 2 · skip 22\n",
      "• 팩터 후보: 2개 발굴 / 1개 testable / 1개 autorun"
    ),
    "🔭 AUTORUN 결과 — within_sector_reversal" = paste0(
      "논문: arXiv:2608.05755 (Döbelt, LSTM sector embeddings)\n",
      "팩터: 섹터-중립 단기역전 signal_i = -(r_i - sector_avg_r)\n\n",
      "📊 성과: SR 0.147 / CAGR 4.23% / MDD 60.43% / IC 0.0271\n",
      "📊 FMB NW_t 1.01 (미유의) / OOS retention -0.49 / Calmar 0.07\n",
      "📊 FF3 alpha -3.48%/yr (t=-1.21)\n\n",
      "🔴 판정: QUARANTINE (Grade F) — L3 robustness FAIL\n",
      "원인: 섹터-중립 선형 처리 → 고변동 구간 비선형 동조 미제거 / long-only MDD 구조 결함 해소 불가\n",
      "방향성은 있음(IC+0.027, 스트레스 2/4 우세: GFC+9.3% · EuDebt+22.0%)\n\n",
      "📌 next_probe 2건 등재:\n",
      "• FQ-167: 저변동 국면 조건부(3분위 하단 활성)\n",
      "• FQ-168: 오버레이 리스크 신호 소비(하위 25% long 축소)"
    ),
    "📂 mode_queue 배포 (optimizer/risk/regime)" = paste0(
      "optimizer ⭐: Policy-Distance Certificates (2608.05901) · Conformal Kelly⚠️OOS (2608.01494)\n",
      "risk ⭐: Proper-score filters (2608.02828) · AI Governance crowding (2608.02311)\n",
      "regime: Stationary Ambiguity (2608.04832) · TF시스템 이론⚠️paper_exhausted (2607.19497)\n",
      "→ 소비: paper_research_dispatch.R 자동 (morning_run)"
    ),
    "🚫 paper_exhausted" = paste0(
      "2607.19497 (Trend-Following Systems):\n",
      "spec_mass_lowfreq (20260727 C) + T_RetAutoCorr (20260802 F) + SpectralPersistence_Hurst (20260808 C)\n",
      "= 3회 standalone QUARANTINE → 논문 closed\n",
      "단 FQ-153 (시장 레벨 Hurst 오버레이 타이밍) frontier_open 유지"
    ),
    "🔢 FQ 업데이트" = paste0(
      "신규 등재: FQ-167 · FQ-168 (within_sector_reversal next_probe)\n",
      "FQ-152 (Markov_PredVolRank) · FQ-153 (Hurst overlay) 기등재 확인\n",
      "frontier 총 172개 항목"
    )
  )
)
cat("[router tg] sent\n")
