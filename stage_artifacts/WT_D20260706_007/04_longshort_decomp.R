# 04_longshort_decomp.R — long-side vs short-side decomposition (THE JUDGMENT LENS)
# Question: value/spread-timing edge from cheap stocks RISING (long-side, harvestable)
#           or expensive stocks FALLING (short-side, NOT harvestable long-only)?
# Method: quintile net-active t. long-side = top-quintile(cheapest) EW active vs bench.
#         short-side = bottom-quintile(expensive) EW active vs bench (negated for "short would profit").
suppressMessages({library(data.table)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
log <- function(...) { cat(format(Sys.time(),"%H:%M:%S"), ..., "\n"); flush.console() }
E <- readRDS(file.path(OUT,"experiment_results.rds"))
fwd <- E$fwd; bm2 <- E$bm2

nwt <- function(a){ n<-length(a); if(n<12) return(NA_real_); m<-mean(a);
  ac<-acf(a,lag.max=3,plot=FALSE,demean=TRUE)$acf[2:4]
  s2<-var(a)/n*(1+2*sum((1-(1:3)/n)*ac)); if(!is.finite(s2)||s2<=0) return(NA_real_); m/sqrt(s2) }

# per-month quintiles by score; EW quintile forward returns; active vs bench
decomp <- function(score_col, sub_from=NULL){
  d <- fwd[is.finite(get(score_col))]
  if(!is.null(sub_from)) d <- d[ym>=sub_from]
  d[, q := cut(frank(get(score_col))/.N, breaks=c(0,.2,.4,.6,.8,1), labels=1:5, include.lowest=TRUE), by=ym]
  # quintile 5 = highest score = cheapest/best (long candidate); quintile 1 = expensive/worst
  qr <- d[, .(ret=mean(fwd_mret)), by=.(Date, q)]
  qr <- merge(qr, bm2, by="Date")
  qr[, active := ret - BM_Ret]
  # long-side = Q5 active; short-side-avoidance = -(Q1 active) [expensive falling => Q1 active<0 => -Q1>0]
  q5 <- qr[q==5][order(Date)]; q1 <- qr[q==1][order(Date)]
  ls <- merge(q5[,.(Date,a5=active)], q1[,.(Date,a1=active)], by="Date")
  ls[, spread_q := a5 - a1]   # long-short (Q5-Q1) — full factor payoff
  list(
    n = nrow(ls),
    long_side_t   = nwt(ls$a5),        # Q5 (cheapest) net-active t — HARVESTABLE long-only
    long_side_mean= mean(ls$a5)*12*100,
    short_side_t  = nwt(-ls$a1),       # -(Q1 expensive active) — profit if could short. >0 & big => short-driven
    short_side_mean = mean(-ls$a1)*12*100,
    ls_spread_t   = nwt(ls$spread_q),  # Q5-Q1 full long-short factor t
    ls_spread_mean= mean(ls$spread_q)*12*100
  )
}

variants <- list(
  value_full   = list(sc="val_z",  from=NULL),
  value_2017   = list(sc="val_z",  from=201701L),
  valqual_full = list(sc="vq_z",   from=NULL),
  valqual_2017 = list(sc="vq_z",   from=201701L),
  quality_full = list(sc="qual_z", from=NULL),
  quality_2017 = list(sc="qual_z", from=201701L)
)
res <- rbindlist(lapply(names(variants), function(nm){
  v <- variants[[nm]]; r <- decomp(v$sc, v$from)
  data.table(variant=nm, n=r$n,
    long_side_t=round(r$long_side_t,2), long_ann_pct=round(r$long_side_mean,2),
    short_side_t=round(r$short_side_t,2), short_ann_pct=round(r$short_side_mean,2),
    LS_spread_t=round(r$ls_spread_t,2), LS_ann_pct=round(r$ls_spread_mean,2))
}))
log("==== LONG-SIDE vs SHORT-SIDE DECOMPOSITION ====")
log("long_side_t = Q5(cheapest) net-active t = HARVESTABLE long-only")
log("short_side_t = -(Q1 expensive active) t = profit ONLY if could short (NOT harvestable)")
log("LS_spread_t = Q5-Q1 full factor t (academic long-short)")
print(res)
fwrite(res, file.path(OUT,"longshort_decomp.csv"))

# ---- spread-conditional decomposition: within EXTREME-spread months only (ON regime) ----
log("\n==== WITHIN EXTREME-SPREAD MONTHS (pctile>=0.80) — is reversion long-side? ====")
decomp_cond <- function(score_col, thr){
  d <- fwd[is.finite(get(score_col)) & exp_pctile>=thr]
  d[, q := cut(frank(get(score_col))/.N, breaks=c(0,.2,.4,.6,.8,1), labels=1:5, include.lowest=TRUE), by=ym]
  qr <- d[, .(ret=mean(fwd_mret)), by=.(Date, q)]
  qr <- merge(qr, bm2, by="Date"); qr[, active := ret-BM_Ret]
  q5 <- qr[q==5][order(Date)]; q1 <- qr[q==1][order(Date)]
  ls <- merge(q5[,.(Date,a5=active)], q1[,.(Date,a1=active)], by="Date")
  data.table(n=nrow(ls), long_side_t=round(nwt(ls$a5),2), long_ann=round(mean(ls$a5)*12*100,2),
             short_side_t=round(nwt(-ls$a1),2), short_ann=round(mean(-ls$a1)*12*100,2),
             LS_t=round(nwt(ls$a5-ls$a1),2))
}
cond_res <- rbindlist(list(
  cbind(variant="value_ON_p80",   decomp_cond("val_z",0.80)),
  cbind(variant="valqual_ON_p80", decomp_cond("vq_z", 0.80)),
  cbind(variant="quality_ON_p80", decomp_cond("qual_z",0.80))
), fill=TRUE)
print(cond_res)
fwrite(cond_res, file.path(OUT,"longshort_decomp_conditional.csv"))
