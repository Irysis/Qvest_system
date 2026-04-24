#!/usr/bin/env Rscript
# Judge Telegram v2 — WT-D20260424_002 Pilot 4 재전송
# v1 plain text ASCII 표가 모바일 proportional font에서 어긋남 → HTML <pre> 표로 재전송

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

source("02_Infrastructure/telegram/telegram_notify.R")

WT_DIR <- "qepm/mailbox/worktask/WT-D20260424_002"
BT_DIR <- file.path(WT_DIR, "backtest_result")
verdict <- fromJSON(file.path(WT_DIR, "judge_verdict.json"), simplifyVector = FALSE)

# ── Header (HTML) ────────────────────────────────────────────────────────────
hdr <- paste0(
  "⚖️ <b>[Judge] Pilot 4 RAPC Breadth-Constrained — GRADE_C</b>\n",
  "🎯 WT-D20260424_002 · Task #26 Optimizer 제약 실증\n",
  "📅 as_of 2026-04-24 · disposition <b>CONDITIONAL_PROGRESS</b>"
)

# ── Table 1: Gate 결과 (mobile-safe compact 2-column + bullet notes) ─────────
gates <- list(
  list(name = "A PIT",           verdict = "PASS",       note = "C1~C15 + lockbox sealed"),
  list(name = "B ISOLATION",     verdict = "PASS",       note = "hash match / Sigma w=1 / n<=20"),
  list(name = "C NET_ALPHA",     verdict = "COND_FAIL",  note = "SR 0.491 / IC 0.0318"),
  list(name = "D CROWDING",      verdict = "FAIL",       note = "Market 48% (>40%)"),
  list(name = "E CONCENTRATION", verdict = "PASS",       note = "n=15 / HHI 0.074 / maxw 0.08"),
  list(name = "F DRIFT/OOS",     verdict = "MIXED_PASS", note = "lockSR 0.774 / actIR -1.31")
)
gate_block <- paste0(
  "📊 <b>Gate 결과 (3 PASS · 1 COND · 1 MIXED · 1 FAIL)</b>\n",
  tg_format_gate_block(gates)
)

# ── Table 2: Portfolio Construction (Task #26 효과) ──────────────────────────
pc_df <- data.frame(
  Metric  = c("n_names", "HHI", "max_w"),
  Pilot3  = c("8",     "0.170", "0.20"),
  Pilot4  = c("15",    "0.074", "0.08"),
  Delta   = c("+7",    "-56%",  "-60%"),
  Verdict = c("PASS",  "PASS",  "PASS"),
  stringsAsFactors = FALSE
)
pc_tbl <- tg_format_table(pc_df)
pc_block <- paste0("🏗️ <b>Portfolio Construction (Grinold 정상화 ✅)</b>\n", pc_tbl)

# ── Table 3: Absolute Performance ────────────────────────────────────────────
perf_df <- data.frame(
  Metric   = c("Full SR", "Full CAGR", "Full MDD", "Train SR", "Val SR"),
  Pilot3   = c("0.282", "6.00%",  "-44.59%", "0.275", "0.317"),
  Pilot4   = c("0.491", "9.25%",  "-36.83%", "0.576", "0.130"),
  Delta    = c("+74%",  "+3.25pp", "+7.76pp", "+109%", "-59%"),
  Verdict  = c("PASS",  "PASS",   "PASS",    "PASS",  "REGRESS"),
  stringsAsFactors = FALSE
)
perf_tbl <- tg_format_table(perf_df)
perf_block <- paste0("📈 <b>Absolute Performance (절대 진전 · Val drift 악화)</b>\n", perf_tbl)

# ── Table 4: Lockbox OOS (Judge helper NEW) ──────────────────────────────────
oos_df <- data.frame(
  Metric     = c("Lockbox SR", "Lockbox CAGR", "Lockbox MDD",
                 "Active IR", "Alpha vs BM", "oos_is_ratio"),
  Pilot3     = c("n/a",  "n/a",    "n/a",     "-1.003",  "-18.79pp", "n/a"),
  Pilot4     = c("0.774","17.14%", "-34.17%", "-1.311",  "-20.40pp", "4.241"),
  Verdict    = c("PASS", "PASS",   "BELOW",   "WORSE",   "WORSE",    "PASS"),
  stringsAsFactors = FALSE
)
oos_tbl <- tg_format_table(oos_df)
oos_block <- paste0("🔒 <b>Lockbox OOS (2024-01-23 ~ 2026-01-23, Judge helper 단일 access)</b>\n", oos_tbl)

# ── Key Insight ──────────────────────────────────────────────────────────────
key_block <- paste0(
  "💡 <b>[KEY INSIGHT] Task #26 breadth 제약 3축 검증</b>\n",
  "(1) ✅ Portfolio construction — Grinold breadth 정상화 (n/HHI/maxw 3/3)\n",
  "(2) ✅ Absolute performance — 절대 SR +74% / MDD 완화 7.76pp / 록박스 OOS CAGR 17.14%\n",
  "(3) ❌ Active management — BM 대비 초과수익 생성 실패 (IR -1.003 → -1.311 악화)\n",
  "\n",
  "🧭 <b>결론: &quot;Breadth cannot save weak alpha&quot;</b>\n",
  "Optimizer 제약은 과집중을 교정했으나 alpha 신호 자체의 약점은 해결 불가.\n",
  "Pilot 3에서 확인했던 Val&gt;Train drift 회피 실증도 Pilot 4에서 재역전 (L-191 RE-EMERGENCE)."
)

# ── L-code + AX + Next Actions ───────────────────────────────────────────────
tail_block <- paste0(
  "📚 <b>L-code &amp; Axiom</b>\n",
  "  • <b>L-193</b> BREADTH_CANNOT_SAVE_WEAK_ALPHA 등재\n",
  "  • <b>L-191</b> RE-EMERGENCE (Val SR 0.130 &lt;&lt; Train SR 0.576)\n",
  "  • AX-002 ✅ · AX-007 부분완화 · AX-008 ✅ (3-source PASS)\n",
  "\n",
  "🚀 <b>차기 Action</b>\n",
  "  1. Task #26 breadth 제약 → production 패턴으로 승격\n",
  "  2. Pilot 5 → Market hedge overlay (beta 0.8 또는 KOSPI200 short)\n",
  "  3. Alpha sprint → RAPC composite 강화 (accrual QoQ · PEAD D1/D30/D60 · BH/BY)\n",
  "  4. 구조 연구 → AX-007 예외지대 (multi-sleeve / 50+ 분산 / ML sizing)\n",
  "  5. methodology_active.md L-191 재등록"
)

msg <- paste(hdr, gate_block, pc_block, perf_block, oos_block,
             key_block, tail_block, sep = "\n\n")

cat("[_judge_telegram_v2] Sending rich HTML message...\n")
tg_send_rich(msg, emoji_min = 5L)

# ── Charts (기존 2건 재전송) ────────────────────────────────────────────────
full_chart <- file.path(BT_DIR, "equity_curve_full.png")
oos_chart  <- file.path(BT_DIR, "equity_curve_oos.png")

if (file.exists(full_chart)) {
  cat("[_judge_telegram_v2] Sending full equity chart...\n")
  tg_send_photo(full_chart,
                caption = "📈 [Judge P4] Full Equity Curve (2012~2026, lockbox 포함)")
} else {
  cat("[_judge_telegram_v2] WARN: full_chart missing\n")
}

if (file.exists(oos_chart)) {
  cat("[_judge_telegram_v2] Sending lockbox OOS chart...\n")
  tg_send_photo(oos_chart,
                caption = "🔒 [Judge P4] Lockbox OOS (2024-01-23 ~ 2026-01-23) — SR 0.774 / CAGR 17.1% / Active IR -1.31")
}

cat("[_judge_telegram_v2] DONE\n")
