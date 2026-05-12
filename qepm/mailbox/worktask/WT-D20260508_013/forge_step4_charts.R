#==============================================================================
# WT-D20260508_013 Forge Step 4 — OOS chart 의무 산출
#
# Per init.md v6.1:
#   - output/equity_curve.png (전기간 walk-forward 5 비중)
#   - output/annual_returns.png (연간 return 비교)
#   - output/oos_zoom_chart.png (recent 60m zoom)
#   - output/regime_decomposition.png (crisis sub-window decomposition)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts); library(ggplot2)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_ID <- "WT-D20260508_013"
SA_DIR <- file.path("stage_artifacts", WT_ID)
FORGE_DIR <- file.path(SA_DIR, "forge")
OUTPUT_DIR <- file.path(FORGE_DIR, "output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("================================================================\n")
cat("[FORGE STEP 4] OOS chart generation\n")
cat("================================================================\n")

# Load 5 ratios period_returns
ratios_pct <- c(0, 5, 10, 15, 20)
all_returns <- list()
for (pct in ratios_pct) {
  pr <- fread(file.path(FORGE_DIR, sprintf("%dpct", pct), "03_period_returns.csv"))
  pr[, date := as.Date(date)]
  pr[, pct_label := sprintf("%d%%", pct)]
  all_returns[[as.character(pct)]] <- pr[, .(date, ret_net, pct_label)]
}
combined <- rbindlist(all_returns)

# 1) Equity curve (전기간 254m)
cat("\n[1] equity_curve.png — 전기간 254m\n")
combined_xts_list <- list()
for (pct in ratios_pct) {
  pr <- all_returns[[as.character(pct)]]
  xt <- xts(pr$ret_net, order.by = pr$date)
  combined_xts_list[[as.character(pct)]] <- xt
}
# Compute equity (cumulative product)
eq_dt <- combined[, .(date, pct_label, ret_net)]
eq_dt[, equity := cumprod(1 + ret_net), by = pct_label]

p1 <- ggplot(eq_dt, aes(x = date, y = equity, color = pct_label)) +
  geom_line(linewidth = 0.7) +
  scale_y_log10() +
  scale_color_manual(values = c("0%"="black", "5%"="#1f77b4", "10%"="#2ca02c",
                                "15%"="#ff7f0e", "20%"="#d62728")) +
  labs(title = "WT-D20260508_013 — Hybrid 4-sleeve 5 비중 Equity Curve (254m)",
       subtitle = "Atilgan 2020 좌측 꼬리 모멘텀 알파 admit 후 Hybrid 70/15/15 변형",
       x = "Date", y = "Equity (log scale)", color = "WT_013 비중") +
  theme_bw() + theme(legend.position = "bottom")
ggsave(file.path(OUTPUT_DIR, "equity_curve.png"), p1, width = 12, height = 7, dpi = 110)
cat("  saved equity_curve.png\n")

# 2) Annual returns
cat("\n[2] annual_returns.png\n")
annual_list <- list()
for (pct in ratios_pct) {
  pr <- all_returns[[as.character(pct)]]
  pr[, year := format(date, "%Y")]
  annu <- pr[, .(annual_ret = prod(1 + ret_net) - 1), by = year]
  annu[, pct_label := sprintf("%d%%", pct)]
  annual_list[[as.character(pct)]] <- annu
}
annual_dt <- rbindlist(annual_list)

p2 <- ggplot(annual_dt, aes(x = year, y = annual_ret, fill = pct_label)) +
  geom_col(position = "dodge", width = 0.8) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_fill_manual(values = c("0%"="grey50", "5%"="#1f77b4", "10%"="#2ca02c",
                                "15%"="#ff7f0e", "20%"="#d62728")) +
  labs(title = "WT-D20260508_013 — Annual Returns 5 비중 비교",
       x = "Year", y = "Annual Return", fill = "WT_013 비중") +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "bottom")
ggsave(file.path(OUTPUT_DIR, "annual_returns.png"), p2, width = 14, height = 7, dpi = 110)
cat("  saved annual_returns.png\n")

# 3) OOS zoom (recent 60m / 5Y)
cat("\n[3] oos_zoom_chart.png — recent 60m zoom\n")
zoom_dt <- combined[date >= as.Date("2021-05-01")]
zoom_dt[, equity := cumprod(1 + ret_net), by = pct_label]

p3 <- ggplot(zoom_dt, aes(x = date, y = equity, color = pct_label)) +
  geom_line(linewidth = 0.9) +
  scale_color_manual(values = c("0%"="black", "5%"="#1f77b4", "10%"="#2ca02c",
                                "15%"="#ff7f0e", "20%"="#d62728")) +
  labs(title = "WT-D20260508_013 — OOS Zoom Recent 60m (2021-05 ~ 2026-04)",
       subtitle = "5 비중 비교 — retail-democratization era (Atilgan 2020 alpha 60m strict 3/3 PASS)",
       x = "Date", y = "Cumulative Return (zoom)", color = "WT_013 비중") +
  theme_bw() + theme(legend.position = "bottom")
ggsave(file.path(OUTPUT_DIR, "oos_zoom_chart.png"), p3, width = 12, height = 7, dpi = 110)
cat("  saved oos_zoom_chart.png\n")

# 4) Regime decomposition (crisis sub-window)
cat("\n[4] regime_decomposition.png — crisis sub-window decomposition\n")
ax_audit <- read_json(file.path(FORGE_DIR, "ax001_v2_realized_audit.json"))
crisis_dt <- rbindlist(lapply(ax_audit$gate4_crisis_alpha_total$sub_window_audit, function(x) {
  if (!isTRUE(x$feasible)) return(NULL)
  data.table(period = x$period,
             range = x$range,
             sleeve = x$sleeve_cum_pct,
             hybrid = x$hyb_cum_pct,
             AR_core = x$ar_cum_pct,
             crisis_alpha_vs_AR = x$crisis_alpha_vs_AR_core_pp,
             crisis_alpha_vs_hyb = x$crisis_alpha_vs_hyb_pp)
}))
crisis_long <- melt(crisis_dt, id.vars = c("period", "range"),
                    measure.vars = c("sleeve", "hybrid", "AR_core"),
                    variable.name = "leg", value.name = "cum_pct")

p4 <- ggplot(crisis_long, aes(x = period, y = cum_pct, fill = leg)) +
  geom_col(position = "dodge", width = 0.7) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  scale_fill_manual(values = c("sleeve"="#d62728", "hybrid"="#1f77b4", "AR_core"="#2ca02c"),
                    labels = c("WT_013 sleeve", "Hybrid 70/15/15", "STR_1715_AR core")) +
  labs(title = "WT-D20260508_013 — Crisis Sub-window Decomposition",
       subtitle = "위기 6개 구간 (2008 GFC ~ 2022 Inflation): sleeve vs Hybrid vs AR core",
       x = "Crisis Period", y = "Cumulative Return (%)", fill = "Leg") +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "bottom")
ggsave(file.path(OUTPUT_DIR, "regime_decomposition.png"), p4, width = 13, height = 7, dpi = 110)
cat("  saved regime_decomposition.png\n")

# 5) Drawdown comparison
cat("\n[5] drawdown_comparison.png\n")
dd_list <- list()
for (pct in ratios_pct) {
  pr <- all_returns[[as.character(pct)]]
  xt <- xts(pr$ret_net, order.by = pr$date)
  nav <- cumprod(1 + xt)
  dd <- nav / cummax(nav) - 1
  dd_list[[as.character(pct)]] <- data.table(date = index(dd), dd = as.numeric(dd),
                                              pct_label = sprintf("%d%%", pct))
}
dd_dt <- rbindlist(dd_list)
p5 <- ggplot(dd_dt, aes(x = date, y = dd, color = pct_label)) +
  geom_line(linewidth = 0.6) +
  scale_color_manual(values = c("0%"="black", "5%"="#1f77b4", "10%"="#2ca02c",
                                "15%"="#ff7f0e", "20%"="#d62728")) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "WT-D20260508_013 — Underwater (Drawdown) 5 비중 비교",
       x = "Date", y = "Drawdown", color = "WT_013 비중") +
  theme_bw() + theme(legend.position = "bottom")
ggsave(file.path(OUTPUT_DIR, "drawdown_comparison.png"), p5, width = 12, height = 7, dpi = 110)
cat("  saved drawdown_comparison.png\n")

cat("\n[FORGE STEP 4] DONE\n")
