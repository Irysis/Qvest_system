## run_fof_round4.R — IC-가중(C2) + regime-gate (post-2017 감쇠 회복 시도, prior 낮음)
## C2 IC-가중 period_returns에 PIT regime exposure w_t 적용(디리스크=cash). 게이트가 2018+ port_t를 양수로?
## 게이트(전부 trailing PIT): 시장추세(trailing12m bench)·시장변동성(trailing6m bench vol)·전략-드로다운(trailing6m 전략 active).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(xts); library(PerformanceAnalytics)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_round4.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ Round 4 — IC-가중 + regime-gate ================"); w(sprintf("실행 %s",as.character(Sys.time())))

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
pr[,bm:=benchmark_ret]; pr[,r:=ret_net]; pr[,act:=r-bm]
n<-nrow(pr)

## PIT trailing 신호 (t시점 = t-1까지 사용)
pr[, bm_tr12 := shift(frollsum(bm,12L),1L)]                 # trailing 12m 시장수익(부호)
pr[, bm_vol6 := shift(frollapply(bm,6L,sd),1L)]            # trailing 6m 시장변동성
vol_med<-median(pr$bm_vol6,na.rm=T)
pr[, strat_tr6 := shift(frollsum(act,6L),1L)]              # trailing 6m 전략 active

## 게이트 → exposure w_t ∈ [0,1]. 결측(워밍업)=1(full).
gates<-list(
  G0_none      = function(p) rep(1,nrow(p)),
  G1_bear_cash = function(p){ w<-ifelse(is.na(p$bm_tr12),1, ifelse(p$bm_tr12<0,0.0,1.0)); w },
  G2_bear_half = function(p){ w<-ifelse(is.na(p$bm_tr12),1, ifelse(p$bm_tr12<0,0.5,1.0)); w },
  G3_highvol   = function(p){ w<-ifelse(is.na(p$bm_vol6),1, ifelse(p$bm_vol6>vol_med,0.5,1.0)); w },
  G4_stratDD   = function(p){ w<-ifelse(is.na(p$strat_tr6),1, ifelse(p$strat_tr6<0,0.5,1.0)); w }
)
pt_on<-function(act_vec, dates, from=NULL){ d<-data.table(date=dates,a=act_vec); if(!is.null(from)) d<-d[date>=as.Date(from)]
  if(nrow(d)<12) return(NA_real_); f<-lm(a~1,data=d); as.numeric(coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }
metr<-function(rg){ # gated portfolio return = w*r + (1-w)*0 ; active = gated_port - bm
  gp<-rg*pr$r; ga<-gp - pr$bm
  full<-pt_on(ga,pr$date); y18<-pt_on(ga,pr$date,"2018-01-01"); y20<-pt_on(ga,pr$date,"2020-01-01")
  mdd<-as.numeric(maxDrawdown(xts(gp,pr$date))); cagr<-prod(1+gp)^(12/length(gp))-1; cal<-if(mdd>0) cagr/mdd else NA
  sr<-mean(ga)/sd(ga)*sqrt(12)
  list(full=full,y18=y18,y20=y20,calmar=cal,mdd=mdd,sr=sr) }

w("\n=== gate별 (gated active port_t / calmar) ===")
tab<-data.table()
for(nm in names(gates)){ rg<-gates[[nm]](pr); m<-metr(rg)
  tab<-rbind(tab,data.table(gate=nm,full=m$full,y2018p=m$y18,y2020p=m$y20,calmar=m$calmar,mdd=m$mdd,net_SR=m$sr,avg_expo=round(mean(rg),2)))
  w(sprintf("  [%-12s] full=%+.2f | 2018+=%+.2f | 2020+=%+.2f | calmar=%.2f | MDD=%.1f%% | SR=%+.3f | avg_expo=%.2f",
    nm,m$full,m$y18,m$y20,m$calmar,100*m$mdd,m$sr,mean(rg))) }
w("\n  → 게이트가 2018+ port_t를 양수(>1)로 만드는가? (못 만들면 = 손실회피만, 알파추가 X = 감쇠 회복불가)")
fwrite(tab,file.path(OUT,"round4_results.csv"))
cat("ROUND4|", paste(sprintf("%s:full%.2f/18p%.2f/cal%.2f",tab$gate,tab$full,tab$y2018p,tab$calmar),collapse=" "),"\n")
close(con); cat("FOF_ROUND4_DONE\n")
