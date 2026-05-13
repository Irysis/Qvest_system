## WT-H20260513_002 — OOS Chart Mandate (Forge v6.1)
## equity_curve + annual_returns + oos_zoom_chart + regime_decomposition
suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-H20260513_002")
OUT_DIR  <- file.path(WT_DIR, "output")

nav_dt  <- fread(file.path(OUT_DIR, "nav_strict015.csv"))
ret_dt  <- fread(file.path(OUT_DIR, "period_returns_strict015.csv"))
nav_dt[, anchor_date := as.Date(anchor_date)]
ret_dt[, anchor_date := as.Date(anchor_date)]

# Load V2 admit nav for overlay comparison
v2_admit_nav_path <- file.path(BASE_DIR,
  "qepm/mailbox/worktask/WT-H20260513_001/output/nav_layer5_variants.csv")
v2_admit_avail <- file.exists(v2_admit_nav_path)
if (v2_admit_avail) {
  v2_nav <- fread(v2_admit_nav_path)
  v2_nav[, anchor_date := as.Date(anchor_date)]
}

LB_START <- as.Date("2024-01-23")

# =============================================
# 1. Equity curve (full + Lockbox marker + V2 admit overlay)
# =============================================
p1_df <- copy(nav_dt[, .(anchor_date, nav = nav_L5_V2_strict015,
                          variant = "V2_strict_015 (ub=0.15)")])
if (v2_admit_avail) {
  v2_admit_df <- v2_nav[, .(anchor_date, nav = nav_L5_V2,
                              variant = "V2_admit (ub=0.20)")]
  p1_df <- rbind(p1_df, v2_admit_df)
}

p1 <- ggplot(p1_df, aes(x = anchor_date, y = nav, color = variant)) +
  geom_line(size = 0.8) +
  scale_y_log10(breaks = c(1, 2, 5, 10, 20, 50, 100, 200, 500, 1000),
                labels = comma) +
  geom_vline(xintercept = as.numeric(LB_START), linetype = "dashed",
             color = "darkred", alpha = 0.6) +
  annotate("text", x = LB_START, y = 100, label = "Lockbox\nstart",
           hjust = -0.1, vjust = 1, color = "darkred", size = 3) +
  scale_color_manual(values = c("V2_strict_015 (ub=0.15)" = "#E74C3C",
                                  "V2_admit (ub=0.20)" = "#2C3E50")) +
  labs(title = "WT-H20260513_002: Equity Curve V2_strict_015 vs V2_admit",
       subtitle = "267m walk-forward (2004-02 ~ 2026-04), log-scale, sequential overlay",
       x = "Date", y = "NAV (log scale)", color = "Variant") +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "equity_curve.png"), p1,
       width = 11, height = 6, dpi = 150)

# =============================================
# 2. Annual returns bar chart
# =============================================
ret_dt[, year := format(anchor_date, "%Y")]
annual_dt <- ret_dt[, .(
  ann_ret_strict = prod(1 + ret_L5_V2_strict015, na.rm = TRUE) - 1,
  ann_ret_L4 = prod(1 + ret_L4_strict015, na.rm = TRUE) - 1
), by = year]
annual_dt[, year_num := as.integer(year)]

annual_long <- melt(annual_dt[, .(year_num, ann_ret_strict, ann_ret_L4)],
                     id.vars = "year_num",
                     variable.name = "variant", value.name = "ann_ret")
annual_long[, variant := factor(variant,
                                 levels = c("ann_ret_strict", "ann_ret_L4"),
                                 labels = c("L5_V2_strict_015 (ub=0.15)",
                                             "L4_strict_015 (no R05)"))]

p2 <- ggplot(annual_long, aes(x = year_num, y = ann_ret, fill = variant)) +
  geom_col(position = "dodge", alpha = 0.85) +
  geom_hline(yintercept = 0, color = "black") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_x_continuous(breaks = seq(2004, 2026, 2)) +
  scale_fill_manual(values = c("L5_V2_strict_015 (ub=0.15)" = "#E74C3C",
                                  "L4_strict_015 (no R05)" = "#27AE60")) +
  labs(title = "WT-H20260513_002: Annual Returns V2_strict_015",
       subtitle = "L5 V2 (full overlay) vs L4 (no R05) — strict015 base",
       x = "Year", y = "Annual Return", fill = "Variant") +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(file.path(OUT_DIR, "annual_returns.png"), p2,
       width = 11, height = 6, dpi = 150)

# =============================================
# 3. OOS zoom chart (Lockbox period 2024-01 ~ 2026-04, recent 5Y)
# =============================================
oos_dt <- nav_dt[anchor_date >= as.Date("2021-01-01")]
if (nrow(oos_dt) >= 12) {
  # Re-base NAV to 1 at start of zoom
  oos_dt[, nav_L5_rebased := nav_L5_V2_strict015 / nav_L5_V2_strict015[1]]
  oos_dt[, nav_L4_rebased := nav_L4_strict015 / nav_L4_strict015[1]]

  p3_df <- rbind(
    oos_dt[, .(anchor_date, nav = nav_L5_rebased,
                variant = "L5_V2_strict_015 (ub=0.15)")],
    oos_dt[, .(anchor_date, nav = nav_L4_rebased,
                variant = "L4_strict_015 (no R05)")]
  )
  if (v2_admit_avail) {
    v2_oos <- v2_nav[anchor_date >= as.Date("2021-01-01")]
    v2_oos[, nav_v2_rebased := nav_L5_V2 / nav_L5_V2[1]]
    p3_df <- rbind(p3_df,
                    v2_oos[, .(anchor_date, nav = nav_v2_rebased,
                                variant = "V2_admit (ub=0.20)")])
  }

  p3 <- ggplot(p3_df, aes(x = anchor_date, y = nav, color = variant)) +
    geom_line(size = 1) +
    geom_hline(yintercept = 1, color = "gray60", linetype = "dotted") +
    geom_vline(xintercept = as.numeric(LB_START), linetype = "dashed",
               color = "darkred", alpha = 0.7) +
    annotate("text", x = LB_START, y = max(p3_df$nav, na.rm = TRUE),
             label = "Lockbox", hjust = -0.1, vjust = 1,
             color = "darkred", size = 3) +
    scale_y_continuous(breaks = scales::pretty_breaks(8)) +
    scale_color_manual(values = c("L5_V2_strict_015 (ub=0.15)" = "#E74C3C",
                                    "L4_strict_015 (no R05)" = "#27AE60",
                                    "V2_admit (ub=0.20)" = "#2C3E50")) +
    labs(title = "WT-H20260513_002: OOS Zoom (2021-01 ~ 2026-04)",
         subtitle = "Re-based to 1.0 at 2021-01 — includes Lockbox period (2024-01+)",
         x = "Date", y = "NAV (re-based)", color = "Variant") +
    theme_minimal() +
    theme(legend.position = "bottom")
  ggsave(file.path(OUT_DIR, "oos_zoom_chart.png"), p3,
         width = 11, height = 6, dpi = 150)
}

# =============================================
# 4. Regime decomposition (SR per regime, V2_strict_015)
# =============================================
regime_dt <- fread(file.path(OUT_DIR, "regime_decomposition_255m.csv"))
if (nrow(regime_dt) > 0) {
  regime_v2_strict <- regime_dt[variant == "ret_L5_V2_strict015"]
  regime_v2_strict[, regime := factor(regime,
                                        levels = c("BULL", "NORMAL", "CAUTION", "CRISIS"))]
  regime_v2_strict[is.na(SR_ann), SR_ann := 0]

  p4 <- ggplot(regime_v2_strict, aes(x = regime, y = SR_ann, fill = regime)) +
    geom_col(alpha = 0.85) +
    geom_hline(yintercept = 0, color = "black") +
    geom_text(aes(label = sprintf("SR=%.2f\nn=%d", SR_ann, n_months)),
              vjust = ifelse(regime_v2_strict$SR_ann >= 0, -0.3, 1.3),
              size = 3.5) +
    scale_fill_manual(values = c(BULL = "#27AE60", NORMAL = "#3498DB",
                                  CAUTION = "#F39C12", CRISIS = "#E74C3C")) +
    labs(title = "WT-H20260513_002: Regime Decomposition (L5_V2_strict_015)",
         subtitle = "Annualized SR per regime (255m admit-comparable)",
         x = "Regime", y = "Annualized SR", fill = "Regime") +
    theme_minimal() +
    theme(legend.position = "none")
  ggsave(file.path(OUT_DIR, "regime_decomposition.png"), p4,
         width = 10, height = 6, dpi = 150)
}

cat("Charts generated:\n")
cat("  equity_curve.png\n")
cat("  annual_returns.png\n")
cat("  oos_zoom_chart.png\n")
cat("  regime_decomposition.png\n")
