suppressPackageStartupMessages({library(data.table);library(xts);library(sandwich);library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R"); source("02_Infrastructure/contracts/essence_score.R")
Z<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds"); mon<-Z$mon; fac<-Z$fac; S<-Z$S12
NM<-nrow(mon); NAx<-1+length(fac); RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0
nwt<-function(x){x<-x[is.finite(x)];m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
## fast NW t (Bartlett lag3) — validated below
fnw<-function(x){n<-length(x);mu<-mean(x);e<-x-mu;g<-sapply(0:3,function(j)sum(e[(1+j):n]*e[1:(n-j)])/n)
  V<-g[1]+2*sum((1-(1:3)/4)*g[2:4]); mu/sqrt(V/n)*sqrt(n/(n-1))}
sc<-function(p,mk,d,tag,ntr){ sim<-list(DAILY_NAV_DT=data.table(Date=d,Strategy_Ret=p,NAV=cumprod(1+p)),
    strategy_xts=xts(p,order.by=d),bm_xts=xts(mk,order.by=d),cost_model_version="adv")
  spec<-list(strategy_name=tag,description="adv",universe="KR broad-21",rebalance="q",signal="fm")
  bt<-build_bt_result(sim,spec,run_id=tolower(tag),strategy_id=toupper(tag),benchmark_id="CAPW_PARENT",
    benchmark_name="cap-w parent",transaction_cost_bps=15,slippage_bps=0,frequency="monthly",
    universe_id="K200_KQ150",code_version="adv_r06",created_by_agent="adversary")
  es<-essence_score(bt,n_trials_cumulative=ntr,selection_type="chain"); e<-es$essence
  data.table(tag=tag,n=length(p),pt=e$portfolio_alpha_t_nw_lag3,oos=e$oos_retention,
    splits=paste(round(es$oos_retention_splits,3),collapse="/"),calmar=e$calmar,dsr=e$dsr,band=es$oos_band_status) }

## ==== A. faithful R12 cohort ensemble (official prereg amendment implementation) ====
run_ens<-function(bps=15,freq=3,ncoh=3,start0=13){
  st_all<-start0+ncoh-1; pr_c<-matrix(NA_real_,ncoh,NM); to_c<-matrix(NA_real_,ncoh,NM)
  for(cc in 0:(ncoh-1)){ st<-start0+cc; wprev<-rep(1/NAx,NAx); wcur<-NULL
    for(m in st:NM){ d<-m-1
      if(is.null(wcur)||((m-st)%%freq==0)){ s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
        if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
      ri<-RET[m,]; dlt<-sum(abs(wcur-wprev)); to_c[cc+1,m]<-dlt
      pr_c[cc+1,m]<-sum(wcur*ri)-(bps/1e4)*dlt
      wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev } }
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  for(m in st_all:NM){ if(all(is.finite(pr_c[,m]))){pr[m]<-mean(pr_c[,m]); tov[m]<-mean(to_c[,m])} }
  list(pr=pr,tov=tov) }
cat("== A. A5E official (R12 cohort, start_all=15) vs peer's variant ==\n")
r<-run_ens(); k<-is.finite(r$pr)
print(sc(r$pr[k],mon$Market[k],mon$medate[k],"ADV_A5E_R12",58))
cat("   fnw check: sandwich=",round(nwt(r$pr[k]-mon$Market[k]),4)," fast=",round(fnw(r$pr[k]-mon$Market[k]),4),"\n")
cat("   cached R12 official pt =",round(readRDS(".cache/_dfa_a5e_r12.rds")$base$pt,4),
    " n=",readRDS(".cache/_dfa_a5e_r12.rds")$base$n,"\n")
## start0 sensitivity of the "phase-free" arbiter
cat("\n   A5E start0 sensitivity (hidden dof):\n")
for(s0 in 13:18){ rr<-run_ens(15,3,3,s0); kk<-is.finite(rr$pr)
  cat(sprintf("     start0=%d n=%d pt=%.3f\n",s0,sum(kk),nwt(rr$pr[kk]-mon$Market[kk]))) }

## ==== B. two-sided bootstrap crit, larger B ====
kA<-is.finite(Z$a5$pr); A<-Z$a5$pr[kA]-mon$Market[kA]; n<-length(A); Ac<-A-mean(A)
set.seed(11); B<-20000; bl<-12; st<-numeric(B)
for(b in 1:B){ idx<-unlist(lapply(1:ceiling(n/bl),function(i)((sample(n,1)+0:(bl-1)-1)%%n)+1))[1:n]; st[b]<-fnw(Ac[idx]) }
o<-fnw(A)
cat(sprintf("\n== B. H0(mean active=0) block bootstrap, B=%d, obs pt=%.4f ==\n",B,o))
cat(sprintf("   null mean=%.3f sd=%.3f | one-sided p=%.5f | two-sided p=%.5f\n",mean(st),sd(st),mean(st>=o),mean(abs(st)>=abs(o))))
for(N in c(1,5,7,20,56,84)) cat(sprintf("   N=%2d Bonferroni crit: one-sided=%.3f two-sided=%.3f | FWER(indep) 1s=%.4f\n",
   N,quantile(st,1-0.05/N),quantile(abs(st),1-0.05/N),1-(1-mean(st>=o))^N))
