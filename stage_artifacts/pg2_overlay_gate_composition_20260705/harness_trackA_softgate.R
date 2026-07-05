## ============================================================================
## Track A — Soft/continuous regime gate vs hard-bin R05  (beyond M4×R05)
## Baseline (authoritative) = no_faith = beta_R05 × m4 × ret_orig − |Δβ_R05|×15bps
##   (WT-D20260702_002 recompute_bt_noLayer4_clean.R와 동일 정의, 269m)
## 목표: 연속 게이트가 step 게이트를 "평균노출 동일" 하에서 이기는지(순수 shape).
##   max-cash 교훈: 총 방어수준을 낮춰 이기는 것 금지 → 평균 β 매칭이 통제변수.
## 검증: contract build_metrics/build_benchmark_compare(ann=12) + paired NW-t + lag1 stress.
## 캐시 vintage: pinned_cache/ (18:12 봉인). 외부 regime는 pin만 소비.
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)
})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
PIN  <- file.path(WD, "pinned_cache")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015

## ---------- 1. base panel (authoritative no_faith source) ----------
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)

## R05_z_avg + expanding quantiles + regime from extended panel (fixed file, PIT-lagged)
h <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))
h <- h[, .(realized_ym, R05_z_avg, R05_q20_past, R05_q50_past, regime_h=regime)]
p <- merge(p, h, by="realized_ym", all.x=TRUE, sort=FALSE); setorder(p, realized_ym)

## baseline series (EXACT authoritative construction)
p[, dR05_base := abs(beta_R05 - shift(beta_R05, 1, fill=1.0))]
p[, ret_base  := beta_R05*m4*ret_orig - dR05_base*COST]

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

## ---------- 3. metric helper via contract ----------
RID <- "TRK_A"; SID <- "TRK_A"
metric_set <- function(ret_vec, tag){
  pr <- data.table(run_id=RID, strategy_id=SID, date=p$anchor_date, frequency="monthly",
                   ret_gross=ret_vec, ret_net=ret_vec, risk_free_ret=0,
                   excess_ret_net=ret_vec, turnover=NA_real_, cost_ret=0,
                   cash_weight=NA_real_, leverage=NA_real_, n_holdings=NA_integer_)
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
    CAGR   = gv(m,"CAGR"), MDD = gv(m,"MDD"), Calmar = gv(m,"Calmar"),
    PORT_t = bc[metric_name=="Portfolio_Alpha_t_NW_lag3"]$strategy_value[1],
    IR     = bc[metric_name=="Information_Ratio"]$active_value[1],
    mean_beta = NA_real_)
}

## Newey-West t of paired difference (cand - base), lag=3
nw_t_paired <- function(cand, base, lag=3){
  d <- cand - base; d <- d[is.finite(d)]; n <- length(d); mu <- mean(d)
  dm <- d - mu; g0 <- sum(dm^2)/n
  gsum <- 0; for(L in 1:lag){ w <- 1 - L/(lag+1); gsum <- gsum + 2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n }
  lrv <- g0 + gsum; se <- sqrt(lrv/n)
  c(mean_diff_ann = mu*12, t = mu/se)
}

## ---------- 4. RECONCILIATION GATE ----------
base_m <- metric_set(p$ret_base, "BASE_no_faith")
cat("\n===== RECONCILIATION (must match judge: SR_geo 1.898 / Calmar 1.943 / PORT_t 6.214) =====\n")
print(base_m)
recon_ok <- abs(base_m$SR_geo-1.898)<0.01 && abs(base_m$Calmar-1.943)<0.02 && abs(base_m$PORT_t-6.214)<0.10
cat(sprintf("[RECON] %s\n", if(recon_ok)"PASS — 하네스 신뢰" else "FAIL — 조사 필요, A/B 중단"))
if(!recon_ok) stop("reconciliation failed")

## ---------- 5. continuous gate builders (avg-exposure matched to base) ----------
## empirical sign: correlate base β_R05 with R05_z_avg
cat(sprintf("\n[diag] cor(beta_R05, R05_z_avg) = %.3f  (양수면 high z=risk-on)\n",
            cor(p$beta_R05, p$R05_z_avg, use="complete.obs")))
mean_beta_base <- mean(p$beta_R05)
cat(sprintf("[diag] mean(beta_R05_base) = %.4f  range [%.2f, %.2f]\n",
            mean_beta_base, min(p$beta_R05), max(p$beta_R05)))

## expanding PIT percentile of R05_z_avg (rank among strictly-past values)
z <- p$R05_z_avg; n <- length(z); u <- rep(NA_real_, n)
for(i in 2:n){ past <- z[1:(i-1)]; past <- past[is.finite(past)]
  if(length(past)>=6 && is.finite(z[i])) u[i] <- mean(past < z[i]) }
u[!is.finite(u)] <- 0.5  ## warmup neutral
## stress = 1-u if high z = risk-on (β↑ with z); else stress = u. set by sign
sgn <- sign(cor(p$beta_R05, p$R05_z_avg, use="complete.obs"))
stress <- if(sgn>=0) (1-u) else u          ## high stress -> de-risk

## builder: linear ramp beta = 1 - c*stress, clip[FLOOR,1], solve c for avg-match
FLOOR <- min(p$beta_R05)  ## 0.3 typically
build_soft_linear <- function(stress_vec, target_mean, floor=FLOOR){
  f <- function(c){ b <- pmin(1, pmax(floor, 1 - c*stress_vec)); mean(b) - target_mean }
  cc <- tryCatch(uniroot(f, c(0, 5))$root, error=function(e) NA_real_)
  if(is.na(cc)) return(rep(NA_real_, length(stress_vec)))
  pmin(1, pmax(floor, 1 - cc*stress_vec))
}
## builder: logistic on stress, avg-match via scale
build_soft_logit <- function(stress_vec, target_mean, floor=FLOOR){
  s <- (stress_vec - mean(stress_vec, na.rm=TRUE))/ (sd(stress_vec,na.rm=TRUE)+1e-9)
  f <- function(k){ b <- floor + (1-floor)/(1+exp(k*s)); mean(b) - target_mean }
  kk <- tryCatch(uniroot(f, c(-8,8))$root, error=function(e) NA_real_)
  if(is.na(kk)) return(rep(NA_real_, length(stress_vec)))
  floor + (1-floor)/(1+exp(kk*s))
}

apply_gate <- function(beta_vec){
  dbeta <- abs(beta_vec - shift(beta_vec, 1, fill=1.0))
  beta_vec*p$m4*p$ret_orig - dbeta*COST
}

## candidate A1: soft-linear on R05_z stress
beta_A1 <- build_soft_linear(stress, mean_beta_base)
## candidate A2: soft-logistic on R05_z stress
beta_A2 <- build_soft_logit(stress, mean_beta_base)
## candidate A3: conditional vol-target — only in CAUTION/CRISIS regimes de-risk by sigma
##   sigma_realized = trailing 12m sd of ret_orig (PIT past). target = full-sample-matched.
so <- p$ret_orig; sig <- rep(NA_real_, n)
for(i in 13:n) sig[i] <- sd(so[(i-12):(i-1)])
sig[!is.finite(sig)] <- median(sig, na.rm=TRUE)
risk_off <- p$regime %in% c("CAUTION","CRISIS")
raw_vt <- ifelse(risk_off, 1/sig, 1)  ## de-risk more when vol high, only risk-off months
## scale raw_vt into [FLOOR,1] and avg-match
f_vt <- function(sc){ b <- ifelse(risk_off, pmin(1, pmax(FLOOR, sc/sig)), 1); mean(b) - mean_beta_base }
sc_star <- tryCatch(uniroot(f_vt, c(1e-5, 5))$root, error=function(e) NA_real_)
beta_A3 <- if(is.na(sc_star)) rep(NA_real_,n) else ifelse(risk_off, pmin(1, pmax(FLOOR, sc_star/sig)), 1)

cand <- list(A1_softlin_R05z=beta_A1, A2_softlogit_R05z=beta_A2, A3_condvoltarget=beta_A3)

## ---------- 6. evaluate candidates ----------
res <- copy(base_m); res$mean_beta <- mean_beta_base
res$mean_diff_ann <- 0; res$paired_t <- NA_real_; res$lag1_t <- NA_real_
for(nm in names(cand)){
  bv <- cand[[nm]]; if(any(!is.finite(bv))){ cat(sprintf("[skip] %s (build failed)\n", nm)); next }
  rc <- apply_gate(bv)
  mm <- metric_set(rc, nm); mm$mean_beta <- mean(bv)
  pt <- nw_t_paired(rc, p$ret_base, 3)
  ## lag1 stress: delay gate signal by +1 month (apply beta_{t-1})
  bv_lag <- shift(bv, 1, fill=1.0); rc_lag <- apply_gate(bv_lag)
  pt_lag <- nw_t_paired(rc_lag, p$ret_base, 3)
  mm$mean_diff_ann <- pt["mean_diff_ann"]; mm$paired_t <- pt["t"]; mm$lag1_t <- pt_lag["t"]
  res <- rbind(res, mm, fill=TRUE)
}
cat("\n===== Track A candidates vs BASE (avg-exposure matched) =====\n")
print(res[, .(tag, SR_geo=round(SR_geo,4), Calmar=round(Calmar,4), MDD=round(MDD,4),
              PORT_t=round(PORT_t,3), IR=round(IR,4), mean_beta=round(mean_beta,4),
              d_ann=round(mean_diff_ann,4), paired_t=round(paired_t,3), lag1_t=round(lag1_t,3))])
fwrite(res, file.path(WD, "trackA_results.csv"))
cat(sprintf("\n[DONE] saved trackA_results.csv\n"))
cat("\n판정 규칙: paired_t>~2 (유의개선) AND lag1_t 부호유지(누출 아님) AND SR_geo>1.898 동시충족만 승격후보.\n")
