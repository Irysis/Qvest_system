suppressPackageStartupMessages({library(data.table);library(arrow);library(xts);library(sandwich);library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/essence_score.R")
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}

## ---- independent monthly build ----
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
R[,ymk:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ymk,.SDcols=c("Market",fac)]
setorder(mon,medate)
NM<-nrow(mon); cat("NM months =",NM," range",format(min(mon$medate)),"~",format(max(mon$medate)),"\n")

sig<-function(win){ S<-matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
  for(fi in seq_along(fac)){f<-fac[fi]; for(m in win:NM){w<-(m-win+1):m
    S[m,fi]<-prod(1+mon[[f]][w])/prod(1+mon$Market[w])-1}}; S }
S12<-sig(12)

## arm engine: phase-shifted rebalance schedule, window fixed
arm<-function(S,mode="cont",bps=15,freq=1,start_m=13,phase=0){
  NAx<-1+length(fac); pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  wprev<-rep(1/NAx,NAx); wcur<-NULL
  for(m in start_m:NM){ d<-m-1
    if(is.null(wcur) || ((m-start_m-phase) %% freq == 0)){
      s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(length(pos)==0){w[1]<-1} else if(mode=="cont"){w[1+pos]<-s[pos]/sum(s[pos])} else {rk<-rank(s[pos]);w[1+pos]<-rk/sum(rk)}
      wcur<-w }
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; pr[m]<-sum(wcur*ri)-(bps/1e4)*dlt
    wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
  list(pr=pr,tov=tov) }

## ---- 1. parity vs cached SER ----
SER<-readRDS(".cache/_dfa_c1_followup_r10.rds"); cat("cache arms:",paste(names(SER),collapse=", "),"\n")
a5<-arm(S12,"cont",15,3,13,0)
ref<-SER[["A5_quart_15"]]
k<-is.finite(a5$pr)&is.finite(ref$pr)
cat(sprintf("PARITY A5 pr: n=%d maxabs=%.3e | tov maxabs=%.3e\n",sum(k),max(abs(a5$pr[k]-ref$pr[k])),max(abs(a5$tov[k]-ref$tov[k]),na.rm=TRUE)))
cat(sprintf("PARITY mon rows: mine=%d cache=%d  Market maxabs=%.3e\n",NM,nrow(ref$mon),max(abs(mon$Market-ref$mon$Market))))

sc<-function(p,tag,ntr=56,sel="chain"){ kk<-is.finite(p); d<-mon$medate[kk]; p2<-p[kk]; m2<-mon$Market[kk]
  sim<-list(DAILY_NAV_DT=data.table(Date=d,Strategy_Ret=p2,NAV=cumprod(1+p2)),
    strategy_xts=xts(p2,order.by=d),bm_xts=xts(m2,order.by=d),cost_model_version="adv")
  spec<-list(strategy_name=tag,description="adv refute",universe="KR broad-21",rebalance="quarterly",signal="factor momentum")
  bt<-build_bt_result(sim,spec,run_id=tolower(tag),strategy_id=toupper(tag),benchmark_id="CAPW_PARENT",
    benchmark_name="cap-w parent",transaction_cost_bps=15,slippage_bps=0,frequency="monthly",
    universe_id="K200_KQ150",code_version="adv_r03",created_by_agent="adversary")
  es<-essence_score(bt,n_trials_cumulative=ntr,selection_type=sel); e<-es$essence
  data.table(tag=tag,n=length(p2),grade=es$grade,pt=e$portfolio_alpha_t_nw_lag3,oos=e$oos_retention,
    splits=paste(round(es$oos_retention_splits,4),collapse="/"),calmar=e$calmar,SR=e$net_sharpe,MDD=e$mdd,dsr=e$dsr) }

cat("\n== 2. contract scoring, independent rebuild ==\n")
T1<-sc(a5$pr,"ADV_A5"); print(T1)
cat("  my nwt(active) =",round(nwt(a5$pr[k]-mon$Market[k]),4)," IR=",round(IRf(a5$pr[k]-mon$Market[k]),4),
    " TO_ann=",round(mean(a5$tov[k])*12,4),"\n")

cat("\n== 3. phase (window fixed, n identical) ==\n")
PH<-rbindlist(lapply(0:2,function(p){r<-arm(S12,"cont",15,3,13,p); x<-sc(r$pr,paste0("ADV_A5_ph",p)); x[,to:=mean(r$tov[is.finite(r$pr)])*12]; x}))
print(PH)
prs<-lapply(0:2,function(p)arm(S12,"cont",15,3,13,p)$pr)
ens<-Reduce(`+`,prs)/3
cat("\n== 4. A5E 3-cohort ensemble ==\n"); print(sc(ens,"ADV_A5E"))
kk<-is.finite(prs[[1]])
cat("  paired nwt(ph0-ph1) =",round(nwt(prs[[1]][kk]-prs[[2]][kk]),4),
    " (ph0-ph2) =",round(nwt(prs[[1]][kk]-prs[[3]][kk]),4),"\n")

cat("\n== 5. cost sensitivity: A5 vs C1 at 0 / 5 / 15 / 30 bps ==\n")
CS<-rbindlist(lapply(c(0,5,15,30),function(b){
  aa<-arm(S12,"cont",b,3,13,0); cc<-arm(S12,"cont",b,1,13,0); kk<-is.finite(aa$pr)&is.finite(cc$pr)
  data.table(bps=b, A5_pt=nwt(aa$pr[kk]-mon$Market[kk]), C1_pt=nwt(cc$pr[kk]-mon$Market[kk]),
    A5_IR=IRf(aa$pr[kk]-mon$Market[kk]), C1_IR=IRf(cc$pr[kk]-mon$Market[kk]),
    paired_nwt_A5_minus_C1=nwt((aa$pr-cc$pr)[kk]),
    A5_TO=mean(aa$tov[kk])*12, C1_TO=mean(cc$tov[kk])*12) }))
print(CS,digits=4)
saveRDS(list(mon=mon,fac=fac,S12=S12,a5=a5,prs=prs),"stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds")
cat("\nR03_DONE\n")
