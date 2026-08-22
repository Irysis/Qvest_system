## run_dfa_a5e_ensemble_r12.R — R12: A5E 3-코호트 중첩 앙상블 (prereg dfa_v11 amendment_1)
## 위상 아티팩트 제거: 매월 자본 1/3이 재결정, 각 코호트 3개월 홀딩. 전체 = 3코호트 평균.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
set.seed(20260822)
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NAx<-1+length(fac)
S<-matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
for(fi in seq_along(fac)) for(m in 12:NM){ w<-(m-11):m; S[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
## 코호트 c(0,1,2): 시작월 13+c, 3개월마다 재결정. 각 코호트 자본 1/3.
run_ens<-function(bps=15,dec_lag=1,perm=NULL,freq=3,ncoh=3,start0=13){
  Sx<-if(is.null(perm)) S else S[perm,,drop=FALSE]
  st_all<-start0+ncoh-1                       # 전 코호트 가동 시점부터 집계
  W<-array(NA_real_,c(ncoh,NM,NAx)); pr_c<-matrix(NA_real_,ncoh,NM); to_c<-matrix(NA_real_,ncoh,NM)
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
  for(m in st_all:NM){ v<-pr_c[,m]; t2<-to_c[,m]
    if(all(is.finite(v))){ pr[m]<-mean(v); tov[m]<-mean(t2)/1 } }   # 자본 1/3씩 → 전체 회전율 = 코호트 평균
  list(pr=pr,tov=tov) }
M<-function(r){ k<-is.finite(r$pr); p<-r$pr[k]; mk<-mon$Market[k]; act<-p-mk
  nav<-cumprod(1+p); n<-length(p)
  list(pt=nwt(act),IR=IRf(act),SR=IRf(p),MDD=min(nav/cummax(nav)-1),
       CAGR=prod(1+p)^(12/n)-1,TO=mean(r$tov[k],na.rm=TRUE)*12,n=n,act=act,k=k,pr=p,mk=mk,d=mon$medate[k]) }
cat("== R12 A5E 3-코호트 중첩 앙상블 (위상 아티팩트 제거) ==\n\n[핵심 셀]\n")
for(bps in c(5,15)){ m<-M(run_ens(bps))
  cat(sprintf("  %2dbps: pt=%.3f IR=%.3f SR=%.3f MDD=%.3f calmar=%.3f TO=%.2f n=%d\n",
    bps,m$pt,m$IR,m$SR,m$MDD,m$CAGR/abs(m$MDD),m$TO,m$n)) }
cat("\n[게이트②③ shift 사다리 — 15bps]\n")
for(dl in c(0,1,2)){ m<-M(run_ens(15,dl)); cat(sprintf("  dec_lag=%d(%s): pt=%.3f IR=%.3f\n",dl,
  c("동월(고의)","정본 m-1","lag1 m-2")[dl+1],m$pt,m$IR)) }
cat("\n[게이트④ placebo 30-seed — 15bps]\n")
b<-M(run_ens(15)); ps<-replicate(30,{ M(run_ens(15,1,perm=sample(NM)))$IR })
cat(sprintf("  real IR=%.3f | placebo mean=%.3f sd=%.3f | p=%.3f\n",b$IR,mean(ps,na.rm=TRUE),sd(ps,na.rm=TRUE),mean(ps>=b$IR,na.rm=TRUE)))
cat("\n[시대분해 — 15bps]\n"); yy<-format(b$d,"%Y")
for(seg in list(c("2007","2011"),c("2012","2016"),c("2017","2021"),c("2022","2026"))){
  s<-yy>=seg[1]&yy<=seg[2]; if(sum(s)>=12) cat(sprintf("  %s-%s: n=%3d pt=%+.3f IR=%+.3f\n",seg[1],seg[2],sum(s),nwt(b$act[s]),IRf(b$act[s]))) }
cat("\n[비용 민감도]\n"); for(bp in c(5,15,25,40)){ m<-M(run_ens(bp)); cat(sprintf("  %2dbps: pt=%.3f\n",bp,m$pt)) }
cat("\n[essence 계약 채점 — 15bps]\n")
sim<-list(DAILY_NAV_DT=data.table(Date=b$d,Strategy_Ret=b$pr,NAV=cumprod(1+b$pr)),
          strategy_xts=xts(b$pr,order.by=b$d),bm_xts=xts(b$mk,order.by=b$d),cost_model_version="fm_a5e_15bps")
spec<-list(strategy_name="DFA_FM_A5E",description="팩터모멘텀 3-코호트 중첩 앙상블 (broad-21, 연속가중, 분기홀딩)",
           universe="KR broad-21 style indices",rebalance="monthly 1/3 cohort (quarterly holding)",signal="trailing 12M active momentum")
bt<-build_bt_result(sim,spec,run_id="fm_a5e_20260822",strategy_id="DFA_FM_A5E",
    benchmark_id="CAPW_PARENT",benchmark_name="cap-w parent",transaction_cost_bps=15,slippage_bps=0,
    frequency="monthly",universe_id="K200_KQ150",code_version="run_dfa_a5e_ensemble_r12.R",created_by_agent="Q-Lead")
au<-audit_bt_result(bt); es<-essence_score(bt,n_trials_cumulative=58,selection_type="chain")
e<-es$essence
cat(sprintf("  grade=%s audit=%s | pt=%.3f oos=%.3f calmar=%.3f SR=%.2f MDD=%.3f DSR=%.3f\n",
  es$grade,au$integrity,e$portfolio_alpha_t_nw_lag3,e$oos_retention,e$calmar,e$net_sharpe,e$mdd,e$dsr))
cat(sprintf("  HARD: PORT_t %s | oos %s | calmar %s | 밴드=%s\n",
  ifelse(e$portfolio_alpha_t_nw_lag3>=2.95,"PASS","FAIL"),
  ifelse(is.finite(e$oos_retention)&&e$oos_retention>=0.7,"PASS",ifelse(is.finite(e$oos_retention)&&e$oos_retention>=0.5,"BAND","FAIL")),
  ifelse(e$calmar>=0.64,"PASS","FAIL"), es$oos_band_status))
cat(sprintf("  oos splits: %s\n",paste(es$oos_retention_splits,collapse=" / ")))
saveRDS(list(base=b,essence=es),".cache/_dfa_a5e_r12.rds")
cat("R12_DONE\n")
