## run_fof_optsweep2.R — 교정 optimizer sweep (실제 함수 직접 호출, 시즌드 universe)
## 비중결정: EW/Tilt(base) + HRP/MaxDiv/CVaR/NCO/RobustMV/FactorRP(RP)/NCO_ScoreTilt/MVO (SOTA).
## universe = IC-가중 top-25 중 48m 중 ≥36 trailing 이력(시즌드, 검증된 base). bounds max_w 0.20.
## PIT: 모든 cov/ret_dt는 date<t trailing만. 측정: 절대 SR + active port_t vs cap-weight 지수 full/pre/2018+.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/portfolio/weight_method_registry.R"); load_weight_infra()
has_corp<-requireNamespace("corpcor",quietly=TRUE)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_optsweep2.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ optimizer sweep v2 (교정·시즌드) ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
RDT<-ret_dt[,.(Date=date,Ticker=tic,Ret)]   # 함수용 Date/Ticker/Ret
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
FIC[,tt:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]; tic<-FIC[,.(signal_date=Date,factor_id,tic=tt)]
x<-merge(sc,tic,by=c("signal_date","factor_id")); x<-x[is.finite(tic)]; x[,wf:=pmax(tic,0)]
S<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; S[,score:=zc(score),by=signal_date]
setnames(S,c("signal_date","security_id"),c("date","tic")); S<-merge(S, liq_dt, by=c("date","tic")); S<-S[adv>=2e8]
months<-sort(unique(S$date)); W<-48L; MAXW<-0.20
hist_cnt<-function(t, tics){ trd<-tail(months[months<t], W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
shrinkcov<-function(R){ if(has_corp) tryCatch(as.matrix(corpcor::cov.shrink(R,verbose=FALSE)),error=function(e) cov(R)) else cov(R) }

METH<-c("EW","Tilt","MVO","HRP","MaxDiv","CVaR","NCO","RobustMV","FactorRP","NCO_ScoreTilt")
ser<-setNames(lapply(METH,function(z) data.table()), METH); prevw<-setNames(lapply(METH,function(z) numeric(0)), METH)
addrow<-function(k,d,net) ser[[k]]<<-rbind(ser[[k]], data.table(date=d, net=net))
costw<-function(k,wv){ allt<-union(names(prevw[[k]]),names(wv)); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw[[k]])]<-prevw[[k]]; cv[names(wv)]<-wv; prevw[[k]]<<-wv; 0.0015*sum(abs(cv-pv)) }
norm1<-function(wv,cn2){ wv<-wv[names(wv) %in% cn2]; wv<-wv[is.finite(wv)&wv>0]; if(length(wv)==0) return(NULL); wv/sum(wv) }

st<-which(months>=months[W+1L])[1]
for(ti in st:length(months)){ t<-months[ti]
  sel<-S[date==t][order(-score)][1:min(25,.N)]; sel<-sel[is.finite(score)]
  hc<-hist_cnt(t, sel$tic); keep<-hc[N>=as.integer(0.75*W),tic]; sel<-sel[tic %in% keep]
  if(nrow(sel)<8) next
  tics<-sel$tic; av<-setNames(sel$score, tics)
  rt<-RDT[Date<t & Ticker %in% tics]                       # trailing (함수가 last n_days 취함)
  fr<-ret_dt[date==t & tic %in% tics]; fwdv<-setNames(fr$Ret, fr$tic); cn2<-intersect(tics, names(fwdv)); if(length(cn2)<8) next
  bm<-bench_dt[date==t,BM]
  Wt<-as.matrix(dcast(rt, Date~Ticker, value.var="Ret")[,-1]); Wt[is.na(Wt)]<-0
  cnW<-colnames(Wt); avc<-av[cnW]; Sig<-shrinkcov(Wt); dimnames(Sig)<-list(cnW,cnW)
  getw<-function(nm){ tryCatch({
    if(nm=="EW") setNames(rep(1,length(tics)),tics)
    else if(nm=="Tilt") setNames(exp(2*av),tics)
    else if(nm=="MVO") mvo_weights(avc, Sig, bounds=c(0,MAXW), max_names=25, min_names=8L)$weights
    else if(nm=="HRP") calc_hrp_weights(tics, rt, n_days=W, max_w=MAXW)
    else if(nm=="MaxDiv") calc_maxdiv_weights(tics, rt, n_days=W, max_w=MAXW)
    else if(nm=="CVaR") calc_cvar_weights(tics, rt, n_days=W, max_w=MAXW, alpha=0.05)
    else if(nm=="NCO") calc_nco_weights(tics, rt, n_days=W, max_w=MAXW)
    else if(nm=="RobustMV") calc_robust_mv_weights(tics, rt, n_days=W, max_w=MAXW)
    else if(nm=="FactorRP") calc_factor_rp_weights(tics, rt, n_days=W, max_w=MAXW)
    else if(nm=="NCO_ScoreTilt") calc_nco_score_tilt_weights(tics, av, rt, n_days=W, max_w=MAXW)
  }, error=function(e) NULL) }
  for(nm in METH){ wv<-getw(nm); if(is.null(wv)){ addrow(nm,t,NA_real_); next }
    if(is.null(names(wv))) names(wv)<-tics
    wv<-norm1(wv,cn2); if(is.null(wv)){ addrow(nm,t,NA_real_); next }
    addrow(nm,t, sum(wv*fwdv[names(wv)],na.rm=TRUE)-costw(nm,wv)) }
}
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
cg<-function(r){r<-r[is.finite(r)];prod(1+r)^(12/length(r))-1}; mdd<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
w("\n=== 비중방식별 (절대 SR/CAGR/MDD + active port_t) | 시즌드 universe ===")
tab<-data.table()
for(k in METH){ d<-ser[[k]]; if(nrow(d)==0||all(!is.finite(d$net))) next; d<-merge(d,bench_dt,by="date"); d[,act:=net-BM]; setorder(d,date)
  tab<-rbind(tab,data.table(method=k,absSR=round(sr(d$net),2),CAGR=round(100*cg(d$net),1),MDD=round(100*mdd(d$net),1),
    pt_full=round(ptv(d),2),pt_pre=round(ptv(d[date<as.Date("2018-01-01")]),2),pt_18p=round(ptv(d,"2018-01-01"),2)))
  w(sprintf("  [%-13s] absSR=%.2f CAGR=%+.1f%% MDD=%.1f%% | active: full=%+.2f pre2018=%+.2f 2018+=%+.2f",
    k,sr(d$net),100*cg(d$net),100*mdd(d$net),ptv(d),ptv(d[date<as.Date("2018-01-01")]),ptv(d,"2018-01-01"))) }
setorder(tab,-absSR)
w(sprintf("\n  절대SR 최고: %s (%.2f). 2018+ active 최고: %s (%.2f).", tab$method[1],tab$absSR[1], tab[which.max(pt_18p),method], max(tab$pt_18p,na.rm=T)))
fwrite(tab,file.path(OUT,"optsweep2_results.csv")); saveRDS(ser,file.path(OUT,"_optsweep2_series.rds"))
cat("OPT2|", paste(sprintf("%s:SR%.2f/18p%.2f",tab$method,tab$absSR,tab$pt_18p),collapse=" "),"\n")
close(con); cat("FOF_OPTSWEEP2_DONE\n")
