# robustness.R — self-adversarial variants: winsorized div_yoy + binary "dividend increased"
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1L)
PR<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT<-file.path(PR,"stage_artifacts/dividend_signaling_wt006")
CYC2<-file.path(PR,"stage_artifacts/flow_microstructure_cycle2")
source(file.path(PR,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PR,"02_Infrastructure/contracts/canonical_screen_bt.R"))
TOP_N<-25L; COST_BPS<-15; D2017<-as.Date("2017-01-01"); D2020<-as.Date("2020-01-01")
rp<-function(d,f) as.data.table(read_parquet(file.path(d,f)))
returns_dt<-rp(CYC2,"returns_dt.parquet"); returns_dt[,Date:=as.Date(Date)]
bench_dt<-rp(CYC2,"bench_dt.parquet"); bench_dt[,Date:=as.Date(Date)]
scores<-rp(OUT,"div_scores.parquet"); scores[,Date:=as.Date(Date)]
liq_dt<-rp(OUT,"liq_dt.parquet"); liq_dt[,Date:=as.Date(Date)]
valid<-sort(unique(returns_dt$Date)); scores<-scores[Date %in% valid]

run<-function(scname, coln, top_n=TOP_N){
  sc<-scores[is.finite(get(coln)), .(Date,Ticker,score=get(coln))]
  r<-canonical_screen_bt(sc, returns_dt, bench_dt, top_n=top_n, cost_bps_oneway=COST_BPS,
      liq_dt=liq_dt[,.(Date,Ticker,adv)], liq_min=2e8, run_id=scname, strategy_id=scname)
  pr<-as.data.table(r$period_returns); pr[,active:=ret_net-benchmark_ret]
  cat(sprintf("[%18s] n=%d PORT_t_full=%.3f post2017=%.3f IR=%.3f netSR=%.3f TO=%.2f\n",
    scname, r$n_months, r$portfolio_alpha_t_nw_lag3,
    .nw_t_mean(pr[date>=D2017]$active,lag=3L), r$information_ratio, r$net_sr, r$turnover_annual))
  invisible(r)
}
cat("===== ROBUSTNESS: signal-construction variants (all payers, top-25 EW) =====\n")
run("div_yoy_raw","div_yoy")
run("div_yoy_wins","div_yoy_wins")
run("div_increased","div_increased")

# mega-tier winsorized long-short (does winsorizing rescue mega?)
tier_ls<-function(coln, tier_name){
  sc<-scores[tier==tier_name & is.finite(get(coln)), .(Date,Ticker,score=get(coln))]
  m<-merge(sc, returns_dt[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
  m<-m[is.finite(score)&is.finite(Ret_1m)]
  sp<-m[,{ if(.N>=4){thr<-median(score); hi<-Ret_1m[score>=thr]; lo<-Ret_1m[score<thr]
    if(length(hi)>=1&&length(lo)>=1) .(ls=mean(hi)-mean(lo)) else .(ls=NA_real_)} else .(ls=NA_real_)}, by=Date]
  sp<-sp[is.finite(ls)]; setorder(sp,Date)
  cat(sprintf("  [%s %s] t_full=%.3f post2017=%.3f post2020=%.3f\n", coln, tier_name,
    .nw_t_mean(sp$ls,lag=3L), .nw_t_mean(sp[Date>=D2017]$ls,lag=3L), .nw_t_mean(sp[Date>=D2020]$ls,lag=3L)))
}
cat("\n===== MEGA-tier long-short under winsorized/binary signal =====\n")
tier_ls("div_yoy_wins","mega")
tier_ls("div_increased","mega")
tier_ls("div_yoy_wins","mid")
cat("\n[DONE robustness]\n")
