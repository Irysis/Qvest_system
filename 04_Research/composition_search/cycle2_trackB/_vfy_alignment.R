# _vfy_alignment.R - adversarial verification of STEP-1 cor result (diagnostic)
# cor(spec, book)=0.016 contradicts documented b1-vs-ret_orig cor 0.81 -> verify
# lag structure + BM co-movement before trusting STAGE_B_PASS. ASCII only.
suppressWarnings(suppressMessages({ library(data.table) }))
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TB <- file.path(PROJ, "04_Research/composition_search/cycle2_trackB")
x <- readRDS(file.path(TB, "stageb_series.rds"))
j <- x$aligned_sb1
setorder(j, Date)
cat(sprintf("n=%d  span %s..%s\n", nrow(j), j[1, ym], j[.N, ym]))

# 1) BM co-movement (both long-only KR equity -> each should be ~0.8 vs BM)
cat(sprintf("cor(spec_net, BM)   = %.4f\n", cor(j$spec_net, j$BM_Ret_m)))
cat(sprintf("cor(book_net, BM)   = %.4f\n", cor(j$book_net, j$BM_Ret_m)))
cat(sprintf("cor(ret_orig, BM)   = %.4f\n", cor(j$ret_orig, j$BM_Ret_m)))
cat(sprintf("cor(book_net, ret_orig) = %.4f (same file, overlay-of-base, expect high)\n",
            cor(j$book_net, j$ret_orig)))

# 2) lag scan: cor(spec_net_t, ret_orig_{t+k}) for k in -3..3
for (k in -3:3) {
  a <- j$spec_net
  b <- data.table::shift(j$ret_orig, n = k)
  ok <- complete.cases(a, b)
  cat(sprintf("k=%+d  cor(spec, ret_orig shifted %+d) = %.4f   cor(spec, book shifted %+d) = %.4f\n",
              k, k, cor(a[ok], b[ok]), k,
              cor(j$spec_net[ok], data.table::shift(j$book_net, n = k)[ok])))
}

# 3) spot months: largest |BM| months - do spec and ret_orig co-move same ym?
top <- j[order(-abs(BM_Ret_m))][1:8, .(ym, BM_Ret_m, spec_net, ret_orig, book_net)]
cat("\nlargest-|BM| months (alignment spot check):\n")
print(top)

# 4) raw heads: first 6 rows
cat("\nfirst rows:\n"); print(j[1:6, .(ym, Date, spec_net, book_net, ret_orig, BM_Ret_m)])
