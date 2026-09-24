suppressPackageStartupMessages({library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
r <- as.data.table(read_parquet(file.path(root,"regime_daily_v2.parquet"), mmap=FALSE)); r[,Date:=as.Date(Date)]
cat("regime_daily_v2:", format(min(r$Date)), "~", format(max(r$Date)), " mtime:", format(file.info(file.path(root,"regime_daily_v2.parquet"))$mtime), "\n")
for (c in c("VIX_z_smooth","HY_z_smooth","NFCI_z_smooth","Claims_z_smooth","Sentiment_z_smooth")) { x <- r[!is.na(get(c))]; cat(sprintf("  %-20s non-NA %s ~ %s\n", c, format(min(x$Date)), format(max(x$Date)))) }
m <- as.data.table(read_parquet(file.path(root,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
cat("HY in macro_fred:", format(min(m[Series_ID=="BAMLH0A0HYM2"]$Date)), "\n")
b <- as.data.table(read_parquet(file.path(root,"fred_macro.parquet.bak_20260701"), mmap=FALSE)); b[,Date:=as.Date(Date)]
cat("HY in bak_20260701:", format(min(b[Series_ID=="BAMLH0A0HYM2"]$Date)), "\n")
