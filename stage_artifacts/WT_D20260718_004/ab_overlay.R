#!/usr/bin/env Rscript
# ab_overlay.R — WT-D20260718_004 detector-swap A/B: M4 BOCPD vs Transformer regime timing overlay.
# base = M4 x AR x R05 (incumbent book_L5). treatment = TF_regime x AR x R05 (swap M4 detector, hold AR+R05).
# Plus detector-only (M4 vs TF), PIT guards (assert + lag1 + strict-PIT loose), paired NW-t, AX-001 v2 crisis.
suppressMessages({ library(data.table); library(arrow) })
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")
Sys.setenv(QVEST_WEIGHTING_AB_NORUN="1", QVEST_REGIME_AB_NORUN="1")
source("02_Infrastructure/ops/auto_weighting_ab.R")  # build_period_bench, build_overlay_exposure

PIN <- ".cache/pins/WT-D20260718_004_r1"
CAR <- file.path(PIN,"carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")
L5  <- file.path(PIN,"period_returns_layer5.csv")
TF  <- "stage_artifacts/WT_D20260718_004/tf_regime_signal.parquet"
ym  <- function(d) format(as.Date(d),"%Y-%m")

# ---- carrier ----
car <- as.data.table(read_parquet(CAR))[selected==TRUE & !is.na(ret_fwd)]
car[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
returns_dt <- car[, .(Date=eval_date, Ticker, Ret_1m=ret_fwd)]
periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date)
periods[, `:=`(ym_e=ym(eval_date))]
W_strat <- car[, .(Date=eval_date, Ticker, w=weight_strategy/sum(weight_strategy)), by=.(eval_date)][, .(Date,Ticker,w)]
# pinned benchmark for period bench
bench_dt <- build_period_bench(periods, bench_path=file.path(PIN,"benchmark.parquet"))[!is.na(BM_Ret)]

# ---- incumbent overlay components (layer5) via ym-join to eval_date ----
Lr <- fread(L5)
Lr[, ym_a := ym(anchor_date)]
comp <- Lr[, .(ym_a, m4=as.numeric(m4_weight_lag), ar=as.numeric(beta_threshold_lag), r05=as.numeric(beta_R05_V5))]
periods[comp, on=.(ym_e=ym_a), `:=`(m4=i.m4, ar=i.ar, r05=i.r05)]

# ---- transformer signal ----
tf <- as.data.table(read_parquet(TF))
tf[, decision_date := as.Date(decision_date)]
tf[, exp_matched_loose := ifelse(!is.na(fire_loose) & fire_loose==1, 0.70, 1.00)]
periods[tf, on=.(decision_date), `:=`(tf_m=i.exposure_matched, tf_2t=i.exposure_2tier,
                                      tf_loose=i.exp_matched_loose, tf_lfd=i.last_feat_date)]
# restrict to common window (months with TF signal)
per <- periods[!is.na(tf_m) & !is.na(m4)]
setorder(per, eval_date)
# lag1 stress: TF exposure shifted one period back (staler)
per[, tf_lag1 := shift(tf_m, 1L)]; per[is.na(tf_lag1), tf_lag1 := 1.0]

cat(sprintf("[ab] common months=%d  %s..%s\n", nrow(per), min(per$eval_date), max(per$eval_date)))
# restrict ALL series to common overlay window (avoid pre-2008 bare-in-both contamination)
cw <- per$eval_date
returns_dt <- returns_dt[Date %in% cw]; W_strat <- W_strat[Date %in% cw]; bench_dt <- bench_dt[Date %in% cw]

# ---- HARD PIT guard: TF last_feat_date < holding-month start (decision_date) ----
assert_overlay_pit(as.Date(per$tf_lfd), as.Date(per$decision_date), label="transformer_regime")
cat("[PIT] assert_overlay_pit PASS (all TF feature cutoffs < holding-month start)\n")

# ---- exposure schedules keyed by Date=eval_date ----
mk <- function(x) per[, .(Date=eval_date, exposure=x)]
scen <- list(
  bare        = NULL,
  base_M4xARxR05  = mk(per$m4 * per$ar * per$r05),
  treat_TFxARxR05 = mk(per$tf_m * per$ar * per$r05),
  treat_TF2t_xARxR05 = mk(per$tf_2t * per$ar * per$r05),
  m4_only     = mk(per$m4),
  tf_only     = mk(per$tf_m),
  strictPIT_loose_TFxARxR05 = mk(per$tf_loose * per$ar * per$r05),
  lag1_TFxARxR05 = mk(per$tf_lag1 * per$ar * per$r05)
)
run1 <- function(exp_dt, id) weighted_screen_bt(W_strat, returns_dt, bench_dt, cost_bps_oneway=15,
                                                run_id=id, strategy_id=id, exposure_dt=exp_dt)
res <- lapply(names(scen), function(nm) run1(scen[[nm]], nm)); names(res) <- names(scen)
tab <- rbindlist(lapply(names(res), function(nm){ r<-res[[nm]]
  data.table(scenario=nm, n=r$n_months, abs_SR=r$abs_net_sr, CAGR=r$abs_cagr, MDD=r$abs_mdd,
             calmar=r$abs_cagr/abs(r$abs_mdd), IR=r$information_ratio, PORT_t=r$portfolio_alpha_t_nw_lag3,
             avg_exp=if(is.null(scen[[nm]])) 1 else mean(scen[[nm]]$exposure,na.rm=TRUE)) }))
cat("\n=== SCENARIO TABLE (strategy weights fixed, 15bps, vs KOSPI200) ===\n"); print(tab)

# ---- paired NW-t: treat - base monthly net returns (lag 3) ----
nw_t <- function(x, lag=3){ x<-x[is.finite(x)]; n<-length(x); m<-mean(x); e<-x-m
  g0<-sum(e*e)/n; v<-g0; for(l in 1:lag){ w<-1-l/(lag+1); c<-sum(e[(l+1):n]*e[1:(n-l)])/n; v<-v+2*w*c }
  se<-sqrt(v/n); list(mean=m, t=m/se, n=n) }
pb <- merge(res$base_M4xARxR05$period_returns[,.(date,base=ret_net)],
            res$treat_TFxARxR05$period_returns[,.(date,treat=ret_net)], by="date")
d_bt <- pb$treat - pb$base
paired <- nw_t(d_bt, 3)
cat(sprintf("\n=== PAIRED NW-t (treat_TF - base_M4), lag3 ===\n  mean_diff=%.5f  t=%.3f  n=%d  (>0 & |t|>~2 => TF better)\n",
            paired$mean, paired$t, paired$n))
# also detector-only paired
pd2 <- merge(res$m4_only$period_returns[,.(date,base=ret_net)], res$tf_only$period_returns[,.(date,treat=ret_net)], by="date")
paired_det <- nw_t(pd2$treat - pd2$base, 3)
cat(sprintf("  detector-only (TF_only - M4_only): mean_diff=%.5f t=%.3f\n", paired_det$mean, paired_det$t))

# ---- strict-PIT A/B: loose (look-ahead) vs strict SR/PORT_t inflation ----
ab_sr <- overlay_lookahead_ab(res$strictPIT_loose_TFxARxR05$abs_net_sr, res$treat_TFxARxR05$abs_net_sr, "abs_SR")
ab_pt <- overlay_lookahead_ab(res$strictPIT_loose_TFxARxR05$portfolio_alpha_t_nw_lag3, res$treat_TFxARxR05$portfolio_alpha_t_nw_lag3, "PORT_t")
cat("\n=== strict-PIT A/B (loose look-ahead vs strict) ===\n  ", ab_sr$message, "\n  ", ab_pt$message, "\n")

# ---- lag1 stress ----
cat(sprintf("\n=== lag1 stress ===\n  treat SR=%.3f  lag1 SR=%.3f  (붕괴=동월누출의심; 유사/개선=timing 견고 or 신호無)\n",
            res$treat_TFxARxR05$abs_net_sr, res$lag1_TFxARxR05$abs_net_sr))

# ---- AX-001 v2 crisis-conditional (exogenous crisis = benchmark monthly ret < -5%) ----
bm_m <- bench_dt[per, on=.(Date=eval_date), nomatch=0][, .(Date, BM_Ret)]
crmark <- res$bare$period_returns[bm_m, on="date==Date", nomatch=0]
crmark[, crisis := benchmark_ret < -0.05]
base_pr <- res$base_M4xARxR05$period_returns[,.(date,base=ret_net)]
treat_pr <- res$treat_TFxARxR05$period_returns[,.(date,treat=ret_net)]
cr <- Reduce(function(a,b) merge(a,b,by="date"), list(crmark[,.(date,crisis,bare=ret_net)], base_pr, treat_pr))
crisis_tab <- cr[, .(n=.N, bare=mean(bare), base_M4=mean(base), treat_TF=mean(treat)), by=crisis]
cat("\n=== AX-001 v2 crisis-conditional (crisis = BM month < -5%) mean monthly net ===\n"); print(crisis_tab)

# ---- production parity: base_recon vs build_overlay_exposure native ----
ovn <- build_overlay_exposure()  # native, keyed by anchor_date
if(!is.null(ovn)){
  res_native <- run1(ovn$exposure[Date %in% per$eval_date], "base_native")
  cat(sprintf("\n=== production parity ===\n  base_recon SR=%.4f PORT_t=%.3f | base_native SR=%.4f PORT_t=%.3f\n",
              res$base_M4xARxR05$abs_net_sr, res$base_M4xARxR05$portfolio_alpha_t_nw_lag3,
              res_native$abs_net_sr, res_native$portfolio_alpha_t_nw_lag3))
}

fwrite(tab, "stage_artifacts/WT_D20260718_004/ab_scenario_table.csv")
saveRDS(list(tab=tab, paired=paired, paired_det=paired_det, ab_sr=ab_sr, ab_pt=ab_pt,
             crisis=crisis_tab, lag1=list(treat=res$treat_TFxARxR05$abs_net_sr, lag1=res$lag1_TFxARxR05$abs_net_sr),
             n_months=nrow(per), window=c(as.character(min(per$eval_date)),as.character(max(per$eval_date)))),
        "stage_artifacts/WT_D20260718_004/ab_result.rds")
cat("\n[done] saved ab_scenario_table.csv + ab_result.rds\n")
