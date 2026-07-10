# ============================================================================
# Champions Tournament slot 3/5 — O3_MIDBAND_FLOOR forensic revalidation
#   Original champion: Track F O3 (2026-06-12) PORT_t 5.679 on OLD book
#   (g_inc = beta_AR x m4; Layer4/beta_AR removed 2026-07-02 look-ahead;
#    benchmark then = pre-IKS200-fix cache).
#   INV-7 differentiated variant (1 trial): transplant midband-floor formula
#   onto CURRENT noLayer4 book gate g = beta_R05 x m4:
#     g_o3 = g            if g < 0.25 or beta_R05 < 0.25 (INV-O1 deep-guard)
#          = max(g, 0.5)  otherwise
#   Differentiation vs 2026-07-05 Track A grid: discrete floor-coarsening,
#   NOT exposure-matched, never tested on noLayer4 book (A1..A5 were
#   continuous, avg-exposure-matched gates).
#   Decision window = IS 2005-2018 (realized_ym). FULL/OOS = context only.
#   Cost: uniform delta 15bps x |d g_arm| on BOTH arms (Track F prereg conv).
#   Benchmark: pinned IKS200 (post 07-02 fix) benchmark_pinned_20260702.
#   metric_type = backtested (contract build_metrics/build_benchmark_compare).
# ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)
})
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "04_Research/champions_revalidation/slot3_o3_midband")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015
PG("[PG] libs+contract loaded")

## ---------- 1. base panel (269m, production faith panel is source of legs) ----
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)
p[, dR05_base := abs(beta_R05 - shift(beta_R05, 1, fill=1.0))]
p[, ret_base_auth := beta_R05*m4*ret_orig - dR05_base*COST]   # authoritative def
PG("[PG] panel loaded n=%d %s..%s", nrow(p), p$realized_ym[1], p$realized_ym[nrow(p)])

## ---------- 2. benchmark (pinned IKS200 post-fix, monthly anchored) ----------
bm <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
bm_x <- xts(bm$BM_Ret, order.by=bm$Date)
a <- p$anchor_date; bmw <- rep(NA_real_, nrow(p))
for(i in 2:nrow(p)){ seg <- bm_x[index(bm_x)>a[i-1] & index(bm_x)<=a[i]]; if(nrow(seg)>0) bmw[i] <- as.numeric(Return.cumulative(seg)) }
bmw[1] <- 0
p[, bm_ret := ifelse(is.na(bmw), 0, bmw)]
PG("[PG] benchmark built (pinned IKS200)")

## ---------- 3. metric helper (windowed) ----------
RID <- "CHAMP_S3"; SID <- "CHAMP_S3"
metric_set <- function(dt_sub, ret_col, tag){
  rv <- dt_sub[[ret_col]]
  pr <- data.table(run_id=RID, strategy_id=SID, date=dt_sub$anchor_date, frequency="monthly",
                   ret_gross=rv, ret_net=rv, risk_free_ret=0, excess_ret_net=rv,
                   turnover=NA_real_, cost_ret=0, cash_weight=NA_real_, leverage=NA_real_, n_holdings=NA_integer_)
  nav_v <- cumprod(1+rv)
  nav_tbl <- data.table(run_id=RID, strategy_id=SID, date=pr$date, frequency="monthly",
                        nav_gross=nav_v, nav_net=nav_v, drawdown=NA_real_)
  hold_tbl <- data.table(matrix(nrow=0, ncol=length(HOLDINGS_COLS), dimnames=list(NULL,HOLDINGS_COLS)))
  br <- data.table(benchmark_id="KOSPI200", benchmark_name="KOSPI 200", date=dt_sub$anchor_date,
                   benchmark_ret=dt_sub$bm_ret, benchmark_nav=cumprod(1+dt_sub$bm_ret),
                   risk_free_ret=0, benchmark_excess_ret=dt_sub$bm_ret, frequency="monthly")
  m  <- build_metrics(nav_tbl, pr, hold_tbl, RID, SID, frequency="monthly", annualization_factor=12)
  bc <- build_benchmark_compare(pr, br, RID, SID, annualization_factor=12)
  gv <- function(dt,mn,col="metric_value"){v<-dt[metric_name==mn][[col]]; if(length(v))v[1] else NA_real_}
  x <- xts(rv, order.by=dt_sub$anchor_date)
  data.table(tag=tag, n=nrow(dt_sub),
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

## ---------- 4. RECONCILIATION GATE (base authoritative vs 07-05 authority) ----
base_full <- metric_set(p, "ret_base_auth", "BASE_auth_FULL")
PG("[PG] RECON SR_geo=%.4f Calmar=%.4f PORT_t=%.4f IR=%.4f",
   base_full$SR_geo, base_full$Calmar, base_full$PORT_t, base_full$IR)
recon_ok <- abs(base_full$SR_geo-1.898)<0.01 && abs(base_full$Calmar-1.943)<0.02 && abs(base_full$PORT_t-6.214)<0.10
if(!recon_ok) stop("reconciliation failed")
PG("[PG] RECON PASS")

## ---------- 5. arms under uniform delta cost ----------
p[, g_base := beta_R05*m4]
p[, g_o3   := ifelse(g_base < 0.25 | beta_R05 < 0.25, g_base, pmax(g_base, 0.5))]
p[, ret_base_u := g_base*ret_orig - abs(g_base - shift(g_base,1,fill=1.0))*COST]
p[, ret_o3_u   := g_o3  *ret_orig - abs(g_o3   - shift(g_o3,  1,fill=1.0))*COST]
## lag1 stress arm
p[, g_o3_lag := shift(g_o3, 1, fill=1.0)]
p[, ret_o3_lag := g_o3_lag*ret_orig - abs(g_o3_lag - shift(g_o3_lag,1,fill=1.0))*COST]

mid_full <- p[g_base >= 0.25 & g_base < 0.5 & beta_R05 >= 0.25]
lift_full <- p[g_o3 != g_base]
PG("[PG] g_base distribution:")
print(p[, .N, by=.(beta_R05, m4, g_base)][order(g_base)])
PG("[PG] midband months FULL = %d | lifted months = %d", nrow(mid_full), nrow(lift_full))

## ---------- 6. windows ----------
is_idx  <- p$realized_ym >= "2005-01" & p$realized_ym <= "2018-12"
oos_idx <- p$realized_ym >= "2019-01"
res <- list()
for(w in list(list(nm="FULL_269m", ix=rep(TRUE,nrow(p))),
              list(nm="IS_2005_2018", ix=is_idx),
              list(nm="OOS_2019_2026", ix=oos_idx))){
  sub <- p[w$ix]
  for(arm in c("ret_base_u","ret_o3_u","ret_o3_lag")){
    tag <- sprintf("%s__%s", w$nm, arm)
    mm <- metric_set(sub, arm, tag)
    if(arm != "ret_base_u"){
      pt <- nw_t_paired(sub[[arm]], sub$ret_base_u, 3)
      mm[, `:=`(mean_diff_ann=pt["mean_diff_ann"], paired_t=pt["t"])]
    } else mm[, `:=`(mean_diff_ann=0, paired_t=NA_real_)]
    mm[, n_lift := sum(sub$g_o3 != sub$g_base)]
    res[[length(res)+1]] <- mm
    PG("[PG] %s SR=%.4f PORT_t=%.3f paired_t=%s", tag, mm$SR_geo, mm$PORT_t,
       ifelse(is.na(mm$paired_t),"-",sprintf("%.2f",mm$paired_t)))
  }
}
out <- rbindlist(res, fill=TRUE)
fwrite(out, file.path(WD, "o3_transplant_results.csv"))
PG("[PG] DONE saved o3_transplant_results.csv (%d rows)", nrow(out))
print(out[, .(tag, n, SR_geo=round(SR_geo,4), MDD=round(MDD,4), Calmar=round(Calmar,4),
              PORT_t=round(PORT_t,3), IR=round(IR,4),
              d_ann=round(mean_diff_ann,4), paired_t=round(paired_t,3), n_lift)])
