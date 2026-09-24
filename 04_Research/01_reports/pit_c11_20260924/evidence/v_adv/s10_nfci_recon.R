suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rg <- as.data.table(read_parquet(paste0(R,"regime_daily_v2.parquet"), mmap=FALSE)); rg[, Date:=as.Date(Date)]
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
w <- dcast(m[, .(Date, Series, Value)], Date ~ Series, value.var="Value", fun.aggregate=function(x){v<-x[!is.na(x)]; if(!length(v)) NA_real_ else v[length(v)]})
setorder(w, Date)
rz <- function(x, window=756L, min_obs=252L){ n<-length(x); z<-rep(NA_real_,n); rm<-frollmean(x,window,na.rm=TRUE); rs<-frollapply(x,window,sd)
  for(i in seq_len(n)){ if(i<min_obs||is.na(x[i])) next; if(i<window){v<-x[1:i];v<-v[!is.na(v)]; if(length(v)>=min_obs) z[i]<-(x[i]-mean(v))/max(sd(v),1e-8)} else if(!is.na(rm[i])&&!is.na(rs[i])&&rs[i]>1e-8) z[i]<-(x[i]-rm[i])/rs[i]}; z}
build <- function(col, pub_lag_days){
  d <- copy(w[, .(Date, x=get(col))])
  if (pub_lag_days>0){ # publication-aware: value dated D becomes visible at D+lag
    obs <- m[Series==col & !is.na(Value), .(Date=Date+pub_lag_days, xv=Value)]
    obs <- obs[, .(xv=xv[.N]), by=Date]
    d[, x:=NULL]; d <- merge(d, obs, by="Date", all=TRUE); setnames(d,"xv","x"); setorder(d,Date)
  }
  d[, x:=nafill(x, "locf")]; d[, z:=rz(x)]; d[, s:=frollmean(z,20L,na.rm=TRUE)]; d[, s_lag:=shift(s)]
  d[, .(Date, s_lag)]
}
for (pr in list(c("Chi_Fin_Cond","NFCI_z_smooth",5L), c("StL_Fin_Stress","FinStress_z_smooth",6L), c("Init_Claims","Claims_z_smooth",5L))) {
  a <- build(pr[1], 0L); p <- build(pr[1], as.integer(pr[3]))
  x <- merge(rg[, .(Date, st=get(pr[2]))], merge(a[,.(Date,A=s_lag)], p[,.(Date,P=s_lag)], by="Date"), by="Date")
  x <- x[Date>=as.Date("2005-01-01") & wday(Date) %in% 2:6 & is.finite(st)&is.finite(A)&is.finite(P)]
  x[, `:=`(dst=st-shift(st), dA=A-shift(A), dP=P-shift(P))]
  cat(sprintf("%-15s n=%d  exact(1e-9) A=%.3f P=%.3f | mean|st-A|=%.4f mean|st-P|=%.4f | cor(dst,dA)=%.3f cor(dst,dP)=%.3f\n", pr[1], nrow(x),
     mean(abs(x$st-x$A)<1e-9), mean(abs(x$st-x$P)<1e-9), mean(abs(x$st-x$A)), mean(abs(x$st-x$P)), cor(x$dst,x$dA,use="c"), cor(x$dst,x$dP,use="c")))
}
