#==============================================================================
# daily_bearish_monitor.R — Daily Early Warning system for 약세예측 v1.3 5-way M2 Regime
#
# Usage:
#   - Daily cron: Rscript daily_bearish_monitor.R [--telegram]
#   - 매일 장마감 후 또는 다음 일 새벽 호출
#
# Function:
#   1. Load latest daily predictions (predictions_dynamic_y_tail_q15.parquet)
#   2. Compute expanding past quantile thresholds (PIT q70/q90/q95)
#   3. Detect alert state (NORMAL / WARNING / ALERT / CRITICAL)
#   4. Generate recommendation
#   5. JSON state save + Telegram alert
#
# Model: v1.3 5-way M2 Regime (XGB + CatBoost + RF + LSTM + TFT, regime-conditional)
# Daily OOS PR-AUC: 0.608 (random baseline 0.228, lift 2.7x)
# Month-end Top 5%% precision: 1.000 (6/6 hit)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(ggplot2); library(patchwork); library(scales)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
LIVE_DIR <- file.path(WS, "outputs/05_live")
dir.create(LIVE_DIR, recursive = TRUE, showWarnings = FALSE)

args <- commandArgs(trailingOnly = TRUE)
USE_TELEGRAM <- "--telegram" %in% args

cat(sprintf("━━━ 약세예측 v1.3 Daily Early Warning Monitor ━━━\n"))
cat(sprintf("Run timestamp: %s\n\n", as.character(Sys.time())))

# ── (1) Load latest daily predictions ──
preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]
preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]
setorder(preds, Date)

latest_date <- max(preds$Date)
latest_p <- preds$p[nrow(preds)]
latest_regime <- preds$regime[nrow(preds)]

cat(sprintf("[Model] predictions latest: %s / p_M2_regime = %.4f / regime = %s\n",
            as.character(latest_date), latest_p, latest_regime))
cat(sprintf("[Model] total daily predictions: %d (since %s)\n",
            nrow(preds), as.character(min(preds$Date))))

# Freshness check
days_stale <- as.numeric(Sys.Date() - latest_date)
if (days_stale > 7) {
  cat(sprintf("\n⚠️ STALE WARNING: predictions %d days old. Re-run model required.\n",
              days_stale))
}

# ── (2) PIT expanding quantile thresholds ──
expanding_q <- function(x, dates, q = 0.5) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 30) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}

# Only compute on recent for efficiency (use past 1y for context, full for thresholds)
# For latest day, threshold = quantile of all past p
all_past_p <- preds$p[preds$Date < latest_date]
q70 <- quantile(all_past_p, 0.70, na.rm = TRUE)
q90 <- quantile(all_past_p, 0.90, na.rm = TRUE)
q95 <- quantile(all_past_p, 0.95, na.rm = TRUE)

cat(sprintf("\n[Thresholds] PIT expanding (from %d past obs):\n", length(all_past_p)))
cat(sprintf("  q70 (caution): %.4f\n", q70))
cat(sprintf("  q90 (alert):   %.4f\n", q90))
cat(sprintf("  q95 (critical):%.4f\n", q95))

# ── (3) Alert state ──
state <- fcase(
  latest_p >= q95, "CRITICAL",
  latest_p >= q90, "ALERT",
  latest_p >= q70, "WARNING",
  default = "NORMAL"
)
emoji <- fcase(
  state == "CRITICAL", "🚨🚨",
  state == "ALERT", "🚨",
  state == "WARNING", "⚠️",
  default = "✅"
)
cat(sprintf("\n%s━━━ Current State: %s ━━━\n", emoji, state))
cat(sprintf("Latest p_M2_regime: %.4f\n", latest_p))
percentile_rank <- mean(all_past_p <= latest_p, na.rm = TRUE) * 100
cat(sprintf("Historical percentile: %.1f%%%% (out of %d past obs)\n",
            percentile_rank, length(all_past_p)))

# Recommendation
recommendation <- fcase(
  state == "CRITICAL", "🚨🚨 Top 5%% historical — STR_1715 비중 축소 검토 (강한 신호). Daily PR-AUC 0.608 + Top 5%% precision 100%%.",
  state == "ALERT", "🚨 Top 10%% historical — V1aV3 Hybrid trigger 임박 가능성. 모니터링 강화.",
  state == "WARNING", "⚠️ Top 30%% historical — 약세 환경 진입 가능성. 익숙한 평소대로 운용.",
  default = "✅ NORMAL — STR_1715 baseline 그대로 운용."
)
cat(sprintf("\nRecommendation: %s\n", recommendation))

# ── (4) Recent 5 days trend ──
cat(sprintf("\n[Recent 5 trading days]:\n"))
recent_5 <- tail(preds, 5)
recent_5[, prev_p := shift(p, 1)]
recent_5[, delta := p - prev_p]
recent_view <- recent_5[, .(Date,
                             p = round(p, 4),
                             percentile = round(sapply(p, function(x)
                               mean(all_past_p <= x) * 100), 1),
                             regime)]
print(recent_view)

# Trend (rising or falling?)
trend <- fcase(
  recent_5$p[5] > recent_5$p[1] + 0.05, "📈 RAPID_RISE",
  recent_5$p[5] > recent_5$p[1] + 0.02, "↗ RISING",
  recent_5$p[5] < recent_5$p[1] - 0.05, "📉 RAPID_FALL",
  recent_5$p[5] < recent_5$p[1] - 0.02, "↘ FALLING",
  default = "→ STABLE"
)
cat(sprintf("\n5-day trend: %s (%+.4f)\n", trend, recent_5$p[5] - recent_5$p[1]))

# ── (4.5) V10 KOSPI Kill Switch Logic (Cycle 35 confirmed PRIMARY) ──
cat(sprintf("\n━━━ V10 KOSPI Kill Switch (cycle 35 PRIMARY) ━━━\n"))
# 3-condition AND:
#   (1) count_5_q70 >= 4 (직전 5일 중 4일+ p >= q70)
#   (2) trend_5d > 0
#   (3) p_eom > q70
recent_5_p <- recent_5$p
count_5_q70 <- sum(recent_5_p >= q70, na.rm = TRUE)
trend_5d_v10 <- recent_5_p[5] - recent_5_p[1]
v10_cond_1 <- count_5_q70 >= 4
v10_cond_2 <- trend_5d_v10 > 0
v10_cond_3 <- latest_p > q70
v10_triggered <- v10_cond_1 && v10_cond_2 && v10_cond_3

cat(sprintf("  Cond 1: count_5_q70 >= 4 → %d/5 (%s)\n",
            count_5_q70, ifelse(v10_cond_1, "✅ PASS", "❌ FAIL")))
cat(sprintf("  Cond 2: trend_5d > 0 → %+.4f (%s)\n",
            trend_5d_v10, ifelse(v10_cond_2, "✅ PASS", "❌ FAIL")))
cat(sprintf("  Cond 3: p_eom > q70 → %.4f > %.4f (%s)\n",
            latest_p, q70, ifelse(v10_cond_3, "✅ PASS", "❌ FAIL")))

v10_action <- ifelse(v10_triggered, "🚨 KOSPI SELL → CASH (V10 TRIGGERED)",
                      "✅ KOSPI HOLD (V10 not triggered)")
v10_state <- ifelse(v10_triggered, "V10_TRIGGER", "V10_HOLD")
cat(sprintf("\n  V10 STATE: %s\n", v10_state))
cat(sprintf("  ACTION: %s\n", v10_action))
cat(sprintf("\n  Backtest performance (109m, cycle 35 confirmed):\n"))
cat(sprintf("    BH KOSPI:  SR 0.448 / MDD -34.6%%%% / CAGR 10.2%%%%\n"))
cat(sprintf("    V10 Kill:  SR 0.921 / MDD -30.6%%%% / CAGR 18.0%%%% (Δ +106%%%% SR)\n"))
cat(sprintf("    Walk-forward 100%%%% / OOS dSR +0.58 / Bootstrap CI [+0.06, +0.94]\n"))

# ── (5) Triple-layer integration status ──
cat(sprintf("\n━━━ Triple-layer status ━━━\n"))
cat(sprintf("  Layer 1: STR_1715 admit baseline (active)\n"))
cat(sprintf("  Layer 2: V1aV3 Hybrid monthly (PRIMARY candidate, pre-Codex)\n"))
cat(sprintf("  Layer 3: 약세예측 v1.3 daily alert — %s state\n", state))

# ── (6) Save state ──
state_out <- list(
  timestamp = as.character(Sys.time()),
  model = "약세예측_v1.3_5way_M2_Regime",
  daily_PR_AUC = 0.608,
  monthend_top5_precision = 1.000,
  latest_pred_date = as.character(latest_date),
  latest_p_M2_regime = latest_p,
  latest_regime_label = latest_regime,
  state = state,
  percentile = percentile_rank,
  thresholds = list(q70 = unname(q70), q90 = unname(q90), q95 = unname(q95)),
  trend_5d = trend,
  trend_5d_delta = recent_5$p[5] - recent_5$p[1],
  recommendation = recommendation,
  v10_kill_switch = list(
    state = v10_state,
    triggered = v10_triggered,
    count_5_q70 = count_5_q70,
    trend_5d = trend_5d_v10,
    p_eom_vs_q70 = list(p_eom = latest_p, q70 = unname(q70), pass = v10_cond_3),
    cond_1_pass = v10_cond_1,
    cond_2_pass = v10_cond_2,
    cond_3_pass = v10_cond_3,
    action = v10_action
  ),
  days_stale = days_stale,
  recent_5d = list(
    Date = as.character(recent_5$Date),
    p = recent_5$p,
    percentile = sapply(recent_5$p, function(x) mean(all_past_p <= x) * 100),
    regime = recent_5$regime
  )
)
write_json(state_out, file.path(LIVE_DIR,
                                 sprintf("bearish_monitor_%s.json",
                                          format(Sys.Date(), "%Y%m%d"))),
           auto_unbox = TRUE, pretty = TRUE)
write_json(state_out, file.path(LIVE_DIR, "bearish_monitor_latest.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/bearish_monitor_latest.json\n", LIVE_DIR))

# ── (7) Generate visualization charts ──
cat(sprintf("\n[Chart] generating 60-day timeline visualization...\n"))

# Load KOSPI200 for overlay
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]
bm_60d <- bm[Date >= (latest_date - 90) & Date <= latest_date, .(Date, BM_Close)]

# Preds 60d window
preds_60d <- tail(preds, 60)
preds_60d[, pct := sapply(p, function(x) mean(all_past_p <= x) * 100)]
preds_60d[, alert_band := fcase(p >= q95, "CRITICAL",
                                 p >= q90, "ALERT",
                                 p >= q70, "WARNING",
                                 default = "NORMAL")]

# Chart 1: KOSPI200 with regime overlay
g_top <- ggplot(bm_60d, aes(x = Date, y = BM_Close)) +
  geom_line(color = "#073B4C", linewidth = 0.8) +
  geom_point(data = bm_60d[Date == latest_date],
             aes(x = Date, y = BM_Close), color = "red", size = 3) +
  labs(title = sprintf("KOSPI200 — Recent 60d (latest %.2f)",
                       bm_60d$BM_Close[nrow(bm_60d)]),
       x = NULL, y = "BM_Close") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

# Chart 2: p_bear timeline with thresholds
g_bot <- ggplot(preds_60d, aes(x = Date, y = p)) +
  geom_rect(xmin = -Inf, xmax = Inf, ymin = q95, ymax = 1,
            fill = "#EF476F", alpha = 0.15, inherit.aes = FALSE) +
  geom_rect(xmin = -Inf, xmax = Inf, ymin = q90, ymax = q95,
            fill = "#FF9F1C", alpha = 0.15, inherit.aes = FALSE) +
  geom_rect(xmin = -Inf, xmax = Inf, ymin = q70, ymax = q90,
            fill = "#FFD166", alpha = 0.15, inherit.aes = FALSE) +
  geom_line(color = "#073B4C", linewidth = 0.7) +
  geom_point(aes(color = alert_band), size = 1.5) +
  geom_hline(yintercept = q70, linetype = "dashed", color = "#FFD166") +
  geom_hline(yintercept = q90, linetype = "dashed", color = "#FF9F1C") +
  geom_hline(yintercept = q95, linetype = "dashed", color = "#EF476F") +
  annotate("text", x = max(preds_60d$Date), y = q70 - 0.005,
           label = sprintf("q70 %.3f", q70), color = "#FFD166", size = 3, hjust = 1) +
  annotate("text", x = max(preds_60d$Date), y = q90 - 0.005,
           label = sprintf("q90 %.3f", q90), color = "#FF9F1C", size = 3, hjust = 1) +
  annotate("text", x = max(preds_60d$Date), y = q95 - 0.005,
           label = sprintf("q95 %.3f", q95), color = "#EF476F", size = 3, hjust = 1) +
  scale_color_manual(values = c("NORMAL" = "#06D6A0", "WARNING" = "#FFD166",
                                 "ALERT" = "#FF9F1C", "CRITICAL" = "#EF476F"),
                     name = NULL) +
  labs(title = sprintf("p_M2_regime — Recent 60d (%s state, %.0f%%%%ile)",
                       state, percentile_rank),
       subtitle = sprintf("Latest %.4f (%s) / 5-day trend %s",
                          latest_p, latest_regime, trend),
       x = NULL, y = "p_bear (M2 Regime)") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1),
        legend.position = "bottom")

# Combined chart
g_combined <- patchwork::wrap_plots(g_top, g_bot, ncol = 1, heights = c(1, 1.4))
chart_path <- file.path(LIVE_DIR, sprintf("daily_chart_%s.png",
                                            format(Sys.Date(), "%Y%m%d")))
ggsave(chart_path, plot = g_combined, width = 12, height = 7, dpi = 120)
chart_latest <- file.path(LIVE_DIR, "daily_chart_latest.png")
ggsave(chart_latest, plot = g_combined, width = 12, height = 7, dpi = 120)
cat(sprintf("[Chart] %s\n", chart_latest))

# ── (8) Telegram alert ──
if (USE_TELEGRAM) {
  source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  sections <- list(
    list(title = sprintf("%s State: %s (Daily monitor)", emoji, state),
         body = sprintf("Latest: %s / p = %.4f (%.0f%%%%ile) / regime = %s",
                        as.character(latest_date), latest_p,
                        percentile_rank, latest_regime)),
    list(title = "📊 Thresholds (PIT)",
         body = sprintf("q70 caution %.3f / q90 alert %.3f / q95 critical %.3f",
                        q70, q90, q95)),
    list(title = "📈 5-day Trend",
         body = sprintf("%s (Δ %+.4f). Recent: %s",
                        trend, recent_5$p[5] - recent_5$p[1],
                        paste(sprintf("%.3f", recent_5$p), collapse = " → "))),
    list(title = "📋 Recommendation",
         body = recommendation),
    list(title = sprintf("%s V10 KOSPI Kill Switch", ifelse(v10_triggered, "🚨", "✅")),
         body = sprintf("State: %s / Action: %s",
                        v10_state, ifelse(v10_triggered,
                                           "KOSPI SELL → CASH",
                                           "KOSPI HOLD"))),
    list(title = "🔍 V10 3-cond AND check",
         body = sprintf("count_5_q70=%d/5 %s / trend_5d=%+.3f %s / p_eom=%.3f vs q70=%.3f %s",
                        count_5_q70, ifelse(v10_cond_1, "✓", "✗"),
                        trend_5d_v10, ifelse(v10_cond_2, "✓", "✗"),
                        latest_p, q70, ifelse(v10_cond_3, "✓", "✗"))),
    list(title = "🏗 Triple-layer status",
         body = "L1 STR_1715 active / L2 V1aV3 Hybrid (pre-Codex) / L3 V10 Kill switch (PRIMARY)."),
    list(title = "📐 Model spec",
         body = sprintf("v1.3 5-way M2 Regime + V10 logic. Daily PR-AUC %.3f. V10 backtest: BH SR 0.45 → 0.92 (+106%%%%), WF 100%%%%, OOS dSR +0.58.",
                        0.608))
  )
  tg_agent_brief(
    agent = "Q-Lead",
    title = sprintf("%s 약세예측 v1.3 Daily Monitor — %s", emoji, state),
    sections = sections,
    charts = list(chart_latest)
  )
  cat(sprintf("\n[Telegram] daily alert sent (%s)\n", state))
}

cat(sprintf("\n[DONE] Daily bearish monitor complete.\n"))
