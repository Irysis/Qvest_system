# =============================================================================
# WT-D20260427_001 Iter 17 — Alpha Telegram Brief (v4 ENFORCE)
# =============================================================================
suppressPackageStartupMessages({library(jsonlite)})
PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)
source("02_Infrastructure/telegram/telegram_notify.R")

res <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260427_001 Iter17 ALPHA_DONE — XGB d=4 nonlinear cross-family REJECT",
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics (Hard Fails)",
         type = "table",
         df = data.frame(
           Metric = c("rank_IC", "ICIR", "sub_stab", "Harvey_NW", "DSR_post", "5-spec PASS"),
           Value  = c("0.0093", "0.1184", "0.0000", "1.1337", "-1.5368", "0/5"),
           Gate   = c(">=0.04", ">=0.20", ">=0.50", ">=3.0", ">=0.5", ">=3/5"),
           Result = c("FAIL", "FAIL", "FAIL", "FAIL", "FAIL", "FAIL"),
           stringsAsFactors = FALSE)),
    list(emoji = "💡", heading = "핵심 발견",
         type = "text",
         body = paste0(
           "Iter 17 (XGB depth=4 nonlinear interaction, 11 features 5-seed ensemble) FAILS 5/5 graduation gates. ",
           "OOS IC profile shows clear sign reversal post-2014 (P1=+0.045, P2=+0.024, P3=-0.001) — same KR ML alpha decay pattern as L-211 (linear) / L-225 (sigmoid joint). ",
           "Cross-family cor < 0.30 mandate technically PASSES (vs STR_1701: 0.013, vs STR_1656: 0.019) but is artifactual: alpha vector at LATEST_ME has only 3 unique score_ens values across 350 universe-filtered tickers (XGBoost over-regularization collapse). ",
           "Net-of-cost: gross 11.2bps - tcost 76.2bps = -65bps NET NEGATIVE. ",
           "Codex CLI gpt-5.5 stalled past 5min wrapper timeout — OVERRIDE_005 substitute applied per L-207 (9/9 explicit decisions). ",
           "DO NOT promote to Risk Agent. Recommend archive as L-code series sibling of L-211/L-225."
         )),
    list(emoji = "🚩", heading = "Challenge Flags (5)",
         type = "bullet",
         items = c(
           "RF-A1 sub_stab=0.0000 << 0.50 (HARD FAIL, sign reversal P1/P2/P3)",
           "RF-A_Degenerate alpha vector at LATEST_ME = 3 unique values across 350 tickers (XGB collapse)",
           "RF-A6 Harvey_NW=1.13 << 3.0 + DSR_post=-1.54 (HARD FAIL — Harvey-Liu-Zhu multi-test)",
           "RF-A_NetNegativeCost gross 11.2 - tcost 76.2 = -65bps NET (Charter principle 7 violated)",
           "RF-A_RegimeBreak OOS post-2014 sign reversal (Avramov 2023 + L-211/L-225 sibling)"
         )),
    list(emoji = "🎛️", heading = "메타",
         type = "kv",
         kv = list(
           WT_ID = "WT-D20260427_001",
           Phase = "ALPHA_DONE_REJECTED",
           Disposition = "REJECT (5/5 gates FAIL)",
           Method = "M07_XGB_d4_5seed_11feat",
           N_sig_dates = "192",
           Codex = "OVERRIDE_005 (CLI stall, 9/9 explicit)",
           Cor_vs_STR1701 = "0.013 (artifactual)",
           Cor_vs_STR1656 = "0.019 (artifactual)",
           Universe = "top20=20/20 K200∪KQ150 PIT",
           Liquidity = "top20=20/20 ≥ 2e8 KRW Close*Vol",
           Next_Action = "Archive as L-code series sibling of L-211/L-225"
         ))
  ),
  emoji_min = 5L
)
stopifnot(isTRUE(res$ok))
cat("Telegram brief sent OK\n")
