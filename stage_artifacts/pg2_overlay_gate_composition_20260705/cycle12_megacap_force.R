## 사이클 12 — 진짜 mega-cap 강제편입 앵커 + 캡 sweep (사용자 질문 definitive)
## 수정: 앞선 앵커는 "selected 중 top-2 size"(삼성 28%월만) = 벤치 mega-cap 앵커 아니었음.
## 여기: 전 유니버스 top-2-by-cap(삼성/하이닉스 PIT)을 미선택 월도 강제편입, 캡{0.20,0.25,0.30} sweep.
## ⚠ anch_w>0.20 = out-of-envelope(도훈 지시 탐색). fidelity: BASE가 carrier baseline(6.69) 재현하는지.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1); PG <- function(...) message(sprintf(...))
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; WD<-file.path(ROOT,"stage_artifacts/pg2_overlay_gate_composition_20260705")
PD<-file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
raw<-as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT-D20260705_005/rawdata_monthend_slim.parquet")))
raw[, Date:=as.Date(Date)]; setorder(raw, Ticker, Date); raw[, fwd_ret:=shift(Ret,-1), by=Ticker]
raw[, ym:=format(Date,"%Y-%m")]; raw[, univ:=(K200==1 | KQ150==1)]
car<-as.data.table(read_parquet(file.path(ROOT,"06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")))
car[, ym:=format(as.Date(decision_date),"%Y-%m")]
yms<-sort(intersect(unique(car$ym), unique(raw[univ==TRUE & is.finite(fwd_ret)]$ym)))
build<-function(anch_w, K){ out<-data.table(ym=yms, ret=NA_real_, maxw=NA_real_)
  for(i in seq_along(yms)){ Y<-yms[i]
    rr<-raw[ym==Y & univ==TRUE & is.finite(Size) & is.finite(fwd_ret)]; if(nrow(rr)<20) next
    setorder(rr,-Size); anch<-if(K>0) rr$Ticker[1:K] else character(0)
    cw<-car[ym==Y]; setorder(cw,-weight_strategy); fill<-cw[!Ticker%in%anch][1:(20-K)]
    fr<-raw[ym==Y][match(fill$Ticker,Ticker), fwd_ret]; ar<-rr[match(anch,Ticker),fwd_ret]
    wf<-fill$weight_strategy/sum(fill$weight_strategy,na.rm=T)*(1-K*anch_w); wa<-rep(anch_w,K)
    ret<-sum(wa*ar,na.rm=T)+sum(wf*fr,na.rm=T); out$ret[i]<-ret; out$maxw[i]<-max(c(wa,wf),na.rm=T) }
  out[is.finite(ret)] }
## benchmark (monthly BM_Ret from raw)
bmm<-raw[univ==TRUE, .(BM_Ret=BM_Ret[1]), by=ym]  # BM_Ret same across tickers per month
## overlay exposure
bt<-readRDS(file.path(PD,"04_backtest_results/bt_result_layer5_R05.rds")); prr<-as.data.table(bt$period_returns)
prr[,e:=ret_L5_V5/ret_orig]; prr[!is.finite(e)|abs(ret_orig)<0.003,e:=NA_real_]; prr[,e:=nafill(nafill(e,"locf"),"nocb")]; prr[e<0,e:=0]; prr[e>1.2,e:=1.2]
prr[, ymk:=ifelse(grepl("-",as.character(realized_ym)),as.character(realized_ym),format(as.Date(paste0(substr(realized_ym,1,4),"-",substr(realized_ym,5,6),"-01")),"%Y-%m"))]
metr<-function(bk,tag,alpha_ov=0,maxw=NA){ b<-merge(bk,bmm,by="ym"); if(nrow(b)<50)return(NULL)
  b[, dt:=as.Date(paste0(ym,"-01"))]; setorder(b,dt)
  if(alpha_ov>0){ b[, ke:=format(dt%m+%months(1),"%Y-%m")]; b<-merge(b,prr[,.(ke=ymk,e)],by="ke",all.x=TRUE); b[is.na(e),e:=1]; b[,ret:=ret*(1-alpha_ov*(1-e))]; setorder(b,dt) }
  prt<-data.table(date=b$dt,ret_net=b$ret,frequency="monthly"); brt<-data.table(date=b$dt,benchmark_ret=b$BM_Ret,benchmark_id="K200")
  bcp<-build_benchmark_compare(prt,brt,tag,tag,annualization_factor=12); gv<-function(n){v<-bcp[metric_name==n,active_value];if(length(v))as.numeric(v[1])else NA_real_}
  act<-b$ret-b$BM_Ret;n<-nrow(b);oos<-median(sapply(c(.55,.65,.75),function(q){ct<-floor(n*q);(mean(act[(ct+1):n])/sd(act[(ct+1):n]))/(mean(act[1:ct])/sd(act[1:ct]))}),na.rm=T)
  p2<-b[dt>=as.Date("2017-01-01")];a2<-p2$ret-p2$BM_Ret;m2<-mean(a2);dm<-a2-m2;nn<-length(a2);g0<-sum(dm^2)/nn;gs<-0;for(L in 1:3){wt<-1-L/4;gs<-gs+2*wt*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn};p17<-m2/sqrt((g0+gs)/nn)
  rx<-xts(b$ret,order.by=b$dt);cg<-as.numeric(Return.annualized(rx,scale=12));md<-as.numeric(maxDrawdown(rx))
  data.table(tag=tag,n=n,max_wt=round(maxw,3),PORT_t=gv("Portfolio_Alpha_t_NW_lag3"),IR=gv("Information_Ratio"),oos=oos,post17=p17,calmar=if(md>0)cg/md else NA,mdd=md) }
B0<-build(0,0)  # fidelity: earnings top-20, no anchor
rows<-list(metr(B0,"FIDELITY_base(noanchor)"))
for(aw in c(0.20,0.25,0.30)){ bb<-build(aw,2); mw<-mean(bb$maxw,na.rm=T)
  rows[[length(rows)+1]]<-metr(bb,sprintf("MEGACAP2_w%.2f_noOvl",aw),0,mw)
  rows[[length(rows)+1]]<-metr(bb,sprintf("MEGACAP2_w%.2f_ovl0.5",aw),0.5,mw) }
res<-rbindlist(rows,fill=TRUE)
b0ovl<-metr(B0,"base_ovl",0.5); base_ir<-b0ovl$IR
res[, dIR_vs_base_ovl:=IR-base_ir]
res[, pass:=is.finite(PORT_t)&PORT_t>=2.95&is.finite(oos)&oos>=0.7&is.finite(calmar)&calmar>=0.64]
print(res[,.(tag,n,max_wt,PORT_t=round(PORT_t,2),IR=round(IR,3),oos=round(oos,3),post17=round(post17,2),calmar=round(calmar,3),mdd=round(mdd,3),dIR=round(dIR_vs_base_ovl,3),pass)])
PG("[FIDELITY] base(noanchor) PORT_t=%.2f — carrier baseline 6.69과 근접해야 rawdata-forward 정렬 OK", res[1]$PORT_t)
PG("[ANSWER] 삼성/하이닉스 강제편입 캡 sweep: 20%↑가 oos/PORT_t/dIR 개선하는가? (out-of-envelope 탐색)")
fwrite(res,file.path(WD,"cycle12_megacap_force_results.csv"))
