suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
a <- as.data.table(read_parquet(file.path(C,"fred_macro.parquet.bak_20260701"), mmap=FALSE)); b <- as.data.table(read_parquet(file.path(C,"fred_macro.parquet"), mmap=FALSE))
a[, Date:=as.Date(Date)]; b[, Date:=as.Date(Date)]
x <- merge(a[, .(Series_ID, Date, va=Value)], b[, .(Series_ID, Date, vb=Value)], by=c("Series_ID","Date"))[Date <= as.Date("2026-05-31") & !is.na(va) & !is.na(vb)]
s <- x[, .(n=.N, revised=sum(abs(va-vb) > 1e-9), max_abs=max(abs(va-vb)), first_rev=suppressWarnings(min(Date[abs(va-vb)>1e-9]))), by=Series_ID][order(-revised)]
print(s)
cat("NFCI 2008-10 example:\n"); print(x[Series_ID=="NFCI" & Date>=as.Date("2008-10-01") & Date<=as.Date("2008-10-31")])
# AE pin vintage vs current for StL/NFCI
p <- as.data.table(read_parquet("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/pins/WT-D20260718_007_r1/fred_macro_wide.parquet", mmap=FALSE)); p[, Date:=as.Date(Date)]
y <- merge(p[!is.na(Chi_Fin_Cond), .(Date, pin=Chi_Fin_Cond)], a[Series_ID=="NFCI", .(Date, jul1=Value)], by="Date")
cat(sprintf("pin(07-18) vs bak_0701 NFCI: n=%d revised=%d\n", nrow(y), sum(abs(y$pin-y$jul1)>1e-9)))
