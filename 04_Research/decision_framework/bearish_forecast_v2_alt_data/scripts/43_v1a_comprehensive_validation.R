#==============================================================================
# 43_v1a_comprehensive_validation.R — Cycle 13 V1a Comprehensive Validation
#
# Part 1: V1a walk-forward 36m rolling (on 110m + 267m)
# Part 2: Persistence threshold sensitivity (N = 1, 2, 3, 4)
# Part 3: Position size sensitivity (0.5, 0.7, 1.0)
# Part 4: Switching cost sensitivity (15, 30, 60 bps)
# Part 5: Combined V1a + V3 (dynamic + re-entry)
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

# ── (1) Load baseline + KOSPI ──
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

panel <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

# Bear trigger (10%% DD)
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
panel[, kospi_dd_6m_lag1 := shift(kospi_dd_6m, 1, fill = 0)]

# Trigger run computation
panel[, trig_run := 0L]
for (i in seq_len(nrow(panel))) {
  if (panel$bear_trigger_lag1[i]) {
    panel[i, trig_run := ifelse(i > 1 && panel$bear_trigger_lag1[i - 1],
                                  panel$trig_run[i - 1] + 1L, 1L)]
  }
}

# ── Helper functions ──
build_hybrid_ret <- function(panel_dt, N_persistence, position, cost_bps) {
  cost <- cost_bps / 10000
  panel_dt[, active := bear_trigger_lag1 & trig_run <= N_persistence]
  panel_dt[, ret_active := position * ret_kospi]
  panel_dt[, state := fifelse(active, "BEAR", "BULL")]
  panel_dt[, state_change := state != shift(state, 1, fill = "BULL")]
  panel_dt[, ret_hyb := fifelse(active, ret_active, ret_L5_V5)]
  panel_dt[state_change == TRUE, ret_hyb := ret_hyb - cost]
  panel_dt$ret_hyb
}

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

# ── (2) Sensitivity grid ──
cat(sprintf("━━━ Sensitivity grid (N_persistence × position × cost) on 267m ━━━\n\n"))
N_vals <- c(1, 2, 3, 4); pos_vals <- c(0.5, 0.7, 1.0); cost_vals <- c(15, 30, 60)
grid_dt <- data.table()
m_base_267 <- compute_m(panel$ret_L5_V5, panel$anchor_date)
for (N in N_vals) for (pos in pos_vals) for (cost in cost_vals) {
  pcopy <- copy(panel)
  ret_hyb <- build_hybrid_ret(pcopy, N, pos, cost)
  mm <- compute_m(ret_hyb, pcopy$anchor_date)
  diff_ret <- ret_hyb - pcopy$ret_L5_V5
  ht <- nw_t(diff_ret, 4)
  grid_dt <- rbind(grid_dt, data.table(
    N = N, position = pos, cost_bps = cost,
    SR = round(mm["SR"], 4), MDD = round(mm["MDD"], 4), CAGR = round(mm["CAGR"], 4),
    dSR = round(mm["SR"] - m_base_267["SR"], 4),
    dMDD = round(mm["MDD"] - m_base_267["MDD"], 4),
    dCAGR = round(mm["CAGR"] - m_base_267["CAGR"], 4),
    harvey_t = round(ht, 3)
  ))
}
grid_dt[, verdict := fcase(
  dSR >= 0.05 & dMDD >= 0 & abs(harvey_t) > 2.0, "ADMIT_STRICT",
  dSR >= 0.05 & dMDD >= 0, "ADMIT_WEAK",
  dSR > 0, "MARGINAL",
  default = "REJECT")]
setorder(grid_dt, -dSR)
cat("TOP 10 grid combinations (267m):\n")
print(head(grid_dt, 10))
cat(sprintf("\nADMIT_STRICT count: %d / %d\n", sum(grid_dt$verdict == "ADMIT_STRICT"), nrow(grid_dt)))
cat(sprintf("ANY ADMIT count   : %d / %d (%.0f%%%%)\n",
            sum(grid_dt$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
            nrow(grid_dt),
            100 * mean(grid_dt$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK"))))

# Per-dimension robustness
cat(sprintf("\nBy N_persistence:\n"))
for (N_loop in N_vals) {
  sub <- grid_dt[N == N_loop]
  cat(sprintf("  N=%d: %d/%d admit (%.0f%%%%) / median dSR %+.3f\n",
              N_loop, sum(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              nrow(sub),
              100 * mean(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              median(sub$dSR)))
}
cat(sprintf("By position:\n"))
for (p in pos_vals) {
  sub <- grid_dt[position == p]
  cat(sprintf("  pos=%.1f: %d/%d admit (%.0f%%%%) / median dSR %+.3f\n",
              p, sum(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              nrow(sub),
              100 * mean(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              median(sub$dSR)))
}
cat(sprintf("By cost (bps):\n"))
for (c_bps in cost_vals) {
  sub <- grid_dt[cost_bps == c_bps]
  cat(sprintf("  %dbps: %d/%d admit (%.0f%%%%) / median dSR %+.3f\n",
              c_bps, sum(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              nrow(sub),
              100 * mean(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              median(sub$dSR)))
}

# ── (3) Walk-forward 36m rolling for best V1a (N=2, pos=0.7, cost=30) ──
cat(sprintf("\n━━━ Walk-forward 36m rolling — V1a (N=2, pos=0.7, 30bps) ━━━\n"))
pcopy <- copy(panel)
panel[, ret_V1a := build_hybrid_ret(pcopy, 2, 0.7, 30)]

W <- 36
n_win <- nrow(panel) - W + 1
wf <- list()
for (i in seq_len(n_win)) {
  win <- panel[i:(i + W - 1)]
  if (sum(!is.na(win$ret_V1a)) < 24) next
  m_b <- compute_m(win$ret_L5_V5, win$anchor_date)
  m_h <- compute_m(win$ret_V1a, win$anchor_date)
  wf[[i]] <- data.table(
    win_start = win$anchor_date[1], win_end = win$anchor_date[W],
    SR_base = round(m_b["SR"], 3), SR_hyb = round(m_h["SR"], 3),
    dSR = round(m_h["SR"] - m_b["SR"], 4),
    dMDD = round(m_h["MDD"] - m_b["MDD"], 4),
    n_trig = sum(win$bear_trigger_lag1 & win$trig_run <= 2))
}
wf_dt <- rbindlist(wf)
win_rate <- mean(wf_dt$dSR > 0)
cat(sprintf("  N windows: %d\n", nrow(wf_dt)))
cat(sprintf("  Win rate dSR>0: %.0f%%%% (%d/%d)\n",
            100 * win_rate, sum(wf_dt$dSR > 0), nrow(wf_dt)))
cat(sprintf("  dSR distribution: median %+.4f / mean %+.4f / min %+.4f / max %+.4f\n",
            median(wf_dt$dSR), mean(wf_dt$dSR), min(wf_dt$dSR), max(wf_dt$dSR)))
cat(sprintf("  dSR IQR: [%+.4f, %+.4f]\n",
            quantile(wf_dt$dSR, 0.25), quantile(wf_dt$dSR, 0.75)))

# Bottom 5
cat(sprintf("\n  Bottom 5 windows (worst dSR):\n"))
print(head(wf_dt[order(dSR), .(win_start, win_end, SR_base, SR_hyb, dSR, dMDD, n_trig)], 5))

# ── (4) V1a + V3 combined (dynamic position with re-entry rule) ──
cat(sprintf("\n━━━ Combined V1a+V3: re-entry + dynamic position scaling ━━━\n"))
# V1a + V3: active = bear_trigger AND trig_run <= 2
# Position when active = 0.7 - 3 * max(0, -(dd_lag1 + 0.10))
panel_v <- copy(panel)
panel_v[, active := bear_trigger_lag1 & trig_run <= 2]
panel_v[, pos_dynamic := pmax(0.0, 0.7 - 3.0 * pmax(0, -(kospi_dd_6m_lag1 + 0.10)))]
panel_v[, ret_active := pos_dynamic * ret_kospi]
panel_v[, state := fifelse(active, "BEAR", "BULL")]
panel_v[, state_change := state != shift(state, 1, fill = "BULL")]
panel_v[, ret_combined := fifelse(active, ret_active, ret_L5_V5)]
panel_v[state_change == TRUE, ret_combined := ret_combined - 0.003]

for (win_name in c("full267", "adm255", "fx110")) {
  win_p <- switch(win_name,
                   full267 = panel_v[realized_ym >= "2004-02" & realized_ym <= "2026-04"],
                   adm255 = panel_v[realized_ym >= "2005-02" & realized_ym <= "2026-04"],
                   fx110 = panel_v[anchor_date >= as.Date("2017-03-01")])
  m_b <- compute_m(win_p$ret_L5_V5, win_p$anchor_date)
  m_h <- compute_m(win_p$ret_combined, win_p$anchor_date)
  ht <- nw_t(win_p$ret_combined - win_p$ret_L5_V5, 4)
  dSR <- m_h["SR"] - m_b["SR"]; dMDD <- m_h["MDD"] - m_b["MDD"]
  verdict <- fcase(
    dSR >= 0.05 & dMDD >= 0 & abs(ht) > 2.0, "ADMIT_STRICT",
    dSR >= 0.05 & dMDD >= 0, "ADMIT_WEAK",
    dSR > 0, "MARGINAL", default = "REJECT")
  cat(sprintf("  %s: SR %.3f→%.3f (Δ%+.3f) MDD %+.3f→%+.3f (Δ%+.3f) t=%+.2f / %s\n",
              win_name, m_b["SR"], m_h["SR"], dSR, m_b["MDD"], m_h["MDD"], dMDD, ht, verdict))
}

# ── (5) Save + chart ──
fwrite(grid_dt, file.path(EVAL_DIR, "v1a_sensitivity_grid.csv"))
fwrite(wf_dt, file.path(EVAL_DIR, "v1a_walkforward.csv"))

out <- list(
  best_grid = list(
    N = grid_dt$N[1], position = grid_dt$position[1], cost_bps = grid_dt$cost_bps[1],
    SR = grid_dt$SR[1], dSR = grid_dt$dSR[1],
    MDD = grid_dt$MDD[1], dMDD = grid_dt$dMDD[1],
    harvey_t = grid_dt$harvey_t[1], verdict = grid_dt$verdict[1]),
  grid_size = nrow(grid_dt),
  admit_strict_count = sum(grid_dt$verdict == "ADMIT_STRICT"),
  any_admit_count = sum(grid_dt$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
  walkforward_v1a = list(
    n_windows = nrow(wf_dt),
    win_rate_dsr_pos = win_rate,
    median_dsr = median(wf_dt$dSR),
    mean_dsr = mean(wf_dt$dSR),
    min_dsr = min(wf_dt$dSR),
    max_dsr = max(wf_dt$dSR)),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v1a_comprehensive_validation.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v1a_comprehensive_validation.json\n", EVAL_DIR))

# Chart: walkforward dSR
g <- ggplot(wf_dt, aes(x = win_end, y = dSR)) +
  geom_line(color = "#073B4C", linewidth = 0.5) +
  geom_point(aes(color = dSR > 0), size = 1.2) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed") +
  scale_color_manual(values = c("TRUE" = "#06D6A0", "FALSE" = "#EF476F"),
                      labels = c("TRUE" = "win", "FALSE" = "lose"), name = NULL) +
  labs(title = "V1a (N=2 / pos=0.7 / 30bps) — 36m rolling ΔSR",
       subtitle = sprintf("Win rate %.0f%%%% / median %+.3f / range [%+.3f, %+.3f] / n=%d",
                          100 * win_rate, median(wf_dt$dSR),
                          min(wf_dt$dSR), max(wf_dt$dSR), nrow(wf_dt)),
       x = "Window end", y = "ΔSR") + theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "23_v1a_walkforward.png"),
       plot = g, width = 13, height = 5, dpi = 120)
cat(sprintf("[Chart 23] %s/23_v1a_walkforward.png\n", CHART_DIR))

cat("\n[DONE]\n")
