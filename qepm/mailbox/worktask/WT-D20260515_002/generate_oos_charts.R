## Forge OOS charts — equity curve / annual returns / OOS zoom / regime decomposition
suppressMessages({
  library(data.table); library(jsonlite); library(ggplot2); library(scales)
})
PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SA <- file.path(PROJ, "stage_artifacts/WT_D20260515_002")
OUT <- file.path(PROJ, "qepm/mailbox/worktask/WT-D20260515_002/output")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

pm <- fread(file.path(SA, "forge_port_monthly.csv"))
pm[, realized_date := as.Date(realized_date)]
pm[, nav_blend_net := cumprod(1 + ret_net)]
pm[, nav_blend_gross := cumprod(1 + ret_gross)]

# STR_1715 PG2 84m subsample NAV
pr_str <- fread(file.path(PROJ,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
pr_str[, anchor_date := as.Date(anchor_date)]
str_84m <- pr_str[realized_ym %in% pm$realized_ym]
setorder(str_84m, anchor_date)
str_84m[, nav_str := cumprod(1 + ret_L5_V2)]

# 1. Equity curve (blend vs STR_1715-only same sample)
nav_df <- data.table(
  date = c(pm$realized_date, str_84m$anchor_date),
  nav = c(pm$nav_blend_net, str_84m$nav_str),
  series = c(rep("Blend 60/40 (net)", nrow(pm)), rep("STR_1715 PG2 (net)", nrow(str_84m)))
)
p_eq <- ggplot(nav_df, aes(x = date, y = nav, color = series)) +
  geom_line(size = 0.8) +
  scale_y_log10(labels = scales::comma) +
  scale_color_manual(values = c("Blend 60/40 (net)" = "#D62728",
                                "STR_1715 PG2 (net)" = "#1F77B4")) +
  labs(title = "WT-D20260515_002 — Equity Curve (84m walk-forward, net of 15bps)",
       subtitle = sprintf("Blend SR_net %.3f vs STR_1715-only 84m SR_net %.3f (production ret_L5_V2)",
                          0.5435, 2.0054),
       x = NULL, y = "NAV (log scale)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))
ggsave(file.path(OUT, "equity_curve.png"), p_eq, width = 11, height = 6, dpi = 130)

# 2. Annual returns bar chart
pm[, year := format(realized_date, "%Y")]
str_84m[, year := format(anchor_date, "%Y")]
ann_blend <- pm[, .(ret_blend = prod(1 + ret_net) - 1), by = year]
ann_str <- str_84m[, .(ret_str = prod(1 + ret_L5_V2) - 1), by = year]
ann_df <- merge(ann_blend, ann_str, by = "year", all = TRUE)
ann_long <- melt(ann_df, id.vars = "year", variable.name = "series",
                 value.name = "annual_return")
ann_long[, series := ifelse(series == "ret_blend", "Blend 60/40", "STR_1715 PG2")]
p_ann <- ggplot(ann_long, aes(x = year, y = annual_return, fill = series)) +
  geom_col(position = position_dodge(0.85), width = 0.75) +
  geom_hline(yintercept = 0, color = "black") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_fill_manual(values = c("Blend 60/40" = "#D62728",
                               "STR_1715 PG2" = "#1F77B4")) +
  labs(title = "WT-D20260515_002 — Annual Returns (net of 15bps)",
       subtitle = "Same 84m sample: blend underperforms STR_1715-only in 6/8 years",
       x = NULL, y = "Annual Return (net)", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))
ggsave(file.path(OUT, "annual_returns.png"), p_ann, width = 11, height = 6, dpi = 130)

# 3. OOS zoom (lockbox 2024-01 to 2025-12 = last 24m)
lb_start <- as.Date("2024-01-01")
lb_end <- as.Date("2025-12-31")
pm_lb <- pm[realized_date >= lb_start & realized_date <= lb_end]
str_lb <- str_84m[anchor_date >= lb_start & anchor_date <= lb_end]
pm_lb[, nav_lb := cumprod(1 + ret_net)]
str_lb[, nav_lb := cumprod(1 + ret_L5_V2)]
nav_lb_df <- data.table(
  date = c(pm_lb$realized_date, str_lb$anchor_date),
  nav = c(pm_lb$nav_lb, str_lb$nav_lb),
  series = c(rep("Blend 60/40", nrow(pm_lb)), rep("STR_1715 PG2", nrow(str_lb)))
)
p_oos <- ggplot(nav_lb_df, aes(x = date, y = nav, color = series)) +
  geom_line(size = 0.9) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray50") +
  scale_color_manual(values = c("Blend 60/40" = "#D62728",
                                "STR_1715 PG2" = "#1F77B4")) +
  labs(title = "WT-D20260515_002 — Lockbox OOS Zoom (2024-01 to 2025-12, 24m)",
       subtitle = "Both series rebased to 1.0 at lockbox start. Net of 15bps.",
       x = NULL, y = "NAV (rebased)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))
ggsave(file.path(OUT, "oos_zoom_chart.png"), p_oos, width = 11, height = 6, dpi = 130)

# 4. Regime decomposition (join via realized_ym, not date)
str_84m_reg <- str_84m[, .(realized_ym, regime, ret_L5_V2)]
pm_reg <- merge(pm[, .(realized_ym, ret_net)], str_84m_reg, by = "realized_ym", all.x = TRUE)
reg_summary <- pm_reg[!is.na(regime), .(
  n = .N,
  mean_ret_blend = mean(ret_net),
  sr_blend = mean(ret_net) / sd(ret_net) * sqrt(12)
), by = regime]
str_reg_summary <- str_84m_reg[!is.na(regime), .(
  mean_ret_str = mean(ret_L5_V2),
  sr_str = mean(ret_L5_V2) / sd(ret_L5_V2) * sqrt(12)
), by = regime]
reg_full <- merge(reg_summary, str_reg_summary, by = "regime", all = TRUE)
reg_full_long <- melt(reg_full, id.vars = c("regime", "n"),
                       measure.vars = c("sr_blend", "sr_str"),
                       variable.name = "series", value.name = "sr")
reg_full_long[, series := ifelse(series == "sr_blend", "Blend 60/40", "STR_1715 PG2")]
p_reg <- ggplot(reg_full_long, aes(x = regime, y = sr, fill = series)) +
  geom_col(position = position_dodge(0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.2f", sr)), position = position_dodge(0.8),
            vjust = -0.3, size = 3.5) +
  scale_fill_manual(values = c("Blend 60/40" = "#D62728",
                               "STR_1715 PG2" = "#1F77B4")) +
  labs(title = "WT-D20260515_002 — Regime-conditional Sharpe (84m sample)",
       subtitle = "Annualized SR_net within each regime (regime field from STR_1715 PG2 R05 panel)",
       x = "Regime", y = "Annualized SR_net", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))
ggsave(file.path(OUT, "regime_decomposition.png"), p_reg, width = 11, height = 6, dpi = 130)

# Persist regime summary
fwrite(reg_full, file.path(SA, "forge_regime_decomposition.csv"))

cat("[forge] OOS charts saved:\n")
cat("  ", file.path(OUT, "equity_curve.png"), "\n")
cat("  ", file.path(OUT, "annual_returns.png"), "\n")
cat("  ", file.path(OUT, "oos_zoom_chart.png"), "\n")
cat("  ", file.path(OUT, "regime_decomposition.png"), "\n")
cat("\nRegime summary:\n"); print(reg_full)
