## OOS Chart Mandate — WT-S20260626_001 A/B charts
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
STAGE <- file.path(ROOT, "stage_artifacts/WT_WT_S20260626_001")
OUT <- file.path(STAGE, "output"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

p <- fread(file.path(STAGE, "ab_panel_full.csv"))
p[, date := as.Date(date)]
setorder(p, date)
p[, nav_inc := cumprod(1 + ret_inc)]
p[, nav_mc  := cumprod(1 + ret_mc)]
p[, nav_bm  := cumprod(1 + bm_ret)]

# 1. Equity curve (full walk-forward) — both arms + BM
png(file.path(OUT, "equity_curve.png"), width = 1200, height = 700, res = 110)
plot(p$date, p$nav_inc, type = "l", log = "y", col = "#1f77b4", lwd = 2,
     xlab = "", ylab = "NAV (log)", main = "WT-S20260626_001 A/B: Incumbent(product) vs Max-cash(min) vs KOSPI200")
lines(p$date, p$nav_mc, col = "#d62728", lwd = 2)
lines(p$date, p$nav_bm, col = "grey50", lwd = 1, lty = 2)
# mark co-firing months
cf <- p[abs(rw_inc - rw_mc) > 1e-9]
points(cf$date, cf$nav_inc, pch = 16, col = "#ff7f0e", cex = 0.6)
legend("topleft", c("Incumbent (product)", "Max-cash (min)", "KOSPI200", "co-firing month"),
       col = c("#1f77b4", "#d62728", "grey50", "#ff7f0e"),
       lty = c(1,1,2,NA), pch = c(NA,NA,NA,16), lwd = c(2,2,1,NA), bty = "n")
dev.off()

# 2. Annual returns — both arms
p[, yr := format(date, "%Y")]
ann <- p[, .(inc = prod(1+ret_inc)-1, mc = prod(1+ret_mc)-1, bm = prod(1+bm_ret)-1), by = yr]
png(file.path(OUT, "annual_returns.png"), width = 1200, height = 600, res = 110)
m <- t(as.matrix(ann[, .(inc, mc)])) * 100
colnames(m) <- ann$yr
barplot(m, beside = TRUE, col = c("#1f77b4", "#d62728"),
        main = "Annual Returns: Incumbent vs Max-cash (%)", las = 2, cex.names = 0.7)
legend("topleft", c("Incumbent (product)", "Max-cash (min)"),
       fill = c("#1f77b4", "#d62728"), bty = "n")
abline(h = 0, col = "grey40")
dev.off()

# 3. OOS zoom — recent 5Y (2021-07..2026-06) where most co-firing divergence lives
zoom <- p[date >= as.Date("2021-07-01")]
zoom[, znav_inc := cumprod(1 + ret_inc)]
zoom[, znav_mc  := cumprod(1 + ret_mc)]
zoom[, znav_bm  := cumprod(1 + bm_ret)]
png(file.path(OUT, "oos_zoom_chart.png"), width = 1200, height = 700, res = 110)
plot(zoom$date, zoom$znav_inc, type = "l", col = "#1f77b4", lwd = 2,
     xlab = "", ylab = "NAV (rebased 2021-07=1)",
     main = "Recent 5Y zoom (2021-07..2026-06): co-firing divergence region",
     ylim = range(c(zoom$znav_inc, zoom$znav_mc, zoom$znav_bm)))
lines(zoom$date, zoom$znav_mc, col = "#d62728", lwd = 2)
lines(zoom$date, zoom$znav_bm, col = "grey50", lwd = 1, lty = 2)
zcf <- zoom[abs(rw_inc - rw_mc) > 1e-9]
points(zcf$date, zcf$znav_inc, pch = 16, col = "#ff7f0e", cex = 0.8)
legend("topleft", c("Incumbent (product)", "Max-cash (min)", "KOSPI200", "co-firing month"),
       col = c("#1f77b4", "#d62728", "grey50", "#ff7f0e"),
       lty = c(1,1,2,NA), pch = c(NA,NA,NA,16), lwd = c(2,2,1,NA), bty = "n")
dev.off()

# 4. Regime decomposition — SR per regime per arm
reg_sr <- function(rcol) {
  p[, .(SR = if (.N >= 2 && sd(get(rcol)) > 0) mean(get(rcol))/sd(get(rcol))*sqrt(12) else NA_real_), by = regime]
}
sr_inc <- reg_sr("ret_inc"); setnames(sr_inc, "SR", "inc")
sr_mc  <- reg_sr("ret_mc");  setnames(sr_mc, "SR", "mc")
reg <- merge(sr_inc, sr_mc, by = "regime")
ord <- c("BULL","NORMAL","CAUTION","CRISIS")
reg <- reg[match(ord, regime, nomatch = 0)]
png(file.path(OUT, "regime_decomposition.png"), width = 1000, height = 600, res = 110)
mm <- t(as.matrix(reg[, .(inc, mc)]))
colnames(mm) <- reg$regime
barplot(mm, beside = TRUE, col = c("#1f77b4", "#d62728"),
        main = "Annualized SR by Regime: Incumbent vs Max-cash", ylab = "SR (ann)")
legend("topright", c("Incumbent (product)", "Max-cash (min)"),
       fill = c("#1f77b4", "#d62728"), bty = "n")
abline(h = 0, col = "grey40")
dev.off()

cat("Charts written to", OUT, "\n")
cat("Files:", paste(list.files(OUT, "\\.png$"), collapse = ", "), "\n")
print(reg)
