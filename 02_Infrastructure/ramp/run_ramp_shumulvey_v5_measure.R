## run_ramp_shumulvey_v5_measure.R — 헤드라인 셀 계약 측정 (FQ-239 P1c 판정 절차)
## build_bt_result(월간 frequency) → audit_bt_result → essence_score(oos_stat_version=v2, selection_type=chain)
## prereg 헤드라인 셀 고정: M0 TE3 × {5,15}bps. env SMV_KEY ∈ {f15, f15_roll}
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/essence_score.R")

KEY<-Sys.getenv("SMV_KEY","f15")
Z<-readRDS(sprintf(".cache/_smv_v5_%s.rds",KEY)); RES<-Z$RES

## 월간 시장 수익 (동일 parquet)
R<-as.data.table(read_parquet(Z$idxfile)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
RM<-copy(R); RM[,ym:=format(Date,"%Y-%m")]
monM<-RM[,.(mkt=prod(1+ifelse(is.finite(Market),Market,0))-1, medate=max(Date)),by=ym]

OUT<-list()
for(bps in c(5,15)){
  row<-RES[arm=="M0" & te==3 & cost_bps==bps][1]
  if(!nrow(row)||is.null(row$series[[1]])){cat("cell missing bps=",bps,"\n");next}
  s<-row$series[[1]]
  d<-as.Date(s$months); pr<-s$pr
  bmv<-monM[match(format(d,"%Y-%m"),ym), mkt]
  k<-which(is.finite(pr)&is.finite(bmv)); d<-d[k]; pr<-pr[k]; bmv<-bmv[k]
  sim<-list(
    DAILY_NAV_DT=data.table(Date=d, Strategy_Ret=pr, NAV=cumprod(1+pr)),
    strategy_xts=xts(pr, order.by=d),
    bm_xts=xts(bmv, order.by=d),
    cost_model_version=sprintf("smv_v5_%dbps_oneway_delta",bps))
  spec<-list(strategy_name=sprintf("SMV_V5_%s_M0_TE3_%dbps",toupper(KEY),bps),
             description="Shu-Mulvey 2024 KR v5: 7 KR 스타일지수, 팩터별 SJM 국면 → BL 뷰 → 롱온리 MVO. 보정 회계(월말 결정→익월 적용).",
             universe="7 long-only KR style indices (K200∪KQ150 파생)",
             rebalance="monthly", cost=sprintf("%dbps one-way delta",bps),
             signal=sprintf("tune=%s, per-factor 2-state SJM, view=국면조건부 평균 active ±5%%cap",ifelse("tune" %in% names(row),row$tune,"fixed")))
  bt<-build_bt_result(sim, spec,
        run_id=sprintf("smv_v5_%s_te3_%d_20260820",KEY,bps),
        strategy_id=sprintf("SMV_V5_%s_TE3_%d",toupper(KEY),bps),
        benchmark_id="CAPW_PARENT", benchmark_name="cap-weighted K200∪KQ150 parent (Market sleeve)",
        transaction_cost_bps=bps, slippage_bps=0,
        frequency="monthly", universe_id="K200_KQ150",
        code_version="run_ramp_shumulvey_v5_daily.R", created_by_agent="Q-Lead")
  au<-audit_bt_result(bt)
  es<-essence_score(bt, n_trials_cumulative=16, selection_type="chain")
  cat(sprintf("\n=== [%s TE3 %dbps] audit=%s grade=%s ===\n",KEY,bps,au$integrity,es$grade))
  print(es$essence)
  cat("hard_fail:",paste(unlist(es$hard_fail),collapse=","),"| reasons:",paste(unlist(es$reasons),collapse=" | "),"\n")
  OUT[[length(OUT)+1]]<-list(bps=bps,audit=au,essence=es)
}
saveRDS(OUT, sprintf(".cache/_smv_v5_measure_%s.rds",KEY))
cat("MEASURE_DONE ",KEY,"\n")
