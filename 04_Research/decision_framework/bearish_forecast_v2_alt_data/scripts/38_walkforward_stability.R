#==============================================================================
# 38_walkforward_stability.R — Cycle 8 Walk-forward stability
#
# Best variant: DD -10%% / V_S5 / 15bps
#
# Rolling 36m windows:
#   - 110m - 36 + 1 = 75 windows
#   - Per window: Hybrid SR / STR_1715 SR / dSR / dMDD
#   - Distribution stats: median / IQR / win rate / outliers
#
# LOO (leave-one-out) outlier dependency:
#   - For each year, exclude → recompute overall dSR
#   - 어떤 1 year를 제외해도 dSR > 0 유지?
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Build best variant Hybrid returns ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(Date_eom = max(Date),
              close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]; preds[, ym := format(Date, "%Y-%m")]
me <- preds[, .SD[which.max(Date)], by = ym]
setorder(me, Date)

s5 <- merge(eom, me[, .(ym, p, regime)], by = "ym", all.x = TRUE)
setorder(s5, ym)
s5[, pos_S5 := fcase(regime == "bull", 1.0,
                     regime == "bear", 0.0,
                     default = 0.5)]
s5[, turn_S5 := abs(pos_S5 - shift(pos_S5, 1, fill = 0))]
s5[, ret_S5 := pos_S5 * ret_kospi - turn_S5 * 0.0015]  # 15bps

panel <- merge(baseline,
               s5[, .(realized_ym, ret_S5, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

# 6m rolling DD trigger
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]

panel[is.na(ret_S5), ret_S5 := 0]
panel[, state := fifelse(bear_trigger_lag1, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]
panel[, ret_hybrid := fifelse(bear_trigger_lag1, ret_S5, ret_L5_V5)]
panel[state_change == TRUE, ret_hybrid := ret_hybrid - 0.0015]

# ── (2) Restrict to 110m β_FX active ──
pfx <- panel[anchor_date >= as.Date("2017-03-01")]
cat(sprintf("Eval period: %s ~ %s (n=%d months)\n",
            as.character(min(pfx$anchor_date)),
            as.character(max(pfx$anchor_date)), nrow(pfx)))

# ── (3) Rolling 36m walk-forward ──
W <- 36
n_windows <- nrow(pfx) - W + 1
cat(sprintf("Rolling 36m windows: %d\n", n_windows))

wf <- vector("list", n_windows)
for (i in seq_len(n_windows)) {
  win <- pfx[i:(i + W - 1)]
  ret_base <- win$ret_L5_V5
  ret_hyb <- win$ret_hybrid
  ok <- !is.na(ret_base) & !is.na(ret_hyb)
  if (sum(ok) < 24) next

  xret_base <- xts::xts(ret_base[ok], order.by = win$anchor_date[ok])
  xret_hyb <- xts::xts(ret_hyb[ok], order.by = win$anchor_date[ok])

  sr_base <- as.numeric(table.AnnualizedReturns(xret_base, scale = 12, Rf = 0)[3, 1])
  sr_hyb <- as.numeric(table.AnnualizedReturns(xret_hyb, scale = 12, Rf = 0)[3, 1])
  mdd_base <- -as.numeric(maxDrawdown(xret_base))
  mdd_hyb <- -as.numeric(maxDrawdown(xret_hyb))
  cagr_base <- as.numeric(table.AnnualizedReturns(xret_base, scale = 12, Rf = 0)[1, 1])
  cagr_hyb <- as.numeric(table.AnnualizedReturns(xret_hyb, scale = 12, Rf = 0)[1, 1])

  wf[[i]] <- data.table(
    window_start = win$anchor_date[1],
    window_end = win$anchor_date[W],
    n_trigger_in_win = sum(win$bear_trigger_lag1),
    SR_base = round(sr_base, 4),
    SR_hyb = round(sr_hyb, 4),
    dSR = round(sr_hyb - sr_base, 4),
    MDD_base = round(mdd_base, 4),
    MDD_hyb = round(mdd_hyb, 4),
    dMDD = round(mdd_hyb - mdd_base, 4),
    dCAGR = round(cagr_hyb - cagr_base, 4)
  )
}
wf_dt <- rbindlist(wf)
cat(sprintf("\n━━━ Walk-forward 36m distribution (n=%d windows) ━━━\n", nrow(wf_dt)))
cat(sprintf("  dSR:   median %+.4f / mean %+.4f / IQR [%+.4f, %+.4f] / min %+.4f / max %+.4f\n",
            median(wf_dt$dSR), mean(wf_dt$dSR),
            quantile(wf_dt$dSR, 0.25), quantile(wf_dt$dSR, 0.75),
            min(wf_dt$dSR), max(wf_dt$dSR)))
cat(sprintf("  dMDD:  median %+.4f / mean %+.4f / IQR [%+.4f, %+.4f]\n",
            median(wf_dt$dMDD), mean(wf_dt$dMDD),
            quantile(wf_dt$dMDD, 0.25), quantile(wf_dt$dMDD, 0.75)))
cat(sprintf("  dCAGR: median %+.4f / mean %+.4f / IQR [%+.4f, %+.4f]\n",
            median(wf_dt$dCAGR), mean(wf_dt$dCAGR),
            quantile(wf_dt$dCAGR, 0.25), quantile(wf_dt$dCAGR, 0.75)))

# Win rate
win_rate_sr <- mean(wf_dt$dSR > 0)
win_rate_strict <- mean(wf_dt$dSR >= 0.1)
cat(sprintf("\n  Win rate dSR>0: %.0f%%%% (%d / %d windows)\n",
            100 * win_rate_sr, sum(wf_dt$dSR > 0), nrow(wf_dt)))
cat(sprintf("  Strict dSR>=0.1: %.0f%%%% (%d / %d)\n",
            100 * win_rate_strict, sum(wf_dt$dSR >= 0.1), nrow(wf_dt)))

# ── (4) Top/Bottom 5 windows ──
cat(sprintf("\n━━━ Top 5 windows (best dSR) ━━━\n"))
print(head(wf_dt[order(-dSR), .(window_start, window_end, n_trigger_in_win,
                                SR_base, SR_hyb, dSR, dMDD, dCAGR)], 5))
cat(sprintf("\n━━━ Bottom 5 windows (worst dSR) ━━━\n"))
print(head(wf_dt[order(dSR), .(window_start, window_end, n_trigger_in_win,
                                SR_base, SR_hyb, dSR, dMDD, dCAGR)], 5))

# ── (5) LOO (leave-one-year-out) sensitivity ──
cat(sprintf("\n━━━ Leave-One-Year-Out sensitivity ━━━\n"))
pfx[, yr := format(anchor_date, "%Y")]
all_yrs <- sort(unique(pfx$yr))
loo_res <- list()
for (yr_iter in all_yrs) {
  sub <- pfx[yr != yr_iter]
  if (nrow(sub) < 24) next
  xret_base <- xts::xts(sub$ret_L5_V5, order.by = sub$anchor_date)
  xret_hyb <- xts::xts(sub$ret_hybrid, order.by = sub$anchor_date)
  sr_b <- as.numeric(table.AnnualizedReturns(xret_base, scale = 12, Rf = 0)[3, 1])
  sr_h <- as.numeric(table.AnnualizedReturns(xret_hyb, scale = 12, Rf = 0)[3, 1])
  loo_res[[yr_iter]] <- data.table(year_excluded = yr_iter, n = nrow(sub),
                                    SR_base = round(sr_b, 4),
                                    SR_hyb = round(sr_h, 4),
                                    dSR = round(sr_h - sr_b, 4))
}
loo_dt <- rbindlist(loo_res)
print(loo_dt)
cat(sprintf("\n  LOO dSR range: [%+.4f, %+.4f]\n", min(loo_dt$dSR), max(loo_dt$dSR)))
cat(sprintf("  LOO dSR all > 0: %s\n", ifelse(all(loo_dt$dSR > 0), "YES (robust)", "NO (year-dependent)")))

# Identify critical year(s): which year drops dSR most when excluded
loo_dt[, drop_from_full := dSR - round(0.5715, 4)]  # vs full sample dSR=+0.5715
crit_yr <- loo_dt[order(drop_from_full)][1:3]
cat(sprintf("\n  Most critical 3 years (excluding causes most dSR drop):\n"))
print(crit_yr[, .(year_excluded, dSR_after_loo = dSR, drop_from_full)])

# ── (6) Persistence verdict ──
cat(sprintf("\n━━━ Persistence Verdict ━━━\n"))
verdict_reasons <- c()
verdict_ok <- TRUE
if (win_rate_sr >= 0.7) {
  cat(sprintf("  ✅ Walk-forward win rate %.0f%%%% ≥ 70%%%%\n", 100 * win_rate_sr))
} else {
  cat(sprintf("  ⚠️ Walk-forward win rate %.0f%%%% < 70%%%%\n", 100 * win_rate_sr))
  verdict_reasons <- c(verdict_reasons, sprintf("win_rate_%.0f%%", 100 * win_rate_sr))
  verdict_ok <- FALSE
}
if (median(wf_dt$dSR) > 0.1) {
  cat(sprintf("  ✅ Median walk-forward dSR %+.3f > +0.1\n", median(wf_dt$dSR)))
} else {
  cat(sprintf("  ⚠️ Median walk-forward dSR %+.3f ≤ +0.1\n", median(wf_dt$dSR)))
  verdict_reasons <- c(verdict_reasons, "median_dsr_weak")
}
if (all(loo_dt$dSR > 0)) {
  cat(sprintf("  ✅ All LOO dSR > 0 (no critical year dependency)\n"))
} else {
  cat(sprintf("  ❌ Some LOO dSR < 0 (critical year dependency)\n"))
  verdict_reasons <- c(verdict_reasons, "loo_year_dependent")
  verdict_ok <- FALSE
}
cat(sprintf("\n[VERDICT] Walk-forward persistence = %s\n",
            ifelse(verdict_ok, "PASS → proceed to PIT audit + Codex Critic Round",
                   sprintf("WEAK — %s", paste(verdict_reasons, collapse = ", ")))))

# ── (7) Save + chart ──
fwrite(wf_dt, file.path(EVAL_DIR, "walkforward_36m_windows.csv"))
fwrite(loo_dt, file.path(EVAL_DIR, "loo_year_sensitivity.csv"))
out <- list(
  n_windows = nrow(wf_dt),
  median_dSR = median(wf_dt$dSR),
  mean_dSR = mean(wf_dt$dSR),
  min_dSR = min(wf_dt$dSR),
  max_dSR = max(wf_dt$dSR),
  win_rate_sr_pos = win_rate_sr,
  win_rate_sr_strict = win_rate_strict,
  loo_all_positive = all(loo_dt$dSR > 0),
  loo_dSR_range = c(min(loo_dt$dSR), max(loo_dt$dSR)),
  most_critical_year = crit_yr$year_excluded[1],
  verdict = ifelse(verdict_ok, "PASS", "WEAK"),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "walkforward_stability.json"),
           auto_unbox = TRUE, pretty = TRUE)

# Chart: dSR distribution + time series
g1 <- ggplot(wf_dt, aes(x = dSR)) +
  geom_histogram(bins = 25, fill = "#073B4C", alpha = 0.7) +
  geom_vline(xintercept = 0, color = "red", linetype = "dashed") +
  geom_vline(xintercept = median(wf_dt$dSR), color = "#06D6A0", linewidth = 1) +
  labs(title = sprintf("Walk-forward 36m ΔSR distribution (n=%d windows)", nrow(wf_dt)),
       subtitle = sprintf("median %+.3f / win rate %.0f%%%% / range [%+.3f, %+.3f]",
                          median(wf_dt$dSR), 100 * win_rate_sr,
                          min(wf_dt$dSR), max(wf_dt$dSR)),
       x = "ΔSR (Hybrid - STR_1715)", y = "Count") +
  theme_minimal(base_size = 11)
g2 <- ggplot(wf_dt, aes(x = window_end, y = dSR)) +
  geom_line(color = "#073B4C", linewidth = 0.5) +
  geom_point(aes(color = dSR > 0), size = 1) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed") +
  scale_color_manual(values = c("TRUE" = "#06D6A0", "FALSE" = "#EF476F"),
                      labels = c("TRUE" = "win", "FALSE" = "lose"), name = NULL) +
  labs(title = "Rolling 36m ΔSR time series",
       x = "Window end date", y = "ΔSR") + theme_minimal(base_size = 11)
g_combined <- patchwork::wrap_plots(g1, g2, ncol = 1)
ggsave(file.path(CHART_DIR, "19_walkforward.png"),
       plot = g_combined, width = 12, height = 8, dpi = 120)
cat(sprintf("\n[Chart 19] %s/19_walkforward.png\n", CHART_DIR))
cat(sprintf("[JSON] %s/walkforward_stability.json\n", EVAL_DIR))

cat("\n[DONE]\n")
