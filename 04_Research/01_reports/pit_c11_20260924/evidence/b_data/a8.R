suppressPackageStartupMessages({library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
e <- as.data.table(read_parquet(file.path(root,"ecos_krw_usd.parquet"), mmap=FALSE)); e[,Date:=as.Date(Date)]
sat <- e[wday(Date)==7]; cat("ECOS KRW Saturday range:", format(min(sat$Date)), "~", format(max(sat$Date)), " n=", nrow(sat), "\n")
b <- as.data.table(read_parquet(file.path(root,"ecos_bond_rates.parquet"), mmap=FALSE)); b[,Date:=as.Date(Date)]
bs <- b[wday(Date)==7, .(n=.N, from=min(Date), to=max(Date)), by=Series]; print(bs)
# ECOS KRW vs KR equity calendar: does ECOS KRW(d) exist for the first trading day after a long KR holiday (value = based on prior session)?
cat("ECOS KRW around 2025 Chuseok:\n"); print(e[Date >= as.Date("2025-10-01") & Date <= as.Date("2025-10-14")])
m <- as.data.table(read_parquet(file.path(root,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
cat("DEXKOUS same window:\n"); print(m[Series_ID=="DEXKOUS" & Date >= as.Date("2025-09-29") & Date <= as.Date("2025-10-14"), .(Date, Value)])
