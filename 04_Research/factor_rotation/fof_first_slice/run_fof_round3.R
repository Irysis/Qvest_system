## run_fof_round3.R — OOS 음수 진단(decay 일반성) + decay-robust 구성 (Round2: IC-가중 full 2.65이나 OOS 음수)
## 진단: 여러 구성의 full/pre2018/2018+/2020+ port_t → decay가 IC-특이 overfit인가 전-구성 일반인가.
## decay-robust: shrunk-IC(EW 블렌드)·EWMA단기·momentum+consensus-only IC가중.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_round3.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
fam_of<-function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="M"&&p!="MA")"Momentum" else if(p1=="C"&&p!="CR")"Consensus" else "Other" }
w("================ Round 3 — decay 진단 + decay-robust ================"); w(sprintf("실행 %s",as.character(Sys.time())))

sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; sc[, mgrp:=sapply(factor_id,fam_of)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
ewma<-function(x,span){ a<-2/(span+1); y<-x; y[1]<-ifelse(is.na(x[1]),0,x[1]); for(i in 2:length(x)){xi<-ifelse(is.na(x[i]),y[i-1],x[i]); y[i]<-a*xi+(1-a)*y[i-1]}; y }
make_tic<-function(L,mode="lin"){ if(mode=="ewma") FIC[,tt:=shift(ewma(ic,L),1L),by=factor_id] else FIC[,tt:=shift(frollmean(ic,L,na.rm=TRUE),1L),by=factor_id]; FIC[,.(signal_date=Date,factor_id,tic=tt)] }
run_sc<-function(sdt,id,topn=25L) canonical_screen_bt(scores_dt=sdt[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
  returns_dt=ret_dt,bench_dt=bench_dt,top_n=topn,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id=id,strategy_id=id)
ptsub<-function(cs,from=NULL,to=NULL){ pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  if(!is.null(from)) pr<-pr[date>=as.Date(from)]; if(!is.null(to)) pr<-pr[date<as.Date(to)]
  if(nrow(pr)<12) return(NA_real_); v<-pr$ret_net-pr$benchmark_ret; f<-lm(v~1); as.numeric(coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }

## 구성 builders
b_group_avg<-function(){ g<-sc[,.(gz=mean(nz,na.rm=T)),by=.(signal_date,security_id,factor_id)] # not used directly
  g<-sc[,.(gz=mean(nz,na.rm=T)),by=.(signal_date,security_id)]; g[,.(signal_date,security_id,score=gz)] }
icw<-function(tic, sub=NULL, shrink=0){ x<-merge(sc,tic,by=c("signal_date","factor_id")); x<-x[is.finite(tic)]
  if(!is.null(sub)) x<-x[mgrp%in%sub]; x[,wf:=pmax(tic,0)]
  if(shrink>0){ x[, wf:=wf + shrink*mean(wf,na.rm=T), by=signal_date] }   # EW 쪽으로 shrink
  s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; s[,score:=zc(score),by=signal_date]; s }

tic12<-make_tic(12,"lin"); tic6<-make_tic(6,"lin"); ewma3<-make_tic(3,"ewma")
CFG<-list(
  C1_group_avg = b_group_avg(),
  C2_icw_L12   = icw(tic12),
  C2s_shrink1  = icw(tic12, shrink=1.0),     # IC-가중을 EW쪽 50% shrink
  C2s_shrink3  = icw(tic12, shrink=3.0),     # 강한 shrink(거의 EW)
  C2e_ewma3    = icw(ewma3),                 # 빠른 적응
  C2m_momcons  = icw(tic12, sub=c("Momentum","Consensus"))  # 생존 팩터군만 IC-가중
)
w("\n=== full / pre-2018 / 2018+ / 2020+ port_t (decay 진단) ===")
tab<-data.table()
for(nm in names(CFG)){ s<-copy(CFG[[nm]]); s[,score:=zc(score),by=signal_date]; cs<-run_sc(s,nm)
  pf<-cs$portfolio_alpha_t_nw_lag3; p_pre<-ptsub(cs,to="2018-01-01"); p18<-ptsub(cs,from="2018-01-01"); p20<-ptsub(cs,from="2020-01-01")
  tab<-rbind(tab,data.table(config=nm,full=pf,pre2018=p_pre,y2018p=p18,y2020p=p20,net_SR=cs$net_sr))
  w(sprintf("  [%-13s] full=%+.2f | pre2018=%+.2f | 2018+=%+.2f | 2020+=%+.2f | net_SR=%+.3f",
    nm,pf,p_pre,p18,p20,cs$net_sr)) }
w("\n=== 해석 ===")
w("  pre2018>>2018+ 이면 = 일반 시간감쇠(전 구성). 2018+에 양수 구성 있으면 decay-robust 후보.")
fwrite(tab,file.path(OUT,"round3_results.csv")); saveRDS(tab,file.path(OUT,"_fof_round3.rds"))
cat("ROUND3|", paste(sprintf("%s:full%.2f/pre%.2f/18p%.2f/20p%.2f", tab$config,tab$full,tab$pre2018,tab$y2018p,tab$y2020p),collapse=" "),"\n")
close(con); cat("FOF_ROUND3_DONE\n")
