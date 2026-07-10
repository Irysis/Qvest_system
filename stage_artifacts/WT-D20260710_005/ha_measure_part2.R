# H-a Part 2: rank-IC advisory + standalone canonical dual-basis + book-marginal exclusion.
# Pre-registered primary: restate_rate_24 (24M restatement rate). Exclusion = top-quintile restate (IS threshold).
# Discipline: IS=2005-2018 selection, OOS=2019-2026 once. placebo(random-exclusion null). lag1 stress. n_trials/null max-t.
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT-D20260710_005")
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))
set.seed(20260710)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a

pm <- readRDS(file.path(OUT,"ha_panel_merged.rds")); P <- pm$P; bm <- pm$bm
P <- P[is.finite(score_eff)&is.finite(Ret_1m)]
setorder(P, ym, Ticker)
IS_MAX <- 201812L  # IS through 2018-12

nwt <- function(x){x<-x[is.finite(x)];n<-length(x);if(n<12)return(NA_real_);m<-mean(x)
  ac<-tryCatch(acf(x,lag.max=3,plot=FALSE,demean=TRUE)$acf[-1],error=function(e)rep(0,3))
  v<-var(x);s<-v*(1+2*sum((1-(1:3)/n)*ac));if(!is.finite(s)||s<=0)return(NA_real_);m/sqrt(s/n)}
ic_stat <- function(dt, sigcol, rmin=201101L, rmax=209912L){
  d <- dt[has_hist==1 & ym>=rmin & ym<=rmax]
  ics <- d[, .(ic=if(.N>=15) suppressWarnings(cor(get(sigcol),Ret_1m,method="spearman")) else NA_real_), by=ym][is.finite(ic)]
  n<-nrow(ics); if(n<12) return(list(n=n,mean_ic=NA,t=NA,icir=NA))
  mu<-mean(ics$ic); s<-sd(ics$ic); list(n=n,mean_ic=mu,t=mu/(s/sqrt(n)),icir=mu/s)
}

# ---- A. rank-IC advisory across quality-signal variants (higher quality = -restate) ----
P[, q_rate24 := -rate_24][, q_rate12 := -rate_12][, q_cnt24 := -as.numeric(cnt_24)][, q_rates24 := -rate_s24]
vars <- c("q_rate24","q_rate12","q_cnt24","q_rates24")
icA <- lapply(vars, function(v) list(
  full = ic_stat(P, v, 201101L),
  sp1  = ic_stat(P, v, 200501L, 201112L),
  sp2  = ic_stat(P, v, 201201L, 201812L),
  sp3  = ic_stat(P, v, 201901L, 202612L),
  y2017= ic_stat(P, v, 201701L)))
names(icA) <- vars
cat("=== A. rank-IC advisory (quality = -restate) ===\n")
for(v in vars) cat(sprintf("  %-10s full t=%.2f ic=%.4f n=%d | 2017+ t=%.2f | sp3(19+) t=%.2f\n",
  v, icA[[v]]$full$t, icA[[v]]$full$mean_ic, icA[[v]]$full$n, icA[[v]]$y2017$t, icA[[v]]$sp3$t))

# ---- B. standalone canonical dual-basis (primary quality = q_rate24), needs valid history ----
cat("\n=== B. standalone canonical (score = q_rate24, top-25 EW 15bps) ===\n")
Pv <- P[has_hist==1]
scores_dt <- Pv[, .(Date=sdate, Ticker, score=q_rate24)]
returns_dt<- Pv[, .(Date=sdate, Ticker, Ret_1m)]
bench_dt  <- unique(merge(Pv[, .(Date=sdate, ym)], bm, by="ym")[, .(Date, BM_Ret)])
liq_dt    <- Pv[, .(Date=sdate, Ticker, adv)]
size_dt   <- Pv[, .(Date=sdate, Ticker, size=Size)]
cs <- tryCatch(canonical_screen_bt(scores_dt, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
        liq_dt=liq_dt, liq_min=5e7, size_dt=size_dt, run_id="ha_rate24", strategy_id="ha_rate24"),
     error=function(e){cat("canon err:",conditionMessage(e),"\n");NULL})
if(!is.null(cs)){
  cat(sprintf("  cap-w PORT_t(NW3)=%.3f n_months=%d IR=%.3f netSR=%.3f TO=%.1f\n",
    cs$portfolio_alpha_t_nw_lag3, cs$n_months, cs$information_ratio, cs$net_sr, cs$turnover_annual))
  dg <- cs$diag_ew_universe
  if(!is.null(dg$portfolio_alpha_t_nw_lag3)) cat(sprintf("  diag_EW-universe PORT_t=%.3f post2017_t=%.3f oos_approx=%.3f\n",
    dg$portfolio_alpha_t_nw_lag3, dg$post2017_t_nw_lag3 %||% NA, dg$oos_retention_approx %||% NA))
  ct <- cs$diag_cap_tier
  if(isTRUE(ct$available)) cat(sprintf("  diag_cap_tier weight_share MEGA=%.2f MID=%.2f OTHER=%.2f | contrib_gross_ann MEGA=%.4f MID=%.4f OTHER=%.4f\n",
    ct$weight_share_avg$MEGA %||% NA, ct$weight_share_avg$MID %||% NA, ct$weight_share_avg$OTHER %||% NA,
    ct$contrib_gross_annualized$MEGA %||% NA, ct$contrib_gross_annualized$MID %||% NA, ct$contrib_gross_annualized$OTHER %||% NA))
}

# ---- C. book-marginal exclusion: remove high-restatement from score_eff top-25 ----
cat("\n=== C. book-marginal exclusion (primary=top-quintile rate_24, IS threshold) ===\n")
# IS-only threshold: top-quintile cutoff of rate_24 among has_hist firms, pooled 2005-2018
is_pool <- P[has_hist==1 & ym<=IS_MAX & rate_24>0]$rate_24
thr_q80 <- if(length(is_pool)>=50) quantile(is_pool, 0.80) else 0.15
cat(sprintf("  IS top-quintile rate_24 threshold=%.4f (n_is_pool=%d)\n", thr_q80, length(is_pool)))
# exclusion variants
P[, ex_q80  := as.integer(has_hist==1 & rate_24>=thr_q80)]      # primary
P[, ex_any  := as.integer(has_hist==1 & rate_24>0 & res_24>=2)] # >=2 restatements/24M
P[, ex_cnt3 := as.integer(has_hist==1 & cnt_24>=3)]             # >=3 restatements/24M

pick_active <- function(excl){
  P[, {
    d <- .SD; if(!is.null(excl)) d <- d[get(excl)==0]
    setorder(d,-score_eff); n<-min(25,nrow(d)); .(port=mean(d$Ret_1m[seq_len(n)]))
  }, by=ym, .SDcols=names(P)]
}
base <- pick_active(NULL)
bmt  <- merge(base[,.(ym,base=port)], bm, by="ym")
run_excl <- function(col){
  ex <- pick_active(col); m <- merge(bmt, ex[,.(ym,ex=port)], by="ym")
  m[, a_base := base - BM_Ret][, a_ex := ex - BM_Ret]; d <- m$a_ex - m$a_base
  chg <- sum(abs(d)>1e-12)
  ir <- function(a){a<-a[is.finite(a)];mean(a)/sd(a)*sqrt(12)}
  list(nwt=nwt(d), mean_delta=mean(d), changed=chg, n=nrow(m),
       dIR=ir(m$a_ex)-ir(m$a_base), ir_base=ir(m$a_base), ir_ex=ir(m$a_ex),
       nwt_is=nwt(d[m$ym<=IS_MAX]), nwt_oos=nwt(d[m$ym>IS_MAX]), d=d, ym=m$ym)
}
res_q80  <- run_excl("ex_q80")
res_any  <- run_excl("ex_any")
res_cnt3 <- run_excl("ex_cnt3")
for(nm in c("q80","any","cnt3")){ r<-get(paste0("res_",nm))
  cat(sprintf("  ex_%-5s: NWt=%.2f (IS=%.2f OOS=%.2f) dIR=%+.4f changed=%d/%d mean_delta=%.5f\n",
    nm, r$nwt, r$nwt_is, r$nwt_oos, r$dIR, r$changed, r$n, r$mean_delta))}

# ---- D. placebo null: random exclusion matching ex_q80 count each month (200 draws) ----
cat("\n=== D. placebo null (random exclusion, 200 draws) ===\n")
nex_by_ym <- P[, .(k=sum(ex_q80)), by=ym]
placebo_nwt <- numeric(200)
for(b in 1:200){
  exp <- P[, {
    d <- copy(.SD); k <- nex_by_ym[ym==.BY$ym]$k
    drop <- if(k>0 && k<nrow(d)) sample(seq_len(nrow(d)), k) else integer(0)
    if(length(drop)) d <- d[-drop]
    setorder(d,-score_eff); n<-min(25,nrow(d)); .(port=mean(d$Ret_1m[seq_len(n)]))
  }, by=ym, .SDcols=names(P)]
  m <- merge(bmt, exp[,.(ym,ex=port)], by="ym"); d <- (m$ex-m$BM_Ret)-(m$base-m$BM_Ret)
  placebo_nwt[b] <- nwt(d)
}
placebo_nwt <- placebo_nwt[is.finite(placebo_nwt)]
p_emp <- mean(abs(placebo_nwt) >= abs(res_q80$nwt))
cat(sprintf("  placebo |NWt| dist: mean=%.2f sd=%.2f q95=%.2f | actual ex_q80 NWt=%.2f | emp p(2-sided)=%.3f\n",
  mean(placebo_nwt), sd(placebo_nwt), quantile(abs(placebo_nwt),0.95), res_q80$nwt, p_emp))

# ---- E. lag1 stress: shift signal 1 month ----
cat("\n=== E. lag1 stress (exclusion signal shifted +1M) ===\n")
setorder(P, Ticker, ym)
P[, ex_q80_lag1 := shift(ex_q80,1L,fill=0L), by=Ticker]
res_lag1 <- run_excl("ex_q80_lag1")
cat(sprintf("  ex_q80_lag1: NWt=%.2f dIR=%+.4f changed=%d\n", res_lag1$nwt, res_lag1$dIR, res_lag1$changed))

# ---- n_trials / null max-t ----
allt <- c(res_q80$nwt,res_any$nwt,res_cnt3$nwt, sapply(vars,function(v) icA[[v]]$full$t))
n_trials <- length(allt)
max_abs_t <- max(abs(allt),na.rm=TRUE)
cat(sprintf("\n=== n_trials=%d max|t|=%.2f | placebo null q95(|NWt|)=%.2f ===\n",
  n_trials, max_abs_t, quantile(abs(placebo_nwt),0.95)))

saveRDS(list(icA=icA, canon=cs, book=list(q80=res_q80,any=res_any,cnt3=res_cnt3,lag1=res_lag1),
  placebo=list(dist=placebo_nwt, emp_p=p_emp), thr_q80=thr_q80, n_trials=n_trials, max_abs_t=max_abs_t),
  file.path(OUT,"ha_results.rds"))
cat("DONE_PART2\n")
