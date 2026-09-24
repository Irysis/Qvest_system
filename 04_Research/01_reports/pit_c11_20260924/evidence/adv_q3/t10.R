suppressPackageStartupMessages({library(arrow); library(data.table); library(dplyr)})
C <- "C:/qm_cache"
k <- as.data.table(read_parquet(file.path(C,"ecos_krw_usd.parquet"), mmap=FALSE)); cat("ecos krw cols:", names(k), "\n")
dc <- intersect(c("Date","date","TIME"), names(k))[1]; k[, D := as.Date(get(dc))]
vc <- setdiff(names(k)[sapply(k, is.numeric)], c())[1]; cat("value col:", vc, "\n")
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
dx <- m[Series_ID=="DEXKOUS", .(D=Date, DEX=Value)]
z <- merge(k[D>=as.Date("2020-03-16") & D<=as.Date("2020-03-25"), .(D, ECOS=get(vc))], dx, by="D", all=TRUE); print(z)
# Known: KRW/USD Seoul close 2020-03-19 = 1285.7 (+40.0), 2020-03-20 close 1246.5.
# daily DB RE_VIX_z vs regime_daily_v2 VIX_z_smooth (same date)
r <- as.data.table(read_parquet(file.path(C,"regime_daily_v2.parquet"), mmap=FALSE)); r[,Date:=as.Date(Date)]
d <- as.data.table(open_dataset(file.path(C,"factor_db_daily","fdb_daily_202003.parquet")) %>% select(Date, Ticker, RE_VIX_z, RE_MRS) %>% collect()); d[,Date:=as.Date(Date)]
dd <- unique(d[, .(Date, RE_VIX_z, RE_MRS)])
zz <- merge(dd, r[, .(Date, VIX_z_smooth, MRS, VIX_z_prev = shift(VIX_z_smooth))], by="Date")
print(zz[Date>=as.Date("2020-03-11") & Date<=as.Date("2020-03-18")])
