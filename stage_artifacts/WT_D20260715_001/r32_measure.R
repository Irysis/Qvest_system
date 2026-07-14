## ============================================================================
## R32 (FQ-048, WT-D20260715_001) — 밸류 추가가 실제 PG2 북(M4xR05 오버레이 적용)의
##   최종 배포 성과를 강화하는가. 3-arm 대칭 비교 (오버레이 동일 적용).
## PURE FUNCTION: 3-package/production READ-ONLY. stage_artifacts/WT_D20260715_001만 write.
## base authority = §7b production-parity clean 0_ic_S7 (spearman=1.0 vs production score).
## metrics = build_metrics/build_benchmark_compare (contract, PerformanceAnalytics, ann=12).
## ============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(lubridate)
  library(PerformanceAnalytics); library(xts); library(sandwich); library(lmtest)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260715_001")
source(file.path(QM,"02_Infrastructure/contracts/weighted_screen_bt.R"))
source(file.path(QM,"02_Infrastructure/contracts/backtest_result_contract.R"))

save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
## production STR_1715 construction (forward_weights_R05_noLayer4.R VERBATIM): N20, LAMBDA 1.5, cap 0.20
N_TARGET<-20L; LAMBDA<-1.5; UB<-0.20
.norm <- function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt <- function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0));z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}
cap_norm<-function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<8)return(NA_real_);fit<-lm(x~1)
  se<-sqrt(NeweyWest(fit,lag=lag,prewhite=FALSE)[1,1]);unname(coef(fit)[1]/se)}
IR_ann<-function(v){v<-v[is.finite(v)];if(length(v)<6)return(NA_real_);s<-sd(v);if(!is.finite(s)||s<=0)return(NA_real_);mean(v)/s*sqrt(12)}
oos3<-function(a,frac=c(0.55,0.65,0.75)){a<-a[is.finite(a)];n<-length(a);if(n<24)return(NA_real_)
  sr<-function(x){if(length(x)<6)return(NA_real_);s<-sd(x);if(!is.finite(s)||s<=0)return(NA_real_);mean(x)/s*sqrt(12)}
  r<-sapply(frac,function(f){k<-floor(n*f);if(k<6||(n-k)<6)return(NA_real_);is<-sr(a[1:k]);oo<-sr(a[(k+1):n])
    if(is.na(is)||is.na(oo)||is<=0)return(NA_real_);oo/is}); if(all(is.na(r)))NA_real_ else median(r,na.rm=TRUE)}
W_BLEND <- 0.30; COST <- 0.0015

## ---- 1. inputs (all frozen 07-14 clean off0 + production CSV) ----
PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
VP  <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_005/value_panels.parquet"))); VP[,Date:=as.Date(Date)]
SI  <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE
FR <- fwd_ret[,.(Date,Ticker,Ret_1m)]
## production overlay scalars (noLayer4 canonical)
PCSV <- fread(file.path(QM,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
PCSV[,anchor_date:=as.Date(anchor_date)]; setorder(PCSV,realized_ym)
OVL <- PCSV[,.(realized_ym, anchor_date, m4, beta_R05, ret_orig)]
OVL[, exposure := m4*beta_R05]
OVL[, dR05 := abs(beta_R05 - shift(beta_R05,1,fill=1.0))]
cat(sprintf("[inputs] PAN %d rows/%d months | VP %d | OVL %d months (%s..%s)\n",
  nrow(PAN),uniqueN(PAN$Date),nrow(VP),nrow(OVL),min(OVL$realized_ym),max(OVL$realized_ym)))

## base score = 0_ic_S7 (production-parity exact). merge value.
DT <- merge(PAN[,.(Date,Ticker,base=`0_ic_S7`)], VP[,.(Date,Ticker,vz_off0)], by=c("Date","Ticker"), all.x=TRUE)
## tier from SIZE (monthly cap_rank)
ST <- SIZE[!is.na(Size),.(Date,Ticker,Size)]; setorder(ST,Date,-Size); ST[,cap_rank:=seq_len(.N),by=Date]
ST[,tier:=fifelse(cap_rank<=10L,"MEGA",fifelse(cap_rank<=30L,"MID","OTHER"))]
DT <- merge(DT, ST[,.(Date,Ticker,Size,tier)], by=c("Date","Ticker"), all.x=TRUE); DT[is.na(tier),tier:="OTHER"]

## ---- 2. build 3 arm scores ----
DT[is.finite(base), b_z := zc(base), by=Date]
DT[, v_z := zc(vz_off0), by=Date]; DT[is.na(v_z), v_z := 0]
DT[, v_boost := fifelse(tier %in% c("MID","OTHER"), v_z, 0)]
DT[, sc_arm0 := base]                                  # baseline (raw base score)
DT[, sc_arm1 := (1-W_BLEND)*b_z + W_BLEND*v_boost]     # B2 non-mega tier-conditional
DT[, sc_arm2 := (1-W_BLEND)*b_z + W_BLEND*v_z]         # Z6 z-blend all tiers

## ---- 3. PRIMARY = production N20 λ1.5 tilt (§7b-faithful). cap-w top-25 = secondary cross-check ----
mk_tilt <- function(scorecol){   # production STR_1715 construction (N20, λ1.5, cap0.20)
  S <- DT[is.finite(get(scorecol)),.(Date,Ticker,Size,sc=get(scorecol))]
  S <- merge(S, liqf[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE); S <- S[is.na(adv)|adv>=2e8]
  dd<-sort(unique(S$Date)); W<-list()
  for(i in seq_along(dd)){d<-dd[i];sub<-S[Date==d];if(nrow(sub)<N_TARGET)next;setorder(sub,-sc)
    hd<-head(sub,N_TARGET); w<-.tilt(hd$sc); W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=w)}
  rbindlist(W)}
mk_capw <- function(scorecol){    # secondary: cap-w top-25 (value arc graduation basis §2)
  S <- DT[is.finite(get(scorecol)),.(Date,Ticker,Size,sc=get(scorecol))]
  S <- merge(S, liqf[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE); S <- S[is.na(adv)|adv>=2e8]
  dd<-sort(unique(S$Date)); W<-list()
  for(i in seq_along(dd)){d<-dd[i];sub<-S[Date==d];if(nrow(sub)<25)next;setorder(sub,-sc);hd<-head(sub,25)
    W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=cap_norm(hd$Size))}
  rbindlist(W)}

## ---- 4. base return (weighted_screen_bt, pre-overlay) + overlay application ----
## d0 (decision month-end) -> production realized_ym. Production row[realized_ym=X] stores return
## realized over month X-1 (anchor=X start, "realized_ym=직전 리밸 종료 기간"). My ret_base at d0
## = forward return over month(d0)+1. So join to production realized_ym = month(d0)+2. (diag lag+1 confirm)
ym_of <- function(d) format(as.Date(d) %m+% months(2), "%Y-%m")

build_arm <- function(scorecol, tag, weighter=mk_tilt){
  W <- weighter(scorecol)
  bt <- weighted_screen_bt(W, FR, bench, cost_bps_oneway=15, run_id=tag, strategy_id=tag)
  pr <- as.data.table(bt$period_returns)          # date(d0), ret_net(base), benchmark_ret
  pr[, realized_ym := ym_of(date)]
  m <- merge(pr, OVL[,.(realized_ym,exposure,dR05,ret_orig,anchor_date)], by="realized_ym")
  setorder(m, date)
  ## overlay applied (production noL4 formula): ret_ovl = exposure*ret_base - dR05*15bps
  m[, ret_base := ret_net]
  m[, ret_ovl := exposure*ret_base - dR05*COST]
  m[, active_base := ret_base - benchmark_ret]
  m[, active_ovl  := ret_ovl  - benchmark_ret]
  ## turnover (base) for reporting
  list(tag=tag, W=W, m=m, turnover_annual=bt$turnover_annual)
}

cat("\n===== building 3 arms =====\n")
A0 <- build_arm("sc_arm0","R32_arm0_baseline")
A1 <- build_arm("sc_arm1","R32_arm1_B2value")
A2 <- build_arm("sc_arm2","R32_arm2_Z6value")
cat(sprintf("[arms] n_months: arm0=%d arm1=%d arm2=%d\n", nrow(A0$m),nrow(A1$m),nrow(A2$m)))

## ---- 5. §7b parity: arm0 base ret_net vs production ret_orig ----
pm <- A0$m[, .(realized_ym, date, ret_base, ret_orig, benchmark_ret)]
pm <- pm[is.finite(ret_base) & is.finite(ret_orig)]
par_corr <- cor(pm$ret_base, pm$ret_orig)
par_sr_recon <- mean(pm$ret_base)/sd(pm$ret_base)*sqrt(12)
par_sr_prod  <- mean(pm$ret_orig)/sd(pm$ret_orig)*sqrt(12)
par_mean_diff <- mean(pm$ret_base - pm$ret_orig)
cat(sprintf("\n===== §7b PARITY (arm0 base recon vs production ret_orig) =====\n"))
cat(sprintf("  n=%d | Pearson corr=%.4f | SR_recon(top25 capw)=%.4f | SR_prod(N20 tilt)=%.4f | mean monthly diff=%.5f\n",
  nrow(pm), par_corr, par_sr_recon, par_sr_prod, par_mean_diff))
parity_stop <- (!is.finite(par_corr)) || (par_corr < 0.90) || (sign(par_sr_recon)!=sign(par_sr_prod))
cat(sprintf("  parity verdict: %s (corr>=0.90 & 부호정합 필요)\n", if(parity_stop) "*** STOP/REVIEW ***" else "PASS (construction convention 잔차 허용)"))

## ---- 6. contract 10-component metrics per arm (overlay applied = primary) ----
mk_metrics <- function(m, tag, series_col){
  d <- m$date; r <- m[[series_col]]; bmr <- m$benchmark_ret
  RID<-tag; SID<-tag
  pr <- data.table(run_id=RID, strategy_id=SID, date=d, frequency="monthly",
    ret_gross=r, ret_net=r, risk_free_ret=0, excess_ret_net=r,
    turnover=NA_real_, cost_ret=0, cash_weight=NA_real_, leverage=NA_real_, n_holdings=25L)
  br <- data.table(benchmark_id="KOSPI200_KQ150_capw", benchmark_name="KOSPI200 union KOSDAQ150 cap-w",
    date=d, benchmark_ret=bmr, benchmark_nav=cumprod(1+ifelse(is.na(bmr),0,bmr)),
    risk_free_ret=0, benchmark_excess_ret=bmr, frequency="monthly")
  nav_v <- cumprod(1+r); dd_v <- nav_v/cummax(nav_v)-1
  nav_tbl <- data.table(run_id=RID, strategy_id=SID, date=d, nav_gross=nav_v, nav_net=nav_v, drawdown=dd_v)
  hold_tbl <- data.table(matrix(nrow=0, ncol=length(HOLDINGS_COLS), dimnames=list(NULL,HOLDINGS_COLS)))
  met <- build_metrics(nav_tbl, pr, hold_tbl, RID, SID, frequency="monthly", annualization_factor=12)
  bc  <- build_benchmark_compare(pr, br, RID, SID, annualization_factor=12)
  draws <- build_drawdowns(pr, br, RID, SID)
  gv<-function(dt,mn){v<-dt[metric_name==mn]$metric_value; if(length(v))v[1] else NA_real_}
  gvb<-function(mn,col){v<-bc[metric_name==mn][[col]]; if(length(v))v[1] else NA_real_}
  SR_geo <- as.numeric(table.AnnualizedReturns(xts(r,order.by=d),scale=12)[3,1])
  list(pr=pr, br=br, nav=nav_tbl, metrics=met, bc=bc, draws=draws,
       SR_arith=gv(met,"Sharpe"), SR_geo=SR_geo, CAGR=gv(met,"CAGR"), MDD=gv(met,"MDD"),
       Calmar=gv(met,"Calmar"), AnnVol=gv(met,"Annualized_Volatility"),
       PORT_t=gvb("Portfolio_Alpha_t_NW_lag3","strategy_value"),
       IR=gvb("Information_Ratio","active_value"), alpha_ann=gvb("Alpha_Annualized","strategy_value"),
       beta=gvb("Beta_to_Benchmark","strategy_value"), nav_v=nav_v, dd_v=dd_v)
}
cat("\n===== contract metrics (OVERLAY APPLIED — primary) =====\n")
M0 <- mk_metrics(A0$m,"R32_arm0_baseline","ret_ovl")
M1 <- mk_metrics(A1$m,"R32_arm1_B2value","ret_ovl")
M2 <- mk_metrics(A2$m,"R32_arm2_Z6value","ret_ovl")
## base (pre-overlay) context metrics
B0 <- mk_metrics(A0$m,"R32_arm0_base_preovl","ret_base")
B1 <- mk_metrics(A1$m,"R32_arm1_base_preovl","ret_base")
B2 <- mk_metrics(A2$m,"R32_arm2_base_preovl","ret_base")

fmt_row <- function(tag, M, ovl){
  data.table(arm=tag, overlay=ovl, n=nrow(M$pr), SR_geo=M$SR_geo, SR_arith=M$SR_arith,
    CAGR=M$CAGR, MDD=M$MDD, Calmar=M$Calmar, AnnVol=M$AnnVol, PORT_t=M$PORT_t, IR=M$IR,
    alpha_ann=M$alpha_ann, beta=M$beta)}
TAB <- rbind(
  fmt_row("arm0_baseline", M0, "applied"), fmt_row("arm1_B2value", M1, "applied"), fmt_row("arm2_Z6value", M2, "applied"),
  fmt_row("arm0_baseline", B0, "pre"),     fmt_row("arm1_B2value", B1, "pre"),     fmt_row("arm2_Z6value", B2, "pre"))
cat("\n----- 3-ARM COMPARISON TABLE -----\n")
print(TAB[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])

## ---- 7. book-marginal delta_IR (overlay-applied net-active recon IR, window-matched) ----
## window-match on common realized_ym across arms (identical by construction, but enforce)
cmn <- Reduce(intersect, list(A0$m$realized_ym, A1$m$realized_ym, A2$m$realized_ym))
ma0 <- A0$m[realized_ym %in% cmn][order(realized_ym)]
ma1 <- A1$m[realized_ym %in% cmn][order(realized_ym)]
ma2 <- A2$m[realized_ym %in% cmn][order(realized_ym)]
ir0 <- IR_ann(ma0$active_ovl); ir1 <- IR_ann(ma1$active_ovl); ir2 <- IR_ann(ma2$active_ovl)
dIR1 <- ir1-ir0; dIR2 <- ir2-ir0
## paired NW-t of active differential (arm - arm0), overlay applied
pt_d1 <- nw_t(ma1$active_ovl - ma0$active_ovl); pt_d2 <- nw_t(ma2$active_ovl - ma0$active_ovl)
## realized active corr (overlay) vs baseline
ac1 <- cor(ma1$active_ovl, ma0$active_ovl); ac2 <- cor(ma2$active_ovl, ma0$active_ovl)
cat(sprintf("\n===== BOOK-MARGINAL (overlay-applied, window-matched n=%d) =====\n", length(cmn)))
cat(sprintf("  IR: arm0=%.4f arm1=%.4f arm2=%.4f | dIR1(B2)=%+.4f dIR2(Z6)=%+.4f\n", ir0,ir1,ir2,dIR1,dIR2))
cat(sprintf("  paired active-diff NW-t vs arm0: B2=%.3f Z6=%.3f | active-corr vs arm0: B2=%.4f Z6=%.4f\n", pt_d1,pt_d2,ac1,ac2))

## ---- 8. risk-axis: drawdown episode decomposition (single-episode check) ----
dd_episodes <- function(m, tag){
  d <- m$date; r <- m$ret_ovl; nav <- cumprod(1+r); dd <- nav/cummax(nav)-1
  ## COVID window (2020-02..2020-05) worst dd
  covid <- min(dd[d>=as.Date("2020-02-01") & d<=as.Date("2020-06-30")], na.rm=TRUE)
  mdd <- min(dd); mdd_date <- d[which.min(dd)]
  ## 2024+ (recency, value reversal window)
  rec_dd <- min(dd[d>=as.Date("2024-01-01")], na.rm=TRUE)
  data.table(arm=tag, MDD=mdd, MDD_date=as.character(mdd_date),
    COVID_2020_dd=covid, recency_2024plus_dd=rec_dd)}
DDE <- rbind(dd_episodes(A0$m,"arm0"), dd_episodes(A1$m,"arm1"), dd_episodes(A2$m,"arm2"))
cat("\n===== DRAWDOWN EPISODE DECOMP (overlay applied) =====\n"); print(DDE[, lapply(.SD,function(x) if(is.numeric(x))round(x,4) else x)])

## ---- 9. save ----
save_safe(TAB, file.path(WT,"comparison_table.parquet"), write_parquet)
save_safe(DDE, file.path(WT,"drawdown_episodes.parquet"), write_parquet)
OUT <- list(
  parity=list(n=nrow(pm), corr=par_corr, sr_recon=par_sr_recon, sr_prod=par_sr_prod,
    mean_diff=par_mean_diff, stop=parity_stop),
  table=TAB, dd_episodes=DDE,
  book_marginal=list(ir0=ir0,ir1=ir1,ir2=ir2,dIR_B2=dIR1,dIR_Z6=dIR2,
    paired_t_B2=pt_d1,paired_t_Z6=pt_d2,active_corr_B2=ac1,active_corr_Z6=ac2,n=length(cmn)),
  turnover=list(arm0=A0$turnover_annual,arm1=A1$turnover_annual,arm2=A2$turnover_annual),
  prod_noL4_ref=list(SR_geo=1.898,Calmar=1.943,MDD=0.2329,CAGR=0.4526,PORT_t=6.214,note="different bench+construction (context only)"))
saveRDS(OUT, file.path(WT,"r32_results.rds"))
## per-arm nav for charts
navdt <- data.table(date=A0$m$date,
  arm0_ovl=cumprod(1+A0$m$ret_ovl), arm1_ovl=cumprod(1+A1$m$ret_ovl), arm2_ovl=cumprod(1+A2$m$ret_ovl),
  bench=cumprod(1+ifelse(is.na(A0$m$benchmark_ret),0,A0$m$benchmark_ret)),
  arm0_dd=M0$dd_v, arm1_dd=M1$dd_v, arm2_dd=M2$dd_v)
save_safe(navdt, file.path(WT,"nav_series.parquet"), write_parquet)
saveRDS(list(A0=A0$m,A1=A1$m,A2=A2$m), file.path(WT,"arm_series.rds"))
cat("\nR32_MEASURE_DONE\n")
