Sys.setenv(R_DATATABLE_NUM_THREADS="1"); suppressMessages(library(data.table)); setDTthreads(1L)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_A<-file.path(ROOT,"stage_artifacts/WT_D20260621_001")
p<-readRDS(file.path(OUT_A,"panel_fixed.rds"))
zc<-function(v){m<-mean(v,na.rm=TRUE);s<-sd(v,na.rm=TRUE);if(!is.finite(s)||s<1e-12)return(rep(NA_real_,length(v)));pmax(pmin((v-m)/s,3),-3)}
p[, z_M01:=zc(M01),by=Date]; p[, z_H504:=zc(H504),by=Date]
gH<-function(H) 1+pmax(pmin((H-0.5)/0.5,1),-1)
p[, sig_a504:=z_M01*gH(H504)]

# ---- C3: recent-3Y ICIR vs full-sample ICIR for a504 ----
ic<-p[is.finite(sig_a504)&is.finite(Ret_1m),
      .(ic=if(.N>=10) cor(sig_a504,Ret_1m,method="spearman") else NA_real_),by=Date][is.finite(ic)][order(Date)]
full_icir<-mean(ic$ic)/sd(ic$ic)
maxd<-max(ic$Date); rec<-ic[Date>=(maxd-as.difftime(3*365,units="days"))]
rec_icir<-mean(rec$ic)/sd(rec$ic)
cat(sprintf("C3 RF-A3 check: full ICIR(monthly)=%.3f  recent-3Y ICIR=%.3f  ratio=%.2fx  (trigger if >1.5x)\n",
    full_icir, rec_icir, rec_icir/full_icir))
cat(sprintf("   recent-3Y rank-IC mean=%.4f (n=%d) vs full mean=%.4f\n", mean(rec$ic), nrow(rec), mean(ic$ic)))

# ---- C5: sector-neutral IC ----
# sector demeaning of sig_a504 within (Date,Sector), then rank-IC vs fwd.
ps<-p[is.finite(sig_a504)&is.finite(Ret_1m)&!is.na(Sector)]
ps[, sig_sn := sig_a504 - mean(sig_a504,na.rm=TRUE), by=.(Date,Sector)]
ic_raw<-ps[, .(ic=if(.N>=10) cor(sig_a504,Ret_1m,method="spearman") else NA_real_),by=Date][is.finite(ic)]
ic_sn <-ps[, .(ic=if(.N>=10) cor(sig_sn,  Ret_1m,method="spearman") else NA_real_),by=Date][is.finite(ic)]
cat(sprintf("\nC5 RF-A4 sector-neutral: raw rank-IC=%.4f  sector-neutral rank-IC=%.4f  retention=%.0f%%\n",
    mean(ic_raw$ic), mean(ic_sn$ic), 100*mean(ic_sn$ic)/mean(ic_raw$ic)))
# also pure-H sector neutral (is pure H a sector artifact?)
p[, z_H252:=zc(H252),by=Date]
ph<-p[is.finite(z_H252)&is.finite(Ret_1m)&!is.na(Sector)]
ph[, h_sn := z_H252 - mean(z_H252,na.rm=TRUE), by=.(Date,Sector)]
ich_raw<-ph[, .(ic=cor(z_H252,Ret_1m,method="spearman")),by=Date][is.finite(ic)]
ich_sn <-ph[, .(ic=cor(h_sn,  Ret_1m,method="spearman")),by=Date][is.finite(ic)]
cat(sprintf("   pure-H: raw rank-IC=%.4f  sector-neutral=%.4f (both ~0/negative -> not a sector artifact, just no signal)\n",
    mean(ich_raw$ic), mean(ich_sn$ic)))
saveRDS(list(full_icir=full_icir, rec_icir=rec_icir, rfa3_ratio=rec_icir/full_icir,
  rec_ic_mean=mean(rec$ic), sn_retention=mean(ic_sn$ic)/mean(ic_raw$ic),
  ic_raw=mean(ic_raw$ic), ic_sn=mean(ic_sn$ic)),
  file.path(OUT_A,"revise_checks.rds"))
