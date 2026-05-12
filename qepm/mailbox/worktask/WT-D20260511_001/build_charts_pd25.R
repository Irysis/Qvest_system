#==============================================================================
# WT-D20260511_001 PD25 — Build mandatory OOS charts
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(scales)
})

OUT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001/backtest_result_pd25"
CHARTS_DIR <- file.path(OUT_DIR, "charts")
dir.create(CHARTS_DIR, recursive = TRUE, showWarnings = FALSE)

nav <- fread(file.path(OUT_DIR, "nav.csv"))
nav[, Date := as.Date(Date)]
setorder(nav, Date)

# 1. Equity curve (full 255m) — all 4 paths
nav_long <- melt(nav[, .(Date, nav_A, nav_B, nav_C, nav_S4)],
                 id.vars = "Date", variable.name = "Path", value.name = "NAV")
nav_long[, Path := factor(Path,
  levels = c("nav_A", "nav_B", "nav_C", "nav_S4"),
  labels = c("Path A — EW (2.75%)", "Path B — Z-linear", "Path C — Z-softmax", "S4 v2 baseline"))]

p1 <- ggplot(nav_long, aes(x = Date, y = NAV, color = Path)) +
  geom_line(linewidth = 0.8) +
  scale_y_log10(labels = scales::number_format(accuracy = 0.1)) +
  geom_vline(xintercept = as.Date("2011-01-01"), linetype = "dashed", color = "gray50") +
  annotate("text", x = as.Date("2011-01-01") + 200, y = max(nav_long$NAV, na.rm = TRUE) * 0.7,
           label = "Active composite\nstart (z_NEW)", color = "gray40", size = 3) +
  labs(title = "PD25 — 3 Weighting Paths vs S4 v2 Baseline (NAV, log scale)",
       subtitle = "Iter5 Ret_1m methodology — 255m full window (2005-02 to 2026-04), 15bps cost embedded",
       x = "Date", y = "NAV (log scale, base=1.0)") +
  theme_minimal() +
  theme(legend.position = "bottom", plot.title = element_text(size = 12),
        plot.subtitle = element_text(size = 9, color = "gray40"))
ggsave(file.path(CHARTS_DIR, "equity_curve.png"), p1, width = 11, height = 6, dpi = 100)
cat("Saved equity_curve.png\n")

# 2. Annual returns barplot
pr <- fread(file.path(OUT_DIR, "period_returns.csv"))
pr[, Date := as.Date(Date)]
pr[, year := as.integer(format(Date, "%Y"))]
ann <- pr[, .(
  A = prod(1 + ifelse(is.na(ret_path_A_net), 0, ret_path_A_net)) - 1,
  B = prod(1 + ifelse(is.na(ret_path_B_net), 0, ret_path_B_net)) - 1,
  C = prod(1 + ifelse(is.na(ret_path_C_net), 0, ret_path_C_net)) - 1,
  S4 = prod(1 + ifelse(is.na(ret_S4_v2_net), 0, ret_S4_v2_net)) - 1
), by = year]
ann_long <- melt(ann, id.vars = "year", variable.name = "Path", value.name = "AnnRet")
ann_long[, Path := factor(Path,
  levels = c("A", "B", "C", "S4"),
  labels = c("Path A — EW", "Path B — Z-linear", "Path C — Z-softmax", "S4 v2 baseline"))]

p2 <- ggplot(ann_long, aes(x = factor(year), y = AnnRet, fill = Path)) +
  geom_bar(stat = "identity", position = "dodge", alpha = 0.85) +
  geom_hline(yintercept = 0, color = "gray40") +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  labs(title = "PD25 — Annual Returns by Path",
       subtitle = "Iter5 Ret_1m methodology — 15bps cost embedded",
       x = "Year", y = "Annual Return") +
  theme_minimal() +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1),
        plot.title = element_text(size = 12), plot.subtitle = element_text(size = 9))
ggsave(file.path(CHARTS_DIR, "annual_returns.png"), p2, width = 12, height = 6, dpi = 100)
cat("Saved annual_returns.png\n")

# 3. OOS zoom chart (active composite period 2011-01 ~ 2026-04, 184m)
nav_active <- nav_long[Date >= "2011-01-01"]
# Rebase NAV to 1.0 at start
nav_active[, NAV_rebased := NAV / NAV[1], by = Path]

p3 <- ggplot(nav_active, aes(x = Date, y = NAV_rebased, color = Path)) +
  geom_line(linewidth = 0.9) +
  scale_y_log10(labels = scales::number_format(accuracy = 0.1)) +
  geom_vline(xintercept = as.Date("2023-12-31"), linetype = "dashed", color = "gray50") +
  annotate("text", x = as.Date("2024-03-01"), y = max(nav_active$NAV_rebased, na.rm = TRUE) * 0.85,
           label = "Lockbox\nboundary", color = "gray40", size = 3) +
  labs(title = "PD25 — OOS Zoom (Active Composite 184m: 2011-01 to 2026-04)",
       subtitle = "Rebased NAV; Iter5 Ret_1m methodology",
       x = "Date", y = "NAV (rebased, log scale)") +
  theme_minimal() +
  theme(legend.position = "bottom", plot.title = element_text(size = 12),
        plot.subtitle = element_text(size = 9, color = "gray40"))
ggsave(file.path(CHARTS_DIR, "oos_zoom_chart.png"), p3, width = 11, height = 6, dpi = 100)
cat("Saved oos_zoom_chart.png\n")

# 4. Regime decomposition (Yearly NAV by path, 2005-2026)
# Simple regime grouping by year-quarter or by year
ann_summary <- ann[, .(
  Path_A = round(A * 100, 2), Path_B = round(B * 100, 2),
  Path_C = round(C * 100, 2), S4_v2 = round(S4 * 100, 2)
), by = year]

# Cumulative drawdown plot per path
pr[, cum_A := cumprod(1 + ifelse(is.na(ret_path_A_net), 0, ret_path_A_net))]
pr[, cum_B := cumprod(1 + ifelse(is.na(ret_path_B_net), 0, ret_path_B_net))]
pr[, cum_C := cumprod(1 + ifelse(is.na(ret_path_C_net), 0, ret_path_C_net))]
pr[, cum_S4 := cumprod(1 + ifelse(is.na(ret_S4_v2_net), 0, ret_S4_v2_net))]
pr[, dd_A := cum_A / cummax(cum_A) - 1]
pr[, dd_B := cum_B / cummax(cum_B) - 1]
pr[, dd_C := cum_C / cummax(cum_C) - 1]
pr[, dd_S4 := cum_S4 / cummax(cum_S4) - 1]

dd_long <- melt(pr[, .(Date, dd_A, dd_B, dd_C, dd_S4)],
                id.vars = "Date", variable.name = "Path", value.name = "Drawdown")
dd_long[, Path := factor(Path,
  levels = c("dd_A", "dd_B", "dd_C", "dd_S4"),
  labels = c("Path A — EW", "Path B — Z-linear", "Path C — Z-softmax", "S4 v2 baseline"))]

p4 <- ggplot(dd_long, aes(x = Date, y = Drawdown, fill = Path, color = Path)) +
  geom_area(alpha = 0.3, position = "identity") +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  labs(title = "PD25 — Drawdown Profile by Path (Regime Decomposition Proxy)",
       subtitle = "Underwater curves; Iter5 Ret_1m methodology",
       x = "Date", y = "Drawdown") +
  theme_minimal() +
  theme(legend.position = "bottom", plot.title = element_text(size = 12),
        plot.subtitle = element_text(size = 9, color = "gray40"))
ggsave(file.path(CHARTS_DIR, "regime_decomposition.png"), p4, width = 11, height = 6, dpi = 100)
cat("Saved regime_decomposition.png\n")

cat("\nAll 4 mandatory charts saved.\n")
