## ============================================================================
## Track A — Soft/continuous regime gate vs hard-bin R05  (beyond M4×R05)
## Baseline (authoritative) = no_faith = beta_R05 × m4 × ret_orig − |Δβ_R05|×15bps
##   (WT-D20260702_002 recompute_bt_noLayer4_clean.R와 동일 정의, 269m)
## 목표: 연속 게이트가 step 게이트를 "평균노출 동일" 하에서 이기는지(순수 shape).
## 검증: contract build_metrics/build_benchmark_compare(ann=12) + paired NW-t + lag1 stress.
## 진행마커 = message()(stderr, unbuffered) → 세그폴트에도 마지막 지점 보존. 증분 CSV 저장.
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)
})
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015
PG("[PG] libs+contract loaded")

## ---------- 1. base panel ----------
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)
h <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))
h <- h[, .(realized_ym, R05_z_avg, R05_q20_past, R05_q50_past, regime_h=regime)]
p <- merge(p, h, by="realized_ym", all.x=TRUE, sort=FALSE); setorder(p, realized_ym)
p[, dR05_base := abs(beta_R05 - shift(beta_R05, 1, fill=1.0))]
p[, ret_base  := beta_R05*m4*ret_orig - dR05_base*COST]
PG("[PG] panels merged, ret_base mean=%.5f", mean(p$ret_base))

## ---------- 2. benchmark (pinned IKS200, monthly anchored) ----------
bm <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
bm_x <- xts(bm$BM_Ret, order.by=bm$Date)
a <- p$anchor_date; bmw <- rep(NA_real_, nrow(p))
for(i in 2:nrow(p)){ seg <- bm_x[index(bm_x)>a[i-1] & index(bm_x)<=a[i]]; if(nrow(seg)>0) bmw[i] <- as.numeric(Return.cumulative(seg)) }
bmw[1] <- 0
br <- data.table(benchmark_id="KOSPI200", benchmark_name="KOSPI 200", date=p$anchor_date,
                 benchmark_ret=bmw, benchmark_nav=cumprod(1+ifelse(is.na(bmw),0,bmw)),
                 risk_free_ret=0, benchmark_excess_ret=bmw, frequency="monthly")
PG("[PG] benchmark built")

## ---------- 3. metric helper ----------
RID <- "TRK_A"; SID <- "TRK_A"
metric_set <- function(ret_vec, tag){
  pr <- data.table(run_id=RID, strategy_id=SID, date=p$anchor_date, frequency="monthly",
                   ret_gross=ret_vec, ret_net=ret_vec, risk_free_ret=0, excess_ret_net=ret_vec,
                   turnover=NA_real_, cost_ret=0, cash_weight=NA_real_, leverage=NA_real_, n_holdings=NA_integer_)
  nav_v <- cumprod(1+ret_vec)
  nav_tbl <- data.table(run_id=RID, strategy_id=SID, date=pr$date, frequency="monthly",
                        nav_gross=nav_v, nav_net=nav_v, drawdown=NA_real_)
  hold_tbl <- data.table(matrix(nrow=0, ncol=length(HOLDINGS_COLS), dimnames=list(NULL,HOLDINGS_COLS)))
  m  <- build_metrics(nav_tbl, pr, hold_tbl, RID, SID, frequency="monthly", annualization_factor=12)
  bc <- build_benchmark_compare(pr, br, RID, SID, annualization_factor=12)
  gv <- function(dt,mn,col="metric_value"){v<-dt[metric_name==mn][[col]]; if(length(v))v[1] else NA_real_}
  x <- xts(ret_vec, order.by=p$anchor_date)
  data.table(tag=tag,
    SR_geo = as.numeric(table.AnnualizedReturns(x, scale=12)[3,1]),
    CAGR=gv(m,"CAGR"), MDD=gv(m,"MDD"), Calmar=gv(m,"Calmar"),
    PORT_t = bc[metric_name=="Portfolio_Alpha_t_NW_lag3"]$strategy_value[1],
    IR     = bc[metric_name=="Information_Ratio"]$active_value[1])
}
nw_t_paired <- function(cand, base, lag=3){
  d <- cand - base; d <- d[is.finite(d)]; n <- length(d); mu <- mean(d)
  dm <- d - mu; g0 <- sum(dm^2)/n; gsum <- 0
  for(L in 1:lag){ w <- 1 - L/(lag+1); gsum <- gsum + 2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n }
  se <- sqrt((g0+gsum)/n); c(mean_diff_ann = mu*12, t = mu/se)
}

## ---------- 4. RECONCILIATION GATE ----------
base_m <- metric_set(p$ret_base, "BASE_no_faith")
PG("[PG] RECON SR_geo=%.4f Calmar=%.4f PORT_t=%.4f IR=%.4f", base_m$SR_geo, base_m$Calmar, base_m$PORT_t, base_m$IR)
recon_ok <- abs(base_m$SR_geo-1.898)<0.01 && abs(base_m$Calmar-1.943)<0.02 && abs(base_m$PORT_t-6.214)<0.10
if(!recon_ok){ PG("[PG] RECON FAIL"); stop("reconciliation failed") }
PG("[PG] RECON PASS")

## ---------- 5. continuous gate builders (avg-exposure matched) ----------
mean_beta_base <- mean(p$beta_R05)
sgn <- sign(cor(p$beta_R05, p$R05_z_avg, use="complete.obs"))
PG("[PG] cor(beta_R05,R05_z)=%.3f mean_beta_base=%.4f floor=%.2f",
   cor(p$beta_R05,p$R05_z_avg,use="complete.obs"), mean_beta_base, min(p$beta_R05))
z <- p$R05_z_avg; n <- length(z); u <- rep(NA_real_, n)
for(i in 2:n){ past <- z[1:(i-1)]; past <- past[is.finite(past)]
  if(length(past)>=6 && is.finite(z[i])) u[i] <- mean(past < z[i]) }
u[!is.finite(u)] <- 0.5
stress <- if(sgn>=0) (1-u) else u
FLOOR <- min(p$beta_R05)

apply_gate <- function(beta_vec){
  dbeta <- abs(beta_vec - shift(beta_vec, 1, fill=1.0)); beta_vec*p$m4*p$ret_orig - dbeta*COST
}
## (A1) linear ramp — near-flat at avg-match (baseline-style contrast)
build_soft_linear <- function(sv, tgt, floor=FLOOR){
  f <- function(c) mean(pmin(1, pmax(floor, 1 - c*sv))) - tgt
  cc <- tryCatch(uniroot(f, c(0,20))$root, error=function(e) NA_real_)
  if(is.na(cc)) rep(NA_real_,length(sv)) else pmin(1, pmax(floor, 1 - cc*sv))
}
## (A2/A4) CONVEX tail-cut: beta=1 for stress<θ, convex cut in tail. avg-match via θ.
##   → keeps normal months at 1.0 (high mean achievable) + cuts hard in tail like bins, but smooth.
build_tailcut <- function(sv, tgt, floor=FLOOR, gamma=2){
  f <- function(th){ x <- pmax(0,(sv-th)/(1-th+1e-9)); mean(1-(1-floor)*pmin(1,x)^gamma) - tgt }
  th <- tryCatch(uniroot(f, c(0,0.999))$root, error=function(e) NA_real_)
  if(is.na(th)) return(rep(NA_real_,length(sv)))
  x <- pmax(0,(sv-th)/(1-th+1e-9)); 1-(1-floor)*pmin(1,x)^gamma
}
## (A3) conditional vol-target, risk-off only
so <- p$ret_orig; sig <- rep(NA_real_, n)
for(i in 13:n) sig[i] <- sd(so[(i-12):(i-1)]); sig[!is.finite(sig)] <- median(sig, na.rm=TRUE)
risk_off <- p$regime %in% c("CAUTION","CRISIS")
PG("[PG] risk_off frac=%.3f  sig range [%.3f,%.3f]", mean(risk_off), min(sig), max(sig))
build_voltarget <- function(tgt){
  f <- function(sc) mean(ifelse(risk_off, pmin(1, pmax(FLOOR, sc/sig)), 1)) - tgt
  sc <- tryCatch(uniroot(f, c(1e-6,100))$root, error=function(e) NA_real_)
  if(is.na(sc)) rep(NA_real_,n) else ifelse(risk_off, pmin(1, pmax(FLOOR, sc/sig)), 1)
}

## (A5) market crisis-prob signal — MSM_Crisis_Prob from pinned regime cache (PIT: last date < anchor)
msm_stress <- rep(NA_real_, n)
tryCatch({
  urs <- as.data.table(read_parquet(file.path(WD,"pinned_cache/unified_regime_signal_daily.parquet")))
  cand_col <- intersect(c("MSM_Crisis_Prob","Regime_Score_smooth","Regime_Score"), names(urs))[1]
  urs[, Date := as.Date(Date)]; setorder(urs, Date)
  urs <- urs[is.finite(get(cand_col))]
  for(i in 1:n){ pastv <- urs[Date < p$anchor_date[i]]; if(nrow(pastv)>0) msm_stress[i] <- tail(pastv[[cand_col]],1) }
  ## normalize to [0,1] expanding percentile (PIT)
  ms <- msm_stress; up <- rep(NA_real_, n)
  for(i in 2:n){ pv <- ms[1:(i-1)]; pv <- pv[is.finite(pv)]; if(length(pv)>=6 && is.finite(ms[i])) up[i] <- mean(pv < ms[i]) }
  up[!is.finite(up)] <- 0.5; msm_stress <<- up
  PG("[PG] A5 signal=%s loaded, cor(base_beta, msm_stress)=%.3f", cand_col, cor(p$beta_R05, up, use="complete.obs"))
}, error=function(e) PG("[PG] A5 signal load ERR: %s", conditionMessage(e)))

beta_A1 <- build_soft_linear(stress, mean_beta_base)
beta_A2 <- build_tailcut(stress, mean_beta_base, gamma=2)
beta_A3 <- build_voltarget(mean_beta_base)
beta_A4 <- build_tailcut(stress, mean_beta_base, gamma=3)
beta_A5 <- if(all(is.finite(msm_stress))) build_tailcut(msm_stress, mean_beta_base, gamma=2) else rep(NA_real_,n)
smry <- function(b) if(all(is.finite(b))) sprintf("mean=%.3f min=%.2f max=%.2f", mean(b),min(b),max(b)) else "HAS_NA"
PG("[PG] A1 %s | A2 %s | A3 %s | A4 %s | A5 %s", smry(beta_A1),smry(beta_A2),smry(beta_A3),smry(beta_A4),smry(beta_A5))

## ---------- 6. evaluate (per-candidate isolated + incremental save) ----------
rows <- list(cbind(base_m, data.table(mean_beta=mean_beta_base, mean_diff_ann=0, paired_t=NA_real_, lag1_t=NA_real_)))
cand <- list(A1_linramp_R05z=beta_A1, A2_tailcut_R05z_g2=beta_A2, A3_condvoltarget=beta_A3,
             A4_tailcut_R05z_g3=beta_A4, A5_tailcut_MSMprob=beta_A5)
for(nm in names(cand)){
  bv <- cand[[nm]]
  if(any(!is.finite(bv))){ PG("[PG] skip %s (build NA)", nm); next }
  r <- tryCatch({
    rc <- apply_gate(bv); mm <- metric_set(rc, nm)
    pt <- nw_t_paired(rc, p$ret_base, 3)
    bv_lag <- shift(bv, 1, fill=1.0); pt_lag <- nw_t_paired(apply_gate(bv_lag), p$ret_base, 3)
    cbind(mm, data.table(mean_beta=mean(bv), mean_diff_ann=pt["mean_diff_ann"], paired_t=pt["t"], lag1_t=pt_lag["t"]))
  }, error=function(e){ PG("[PG] ERR %s: %s", nm, conditionMessage(e)); NULL })
  if(!is.null(r)){ rows[[length(rows)+1]] <- r
    PG("[PG] %s SR=%.4f PORT_t=%.3f paired_t=%.2f lag1_t=%.2f", nm, r$SR_geo, r$PORT_t, r$paired_t, r$lag1_t) }
}
res <- rbindlist(rows, fill=TRUE)
fwrite(res, file.path(WD, "trackA_results.csv"))
PG("[PG] DONE saved trackA_results.csv (%d rows)", nrow(res))
print(res[, .(tag, SR_geo=round(SR_geo,4), Calmar=round(Calmar,4), MDD=round(MDD,4),
              PORT_t=round(PORT_t,3), IR=round(IR,4), mean_beta=round(mean_beta,4),
              d_ann=round(mean_diff_ann,4), paired_t=round(paired_t,3), lag1_t=round(lag1_t,3))])
