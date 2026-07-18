#!/usr/bin/env Rscript
# D3_forge_graduation.R — WT-D20260718_007: forge-authoritative calmar-graduation of the D3 intersection overlay.
# D3 book (carrier STR_1715 x (M4∩AE agreement) x AR x R05) vs incumbent M4 book (carrier x M4 x AR x R05).
# build_bt_result 10-component (PerformanceAnalytics, no self-synthesis) + essence_score(oos v2, DSR) + holdout falsification.
# RETURN is neutral (paired <+2 fixed) — this measures ONLY the CALMAR/MDD/tail graduation axis. Capital = 도훈 manual.
suppressMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics); library(jsonlite) })
setDTthreads(1)
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/essence_score.R")
source("02_Infrastructure/contracts/holdout_falsification.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")
Sys.setenv(QVEST_WEIGHTING_AB_NORUN="1", QVEST_REGIME_AB_NORUN="1")
source("02_Infrastructure/ops/auto_weighting_ab.R")
PIN <- ".cache/pins/WT-D20260718_007_r1"; ym <- function(d) format(as.Date(d),"%Y-%m"); ST <- "stage_artifacts/WT_D20260718_007"

# ---- carrier + M4 + AE + intersection (identical construction to refine.R) ----
car <- as.data.table(read_parquet(file.path(PIN,"carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")))[selected==TRUE & !is.na(ret_fwd)]
car[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
returns_dt <- car[, .(Date=eval_date, Ticker, Ret_1m=ret_fwd)]
periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date); periods[, ym_e:=ym(eval_date)]
W_strat <- car[, .(Date=eval_date, Ticker, w=weight_strategy/sum(weight_strategy)), by=.(eval_date)][, .(Date,Ticker,w)]
bench_dt <- build_period_bench(periods, bench_path=file.path(PIN,"benchmark.parquet"))[!is.na(BM_Ret)]
Lr <- fread(file.path(PIN,"period_returns_layer5.csv")); Lr[, ym_a:=ym(anchor_date)]
comp <- Lr[, .(ym_a, m4=as.numeric(m4_weight_lag), ar=as.numeric(beta_threshold_lag), r05=as.numeric(beta_R05_V5))]
periods[comp, on=.(ym_e=ym_a), `:=`(m4=i.m4, ar=i.ar, r05=i.r05)]
ae <- as.data.table(read_parquet(file.path(ST,"ae_regime_signal.parquet"))); ae[, decision_date:=as.Date(decision_date)]
periods[ae, on=.(decision_date), `:=`(fire_seq=i.fire_seq, ae_lfd=i.last_feat_date)]
per <- periods[!is.na(fire_seq) & !is.na(m4)]; setorder(per, eval_date)
per[, m4_fire := as.integer(m4 < 0.999)]
per[, ens_int_exp := fifelse(m4_fire==1 & fire_seq==1, 0.70, 1.00)]   # D3: de-risk iff BOTH fire
cw <- per$eval_date
returns_dt <- returns_dt[Date %in% cw]; W_strat <- W_strat[Date %in% cw]; bench_dt <- bench_dt[Date %in% cw]
# PIT: AE cutoff < holding-month start (M4/AR/R05 are incumbent production, already PIT)
assert_overlay_pit(as.Date(per$ae_lfd), as.Date(per$decision_date), label="D3_intersection_AE")
cat("[PIT] D3 assert_overlay_pit PASS\n")

run1 <- function(exp) weighted_screen_bt(W_strat, returns_dt, bench_dt, cost_bps_oneway=15, run_id="d3", strategy_id="d3", exposure_dt=per[,.(Date=eval_date, exposure=exp)])
res_base <- run1(per$m4          * per$ar * per$r05)   # incumbent M4 overlay (production parity verified r1)
res_d3   <- run1(per$ens_int_exp * per$ar * per$r05)   # D3 intersection overlay

# ---- bridge monthly net returns -> sim_result -> build_bt_result (PerformanceAnalytics, monthly, ann=12) ----
to_bt <- function(pr, sid){
  pr <- pr[order(date)]
  sx <- xts(pr$ret_net, order.by=pr$date); bx <- xts(pr$benchmark_ret, order.by=pr$date)
  nav <- data.table(Date=pr$date, NAV=as.numeric(cumprod(1+pr$ret_net)))
  nav[, NAV_gross := NAV]   # net==gross bridge (cost already embedded in ret_net; graduation gates are net)
  sim <- list(DAILY_NAV_DT=nav, strategy_xts=sx, bm_xts=bx)
  spec <- list(strategy_id=sid, name=sid, universe="KOSPI200_KOSDAQ150", rebalance="monthly", benchmark="KOSPI200")
  bt <- build_bt_result(sim, spec, run_id=sid, strategy_id=sid, frequency="monthly", annualization_factor=12,
                        transaction_cost_bps=15, slippage_bps=0, benchmark_id="KOSPI200", created_by_agent="Alpha")
  bt
}
bt_base <- to_bt(res_base$period_returns, "M4_incumbent_overlay")
bt_d3   <- to_bt(res_d3$period_returns,   "D3_intersection_overlay")

getm  <- function(bt,nm){ M<-as.data.table(bt$metrics); v<-M[metric_name==nm, metric_value]; if(length(v)) as.numeric(v[1]) else NA_real_ }
getbc <- function(bt,nm){ B<-as.data.table(bt$benchmark_compare); v<-B[metric_name==nm, active_value]; if(length(v)) as.numeric(v[1]) else NA_real_ }
row <- function(bt,lbl) data.table(book=lbl, Sharpe=getm(bt,"Sharpe"), CAGR=getm(bt,"CAGR"), MDD=getm(bt,"MDD"),
                                   Calmar=getm(bt,"Calmar"), PORT_t=getbc(bt,"Portfolio_Alpha_t_NW_lag3"), IR=getbc(bt,"Information_Ratio"))
mtab <- rbind(row(bt_base,"M4_incumbent"), row(bt_d3,"D3_intersection"))
cat("\n=== forge-authoritative build_bt_result metrics (monthly, ann=12, 15bps) ===\n"); print(mtab)

# ---- essence_score graduation gates (oos v2, DSR). n_trials honest: r1(3 AE arms)+r2(D1a/D1b/D2x3/D3x2)=9 constructions ----
N_TRIALS <- 9L
es_d3   <- essence_score(bt_d3,   n_trials_cumulative=N_TRIALS, selection_type="chain", oos_stat_version="v2", calmar_min=0.64)
es_base <- essence_score(bt_base, n_trials_cumulative=N_TRIALS, selection_type="chain", oos_stat_version="v2", calmar_min=0.64)
.nz2 <- function(x){ v<-suppressWarnings(as.numeric(x)); if(length(v)) v[1] else NA_real_ }
# essence_score returns a data.table/list — pull fields robustly
pull <- function(es, nm){ if(is.data.frame(es) && nm %in% names(es)) return(.nz2(es[[nm]][1]))
  if(is.list(es) && nm %in% names(es)) return(.nz2(es[[nm]])); NA_real_ }
cat("\n=== essence_score fields (D3) ===\n"); print(if(is.data.frame(es_d3)) as.data.table(es_d3) else es_d3)

# ---- holdout falsification: seal interval on IS (first 60%), judge on OOS ----
prd3 <- res_d3$period_returns[order(date)]
N <- nrow(prd3); is_n <- floor(0.60*N)
is_ret <- prd3$ret_net[1:is_n]; oos_ret <- prd3$ret_net[(is_n+1):N]
hpath <- file.path("06_Registry/live_track/WT-D20260718_007_D3", "holdout_interval.json")
iv <- build_holdout_interval(is_ret, holdout_months=length(oos_ret), block=12L, B=4000L, seed=20260718, strategy_id="D3_intersection")
tryCatch(save_holdout_interval(iv, hpath, overwrite=FALSE), error=function(e) cat("[holdout] interval exists (immutable):", conditionMessage(e),"\n"))
hj <- judge_holdout(iv, oos_ret, window_label="D3_OOS_2019plus")
cat(sprintf("\n=== holdout falsification (IS-sealed interval, OOS judged) ===\n  IS-sealed SR interval [q05=%.3f, q95=%.3f] boot_median=%.3f | OOS realized SR=%.3f -> %s\n",
            iv$q05, iv$q95, iv$boot_median, hj$realized_sr, hj$verdict))

# ---- graduation verdict (CALMAR axis; return neutral by prior) ----
cal_d3 <- getm(bt_d3,"Calmar"); cal_base <- getm(bt_base,"Calmar")
oos_d3 <- pull(es_d3,"oos_retention"); dsr_d3 <- pull(es_d3,"dsr")
gate <- list(
  calmar_hard_0.64 = list(value=cal_d3, pass=is.finite(cal_d3) && cal_d3>=0.64),
  calmar_vs_incumbent = list(d3=cal_d3, m4=cal_base, improved=is.finite(cal_d3)&&is.finite(cal_base)&&cal_d3>cal_base),
  oos_retention_v2_0.7 = list(value=oos_d3, pass=is.finite(oos_d3) && oos_d3>=0.7, band_lo=0.5),
  dsr = list(value=dsr_d3, n_trials=N_TRIALS, selection_type="chain", note="chain -> DSR advisory (measurement-graduation §3); value recorded"),
  holdout = list(verdict=hj$verdict, realized_sr=hj$realized_sr, q05=iv$q05, q95=iv$q95),
  return_axis = list(paired_nw_t=0.49, note="return-graduation NOT claimed (paired <+2 fixed r1/r2); this measures CALMAR axis only")
)
out <- list(task_id="WT-D20260718_007", measurement="D3_intersection_overlay_calmar_graduation", as_of=as.character(Sys.Date()),
            pin_tag="WT-D20260718_007_r1", metric_type="backtested (build_bt_result 10-component, PerformanceAnalytics)",
            incumbent_base="M4 overlay (carrier x m4 x AR x R05) = production STR_1715_on_M4_R05; r1 production_parity EXACT SR 1.8088",
            vintage_caveat="measured vs production-code-derived incumbent overlay (T-1); NOT a derived same-month stored panel. base parity verified r1.",
            metrics=as.list(mtab), gates=gate, n_trials_cumulative=N_TRIALS, single_seed=20260718)
write_json(out, file.path("qepm/mailbox/worktask/WT-D20260718_007/D3_forge_graduation.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
write_json(out, file.path(ST,"D3_forge_graduation.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
saveRDS(list(mtab=mtab, es_d3=es_d3, es_base=es_base, holdout=hj, iv=iv, gate=gate), file.path(ST,"D3_forge_result.rds"))
cat("\n=== GRADUATION GATES (D3 intersection, CALMAR axis) ===\n")
cat(sprintf("  calmar>=0.64 HARD      : %.3f -> %s\n", cal_d3, ifelse(gate$calmar_hard_0.64$pass,"PASS","FAIL")))
cat(sprintf("  calmar > incumbent     : D3 %.3f vs M4 %.3f -> %s\n", cal_d3, cal_base, ifelse(gate$calmar_vs_incumbent$improved,"IMPROVED","no")))
cat(sprintf("  oos_retention v2>=0.7  : %.3f -> %s\n", oos_d3, ifelse(gate$oos_retention_v2_0.7$pass,"PASS","FAIL/BAND")))
cat(sprintf("  DSR (advisory, chain)  : %.3f (n_trials=%d)\n", dsr_d3, N_TRIALS))
cat(sprintf("  holdout                : %s (OOS SR %.3f vs IS [q05 %.3f, q95 %.3f])\n", hj$verdict, hj$realized_sr, iv$q05, iv$q95))
cat("\n[done] D3_forge_graduation\n")
