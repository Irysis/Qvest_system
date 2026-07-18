# WT-D20260718_005 — Transformer OOS paired A/B vs static base AND vs simple momentum rule.
# All strategies evaluated on the IDENTICAL OOS window (transformer walk-forward months).
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts); library(jsonlite)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "04_Research/method_frontier/wt005_factor_timing"
fams <- c("value","quality","momentum","low_vol","size","dividend")

FAM  <- as.data.table(read_parquet(file.path(OUT,"family_z_panel.parquet"))); FAM[,Date:=as.Date(Date)]
FEAT <- as.data.table(read_parquet(file.path(OUT,"family_feature_panel.parquet"))); FEAT[,date:=as.Date(date)]
Rg <- as.data.table(read_parquet(file.path(OUT,"grid_returns.parquet"))); Rg[,Date:=as.Date(Date)]
BMg<- as.data.table(read_parquet(file.path(OUT,"grid_bench.parquet"))); BMg[,Date:=as.Date(Date)]
LQg<- as.data.table(read_parquet(file.path(OUT,"grid_liq.parquet"))); LQg[,Date:=as.Date(Date)]
size_dt <- FAM[, .(Date,Ticker,size=Size)]
meta <- fromJSON(file.path(OUT,"transformer_meta.json"))
oos_start <- as.Date(meta$oos_start)

canon <- function(score_dt, dates=NULL){
  S <- score_dt[!is.na(score), .(Date,Ticker,score)]; S <- S[Date %in% Rg$Date]
  if(!is.null(dates)) S <- S[Date %in% dates]
  canonical_screen_bt(S, Rg, BMg, top_n=25L, cost_bps_oneway=15, liq_dt=LQg, liq_min=2e8,
                      run_id="wt005", strategy_id="wt005", periods_per_year=12L,
                      diag_dual_basis=TRUE, size_dt=size_dt)
}
calmar_of <- function(pr){ x<-xts(pr$ret_net,order.by=as.Date(pr$date)); n<-nrow(x)
  ann<-prod(1+coredata(x))^(12/n)-1; mdd<-as.numeric(maxDrawdown(x)); if(!is.finite(mdd)||mdd<=0) return(NA); ann/mdd }

score_from_theta <- function(th){   # th: date, family, theta
  W <- dcast(th, date ~ family, value.var="theta"); setnames(W, fams, paste0("th_",fams))
  M <- merge(FAM, W, by.x="Date", by.y="date"); sc <- numeric(nrow(M))
  for(fk in fams){ z<-M[[fk]]; w<-M[[paste0("th_",fk)]]; z[is.na(z)]<-0; w[is.na(w)]<-0; sc<-sc+w*z }
  M[, score:=sc]; M[, .(Date,Ticker,score)]
}
# static EW composite (theta = 1/6)
FAM[, score_ew := rowMeans(.SD, na.rm=TRUE), .SDcols=fams]
# simple momentum-timing rule (softmax b2 on tr_12m)
mom_theta <- FEAT[is.finite(tr_12m), {z<-(tr_12m-mean(tr_12m))/(sd(tr_12m)+1e-9); w<-exp(2*z); .(family=family, theta=w/sum(w))}, by=date]

active_series <- function(res){ pr<-res$period_returns; pr[,active:=ret_net-benchmark_ret]; pr[,.(date,active,ret_net)] }
paired_t <- function(a_t, a_s){ mg<-merge(a_t[,.(date,at=active)],a_s[,.(date,as=active)],by="date"); d<-mg$at-mg$as; list(t=.nw_t_mean(d,lag=3), md=mean(d), n=nrow(mg)) }
oos_ret_of <- function(pr){ # anchored 3-split median of active-SR OOS/IS
  a<-pr$active; n<-length(a); fr<-c(.55,.65,.75); sr<-function(x){s<-sd(x);if(!is.finite(s)||s<=0)return(NA);mean(x)/s*sqrt(12)}
  r<-sapply(fr,function(f){k<-floor(n*f); if(k<6||n-k<6)return(NA); is<-sr(a[1:k]); oo<-sr(a[(k+1):n]); if(is.na(is)||is<=0)return(NA); oo/is}); median(r,na.rm=TRUE) }

# OOS dates = transformer test months
oos_dates <- sort(unique(as.Date(read_parquet(file.path(OUT,"theta_transformer_ensemble.parquet"))$date)))
cat("OOS window:", as.character(min(oos_dates)), "..", as.character(max(oos_dates)), " n=", length(oos_dates), "\n\n")

rows <- list()
addrow <- function(label, res, ref_static, ref_mom=NULL){
  a <- active_series(res); pt <- res$portfolio_alpha_t_nw_lag3
  pv <- paired_t(a, ref_static)
  pm <- if(!is.null(ref_mom)) paired_t(a, ref_mom) else list(t=NA,md=NA)
  data.table(strategy=label, n=res$n_months, port_t=round(pt,3),
    net_sr=round(res$net_sr,3), calmar=round(calmar_of(res$period_returns),3),
    oos_ret=round(oos_ret_of(res$period_returns),3),
    paired_vs_static_t=round(pv$t,3), diff_vs_static_bps=round(pv$md*1e4,1),
    paired_vs_mom_t=round(pm$t,3),
    ew_uni_t=round(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,3), turn=round(res$turnover_annual,2))
}
# references on OOS window
res_static <- canon(FAM[,.(Date,Ticker,score=score_ew)], oos_dates); a_static <- active_series(res_static)
res_mom    <- canon(score_from_theta(mom_theta), oos_dates);          a_mom    <- active_series(res_mom)
rows[["static"]] <- addrow("static_EW (OOS ref)", res_static, a_static)
rows[["mom"]]    <- addrow("simple_mom12_b2 (OOS)", res_mom, a_static)

# transformer: ensemble + per seed
for(tag in c("ensemble","seed0","seed1","seed2")){
  f <- file.path(OUT, paste0("theta_transformer_", tag, ".parquet"))
  th <- as.data.table(read_parquet(f)); th[,date:=as.Date(date)]
  res <- canon(score_from_theta(th[,.(date,family,theta)]), oos_dates)
  rows[[tag]] <- addrow(paste0("transformer_",tag), res, a_static, a_mom)
}
TAB <- rbindlist(rows, use.names=TRUE, fill=TRUE)
print(TAB)
fwrite(TAB, file.path(OUT,"transformer_eval_summary.csv"))

cat("\n=== decision summary (OOS", as.character(min(oos_dates)),"..",as.character(max(oos_dates)),") ===\n")
cat("static_EW port_t     :", TAB[strategy=="static_EW (OOS ref)"]$port_t, "\n")
cat("simple_mom12 port_t  :", TAB[strategy=="simple_mom12_b2 (OOS)"]$port_t, " paired_vs_static_t:", TAB[strategy=="simple_mom12_b2 (OOS)"]$paired_vs_static_t, "\n")
cat("transformer_ens port_t:", TAB[strategy=="transformer_ensemble"]$port_t,
    " paired_vs_static_t:", TAB[strategy=="transformer_ensemble"]$paired_vs_static_t,
    " paired_vs_mom_t:", TAB[strategy=="transformer_ensemble"]$paired_vs_mom_t, "\n")
