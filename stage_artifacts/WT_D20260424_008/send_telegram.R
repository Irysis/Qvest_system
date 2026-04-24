#!/usr/bin/env Rscript
# Judge Pilot 10 Telegram via tg_agent_brief SOT
suppressPackageStartupMessages({
  source("02_Infrastructure/telegram/telegram_notify.R")
  library(data.table)
})

title <- "WT-D20260424_008 Pilot 10 GRADE_C / OVERLAY_NEGATIVE"

# Gate A~F summary table
gates_df <- data.frame(
  Gate = c("A PIT", "B ISO", "C NET_α", "D CROWD", "E CONC", "F DRIFT", "G TAIL"),
  Verdict = c("PASS", "PASS", "FAIL", "PASS", "PASS_BL", "FAIL", "FAIL_NEG"),
  Note = c("C5 t-1 MRS lag",
           "Alpha/Risk/Opt hash 100% match",
           "ΔActive IR -0.189",
           "Pilot 9 상속",
           "N=16, HHI 0.09",
           "-0.71→-0.90",
           "MDD -17.28→-17.95"),
  stringsAsFactors = FALSE
)

# Lockbox overlay comparison
lb_df <- data.frame(
  Metric = c("SR", "CAGR %", "MDD %", "Active IR", "α ann %"),
  Pilot9 = c("1.05", "23.40", "-17.28", "-0.710", "-15.15"),
  Pilot10 = c("0.95", "19.63", "-17.95", "-0.899", "-18.53"),
  Delta = c("-0.10", "-3.77pp", "-0.67pp", "-0.189", "-3.37pp"),
  stringsAsFactors = FALSE
)

# Regime decomposition Lockbox
reg_df <- data.frame(
  Regime = c("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS"),
  N = c(92, 142, 172, 61),
  Base_IR = c("-4.26", "-0.45", "-1.01", "+3.92"),
  Overlay_IR = c("-4.40", "-0.64", "-1.17", "+3.54"),
  Delta = c("-0.14", "-0.19", "-0.16", "-0.38"),
  stringsAsFactors = FALSE
)

# Layer breakdown Lockbox (monthly)
layer_df <- data.frame(
  Layer = c("Layer 1 (MRS<30)", "Layer 2 (30~60)", "Layer 3 (≥60 3m)"),
  Months = c(15, 9, 0),
  Days = c(355, 132, 0),
  Pct = c("72.9%", "27.1%", "0.0%"),
  MeanFw = c("1.000", "0.819", "N/A"),
  stringsAsFactors = FALSE
)

sections <- list(
  list(type = "table", heading = "Gates A~F (Judge Verdict)",
       df = gates_df, emoji = "⚖️"),
  list(type = "table", heading = "Lockbox Overlay 효과 (핵심)",
       df = lb_df, emoji = "🔒"),
  list(type = "table", heading = "Regime Decomposition (baseline vs overlay)",
       df = reg_df, emoji = "🌪️"),
  list(type = "table", heading = "Lockbox Layer Breakdown",
       df = layer_df, emoji = "🛡️"),
  list(type = "text", heading = "핵심 해석 — STR_1631 overlay 원리 ablation",
       body = paste(
         "① Lockbox max MRS 54.94 < Layer 3 threshold 60 → Layer 3 미발동 (overlay의 핵심 defense mechanism 무력)",
         "② Layer 2 (MRS 30~60) 27.1% 구간에서 fw 0.58~0.92 cash hedge 적용 → BM 상승 구간(2024-09 등)과 겹쳐 drag 초래",
         "③ CRISIS regime Active IR +3.92 → +3.54: Earnings-consensus α의 의외 crisis-selectivity를 overlay가 9.7% 희석",
         "④ 모든 4-regime 악화 (overlay decay = α magnitude 감소, not variance reduction)",
         "⑤ STR_1631 SYN_05 overlay도 동일 위험 — scalar cash on single-sleeve core α는 α decay 경로",
         sep = "\n"),
       emoji = "💡"),
  list(type = "text", heading = "L-code 신설 + Pilot 11 방향",
       body = paste(
         "L-201: Monthly 3-Layer MRS Overlay Lockbox NEGATIVE (Consensus α 부적합)",
         "L-202: Overlay 검증은 regime 실존 구간에서만 유효 (Lockbox-Train composition 불일치)",
         "L-196 v3 candidate: Single-sleeve에서 제어 개입은 α magnitude 희석 (Pilot 6~10 5-way 실패 패턴)",
         "AX-009 candidate: Scalar cash overlay는 defense 아님. Asset-swap multi-sleeve 필요.",
         "",
         "Pilot 11 방향: AX-007 Multi-sleeve (Core Consensus 10종 + Defense Q25/R16 10종)",
         "Allocation: MRS<30 Core100 / 30~60 C70+D30 / ≥60 3m C30+D70",
         "Rejected: HRP_SCORE (weight eng 한계) + Overlay tuning (composition 문제 해결 못함)",
         sep = "\n"),
       emoji = "➡️")
)

result <- tg_agent_brief(
  agent = "Judge",
  title = title,
  sections = sections,
  as_of = "2026-04-24",
  footer = "Judge Opus 4.7 | Pilot 10 Lockbox Overlay Ablation | v6.1 schema"
)

stopifnot(isTRUE(result$ok))
cat("✅ Telegram sent OK\n")
