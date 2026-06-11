# Lens 2 adversarial audit — blend cost/turnover recomputation (read-only inputs)
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
})
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/value_sleeve_combination")
M <- readRDS(file.path(OUTDIR, "aligned_series.rds"))
setorder(M, realized_ym)
dates <- as.Date(paste0(M$realized_ym, "-01"))
ret_mat <- xts(cbind(book = M$book_ret, value = M$value_ret), order.by = dates)
cat(sprintf("months=%d range %s..%s\n", nrow(M), M$realized_ym[1], M$realized_ym[nrow(M)]))

# book-only SR reproduction
sr_book <- as.numeric(SharpeRatio.annualized(ret_mat[, "book"], Rf = 0))
cat(sprintf("book-only SR recomputed = %.4f (claimed 1.9175)\n", sr_book))

W_GRID <- c(0.05, 0.10, 0.15, 0.20, 0.30)
rows <- list()
for (wv in W_GRID) {
  wts <- c(book = 1 - wv, value = wv)
  rp <- Return.portfolio(ret_mat, weights = wts, rebalance_on = "months", verbose = TRUE)
  gross <- rp$returns
  bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
  n <- nrow(bop)
  to <- rep(0, n)
  for (i in 2:n) to[i] <- sum(abs(as.numeric(bop[i, ]) - as.numeric(eop[i - 1, ])))
  bop_dev <- max(abs(sweep(as.matrix(bop), 2, wts, "-")))  # 0 => true monthly reset to target
  cost_x <- xts(to * 15 / 1e4, order.by = index(gross))
  net <- gross - cost_x
  sr_net   <- as.numeric(SharpeRatio.annualized(net, Rf = 0))
  sr_gross <- as.numeric(SharpeRatio.annualized(gross, Rf = 0))
  # analytic 2-asset drift turnover: sum|target - drifted| = 2*w*(1-w)*|rb-rv|/(1+rp)
  rb <- as.numeric(ret_mat$book); rv <- as.numeric(ret_mat$value)
  rp_t <- (1 - wv) * rb + wv * rv
  analytic_to <- mean(2 * wv * (1 - wv) * abs(rb - rv) / (1 + rp_t))
  rows[[as.character(wv)]] <- data.table(
    w_value = wv,
    blend_TO_yr = mean(to) * 12,
    analytic_TO_yr = analytic_to * 12,
    to_month1 = to[1],
    bop_max_dev = bop_dev,
    cost_drag_pct_yr = mean(to) * 12 * 15 / 1e2,  # in % per year
    SR_gross = sr_gross, SR_net = sr_net, dSR_from_cost = sr_net - sr_gross
  )
}
out <- rbindlist(rows)
print(out, digits = 5)

# ---- asymmetry arithmetic (b0 framework) ----
flat_yr <- 12 * 15 / 1e4                  # v2.3 flat: 15bps buy-leg full notional / month
val_sumabs_to <- 16.3904                  # sum|dw| basis (two legs), from blend_result.json
val_delta_yr <- val_sumabs_to * 15 / 1e4  # actual delta charge in sleeve series
book_oneway <- 5.57                       # b0/MEMORY one-way TO of book
book_true_yr <- 2 * book_oneway * 15 / 1e4
cat(sprintf("\nflat v2.3 cost = %.3f%%/yr (TO-insensitive)\n", flat_yr * 100))
cat(sprintf("value delta charge = %.3f%%/yr vs flat %.3f%%/yr -> delta heavier by %.3f pp/yr\n",
            val_delta_yr * 100, flat_yr * 100, (val_delta_yr - flat_yr) * 100))
cat(sprintf("book delta-true = %.3f%%/yr vs flat %.3f%%/yr -> book OVER-charged %.3f pp/yr by flat\n",
            book_true_yr * 100, flat_yr * 100, (flat_yr - book_true_yr) * 100))
w <- 0.20
cat(sprintf("at w=0.20 effect on dCAGR(blend-book):\n"))
cat(sprintf("  book flat over-charge   : %+.4f pp/yr (ANTI-conservative for delta claim)\n",
            +w * (flat_yr - book_true_yr) * 100))
cat(sprintf("  value delta vs flat     : %+.4f pp/yr (conservative)\n",
            -w * (val_delta_yr - flat_yr) * 100))
to20 <- out[w_value == 0.20, blend_TO_yr]
cat(sprintf("  blend-level rebal charge: %+.4f pp/yr (conservative, blend only)\n",
            -to20 * 15 / 1e2))
net_bias <- w * (flat_yr - book_true_yr) - w * (val_delta_yr - flat_yr) - to20 * 15 / 1e4
cat(sprintf("  NET bias on dCAGR       : %+.4f pp/yr (negative = conservative)\n", net_bias * 100))
