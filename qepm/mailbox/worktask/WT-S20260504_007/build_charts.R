## ============================================================================
## WT-S20260504_007 — Forge Charts (OOS Chart Mandate v6.1)
## Equity curves (4 variants) + annual returns + OOS zoom + regime decomposition
## ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xts)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID    <- "WT-S20260504_007"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
OUT_DIR  <- file.path(WT_DIR, "output")
BT_DIR   <- file.path(WT_DIR, "backtest_result")
SA_DIR   <- file.path(BASE_DIR, "stage_artifacts", paste0("WT_", WT_ID))

cat("[charts] Loading 4 bt_results\n")
variants <- c("S0_baseline", "S1_threshold", "S2_linear", "S3_sigmoid")
nav_list <- list()
for (v in variants) {
  bt <- readRDS(file.path(BT_DIR, sprintf("bt_result_%s.rds", v)))
  nav_dt <- bt$nav
  nav_dt[, variant := v]
  nav_list[[v]] <- nav_dt[, .(date, nav_net, variant)]
}
nav_all <- rbindlist(nav_list)

# ─────────────────────────────────────────────────────────
# 1. Equity curve (full period log scale)
# ─────────────────────────────────────────────────────────
cat("[charts] Equity curve (full period)\n")

LB_START <- as.Date("2024-01-23")  # STR_1715 lockbox start (OOS marker)

p1 <- ggplot(nav_all, aes(x = date, y = nav_net, color = variant)) +
  geom_line(linewidth = 0.7) +
  geom_vline(xintercept = LB_START, linetype = "dashed", color = "red", alpha = 0.6) +
  annotate("text", x = LB_START, y = max(nav_all$nav_net) * 0.9,
           label = "Lockbox / OOS start (2024-01)", color = "red",
           hjust = -0.05, size = 3) +
  scale_y_log10(labels = label_number(big.mark = ",")) +
  scale_color_manual(values = c(
    "S0_baseline" = "black",
    "S1_threshold" = "#1f77b4",
    "S2_linear" = "#ff7f0e",
    "S3_sigmoid" = "#2ca02c"
  )) +
  labs(
    title = "WT-S20260504_007 AR Pure Overlay — 4 Variant Equity Curves (268m)",
    subtitle = paste0(
      "Walk-forward share-based NAV. STR_1715 alpha 100% preserved (rank_corr=1.0). ",
      "15bps cost. Log scale."
    ),
    x = NULL, y = "NAV (log, start=100)",
    color = "Variant",
    caption = "Forge run_all.R — Pure Function. Codex Round mandatory."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width = 11, height = 6, dpi = 130)

# ─────────────────────────────────────────────────────────
# 2. OOS zoom (Lockbox period 2024-01 ~ end)
# ─────────────────────────────────────────────────────────
cat("[charts] OOS zoom chart (Lockbox period)\n")

nav_oos <- nav_all[date >= LB_START]
# Renormalize to 100 at LB_START
nav_oos[, nav_norm := nav_net / nav_net[1], by = variant]
nav_oos[, nav_idx := nav_norm * 100]

p2 <- ggplot(nav_oos, aes(x = date, y = nav_idx, color = variant)) +
  geom_line(linewidth = 0.9) +
  geom_hline(yintercept = 100, linetype = "dotted", alpha = 0.5) +
  scale_color_manual(values = c(
    "S0_baseline" = "black",
    "S1_threshold" = "#1f77b4",
    "S2_linear" = "#ff7f0e",
    "S3_sigmoid" = "#2ca02c"
  )) +
  labs(
    title = "OOS Zoom — Lockbox period (2024-01 ~ today)",
    subtitle = sprintf("Renormalized to 100 at %s (STR_1715 PG2 frozen lockbox release)",
                       format(LB_START, "%Y-%m-%d")),
    x = NULL, y = "NAV (normalized, LB_START=100)",
    color = "Variant"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "oos_zoom_chart.png"), p2, width = 11, height = 6, dpi = 130)

# ─────────────────────────────────────────────────────────
# 3. Annual returns
# ─────────────────────────────────────────────────────────
cat("[charts] Annual returns chart\n")

# Compute annual returns from monthly via apply.yearly
annual_list <- list()
for (v in variants) {
  bt <- readRDS(file.path(BT_DIR, sprintf("bt_result_%s.rds", v)))
  pr <- bt$period_returns
  ret_xts <- xts(pr$ret_net, order.by = pr$date)
  yearly <- apply.yearly(ret_xts, Return.cumulative)
  annual_list[[v]] <- data.table(
    year = format(index(yearly), "%Y"),
    ret = as.numeric(yearly),
    variant = v
  )
}
annual_dt <- rbindlist(annual_list)

p3 <- ggplot(annual_dt, aes(x = year, y = ret, fill = variant)) +
  geom_bar(stat = "identity", position = position_dodge(0.85), width = 0.8) +
  geom_hline(yintercept = 0, color = "black", alpha = 0.5) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  scale_fill_manual(values = c(
    "S0_baseline" = "black",
    "S1_threshold" = "#1f77b4",
    "S2_linear" = "#ff7f0e",
    "S3_sigmoid" = "#2ca02c"
  )) +
  labs(
    title = "Annual Returns (calendar-year compound)",
    subtitle = "AR Pure Overlay 4 variants",
    x = NULL, y = "Annual Return",
    fill = "Variant"
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1, size = 8))

ggsave(file.path(OUT_DIR, "annual_returns.png"), p3, width = 13, height = 6, dpi = 130)

# ─────────────────────────────────────────────────────────
# 4. AR-regime decomposition (β_t schedule + variant returns by regime)
# ─────────────────────────────────────────────────────────
cat("[charts] AR-regime decomposition\n")

ovl <- fread(file.path(SA_DIR, "overlay_schedule.csv"))
ovl[, date := as.Date(date)]

# Plot β_t schedule for 3 variants
ovl_long <- melt(ovl[, .(date, beta_linear, beta_threshold, beta_sigmoid)],
                  id.vars = "date", variable.name = "variant", value.name = "beta")
ovl_long[, variant := gsub("beta_", "", variant)]

p4 <- ggplot(ovl_long, aes(x = date, y = beta, color = variant)) +
  geom_line(linewidth = 0.7) +
  scale_y_continuous(labels = label_percent(accuracy = 1), limits = c(0, 1.05)) +
  scale_color_manual(values = c(
    "linear" = "#ff7f0e",
    "threshold" = "#1f77b4",
    "sigmoid" = "#2ca02c"
  )) +
  labs(
    title = "β_t Overlay Schedule (3 mapping variants × 268 months)",
    subtitle = "AR_t = top-5 eigenvalue / total variance (Kritzman-Page-Turkington 2011, K=5/W=252)",
    x = NULL, y = "β_t (gross exposure)",
    color = "Mapping",
    caption = "β_t < 1 ⇒ partial cash. β_t = 0 (linear only) ⇒ all cash month."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "regime_decomposition.png"), p4, width = 11, height = 5.5, dpi = 130)

cat("[charts] DONE — 4 charts saved to ", OUT_DIR, "\n", sep = "")
cat("  - equity_curve.png\n")
cat("  - oos_zoom_chart.png\n")
cat("  - annual_returns.png\n")
cat("  - regime_decomposition.png\n")
