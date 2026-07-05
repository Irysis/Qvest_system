## 사이클 11 — 20% 캡 해제 테스트 (도훈 지시) · forge-fidelity carrier.
## ⚠ OUT-OF-ENVELOPE: 20% 캡은 production 제약. 이건 탐색 테스트지 현 제약 하 배포 마일스톤 아님(정직 라벨).
## 앵커(top-K by size)를 20%↑(0.25/0.30/0.35/벤치cap)로 풀어 벤치 mega-cap 추종 강화 시 벽/게이트 반응.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1); PG <- function(...) message(sprintf(...))
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; WD<-file.path(ROOT,"stage_artifacts/pg2_overlay_gate_composition_20260705")
PD<-file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R")); COST<-0.0015
car<-as.data.table(read_parquet(file.path(ROOT,"06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")))
car[, dd:=as.Date(decision_date)]
pm<-as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[,Date:=as.Date(Date)]
car<-merge(car, pm[,.(Date,Ticker,size)], by.x=c("dd","Ticker"), by.y=c("Date","Ticker"), all.x=TRUE)
## anchor override: top-K by size -> anch_w each (uncapped >0.20 allowed), rescale rest to (1-K*anch_w).
## anch_w=NA => cap-weight to benchmark (proportional to size among anchors, total = benchmark top-K share proxy=0.45)
build_anchor<-function(K, anch_w){
  x<-copy(car)[!is.na(ret_fwd)&!is.na(weight_strategy)&!is.na(size)]
  x[order(-size), is_anchor:=(seq_len(.N)<=K), by=dd]
  x[, resid:=sum(weight_strategy[!is_anchor]), by=dd]
  if(is.na(anch_w)){ x[, atot:=sum(size[is_anchor]),by=dd]; x[is_anchor==TRUE, w_new:=size/atot*0.45]; x[, aw:=sum(w_new[is_anchor]),by=dd]
    x[is_anchor==FALSE, w_new:=weight_strategy/resid*(1-aw)] }
  else { x[, w_new:=weight_strategy]; x[is_anchor==TRUE, w_new:=anch_w]; x[is_anchor==FALSE, w_new:=weight_strategy/resid*(1-K*anch_w)] }
  x[, maxw:=max(w_new,na.rm=TRUE), by=dd]
  list(ret=x[, .(ret=sum(w_new*ret_fwd,na.rm=TRUE)), by=dd], maxw=mean(x$maxw,na.rm=TRUE))
}
base<-car[, .(ret=sum(weight_strategy*ret_fwd,na.rm=TRUE), sw=sum(weight_strategy,na.rm=TRUE)), by=dd][sw>0.5]
bt<-readRDS(file.path(PD,"04_backtest_results/bt_result_layer5_R05.rds")); prr<-as.data.table(bt$period_returns)
prr[,e:=ret_L5_V5/ret_orig]; prr[!is.finite(e)|abs(ret_orig)<0.003,e:=NA_real_]; prr[,e:=nafill(nafill(e,"locf"),"nocb")]; prr[e<0,e:=0]; prr[e>1.2,e:=1.2]
prr[, ym_key:=ifelse(grepl("-",as.character(realized_ym)), as.character(realized_ym), format(as.Date(paste0(substr(realized_ym,1,4),"-",substr(realized_ym,5,6),"-01")),"%Y-%m"))]
bm<-as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[,Date:=as.Date(Date)]; bm<-bm[is.finite(BM_Ret)]; bm[,ym:=format(Date,"%Y-%m")]; bmm<-bm[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
bo<-0;bc<--2;for(o in -1:3){t<-copy(base);t[,k:=format(as.Date(paste0(format(dd,"%Y-%m"),"-01"))%m+%months(o),"%Y-%m")];mm<-merge(t,bmm[,.(k=ym,bm_ret)],by="k");if(nrow(mm)>50){cc<-cor(mm$ret,mm$bm_ret);if(cc>bc){bc<-cc;bo<-o}}}
metr<-function(bk, tag, alpha_ov=0, maxw=NA){ b<-copy(bk); b[,ym:=format(dd,"%Y-%m")]
  b[,kk:=format(as.Date(paste0(ym,"-01"))%m+%months(bo),"%Y-%m")]; b<-merge(b,bmm[,.(kk=ym,BM_Ret=bm_ret)],by="kk")
  if(alpha_ov>0){ b[,ke:=format(as.Date(paste0(ym,"-01"))%m+%months(1),"%Y-%m")]; b<-merge(b,prr[,.(ke=ym_key,e)],by="ke",all.x=TRUE); b[is.na(e),e:=1]; b[,ret:=ret*(1-alpha_ov*(1-e))] }
  if(nrow(b)<50)return(NULL); setorder(b,dd)
  prt<-data.table(date=b$dd,ret_net=b$ret,frequency="monthly"); brt<-data.table(date=b$dd,benchmark_ret=b$BM_Ret,benchmark_id="K200")
  bcp<-build_benchmark_compare(prt,brt,tag,tag,annualization_factor=12); gv<-function(n){v<-bcp[metric_name==n,active_value];if(length(v))as.numeric(v[1])else NA_real_}
  act<-b$ret-b$BM_Ret;n<-nrow(b);oos<-median(sapply(c(.55,.65,.75),function(q){ct<-floor(n*q);(mean(act[(ct+1):n])/sd(act[(ct+1):n]))/(mean(act[1:ct])/sd(act[1:ct]))}),na.rm=T)
  rx<-xts(b$ret,order.by=b$dd);cg<-as.numeric(Return.annualized(rx,scale=12));md<-as.numeric(maxDrawdown(rx))
  data.table(tag=tag,max_wt=round(maxw,3),PORT_t=gv("Portfolio_Alpha_t_NW_lag3"),IR=gv("Information_Ratio"),oos_ret=oos,cagr=cg,mdd=md,calmar=if(md>0)cg/md else NA_real_) }
rows<-list()
rows[[1]]<-metr(base,"BASE_prod(cap0.20)",0,0.20); rows[[2]]<-metr(base,"BASE_prod+ovl0.5",0.5,0.20)
for(aw in c(0.20,0.25,0.30,0.35)){ a<-build_anchor(2,aw)
  rows[[length(rows)+1]]<-metr(a$ret,sprintf("A2_w%.2f_noOvl",aw),0,a$maxw)
  rows[[length(rows)+1]]<-metr(a$ret,sprintf("A2_w%.2f_ovl0.5",aw),0.5,a$maxw) }
ac<-build_anchor(2,NA); rows[[length(rows)+1]]<-metr(ac$ret,"A2_benchCap_ovl0.5",0.5,ac$maxw)
res<-rbindlist(rows,fill=TRUE)
base_ir_ovl<-res[tag=="BASE_prod+ovl0.5",IR]
res[, dIR_vs_base:=IR-base_ir_ovl]
res[, pass_all:=is.finite(PORT_t)&PORT_t>=2.95&is.finite(oos_ret)&oos_ret>=0.7&is.finite(calmar)&calmar>=0.64]
print(res[,.(tag,max_wt,PORT_t=round(PORT_t,2),IR=round(IR,3),oos_ret=round(oos_ret,3),calmar=round(calmar,3),mdd=round(mdd,3),dIR_vs_base=round(dIR_vs_base,3),pass_all)])
PG("[CAP-RELAX] 캡 해제(anchor>0.20)가 oos/PORT_t/book-marginal 개선하는가 — dIR_vs_base(동일 ovl0.5) 및 pass_all 확인")
PG("[⚠ENVELOPE] anchor>0.20 = out-of-envelope(production [0,0.20] 위반). 개선 있어도 현 제약 하 배포 불가 — 제약 방화벽(INV-7).")
fwrite(res,file.path(WD,"cycle11_cap_relax_results.csv"))
