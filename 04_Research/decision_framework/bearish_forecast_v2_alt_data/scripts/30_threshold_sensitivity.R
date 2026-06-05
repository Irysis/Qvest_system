#==============================================================================
# 30_threshold_sensitivity.R — β_FX threshold sensitivity (검증 3b)
#
# 4 variants:
#   V_T05: Top 5%% (alert: p > q95_past, scalar = 0.5)
#   V_T10: Top 10%% (alert: p > q90_past, scalar = 0.5)
#   V_T20: Top 20%% (alert: p > q80_past, scalar = 0.5)
#   V_T30: Top 30%% (alert + caution: p > q70_past → 0.7, > q90 → 0.5)
#
# Decision rule per variant:
#   ΔSR ≥ +0.05 AND ΔMDD ≤ 0pp AND Harvey-t > 2.0 → ADMIT
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

# ── (1) Load baseline + p_bear ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]; preds[, ym := format(Date, "%Y-%m")]
me <- preds[, .SD[which.max(Date)], by = ym]
setorder(me, Date)

# ── (2) Build β_FX for 4 variants (PIT expanding quantile) ──
expanding_q <- function(x, dates, q = 0.5) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}
me[, q95_past := expanding_q(p, Date, 0.95)]
me[, q90_past := expanding_q(p, Date, 0.90)]
me[, q80_past := expanding_q(p, Date, 0.80)]
me[, q70_past := expanding_q(p, Date, 0.70)]

# V_T05: Top 5% only
me[, beta_FX_T05 := fcase(is.na(q95_past), 1.0,
                          p > q95_past, 0.5,
                          default = 1.0)]
# V_T10: Top 10% only
me[, beta_FX_T10 := fcase(is.na(q90_past), 1.0,
                          p > q90_past, 0.5,
                          default = 1.0)]
# V_T20: Top 20% only
me[, beta_FX_T20 := fcase(is.na(q80_past), 1.0,
                          p > q80_past, 0.5,
                          default = 1.0)]
# V_T30: Top 30% two-tier (admit baseline from validation 1)
me[, beta_FX_T30 := fcase(is.na(q70_past) | is.na(q90_past), 1.0,
                          p > q90_past, 0.5,
                          p > q70_past, 0.7,
                          default = 1.0)]

# ── (3) Merge to baseline panel ──
me[, yr := as.integer(substr(ym, 1, 4))]
me[, mn := as.integer(substr(ym, 6, 7))]
me[, next_yr := ifelse(mn == 12, yr + 1, yr)]
me[, next_mn := ifelse(mn == 12, 1, mn + 1)]
me[, realized_ym := sprintf("%04d-%02d", next_yr, next_mn)]

merge_cols <- c("realized_ym", "beta_FX_T05", "beta_FX_T10", "beta_FX_T20", "beta_FX_T30")
panel <- merge(baseline, me[, ..merge_cols], by = "realized_ym", all.x = TRUE)
for (v in c("T05", "T10", "T20", "T30")) {
  bcol <- paste0("beta_FX_", v)
  panel[is.na(get(bcol)), (bcol) := 1.0]
}
setorder(panel, anchor_date)

# Δβ_FX turnover cost
for (v in c("T05", "T10", "T20", "T30")) {
  bcol <- paste0("beta_FX_", v)
  dcol <- paste0("db_FX_", v)
  panel[, (dcol) := abs(get(bcol) - shift(get(bcol), 1, fill = 1.0))]
  panel[is.na(get(dcol)), (dcol) := 0]
}

# ── (4) Build Layer 6 returns per variant ──
for (v in c("T05", "T10", "T20", "T30")) {
  bcol <- paste0("beta_FX_", v)
  dcol <- paste0("db_FX_", v)
  rcol <- paste0("ret_L6_", v)
  panel[, (rcol) := get(bcol) * ret_L5_V5 - get(dcol) * 0.0015]
}

# ── (5) Eval window: β_FX active subset (post-2018-05) ──
pfx <- panel[anchor_date >= as.Date("2017-03-01")]

# ── (6) Metrics function ──
compute_metrics <- function(ret_vec, dates, label) {
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

# Newey-West t-stat
nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  gamma0 <- sum(resid^2) / n; S <- gamma0
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  list(t = xbar / sqrt(S / n), mean = xbar)
}

# ── (7) Per variant evaluation ──
cat("━━━ Threshold sensitivity (110m β_FX active subset) ━━━\n\n")
res <- list()
res$L5 <- compute_metrics(pfx$ret_L5_V5, pfx$anchor_date, "L5 admit baseline")
res$T05 <- compute_metrics(pfx$ret_L6_T05, pfx$anchor_date, "L6 V_T05 (Top 5%%)")
res$T10 <- compute_metrics(pfx$ret_L6_T10, pfx$anchor_date, "L6 V_T10 (Top 10%%)")
res$T20 <- compute_metrics(pfx$ret_L6_T20, pfx$anchor_date, "L6 V_T20 (Top 20%%)")
res$T30 <- compute_metrics(pfx$ret_L6_T30, pfx$anchor_date, "L6 V_T30 (Top 30%% 2-tier)")

# β_FX active count + alert ratio
alert_count <- sapply(c("T05", "T10", "T20", "T30"), function(v) {
  bcol <- paste0("beta_FX_", v)
  sum(pfx[[bcol]] != 1.0)
})
cat("Alert counts per variant (out of 110m):\n")
print(alert_count)
cat(sprintf("Alert ratios: %s\n\n",
            paste(sprintf("%s=%.1f%%", names(alert_count),
                          100 * alert_count / nrow(pfx)), collapse = " / ")))

dt_res <- rbindlist(lapply(res, function(x) {
  data.table(variant = x$label, n = x$n, CAGR = x$CAGR, Sharpe = x$Sharpe,
             MDD = x$MDD, Calmar = x$Calmar)
}))
print(dt_res)

# ── (8) Delta + Harvey-t per variant ──
cat("\n━━━ Delta + Harvey-t (vs L5 admit) ━━━\n\n")
delta_dt <- data.table(
  variant = c("T05", "T10", "T20", "T30"),
  dSR = c(res$T05$Sharpe, res$T10$Sharpe, res$T20$Sharpe, res$T30$Sharpe) - res$L5$Sharpe,
  dMDD = c(res$T05$MDD, res$T10$MDD, res$T20$MDD, res$T30$MDD) - res$L5$MDD,
  dCAGR = c(res$T05$CAGR, res$T10$CAGR, res$T20$CAGR, res$T30$CAGR) - res$L5$CAGR,
  alert_ratio = round(100 * alert_count / nrow(pfx), 1)
)
for (i in seq_len(nrow(delta_dt))) {
  v <- delta_dt$variant[i]
  rcol <- paste0("ret_L6_", v)
  diff_ret <- pfx[[rcol]] - pfx$ret_L5_V5
  nw <- nw_t(diff_ret, 4)
  delta_dt[i, harvey_t := round(nw$t, 3)]
}
delta_dt[, admit := fcase(
  dSR >= 0.05 & dMDD <= 0 & abs(harvey_t) > 2.0, "✅ ADMIT",
  dSR >= 0 & dMDD <= 0, "⚠️ WEAK_NEUTRAL",
  default = "❌ REJECT"
)]
print(delta_dt)

# ── (9) Verdict ──
admit_variants <- delta_dt[admit == "✅ ADMIT", variant]
cat(sprintf("\n[VERDICT] Admit variants: %s\n",
            ifelse(length(admit_variants) == 0, "NONE",
                   paste(admit_variants, collapse = ", "))))

if (length(admit_variants) > 0) {
  best_v <- delta_dt[admit == "✅ ADMIT"][which.max(dSR)]
  cat(sprintf("[BEST] V_%s — ΔSR %+.4f / ΔMDD %+.4f / Harvey-t %+.3f / Alert %.1f%%\n",
              best_v$variant, best_v$dSR, best_v$dMDD,
              best_v$harvey_t, best_v$alert_ratio))
} else {
  cat("\n[FALLBACK] 모든 variant REJECT. β_FX는 Layer 6 추가 불가.\n")
  cat("후속 path: (A) Multi-overlay AND gate (β_FX + m4 + AR 동시 alert만 발동)\n")
  cat("           (B) Daily monitoring tool로만 활용 (overlay 추가 X)\n")
  cat("           (C) Target 재정의 + 재학습 (calendar-month Q15)\n")
}

# ── (10) Save ──
out <- list(
  alert_count = as.list(alert_count),
  metrics_per_variant = res,
  delta_table = delta_dt,
  admit_variants = admit_variants,
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "threshold_sensitivity.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/threshold_sensitivity.json\n", EVAL_DIR))

# ── (11) Chart ──
nav_dt <- panel[anchor_date >= as.Date("2017-03-01"),
                .(anchor_date,
                  L5 = cumprod(1 + ret_L5_V5),
                  T05 = cumprod(1 + ret_L6_T05),
                  T10 = cumprod(1 + ret_L6_T10),
                  T20 = cumprod(1 + ret_L6_T20),
                  T30 = cumprod(1 + ret_L6_T30))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) +
  scale_y_log10() +
  scale_color_manual(values = c("L5" = "#073B4C", "T05" = "#06D6A0", "T10" = "#FFD166",
                                 "T20" = "#EF476F", "T30" = "#8338EC")) +
  labs(title = "β_FX threshold sensitivity — NAV (110m, log scale)",
       subtitle = sprintf("Best variant: %s",
                          ifelse(length(admit_variants) > 0,
                                 paste(admit_variants, collapse = ", "),
                                 "NONE (all REJECT)")),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "13_threshold_sensitivity.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 13] %s/13_threshold_sensitivity.png\n", CHART_DIR))

cat("\n[DONE]\n")
