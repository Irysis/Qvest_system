#!/usr/bin/env Rscript
# refine.R — WT-D20260718_007 정밀화: paired-return 유의화 3방향 실측 (PIT-clean, IS-only selection).
# D1 tau 정확 재매칭(exposure-budget confound 제거)  D2 grind(낙폭지속) 보완  D3 앙상블 최적가중(IS-only).
# base = M4 incumbent. 측정 = weighted_screen book A/B (carrier STR_1715 fixed, 15bps, WT-004 r1 pin).
suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1)
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")
Sys.setenv(QVEST_WEIGHTING_AB_NORUN="1", QVEST_REGIME_AB_NORUN="1")
source("02_Infrastructure/ops/auto_weighting_ab.R")
PIN <- ".cache/pins/WT-D20260718_007_r1"; ym <- function(d) format(as.Date(d),"%Y-%m")
ST  <- "stage_artifacts/WT_D20260718_007"

# ---- carrier + M4 + AE (same as ab_overlay_ae.R) ----
car <- as.data.table(read_parquet(file.path(PIN,"carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")))[selected==TRUE & !is.na(ret_fwd)]
car[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
returns_dt <- car[, .(Date=eval_date, Ticker, Ret_1m=ret_fwd)]
periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date); periods[, ym_e:=ym(eval_date)]
W_strat <- car[, .(Date=eval_date, Ticker, w=weight_strategy/sum(weight_strategy)), by=.(eval_date)][, .(Date,Ticker,w)]
bench_dt <- build_period_bench(periods, bench_path=file.path(PIN,"benchmark.parquet"))[!is.na(BM_Ret)]
Lr <- fread(file.path(PIN,"period_returns_layer5.csv")); Lr[, ym_a:=ym(anchor_date)]
comp <- Lr[, .(ym_a, m4=as.numeric(m4_weight_lag), ar=as.numeric(beta_threshold_lag), r05=as.numeric(beta_R05_V5))]
periods[comp, on=.(ym_e=ym_a), `:=`(m4=i.m4, ar=i.ar, r05=i.r05)]
ae <- as.data.table(read_parquet(file.path(ST,"ae_regime_signal.parquet")))
ae[, decision_date := as.Date(decision_date)]
periods[ae, on=.(decision_date), `:=`(ae_seq=i.ae_seq, tau_seq=i.tau_seq, fire_seq=i.fire_seq, ae_lfd=i.last_feat_date)]

# ============================ GRIND signal (PIT-safe from benchmark daily) ============================
# 'grind' = SLOW decline. NOT all-time-high drawdown (KOSPI didn't reclaim 2007 ATH for ~10y -> broken).
# Use ROLLING-252d-high drawdown (resets on new 1y high) + trailing 126d return.
bmd <- as.data.table(read_parquet(file.path(PIN,"benchmark.parquet")))[!is.na(BM_Close)]
bmd[, Date := as.Date(Date)]; setorder(bmd, Date)
bmd[, roll_max252 := frollapply(BM_Close, 252, max, align="right")]
bmd[is.na(roll_max252), roll_max252 := cummax(BM_Close)]              # expanding max for first 251 (past-only)
bmd[, dd252 := BM_Close/roll_max252 - 1]                              # drawdown from 1y-rolling high (<=0)
dur <- integer(nrow(bmd)); d <- 0L
for(i in seq_len(nrow(bmd))){ d <- if(bmd$dd252[i] >= -0.02) 0L else d+1L; dur[i] <- d }  # in >2% rolling DD
bmd[, dd_dur := dur]
bmd[, ret126 := BM_Close/shift(BM_Close,126) - 1]                     # trailing ~6M return
bmd[, ret63  := BM_Close/shift(BM_Close,63)  - 1]                     # trailing ~3M return
# monthly grind feature as-of last BM day STRICTLY BEFORE decision_date (holding-month start)
gfeat <- periods[, {
  cutoff <- decision_date - 1L
  sub <- bmd[Date <= cutoff]; last <- sub[.N]
  .(grind_cutoff=last$Date, dd_dur=last$dd_dur, ret126=last$ret126, ret63=last$ret63, dd252=last$dd252)
}, by=.(decision_date)]
periods[gfeat, on=.(decision_date), `:=`(grind_cutoff=i.grind_cutoff, dd_dur=i.dd_dur, ret126=i.ret126, ret63=i.ret63, dd252=i.dd252)]

per <- periods[!is.na(ae_seq) & !is.na(m4) & !is.na(dd_dur)]; setorder(per, eval_date)
per[, m4_fire := as.integer(m4 < 0.999)]
per[, ae_exp := fifelse(fire_seq==1, 0.70, 1.00)]
N <- nrow(per)
# ---- restrict all series to common overlay window (avoid pre-2008 bare contamination) ----
cw <- per$eval_date
returns_dt <- returns_dt[Date %in% cw]; W_strat <- W_strat[Date %in% cw]; bench_dt <- bench_dt[Date %in% cw]
cat(sprintf("[refine] months=%d  %s..%s  M4_fire=%.3f AE_fire=%.3f\n", N, min(per$eval_date), max(per$eval_date),
            mean(per$m4_fire), mean(per$fire_seq)))

# ---- IS window = first 60% (weight/threshold selection ONLY here). OOS = last 40% ----
is_cut <- per$eval_date[floor(0.60*N)]
per[, is_win := eval_date <= is_cut]
cat(sprintf("[split] IS %s..%s (n=%d) | OOS %s..%s (n=%d)\n",
            min(per$eval_date), is_cut, sum(per$is_win), per$eval_date[floor(0.60*N)+1], max(per$eval_date), sum(!per$is_win)))

# ---- grind: SLOW decline. IS-calibrated dd_dur threshold (rolling-252d DD) + trailing 6M return negative ----
thr_dur <- as.numeric(quantile(per[is_win==TRUE & dd_dur>0]$dd_dur, 0.60, na.rm=TRUE))
per[, grind_fire := as.integer(dd_dur >= thr_dur & ret126 < -0.05)]
per[, grind_exp := fifelse(grind_fire==1, 0.70, 1.00)]
cat(sprintf("[grind] IS thr_dur=%.0f trading-days (rolling-252d DD); grind_fire rate=%.3f (IS %.3f / OOS %.3f)\n",
            thr_dur, mean(per$grind_fire), mean(per[is_win==TRUE]$grind_fire), mean(per[is_win==FALSE]$grind_fire)))

# ============================ D1: tau exact re-match ============================
# D1a PIT-safe: expanding realized-quantile threshold on ae_seq targeting M4 fire rate; bootstrap first 36 mo w/ IS fire.
target_fr <- mean(per$m4_fire)  # 0.126
ae_seq <- per$ae_seq; fire_re <- integer(N); N0 <- 36L
for(i in seq_len(N)){
  if(i <= N0){ fire_re[i] <- per$fire_seq[i] }             # bootstrap: preserve early(2008) IS firing
  else { thr <- as.numeric(quantile(ae_seq[1:(i-1)], 1-target_fr, na.rm=TRUE)); fire_re[i] <- as.integer(ae_seq[i] > thr) }
}
per[, ae_rematch_exp := fifelse(fire_re==1, 0.70, 1.00)]
# D1b NON-PIT diagnostic ceiling: global top-(target_fr) of ae_seq = fire (look-ahead; labeled)
gthr <- as.numeric(quantile(ae_seq, 1-target_fr))
per[, ae_global_exp := fifelse(ae_seq > gthr, 0.70, 1.00)]
cat(sprintf("[D1] AE_rematch fire=%.3f (target %.3f) | AE_global(non-PIT) fire=%.3f\n",
            mean(fire_re), target_fr, mean(per$ae_seq>gthr)))

# ============================ D3: ensemble weighting ============================
# intersection: de-risk only when BOTH M4 & AE fire
per[, ens_int_exp := fifelse(m4_fire==1 & fire_seq==1, 0.70, 1.00)]
# IS-optimized convex blend of exposures w*m4 + (1-w)*ae_rematch ; pick w on IS book calmar
run1 <- function(exp_dt,id) weighted_screen_bt(W_strat, returns_dt, bench_dt, cost_bps_oneway=15, run_id=id, strategy_id=id, exposure_dt=exp_dt)
is_dates <- per[is_win==TRUE]$eval_date
calmar_is <- function(expv){
  ed <- per[, .(Date=eval_date, exposure=expv * ar * r05)][Date %in% is_dates]
  r <- weighted_screen_bt(W_strat[Date %in% is_dates], returns_dt[Date %in% is_dates], bench_dt[Date %in% is_dates],
                          cost_bps_oneway=15, run_id="is", strategy_id="is", exposure_dt=ed)
  r$abs_cagr/abs(r$abs_mdd)
}
ws <- seq(0,1,0.1)
cal_is <- sapply(ws, function(w) calmar_is(w*per$m4 + (1-w)*per$ae_rematch_exp))
w_best <- ws[which.max(cal_is)]
per[, ens_blend_exp := w_best*per$m4 + (1-w_best)*per$ae_rematch_exp]
cat(sprintf("[D3] IS-optimal blend w(M4)=%.1f (IS calmar=%.3f); intersection fire=%.3f\n",
            w_best, max(cal_is), mean(per$m4_fire & per$fire_seq)))

# ============================ run all scenarios ============================
mk <- function(x) per[, .(Date=eval_date, exposure=x)]
scen <- list(
  base_M4              = mk(per$m4 * per$ar * per$r05),
  AEseq_orig           = mk(per$ae_exp * per$ar * per$r05),
  D1a_AE_rematch       = mk(per$ae_rematch_exp * per$ar * per$r05),
  D1b_AE_global_LA     = mk(per$ae_global_exp * per$ar * per$r05),
  D2_grind_only        = mk(pmin(per$m4, per$grind_exp) * per$ar * per$r05),   # M4 (+) grind
  D2_M4_AE_grind       = mk(pmin(per$m4, per$ae_exp, per$grind_exp) * per$ar * per$r05),
  D2_AErematch_grind   = mk(pmin(per$ae_rematch_exp, per$grind_exp) * per$ar * per$r05),
  D3_intersection      = mk(per$ens_int_exp * per$ar * per$r05),   # de-risk only when BOTH M4 & AE fire
  D3_blend             = mk(per$ens_blend_exp * per$ar * per$r05)
)
res <- lapply(names(scen), function(nm) run1(scen[[nm]], nm)); names(res) <- names(scen)

nw_t <- function(x,lag=3){ x<-x[is.finite(x)]; n<-length(x); m<-mean(x); e<-x-m; g0<-sum(e*e)/n; v<-g0
  for(l in 1:lag){ w<-1-l/(lag+1); c<-sum(e[(l+1):n]*e[1:(n-l)])/n; v<-v+2*w*c }; list(t=m/sqrt(v/n), mean=m) }
paired_full <- function(id){ pb<-merge(res$base_M4$period_returns[,.(date,b=ret_net)], res[[id]]$period_returns[,.(date,a=ret_net)], by="date"); nw_t(pb$a-pb$b,3) }
paired_oos  <- function(id){ oos<-per[is_win==FALSE]$eval_date
  pb<-merge(res$base_M4$period_returns[,.(date,b=ret_net)], res[[id]]$period_returns[,.(date,a=ret_net)], by="date")[date %in% oos]; nw_t(pb$a-pb$b,3) }

tab <- rbindlist(lapply(names(res), function(nm){ r<-res[[nm]]; pf<-paired_full(nm); po<-paired_oos(nm)
  data.table(scenario=nm, SR=r$abs_net_sr, calmar=r$abs_cagr/abs(r$abs_mdd), MDD=r$abs_mdd, CAGR=r$abs_cagr,
             PORT_t=r$portfolio_alpha_t_nw_lag3, avg_exp=mean(scen[[nm]]$exposure,na.rm=TRUE),
             paired_t_full=pf$t, paired_t_oos=po$t) }))
cat("\n=== REFINEMENT SCENARIO TABLE (vs base_M4; paired NW-t lag3) ===\n"); print(tab)

# ---- PIT: grind cutoff HARD + lag1 on best refined + strict-PIT(grind loose vs strict via ret63 shift) ----
assert_overlay_pit(as.Date(per$grind_cutoff), as.Date(per$decision_date), label="grind_drawdown")
cat("[PIT] grind assert_overlay_pit PASS (grind_cutoff < holding-month start)\n")
# lag1 stress on D2_M4_AE_grind
per[, ae_lag1 := shift(ae_exp,1L)]; per[is.na(ae_lag1), ae_lag1:=1.0]
per[, grind_lag1 := shift(grind_exp,1L)]; per[is.na(grind_lag1), grind_lag1:=1.0]
r_lag1 <- run1(mk(pmin(per$m4, per$ae_lag1, per$grind_lag1) * per$ar * per$r05), "lag1")
cat(sprintf("[PIT] D2 lag1 stress: treat SR=%.3f lag1 SR=%.3f (붕괴=누출)\n", res$D2_M4_AE_grind$abs_net_sr, r_lag1$abs_net_sr))

# ---- crisis firing of grind (does it cover 2011/2018/2022 grinds?) ----
bm_m <- bench_dt[per, on=.(Date=eval_date), nomatch=0][, .(Date, BM_Ret)]
crmark <- res$base_M4$period_returns[bm_m, on="date==Date", nomatch=0]; crmark[, crisis := benchmark_ret < -0.05]
fdt <- merge(per[,.(date=eval_date, m4_fire, fire_seq, grind_fire)], crmark[,.(date,crisis)], by="date")
ep <- list("2011Euro"=c("2011-07","2011-11"),"2018sell"=c("2018-09","2018-12"),"2022"=c("2022-01","2022-10"))
epr <- rbindlist(lapply(names(ep), function(k){ r<-ep[[k]]
  sub<-fdt[date>=as.Date(paste0(r[1],"-01")) & date<=as.Date(paste0(r[2],"-28"))]
  data.table(episode=k, months=nrow(sub), m4=sum(sub$m4_fire), ae=sum(sub$fire_seq), grind=sum(sub$grind_fire), crash=sum(sub$crisis)) }))
cat("\n=== grind coverage of slow declines (fire counts) ===\n"); print(epr)

saveRDS(list(tab=tab, w_best=w_best, thr_dur=thr_dur, is_cut=is_cut, epr=epr,
             rematch_fire=mean(fire_re), lag1=list(treat=res$D2_M4_AE_grind$abs_net_sr, lag1=r_lag1$abs_net_sr)),
        file.path(ST,"refine_result.rds"))
fwrite(tab, file.path(ST,"refine_scenario_table.csv"))
cat("\n[done] refine\n")
