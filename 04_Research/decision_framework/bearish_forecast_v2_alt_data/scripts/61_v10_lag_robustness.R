#==============================================================================
# 61_v10_lag_robustness.R — Cycle 37 T+N day lag impact (실 운영 시차)
#
# 도훈 우려 (2026-05-20):
#   "KRX 데이터 API 업데이트 시차 → 실 운용 시 1-5 trading day lag 가능"
#
# Test scenarios:
#   Lag 0 (current backtest): t-1 EOM 5 days 사용 → t 시점 결정
#   Lag 1: t-1 EOM -1 day (1 trading day skip)
#   Lag 2: t-1 EOM -2 day (외국인 확정치 + verify time)
#   Lag 3: t-1 EOM -3 day (보수적 operational margin)
#   Lag 5: t-1 EOM -5 day (1주일 lag, extreme conservative)
#
# Each scenario: V10 (3-cond AND) → backtest → SR/MDD/dSR
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load ──
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

# ── (2) Build V10 panel for each lag scenario ──
build_v10_with_lag <- function(lag_days, preds, eom, cost = 0.003) {
  # For each month, find EOM date, shift back by lag_days trading days
  # Then compute 5-day window ending at that shifted date
  preds_me <- preds[, .(eom_date = max(Date),
                          p_eom = p[which.max(Date)],
                          n_days_in_month = .N),
                     by = ym]
  setorder(preds_me, eom_date)

  # For lag scenarios, shift eom_date back by lag_days TRADING days
  # Use preds Date as trading day index
  trading_dates <- sort(unique(preds$Date))
  for (i in seq_len(nrow(preds_me))) {
    eom_idx <- which(trading_dates == preds_me$eom_date[i])
    if (length(eom_idx) == 0) {
      preds_me[i, effective_date := preds_me$eom_date[i]]
      next
    }
    new_idx <- max(1, eom_idx - lag_days)
    preds_me[i, effective_date := trading_dates[new_idx]]
  }

  # Recompute p_eom, count_5_q70, trend_5d AT effective_date
  preds_me[, p_eom_lag := NA_real_]
  preds_me[, count_5_q70_lag := NA_integer_]
  preds_me[, trend_5d_lag := NA_real_]
  preds_me[, q70_lag := NA_real_]

  for (i in seq_len(nrow(preds_me))) {
    eff_date <- preds_me$effective_date[i]
    # Past p values BEFORE eff_date (strictly past for q70 PIT)
    past_p <- preds$p[preds$Date < eff_date]
    if (length(past_p) < 30) next
    q70 <- quantile(past_p, 0.70, na.rm = TRUE)
    preds_me[i, q70_lag := q70]

    # 5-day window ending at eff_date (inclusive)
    window_5 <- preds$p[preds$Date <= eff_date]
    window_5 <- tail(window_5, 5)
    if (length(window_5) < 5) next
    preds_me[i, p_eom_lag := window_5[5]]
    preds_me[i, count_5_q70_lag := sum(window_5 >= q70, na.rm = TRUE)]
    preds_me[i, trend_5d_lag := window_5[5] - window_5[1]]
  }

  preds_me[, realized_ym := shift(ym, -1, type = "lead")]
  panel <- merge(eom[, .(realized_ym, ret_kospi)],
                 preds_me[, .(realized_ym, p_eom = p_eom_lag,
                               trend_5d = trend_5d_lag,
                               count_5_q70 = count_5_q70_lag,
                               q70 = q70_lag)],
                 by = "realized_ym")
  panel <- panel[!is.na(p_eom) & !is.na(q70) & !is.na(ret_kospi)]

  # V10 trigger
  trig <- panel$count_5_q70 >= 4 &
            panel$trend_5d > 0 &
            panel$p_eom > panel$q70
  trig_prev <- shift(trig, 1, fill = FALSE)
  change <- trig != trig_prev
  ret <- ifelse(trig, 0, panel$ret_kospi)
  ret[change] <- ret[change] - cost

  list(panel = panel, ret = ret, n_trigger = sum(trig),
       precision = if (sum(trig) > 0)
         sum(trig & panel$ret_kospi < 0) / sum(trig) else NA)
}

# ── (3) Run for each lag ──
cat(sprintf("━━━ T+N day lag impact (V10) ━━━\n\n"))

compute_m <- function(ret_vec, dates) {
  xret <- xts::xts(ret_vec, order.by = dates)
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

results <- data.table()
for (lag_d in c(0, 1, 2, 3, 5, 10)) {
  res <- build_v10_with_lag(lag_d, preds, eom)
  if (nrow(res$panel) < 12) next
  dates <- as.Date(paste0(res$panel$realized_ym, "-01"))
  mm <- compute_m(res$ret, dates)
  m_base <- compute_m(res$panel$ret_kospi, dates)
  ht <- nw_t(res$ret - res$panel$ret_kospi, 4)

  results <- rbind(results, data.table(
    lag_days = lag_d,
    description = sprintf("T+%d trading day lag", lag_d),
    n_months = nrow(res$panel),
    n_trigger = res$n_trigger,
    precision = if (is.na(res$precision)) NA_real_ else round(res$precision, 3),
    SR_BH = round(m_base["SR"], 4),
    SR_V10 = round(mm["SR"], 4),
    dSR = round(mm["SR"] - m_base["SR"], 4),
    MDD_V10 = round(mm["MDD"], 4),
    CAGR_V10 = round(mm["CAGR"], 4),
    harvey_t = round(ht, 3)
  ))
}
print(results)

# ── (4) Analysis ──
cat(sprintf("\n━━━ Analysis ━━━\n"))
baseline_dSR <- results[lag_days == 0, dSR]
cat(sprintf("Baseline (T+0, current backtest): dSR %+.4f\n", baseline_dSR))
for (lag_d in c(1, 2, 3, 5, 10)) {
  current_dSR <- results[lag_days == lag_d, dSR]
  drop_pct <- (current_dSR - baseline_dSR) / abs(baseline_dSR) * 100
  cat(sprintf("  T+%d lag: dSR %+.4f (drop %+.1f%%%% from baseline)\n",
              lag_d, current_dSR, drop_pct))
}

# Verdict
realistic_lag_dSR <- results[lag_days == 2, dSR]  # T+2 = realistic operational
cat(sprintf("\n[Realistic operational T+2 lag]: dSR %+.4f\n", realistic_lag_dSR))
if (realistic_lag_dSR > 0.2) {
  cat(sprintf("  ✅ STRONG — 실 운영 시차 흡수 가능\n"))
  verdict <- "STRONG"
} else if (realistic_lag_dSR > 0.1) {
  cat(sprintf("  △ MODERATE — alpha 일부 손실, but 사용 가능\n"))
  verdict <- "MODERATE"
} else if (realistic_lag_dSR > 0) {
  cat(sprintf("  ⚠️ WEAK — alpha 큰 폭 손실\n"))
  verdict <- "WEAK"
} else {
  cat(sprintf("  ❌ FAIL — 시차로 alpha 소멸\n"))
  verdict <- "FAIL"
}

# ── (5) Save + chart ──
out <- list(
  results = results,
  baseline_T0_dSR = baseline_dSR,
  realistic_T2_dSR = realistic_lag_dSR,
  verdict = verdict,
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v10_lag_robustness.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v10_lag_robustness.json\n", EVAL_DIR))

# Chart
g <- ggplot(results, aes(x = lag_days, y = dSR)) +
  geom_line(color = "#073B4C", linewidth = 1) +
  geom_point(aes(color = dSR > 0.1), size = 4) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed") +
  geom_hline(yintercept = 0.1, color = "orange", linetype = "dotted") +
  geom_hline(yintercept = 0.2, color = "green", linetype = "dotted") +
  scale_color_manual(values = c("TRUE" = "#06D6A0", "FALSE" = "#EF476F"), name = NULL) +
  scale_x_continuous(breaks = c(0, 1, 2, 3, 5, 10)) +
  annotate("text", x = 9, y = 0.105, label = "MODERATE threshold +0.1",
           color = "orange", size = 3) +
  annotate("text", x = 9, y = 0.205, label = "STRONG threshold +0.2",
           color = "green", size = 3) +
  labs(title = "V10 dSR vs operational lag (T+N trading days)",
       subtitle = sprintf("Baseline T+0: %+.3f / Realistic T+2: %+.3f (%s)",
                          baseline_dSR, realistic_lag_dSR, verdict),
       x = "Lag (trading days)", y = "ΔSR vs BH KOSPI") +
  theme_minimal(base_size = 12)
ggsave(file.path(CHART_DIR, "38_v10_lag_robustness.png"),
       plot = g, width = 11, height = 6, dpi = 120)
cat(sprintf("[Chart 38] %s/38_v10_lag_robustness.png\n", CHART_DIR))

cat(sprintf("\n[DONE]\n"))
