#==============================================================================
# 31_top5_alert_month_audit.R — Top 5%% alert month KOSPI200 monthly close audit
#
# Cycle 1.1: 검증 1에서 발견한 Top 5%% precision 1.0 (6/6 hit) 의
# actual KOSPI200 monthly close-to-close ret 확인.
#
# 핵심 질문: tail event label (y_tail_q15=1) ≠ negative monthly close ret 가능
# 만약 6번 적중 중 monthly close ret이 양수인 month 있으면 inverse 베팅 부적합
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")

# ── (1) Load predictions + targets ──
preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p) & !is.na(y)]; preds[, ym := format(Date, "%Y-%m")]

# Month-end snapshot
me <- preds[, .SD[which.max(Date)], by = ym]
setorder(me, Date)

# ── (2) PIT expanding quantile (re-derive Top 5%%, 10%%, 20%%, 30%%) ──
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
me[, alert_T05 := !is.na(q95_past) & p > q95_past]
me[, alert_T10 := !is.na(q90_past) & p > q90_past]
me[, alert_T20 := !is.na(q80_past) & p > q80_past]
me[, alert_T30 := !is.na(q70_past) & p > q70_past]

# ── (3) Load actual KOSPI200 (BM_Close from targets_full) ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]
bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)

# Month-end close + next month close
eom <- bm[, .(Date_eom = max(Date),
              close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, close_eom_next := shift(close_eom, n = 1L, type = "lead")]
eom[, ym_next := shift(ym, n = 1L, type = "lead")]
eom[, ret_next_month := close_eom_next / close_eom - 1]

# ── (4) Merge alerts + actuals ──
audit <- merge(me[, .(ym, Date_eom = Date, p, q95_past, q90_past, q80_past, q70_past,
                       alert_T05, alert_T10, alert_T20, alert_T30, y_tail_q15 = y)],
               eom[, .(ym, ym_next, close_eom, close_eom_next, ret_next_month)],
               by = "ym", all.x = TRUE)
setorder(audit, ym)

# ── (5) Top 5%% audit ──
top5 <- audit[alert_T05 == TRUE]
cat(sprintf("━━━ Top 5%% alert audit ━━━\n"))
cat(sprintf("Total Top 5%% alerts: %d\n", nrow(top5)))
cat(sprintf("y_tail_q15 hits (daily tail label): %d (%.0f%%)\n",
            sum(top5$y_tail_q15), 100 * mean(top5$y_tail_q15)))
cat(sprintf("\nDetail:\n"))
print(top5[, .(snap = Date_eom, target = ym_next,
               p = round(p, 4),
               q95_past = round(q95_past, 4),
               y_daily = y_tail_q15,
               ret_pct = sprintf("%+.2f%%", 100 * ret_next_month),
               monthly_neg = ret_next_month < 0,
               monthly_lt_neg3 = ret_next_month < -0.03,
               monthly_lt_neg5 = ret_next_month < -0.05)])

monthly_neg_T05 <- sum(top5$ret_next_month < 0, na.rm = TRUE)
monthly_lt3_T05 <- sum(top5$ret_next_month < -0.03, na.rm = TRUE)
monthly_lt5_T05 <- sum(top5$ret_next_month < -0.05, na.rm = TRUE)
mean_ret_T05 <- mean(top5$ret_next_month, na.rm = TRUE)
cat(sprintf("\nMonthly close-to-close summary:\n"))
cat(sprintf("  Mean ret: %+.2f%%\n", 100 * mean_ret_T05))
cat(sprintf("  Negative monthly ret: %d / %d (%.0f%%)\n",
            monthly_neg_T05, nrow(top5), 100 * monthly_neg_T05 / nrow(top5)))
cat(sprintf("  Ret < -3%%: %d / %d (%.0f%%)\n",
            monthly_lt3_T05, nrow(top5), 100 * monthly_lt3_T05 / nrow(top5)))
cat(sprintf("  Ret < -5%%: %d / %d (%.0f%%)\n",
            monthly_lt5_T05, nrow(top5), 100 * monthly_lt5_T05 / nrow(top5)))

# ── (6) Top 10%% / 20%% / 30%% comparison ──
cat(sprintf("\n━━━ Threshold sweep — monthly close ret hit ━━━\n"))
cat(sprintf("%-10s %-8s %-15s %-15s %-15s %-15s\n",
            "Variant", "Alerts", "Daily_hit_pct", "Mthly_neg_pct",
            "Mthly<-3%%_pct", "Mean_ret"))
for (v in c("T05", "T10", "T20", "T30")) {
  acol <- paste0("alert_", v)
  sub <- audit[get(acol) == TRUE]
  if (nrow(sub) == 0) next
  cat(sprintf("%-10s %-8d %-15.0f %-15.0f %-15.0f %+.2f%%\n",
              v, nrow(sub),
              100 * mean(sub$y_tail_q15),
              100 * mean(sub$ret_next_month < 0, na.rm = TRUE),
              100 * mean(sub$ret_next_month < -0.03, na.rm = TRUE),
              100 * mean(sub$ret_next_month, na.rm = TRUE)))
}

# ── (7) Inverse bet expected PnL ──
cat(sprintf("\n━━━ Inverse bet expected PnL (1x, no decay assumed) ━━━\n"))
for (v in c("T05", "T10", "T20", "T30")) {
  acol <- paste0("alert_", v)
  sub <- audit[get(acol) == TRUE & !is.na(ret_next_month)]
  if (nrow(sub) == 0) next
  # Inverse return = -ret_next_month
  inv_ret <- -sub$ret_next_month
  cum_inv <- prod(1 + inv_ret) - 1  # cumulative
  mean_inv <- mean(inv_ret)
  sd_inv <- sd(inv_ret)
  hit_pct <- mean(inv_ret > 0)
  cat(sprintf("  %s: n=%d / mean_inv_ret=%+.2f%% / sd=%.2f%% / hit=%.0f%% / cum_inv=%+.1f%%\n",
              v, nrow(sub), 100 * mean_inv, 100 * sd_inv, 100 * hit_pct, 100 * cum_inv))
}

# ── (8) Top 5%% alert을 인버스 베팅했을 때 (no other months) ──
# Cycle 1 baseline: alert 6번 100%% 인버스 vs 그 외 0%% (cash)
cat(sprintf("\n━━━ Top 5%% pure inverse bet (only on alert) ━━━\n"))
top5_active <- top5[!is.na(ret_next_month)]
if (nrow(top5_active) > 0) {
  inv_ret <- -top5_active$ret_next_month
  cum_inv <- prod(1 + inv_ret) - 1
  cat(sprintf("  n_alerts=%d / cum_inverse_ret=%+.2f%% / per_alert_avg=%+.2f%%\n",
              nrow(top5_active), 100 * cum_inv, 100 * mean(inv_ret)))
  if (mean(inv_ret) > 0) {
    cat(sprintf("  ✅ POSITIVE expected — inverse 베팅 가치 있음\n"))
  } else {
    cat(sprintf("  ❌ NEGATIVE expected — inverse 베팅 부적합 (FP가 alpha 잡아먹음)\n"))
  }
}

# ── (9) Save audit ──
fwrite(audit, file.path(WS, "outputs/04_evaluation/top5_alert_month_audit.csv"))
cat(sprintf("\n[CSV] outputs/04_evaluation/top5_alert_month_audit.csv\n"))
cat(sprintf("\n[DONE]\n"))
