#==============================================================================
# WT-D20260426_002 Iter 8 — Telegram brief (v4 ENFORCE)
# Single-Dispatch tg_agent_brief() — sections >= 4, table nrow>=2 ncol>=2,
# emoji_min=5, body>=50, items>=3, bytes>=1200
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

WT_ID <- "WT-D20260426_002"

# Diagnostic table
diag_df <- data.frame(
  Metric    = c("rank_IC active", "ICIR active", "Harvey t",
                "DSR (n=10)", "Post-neut IC", "TDC vs STR_1700",
                "Subp consist", "Specs t>3"),
  Value     = c("-0.0051", "-0.044", "-0.53",
                "0.018", "-0.0091", "0.173",
                "0.67", "0/5"),
  Threshold = c(">= 0.04", ">= 0.20", ">= 3.0",
                ">= 0.5", ">= 50% raw", "< 0.30",
                ">= 0.50", ">= 4/5"),
  Pass      = c("FAIL", "FAIL", "FAIL",
                "FAIL", "PASS(vacuous)", "PASS",
                "PASS", "FAIL"),
  stringsAsFactors = FALSE
)

# Regime IC table
regime_df <- data.frame(
  Regime = c("BULL", "NORMAL", "CAUTION", "CRISIS"),
  N_periods = c("85", "60", "25", "5"),
  ICIR = c("-0.116", "+0.062", "alpha=0", "alpha=0"),
  Verdict = c("REVERSE", "BORDERLINE FAIL", "cash sleeve", "cash sleeve"),
  stringsAsFactors = FALSE
)

res <- tg_agent_brief(
  agent = "Alpha",
  title = paste0("WT-", WT_ID, " ALPHA_DONE — Iter 8 L01_Amihud regime-conditional FAIL (graduation NOT MET, sprint termination 권고)"),
  sections = list(
    list(
      emoji = "📊",
      heading = "Graduation Diagnostics (universe-restricted, post-neutralized)",
      type = "table",
      df = diag_df
    ),
    list(
      emoji = "🌊",
      heading = "Regime-Conditional ICIR Decomposition",
      type = "table",
      df = regime_df
    ),
    list(
      emoji = "💡",
      heading = "핵심 발견 (가설 미입증)",
      type = "text",
      body = paste0(
        "Iter 8 가설 'Liquidity premium = BULL/NORMAL only positive' — KR market에서 미입증. ",
        "BULL ICIR=-0.116 (가설과 reverse: illiquid 종목 BULL 국면에서 underperform). ",
        "NORMAL ICIR=+0.062 (보더라인 미만, Harvey t=-0.53 통계 유의성 부재). ",
        "Subperiod 2008-14 명확히 reverse — recent 3Y bias 9x trigger. ",
        "Codex round REJECT (7 concerns) 전부 반영 후 universe 773 tickers + mom12-orthogonal 적용에도 결과 fail. ",
        "Iter 7 (composite IC=-0.05) + Iter 8 (single-axis regime IC=-0.005) 연속 fail로 KR Liquidity_Risk family alpha origin 한계 명백."
      )
    ),
    list(
      emoji = "🚩",
      heading = "Challenge Flags (severity HIGH)",
      type = "bullet",
      items = c(
        "GRADUATION_FAIL — 모든 metric FAIL (rank_IC=-0.005 / ICIR=-0.04 / Harvey t=-0.53 / DSR=0.02 / Mono=-0.42)",
        "REGIME_ASYMMETRY_REVERSE — BULL에서 가설과 reverse(-0.116), NORMAL 보더라인(+0.062)도 통계 유의성 부재",
        "RF-A3_RECENT_BIAS — 2020-23 ICIR(0.24) / overall(0.026) = 9x ratio, sample selection 의심",
        "AX007_OVERCLAIM_REVISED — cash sleeve = overlay-not-alpha, single-axis long-only top-20 mechanism break 미해소",
        "SPRINT_TERMINATION_RECOMMENDED — Iter 7+8 연속 fail, L-209 적립 + Sprint 종결 또는 cross-family pivot"
      )
    ),
    list(
      emoji = "🎛️",
      heading = "Meta",
      type = "kv",
      kv = list(
        WT_ID = WT_ID,
        Phase = "ALPHA_DONE",
        Iter = 8,
        Family = "Liquidity_Risk(L01_regime_conditional)",
        AX_007 = "EXCEPTION#1_DECLARED_BUT_INSUFFICIENT",
        TDC_vs_STR1700 = "0.173 (PASS, cross-family)",
        Codex_stance = "REJECT (veto=FALSE)",
        Sprint_recommendation = "TERMINATE + L-209 또는 Iter 9 pivot",
        N_sig_dates = "173 total / 145 active(BULL+NORMAL)",
        Universe = "773 tickers (KOSPI200∪KOSDAQ150 audited)"
      )
    )
  ),
  emoji_min = 5L
)

stopifnot(isTRUE(res$ok))
cat("[TG] Brief sent. bytes=", res$bytes, " sections=", res$sections, "\n")
