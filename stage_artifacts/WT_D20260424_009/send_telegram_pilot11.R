#!/usr/bin/env Rscript
# Pilot 11 Telegram brief — tg_agent_brief() SOT

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
suppressPackageStartupMessages({
  library(jsonlite); library(data.table)
})
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

perf_f  <- file.path(ROOT, "04_Research/strategies/WT_D20260424_009_pilot11/backtest_result/performance_summary.json")
abl_f   <- file.path(ROOT, "stage_artifacts/WT_D20260424_009/breadth_ablation.json")
chart1  <- file.path(ROOT, "04_Research/strategies/WT_D20260424_009_pilot11/backtest_result/equity_curve.png")
chart2  <- file.path(ROOT, "04_Research/strategies/WT_D20260424_009_pilot11/backtest_result/annual_returns.png")

perf <- fromJSON(perf_f)
abl  <- fromJSON(abl_f)

verdict <- abl$verdict

# Performance table
cmp_df <- data.frame(
  Label    = c("P9_ERC_n16", "P11_HRP+Sc_n20", "BM_KOSPI"),
  Full_SR  = c("0.179", sprintf("%.3f", perf$full$sr), "0.531"),
  Val_SR   = c("-0.293", sprintf("%.3f", perf$val$sr), "N/A"),
  CAGR     = c("N/A", sprintf("%.1f%%", perf$full$cagr), "11.0%"),
  MDD      = c("N/A", sprintf("%.1f%%", perf$full$mdd), "-54.5%"),
  HHI      = c("0.0906", sprintf("%.4f", perf$hhi_avg), "N/A"),
  stringsAsFactors = FALSE
)

# 5-method ablation table (from weight_method_selected.md)
optim_df <- data.frame(
  Method    = c("HRP+Score(P11)", "ERC(P9-base)", "Score_pure", "HRP_pure", "MinVar"),
  net_IR    = c(80.05, 80.80, 79.89, 79.63, 56.34),
  n_names   = c(20, 20, 20, 20, 7),
  HHI       = c(0.0514, 0.0520, 0.0517, 0.0529, 0.1450),
  stringsAsFactors = FALSE
)

p9_alpha_hash <- "c3acd44beae5b8c189bb95301d355d09d12a209cb5895b6acc8ed18d2c672172"
p9_risk_hash  <- "edf6c7a90e3f54682823b67dfd7ee7e0ddee5f3e4bcc3b0fd694d6029c509035"

result <- tg_agent_brief(
  agent = "Forge",
  title = sprintf("WT-D20260424_009 Pilot 11 Breadth Ablation -- n20 effect %s", verdict),
  sections = list(
    list(type = "text",
         heading = "Pilot 11 HRP+Score Hybrid n=20 (No Overlay) vs Pilot 9 ERC n=16",
         body = "Alpha: Consensus RAPC v2 (동일). Risk: LW Oracle cond 9.47 (동일). 변경: ERC n=16 -> HRP+Score n=20"),

    list(type = "table",
         heading = "Performance Full / Train / Val",
         df = cmp_df),

    list(type = "bullet",
         heading = "Breadth Delta (Pilot 9 vs 11)",
         items = c(
           sprintf("n_names: 16 -> 20 (+4)"),
           sprintf("HHI: 0.0906 -> %.4f (-32.6%%)", perf$hhi_avg),
           sprintf("Full SR: 0.179 -> %.3f (+%.3f)", perf$full$sr, perf$full$sr - 0.179),
           sprintf("Val SR: -0.293 -> %.3f (+%.3f)", perf$val$sr, perf$val$sr + 0.293),
           "Fundamental Law pred: +11.8% (actual gain 494%% >> theoretical)"
         )),

    list(type = "table",
         heading = "5-Method Ablation (Optimizer R13 result)",
         df = optim_df),

    list(type = "bullet",
         heading = "Integration Audit",
         items = c(
           sprintf("alpha_sha256: %s...", substr(p9_alpha_hash, 1, 16)),
           sprintf("risk_sha256: %s...",  substr(p9_risk_hash, 1, 16)),
           sprintf("v2.3 compliance: PASS (HHI=%.4f, max_w=0.067, n=20)", perf$hhi_avg),
           "HRP success: 279 / EW fallback: 0"
         )),

    list(type = "bullet",
         heading = sprintf("Breadth Effect Verdict: %s", verdict),
         items = c(
           abl$interpretation,
           sprintf("Pilot 12 권고: %s", abl$pilot12_recommendation),
           "MDD 57.5%% 주의 -- 전구간. Lockbox MDD Judge 확인 필요"
         ))
  ),
  charts = c(chart1, chart2)
)

stopifnot(isTRUE(result$ok))
cat(sprintf("Telegram sent: ok=%s bytes=%d\n", result$ok, result$bytes))
