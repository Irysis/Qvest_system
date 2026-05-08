#==============================================================================
# send_telegram_brief.R — WT-D20260508_002 Alpha-research FINAL brief
# v6 SOT: tg_agent_brief() 단일 진입점 (Hook deny others)
#==============================================================================

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))

result <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260508_002 ALPHA_DONE — DISCOVERY_FAIL_REJECTED (Codex 8 concerns ACCEPT)",
  sections = list(
    list(
      emoji = "📌",
      heading = "Summary",
      type = "text",
      body = paste(
        "ML residual cross-section 2차 시도. Empirical PASS (IC 0.291 SR 2.45) 그러나 Codex REJECT.",
        "8 concerns 중 4 HIGH (PIT-C1 factor pre-selection / PIT-C10 universe same-month / TO 805% hard fail / DSR multi-trial) ACCEPT 동의.",
        "AX-002 / AX-007 / AX-008 모두 FAIL post-Codex.",
        "WT_001 (VRP) 정합 패턴 — KR top universe alpha discovery에서 empirical 강세 + process integrity 동시 달성 구조적 어려움."
      )
    ),
    list(
      emoji = "📊",
      heading = "Key metrics",
      type = "table",
      df = data.frame(
        Item = c("Empirical IC", "ICIR", "Harvey-t (NW)", "DSR (single)", "DSR strict est",
                 "Long Net SR", "Turnover ann", "PIT corrected IC est"),
        Value = c("0.2909", "2.4361", "17.40", "17.76", "13.65 (multi-trial)",
                  "2.45", "8.05 (805% > 600% hard fail)", "0.087~0.20 (L-228 deflation 30~60%)"),
        stringsAsFactors = FALSE
      ),
      max_col_width = 25L
    ),
    list(
      emoji = "🚩",
      heading = "Codex REJECT 8 concerns disposition",
      type = "bullet",
      items = c(
        "C1 PIT-C1 HIGH ACCEPT — top80 factor selection at 2024-12 coverage applied backward (Lopez de Prado 2018)",
        "C2 PIT-C10 HIGH ACCEPT — universe / Admin / 20d TV same-month + 2e8 → 5e7 floor relax",
        "C3 AX-007 HIGH ACCEPT — turnover 805% > 600% Hurdle Gate v2.2 hard fail",
        "C4 RF-A6 HIGH PARTIAL — DSR single-test, strict 13.65 still PASS but caveat insufficient",
        "C5/C6/C7/C8 MEDIUM ACCEPT — forward signal / sector-neutral rerun / lineage / MLP fabrication",
        "Auto-rationalization 3 (Codex auto-detect): conservative / GPU minimal / interpret conservatively → 모두 ACCEPT 정량 정정",
        "agent_agree_with_codex = TRUE 8/8, REBUTTAL 0건"
      )
    ),
    list(
      emoji = "➡️",
      heading = "Next actions (Q-Lead 결정 의무)",
      type = "bullet",
      items = c(
        "Auto-escalate trigger 작동: AX hard FAIL 3 (AX-002+007+008) + PIT-C1 violation 2건",
        "Priority 1: PIT-rework v5 ML residual (rolling factor selection + universe t-1 + 2e8 floor + TO≤600% + strict DSR + sector-neutral ICIR + forward 2026-05 signal + MLP 정정)",
        "Priority 2: VKOSPI direct via KRX OpenAPI (WT_001 carry, ~3-5h fetch)",
        "Priority 3: Defensive_LowVol_KR multi-sleeve EXCLUSION (AX-005 v1.2)",
        "Priority 4: Commodity Gold/Copper KR ETF",
        "Priority 5: IPCA latent factor Kelly-Pruitt-Su 2019 JFE"
      )
    ),
    list(
      emoji = "🔧",
      heading = "Compute + 도훈 GPU 명시 disposition",
      type = "bullet",
      items = c(
        "Compute 47.97 min / 16-core CPU / 72272 panel rows × 81 features × 136 month",
        "도훈 RTX 4080 SUPER 16GB 명시 받음. nvidia-smi verified hardware OK.",
        "torch::cuda_is_available()=FALSE / xgboost device='cuda' CPU fallback WARNING — R 패키지 CPU-only build (CRAN binary 한계)",
        "CUDA toolkit 12.6 가용. 후속 architect WT — R xgboost source build + R torch CUDA reinstall 권고",
        "본 WT data scale (3k rows × 81 features per month) GPU benefit 0.5x~1.5x range 추정 (small data init overhead). full-panel single-train 72k rows는 5x+ 가능"
      )
    )
  ),
  as_of = "2026-05-08",
  footer = "alpha-research / Charter v1.7 §10 Codex Round / Honest empirical FAIL — PIT integrity > strong empirics"
)

cat("Telegram brief result:\n")
str(result)
