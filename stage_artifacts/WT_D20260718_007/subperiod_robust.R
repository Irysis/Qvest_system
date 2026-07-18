#!/usr/bin/env Rscript
# subperiod_robust.R — is the AE_seq calmar/MDD edge concentrated in 2008, or does it persist?
suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1)
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
Sys.setenv(QVEST_WEIGHTING_AB_NORUN="1", QVEST_REGIME_AB_NORUN="1")
source("02_Infrastructure/ops/auto_weighting_ab.R")
PIN <- ".cache/pins/WT-D20260718_007_r1"; ym <- function(d) format(as.Date(d),"%Y-%m")
car <- as.data.table(read_parquet(file.path(PIN,"carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")))[selected==TRUE & !is.na(ret_fwd)]
car[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
returns_dt <- car[, .(Date=eval_date, Ticker, Ret_1m=ret_fwd)]
periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date); periods[, ym_e:=ym(eval_date)]
W_strat <- car[, .(Date=eval_date, Ticker, w=weight_strategy/sum(weight_strategy)), by=.(eval_date)][, .(Date,Ticker,w)]
bench_dt <- build_period_bench(periods, bench_path=file.path(PIN,"benchmark.parquet"))[!is.na(BM_Ret)]
Lr <- fread(file.path(PIN,"period_returns_layer5.csv")); Lr[, ym_a:=ym(anchor_date)]
comp <- Lr[, .(ym_a, m4=as.numeric(m4_weight_lag), ar=as.numeric(beta_threshold_lag), r05=as.numeric(beta_R05_V5))]
periods[comp, on=.(ym_e=ym_a), `:=`(m4=i.m4, ar=i.ar, r05=i.r05)]
ae <- as.data.table(read_parquet("stage_artifacts/WT_D20260718_007/ae_regime_signal.parquet"))
ae[, decision_date:=as.Date(decision_date)]; ae[, exp_seq:=fifelse(fire_seq==1,0.70,1.00)]
periods[ae, on=.(decision_date), `:=`(ae_seq=i.exp_seq)]
per <- periods[!is.na(ae_seq) & !is.na(m4)]; setorder(per, eval_date)

run1 <- function(exp_dt,id) weighted_screen_bt(W_strat, returns_dt, bench_dt, cost_bps_oneway=15, run_id=id, strategy_id=id, exposure_dt=exp_dt)
nw_t <- function(x,lag=3){ x<-x[is.finite(x)]; n<-length(x); m<-mean(x); e<-x-m; g0<-sum(e*e)/n; v<-g0
  for(l in 1:lag){ w<-1-l/(lag+1); c<-sum(e[(l+1):n]*e[1:(n-l)])/n; v<-v+2*w*c }; m/sqrt(v/n) }

splits <- list(full=c("2008-01-01","2027-01-01"), excl2008=c("2010-01-01","2027-01-01"),
               p2015=c("2015-01-01","2027-01-01"))
out <- rbindlist(lapply(names(splits), function(nm){ s<-as.Date(splits[[nm]])
  sub <- per[eval_date>=s[1] & eval_date<s[2]]
  cw <- sub$eval_date
  rd<-returns_dt[Date%in%cw]; ws<-W_strat[Date%in%cw]; bd<-bench_dt[Date%in%cw]
  wb <- function(exp){ weighted_screen_bt(ws, rd, bd, cost_bps_oneway=15, run_id=nm, strategy_id=nm,
                                          exposure_dt=sub[,.(Date=eval_date, exposure=exp)]) }
  rb <- wb(sub$m4*sub$ar*sub$r05); ra <- wb(sub$ae_seq*sub$ar*sub$r05)
  pr <- merge(rb$period_returns[,.(date,b=ret_net)], ra$period_returns[,.(date,a=ret_net)], by="date")
  data.table(split=nm, n=nrow(sub),
             M4_calmar=rb$abs_cagr/abs(rb$abs_mdd), AE_calmar=ra$abs_cagr/abs(ra$abs_mdd),
             M4_MDD=rb$abs_mdd, AE_MDD=ra$abs_mdd, M4_SR=rb$abs_net_sr, AE_SR=ra$abs_net_sr,
             paired_t=nw_t(pr$a-pr$b,3)) }))
cat("\n=== AE_seq vs M4 book — subperiod robustness (is the calmar edge just 2008?) ===\n"); print(out)
saveRDS(out,"stage_artifacts/WT_D20260718_007/subperiod_robust.rds")
