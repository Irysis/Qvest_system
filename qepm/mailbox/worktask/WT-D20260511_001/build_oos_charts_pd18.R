#==============================================================================
# WT-D20260511_001 PD18 — OOS charts mandate (v6.1 신규)
#
# Required:
#   - equity_curve.png (전기간 walk-forward + Lockbox marker)
#   - annual_returns.png
#   - oos_zoom_chart.png (recent 27m 2024-01~2026-04 PD13 extension OOS)
#   - regime_decomposition.png (alpha-active vs pre-alpha period)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR <- "stage_artifacts/WT_D20260511_001"
OUT_DIR <- file.path(WT_DIR, "backtest_result_med_10pct_pd18")
CHART_DIR <- file.path(OUT_DIR, "charts")
dir.create(CHART_DIR, showWarnings = FALSE, recursive = TRUE)

sm_save <- fread(file.path(OUT_DIR, "composite_returns_5sleeve_pd18.csv"))
sm_save[, Date := as.Date(Date)]
setorder(sm_save, Date)

# Build NAV
nav_redist <- cumprod(1 + sm_save$ret_5sleeve_redistribute)
nav_S4 <- cumprod(1 + sm_save$ret_S4_baseline)

cat("=== Building PD18 OOS charts ===\n")

# 1. equity_curve.png
png(file.path(CHART_DIR, "equity_curve.png"), width = 1400, height = 800, res = 100)
par(mar = c(4, 5, 4, 2))
plot(sm_save$Date, nav_redist, type = "l", col = "blue", lwd = 2,
     ylim = c(0, max(nav_redist, nav_S4) * 1.05),
     xlab = "Date", ylab = "NAV (cumulative)",
     main = "PD18 redistribute primary vs S4 v2 baseline (256m walk-forward)")
lines(sm_save$Date, nav_S4, col = "red", lwd = 2)
abline(v = as.Date("2011-01-01"), col = "gray", lty = 2)  # alpha start
abline(v = as.Date("2023-11-01"), col = "purple", lty = 2)  # PD16 frozen cutoff
abline(v = as.Date("2024-01-01"), col = "green", lty = 2)  # PD13 extension start
legend("topleft",
       legend = c("PD18 redistribute (184 dates monthly rebal)",
                  "S4 v2 baseline (4-sleeve)",
                  "alpha start (2011-01)",
                  "PD16 frozen cutoff (2023-11)",
                  "PD13 extension start (2024-01)"),
       col = c("blue", "red", "gray", "purple", "green"),
       lty = c(1, 1, 2, 2, 2), lwd = c(2, 2, 1, 1, 1), bty = "n", cex = 0.9)
grid()
dev.off()
cat("  equity_curve.png saved\n")

# 2. annual_returns.png
sm_save[, year := format(Date, "%Y")]
ann_redist <- sm_save[, .(ret = prod(1 + ret_5sleeve_redistribute) - 1), by = year]
ann_S4 <- sm_save[, .(ret = prod(1 + ret_S4_baseline) - 1), by = year]

png(file.path(CHART_DIR, "annual_returns.png"), width = 1400, height = 800, res = 100)
par(mar = c(4, 5, 4, 2))
years <- ann_redist$year
n_y <- length(years)
bar_data <- rbind(ann_redist$ret, ann_S4$ret) * 100
barplot(bar_data, beside = TRUE, names.arg = years,
        col = c("blue", "red"), border = NA,
        ylab = "Annual return (%)", xlab = "Year",
        main = "Annual returns: PD18 redistribute vs S4 v2 baseline",
        las = 2)
abline(h = 0, col = "black", lwd = 1)
legend("topright", legend = c("PD18 redistribute", "S4 v2 baseline"),
       fill = c("blue", "red"), bty = "n")
dev.off()
cat("  annual_returns.png saved\n")

# 3. oos_zoom_chart.png (PD13 extension 2024-01 ~ 2026-04, 28m)
sm_oos <- sm_save[Date >= as.Date("2024-01-01") & Date <= as.Date("2026-04-30")]
nav_oos_redist <- cumprod(1 + sm_oos$ret_5sleeve_redistribute)
nav_oos_S4 <- cumprod(1 + sm_oos$ret_S4_baseline)

png(file.path(CHART_DIR, "oos_zoom_chart.png"), width = 1400, height = 800, res = 100)
par(mar = c(4, 5, 4, 2))
plot(sm_oos$Date, nav_oos_redist, type = "l", col = "blue", lwd = 3,
     ylim = c(0.95, max(nav_oos_redist, nav_oos_S4) * 1.05),
     xlab = "Date", ylab = "NAV (cumulative, OOS start = 1)",
     main = "PD18 OOS zoom: PD13 extension period (2024-01 ~ 2026-04, alpha 29 new dates monthly rebal)")
lines(sm_oos$Date, nav_oos_S4, col = "red", lwd = 3)
legend("topleft",
       legend = c(sprintf("PD18 redistribute SR=%.2f CAGR=%.1f%%",
                          4.4353, 53.05),
                  sprintf("S4 v2 baseline SR=%.2f CAGR=%.1f%%", 3.6046, 47.6)),
       col = c("blue", "red"), lty = 1, lwd = 3, bty = "n", cex = 1.1)
grid()
dev.off()
cat("  oos_zoom_chart.png saved\n")

# 4. regime_decomposition.png (pre-alpha 2005-02 ~ 2010-12 vs alpha-active 2011-01 ~ 2026-04)
sm_save[, regime := ifelse(Date < as.Date("2011-01-01"), "pre_alpha", "alpha_active")]

regime_metrics <- function(r_vec, label) {
  r_xts <- xts(r_vec, order.by = seq.Date(as.Date("2005-02-01"),
                                            by = "month", length.out = length(r_vec)))
  sr <- as.numeric(SharpeRatio.annualized(r_xts, geometric = TRUE))
  cagr <- as.numeric(Return.annualized(r_xts, geometric = TRUE))
  mdd <- abs(as.numeric(maxDrawdown(r_xts)))
  list(SR = sr, CAGR = cagr, MDD = mdd)
}

pre_alpha_redist <- regime_metrics(sm_save[regime == "pre_alpha"]$ret_5sleeve_redistribute, "pre_alpha")
alpha_active_redist <- regime_metrics(sm_save[regime == "alpha_active"]$ret_5sleeve_redistribute, "alpha_active")
pre_alpha_S4 <- regime_metrics(sm_save[regime == "pre_alpha"]$ret_S4_baseline, "pre_alpha")
alpha_active_S4 <- regime_metrics(sm_save[regime == "alpha_active"]$ret_S4_baseline, "alpha_active")

png(file.path(CHART_DIR, "regime_decomposition.png"), width = 1400, height = 800, res = 100)
par(mfrow = c(1, 3), mar = c(4, 5, 4, 2))
# SR
barplot(matrix(c(pre_alpha_redist$SR, pre_alpha_S4$SR,
                  alpha_active_redist$SR, alpha_active_S4$SR), nrow = 2),
        beside = TRUE, names.arg = c("pre_alpha\n(2005-02 ~ 2010-12)", "alpha_active\n(2011-01 ~ 2026-04)"),
        col = c("blue", "red"), main = "Sharpe Ratio",
        legend.text = c("PD18 redistribute", "S4 v2 baseline"),
        args.legend = list(x = "topleft", bty = "n"))
# CAGR
barplot(matrix(c(pre_alpha_redist$CAGR, pre_alpha_S4$CAGR,
                  alpha_active_redist$CAGR, alpha_active_S4$CAGR) * 100, nrow = 2),
        beside = TRUE, names.arg = c("pre_alpha", "alpha_active"),
        col = c("blue", "red"), main = "CAGR (%)",
        ylab = "CAGR (%)")
# MDD
barplot(matrix(c(pre_alpha_redist$MDD, pre_alpha_S4$MDD,
                  alpha_active_redist$MDD, alpha_active_S4$MDD) * 100, nrow = 2),
        beside = TRUE, names.arg = c("pre_alpha", "alpha_active"),
        col = c("blue", "red"), main = "MDD (% abs)",
        ylab = "MDD (% abs)")
dev.off()
cat("  regime_decomposition.png saved\n")

cat("\nAll 4 charts saved to:", CHART_DIR, "\n")
cat("DONE.\n")
