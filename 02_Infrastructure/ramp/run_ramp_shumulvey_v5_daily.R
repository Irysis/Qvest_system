## run_ramp_shumulvey_v5_daily.R — Shu-Mulvey KR v5: 보정 회계 + 일별 온라인 필터 (FQ-239 P1).
## prereg: outputs/ramp/smv_v5_prereg_20260820.json (결과 산출 전 기록 완료 — grid·헤드라인 셀·판정 규칙 고정)
## arms:
##   M0 = 월간 케이던스 + 보정 회계(월말 결정 → 익월 적용) — P0-2 확정 기준선 회계
##   D1 = 일별 온라인 추론(Nystrup 2020: centroid 동결 + lookback 상태열 DP 재최적화, 마지막 상태)
##        + T+2 회계: h[t] = w_dec[t-2] (T종가 신호 → T+1종가 체결 → T+2 수익 귀속)
## look-ahead 원천 제거: ① 비중은 결정 시점 이후 수익만 획득 ② c 캘리브 = 각 refit일 ex-ante TE 이분탐색(인과)
##   ③ 온라인 표준화 = refit 동결 mu/sg만 ④ 피처는 전부 trailing (f17 금리 = ECOS 당일 고시 적법, usvix = t-1).
## env: SMV_IDXFILE / SMV_FEATSET(f15|f17|f17_usvix) / SMV_ARMS("M0,D1") / SMV_LAMMULT("1,2") / SMV_KEY
suppressPackageStartupMessages({library(data.table); library(arrow); library(Rcpp); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/ramp/ramp_shumulvey_features.R")

IDXFILE<-Sys.getenv("SMV_IDXFILE","outputs/ramp/shumulvey_index_returns_202608.parquet")
FEATSET<-Sys.getenv("SMV_FEATSET","f15")
ARMS<-strsplit(Sys.getenv("SMV_ARMS","M0,D1"),",")[[1]]
LAMM<-as.numeric(strsplit(Sys.getenv("SMV_LAMMULT","1,2"),",")[[1]])
SHIFT<-as.integer(Sys.getenv("SMV_SHIFT","2"))   # D1 회계 시프트: 2=T+2(정본) / 3=lag1 스트레스 / 0=동월성 고의 재현(strict A/B 문서화용 — 헤드라인 금지)
PSEED<-Sys.getenv("SMV_PLACEBO_SEED","")          # 설정 시 뷰 월-블록 셔플 placebo (상태·Σ·c 기계 불변, 뷰 타이밍만 파괴)
TE_FILTER<-Sys.getenv("SMV_TE","")                # 예: "3" 또는 "3,4" — 지정 시 해당 TE 타깃만 실행
TUNE<-Sys.getenv("SMV_TUNE","fixed")              # fixed=λ50/κ²9.5 | roll=인과 rolling re-tune (P1c: 6mo마다 trailing 6y 검증 L/S(T+1적용+5bps) argmax — IS-only 인과, 논문 §3.2)
KEY<-Sys.getenv("SMV_KEY",FEATSET)
PG<-sprintf(".cache/_smv_v5_prog_%s.txt",KEY); cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)

IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

cppFunction('IntegerVector jumpDP(NumericMatrix C, double lam){
  int n=C.nrow(); NumericMatrix D(n,2); IntegerMatrix B(n,2);
  D(0,0)=C(0,0); D(0,1)=C(0,1);
  for(int t=1;t<n;t++){ for(int k=0;k<2;k++){
    double stay=D(t-1,k); double sw=D(t-1,1-k)+lam;
    if(stay<=sw){D(t,k)=C(t,k)+stay;B(t,k)=k;} else {D(t,k)=C(t,k)+sw;B(t,k)=1-k;} }}
  IntegerVector s(n); s[n-1]= D(n-1,0)<=D(n-1,1)?0:1;
  for(int t=n-2;t>=0;t--) s[t]=B(t+1,s[t+1]);
  return s+1; }')
cppFunction('int jumpDPlast(NumericMatrix C, double lam){
  int n=C.nrow(); double d0=C(0,0), d1=C(0,1);
  for(int t=1;t<n;t++){ double n0=C(t,0)+std::min(d0,d1+lam); double n1=C(t,1)+std::min(d1,d0+lam); d0=n0; d1=n1; }
  return d0<=d1?1:2; }')
sparse_jm<-function(X,lam=50,kappa=sqrt(9.5),outer=8,inner=10){
  X<-as.matrix(X); T<-nrow(X); p<-ncol(X)
  wj<-rep(1/sqrt(p),p); s<-as.integer(X[,1] > median(X[,1]))+1L
  soft<-function(a,d) sign(a)*pmax(abs(a)-d,0)
  for(o in 1:outer){
    for(it in 1:inner){
      th<-matrix(0,2,p); for(k in 1:2){idx<-which(s==k); th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE]) else colMeans(X)}
      C<-matrix(0,T,2); for(k in 1:2){d2<-sweep(X,2,th[k,],"-")^2; C[,k]<-as.numeric(d2 %*% wj)}
      ns<-jumpDP(C,lam); if(all(ns==s))break; s<-ns }
    th<-matrix(0,2,p); for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE]) else colMeans(X)}
    gm<-colMeans(X); TSS<-colSums(sweep(X,2,gm,"-")^2)
    WCSS<-rep(0,p); for(k in 1:2){idx<-which(s==k);if(length(idx)>0)WCSS<-WCSS+colSums(sweep(X[idx,,drop=FALSE],2,th[k,],"-")^2)}
    a<-pmax(TSS-WCSS,0)
    f<-function(d){sw<-soft(a,d);nm<-sqrt(sum(sw^2));if(nm<1e-12)return(0);sum(abs(sw/nm))}
    if(f(0)<=kappa){ d<-0 } else { lo<-0;hi<-max(a);for(b in 1:50){mid<-(lo+hi)/2;if(f(mid)>kappa)lo<-mid else hi<-mid};d<-hi }
    sw<-soft(a,d);nm<-sqrt(sum(sw^2));wnew<-if(nm<1e-12)rep(1/sqrt(p),p) else sw/nm
    if(max(abs(wnew-wj))<1e-4){wj<-wnew;break}; wj<-wnew }
  list(s=s, th=th, w=wj)
}

## ==== LOAD ====
R<-as.data.table(read_parquet(IDXFILE))
R[,Date:=as.Date(Date)]; setorder(R,Date)
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth"); IDX<-c("Market",FACN)
for(cn in IDX) R[[cn]][!is.finite(R[[cn]])]<-NA
R<-R[is.finite(Market)]
NS<-nrow(R)
ACT<-copy(R[,.(Date)]); for(f in FACN) ACT[[f]]<-R[[f]]-R$Market
ym<-format(R$Date,"%Y-%m"); meix<-which(!duplicated(ym,fromLast=TRUE)); medates<-R$Date[meix]
NM<-length(medates)
RM<-copy(R); RM[,ym:=format(Date,"%Y-%m")]
mon<-RM[,lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),by=ym,.SDcols=IDX]
mon[,medate:=medates]; setorder(mon,medate)
pg("loaded %s rows=%d months=%d featset=%s\n",IDXFILE,NS,NM,FEATSET)

## extras (f17 계열)
extras<-NULL
if(FEATSET %in% c("f17","f17_usvix")){
  rt<-smv_load_rates(R$Date); extras<-list(rate3y=rt$rate3y, rate10y=rt$rate10y)
  if(FEATSET=="f17_usvix") extras$usvix_lag<-smv_load_usvix(R$Date)
}
feats<-lapply(FACN,function(f)build_feat_v2(ACT[[f]],R$Market,FEATSET,extras)); names(feats)<-FACN

## ==== STAGE 1: 월간 refit (fixed: λ=50/κ²=9.5 — prereg | roll: 인과 재선택) + 산출 보존 ====
MINY<-8; MAXY<-12; PER<-252
GRID9<-expand.grid(lam=c(20,50,100),k2=c(6,9.5,14))   # v3 grid 승계 (사전등록 v3 프로토콜)
ls_sh_t1<-function(s,aok){ n<-length(s); if(n<100)return(-9)   # 검증 L/S: T+1 적용 + 5bps (v3 same-day 결함 수리)
  vr<-sapply(1:2,function(k){v<-mean(aok[s==k])*PER; if(!is.finite(v))0 else max(min(v,0.05),-0.05)})
  pos<-pmax(pmin(vr[s]/0.05,1),-1)
  cost<-5e-4*abs(c(0,diff(pos)))
  net<-pos[1:(n-1)]*aok[2:n]-cost[1:(n-1)]
  net<-net[is.finite(net)]; if(length(net)<100||sd(net)<1e-9)return(-9)
  mean(net)/sd(net)*sqrt(PER) }
refit_cache<-sprintf(".cache/_smv_v5_refit_%s_%s_%s.rds",FEATSET,TUNE,gsub("[^A-Za-z0-9]","_",basename(IDXFILE)))
REF<-NULL
if(file.exists(refit_cache)){ z<-readRDS(refit_cache)
  if(identical(z$idx_max,max(R$Date)) && identical(z$nm,NM)) REF<-z$REF }
if(is.null(REF)){
  REF<-list()
  for(f in FACN){ X0<-as.matrix(feats[[f]]); a<-ACT[[f]]
    rl<-vector("list",NM); cur<-list(lam=50,k2=9.5); last_tune<--999L
    for(mi in seq_len(NM)){ md<-medates[mi]; ei<-meix[mi]
      lo_i<-which(R$Date>=max(R$Date[1], md-MAXY*365))[1]
      tr_i<-lo_i:ei
      if(length(tr_i) < MINY*PER) next
      Xtr<-X0[tr_i,,drop=FALSE]; atr<-a[tr_i]
      ok<-which(apply(Xtr,1,function(r)all(is.finite(r))) & is.finite(atr))
      if(length(ok)<MINY*PER) next
      Xok<-Xtr[ok,,drop=FALSE]; aok<-atr[ok]
      mu<-colMeans(Xok); sg<-apply(Xok,2,sd); sg[!is.finite(sg)|sg<1e-9]<-1
      Xs<-sweep(sweep(Xok,2,mu,"-"),2,sg,"/")
      if(TUNE=="roll" && (mi-last_tune)>=6L){   # 인과 재선택: 결정 시점 ei 이전 데이터만 (trailing 6y)
        vlo<-which(R$Date>=max(R$Date[1], md-6*365))[1]; vi<-vlo:ei
        Xv<-X0[vi,,drop=FALSE]; av<-a[vi]
        vok<-which(apply(Xv,1,function(r)all(is.finite(r))) & is.finite(av))
        if(length(vok)>=6*PER*0.8){
          muv<-colMeans(Xv[vok,,drop=FALSE]); sgv<-apply(Xv[vok,,drop=FALSE],2,sd); sgv[!is.finite(sgv)|sgv<1e-9]<-1
          Xvs<-sweep(sweep(Xv[vok,,drop=FALSE],2,muv,"-"),2,sgv,"/"); avk<-av[vok]
          best<-list(sh=-Inf,lam=cur$lam,k2=cur$k2)
          for(g in 1:nrow(GRID9)){ fitg<-tryCatch(sparse_jm(Xvs,lam=GRID9$lam[g],kappa=sqrt(GRID9$k2[g])),error=function(e)NULL)
            if(is.null(fitg))next; sh<-ls_sh_t1(fitg$s,avk)
            if(is.finite(sh)&&sh>best$sh)best<-list(sh=sh,lam=GRID9$lam[g],k2=GRID9$k2[g]) }
          cur<-list(lam=best$lam,k2=best$k2); last_tune<-mi } }
      lam_use<-if(TUNE=="roll")cur$lam else 50; kap2_use<-if(TUNE=="roll")cur$k2 else 9.5
      fit<-tryCatch(sparse_jm(Xs,lam=lam_use,kappa=sqrt(kap2_use)),error=function(e)NULL); if(is.null(fit)) next
      s<-fit$s
      m_ann<-sapply(1:2,function(k){v<-mean(aok[s==k])*PER; if(!is.finite(v))v<-0; max(min(v,0.05),-0.05)})
      rl[[mi]]<-list(th=fit$th, wj=fit$w, mu=mu, sg=sg, cur=s[length(s)], m_ann=m_ann, win_lo=lo_i,
                     lam=lam_use, k2=kap2_use)
    }
    REF[[f]]<-rl; pg("  refit done %s (n=%d, tune=%s)\n",f,sum(!sapply(rl,is.null)),TUNE)
  }
  saveRDS(list(REF=REF,idx_max=max(R$Date),nm=NM),refit_cache)
} else pg("refit cache hit\n")

## ==== STAGE 2: 일별 온라인 상태 (λ_mult별) ====
## s_daily[t,f]: t일 종가 기준 결정 상태. refit일 ei = cur(스무더 마지막 상태 = 온라인과 동일점).
## 블록 (ei+1)..next_ei: 동결 th/wj/mu/sg로 C 선계산 → 각 일 prefix DP 마지막 상태. 결측피처일 = locf.
online_states<-function(lm_mult){
  scache<-sprintf(".cache/_smv_v5_states_%s_%s_%s_lm%g.rds",FEATSET,TUNE,gsub("[^A-Za-z0-9]","_",basename(IDXFILE)),lm_mult)
  if(file.exists(scache)){ z<-readRDS(scache); if(identical(z$idx_max,max(R$Date))){pg("  states cache hit lm=%g\n",lm_mult); return(z$S)} }
  S<-matrix(NA_integer_,NS,length(FACN)); colnames(S)<-FACN
  for(fi in seq_along(FACN)){ f<-FACN[fi]; X0<-as.matrix(feats[[f]]); rl<-REF[[f]]
    for(mi in seq_len(NM)){ rf<-rl[[mi]]; if(is.null(rf)) next
      lam_o<-(if(is.null(rf$lam))50 else rf$lam)*lm_mult
      ei<-meix[mi]; nx<-if(mi<NM) meix[mi+1] else NS
      S[ei,fi]<-rf$cur
      if(ei+1>nx) next
      rows<-rf$win_lo:nx
      Xb<-sweep(sweep(X0[rows,,drop=FALSE],2,rf$mu,"-"),2,rf$sg,"/")
      bad<-!apply(Xb,1,function(r)all(is.finite(r)))
      Xb[bad,]<-0
      Cb<-matrix(0,nrow(Xb),2)
      for(k in 1:2){d2<-sweep(Xb,2,rf$th[k,],"-")^2; Cb[,k]<-as.numeric(d2 %*% rf$wj)}
      Cb[bad,]<-0   # 무증거일: 상태 전환 이득 없음 → jump penalty가 유지 편향
      for(t in (ei+1):nx){ q<-t-rf$win_lo+1
        if(bad[q]){ S[t,fi]<-S[t-1,fi]; next }
        S[t,fi]<-jumpDPlast(Cb[1:q,,drop=FALSE],lam_o)
      }
    }
    pg("  online %s lam_mult=%g done\n",f,lm_mult)
  }
  saveRDS(list(S=S,idx_max=max(R$Date)),scache)
  S
}

## ==== STAGE 3: 일별 Σ (EWM 126d, annualized 스냅샷) ====
delta<-2.5; w_ew<-rep(1/7,7)
RmatAll<-as.matrix(R[,..IDX]); RmatAll[!is.finite(RmatAll)]<-0
a126<-1-exp(log(0.5)/126)
SIG<-array(NA_real_,c(7,7,NS)); Sacc<-matrix(0,7,7)
for(t in 1:NS){ x<-RmatAll[t,]; Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc; if(t>=130) SIG[,,t]<-Sacc*PER }
pg("sigma daily done\n")

P<-matrix(0,6,7); for(j in 1:6)P[j,1+j]<-1; P[,1]<- -1
solveMVO<-function(muv,Sig){ D<-delta*Sig; D<-D+diag(1e-6,7); A<-cbind(rep(1,7),diag(7));b0<-c(1,rep(0,7))
  r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL); if(is.null(r))return(w_ew); pmax(r$solution,0)/sum(pmax(r$solution,0)) }
bl_w<-function(Sig,vv,cc){ pri<-delta*as.numeric(Sig%*%w_ew)
  M<-P%*%Sig%*%t(P); Om<-cc*diag(diag(M))
  muBL<-pri + as.numeric(Sig%*%t(P)%*%solve(M+Om,(vv - as.numeric(P%*%pri))))
  solveMVO(muBL,Sig) }
te_ex<-function(w,Sig) sqrt(max(as.numeric(t(w-w_ew)%*%Sig%*%(w-w_ew)),0))

## refit별 뷰(월말 cur 기준) — c 캘리브·M0 공용
view_me<-matrix(NA_real_,NM,6); colnames(view_me)<-FACN
for(fi in seq_along(FACN)){ rl<-REF[[FACN[fi]]]
  for(mi in seq_len(NM)){ rf<-rl[[mi]]; if(is.null(rf))next; view_me[mi,fi]<-rf$m_ann[rf$cur] } }

## ---- PLACEBO (뷰 월-블록 셔플): 유효 월 집합 내 순열 — 기계(Σ/c/QP/회계) 불변, 뷰 타이밍만 파괴 ----
PERM<-NULL
if(nzchar(PSEED)){
  set.seed(as.integer(PSEED))
  validm<-which(apply(view_me,1,function(r)all(is.finite(r))))
  PERM<-rep(NA_integer_,NM); PERM[validm]<-sample(validm)
  view_me[validm,]<-view_me[PERM[validm],,drop=FALSE]
  pg("PLACEBO seed=%s (perm over %d months)\n",PSEED,length(validm))
}

## ==== STAGE 4: c 캘리브 (각 refit일 ex-ante TE 이분탐색 — 인과) ====
TE_T<-c(0.01,0.02,0.03,0.04)
if(nzchar(TE_FILTER)) TE_T<-TE_T[c(0.01,0.02,0.03,0.04)*100 %in% as.numeric(strsplit(TE_FILTER,",")[[1]])]
cmat<-matrix(NA_real_,NM,length(TE_T))
for(mi in seq_len(NM)){ ei<-meix[mi]; if(!is.finite(SIG[1,1,ei]))next
  vv<-view_me[mi,]; if(any(!is.finite(vv)))next
  Sig<-SIG[,,ei]
  for(k in seq_along(TE_T)){ tgt<-TE_T[k]; lo<-1e-3; hi<-50
    for(b in 1:25){ mid<-sqrt(lo*hi); te<-te_ex(bl_w(Sig,vv,mid),Sig)
      if(!is.finite(te)){hi<-mid;next}; if(te>tgt)lo<-mid else hi<-mid }
    cmat[mi,k]<-sqrt(lo*hi) } }
pg("c calib done (%d months valid)\n",sum(is.finite(cmat[,1])))

## 월별 governing refit (일 t → 최근 refit mi with meix[mi] <= t)
gmi<-findInterval(seq_len(NS), meix)   # 0 = refit 이전

## ==== 공통: EW 일별 벤치 (분기말 리셋) ====
qend<-meix[which(as.integer(format(medates,"%m")) %% 3 == 0)]
ew_d<-numeric(NS); wE<-rep(1/7,7)
for(t in 1:NS){ ri<-RmatAll[t,]; ew_d[t]<-sum(wE*ri); wd<-wE*(1+ri); wE<-wd/sum(wd); if(t %in% qend) wE<-rep(1/7,7) }
mkt_d<-RmatAll[,1]

agg_m<-function(x){ dtx<-data.table(ym=ym,x=x); dtx[,prod(1+ifelse(is.finite(x),x,0))-1,by=ym]$V1 }
metrics_row<-function(net_d, dlt_d, lab, lm_mult, te, bps, first_t){
  sel<-first_t:NS
  pr<-agg_m(replace(net_d,seq_len(first_t-1),NA)); mk<-agg_m(replace(mkt_d,seq_len(first_t-1),NA)); ewm_<-agg_m(replace(ew_d,seq_len(first_t-1),NA))
  ## 유효 월 = first_t 이후 완전월만: 첫 부분월 제거
  fm<-ym[first_t]; mids<-which(unique(ym)>fm)
  pr<-pr[mids]; mk<-mk[mids]; ewm_<-ewm_[mids]
  actM<-pr-mk; actE<-pr-ewm_
  nav<-cumprod(1+ifelse(is.finite(net_d[sel]),net_d[sel],0)); mdd<-min(nav/cummax(nav)-1)
  data.table(arm=lab, featset=FEATSET, tune=TUNE, lam_mult=lm_mult, te=te, cost_bps=bps, acct_shift=SHIFT,
    placebo_seed=ifelse(nzchar(PSEED),as.integer(PSEED),NA_integer_), n_mo=length(pr),
    IR_vsMkt=IRf(actM), IR_vsEW=IRf(actE), pt_capwt=nwt(actM), abs_SR=IRf(pr),
    abs_CAGR=prod(1+pr)^(12/length(pr))-1, abs_MDD=mdd, TO_ann=mean(dlt_d[sel],na.rm=TRUE)*PER,
    series=list(list(pr=pr,actM=actM,actE=actE,months=unique(ym)[mids])))
}

RESULTS<-list()

## ==== ARM M0: 월간 보정 회계 ====
if("M0" %in% ARMS){
  keepm<-which(is.finite(cmat[,1]))
  for(k in seq_along(TE_T)){
    Wm<-matrix(NA_real_,NM,7)
    for(mi in keepm){ Wm[mi,]<-bl_w(SIG[,,meix[mi]],view_me[mi,],cmat[mi,k]) }
    k0<-keepm[1]; rng<-k0:NM
    mr<-as.matrix(mon[rng,..IDX]); Wr<-Wm[rng,,drop=FALSE]
    for(i in 2:nrow(Wr))if(any(!is.finite(Wr[i,])))Wr[i,]<-Wr[i-1,]
    Wr[!is.finite(Wr)]<-1/7
    ii<-2:nrow(mr); wprev<-rep(1/7,7)
    pr5<-numeric(length(ii)); pr15<-numeric(length(ii)); tov<-numeric(length(ii))
    ewv<-numeric(length(ii)); wE2<-rep(1/7,7)
    for(q in seq_along(ii)){ i<-ii[q]; wt<-Wr[i-1,]; ri<-mr[i,]
      gross<-sum(wt*ri); dlt<-sum(abs(wt-wprev)); tov[q]<-dlt
      pr5[q]<-gross-5e-4*dlt; pr15[q]<-gross-15e-4*dlt
      wd<-wt*(1+ri); wprev<-wd/sum(wd)
      ewv[q]<-sum(wE2*ri); wd2<-wE2*(1+ri); wE2<-wd2/sum(wd2)
      if(as.integer(format(mon$medate[rng[i]],"%m")) %% 3 == 0) wE2<-rep(1/7,7) }   # 달력 분기말 리셋 — D1 일별 EW와 동일 규약
    mk<-mr[ii,1]
    for(bps in c(5,15)){ pr<-if(bps==5)pr5 else pr15
      actM<-pr-mk; actE<-pr-ewv
      nav<-cumprod(1+pr); mdd<-min(nav/cummax(nav)-1)
      RESULTS[[length(RESULTS)+1]]<-data.table(arm="M0",featset=FEATSET,tune=TUNE,lam_mult=NA_real_,te=TE_T[k]*100,cost_bps=bps,acct_shift=NA_integer_,
        placebo_seed=ifelse(nzchar(PSEED),as.integer(PSEED),NA_integer_),
        n_mo=length(pr), IR_vsMkt=IRf(actM), IR_vsEW=IRf(actE), pt_capwt=nwt(actM), abs_SR=IRf(pr),
        abs_CAGR=prod(1+pr)^(12/length(pr))-1, abs_MDD=mdd, TO_ann=mean(tov)*12,
        series=list(list(pr=pr,actM=actM,actE=actE,months=as.character(mon$medate[rng[ii]])))) }
  }
  pg("M0 done\n")
}

## ==== ARM D1: 일별 온라인 + T+2 ====
if("D1" %in% ARMS){
  for(lm in LAMM){
    S<-online_states(lm)
    saveRDS(S,sprintf(".cache/_smv_v5_states_%s_lm%g.rds",KEY,lm))
    ## 일별 뷰: v[t,f] = refit[gmi[t]]$m_ann[S[t,f]]
    V<-matrix(NA_real_,NS,6)
    for(fi in seq_along(FACN)){ rl<-REF[[FACN[fi]]]
      for(t in seq_len(NS)){ mi<-gmi[t]; if(mi<1)next; rf<-rl[[mi]]; if(is.na(S[t,fi])||is.null(rf))next
        V[t,fi]<-rf$m_ann[S[t,fi]] } }
    if(!is.null(PERM)){  # placebo: 일별 뷰를 월-블록 단위로 순열 재배치 (타이밍 파괴, 분포 보존)
      Vp<-V
      for(mi in seq_len(NM)){ pm<-PERM[mi]; if(is.na(pm))next
        rows_dst<-which(gmi==mi); rows_src<-which(gmi==pm)
        if(!length(rows_dst)||!length(rows_src))next
        Vp[rows_dst,]<-V[rows_src[rep_len(seq_along(rows_src),length(rows_dst))],,drop=FALSE] }
      V<-Vp }
    for(k in seq_along(TE_T)){
      Wd<-matrix(NA_real_,NS,7)
      for(t in seq_len(NS)){ mi<-gmi[t]; if(mi<1)next
        cc<-cmat[mi,k]; if(!is.finite(cc))next
        vv<-V[t,]; if(any(!is.finite(vv)))next
        if(!is.finite(SIG[1,1,t]))next
        Wd[t,]<-bl_w(SIG[,,t],vv,cc) }
      ## T+2 회계
      dec_ok<-which(apply(Wd,1,function(r)all(is.finite(r))))
      if(length(dec_ok)<200){pg("D1 te=%g insufficient\n",TE_T[k]);next}
      first_t<-dec_ok[1]+max(SHIFT,1)
      net5<-rep(NA_real_,NS); net15<-rep(NA_real_,NS); dltv<-rep(NA_real_,NS)
      wheld<-rep(1/7,7)
      for(t in first_t:NS){ tgt<-if(SHIFT==0) Wd[t,] else Wd[t-SHIFT,]
        if(any(!is.finite(tgt))) tgt<-wheld
        ri<-RmatAll[t,]
        dlt<-sum(abs(tgt-wheld)); dltv[t]<-dlt
        gross<-sum(tgt*ri)
        net5[t]<-gross-5e-4*dlt; net15[t]<-gross-15e-4*dlt
        wd<-tgt*(1+ri); wheld<-wd/sum(wd) }
      for(bps in c(5,15)){ nd<-if(bps==5)net5 else net15
        RESULTS[[length(RESULTS)+1]]<-metrics_row(nd,dltv,"D1",lm,TE_T[k]*100,bps,first_t) }
      pg("D1 lm=%g te=%g done (first=%s)\n",lm,TE_T[k],as.character(R$Date[first_t]))
    }
  }
}

RES<-rbindlist(RESULTS)
out_csv<-RES[,!"series"]
fwrite(out_csv, sprintf("outputs/ramp/smv_v5_results_%s.csv",KEY))
saveRDS(list(RES=RES, idxfile=IDXFILE, featset=FEATSET, prereg="outputs/ramp/smv_v5_prereg_20260820.json",
             cmat=cmat, view_me=view_me, meix=meix, medates=medates),
        sprintf(".cache/_smv_v5_%s.rds",KEY))
cat("== v5 results (",KEY,") ==\n")
print(out_csv[order(arm,lam_mult,te,cost_bps)], digits=3, nrows=50)
cat("V5_DONE\n")
