suppressPackageStartupMessages({library(data.table);library(arrow)});setDTthreads(1)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot";WD<-file.path(ROOT,"stage_artifacts/selfdev_c1_benchaware_construction")
# reconstruct cap-weighted K200 return from RAWDATA month-ends and correlate with real BM_Ret
rd<-as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet")))
rd<-rd[,.(Date,Ticker,K200,Close,Size)];rd[,Date:=as.Date(Date)];setorder(rd,Ticker,Date);rd[,ym:=as.Date(cut(Date,"month"))]
rd[,.grp:=.GRP,by=.(Ticker,ym)];me<-rd[rd[,.I[.N],by=.grp]$V1];setorder(me,Ticker,ym)
me[,cp:=shift(Close,1),by=Ticker];me[,mret:=Close/cp-1]
# lag cap for weight (PIT: weight by t-1 cap, realize t return)
me[,cap_lag:=shift(Size,1),by=Ticker]
k<-me[K200==TRUE & is.finite(mret) & is.finite(cap_lag)]
recon<-k[,.(recon=sum(cap_lag/sum(cap_lag)*mret)),by=ym]
P<-as.data.table(read_parquet(file.path(WD,"panel/panel_monthly.parquet")));P[,Date:=as.Date(Date)]
bench<-as.data.table(read_parquet(file.path(WD,"panel/benchmark_monthly.parquet")));bench[,Date:=as.Date(Date)]
# real BM_Ret is FORWARD (aligned to signal t). To compare with recon (realized at month), shift bench back.
setorder(bench,Date);bench[,realized:=shift(BM_Ret,1)] # realized at month = last month's forward
cmp<-merge(recon,bench[,.(ym=Date,realized)],by="ym")[is.finite(recon)&is.finite(realized)]
cmp<-cmp[ym>=as.Date("2005-01-01")]
cat(sprintf("recon cap-w K200 vs real BM_Ret: n=%d cor=%.3f mean_recon=%.4f mean_real=%.4f\n",
    nrow(cmp),cor(cmp$recon,cmp$realized),mean(cmp$recon)*12,mean(cmp$realized)*12))
