#==============================================================================
# live_monitor_v1av3.R — Daily/Monthly live monitoring for
# KOSPI_DD_Hybrid_V1aV3_2M_5PCT strategy (deploy-ready)
#
# Usage:
#   - Daily cron: Rscript live_monitor_v1av3.R [--telegram]
#   - 매 월말 또는 monthly rebalancing trigger 후 호출
#
# Function:
#   1. Fetch latest KOSPI200 (BM_Close from targets_full + 069500 ETF)
#   2. Compute 2m rolling DD
#   3. Detect trigger state (BEAR_ACTIVE / BULL_NORMAL / BEAR_EXPIRED)
#   4. Calculate recommended position (dynamic V3 scaling)
#   5. Output state + position + Telegram alert
#
# Strategy spec (Cycle 18 PRIMARY):
#   Trigger: KOSPI 2m rolling DD ≤ -5%% (lag 1)
#   Persistence: active only first 2m of trigger episode
#   Position: max(0, 0.7 - 3×max(0, -(dd+0.10)))
#   Inactive: STR_1715_AR_on_M4_R05_overlay_PG2 baseline
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
LIVE_DIR <- file.path(WS, "outputs/05_live")
dir.create(LIVE_DIR, recursive = TRUE, showWarnings = FALSE)

# Args
args <- commandArgs(trailingOnly = TRUE)
USE_TELEGRAM <- "--telegram" %in% args

cat(sprintf("━━━ KOSPI_DD_Hybrid_V1aV3_2M_5PCT Live Monitor ━━━\n"))
cat(sprintf("Run timestamp: %s\n\n", as.character(Sys.time())))

# ── (1) Load BM_Close (KOSPI 합성) ──
bm_path <- file.path(WS, "outputs/02_targets/targets_full.parquet")
if (file.exists(bm_path)) {
  bm <- as.data.table(read_parquet(bm_path))
  bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
  setorder(bm, Date)
  eom <- bm[, .(close_eom = BM_Close[which.max(Date)],
                Date_eom = max(Date)), by = ym]
  setorder(eom, ym)
  cat(sprintf("[BM_Close] loaded: %s ~ %s (n=%d months)\n",
              eom$ym[1], eom$ym[nrow(eom)], nrow(eom)))
} else {
  stop(sprintf("targets_full.parquet not found at %s", bm_path))
}

# ── (2) Compute 2m rolling DD ──
eom[, kospi_log_cum := cumsum(log(1 + c(0, diff(close_eom) / head(close_eom, -1))))]
eom[, kospi_lvl := exp(kospi_log_cum)]
eom[, kospi_2m_max := frollapply(kospi_lvl, 2, max, align = "right")]
eom[, kospi_dd_2m := kospi_lvl / kospi_2m_max - 1]
eom[, prev_month_ret := c(NA, diff(close_eom) / head(close_eom, -1))]

# Latest 6 months snapshot
recent <- tail(eom, 6)
cat(sprintf("\n[Recent 6 months DD-2m]:\n"))
recent_view <- recent[, .(ym,
                          close = round(close_eom, 2),
                          prev_ret = sprintf("%+.2f%%%%", 100 * prev_month_ret),
                          dd_2m = sprintf("%+.2f%%%%", 100 * kospi_dd_2m),
                          trigger = kospi_dd_2m <= -0.05)]
print(recent_view)

# ── (3) Detect current trigger state ──
# Latest 2 months trigger status (for trig_run determination)
latest_dd <- tail(eom$kospi_dd_2m, 3)  # past 3 months
latest_trigger <- !is.na(latest_dd) & latest_dd <= -0.05
cat(sprintf("\n[Trigger status — past 3m]:\n"))
for (i in seq_along(latest_trigger)) {
  ym_idx <- tail(eom$ym, 3)[i]
  cat(sprintf("  %s: dd_2m=%+.2f%%%% / trigger=%s\n",
              ym_idx, 100 * latest_dd[i], latest_trigger[i]))
}

# Trig_run (consecutive trigger months ending at latest)
trig_run <- 0
for (i in length(latest_trigger):1) {
  if (latest_trigger[i]) trig_run <- trig_run + 1
  else break
}
cat(sprintf("\nCurrent trig_run: %d consecutive trigger month(s)\n", trig_run))

# Decision logic:
# If trig_run == 0 → BULL (use STR_1715)
# If trig_run in [1, 2] → BEAR_ACTIVE (use V1a+V3 KOSPI position)
# If trig_run >= 3 → BEAR_EXPIRED (revert to STR_1715, persistence rule kicks in)
current_dd <- tail(latest_dd, 1)
state <- fcase(
  trig_run == 0, "BULL_NORMAL",
  trig_run <= 2, "BEAR_ACTIVE",
  trig_run >= 3, "BEAR_EXPIRED"
)
cat(sprintf("\n━━━ Current State: %s ━━━\n", state))

# ── (4) Calculate position ──
if (state == "BEAR_ACTIVE") {
  # V3 dynamic scaling using kospi_dd_2m_lag1 (decision at t-1 EOM applied to t)
  dd_lag <- tail(eom$kospi_dd_2m, 2)[1]  # t-1 EOM DD
  pos_factor <- max(0.0, 0.7 - 3.0 * max(0, -(dd_lag + 0.10)))
  cat(sprintf("Position factor: max(0, 0.7 - 3 × max(0, -(%.4f + 0.10)))\n", dd_lag))
  cat(sprintf("                = %.3f (%.0f%%%% KOSPI200 long)\n",
              pos_factor, 100 * pos_factor))
  recommendation <- sprintf("KOSPI200 (069500 ETF) %.0f%%%% long + %.0f%%%% cash for next month",
                            100 * pos_factor, 100 * (1 - pos_factor))
} else if (state == "BEAR_EXPIRED") {
  pos_factor <- NA
  cat(sprintf("Trig_run >= 3 → persistence rule expired\n"))
  recommendation <- "Revert to STR_1715_AR_on_M4_R05_overlay_PG2 baseline (BEAR persisted >2m)"
} else {  # BULL_NORMAL
  pos_factor <- NA
  recommendation <- "STR_1715_AR_on_M4_R05_overlay_PG2 baseline (normal state)"
}
cat(sprintf("\nRecommendation: %s\n", recommendation))

# ── (5) Save state ──
state_out <- list(
  timestamp = as.character(Sys.time()),
  strategy = "KOSPI_DD_Hybrid_V1aV3_2M_5PCT",
  version = "v1.1_PRIMARY",
  latest_month = eom$ym[nrow(eom)],
  latest_dd_2m = current_dd,
  trig_run = trig_run,
  state = state,
  position_factor = if (is.na(pos_factor)) NA_real_ else pos_factor,
  recommendation = recommendation,
  recent_6m = list(
    ym = recent$ym,
    close = recent$close_eom,
    dd_2m_pct = 100 * recent$kospi_dd_2m,
    trigger = recent$kospi_dd_2m <= -0.05
  )
)
write_json(state_out, file.path(LIVE_DIR, sprintf("monitor_state_%s.json",
                                                    format(Sys.Date(), "%Y%m%d"))),
           auto_unbox = TRUE, pretty = TRUE)
write_json(state_out, file.path(LIVE_DIR, "monitor_state_latest.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/monitor_state_latest.json\n", LIVE_DIR))

# ── (6) Telegram alert (optional) ──
if (USE_TELEGRAM) {
  source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  emoji <- fcase(state == "BEAR_ACTIVE", "🚨",
                  state == "BEAR_EXPIRED", "⏰",
                  default = "✅")
  sections <- list(
    list(title = sprintf("%s State: %s", emoji, state),
         body = sprintf("Latest month: %s / dd_2m = %+.2f%%%% / trig_run = %d / pos = %s",
                        eom$ym[nrow(eom)], 100 * current_dd, trig_run,
                        ifelse(is.na(pos_factor), "STR_1715 baseline",
                               sprintf("%.0f%%%% KOSPI", 100 * pos_factor)))),
    list(title = "📋 Recommendation",
         body = recommendation),
    list(title = "📊 Recent 3m dd_2m",
         body = paste(sprintf("%s: %+.2f%%%%", tail(eom$ym, 3),
                              100 * tail(eom$kospi_dd_2m, 3)),
                       collapse = " | ")),
    list(title = "📐 Strategy spec",
         body = "KOSPI_DD_Hybrid_V1aV3_2M_5PCT v1.1 PRIMARY. Trigger: 2m DD ≤ -5%%. Persistence ≤ 2m. Pos = max(0, 0.7-3×max(0,-(dd+0.1))).")
  )
  tg_agent_brief(agent = "Q-Lead",
                  title = sprintf("%s KOSPI_DD_Hybrid Live Monitor", emoji),
                  sections = sections,
                  charts = list())
  cat(sprintf("\n[Telegram] alert sent\n"))
}

cat(sprintf("\n[DONE] Live monitor complete.\n"))
