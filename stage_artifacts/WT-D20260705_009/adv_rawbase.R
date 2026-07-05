suppressMessages({library(arrow);library(data.table)})
cat("t0",format(Sys.time()),"\n"); flush.console()
STAGE<-"stage_artifacts/WT-D20260705_009"; P<-file.path(STAGE,"panel")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
cat("sourced",format(Sys.time()),"\n"); flush.console()
feat<-as.data.table(read_parquet(file.path(P,"features_monthly.parquet")))
cat("feat read rows",nrow(feat),format(Sys.time()),"\n"); flush.console()
fc<-as.data.table(read_parquet(file.path(STAGE,"forecast_dist.parquet")))
ret<-as.data.table(read_parquet(file.path(P,"returns_monthly.parquet")))
uf<-as.data.table(read_parquet(file.path(P,"universe_flags.parquet")))
bm<-as.data.table(read_parquet(file.path(P,"benchmark_monthly.parquet")))
for(x in list(feat,fc,ret,uf,bm)) x[,Date:=as.Date(cut(as.Date(Date),"month"))]
fcols<-setdiff(names(feat),c("Date","Ticker"))
feat[, raw_base := rowMeans(as.matrix(.SD),na.rm=TRUE), .SDcols=fcols]
cat("raw_base done",format(Sys.time()),"\n"); flush.console()
d<-merge(feat[,.(Date,Ticker,raw_base)], fc[,.(Date,Ticker,sigma_hat)], by=c("Date","Ticker"))
d<-merge(d, uf[,.(Date,Ticker,adv=adv20)], by=c("Date","Ticker"))
d<-d[is.finite(raw_base)]
cat("merged d rows",nrow(d),format(Sys.time()),"\n"); flush.console()
liq<-uf[,.(Date,Ticker,adv=adv20)]
d[, score_A := raw_base]; d[, score_B := raw_base/sigma_hat]
run<-function(sc,filt=NULL,tag=""){
  s<-d[,.(Date,Ticker,score=get(sc))][!is.na(score)]; if(!is.null(filt))s<-s[filt(Date)]
  r<-ret; b<-bm; if(!is.null(filt)){r<-ret[filt(Date)];b<-bm[filt(Date)]}
  canonical_screen_bt(s, r[,.(Date,Ticker,Ret_1m)], b[,.(Date,BM_Ret)], top_n=25L,
    cost_bps_oneway=15, liq_dt=liq, liq_min=5e7, periods_per_year=12L, run_id=tag, strategy_id=tag)
}
p17<-function(x) x>=as.Date("2017-01-01")
Af<-run("score_A",NULL); cat("Af done",format(Sys.time()),"\n"); flush.console()
Bf<-run("score_B",NULL); Ap<-run("score_A",p17); Bp<-run("score_B",p17)
ff<-function(r) sprintf("PORT_t=%.3f netSR=%.3f TO=%.1f", r$portfolio_alpha_t_nw_lag3, r$net_sr, r$turnover_annual)
cat("RESULT_RAW_BASE\n")
cat("ArmA_full    ",ff(Af),"\nArmB_full    ",ff(Bf),"\nArmA_post2017",ff(Ap),"\nArmB_post2017",ff(Bp),"\n")
d2<-d[is.finite(adv)&adv>0]; d2[,ln_adv:=log(adv)]
cat(sprintf("cor(sigma_hat,log_adv)=%.3f  cor(sigma_hat,raw_base)=%.3f\n",
  cor(d2$sigma_hat,d2$ln_adv), cor(d$sigma_hat,d$raw_base)))
