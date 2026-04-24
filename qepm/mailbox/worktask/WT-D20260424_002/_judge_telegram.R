#!/usr/bin/env Rscript
# Judge Telegram — WT-D20260424_002 Pilot 4 RAPC Breadth-Constrained
# Pilot 3 vs Pilot 4 비교 + Lockbox OOS 차트 2건

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

source("02_Infrastructure/telegram/telegram_notify.R")

WT_DIR <- "qepm/mailbox/worktask/WT-D20260424_002"
BT_DIR <- file.path(WT_DIR, "backtest_result")

verdict <- fromJSON(file.path(WT_DIR, "judge_verdict.json"), simplifyVector = FALSE)
oos <- fromJSON(file.path(BT_DIR, "oos_summary.json"), simplifyVector = FALSE)

# ---- Header ----
hdr <- paste0(
  "[Judge] Pilot 4 RAPC Breadth-Constrained - GRADE_C\n",
  "WT-D20260424_002 | Task #26 Optimizer 제약 실증\n",
  "as_of: 2026-04-24 | disposition: CONDITIONAL_PROGRESS"
)

# ---- Gate Summary ----
gs <- verdict$gate_summary
gate_block <- paste0(
  "Gate 결과 (6종)\n",
  "  A PIT           : PASS\n",
  "  B ISOLATION     : PASS\n",
  "  C NET_ALPHA     : CONDITIONAL_FAIL (SR 0.491 / rank_IC 0.0318)\n",
  "  D CROWDING      : FAIL (Market 48%)\n",
  "  E CONCENTRATION : PASS (n=15, HHI 0.074, max_w 0.08)\n",
  "  F DRIFT/OOS     : MIXED_PASS (lockbox SR 0.774 / active IR -1.31)\n",
  "  -> 3 PASS + 1 COND + 1 MIXED + 1 FAIL -> GRADE_C"
)

# ---- Pilot 3 vs Pilot 4 핵심 비교 ----
cmp_block <- paste0(
  "[CORE] Pilot 3 vs Pilot 4 비교\n",
  "---------------------------------------\n",
  "지표            Pilot3    Pilot4    변화\n",
  "---------------------------------------\n",
  "n_names            8        15      +7  PASS\n",
  "HHI             0.170    0.074     -56% PASS\n",
  "max_w            0.20     0.08     -60% PASS\n",
  "Full SR         0.282    0.491     +74% PASS\n",
  "Full CAGR       6.00%    9.25%    +3.25 PASS\n",
  "Full MDD      -44.59%  -36.83%    +7.76 PASS\n",
  "Val SR          0.317    0.130     -59% FAIL\n",
  "---------------------------------------\n",
  "[Lockbox OOS - Judge helper 실측]\n",
  "Lockbox SR      n/a      0.774   PASS\n",
  "Lockbox CAGR    n/a     17.14%   PASS\n",
  "Lockbox MDD     n/a    -34.17%   BELOW\n",
  "Active IR     -1.003   -1.311    악화 FAIL\n",
  "alpha vs BM  -18.79pp -20.40pp   악화 FAIL\n",
  "oos_is_ratio    n/a     4.241    PASS (>>0.7)"
)

# ---- 핵심 판결 ----
key_block <- paste0(
  "[KEY INSIGHT]\n",
  "Task #26 optimizer breadth 제약 효과:\n",
  "(1) Portfolio construction 3/3 PASS - n/HHI/max_w 모두 Grinold 기준 정상화\n",
  "(2) Absolute performance 개선 - 절대 SR/MDD 모두 진전\n",
  "(3) 그러나 Active management 악화 - BM 대비 초과수익 생성 실패 (IR -1.31)\n",
  "\n",
  "결론: 'Breadth가 weak alpha를 구할 수 없다.'\n",
  "Optimizer 제약은 과집중 교정은 해결, alpha 신호 자체는 미해결.\n",
  "L-191 Val>Train 회피 실증도 Pilot 4에서 재역전 (L-191 RE-EMERGENCE)."
)

# ---- L-code + Next ----
tail_block <- paste0(
  "[L-code] L-193 (BREADTH_CANNOT_SAVE_WEAK_ALPHA) 등재\n",
  "[AX] AX-002 PASS / AX-007 partial relief / AX-008 PASS (3-source)\n",
  "[Disposition] CONDITIONAL_PROGRESS - Pilot 4 admission 불가\n",
  "\n",
  "차기 Action:\n",
  "  1. Task #26 breadth 패턴 - production 패턴으로 승격 추천\n",
  "  2. Pilot 5 - market hedge overlay (beta 0.8 or KOSPI200 short)\n",
  "  3. Alpha sprint - RAPC composite 강화 (accrual QoQ, PEAD D1/D30/D60)\n",
  "  4. AX-007 예외지대 - multi-sleeve or 50+ 분산 or ML sizing\n",
  "  5. L-191 재등록 - methodology_active.md"
)

msg <- paste(hdr, gate_block, cmp_block, key_block, tail_block, sep = "\n\n")

cat("[_judge_telegram.R] Sending text...\n")
tg_send(msg)

# ---- Charts ----
full_chart <- file.path(BT_DIR, "equity_curve_full.png")
oos_chart  <- file.path(BT_DIR, "equity_curve_oos.png")

if (file.exists(full_chart)) {
  cat("[_judge_telegram.R] Sending full chart...\n")
  tg_send_photo(full_chart, caption = "[Judge P4] Full Equity Curve (2012~2026, lockbox 포함)")
} else {
  cat("[_judge_telegram.R] WARN: full_chart missing\n")
}

if (file.exists(oos_chart)) {
  cat("[_judge_telegram.R] Sending lockbox OOS chart...\n")
  tg_send_photo(oos_chart, caption = "[Judge P4] Lockbox OOS (2024-01-23~2026-01-23) — SR 0.774 / CAGR 17.1% / Active IR -1.31")
} else {
  cat("[_judge_telegram.R] WARN: oos_chart missing\n")
}

cat("[_judge_telegram.R] DONE\n")
