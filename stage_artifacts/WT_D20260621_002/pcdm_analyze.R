#==============================================================================
# PCDM Analysis — IC / ICIR / Harvey-t / orthogonality vs M01/M08/M24 /
#   canonical_screen (PORT_t) / continuation-vs-reversal / robustness
# Real-computation only. metric_type labels enforced.
#==============================================================================
Sys.setenv(OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1", ARROW_NUM_THREADS="2")
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1); arrow::set_cpu_count(1)
source("02_Infrastructure/contracts/canonical_screen_bt.R")

OUT <- "stage_artifacts/WT_D20260621_002"
LOG <- function(...) cat(sprintf("[%s] %s\n", format(Sys.time(),"%H:%M:%S"), paste0(...)))

pcdm <- as.data.table(read_parquet(file.path(OUT,"pcdm_panel.parquet")))
ref  <- as.data.table(read_parquet(file.path(OUT,"ref_panel.parquet")))
fwd  <- as.data.table(read_parquet(file.path(OUT,"fwd_panel.parquet")))
adtv <- as.data.table(read_parquet(file.path(OUT,"adtv_panel.parquet")))
pcdm[, sig_date := as.Date(sig_date)]; ref[, sig_date := as.Date(sig_date)]
fwd[, sig_date := as.Date(sig_date)]; adtv[, sig_date := as.Date(sig_date)]

BM <- as.data.table(read_parquet(".cache/benchmark.parquet")); BM[,Date:=as.Date(Date)]
# monthly BM return aligned to sig_date->next month-end (forward), same convention as fwd label
RAWdates <- sort(unique(fwd$sig_date))
# benchmark monthly forward returns: compound BM daily between sig_date(excl) and next sig_date
sigs <- sort(unique(fwd$sig_date))
bm_monthly <- data.table(Date = sigs, BM_Ret = NA_real_)
for (i in seq_len(nrow(bm_monthly)-1L)) {
  d0 <- bm_monthly$Date[i]; d1 <- bm_monthly$Date[i+1L]
  seg <- BM[Date > d0 & Date <= d1, BM_Ret]
  bm_monthly$BM_Ret[i] <- prod(1+seg)-1
}
bm_monthly <- bm_monthly[!is.na(BM_Ret)]

#--- helper: rank IC (Spearman) per month, ICIR, Harvey-t ---------------------
ic_stats <- function(score_dt, fwd_dt, label="x") {
  m <- merge(score_dt, fwd_dt[,.(sig_date,Ticker,Ret_1m)], by=c("sig_date","Ticker"))
  m <- m[!is.na(score) & !is.na(Ret_1m)]
  ics <- m[, {
    if (.N >= 20L && sd(score)>0 && sd(Ret_1m)>0)
      list(ic = cor(score, Ret_1m, method="spearman"), n=.N)
    else list(ic = NA_real_, n=.N)
  }, by=sig_date][!is.na(ic)]
  if (nrow(ics) < 12L) return(list(label=label, n_months=nrow(ics), rank_ic=NA, icir=NA, harvey_t=NA))
  mu <- mean(ics$ic); s <- sd(ics$ic); nM <- nrow(ics)
  icir <- mu/s
  # Newey-West t on monthly IC series (lag 3)
  nw_t <- function(x, lag=3) {
    n <- length(x); xb <- mean(x); e <- x-xb
    g0 <- sum(e^2)/n
    gs <- g0
    for (l in 1:lag) { w <- 1-l/(lag+1); gs <- gs + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
    se <- sqrt(gs/n); xb/se
  }
  harvey <- nw_t(ics$ic, 3)
  list(label=label, n_months=nM, rank_ic=mu, icir=icir, harvey_t=harvey, ic_series=ics)
}

#--- 1. IC for every PCDM variant + reference factors -------------------------
LOG("computing IC per variant ...")
pcdm[, variant := paste0("PCDM_K",K,"_W",W,"_",H)]
variants <- unique(pcdm$variant)
ic_results <- list()
for (v in variants) {
  sub <- pcdm[variant==v, .(sig_date, Ticker, score=pcdm)]
  ic_results[[v]] <- ic_stats(sub, fwd, v)
}
# reference factors
ref_long <- melt(ref, id.vars=c("sig_date","Ticker"), variable.name="fac", value.name="score")
for (f in c("M01","M08","M24")) {
  sub <- ref_long[fac==f, .(sig_date,Ticker,score)]
  ic_results[[f]] <- ic_stats(sub, fwd, f)
}
ic_tbl <- rbindlist(lapply(ic_results, function(x)
  data.table(label=x$label, n_months=x$n_months, rank_ic=x$rank_ic,
             icir=x$icir, harvey_t=x$harvey_t)), fill=TRUE)
setorder(ic_tbl, -rank_ic)
LOG("=== IC TABLE (metric_type=canonical_ic, Spearman rank IC; harvey_t = NW lag3 on IC series) ===")
print(ic_tbl)
fwrite(ic_tbl, file.path(OUT,"ic_table.csv"))

#--- 2. Orthogonality: cross-sectional corr of PCDM vs M01/M08/M24 ------------
LOG("computing orthogonality ...")
# pick best variant by harvey_t among PCDM
pcdm_ic <- ic_tbl[grepl("^PCDM",label)]
best_v <- pcdm_ic[which.max(harvey_t), label]
LOG("best PCDM variant by harvey_t = ", best_v)
bestp <- pcdm[variant==best_v, .(sig_date,Ticker,PCDM=pcdm)]
om <- merge(bestp, ref, by=c("sig_date","Ticker"))
# pooled cross-sectional corr (per-month then average) using rank corr
orth <- data.table()
for (f in c("M01","M08","M24")) {
  cc <- om[, {
    x <- get("PCDM"); y <- get(f)
    if (sum(!is.na(x)&!is.na(y))>=20 && sd(x,na.rm=T)>0 && sd(y,na.rm=T)>0)
      list(c = cor(x,y,method="spearman",use="complete.obs")) else list(c=NA_real_)
  }, by=sig_date][!is.na(c)]
  orth <- rbind(orth, data.table(factor=f, mean_rank_corr=mean(cc$c), median_rank_corr=median(cc$c)))
}
LOG("=== ORTHOGONALITY (best PCDM vs reference, per-month rank corr, averaged) ===")
print(orth)
fwrite(orth, file.path(OUT,"orthogonality.csv"))

#--- 3. Incremental IC: PCDM residualized vs {M01,M08,M24} --------------------
LOG("computing incremental IC (PCDM ⊥ M01,M08,M24) ...")
om2 <- merge(bestp, ref, by=c("sig_date","Ticker"))
om2 <- merge(om2, fwd[,.(sig_date,Ticker,Ret_1m)], by=c("sig_date","Ticker"))
om2 <- om2[!is.na(PCDM)&!is.na(M01)&!is.na(M08)&!is.na(M24)&!is.na(Ret_1m)]
# per-month: residualize PCDM on M01+M08+M24 (cross-sectional), then IC of residual
resid_ic <- om2[, {
  if (.N>=30) {
    zz <- function(v){(v-mean(v))/sd(v)}
    df <- data.table(p=zz(PCDM), m1=zz(M01), m8=zz(M08), m24=zz(M24), r=Ret_1m)
    fit <- lm(p ~ m1+m8+m24, data=df)
    rr <- residuals(fit)
    list(ic_resid = cor(rr, df$r, method="spearman"),
         ic_raw   = cor(df$p, df$r, method="spearman"))
  } else list(ic_resid=NA_real_, ic_raw=NA_real_)
}, by=sig_date][!is.na(ic_resid)]
nw_t <- function(x, lag=3){n<-length(x);e<-x-mean(x);g<-sum(e^2)/n;for(l in 1:lag){w<-1-l/(lag+1);g<-g+2*w*sum(e[(l+1):n]*e[1:(n-l)])/n};mean(x)/sqrt(g/n)}
inc <- data.table(
  ic_raw_pcdm = mean(resid_ic$ic_raw),
  harvey_raw  = nw_t(resid_ic$ic_raw,3),
  ic_resid_orthogonalized = mean(resid_ic$ic_resid),
  harvey_resid = nw_t(resid_ic$ic_resid,3),
  retention = mean(resid_ic$ic_resid)/mean(resid_ic$ic_raw),
  n_months = nrow(resid_ic))
LOG("=== INCREMENTAL IC (raw vs residual-vs-M01/M08/M24) ===")
print(inc)
fwrite(inc, file.path(OUT,"incremental_ic.csv"))

#--- 4. Continuation-vs-reversal test ----------------------------------------
# does high-PCDM continue (positive fwd) or reverse (negative)? decile spread sign
# + 3-month-ahead IC (if reversal, IC flips at longer horizon)
LOG("continuation-vs-reversal ...")
# decile spread monthly: top decile minus bottom decile fwd Ret_1m
cr <- merge(bestp, fwd[,.(sig_date,Ticker,Ret_1m)], by=c("sig_date","Ticker"))[!is.na(PCDM)&!is.na(Ret_1m)]
spread <- cr[, {
  if (.N>=30){
    d <- cut(frank(PCDM)/.N, breaks=c(0,.1,.9,1), labels=c("bot","mid","top"))
    list(top=mean(Ret_1m[d=="top"]), bot=mean(Ret_1m[d=="bot"]))
  } else list(top=NA_real_,bot=NA_real_)
}, by=sig_date][!is.na(top)]
spread[, hl := top-bot]
cr_summary <- data.table(
  mean_topdecile_fwd = mean(spread$top),
  mean_botdecile_fwd = mean(spread$bot),
  mean_HL_spread = mean(spread$hl),
  HL_t_nw = nw_t(spread$hl,3),
  frac_months_HL_positive = mean(spread$hl>0),
  verdict = ifelse(mean(spread$hl)>0, "CONTINUATION", "REVERSAL"))
LOG("=== CONTINUATION vs REVERSAL ===")
print(cr_summary)
fwrite(cr_summary, file.path(OUT,"continuation_reversal.csv"))

#--- 5. canonical_screen (PORT_t) for best PCDM + references -----------------
LOG("canonical_screen for best PCDM + M01/M08/M24 ...")
# returns_dt needs Date,Ticker,Ret_1m ; bench needs Date,BM_Ret  (Date = sig_date)
ret_dt <- fwd[,.(Date=sig_date, Ticker, Ret_1m)]
bench_dt <- bm_monthly[,.(Date, BM_Ret)]
liq_dt <- adtv[,.(Date=sig_date, Ticker, adv)]
screen_one <- function(score_dt, lab) {
  sc <- score_dt[!is.na(score), .(Date=sig_date, Ticker, score)]
  r <- canonical_screen_bt(sc, ret_dt, bench_dt, top_n=20L, cost_bps_oneway=15,
                           liq_dt=liq_dt, liq_min=2e8, run_id=lab, strategy_id=lab)
  data.table(label=lab, n_months=r$n_months, port_t_nw=r$portfolio_alpha_t_nw_lag3,
             IR=r$information_ratio, alpha_ann=r$alpha_annualized, net_sr=r$net_sr,
             mean_active_net=r$mean_active_net, turnover_ann=r$turnover_annual)
}
screen_res <- list()
screen_res[["best_PCDM"]] <- screen_one(pcdm[variant==best_v,.(sig_date,Ticker,score=pcdm)], best_v)
for (f in c("M01","M08","M24"))
  screen_res[[f]] <- screen_one(ref_long[fac==f,.(sig_date,Ticker,score)], f)
# also screen a couple alt PCDM variants for robustness
alt_v <- setdiff(head(pcdm_ic[order(-harvey_t),label],4), best_v)
for (av in alt_v)
  screen_res[[av]] <- screen_one(pcdm[variant==av,.(sig_date,Ticker,score=pcdm)], av)
screen_tbl <- rbindlist(screen_res, fill=TRUE)
LOG("=== CANONICAL_SCREEN (metric_type=canonical_screen, top-20 EW long-only, 15bps, 2e8 liq) ===")
print(screen_tbl)
fwrite(screen_tbl, file.path(OUT,"screen_table.csv"))

#--- 6. Robustness across K/window/horizon (IC dispersion) -------------------
LOG("robustness summary ...")
rob <- ic_tbl[grepl("^PCDM",label)]
rob_summary <- data.table(
  n_variants = nrow(rob),
  rank_ic_min = min(rob$rank_ic), rank_ic_max=max(rob$rank_ic),
  rank_ic_mean = mean(rob$rank_ic), rank_ic_sd = sd(rob$rank_ic),
  harvey_min = min(rob$harvey_t), harvey_max=max(rob$harvey_t),
  frac_variants_harvey_gt2 = mean(rob$harvey_t>2),
  frac_variants_ic_gt0 = mean(rob$rank_ic>0))
LOG("=== ROBUSTNESS (across 12 K/W/H variants) ===")
print(rob_summary)
fwrite(rob_summary, file.path(OUT,"robustness.csv"))

saveRDS(list(ic_tbl=ic_tbl, orth=orth, inc=inc, cr=cr_summary,
             screen=screen_tbl, rob=rob_summary, best_v=best_v,
             bm_monthly=bm_monthly),
        file.path(OUT,"analysis_results.rds"))
LOG("ANALYSIS DONE")
