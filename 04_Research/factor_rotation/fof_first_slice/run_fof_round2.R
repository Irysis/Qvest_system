## run_fof_round2.R — IC-가중 최적화 + 졸업게이트 검증 (Round 1 C2=2.65 돌파 후)
## 그리드: IC lookback {6,12,18,24,36} × weighting {lin,ewma,sqrt} × 집중도 {25,20,15}. 핵심만 추려 측정.
## 게이트: port_t(NW lag3)≥2.95 · oos_retention(SR_oos/SR_is anchored 60/40)≥0.7 · calmar≥0.64. + PIT 토글.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(xts); library(PerformanceAnalytics)})
setDTthreads(1); try(arrow::set_io_thread_count(1), silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_round2.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ Round 2 — IC-가중 최적화 + 졸업검증 ================"); w(sprintf("실행 %s",as.character(Sys.time())))

sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds"))   # Date, factor_id, ic, (t_ic 12m)
setorder(FIC, factor_id, Date)
ewma<-function(x,span){ a<-2/(span+1); y<-x; y[1]<-ifelse(is.na(x[1]),0,x[1]); for(i in 2:length(x)){ xi<-ifelse(is.na(x[i]),y[i-1],x[i]); y[i]<-a*xi+(1-a)*y[i-1] }; y }
make_tic<-function(L, mode="lin"){
  if(mode=="ewma"){ FIC[, tt:=shift(ewma(ic, L),1L), by=factor_id] } else { FIC[, tt:=shift(frollmean(ic,L,na.rm=TRUE),1L), by=factor_id] }
  FIC[,.(signal_date=Date, factor_id, tic=tt)] }

run_sc<-function(sdt,id,topn) canonical_screen_bt(scores_dt=sdt[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
  returns_dt=ret_dt,bench_dt=bench_dt,top_n=topn,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id=id,strategy_id=id)
ic_weighted_score<-function(tic, wtfun){ x<-merge(sc, tic, by=c("signal_date","factor_id")); x<-x[is.finite(tic)]
  x[, wf:=wtfun(tic)]; s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]
  s[,score:=zc(score),by=signal_date]; s }
wt_lin<-function(t) pmax(t,0); wt_sqrt<-function(t) sqrt(pmax(t,0));

## 성과 메트릭 (period_returns 기반)
metr<-function(cs){ pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; setorder(pr,date)
  a<-pr$ret_net-pr$benchmark_ret; n<-length(a); k<-floor(0.6*n)
  sr<-function(v) if(length(v)>2 && sd(v)>0) mean(v)/sd(v)*sqrt(12) else NA
  sr_is<-sr(a[1:k]); sr_oos<-sr(a[(k+1):n]); oret<- if(!is.na(sr_is)&&sr_is>0) sr_oos/sr_is else NA
  nav<-cumprod(1+pr$ret_net); mdd<-as.numeric(maxDrawdown(xts(pr$ret_net, pr$date)))
  cagr<-prod(1+pr$ret_net)^(12/n)-1; calmar<-if(mdd>0) cagr/mdd else NA
  list(port_t=cs$portfolio_alpha_t_nw_lag3, net_SR=cs$net_sr, sr_is=sr_is, sr_oos=sr_oos, oos_ret=oret, mdd=mdd, calmar=calmar, to=cs$turnover_annual) }

## ── 그리드: lookback × weighting(lin) × topn ──
GRID<-list()
for(L in c(6,12,18,24,36)) GRID[[sprintf("L%d_lin_t25",L)]]<-list(L=L,mode="lin",wt=wt_lin,topn=25L)
GRID[["L18_ewma_t25"]]<-list(L=18,mode="ewma",wt=wt_lin,topn=25L)
GRID[["L18_sqrt_t25"]]<-list(L=18,mode="lin",wt=wt_sqrt,topn=25L)
GRID[["L18_lin_t20"]]<-list(L=18,mode="lin",wt=wt_lin,topn=20L)
GRID[["L18_lin_t15"]]<-list(L=18,mode="lin",wt=wt_lin,topn=15L)

tab<-data.table()
for(nm in names(GRID)){ g<-GRID[[nm]]; tic<-make_tic(g$L, g$mode); s<-ic_weighted_score(tic, g$wt)
  cs<-run_sc(s, nm, g$topn); m<-metr(cs)
  pass<-(!is.na(m$port_t)&&m$port_t>=2.95)+(!is.na(m$oos_ret)&&m$oos_ret>=0.7)+(!is.na(m$calmar)&&m$calmar>=0.64)
  tab<-rbind(tab, data.table(config=nm, port_t=m$port_t, net_SR=m$net_SR, oos_ret=m$oos_ret, calmar=m$calmar, mdd=m$mdd, to=round(100*m$to), gates=sprintf("%d/3",pass)))
  w(sprintf("  [%-14s] port_t=%+.2f | net_SR=%+.3f | oos_ret=%s | calmar=%s | MDD=%.1f%% | TO=%d%% | gates=%d/3",
    nm, m$port_t, m$net_SR, ifelse(is.na(m$oos_ret),"NA",sprintf("%.2f",m$oos_ret)), ifelse(is.na(m$calmar),"NA",sprintf("%.2f",m$calmar)), 100*m$mdd, round(100*m$to), pass)) }
setorder(tab,-port_t)

## ── PIT 토글: 최고 config의 t_ic를 +1 추가 shift(미래정보 더 제거) → 진짜 causal이면 비슷/약간저하, look-ahead면 급락해야 ──
bestL<-as.integer(sub("L(\\d+)_.*","\\1", tab$config[grepl("_lin_t25",tab$config)][1]))
if(is.na(bestL)) bestL<-18L
FIC[, tt:=shift(frollmean(ic,bestL,na.rm=TRUE),2L), by=factor_id]   # shift 2 (한 달 더 과거)
tic_tog<-FIC[,.(signal_date=Date,factor_id,tic=tt)]; s_tog<-ic_weighted_score(tic_tog, wt_lin)
cs_tog<-run_sc(s_tog,"pit_toggle",25L)
w(sprintf("\n=== PIT 토글 (L%d, shift+1 추가=더 과거) ===", bestL))
w(sprintf("  정상(shift1) vs 토글(shift2) port_t: 토글 port_t=%+.2f (정상 대비 급락 없으면 look-ahead 부재)", cs_tog$portfolio_alpha_t_nw_lag3))

w("\n=== 정렬 (port_t 내림차순) ===")
for(i in 1:nrow(tab)) w(sprintf("  %d. %-14s port_t=%+.2f net_SR=%+.3f oos_ret=%s calmar=%s gates=%s",
  i, tab$config[i], tab$port_t[i], tab$net_SR[i], ifelse(is.na(tab$oos_ret[i]),"NA",sprintf("%.2f",tab$oos_ret[i])), ifelse(is.na(tab$calmar[i]),"NA",sprintf("%.2f",tab$calmar[i])), tab$gates[i]))
fwrite(tab, file.path(OUT,"round2_results.csv")); saveRDS(tab, file.path(OUT,"_fof_round2.rds"))
cat("ROUND2|", paste(sprintf("%s:pt%.2f/oos%s/cal%s", tab$config, tab$port_t, ifelse(is.na(tab$oos_ret),"NA",sprintf("%.2f",tab$oos_ret)), ifelse(is.na(tab$calmar),"NA",sprintf("%.2f",tab$calmar))), collapse=" "), "\n")
cat(sprintf("PIT_TOGGLE|shift2_port_t=%.2f\n", cs_tog$portfolio_alpha_t_nw_lag3))
close(con); cat("FOF_ROUND2_DONE\n")
