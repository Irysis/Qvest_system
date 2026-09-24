suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
mr <- as.data.table(read_parquet(file.path(C,"macro_regime.parquet"), mmap=FALSE)); mr[,Date:=as.Date(Date)]
cat("macro_regime mtime", format(file.info(file.path(C,"macro_regime.parquet"))$mtime), "\n")
cols <- intersect(c("Date","VIX","Chi_Fin_Cond","Init_Claims","StL_Fin_Stress","UMich_Sentiment","US_CPI","CPI_YoY","HY_Spread","Macro_Risk_Score","VIX_Regime"), names(mr))
print(tail(mr[, ..cols], 3))
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
cat("label dates of last obs in Aug-2026 per series:\n"); print(m[Date>=as.Date("2026-08-01") & Date<=as.Date("2026-08-31") & Series_ID %in% c("VIXCLS","NFCI","ICSA","STLFSI4","UMCSENT","CPIAUCSL"), .(last_label=max(Date), val=Value[which.max(Date)]), by=Series_ID])
cat("macro_regime 2020-03 row:\n"); print(mr[Date==as.Date("2020-03-31"), ..cols])
u <- as.data.table(read_parquet(file.path(C,"unified_regime_signal_daily.parquet"), mmap=FALSE)); u[,Date:=as.Date(Date)]
w <- as.data.table(read_parquet(file.path(C,"fred_macro_wide.parquet"), mmap=FALSE)); w[,Date:=as.Date(Date)]
cat("fred_macro_wide cols:", head(names(w),30), "\n")
cat("wide VIX 2020-03-16:", w[Date==as.Date("2020-03-16")]$VIX, "\n")
print(u[Date>=as.Date("2026-08-27") & Date<=as.Date("2026-09-02"), .(Date, FRED_MRS, Category, Regime_Score)])
setorder(w, Date); for (c in setdiff(names(w),"Date")) if (is.numeric(w[[c]])) setnafill(w, "locf", cols=c)
nm <- function(x,l,h) pmax(0,pmin(1,(x-l)/(h-l)))
w[, mrs := {s <- 25*nm(VIX,12,40)+25*nm(HY_Spread,2,8)+15*nm(0.5-Term_Spread,0,2)+10*nm(Fed_Funds_Rate,2,6)+15*nm(BBB_Spread,1,4)+10*nm(Chi_Fin_Cond,-0.5,1.5); s}]
print(w[Date>=as.Date("2026-08-27") & Date<=as.Date("2026-09-02"), .(Date, VIX, HY_Spread, Chi_Fin_Cond, Fed_Funds_Rate, mrs)])
