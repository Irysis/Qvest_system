## ============================================================================
## STR_1715 May 2026 Forward Recompute — Step 4: OOS zoom chart + provenance
##
## v6.1 OOS Chart Mandate compliance:
##   - oos_zoom_chart.png (Lockbox period 2024-01-23 ~ 2026-01-23 + post-LB to today)
##   - Reuses existing M4 backtest (WT-D20260430_001) NAV (admitted as production)
## ============================================================================

cat("=== STR_1715 May 2026 Forward — Step 4: OOS zoom chart ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(ggplot2); library(scales)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-P20260429_002"
OUT_DIR      <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID, "forge_may2026")

LOCKBOX_START <- as.Date("2024-01-23")
LOCKBOX_END   <- as.Date("2026-01-23")

# ---- Load existing STR_1715 NAV from production output ----
nav_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/02_nav.csv")
if (file.exists(nav_path)) {
  nav_dt <- fread(nav_path)
  if ("date" %in% names(nav_dt)) setnames(nav_dt, "date", "Date")
  if ("Date" %in% names(nav_dt)) nav_dt[, Date := as.Date(Date)]
  cat(sprintf("[Step 4] STR_1715 NAV: %d rows\n  cols: %s\n",
              nrow(nav_dt), paste(names(nav_dt), collapse=", ")))
  cat(sprintf("  range %s ~ %s\n", min(nav_dt$Date, na.rm=TRUE), max(nav_dt$Date, na.rm=TRUE)))
} else {
  stop("NAV path not found: ", nav_path)
}

# Choose NAV column — prefer nav_net (after cost) > nav_gross
nav_col <- if ("nav_net" %in% names(nav_dt)) "nav_net" else
           if ("nav_gross" %in% names(nav_dt)) "nav_gross" else
           if ("NAV" %in% names(nav_dt)) "NAV" else
           if ("Wealth" %in% names(nav_dt)) "Wealth" else names(nav_dt)[2]
cat(sprintf("[Step 4] Using NAV column: %s\n", nav_col))

setnames(nav_dt, nav_col, "NAV")
nav_dt <- nav_dt[!is.na(NAV) & NAV > 0]
nav_dt[, NAV := NAV / NAV[1L]]  # rebase to 1.0

# ---- OOS zoom: 2023-01-01 ~ today (covers pre-lockbox + lockbox + post-lockbox) ----
zoom_start <- as.Date("2023-01-01")
zoom_dt <- nav_dt[Date >= zoom_start]
cat(sprintf("[Step 4] OOS zoom range: %s ~ %s (%d points)\n",
            min(zoom_dt$Date), max(zoom_dt$Date), nrow(zoom_dt)))

# Re-index NAV in zoom window to start at 1.0
zoom_dt[, NAV_rebased := NAV / NAV[1L]]

p_oos <- ggplot(zoom_dt, aes(x = Date, y = NAV_rebased)) +
  # Lockbox shaded region
  annotate("rect", xmin = LOCKBOX_START, xmax = LOCKBOX_END, ymin = -Inf, ymax = Inf,
           fill = "red", alpha = 0.10) +
  geom_line(color = "steelblue", linewidth = 0.7) +
  geom_vline(xintercept = LOCKBOX_START, linetype = "dashed", color = "red") +
  geom_vline(xintercept = LOCKBOX_END,   linetype = "dashed", color = "red") +
  geom_vline(xintercept = as.Date("2026-05-01"),
             linetype = "dotted", color = "darkgreen", linewidth = 0.8) +
  annotate("text", x = LOCKBOX_START, y = max(zoom_dt$NAV_rebased) * 0.96,
           label = "Lockbox\nstart\n2024-01-23", color = "red", size = 3, hjust = -0.05) +
  annotate("text", x = LOCKBOX_END,   y = max(zoom_dt$NAV_rebased) * 0.96,
           label = "Lockbox\nend\n2026-01-23", color = "red", size = 3, hjust = -0.05) +
  annotate("text", x = as.Date("2026-05-01"),
           y = min(zoom_dt$NAV_rebased) * 1.05,
           label = "5월 운용\n2026-05-01", color = "darkgreen", size = 3, hjust = 1.05) +
  scale_y_continuous(name = "NAV (rebased)", labels = label_number(accuracy = 0.01)) +
  scale_x_date(date_breaks = "6 months", date_labels = "%Y-%m") +
  labs(title = "STR_1715 OOS Zoom Chart — Lockbox period + May 2026 운용 entry",
       subtitle = sprintf("Pre-LB (2023-01~2024-01-22) + Lockbox (2024-01-23~2026-01-23) + Post-LB (2026-01-24~%s)",
                          as.character(max(zoom_dt$Date))),
       x = "Date") +
  theme_minimal() +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"))

oos_zoom_path <- file.path(OUT_DIR, "oos_zoom_chart_may2026.png")
ggsave(oos_zoom_path, p_oos, width = 11, height = 6, dpi = 150)
cat(sprintf("[Step 4] OOS zoom chart saved: %s\n", oos_zoom_path))

# ---- Equity curve (full period, with Lockbox marker) ----
nav_full <- nav_dt
nav_full[, NAV_rebased := NAV / NAV[1L]]

p_full <- ggplot(nav_full, aes(x = Date, y = NAV_rebased)) +
  annotate("rect", xmin = LOCKBOX_START, xmax = LOCKBOX_END, ymin = -Inf, ymax = Inf,
           fill = "red", alpha = 0.10) +
  geom_line(color = "steelblue", linewidth = 0.6) +
  geom_vline(xintercept = LOCKBOX_START, linetype = "dashed", color = "red") +
  geom_vline(xintercept = LOCKBOX_END,   linetype = "dashed", color = "red") +
  scale_y_log10(name = "NAV (log scale, rebased)", labels = label_number(accuracy = 0.01)) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(title = "STR_1715 Equity Curve — Full period with Lockbox marker",
       subtitle = sprintf("range: %s ~ %s | sleeves: Iter5 alpha → Iter31 LinearTilt λ=1.5/TOphi=3 + Cash overlay",
                          as.character(min(nav_full$Date)), as.character(max(nav_full$Date))),
       x = "Date") +
  theme_minimal() +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"))

eq_path <- file.path(OUT_DIR, "equity_curve_may2026.png")
ggsave(eq_path, p_full, width = 12, height = 6, dpi = 150)
cat(sprintf("[Step 4] Equity curve saved: %s\n", eq_path))

# ---- OOS metrics summary (NAV-based) ----
post_lb_dt <- nav_dt[Date > LOCKBOX_END]
if (nrow(post_lb_dt) >= 5L) {
  post_lb_dt[, NAV_rebased := NAV / NAV[1L]]
  ret_post_lb <- post_lb_dt$NAV[-1L] / post_lb_dt$NAV[-nrow(post_lb_dt)] - 1
  daily_sr_proxy <- mean(ret_post_lb, na.rm = TRUE) / sd(ret_post_lb, na.rm = TRUE) * sqrt(252)
  total_post_lb_ret <- tail(post_lb_dt$NAV, 1L) / head(post_lb_dt$NAV, 1L) - 1
  cat(sprintf("[Step 4] Post-Lockbox NAV: %s ~ %s | total_ret=%.2f%% | daily SR proxy=%.3f\n",
              min(post_lb_dt$Date), max(post_lb_dt$Date),
              total_post_lb_ret * 100, daily_sr_proxy))
}

cat("\n=== Step 4 DONE ===\n")
