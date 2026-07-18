# WT-D20260718_005 — Realizable (parameter-free) timing rules, paired A/B vs static EW.
# Rules use only features known at t (PIT). Fixed economic sign → full-sample = OOS-honest
# for the sign hypothesis (only DoF = temperature beta, reported across a small fixed grid).
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "04_Research/method_frontier/wt005_factor_timing"
fams <- c("value","quality","momentum","low_vol","size","dividend")

FAM  <- as.data.table(read_parquet(file.path(OUT,"family_z_panel.parquet"))); FAM[, Date:=as.Date(Date)]
FEAT <- as.data.table(read_parquet(file.path(OUT,"family_feature_panel.parquet"))); FEAT[, date:=as.Date(date)]
Rg <- as.data.table(read_parquet(file.path(OUT,"grid_returns.parquet"))); Rg[,Date:=as.Date(Date)]
BMg<- as.data.table(read_parquet(file.path(OUT,"grid_bench.parquet"))); BMg[,Date:=as.Date(Date)]
LQg<- as.data.table(read_parquet(file.path(OUT,"grid_liq.parquet"))); LQg[,Date:=as.Date(Date)]
so <- readRDS(file.path(OUT,"static_oracle.rds"))
size_dt <- FAM[, .(Date,Ticker,size=Size)]

canon <- function(score_dt){
  S <- score_dt[!is.na(score), .(Date,Ticker,score)]; S <- S[Date %in% Rg$Date]
  canonical_screen_bt(S, Rg, BMg, top_n=25L, cost_bps_oneway=15, liq_dt=LQg, liq_min=2e8,
                      run_id="wt005", strategy_id="wt005", periods_per_year=12L,
                      diag_dual_basis=TRUE, size_dt=size_dt)
}
calmar_of <- function(pr){ x<-xts(pr$ret_net,order.by=as.Date(pr$date)); n<-nrow(x)
  ann<-prod(1+coredata(x))^(12/n)-1; mdd<-as.numeric(maxDrawdown(x)); if(!is.finite(mdd)||mdd<=0) return(NA); ann/mdd }

# static base active series
prS <- so$res_ew$period_returns; prS[, active := ret_net - benchmark_ret]
base_t <- so$res_ew$portfolio_alpha_t_nw_lag3

# theta weights per month from a signal column; softmax(beta*z) OR top2-EW
build_theta <- function(signal_col, beta, mode="softmax"){
  F <- FEAT[, .(date, family, sig=get(signal_col))]
  F <- F[is.finite(sig)]
  th <- F[, {
    s <- sig; z <- (s-mean(s))/ (sd(s)+1e-9)
    if(mode=="softmax"){ w <- exp(beta*z); w <- w/sum(w) }
    else { # top2 EW
      w <- rep(0,length(z)); ord <- order(-z)[1:min(2,length(z))]; w[ord] <- 1/length(ord) }
    .(family=family, theta=w)
  }, by=date]
  th
}
# composite score from theta: for each (Date,Ticker) sum theta_k * z_k
composite <- function(th){
  W <- dcast(th, date ~ family, value.var="theta")
  M <- merge(FAM, W, by.x="Date", by.y="date")
  sc <- rep(0, nrow(M))
  for(fk in fams){ zk <- M[[fk]]; wk <- M[[paste0(fk)]]  # theta col same name after dcast? disambiguate
  }
  M
}
# safer: explicit theta columns prefixed
score_from_theta <- function(th){
  W <- dcast(th, date ~ family, value.var="theta")
  setnames(W, fams, paste0("th_",fams))
  M <- merge(FAM, W, by.x="Date", by.y="date")
  sc <- numeric(nrow(M))
  for(fk in fams){ z<-M[[fk]]; w<-M[[paste0("th_",fk)]]; z[is.na(z)]<-0; w[is.na(w)]<-0; sc <- sc + w*z }
  M[, score := sc]; M[, .(Date,Ticker,score)]
}

paired <- function(res_t){
  prT <- res_t$period_returns; prT[, active := ret_net - benchmark_ret]
  mg <- merge(prS[,.(date,active_s=active)], prT[,.(date,active_t=active)], by="date")
  d <- mg$active_t - mg$active_s
  list(paired_t=.nw_t_mean(d,lag=3), mean_diff=mean(d), n=nrow(mg))
}

rules <- list(
  mom12   = list(col="tr_12m",  desc="factor momentum (trailing 12m winners)"),
  val     = list(col="vs_z",    desc="Arnott valuation (cheap factors, vs_z)"),
  val_rev = list(col="vs_z",    desc="PLACEBO expensive factors (-vs_z)", flip=TRUE),
  mom_rev = list(col="tr_12m",  desc="PLACEBO reversal (trailing losers)", flip=TRUE)
)
betas <- c(1, 2)
out <- list()
for(rn in names(rules)){
  r <- rules[[rn]]
  FEAT[, sigcol := get(r$col)]; if(isTRUE(r$flip)) FEAT[, sigcol := -sigcol]
  for(bt in betas){
    th <- build_theta("sigcol", bt, "softmax")
    res <- canon(score_from_theta(th))
    p <- paired(res)
    out[[paste0(rn,"_b",bt)]] <- data.table(rule=rn, desc=r$desc, mode=paste0("softmax_b",bt),
      port_t=round(res$portfolio_alpha_t_nw_lag3,3), base_t=round(base_t,3),
      delta_vs_base=round(res$portfolio_alpha_t_nw_lag3-base_t,3),
      paired_t=round(p$paired_t,3), mean_diff_bps=round(p$mean_diff*1e4,1),
      net_sr=round(res$net_sr,3), calmar=round(calmar_of(res$period_returns),3),
      turn=round(res$turnover_annual,2), ew_uni_t=round(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,3))
  }
  # top2 rotation (more aggressive)
  th2 <- build_theta("sigcol", NA, "top2")
  res2 <- canon(score_from_theta(th2)); p2 <- paired(res2)
  out[[paste0(rn,"_top2")]] <- data.table(rule=rn, desc=r$desc, mode="top2EW",
    port_t=round(res2$portfolio_alpha_t_nw_lag3,3), base_t=round(base_t,3),
    delta_vs_base=round(res2$portfolio_alpha_t_nw_lag3-base_t,3),
    paired_t=round(p2$paired_t,3), mean_diff_bps=round(p2$mean_diff*1e4,1),
    net_sr=round(res2$net_sr,3), calmar=round(calmar_of(res2$period_returns),3),
    turn=round(res2$turnover_annual,2), ew_uni_t=round(res2$diag_ew_universe$portfolio_alpha_t_nw_lag3,3))
}
TAB <- rbindlist(out)
setorder(TAB, -paired_t)
print(TAB[, .(rule,mode,port_t,base_t,delta_vs_base,paired_t,mean_diff_bps,net_sr,calmar,ew_uni_t)])
fwrite(TAB, file.path(OUT,"simple_timing_summary.csv"))
cat("\nbase static_EW port_t=",round(base_t,3)," (cap-w). paired_t>0 & sig(>1.7) = timing adds over static.\n")
