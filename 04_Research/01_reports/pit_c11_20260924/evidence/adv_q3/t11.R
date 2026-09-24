suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
k <- as.data.table(read_parquet(file.path(C,"ecos_krw_usd.parquet"), mmap=FALSE)); k[, Date := as.Date(Date)]
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
dx <- m[Series_ID=="DEXKOUS", .(Date, DEX=Value)]
z <- merge(k, dx, by="Date", all=TRUE)
print(z[Date>=as.Date("2020-03-16") & Date<=as.Date("2020-03-25")])
print(z[Date>=as.Date("2008-10-22") & Date<=as.Date("2008-10-31")])
