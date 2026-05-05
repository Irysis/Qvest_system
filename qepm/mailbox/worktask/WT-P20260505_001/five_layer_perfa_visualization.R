## 5-layer 전기간 성과 PerformanceAnalytics 정합 비교 + 시각화
## Layers:
##   1. Baseline (no overlay = Original STR_1715 raw walk-forward)
##   2. MRS (simple 4-state cash 0/10/20/40)
##   3. M4 (BOCPD + decay + BL tri-pillar)
##   4. AR (Absorption Ratio threshold on Original, no M4)
##   5. AR on M4 (sequential admitted layer)

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_dir <- file.path(base_dir, "qepm/mailbox/worktask/WT-P20260505_001")
charts_dir <- file.path(wt_dir, "charts")
dir.create(charts_dir, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------
# 1. Load 5-layer return path (from previous four_layer_comparison)
# ------------------------------------------------------------
src_path <- file.path(base_dir,
  "qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv")
dt <- fread(src_path)
dt[, date := as.Date(date)]
setorder(dt, date)
cat("[loaded] n_rows=", nrow(dt), " range:",
    as.character(min(dt$date)), "to", as.character(max(dt$date)), "\n")
print(head(dt, 3))

# Standardize names
setnames(dt,
         old = c("ret_orig", "ret_MRS", "ret_M4",
                  "ret_AR_on_M4", "ret_AR_on_Orig"),
         new = c("Baseline", "MRS", "M4", "AR_on_M4", "AR_only"))

# 5-layer return matrix
xret <- xts(as.matrix(dt[, .(Baseline, MRS, M4, AR_only, AR_on_M4)]),
            order.by = dt$date)
colnames(xret) <- c("Baseline", "MRS", "M4", "AR_only", "AR_on_M4")

cat("[xret]\n")
cat("  n_periods:", nrow(xret), "\n")
cat("  range:", as.character(start(xret)), "to", as.character(end(xret)), "\n")

# ------------------------------------------------------------
# 2. PerformanceAnalytics standard metrics
# ------------------------------------------------------------
ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
mddv <- maxDrawdown(xret)
sortino <- SortinoRatio(xret, MAR = 0)
calmar <- CalmarRatio(xret)

cat("\n=== PerformanceAnalytics 5-layer metrics ===\n")
print(ann)
cat("MDD:\n"); print(mddv)
cat("Sortino:\n"); print(sortino)
cat("Calmar:\n"); print(calmar)

summary_dt <- data.table(
  Layer = c("1.Baseline_no_overlay", "2.MRS_simple_cash",
            "3.M4_BOCPD_decay_BL", "4.AR_only_no_M4",
            "5.AR_on_M4_admitted"),
  CAGR = round(as.numeric(ann[1, ]), 4),
  Vol = round(as.numeric(ann[2, ]), 4),
  Sharpe = round(as.numeric(ann[3, ]), 4),
  MDD = round(-as.numeric(mddv), 4),
  Sortino = round(as.numeric(sortino), 4),
  Calmar = round(as.numeric(calmar), 4)
)
cat("\n=== SUMMARY (PerfA) ===\n")
print(summary_dt)

# ------------------------------------------------------------
# 3. Charts (PNG, high-DPI)
# ------------------------------------------------------------
colors_5 <- c("Baseline" = "#666666",
              "MRS" = "#1f77b4",
              "M4" = "#2ca02c",
              "AR_only" = "#ff7f0e",
              "AR_on_M4" = "#d62728")

# Chart 1: Equity curves
png(file.path(charts_dir, "01_equity_curves_5layer.png"),
    width = 1600, height = 900, res = 150)
chart.CumReturns(xret,
                 main = "5-Layer Cumulative Equity Curves (256m, 2005-02 ~ 2026-05, PerfA)",
                 colorset = colors_5,
                 lwd = 2,
                 legend.loc = "topleft",
                 wealth.index = TRUE)
dev.off()
cat("[chart] 01_equity_curves_5layer.png saved\n")

# Chart 2: Drawdowns
png(file.path(charts_dir, "02_drawdowns_5layer.png"),
    width = 1600, height = 900, res = 150)
chart.Drawdown(xret,
               main = "5-Layer Drawdown Comparison (PerfA)",
               colorset = colors_5,
               lwd = 2,
               legend.loc = "bottomleft")
dev.off()
cat("[chart] 02_drawdowns_5layer.png saved\n")

# Chart 3: Annual returns bar
png(file.path(charts_dir, "03_annual_returns_5layer.png"),
    width = 1600, height = 900, res = 150)
ann_returns <- apply.yearly(xret, Return.cumulative)
barplot(t(coredata(ann_returns)) * 100,
        beside = TRUE,
        col = colors_5,
        names.arg = format(index(ann_returns), "%Y"),
        las = 2,
        main = "5-Layer Annual Returns (%) per year",
        ylab = "Return (%)",
        cex.names = 0.8,
        cex.axis = 0.9)
legend("topleft", legend = colnames(xret), fill = colors_5, bty = "n",
       cex = 0.85)
abline(h = 0, lty = 2)
dev.off()
cat("[chart] 03_annual_returns_5layer.png saved\n")

# Chart 4: Rolling 36m Sharpe
png(file.path(charts_dir, "04_rolling_sharpe_5layer.png"),
    width = 1600, height = 900, res = 150)
chart.RollingPerformance(xret,
                          width = 36,
                          FUN = "SharpeRatio.annualized",
                          scale = 12,
                          main = "5-Layer Rolling 36m Sharpe (PerfA)",
                          colorset = colors_5,
                          lwd = 2,
                          legend.loc = "bottomright")
dev.off()
cat("[chart] 04_rolling_sharpe_5layer.png saved\n")

# Chart 5: Risk-Return scatter
png(file.path(charts_dir, "05_risk_return_scatter_5layer.png"),
    width = 1200, height = 900, res = 150)
plot(summary_dt$Vol * 100, summary_dt$CAGR * 100,
     pch = 19, cex = 2.5,
     col = colors_5,
     xlab = "Annualized Vol (%)",
     ylab = "CAGR (%)",
     main = "5-Layer Risk-Return Profile",
     xlim = c(min(summary_dt$Vol) * 100 - 2, max(summary_dt$Vol) * 100 + 2),
     ylim = c(min(summary_dt$CAGR) * 100 - 5, max(summary_dt$CAGR) * 100 + 5))
text(summary_dt$Vol * 100, summary_dt$CAGR * 100 + 1.5,
     summary_dt$Layer, cex = 0.7, pos = 3)
abline(0, 1, lty = 2, col = "gray")
abline(0, 1.585, lty = 3, col = "gray60")
abline(0, 1.7670, lty = 3, col = "gray60")
abline(0, 1.7758, lty = 3, col = "gray60")
text(8, 32, "SR=1.0", cex = 0.6, col = "gray")
text(20, 42, "Best SR (M4: 1.7670)", cex = 0.7, col = "darkgreen")
dev.off()
cat("[chart] 05_risk_return_scatter_5layer.png saved\n")

# Chart 6: Stacked metrics comparison
png(file.path(charts_dir, "06_metrics_comparison_5layer.png"),
    width = 1600, height = 1000, res = 150)
par(mfrow = c(2, 3), mar = c(6, 4, 3, 1))
mat <- as.matrix(summary_dt[, .(CAGR, Vol, Sharpe, -MDD, Sortino, Calmar)])
rownames(mat) <- summary_dt$Layer
colnames(mat) <- c("CAGR", "Vol", "Sharpe", "MDD_abs", "Sortino", "Calmar")
for (i in seq_len(ncol(mat))) {
  barplot(mat[, i],
          col = colors_5,
          main = colnames(mat)[i],
          names.arg = c("Baseline", "MRS", "M4", "AR_only", "AR_on_M4"),
          las = 2, cex.names = 0.7)
}
dev.off()
cat("[chart] 06_metrics_comparison_5layer.png saved\n")

# ------------------------------------------------------------
# 4. Save summary CSV + JSON
# ------------------------------------------------------------
fwrite(summary_dt, file.path(wt_dir, "five_layer_perfa_summary.csv"))

result <- list(
  task_id = "WT-P20260505_001",
  comparison_kind = "5_layer_PerfA_strict_visualization",
  convention = "PerformanceAnalytics_geometric_Charter_v1_5_§13_Backtest_Contract_v1_0",
  n_months = nrow(dt),
  period = paste0(min(dt$date), " to ", max(dt$date)),
  layers = lapply(seq_len(5), function(i) {
    list(
      layer = summary_dt$Layer[i],
      CAGR = summary_dt$CAGR[i],
      Vol = summary_dt$Vol[i],
      Sharpe = summary_dt$Sharpe[i],
      MDD = summary_dt$MDD[i],
      Sortino = summary_dt$Sortino[i],
      Calmar = summary_dt$Calmar[i]
    )
  }),
  charts_emitted = list.files(charts_dir, pattern = "_5layer\\.png$"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)
write_json(result, file.path(wt_dir, "five_layer_perfa_visualization.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[saved]\n")
cat("  - five_layer_perfa_summary.csv\n")
cat("  - five_layer_perfa_visualization.json\n")
cat("  - charts/ ", length(list.files(charts_dir, pattern = "\\.png$")), "PNGs\n")
