## 사이클 8 — 앵커 C2 오버레이-강도 sweep: 3게이트 동시통과 config 존재하는가 (앵커 스레드 결정)
## C2 no-overlay: PORT_t 4.53 calmar 0.58 / C2 full-overlay(V5): PORT_t 2.90 calmar 0.91.
## 부분 오버레이 e_a = 1 - a*(1-e_full) (a=오버레이 강도). a↑ → calmar↑ PORT_t↓. sweet spot?
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1); PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; WD <- file.path(ROOT,"stage_artifacts/pg2_overlay_gate_composition_20260705")
PD <- file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R")); source(file.path(ROOT,"02_Infrastructure/portfolio/strategy_tilt_weights.R"))
COST<-0.0015
bt<-readRDS(file.path(PD,"04_backtest_results/bt_result_layer5_R05.rds")); pr<-as.data.table(bt$period_returns); pr[,ym:=as.character(realized_ym)]
pr[, e := ret_L5_V5/ret_orig]; pr[!is.finite(e)|abs(ret_orig)<0.003, e:=NA_real_]; pr[, e:=nafill(nafill(e,"locf"),"nocb")]; pr[e<0,e:=0]; pr[e>1.2,e:=1.2]
sp<-as.data.table(read_parquet(file.path(PD,"02_holdings_universe/alpha_scores_r05_panel.parquet"))); sp[,Date:=as.Date(Date)]
pm<-as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[,Date:=as.Date(Date)]; sp<-merge(sp,pm,by=c("Date","Ticker"),all.x=TRUE); dts<-sort(unique(sp$Date))
bm<-as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[,Date:=as.Date(Date)]; bm<-bm[is.finite(BM_Ret)]; bm[,ym:=format(Date,"%Y-%m")]; bmm<-bm[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
ew<-sp[is.finite(Ret_1m),.(ew=mean(Ret_1m)),by=Date]; ew[,ym:=format(Date,"%Y-%m")]
bo<-0; bc<--2; for(o in -1:3){e2<-copy(ew); e2[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(o),"%Y-%m")]; mm<-merge(e2,bmm[,.(k=ym,bm_ret)],by="k"); if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret); if(cc>bc){bc<-cc;bo<-o}}}
ew[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(bo),"%Y-%m")]; bench<-merge(ew[,.(Date,k)],bmm[,.(k=ym,BM_Ret=bm_ret)],by="k")[,.(Date,BM_Ret)]
build_raw<-function(K,aw,N=20L){prevfill<-NULL;prevtk<-NULL;prevw<-NULL;out<-data.table(Date=dts,ret=NA_real_)
  for(i in seq_along(dts)){D<-dts[i];m<-sp[Date==D&is.finite(score_eff)&is.finite(Ret_1m)&is.finite(size)];if(nrow(m)<N)next
    setorder(m,-size);anch<-if(K>0)m$Ticker[1:K]else character(0);ma<-m[!Ticker%in%anch];setorder(ma,-score_eff);nf<-N-K;sel<-ma[1:nf]
    a_t<-sel$score_eff;names(a_t)<-sel$Ticker;fw<-linear_tilt_to_penalty_qd(a_t,lambda=1.5,w_prev=prevfill,phi=3.0,lb=0,ub=0.20)
    tk<-c(anch,names(fw));w<-c(rep(aw,K),as.numeric(fw)*(1-K*aw));rr<-c(m[match(anch,Ticker),Ret_1m],sel$Ret_1m[match(names(fw),sel$Ticker)])
    if(is.null(prevw))turn<-1 else{al<-union(tk,prevtk);wc<-ifelse(al%in%tk,w[match(al,tk)],0);wc[is.na(wc)]<-0;wp<-ifelse(al%in%prevtk,prevw[match(al,prevtk)],0);wp[is.na(wp)]<-0;turn<-sum(abs(wc-wp))}
    out$ret[i]<-sum(w*rr)-turn*COST;prevfill<-fw;prevtk<-tk;prevw<-w};out[is.finite(ret)]}
C0<-build_raw(0,0);C0[,ym:=format(Date,"%Y-%m")]; ao<-0;ac<--2;for(o in 0:2){t<-copy(C0);t[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(o),"%Y-%m")];mm<-merge(t,pr[,.(k=ym,ret_orig)],by="k");if(nrow(mm)>50){cc<-cor(mm$ret,mm$ret_orig);if(cc>ac){ac<-cc;ao<-o}}}
metr<-function(bk,tag){p2<-merge(bk,bench,by="Date");if(nrow(p2)<50)return(NULL)
  prt<-data.table(date=p2$Date,ret_net=p2$ret,frequency="monthly");brt<-data.table(date=p2$Date,benchmark_ret=p2$BM_Ret,benchmark_id="K200")
  b<-build_benchmark_compare(prt,brt,tag,tag,annualization_factor=12);gv<-function(n){v<-b[metric_name==n,active_value];if(length(v))as.numeric(v[1])else NA_real_}
  act<-p2$ret-p2$BM_Ret;n<-nrow(p2);oos<-median(sapply(c(.55,.65,.75),function(q){ct<-floor(n*q);(mean(act[(ct+1):n])/sd(act[(ct+1):n]))/(mean(act[1:ct])/sd(act[1:ct]))}),na.rm=T)
  rx<-xts(p2$ret,order.by=p2$Date);cg<-as.numeric(Return.annualized(rx,scale=12));md<-as.numeric(maxDrawdown(rx))
  data.table(tag=tag,PORT_t=gv("Portfolio_Alpha_t_NW_lag3"),IR=gv("Information_Ratio"),oos_ret=oos,cagr=cg,mdd=md,calmar=if(md>0)cg/md else NA_real_)}
ov<-function(bk,a){bk<-copy(bk);bk[,ym:=format(Date,"%Y-%m")];bk[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(ao),"%Y-%m")];bk<-merge(bk,pr[,.(k=ym,e)],by="k",all.x=TRUE);bk[is.na(e),e:=1];bk[,ea:=1-a*(1-e)];bk[,ret:=ret*ea];bk[,.(Date,ret)]}
C2<-build_raw(2,0.20)
res<-rbindlist(lapply(c(0,0.25,0.4,0.5,0.6,0.75,1.0),function(a) metr(ov(C2,a),sprintf("C2_ovl_a%.2f",a))),fill=TRUE)
res[,pass_all:=is.finite(PORT_t)&PORT_t>=2.95&is.finite(oos_ret)&oos_ret>=0.7&is.finite(calmar)&calmar>=0.64]
PG("[align] C0 vs ret_orig offset=%d cor=%.3f (cycle7 정렬 재확인)",ao,ac)
print(res[,.(tag,PORT_t=round(PORT_t,2),oos_ret=round(oos_ret,3),calmar=round(calmar,3),mdd=round(mdd,3),pass_all)])
np<-sum(res$pass_all,na.rm=T); PG("[RESULT] 3-게이트 동시통과 오버레이-강도 config: %d",np)
if(np>0){b<-res[pass_all==TRUE][which.max(PORT_t)];PG("[MILESTONE-CANDIDATE] %s PORT_t=%.2f oos=%.3f calmar=%.3f",b$tag,b$PORT_t,b$oos_ret,b$calmar)} else PG("[VERDICT] 앵커 스레드: 3-게이트 동시통과 config 부재 (오버레이 전 강도서) — sub-capital-grade")
fwrite(res,file.path(WD,"cycle8_overlay_strength_results.csv"))
