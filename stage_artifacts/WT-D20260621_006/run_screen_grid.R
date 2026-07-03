# WT-D20260621_006 — canonical_screen_bt over grid + decile profile (PRIMARY)
suppressMessages({library(data.table)})
setDTthreads(1L)
PROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROOT)
OUT <- file.path(PROOT,"stage_artifacts/WT-D20260621_006")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

returns_dt <- readRDS(file.path(OUT,"returns_dt.rds"))
bench_dt   <- readRDS(file.path(OUT,"bench_dt.rds"))
liq_dt     <- readRDS(file.path(OUT,"liq_dt.rds"))
scores_primary <- readRDS(file.path(OUT,"scores_primary.rds"))

# ---- canonical screen helper with metrics ----
run_one <- function(scores_dt, top_n=20L, tag="") {
  res <- canonical_screen_bt(scores_dt[,.(Date,Ticker,score)], returns_dt, bench_dt,
                             top_n=top_n, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8,
                             run_id=paste0("WT006_",tag), strategy_id=paste0("WT006_",tag))
  pr <- res$period_returns
  # oos_retention: anchored 3-split medians of active-net Sharpe OOS/IS
  retention <- NA_real_; calmar <- NA_real_
  if (!is.null(pr) && nrow(pr) > 24) {
    pr <- pr[order(date)]
    act <- pr$ret_net - pr$benchmark_ret
    n <- length(act)
    sr <- function(x) if(length(x)<6 || sd(x)==0) NA_real_ else mean(x)/sd(x)*sqrt(12)
    rets <- sapply(c(0.55,0.65,0.75), function(f){
      cut <- floor(n*f); is_sr<-sr(act[1:cut]); oos_sr<-sr(act[(cut+1):n])
      if(is.na(is_sr)||is.na(oos_sr)||is_sr<=0) NA_real_ else oos_sr/is_sr
    })
    retention <- median(rets, na.rm=TRUE)
    # calmar on NET portfolio (gross-of-benchmark net return = ret_net)
    nav <- cumprod(1+pr$ret_net)
    cagr <- nav[length(nav)]^(12/length(nav)) - 1
    peak <- cummax(nav); dd <- nav/peak - 1; mdd <- -min(dd)
    calmar <- if(mdd>0) cagr/mdd else NA_real_
  }
  data.table(tag=tag, top_n=top_n, n_months=res$n_months,
             port_t_nw=res$portfolio_alpha_t_nw_lag3,
             IR=res$information_ratio, net_sr=res$net_sr,
             alpha_ann=res$alpha_annualized, turnover=res$turnover_annual,
             oos_retention=retention, calmar=calmar)
}

# ---- rank-IC (Spearman) of score vs forward Ret_1m, pooled-by-date ----
rank_ic_profile <- function(scores_dt) {
  m <- merge(scores_dt[,.(Date,Ticker,score)], returns_dt, by=c("Date","Ticker"))
  ics <- m[, .(ic = if(.N>=10) cor(score, Ret_1m, method="spearman") else NA_real_), by=Date][!is.na(ic)]
  ic_mean <- mean(ics$ic); ic_sd <- sd(ics$ic); n<-nrow(ics)
  icir <- ic_mean/ic_sd
  # Harvey-t (NW lag-3 on monthly IC series)
  nw_t <- {
    x <- ics$ic - mean(ics$ic); L<-3; g0<-mean(x^2)
    gam <- sapply(1:L, function(l) mean(x[(l+1):n]*x[1:(n-l)]))
    lrv <- g0 + 2*sum((1-(1:L)/(L+1))*gam)
    ic_mean / sqrt(lrv/n)
  }
  list(ic_mean=ic_mean, icir=icir, harvey_t=nw_t, n=n,
       subperiods = {
         ics[, sp := cut(Date, breaks=3, labels=c("s1","s2","s3"))]
         ics[, .(ic=mean(ic)), by=sp]
       })
}

# ---- decile concentration (CRITICAL — C23 lesson) ----
# For each sig_date: decile by score; mean forward Ret_1m per decile; active vs EW-universe
decile_profile <- function(scores_dt) {
  m <- merge(scores_dt[,.(Date,Ticker,score)], returns_dt, by=c("Date","Ticker"))
  m <- m[, if(.N>=20) .SD, by=Date]
  m[, dec := cut(frank(score)/.N, breaks=seq(0,1,0.1), labels=1:10, include.lowest=TRUE), by=Date]
  m[, uni_mean := mean(Ret_1m), by=Date]
  dec <- m[, .(ret=mean(Ret_1m), active=mean(Ret_1m-uni_mean), n=.N), by=.(Date,dec)]
  prof <- dec[, .(mean_active=mean(active), mean_ret=mean(ret), t_active = mean(active)/sd(active)*sqrt(.N)), by=dec][order(dec)]
  prof
}

cat("=== rank-IC PRIMARY ===\n")
ric <- rank_ic_profile(scores_primary)
cat(sprintf("ic_mean=%.4f icir=%.3f harvey_t=%.2f n=%d\n", ric$ic_mean, ric$icir, ric$harvey_t, ric$n))
print(ric$subperiods)

cat("\n=== DECILE PROFILE PRIMARY (CRITICAL) ===\n")
dp <- decile_profile(scores_primary)
print(dp)
d10 <- dp[dec=="10", mean_active]; d9 <- dp[dec=="9", mean_active]
cat(sprintf("\nD10 active=%.5f  D9 active=%.5f  D10-D9 gap=%.5f\n", d10, d9, d10-d9))
cat(sprintf("TOP-concentration: %s\n", ifelse(d10-d9 > 0 && d10>0, "edge concentrated in D10 (top-20 tradeable)", "FLAT/mid-decile -> screen-route risk")))
saveRDS(list(rank_ic=ric, decile=dp), file.path(OUT,"diag_primary.rds"))

cat("\n=== canonical_screen PRIMARY top_n=20 ===\n")
r20 <- run_one(scores_primary, 20L, "primary_n20")
print(r20)
cat("\n=== canonical_screen PRIMARY top_n=25 ===\n")
r25 <- run_one(scores_primary, 25L, "primary_n25")
print(r25)
saveRDS(rbind(r20,r25), file.path(OUT,"screen_primary.rds"))
fwrite(rbind(r20,r25), file.path(OUT,"screen_primary.csv"))
cat("\n=== run_screen_grid.R DONE ===\n")
