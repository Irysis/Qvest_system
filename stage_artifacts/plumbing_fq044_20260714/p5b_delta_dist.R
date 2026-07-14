## p5b_delta_dist.R — icw 재현 residual 분포 정밀화 (판단 재료)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/ramp/factor_validation.R")
GS<-"outputs/ramp/factor_group_scores.parquet"
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p=="TR") "Size_Liquidity" else "Composite" }
G<-as.data.table(read_parquet(GS)); G[,signal_date:=as.Date(signal_date)]
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
sig<-sort(unique(af$factor_id))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
      col_select=c("signal_date","security_id","factor_id","neutralized_z")))
sc[,signal_date:=as.Date(signal_date)]; sc<-sc[factor_id %in% sig]
sc[,family:=sapply(factor_id,fam_of)]; sc<-sc[family!="Macro"]
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet",
  col_select=all_of(c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret"))))
rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(sc$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
fr<-fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)]
rm(rawdata); invisible(gc())
icm<-merge(sc[,.(signal_date,security_id,factor_id,neutralized_z)],fr,by=c("signal_date","security_id"))
fic<-icm[,.(ic=if(.N>=20&&sd(neutralized_z)>0&&sd(Ret_1m)>0)cor(neutralized_z,Ret_1m,method="spearman")else NA_real_),
         by=.(signal_date,factor_id)]
rm(icm); invisible(gc())
setorder(fic,factor_id,signal_date)
fic[,ic_trail:=shift(cumsum(fifelse(is.na(ic),0,ic))/cumsum(!is.na(ic)),1),by=factor_id]
fic[is.na(ic_trail),ic_trail:=0]
sc2<-merge(sc,fic[,.(signal_date,factor_id,ic_trail)],by=c("signal_date","factor_id"),all.x=TRUE)
sc2[is.na(ic_trail),ic_trail:=0]; sc2[,wgt:=pmax(ic_trail,0)]
sc2[,wsum:=sum(wgt),by=.(signal_date,security_id,family)]
sc2[,wgt2:=fifelse(wsum<1e-9, 1.0, wgt)]
grp<-sc2[,.(z=sum(neutralized_z*wgt2)/sum(wgt2)),by=.(signal_date,security_id,family)]
grp[,gz:={m<-mean(z,na.rm=T);s<-sd(z,na.rm=T);if(is.na(s)||s<1e-9)z-m else (z-m)/s},by=.(signal_date,family)]
GRP<-grp[,.(signal_date,security_id,family,group_z=gz)]
rm(sc,sc2,grp); invisible(gc())
save_p<-"stage_artifacts/plumbing_fq044_20260714/p5_GRP_recomputed.parquet"
.t<-paste0(save_p,".tmp"); write_parquet(GRP,.t); if(file.exists(save_p))file.remove(save_p); file.rename(.t,save_p)

## 전 기간(1970~2026-05, 즉 저장 파일 전 월) delta 분포
M<-merge(GRP, G[,.(signal_date,security_id,family,ref=group_z)], by=c("signal_date","security_id","family"))
M[,d:=abs(group_z-ref)]
cat(sprintf("[dist all-months] n=%d | share<1e-9=%.5f <1e-6=%.5f <1e-3=%.5f <1e-2=%.5f | q999=%.3e max=%.3e\n",
  nrow(M), M[,mean(d<1e-9)], M[,mean(d<1e-6)], M[,mean(d<1e-3)], M[,mean(d<1e-2)],
  M[,quantile(d,0.999)], M[,max(d)]))
by_yr<-M[,.(n=.N, med=median(d), q99=quantile(d,0.99), mx=max(d)), by=.(yr=format(signal_date,"%Y"))][order(yr)]
print(by_yr, nrows=30)
by_fam<-M[,.(med=median(d), mx=max(d)), by=family][order(-mx)]
print(by_fam)
cat("P5B_DIST_DONE\n")
