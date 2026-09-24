suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
print(m[, .(n=.N, first=min(Date), last=max(Date)), by=.(Series, Series_ID, Frequency)])
r <- as.data.table(read_parquet(file.path(C,"regime_daily_v2.parquet"), mmap=FALSE)); r[,Date:=as.Date(Date)]
cat("regime_daily_v2 cols:", names(r), "\n"); cat("range", format(range(r$Date)), " mtime", format(file.info(file.path(C,"regime_daily_v2.parquet"))$mtime), "\n")
print(tail(r[, .SD, .SDcols = intersect(names(r), c("Date","MRS","VIX_z_smooth","Claims_z_smooth","Init_Claims_z_smooth","Sentiment_z_smooth","NFCI_z_smooth"))], 8))
