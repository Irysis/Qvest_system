suppressPackageStartupMessages({
  library(data.table)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

diag_df <- data.frame(
  Metric = c("rank_IC (as-is)", "ICIR", "Harvey t (abs)",
             "Subperiod (3/3 same-sign)", "TDC vs STR_1700",
             "DSR_BLP Q1 / Q10", "Sector-neutral IC ret"),
  Value  = c("-0.0511", "-0.481", "7.43",
             "1.00 (all neg)", "0.12 (<0.30 PASS)",
             "0.082 / 0.022", "0.66"),
  stringsAsFactors = FALSE
)

res <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260426_001 ALPHA_DONE — Iter 7 cross-family L01+L11+L12+R13 NOT_GRADUATING",
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics (post-Codex v2, no flip, TV>=2e8)",
         type = "table", df = diag_df),
    list(emoji = "💡", heading = "핵심 발견",
         type = "text",
         body = paste(
           "4-axis Liquidity_Risk(L01+L11+L12) + Tail_Risk(R13_NCSKEW) composite.",
           "239 sig_dates × 3101 tickers (446k rows).",
           "Codex Round 1 REJECT (PIT-C13 sign-flip + DSR formula + AX-007 evidence).",
           "v2 PARTIAL response: sign-flip REMOVED, Bailey-LdP DSR formal.",
           "honest verdict: ALPHA_NOT_GRADUATING. Cross-family TDC=0.12 PASS structurally,",
           "but alpha quality FAIL on both Q1 and Q10 long directions.",
           "Recommendation: archive as L-code lesson + pivot to Growth × Investor_Flow",
           "or single-axis L01 regime-conditional sleeve next iteration."
         )),
    list(emoji = "🚩", heading = "Challenge Flags",
         type = "bullet",
         items = c(
           "DIRECTION-AS-IS: Factor DB IC-aligned default. NO manual flip (Codex C1 conceded).",
           "ALPHA-NOT-GRADUATING: rank_IC=-0.051, both Q1 (0.082) and Q10 (0.022) DSR_BLP < 0.5.",
           "RF-A6-DSR-FAIL: Bailey-LdP formal DSR << 0.5 hurdle. Honest reporting.",
           "AX-007-DEFER: multi-sleeve mandate declared but verification deferred (alpha-stage limit).",
           "RECOMMEND-ARCHIVE: KR Liquidity+Tail composite no graduable direction. Lesson L-code."
         )),
    list(emoji = "🎛️", heading = "메타",
         type = "kv",
         kv = list(
           WT_ID = "WT-D20260426_001",
           Phase = "ALPHA_DONE",
           CodexStance = "REJECT",
           AlphaResponse = "PARTIAL",
           Verdict = "ALPHA_NOT_GRADUATING",
           SigDates = "239 (2004-01 to 2023-11)",
           Universe = "TV>=2e8 KRW (326k rows)",
           AX_Compliance = "AX003/004/005 PASS, AX007 DEFER, AX002 PASS, PIT-C13 PASS_v2"
         ))
  ),
  emoji_min = 5L
)
cat("Telegram brief result: ok=", isTRUE(res$ok), "\n")
print(res)
