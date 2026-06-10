# b0c_retorig_check.R — Why is corr(ret_orig, BM) ~ 0? (diagnostic)
suppressPackageStartupMessages({
  library(data.table); library(arrow)
})
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")

pr <- fread(file.path(PROD_DIR, "04_backtest_results/period_returns_layer5.csv"))
cat("ret_orig summary:\n"); print(summary(pr$ret_orig))
cat("ret_orig sd:", sd(pr$ret_orig), " ann vol:", sd(pr$ret_orig)*sqrt(12), "\n")

bm <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
setorder(bm, Date)
bmm <- bm[, .(last_close = BM_Close[.N]), by = .(ym = format(Date, "%Y-%m"))]
setorder(bmm, ym)
bmm[, bm_ret := last_close / shift(last_close, 1, type = "lag") - 1]
cat("\nBM monthly ret summary (2004+):\n"); print(summary(bmm[ym >= "2004-01", bm_ret]))
cat("BM monthly tail:\n"); print(tail(bmm, 4))

ym_shift <- function(ym, k) {
  d <- as.Date(paste0(ym, "-01"))
  format(seq(d, by = paste(k, "month"), length.out = 2)[2], "%Y-%m")
}
pr[, ym_m1 := sapply(realized_ym, ym_shift, k = -1)]
pr[, ym_p1 := sapply(realized_ym, ym_shift, k = 1)]
for (h in c("ym_m1", "realized_ym", "ym_p1")) {
  mm <- merge(pr[, .(ym = get(h), ret_orig)], bmm[, .(ym, bm_ret)], by = "ym")
  cat(sprintf("ret_orig vs BM @%s: pearson=%.4f spearman=%.4f (n=%d)\n", h,
              mm[, cor(ret_orig, bm_ret, use="complete.obs")],
              mm[, cor(ret_orig, bm_ret, method="spearman", use="complete.obs")], nrow(mm)))
}

# scatter check for outliers: top |bm_ret| months
mm <- merge(pr[, .(ym = realized_ym, ret_orig)], bmm[, .(ym, bm_ret)], by = "ym")
setorder(mm, -bm_ret)
cat("\nTop 5 BM up months:\n"); print(head(mm, 5))
setorder(mm, bm_ret)
cat("Top 5 BM down months:\n"); print(head(mm, 5))

# upstream source check
up_path <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
cat("\nupstream exists:", file.exists(up_path), "\n")
if (file.exists(up_path)) {
  up <- fread(up_path)
  cat("upstream cols:", paste(names(up), collapse=", "), " rows:", nrow(up), "\n")
  print(head(up, 3))
  up[, ym := format(as.Date(date), "%Y-%m")]
  mm2 <- merge(up[, .(ym, ret_net)], bmm[, .(ym, bm_ret)], by = "ym")
  cat(sprintf("upstream ret_net vs BM same month: pearson=%.4f spearman=%.4f (n=%d)\n",
              mm2[, cor(ret_net, bm_ret, use="complete.obs")],
              mm2[, cor(ret_net, bm_ret, method="spearman", use="complete.obs")], nrow(mm2)))
  # identity check vs layer5 ret_orig
  mm3 <- merge(up[, .(ym, ret_net)], pr[, .(ym = realized_ym, ret_orig)], by = "ym")
  cat("upstream ret_net == layer5 ret_orig? max abs diff:",
      mm3[, max(abs(ret_net - ret_orig), na.rm=TRUE)], " n=", nrow(mm3), "\n")
}
cat("[b0c] DONE\n")
