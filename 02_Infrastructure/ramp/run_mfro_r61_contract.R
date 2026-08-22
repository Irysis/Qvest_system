## run_mfro_r61_contract.R — R61: MFRO 계약 측정 (HARD 3종 최초 산출)
## build_bt_result -> audit_bt_result -> essence_score(oos_stat_version=v2, selection_type=chain)
## ★이 아크의 어느 라운드도 PORT_t(forge-authoritative)·oos_retention·calmar 를 계약 경유로 낸 적이 없다.
## R60 라벨이 SIGNAL_REAL_BUT_INSUFFICIENT 가 된 지금 처음으로 의미를 갖는다.
suppressPackageStartupMessages({library(data.table);library(arrow);library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")

Z<-readRDS(".cache/_mfro_r60.rds"); AR<-Z$AR; YM<-Z$YM; E<-Z$E; bmf<-Z$bmf
## 날짜: pr[m] 은 YM[m] 결정 -> YM[m]+1 실현. 따라서 계열 날짜 = 익월 월말.
P<-as.data.table(read_parquet("outputs/ramp/mfro_panel.parquet"))
reb<-unique(P[,.(ym,rebal)]); setkey(reb,ym)
nextym<-function(y){a<-as.integer(substr(y,1,4));mm<-as.integer(substr(y,6,7))
  m2<-mm+1L;a2<-a+(m2>12L);m2<-ifelse(m2>12L,1L,m2);sprintf("%04d-%02d",a2,m2)}
fym<-nextym(YM)
fdate<-as.Date(reb[match(fym,ym),rebal])
cat(sprintf("[정렬] 계열 날짜 = 익월 월말. 유효 %d / %d (마지막은 정상 결측)\n",
  sum(!is.na(fdate)),length(fdate)))

ARMS<-list(D1_rotation_top5="MFRO_D1_rotation_top5", C1_no_signal="MFRO_C1_no_signal")
OUT<-list()
for(nm in names(ARMS)) for(win in c("full","clean")){
  r<-AR[[nm]]
  k<-which(E[[win]] & is.finite(r$pr) & is.finite(bmf) & !is.na(fdate))
  if(length(k)<24){cat("셀 부족:",nm,win,"\n");next}
  d<-fdate[k]; pr<-r$pr[k]; bmv<-bmf[k]
  o<-order(d); d<-d[o];pr<-pr[o];bmv<-bmv[o]
  stopifnot(!any(duplicated(d)))
  sim<-list(DAILY_NAV_DT=data.table(Date=d,Strategy_Ret=pr,NAV=cumprod(1+pr)),
            strategy_xts=xts(pr,order.by=d), bm_xts=xts(bmv,order.by=d),
            cost_model_version="mfro_15bps_oneway_delta")
  spec<-list(strategy_name=sprintf("%s_%s",ARMS[[nm]],win),
    description=paste0("MFRO 멀티팩터 로테이션 오버레이. 유니버스 시총 상위 25종을 보유하고, ",
      "DFA 21 팩터지수의 trailing 12M active 상위 5개 팩터의 z 로 비중만 재틸트. ",
      "production 가중규칙 .tilt(lambda=1.5) cap 0.20. C1 은 무신호 대조(시총가중)."),
    universe="KOSPI200 U KOSDAQ150, adv20 >= 2e8 KRW, 시총 상위 25",
    rebalance="monthly", cost="15bps one-way delta",
    signal=if(nm=="D1_rotation_top5") "factor rotation top-5 by trailing 12M index active (dec_lag=1)" else "none (cap-weighted control)")
  bt<-build_bt_result(sim,spec,
    run_id=sprintf("mfro_r61_%s_%s_20260822",nm,win),
    strategy_id=sprintf("%s_%s",ARMS[[nm]],toupper(win)),
    benchmark_id="CAPW_PARENT", benchmark_name="cap-weighted K200 U KQ150 parent (Market sleeve)",
    transaction_cost_bps=15, slippage_bps=0, frequency="monthly", universe_id="K200_KQ150",
    code_version="run_mfro_r60_reissue.R", created_by_agent="Q-Lead")
  au<-audit_bt_result(bt)
  es<-essence_score(bt, n_trials_cumulative=1, selection_type="chain")
  cat(sprintf("\n=== [%s / %s] n=%d audit=%s grade=%s ===\n",nm,win,length(pr),au$integrity,es$grade))
  print(es$essence)
  cat("hard_fail:",paste(unlist(es$hard_fail),collapse=","),
      "\nreasons:",paste(unlist(es$reasons),collapse=" | "),"\n")
  OUT[[paste0(nm,"_",win)]]<-list(audit=au,essence=es,n=length(pr))
}
saveRDS(OUT,".cache/_mfro_r61_contract.rds")

cat("\n=== ★HARD 3종 요약 (문턱: PORT_t 2.95 · oos_retention 0.70 · calmar 0.64) ===\n")
for(k in names(OUT)){e<-OUT[[k]]$essence$essence
  g<-function(f) if(!is.null(e[[f]])) as.numeric(e[[f]]) else NA_real_
  pt<-g("portfolio_alpha_t_nw"); if(is.na(pt)) pt<-g("portfolio_alpha_t")
  oo<-g("oos_retention"); ca<-g("calmar")
  cat(sprintf("  %-28s PORT_t %s | oos %s | calmar %s\n",k,
    ifelse(is.na(pt),"n/a",sprintf("%+.3f %s",pt,ifelse(pt>=2.95,"PASS","FAIL"))),
    ifelse(is.na(oo),"n/a",sprintf("%.3f %s",oo,ifelse(oo>=0.70,"PASS","FAIL"))),
    ifelse(is.na(ca),"n/a",sprintf("%.3f %s",ca,ifelse(ca>=0.64,"PASS","FAIL")))))}
cat("\nR61_DONE\n")
