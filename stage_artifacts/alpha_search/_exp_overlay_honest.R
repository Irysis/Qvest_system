## Honest PIT overlay: trailing-drawdown de-risk (strictly past core returns).
## If even this helps robustly, an honest regime overlay might exist.
suppressPackageStartupMessages({library(data.table);library(PerformanceAnalytics);library(xts)})
options(warn=1)
OUT<-"G:/Quant_Module_Moltbot/stage_artifacts/alpha_search"; BPS<-15
b<-readRDS(file.path(OUT,"_exp_baseline.rds")); core<-copy(b$dt); setorder(core,period_end); NP<-nrow(core)
metr<-function(ret,bm,end){rx<-xts(ret,order.by=as.Date(end));bx<-xts(bm,order.by=as.Date(end));ax<-rx-bx
 list(sr_total=as.numeric(SharpeRatio.annualized(rx,Rf=0,scale=12)),sr_active=as.numeric(SharpeRatio.annualized(ax,Rf=0,scale=12)),
      cagr=as.numeric(Return.annualized(rx,scale=12)),mdd=as.numeric(maxDrawdown(rx)))}
apply_e<-function(e){e[!is.finite(e)]<-1;e<-pmin(pmax(e,0),1);ep<-c(1,head(e,-1));to<-ep*core$turnover+abs(e-ep)
 e*core$port_gross-(BPS/1e4)*to*2}
rep_e<-function(e,nm){ret<-apply_e(e);f<-metr(ret,core$bm_ret,core$period_end)
 oos<-core$period_end>=as.Date("2010-01-01")&core$period_end<=as.Date("2023-12-31");o<-metr(ret[oos],core$bm_ret[oos],core$period_end[oos])
 sp<-function(a,z){i<-core$period_end>=as.Date(a)&core$period_end<=as.Date(z);metr(ret[i],core$bm_ret[i],core$period_end[i])}
 p1<-sp("2005-01-01","2014-12-31");p2<-sp("2015-01-01","2019-12-31");p3<-sp("2020-01-01","2026-12-31")
 mid<-ceiling(NP/2);me<-metr(apply_e(e)[1:mid],core$bm_ret[1:mid],core$period_end[1:mid]);ml<-metr(apply_e(e)[(mid+1):NP],core$bm_ret[(mid+1):NP],core$period_end[(mid+1):NP])
 cat(sprintf("  %-20s FULL SR=%.4f act=%.4f CAGR=%.4f MDD=%.4f | OOS SR=%.4f | P1=%.3f P2=%.3f P3=%.3f | oosret=%.3f\n",
   nm,f$sr_total,f$sr_active,f$cagr,f$mdd,o$sr_total,p1$sr_total,p2$sr_total,p3$sr_total,ml$sr_total/me$sr_total))}
cat("=== baseline ===\n"); rep_e(rep(1,NP),"baseline")
## trailing drawdown of core net (strictly past): cumulative NAV up to t-1, dd = 1 - nav/peak
nav<-cumprod(1+core$port_net); peak<-cummax(nav); dd<-1-nav/peak
dd_lag<-c(0,head(dd,-1))  # t-1 PIT (C9)
cat("\n=== trailing-DD de-risk (strictly t-1) ===\n")
for(thr in c(0.10,0.15,0.20)) for(keep in c(0.5,0.0)){
  e<-ifelse(dd_lag>thr,keep,1); rep_e(e,sprintf("dd>%.0f%%_keep%.0f",thr*100,keep*100))}
cat("\n[DONE]\n")
