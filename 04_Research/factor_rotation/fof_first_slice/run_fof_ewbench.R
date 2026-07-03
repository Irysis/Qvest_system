## run_fof_ewbench.R — 감쇠 메커니즘 결정 확인: cap-weight 지수 vs EW 유니버스 벤치
## 가설: post-2017 감쇠 = long-only 25종이 메가캡-집중 cap-weight 지수를 못 따라감.
## 검정: IC-가중 팩터북의 active를 (a)cap-weight BM (b)EW 유니버스(mean 전종목) 두 벤치로 측정. EW에서 post양수면 = 벤치집중 확정.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_ewbench.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 감쇠 확인: cap-weight vs EW 벤치 ================"); w(sprintf("실행 %s",as.character(Sys.time())))

sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]; bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]; liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
FIC[,tt:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]; tic<-FIC[,.(signal_date=Date,factor_id,tic=tt)]
x<-merge(sc,tic,by=c("signal_date","factor_id")); x<-x[is.finite(tic)]; x[,wf:=pmax(tic,0)]
s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; s[,score:=zc(score),by=signal_date]
cs<-canonical_screen_bt(scores_dt=s[,.(Date=as.Date(signal_date),Ticker=security_id,score)],returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id="C2",strategy_id="C2")
pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; setorder(pr,date)

## EW 유니버스 벤치 = 유동(adv≥2e8) 종목 mean Ret (지수 구성에 맞춰 유동필터)
liq_ok<-liq_dt[adv>=2e8,.(Date,Ticker)]
rl<-merge(ret_dt, liq_ok, by=c("Date","Ticker"))
ewb<-rl[,.(ew=mean(Ret_1m,na.rm=TRUE)),by=.(date=Date)]
pr<-merge(pr, ewb, by="date")
pr[, act_cap := ret_net - benchmark_ret]   # vs cap-weight 지수
pr[, act_ew  := ret_net - ew]              # vs EW 유니버스

ptv<-function(v,d,from=NULL,to=NULL){ dd<-data.table(date=d,a=v); if(!is.null(from)) dd<-dd[date>=as.Date(from)]; if(!is.null(to)) dd<-dd[date<as.Date(to)]
  if(nrow(dd)<12) return(NA); f<-lm(a~1,data=dd); as.numeric(coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }
sr<-function(v) mean(v,na.rm=T)/sd(v,na.rm=T)*sqrt(12)
w("\n=== IC-가중 팩터북 — 두 벤치 대비 (port_t / 월평균 active%) ===")
for(lab in c("cap","ew")){ a<-pr[[paste0("act_",lab)]]
  w(sprintf("  vs %s-benchmark:  full t=%+.2f (%.2f%%/월) | pre2018 t=%+.2f (%.2f%%) | 2018+ t=%+.2f (%.2f%%)",
    ifelse(lab=="cap","cap-weight지수","EW유니버스"),
    ptv(a,pr$date), 100*mean(a,na.rm=T),
    ptv(a,pr$date,to="2018-01-01"), 100*mean(a[pr$date<as.Date("2018-01-01")],na.rm=T),
    ptv(a,pr$date,from="2018-01-01"), 100*mean(a[pr$date>=as.Date("2018-01-01")],na.rm=T))) }
w(sprintf("\n  net_SR(IR) vs cap=%.3f | vs EW=%.3f", sr(pr$act_cap), sr(pr$act_ew)))
w("\n  → EW유니버스 대비 2018+ port_t 양수면: 감쇠=cap-weight 메가캡 벤치 구조 (팩터선택은 살아있음).")
cat(sprintf("EWBENCH| cap_full=%.2f cap_18p=%.2f | ew_full=%.2f ew_pre=%.2f ew_18p=%.2f\n",
  ptv(pr$act_cap,pr$date), ptv(pr$act_cap,pr$date,from="2018-01-01"),
  ptv(pr$act_ew,pr$date), ptv(pr$act_ew,pr$date,to="2018-01-01"), ptv(pr$act_ew,pr$date,from="2018-01-01")))
fwrite(pr[,.(date,ret_net,benchmark_ret,ew,act_cap,act_ew)], file.path(OUT,"ewbench_monthly.csv"))
close(con); cat("FOF_EWBENCH_DONE\n")
