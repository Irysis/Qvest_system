suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
cat("mtimes: unified", format(file.info(file.path(C,"unified_regime_signal_daily.parquet"))$mtime), " wide", format(file.info(file.path(C,"fred_macro_wide.parquet"))$mtime), "\n")
u <- as.data.table(read_parquet(file.path(C,"unified_regime_signal_daily.parquet"), mmap=FALSE)); u[,Date:=as.Date(Date)]
w <- as.data.table(read_parquet(file.path(C,"fred_macro_wide.parquet"), mmap=FALSE)); w[,Date:=as.Date(Date)]; setorder(w, Date)
for (c in setdiff(names(w),"Date")) if (is.numeric(w[[c]])) setnafill(w, "locf", cols=c)
nm <- function(x,l,h) pmax(0,pmin(1,(x-l)/(h-l)))
w[, `:=`(vc=nm(VIX,12,40), hc=nm(HY_Spread,2,8), tc=nm(0.5-Term_Spread,0,2), fc=nm(Fed_Funds_Rate,2,6), bc=nm(BBB_Spread,1,4), nc=nm(Chi_Fin_Cond,-0.5,1.5))]
w[, aw := (!is.na(vc))*25+(!is.na(hc))*25+(!is.na(tc))*15+(!is.na(fc))*10+(!is.na(bc))*15+(!is.na(nc))*10]
w[, mrs := (fifelse(is.na(vc),0,25*vc)+fifelse(is.na(hc),0,25*hc)+fifelse(is.na(tc),0,15*tc)+fifelse(is.na(fc),0,10*fc)+fifelse(is.na(bc),0,15*bc)+fifelse(is.na(nc),0,10*nc))*100/aw]
w[, mrs_lag1 := shift(mrs)]
z <- merge(u[, .(Date, FRED_MRS)], w[, .(Date, mrs, mrs_lag1, VIX)], by="Date")
for (per in list(c("2010-01-01","2019-12-31"), c("2020-02-15","2020-04-30"), c("2025-01-01","2026-09-30"))) {
  zz <- z[Date>=as.Date(per[1]) & Date<=as.Date(per[2]) & !is.na(FRED_MRS)]
  cat(sprintf("%s~%s n=%d exact(lag0)=%.3f exact(lag1)=%.3f  mean|d| lag0=%.4f lag1=%.4f\n", per[1], per[2], nrow(zz),
    mean(abs(zz$FRED_MRS-zz$mrs)<1e-6,na.rm=T), mean(abs(zz$FRED_MRS-zz$mrs_lag1)<1e-6,na.rm=T), mean(abs(zz$FRED_MRS-zz$mrs),na.rm=T), mean(abs(zz$FRED_MRS-zz$mrs_lag1),na.rm=T)))
}
print(z[Date>=as.Date("2020-03-11") & Date<=as.Date("2020-03-18")])
