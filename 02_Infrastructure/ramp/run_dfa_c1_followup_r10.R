## run_dfa_c1_followup_r10.R — R10: C1 후속 (prereg dfa_v11) A2~A5 + A1 밴드 보강증거
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

load_mon<-function(path){
  R<-as.data.table(read_parquet(path)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
  fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
  R[,ym:=format(Date,"%Y-%m")]
  mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
  setorder(mon,medate); list(mon=mon,fac=fac) }
BR<-load_mon("outputs/ramp/dfa_index_returns_broad_202608.parquet")

mk_sig<-function(mon,fac,win=12){
  NM<-nrow(mon); S<-matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
  for(fi in seq_along(fac)){ f<-fac[fi]
    for(m in win:NM){ w<-(m-win+1):m
      S[m,fi]<-prod(1+mon[[f]][w])/prod(1+mon$Market[w])-1 } }
  S }
## mode: cont(비례) | rank(순위) ; freq: 1(월간) | 3(분기)
run_arm<-function(mon,fac,S,mode="cont",bps=15,freq=1,start_m=13){
  NM<-nrow(mon); NAx<-1+length(fac)
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM); wprev<-rep(1/NAx,NAx); wcur<-NULL
  for(m in start_m:NM){ d<-m-1
    if(is.null(wcur) || ((m-start_m) %% freq == 0)){
      s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(length(pos)==0){ w[1]<-1 } else if(mode=="cont"){ w[1+pos]<-s[pos]/sum(s[pos])
      } else { rk<-rank(s[pos]); w[1+pos]<-rk/sum(rk) }
      wcur<-w }
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt
    pr[m]<-sum(wcur*ri)-(bps/1e4)*dlt
    wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
  list(pr=pr,tov=tov) }
mets<-function(mon,pr,tov){ k<-is.finite(pr); p<-pr[k]; mk<-mon$Market[k]
  act<-p-mk; nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); n<-length(p)
  post17<-format(mon$medate[k],"%Y")>="2017"
  data.table(n_mo=n,pt_vsMkt=nwt(act),IR_vsMkt=IRf(act),SR=IRf(p),
    CAGR=prod(1+p)^(12/n)-1,MDD=mdd,calmar=(prod(1+p)^(12/n)-1)/abs(mdd),
    TO_ann=mean(tov[k],na.rm=TRUE)*12,pt_post17=nwt(act[post17])) }

S12<-mk_sig(BR$mon,BR$fac,12); S6<-mk_sig(BR$mon,BR$fac,6); S24<-mk_sig(BR$mon,BR$fac,24)
ARMS<-list(
  C1_base =list(S=S12,mode="cont",freq=1,start=13),
  A2_rank =list(S=S12,mode="rank",freq=1,start=13),
  A3_win6 =list(S=S6, mode="cont",freq=1,start=13),
  A4_win24=list(S=S24,mode="cont",freq=1,start=25),
  A5_quart=list(S=S12,mode="cont",freq=3,start=13))
OUT<-list(); SER<-list()
for(an in names(ARMS)){ a<-ARMS[[an]]
  for(bps in c(5,15)){ r<-run_arm(BR$mon,BR$fac,a$S,a$mode,bps,a$freq,a$start)
    m<-mets(BR$mon,r$pr,r$tov); OUT[[length(OUT)+1]]<-cbind(data.table(arm=an,cost_bps=bps),m)
    SER[[sprintf("%s_%d",an,bps)]]<-list(mon=BR$mon,pr=r$pr,tov=r$tov) } }
RES<-rbindlist(OUT)
for(an in setdiff(names(ARMS),"C1_base")) for(bps in c(5,15)){
  s0<-SER[[sprintf("C1_base_%d",bps)]]; s1<-SER[[sprintf("%s_%d",an,bps)]]
  k<-is.finite(s0$pr)&is.finite(s1$pr)
  RES[arm==an&cost_bps==bps, paired_nwt_vs_C1:=nwt((s1$pr-s0$pr)[k])] }
cat("== R10 C1 후속 (broad-21, 사전등록 A2~A5) ==\n"); print(RES,digits=3)

## ---- A1: 밴드 보강증거 (C1 기준선 15bps) ----
cat("\n== A1 oos 밴드 보강증거 (C1 15bps) ==\n")
s<-SER[["C1_base_15"]]; k<-which(is.finite(s$pr)); p<-s$pr[k]; mk<-s$mon$Market[k]; act<-p-mk
n<-length(p); tw<-tail(seq_len(n), floor(n/3))
cat(sprintf("  (i) trailing 1/3 PORT_t = %.3f (n=%d) -> %s\n",nwt(act[tw]),length(tw),ifelse(nwt(act[tw])>0,"PASS","FAIL")))
cat(sprintf("  (ii) placebo p (R7 기산출, 30-seed 월블록 셔플) = 0.000 -> PASS\n"))
cat(sprintf("  (iii) book-marginal: 별도 산출 필요 (production base 대비) -> 미산출\n"))
## essence 계약 채점 (전 팔 15bps)
cat("\n== essence 계약 채점 (15bps) ==\n")
for(an in names(ARMS)){ ser<-SER[[sprintf("%s_15",an)]]; kk<-is.finite(ser$pr)
  d<-ser$mon$medate[kk]; p2<-ser$pr[kk]; m2<-ser$mon$Market[kk]
  sim<-list(DAILY_NAV_DT=data.table(Date=d,Strategy_Ret=p2,NAV=cumprod(1+p2)),
            strategy_xts=xts(p2,order.by=d),bm_xts=xts(m2,order.by=d),cost_model_version="fm_r10_15bps")
  spec<-list(strategy_name=sprintf("DFA_FM_R10_%s",an),description="C1 후속 (R10)",universe="KR broad-21",
             rebalance=ifelse(an=="A5_quart","quarterly","monthly"),signal="factor momentum")
  bt<-build_bt_result(sim,spec,run_id=sprintf("fm_r10_%s",tolower(an)),strategy_id=sprintf("DFA_FM_R10_%s",toupper(an)),
      benchmark_id="CAPW_PARENT",benchmark_name="cap-w parent",transaction_cost_bps=15,slippage_bps=0,
      frequency="monthly",universe_id="K200_KQ150",code_version="run_dfa_c1_followup_r10.R",created_by_agent="Q-Lead")
  es<-essence_score(bt,n_trials_cumulative=56,selection_type="chain")
  e<-es$essence
  cat(sprintf("  [%s] grade=%s pt=%.3f oos=%.3f calmar=%.3f SR=%.2f MDD=%.3f | HARD pt%s oos%s cal%s\n",
    an,es$grade,e$portfolio_alpha_t_nw_lag3,e$oos_retention,e$calmar,e$net_sharpe,e$mdd,
    ifelse(e$portfolio_alpha_t_nw_lag3>=2.95,"P","F"),
    ifelse(is.finite(e$oos_retention)&&e$oos_retention>=0.7,"P",ifelse(is.finite(e$oos_retention)&&e$oos_retention>=0.5,"b","F")),
    ifelse(e$calmar>=0.64,"P","F"))) }
fwrite(RES,"outputs/ramp/dfa_c1_followup_r10_20260822.csv")
saveRDS(SER,".cache/_dfa_c1_followup_r10.rds")
cat("R10_DONE\n")
