#==============================================================================
# WT-D20260511_001 PD20-C Path 3 — OOS Charts (Forge v6.1 mandate)
#   - equity_curve.png (walk-forward Lockbox marker)
#   - annual_returns.png
#   - oos_zoom_chart.png (recent 5Y)
#   - regime_decomposition.png (if regime data avail)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(scales); library(xts)
  library(PerformanceAnalytics); library(zoo)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd20c_path3")
CHART_DIR <- file.path(OUT_DIR, "output")
dir.create(CHART_DIR, showWarnings = FALSE, recursive = TRUE)

# Load returns
pr <- fread(file.path(OUT_DIR, "period_returns.csv"))
pr[, Date := as.Date(Date)]
setorder(pr, Date)
non_na <- pr[!is.na(net_return)]

# Compute NAV
non_na[, nav := cumprod(1 + net_return)]

# Compare benchmarks
S4_baseline_ret <- 0.50 * non_na$AR_on_M4 + 0.25 * non_na$TSMOM + 0.20 * non_na$KR_10y + 0.05 * non_na$Cash
non_na[, S4_baseline_ret := S4_baseline_ret]
non_na[, S4_baseline_nav := cumprod(1 + S4_baseline_ret)]

# PD20-B comparison (if avail)
pd20b_path <- file.path(WT_DIR, "backtest_result_pd20b/composite_returns_4sleeve_pd20b.csv")
if (file.exists(pd20b_path)) {
  pd20b_dt <- fread(pd20b_path)
  pd20b_dt[, Date := as.Date(Date)]
  pd20b_dt[, pd20b_nav := cumprod(1 + ret_pd20b_path2_net)]
  pd20b_dt <- pd20b_dt[, .(Date, pd20b_nav)]
  non_na <- merge(non_na, pd20b_dt, by = "Date", all.x = TRUE)
}

# ========= 1. EQUITY CURVE =========
plot_data <- melt(non_na[, .(Date, Path3 = nav, S4_baseline = S4_baseline_nav,
                              PD20B = if ("pd20b_nav" %in% names(non_na)) pd20b_nav else NULL)],
                  id.vars = "Date", variable.name = "Strategy", value.name = "NAV")
plot_data <- plot_data[!is.na(NAV)]

p1 <- ggplot(plot_data, aes(x = Date, y = NAV, color = Strategy)) +
  geom_line(linewidth = 0.8) +
  scale_y_log10(labels = comma_format(accuracy = 1)) +
  scale_color_manual(values = c("Path3" = "#E41A1C", "S4_baseline" = "#377EB8", "PD20B" = "#4DAF4A")) +
  geom_vline(xintercept = as.numeric(as.Date("2023-12-22")), linetype = "dashed", color = "purple", alpha = 0.6) +
  annotate("text", x = as.Date("2023-12-22"), y = max(plot_data$NAV, na.rm=TRUE) * 0.9,
           label = "Lockbox cutoff\n2023-12-22", size = 3, hjust = 1.05, color = "purple") +
  labs(title = "PD20-C Path 3 vs S4 v2 baseline vs PD20-B Path 2 — Equity Curve (256m)",
       subtitle = sprintf("composite 0.45 + buffer keep25/entry20 + Cash 14.5%% | SR=%.4f, MDD=%.4f, RT_TO=%.1f%%",
                          2.0826, 0.1337, 613.0),
       x = "Date", y = "NAV (log scale, starting NAV = 1.0)") +
  theme_minimal() +
  theme(plot.title = element_text(size = 12, face = "bold"),
        legend.position = "top")
ggsave(file.path(CHART_DIR, "equity_curve.png"), p1, width = 11, height = 6, dpi = 100)
cat("Saved: equity_curve.png\n")

# ========= 2. ANNUAL RETURNS =========
non_na[, year := as.integer(format(Date, "%Y"))]
ann_dt <- non_na[, .(annual_path3 = prod(1 + net_return) - 1,
                     annual_s4 = prod(1 + S4_baseline_ret) - 1,
                     n_months = .N), by = year]

plot_ann <- melt(ann_dt, id.vars = c("year", "n_months"),
                  measure.vars = c("annual_path3", "annual_s4"),
                  variable.name = "Strategy", value.name = "AnnualReturn")
plot_ann[, Strategy := ifelse(Strategy == "annual_path3", "Path 3", "S4 baseline")]

p2 <- ggplot(plot_ann, aes(x = factor(year), y = AnnualReturn, fill = Strategy)) +
  geom_bar(stat = "identity", position = "dodge") +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_manual(values = c("Path 3" = "#E41A1C", "S4 baseline" = "#377EB8")) +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.4) +
  labs(title = "PD20-C Path 3 Annual Returns (256m)",
       subtitle = "vs S4 v2 baseline (50/25/20/5)",
       x = "Year", y = "Annual Return") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "top",
        plot.title = element_text(size = 12, face = "bold"))
ggsave(file.path(CHART_DIR, "annual_returns.png"), p2, width = 11, height = 5, dpi = 100)
cat("Saved: annual_returns.png\n")

# ========= 3. OOS ZOOM CHART (recent 5Y: 2021-04 ~ 2026-04) =========
oos_data <- non_na[Date >= as.Date("2021-01-01")]
oos_data[, nav_rebase := nav / nav[1]]
oos_data[, S4_nav_rebase := S4_baseline_nav / S4_baseline_nav[1]]

plot_oos <- melt(oos_data[, .(Date, Path3 = nav_rebase, S4_baseline = S4_nav_rebase)],
                  id.vars = "Date", variable.name = "Strategy", value.name = "NAV_rebase")

p3 <- ggplot(plot_oos, aes(x = Date, y = NAV_rebase, color = Strategy)) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c("Path3" = "#E41A1C", "S4_baseline" = "#377EB8")) +
  geom_vline(xintercept = as.numeric(as.Date("2023-12-22")), linetype = "dashed", color = "purple", alpha = 0.6) +
  annotate("text", x = as.Date("2023-12-22"), y = max(plot_oos$NAV_rebase, na.rm = TRUE) * 0.95,
           label = "Lockbox", size = 3, hjust = 1.05, color = "purple") +
  labs(title = "PD20-C Path 3 OOS Zoom (Recent 5Y: 2021-04 ~ 2026-04)",
       subtitle = "NAV rebased to 1.0 at start | Lockbox cutoff 2023-12-22",
       x = "Date", y = "NAV (rebased)") +
  theme_minimal() +
  theme(plot.title = element_text(size = 12, face = "bold"),
        legend.position = "top")
ggsave(file.path(CHART_DIR, "oos_zoom_chart.png"), p3, width = 11, height = 6, dpi = 100)
cat("Saved: oos_zoom_chart.png\n")

# ========= 4. REGIME DECOMPOSITION (if MRS data available) =========
mrs_path <- ".cache/mrs_state.csv"
if (file.exists(mrs_path)) {
  mrs <- fread(mrs_path)
  if ("date" %in% names(mrs)) mrs[, Date := as.Date(date)] else mrs[, Date := as.Date(Date)]
  mrs[, ym := format(Date, "%Y-%m")]
  # Last regime per month
  mrs_m <- mrs[, .SD[.N], by = ym]
  non_na[, ym := format(Date, "%Y-%m")]
  merged_mrs <- merge(non_na[, .(ym, net_return, S4_baseline_ret)], mrs_m[, .(ym, regime)],
                       by = "ym", all.x = TRUE)
  merged_mrs[is.na(regime), regime := "Unknown"]

  reg_summary <- merged_mrs[, .(
    n_months = .N,
    path3_mean = mean(net_return),
    path3_sd = sd(net_return),
    s4_mean = mean(S4_baseline_ret),
    s4_sd = sd(S4_baseline_ret)
  ), by = regime]
  reg_summary[, path3_SR := path3_mean / path3_sd * sqrt(12)]
  reg_summary[, s4_SR := s4_mean / s4_sd * sqrt(12)]
  reg_summary[, path3_CAGR := (1 + path3_mean)^12 - 1]
  reg_summary[, s4_CAGR := (1 + s4_mean)^12 - 1]

  plot_reg <- melt(reg_summary, id.vars = c("regime", "n_months"),
                    measure.vars = c("path3_SR", "s4_SR"),
                    variable.name = "Strategy", value.name = "SR")
  plot_reg[, Strategy := ifelse(Strategy == "path3_SR", "Path 3", "S4 baseline")]

  p4 <- ggplot(plot_reg, aes(x = regime, y = SR, fill = Strategy)) +
    geom_bar(stat = "identity", position = "dodge") +
    scale_fill_manual(values = c("Path 3" = "#E41A1C", "S4 baseline" = "#377EB8")) +
    geom_text(aes(label = sprintf("%.2f\nN=%d", SR, n_months)),
              position = position_dodge(width = 0.9), vjust = -0.5, size = 3) +
    labs(title = "PD20-C Path 3 Regime Decomposition (SR by MRS state)",
         subtitle = "vs S4 v2 baseline",
         x = "MRS Regime", y = "Annualized SR") +
    theme_minimal() +
    theme(legend.position = "top", plot.title = element_text(size = 12, face = "bold"))
  ggsave(file.path(CHART_DIR, "regime_decomposition.png"), p4, width = 11, height = 6, dpi = 100)
  cat("Saved: regime_decomposition.png\n")
} else {
  cat("MRS state cache not found; skipping regime_decomposition.png\n")
  # Make placeholder
  png(file.path(CHART_DIR, "regime_decomposition.png"), width = 800, height = 400)
  plot.new()
  text(0.5, 0.5, "Regime decomposition: MRS data cache absent\nSee text-based regime metrics in metrics.csv",
       cex = 1.2)
  dev.off()
  cat("Wrote placeholder regime_decomposition.png\n")
}

cat("\nAll OOS charts generated in:", CHART_DIR, "\n")
