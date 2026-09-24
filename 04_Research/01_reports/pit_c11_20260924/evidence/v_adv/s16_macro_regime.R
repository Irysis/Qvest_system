suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
mr <- as.data.table(read_parquet(paste0(R,"macro_regime.parquet"), mmap=FALSE))
cat("cols:", paste(names(mr), collapse=","), "\n")
dc <- intersect(c("Date","YM","date"), names(mr))
print(mr[as.character(get(dc[1])) %like% "2020-03|202003|2026-08|202608"])
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
print(m[Series_ID %in% c("VIXCLS","NFCI","ICSA","STLFSI4") & Date %between% c(as.Date("2020-03-25"), as.Date("2020-04-02")), .(Date, Series_ID, Value)])
print(m[Series_ID %in% c("VIXCLS","NFCI","ICSA","STLFSI4") & Date %between% c(as.Date("2026-08-26"), as.Date("2026-09-02")), .(Date, Series_ID, Value)])
