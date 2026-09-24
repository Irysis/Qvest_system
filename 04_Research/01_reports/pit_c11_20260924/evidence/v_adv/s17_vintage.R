suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rd <- function(f){ x <- as.data.table(read_parquet(paste0(R,f), mmap=FALSE)); x[, Date:=as.Date(Date)]; sid <- if ("Series_ID" %in% names(x)) "Series_ID" else "Series"; x[, .(S=get(sid), Date, Value)] }
old <- rd("fred_macro.parquet.bak_20260701"); new <- rd("macro_fred.parquet")
j <- merge(old[Date<=as.Date("2026-05-31"), .(S,Date,v0=Value)], new[Date<=as.Date("2026-05-31"), .(S,Date,v1=Value)], by=c("S","Date"))
print(j[, .(n=.N, changed=sum(abs(v1-v0)>1e-9,na.rm=TRUE), first_chg=suppressWarnings(min(Date[abs(v1-v0)>1e-9],na.rm=TRUE))), by=S][order(-changed)][1:10])
print(j[S %in% c("NFCI","STLFSI4") & Date==as.Date("2020-03-27")])
