## ============================================================
## WT-D20260529_001 FLOW — Codex Round remediation (post-critic)
## Addresses ACCEPTed concerns C1(5-spec Harvey supporting), C2(MDD elevate),
## C3(same-period STR_1715 baseline), C4(realized DSR + penalty), C5(turnover fix),
## C6(monthly_returns.parquet), C9(three-way Pre-LB/Lockbox/Combined metrics).
## Reuses bt_result.rds (no re-run of daily NAV loop). Contract funcs only.
## ============================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics); library(sandwich); library(lmtest); library(e1071)
})
BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260529_001")
BT_DIR <- file.path(WT_DIR, "backtest_result")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(BASE,"02_Infrastructure/contracts/backtest_result_contract.R"))

bt <- readRDS(file.path(BT_DIR,"bt_result.rds"))
pr <- bt$period_returns; br <- bt$benchmark_returns
LB <- as.Date("2023-12-22"); LB_OOS_START <- as.Date("2024-01-01")

# monthly net + benchmark via contract aggregation
rx <- xts(pr$ret_net, order.by=pr$date); bx <- xts(br$benchmark_ret, order.by=br$date)
rm_m <- apply.monthly(rx, Return.cumulative); bm_m <- apply.monthly(bx, Return.cumulative)
M <- merge(data.table(Date=as.Date(index(rm_m)), ret=as.numeric(rm_m)),
           data.table(Date=as.Date(index(bm_m)), bret=as.numeric(bm_m)), by="Date")
M[, active := ret - bret]

# ---- C6: emit monthly_returns.parquet ----
write_parquet(M, file.path(BT_DIR,"monthly_returns.parquet"))
cat(sprintf("[C6] monthly_returns.parquet emitted (%d months)\n", nrow(M)))

# ---- helper: three-window perf ----
perf_window <- function(dt, label, n_cands=0L, pen=0.05) {
  r <- dt$ret; a <- dt$active; n <- length(r); ny <- n/12
  sr_m <- mean(r)/sd(r); sr <- sr_m*sqrt(12)
  cagr <- prod(1+r)^(1/ny)-1; vol <- sd(r)*sqrt(12)
  cum <- cumprod(1+r); mdd <- min(cum/cummax(cum)-1)
  pa_t <- .nw_t_mean(a, lag=3L)
  ir <- mean(a)/sd(a)*sqrt(12)
  ann_ex <- (prod(1+r)^(1/ny)-1) - (prod(1+dt$bret)^(1/ny)-1)
  sk <- tryCatch(e1071::skewness(r),error=function(e)0); ku <- tryCatch(e1071::kurtosis(r)+3,error=function(e)3)
  den <- sqrt((1 - sk*sr_m + (ku-1)/4*sr_m^2)/(n-1))
  dsr_raw <- if(!is.na(den)&&den>1e-10) sr/(den*sqrt(12)) else NA
  dsr_post <- if(!is.na(dsr_raw)) dsr_raw - n_cands*pen else NA
  cat(sprintf("  [%-26s] n=%3d | SR=%.4f | CAGR=%+.2f%% | MDD=%.2f%% | pa_t=%.4f | IR=%.4f | annEx=%+.2f%% | DSRpost=%.4f\n",
              label, n, sr, cagr*100, mdd*100, pa_t, ir, ann_ex*100, dsr_post %||% NA))
  list(label=label,n=n,sr=round(sr,4),cagr=round(cagr,4),mdd=round(mdd,4),vol=round(vol,4),
       pa_t=round(pa_t,4),ir=round(ir,4),ann_excess=round(ann_ex,4),
       dsr_raw=round(dsr_raw %||% NA,4),dsr_post=round(dsr_post %||% NA,4))
}

# total disclosed trials: alpha 15 factor-level + optimizer 11 sleeve configs = 26
N_CANDS <- 26L; DSR_PEN <- 0.05
cat("\n[C9 + C4] Three-window metrics (DSR penalty n_cands=26 x 0.05):\n")
w_full <- perf_window(M,                       "FULL 2005-2026",  N_CANDS, DSR_PEN)
w_pre  <- perf_window(M[Date<=LB],             "PRE-LB <=2023-12", N_CANDS, DSR_PEN)
w_oos  <- perf_window(M[Date>=LB_OOS_START],   "LOCKBOX-OOS 2024+", 0L, DSR_PEN)

# ---- C1: 5-spec Harvey NW-HAC on monthly excess (FULL + PRE-LB) ----
cat("\n[C1] 5-spec Harvey NW-HAC regression (FF5 v2):\n")
ff5 <- as.data.table(read_parquet(file.path(BASE,".cache/kr_factor_returns_v2.parquet")))
ff5[, YM := format(Date,"%Y-%m")]
Mh <- copy(M); Mh[, YM := format(Date,"%Y-%m")]
Mh <- merge(Mh, ff5[,.(YM,MKT,SMB,HML,WML,RMW,CMA,RF)], by="YM", all.x=TRUE)
Mh[, exr := ret - RF]
nw_t <- function(mod){ n<-length(residuals(mod)); lag<-max(1L,floor(4*(n/100)^(2/9)))
  ct<-coeftest(mod, vcov=NeweyWest(mod,lag=lag,prewhite=FALSE,adjust=TRUE))
  list(alpha=ct["(Intercept)","Estimate"], t=ct["(Intercept)","t value"], p=ct["(Intercept)","Pr(>|t|)"], n=n) }
specs <- list(CAPM=c("MKT"),Carhart3=c("MKT","SMB","HML"),Carhart4=c("MKT","SMB","HML","WML"),
              FF5=c("MKT","SMB","HML","RMW","CMA"),FF6=c("MKT","SMB","HML","WML","RMW","CMA"))
harvey_full <- list(); harvey_pre <- list()
run_specs <- function(dat, store){
  for(sp in names(specs)){ v<-specs[[sp]]; sub<-dat[rowSums(!is.na(dat[,..v]))==length(v) & !is.na(exr)]
    if(nrow(sub)<20){store[[sp]]<-list(t=NA,alpha=NA,p=NA,n=nrow(sub),pass=FALSE);next}
    mod<-lm(as.formula(paste("exr ~",paste(v,collapse="+"))),sub); res<-nw_t(mod)
    store[[sp]]<-list(t=round(res$t,3),alpha_monthly_pct=round(res$alpha*100,4),p=round(res$p,4),n=res$n,pass=isTRUE(res$t>=2.95)) }
  store }
harvey_full <- run_specs(Mh, harvey_full)
harvey_pre  <- run_specs(Mh[Date<=LB], harvey_pre)
cat("  FULL window:\n"); for(sp in names(harvey_full)){x<-harvey_full[[sp]];cat(sprintf("    %-9s t_NW=%+.3f alpha=%+.4f%% n=%d [%s]\n",sp,x$t %||% NA,x$alpha_monthly_pct %||% NA,x$n,if(isTRUE(x$pass))"PASS"else"FAIL"))}
cat("  PRE-LB window (proxy basis):\n"); for(sp in names(harvey_pre)){x<-harvey_pre[[sp]];cat(sprintf("    %-9s t_NW=%+.3f alpha=%+.4f%% n=%d [%s]\n",sp,x$t %||% NA,x$alpha_monthly_pct %||% NA,x$n,if(isTRUE(x$pass))"PASS"else"FAIL"))}
n_pass_full <- sum(sapply(harvey_full,function(x)isTRUE(x$pass)))
n_pass_pre  <- sum(sapply(harvey_pre, function(x)isTRUE(x$pass)))
cat(sprintf("  Harvey 5-spec PASS: FULL %d/5 | PRE-LB %d/5\n", n_pass_full, n_pass_pre))

# ---- C3: same-period STR_1715 baseline (recomputed, same cost basis already net) ----
cat("\n[C3] Same-period STR_1715 baseline (realized monthly, same period/cost):\n")
s1715 <- fread(file.path(BASE,"qepm/mailbox/governor/str_1715_full_reassessment/str_1715_monthly_returns_full.csv"))
s1715[, Date := as.Date(Date)]; s1715[, YM := format(Date,"%Y-%m")]
Mb <- copy(M); Mb[, YM := format(Date,"%Y-%m")]
# overlap on year-month
ov <- merge(Mb[,.(YM,flow_ret=ret,bret)], s1715[,.(YM,s1715_ret=monthly_ret)], by="YM")
cat(sprintf("  overlap %d months (%s ~ %s)\n", nrow(ov), min(ov$YM), max(ov$YM)))
base_perf <- function(r, b, n_cands, label){
  n<-length(r); ny<-n/12; sr_m<-mean(r)/sd(r); sr<-sr_m*sqrt(12)
  a<-r-b; pa_t<-.nw_t_mean(a,lag=3L); ir<-mean(a)/sd(a)*sqrt(12)
  cum<-cumprod(1+r); mdd<-min(cum/cummax(cum)-1)
  sk<-tryCatch(e1071::skewness(r),error=function(e)0);ku<-tryCatch(e1071::kurtosis(r)+3,error=function(e)3)
  den<-sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(n-1)); dsr_raw<-if(!is.na(den)&&den>1e-10)sr/(den*sqrt(12))else NA
  dsr_post<-if(!is.na(dsr_raw))dsr_raw-n_cands*0.05 else NA
  cat(sprintf("  [%-20s] n=%d SR=%.4f MDD=%.2f%% pa_t=%.4f IR=%.4f DSRpost=%.4f\n",label,n,sr,mdd*100,pa_t,ir,dsr_post %||% NA))
  list(n=n,sr=round(sr,4),mdd=round(mdd,4),pa_t=round(pa_t,4),ir=round(ir,4),dsr_post=round(dsr_post %||% NA,4)) }
# STR_1715 baseline gets its OWN disclosed-trials penalty too (it is an incumbent; conservative: 0 extra since not re-shopped here, label honestly)
base_1715 <- base_perf(ov$s1715_ret, ov$bret, 0L, "STR_1715 baseline")
flow_ovl  <- base_perf(ov$flow_ret,  ov$bret, N_CANDS, "FLOW (same period)")

# ---- C5: turnover convention reconciliation ----
cat("\n[C5] Turnover reconciliation:\n")
avg_to <- bt$metrics[metric_name=="Average_Turnover", as.numeric(metric_value)][1]
n_rebal_per_yr <- 4  # quarterly
ann_to_correct <- avg_to * n_rebal_per_yr  # one-way L1 per rebal x rebals/yr
cat(sprintf("  Average_Turnover (per-rebal one-way L1) = %.4f\n", avg_to))
cat(sprintf("  Annualized (x4 quarterly) = %.4f/yr one-way (round-trip = %.4f/yr)\n", ann_to_correct, ann_to_correct*2))
cat(sprintf("  Contract's daily-annualized 163.296 is INVALID for quarterly rebal (x252 mislabel) — overridden.\n"))

# save remediation bundle
remediation <- list(
  three_window = list(full=w_full, pre_lb=w_pre, lockbox_oos=w_oos),
  harvey_5spec = list(full=harvey_full, pre_lb=harvey_pre, pass_full=n_pass_full, pass_pre_lb=n_pass_pre,
                      note="v8.x graduation Gate C metric = portfolio_alpha_t_nw_lag3 (judge owns 5-spec Gate); 5-spec emitted as supporting evidence per Codex C1."),
  same_period_baseline = list(overlap_months=nrow(ov), str_1715=base_1715, flow_same_period=flow_ovl,
                              note="STR_1715 realized monthly (Charter v1.4 standard basis), same overlap period, net. FLOW DSR penalized n_cands=26."),
  turnover = list(avg_per_rebal_oneway=round(avg_to,4), ann_oneway=round(ann_to_correct,4),
                  ann_roundtrip=round(ann_to_correct*2,4), rebal_per_yr=4,
                  contract_metric_invalid=163.296, contract_note="build_metrics x252 mislabels quarterly TO; corrected to x4."),
  mdd_hard_constraint = list(mdd_full=round(w_full$mdd,4), mdd_pre_lb=round(w_pre$mdd,4),
                             hard_cap=-0.45, breach=abs(w_full$mdd)>0.45,
                             note="MDD 58.8% FULL breaches 45% base hard constraint (Codex C2). Driven by 2008 GFC (beta~1 sleeve). Pre-LB MDD also reported.")
)
write_json(remediation, file.path(WT_DIR,"forge_remediation.json"), auto_unbox=TRUE, pretty=TRUE, na="null")
cat("\n[done] forge_remediation.json saved\n")
