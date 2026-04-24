#!/usr/bin/env Rscript
# Judge Pilot 9 Telegram Brief — tg_agent_brief SOT
suppressPackageStartupMessages({
  source("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")
})

OUT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/stage_artifacts/WT_D20260424_007"

result <- tg_agent_brief(
  agent = "Judge",
  title = "WT-D20260424_007 Pilot 9 GRADE_C / CONDITIONAL_REFRAME + FF3 R² 36.1%",
  sections = list(
    list(
      heading = "Gate A~F 판정",
      body = paste(
        "A PIT: <b>PASS</b> (C1/C13/C14/C15)",
        "B ISO: <b>PASS</b> (역할 경계 준수)",
        "C NET_α: <b>FAIL</b> (FF3 α월 0.28% / t=0.533, Val SR -0.293)",
        "D CROWDING: <b>PASS</b> (market 28.1% / unique 98.1%)",
        "E CONC: <b>PASS_BORDERLINE</b> (N=16, HHI 0.091)",
        "F DRIFT: <b>FAIL</b> (Val -0.293 / Lock Active IR -0.71)",
        "G TAIL: <b>BORDERLINE</b> (Full MDD -48.6% / Lock MDD -17.3%)",
        sep = "\n"
      )
    ),
    list(
      heading = "FF3 Attribution 정의 명확화",
      body = paste(
        "<b>Alpha Agent 94.6%</b> = IC-level retention (IC 시계열 FF3 IC 투영)",
        "<b>Judge 63.9%</b> = Return-level retention (실수익률 FF3 투영)",
        "→ 둘 다 다른 metric. Alpha 해석+Forge 의심 모두 부분적 타당.",
        "",
        "Return-level R²:",
        "• Full:    0.361 (retention 63.9%)",
        "• Train:   0.488 (style 절반 복제)",
        "• Lockbox: 0.076 (retention 92.4% ← OOS style-decoupled)",
        "• FF5:     0.405 / Carhart4: 0.375",
        "• FF3 α t: 0.533 (유의 없음)",
        "",
        "<b>아이러니</b>: Train 복제 + Lockbox 독립. Pilot 9 α는 OOS에서 진짜 α지만 magnitude 부족.",
        sep = "\n"
      )
    ),
    list(
      heading = "4-Pilot Lockbox 비교",
      body = paste(
        "| Pilot | β | Active IR |",
        "| P6 MinVar_BH | ~1.0 | ~-1.94 |",
        "| P7 MinVar_BH | ~1.0 | ~-1.94 |",
        "| P8 MinVar_BS | 1.022 | -1.942 |",
        "| <b>P9 ERC</b>   | 0.884 | <b>-0.71</b> (+1.23) |",
        "",
        "<b>Lockbox Regime</b> (Pilot 9):",
        "• RISK_ON (92d): Active IR -4.26 ← 핵심 underperform",
        "• NEUTRAL (142d): -0.45",
        "• CAUTION (172d): -1.01",
        "• <b>CRISIS  (61d): +3.92</b> ← 예상 외 defense alpha 획득",
        sep = "\n"
      )
    ),
    list(
      heading = "L-198 β 철학 FINAL Verdict",
      body = paste(
        "<b>REJECTED_WITH_NUANCE</b>",
        "• β=1.022 (P8) → Active IR -1.942",
        "• β=0.884 (P9) → Active IR -0.71",
        "→ <b>저β가 오히려 성과 향상</b>",
        "→ β 상승 ≠ α 증폭. 가설 실증 실패.",
        "→ L-198 CLOSE.",
        sep = "\n"
      )
    ),
    list(
      heading = "L-196 최종 Status + L-197 재정의",
      body = paste(
        "<b>L-196 PARTIALLY_REFUTED</b>",
        "4 pilot: MinVar 3 + ERC 1. MinVar universal supremacy 깨짐.",
        "단 α-aware MVO 0/4 선택 → 아키텍처 실패가 더 근본적.",
        "",
        "<b>L-197 v2 (3-way bottleneck)</b>:",
        "(a) min_names=15~20 breadth 제약",
        "(b) HIGH tier α uniform + Σ noise로 MVO degenerate",
        "(c) MinVar/ERC의 low-vol 자연 선호",
        "→ Risk-parity family가 현실적 해.",
        sep = "\n"
      )
    ),
    list(
      heading = "Pilot 10 권고 방향",
      body = paste(
        "<b>Primary: MULTI_SLEEVE (AX-007 예외지대)</b>",
        "• Core sleeve (Consensus RAPC) 10종",
        "• Defense sleeve (Q25/R16) 10종",
        "• Regime-weighted: CRISIS → defense overweight",
        "",
        "<b>Secondary: NEW_ALPHA_FAMILY</b>",
        "• Consensus RAPC 4연속 Lockbox fail → archive 검토",
        "• Low-freq macro + quality + tail-hedge 3-axis",
        "",
        "<b>금지</b>: β 조작 재시도, α-aware MVO 단독",
        sep = "\n"
      )
    ),
    list(
      heading = "신규 L-code",
      body = paste(
        "• <b>L-199</b>: FF3 retention IC-level vs Return-level 정의 불일치 표준화",
        "• <b>L-198_final</b>: β amplification REJECT",
        "• <b>L-197_v2</b>: 3-way bottleneck (α × Σ × breadth)",
        "• <b>L-200</b>: Consensus RAPC CRISIS alpha 획득 (multi-sleeve 후보)",
        sep = "\n"
      )
    )
  ),
  charts = c(
    file.path(OUT, "equity_curve_full.png"),
    file.path(OUT, "equity_curve_oos.png")
  ),
  footer = "🤖 Judge Opus 4.7 | AX-002 Lockbox first+only access | dispatch SOT"
)

stopifnot(isTRUE(result$ok))
cat("[Judge] Telegram dispatch OK\n")
