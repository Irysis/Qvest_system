## run_fof_seasontilt_validate.R — 시즌드+틸트(2018+ active +2.46) robustness 검증
## stale 토글(누설/감쇠) · 비용 15/30bps · λ 민감도 · 집중도(effN/maxw) · 서브기간. load-bearing 결과 방어.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_stvalid.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 시즌드+틸트 robustness 검증 ================"); w(sprintf("실행 %s",as.character(Sys.time())))
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
setnames(S,c("signal_date","security_id"),c("date","tic")); S<-merge(S, liq_dt, by=c("date","tic")); S<-S[adv>=2e8]
months<-sort(unique(S$date)); W<-48L
hist_cnt<-function(t,tics){ trd<-tail(months[months<t],W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
run<-function(stale=FALSE, cost=0.0015, lambda=2){
  ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[W+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; ts<-if(stale) months[ti-1] else t
    sel<-S[date==ts][order(-score)][1:min(25,.N)]; sel<-sel[is.finite(score)]
    hc<-hist_cnt(t, sel$tic); sel<-sel[tic %in% hc[N>=as.integer(0.75*W),tic]]; if(nrow(sel)<8) next
    fr<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr$Ret,fr$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn); wv<-exp(lambda*av); wv<-wv/sum(wv)
    allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv
    to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-cost*to, effN=1/sum(wv^2), maxw=max(wv), n=length(cn)))
  }
  merge(ser,bench_dt,by="date")[,act:=net-BM][] }
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
sr<-function(r){r<-r[is.finite(r)];mean(r)/sd(r)*sqrt(12)}; mdd<-function(r){nav<-cumprod(1+r);max(1-nav/cummax(nav))}
rep1<-function(lab,d) w(sprintf("  [%-16s] absSR=%.2f MDD=%.1f%% effN=%.1f maxw=%.0f%% | active: full=%+.2f 2018+=%+.2f 2020+=%+.2f 2024+=%+.2f",
  lab, sr(d$net), 100*mdd(d$net), mean(d$effN), 100*mean(d$maxw), ptv(d), ptv(d,"2018-01-01"), ptv(d,"2020-01-01"), ptv(d,"2024-01-01")))
w("\n=== 시즌드+틸트 변형 (active port_t vs cap-weight 지수) ===")
base<-run(); rep1("BASE λ2 15bps", base)
rep1("STALE(+1m)", run(stale=TRUE))
rep1("cost 30bps", run(cost=0.0030))
rep1("λ=1 (완만)", run(lambda=1))
rep1("λ=3 (공격)", run(lambda=3))
w(sprintf("\n  → STALE 2018+ (%+.2f) 양수면 PIT OK. cost30 (%+.2f)·λ1 (%+.2f) 견조하면 robust.",
  ptv(run(stale=TRUE),"2018-01-01"), ptv(run(cost=0.0030),"2018-01-01"), ptv(run(lambda=1),"2018-01-01")))
cat(sprintf("STVALID| base_18p=%.2f stale_18p=%.2f cost30_18p=%.2f l1_18p=%.2f base_SR=%.2f base_MDD=%.1f base_effN=%.1f\n",
  ptv(base,"2018-01-01"), ptv(run(stale=TRUE),"2018-01-01"), ptv(run(cost=0.0030),"2018-01-01"), ptv(run(lambda=1),"2018-01-01"),
  sr(base$net), 100*mdd(base$net), mean(base$effN)))
close(con); cat("FOF_STVALID_DONE\n")
