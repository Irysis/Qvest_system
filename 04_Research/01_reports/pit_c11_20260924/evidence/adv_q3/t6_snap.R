suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
fs <- c(sprintf("fred_macro.parquet.bak_%s", c("20260917","20260918","20260921","20260923")), "fred_macro.parquet", "macro_fred.parquet")
for (f in fs) { x <- as.data.table(read_parquet(file.path(C,f), mmap=FALSE)); x[,Date:=as.Date(Date)]
  mx <- x[!is.na(Value), .(mx=max(Date)), by=Series_ID]
  cat(sprintf("%-34s mtime %s | VIX %s HY %s BBB %s DGS10 %s T10Y2Y %s DEXKOUS %s NFCI %s ICSA %s STLFSI4 %s CPI %s INDPRO %s UMCSENT %s\n", f, format(file.info(file.path(C,f))$mtime, "%m-%d %H:%M"),
    mx[Series_ID=="VIXCLS"]$mx, mx[Series_ID=="BAMLH0A0HYM2"]$mx, mx[Series_ID=="BAMLC0A4CBBB"]$mx, mx[Series_ID=="DGS10"]$mx, mx[Series_ID=="T10Y2Y"]$mx, mx[Series_ID=="DEXKOUS"]$mx, mx[Series_ID=="NFCI"]$mx, mx[Series_ID=="ICSA"]$mx, mx[Series_ID=="STLFSI4"]$mx, mx[Series_ID=="CPIAUCSL"]$mx, mx[Series_ID=="INDPRO"]$mx, mx[Series_ID=="UMCSENT"]$mx)) }
# NFCI / STLFSI4 / INDPRO revision check: bak_20260701 vs current
a <- as.data.table(read_parquet(file.path(C,"fred_macro.parquet.bak_20260701"), mmap=FALSE)); a[,Date:=as.Date(Date)]
b <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); b[,Date:=as.Date(Date)]
for (s in c("NFCI","STLFSI4","INDPRO","CPIAUCSL","ICSA","VIXCLS","DGS10","UMCSENT")) {
  z <- merge(a[Series_ID==s, .(Date, va=Value)], b[Series_ID==s, .(Date, vb=Value)], by="Date")
  d <- z[abs(va-vb) > 1e-9]
  cat(sprintf("%-8s overlap=%5d changed=%5d  max|chg|=%.4g  example: %s\n", s, nrow(z), nrow(d), if(nrow(d)) max(abs(d$va-d$vb)) else 0,
     if(nrow(d)) paste(format(d$Date[1]), d$va[1], "->", d$vb[1]) else "-"))
}
# NFCI 2008-10 old vs new
z <- merge(a[Series_ID=="NFCI", .(Date, va=Value)], b[Series_ID=="NFCI", .(Date, vb=Value)], by="Date"); print(z[Date>=as.Date("2008-10-01") & Date<=as.Date("2008-10-24")])
