## plan_lib.R — 충실구현 공용 라이브러리 (S2 가지치기·생존가중 · 절대수익 metric · S4 레짐 · S5 Kelly/CDaR 사영)
## Phase0 제외: 기존 316팩터 패널·returns 사용. 목적함수 = 절대수익 Calmar/CDaR (IR/active-t 아님).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); OUT<-"04_Research/factor_rotation/fof_first_slice"
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
## ── 데이터 ──
.load_data<-function(){
  sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
  setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
  bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
  ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
  bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]; setorder(bench_dt,date)
  liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
  FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
  list(sc=sc, ret_dt=ret_dt, bench_dt=bench_dt, liq_dt=liq_dt, FIC=FIC) }
## ── S2: 롱온리 생존가중 + 인과 sign-stability 가지치기 (사전등록: 전반부-후반부 IC 부호 일치) ──
## survival = 롱레그 프리미엄 점유 (숏 의존 팩터 감점). prune: 부호 불안정 팩터 제거.
build_S2<-function(D){
  sc<-D$sc; ret_dt<-D$ret_dt; bench_dt<-D$bench_dt
  m<-merge(sc[,.(date,tic,factor_id,nz)], ret_dt, by=c("date","tic"))
  m<-merge(m, bench_dt, by="date")
  m[, q:=frank(nz,ties.method="first")/.N, by=.(date,factor_id)]
  ll<-m[, .(long=mean(Ret[q>0.8],na.rm=T)-mean(BM,na.rm=T), short=mean(BM,na.rm=T)-mean(Ret[q<=0.2],na.rm=T)), by=.(date,factor_id)]
  surv<-ll[, .(long=mean(long,na.rm=T), short=mean(short,na.rm=T)), by=factor_id]
  surv[, survival := pmax(long,0)/(pmax(long,0)+pmax(short,0)+1e-9) ]   # 롱레그 점유 [0,1]
  ## sign-stability: 전반/후반 IC 부호 일치
  FIC<-D$FIC; dmid<-FIC[,median(Date)]
  ss<-FIC[, .(ic1=mean(ic[Date<dmid],na.rm=T), ic2=mean(ic[Date>=dmid],na.rm=T)), by=factor_id]
  ss[, stable := sign(ic1)==sign(ic2) & abs(ic1)>0.002 & abs(ic2)>0.002 ]
  surv<-merge(surv, ss, by="factor_id")
  list(surv=surv, kept=surv[stable==TRUE, factor_id], surv_w=setNames(surv$survival, surv$factor_id)) }
## ── 절대수익 metric ──
mdd<-function(r){ r<-r[is.finite(r)]; nav<-cumprod(1+r); max(1-nav/cummax(nav)) }
cdar<-function(r,a=0.1){ r<-r[is.finite(r)]; nav<-cumprod(1+r); dd<-1-nav/cummax(nav); mean(tail(sort(dd),max(1,floor(length(dd)*a)))) }
sortino<-function(r){ r<-r[is.finite(r)]; dn<-r[r<0]; if(length(dn)<2) return(NA); mean(r)/sqrt(mean(dn^2))*sqrt(12) }
absSR<-function(r){ r<-r[is.finite(r)]; mean(r)/sd(r)*sqrt(12) }
cagr<-function(r){ r<-r[is.finite(r)]; prod(1+r)^(12/length(r))-1 }
calmar<-function(r){ cagr(r)/mdd(r) }
recov<-function(r){ r<-r[is.finite(r)]; nav<-cumprod(1+r); dd<-nav<cummax(nav); rle_<-rle(dd); max(rle_$lengths[rle_$values],0) }
## ── S4 레짐 (PIT): BM trailing 6m 변동성 상태 → invested β. 사전등록: vol>과거60m 70%ile = risk-off ──
regime_beta<-function(bench_dt, beta_off=0.4){
  b<-copy(bench_dt); setorder(b,date); b[, vol6:=frollapply(BM,6L,sd)]; b[, vol6_l:=shift(vol6,1L)]
  b[, thr:=shift(frollapply(vol6, 60L, function(z) quantile(z,0.7,na.rm=T)),1L)]
  b[, beta := fifelse(is.finite(vol6_l)&is.finite(thr)&vol6_l>thr, beta_off, 1.0)]
  b[,.(date,beta)] }
## ── S5 사영: score → top-N(≤25, β연동) fractional-Kelly 가중, idio cap 0.20, ×β 현금 ──
## 목적=절대수익. Kelly w∝pmax(score,0)/var, 0.5 fractional.
project_portfolio<-function(score_dt, D, seasW=48L, topN=25L, kelly=TRUE, use_regime=TRUE, beta_off=0.4){
  ret_dt<-D$ret_dt; liq_dt<-D$liq_dt; bench_dt<-D$bench_dt
  months<-sort(unique(D$sc$date)); rb<-regime_beta(bench_dt, beta_off)
  ## 종목 trailing 12m 변동성 (Kelly denom, PIT)
  setorder(ret_dt,tic,date); ret_dt[, var12:=shift(frollapply(Ret,12L,var,fill=NA),1L), by=tic]
  vmap<-ret_dt[,.(date,tic,var12)]
  hist_cnt<-function(t,tics){ trd<-tail(months[months<t],seasW); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
  S<-merge(score_dt[is.finite(score)], liq_dt, by=c("date","tic"))[adv>=2e8]
  ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[seasW+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]
    bt<-if(use_regime) rb[date==t,beta] else 1.0; if(length(bt)==0||!is.finite(bt)) bt<-1.0
    Nt<-if(use_regime && bt<1) as.integer(round(topN*bt)) else topN; Nt<-max(Nt,8L)
    sel<-S[date==t][order(-score)][1:min(topN,.N)][is.finite(score)]
    sel<-sel[tic %in% hist_cnt(t,sel$tic)[N>=as.integer(0.75*seasW),tic]]; if(nrow(sel)<8) next
    fr<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr$Ret,fr$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn)
    if(kelly){ vv<-vmap[date==t & tic %in% cn]; vm<-setNames(vv$var12,vv$tic); vd<-vm[cn]; vd[!is.finite(vd)|vd<=0]<-median(vd[vd>0],na.rm=T)
      wv<-pmax(av-min(av),1e-6)/vd } else wv<-exp(2*av)   # fractional-Kelly ∝ score/var
    wv<-wv[order(-wv)][1:min(length(wv),25)]; wv<-pmin(wv/sum(wv),0.20); wv<-wv/sum(wv)*bt   # idio cap 0.20, ×β
    allt<-union(names(prevw),names(wv)); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[names(wv)]<-wv
    to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[names(wv)],na.rm=T)-0.0015*to, inv=sum(wv))) }
  merge(ser,bench_dt,by="date")[order(date)] }
metrics_abs<-function(d){ r<-d$net; list(SR=absSR(r), Sortino=sortino(r), CAGR=100*cagr(r), MDD=100*mdd(r), Calmar=calmar(r), CDaR=100*cdar(r), recov=recov(r), avg_inv=mean(d$inv,na.rm=T)) }
cat("[plan_lib.R] loaded — S2/절대metric/S4regime/S5project\n")
