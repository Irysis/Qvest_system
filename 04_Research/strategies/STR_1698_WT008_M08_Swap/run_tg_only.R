#!/usr/bin/env Rscript
## Standalone telegram brief for STR_1698 (re-send after agent name fix)
## Reads from backtest_result/*.json + forge_package.json — no backtest re-run.

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR    <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1698_WT008_M08_Swap")
OUT_DIR      <- file.path(STRAT_DIR, "backtest_result")
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260425_008")

perf <- fromJSON(file.path(OUT_DIR, "performance_summary.json"))
m08  <- fromJSON(file.path(OUT_DIR, "m08_oos_validation.json"))
crowd <- fromJSON(file.path(OUT_DIR, "crowding_validation.json"))
fp   <- fromJSON(file.path(WT_DIR, "forge_package.json"))

# Extract key metrics
full_sr   <- perf$prelb$sr
full_cagr <- perf$prelb$cagr
full_mdd  <- perf$prelb$mdd
to_full   <- perf$prelb$turnover
p1_sr <- perf$subperiods$p1_2008_2014$sr
p1_cagr <- perf$subperiods$p1_2008_2014$cagr
p1_mdd <- perf$subperiods$p1_2008_2014$mdd
p2_sr <- perf$subperiods$p2_2015_2019$sr
p2_cagr <- perf$subperiods$p2_2015_2019$cagr
p2_mdd <- perf$subperiods$p2_2015_2019$mdd
p3_sr <- perf$subperiods$p3_2020_2024$sr
p3_cagr <- perf$subperiods$p3_2020_2024$cagr
p3_mdd <- perf$subperiods$p3_2020_2024$mdd
bm_sr <- perf$benchmark$sr
bm_cagr <- perf$benchmark$cagr
bm_mdd <- perf$benchmark$mdd

m08_p3_ic <- m08$m08_p3_ic_mean
m08_p3_icir <- m08$m08_p3_ic_icir
overlay_sr_delta <- m08$overlay_effect$sr_delta
overlay_mdd_delta <- m08$overlay_effect$mdd_delta
overlay_cagr_delta <- m08$overlay_effect$cagr_delta
overlay_perf <- m08$overlay_performance

tdc_baseline <- crowd$tdc_q07_ac21_baseline
tdc_iter3 <- crowd$tdc_q07_m08_iter3
tdc_delta <- crowd$tdc_delta_pct

mom_2009 <- fp$momentum_crash_resilience$periods$momentum_2009_reversal
mom_2020 <- fp$momentum_crash_resilience$periods$momentum_2020_covid_rally

hill_realized <- fp$heavy_tail_validation$hill_alpha_realized
cvar_realized <- fp$heavy_tail_validation$cvar_95_daily_realized

wf_pure <- fp$walkforward_integrity$pure_walkforward_dates
wf_total <- fp$walkforward_integrity$total_sig_dates
wf_pct <- fp$walkforward_integrity$pure_walkforward_pct

BASELINE_SR <- 1.258
BASELINE_CAGR <- 26.9
BASELINE_MDD <- -36.95

source(file.path(FUNC_PATH, "telegram/telegram_notify.R"))

perf_df <- data.frame(
  Label = c("MEGA_05 Baseline", "STR_1698 (Opus REBUILD)", "KOSPI200"),
  SR    = c(sprintf("%.3f", BASELINE_SR), sprintf("%.3f", full_sr), sprintf("%.3f", bm_sr)),
  CAGR  = c(sprintf("%.1f%%", BASELINE_CAGR), sprintf("%.1f%%", full_cagr), sprintf("%.1f%%", bm_cagr)),
  MDD   = c(sprintf("%.1f%%", BASELINE_MDD), sprintf("%.1f%%", full_mdd), sprintf("%.1f%%", bm_mdd)),
  stringsAsFactors = FALSE
)

sub_df <- data.frame(
  Period = c("P1 2008-2014", "P2 2015-2019", "P3 2020-2024 (OOS)"),
  SR     = c(sprintf("%.3f", p1_sr), sprintf("%.3f", p2_sr), sprintf("%.3f", p3_sr)),
  CAGR   = c(sprintf("%.1f%%", p1_cagr), sprintf("%.1f%%", p2_cagr), sprintf("%.1f%%", p3_cagr)),
  MDD    = c(sprintf("%.1f%%", p1_mdd), sprintf("%.1f%%", p2_mdd), sprintf("%.1f%%", p3_mdd)),
  stringsAsFactors = FALSE
)

decay_df <- data.frame(
  Metric = c("M08 P3 IC mean", "M08 P3 ICIR", "Decay triggered",
             "Overlay SR delta", "Overlay MDD delta", "Overlay CAGR delta",
             "Hill alpha realized"),
  Value  = c(sprintf("%.4f (baseline 0.0289)", m08_p3_ic),
             sprintf("%.4f", m08_p3_icir),
             "TRUE (P3 IC < 0)",
             sprintf("%+.4f", overlay_sr_delta),
             sprintf("%+.2fpp", overlay_mdd_delta),
             sprintf("%+.2fpp", overlay_cagr_delta),
             sprintf("%.4f (M08 ex-ante 0.4579)", hill_realized)),
  stringsAsFactors = FALSE
)

crowding_df <- data.frame(
  Metric = c("TDC Q07-AC21 baseline", "TDC Q07-M08 iter3", "TDC delta (-65% target)",
             "Claim confirmed", "AX-004"),
  Value  = c(sprintf("%.4f", tdc_baseline),
             sprintf("%.4f", tdc_iter3),
             sprintf("%.1f%%", tdc_delta),
             ifelse(abs(tdc_delta - (-65)) < 5, "YES", "DEVIATION"),
             "CLEARED (multi-axis composite)"),
  stringsAsFactors = FALSE
)

mom_df <- data.frame(
  Period = c("2009 Reversal", "2020 COVID Rally"),
  SR     = c(sprintf("%.3f", mom_2009$sr), sprintf("%.3f", mom_2020$sr)),
  CAGR   = c(sprintf("%.1f%%", mom_2009$cagr), sprintf("%.1f%%", mom_2020$cagr)),
  MDD    = c(sprintf("%.1f%%", mom_2009$mdd), sprintf("%.1f%%", mom_2020$mdd)),
  stringsAsFactors = FALSE
)

result <- tg_agent_brief(
  agent = "Forge",
  title = sprintf("STR_1698 WT008 M08 Swap REBUILD (Opus 4.7) -- %s",
                  fp$mega05_comparison$swap_verdict),
  sections = list(
    list(type = "text",
         title = "📌 REBUILD 개요",
         body = paste0(
           "🔧 Iter 3 REBUILD by Opus 4.7. STR ID 충돌 해결: sonnet STR_1696 → STR_1698.\n",
           "📐 6F (C01+C02+C04+C06+Q07+M08) | HRP_lw walk-forward | n=20 | 15bps.\n",
           "🔒 Walk-forward 100% (313/313) + Package hashes UNCHANGED (R12 pure function)."
         )),

    list(type = "table",
         title = "💼 MEGA_05 Baseline vs STR_1698 (Opus REBUILD, Pre-LB)",
         df = perf_df),

    list(type = "table",
         title = "📊 Sub-period Breakdown (P1/P2/P3 OOS)",
         df = sub_df),

    list(type = "table",
         title = "⚠️ M08 OOS Decay + VT18 Overlay 효과",
         df = decay_df),

    list(type = "table",
         title = "🎯 Crowding Validation (-65% TDC)",
         df = crowding_df),

    list(type = "table",
         title = "📈 Momentum Crash 견고성 (Daniel-Moskowitz 2016)",
         df = mom_df),

    list(type = "kv",
         title = "🛡️ Walk-Forward Integrity + Lockbox + AX-004",
         kv = list(
           "Walk-forward pure"   = sprintf("%d / %d (%.1f%%)", wf_pure, wf_total, wf_pct),
           "OPT-frozen sig_dates" = "0 (Pre-LB <= 2024-01-22, opt 2024-01-01 falls in same period — pure HRP)",
           "Lockbox SEALED"      = "2024-01-23 ~ 2026-01-23 (AX-002)",
           "Package hashes"      = "alpha=f648d2d3 risk=dc8ebd7c opt=63de76f9 (UNCHANGED)",
           "CVaR 95% daily"      = sprintf("%.4f (cap 0.0250 — breach expected)", cvar_realized),
           "M08 weight"          = "4.01% (cross-family diversifier role)",
           "AX-004"              = "CLEARED — multi-axis composite (Consensus+Quality+Residual_Mom)"
         ))
  ),
  charts = c(
    file.path(OUT_DIR, "equity_curve.png"),
    file.path(OUT_DIR, "annual_returns.png")
  )
)

cat(sprintf("[tg] ok=%s bytes=%d\n", result$ok, result$bytes))
