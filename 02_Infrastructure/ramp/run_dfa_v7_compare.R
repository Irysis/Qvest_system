## run_dfa_v7_compare.R — R3-B/R3-C 판정 대조 (prereg smv_v7: 공통창 window-matched + paired NW-t)
## R3-B: MINY5 vs MINY8(기준선) — 공통창(양쪽 유효 월 교집합) 1차 + 전체창 병기
## R3-C: H1-q95(정렬 트리거) vs 기준선 M0-roll — 동일창
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
.rds<-function(k){p<-sprintf(".cache/_dfa_v5_%s.rds",k); if(file.exists(p))p else sprintf(".cache/_smv_v5_%s.rds",k)}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

get_series<-function(key,armn,te,bps){ Z<-readRDS(.rds(key)); R<-Z$RES
  i<-which(R$arm==armn & R$te==te & R$cost_bps==bps); if(!length(i))return(NULL)
  s<-R$series[[i[1]]]; if(is.null(s))return(NULL)
  data.table(ym=substr(as.character(s$months),1,7), pr=s$pr, actM=s$actM) }

mets<-function(d){ nav<-cumprod(1+d$pr); mdd<-min(nav/cummax(nav)-1); n<-nrow(d)
  cagr<-prod(1+d$pr)^(12/n)-1
  data.table(n_mo=n, pt=nwt(d$actM), IR_vsMkt=IRf(d$actM), SR=IRf(d$pr), CAGR=cagr, MDD=mdd, calmar=cagr/abs(mdd)) }

cmp<-function(kA,kB,armA,armB,lab,te=3){
  out<-list()
  for(bps in c(5,15)){ A<-get_series(kA,armA,te,bps); B<-get_series(kB,armB,te,bps)
    if(is.null(A)||is.null(B))next
    ymc<-intersect(A$ym,B$ym); Ac<-A[ym %in% ymc][order(ym)]; Bc<-B[ym %in% ymc][order(ym)]
    mA<-mets(Ac); mB<-mets(Bc); pt_d<-nwt(Ac$actM-Bc$actM)
    out[[length(out)+1]]<-data.table(compare=lab,cost_bps=bps,n_common=length(ymc),
      arm=c("test","base"), pt=c(mA$pt,mB$pt), IR=c(mA$IR_vsMkt,mB$IR_vsMkt),
      SR=c(mA$SR,mB$SR), MDD=c(mA$MDD,mB$MDD), calmar=c(mA$calmar,mB$calmar),
      paired_nwt=c(pt_d,NA)) }
  rbindlist(out) }

R3B<-cmp("f15_roll_m5","f15_roll","M0","M0","R3B_MINY5_vs_MINY8")
R3C<-cmp("f15_roll_h1q95","f15_roll","H1","M0","R3C_H1q95_vs_M0")
ALL<-rbind(R3B,R3C)
fwrite(ALL,"outputs/ramp/dfa_v7_compare_20260821.csv")
cat("== R3-B / R3-C 공통창 대조 (TE3) ==\n"); print(ALL,digits=3)

## 전체창 병기 (MINY5는 창이 더 길다 — 별도 라벨)
full5<-get_series("f15_roll_m5","M0",3,5); if(!is.null(full5)){
  cat(sprintf("\n[R3-B 전체창 병기] MINY5 n=%d %s~%s | ",nrow(full5),min(full5$ym),max(full5$ym)))
  print(mets(full5),digits=3) }

## 헤드라인 셀 계약 채점 (개선 후보만)
mon_bm<-{R<-as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns_202608.parquet",col_select=c("Date","Market")))
  R[,Date:=as.Date(Date)];R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
  R[,.(mkt=prod(1+Market)-1, d=max(Date)),by=ym]}
score_cell<-function(key,armn,bps,sid){
  s<-get_series(key,armn,3,bps); if(is.null(s))return(NULL)
  i<-match(s$ym,mon_bm$ym); d<-mon_bm$d[i]; mk<-mon_bm$mkt[i]
  k<-is.finite(s$pr)&is.finite(mk)
  sim<-list(DAILY_NAV_DT=data.table(Date=d[k],Strategy_Ret=s$pr[k],NAV=cumprod(1+s$pr[k])),
            strategy_xts=xts(s$pr[k],order.by=d[k]), bm_xts=xts(mk[k],order.by=d[k]),
            cost_model_version=sprintf("dfa_v7_%dbps",bps))
  spec<-list(strategy_name=sid, description="DFA_RegimeSignals v7", universe="7 KR style indices",
             rebalance="monthly", signal=key)
  bt<-build_bt_result(sim,spec,run_id=tolower(sid),strategy_id=sid,benchmark_id="CAPW_PARENT",
      benchmark_name="cap-w parent",transaction_cost_bps=bps,slippage_bps=0,frequency="monthly",
      universe_id="K200_KQ150",code_version="run_dfa_v7_compare.R",created_by_agent="Q-Lead")
  au<-audit_bt_result(bt); es<-essence_score(bt,n_trials_cumulative=34,selection_type="chain")
  cat(sprintf("[essence %s %dbps] grade=%s pt=%.3f oos=%.3f calmar=%.3f SR=%.2f MDD=%.3f\n",
      sid,bps,es$grade,es$essence$portfolio_alpha_t_nw_lag3,es$essence$oos_retention,
      es$essence$calmar,es$essence$net_sharpe,es$essence$mdd))
  list(id=sid,bps=bps,grade=es$grade,essence=es$essence,audit=au$integrity) }
cat("\n== 헤드라인 계약 채점 ==\n")
E<-list()
for(bps in c(5,15)){ E[[length(E)+1]]<-score_cell("f15_roll_m5","M0",bps,"DFA_V7_MINY5_TE3")
                     E[[length(E)+1]]<-score_cell("f15_roll_h1q95","H1",bps,"DFA_V7_H1Q95_TE3") }
saveRDS(list(ALL=ALL,E=E),".cache/_dfa_v7_compare.rds")
cat("V7_COMPARE_DONE\n")
