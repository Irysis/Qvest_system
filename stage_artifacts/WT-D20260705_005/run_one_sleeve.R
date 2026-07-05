## WT-D20260705_005 — 단일 sleeve 스크리닝 (프로세스 격리; segfault 방어)
## 인자: commandArgs 1 = family name. 결과를 per-sleeve parquet로 저장.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
FM <- commandArgs(trailingOnly=TRUE)[1]
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "stage_artifacts/WT-D20260705_005"
PER_DIR <- file.path(OUT,"per_sleeve"); dir.create(PER_DIR, showWarnings=FALSE, recursive=TRUE)

g <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"))
g[, signal_date := as.Date(signal_date)]
gw <- g[family==FM, .(signal_date, security_id, score=group_z)]
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","BM_Ret")
rawdata <- as.data.table(read_parquet(file.path(OUT,"rawdata_monthend_slim.parquet"), col_select=all_of(.need)))
rawdata[,Date:=as.Date(Date)]
sig_dates <- sort(unique(g$signal_date))
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
post2017 <- as.Date("2017-01-01")
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]

srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
rank_ic_stats <- function(score_dt){
  m <- merge(score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
             fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)], by=c("Date","Ticker"))
  ics <- m[, .(ic = suppressWarnings(cor(score, Ret_1m, method="spearman", use="complete.obs"))), by=Date][is.finite(ic)]
  if(nrow(ics)<12) return(list(ic=NA_real_, icir=NA_real_, harvey_t=NA_real_))
  icm<-mean(ics$ic); ics_sd<-sd(ics$ic); icir<-if(ics_sd>1e-9) icm/ics_sd else NA_real_
  list(ic=icm, icir=icir, harvey_t=icir*sqrt(nrow(ics)))
}

sub <- copy(gw); sub[, score := zc(score), by=signal_date]
cs <- canonical_screen_bt(
  sub[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
  fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)],
  fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)],
  top_n=25L, cost_bps_oneway=15,
  liq_dt=fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)], liq_min=2e8,
  run_id="wt005", strategy_id=paste0("sleeve_",FM))
pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
pr <- merge(pr, ewb, by="date", all.x=TRUE)
pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
nav <- cumprod(1+pr$ret_net); dd<-min(nav/cummax(nav)-1); ann<-prod(1+pr$ret_net)^(12/nrow(pr))-1
cal <- if(dd<0) ann/abs(dd) else NA_real_
.splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)
  if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act_bm[1:k]); .oo<-srf(pr$act_bm[(k+1):nrow(pr)])
  if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
retn <- median(.rets, na.rm=TRUE)
ri <- rank_ic_stats(sub)
res <- data.table(model=paste0("sleeve_",FM), family=FM,
  port_t_capwt=nwt(pr$act_bm), port_t_EWuni=nwt(pr$act),
  port_alpha_t_contract=cs$portfolio_alpha_t_nw_lag3,
  rank_ic=ri$ic, icir=ri$icir, harvey_t=ri$harvey_t,
  oos_retention=retn, calmar=cal, mdd=dd, ann_ret=ann,
  post2017_bm_sr=srf(pr[date>=post2017, act_bm]), post2017_t=nwt(pr[date>=post2017, act_bm]),
  full_bm_sr=srf(pr$act_bm), net_sr=cs$net_sr, ir=cs$information_ratio,
  turnover=cs$turnover_annual, n_months=nrow(pr))
write_parquet(res, file.path(PER_DIR, paste0(FM,".parquet")))
# period returns 저장 (스택용)
write_parquet(pr[,.(date, family=FM, ret_net, benchmark_ret, act_bm)], file.path(PER_DIR, paste0(FM,"_pr.parquet")))
cat(sprintf("DONE %s: PORTt=%.2f oos=%.2f cal=%.2f post17_t=%.2f rankIC=%.3f\n",
    FM, res$port_t_capwt, res$oos_retention, res$calmar, res$post2017_t, res$rank_ic))
