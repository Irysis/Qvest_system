# _vfy_l5_label.R - decisive label-direction check on production L5 panel (READ-ONLY)
suppressWarnings(suppressMessages({ library(data.table) }))
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
l5 <- fread("C:/Users/99922/OneDrive/Quant_Module_Moltbot/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
bm <- fread(file.path(PROJ, "04_Research/composition_search/cycle1b_trackV/inputs/bm_monthly.csv"))
bm[, ym := format(as.Date(Date), "%Y-%m")]

# Oct-2008 crash (KOSPI200 -23.1%): which l5 label holds it?
cat("l5 rows around Oct-2008 (BM crash month):\n")
print(l5[realized_ym >= "2008-08" & realized_ym <= "2009-01",
         .(anchor_date, realized_ym, ret_orig, ret_L5_V2)])
cat("\nBM same months:\n")
print(bm[ym >= "2008-08" & ym <= "2009-01", .(ym, BM_Ret_m)])

# full-grid label test: cor(ret_orig @ label M, BM @ M) vs BM @ (M-1)
l5[, ym_lab := realized_ym]
l5[, ym_prev := format(as.Date(paste0(realized_ym, "-01")) - 1L, "%Y-%m")]
a <- merge(l5[, .(ym = ym_lab, ret_orig)], bm[, .(ym, BM_Ret_m)], by = "ym")
b <- merge(l5[, .(ym = ym_prev, ret_orig)], bm[, .(ym, BM_Ret_m)], by = "ym")
cat(sprintf("\ncor(ret_orig@label M, BM@M)   = %.4f (n=%d)\n", cor(a$ret_orig, a$BM_Ret_m), nrow(a)))
cat(sprintf("cor(ret_orig@label M, BM@M-1) = %.4f (n=%d)\n", cor(b$ret_orig, b$BM_Ret_m), nrow(b)))
