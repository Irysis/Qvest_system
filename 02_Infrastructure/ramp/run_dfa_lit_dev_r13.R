## run_dfa_lit_dev_r13.R — R13: 후속·인접 문헌 반영 발전 (prereg dfa_v12)
## B1 다중지평(Gupta-Kelly) · B2 변동성표준화 · B3 절대모멘텀(Bosancic 대조) · B4 breadth 익스포저(2024a 이식)
## 전 팔은 A5E 골격(3-코호트 중첩 앙상블, broad-21, 월말결정→익월, 분기홀딩) 위에서 신호/가중만 교체
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/contracts/backtest_result_contract.R"); source("02_Infrastructure/contracts/audit_bt_result.R"); source("02_Infrastructure/contracts/essence_score.R")
set.seed(20260822)
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NF<-length(fac); NAx<-1+NF
ACT<-matrix(NA_real_,NM,NF); colnames(ACT)<-fac
for(fi in seq_along(fac)) ACT[,fi]<-mon[[fac[fi]]]-mon$Market      # 월별 active
RAW<-matrix(NA_real_,NM,NF); for(fi in seq_along(fac)) RAW[,fi]<-mon[[fac[fi]]]  # 절대수익

## ---- 신호 생성기 (전부 결정월 d 까지의 정보만) ----
sig_h<-function(M_,h){ S<-matrix(NA_real_,NM,NF)
  for(fi in 1:NF) for(m in h:NM){ w<-(m-h+1):m; S[m,fi]<-prod(1+M_[w,fi]+ifelse(FALSE,0,0))-1 }
  S }   # 누적(단순): active 월수익 누적
sig_cum<-function(M_,h){ S<-matrix(NA_real_,NM,NF)
  for(fi in 1:NF){ x<-M_[,fi]
    for(m in h:NM) S[m,fi]<-sum(x[(m-h+1):m],na.rm=TRUE) }
  S }
## B0: 12M active 누적비 (A5E 원형 — mon 기준 compounding)
S_A5E<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM){ w<-(m-11):m; S_A5E[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
## B1: 다중지평 표준화 결합 (h=1,3,6,12 각각 횡단면 sd 로 표준화 후 평균)
S_B1<-matrix(NA_real_,NM,NF)
{ Hs<-c(1,3,6,12); Zs<-vector("list",length(Hs))
  for(i in seq_along(Hs)){ h<-Hs[i]; Sh<-sig_cum(ACT,h)
    Z<-Sh; for(m in 1:NM){ v<-Sh[m,]; s<-sd(v,na.rm=TRUE); if(is.finite(s)&&s>0) Z[m,]<-v/s else Z[m,]<-NA }
    Zs[[i]]<-Z }
  for(m in 1:NM) for(fi in 1:NF){ v<-sapply(Zs,function(Z)Z[m,fi]); if(all(is.finite(v))) S_B1[m,fi]<-mean(v) } }
## B2: 변동성 표준화 (act12 / trailing 12M active sd)
S_B2<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM){ w<-(m-11):m; sdv<-sd(ACT[w,fi],na.rm=TRUE)
  if(is.finite(sdv)&&sdv>0) S_B2[m,fi]<-S_A5E[m,fi]/sdv }
## B3: 절대 모멘텀 (팩터 절대수익 12M 누적)
S_B3<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM){ w<-(m-11):m; S_B3[m,fi]<-prod(1+RAW[w,fi])-1 }

## ---- 앙상블 실행기 (A5E 골격) ----
run_ens<-function(S,bps=15,dec_lag=1,perm=NULL,freq=3,ncoh=3,start0=13,exposure=NULL){
  Sx<-if(is.null(perm)) S else S[perm,,drop=FALSE]
  st_all<-start0+ncoh-1
  pr_c<-matrix(NA_real_,ncoh,NM); to_c<-matrix(NA_real_,ncoh,NM)
  for(cc in 0:(ncoh-1)){ st<-start0+cc; wprev<-rep(1/NAx,NAx); wcur<-NULL
    for(m in st:NM){ d<-m-dec_lag; if(d<1) next
      if(is.null(wcur) || ((m-st)%%freq==0)){
        s<-Sx[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
        if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
      ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
      dlt<-sum(abs(wcur-wprev)); to_c[cc+1,m]<-dlt
      pr_c[cc+1,m]<-sum(wcur*ri)-(bps/1e4)*dlt
      wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev } }
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  for(m in st_all:NM){ if(all(is.finite(pr_c[,m]))){ pr[m]<-mean(pr_c[,m]); tov[m]<-mean(to_c[,m]) } }
  if(!is.null(exposure)){ ex<-exposure; dex<-abs(diff(c(1,ex))); pr<-ex*pr-(bps/1e4)*dex; tov<-tov+dex }
  list(pr=pr,tov=tov) }
M<-function(r){ k<-is.finite(r$pr); p<-r$pr[k]; mk<-mon$Market[k]; act<-p-mk
  nav<-cumprod(1+p); n<-length(p)
  list(pt=nwt(act),IR=IRf(act),SR=IRf(p),MDD=min(nav/cummax(nav)-1),
       CAGR=prod(1+p)^(12/n)-1,calmar=(prod(1+p)^(12/n)-1)/abs(min(nav/cummax(nav)-1)),
       TO=mean(r$tov[k],na.rm=TRUE)*12,n=n,act=act,k=k,pr=p,mk=mk,d=mon$medate[k]) }
## B4: breadth 익스포저 벡터 (결정 d=m-1 의 breadth)
breadth<-rep(NA_real_,NM)
for(m in 12:NM){ s<-S_A5E[m,]; breadth[m]<-mean(is.finite(s)&s>0) }
ex_b4<-0.70+0.30*shift(breadth,1); ex_b4[!is.finite(ex_b4)]<-1.00

cat("== R13 문헌 반영 발전 (A5E 골격 위) ==\n")
ARMS<-list(A5E_base=list(S=S_A5E,ex=NULL), B1_multihorizon=list(S=S_B1,ex=NULL),
           B2_volscaled=list(S=S_B2,ex=NULL), B3_absolute=list(S=S_B3,ex=NULL),
           B4_breadth_exp=list(S=S_A5E,ex=ex_b4))
OUT<-list(); SER<-list()
for(an in names(ARMS)){ a<-ARMS[[an]]
  for(bps in c(5,15)){ r<-run_ens(a$S,bps,exposure=a$ex); m<-M(r)
    OUT[[length(OUT)+1]]<-data.table(arm=an,cost_bps=bps,n_mo=m$n,pt=m$pt,IR=m$IR,SR=m$SR,
      CAGR=m$CAGR,MDD=m$MDD,calmar=m$calmar,TO=m$TO)
    SER[[sprintf("%s_%d",an,bps)]]<-r } }
RES<-rbindlist(OUT)
for(an in setdiff(names(ARMS),"A5E_base")) for(bps in c(5,15)){
  s0<-SER[[sprintf("A5E_base_%d",bps)]]$pr; s1<-SER[[sprintf("%s_%d",an,bps)]]$pr
  k<-is.finite(s0)&is.finite(s1); RES[arm==an&cost_bps==bps, paired_nwt:=nwt((s1-s0)[k])] }
print(RES,digits=3)
cat("\n[B4 breadth 분포] 중앙:",round(median(breadth,na.rm=TRUE),3),
    "| 최소:",round(min(breadth,na.rm=TRUE),3),"| 평균 노출:",round(mean(ex_b4,na.rm=TRUE),3),"\n")
cat("\n[essence 계약 채점 — 15bps]\n")
for(an in names(ARMS)){ r<-SER[[sprintf("%s_15",an)]]; m<-M(r)
  sim<-list(DAILY_NAV_DT=data.table(Date=m$d,Strategy_Ret=m$pr,NAV=cumprod(1+m$pr)),
            strategy_xts=xts(m$pr,order.by=m$d),bm_xts=xts(m$mk,order.by=m$d),cost_model_version="fm_r13_15bps")
  spec<-list(strategy_name=sprintf("DFA_FM_R13_%s",an),description="R13 문헌반영",universe="KR broad-21",
             rebalance="monthly 1/3 cohort",signal=an)
  bt<-build_bt_result(sim,spec,run_id=sprintf("fm_r13_%s",tolower(an)),strategy_id=sprintf("DFA_FM_R13_%s",toupper(an)),
      benchmark_id="CAPW_PARENT",benchmark_name="cap-w parent",transaction_cost_bps=15,slippage_bps=0,
      frequency="monthly",universe_id="K200_KQ150",code_version="run_dfa_lit_dev_r13.R",created_by_agent="Q-Lead")
  es<-essence_score(bt,n_trials_cumulative=63,selection_type="chain"); e<-es$essence
  cat(sprintf("  [%-16s] grade=%s pt=%.3f oos=%.3f calmar=%.3f MDD=%.3f | HARD pt%s oos%s cal%s\n",
    an,es$grade,e$portfolio_alpha_t_nw_lag3,e$oos_retention,e$calmar,e$mdd,
    ifelse(e$portfolio_alpha_t_nw_lag3>=2.95,"P","F"),
    ifelse(is.finite(e$oos_retention)&&e$oos_retention>=0.7,"P",ifelse(is.finite(e$oos_retention)&&e$oos_retention>=0.5,"b","F")),
    ifelse(e$calmar>=0.64,"P","F"))) }
fwrite(RES,"outputs/ramp/dfa_lit_dev_r13_20260822.csv"); saveRDS(SER,".cache/_dfa_lit_dev_r13.rds")
cat("R13_DONE\n")
