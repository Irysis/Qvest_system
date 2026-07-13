# R16 placebo (month-shuffle) + DSR (sweep n_trials=5)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent = TRUE)
STAGE <- "stage_artifacts/r16_microstructure"
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

scores_long <- as.data.table(read_parquet(file.path(STAGE,"scores_long.parquet")))
returns_dt  <- as.data.table(read_parquet(file.path(STAGE,"returns_dt.parquet")))
bench_dt    <- as.data.table(read_parquet(file.path(STAGE,"bench_dt.parquet")))
liq_dt      <- as.data.table(read_parquet(file.path(STAGE,"liq_dt.parquet")))
for (d in list(scores_long,returns_dt,bench_dt,liq_dt)) d[, Date := as.Date(Date)]
FACS <- c("VSHK_P","TOD_DT","AMT_ASY","VPRC_CORR","ILLIQ_VOL")
set.seed(20260713L); N_PERM <- 200L

port_t_of <- function(sc, ret, ben) {
  cs <- tryCatch(canonical_screen_bt(sc, ret, ben, top_n=25L, cost_bps_oneway=15,
                   liq_dt=liq_dt, liq_min=2e8, diag_dual_basis=FALSE,
                   run_id="p", strategy_id="p"), error=function(e) NULL)
  if (is.null(cs)) return(NA_real_); cs$portfolio_alpha_t_nw_lag3
}
udates <- sort(unique(returns_dt$Date))
placebo <- list(); active_by_factor <- list()
for (f in FACS) {
  sc <- scores_long[factor==f, .(Date,Ticker,score)]
  obs <- port_t_of(sc, returns_dt[,.(Date,Ticker,Ret_1m)], bench_dt[,.(Date,BM_Ret)])
  # store active series for DSR (monthly)
  cs0 <- canonical_screen_bt(sc, returns_dt[,.(Date,Ticker,Ret_1m)], bench_dt[,.(Date,BM_Ret)],
                             top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8,
                             diag_dual_basis=FALSE, run_id=f, strategy_id=f)
  pr <- as.data.table(cs0$period_returns); active_by_factor[[f]] <- pr$ret_net - pr$benchmark_ret
  null_t <- numeric(N_PERM)
  for (p in seq_len(N_PERM)) {
    remap <- data.table(Date = udates, newD = sample(udates))
    rp <- merge(returns_dt[,.(Date,Ticker,Ret_1m)], remap, by="Date")[,.(Date=newD,Ticker,Ret_1m)]
    bp <- merge(bench_dt[,.(Date,BM_Ret)], remap, by="Date")[,.(Date=newD,BM_Ret)]
    null_t[p] <- port_t_of(sc, rp, bp)
  }
  null_t <- null_t[is.finite(null_t)]
  p_one <- mean(null_t >= obs)          # one-sided upper (positive hypothesis)
  p_two <- mean(abs(null_t) >= abs(obs))
  placebo[[f]] <- list(obs_port_t=obs, n_null=length(null_t),
                       null_mean=mean(null_t), null_sd=sd(null_t),
                       p_one_sided=p_one, p_two_sided=p_two,
                       null_q95=as.numeric(quantile(null_t,.95)))
  cat(sprintf("[placebo] %s obs=%.3f null(mean=%.2f sd=%.2f q95=%.2f) p_one=%.3f p_two=%.3f\n",
      f, obs, mean(null_t), sd(null_t), quantile(null_t,.95), p_one, p_two))
}

# DSR (sweep, n_trials=5) — Bailey-Lopez de Prado 2014, monthly (per-obs) Sharpe
dsr_of <- function(active, sr_trials, N_trials) {
  n <- length(active); sr <- mean(active)/sd(active)
  sk <- { m<-mean(active); s<-sd(active); mean((active-m)^3)/s^3 }
  ku <- { m<-mean(active); s<-sd(active); mean((active-m)^4)/s^4 }
  varsr <- var(sr_trials)
  gamma <- 0.5772156649
  emax <- sqrt(varsr) * ((1-gamma)*qnorm(1-1/N_trials) + gamma*qnorm(1-1/(N_trials*exp(1))))
  z <- (sr - emax) * sqrt(n-1) / sqrt(1 - sk*sr + (ku-1)/4*sr^2)
  list(sr_monthly=sr, skew=sk, kurt=ku, sr0_expmax=emax, dsr=pnorm(z))
}
sr_trials <- sapply(active_by_factor, function(a) mean(a)/sd(a))
best <- names(which.max(sr_trials))
dsr_best <- dsr_of(active_by_factor[[best]], sr_trials, length(FACS))
cat(sprintf("\n[DSR] best=%s sr_m=%.3f sr0_expmax=%.3f DSR=%.3f (n_trials=%d)\n",
    best, dsr_best$sr_monthly, dsr_best$sr0_expmax, dsr_best$dsr, length(FACS)))

write_json(list(n_perm=N_PERM, placebo=placebo,
                dsr=list(best_factor=best, sr_trials=as.list(round(sr_trials,3)),
                         n_trials=length(FACS), detail=dsr_best)),
           file.path(STAGE,"results_placebo_dsr.json"), auto_unbox=TRUE, pretty=TRUE, na="null")
cat("[DONE measure_placebo]\n")
