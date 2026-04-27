# Factor engine proposal — Iter 24 V24 Coskew-only Pure Defense
# WT-D20260427_009

# alpha_v24 = z_coskew (sign-flipped cross-sec Z of trailing 24M coskew)
# coskew_i = E[(R_i - mu_i)(R_str1701 - mu_str)^2] / (sigma_i * sigma_str^2)
# Pure 3rd-order return moment. NO financial factors.

compute_v24_alpha <- function(sig_date, panel) {
  # panel: data.table with Date, Ticker, z_coskew (from Iter 23-style 24M trailing)
  # Returns alpha_v24 = z_coskew aligned at sig_date.
  panel[, alpha_v24 := z_coskew]
  panel[, alpha_v24]
}

