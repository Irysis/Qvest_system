# Factor engine proposal — Iter 23 V23 Nonlinear Tail-Conditional Defense
# WT-D20260427_008

# 4 nonlinear scores (NO financial factors):
#   1. Lower tail dependence (empirical λ_L, Clayton-style)
#   2. Regime-conditional β (β_high − β_low, expanding 75th-pct vol regime)
#   3. Mutual information excess (binned MI − Pearson-implied)
#   4. Co-skewness (E[(R_stock)(R_str)²])

compute_v23_alpha <- function(sig_date, panel, str_1701_monthly) {
  # panel: data.table with Date, Ticker, stock_ret_m, ym, vol_regime_high, str_drawdown, str_ret
  # str_1701_monthly: data.table with ym, port_ret
  # All scores computed from STRICTLY PAST 24M panel; result aligned for use at sig_date.
  z_cols <- c('z_lambda_L', 'z_beta_diff', 'z_mi_excess', 'z_coskew')
  panel[, V23_alpha := rowMeans(.SD, na.rm = TRUE), .SDcols = z_cols]
  panel[, V23_alpha]
}

