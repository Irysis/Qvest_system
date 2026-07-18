# WT-D20260718_005 — Self-adversarial checks: (1) lag-1 PIT stress on momentum-timing,
# (2) DSR on the momentum side-finding (sweep of 12 rules), (3) full-sample momentum oos_retention.
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)})
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
size_dt <- FAM[,.(Date,Ticker,size=Size)]
canon <- function(sd){ S<-sd[!is.na(score),.(Date,Ticker,score)]; S<-S[Date %in% Rg$Date]
  canonical_screen_bt(S,Rg,BMg,top_n=25L,cost_bps_oneway=15,liq_dt=LQg,liq_min=2e8,run_id="a",strategy_id="a",periods_per_year=12L,diag_dual_basis=FALSE) }
score_from_theta <- function(th){ W<-dcast(th,date~family,value.var="theta"); setnames(W,fams,paste0("th_",fams))
  M<-merge(FAM,W,by.x="Date",by.y="date"); sc<-numeric(nrow(M))
  for(fk in fams){z<-M[[fk]];w<-M[[paste0("th_",fk)]];z[is.na(z)]<-0;w[is.na(w)]<-0;sc<-sc+w*z}; M[,score:=sc]; M[,.(Date,Ticker,score)] }
FAM[, score_ew := rowMeans(.SD,na.rm=TRUE), .SDcols=fams]
res_static <- canon(FAM[,.(Date,Ticker,score=score_ew)]); prS<-res_static$period_returns; prS[,active:=ret_net-benchmark_ret]
paired <- function(res){ pr<-res$period_returns; pr[,active:=ret_net-benchmark_ret]
  mg<-merge(prS[,.(date,as=active)],pr[,.(date,at=active)],by="date"); d<-mg$at-mg$as; .nw_t_mean(d,lag=3) }

# theta builder from a signal col with optional extra lag (lag-1 PIT stress)
mk_theta <- function(col, beta=2, extra_lag=0){
  F <- copy(FEAT)[, .(date,family,sig=get(col))]
  if(extra_lag>0){ setorder(F,family,date); F[, sig:=shift(sig,extra_lag), by=family] }
  F <- F[is.finite(sig)]
  F[, {z<-(sig-mean(sig))/(sd(sig)+1e-9); w<-exp(beta*z); .(family=family,theta=w/sum(w))}, by=date]
}
cat("=== (1) lag-1 PIT stress (momentum tr_12m, softmax b2) ===\n")
for(el in c(0,1,2)){
  r <- canon(score_from_theta(mk_theta("tr_12m",2,el)))
  cat(sprintf("  extra_lag=%d  port_t=%.3f  paired_vs_static_t=%.3f  net_sr=%.3f\n",
      el, r$portfolio_alpha_t_nw_lag3, paired(r), r$net_sr))
}

cat("\n=== (2) DSR on momentum finding (sweep = 12 rules tried in run_simple_timing) ===\n")
# best momentum rule net SR (monthly active) -> DSR with n_trials=12
r_best <- canon(score_from_theta(mk_theta("tr_12m",2,0)))
a <- { pr<-r_best$period_returns; pr[,active:=ret_net-benchmark_ret]; pr$active }
sr_m <- mean(a)/sd(a); n <- length(a); N_TRIALS <- 12
# Bailey-Lopez de Prado DSR (approx): expected max SR under N trials, variance of SR estimate
sr_ann <- sr_m*sqrt(12)
sk <- mean((a-mean(a))^3)/sd(a)^3; ku <- mean((a-mean(a))^4)/sd(a)^4
# SR estimation variance (Mertens): (1 - sk*SR + (ku-1)/4*SR^2)/(n-1) on monthly SR
var_sr <- (1 - sk*sr_m + ((ku-1)/4)*sr_m^2)/(n-1)
se_sr <- sqrt(var_sr)
emc <- 0.5772156649
# expected max of N iid standard normals approx
z_exp <- (1-emc)*qnorm(1-1/N_TRIALS) + emc*qnorm(1-1/(N_TRIALS*exp(1)))
sr0 <- z_exp*se_sr   # threshold SR (monthly) under multiple testing
dsr <- pnorm((sr_m - sr0)/se_sr)
cat(sprintf("  momentum monthly SR=%.4f (ann %.3f) n=%d skew=%.2f kurt=%.2f\n", sr_m, sr_ann, n, sk, ku))
cat(sprintf("  N_trials=%d  SR0(threshold)=%.4f  DSR=%.3f  (HARD>=0.5 for sweep)\n", N_TRIALS, sr0, dsr))

cat("\n=== (3) full-sample momentum oos_retention (anchored 3-split median) ===\n")
oosret <- function(a){ nn<-length(a); fr<-c(.55,.65,.75); srf<-function(x){s<-sd(x);if(!is.finite(s)||s<=0)return(NA);mean(x)/s}
  r<-sapply(fr,function(f){k<-floor(nn*f); if(k<6||nn-k<6)return(NA); is<-srf(a[1:k]); oo<-srf(a[(k+1):nn]); if(is.na(is)||is<=0)return(NA); oo/is}); median(r,na.rm=TRUE) }
cat(sprintf("  momentum full-sample oos_retention=%.3f  (HARD>=0.7)\n", oosret(a)))
cat(sprintf("  static_EW port_t (full)=%.3f\n", res_static$portfolio_alpha_t_nw_lag3))
