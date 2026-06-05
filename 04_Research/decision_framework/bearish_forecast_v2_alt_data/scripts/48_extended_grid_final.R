#==============================================================================
# 48_extended_grid_final.R — Cycle 18 Extended grid (final local opt check)
#
# DD windows: 2, 3, 4, 5, 6 months (granular gap fill)
# DD thresholds: -3, -4, -5, -6, -7, -8, -9%% (6 levels)
# Alternative: single-month return trigger (ret_kospi[t-1] ≤ -X%%)
#
# Total: 5 × 7 + 4 single-month = 39 combos
#
# Goal: 진짜 local optimum 확정 + 도훈에게 최종 best 보고
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

panel_base <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
                     by = "realized_ym", all.x = TRUE)
setorder(panel_base, anchor_date)
panel_base[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel_base[, kospi_lvl := exp(kospi_log_cum)]

# Helpers
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

build_v1av3 <- function(pc, trigger_vec, cost = 0.003, dd_for_position = NULL) {
  pc <- copy(pc)
  pc[, bear_trigger := trigger_vec]
  pc[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
  pc[, trig_run := 0L]
  for (i in seq_len(nrow(pc))) {
    if (pc$bear_trigger_lag1[i]) {
      pc[i, trig_run := ifelse(i > 1 && pc$bear_trigger_lag1[i - 1],
                                 pc$trig_run[i - 1] + 1L, 1L)]
    }
  }
  pc[, active := bear_trigger_lag1 & trig_run <= 2]

  # Position formula uses dd_lag for V3 dynamic scaling
  if (is.null(dd_for_position)) {
    # Default: use 0.7 fixed (no dynamic scaling)
    pc[, pos_combo := 0.7]
  } else {
    pc[, dd_lag := shift(dd_for_position, 1, fill = 0)]
    pc[, pos_combo := pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))]
  }
  pc[, ret_active := pos_combo * ret_kospi]
  pc[, state := fifelse(active, "BEAR", "BULL")]
  pc[, state_change := state != shift(state, 1, fill = "BULL")]
  pc[, ret_hyb := fifelse(active, ret_active, ret_L5_V5)]
  pc[state_change == TRUE, ret_hyb := ret_hyb - cost]
  pc
}

m_base_267 <- compute_m(panel_base$ret_L5_V5, panel_base$anchor_date)
cat(sprintf("━━━ Cycle 18: Final extended grid ━━━\n"))
cat(sprintf("Baseline STR_1715: SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base_267["SR"], m_base_267["MDD"], m_base_267["CAGR"]))

# ── (2) DD window × threshold grid (5 × 7 = 35) ──
grid_dt <- data.table()
for (W_dd in c(2, 3, 4, 5, 6)) for (thr in c(-0.03, -0.04, -0.05, -0.06, -0.07, -0.08, -0.09)) {
  pc_tmp <- copy(panel_base)
  max_col <- "max_v"; dd_col <- "dd_v"
  pc_tmp[[max_col]] <- frollapply(pc_tmp$kospi_lvl, W_dd, max, align = "right")
  pc_tmp[[dd_col]] <- pc_tmp$kospi_lvl / pc_tmp[[max_col]] - 1
  trig_vec <- !is.na(pc_tmp[[dd_col]]) & pc_tmp[[dd_col]] <= thr
  pc <- build_v1av3(pc_tmp, trig_vec, dd_for_position = pc_tmp[[dd_col]])
  mm <- compute_m(pc$ret_hyb, pc$anchor_date)
  ht <- nw_t(pc$ret_hyb - pc$ret_L5_V5, 4)
  grid_dt <- rbind(grid_dt, data.table(
    type = "DD",
    W_dd = W_dd, threshold = thr,
    n_active = sum(pc$active),
    SR = round(mm["SR"], 4), MDD = round(mm["MDD"], 4),
    dSR = round(mm["SR"] - m_base_267["SR"], 4),
    dMDD = round(mm["MDD"] - m_base_267["MDD"], 4),
    harvey_t = round(ht, 3)))
}

# ── (3) Single-month return trigger (alternative type) ──
for (thr in c(-0.02, -0.03, -0.05, -0.07)) {
  trig_vec <- !is.na(panel_base$ret_kospi) & panel_base$ret_kospi <= thr
  # Position formula uses single-month return as "depth proxy"
  pc <- build_v1av3(panel_base, trig_vec,
                     dd_for_position = panel_base$ret_kospi)
  mm <- compute_m(pc$ret_hyb, pc$anchor_date)
  ht <- nw_t(pc$ret_hyb - pc$ret_L5_V5, 4)
  grid_dt <- rbind(grid_dt, data.table(
    type = "RET_1M",
    W_dd = 1, threshold = thr,
    n_active = sum(pc$active),
    SR = round(mm["SR"], 4), MDD = round(mm["MDD"], 4),
    dSR = round(mm["SR"] - m_base_267["SR"], 4),
    dMDD = round(mm["MDD"] - m_base_267["MDD"], 4),
    harvey_t = round(ht, 3)))
}

grid_dt[, verdict := fcase(
  dSR >= 0.05 & dMDD >= 0 & abs(harvey_t) > 3.0, "STRICT_HARVEY",
  dSR >= 0.05 & dMDD >= 0 & abs(harvey_t) > 2.0, "STRICT",
  dSR >= 0.05 & dMDD >= 0, "WEAK",
  dSR > 0, "MARGINAL",
  default = "REJECT")]
setorder(grid_dt, -dSR)

cat(sprintf("TOP 15 combinations:\n"))
print(head(grid_dt, 15))

# ── (4) Local optimum check for best ──
best <- grid_dt[1]
cat(sprintf("\n━━━ Best: type=%s, W=%d, thr=%.2f ━━━\n",
            best$type, best$W_dd, best$threshold))
cat(sprintf("  SR %.4f / MDD %+.4f / dSR %+.4f / Harvey-t %+.3f / %s\n",
            best$SR, best$MDD, best$dSR, best$harvey_t, best$verdict))

# Neighbors check (only for DD type)
if (best$type == "DD") {
  neighbors <- grid_dt[type == "DD" &
                        ((W_dd == best$W_dd - 1 & threshold == best$threshold) |
                         (W_dd == best$W_dd + 1 & threshold == best$threshold) |
                         (W_dd == best$W_dd & threshold == best$threshold - 0.01) |
                         (W_dd == best$W_dd & threshold == best$threshold + 0.01))]
  is_local <- best$SR >= max(neighbors$SR, na.rm = TRUE)
  cat(sprintf("\n  Local optimum check (vs 4 neighbors):\n"))
  for (i in seq_len(nrow(neighbors))) {
    cat(sprintf("    W=%d, thr=%.2f: SR %.3f / dSR %+.3f\n",
                neighbors$W_dd[i], neighbors$threshold[i],
                neighbors$SR[i], neighbors$dSR[i]))
  }
  cat(sprintf("\n  Local optimum: %s\n",
              ifelse(is_local, "YES", "NO (neighbor better)")))
}

# Compare best vs canonical 6m/-10%%
cat(sprintf("\n━━━ Best vs canonical comparison ━━━\n"))
# Compute canonical 6m/-10%% (not in current grid)
pc_canon <- copy(panel_base)
pc_canon[, max_v := frollapply(pc_canon$kospi_lvl, 6, max, align = "right")]
pc_canon[, dd_v := pc_canon$kospi_lvl / pc_canon$max_v - 1]
trig_canon <- !is.na(pc_canon$dd_v) & pc_canon$dd_v <= -0.10
pc_canon_h <- build_v1av3(pc_canon, trig_canon, dd_for_position = pc_canon$dd_v)
mm_canon <- compute_m(pc_canon_h$ret_hyb, pc_canon_h$anchor_date)
cat(sprintf("  Canonical 6m/-10%%: SR %.4f / dSR %+.4f / MDD %+.4f\n",
            mm_canon["SR"], mm_canon["SR"] - m_base_267["SR"], mm_canon["MDD"]))
cat(sprintf("  Best %s/%dm/%.2f: SR %.4f / dSR %+.4f / MDD %+.4f\n",
            best$type, best$W_dd, best$threshold, best$SR, best$dSR, best$MDD))
cat(sprintf("  ΔSR upgrade: %+.4f\n", best$dSR - (mm_canon["SR"] - m_base_267["SR"])))

# ── (5) Save ──
fwrite(grid_dt, file.path(EVAL_DIR, "extended_grid_final.csv"))
out <- list(
  best_overall = as.list(best),
  canonical_6m_neg10 = list(SR = unname(mm_canon["SR"]),
                             dSR = unname(mm_canon["SR"] - m_base_267["SR"]),
                             MDD = unname(mm_canon["MDD"])),
  grid_size = nrow(grid_dt),
  admit_strict_count = sum(grid_dt$verdict %in% c("STRICT", "STRICT_HARVEY")),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "extended_grid_final.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/extended_grid_final.json\n", EVAL_DIR))

# Chart heatmap (DD type only)
dd_only <- grid_dt[type == "DD"]
g <- ggplot(dd_only, aes(x = factor(100 * threshold),
                          y = factor(W_dd), fill = dSR)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.2f\n(t=%.1f)", dSR, harvey_t)),
            size = 2.5) +
  scale_fill_gradient2(low = "#073B4C", mid = "white", high = "#EF476F",
                       midpoint = 0) +
  labs(title = "Cycle 18 Final Grid — DD window × threshold (267m, V1a+V3)",
       subtitle = sprintf("Best: %dm/%.0f%%%% dSR %+.3f t=%.2f | Canonical 6m/-10%%%% dSR %+.3f",
                          best$W_dd, 100 * best$threshold,
                          best$dSR, best$harvey_t,
                          mm_canon["SR"] - m_base_267["SR"]),
       x = "DD threshold (%%)", y = "DD window (months)", fill = "ΔSR") +
  theme_minimal(base_size = 10)
ggsave(file.path(CHART_DIR, "27_final_grid.png"),
       plot = g, width = 11, height = 5, dpi = 120)
cat(sprintf("[Chart 27] %s/27_final_grid.png\n", CHART_DIR))

cat("\n[DONE]\n")
