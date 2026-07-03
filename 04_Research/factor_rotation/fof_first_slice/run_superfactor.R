## run_superfactor.R — 정의적 슈퍼팩터(373 정제+결합) 계약-등급 검증 (proxy → canonical_confirm)
## 슈퍼팩터 = FWL 316 IC-가중 결합 = S-base. canonical_screen_bt(계약등급) + placebo + DSR + holdout.
## 에이전트 지적: 지금까지 全 proxy(Σw·r). 이게 계약등급서도 gate 통과? proxy 과대계상 여부 판정.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_superfactor.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("======== 정의적 슈퍼팩터 — 계약등급 검증 ========"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date); FIC[,tw:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]
## 슈퍼팩터 score (FWL 316 IC-가중)
mk_super<-function(fset=NULL){ x<-sc[,.(date,tic,factor_id,nz)]; if(!is.null(fset)) x<-x[factor_id %in% fset]
  x<-merge(x, FIC[,.(date=Date,factor_id,tw)], by=c("date","factor_id")); x<-x[is.finite(tw)]; x[,wf:=pmax(tw,0)]
  s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(date,tic)]; s[,score:=zc(score),by=date]; s[,.(Date=date,Ticker=tic,score)] }
supr<-mk_super()
## ── 계약등급 canonical_screen_bt (top-25 EW long-only, 15bps delta, liq 2e8, NW lag-3) ──
cs<-canonical_screen_bt(scores_dt=supr, returns_dt=ret_dt, bench_dt=bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8, run_id="SUPER", strategy_id="SUPER")
pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; setorder(pr,date)
port_t_full<-cs$portfolio_alpha_t_nw_lag3; net_sr<-cs$net_sr
p18<-{a<-pr[date>=as.Date("2018-01-01")]; v<-a$ret_net-a$benchmark_ret; f<-lm(v~1); as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
w(sprintf("\n=== 계약등급 (canonical_screen_bt, top-25 EW) ===\n  portfolio_alpha_t_nw_lag3(full)=%+.2f | 2018+=%+.2f | net_SR=%.2f",port_t_full,p18,net_sr))
w(sprintf("  (참조: 내 proxy seasoned+tilt evalS는 3.57 — 계약등급 EW와 비교해 proxy 과대계상 여부 판정)"))
## ── holdout: 마지막 20% 봉인 검정 ──
n<-nrow(pr); ho<-pr[floor(n*0.8):n]; isv<-pr[1:floor(n*0.8)]
sr<-function(a) mean(a)/sd(a)*sqrt(12)
w(sprintf("\n=== holdout (마지막 20%%) ===\n  IS active SR=%.2f | holdout active SR=%.2f | retention=%.2f",
  sr(isv$ret_net-isv$benchmark_ret), sr(ho$ret_net-ho$benchmark_ret), sr(ho$ret_net-ho$benchmark_ret)/sr(isv$ret_net-isv$benchmark_ret)))
## ── placebo: 랜덤 동일크기 팩터셋 슈퍼팩터 (계약등급 port_t) ──
facs<-unique(sc$factor_id); set.seed(11); pl<-c()
for(i in 1:60){ fs<-sample(facs, length(facs)); # 전체 랜덤가중이 아니라 랜덤 IC부호로 교란
  sp<-mk_super(sample(facs, as.integer(length(facs)*0.5)))
  csp<-tryCatch(canonical_screen_bt(scores_dt=sp,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id="pl",strategy_id="pl"),error=function(e) NULL)
  if(!is.null(csp)) pl<-c(pl, csp$portfolio_alpha_t_nw_lag3) }
w(sprintf("\n=== placebo (랜덤 50%% 팩터 슈퍼팩터 x%d, 계약등급 port_t) ===\n  슈퍼팩터 %.2f vs 랜덤 %.1f%%ile (mean %.2f, p95 %.2f)",
  length(pl), port_t_full, 100*mean(pl<port_t_full), mean(pl), quantile(pl,0.95)))
w(sprintf("\n  ★판정: 계약등급 port_t=%+.2f (gate 2.95). holdout retention. placebo %%ile. — proxy 3.57 대비 얼마나 유지되나.",port_t_full))
cat(sprintf("SUPER| contract_port_t=%.2f p18=%.2f net_SR=%.2f placebo_pctile=%.0f\n",port_t_full,p18,net_sr,100*mean(pl<port_t_full)))
close(con); cat("SUPERFACTOR_DONE\n")
