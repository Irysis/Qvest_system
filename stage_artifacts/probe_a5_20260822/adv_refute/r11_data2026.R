suppressPackageStartupMessages({library(data.table);library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[,Date:=as.Date(Date)]; rd<-rd[Date>=as.Date("2005-01-01")&is.finite(Ret)&is.finite(Size)&Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]; u<-rd[inuniv==TRUE]; u[,yr:=format(Date,"%Y")]
cat("== A. fraction of universe at daily limit (|Ret|>=0.299) — by year ==\n")
D<-u[,.(n=.N, lim_up=mean(Ret>=0.299), lim_dn=mean(Ret<=-0.299)),by=.(Date,yr)]
print(D[,.(days=.N, mean_limup=mean(lim_up), max_limup=max(lim_up), days_limup_gt10pct=sum(lim_up>0.10),
   days_limup_gt25pct=sum(lim_up>0.25)),by=yr],digits=3)
cat("\n== B. days with >25% of universe limit-up ==\n")
print(D[lim_up>0.25][order(-lim_up)][1:15,.(Date,n,lim_up=round(lim_up,3),lim_dn=round(lim_dn,3))])
cat("\n== C. exact-value clustering of Ret ==\n")
for(y in c("2015","2020","2024","2025","2026")) cat(sprintf("   %s: Ret==0.30 exactly: %d  |Ret|>0.30: %d  of %d\n",
  y,u[yr==y&abs(Ret-0.30)<1e-12,.N],u[yr==y&abs(Ret)>0.30+1e-9,.N],u[yr==y,.N]))
cat("\n== D. index parquet 2026-07-31 reproduced from rawdata (Size_lag VW) ==\n")
setorder(u,Ticker,Date); u[,Size_lag:=shift(Size,1),by=Ticker]
for(dt in as.Date(c("2026-07-31","2026-03-04","2026-07-28"))){ x<-u[Date==dt&is.finite(Size_lag)&Size_lag>0]
  cat(sprintf("   %s VW(Size_lag)=%+.5f  n=%d\n",as.character(dt),sum(x$Size_lag*x$Ret)/sum(x$Size_lag),nrow(x))) }
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet")); R[,Date:=as.Date(Date)]
print(R[Date%in%as.Date(c("2026-07-31","2026-03-04","2026-07-28")),.(Date,Market=round(Market,5))])
cat("\n== E. universe size + Size level drift ==\n")
print(u[,.(n_names=uniqueN(Ticker), tot_cap_tn=round(sum(Size[Date==max(Date)])/1e12,0)),by=yr][c(1,5,10,15,19,20,21,22)])
cat("\n== F. Market index cumulative by year (index parquet) ==\n")
R[,yr:=format(Date,"%Y")]; print(R[,.(mkt=round(prod(1+Market)-1,4)),by=yr][17:22])
