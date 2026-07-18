# WT-D20260718_005 — emit alpha_scores.parquet + AX-001 v2 crisis defense + key-number json.
suppressMessages({library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics); library(xts)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "04_Research/method_frontier/wt005_factor_timing"
ART <- "stage_artifacts/WT_D20260718_005"; dir.create(ART, showWarnings=FALSE, recursive=TRUE)
fams <- c("value","quality","momentum","low_vol","size","dividend")
FAM <- as.data.table(read_parquet(file.path(OUT,"family_z_panel.parquet"))); FAM[,Date:=as.Date(Date)]
FEAT<- as.data.table(read_parquet(file.path(OUT,"family_feature_panel.parquet"))); FEAT[,date:=as.Date(date)]
Rg <- as.data.table(read_parquet(file.path(OUT,"grid_returns.parquet"))); Rg[,Date:=as.Date(Date)]
BMg<- as.data.table(read_parquet(file.path(OUT,"grid_bench.parquet"))); BMg[,Date:=as.Date(Date)]
LQg<- as.data.table(read_parquet(file.path(OUT,"grid_liq.parquet"))); LQg[,Date:=as.Date(Date)]
size_dt <- FAM[,.(Date,Ticker,size=Size)]
canon <- function(sd){ S<-sd[!is.na(score),.(Date,Ticker,score)]; S<-S[Date %in% Rg$Date]
  canonical_screen_bt(S,Rg,BMg,top_n=25L,cost_bps_oneway=15,liq_dt=LQg,liq_min=2e8,run_id="e",strategy_id="e",periods_per_year=12L,diag_dual_basis=FALSE) }
score_from_theta <- function(th){ W<-dcast(th,date~family,value.var="theta"); setnames(W,fams,paste0("th_",fams))
  M<-merge(FAM,W,by.x="Date",by.y="date"); sc<-numeric(nrow(M))
  for(fk in fams){z<-M[[fk]];w<-M[[paste0("th_",fk)]];z[is.na(z)]<-0;w[is.na(w)]<-0;sc<-sc+w*z}; M[,score:=sc]; M[,.(Date,Ticker,score)] }
FAM[, score_ew := rowMeans(.SD,na.rm=TRUE), .SDcols=fams]
mom_theta <- FEAT[is.finite(tr_12m), {z<-(tr_12m-mean(tr_12m))/(sd(tr_12m)+1e-9); w<-exp(2*z); .(family=family,theta=w/sum(w))}, by=date]

# --- alpha_scores.parquet: transformer-ensemble timed composite (primary WT artifact) + momentum + static ---
th_ens <- as.data.table(read_parquet(file.path(OUT,"theta_transformer_ensemble.parquet"))); th_ens[,date:=as.Date(date)]
sc_tr  <- score_from_theta(th_ens[,.(date,family,theta)]); setnames(sc_tr,"score","score_transformer")
sc_mom <- score_from_theta(mom_theta);                     setnames(sc_mom,"score","score_momentum")
sc_st  <- FAM[,.(Date,Ticker,score_static=score_ew)]
AS <- Reduce(function(a,b) merge(a,b,by=c("Date","Ticker"),all=TRUE), list(sc_st, sc_mom, sc_tr))
write_parquet(AS, file.path(ART,"alpha_scores.parquet"))
cat("alpha_scores rows",nrow(AS),"\n")

# --- AX-001 v2 crisis defense: momentum-timed vs static active in crisis vs normal months ---
res_static <- canon(FAM[,.(Date,Ticker,score=score_ew)]); prS<-res_static$period_returns; prS[,active_s:=ret_net-benchmark_ret]
res_mom    <- canon(sc_mom[,.(Date,Ticker,score=score_momentum)]); prM<-res_mom$period_returns; prM[,active_m:=ret_net-benchmark_ret]
mg <- merge(prS[,.(date,active_s,rs=ret_net,bm=benchmark_ret)], prM[,.(date,active_m,rm=ret_net)], by="date")
crisis <- mg[(date>=as.Date("2008-06-01")&date<=as.Date("2009-03-31")) |
             (date>=as.Date("2011-08-01")&date<=as.Date("2011-11-30")) |
             (date>=as.Date("2020-02-01")&date<=as.Date("2020-05-31")) |
             (date>=as.Date("2022-01-01")&date<=as.Date("2022-10-31"))]
normal <- mg[!date %in% crisis$date]
ax <- list(
  crisis_n=nrow(crisis), normal_n=nrow(normal),
  mom_mean_active_crisis=round(mean(crisis$active_m),4), static_mean_active_crisis=round(mean(crisis$active_s),4),
  mom_mean_active_normal=round(mean(normal$active_m),4), static_mean_active_normal=round(mean(normal$active_s),4),
  mom_bm_mean_crisis=round(mean(crisis$bm),4),
  ax001_v2_crisis_improvement=round(mean(crisis$active_m)-mean(crisis$active_s),4))

# transformer full-window canonical for record
res_tr <- canon(sc_tr[,.(Date,Ticker,score=score_transformer)])
key <- list(
  static_full_port_t=round(res_static$portfolio_alpha_t_nw_lag3,3),
  momentum_full_port_t=round(res_mom$portfolio_alpha_t_nw_lag3,3),
  transformer_full_port_t=round(res_tr$portfolio_alpha_t_nw_lag3,3),
  ax001_v2=ax)
write_json(key, file.path(OUT,"ax001_key.json"), auto_unbox=TRUE, pretty=TRUE, digits=5)
cat("AX-001 v2 crisis: mom active",ax$mom_mean_active_crisis," static",ax$static_mean_active_crisis,
    " improvement",ax$ax001_v2_crisis_improvement,"  (crisis n=",ax$crisis_n,")\n")
cat("full port_t: static",key$static_full_port_t," mom",key$momentum_full_port_t," transformer",key$transformer_full_port_t,"\n")
