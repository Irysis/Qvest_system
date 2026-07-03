## run_fof_optsweep.R — 도훈: 비중결정 다양한 최적화 기법 튜닝 (SOTA optimizer sweep)
## IC-가중 top-25 *선택* 고정 → 비중을 EW/tilt/MVO/HRP/ERC/MaxDiv/CVaR로 결정, 절대 SR·active 비교.
## PIT: 공분산은 t 이전 trailing 월수익만(forward Ret_1m을 과거 signal_date에서). bounds [0,0.20], max 25.
## 인프라 재사용: weight_method_registry::dispatch_weight_method + corpcor Ledoit-Wolf shrink.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/portfolio/weight_method_registry.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_optsweep.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ optimizer sweep (비중결정 SOTA) ================"); w(sprintf("실행 %s",as.character(Sys.time())))

## ── 알파 신호 = IC-가중 score (factor-of-factors) ──
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
S<-merge(S, liq_dt, by=c("date","tic")); S<-S[adv>=2e8]   # 유동필터

has_corp<-requireNamespace("corpcor",quietly=TRUE)
shrinkcov<-function(R){ if(has_corp) tryCatch(as.matrix(corpcor::cov.shrink(R,verbose=FALSE)),error=function(e) cov(R)) else cov(R) }

months<-sort(unique(S$date)); W<-48L; N<-25L; bnd<-c(0,0.20)
METH<-c("MVO","HRP","ERC","MaxDiv","CVaR_LP")
ser<-list(); for(k in c("EW","Tilt",METH)) ser[[k]]<-data.table()
prevw<-list(); for(k in c("EW","Tilt",METH)) prevw[[k]]<-numeric(0)
addrow<-function(k,d,net) ser[[k]]<<-rbind(ser[[k]], data.table(date=d, net=net))
turn<-function(k,wv){ allt<-union(names(prevw[[k]]),names(wv)); pv<-setNames(rep(0,length(allt)),allt); cv<-pv
  pv[names(prevw[[k]])]<-prevw[[k]]; cv[names(wv)]<-wv; prevw[[k]]<<-wv; sum(abs(cv-pv)) }

st<-which(months>=months[W+1L])[1]
for(ti in st:length(months)){ t<-months[ti]
  sel<-S[date==t][order(-score)][1:min(N,.N)]; sel<-sel[is.finite(score)]
  if(nrow(sel)<10) next
  trd<-months[months<t]; trd<-tail(trd, W)
  Rt<-dcast(ret_dt[tic %in% sel$tic & date %in% trd], date~tic, value.var="Ret")
  Rm<-as.matrix(Rt[,-1]); cn<-colnames(Rm)
  ok<-colSums(!is.na(Rm))>=as.integer(0.75*length(trd)); Rm<-Rm[,ok,drop=FALSE]; cn<-cn[ok]
  if(ncol(Rm)<10) next
  for(j in 1:ncol(Rm)){ v<-Rm[,j]; v[is.na(v)]<-mean(v,na.rm=TRUE); Rm[,j]<-v }
  Sig<-shrinkcov(Rm); dimnames(Sig)<-list(cn,cn)
  av<-setNames(sel[match(cn,tic),score],cn)
  fr<-ret_dt[date==t & tic %in% cn]; fwdv<-setNames(fr$Ret, fr$tic); cn2<-intersect(cn,names(fwdv)); if(length(cn2)<10) next
  bm<-bench_dt[date==t,BM]
  applyw<-function(wv){ wv<-wv[names(wv) %in% cn2]; if(length(wv)==0||sum(wv,na.rm=T)<=0) return(NULL); wv<-wv/sum(wv,na.rm=T); wv }
  ## baselines
  wE<-applyw(setNames(rep(1,length(cn2)),cn2)); pr<-sum(wE*fwdv[names(wE)]); addrow("EW",t, pr-0.0015*turn("EW",wE))
  wT<-applyw(setNames(exp(2*av[cn2]),cn2)); pr<-sum(wT*fwdv[names(wT)]); addrow("Tilt",t, pr-0.0015*turn("Tilt",wT))
  ## optimizers
  for(m in METH){ r<-tryCatch(dispatch_weight_method(m, alpha=av, cov_matrix=Sig, returns=Rm, bounds=bnd, max_names=N), error=function(e) list(infeasible=TRUE))
    wv<-r$weights; if(is.null(wv)||all(!is.finite(wv))){ addrow(m,t,NA_real_); next }
    if(is.null(names(wv))) names(wv)<-cn
    wv<-applyw(wv); if(is.null(wv)){ addrow(m,t,NA_real_); next }
    pr<-sum(wv*fwdv[names(wv)],na.rm=TRUE); addrow(m,t, pr-0.0015*turn(m,wv)) }
}
## ── 성과 집계 ──
sr<-function(r){ r<-r[is.finite(r)]; if(length(r)<6) return(NA); mean(r)/sd(r)*sqrt(12) }
cg<-function(r){ r<-r[is.finite(r)]; prod(1+r)^(12/length(r))-1 }
mdd<-function(r){ r<-r[is.finite(r)]; nav<-cumprod(1+r); max(1-nav/cummax(nav)) }
ptv<-function(d,from=NULL){ a<-d; if(!is.null(from)) a<-a[date>=as.Date(from)]; a<-a[is.finite(act)]; if(nrow(a)<12) return(NA); f<-lm(act~1,a); as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3]) }
w("\n=== 비중방식별 (절대 SR/CAGR/MDD + active port_t vs cap-weight 지수) ===")
tab<-data.table()
for(k in c("EW","Tilt",METH)){ d<-ser[[k]]; if(nrow(d)==0) next; d<-merge(d,bench_dt,by="date"); d[,act:=net-BM]; setorder(d,date)
  tab<-rbind(tab, data.table(method=k, SR=round(sr(d$net),2), CAGR=round(100*cg(d$net),1), MDD=round(100*mdd(d$net),1),
    pt_full=round(ptv(d),2), pt_pre=round(ptv(d[date<as.Date("2018-01-01")]),2), pt_18p=round(ptv(d,"2018-01-01"),2), n=nrow(d)))
  w(sprintf("  [%-8s] SR=%.2f CAGR=%+.1f%% MDD=%.1f%% | active pt: full=%+.2f pre2018=%+.2f 2018+=%+.2f (n=%d)",
    k, sr(d$net),100*cg(d$net),100*mdd(d$net), ptv(d),ptv(d[date<as.Date("2018-01-01")]),ptv(d,"2018-01-01"), nrow(d))) }
setorder(tab,-SR)
w(sprintf("\n  최고 절대 SR: %s (%.2f). EW baseline 대비 lift = %.2f", tab$method[1], tab$SR[1], tab$SR[1]-tab[method=="EW",SR]))
fwrite(tab,file.path(OUT,"optsweep_results.csv"))
saveRDS(ser, file.path(OUT,"_optsweep_series.rds"))
cat("OPTSWEEP|", paste(sprintf("%s:SR%.2f/18p%.2f",tab$method,tab$SR,tab$pt_18p),collapse=" "),"\n")
close(con); cat("FOF_OPTSWEEP_DONE\n")
