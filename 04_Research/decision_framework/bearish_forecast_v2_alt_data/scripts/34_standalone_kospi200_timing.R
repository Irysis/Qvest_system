#==============================================================================
# 34_standalone_kospi200_timing.R — Cycle 4.1 Standalone KOSPI200 timing
#
# Hypothesis: STR_1715 base에 흡수 안 되니 모델을 standalone KOSPI200 timing
# strategy로 valuation. 모델의 진짜 (가능한) 알파 path.
#
# 5 variants on monthly KOSPI200 ret (close-to-close):
#   V_S1 (long-only): p < q50_past → long, else cash
#   V_S2 (long-cash-inverse 3-state): p < q33 → long, q33-q67 → cash, p > q67 → inverse 1x
#   V_S3 (long-cash-inverse asymmetric): p < q70 → long, p > q90 → inverse 1x, mid → cash
#   V_S4 (continuous): position = clip(-1, 1, 2*(0.5 - normalized_p))
#   V_S5 (regime conditional): use M2 regime from preds
#
# Baseline: Buy-and-hold KOSPI200 (long always)
#
# Cost: 30bps round trip (switching 시)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load monthly KOSPI200 ret + p_bear ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(Date_eom = max(Date),
              close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, ym_target := shift(ym, n = 1L, type = "lead")]

preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]; preds[, ym := format(Date, "%Y-%m")]
me <- preds[, .SD[which.max(Date)], by = ym]
setorder(me, Date)

panel <- merge(eom, me[, .(ym, p, regime)], by = "ym", all.x = TRUE)
setorder(panel, ym)

# ── (2) PIT expanding quantiles ──
expanding_q <- function(x, dates, q = 0.5) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}
pan_p <- panel[!is.na(p)]
pan_p[, q33 := expanding_q(p, Date_eom, 0.33)]
pan_p[, q50 := expanding_q(p, Date_eom, 0.50)]
pan_p[, q67 := expanding_q(p, Date_eom, 0.67)]
pan_p[, q70 := expanding_q(p, Date_eom, 0.70)]
pan_p[, q90 := expanding_q(p, Date_eom, 0.90)]
pan_p[, p_z := (p - q50) / pmax((q90 - q50), 0.01)]  # normalized [-1, 1]-ish

# ── (3) Define variants (position ∈ [-1, 0, 1] or continuous) ──
# V_S1: long-only switching
pan_p[, pos_S1 := fifelse(!is.na(q50) & p < q50, 1.0, 0.0)]

# V_S2: long-cash-inverse 3-state
pan_p[, pos_S2 := fcase(is.na(q33) | is.na(q67), 0.0,
                         p < q33, 1.0,
                         p > q67, -1.0,
                         default = 0.0)]

# V_S3: long-cash-inverse asymmetric (more long, less inverse)
pan_p[, pos_S3 := fcase(is.na(q70) | is.na(q90), 0.0,
                         p < q70, 1.0,
                         p > q90, -1.0,
                         default = 0.0)]

# V_S4: continuous (clipped tanh-style)
pan_p[, pos_S4 := pmax(-1.0, pmin(1.0, -2.0 * p_z))]
pan_p[is.na(pos_S4), pos_S4 := 0]

# V_S5: regime conditional (bear regime → cash, bull → long)
pan_p[, pos_S5 := fcase(regime == "bull", 1.0,
                         regime == "bear", 0.0,
                         default = 0.5)]

# ── (4) Lag positions by 1 (decision at t-1 EOM applied to t) ──
# (already done: pos at month t determined at end of month t, applied to ret_kospi[t]
#  which is close[t+1] - close[t]. So pos at row t → return at row t.)
# Position turnover for cost
for (v in c("S1", "S2", "S3", "S4", "S5")) {
  pcol <- paste0("pos_", v)
  tcol <- paste0("turn_", v)
  pan_p[, (tcol) := abs(get(pcol) - shift(get(pcol), 1, fill = 0))]
}

# ── (5) Build returns (30bps round trip cost) ──
for (v in c("S1", "S2", "S3", "S4", "S5")) {
  pcol <- paste0("pos_", v)
  tcol <- paste0("turn_", v)
  rcol <- paste0("ret_", v)
  pan_p[, (rcol) := get(pcol) * ret_kospi - get(tcol) * 0.003]  # 30bps
}

# Buy-and-hold baseline
pan_p[, ret_BH := ret_kospi]

# ── (6) Eval ──
pfx <- pan_p[!is.na(ret_kospi)]
cat(sprintf("Eval period: %s ~ %s (n=%d months)\n",
            as.character(min(pfx$Date_eom)),
            as.character(max(pfx$Date_eom)), nrow(pfx)))

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
       Calmar = round(as.numeric(CalmarRatio(xret)), 4))
}

res <- list()
res$BH <- compute_m(pfx$ret_BH, pfx$Date_eom, "Buy-and-hold KOSPI200")
res$S1 <- compute_m(pfx$ret_S1, pfx$Date_eom, "V_S1 long-only switch (p<q50)")
res$S2 <- compute_m(pfx$ret_S2, pfx$Date_eom, "V_S2 LCI 3-state (q33/q67)")
res$S3 <- compute_m(pfx$ret_S3, pfx$Date_eom, "V_S3 LCI asym (q70/q90)")
res$S4 <- compute_m(pfx$ret_S4, pfx$Date_eom, "V_S4 continuous tanh")
res$S5 <- compute_m(pfx$ret_S5, pfx$Date_eom, "V_S5 regime conditional")

cat(sprintf("\n━━━ Standalone strategy comparison ━━━\n\n"))
dt_res <- rbindlist(lapply(res, function(x) {
  data.table(variant = x$label, n = x$n, CAGR = x$CAGR, Sharpe = x$Sharpe,
             MDD = x$MDD, Calmar = x$Calmar)
}))
print(dt_res)

# ── (7) Delta vs BH ──
cat(sprintf("\n━━━ Delta vs Buy-and-hold ━━━\n\n"))
delta_dt <- data.table(
  variant = c("S1", "S2", "S3", "S4", "S5"),
  dSR = sapply(c("S1", "S2", "S3", "S4", "S5"), function(v) res[[v]]$Sharpe) - res$BH$Sharpe,
  dMDD = sapply(c("S1", "S2", "S3", "S4", "S5"), function(v) res[[v]]$MDD) - res$BH$MDD,
  dCAGR = sapply(c("S1", "S2", "S3", "S4", "S5"), function(v) res[[v]]$CAGR) - res$BH$CAGR
)
delta_dt[, verdict := fcase(
  dSR >= 0.2 & dMDD <= 0, "✅ STRONG WIN",
  dSR >= 0.1 & dMDD <= 0, "⚠️ MILD WIN",
  dSR > 0, "△ NEUTRAL (SR↑ but trade-off)",
  default = "❌ LOSE")]
print(delta_dt)

# ── (8) Turnover summary ──
cat(sprintf("\n━━━ Turnover (annual round-trips) ━━━\n"))
for (v in c("S1", "S2", "S3", "S4", "S5")) {
  tot_turn <- sum(pfx[[paste0("turn_", v)]], na.rm = TRUE)
  ann_turn <- tot_turn / (nrow(pfx) / 12)
  cat(sprintf("  V_%s: total turn=%.1f / annual round-trips=%.2f\n",
              v, tot_turn, ann_turn))
}

# ── (9) Best variant ──
best_idx <- which.max(delta_dt$dSR)
cat(sprintf("\n[BEST] V_%s — SR %.3f / MDD %.3f / CAGR %.3f / vs BH ΔSR %+.3f / %s\n",
            delta_dt$variant[best_idx],
            res[[delta_dt$variant[best_idx]]]$Sharpe,
            res[[delta_dt$variant[best_idx]]]$MDD,
            res[[delta_dt$variant[best_idx]]]$CAGR,
            delta_dt$dSR[best_idx], delta_dt$verdict[best_idx]))

# ── (10) Save + chart ──
out <- list(metrics = res, delta = delta_dt,
            best_variant = delta_dt$variant[best_idx],
            timestamp = as.character(Sys.time()))
write_json(out, file.path(EVAL_DIR, "standalone_kospi200_timing.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/standalone_kospi200_timing.json\n", EVAL_DIR))

nav_dt <- pfx[, .(Date_eom,
                  BH = cumprod(1 + ret_BH),
                  S1 = cumprod(1 + ret_S1),
                  S2 = cumprod(1 + ret_S2),
                  S3 = cumprod(1 + ret_S3),
                  S4 = cumprod(1 + ret_S4),
                  S5 = cumprod(1 + ret_S5))]
nav_long <- melt(nav_dt, id.vars = "Date_eom", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = Date_eom, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = "Standalone KOSPI200 timing vs Buy-and-hold (110m, log NAV)",
       subtitle = sprintf("Best: V_%s ΔSR %+.3f / %s",
                          delta_dt$variant[best_idx], delta_dt$dSR[best_idx],
                          delta_dt$verdict[best_idx]),
       x = NULL, y = "NAV (log)") + theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "15_standalone_timing.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 15] %s/15_standalone_timing.png\n", CHART_DIR))

cat("\n[DONE]\n")
