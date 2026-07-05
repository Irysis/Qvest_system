suppressPackageStartupMessages({library(data.table);library(arrow)});setDTthreads(1)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
rd<-as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet")))
rd<-rd[,.(Date,Ticker,K200,Close,Size,BM_Ret)];rd[,Date:=as.Date(Date)];setorder(rd,Ticker,Date);rd[,ym:=as.Date(cut(Date,"month"))]
rd[,.grp:=.GRP,by=.(Ticker,ym)];me<-rd[rd[,.I[.N],by=.grp]$V1];setorder(me,Ticker,ym)
me[,cp:=shift(Close,1),by=Ticker];me[,mret:=Close/cp-1];me[,cap_lag:=shift(Size,1),by=Ticker]
k<-me[K200==TRUE & is.finite(mret) & is.finite(cap_lag)]
recon<-k[,.(recon=sum(cap_lag/sum(cap_lag)*mret)),by=ym]
# real realized monthly BM from daily BM_Ret compounded (same as panel builder, but NOT forward-shifted)
bm<-unique(rd[!is.na(BM_Ret),.(Date,ym,BM_Ret)],by="Date")
bmm<-bm[,.(real=prod(1+BM_Ret)-1),by=ym]
cmp<-merge(recon,bmm,by="ym")[is.finite(recon)&is.finite(real) & ym>=as.Date("2005-01-01")]
cat(sprintf("recon cap-w K200 vs real KOSPI200 realized: n=%d cor=%.3f mean_recon_ann=%.4f mean_real_ann=%.4f\n",
    nrow(cmp),cor(cmp$recon,cmp$real),mean(cmp$recon)*12,mean(cmp$real)*12))
