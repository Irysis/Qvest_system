#==============================================================================
# 44_v1a_v3_deep_validation.R — Cycle 14 V1a+V3 Combined Deep Validation
#
# Strategy:
#   active = bear_trigger_lag1 AND trig_run <= 2
#   position when active = max(0, 0.7 - 3 * max(0, -(dd_lag1 + 0.10)))
#   else: STR_1715 baseline
#   30bps switching cost
#
# Tests:
#   1. 267m walk-forward 36m rolling
#   2. LOO year sensitivity
#   3. Per-episode bear_trigger performance
#   4. Bootstrap CI for dSR (B=2000)
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

# ── (1) Build V1a+V3 panel ──
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
eom <- bm[, .(close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

panel <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
panel[, kospi_dd_6m_lag1 := shift(kospi_dd_6m, 1, fill = 0)]
panel[, trig_run := 0L]
for (i in seq_len(nrow(panel))) {
  if (panel$bear_trigger_lag1[i]) {
    panel[i, trig_run := ifelse(i > 1 && panel$bear_trigger_lag1[i - 1],
                                  panel$trig_run[i - 1] + 1L, 1L)]
  }
}

# V1a+V3 combined
panel[, active := bear_trigger_lag1 & trig_run <= 2]
panel[, pos_combo := pmax(0.0, 0.7 - 3.0 * pmax(0, -(kospi_dd_6m_lag1 + 0.10)))]
panel[, ret_active := pos_combo * ret_kospi]
panel[, state := fifelse(active, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]
panel[, ret_V1aV3 := fifelse(active, ret_active, ret_L5_V5)]
panel[state_change == TRUE, ret_V1aV3 := ret_V1aV3 - 0.003]

cat(sprintf("[Panel] %d months / active months: %d / state switches: %d\n",
            nrow(panel), sum(panel$active), sum(panel$state_change)))

# ── (2) Walk-forward 36m on full 267m ──
compute_m <- function(ret_vec, dates) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 12) return(c(SR = NA, MDD = NA, CAGR = NA))
  xret <- xts::xts(r, order.by = d)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  c(SR = as.numeric(ann[3, 1]),
    MDD = -as.numeric(maxDrawdown(xret)),
    CAGR = as.numeric(ann[1, 1]))
}
nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  if (n < 10) return(NA)
  S <- sum(resid^2) / n
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  xbar / sqrt(S / n)
}

W <- 36
n_win <- nrow(panel) - W + 1
wf <- list()
for (i in seq_len(n_win)) {
  win <- panel[i:(i + W - 1)]
  if (sum(!is.na(win$ret_V1aV3)) < 24) next
  m_b <- compute_m(win$ret_L5_V5, win$anchor_date)
  m_h <- compute_m(win$ret_V1aV3, win$anchor_date)
  wf[[i]] <- data.table(
    win_start = win$anchor_date[1], win_end = win$anchor_date[W],
    SR_base = round(m_b["SR"], 3), SR_hyb = round(m_h["SR"], 3),
    dSR = round(m_h["SR"] - m_b["SR"], 4),
    dMDD = round(m_h["MDD"] - m_b["MDD"], 4),
    n_trig = sum(win$active))
}
wf_dt <- rbindlist(wf)
win_rate <- mean(wf_dt$dSR > 0)

cat(sprintf("\n━━━ Walk-forward 36m (V1a+V3, full 267m) ━━━\n"))
cat(sprintf("  N windows: %d\n", nrow(wf_dt)))
cat(sprintf("  Win rate dSR>0: %.0f%%%% (%d/%d)\n",
            100 * win_rate, sum(wf_dt$dSR > 0), nrow(wf_dt)))
cat(sprintf("  dSR: median %+.4f / mean %+.4f / IQR [%+.4f, %+.4f]\n",
            median(wf_dt$dSR), mean(wf_dt$dSR),
            quantile(wf_dt$dSR, 0.25), quantile(wf_dt$dSR, 0.75)))
cat(sprintf("  dSR: min %+.4f / max %+.4f\n", min(wf_dt$dSR), max(wf_dt$dSR)))
cat(sprintf("\n  Bottom 5 windows (worst dSR):\n"))
print(head(wf_dt[order(dSR), .(win_start, win_end, SR_base, SR_hyb, dSR, dMDD, n_trig)], 5))

# ── (3) LOO year sensitivity ──
cat(sprintf("\n━━━ LOO year sensitivity (267m) ━━━\n"))
panel[, yr := format(anchor_date, "%Y")]
all_yrs <- sort(unique(panel$yr))
loo_res <- list()
for (yr_iter in all_yrs) {
  sub <- panel[yr != yr_iter]
  if (nrow(sub) < 24) next
  m_b <- compute_m(sub$ret_L5_V5, sub$anchor_date)
  m_h <- compute_m(sub$ret_V1aV3, sub$anchor_date)
  loo_res[[yr_iter]] <- data.table(year_excluded = yr_iter,
                                    SR_base = round(m_b["SR"], 4),
                                    SR_hyb = round(m_h["SR"], 4),
                                    dSR = round(m_h["SR"] - m_b["SR"], 4))
}
loo_dt <- rbindlist(loo_res)
cat(sprintf("  LOO dSR: range [%+.4f, %+.4f]\n", min(loo_dt$dSR), max(loo_dt$dSR)))
cat(sprintf("  All LOO > 0: %s\n", ifelse(all(loo_dt$dSR > 0), "YES", "NO")))
# Find most critical year
full_dSR <- m_h <- compute_m(panel$ret_V1aV3, panel$anchor_date)["SR"] -
                    compute_m(panel$ret_L5_V5, panel$anchor_date)["SR"]
loo_dt[, drop := dSR - round(full_dSR, 4)]
crit <- loo_dt[order(drop)][1:3]
cat(sprintf("\n  Most critical 3 years:\n"))
print(crit)

# ── (4) Per-episode performance ──
panel[, trig_group := cumsum(state != shift(state, 1, fill = "BULL"))]
ep_dt <- panel[active == TRUE,
               .(period = sprintf("%s ~ %s",
                                  format(min(anchor_date), "%Y-%m"),
                                  format(max(anchor_date), "%Y-%m")),
                 n_months = .N,
                 cum_base = prod(1 + ret_L5_V5) - 1,
                 cum_hyb = prod(1 + ret_V1aV3) - 1,
                 cum_kospi = prod(1 + ret_kospi) - 1),
               by = trig_group]
ep_dt[, edge := cum_hyb - cum_base]
cat(sprintf("\n━━━ Per-episode performance ━━━\n"))
print(ep_dt[order(trig_group), .(period, n_months,
                                  cum_base = round(cum_base * 100, 2),
                                  cum_hyb = round(cum_hyb * 100, 2),
                                  cum_kospi = round(cum_kospi * 100, 2),
                                  edge_pp = round(edge * 100, 2))])
cat(sprintf("\n  Wins (edge > 0): %d / %d episodes (%.0f%%%%)\n",
            sum(ep_dt$edge > 0), nrow(ep_dt), 100 * mean(ep_dt$edge > 0)))
cat(sprintf("  Average edge: %+.2f pp\n", 100 * mean(ep_dt$edge)))

# ── (5) Bootstrap CI for dSR ──
cat(sprintf("\n━━━ Bootstrap CI for dSR (B=2000) ━━━\n"))
set.seed(42)
B <- 2000
boot_dSR <- numeric(B)
for (b in seq_len(B)) {
  idx <- sample(nrow(panel), nrow(panel), replace = TRUE)
  sub <- panel[idx]
  sr_b <- compute_m(sub$ret_L5_V5, sub$anchor_date)["SR"]
  sr_h <- compute_m(sub$ret_V1aV3, sub$anchor_date)["SR"]
  boot_dSR[b] <- sr_h - sr_b
}
boot_dSR <- boot_dSR[!is.na(boot_dSR)]
cat(sprintf("  Mean dSR: %+.4f\n", mean(boot_dSR)))
cat(sprintf("  95%% CI: [%+.4f, %+.4f]\n",
            quantile(boot_dSR, 0.025), quantile(boot_dSR, 0.975)))
ci_includes_0 <- quantile(boot_dSR, 0.025) <= 0 & quantile(boot_dSR, 0.975) >= 0
cat(sprintf("  CI includes 0: %s\n",
            ifelse(ci_includes_0, "YES (insignificant)", "NO (significant)")))

# ── (6) Final verdict ──
all_admit <- (win_rate >= 0.6 &&
               all(loo_dt$dSR > 0) &&
               !ci_includes_0 &&
               mean(ep_dt$edge > 0) >= 0.7)
cat(sprintf("\n━━━ Cycle 14 Final Verdict ━━━\n"))
cat(sprintf("  Walk-forward win rate ≥60%%: %s (%.0f%%%%)\n",
            ifelse(win_rate >= 0.6, "✅", "❌"), 100 * win_rate))
cat(sprintf("  LOO all positive: %s\n", ifelse(all(loo_dt$dSR > 0), "✅", "❌")))
cat(sprintf("  Bootstrap CI > 0: %s\n", ifelse(!ci_includes_0, "✅", "❌")))
cat(sprintf("  Episodes win ≥70%%: %s (%.0f%%%%)\n",
            ifelse(mean(ep_dt$edge > 0) >= 0.7, "✅", "❌"),
            100 * mean(ep_dt$edge > 0)))
cat(sprintf("\n[VERDICT] %s\n",
            ifelse(all_admit,
                   "✅ ALL PASS → V1a+V3 ADMIT-ready, proceed to spec / Codex",
                   "⚠️ PARTIAL — see individual checks")))

# ── (7) Save + chart ──
out <- list(
  walkforward = list(n = nrow(wf_dt), win_rate = win_rate,
                      median_dSR = median(wf_dt$dSR),
                      min_dSR = min(wf_dt$dSR), max_dSR = max(wf_dt$dSR)),
  loo_all_positive = all(loo_dt$dSR > 0),
  loo_dSR_range = c(min(loo_dt$dSR), max(loo_dt$dSR)),
  most_critical_year = crit$year_excluded[1],
  per_episode = list(n_ep = nrow(ep_dt),
                      win_rate = mean(ep_dt$edge > 0),
                      avg_edge_pp = 100 * mean(ep_dt$edge)),
  bootstrap = list(B = B, mean_dSR = mean(boot_dSR),
                    ci_lo = unname(quantile(boot_dSR, 0.025)),
                    ci_hi = unname(quantile(boot_dSR, 0.975))),
  final_verdict = ifelse(all_admit, "PASS", "PARTIAL"),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v1a_v3_deep_validation.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v1a_v3_deep_validation.json\n", EVAL_DIR))

# Chart: walkforward + per-episode
g1 <- ggplot(wf_dt, aes(x = win_end, y = dSR)) +
  geom_line(color = "#073B4C", linewidth = 0.4) +
  geom_point(aes(color = dSR > 0), size = 1) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed") +
  scale_color_manual(values = c("TRUE" = "#06D6A0", "FALSE" = "#EF476F"),
                      labels = c("TRUE" = "win", "FALSE" = "lose"), name = NULL) +
  labs(title = sprintf("V1a+V3 walk-forward 36m (n=%d windows)", nrow(wf_dt)),
       subtitle = sprintf("Win rate %.0f%%%% / median %+.3f", 100 * win_rate, median(wf_dt$dSR)),
       x = NULL, y = "ΔSR") + theme_minimal(base_size = 10)
g2 <- ggplot(ep_dt, aes(x = trig_group, y = 100 * edge, fill = edge > 0)) +
  geom_col(alpha = 0.8) + geom_hline(yintercept = 0, color = "gray60") +
  scale_fill_manual(values = c("TRUE" = "#06D6A0", "FALSE" = "#EF476F"), name = NULL) +
  labs(title = "Per-episode edge (Hybrid - STR_1715)",
       x = "Episode #", y = "Edge (pp)") + theme_minimal(base_size = 10)
g_comb <- patchwork::wrap_plots(g1, g2, ncol = 1)
ggsave(file.path(CHART_DIR, "24_v1a_v3_validation.png"),
       plot = g_comb, width = 13, height = 8, dpi = 120)
cat(sprintf("[Chart 24] %s/24_v1a_v3_validation.png\n", CHART_DIR))

cat("\n[DONE]\n")
