#==============================================================================
# 25_monthly_rebal_eval.R — 월간 리밸런싱 시점 예측력 평가
#
# 본 평가 목적:
#   매월 첫영업일에 가용한 데이터(직전 월말까지)로 예측한 p_bear가
#   실제 해당 월(다음 calendar month) KOSPI200 수익률과 일치하는지 검증.
#   예: 2026-04-30 종가 데이터까지 사용해 모델이 산출한 p_M2_regime이
#       2026-05 (4/30 → 5/29 close-to-close) 실제 수익률을 정확히 예측했는가?
#
# Output:
#   - outputs/04_evaluation/monthly_rebal_predictions.csv
#   - outputs/06_reports/charts/09_monthly_rebal_eval.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DYN_DIR <- file.path(WS, "outputs/03_models/dynamic_ensemble")
TGT_DIR <- file.path(WS, "outputs/02_targets")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)

# ── (1) Load v1.3 best predictions (M2 Regime-Conditional on y_tail_q15) ──
preds <- as.data.table(read_parquet(
  file.path(DYN_DIR, "predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]
preds[, p := p_M2_regime]
preds <- preds[!is.na(p), .(Date, p, regime)]

# ── (2) Load BM_Close (KOSPI200) ──
bm <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
bm[, Date := as.Date(Date)]
bm <- bm[, .(Date, BM_Close)]
setorder(bm, Date)
bm[, ym := format(Date, "%Y-%m")]

# Month-end (last trading day of each month)
eom <- bm[, .(Date_eom = max(Date), close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)

# Next calendar month forward return (close_eom[t+1] / close_eom[t] - 1)
# data.table::shift(x, n=1, type="lead") returns x[i+1] (next), 이게 정상 방향
eom[, close_eom_next := shift(close_eom, n = 1L, type = "lead")]
eom[, ym_next := shift(ym, n = 1L, type = "lead")]
eom[, Date_eom_next := shift(Date_eom, n = 1L, type = "lead")]
eom[, ret_next_month := close_eom_next / close_eom - 1]
# 마지막 row (live snap 직전 ym)의 다음월은 partial month 가능 (오늘이 월 중간이면)
eom[, days_in_next := as.integer(Date_eom_next - Date_eom)]
eom[, is_partial_next := as.integer(days_in_next < 18)]  # 21 영업일 미만이면 partial

# ── (3) Merge: 월말 시점 p_bear + 다음월 수익률 ──
ms <- merge(eom, preds, by.x = "Date_eom", by.y = "Date", all.x = TRUE)
ms <- ms[!is.na(p) & !is.na(ret_next_month)]
setorder(ms, ym)

cat("=== 월간 리밸런싱 예측력 평가 (월말 snapshot → 다음 calendar month 수익률) ===\n\n")
cat(sprintf("Model: v1.3 5-way M2 Regime-Conditional Dynamic (target = y_tail_q15)\n"))
cat(sprintf("Total months: %d\n", nrow(ms)))
cat(sprintf("Snapshot range: %s ~ %s\n",
            as.character(min(ms$Date_eom)), as.character(max(ms$Date_eom))))
cat(sprintf("실제 다음월 수익률 < 0: %d months (%.1f%%)\n",
            sum(ms$ret_next_month < 0), 100 * mean(ms$ret_next_month < 0)))
cat(sprintf("실제 다음월 수익률 < -3%%: %d months (%.1f%%)\n",
            sum(ms$ret_next_month < -0.03), 100 * mean(ms$ret_next_month < -0.03)))
cat(sprintf("실제 다음월 수익률 < -5%%: %d months (%.1f%%)\n\n",
            sum(ms$ret_next_month < -0.05), 100 * mean(ms$ret_next_month < -0.05)))

# ── (4) Correlation (IC) ──
cor_p <- cor(ms$p, ms$ret_next_month, method = "pearson")
cor_s <- cor(ms$p, ms$ret_next_month, method = "spearman")
cat("━━━ Information Coefficient (월간) ━━━\n")
cat(sprintf("Pearson cor (p, next_month_ret) = %+.4f\n", cor_p))
cat(sprintf("Spearman cor (p, next_month_ret) = %+.4f\n", cor_s))
cat(sprintf("[해석] cor < 0 = 정상 방향 (p 높을수록 수익률 낮음)\n\n"))

# ── (5) Tercile 분석 (Top 30% vs Bot 30%) ──
q30 <- quantile(ms$p, 0.70, na.rm = TRUE)  # 상위 30% 진입 임계값
q70 <- quantile(ms$p, 0.30, na.rm = TRUE)  # 하위 30% 진입 임계값
top30 <- ms[p >= q30]
bot30 <- ms[p <= q70]
mid40 <- ms[p > q70 & p < q30]

cat("━━━ Tercile 분석 ━━━\n")
cat(sprintf("%-25s %-7s %-12s %-12s %-12s\n",
            "Bucket", "N", "mean_ret", "neg_share", "ret<-3%%"))
cat(sprintf("%-25s %-7d %+11.2f%% %11.1f%% %11.1f%%\n",
            sprintf("Top 30%% (p>=%.3f)", q30), nrow(top30),
            100 * mean(top30$ret_next_month),
            100 * mean(top30$ret_next_month < 0),
            100 * mean(top30$ret_next_month < -0.03)))
cat(sprintf("%-25s %-7d %+11.2f%% %11.1f%% %11.1f%%\n",
            "Mid 40%%", nrow(mid40),
            100 * mean(mid40$ret_next_month),
            100 * mean(mid40$ret_next_month < 0),
            100 * mean(mid40$ret_next_month < -0.03)))
cat(sprintf("%-25s %-7d %+11.2f%% %11.1f%% %11.1f%%\n",
            sprintf("Bot 30%% (p<=%.3f)", q70), nrow(bot30),
            100 * mean(bot30$ret_next_month),
            100 * mean(bot30$ret_next_month < 0),
            100 * mean(bot30$ret_next_month < -0.03)))
cat(sprintf("\n[해석] Top 30%% mean_ret < Bot 30%% mean_ret 정도가 직접적 alpha proxy\n"))
cat(sprintf("       Spread = %+.2f pp\n\n",
            100 * (mean(top30$ret_next_month) - mean(bot30$ret_next_month))))

# ── (6) Hit rate at various bear thresholds ──
cat("━━━ Hit Rate (Top 30%% alert 기준) ━━━\n")
cat(sprintf("%-20s %-10s %-10s %-10s %-10s\n",
            "Bear threshold", "Actual", "TP", "Precision", "Recall"))
for (thr in c(0, -0.02, -0.03, -0.05)) {
  bear_actual <- as.integer(ms$ret_next_month < thr)
  pred_alert <- as.integer(ms$p >= q30)
  tp <- sum(pred_alert == 1 & bear_actual == 1)
  fp <- sum(pred_alert == 1 & bear_actual == 0)
  fn <- sum(pred_alert == 0 & bear_actual == 1)
  precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
  cat(sprintf("ret < %+5.0f%%        %-10d %-10d %-10.2f %-10.2f\n",
              100 * thr, sum(bear_actual), tp, precision, recall))
}

# ── (7) 연도별 IC ──
ms[, year := format(Date_eom, "%Y")]
ic_year <- ms[, .(N = .N,
                  pearson = round(cor(p, ret_next_month, method = "pearson"), 3),
                  spearman = round(cor(p, ret_next_month, method = "spearman"), 3),
                  mean_p = round(mean(p), 3),
                  neg_share = sprintf("%.0f%%", 100 * mean(ret_next_month < 0))),
              by = year]
cat("\n━━━ 연도별 IC ━━━\n")
print(ic_year)

# ── (8) 최근 24개월 prediction vs actual detail ──
cat("\n━━━ 최근 24개월 월간 prediction vs actual ━━━\n")
recent_24 <- tail(ms, 24)[, .(Date_eom, target_month = ym_next, p, ret_next_month, regime)]
recent_24[, ret_pct := sprintf("%+.2f%%", 100 * ret_next_month)]
recent_24[, alert := fifelse(p >= q30, "🚨", "  ")]
recent_24[, actual_bear := fifelse(ret_next_month < -0.03, "📉",
                            fifelse(ret_next_month < 0, "▼", "▲"))]
recent_24[, hit := fcase(
  p >= q30 & ret_next_month < -0.03, "✓ TP (high alert + bear)",
  p <= q70 & ret_next_month >= 0, "✓ TN (low alert + bull)",
  p >= q30 & ret_next_month >= 0, "✗ FP (high alert miss)",
  p <= q70 & ret_next_month < -0.03, "✗ FN (low alert miss bear)",
  default = " "
)]
print(recent_24[, .(snap = Date_eom, target = target_month, p = round(p, 3),
                    ret = ret_pct, regime, alert, actual = actual_bear, eval = hit)])

# ── (9) 최신 (live) prediction ──
latest_snap <- ms[.N]
cat(sprintf("\n━━━ 최신 (live) ━━━\n"))
cat(sprintf("Snapshot 기준일: %s\n", as.character(latest_snap$Date_eom)))
cat(sprintf("예측 대상월: %s\n", latest_snap$ym_next))
cat(sprintf("p_M2_regime: %.4f\n", latest_snap$p))
cat(sprintf("Regime (snap day): %s\n", latest_snap$regime))
cat(sprintf("Top 30%% threshold = %.3f\n", q30))
cat(sprintf("→ Status: %s\n", ifelse(latest_snap$p >= q30, "🚨 ALERT (top 30%% — 위험 신호)",
                                       ifelse(latest_snap$p <= q70, "✅ SAFE (bot 30%% — 안정 신호)",
                                              "⚠️ MID (중간 — 모호 신호)"))))
cat(sprintf("실제 ret_next_month: %s\n",
            ifelse(is.na(latest_snap$ret_next_month),
                   "TBD (월 미완성)",
                   sprintf("%+.2f%%", 100 * latest_snap$ret_next_month))))

# 직전 snapshot 5건 (live + 검증된 최근 4개월)
cat("\n━━━ 직전 5개 snapshot 검증 ━━━\n")
last5 <- tail(ms, 5)[, .(snap = Date_eom, target_month = ym_next,
                         p = round(p, 4),
                         q30_threshold = round(q30, 4),
                         alert = ifelse(p >= q30, "🚨", "  "),
                         actual_ret = sprintf("%+.2f%%", 100 * ret_next_month),
                         eval = ifelse(p >= q30 & ret_next_month < -0.03, "✓ TP",
                                ifelse(p <= q70 & ret_next_month >= 0, "✓ TN",
                                ifelse(p >= q30 & ret_next_month >= 0, "✗ FP",
                                ifelse(p <= q70 & ret_next_month < -0.03, "✗ FN", "—")))))]
print(last5)

# ── (10) Save outputs ──
fwrite(ms[, .(snap = Date_eom, target_month = ym_next, p, regime,
              ret_next_month,
              alert = ifelse(p >= q30, 1L, 0L),
              actual_bear_3pct = ifelse(ret_next_month < -0.03, 1L, 0L))],
       file.path(EVAL_DIR, "monthly_rebal_predictions.csv"))
cat(sprintf("\n[CSV] Saved: outputs/04_evaluation/monthly_rebal_predictions.csv (%d rows)\n",
            nrow(ms)))

# ── (11) Chart ──
g <- ggplot(ms, aes(x = Date_eom)) +
  geom_col(aes(y = ret_next_month * 100, fill = ret_next_month < 0),
           alpha = 0.7, width = 25) +
  geom_line(aes(y = (p - 0.5) * 40), color = "#073B4C", linewidth = 0.7) +
  geom_hline(yintercept = (q30 - 0.5) * 40, linetype = "dashed",
             color = "orange", linewidth = 0.4) +
  annotate("text", x = max(ms$Date_eom), y = (q30 - 0.5) * 40 + 1.5,
           label = "p 상위 30%% threshold", color = "orange", size = 3, hjust = 1) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray60") +
  scale_fill_manual(values = c("FALSE" = "#06D6A0", "TRUE" = "#EF476F"),
                    labels = c("FALSE" = "Positive", "TRUE" = "Negative"),
                    name = "Next month") +
  labs(title = "월간 리밸런싱 예측력 — 월말 p_bear (적색선) vs 다음월 수익률 (막대)",
       subtitle = sprintf("Pearson %+.3f / Spearman %+.3f / N=%d months / Top30 spread %+.2fpp",
                          cor_p, cor_s, nrow(ms),
                          100 * (mean(top30$ret_next_month) - mean(bot30$ret_next_month))),
       caption = "Model: v1.3 5-way M2 Regime-Conditional Dynamic (y_tail_q15)",
       x = NULL, y = "Next-month return (%)") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(CHART_DIR, "09_monthly_rebal_eval.png"), g,
       width = 13, height = 5.5, dpi = 120)
cat(sprintf("[Chart 9] Saved: charts/09_monthly_rebal_eval.png\n"))

cat("\n[DONE]\n")
