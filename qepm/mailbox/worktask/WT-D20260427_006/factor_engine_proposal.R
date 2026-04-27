# Factor engine proposal — Iter 22 V22 Drawdown-Conditioned Defensive
# WT-D20260427_006

compute_v22_alpha <- function(sig_date, panel) {
  # V22 components: M11_ST_Reversal, Q33_Earnings_Persistence, Q25_Ohlson_O, Q07_Earnings_Stability, D25_Left_Tail_Beta, Q32_Interest_Coverage, Q14_Current_Ratio
  z_cols <- c("M11_ST_Reversal", "Q33_Earnings_Persistence", "Q25_Ohlson_O", "Q07_Earnings_Stability", "D25_Left_Tail_Beta", "Q32_Interest_Coverage", "Q14_Current_Ratio")
  panel[, V22_alpha := rowMeans(.SD, na.rm = TRUE), .SDcols = z_cols]
  panel[, V22_alpha]
}

