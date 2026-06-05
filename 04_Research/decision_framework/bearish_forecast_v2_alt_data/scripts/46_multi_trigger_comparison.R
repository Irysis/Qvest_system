#==============================================================================
# 46_multi_trigger_comparison.R — Cycle 16 Multi-trigger comparison
#
# Tests alternative bear triggers (DD window × threshold grid):
#   DD windows: 3m, 6m (current), 9m, 12m
#   DD thresholds: -5%%, -8%%, -10%% (current), -12%%, -15%%, -20%%
#
# All paired with V1a+V3 active strategy (trig_run≤2 + dynamic position).
# Compare against current canonical (6m, -10%%).
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

# ── (1) Load data ──
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

# Pre-compute DD windows
for (W_dd in c(3, 6, 9, 12)) {
  max_col <- paste0("max_", W_dd, "m")
  dd_col <- paste0("dd_", W_dd, "m")
  panel[[max_col]] <- frollapply(panel$kospi_lvl, W_dd, max, align = "right")
  panel[[dd_col]] <- panel$kospi_lvl / panel[[max_col]] - 1
  lag_col <- paste0("dd_", W_dd, "m_lag1")
  panel[[lag_col]] <- shift(panel[[dd_col]], 1, fill = 0)
}

# ── (2) Build V1a+V3 hybrid for each (DD window, threshold) combo ──
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

m_base_267 <- compute_m(panel$ret_L5_V5, panel$anchor_date)
cat(sprintf("━━━ Multi-trigger comparison (V1a+V3, 267m) ━━━\n"))
cat(sprintf("Baseline STR_1715: SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base_267["SR"], m_base_267["MDD"], m_base_267["CAGR"]))

W_vals <- c(3, 6, 9, 12)
thr_vals <- c(-0.05, -0.08, -0.10, -0.12, -0.15, -0.20)
grid_dt <- data.table()
for (W_dd in W_vals) for (thr in thr_vals) {
  pc <- copy(panel)
  dd_col <- paste0("dd_", W_dd, "m")
  dd_lag_col <- paste0("dd_", W_dd, "m_lag1")
  pc[, bear_trigger := !is.na(get(dd_col)) & get(dd_col) <= thr]
  pc[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
  pc[, trig_run := 0L]
  for (i in seq_len(nrow(pc))) {
    if (pc$bear_trigger_lag1[i]) {
      pc[i, trig_run := ifelse(i > 1 && pc$bear_trigger_lag1[i - 1],
                                 pc$trig_run[i - 1] + 1L, 1L)]
    }
  }
  pc[, active := bear_trigger_lag1 & trig_run <= 2]
  pc[, pos_combo := pmax(0.0, 0.7 - 3.0 * pmax(0, -(get(dd_lag_col) + 0.10)))]
  pc[, ret_active := pos_combo * ret_kospi]
  pc[, state := fifelse(active, "BEAR", "BULL")]
  pc[, state_change := state != shift(state, 1, fill = "BULL")]
  pc[, ret_hyb := fifelse(active, ret_active, ret_L5_V5)]
  pc[state_change == TRUE, ret_hyb := ret_hyb - 0.003]

  mm <- compute_m(pc$ret_hyb, pc$anchor_date)
  diff_ret <- pc$ret_hyb - pc$ret_L5_V5
  ht <- nw_t(diff_ret, 4)
  n_active <- sum(pc$active, na.rm = TRUE)

  grid_dt <- rbind(grid_dt, data.table(
    DD_window = W_dd, DD_threshold_pct = 100 * thr,
    n_active = n_active,
    SR_hyb = round(mm["SR"], 4),
    MDD_hyb = round(mm["MDD"], 4),
    CAGR_hyb = round(mm["CAGR"], 4),
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

cat(sprintf("TOP 10 trigger combos (267m):\n"))
print(head(grid_dt, 10))

# Best vs canonical comparison
canonical <- grid_dt[DD_window == 6 & DD_threshold_pct == -10]
best <- grid_dt[1]
cat(sprintf("\n━━━ Best vs Canonical ━━━\n"))
cat(sprintf("  Canonical (6m, -10%%%%):\n"))
cat(sprintf("    SR %.4f / MDD %+.4f / dSR %+.4f / Harvey-t %+.3f / %s\n",
            canonical$SR_hyb, canonical$MDD_hyb, canonical$dSR,
            canonical$harvey_t, canonical$verdict))
cat(sprintf("  Best (%dm, %.0f%%%%):\n",
            best$DD_window, best$DD_threshold_pct))
cat(sprintf("    SR %.4f / MDD %+.4f / dSR %+.4f / Harvey-t %+.3f / %s\n",
            best$SR_hyb, best$MDD_hyb, best$dSR,
            best$harvey_t, best$verdict))
cat(sprintf("  Improvement: ΔdSR %+.4f / ΔdMDD %+.4f / Δharvey_t %+.3f\n",
            best$dSR - canonical$dSR, best$dMDD - canonical$dMDD,
            best$harvey_t - canonical$harvey_t))

# Summary
cat(sprintf("\n━━━ Robustness Summary ━━━\n"))
n_admit_strict <- sum(grid_dt$verdict == "ADMIT_STRICT")
n_admit_any <- sum(grid_dt$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK"))
cat(sprintf("  ADMIT_STRICT: %d / %d (%.0f%%%%)\n",
            n_admit_strict, nrow(grid_dt), 100 * n_admit_strict / nrow(grid_dt)))
cat(sprintf("  ANY ADMIT   : %d / %d (%.0f%%%%)\n",
            n_admit_any, nrow(grid_dt), 100 * n_admit_any / nrow(grid_dt)))

# Per-dimension admit rate
cat(sprintf("\nBy DD window:\n"))
for (W_loop in W_vals) {
  sub <- grid_dt[DD_window == W_loop]
  cat(sprintf("  %dm: %d/%d admit (%.0f%%%%) / median dSR %+.3f\n",
              W_loop, sum(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              nrow(sub),
              100 * mean(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              median(sub$dSR)))
}
cat(sprintf("\nBy DD threshold:\n"))
for (t_loop in thr_vals) {
  sub <- grid_dt[DD_threshold_pct == 100 * t_loop]
  cat(sprintf("  %.0f%%%%: %d/%d admit (%.0f%%%%) / median dSR %+.3f\n",
              100 * t_loop, sum(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              nrow(sub),
              100 * mean(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              median(sub$dSR)))
}

# ── (3) Save ──
fwrite(grid_dt, file.path(EVAL_DIR, "multi_trigger_grid.csv"))
out <- list(
  baseline = list(SR = unname(m_base_267["SR"]),
                   MDD = unname(m_base_267["MDD"]),
                   CAGR = unname(m_base_267["CAGR"])),
  canonical_6m_neg10 = as.list(canonical),
  best = as.list(best),
  grid_size = nrow(grid_dt),
  admit_strict_count = n_admit_strict,
  any_admit_count = n_admit_any,
  robust_pct = 100 * n_admit_any / nrow(grid_dt),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "multi_trigger_comparison.json"),
           auto_unbox = TRUE, pretty = TRUE)

# ── (4) Chart: heatmap of dSR by (window × threshold) ──
g <- ggplot(grid_dt, aes(x = factor(DD_threshold_pct),
                          y = factor(DD_window), fill = dSR)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.3f\n(t=%.1f)", dSR, harvey_t)),
            size = 3, color = "black") +
  scale_fill_gradient2(low = "#073B4C", mid = "white", high = "#EF476F",
                       midpoint = 0) +
  labs(title = "Multi-trigger comparison — V1a+V3 ΔSR (267m)",
       subtitle = sprintf("Canonical 6m/-10%%%% ΔSR %+.3f | Best %dm/%.0f%%%% ΔSR %+.3f",
                          canonical$dSR, best$DD_window,
                          best$DD_threshold_pct, best$dSR),
       x = "DD threshold (%%)", y = "DD window (months)", fill = "ΔSR") +
  theme_minimal(base_size = 10)
ggsave(file.path(CHART_DIR, "25_multi_trigger.png"),
       plot = g, width = 11, height = 5, dpi = 120)
cat(sprintf("\n[Chart 25] %s/25_multi_trigger.png\n", CHART_DIR))
cat(sprintf("[JSON] %s/multi_trigger_comparison.json\n", EVAL_DIR))

cat("\n[DONE]\n")
