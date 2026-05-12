#==============================================================================
# WT-D20260511_001 PD20-B — OOS charts (equity curve + annual returns + zoom)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd20b")
CHART_DIR <- file.path(OUT_DIR, "charts")
dir.create(CHART_DIR, showWarnings = FALSE, recursive = TRUE)

cat("=== PD20-B OOS Charts build ===\n\n")

# Load data
pr <- fread(file.path(OUT_DIR, "period_returns.csv"))
pr[, Date := as.Date(Date)]
setorder(pr, Date)

# S4 v2 baseline
pr[, ret_S4 := 0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash]
# PD18 5-sleeve raw
pd18_dt <- fread(file.path(WT_DIR, "backtest_result_med_10pct_pd18/composite_returns_5sleeve_pd18.csv"))
pd18_dt[, Date := as.Date(Date)]
pr <- merge(pr, pd18_dt[, .(Date, ret_pd18 = ret_5sleeve_redistribute)], by = "Date", all.x = TRUE)

# NAV calc
pr[, nav_pd20b := cumprod(1 + net_return)]
pr[, nav_S4 := cumprod(1 + ret_S4)]
pr[, nav_pd18 := cumprod(1 + ret_pd18)]

# Equity curve
png(file.path(CHART_DIR, "equity_curve.png"), width = 1400, height = 800, res = 140)
par(mar = c(5, 5, 4, 2))
plot(pr$Date, pr$nav_pd20b, type = "l", lwd = 2, col = "#1f77b4",
     xlab = "Date", ylab = "NAV (start = 1.0)",
     main = "PD20-B Path 2 Z-Score Composite vs S4 v2 vs PD18 (256m)",
     log = "y", ylim = c(0.8, max(pr$nav_pd20b, pr$nav_pd18, pr$nav_S4, na.rm = TRUE) * 1.1))
lines(pr$Date, pr$nav_S4, lwd = 1.5, col = "#ff7f0e", lty = 2)
lines(pr$Date, pr$nav_pd18, lwd = 1.5, col = "#2ca02c", lty = 3)
abline(h = 1, col = "gray", lty = 3)
# Lockbox marker (SIGNAL_CUTOFF 2023-12-22)
abline(v = as.Date("2023-12-22"), col = "red", lty = 2, lwd = 1.5)
text(as.Date("2023-12-22"), max(pr$nav_pd20b, na.rm = TRUE) * 0.9,
     "Lockbox cutoff", pos = 4, cex = 0.9, col = "red")
# Composite-active marker
abline(v = as.Date("2011-01-01"), col = "purple", lty = 2, lwd = 1.5)
text(as.Date("2011-01-01"), max(pr$nav_pd20b, na.rm = TRUE) * 0.6,
     "Composite active (NEW alpha start)", pos = 4, cex = 0.9, col = "purple")
legend("topleft", legend = c("PD20-B Path 2 (4-sleeve, comp top20)",
                              "S4 v2 baseline (50/25/20/5)",
                              "PD18 5-sleeve (NEW 10%)"),
       col = c("#1f77b4", "#ff7f0e", "#2ca02c"), lwd = c(2, 1.5, 1.5), lty = c(1, 2, 3), cex = 0.95)
grid()
dev.off()
cat("  equity_curve.png written\n")

# Annual returns
pr[, year := format(Date, "%Y")]
ann_dt <- pr[, .(
  pd20b = prod(1 + net_return) - 1,
  S4 = prod(1 + ret_S4) - 1,
  pd18 = prod(1 + ret_pd18, na.rm = TRUE) - 1
), by = year]

png(file.path(CHART_DIR, "annual_returns.png"), width = 1400, height = 700, res = 140)
par(mar = c(5, 5, 4, 2))
bp_data <- t(as.matrix(ann_dt[, .(pd20b, S4, pd18)]))
barplot(bp_data, beside = TRUE,
        col = c("#1f77b4", "#ff7f0e", "#2ca02c"),
        names.arg = ann_dt$year, las = 2,
        ylab = "Annual return",
        main = "Annual returns: PD20-B Path 2 vs S4 v2 vs PD18 (2005-2026)")
abline(h = 0, col = "black", lwd = 0.5)
legend("topleft", legend = c("PD20-B", "S4 v2", "PD18"),
       fill = c("#1f77b4", "#ff7f0e", "#2ca02c"), cex = 0.9)
grid(nx = NA, ny = NULL)
dev.off()
cat("  annual_returns.png written\n")

# OOS zoom (recent 5Y 2021-2026)
oos_dt <- pr[Date >= as.Date("2021-01-01")]
oos_dt[, nav_pd20b_zoom := cumprod(1 + net_return)]
oos_dt[, nav_S4_zoom := cumprod(1 + ret_S4)]
oos_dt[, nav_pd18_zoom := cumprod(1 + ret_pd18)]

png(file.path(CHART_DIR, "oos_zoom_chart.png"), width = 1400, height = 800, res = 140)
par(mar = c(5, 5, 4, 2))
plot(oos_dt$Date, oos_dt$nav_pd20b_zoom, type = "l", lwd = 2, col = "#1f77b4",
     xlab = "Date", ylab = "NAV (start 2021-01 = 1.0)",
     main = "PD20-B Path 2 OOS zoom (2021-01 ~ 2026-04, 5Y recent)",
     ylim = c(0.8, max(oos_dt$nav_pd20b_zoom, oos_dt$nav_pd18_zoom, oos_dt$nav_S4_zoom, na.rm = TRUE) * 1.05))
lines(oos_dt$Date, oos_dt$nav_S4_zoom, lwd = 1.5, col = "#ff7f0e", lty = 2)
lines(oos_dt$Date, oos_dt$nav_pd18_zoom, lwd = 1.5, col = "#2ca02c", lty = 3)
abline(h = 1, col = "gray", lty = 3)
abline(v = as.Date("2023-12-22"), col = "red", lty = 2, lwd = 1.5)
text(as.Date("2023-12-22"), 1.05, "Lockbox cutoff", pos = 4, cex = 0.9, col = "red")
legend("topleft", legend = c("PD20-B Path 2", "S4 v2 baseline", "PD18 5-sleeve"),
       col = c("#1f77b4", "#ff7f0e", "#2ca02c"), lwd = c(2, 1.5, 1.5), lty = c(1, 2, 3), cex = 0.95)
grid()
dev.off()
cat("  oos_zoom_chart.png written\n")

# Regime decomposition (BULL/BEAR/CAUTION proxy via 12m rolling SR)
# Simple regime tag: positive trailing 12m return = "Trend Up", negative = "Trend Down"
pr_rolling <- copy(pr)
pr_rolling[, trail_12m := frollmean(net_return, n = 12, align = "right", na.rm = TRUE)]
pr_rolling[, regime := ifelse(is.na(trail_12m), "Initial",
                               ifelse(trail_12m > 0.005, "Bull",
                                      ifelse(trail_12m < -0.005, "Bear", "Sideways")))]
regime_summary <- pr_rolling[!is.na(trail_12m),
                              .(N = .N,
                                CAGR = (prod(1 + net_return)^(12 / .N)) - 1,
                                S4_CAGR = (prod(1 + ret_S4)^(12 / .N)) - 1,
                                PD18_CAGR = (prod(1 + ret_pd18, na.rm = TRUE)^(12 / .N)) - 1),
                              by = regime]

png(file.path(CHART_DIR, "regime_decomposition.png"), width = 1200, height = 700, res = 140)
par(mar = c(5, 5, 4, 2))
regime_data <- regime_summary[, .(regime, CAGR, S4_CAGR, PD18_CAGR)]
bp_data <- t(as.matrix(regime_data[, .(CAGR, S4_CAGR, PD18_CAGR)]))
barplot(bp_data, beside = TRUE,
        col = c("#1f77b4", "#ff7f0e", "#2ca02c"),
        names.arg = regime_data$regime,
        ylab = "Annualized return", main = "PD20-B Regime Decomposition (Bull/Bear/Sideways)")
legend("topleft", legend = c("PD20-B", "S4 v2", "PD18"),
       fill = c("#1f77b4", "#ff7f0e", "#2ca02c"), cex = 0.9)
abline(h = 0, col = "black", lwd = 0.5)
grid(nx = NA, ny = NULL)
dev.off()
cat("  regime_decomposition.png written\n")

cat("\nDONE: PD20-B charts.\n")
cat("Output dir:", CHART_DIR, "\n")
