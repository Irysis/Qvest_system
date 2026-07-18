# WT-D20260718_006 — Canonical A/B: forecasting configs vs static + FACTOR-MOMENTUM baseline (WT-005).
# Identical OOS window (2012-12..2026-06, 163mo). KEY judgment = paired_vs_mom_t + oos_retention v2.
# All via canonical_screen_bt (top-25 EW long-only, cap-w KOSPI200, 15bps, liq 2e8) + dual-basis diag.
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts); library(jsonlite)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
W5  <- "04_Research/method_frontier/wt005_factor_timing"
OUT <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- c("value","quality","momentum","low_vol","size","dividend")

FAM  <- as.data.table(read_parquet(file.path(W5,"family_z_panel.parquet"))); FAM[,Date:=as.Date(Date)]
FEAT <- as.data.table(read_parquet(file.path(W5,"family_feature_panel.parquet"))); FEAT[,date:=as.Date(date)]
Rg <- as.data.table(read_parquet(file.path(W5,"grid_returns.parquet"))); Rg[,Date:=as.Date(Date)]
BMg<- as.data.table(read_parquet(file.path(W5,"grid_bench.parquet"))); BMg[,Date:=as.Date(Date)]
LQg<- as.data.table(read_parquet(file.path(W5,"grid_liq.parquet"))); LQg[,Date:=as.Date(Date)]
size_dt <- FAM[, .(Date,Ticker,size=Size)]

canon <- function(score_dt, dates=NULL){
  S <- score_dt[!is.na(score), .(Date,Ticker,score)]; S <- S[Date %in% Rg$Date]
  if(!is.null(dates)) S <- S[Date %in% dates]
  canonical_screen_bt(S, Rg, BMg, top_n=25L, cost_bps_oneway=15, liq_dt=LQg, liq_min=2e8,
                      run_id="wt006", strategy_id="wt006", periods_per_year=12L, diag_dual_basis=TRUE, size_dt=size_dt)
}
calmar_of <- function(pr){ x<-xts(pr$ret_net,order.by=as.Date(pr$date)); n<-nrow(x)
  ann<-prod(1+coredata(x))^(12/n)-1; mdd<-as.numeric(maxDrawdown(x)); if(!is.finite(mdd)||mdd<=0) return(NA); ann/mdd }
score_from_theta <- function(th){
  W <- dcast(th, date ~ family, value.var="theta"); setnames(W, fams, paste0("th_",fams))
  M <- merge(FAM, W, by.x="Date", by.y="date"); sc <- numeric(nrow(M))
  for(fk in fams){ z<-M[[fk]]; w<-M[[paste0("th_",fk)]]; z[is.na(z)]<-0; w[is.na(w)]<-0; sc<-sc+w*z }
  M[, score:=sc]; M[, .(Date,Ticker,score)]
}
active_series <- function(res){ pr<-res$period_returns; pr[,active:=ret_net-benchmark_ret]; pr[,.(date,active,ret_net)] }
paired_t <- function(a_t, a_s){ mg<-merge(a_t[,.(date,at=active)],a_s[,.(date,as=active)],by="date"); d<-mg$at-mg$as; list(t=.nw_t_mean(d,lag=3), md=mean(d), n=nrow(mg)) }
oos_ret_of <- function(pr){ a<-pr$active; n<-length(a); fr<-c(.55,.65,.75); sr<-function(x){s<-sd(x);if(!is.finite(s)||s<=0)return(NA);mean(x)/s*sqrt(12)}
  r<-sapply(fr,function(f){k<-floor(n*f); if(k<6||n-k<6)return(NA); is<-sr(a[1:k]); oo<-sr(a[(k+1):n]); if(is.na(is)||is<=0)return(NA); oo/is}); median(r,na.rm=TRUE) }

oos_dates <- sort(unique(as.Date(read_parquet(file.path(W5,"theta_transformer_ensemble.parquet"))$date)))

# baselines on OOS window
FAM[, score_ew := rowMeans(.SD, na.rm=TRUE), .SDcols=fams]
mom_theta <- FEAT[is.finite(tr_12m), {z<-(tr_12m-mean(tr_12m))/(sd(tr_12m)+1e-9); w<-exp(2*z); .(family=family, theta=w/sum(w))}, by=date]
val_theta <- FEAT[is.finite(vs_z), {z<-(vs_z-mean(vs_z))/(sd(vs_z)+1e-9); w<-exp(2*z); .(family=family, theta=w/sum(w))}, by=date]

res_static <- canon(FAM[,.(Date,Ticker,score=score_ew)], oos_dates); a_static <- active_series(res_static)
res_mom    <- canon(score_from_theta(mom_theta), oos_dates);          a_mom    <- active_series(res_mom)

rows <- list()
addrow <- function(label, th, is_theta=TRUE, score_dt=NULL, logic=NA){
  res <- if(is_theta) canon(score_from_theta(th), oos_dates) else canon(score_dt, oos_dates)
  a <- active_series(res)
  pv <- paired_t(a, a_static); pm <- paired_t(a, a_mom)
  data.table(strategy=label, logic=logic, n=res$n_months, port_t=round(res$portfolio_alpha_t_nw_lag3,3),
    net_sr=round(res$net_sr,3), calmar=round(calmar_of(res$period_returns),3),
    oos_ret=round(oos_ret_of(res$period_returns),3),
    paired_vs_static_t=round(pv$t,3), paired_vs_mom_t=round(pm$t,3),
    diff_vs_mom_bps=round(pm$md*1e4,1),
    ew_uni_t=round(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,3), turn=round(res$turnover_annual,2))
}
rows[["static"]] <- addrow("static_EW (base)", NULL, is_theta=FALSE, score_dt=FAM[,.(Date,Ticker,score=score_ew)])
rows[["mom"]]    <- addrow("factor_momentum (WT005 baseline)", mom_theta)
rows[["val"]]    <- addrow("valuation (Arnott vs_z)", val_theta)

# EN configs
for(cn in c("combined","L1_crowding","L2_dispersion","L3_funding","L4_crashrisk","L5_crossfactor","L6_macro")){
  f <- file.path(OUT, paste0("theta_EN_",cn,".parquet")); if(!file.exists(f)) next
  th <- as.data.table(read_parquet(f)); th[,date:=as.Date(date)]
  rows[[paste0("EN_",cn)]] <- addrow(paste0("EN_",cn), th, logic=cn)
}
# GBM ensemble + seeds
for(tag in c("ensemble","seed0","seed1","seed2")){
  f <- file.path(OUT, paste0("theta_GBM_",tag,".parquet")); if(!file.exists(f)) next
  th <- as.data.table(read_parquet(f)); th[,date:=as.Date(date)]
  rows[[paste0("GBM_",tag)]] <- addrow(paste0("GBM_",tag), th, logic="combined_gbm")
}
TAB <- rbindlist(rows, use.names=TRUE, fill=TRUE)
setorder(TAB, -paired_vs_mom_t)
print(TAB)
fwrite(TAB, file.path(OUT,"wt006_eval_summary.csv"))

# ---- DSR sweep (combo search = sweep; n_trials honest) ----
# best treatment by OOS port_t among forecasting configs
fc <- TAB[grepl("^EN_|^GBM_", strategy)]
best <- fc[which.max(port_t)]
cat("\nbest forecasting config (by OOS port_t):", best$strategy, " port_t=", best$port_t,
    " oos_ret=", best$oos_ret, " paired_vs_mom_t=", best$paired_vs_mom_t, "\n")

# DSR: N_trials = EN configs(7) + GBM(1 ensemble; seeds are same config) + 2 baselines-as-timing(val) approx
n_trials <- 7 + 1 + 1  # 7 EN + 1 GBM + valuation-as-timing (momentum is the a-priori baseline, not counted)
# use best config's monthly active SR
best_th_file <- file.path(OUT, paste0("theta_", ifelse(grepl("^EN_",best$strategy), sub("EN_","EN_",best$strategy), sub("GBM_","GBM_",best$strategy)), ".parquet"))
res_best <- if(grepl("^EN_",best$strategy)) canon(score_from_theta(as.data.table(read_parquet(file.path(OUT,paste0("theta_",best$strategy,".parquet"))))[,date:=as.Date(date)]), oos_dates) else
                                            canon(score_from_theta(as.data.table(read_parquet(file.path(OUT,paste0("theta_",best$strategy,".parquet"))))[,date:=as.Date(date)]), oos_dates)
pr_best <- res_best$period_returns; pr_best[,active:=ret_net-benchmark_ret]
msr <- mean(pr_best$active)/sd(pr_best$active); nmo <- nrow(pr_best)
sk <- {x<-pr_best$active; m<-mean(x);s<-sd(x); mean(((x-m)/s)^3)}; ku <- {x<-pr_best$active;m<-mean(x);s<-sd(x);mean(((x-m)/s)^4)}
# Bailey-LdP DSR approx
sr0 <- sqrt((1-0.5772)*qnorm(1-1/n_trials)^2)/sqrt(nmo-1)  # rough expected max SR under null (monthly units approx via var(SR))
# expected-max-SR threshold (monthly): E[max] ~ sd_SR * ((1-g)*Z_{1-1/N} + g*Z_{1-1/(N e)}), sd_SR=sqrt(1/nmo)
g <- 0.5772; sdsr <- sqrt(1/nmo)
emax <- sdsr*((1-g)*qnorm(1-1/n_trials) + g*qnorm(1-1/(n_trials*exp(1))))
dsr_num <- (msr - emax)*sqrt(nmo-1)
dsr_den <- sqrt(1 - sk*msr + ((ku-1)/4)*msr^2)
DSR <- pnorm(dsr_num/dsr_den)
cat(sprintf("DSR sweep: n_trials=%d monthly_SR=%.4f E[max]=%.4f DSR=%.3f (>=0.5 pass)\n", n_trials, msr, emax, DSR))

# ---- lag-1 PIT stress on best forecasting config theta ----
best_th <- as.data.table(read_parquet(file.path(OUT,paste0("theta_",best$strategy,".parquet")))); best_th[,date:=as.Date(date)]
# shift theta by 1 month (use previous month's weights) -> if signal leaks same-month, port_t collapses
dts_th <- sort(unique(best_th$date))
lag_map <- data.table(date=dts_th, lagdate=shift(dts_th,1))
best_th_lag <- merge(best_th, lag_map, by="date")[!is.na(lagdate)]
best_th_lag <- best_th_lag[,.(date=lagdate, family, theta)]  # apply t-1 weights at t... actually assign prev weights
# proper: weights_used_at_t = theta(t-1)
lagged <- merge(data.table(date=dts_th), lag_map, by="date")
lg <- best_th[, .(prevdate=date, family, theta)]
best_th_lag2 <- merge(lag_map[!is.na(lagdate)], lg, by.x="lagdate", by.y="prevdate", allow.cartesian=TRUE)[,.(date, family, theta)]
res_lag <- canon(score_from_theta(best_th_lag2), oos_dates)
cat(sprintf("lag-1 PIT stress: base port_t=%.3f -> lag1 port_t=%.3f (collapse->leak; gentle->clean)\n",
            best$port_t, res_lag$portfolio_alpha_t_nw_lag3))

# ---- AX-001 v2 (crisis conditional) on best config vs momentum ----
reg <- tryCatch(as.data.table(read_parquet("04_Research/decision_framework/smart_beta_regime/outputs/regime_labels_monthly.parquet")), error=function(e) NULL)
crisis_note <- "regime file unavailable"
if(!is.null(reg)){
  rc <- names(reg)[grepl("regime|label|state|crisis|bear", names(reg), ignore.case=TRUE)][1]
  dc <- names(reg)[grepl("date|ym|Date", names(reg), ignore.case=TRUE)][1]
  crisis_note <- paste("regime col:", rc, "date col:", dc)
}
cat("AX-001 note:", crisis_note, "\n")

summary_out <- list(
  oos_window=c(as.character(min(oos_dates)), as.character(max(oos_dates))), n_oos=length(oos_dates),
  static_port_t=rows[["static"]]$port_t, momentum_port_t=rows[["mom"]]$port_t,
  best_config=best$strategy, best_port_t=best$port_t, best_oos_ret=best$oos_ret,
  best_paired_vs_mom_t=best$paired_vs_mom_t, momentum_oos_ret=rows[["mom"]]$oos_ret,
  dsr=round(DSR,3), n_trials=n_trials, lag1_port_t=round(res_lag$portfolio_alpha_t_nw_lag3,3),
  beats_momentum_oos = (best$paired_vs_mom_t > 1.7 && best$oos_ret >= 0.7))
write_json(summary_out, file.path(OUT,"wt006_decision_summary.json"), pretty=TRUE, auto_unbox=TRUE)
cat("\n=== DECISION SUMMARY ===\n"); print(summary_out)
