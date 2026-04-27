# Factor engine proposal — Iter 25 V25 Explicit Anti-Correlation
# WT-D20260427_010

# Single mathematical inverse score (returns ONLY):
#   1. Rolling 24M Pearson β: β_i = cov(R_i, R_str_1701) / var(R_str_1701)
#   2. Cross-sectional Z-score per ym, then negate: V25 = -Z_cs(β)
#   3. Selection: V25 top-10% (= β bottom-10%, most negative β)

compute_v25_alpha <- function(sig_date, panel, str_1701_monthly, window_m = 24L) {
  # panel: data.table with Date, Ticker, stock_ret_m, ym
  # str_1701_monthly: data.table with ym, port_ret
  # PIT: compute β using STRICTLY PAST 24M panel.
  joint <- merge(panel, str_1701_monthly[, .(ym, str_ret = port_ret)], by = 'ym')
  joint[, ym_int := as.integer(format(as.Date(paste0(ym,'-01')), '%Y%m'))]
  sig_int <- as.integer(format(sig_date, '%Y%m'))
  beta_dt <- joint[ym_int < sig_int,
    .(beta_24m = cov(stock_ret_m, str_ret) / var(str_ret)), by = Ticker]
  beta_dt[, V25_alpha := -((beta_24m - mean(beta_24m, na.rm=TRUE)) /
                            sd(beta_24m, na.rm=TRUE))]
  beta_dt[, .(Ticker, V25_alpha)]
}

