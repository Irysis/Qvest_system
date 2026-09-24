suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
f <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); f[,Date:=as.Date(Date)]
w <- dcast(f[, .(Date, Series, Value)], Date ~ Series, value.var="Value", fun.aggregate=function(x){v<-x[!is.na(x)]; if(!length(v)) NA_real_ else v[length(v)]})
setorder(w, Date)
for (c in c("VIX","Init_Claims","Chi_Fin_Cond")) w[, (c) := nafill(get(c), type="locf")]
rz <- function(x, window=756L, min_obs=252L){ n<-length(x); z<-rep(NA_real_,n); rm<-frollmean(x,n=window,align="right",na.rm=TRUE); rs<-frollapply(x,n=window,FUN=sd,align="right")
  cs <- cumsum(!is.na(x)); s1 <- cumsum(fifelse(is.na(x),0,x)); s2 <- cumsum(fifelse(is.na(x),0,x^2))
  for(i in seq_len(n)){ if(i<min_obs||is.na(x[i])) next; if(i<window){ k<-cs[i]; if(k>=min_obs){ mu<-s1[i]/k; sdv<-sqrt(max((s2[i]-k*mu^2)/(k-1),0)); z[i]<-(x[i]-mu)/max(sdv,1e-8)}} else if(!is.na(rm[i])&&!is.na(rs[i])&&rs[i]>1e-8) z[i]<-(x[i]-rm[i])/rs[i]}; z}
for (c in c("VIX","Init_Claims","Chi_Fin_Cond")) { w[, (paste0(c,"_zs")) := frollmean(rz(get(c)), n=20L, align="right", na.rm=TRUE)] }
w[, `:=`(VIX_lag1 = shift(VIX_zs), CL_lag1 = shift(Init_Claims_zs), NF_lag1 = shift(Chi_Fin_Cond_zs))]
r <- as.data.table(read_parquet(file.path(C,"regime_daily_v2.parquet"), mmap=FALSE)); r[,Date:=as.Date(Date)]
z <- merge(r[, .(Date, VIX_z_smooth, Claims_z_smooth, NFCI_z_smooth)], w[, .(Date, VIX_zs, VIX_lag1, Init_Claims_zs, CL_lag1, Chi_Fin_Cond_zs, NF_lag1)], by="Date")
z <- z[Date >= as.Date("2004-01-01")]
cat(sprintf("VIX : match lag1 %.4f  lag0 %.4f (n=%d)\n", mean(abs(z$VIX_z_smooth-z$VIX_lag1)<1e-6,na.rm=T), mean(abs(z$VIX_z_smooth-z$VIX_zs)<1e-6,na.rm=T), sum(!is.na(z$VIX_z_smooth))))
cat(sprintf("ICSA: match lag1 %.4f  lag0 %.4f\n", mean(abs(z$Claims_z_smooth-z$CL_lag1)<1e-6,na.rm=T), mean(abs(z$Claims_z_smooth-z$Init_Claims_zs)<1e-6,na.rm=T)))
cat(sprintf("NFCI: match lag1 %.4f  lag0 %.4f\n", mean(abs(z$NFCI_z_smooth-z$NF_lag1)<1e-6,na.rm=T), mean(abs(z$NFCI_z_smooth-z$Chi_Fin_Cond_zs)<1e-6,na.rm=T)))
# Leak illustration: COVID ICSA spike label 2020-03-21 (3.3M), released Thu 2020-03-26 08:30 ET (=21:30 KST)
cat("ICSA raw around 2020-03:\n"); print(f[Series=="Init_Claims" & Date>=as.Date("2020-03-07") & Date<=as.Date("2020-04-04"), .(Date, wd=weekdays(Date), Value)])
print(z[Date>=as.Date("2020-03-19") & Date<=as.Date("2020-03-27"), .(Date, wd=weekdays(Date), Claims_z_smooth, CL_lag1)])
