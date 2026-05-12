#==============================================================================
# WT-D20260511_001 PD20-A Path 1 — OOS Charts mandate (v6.1 신규)
# Charts:
#   - equity_curve.png (전기간 + PD18 baseline)
#   - annual_returns.png (Path 1 vs PD18 vs S4 v2)
#   - oos_zoom_chart.png (2024-01 ~ 2026-04 PD13 extension)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(xts); library(zoo)
  library(PerformanceAnalytics)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd20a_path1")
CHART_DIR <- file.path(OUT_DIR, "charts")
dir.create(CHART_DIR, showWarnings = FALSE, recursive = TRUE)

composite <- fread(file.path(OUT_DIR, "composite_returns_5sleeve_pd20a_path1.csv"))
composite[, Date := as.Date(Date)]
setorder(composite, Date)

# Build NAVs
composite[, nav_path1 := cumprod(1 + ret_path1_redist)]
composite[, nav_pd18 := cumprod(1 + ret_pd18_redist)]
composite[, nav_S4 := cumprod(1 + ret_S4_baseline)]

#====================================================
# 1. Equity Curve (전기간)
#====================================================
df_long <- rbind(
  data.frame(Date = composite$Date, nav = composite$nav_path1, strategy = "PD20-A Path 1 (top16+4)"),
  data.frame(Date = composite$Date, nav = composite$nav_pd18, strategy = "PD18 (top20+20) baseline"),
  data.frame(Date = composite$Date, nav = composite$nav_S4, strategy = "S4 v2 (4-sleeve, no NEW)")
)

p1 <- ggplot(df_long, aes(x = Date, y = nav, color = strategy)) +
  geom_line(linewidth = 0.7) +
  scale_y_log10() +
  labs(title = "Equity Curve (Log NAV) — PD20-A Path 1 vs PD18 vs S4 v2",
       subtitle = "256m walk-forward 2005-02 ~ 2026-04 (1715 top16 + NEW top4)",
       x = "Date", y = "Cumulative NAV (log scale)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(CHART_DIR, "equity_curve.png"), p1, width = 11, height = 6, dpi = 100)
cat("Saved: equity_curve.png\n")

#====================================================
# 2. Annual Returns
#====================================================
composite[, Year := format(Date, "%Y")]
annual <- composite[, .(
  ret_path1 = prod(1 + ret_path1_redist) - 1,
  ret_pd18 = prod(1 + ret_pd18_redist) - 1,
  ret_S4 = prod(1 + ret_S4_baseline) - 1
), by = Year]
annual_long <- rbind(
  data.frame(Year = as.numeric(annual$Year), Annual_Return = annual$ret_path1, strategy = "PD20-A Path 1"),
  data.frame(Year = as.numeric(annual$Year), Annual_Return = annual$ret_pd18, strategy = "PD18 baseline"),
  data.frame(Year = as.numeric(annual$Year), Annual_Return = annual$ret_S4, strategy = "S4 v2")
)
p2 <- ggplot(annual_long, aes(x = Year, y = Annual_Return, fill = strategy)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.65) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Annual Returns — PD20-A Path 1 vs PD18 vs S4 v2",
       x = "Year", y = "Annual Return") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(CHART_DIR, "annual_returns.png"), p2, width = 11, height = 6, dpi = 100)
cat("Saved: annual_returns.png\n")

#====================================================
# 3. OOS Zoom Chart (PD13 extension 2024-01 ~ 2026-04, operational monitoring)
#====================================================
zoom <- composite[Date >= as.Date("2024-01-01")]
zoom[, nav_path1_z := cumprod(1 + ret_path1_redist)]
zoom[, nav_pd18_z := cumprod(1 + ret_pd18_redist)]
zoom[, nav_S4_z := cumprod(1 + ret_S4_baseline)]
df_zoom <- rbind(
  data.frame(Date = zoom$Date, nav = zoom$nav_path1_z, strategy = "PD20-A Path 1"),
  data.frame(Date = zoom$Date, nav = zoom$nav_pd18_z, strategy = "PD18 baseline"),
  data.frame(Date = zoom$Date, nav = zoom$nav_S4_z, strategy = "S4 v2")
)
p3 <- ggplot(df_zoom, aes(x = Date, y = nav, color = strategy)) +
  geom_line(linewidth = 0.8) +
  labs(title = "Operational alpha-refresh monitoring 2024-01 ~ 2026-04 (NOT sealed lockbox OOS)",
       subtitle = "PD20-A Path 1 vs PD18 vs S4 v2 — Note: C2 PARTIAL labeling segregation (도훈 mandate)",
       x = "Date", y = "Cumulative NAV (normalized to 1.0 at 2024-01)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(CHART_DIR, "oos_zoom_chart.png"), p3, width = 11, height = 6, dpi = 100)
cat("Saved: oos_zoom_chart.png\n")

#====================================================
# 4. Drawdown comparison
#====================================================
ret_xts_p1 <- xts(composite$ret_path1_redist, order.by = composite$Date)
ret_xts_pd18 <- xts(composite$ret_pd18_redist, order.by = composite$Date)
dd_p1 <- Drawdowns(ret_xts_p1)
dd_pd18 <- Drawdowns(ret_xts_pd18)
df_dd <- rbind(
  data.frame(Date = composite$Date, dd = as.numeric(dd_p1), strategy = "PD20-A Path 1"),
  data.frame(Date = composite$Date, dd = as.numeric(dd_pd18), strategy = "PD18 baseline")
)
p4 <- ggplot(df_dd, aes(x = Date, y = dd, color = strategy)) +
  geom_line(linewidth = 0.7) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Drawdown — PD20-A Path 1 vs PD18 baseline",
       subtitle = "Path 1 MDD -28.07% vs PD18 -11.54% (Δ -16.53pp severe truncation effect)",
       x = "Date", y = "Drawdown") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(CHART_DIR, "drawdown_comparison.png"), p4, width = 11, height = 6, dpi = 100)
cat("Saved: drawdown_comparison.png\n")

cat("\nDONE: 4 charts saved in", CHART_DIR, "\n")
