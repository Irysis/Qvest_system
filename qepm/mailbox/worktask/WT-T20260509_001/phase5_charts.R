## ============================================================================
## WT-T20260509_001 — Phase 5: Charts (OOS + Equity + Annual Returns)
##
## Mandate (Forge agent prompt v6.1+):
##   - output/equity_curve.png (전기간 walk-forward + Lockbox marker)
##   - output/annual_returns.png
##   - output/oos_zoom_chart.png (Lockbox period 2024-01 ~ 2026-04)
##   - output/regime_decomposition.png (regime별 SR/CAGR plot — 4-layer)
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260509_001 Phase 5 — Charts\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260509_001")
OUT_DIR <- file.path(WT_DIR, "output")
setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(scales)
})

# Load 4-layer + 5family data
fl <- fread(file.path(OUT_DIR, "four_layer_returns_path_updated.csv"))
fl[, date := as.Date(date)]

# Load 5 family period_returns
fam_dirs <- list.dirs(file.path(OUT_DIR, "5family_updated"), recursive = FALSE)
fam_data <- list()
for (d in fam_dirs) {
  sname <- basename(d)
  pr <- fread(file.path(d, "period_returns.csv"))
  pr[, date := as.Date(date)]
  pr[, family := sname]
  pr[, NAV := cumprod(1 + ret_net)]
  fam_data[[sname]] <- pr[, .(date, family, ret_net, NAV)]
}
fam_dt <- rbindlist(fam_data, fill = TRUE)

LB_START <- as.Date("2024-01-01")
LB_END   <- as.Date("2026-05-01")

# ─── Chart 1: equity_curve.png (5 family + Lockbox marker) ────────────────────
cat("[CHART 1] equity_curve.png (5 family NAV)\n")
p1 <- ggplot(fam_dt, aes(x = date, y = NAV, color = family)) +
  geom_line(linewidth = 0.6) +
  geom_vline(xintercept = LB_START, linetype = "dashed", color = "red", alpha = 0.7) +
  annotate("text", x = LB_START, y = max(fam_dt$NAV) * 0.95,
            label = "  Lockbox release\n  (alpha 갱신)",
            color = "red", hjust = 0, size = 3) +
  scale_y_continuous(labels = comma_format(accuracy = 0.1)) +
  labs(title = "WT-T20260509_001: 5-Family Equity Curve (alpha 268m updated)",
        subtitle = sprintf("Period: %s ~ %s | 15bps cost | Pure Function R12",
                            min(fam_dt$date), max(fam_dt$date)),
        x = "Date", y = "NAV (cumulative growth)", color = "Family") +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width = 12, height = 6, dpi = 110)

# ─── Chart 2: annual_returns.png ─────────────────────────────────────────────
cat("[CHART 2] annual_returns.png\n")
fam_dt[, year := format(date, "%Y")]
ann_ret <- fam_dt[, .(annual_ret = prod(1 + ret_net) - 1), by = .(year, family)]
ann_ret[, year := as.integer(year)]
p2 <- ggplot(ann_ret, aes(x = year, y = annual_ret, fill = family)) +
  geom_bar(stat = "identity", position = "dodge") +
  geom_hline(yintercept = 0, color = "black", linetype = "dotted") +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  labs(title = "WT-T20260509_001: 5-Family Annual Returns",
        subtitle = "Net of 15bps cost, monthly compound",
        x = "Year", y = "Annual Return", fill = "Family") +
  theme_minimal() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(OUT_DIR, "annual_returns.png"), p2, width = 12, height = 6, dpi = 110)

# ─── Chart 3: oos_zoom_chart.png (2024-01 ~ 2026-04) ──────────────────────────
cat("[CHART 3] oos_zoom_chart.png (lockbox period zoom)\n")
oos_dt <- fam_dt[date >= LB_START & date < LB_END]
oos_dt[, NAV_oos_rebased := NAV / NAV[1], by = family]
p3 <- ggplot(oos_dt, aes(x = date, y = NAV_oos_rebased, color = family)) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = 1, linetype = "dotted") +
  scale_y_continuous(labels = comma_format(accuracy = 0.01)) +
  labs(title = "WT-T20260509_001: 5-Family OOS Zoom (2024-01 ~ 2026-04, 28m)",
        subtitle = "Lockbox release effect — alpha 갱신 후 실측 OOS path. NAV rebased to 1.0 at 2024-01-01.",
        x = "Date", y = "NAV (rebased)", color = "Family") +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(file.path(OUT_DIR, "oos_zoom_chart.png"), p3, width = 12, height = 6, dpi = 110)

# ─── Chart 4: 4-Layer regime decomposition (Original/MRS/M4/AR) ───────────────
cat("[CHART 4] regime_decomposition.png (4-layer NAV)\n")
fl_long <- melt(fl[, .(date, ret_orig, ret_MRS, ret_M4, ret_AR_on_M4, ret_AR_on_Orig)],
                id.vars = "date", variable.name = "layer", value.name = "ret_net")
fl_long[, NAV := cumprod(1 + ret_net), by = layer]
fl_long[, layer_label := fcase(
  layer == "ret_orig",       "1_Original_no_overlay",
  layer == "ret_MRS",        "2_MRS_simple_cash",
  layer == "ret_M4",         "3_M4_BOCPD_BL",
  layer == "ret_AR_on_M4",   "4_AR_on_M4_threshold (admit)",
  layer == "ret_AR_on_Orig", "5_AR_on_Original"
)]
p4 <- ggplot(fl_long, aes(x = date, y = NAV, color = layer_label)) +
  geom_line(linewidth = 0.6) +
  geom_vline(xintercept = LB_START, linetype = "dashed", color = "red", alpha = 0.7) +
  scale_y_continuous(labels = comma_format(accuracy = 0.1)) +
  labs(title = "WT-T20260509_001: 4-Layer Decomposition (alpha 268m updated)",
        subtitle = "Original / MRS / M4 / AR-on-M4 / AR-on-Original | dashed red = lockbox release",
        x = "Date", y = "NAV (cumulative)", color = "Layer") +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(file.path(OUT_DIR, "regime_decomposition.png"), p4, width = 12, height = 6, dpi = 110)

cat("\n[CHARTS] All 4 charts saved to output/\n")
print(list.files(OUT_DIR, pattern = "\\.png$"))
cat("\n========================================================\n")
cat("  Phase 5 — Charts DONE\n")
cat("========================================================\n")
