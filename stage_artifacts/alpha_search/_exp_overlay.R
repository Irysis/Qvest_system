## ============================================================
## EXPERIMENT 2: STR_1715 core + OVERLAY (exposure scaling)
## Optimizer-research. STR_1715 frozen. Measurement-only (no 05_Production write).
## Layer = exposure_{t-1} applied to FROZEN core net/gross monthly series.
##   - Vol-targeting (Moreira-Muir 2017): e_t = min(1, sig_target / sigma_hat_{t-1})
##   - Regime overlay (R05 reconstruction): de-risk in CRISIS/CAUTION (t-1 lag)
##   - Combo = product (double de-risk; clipped to [0,1])
## All metrics via PerformanceAnalytics (no self-synthesis of cumulative).
## PIT: every overlay signal uses ONLY info up to t-1 (C5/C9).
## ============================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(PerformanceAnalytics); library(xts)
})
options(warn=1)
BASE <- "G:/Quant_Module_Moltbot"
PROD <- file.path(BASE,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe")
OUT  <- file.path(BASE,"stage_artifacts/alpha_search")

BPS <- 15  # one-way bps

## ---- load FROZEN baseline core series (experiment 1 output) ----
b <- readRDS(file.path(OUT,"_exp_baseline.rds"))
core <- copy(b$dt)              # period_end, port_net, port_gross, bm_ret, turnover, n
setorder(core, period_end)
NP <- nrow(core)
cat(sprintf("core periods: %d  (%s ~ %s)\n", NP,
    as.character(min(core$period_end)), as.character(max(core$period_end))))

## ---- load regime_state (per sig date) for R05 reconstruction ----
r05 <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_r05_panel.parquet")))
reg <- unique(r05[,.(sig_date=Date, regime_state, w_new_regime)], by="sig_date")
setorder(reg, sig_date)
## map each core period_end to the regime_state KNOWN at the signal date that
## generated that period's holdings. The core dt period_end[i] corresponds to
## the holding period AFTER sig_dates[i]. r05 sig_dates align 1:1 with core rows
## (both 267/268 from same engine). We attach regime by position (PIT: regime
## known at sig date <= period start).
cat(sprintf("regime dates: %d  states: %s\n", nrow(reg),
    paste(names(table(reg$regime_state)), table(reg$regime_state), collapse=" ")))

## sig_dates used in baseline engine = first 267 of 268 (loop i in 1..len-1)
sig_all <- reg$sig_date
## core has 267 rows = periods after sig_dates[1..267]. regime for period i = state at sig_dates[i]
if(nrow(reg) >= NP){
  core[, sig_date := sig_all[seq_len(NP)]]
  core[, regime_state := reg$regime_state[seq_len(NP)]]
} else stop("regime panel shorter than core")

## ===== metrics helper (PerformanceAnalytics only) =====
metrics_of <- function(dt_ret, dt_bm, dt_end, dt_to, label){
  if(length(dt_ret)<12) return(NULL)
  rx <- xts(dt_ret, order.by=as.Date(dt_end))
  bx <- xts(dt_bm,  order.by=as.Date(dt_end))
  ax <- rx - bx
  sr_tot <- as.numeric(SharpeRatio.annualized(rx, Rf=0, scale=12))
  sr_act <- as.numeric(SharpeRatio.annualized(ax, Rf=0, scale=12))
  cagr   <- as.numeric(Return.annualized(rx, scale=12))
  mdd    <- as.numeric(maxDrawdown(rx))
  calmar <- if(mdd>0) cagr/mdd else NA_real_
  list(label=label, n=length(dt_ret), sr_total=sr_tot, sr_active=sr_act,
       cagr=cagr, mdd=mdd, calmar=calmar, ann_to=mean(dt_to,na.rm=TRUE)*12)
}

## Build a full report on an overlaid series.
## Input: data.table with period_end, ret_net, bm_ret, to_eff
report_overlay <- function(dt, name){
  setorder(dt, period_end)
  full <- metrics_of(dt$ret_net, dt$bm_ret, dt$period_end, dt$to_eff, paste0(name,"_FULL"))
  oosd <- dt[period_end>=as.Date("2010-01-01") & period_end<=as.Date("2023-12-31")]
  oos  <- metrics_of(oosd$ret_net, oosd$bm_ret, oosd$period_end, oosd$to_eff, paste0(name,"_OOS_2010_2023"))
  ## early/late for oos_retention (TOTAL basis)
  mid <- dt$period_end[ceiling(nrow(dt)/2)]
  e <- dt[period_end<=mid]; l <- dt[period_end>mid]
  me <- metrics_of(e$ret_net, e$bm_ret, e$period_end, e$to_eff, paste0(name,"_EARLY"))
  ml <- metrics_of(l$ret_net, l$bm_ret, l$period_end, l$to_eff, paste0(name,"_LATE"))
  ret_tot <- if(!is.null(me)&&!is.null(ml)&&me$sr_total!=0) ml$sr_total/me$sr_total else NA
  ret_act <- if(!is.null(me)&&!is.null(ml)&&me$sr_active!=0) ml$sr_active/me$sr_active else NA
  ## 3 subperiods
  sp <- list(
    P1_2005_2014 = dt[period_end>=as.Date("2005-01-01") & period_end<=as.Date("2014-12-31")],
    P2_2015_2019 = dt[period_end>=as.Date("2015-01-01") & period_end<=as.Date("2019-12-31")],
    P3_2020_2026 = dt[period_end>=as.Date("2020-01-01")]
  )
  spm <- lapply(names(sp), function(nm){
    d<-sp[[nm]]; metrics_of(d$ret_net,d$bm_ret,d$period_end,d$to_eff,paste0(name,"_",nm))
  }); names(spm) <- names(sp)
  list(full=full, oos=oos, early=me, late=ml,
       oos_retention_total=ret_tot, oos_retention_active=ret_act, subperiods=spm)
}

## ---- apply an exposure vector e (length NP, exposure for period i, ALREADY t-1 safe) ----
## core net already had base cost deducted. We re-derive net from gross so overlay
## cost accounting is explicit and base cost scales with exposure.
apply_overlay <- function(e_vec, name){
  stopifnot(length(e_vec)==NP)
  e_vec[!is.finite(e_vec)] <- 1
  e_vec <- pmin(pmax(e_vec,0),1)
  dt <- copy(core)
  dt[, e := e_vec]
  ## effective gross = e * core_gross (cash leg returns 0)
  dt[, gross_eff := e * port_gross]
  ## base turnover cost scales with invested fraction e
  ## overlay turnover = |e_t - e_{t-1}| (cash<->equity shift), e_0 assume 1 (start invested)
  e_prev <- c(1, head(e_vec, -1))
  dt[, d_exposure := abs(e - e_prev)]
  ## total one-way turnover = e_prev*base_turnover (rebal of invested sleeve) + d_exposure
  dt[, to_eff := e_prev*turnover + d_exposure]
  dt[, cost_eff := (BPS/1e4) * to_eff * 2]   # round-trip x2, NOT x12
  dt[, ret_net := gross_eff - cost_eff]
  report_overlay(dt, name)
}

pr <- function(m){ if(is.null(m)){cat("  (insufficient)\n");return(invisible())}
  cat(sprintf("  %-30s n=%3d | SR_tot=%.4f SR_act=%.4f CAGR=%.4f MDD=%.4f Calmar=%.3f TO=%.2f\n",
      m$label,m$n,m$sr_total,m$sr_active,m$cagr,m$mdd,ifelse(is.na(m$calmar),-99,m$calmar),m$ann_to)) }
prrep <- function(rep){
  pr(rep$full); pr(rep$oos)
  for(nm in names(rep$subperiods)) pr(rep$subperiods[[nm]])
  cat(sprintf("  oos_retention(total)=%.4f  (active)=%.4f\n",
      rep$oos_retention_total, rep$oos_retention_active))
}

results <- list()

## ===== CONFIG 1: BASELINE (exposure = 1) =====
cat("\n===== CONFIG 1: BASELINE (overlay=1) =====\n")
rep_base <- apply_overlay(rep(1, NP), "baseline")
prrep(rep_base); results[["baseline"]] <- rep_base

## ===== CONFIG 2: VOL-TARGETING =====
## sigma_hat_{t-1} = annualized trailing realized vol of core NET returns up to t-1
## (uses only past core returns -> PIT safe). exposure_t = min(1, sig_target/sigma_hat)
core_net <- core$port_net
roll_vol_ann <- function(x, L){
  v <- rep(NA_real_, length(x))
  for(i in seq_along(x)){
    lo <- i-L; if(lo<1) next                 # need L past obs strictly before i
    win <- x[(lo):(i-1)]                      # t-1 .. t-L  (STRICTLY past)
    if(length(win)>=max(3,floor(L/2))) v[i] <- sd(win, na.rm=TRUE)*sqrt(12)
  }
  v
}
sig_targets <- c(0.12, 0.15, 0.18)
lookbacks   <- c(6L, 12L)
n_trials_voltarget <- length(sig_targets)*length(lookbacks)
for(L in lookbacks){
  sig_hat <- roll_vol_ann(core_net, L)
  for(st in sig_targets){
    e <- pmin(1, st/sig_hat)
    e[!is.finite(e)] <- 1   # warmup periods before lookback fills -> stay invested
    tag <- sprintf("voltgt_s%02d_L%02d", round(st*100), L)
    cat(sprintf("\n===== CONFIG 2: %s (sig_target=%.0f%%, lookback=%dm) =====\n", tag, st*100, L))
    rep <- apply_overlay(e, tag)
    prrep(rep)
    results[[tag]] <- rep
  }
}

## ===== CONFIG 3: REGIME OVERLAY (R05 reconstruction, t-1 lag) =====
## defensive regimes (CRISIS, CAUTION) -> de-risk to cash by fraction (1-derisk_keep)
## regime_state[i] is known at sig_date[i] (start of period i) => already PIT for period i.
## but to be strictly t-1 we LAG by one period (use regime decided at PREVIOUS rebal?
## regime_state[i] IS the state at the sig date that PRECEDES holding period i, so it is
## the information set at period-i start. That is the production convention (overlay set at
## rebal). We keep regime_state[i] (decision at period start = PIT-valid, like overlay applied
## at the same rebal that sets weights). No future info.
derisk_keeps <- c(0.5, 0.3, 0.0)  # equity fraction kept in CRISIS/CAUTION
for(dk in derisk_keeps){
  e <- ifelse(core$regime_state %in% c("CRISIS","CAUTION"), dk, 1.0)
  tag <- sprintf("regime_keep%02d", round(dk*100))
  cat(sprintf("\n===== CONFIG 3: %s (CRISIS/CAUTION keep=%.0f%% equity) =====\n", tag, dk*100))
  rep <- apply_overlay(e, tag)
  prrep(rep)
  results[[tag]] <- rep
}

## ===== CONFIG 4: COMBO (best vol-target x regime keep=0.5) =====
## pick best-OOS vol-target among configs passing direction, combine with regime keep=0.5
## (choose representative: s15 L12 = lowest-overfit single param)
sig_hat12 <- roll_vol_ann(core_net, 12L)
e_vt <- pmin(1, 0.15/sig_hat12); e_vt[!is.finite(e_vt)] <- 1
e_rg <- ifelse(core$regime_state %in% c("CRISIS","CAUTION"), 0.5, 1.0)
e_combo <- pmin(1, e_vt * e_rg)   # product
cat("\n===== CONFIG 4: COMBO voltgt_s15_L12 x regime_keep50 =====\n")
rep_combo <- apply_overlay(e_combo, "combo_vt15L12_rg50")
prrep(rep_combo); results[["combo_vt15L12_rg50"]] <- rep_combo

## save
saveRDS(list(results=results, n_trials_voltarget=n_trials_voltarget,
             baseline_full_sr_total=rep_base$full$sr_total,
             baseline_oos_sr_total=rep_base$oos$sr_total),
        file.path(OUT,"_exp_overlay.rds"))
cat(sprintf("\n[DONE] n_trials(voltgt)=%d + regime 3 + combo 1. saved _exp_overlay.rds\n", n_trials_voltarget))
