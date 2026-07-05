## 사이클 10 — carrier 기반 forge-fidelity 측정 (재구성/정렬 모호성 제거)
## 문제: cycles7-9 오버레이가 내 LinearTilt 재구성(cor 0.84·offset2)에 의존 → alignment-fragile.
## 해법: production carrier(실제 selection+weight_strategy+ret_fwd)를 baseline으로, 앵커 override 직접 적용.
##   fidelity 체크: carrier baseline book return이 bt ret_orig과 일치(cor~1)하면 정렬 exact = forge-fidelity.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1); PG <- function(...) message(sprintf(...))
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; WD<-file.path(ROOT,"stage_artifacts/pg2_overlay_gate_composition_20260705")
PD<-file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
COST<-0.0015; INCUMBENT_IR<-1.416
car<-as.data.table(read_parquet(file.path(ROOT,"06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")))
PG("carrier cols: %s | nrow=%d", paste(names(car),collapse=","), nrow(car))
dcol<-if("decision_date"%in%names(car))"decision_date" else "eval_date"
car[, dd:=as.Date(get(dcol))]
## size for anchor
pm<-as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[,Date:=as.Date(Date)]
car<-merge(car, pm[,.(Date,Ticker,size)], by.x=c("dd","Ticker"), by.y=c("Date","Ticker"), all.x=TRUE)
## baseline book (production weights) monthly return
base<-car[selected==TRUE | is.na(selected), .(ret=sum(weight_strategy*ret_fwd, na.rm=TRUE), sw=sum(weight_strategy,na.rm=TRUE)), by=dd]
base<-base[sw>0.5]  # valid months
## anchor override: top-K by size -> anch_w each, rescale rest of weight_strategy to (1-K*anch_w)
build_anchor<-function(K, anch_w){
  x<-copy(car)[!is.na(ret_fwd) & !is.na(weight_strategy)]
  x[, is_anchor:=FALSE]
  x[order(-size), is_anchor:=(seq_len(.N)<=K), by=dd]
  x[, w_new:=weight_strategy]
  x[, resid:=sum(weight_strategy[!is_anchor]), by=dd]
  x[is_anchor==TRUE, w_new:=anch_w]
  x[is_anchor==FALSE, w_new:=weight_strategy/resid*(1-K*anch_w)]
  x[, .(ret=sum(w_new*ret_fwd, na.rm=TRUE)), by=dd]
}
## overlay exposure from bt (aligned by realized month = dd exact since same book)
bt<-readRDS(file.path(PD,"04_backtest_results/bt_result_layer5_R05.rds")); prr<-as.data.table(bt$period_returns)
prr[,e:=ret_L5_V5/ret_orig]; prr[!is.finite(e)|abs(ret_orig)<0.003,e:=NA_real_]; prr[,e:=nafill(nafill(e,"locf"),"nocb")]; prr[e<0,e:=0]; prr[e>1.2,e:=1.2]
prr[, rym:=as.character(realized_ym)]
## fidelity check: carrier baseline vs bt ret_orig by matching month (try offsets)
base[, ym:=format(dd,"%Y-%m")]
prr[, ym_key:=ifelse(grepl("-",rym), rym, format(as.Date(paste0(substr(rym,1,4),"-",substr(rym,5,6),"-01")),"%Y-%m"))]
best<-list(o=NA,c=-2); for(o in -2:2){ t<-copy(base); t[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(o),"%Y-%m")]; mm<-merge(t,prr[,.(k=ym_key,ret_orig)],by="k"); if(nrow(mm)>50){cc<-cor(mm$ret,mm$ret_orig); if(cc>best$c){best$c<-cc;best$o<-o}} }
PG("[FIDELITY] carrier baseline vs bt ret_orig: best offset=%d cor=%.4f (>0.97 = forge-fidelity, 정렬 exact)", best$o, best$c)
## benchmark
bm<-as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[,Date:=as.Date(Date)]; bm<-bm[is.finite(BM_Ret)]; bm[,ym:=format(Date,"%Y-%m")]; bmm<-bm[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
bo<-0;bc<--2;for(o in -1:3){t<-copy(base);t[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(o),"%Y-%m")];mm<-merge(t,bmm[,.(k=ym,bm_ret)],by="k");if(nrow(mm)>50){cc<-cor(mm$ret,mm$bm_ret);if(cc>bc){bc<-cc;bo<-o}}}
mkbench<-function(b){ b<-copy(b); b[,ym:=format(dd,"%Y-%m")]; b[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(bo),"%Y-%m")]; merge(b,bmm[,.(k=ym,BM_Ret=bm_ret)],by="k") }
applyov<-function(b){ b<-copy(b); b[,ym:=format(dd,"%Y-%m")]; b[,k:=format(as.Date(paste0(ym,"-01"))%m+%months(best$o),"%Y-%m")]; b<-merge(b,prr[,.(k=ym_key,e)],by="k",all.x=TRUE); b[is.na(e),e:=1]; b }
metr<-function(b, tag, alpha_ov=NULL){ pb<-mkbench(b); if(!is.null(alpha_ov)){ pb<-applyov(pb); pb[,ret:=ret*(1-alpha_ov*(1-e))] }
  if(nrow(pb)<50) return(NULL); setorder(pb,dd)
  prt<-data.table(date=pb$dd,ret_net=pb$ret,frequency="monthly"); brt<-data.table(date=pb$dd,benchmark_ret=pb$BM_Ret,benchmark_id="K200")
  bcp<-build_benchmark_compare(prt,brt,tag,tag,annualization_factor=12); gv<-function(n){v<-bcp[metric_name==n,active_value];if(length(v))as.numeric(v[1])else NA_real_}
  act<-pb$ret-pb$BM_Ret;n<-nrow(pb);oos<-median(sapply(c(.55,.65,.75),function(q){ct<-floor(n*q);(mean(act[(ct+1):n])/sd(act[(ct+1):n]))/(mean(act[1:ct])/sd(act[1:ct]))}),na.rm=T)
  p2<-pb[dd>=as.Date("2017-01-01")];a2<-p2$ret-p2$BM_Ret;m2<-mean(a2);dm<-a2-m2;nn<-length(a2);g0<-sum(dm^2)/nn;gs<-0;for(L in 1:3){wt<-1-L/4;gs<-gs+2*wt*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn};p17<-m2/sqrt((g0+gs)/nn)
  rx<-xts(pb$ret,order.by=pb$dd);cg<-as.numeric(Return.annualized(rx,scale=12));md<-as.numeric(maxDrawdown(rx))
  data.table(tag=tag,n=n,PORT_t=gv("Portfolio_Alpha_t_NW_lag3"),IR=gv("Information_Ratio"),oos_ret=oos,post2017_t=p17,cagr=cg,mdd=md,calmar=if(md>0)cg/md else NA_real_) }
res<-rbindlist(list(
  metr(base,"BASE_production_noOvl"),
  metr(base,"BASE_production_fullOvl",alpha_ov=1.0),
  metr(build_anchor(2,0.20),"ANCHOR2_noOvl"),
  metr(build_anchor(2,0.20),"ANCHOR2_ovl0.5",alpha_ov=0.5),
  metr(build_anchor(2,0.20),"ANCHOR2_fullOvl",alpha_ov=1.0),
  metr(build_anchor(2,0.16),"ANCHOR2w16_ovl0.5",alpha_ov=0.5),
  metr(build_anchor(1,0.20),"ANCHOR1_ovl0.5",alpha_ov=0.5)
),fill=TRUE)
res[,pass_all:=is.finite(PORT_t)&PORT_t>=2.95&is.finite(oos_ret)&oos_ret>=0.7&is.finite(calmar)&calmar>=0.64]
print(res[,.(tag,n,PORT_t=round(PORT_t,2),IR=round(IR,3),oos_ret=round(oos_ret,3),post2017_t=round(post2017_t,2),calmar=round(calmar,3),mdd=round(mdd,3),pass_all)])
bA<-res[tag=="ANCHOR2_ovl0.5"]; bB<-res[tag=="BASE_production_fullOvl"]
PG("[BOOK-MARGINAL] anchor2_ovl0.5 IR=%.3f vs production_fullOvl IR=%.3f ΔIR=%.3f (>=0.05 admit)",bA$IR,bB$IR,bA$IR-bB$IR)
fwrite(res,file.path(WD,"cycle10_carrier_results.csv"))
PG("[VERDICT] forge-fidelity(carrier): milestone if any ANCHOR pass_all ∧ ΔIR vs production >=0.05")
