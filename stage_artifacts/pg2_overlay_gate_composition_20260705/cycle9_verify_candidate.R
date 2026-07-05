## 사이클 9 — 마일스톤 후보(앵커+부분오버레이) 적대검증: alignment-artifact / placebo / lag1 / book-marginal.
## 핵심 리스크: cycle7/8 오버레이가 offset2·cor0.84 정렬에 의존 → 결과가 정렬 오프셋에 민감하면 아티팩트.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1); set.seed(20260706); PG <- function(...) message(sprintf(...))
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; WD<-file.path(ROOT,"stage_artifacts/pg2_overlay_gate_composition_20260705")
PD<-file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R")); source(file.path(ROOT,"02_Infrastructure/portfolio/strategy_tilt_weights.R"))
COST<-0.0015; INCUMBENT_IR<-1.416
bt<-readRDS(file.path(PD,"04_backtest_results/bt_result_layer5_R05.rds")); pr<-as.data.table(bt$period_returns); pr[,ym:=as.character(realized_ym)]
pr[,e:=ret_L5_V5/ret_orig]; pr[!is.finite(e)|abs(ret_orig)<0.003,e:=NA_real_]; pr[,e:=nafill(nafill(e,"locf"),"nocb")]; pr[e<0,e:=0]; pr[e>1.2,e:=1.2]
sp<-as.data.table(read_parquet(file.path(PD,"02_holdings_universe/alpha_scores_r05_panel.parquet"))); sp[,Date:=as.Date(Date)]
pm<-as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[,Date:=as.Date(Date)]; sp<-merge(sp,pm,by=c("Date","Ticker"),all.x=TRUE); dts<-sort(unique(sp$Date))
bm<-as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[,Date:=as.Date(Date)]; bm<-bm[is.finite(BM_Ret)]; bm[,ym:=format(Date,"%Y-%m")]; bmm<-bm[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
ew<-sp[is.finite(Ret_1m),.(ew=mean(Ret_1m)),by=Date]; ew[,ym:=format(Date,"%Y-%m")]
bo<-0;bc<--2;for(o in -1:3){e2<-copy(ew);e2[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(o),"%Y-%m")];mm<-merge(e2,bmm[,.(k=ym,bm_ret)],by="k");if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret);if(cc>bc){bc<-cc;bo<-o}}}
ew[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(bo),"%Y-%m")]; bench<-merge(ew[,.(Date,k)],bmm[,.(k=ym,BM_Ret=bm_ret)],by="k")[,.(Date,BM_Ret)]
build_raw<-function(K,aw,N=20L,mode="alpha"){prevfill<-NULL;prevtk<-NULL;prevw<-NULL;out<-data.table(Date=dts,ret=NA_real_)
  for(i in seq_along(dts)){D<-dts[i];m<-sp[Date==D&is.finite(score_eff)&is.finite(Ret_1m)&is.finite(size)];if(nrow(m)<N)next
    setorder(m,-size);anch<-if(K>0)m$Ticker[1:K]else character(0);ma<-m[!Ticker%in%anch]
    if(mode=="placebo"){sel<-ma[sample(.N,min(N-K,.N))]}else{setorder(ma,-score_eff);sel<-ma[1:(N-K)]}
    a_t<-sel$score_eff;names(a_t)<-sel$Ticker;fw<-linear_tilt_to_penalty_qd(a_t,lambda=1.5,w_prev=prevfill,phi=3.0,lb=0,ub=0.20)
    tk<-c(anch,names(fw));w<-c(rep(aw,K),as.numeric(fw)*(1-K*aw));rr<-c(m[match(anch,Ticker),Ret_1m],sel$Ret_1m[match(names(fw),sel$Ticker)])
    if(is.null(prevw))turn<-1 else{al<-union(tk,prevtk);wc<-ifelse(al%in%tk,w[match(al,tk)],0);wc[is.na(wc)]<-0;wp<-ifelse(al%in%prevtk,prevw[match(al,prevtk)],0);wp[is.na(wp)]<-0;turn<-sum(abs(wc-wp))}
    out$ret[i]<-sum(w*rr)-turn*COST;prevfill<-fw;prevtk<-tk;prevw<-w};out[is.finite(ret)]}
metr<-function(bk,tag){p2<-merge(bk,bench,by="Date");if(nrow(p2)<50)return(NULL)
  prt<-data.table(date=p2$Date,ret_net=p2$ret,frequency="monthly");brt<-data.table(date=p2$Date,benchmark_ret=p2$BM_Ret,benchmark_id="K200")
  b<-build_benchmark_compare(prt,brt,tag,tag,annualization_factor=12);gv<-function(n){v<-b[metric_name==n,active_value];if(length(v))as.numeric(v[1])else NA_real_}
  act<-p2$ret-p2$BM_Ret;n<-nrow(p2);oos<-median(sapply(c(.55,.65,.75),function(q){ct<-floor(n*q);(mean(act[(ct+1):n])/sd(act[(ct+1):n]))/(mean(act[1:ct])/sd(act[1:ct]))}),na.rm=T)
  rx<-xts(p2$ret,order.by=p2$Date);cg<-as.numeric(Return.annualized(rx,scale=12));md<-as.numeric(maxDrawdown(rx))
  data.table(tag=tag,PORT_t=gv("Portfolio_Alpha_t_NW_lag3"),IR=gv("Information_Ratio"),oos_ret=oos,cagr=cg,mdd=md,calmar=if(md>0)cg/md else NA_real_)}
ov<-function(bk,a,offset){bk<-copy(bk);bk[,ym:=format(Date,"%Y-%m")];bk[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(offset),"%Y-%m")];bk<-merge(bk,pr[,.(k=ym,e)],by="k",all.x=TRUE);bk[is.na(e),e:=1];bk[,ea:=1-a*(1-e)];bk[,ret:=ret*ea];bk[,.(Date,ret)]}
C2<-build_raw(2,0.20); C0<-build_raw(0,0)
## (1) alignment robustness: offset 1,2,3 × α 0.4,0.5,0.6 — does pass_all hold?
PG("=== (1) ALIGNMENT ROBUSTNESS (offset × α) ===")
rob<-list()
for(off in 1:3) for(a in c(0.4,0.5,0.6)){ r<-metr(ov(C2,a,off),sprintf("off%d_a%.1f",off,a))
  r[,pass:=is.finite(PORT_t)&PORT_t>=2.95&is.finite(oos_ret)&oos_ret>=0.7&is.finite(calmar)&calmar>=0.64]; rob[[length(rob)+1]]<-r }
robdt<-rbindlist(rob); print(robdt[,.(tag,PORT_t=round(PORT_t,2),oos_ret=round(oos_ret,3),calmar=round(calmar,3),pass)])
PG("[align-robust] pass_all count across %d (offset,α) combos = %d/%d", nrow(robdt), sum(robdt$pass,na.rm=T), nrow(robdt))
## (2) placebo: random anchor at α0.5 offset2 — 20 draws, candidate PORT_t must exceed null
cand<-metr(ov(C2,0.5,2),"cand"); PG("=== (2) PLACEBO (α0.5) ===")
plc<-sapply(1:20,function(s){set.seed(s);r<-metr(ov(build_raw(2,0.20,mode="placebo"),0.5,2),"p");if(is.null(r))NA_real_ else r$PORT_t})
PG("[placebo] cand PORT_t=%.2f vs null mean=%.2f sd=%.2f p=%.3f",cand$PORT_t,mean(plc,na.rm=T),sd(plc,na.rm=T),mean(plc>=cand$PORT_t,na.rm=T))
## (3) lag1 PIT
c2lag<-copy(C2)[,ret:=shift(ret,1)][is.finite(ret)]; lagm<-metr(ov(c2lag,0.5,2),"lag1")
PG("=== (3) lag1 PIT === cand=%.2f  lag1=%.2f (graceful if not collapsed/reversed)",cand$PORT_t,if(!is.null(lagm))lagm$PORT_t else NA)
## (4) book-marginal: C2 vs C0 at α0.5 (same recon+overlay), and vs incumbent
c0o<-metr(ov(C0,0.5,2),"C0_a0.5"); PG("=== (4) BOOK-MARGINAL (α0.5) ===")
PG("[book-marg] C2+ovl IR=%.3f vs C0+ovl IR=%.3f ΔIR=%.3f | vs incumbent %.3f ΔIR=%.3f",cand$IR,c0o$IR,cand$IR-c0o$IR,INCUMBENT_IR,cand$IR-INCUMBENT_IR)
saveRDS(list(rob=robdt,cand=cand,placebo=plc,lag1=lagm,c0=c0o),file.path(WD,"cycle9_verify.rds"))
fwrite(robdt,file.path(WD,"cycle9_robust_results.csv"))
PG("[VERDICT] milestone-candidate survives if: align-robust pass_all majority ∧ placebo p<0.05 ∧ lag1 graceful ∧ ΔIR_vs_C0>0")
