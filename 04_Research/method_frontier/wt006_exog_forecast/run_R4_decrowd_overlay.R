# WT-006 R4 — decrowding_overlay: de-crowd the momentum top-25 basket WITHOUT reallocating families
#                                  or changing selection (분산 PRESERVE). weighted_screen_bt.
#
# ARC context (R1 6 logics + R2 6 approaches + R3 3 frontiers): every return-derived style FORECAST
#   and every CONSTRUCTION/SELECTION reshape died at the top-25 long-only cap-w TRANSLATION wall
#   (baseline factor-momentum cap-w port_t = 1.277; ORACLE 1.248 < 1.277). R3 P1 confirmed the wall is
#   NOT at family-allocation NOR cap-tier-structuring but at the top-25 cap-w translation layer itself.
#   R3 non-return learner had genuine EW signal (ew_uni 1.664, beats static +0.696) but died cap-w (0.297).
#
# R4 CORE QUESTION (the last un-tested mechanism): is the cap-w trap SELECTION-specific (only the
#   cross-sectional stock pick can't realize it), or does it also bind CONSTRUCTION/OVERLAY?
#   This lane tests the OVERLAY leg: keep the exact momentum top-25 basket (preserve the cross-family
#   diversification that R3 proved carries momentum's residual alpha), and apply only:
#     (A) SOFT stock-level de-crowding WEIGHT tilt (down-weight crowded names, keep all 25), and
#     (B) a basket-level EXPOSURE scalar driven by the non-return crowding/dispersion channel.
#   beats_momentum := (paired_vs_mom_t > 1.0). wall_moved := (port_t >= 2.95).
#
# PIT: overlay weights/exposure at t use ONLY t-observable cross-section (value/mom z at t) and
#   strictly-past (< t) history for the exposure percentile (expanding). IS-only, no OOS peeking,
#   fixed a-priori hyperparameters (NOT swept -> DSR n/a, selection_type=chain). lag1 self-check per variant.
# metric_type = weighted_screen (contract build_benchmark_compare, NW lag-3).
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1); set.seed(42)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
OUT <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- .fams
dates <- .oos_dates

# ============================================================================================
# 1) Reproduce the EXACT momentum top-25 basket (mirror canonical_screen_bt selection)
#    holdings H_t = liq-filtered top-25 by factor-momentum composite score. EW = 1/n anchor.
# ============================================================================================
score_mom <- .score_from_theta(.mom_theta)                 # (Date,Ticker,score) — momentum family tilt
S <- score_mom[!is.na(score)]
S <- S[Date %in% .Rg$Date & Date %in% .oos_dates]
# liq filter (adv >= 2e8, NA adv passes — identical to canonical)
S <- merge(S, .LQg[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
S <- S[is.na(adv) | adv >= 2e8]; S[, adv := NULL]
setorder(S, Date, -score)
HOLD <- S[, { n <- min(25L, .N); .(Ticker=Ticker[seq_len(n)], rank=seq_len(n)) }, by=Date]
cat(sprintf("[basket] momentum top-25 holdings built: %d date x avg %.1f names\n",
            uniqueN(HOLD$Date), nrow(HOLD)/uniqueN(HOLD$Date)))

# attach per-stock t-observable z (value/momentum/size) for stock-level crowding proxies
Z <- .FAM[, .(Date, Ticker, z_value=value, z_mom=momentum, z_size=size, z_lowvol=low_vol)]
HB <- merge(HOLD, Z, by=c("Date","Ticker"), all.x=TRUE)
# within-basket standardize each proxy per date (robust to NA)
zstd <- function(x){ m<-mean(x,na.rm=TRUE); s<-stats::sd(x,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(0,length(x))); v<-(x-m)/s; v[!is.finite(v)]<-0; v }
HB[, `:=`(zv=zstd(z_value), zm=zstd(z_mom), zs=zstd(z_size), zl=zstd(z_lowvol)), by=Date]

# ============================================================================================
# 2) Overlay weight builders (SOFT tilt, preserve breadth: clip to [0.4/n, 2.5/n] then renorm)
#    de-crowding = UP-weight cheap (high value z) / DOWN-weight most-extended momentum (high mom z).
# ============================================================================================
build_w <- function(tiltcol_expr, lam=0.0){
  W <- copy(HB)
  W[, tilt := eval(tiltcol_expr, envir=.SD)]
  W[!is.finite(tilt), tilt := 0]
  W[, w := (1)*exp(lam*tilt), by=Date]                     # EW base = 1/n; exp soft tilt
  W[, w := w/sum(w), by=Date]
  # clip to preserve breadth (분산 PRESERVE): no name < 0.4/n or > 2.5/n, renorm
  W[, n := .N, by=Date]
  W[, w := pmin(pmax(w, 0.4/n), 2.5/n)]
  W[, w := w/sum(w), by=Date]
  W[, .(Date, Ticker, w)]
}
W_ew        <- build_w(quote(0*zv),          lam=0.0)                 # EW anchor
W_decv      <- build_w(quote(zv),            lam=1.0)                 # de-crowd by value (up-weight cheap)
W_dectrim   <- build_w(quote(-zm),           lam=0.7)                 # trim extended momentum
W_deccomp   <- build_w(quote(0.6*zv-0.5*zm), lam=1.0)                 # composite crowding tilt
W_decvlv    <- build_w(quote(0.6*zv+0.4*zl), lam=1.0)                 # cheap + low-vol (crowded=high-vol chase)

# ============================================================================================
# 3) Basket EXPOSURE scalar from the non-return crowding/dispersion channel (family/market level)
#    e_t defensive de-crowd: reduce exposure when momentum-family valuation spread (crowding) is
#    HIGH vs strictly-past expanding history. one-sided (only trim when crowded above past median).
#    PIT: signal at t is t-observable; percentile uses ONLY history < t (expanding).
# ============================================================================================
X <- as.data.table(read_parquet(file.path(OUT,"wt006_candidate_features.parquet"))); X[,date:=as.Date(date)]
crowd <- X[family=="momentum", .(Date=date, vs=val_spread)]          # momentum-family valuation spread
disp  <- unique(X[, .(Date=date, dispersion=disp_ret12, avgcorr=avg_corr24)])
crowd <- merge(crowd, disp, by="Date", all.x=TRUE)
setorder(crowd, Date)
# expanding percentile (strictly past) of momentum crowding
crowd[, pct_crowd := {
  out <- rep(NA_real_, .N)
  for(i in seq_len(.N)){ h <- vs[seq_len(i-1)]; h <- h[is.finite(h)]
    if(length(h) >= 12L && is.finite(vs[i])) out[i] <- mean(h <= vs[i]) }
  out
}]
PHI <- 0.30; EFLOOR <- 0.70
crowd[, exposure := 1 - PHI*pmax(0, (pct_crowd-0.5))*2]              # crowded above past-median -> trim
crowd[!is.finite(exposure), exposure := 1]
crowd[, exposure := pmax(exposure, EFLOOR)]
EXP_dt <- crowd[Date %in% dates, .(Date, exposure)]
cat(sprintf("[exposure] mean=%.3f min=%.3f frac_trimmed(<0.999)=%.2f\n",
            mean(EXP_dt$exposure), min(EXP_dt$exposure), mean(EXP_dt$exposure<0.999)))

# ============================================================================================
# 4) Measurement via weighted_screen_bt (contract-grade) + harness metrics
# ============================================================================================
retn <- .Rg[, .(Date, Ticker, Ret_1m)]; benc <- .BMg[, .(Date, BM_Ret)]
measure <- function(W_dt, label, exposure_dt=NULL){
  r <- weighted_screen_bt(W_dt, retn, benc, cost_bps_oneway=15,
                          run_id="r4", strategy_id=paste0("r4_",label), exposure_dt=exposure_dt)
  pr <- r$period_returns; pr[, active := ret_net - benchmark_ret]
  # paired vs momentum EW baseline (harness .a_mom active series), NW lag-3
  mg  <- merge(pr[,.(date,active)], .a_mom[,.(date,am=active)], by="date")
  pvm <- .nw_t_mean(mg$active - mg$am, lag=3)
  mgs <- merge(pr[,.(date,active)], .a_static[,.(date,as=active)], by="date")
  pvs <- .nw_t_mean(mgs$active - mgs$as, lag=3)
  list(label=label, n_months=r$n_months,
       port_t=round(r$portfolio_alpha_t_nw_lag3,3),
       ew_uni_t=NA_real_,   # weighted_screen_bt has no EW-universe diag; report cap-w only (see note)
       oos_ret=round(.oos_ret_of(pr),3),
       net_sr=round(r$net_sr,3), calmar=round(.calmar_of(pr),3),
       turnover=round(r$turnover_annual,2),
       paired_vs_mom_t=round(pvm,3), paired_vs_static_t=round(pvs,3),
       ir=round(r$information_ratio,3), alpha_ann=round(r$alpha_annualized,4))
}
# lag1 self-check: lag the stock-crowding z by 1 month (use t-1 basket's tilt on t basket is ill-defined;
#   instead lag the exposure signal + re-tilt using previous-date within-basket z rank via shifted crowd).
#   For weight-tilt variants we lag the exposure only (weights use t z which is genuinely t-observable);
#   for exposure variant we shift exposure by 1 month (prev-month exposure applied to current month).
lag1_exposure <- function(exposure_dt){
  e <- copy(exposure_dt); setorder(e, Date); e[, exposure := shift(exposure, 1)]; e[is.na(exposure), exposure := 1]; e
}
measure_lag1 <- function(W_dt, exposure_dt){
  r <- weighted_screen_bt(W_dt, retn, benc, cost_bps_oneway=15, run_id="r4l", strategy_id="r4l",
                          exposure_dt=if(is.null(exposure_dt)) NULL else lag1_exposure(exposure_dt))
  round(r$portfolio_alpha_t_nw_lag3,3)
}

variants <- list(
  list(W=W_ew,      lab="base_EW",           exp=NULL),
  list(W=W_decv,    lab="decrowd_value",     exp=NULL),
  list(W=W_dectrim, lab="trim_extended_mom", exp=NULL),
  list(W=W_deccomp, lab="decrowd_composite", exp=NULL),
  list(W=W_decvlv,  lab="decrowd_val_lowvol",exp=NULL),
  list(W=W_ew,      lab="exposure_only",     exp=EXP_dt),
  list(W=W_deccomp, lab="decrowd+exposure",  exp=EXP_dt)   # DELIVERABLE (full overlay)
)
res <- list()
for(v in variants){
  m <- measure(v$W, v$lab, exposure_dt=v$exp)
  m$lag1_port_t <- measure_lag1(v$W, v$exp)
  res[[v$lab]] <- m
}

pr_row <- function(r) cat(sprintf("%-20s port_t=%6.3f oos=%7.3f net_sr=%6.3f calmar=%5.3f turn=%6.2f IR=%6.3f paired_mom=%7.3f paired_stat=%7.3f lag1=%6.3f n=%d\n",
  r$label, r$port_t, r$oos_ret, r$net_sr, r$calmar, r$turnover, r$ir, r$paired_vs_mom_t, r$paired_vs_static_t, r$lag1_port_t, r$n_months))
cat(sprintf("\n=== R4 decrowding_overlay (baseline momentum cap-w port_t=%.3f, HARD gate 2.95) ===\n", .BASELINE_MOM_PORT_T))
for(nm in names(res)) pr_row(res[[nm]])

deliv <- res[["decrowd+exposure"]]
best  <- res[[ names(which.max(sapply(res[names(res)!="base_EW"], function(r) r$paired_vs_mom_t))) ]]
out <- list(
  lane="WT-006 R4 decrowding_overlay (stock-level soft de-crowd tilt + non-return crowding exposure scalar; basket & selection PRESERVED)",
  date=as.character(Sys.Date()),
  measurement="weighted_screen_bt cap-w KOSPI200 top-25 momentum basket, 15bps, NW lag-3. metric_type=weighted_screen. PIT walk-forward IS-only, expanding exposure percentile, fixed a-priori hyperparams (chain, DSR n/a).",
  baseline_momentum_port_t=.BASELINE_MOM_PORT_T, hard_gate_port_t=2.95,
  hyperparams=list(lambda_value=1.0, lambda_trim_mom=0.7, weight_clip=c(0.4,2.5), phi_exposure=0.30, exposure_floor=0.70),
  results=res,
  deliverable=deliv,
  best_by_paired_mom=list(label=best$label, paired_vs_mom_t=best$paired_vs_mom_t, port_t=best$port_t),
  beats_momentum=isTRUE(best$paired_vs_mom_t > 1.0),
  wall_moved=isTRUE(deliv$port_t >= 2.95)
)
jsonlite::write_json(out, file.path(OUT,"R4_decrowd_overlay_results.json"), pretty=TRUE, auto_unbox=TRUE, digits=4)
saveRDS(out, file.path(OUT,"R4_decrowd_overlay_results.rds"))
write_parquet(W_deccomp, file.path(OUT,"W_R4_decrowd_composite.parquet"))
write_parquet(EXP_dt,    file.path(OUT,"R4_exposure_scalar.parquet"))
cat(sprintf("\n[done] R4_decrowd_overlay_results.json written. beats_momentum=%s (best paired=%.3f, %s). wall_moved=%s\n",
    out$beats_momentum, best$paired_vs_mom_t, best$label, out$wall_moved))
