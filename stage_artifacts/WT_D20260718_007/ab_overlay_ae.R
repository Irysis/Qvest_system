#!/usr/bin/env Rscript
# ab_overlay_ae.R — WT-D20260718_007 detector-swap A/B: M4 BOCPD vs UNSUPERVISED autoencoder regime timing overlay.
# base = M4 x AR x R05 (incumbent book_L5). treat = AE_seq / AE_pt x AR x R05 (swap ONLY the detector; hold AR+R05).
# + ENSEMBLE (M4 (+) AE_seq union, most-defensive). + detector-only. + PIT guards (assert/lag1/strict-loose).
# + paired NW-t. + AX-001 v2 crisis. + crisis-firing correlation vs M4 (the WT-004 root-cause test).
suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1)
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")
Sys.setenv(QVEST_WEIGHTING_AB_NORUN="1", QVEST_REGIME_AB_NORUN="1")
source("02_Infrastructure/ops/auto_weighting_ab.R")  # build_period_bench, build_overlay_exposure

PIN <- ".cache/pins/WT-D20260718_007_r1"
CAR <- file.path(PIN,"carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")
L5  <- file.path(PIN,"period_returns_layer5.csv")
AE  <- "stage_artifacts/WT_D20260718_007/ae_regime_signal.parquet"
ym  <- function(d) format(as.Date(d),"%Y-%m")

# ---- carrier (weights FIXED) ----
car <- as.data.table(read_parquet(CAR))[selected==TRUE & !is.na(ret_fwd)]
car[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
returns_dt <- car[, .(Date=eval_date, Ticker, Ret_1m=ret_fwd)]
periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date)
periods[, `:=`(ym_e=ym(eval_date))]
W_strat <- car[, .(Date=eval_date, Ticker, w=weight_strategy/sum(weight_strategy)), by=.(eval_date)][, .(Date,Ticker,w)]
bench_dt <- build_period_bench(periods, bench_path=file.path(PIN,"benchmark.parquet"))[!is.na(BM_Ret)]

# ---- incumbent overlay components (layer5) via ym-join to eval_date ----
Lr <- fread(L5); Lr[, ym_a := ym(anchor_date)]
comp <- Lr[, .(ym_a, m4=as.numeric(m4_weight_lag), ar=as.numeric(beta_threshold_lag), r05=as.numeric(beta_R05_V5))]
periods[comp, on=.(ym_e=ym_a), `:=`(m4=i.m4, ar=i.ar, r05=i.r05)]

# ---- autoencoder signal ----
ae <- as.data.table(read_parquet(AE))
ae[, decision_date := as.Date(decision_date)]
ae[, `:=`(exp_seq=fifelse(fire_seq==1,0.70,1.00), exp_pt=fifelse(fire_pt==1,0.70,1.00),
          exp_seq_loose=fifelse(fire_seq_loose==1,0.70,1.00))]
periods[ae, on=.(decision_date), `:=`(ae_seq=i.exp_seq, ae_pt=i.exp_pt, ae_seq_loose=i.exp_seq_loose,
                                      fire_seq=i.fire_seq, fire_pt=i.fire_pt, ae_lfd=i.last_feat_date)]
per <- periods[!is.na(ae_seq) & !is.na(m4)]; setorder(per, eval_date)
per[, m4_fire := as.integer(m4 < 0.999)]
# ENSEMBLE: M4 (+) AE_seq union — most-defensive of the two detectors, hold AR+R05
per[, ens_exp := pmin(m4, ae_seq)]
# lag1 stress: AE_seq exposure shifted one period back (staler)
per[, ae_lag1 := shift(ae_seq, 1L)]; per[is.na(ae_lag1), ae_lag1 := 1.0]

cat(sprintf("[ab] common months=%d  %s..%s\n", nrow(per), min(per$eval_date), max(per$eval_date)))
cat(sprintf("[fire rates] M4=%.3f  AE_seq=%.3f  AE_pt=%.3f  (target match ~0.126)\n",
            mean(per$m4_fire), mean(per$fire_seq), mean(per$fire_pt)))
cw <- per$eval_date
returns_dt <- returns_dt[Date %in% cw]; W_strat <- W_strat[Date %in% cw]; bench_dt <- bench_dt[Date %in% cw]

# ---- HARD PIT guard: AE last_feat_date < holding-month start (decision_date) ----
assert_overlay_pit(as.Date(per$ae_lfd), as.Date(per$decision_date), label="autoencoder_regime")
cat("[PIT] assert_overlay_pit PASS (all AE feature cutoffs < holding-month start)\n")

# ---- exposure schedules keyed by Date=eval_date ----
mk <- function(x) per[, .(Date=eval_date, exposure=x)]
scen <- list(
  bare              = NULL,
  base_M4xARxR05    = mk(per$m4     * per$ar * per$r05),
  treat_AEseqxARxR05= mk(per$ae_seq * per$ar * per$r05),
  treat_AEptxARxR05 = mk(per$ae_pt  * per$ar * per$r05),
  treat_ENSxARxR05  = mk(per$ens_exp* per$ar * per$r05),
  m4_only           = mk(per$m4),
  aeseq_only        = mk(per$ae_seq),
  aept_only         = mk(per$ae_pt),
  strictPIT_loose_AEseqxARxR05 = mk(per$ae_seq_loose * per$ar * per$r05),
  lag1_AEseqxARxR05 = mk(per$ae_lag1 * per$ar * per$r05)
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
paired_of <- function(a,b){ pb<-merge(res[[a]]$period_returns[,.(date,base=ret_net)],
                                      res[[b]]$period_returns[,.(date,treat=ret_net)], by="date")
  nw_t(pb$treat - pb$base, 3) }
p_seq <- paired_of("base_M4xARxR05","treat_AEseqxARxR05")
p_pt  <- paired_of("base_M4xARxR05","treat_AEptxARxR05")
p_ens <- paired_of("base_M4xARxR05","treat_ENSxARxR05")
p_det <- paired_of("m4_only","aeseq_only")
cat("\n=== PAIRED NW-t (treat - base_M4), lag3  (>0 & |t|>~2 => AE better) ===\n")
cat(sprintf("  AE_seq - M4 : mean=%.5f t=%.3f n=%d\n", p_seq$mean, p_seq$t, p_seq$n))
cat(sprintf("  AE_pt  - M4 : mean=%.5f t=%.3f\n", p_pt$mean, p_pt$t))
cat(sprintf("  ENS    - M4 : mean=%.5f t=%.3f\n", p_ens$mean, p_ens$t))
cat(sprintf("  detector-only AE_seq - M4 : mean=%.5f t=%.3f\n", p_det$mean, p_det$t))

# ---- strict-PIT A/B: loose (look-ahead) vs strict SR/PORT_t inflation ----
ab_sr <- overlay_lookahead_ab(res$strictPIT_loose_AEseqxARxR05$abs_net_sr, res$treat_AEseqxARxR05$abs_net_sr, "abs_SR")
ab_pt <- overlay_lookahead_ab(res$strictPIT_loose_AEseqxARxR05$portfolio_alpha_t_nw_lag3, res$treat_AEseqxARxR05$portfolio_alpha_t_nw_lag3, "PORT_t")
cat("\n=== strict-PIT A/B (loose look-ahead vs strict) ===\n  ", ab_sr$message, "\n  ", ab_pt$message, "\n")

# ---- lag1 stress ----
cat(sprintf("\n=== lag1 stress (AE_seq) ===\n  treat SR=%.3f  lag1 SR=%.3f  (붕괴=동월누출의심; 유사/개선=timing 견고 or 신호無)\n",
            res$treat_AEseqxARxR05$abs_net_sr, res$lag1_AEseqxARxR05$abs_net_sr))

# ---- AX-001 v2 crisis-conditional + CRISIS-FIRING CORRELATION (WT-004 root-cause test) ----
bm_m <- bench_dt[per, on=.(Date=eval_date), nomatch=0][, .(Date, BM_Ret)]
crmark <- res$bare$period_returns[bm_m, on="date==Date", nomatch=0]
crmark[, crisis := benchmark_ret < -0.05]
base_pr <- res$base_M4xARxR05$period_returns[,.(date,base=ret_net)]
tseq_pr <- res$treat_AEseqxARxR05$period_returns[,.(date,treat=ret_net)]
tens_pr <- res$treat_ENSxARxR05$period_returns[,.(date,ens=ret_net)]
cr <- Reduce(function(a,b) merge(a,b,by="date"),
             list(crmark[,.(date,crisis,bare=ret_net)], base_pr, tseq_pr, tens_pr))
crisis_tab <- cr[, .(n=.N, bare=mean(bare), base_M4=mean(base), treat_AEseq=mean(treat), treat_ENS=mean(ens)), by=crisis]
cat("\n=== AX-001 v2 crisis-conditional (crisis = BM month < -5%) mean monthly net ===\n"); print(crisis_tab)

# crisis-firing correlation: does each detector fire (de-risk) WHEN crises happen?
fdt <- merge(per[,.(date=eval_date, m4_fire, fire_seq, fire_pt)], crmark[,.(date,crisis)], by="date")
pbcor <- function(fire, crisis){ f<-as.integer(fire); c<-as.integer(crisis)
  if(sd(f)==0||sd(c)==0) return(NA_real_); suppressWarnings(cor(f,c)) }
cat("\n=== CRISIS-FIRING CORRELATION (fire flag vs BM-crash month) — WT-004 root-cause test ===\n")
cat(sprintf("  M4     : corr=%.3f  fire_in_crisis=%d/%d\n", pbcor(fdt$m4_fire,fdt$crisis),  sum(fdt$m4_fire & fdt$crisis),  sum(fdt$crisis)))
cat(sprintf("  AE_seq : corr=%.3f  fire_in_crisis=%d/%d\n", pbcor(fdt$fire_seq,fdt$crisis), sum(fdt$fire_seq & fdt$crisis), sum(fdt$crisis)))
cat(sprintf("  AE_pt  : corr=%.3f  fire_in_crisis=%d/%d\n", pbcor(fdt$fire_pt,fdt$crisis),  sum(fdt$fire_pt & fdt$crisis),  sum(fdt$crisis)))
# named-episode hit table
ep <- list("2008GFC"=c("2008-08","2009-04"),"2011Euro"=c("2011-07","2011-11"),
           "2018sell"=c("2018-09","2018-12"),"COVID"=c("2020-02","2020-05"),"2022"=c("2022-01","2022-10"))
epr <- rbindlist(lapply(names(ep), function(k){ r<-ep[[k]]
  sub<-fdt[date>=as.Date(paste0(r[1],"-01")) & date<=as.Date(paste0(r[2],"-28"))]
  data.table(episode=k, months=nrow(sub), m4_fire=sum(sub$m4_fire), aeseq_fire=sum(sub$fire_seq),
             aept_fire=sum(sub$fire_pt), any_crash=sum(sub$crisis)) }))
cat("\n=== named crisis episode firing (fire counts within window) ===\n"); print(epr)

# ---- production parity: base_recon vs build_overlay_exposure native ----
ovn <- build_overlay_exposure()
if(!is.null(ovn)){
  res_native <- run1(ovn$exposure[Date %in% per$eval_date], "base_native")
  cat(sprintf("\n=== production parity ===\n  base_recon SR=%.4f PORT_t=%.3f | base_native SR=%.4f PORT_t=%.3f\n",
              res$base_M4xARxR05$abs_net_sr, res$base_M4xARxR05$portfolio_alpha_t_nw_lag3,
              res_native$abs_net_sr, res_native$portfolio_alpha_t_nw_lag3))
}

fwrite(tab, "stage_artifacts/WT_D20260718_007/ab_scenario_table.csv")
saveRDS(list(tab=tab, paired=list(seq=p_seq,pt=p_pt,ens=p_ens,det=p_det),
             ab_sr=ab_sr, ab_pt=ab_pt, crisis=crisis_tab, epr=epr,
             crisis_corr=list(m4=pbcor(fdt$m4_fire,fdt$crisis), aeseq=pbcor(fdt$fire_seq,fdt$crisis), aept=pbcor(fdt$fire_pt,fdt$crisis)),
             lag1=list(treat=res$treat_AEseqxARxR05$abs_net_sr, lag1=res$lag1_AEseqxARxR05$abs_net_sr),
             fire_rates=list(m4=mean(per$m4_fire), aeseq=mean(per$fire_seq), aept=mean(per$fire_pt)),
             n_months=nrow(per), window=c(as.character(min(per$eval_date)),as.character(max(per$eval_date)))),
        "stage_artifacts/WT_D20260718_007/ab_result.rds")
cat("\n[done] saved ab_scenario_table.csv + ab_result.rds\n")
