#!/usr/bin/env Rscript
# judge_send_tg.R — Judge S6 verdict telegram brief (v4 ENFORCE)

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260426_005")
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

verdict <- fromJSON(file.path(WT_DIR, "judge_verdict.json"))

# Build sections
gate_table <- data.frame(
  Gate = c("0 PIT", "1 Hard", "2 Harvey", "3 Hurdle", "4 Role", "5 AX", "6 Tail"),
  Verdict = c("PASS", "PASS", "FAIL", "FAIL", "RELABEL", "PASS", "FAIL"),
  Evidence = c("hash 4/4 intact",
                "max_w 0.20 / TO 471",
                "0/5 t<2.95 max=2.62",
                "SR 0.64 / DSR 1.89",
                "vol_reduction_diversifier",
                "AX-005 EXC + 008 3/3",
                "CVaR_d 0.0290>cap")
)

scenario_table <- data.frame(
  Scenario = c("A 100% Iter12", "B 60/20/20 Mix", "AB 80/20", "D PG2 Now"),
  SR = c(0.6448, 1.1995, 0.8731, 0.9345),
  CAGR = c(0.1264, 0.1927, 0.1479, 0.1423),
  MDD = c(-0.3881, -0.2884, -0.3452, -0.2482),
  Verdict = c("REJECT", "PROVISIONAL", "WEAK_REJ", "BASELINE")
)

cvar_table <- data.frame(
  Source = c("Forge proxy m/sqrt21", "Judge daily pre-LB", "Judge daily lockbox", "Cap"),
  CVaR_d = c(0.0243, 0.0290, 0.0307, 0.0250),
  Verdict = c("PASS_proxy", "FAIL_direct", "FAIL_direct", "threshold")
)

sections <- list(
  list(
    type = "kv", heading = "Verdict 핵심", emoji = "⚖️",
    kv = list(
      "Verdict" = "JUDGE_FAILED (standalone)",
      "Mix B 시나리오" = "PROVISIONAL_PASS (Governor 위임)",
      "Role 재라벨" = "vol_reduction_diversifier_low_alpha",
      "Triangulation" = "Forge+Codex+Judge 3/3 REJECT 수렴",
      "L-code" = "L-220 (제안)"
    )
  ),
  list(
    type = "table", heading = "Gate 0~6 판정", emoji = "🎛️",
    df = gate_table
  ),
  list(
    type = "table", heading = "Codex C1 daily CVaR 재구성", emoji = "🚩",
    df = cvar_table,
    notes = c("Forge monthly/sqrt(21) proxy = 0.0243 (PASS by 6.8bps)",
              "Judge harness 직접 daily reconstruction = 0.0290 (BREACH 40bps)",
              "Codex C1 PARTIAL → CONFIRMED")
  ),
  list(
    type = "table", heading = "시나리오 비교 (240m same-period)", emoji = "🔍",
    df = scenario_table
  ),
  list(
    type = "bullet", heading = "Gate FAIL 사유", emoji = "🚨",
    items = c(
      "Gate 2 Harvey 0/5 specs t<2.95 (max 2.62) — alpha 실재하나 통계적 미약",
      "Gate 3 Hurdle FAIL: SR 0.64 < 0.8 / CAGR 12.6 < 16 / DSR_post 1.89 < 3.0 floor",
      "Gate 6 daily CVaR_d 0.0290 > cap 0.025 (Codex C1 confirmed)",
      "Gate 4 Role 재라벨: 'core' claim → 실측 'vol_reduction_diversifier_low_alpha'",
      "novelty_bonus 비대칭 (Iter11 0.20 < 0.3 ✓ but MEGA 0.57 ≥ 0.5 ✗) → Grade A_NOVEL DENIED"
    )
  ),
  list(
    type = "bullet", heading = "Lockbox 24-26 OOS triangulation", emoji = "🔒",
    items = c(
      "Forge OOS monthly SR=1.346, CAGR=29.26%, MDD=-19.55%",
      "Judge harness daily SR=1.540, CAGR=34.92%, MDD=-23.61%",
      "SR diff 0.194 < tol 0.30 ✓ within tolerance",
      "단 lockbox CVaR_d 0.0307도 cap 위반 — vol overlay tail suppress 실패",
      "Pre-LB walk-forward 213 sig_dates 검증 ✓ single-snapshot 위험 LOW"
    )
  ),
  list(
    type = "bullet", heading = "Mix Scenario B (60/20/20) provisional", emoji = "✨",
    items = c(
      "60% Iter12 + 20% Iter11 + 20% STR_1699: SR 1.1995 / DSR_post 4.47 / Harvey t 5.29",
      "현 PG2 (D_baseline SR 0.93) 대비 +28.5% lift",
      "Iter12-Iter11 cor 0.20 — complementary diversifier value 입증",
      "단, STR_1699 = STR_1656 proxy (ML 트레일 부재) → Governor stage 검증 필요",
      "Sequential Admission TDC vs PG2_v3.0 미측정 — admission rule 적용 불가"
    )
  ),
  list(
    type = "bullet", heading = "다음 액션", emoji = "➡️",
    items = c(
      "Governor 위임 ① Mix Scenario B sequential admission TDC 측정",
      "Governor 위임 ② STR_1656 trail 복구 시도 (실패 시 STR_1699 proxy 명시 유지)",
      "Q-Lead 결정 ③ Replacement A 폐기 — Iter11 Monthly LinTilt PG2 우위 유지",
      "L-220 적립 — high-machinery overlay 전략 = pre-LB Harvey gate 필수",
      "Scout/Forge 재작업 ④ Iter13 후보: TO 줄이는 monthly+linear (not quarterly)"
    )
  )
)

cat("[judge_send_tg] dispatching telegram...\n")
result <- tg_agent_brief(
  agent = "Judge",
  title = "WT-D20260426_005 Iter12 STR_1702 Final",
  sections = sections,
  charts = c(
    file.path(WT_DIR, "backtest_result/equity_curve.png"),
    file.path(WT_DIR, "backtest_result/oos_zoom.png"),
    file.path(WT_DIR, "backtest_result/scenario_comparison.png")
  ),
  footer = "judge_v6.1 multi-gate + lockbox harness + Codex C1 daily reconstruction"
)
cat(sprintf("[judge_send_tg] result: ok=%s\n", isTRUE(result$ok)))
str(result, max.level = 1)
