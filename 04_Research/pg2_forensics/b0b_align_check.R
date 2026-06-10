# b0b_align_check.R — Determine which calendar month Ret_1m covers (diagnostic)
# Method: cross-sectional mean of Ret_1m at score date t (selection-free market proxy)
# vs benchmark monthly returns at month(t)-1, month(t), month(t)+1.
suppressPackageStartupMessages({
  library(data.table); library(arrow)
})
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")

bm <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
cat("benchmark cols:", paste(names(bm), collapse=", "), " rows:", nrow(bm), "\n")
print(head(bm, 3)); print(tail(bm, 3))

sc <- as.data.table(read_parquet(file.path(PROD_DIR, "02_holdings_universe/alpha_scores_str1715_268m.parquet")))
sc[, Date := as.Date(Date)]

# market proxy: EW mean Ret_1m across all stocks per score date
mkt <- sc[!is.na(Ret_1m), .(mkt_ret = mean(Ret_1m), n = .N), by = Date][order(Date)]
mkt[, ym := format(Date, "%Y-%m")]

# benchmark monthly returns by calendar month
bm[, Date := as.Date(Date)]
setorder(bm, Date)
# detect close col
ccol <- intersect(c("BM_Close","Close","close","KOSPI_Close","Index"), names(bm))[1]
cat("using close col:", ccol, "\n")
bmm <- bm[, .(last_close = .SD[[ccol]][.N]), by = .(ym = format(Date, "%Y-%m"))]
setorder(bmm, ym)
bmm[, bm_ret := last_close / shift(last_close, n = 1L, type = "lag") - 1]

# month arithmetic helpers
ym_shift <- function(ym, k) {
  d <- as.Date(paste0(ym, "-01"))
  format(seq(d, by = paste(k, "month"), length.out = 2)[2], "%Y-%m")
}
mkt[, ym_m1 := sapply(ym, ym_shift, k = -1)]
mkt[, ym_p1 := sapply(ym, ym_shift, k = 1)]

for (h in c("ym_m1", "ym", "ym_p1")) {
  mm <- merge(mkt[, .(ym_match = get(h), mkt_ret)], bmm[, .(ym_match = ym, bm_ret)], by = "ym_match")
  cat(sprintf("corr(mean Ret_1m @t, BM ret of %s): %.4f (n=%d)\n",
              h, mm[, cor(mkt_ret, bm_ret, use = "complete.obs")], nrow(mm)))
}

# Also: correlate production ret_orig with BM by realized_ym (sanity that ret_orig is a return)
pr <- fread(file.path(PROD_DIR, "04_backtest_results/period_returns_layer5.csv"))
mm2 <- merge(pr[, .(ym_match = realized_ym, ret_orig)], bmm[, .(ym_match = ym, bm_ret)], by = "ym_match")
cat(sprintf("corr(ret_orig @realized_ym, BM ret same month): %.4f (n=%d)\n",
            mm2[, cor(ret_orig, bm_ret, use = "complete.obs")], nrow(mm2)))
cat("[b0b] DONE\n")
