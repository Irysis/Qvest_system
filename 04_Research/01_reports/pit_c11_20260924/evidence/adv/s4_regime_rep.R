suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
REPO <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
sig_d <- as.Date(Sys.getenv("SIGD", "2026-08-31")); ym <- format(sig_d, "%Y%m")
ds <- open_dataset(file.path(C,"RAWDATA.parquet"))
lo <- sig_d - 1400
rd <- as.data.table(ds |> dplyr::filter(Date >= lo, Date <= sig_d) |> dplyr::select(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret) |> dplyr::collect())
rd[, Date:=as.Date(Date)]; setkey(rd, Date, Ticker)
# variant A: live macro_fred (builder convention)
tmpA <- file.path(Sys.getenv("TMPD"), "cacheA"); dir.create(tmpA, showWarnings=FALSE)
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
write_parquet(m, file.path(tmpA, "macro_fred.parquet"))
# variant B: publication-aware — monthly series (freq m) obs dated YYYY-MM-01 only usable if release (approx) <= sig_d-1
#   conservative approx: monthly obs usable from Date + 1 month + 20 days (CPI ~10-15th, INDPRO ~15-17th next month)
tmpB <- file.path(Sys.getenv("TMPD"), "cacheB"); dir.create(tmpB, showWarnings=FALSE)
mB <- copy(m); mB <- mB[!(Frequency %in% c("m","M","monthly") & (seq_len(.N) > 0) & (as.Date(sapply(Date, function(d) as.character(seq(d, by="1 month", length.out=2)[2]))) + 19 > sig_d - 1))]
write_parquet(mB, file.path(tmpB, "macro_fred.parquet"))
source(file.path(REPO, "02_Infrastructure/factor_db/compute_regime.R"))
CACHE_DIR <- tmpA; ra <- compute_regime(rd, sig_d)
CACHE_DIR <- tmpB; rb <- compute_regime(rd, sig_d)
fd <- as.data.table(read_parquet(file.path(C,"factor_db",sprintf("factor_db_%s.parquet", ym)), mmap=FALSE))
for (fn in c("MA01_GDP_Sensitivity","MA02_CPI_Sensitivity","MA03_Rate_Sensitivity","MA04_YieldCurve_Sensitivity","RE14_Inflation_YoY","MA07_BusinessCycle_Composite")) {
  s <- fd[Factor_Name==fn, .(Ticker, st=Raw_Value)]; a <- ra[Factor_Name==fn, .(Ticker, a=Raw_Value)]; b <- rb[Factor_Name==fn, .(Ticker, b=Raw_Value)]
  x <- merge(merge(s, a, by="Ticker", all=TRUE), b, by="Ticker", all=TRUE)
  cat(sprintf("%s %-30s stored n=%d | repA n=%d maxdiff(st,A)=%s | pubaware n=%d | spearman(A,B)=%s\n", ym, fn, sum(!is.na(x$st)), sum(!is.na(x$a)),
     if (sum(!is.na(x$st) & !is.na(x$a))) format(max(abs(x$st-x$a), na.rm=TRUE), digits=3) else "NA",
     sum(!is.na(x$b)), if (sum(!is.na(x$a) & !is.na(x$b))>10) format(cor(x$a, x$b, method="spearman", use="c"), digits=4) else "NA"))
  if (fn %in% c("RE14_Inflation_YoY","MA07_BusinessCycle_Composite")) cat(sprintf("     stored=%s A=%s B=%s\n", x$st[1], x$a[1], x$b[1]))
}
