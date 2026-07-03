## run_ramp_shumulvey.R — Shu & Mulvey (2024, arXiv 2410.14841) 충실 구현 STAGE 2.
## (1) 팩터별 active(팩터-시장) ~15 피처 → 2-state Sparse Jump Model (희소 피처가중 + jump penalty DP).
##     확장윈도 min 8y/max 12y, 월refit, 마지막 상태=현 국면(PIT 1기 지연).
## (2) 단일팩터 L/S 진단(논문 §3.2, 튜닝/검증용, hypothetical) — 논문 Table 부호·Sharpe 대조.
## (3) regime → 동일국면 과거평균 active(연율, ±5% cap) = view.
## (4) Black-Litterman: EW prior, P 6×7(+factor/-market), Σ=EWMA126d, δ=2.5,
##     Ω/τ=c·diag(PΣP') (c=목표 TE 캘리브), posterior μ → long-only Σw=1 MVO QP.
## (5) 백테 vs EW(분기리밸)·vs Market, 논문 헤드라인 대조. 5bps. 모든 제약 해지(논문 그대로).
suppressPackageStartupMessages({library(data.table); library(arrow); library(Rcpp); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_smv.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_smv_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)

## ---- helpers ----
ewm<-function(x,hl){a<-1-exp(log(0.5)/hl);y<-numeric(length(x));acc<-NA_real_
  for(i in seq_along(x)){xi<-x[i];if(is.na(xi)){y[i]<-acc;next};acc<-if(is.na(acc))xi else a*xi+(1-a)*acc;y[i]<-acc};y}
rollmin<-function(x,w){n<-length(x);y<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1,i-w+1);y[i]<-min(x[lo:i])};y}
rollmax<-function(x,w){n<-length(x);y<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1,i-w+1);y[i]<-max(x[lo:i])};y}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
SRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

## ---- 2-state jump DP (Viterbi, inline Rcpp) ----
cppFunction('IntegerVector jumpDP(NumericMatrix C, double lam){
  int n=C.nrow(); NumericMatrix D(n,2); IntegerMatrix B(n,2);
  D(0,0)=C(0,0); D(0,1)=C(0,1);
  for(int t=1;t<n;t++){ for(int k=0;k<2;k++){
    double stay=D(t-1,k); double sw=D(t-1,1-k)+lam;
    if(stay<=sw){D(t,k)=C(t,k)+stay;B(t,k)=k;} else {D(t,k)=C(t,k)+sw;B(t,k)=1-k;} }}
  IntegerVector s(n); s[n-1]= D(n-1,0)<=D(n-1,1)?0:1;
  for(int t=n-2;t>=0;t--) s[t]=B(t+1,s[t+1]);
  return s+1; }')

## ---- Sparse Jump Model (Witten-Tibshirani 피처가중 + jump DP) ----
## X: T×p 표준화 피처. K=2. lam=jump penalty. kappa=ℓ1 bound(√9.5). 반환 states(1/2)+centroids+w
sparse_jm<-function(X,lam=50,kappa=sqrt(9.5),outer=8,inner=10){
  X<-as.matrix(X); T<-nrow(X); p<-ncol(X)
  wj<-rep(1/sqrt(p),p)                      # 피처 가중 init
  s<-as.integer(X[,1] > median(X[,1]))+1L   # state init by 1st feature
  soft<-function(a,d) sign(a)*pmax(abs(a)-d,0)
  for(o in 1:outer){
    ## --- JM fit (가중 거리) ---
    for(it in 1:inner){
      th<-matrix(0,2,p); for(k in 1:2){idx<-which(s==k); th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE]) else colMeans(X)}
      C<-matrix(0,T,2); for(k in 1:2){d2<-sweep(X,2,th[k,],"-")^2; C[,k]<-as.numeric(d2 %*% wj)}
      ns<-jumpDP(C,lam); if(all(ns==s))break; s<-ns
    }
    ## --- 피처 가중 갱신: a_j = between-cluster SS (TSS-WCSS) ---
    th<-matrix(0,2,p); for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE]) else colMeans(X)}
    gm<-colMeans(X); TSS<-colSums(sweep(X,2,gm,"-")^2)
    WCSS<-rep(0,p); for(k in 1:2){idx<-which(s==k);if(length(idx)>0)WCSS<-WCSS+colSums(sweep(X[idx,,drop=FALSE],2,th[k,],"-")^2)}
    a<-pmax(TSS-WCSS,0)
    ## ℓ1 bound kappa: Δ 이분탐색 (||w||2=1, ||w||1<=kappa)
    f<-function(d){sw<-soft(a,d);nm<-sqrt(sum(sw^2));if(nm<1e-12)return(0);sum(abs(sw/nm))}
    if(f(0)<=kappa){ d<-0 } else { lo<-0;hi<-max(a);for(b in 1:50){mid<-(lo+hi)/2;if(f(mid)>kappa)lo<-mid else hi<-mid};d<-hi }
    sw<-soft(a,d);nm<-sqrt(sum(sw^2));wnew<-if(nm<1e-12)rep(1/sqrt(p),p) else sw/nm
    if(max(abs(wnew-wj))<1e-4){wj<-wnew;break}; wj<-wnew
  }
  list(s=s, th=th, w=wj)
}

## ---- 피처 빌드 (active 일별 a_t, 시장 m_t, 시장환경) ----
build_feat<-function(a,m){ n<-length(a); L<-cumprod(1+ifelse(is.finite(a),a,0))  # 누적 active 레벨
  F<-list()
  for(hl in c(8,21,63)){F[[paste0("ewma",hl)]]<-ewm(a,hl)}
  for(wn in c(8,21,63)){ up<-ewm(pmax(a,0),wn);dn<-ewm(pmax(-a,0),wn);F[[paste0("rsi",wn)]]<-100-100/(1+up/(dn+1e-12))}
  for(wn in c(8,21,63)){rmn<-rollmin(L,wn);rmx<-rollmax(L,wn);F[[paste0("k",wn)]]<-100*(L-rmn)/(rmx-rmn+1e-12)}
  F[["macd_8_21"]]<-(ewm(L,8)-ewm(L,21))/L; F[["macd_21_63"]]<-(ewm(L,21)-ewm(L,63))/L
  dd<-sqrt(ewm(pmin(a,0)^2,21)); F[["logdd21"]]<-log(dd+1e-8)
  ma<-ewm(a,21);mm<-ewm(m,21);cov<-ewm((a-ma)*(m-mm),21);vr<-ewm((m-mm)^2,21);F[["beta21"]]<-cov/(vr+1e-12)
  F[["mkt21"]]<-ewm(m,21)
  rv<-rep(NA_real_,n);for(i in 22:n)rv[i]<-sd(m[(i-20):i]);lrv<-log(rv+1e-8);F[["vix21"]]<-ewm(c(NA,diff(lrv)),21)
  as.data.table(F) }

## ---- LOAD ----
R<-as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date)
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth"); IDX<-c("Market",FACN)
for(c in IDX) R[[c]][!is.finite(R[[c]])]<-NA
R<-R[is.finite(Market)]
ACT<-copy(R[,.(Date)]); for(f in FACN) ACT[[f]]<-R[[f]]-R$Market   # active returns
pg("loaded R rows=%d\n",nrow(R))

## ---- 월말 인덱스 ----
ym<-format(R$Date,"%Y-%m"); meix<-which(!duplicated(ym,fromLast=TRUE)); medates<-R$Date[meix]
# 월간 인덱스 수익 (일별 복리)
RM<-copy(R); RM[,ym:=format(Date,"%Y-%m")]
mon<-RM[,lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),by=ym,.SDcols=IDX]
mon[,medate:=R$Date[meix]]; setorder(mon,medate)
pg("monthly built rows=%d\n",nrow(mon))

## ==== STAGE 2A: 팩터별 SJM walk-forward (확장윈도 8-12y, 월refit, 마지막 상태) ====
MINY<-8; MAXY<-12; PER<-252
feats<-lapply(FACN,function(f)build_feat(ACT[[f]],R$Market)); names(feats)<-FACN
# 각 팩터 피처 표준화는 refit window 내에서 (PIT). 상태/뷰를 월말마다 산출.
regime<-data.table(medate=medates)   # 팩터별 현재 state (1/2)
view_ann<-data.table(medate=medates) # 팩터별 view (현 state 과거평균 active 연율, ±5% cap)
diag_ls<-list()                      # L/S 진단용 일별 position
NS<-length(R$Date); dateI<-as.integer(R$Date)
for(f in FACN){ X0<-feats[[f]]; a<-ACT[[f]]
  st_series<-rep(NA_integer_,length(medates)); vw_series<-rep(NA_real_,length(medates))
  lspos<-rep(0,NS)   # 일별 L/S 포지션(다음날 적용)
  for(mi in seq_along(medates)){ md<-medates[mi]; ei<-meix[mi]
    lo_date<-md - MAXY*365; hi_i<-ei
    lo_i<-which(R$Date>=max(R$Date[1], md-MAXY*365))[1]
    tr_i<-lo_i:hi_i
    if(length(tr_i) < MINY*PER){next}     # 최소 8y
    Xtr<-as.matrix(X0[tr_i]); atr<-a[tr_i]
    ok<-which(apply(Xtr,1,function(r)all(is.finite(r))) & is.finite(atr))
    if(length(ok)<MINY*PER){next}
    Xok<-Xtr[ok,,drop=FALSE]; aok<-atr[ok]
    mu<-colMeans(Xok); sg<-apply(Xok,2,sd); sg[!is.finite(sg)|sg<1e-9]<-1
    Xs<-sweep(sweep(Xok,2,mu,"-"),2,sg,"/")
    fit<-tryCatch(sparse_jm(Xs,lam=50,kappa=sqrt(9.5)),error=function(e)NULL); if(is.null(fit))next
    s<-fit$s
    # 상태 라벨: 평균 active 높은 state = bull(2)
    mret<-c(mean(aok[s==1]),mean(aok[s==2])); bull<-which.max(mret)
    cur<-s[length(s)]; cur_bull<-(cur==bull)
    st_series[mi]<-if(cur_bull)2L else 1L
    # view = 현 상태 과거평균 active (연율), ±5% cap
    vraw<-mean(aok[s==cur])*PER; vw_series[mi]<-max(min(vraw,0.05),-0.05)
    # L/S 진단: 현 상태 view>+5%→+1, <−5%→−1, else 선형(±5%cap 비례)
    pos<-max(min(vraw/0.05,1),-1);
    # 다음 월 일별에 pos 적용 (md+1 ~ next medate)
    nx<-if(mi<length(medates))meix[mi+1] else NS
    if(ei+1<=nx) lspos[(ei+1):nx]<-pos
  }
  regime[[f]]<-st_series; view_ann[[f]]<-vw_series; diag_ls[[f]]<-lspos
  pg("  SJM done %s (states non-NA=%d)\n",f,sum(!is.na(st_series)))
}
pg("STAGE2A done\n")
saveRDS(list(regime=regime,view_ann=view_ann,diag_ls=diag_ls,medates=medates,meix=meix),".cache/_smv_regime.rds")

## ==== STAGE 2B: 단일팩터 L/S 진단 (논문 Table 대조) ====
w("=== 단일팩터 L/S 진단 (논문 §3.2; hypothetical, 튜닝/검증) — 논문 Table: Value .39/Mom .16/LowVol .30/Growth .37 ===")
w(sprintf("  %-10s %8s %8s %8s","factor","LS_SR","ann_act%","n_shift/yr"))
for(f in FACN){ pos<-diag_ls[[f]]; a<-ACT[[f]]; m<-R$Market
  # L/S 일별: pos*(factor active) - cost. active = factor-market 이므로 L/S(+factor/-market)=pos*active
  lsr<-pos*a; cost<-5e-4*abs(c(0,diff(pos)))   # 5bps × |Δpos| (200% flip=2)
  net<-lsr-cost; net<-net[is.finite(net)]
  ann_act<-mean(net)*PER*100; sr<-mean(net)/sd(net)*sqrt(PER)
  nsh<-sum(abs(diff(pos))>1e-9)/ (length(pos)/PER)
  w(sprintf("  %-10s %+8.2f %+8.2f %8.2f",f,sr,ann_act,nsh))}

## ==== STAGE 2C: Black-Litterman 월간 배분 ====
delta<-2.5; w_ew<-rep(1/7,7)
# 일별 EWMA cov (126d half-life) of 7 indices → 월말 annualized Σ (증분 1회, 캐시)
RmatAll<-as.matrix(R[,..IDX]); RmatAll[!is.finite(RmatAll)]<-0
a126<-1-exp(log(0.5)/126); Sacc<-matrix(0,7,7); Sig_list<-vector("list",length(medates)); .mi<-1L
for(t in 1:nrow(RmatAll)){ x<-RmatAll[t,]; Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc
  if(.mi<=length(meix) && t==meix[.mi]){ if(t>=130)Sig_list[[.mi]]<-Sacc*PER; .mi<-.mi+1L } }
pg("ewcov snapshots=%d\n",sum(!sapply(Sig_list,is.null)))
P<-matrix(0,6,7); for(j in 1:6)P[j,1+j]<-1; P[,1]<- -1   # +factor / -market
colnames(P)<-IDX

solveMVO<-function(muv,Sig){ D<-delta*Sig; D<-D+diag(1e-6,7); A<-cbind(rep(1,7),diag(7));b0<-c(1,rep(0,7))
  r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL); if(is.null(r))return(w_ew); pmax(r$solution,0)/sum(pmax(r$solution,0)) }

# 월말마다 Σ, view, BL posterior, c-sweep용 BL μ 함수
build_weights<-function(cc){ Wt<-matrix(NA_real_,length(medates),7); te<-rep(NA_real_,length(medates))
  for(mi in seq_along(medates)){ Sig<-Sig_list[[mi]]; if(is.null(Sig))next
    vv<-as.numeric(view_ann[mi,..FACN]); if(any(!is.finite(vv)))next
    pri<-delta*as.numeric(Sig%*%w_ew)             # π
    M<-P%*%Sig%*%t(P); Om<-cc*diag(diag(M))
    muBL<-pri + as.numeric(Sig%*%t(P)%*%solve(M+Om,(vv - as.numeric(P%*%pri))))
    wts<-solveMVO(muBL,Sig); Wt[mi,]<-wts
    te[mi]<-sqrt(as.numeric(t(wts-w_ew)%*%Sig%*%(wts-w_ew)))
  }; list(W=Wt,te=te) }

# c 캘리브: 목표 TE(연율) 평균 맞추도록 이분탐색
calib_c<-function(target){ lo<-1e-3; hi<-50
  for(b in 1:30){ mid<-sqrt(lo*hi); bw<-build_weights(mid); mte<-mean(bw$te,na.rm=TRUE)
    if(!is.finite(mte)){hi<-mid;next}; if(mte>target)lo<-mid else hi<-mid }
  sqrt(lo*hi) }

## 백테 함수: 월간 weights → 포트 수익 (5bps delta), vs EW(분기리밸)·vs Market
bt<-function(W,lab){ keep<-which(apply(W,1,function(r)all(is.finite(r)))); if(length(keep)<24)return(NULL)
  k0<-keep[1]; rng<-k0:length(medates)
  mr<-as.matrix(mon[rng,..IDX]); Wr<-W[rng,,drop=FALSE]
  # 결측월 forward-fill weights
  for(i in 2:nrow(Wr))if(any(!is.finite(Wr[i,])))Wr[i,]<-Wr[i-1,]
  Wr[!is.finite(Wr)]<-1/7
  pr<-numeric(nrow(mr)); to<-numeric(nrow(mr)); wprev<-rep(1/7,7)
  for(i in 1:nrow(mr)){ wt<-Wr[i,]; ri<-mr[i,]; gross<-sum(wt*ri)
    dlt<-sum(abs(wt-wprev)); cost<-5e-4*dlt; pr[i]<-gross-cost; to[i]<-dlt
    wd<-wt*(1+ri); wprev<-wd/sum(wd) }
  mkt<-mr[,1]
  # EW (분기리밸): 매분기 1/7 리셋, 사이 drift
  ew<-numeric(nrow(mr)); we<-rep(1/7,7)
  for(i in 1:nrow(mr)){ri<-mr[i,];ew[i]<-sum(we*ri);wd<-we*(1+ri);we<-wd/sum(wd); if(i%%3==0)we<-rep(1/7,7)}
  actM<-pr-mkt; actE<-pr-ew; n<-length(pr); yfrac<-12/n
  nav<-cumprod(1+pr); mdd<-min(nav/cummax(nav)-1)
  navA<-cumprod(1+actM); mddA<-min(navA/cummax(navA)-1)
  data.table(model=lab, n_mo=n,
    IR_vsMkt=IRf(actM), IR_vsEW=IRf(actE), pt_capwt=nwt(actM),
    abs_SR=SRf(pr), abs_CAGR=prod(1+pr)^(12/n)-1, abs_MDD=mdd, act_MDD=mddA,
    TO_ann=mean(to)*12) }

## ---- 실행: TE 1/2/3/4% 캘리브 + 백테 ----
pg("STAGE2C calibrating\n")
res<-list(); cvals<-c()
for(tgt in c(0.01,0.02,0.03,0.04)){ cc<-calib_c(tgt); cvals<-c(cvals,cc); bw<-build_weights(cc)
  r<-bt(bw$W,sprintf("BL_TE%.0f%%",tgt*100)); if(!is.null(r)){r[,c_used:=round(cc,3)][,te_real:=round(mean(bw$te,na.rm=T)*100,2)];res[[length(res)+1]]<-r}
  pg("  TE%.0f%% c=%.3f realTE=%.2f%%\n",tgt*100,cc,mean(bw$te,na.rm=T)*100) }
# EW & Market baseline (동일 기간)
Wew<-matrix(1/7,length(medates),7); rew<-bt(Wew,"EW_benchmark")
RES<-rbindlist(res,fill=TRUE)

w("\n=== Shu-Mulvey KR 충실구현 — 동적 멀티팩터 (vs EW / vs Market), 논문 대조 ===")
w(sprintf("  %-12s %6s %8s %8s %8s %7s %8s %8s %8s %7s","model","n_mo","IR_vsMkt","IR_vsEW","pt_capwt","absSR","absCAGR","absMDD","actMDD","TO_yr"))
prnt<-function(r)w(sprintf("  %-12s %6d %+8.2f %+8.2f %+8.2f %+7.2f %+8.3f %+8.3f %+8.3f %7.2f",r$model,r$n_mo,r$IR_vsMkt,r$IR_vsEW,r$pt_capwt,r$abs_SR,r$abs_CAGR,r$abs_MDD,r$act_MDD,r$TO_ann))
if(!is.null(rew))prnt(rew)
for(i in seq_len(nrow(RES)))prnt(RES[i])
w("\n논문 헤드라인(US 2007-2024): IR_vsEW 0.40~0.49 / IR_vsMkt EW0.05→0.44 / absSR Mkt0.52→TE4 0.65 / actMDD -10%→-6%")
w(sprintf("c_used by TE: %s",paste(sprintf('%.0f%%=%.3f',c(1,2,3,4),cvals),collapse=" ")))
saveRDS(list(RES=RES,rew=rew,cvals=cvals),".cache/_smv_result.rds")
close(con); cat("SMV_DONE\n")
