#==============================================================================
# 33_contrarian_leverage_backtest.R — Cycle 3.1 Contrarian Application
#
# Hypothesis: 4-overlay 중 ≥3 동시 alert는 lag로 인한 mean-reversion signal
# → STR_1715 leverage up (1.2x / 1.5x) 가 alpha 생성 가능
#
# 3 variants:
#   V_C1 (mild): ≥3 alert → leverage 1.2x
#   V_C2 (medium): ≥3 alert → leverage 1.5x
#   V_C3 (asymmetric): ≥3 alert → 1.5x, ≥2 alert → 1.2x, ≤1 alert → 1.0x
#
# Constraints:
#   - Leverage 적용은 admit STR_1715_AR_on_M4_R05_overlay_PG2 base에 추가
#   - 매월 결정 t-1 EOM 4-overlay alerts 보고 lev_factor 결정
#   - Leverage cost: 추가 borrowing 비용 무시 (현실은 100~200bps but 본 cycle simplified)
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

# ── (1) Load baseline + overlay alerts ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

audit <- fread(file.path(EVAL_DIR, "multi_overlay_alert_audit.csv"))
audit[, n_alerts := as.integer(alert_m4) + as.integer(alert_AR) +
                     as.integer(alert_R05) + as.integer(alert_FX)]
audit[, yr := as.integer(substr(ym, 1, 4))]
audit[, mn := as.integer(substr(ym, 6, 7))]
audit[, next_yr := ifelse(mn == 12, yr + 1, yr)]
audit[, next_mn := ifelse(mn == 12, 1, mn + 1)]
audit[, realized_ym := sprintf("%04d-%02d", next_yr, next_mn)]

# Merge n_alerts to baseline panel
panel <- merge(baseline, audit[, .(realized_ym, n_alerts)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(n_alerts), n_alerts := 0]
setorder(panel, anchor_date)

# ── (2) Leverage variants ──
# V_C1 mild: lev_factor = 1.2 if n_alerts >= 3, else 1.0
panel[, lev_C1 := fifelse(n_alerts >= 3, 1.2, 1.0)]

# V_C2 medium: 1.5x if >=3
panel[, lev_C2 := fifelse(n_alerts >= 3, 1.5, 1.0)]

# V_C3 asymmetric: 1.5x if >=3, 1.2x if >=2, else 1.0
panel[, lev_C3 := fcase(n_alerts >= 3, 1.5,
                        n_alerts >= 2, 1.2,
                        default = 1.0)]

# V_C4 monotonic: 1.0 + 0.15 * n_alerts (smooth)
panel[, lev_C4 := 1.0 + 0.15 * n_alerts]  # range [1.0, 1.6]

# Leverage turnover cost (Δlev × 15bps assumed for borrowing slope)
for (v in c("C1", "C2", "C3", "C4")) {
  lcol <- paste0("lev_", v)
  dcol <- paste0("dlev_", v)
  panel[, (dcol) := abs(get(lcol) - shift(get(lcol), 1, fill = 1.0))]
  panel[is.na(get(dcol)), (dcol) := 0]
}

# ── (3) Build leveraged returns ──
# ret_lev = lev_factor × ret_L5_V5 - dlev × 0.0015 (turnover cost)
for (v in c("C1", "C2", "C3", "C4")) {
  lcol <- paste0("lev_", v); dcol <- paste0("dlev_", v)
  rcol <- paste0("ret_", v)
  panel[, (rcol) := get(lcol) * ret_L5_V5 - get(dcol) * 0.0015]
}

# ── (4) Eval: β_FX active subset (110m post-2017-03) ──
pfx <- panel[anchor_date >= as.Date("2017-03-01")]
cat(sprintf("Eval period: %s ~ %s (n=%d months)\n",
            as.character(min(pfx$anchor_date)),
            as.character(max(pfx$anchor_date)), nrow(pfx)))
cat(sprintf("Leverage active months (lev > 1.0):\n"))
for (v in c("C1", "C2", "C3", "C4")) {
  lcol <- paste0("lev_", v)
  cat(sprintf("  V_%s: %d months\n", v, sum(pfx[[lcol]] > 1.0)))
}

# ── (5) Metrics ──
compute_m <- function(ret_vec, dates, label) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 12) return(NULL)
  xret <- xts::xts(r, order.by = d)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mdd <- maxDrawdown(xret)
  list(label = label, n = length(r),
       CAGR = round(as.numeric(ann[1, 1]), 4),
       Sharpe = round(as.numeric(ann[3, 1]), 4),
       MDD = round(-as.numeric(mdd), 4),
       Calmar = round(as.numeric(CalmarRatio(xret)), 4),
       Sortino = round(as.numeric(SortinoRatio(xret, MAR = 0)), 4))
}

nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  S <- sum(resid^2) / n
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  list(t = xbar / sqrt(S / n), mean = xbar)
}

res <- list()
res$L5 <- compute_m(pfx$ret_L5_V5, pfx$anchor_date, "L5 admit baseline")
res$C1 <- compute_m(pfx$ret_C1, pfx$anchor_date, "V_C1 mild (1.2x on ≥3)")
res$C2 <- compute_m(pfx$ret_C2, pfx$anchor_date, "V_C2 medium (1.5x on ≥3)")
res$C3 <- compute_m(pfx$ret_C3, pfx$anchor_date, "V_C3 asym (1.5/1.2)")
res$C4 <- compute_m(pfx$ret_C4, pfx$anchor_date, "V_C4 monotonic (1+0.15*n)")

cat(sprintf("\n━━━ 4-variant Contrarian leverage comparison ━━━\n\n"))
dt_res <- rbindlist(lapply(res, function(x) {
  data.table(variant = x$label, n = x$n, CAGR = x$CAGR, Sharpe = x$Sharpe,
             MDD = x$MDD, Calmar = x$Calmar, Sortino = x$Sortino)
}))
print(dt_res)

# ── (6) Delta + Harvey-t ──
cat(sprintf("\n━━━ Delta (vs L5 admit) ━━━\n\n"))
delta_dt <- data.table(
  variant = c("C1", "C2", "C3", "C4"),
  dSR = c(res$C1$Sharpe, res$C2$Sharpe, res$C3$Sharpe, res$C4$Sharpe) - res$L5$Sharpe,
  dMDD = c(res$C1$MDD, res$C2$MDD, res$C3$MDD, res$C4$MDD) - res$L5$MDD,
  dCAGR = c(res$C1$CAGR, res$C2$CAGR, res$C3$CAGR, res$C4$CAGR) - res$L5$CAGR
)
for (i in seq_len(nrow(delta_dt))) {
  v <- delta_dt$variant[i]
  diff_ret <- pfx[[paste0("ret_", v)]] - pfx$ret_L5_V5
  nw <- nw_t(diff_ret, 4)
  delta_dt[i, harvey_t := round(nw$t, 3)]
}
delta_dt[, admit := fcase(
  dSR >= 0.05 & dMDD <= 0 & abs(harvey_t) > 2.0, "✅ ADMIT_STRICT",
  dSR >= 0.05 & dMDD <= 0, "⚠️ ADMIT_WEAK",
  dSR >= 0 & dMDD <= 0, "△ NEUTRAL",
  default = "❌ REJECT"
)]
print(delta_dt)

# ── (7) Best variant ──
best_idx <- which.max(delta_dt$dSR)
cat(sprintf("\n[BEST] V_%s — ΔSR %+.4f / ΔMDD %+.4f / ΔCAGR %+.2fpp / Harvey-t %+.3f / %s\n",
            delta_dt$variant[best_idx], delta_dt$dSR[best_idx], delta_dt$dMDD[best_idx],
            100 * delta_dt$dCAGR[best_idx], delta_dt$harvey_t[best_idx], delta_dt$admit[best_idx]))

# ── (8) 255m / 267m extension check (since β_FX only post-2018-05) ──
cat(sprintf("\n━━━ Sanity: 255m + 267m extension (pre-β_FX = no leverage) ━━━\n"))
p255 <- panel[realized_ym >= "2005-02" & realized_ym <= "2026-04"]
p267 <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-04"]
for (v in c("C1", "C2", "C3", "C4")) {
  rcol <- paste0("ret_", v)
  m255 <- compute_m(p255[[rcol]], p255$anchor_date, sprintf("255m V_%s", v))
  m267 <- compute_m(p267[[rcol]], p267$anchor_date, sprintf("267m V_%s", v))
  cat(sprintf("  255m V_%s: SR %.3f / MDD %.3f / CAGR %.3f\n",
              v, m255$Sharpe, m255$MDD, m255$CAGR))
  cat(sprintf("  267m V_%s: SR %.3f / MDD %.3f / CAGR %.3f\n",
              v, m267$Sharpe, m267$MDD, m267$CAGR))
}
cat(sprintf("  255m L5 baseline: SR %.3f / MDD %.3f\n",
            compute_m(p255$ret_L5_V5, p255$anchor_date, "L5")$Sharpe,
            compute_m(p255$ret_L5_V5, p255$anchor_date, "L5")$MDD))

# ── (9) Save ──
out <- list(
  metrics_110m = res,
  delta_table = delta_dt,
  best_variant = delta_dt$variant[best_idx],
  best_dSR = delta_dt$dSR[best_idx],
  best_admit = delta_dt$admit[best_idx],
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "contrarian_leverage_backtest.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/contrarian_leverage_backtest.json\n", EVAL_DIR))

# ── (10) Chart ──
nav_dt <- pfx[, .(anchor_date,
                  L5 = cumprod(1 + ret_L5_V5),
                  C1 = cumprod(1 + ret_C1),
                  C2 = cumprod(1 + ret_C2),
                  C3 = cumprod(1 + ret_C3),
                  C4 = cumprod(1 + ret_C4))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  scale_color_manual(values = c("L5" = "#073B4C", "C1" = "#06D6A0", "C2" = "#FFD166",
                                 "C3" = "#EF476F", "C4" = "#8338EC")) +
  labs(title = "Contrarian leverage on ≥3 overlay alert — NAV (110m, log)",
       subtitle = sprintf("Best: V_%s (ΔSR %+.3f / %s)",
                          delta_dt$variant[best_idx], delta_dt$dSR[best_idx],
                          delta_dt$admit[best_idx]),
       x = NULL, y = "NAV (log)") + theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "14_contrarian_leverage.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 14] %s/14_contrarian_leverage.png\n", CHART_DIR))

cat("\n[DONE]\n")
