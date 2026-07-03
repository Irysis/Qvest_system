Sys.setenv(R_DATATABLE_NUM_THREADS="1"); suppressMessages({library(data.table);library(arrow)}); setDTthreads(1L)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_A<-file.path(ROOT,"stage_artifacts/WT_D20260621_001")
p<-readRDS(file.path(OUT_A,"panel_fixed.rds"))
# attach Sector at each (Date,Ticker) from rawdata
RAW<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Sector")))
RAW[,Date:=as.Date(Date)]
p<-merge(p, RAW, by=c("Date","Ticker"), all.x=TRUE)
zc<-function(v){m<-mean(v,na.rm=TRUE);s<-sd(v,na.rm=TRUE);if(!is.finite(s)||s<1e-12)return(rep(NA_real_,length(v)));pmax(pmin((v-m)/s,3),-3)}
p[, z_M01:=zc(M01),by=Date]; p[, z_H252:=zc(H252),by=Date]
gH<-function(H) 1+pmax(pmin((H-0.5)/0.5,1),-1)
p[, sig_a504:=z_M01*gH(H504)]
ps<-p[is.finite(sig_a504)&is.finite(Ret_1m)&!is.na(Sector)]
ps[, sig_sn := sig_a504 - mean(sig_a504,na.rm=TRUE), by=.(Date,Sector)]
ic_raw<-ps[, .(ic=if(.N>=10) cor(sig_a504,Ret_1m,method="spearman") else NA_real_),by=Date][is.finite(ic)]
ic_sn <-ps[, .(ic=if(.N>=10) cor(sig_sn,  Ret_1m,method="spearman") else NA_real_),by=Date][is.finite(ic)]
cat(sprintf("C5 RF-A4 sector-neutral (a504): raw IC=%.4f  SN IC=%.4f  retention=%.0f%%\n",
    mean(ic_raw$ic), mean(ic_sn$ic), 100*mean(ic_sn$ic)/mean(ic_raw$ic)))
ph<-p[is.finite(z_H252)&is.finite(Ret_1m)&!is.na(Sector)]
ph[, h_sn := z_H252 - mean(z_H252,na.rm=TRUE), by=.(Date,Sector)]
ich_raw<-ph[, .(ic=cor(z_H252,Ret_1m,method="spearman")),by=Date][is.finite(ic)]
ich_sn <-ph[, .(ic=cor(h_sn,Ret_1m,method="spearman")),by=Date][is.finite(ic)]
cat(sprintf("   pure-H: raw IC=%.4f  SN IC=%.4f (both ~0/neg -> not sector artifact, just no signal)\n",
    mean(ich_raw$ic), mean(ich_sn$ic)))
old<-readRDS(file.path(OUT_A,"revise_checks.rds"))
old$sn_retention<-mean(ic_sn$ic)/mean(ic_raw$ic); old$ic_raw<-mean(ic_raw$ic); old$ic_sn<-mean(ic_sn$ic)
old$pureH_raw<-mean(ich_raw$ic); old$pureH_sn<-mean(ich_sn$ic)
saveRDS(old, file.path(OUT_A,"revise_checks.rds"))
