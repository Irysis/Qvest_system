## R29 verification: (A) reproduce R27's exact 3.807 (STORED panel base + pure_factor_scores value),
## (B) controlled base-vintage swap on the SAME value (stored->recon-off0 clean),
## (C) diagnose the LA-value(vz_off1) sign flip (coverage + per-month).
suppressPackageStartupMessages({library(arrow); library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_005")
source(file.path(QM,"02_Infrastructure/contracts/weighted_screen_bt.R"))
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
cap_norm<-function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<8)return(NA_real_);fit<-lm(x~1)
  se<-sqrt(NeweyWest(fit,lag=lag,prewhite=FALSE)[1,1]);unname(coef(fit)[1]/se)}
IR_ann<-function(v){v<-v[is.finite(v)];if(length(v)<6)return(NA_real_);s<-sd(v);mean(v)/s*sqrt(12)}
IS_END<-as.Date("2024-06-30"); W<-0.30

PAN<-as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet")));PAN[,Date:=as.Date(Date)]
VP<-as.data.table(read_parquet(file.path(WT,"value_panels.parquet")));VP[,Date:=as.Date(Date)]
SI<-readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fwd_ret<-SI$fwd_ret;bench<-SI$bench;liqf<-SI$liqf;SIZE<-SI$SIZE;bk<-SI$bk

## ---- map STORED panel to d0 dates (verbatim from R28 screen_r28.R) ----
bk_sc<-bk[is.finite(score_eff),.(Date=as.Date(Date),Ticker,score_eff)]
bk_sc[,map_ym:=format(as.Date(paste0(format(Date,"%Y-%m"),"-01"))-1,"%Y-%m")]
d0map<-data.table(d0=sort(unique(fwd_ret$Date)));d0map[,ym:=format(d0,"%Y-%m")]
bk_sc<-merge(bk_sc,d0map,by.x="map_ym",by.y="ym")
STORED<-bk_sc[,.(Date=d0,Ticker,score_stored=score_eff)]

DT<-merge(PAN,VP,by=c("Date","Ticker"),all.x=TRUE)
DT<-merge(DT,STORED,by=c("Date","Ticker"),all.x=TRUE)

mk_capw<-function(dt,scorecol){S<-merge(dt[is.finite(get(scorecol)),.(Date,Ticker,sc=get(scorecol))],SIZE,by=c("Date","Ticker"))
  S<-merge(S,liqf,by=c("Date","Ticker"),all.x=TRUE);S<-S[is.na(adv)|adv>=2e8];dd<-sort(unique(S$Date));Wl<-list()
  for(i in seq_along(dd)){d<-dd[i];sub<-S[Date==d];if(nrow(sub)<25)next;setorder(sub,-sc);hd<-head(sub,25)
    Wl[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=cap_norm(hd$Size))};rbindlist(Wl)}
screen_col<-function(dt,scorecol,tag){Wc<-mk_capw(dt,scorecol);if(nrow(Wc)==0)return(NULL)
  res<-weighted_screen_bt(Wc,fwd_ret,bench,cost_bps_oneway=15,run_id=tag,strategy_id=tag)
  pr<-as.data.table(res$period_returns);pr[,active:=ret_net-benchmark_ret];list(pr=pr,res=res)}
blend_col<-function(dt,basecol,valcol,w=W){d<-copy(dt[is.finite(get(basecol)),.(Date,Ticker,b=get(basecol),v=get(valcol))])
  d[,b_z:=zc(b),by=Date];d[,v_z:=zc(v),by=Date];d[is.na(v_z),v_z:=0];d[,blend:=(1-w)*b_z+w*v_z];d[,.(Date,Ticker,blend)]}
paired_of<-function(varpr,basepr){m<-merge(varpr[,.(date,va=active)],basepr[,.(date,ba=active)],by="date")
  list(full=nw_t(m$va-m$ba),is=nw_t(m[date<=IS_END,va-ba]),ho=nw_t(m[date>IS_END,va-ba]),
       dIR=IR_ann(m$va)-IR_ann(m$ba),n=nrow(m))}

## ==== (A) reproduce R27 exact: STORED base + pure_factor_scores value (vz_pfs) ====
b_stored<-screen_col(DT,"score_stored","vfy_base_stored")
cat(sprintf("(A) STORED base PORT_t=%.3f IR=%.3f n=%d  [R27 expected 5.324/1.275/255]\n",
  b_stored$res$portfolio_alpha_t_nw_lag3,b_stored$res$information_ratio,b_stored$res$n_months))
bl<-blend_col(DT,"score_stored","vz_pfs"); bdt<-merge(DT[,.(Date,Ticker)],bl,by=c("Date","Ticker"),all.x=TRUE)
v_stored<-screen_col(bdt,"blend","vfy_Z6_stored"); p<-paired_of(v_stored$pr,b_stored$pr)
cat(sprintf("(A) Z6 STORED base + pfs value: var_pt=%.3f paired_full=%.3f IS=%.3f HO=%.3f dIR=%.3f  [R27: paired 3.807/IS 3.171/HO 4.300/dIR 0.481]\n",
  v_stored$res$portfolio_alpha_t_nw_lag3,p$full,p$is,p$ho,p$dIR))

## ==== (B) controlled base-vintage swap holding value = vz_pfs (=clean, cor 1.0) ====
for(bc in c("1_stored_S7","0_stored_S7","1_ic_S7","0_ic_S7")){
  bb<-screen_col(DT,bc,paste0("vfy_b_",bc))
  bl<-blend_col(DT,bc,"vz_pfs"); bdt<-merge(DT[,.(Date,Ticker)],bl,by=c("Date","Ticker"),all.x=TRUE)
  vv<-screen_col(bdt,"blend",paste0("vfy_z6_",bc)); pp<-paired_of(vv$pr,bb$pr)
  cat(sprintf("(B) base=%-12s pt=%.2f + vz_pfs: var_pt=%.2f paired=%.3f IS=%.3f HO=%.3f dIR=%.3f\n",
    bc,bb$res$portfolio_alpha_t_nw_lag3,vv$res$portfolio_alpha_t_nw_lag3,pp$full,pp$is,pp$ho,pp$dIR))
}

## ==== (C) diagnose LA value (vz_off1) sign flip ====
cat("\n(C) value vintage coverage per era:\n")
VP2<-copy(VP); VP2[,era:=fifelse(Date<=IS_END,"IS","HO")]
cvg<-VP2[,.(n=.N, fin_off0=sum(is.finite(vz_off0)), fin_off1=sum(is.finite(vz_off1)), fin_pfs=sum(is.finite(vz_pfs))),by=era]
print(cvg)
## per-month: how often does off1 disagree in SIGN of the tilt with off0 (top/bottom quintile flips)?
mm<-VP[is.finite(vz_off0)&is.finite(vz_off1)]
mm[,d:=vz_off1-vz_off0]
cat(sprintf("  vz_off1-vz_off0: mean abs diff=%.3f  q95 abs=%.3f  (self-cor 0.985)\n",mean(abs(mm$d)),quantile(abs(mm$d),0.95)))
## recent-edge: months where off1 exists (factor_db_{M+1} available)
last_off1<-VP[is.finite(vz_off1),max(Date)]; last_off0<-VP[is.finite(vz_off0),max(Date)]
cat(sprintf("  last month with finite vz_off1=%s ; vz_off0=%s\n",as.character(last_off1),as.character(last_off0)))
cat("VERIFY_DONE\n")
