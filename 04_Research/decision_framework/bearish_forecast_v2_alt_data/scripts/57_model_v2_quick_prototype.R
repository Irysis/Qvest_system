#==============================================================================
# 57_model_v2_quick_prototype.R — Cycle 32 v1.3 Limitation Diagnosis +
# v2.0 Quick Prototype (no retrain required)
#
# Hypothesis: Monthly application 실패는 single-day snapshot의 noise.
# Quick fix: smoothed / aggregated p_bear → less noisy monthly signal.
#
# Variants tested (without retrain):
#   V0: Single-day p_eom (current — fail in cycles 30-31)
#   V1: 5-day average p_bear at month-end
#   V2: 10-day max p_bear at month-end (sustained signal)
#   V3: 5-day trend (rising 만 trigger)
#   V4: Multi-threshold confirmation (3-of-5 days above q90)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load data ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]
setorder(preds, Date)
preds[, ym := format(Date, "%Y-%m")]

# ── (2) Build 5 variant signals per month ──
preds_me <- preds[, .(
  V0_p_eom = p[which.max(Date)],
  V1_5d_avg = mean(tail(p, 5)),
  V2_10d_max = max(tail(p, 10)),
  V3_5d_trend = tail(p, 1) - p[max(1, length(p) - 5)],
  V4_count_q70_5d = sum(tail(p, 5) >= quantile(p[Date < Date[which.max(Date)]], 0.70, na.rm = TRUE))
), by = ym]
setorder(preds_me, ym)

# PIT q70/q90/q95 per month
preds_me[, q70 := NA_real_]; preds_me[, q90 := NA_real_]; preds_me[, q95 := NA_real_]
for (i in seq_len(nrow(preds_me))) {
  past_p <- preds$p[preds$ym < preds_me$ym[i]]
  past_p <- past_p[!is.na(past_p)]
  if (length(past_p) >= 30) {
    preds_me[i, q70 := quantile(past_p, 0.70)]
    preds_me[i, q90 := quantile(past_p, 0.90)]
    preds_me[i, q95 := quantile(past_p, 0.95)]
  }
}

preds_me[, realized_ym := shift(ym, -1, type = "lead")]
panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym,
                             V0_eom = V0_p_eom,
                             V1_5d_avg, V2_10d_max,
                             V3_trend = V3_5d_trend,
                             V4_count_q70 = V4_count_q70_5d,
                             q70, q90, q95)],
               by = "realized_ym")
panel <- panel[!is.na(V0_eom) & !is.na(q95) & !is.na(ret_kospi)]
cat(sprintf("[Panel] %d months\n", nrow(panel)))

# ── (3) Define trigger per variant ──
# V0: single-day p > q95 (current monthly fail)
panel[, trig_V0 := V0_eom > q95]
# V1: 5d avg > q90 (smoother, sustained)
panel[, trig_V1 := V1_5d_avg > q90]
# V2: 10d max > q95 (any recent spike)
panel[, trig_V2 := V2_10d_max > q95]
# V3: rising trend + p > q70 (momentum-confirmed)
panel[, trig_V3 := V3_trend > 0.05 & V0_eom > q70]
# V4: 3-of-5 days above q70 (sustained warning)
panel[, trig_V4 := V4_count_q70 >= 3]

# ── (4) Backtest: kill switch on each trigger ──
cost <- 0.003

m_base <- {
  xret <- xts::xts(panel$ret_kospi, order.by = as.Date(paste0(panel$realized_ym, "-01")))
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  c(SR = as.numeric(ann[3, 1]),
    MDD = -as.numeric(maxDrawdown(xret)),
    CAGR = as.numeric(ann[1, 1]))
}
cat(sprintf("\n━━━ BH KOSPI baseline ━━━\n"))
cat(sprintf("  SR %.4f / MDD %+.4f / CAGR %.4f\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

compute_m <- function(ret_vec, dates) {
  xret <- xts::xts(ret_vec, order.by = dates)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  c(SR = as.numeric(ann[3, 1]),
    MDD = -as.numeric(maxDrawdown(xret)),
    CAGR = as.numeric(ann[1, 1]))
}
nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  S <- sum(resid^2) / n
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  xbar / sqrt(S / n)
}

cat(sprintf("\n━━━ 5 trigger variants comparison ━━━\n"))
dates <- as.Date(paste0(panel$realized_ym, "-01"))
results <- data.table()
for (v in 0:4) {
  tcol <- paste0("trig_V", v)
  trigs <- panel[[tcol]]
  trigs_prev <- shift(trigs, 1, fill = FALSE)
  change <- trigs != trigs_prev

  ret <- ifelse(trigs, 0, panel$ret_kospi)
  ret[change] <- ret[change] - cost

  mm <- compute_m(ret, dates)
  ht <- nw_t(ret - panel$ret_kospi, 4)

  # Episodes accuracy
  ep_active <- sum(trigs)
  ep_tp <- sum(trigs & panel$ret_kospi < 0)
  ep_prec <- if (ep_active > 0) ep_tp / ep_active else NA

  results <- rbind(results, data.table(
    variant = paste0("V", v),
    description = c("V0 single-day p_eom > q95",
                     "V1 5d_avg > q90 (smoothed)",
                     "V2 10d_max > q95 (spike)",
                     "V3 trend+q70 (rising)",
                     "V4 3-of-5 above q70 (sustained)")[v + 1],
    n_trigger = ep_active,
    precision = round(ep_prec, 3),
    SR = round(mm["SR"], 4),
    MDD = round(mm["MDD"], 4),
    CAGR = round(mm["CAGR"], 4),
    dSR = round(mm["SR"] - m_base["SR"], 4),
    harvey_t = round(ht, 3)
  ))
}
print(results)

best <- results[which.max(dSR)]
cat(sprintf("\n[Best] %s — dSR %+.4f (vs BH SR %.4f) / Precision %.3f / Harvey-t %+.3f\n",
            best$variant, best$dSR, m_base["SR"],
            best$precision, best$harvey_t))

# ── (5) Save + Document ──
out <- list(
  baseline_BH = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                      CAGR = unname(m_base["CAGR"])),
  variants = results,
  best = list(variant = best$variant, dSR = best$dSR,
               precision = best$precision, harvey_t = best$harvey_t),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "model_v2_quick_prototype.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/model_v2_quick_prototype.json\n", EVAL_DIR))

cat("\n[DONE]\n")
