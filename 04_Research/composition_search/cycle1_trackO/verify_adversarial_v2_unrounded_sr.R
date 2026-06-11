# Adversarial check V8: unrounded IS Sharpe ordering via SharpeRatio.annualized
# (table.AnnualizedReturns rounds to 4dp internally; confirm argmax robust)
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
l5 <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)
g_inc <- l5$beta_threshold_lag * l5$m4_weight_lag
b_inc <- g_inc * l5$beta_R05_V2
deep  <- b_inc < 0.25
RHO <- 0.4951
bAR <- l5$beta_threshold_lag; m4 <- l5$m4_weight_lag
gl <- list(O1_MIN_DEDUP      = pmin(bAR, m4),
           O2_M4_PRIORITY_OR = ifelse(m4 < 1 - 1e-12, m4, bAR),
           O3_MIDBAND_FLOOR  = ifelse(g_inc < 0.25, g_inc, pmax(g_inc, 0.5)),
           O4_POWER_RHO      = (bAR * m4)^(1/(1+RHO)),
           O5_BLEND_RHO      = (1-RHO)*(bAR*m4) + RHO*pmin(bAR, m4))
gl <- lapply(gl, function(g) { g[deep] <- g_inc[deep]; g })
w <- l5$realized_ym >= "2005-01" & l5$realized_ym <= "2018-12"
sr <- c()
for (nm in names(gl)) {
  g <- gl[[nm]]; dg <- abs(diff(c(1, g)))
  r <- l5$beta_R05_V2 * g * l5$ret_orig - 0.0015*dg - 0.0015*l5$db_R05_V2
  x <- xts(r[w], order.by = l5$anchor_date[w])
  sr[nm] <- as.numeric(SharpeRatio.annualized(x, Rf = 0, scale = 12))
  cat(sprintf("%s IS SR unrounded = %.10f\n", nm, sr[nm]))
}
cat(sprintf("[V8] unrounded IS argmax = %s\n", names(sr)[which.max(sr)]))
