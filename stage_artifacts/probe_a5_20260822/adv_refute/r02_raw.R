suppressPackageStartupMessages({library(data.table);library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[,Date:=as.Date(Date)]
rd<-rd[Date>=as.Date("2005-01-01") & is.finite(Ret) & is.finite(Size) & Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]
u<-rd[inuniv==TRUE]
cat("universe rows:",nrow(u)," date max:",as.character(max(u$Date)),"\n")
cat("\n-- univ member count + ret dispersion by year --\n")
u[,yr:=format(Date,"%Y")]
print(u[,.(n_ticker_day=.N, n_uniq_tk=uniqueN(Ticker), med_n_per_day=as.numeric(median(table(Date))),
   ret_sd=sd(Ret), ret_min=min(Ret), ret_max=max(Ret), ret_mean=mean(Ret)),by=yr])
cat("\n-- 2026-07-31 detail --\n")
d<-u[Date==as.Date("2026-07-31")]
cat("n=",nrow(d)," mean ret=",mean(d$Ret)," ; VW(with Size same-day)=",sum(d$Size*d$Ret)/sum(d$Size),"\n")
print(head(d[order(-abs(Ret)),.(Ticker,Ret,Size)],10))
cat("\n-- daily EW mean ret, 2026 monthly --\n")
print(u[format(Date,"%Y")=="2026",.(nd=uniqueN(Date), ew=mean(Ret), sd=sd(Ret), mx=max(Ret), mn=min(Ret)),by=.(ym=format(Date,"%Y-%m"))])
cat("\n-- pct of |Ret|>0.30 by year (limit-breach proxy) --\n")
print(u[,.(frac_gt30=mean(abs(Ret)>0.30), frac_gt15=mean(abs(Ret)>0.15)),by=yr])
