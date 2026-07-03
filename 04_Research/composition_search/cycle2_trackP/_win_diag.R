# _win_diag.R - locate the audit 255m window/convention (diagnostic only)
suppressPackageStartupMessages({library(data.table); library(xts); library(PerformanceAnalytics)})
bk <- fread("data/period_returns_layer5_copy.csv"); setorder(bk, anchor_date)
n <- nrow(bk); cat("rows:", n, "\n")
rows <- list()
for (i in 1:(n - 254)) {
  w <- bk[i:(i + 254)]
  x4 <- xts(w$ret_L4_baseline, as.Date(paste0(w$realized_ym, "-01")))
  xv <- xts(w$ret_L5_V2,       as.Date(paste0(w$realized_ym, "-01")))
  rows[[i]] <- data.table(
    start = w$realized_ym[1], end = w$realized_ym[255],
    L4_mean12   = mean(w$ret_L4_baseline) * 12,
    L4_geo      = as.numeric(Return.annualized(x4, scale = 12)),
    L4_vol      = sd(w$ret_L4_baseline) * sqrt(12),
    L4_sr_arith = mean(w$ret_L4_baseline) / sd(w$ret_L4_baseline) * sqrt(12),
    L4_sr_geo   = as.numeric(Return.annualized(x4, scale = 12)) /
                  as.numeric(StdDev.annualized(x4, scale = 12)),
    V2_geo      = as.numeric(Return.annualized(xv, scale = 12)),
    V2_sr_geo   = as.numeric(Return.annualized(xv, scale = 12)) /
                  as.numeric(StdDev.annualized(xv, scale = 12)),
    L4_mdd      = as.numeric(maxDrawdown(x4)))
}
res <- rbindlist(rows)
print(res, digits = 4)
cat("\ntargets: L4 CAGR .3868 Vol .2212 SR 1.7486 MDD .2481 | V2 CAGR .4150 SR 1.9536\n")
