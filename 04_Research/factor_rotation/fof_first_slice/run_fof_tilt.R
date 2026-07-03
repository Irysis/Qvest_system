## run_fof_tilt.R — 도훈: 20% cap 제거 + 스코어 틸트 기본 (메가캡 담아 cap-weight 지수 추종?)
## 진단: post-2017 감쇠=25종·[0,0.20] long-only가 메가캡 구조적 언더웨이트. 처방=cap제거+틸트+메가캡 보유.
## 알파신호=IC-가중(C2). 가중=score-tilt(w∝exp(λ·score)) 무-cap, 또는 adv(시총proxy)-base×틸트.
## 측정: 월별 net active vs cap-weight 지수, port_t full/pre2018/2018+. (Σw·r 월간리밸 정확 + 15bps Σ|Δw|)
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_tilt.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 20% cap 제거 + 스코어 틸트 ================"); w(sprintf("실행 %s",as.character(Sys.time())))

sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
FIC[,tt:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]; tic<-FIC[,.(signal_date=Date,factor_id,tic=tt)]
x<-merge(sc,tic,by=c("signal_date","factor_id")); x<-x[is.finite(tic)]; x[,wf:=pmax(tic,0)]
S<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; S[,score:=zc(score),by=signal_date]
setnames(S,c("signal_date","security_id"),c("date","tic"))

## 패널: score + fwd Ret + adv, 유동필터
P<-merge(S, ret_dt, by=c("date","tic")); P<-merge(P, liq_dt, by=c("date","tic")); P<-P[adv>=2e8]
P[, sz := zc(log(adv)), by=date]   # 시총proxy z (adv 로그)

## 가중 빌더: 월별 wg (long-only, Σw=1, NO 20% cap)
mk_w <- function(P, topn=NULL, by_adv=FALSE, lambda=2, advbase=FALSE){
  d<-copy(P)
  if(by_adv){ d[, rk:=frank(-adv,ties.method="first"), by=date] } else { d[, rk:=frank(-score,ties.method="first"), by=date] }
  if(!is.null(topn)) d<-d[rk<=topn]
  if(advbase){ d[, raw:= adv * exp(lambda*score) ] } else { d[, raw:= exp(lambda*score) ] }   # 틸트
  d[, wg := raw/sum(raw), by=date]
  d[,.(date,tic,wg,Ret,BM=NULL)] }

## 성과: Σw·r 월간 + 15bps Σ|Δw| 비용 → active vs cap-weight 지수
perf <- function(W){
  g<-W[,.(g=sum(wg*Ret,na.rm=TRUE)),by=date]
  WW<-dcast(W, date~tic, value.var="wg", fill=0); setorder(WW,date)
  M<-as.matrix(WW[,-1]); to<-c(NA, rowSums(abs(diff(M)))); cost<-0.0015*ifelse(is.na(to),0,to)
  g[, cost:=cost][, net:=g-cost]
  g<-merge(g, bench_dt, by="date"); g[, act:=net-BM]; setorder(g,date)
  pt<-function(from=NULL){ a<-if(is.null(from)) g else g[date>=as.Date(from)]; if(nrow(a)<12) return(NA)
    f<-lm(act~1,data=a); as.numeric(coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }
  list(full=pt(), pre=pt2<-{a<-g[date<as.Date("2018-01-01")]; f<-lm(act~1,a); as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])},
       y18=pt("2018-01-01"), sr=mean(g$act)/sd(g$act)*sqrt(12), to=mean(to,na.rm=T)) }

CFG<-list(
  T1_EW25_cap     = list(fn=function() { W<-mk_w(P, topn=25, lambda=0); W }),   # lambda0=EW (참고)
  T2_tilt25_nocap = list(fn=function() mk_w(P, topn=25, lambda=2)),
  T3_tilt50_nocap = list(fn=function() mk_w(P, topn=50, lambda=2)),
  T4_tilt100_nocap= list(fn=function() mk_w(P, topn=100, lambda=2)),
  T5_advbase_tilt = list(fn=function() mk_w(P, topn=100, by_adv=TRUE, lambda=2, advbase=TRUE)), # 메가캡 base×틸트
  T6_advbase_t200 = list(fn=function() mk_w(P, topn=200, by_adv=TRUE, lambda=2, advbase=TRUE))
)
w("\n=== 가중방식별 (vs cap-weight 지수, port_t full/pre2018/2018+) ===")
tab<-data.table()
for(nm in names(CFG)){ W<-CFG[[nm]]$fn(); m<-perf(W)
  tab<-rbind(tab,data.table(config=nm,full=m$full,pre2018=m$pre,y2018p=m$y18,net_SR=m$sr,to=round(100*m$to)))
  w(sprintf("  [%-16s] full=%+.2f | pre2018=%+.2f | 2018+=%+.2f | net_SR=%+.3f | TO=%d%%", nm,m$full,m$pre,m$y18,m$sr,round(100*m$to))) }
setorder(tab,-y2018p)
w("\n  → 2018+ 양수(특히 advbase=메가캡 보유)면: cap제거+메가캡틸트가 cap-weight 지수 추종 회복.")
fwrite(tab,file.path(OUT,"tilt_results.csv"))
cat("TILT|", paste(sprintf("%s:full%.2f/18p%.2f",tab$config,tab$full,tab$y2018p),collapse=" "),"\n")
close(con); cat("FOF_TILT_DONE\n")
