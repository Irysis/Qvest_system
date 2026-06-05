#==============================================================================
# 23_recent_12m_brief.R — 최근 12개월 (2025-05-19 ~ 2026-05-19) 예측력 분석
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(ggplot2)
  library(patchwork); library(scales)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DYN_DIR <- file.path(WS, "outputs/03_models/dynamic_ensemble")
TGT_DIR <- file.path(WS, "outputs/02_targets")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

END_DATE <- as.Date("2026-05-19")
START_DATE <- END_DATE - 365  # 12개월

# Load v1.3 best predictions (M2 Regime-Conditional) for y_tail_q15
preds <- as.data.table(read_parquet(
  file.path(DYN_DIR, "predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]

# Filter recent 12m
recent <- preds[Date >= START_DATE & Date <= END_DATE]
setorder(recent, Date)

cat("=== 최근 12개월 (2025-05-19 ~ 2026-05-19) 예측력 ===\n\n")
cat(sprintf("Total trading days: %d\n", nrow(recent)))
cat(sprintf("Date range: %s ~ %s\n",
            as.character(min(recent$Date)), as.character(max(recent$Date))))
cat(sprintf("실제 약세 events (y_tail_q15=1): %d (%.2f%%)\n",
            sum(recent$y), 100 * mean(recent$y)))

# Use M2 Regime (v1.3 best)
recent[, p := p_M2_regime]
recent <- recent[!is.na(p)]
cat(sprintf("Valid predictions: %d\n\n", nrow(recent)))

# ── PR-AUC + baseline ──
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

prevalence <- mean(recent$y)
pa <- pr_auc(recent$p, recent$y)
cat(sprintf("PR-AUC (recent 12m): %.4f\n", pa))
cat(sprintf("Baseline (prevalence): %.4f\n", prevalence))
cat(sprintf("Lift: %.2f%% (= %.2fx random)\n\n",
            100 * (pa - prevalence) / prevalence, pa / prevalence))

# ── Threshold tuning ──
n_total <- nrow(recent)
total_events <- sum(recent$y)
cat("=== Threshold tuning (top % alert) ===\n")
cat(sprintf("%-10s %-10s %-10s %-10s %-10s\n",
            "Top %", "Alerts", "TP", "Precision", "Recall"))
for (pct in c(0.05, 0.10, 0.15, 0.20, 0.30, 0.50)) {
  k <- ceiling(n_total * pct)
  alert_idx <- order(recent$p, decreasing = TRUE)[1:k]
  tp <- sum(recent$y[alert_idx])
  prec <- tp / k
  rec <- tp / total_events
  cat(sprintf("%-10s %-10d %-10d %-10.2f %-10.2f\n",
              sprintf("%.0f%%", 100 * pct), k, tp, prec, rec))
}

# ── Top alert dates ──
cat("\n=== Top 10 highest p_bear days (최근 12m) ===\n")
top10 <- recent[order(-p)][1:10, .(Date, p, y, regime)]
print(top10)

# ── 월별 평균 p_bear + actual events ──
recent[, ym := format(Date, "%Y-%m")]
monthly <- recent[, .(N = .N, mean_p = mean(p), n_events = sum(y),
                       max_p = max(p)), by = ym]
cat("\n=== 월별 요약 ===\n")
print(monthly)

# ── Specific period analysis: 2024-08 폭락 vs 2025-2026 강세 ──
# (단 OOS 2016~2026-04이므로 2024-08은 별도, 2025-05~2026-05는 본 recent 12m)
yoy_period <- list(
  "2025-05~2025-08 (여름 변동성)" = c("2025-05-01", "2025-08-31"),
  "2025-09~2025-12 (가을~연말)" = c("2025-09-01", "2025-12-31"),
  "2026-01~2026-04 (YTD 강세)" = c("2026-01-01", "2026-04-30")
)

cat("\n=== 시기별 (sub-period) 평균 p_bear + events ===\n")
for (name in names(yoy_period)) {
  rng <- as.Date(yoy_period[[name]])
  sub <- recent[Date >= rng[1] & Date <= rng[2]]
  if (nrow(sub) == 0) next
  cat(sprintf("  %-30s : N=%d / mean_p=%.3f / max_p=%.3f / events=%d\n",
              name, nrow(sub), mean(sub$p), max(sub$p), sum(sub$y)))
}

# ── Chart: recent 12m timeline ──
g <- ggplot(recent, aes(x = Date, y = p)) +
  geom_line(color = "#073B4C", alpha = 0.7, linewidth = 0.4) +
  geom_point(data = recent[y == 1], aes(x = Date, y = p),
             color = "#EF476F", size = 1.5, alpha = 0.7) +
  geom_hline(yintercept = quantile(recent$p, 0.8, na.rm = TRUE),
             linetype = "dashed", color = "orange") +
  annotate("text", x = max(recent$Date), y = quantile(recent$p, 0.83, na.rm = TRUE),
           label = "top 20% alert threshold", color = "orange", size = 3, hjust = 1) +
  geom_hline(yintercept = quantile(recent$p, 0.9, na.rm = TRUE),
             linetype = "dotted", color = "red") +
  annotate("text", x = max(recent$Date), y = quantile(recent$p, 0.92, na.rm = TRUE),
           label = "top 10% high-confidence", color = "red", size = 3, hjust = 1) +
  labs(title = sprintf("Chart — Recent 12M (2025-05 ~ 2026-05) p_bear (v1.3 M2 Regime)"),
       subtitle = sprintf("PR-AUC %.4f / baseline %.4f / lift %.1fx / events %d / days %d",
                          pa, prevalence, pa / prevalence,
                          sum(recent$y), nrow(recent)),
       x = NULL, y = "Predicted probability (M2 Regime)") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(CHART_DIR, "08_recent_12m_timeline.png"), g,
       width = 12, height = 5, dpi = 120)
cat(sprintf("\n[Chart 8] Saved: %s/08_recent_12m_timeline.png\n", CHART_DIR))

# Save recent metrics
fwrite(recent[, .(Date, p, y, regime)],
       file.path(WS, "outputs/04_evaluation/recent_12m_predictions.csv"))
cat(sprintf("[CSV] Saved: outputs/04_evaluation/recent_12m_predictions.csv\n"))
