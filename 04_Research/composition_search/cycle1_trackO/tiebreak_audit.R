# Tie-break audit: unrounded IS MDD/SR for tie set {O3, O4} (|dSR|<0.005)
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
l5 <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)
l5[, g_inc := beta_threshold_lag * m4_weight_lag]
l5[, b_inc := g_inc * beta_R05_V2]
deep <- l5$b_inc < 0.25
RHO <- 0.4951
g3 <- ifelse(l5$g_inc < 0.25, l5$g_inc, pmax(l5$g_inc, 0.5)); g3[deep] <- l5$g_inc[deep]
g4 <- (l5$beta_threshold_lag * l5$m4_weight_lag)^(1 / (1 + RHO)); g4[deep] <- l5$g_inc[deep]
mk <- function(g) {
  dg <- abs(diff(c(1, g)))
  l5$beta_R05_V2 * g * l5$ret_orig - 0.0015 * dg - 0.0015 * l5$db_R05_V2
}
w <- l5$realized_ym >= "2005-01" & l5$realized_ym <= "2018-12"
gl <- list(O3_MIDBAND_FLOOR = g3, O4_POWER_RHO = g4)
for (nm in names(gl)) {
  r <- mk(gl[[nm]])[w]
  x <- xts(r, order.by = l5$anchor_date[w])
  cat(sprintf("%s IS MDD unrounded = %.12f | IS SR unrounded = %.8f\n", nm,
              -abs(as.numeric(maxDrawdown(x))),
              as.numeric(table.AnnualizedReturns(x, scale = 12, Rf = 0)[3, 1])))
}
