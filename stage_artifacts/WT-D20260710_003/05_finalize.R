# 05_finalize.R — Stage B: OOS (1 look on winner) + full map + DSR(sweep) + placebo + jackknife + holdout.
# Selection was locked in Stage A (winner_config.json). This stage does the honest OOS test.
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "stage_artifacts/WT-D20260710_003/02_harness.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260710_003")
bundle <- readRDS(file.path(OUT, "panel_bundle.rds"))
regime <- build_regime_signal(bundle)
CFG <- readRDS(file.path(OUT, "all_configs.rds"))
win <- fromJSON(file.path(OUT, "winner_config.json"))
wcfg <- CFG[[which(sapply(CFG, function(c) c$id) == win$winner_id)]]
n_trials <- win$n_trials
cat(sprintf("[fin] WINNER=%s  n_trials=%d\n", win$winner_id, n_trials))

runwin <- function(cfg, w) screen_config(cfg, bundle, regime=regime, window=w)

# ---- full map: full+OOS for ALL configs (post-selection reporting, non-binding) ----
map <- list()
for (cfg in CFG) {
  rf <- tryCatch(runwin(cfg,"full"), error=function(e) NULL)
  ro <- tryCatch(runwin(cfg,"OOS"),  error=function(e) NULL)
  if (is.null(rf)) next
  map[[length(map)+1]] <- data.table(id=cfg$id, H=cfg$H,
    full_port_t=rf$port_t, full_net_sr=rf$net_sr, full_calmar=rf$calmar, full_oos_ret=rf$oos_retention,
    oos_port_t=if(!is.null(ro)) ro$port_t else NA, oos_net_sr=if(!is.null(ro)) ro$net_sr else NA,
    bm_cor=rf$bm_cor, bm_dIR=rf$bm_dIR_sleeve)
}
mapdt <- rbindlist(map); setorder(mapdt, -full_port_t)
fwrite(mapdt, file.path(OUT, "full_oos_map.csv"))
cat("\n[fin] === FULL + OOS MAP (post-selection, reporting) ===\n")
print(mapdt[, .(id,H,full_port_t=round(full_port_t,2),oos_port_t=round(oos_port_t,2),
                oos_net_sr=round(oos_net_sr,2),full_calmar=round(full_calmar,2),bm_dIR=round(bm_dIR,3))])

# ---- WINNER detail: IS / OOS / full ----
wis <- runwin(wcfg,"IS"); woos <- runwin(wcfg,"OOS"); wf <- runwin(wcfg,"full")
cat(sprintf("\n[fin] WINNER %s  IS port_t=%.3f (n=%d) | OOS port_t=%.3f net_sr=%.3f (n=%d) | FULL port_t=%.3f calmar=%.3f\n",
    win$winner_id, wis$port_t, wis$n_months, woos$port_t, woos$net_sr, woos$n_months, wf$port_t, wf$calmar))

# ---- DSR (sweep, Bailey-Lopez de Prado) on winner FULL net returns, deflated by n_trials ----
dsr_sweep <- function(net, trial_srs_monthly, N) {
  sr <- mean(net)/sd(net)              # per-period (monthly)
  n  <- length(net)
  sk <- PerformanceAnalytics::skewness(net); ku <- PerformanceAnalytics::kurtosis(net) + 3  # kurtosis() is excess
  gamma <- 0.5772156649
  vsr <- sd(trial_srs_monthly)
  sr0 <- vsr * ((1-gamma)*qnorm(1 - 1/N) + gamma*qnorm(1 - 1/(N*exp(1))))
  denom <- sqrt(1 - sk*sr + ((ku-1)/4)*sr^2)
  z <- (sr - sr0) * sqrt(n - 1) / denom
  list(dsr=pnorm(z), sr_monthly=sr, sr0_hurdle=sr0, skew=sk, kurt=ku, n=n, vsr=vsr)
}
# trial SRs (monthly) from full-period net_sr of all configs (annualized -> /sqrt(12))
trial_sr_m <- sapply(CFG, function(cfg){ r<-tryCatch(runwin(cfg,"full"),error=function(e)NULL); if(is.null(r)) NA else r$net_sr/sqrt(12)})
trial_sr_m <- trial_sr_m[is.finite(trial_sr_m)]
D <- dsr_sweep(wf$pr$ret_net - wf$pr$benchmark_ret * 0 + (wf$active), trial_sr_m, n_trials)  # use ACTIVE series SR (alpha)
# NOTE: DSR on active(alpha) series — consistent with alpha screening (excess-over-bench)
Dact <- dsr_sweep(wf$active, trial_sr_m, n_trials)
cat(sprintf("[fin] DSR(sweep, active) = %.3f  [sr_m=%.3f hurdle_sr0=%.3f skew=%.2f kurt=%.2f N=%d]  -> HARD>=0.5 %s\n",
    Dact$dsr, Dact$sr_monthly, Dact$sr0_hurdle, Dact$skew, Dact$kurt, n_trials, ifelse(Dact$dsr>=0.5,"PASS","FAIL")))

# ---- Placebo: random 25-name EW long-only portfolios, full-period port_t null ----
set.seed(710003)
liq <- merge(bundle$returns[,.(Date,Ticker,Ret_1m)], bundle$univ[,.(Date,Ticker,adv20)], by=c("Date","Ticker"))
liq <- liq[is.na(adv20)|adv20>=2e8]
months <- sort(unique(liq$Date))
Bd <- bundle$bench
nperm <- 200
plac <- numeric(nperm)
for (p in 1:nperm) {
  W <- liq[, {ii <- sample(.N, min(25,.N)); .(Ticker=Ticker[ii], w=1/length(ii))}, by=Date]
  WR <- merge(W, liq[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
  port <- WR[, .(rg=sum(w*Ret_1m)), by=Date]
  pr <- merge(port[,.(date=Date,rg)], Bd[,.(date=Date,bm=BM_Ret)], by="date")
  a <- pr$rg - pr$bm  # gross active (placebo null; cost roughly common)
  plac[p] <- .nw_t_mean(a, lag=3)
}
win_full_t <- wf$port_t
plac_p <- mean(plac >= win_full_t)
cat(sprintf("[fin] Placebo (n=%d random 25-EW): null port_t mean=%.2f sd=%.2f q95=%.2f | winner_full=%.2f  p=%.3f\n",
    nperm, mean(plac), sd(plac), quantile(plac,.95), win_full_t, plac_p))

# ---- Jackknife by continuous subwindow (3 blocks) on winner FULL active ----
a <- wf$active; d <- wf$dates; n <- length(a); b <- floor(n/3)
blk <- list(a[1:b], a[(b+1):(2*b)], a[(2*b+1):n])
jk <- sapply(blk, function(v) .nw_t_mean(v, lag=3))
cat(sprintf("[fin] Jackknife 3 continuous blocks (winner active NW-t): %.2f / %.2f / %.2f  (all>0: %s)\n",
    jk[1], jk[2], jk[3], all(jk>0)))

# ---- Holdout falsification: IS block-bootstrap OOS-length Sharpe [q05,q95], vs OOS realized ----
is_active <- wis$active; oos_len <- woos$n_months
set.seed(99)
bb <- replicate(2000, {
  blocks <- ceiling(oos_len/12); idx <- sample(1:(length(is_active)-12+1), blocks, replace=TRUE)
  s <- unlist(lapply(idx, function(i) is_active[i:(i+11)]))[1:oos_len]
  mean(s)/sd(s)*sqrt(12)
})
q05 <- quantile(bb,.05); q95 <- quantile(bb,.95)
oos_sr <- woos$net_sr
verdict <- if (oos_sr < q05) "FAIL_FALSIFIED" else if (oos_sr > q95) "PASS_PLUS" else "PASS_LOW_INFO"
cat(sprintf("[fin] Holdout falsification: IS-bootstrap OOS-len Sharpe [q05=%.2f, q95=%.2f] | OOS realized=%.2f -> %s\n",
    q05, q95, oos_sr, verdict))

fin <- list(
  winner_id=win$winner_id, n_trials=n_trials,
  winner_metrics=list(is_port_t=wis$port_t, oos_port_t=woos$port_t, oos_net_sr=woos$net_sr,
                      full_port_t=wf$port_t, full_calmar=wf$calmar, full_net_sr=wf$net_sr,
                      bm_cor=wf$bm_cor, bm_dIR_sleeve=wf$bm_dIR_sleeve, is_n=wis$n_months, oos_n=woos$n_months),
  dsr_sweep_active=Dact,
  placebo=list(nperm=nperm, null_mean=mean(plac), null_q95=as.numeric(quantile(plac,.95)), winner_full_t=win_full_t, p_value=plac_p),
  jackknife_3block_nwt=as.numeric(jk), jackknife_all_pos=all(jk>0),
  holdout=list(is_bootstrap_q05=as.numeric(q05), q95=as.numeric(q95), oos_realized_sr=oos_sr, verdict=verdict))
write_json(fin, file.path(OUT, "finalize_results.json"), pretty=TRUE, auto_unbox=TRUE)
cat("\n[fin] finalize_results.json written. DONE\n")
