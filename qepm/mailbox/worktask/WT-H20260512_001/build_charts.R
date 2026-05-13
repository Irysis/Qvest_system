## Build charts for WT-H20260512_001 (Forge OOS Chart Mandate)
suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
  library(jsonlite)
  library(xts)
  library(PerformanceAnalytics)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-H20260512_001"
BT   <- file.path(BASE, "backtest_result")
OUT  <- file.path(BASE, "output")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

variants <- c("V1_equal_norm_sqrt2", "V2_equal_simple_50_50",
              "V3_ic_weighted_exp", "V4_regime_4state",
              "V5_defense_amplifier")
BEST_VARIANT <- "V5_defense_amplifier"

# Load all variants period returns
all_pr <- list()
for (v in variants) {
  pr <- fread(file.path(BT, sprintf("period_returns_%s.csv", v)))
  pr[, period_end := as.Date(period_end)]
  pr[, variant := v]
  all_pr[[v]] <- pr
}
pr_all <- rbindlist(all_pr, use.names = TRUE, fill = TRUE)

# Compute NAV per variant (PerformanceAnalytics-compatible cumprod via Return.cumulative)
# Note: cumprod(1+r) for NAV display is permitted (Backtest Contract v1.0)
pr_all[, nav := cumprod(1 + ret_net), by = variant]

# 1. Equity curve
LB_START <- as.Date("2024-01-23")
p_eq <- ggplot(pr_all, aes(x = period_end, y = nav, color = variant)) +
  geom_line(linewidth = 0.8) +
  geom_vline(xintercept = LB_START, linetype = "dashed", color = "red", alpha = 0.6) +
  annotate("text", x = LB_START + 30, y = max(pr_all$nav, na.rm = TRUE) * 0.9,
           label = "Lockbox\n2024-01-23", color = "red", size = 3, hjust = 0) +
  scale_y_log10(labels = comma) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(
    title = "STR_1715_ZSC_v1 — 5 Variants Equity Curve (NAV, log scale, 267m)",
    subtitle = sprintf("Best variant: %s | Baseline Layer 1 SR=1.6315 (not shown)", BEST_VARIANT),
    x = "Date", y = "NAV (initial=1)", color = "Variant"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(OUT, "equity_curve.png"),
       p_eq, width = 11, height = 6.5, dpi = 150)
cat("Saved: equity_curve.png\n")

# 2. Annual returns
pr_all[, year := as.integer(format(period_end, "%Y"))]
ann_ret <- pr_all[, .(annual_ret = prod(1 + ret_net) - 1), by = .(variant, year)]
ann_ret <- ann_ret[year >= 2005]

p_ann <- ggplot(ann_ret, aes(x = year, y = annual_ret * 100, fill = variant)) +
  geom_col(position = "dodge") +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.4) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  labs(
    title = "STR_1715_ZSC_v1 — Annual Returns by Variant (2005~2026)",
    subtitle = sprintf("Best variant: %s", BEST_VARIANT),
    x = "Year", y = "Annual Return", fill = "Variant"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(OUT, "annual_returns.png"),
       p_ann, width = 12, height = 6.5, dpi = 150)
cat("Saved: annual_returns.png\n")

# 3. OOS zoom (Lockbox 2024-01 onwards + recent 5Y for diagnostic only)
OOS_START <- as.Date("2021-01-01")  # 5Y zoom
pr_oos <- pr_all[period_end >= OOS_START]
# Re-base NAV per variant from OOS_START
pr_oos[, nav_oos := cumprod(1 + ret_net), by = variant]

p_oos <- ggplot(pr_oos, aes(x = period_end, y = nav_oos, color = variant)) +
  geom_line(linewidth = 0.9) +
  geom_vline(xintercept = LB_START, linetype = "dashed", color = "red", alpha = 0.6) +
  annotate("text", x = LB_START + 15, y = max(pr_oos$nav_oos, na.rm = TRUE) * 0.92,
           label = "Lockbox\n2024-01-23", color = "red", size = 3, hjust = 0) +
  scale_y_continuous(labels = comma) +
  scale_x_date(date_breaks = "6 months", date_labels = "%Y-%m") +
  labs(
    title = "STR_1715_ZSC_v1 — Recent 5Y OOS Zoom (NAV rebased from 2021-01)",
    subtitle = "Diagnostic only — Lockbox scope NOT applied per lockbox-scope.md (forge=deprecated, 2026-05-09)",
    x = "Date", y = "NAV (rebased=1)", color = "Variant"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(OUT, "oos_zoom_chart.png"),
       p_oos, width = 12, height = 6.5, dpi = 150)
cat("Saved: oos_zoom_chart.png\n")

# 4. Regime decomposition (V5 best variant)
regime_dt <- fread(file.path(BT, sprintf("regime_decomposition_%s.csv", BEST_VARIANT)))
regime_dt[, regime := factor(regime, levels = c("BULL","NORMAL","CAUTION","CRISIS"))]
p_reg <- ggplot(regime_dt, aes(x = regime, y = sr_ann, fill = regime)) +
  geom_col() +
  geom_text(aes(label = sprintf("SR=%.2f\nn=%d", sr_ann, n_months)),
            vjust = ifelse(regime_dt$sr_ann >= 0, -0.3, 1.2),
            size = 4) +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.4) +
  scale_fill_manual(values = c("BULL" = "#2ecc71", "NORMAL" = "#3498db",
                                 "CAUTION" = "#f39c12", "CRISIS" = "#e74c3c")) +
  labs(
    title = sprintf("STR_1715_ZSC_v1 — Per-Regime SR Decomposition (Best: %s)",
                     BEST_VARIANT),
    subtitle = "n_months = period count per regime | sr_ann = annualized Sharpe",
    x = "Regime", y = "Annualized Sharpe"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none")
ggsave(file.path(OUT, "regime_decomposition.png"),
       p_reg, width = 10, height = 6, dpi = 150)
cat("Saved: regime_decomposition.png\n")

# 5. Variant comparison bar chart (key visualization)
metrics_dt <- fread(file.path(BT, "metrics_grid_all_variants.csv"))
metrics_267 <- metrics_dt[grepl("_267m_raw_cover", label)]
metrics_267[, variant := gsub("_267m_raw_cover", "", label)]

# Add baseline rows
baseline_l1_267 <- data.table(
  label = "BASELINE_Layer1_no_overlay_267m",
  n_months = 267,
  CAGR = 0.4351, Vol = 0.2667, Sharpe = 1.6315, MDD = -0.4074,
  Sortino = 0.8738, Calmar = 1.0682, HitRate = NA_real_,
  variant = "BASELINE_L1_no_overlay"
)
baseline_admit <- data.table(
  label = "BASELINE_Admit_overlay_inclusive_256m",
  n_months = 256,
  CAGR = NA_real_, Vol = NA_real_, Sharpe = 1.7758, MDD = -0.2515,
  Sortino = NA_real_, Calmar = NA_real_, HitRate = NA_real_,
  variant = "BASELINE_AR_on_M4_overlay"
)
compare_dt <- rbindlist(list(metrics_267, baseline_l1_267, baseline_admit), use.names = TRUE, fill = TRUE)

p_cmp <- ggplot(compare_dt, aes(x = reorder(variant, -Sharpe), y = Sharpe, fill = variant)) +
  geom_col() +
  geom_text(aes(label = sprintf("SR=%.3f\nMDD=%.1f%%", Sharpe, MDD * 100)),
            vjust = -0.2, size = 3.2) +
  geom_hline(yintercept = 1.6315, linetype = "dashed", color = "red", alpha = 0.6) +
  annotate("text", x = 1.5, y = 1.65,
           label = "Layer1 baseline SR=1.6315", color = "red", size = 3, hjust = 0) +
  scale_fill_brewer(palette = "Set3") +
  scale_y_continuous(limits = c(0, 2.0)) +
  labs(
    title = "STR_1715_ZSC_v1 — Variant vs Baseline Comparison (267m)",
    subtitle = "Conclusion: All 5 ZSC variants underperform Layer1 same-mechanism baseline",
    x = "Variant", y = "Annualized Sharpe (PerformanceAnalytics geometric)"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        axis.text.x = element_text(angle = 30, hjust = 1, size = 9))
ggsave(file.path(OUT, "variant_vs_baseline_comparison.png"),
       p_cmp, width = 11, height = 6.5, dpi = 150)
cat("Saved: variant_vs_baseline_comparison.png\n")

cat("\n=== All charts saved to ", OUT, " ===\n")
