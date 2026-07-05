## ============================================================================
## WT-P20260706_002 FORGE — mega-cap anchor forge-authoritative escalation
## Role: QEPM Forge Agent (pure function). Faithfully implement the published C2
##   composition spec; do NOT alter alpha (score_eff) or the anchor rule.
## Deliverables: independent reproduction of C2 screening + build_bt_result
##   10-component (A=EW-fill, B=LinearTilt) + audit PASS + book-marginal DeltaIR
##   vs REAL incumbent 1.416 (m4xR05 overlay context) + oos band 2/3 + concentration.
## Vintage pin: RAWDATA_pin20260703 (unused here) + pinned_cache/benchmark.parquet.
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(lubridate)
  library(PerformanceAnalytics); library(xts)
})
setDTthreads(1); try(arrow::set_cpu_count(2), silent=TRUE)
set.seed(20260706)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
OUT  <- file.path(ROOT, "qepm/mailbox/worktask/WT-P20260706_002/output")
dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))
COST <- 0.0015; INCUMBENT_IR <- 1.416
PIN_TAG <- "pin20260703 (RAWDATA_pin20260703) + pinned_cache/benchmark.parquet md5=6722b788985cf920b3916a732fdbfd74"

## ---- panels (production alpha score_eff + size/mom) ----
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE)
sp[, score_lag := shift(score_eff,1), by=Ticker]; sp[is.na(score_lag), score_lag := score_eff]
dts <- sort(unique(sp$Date))

## ---- cap-weighted KOSPI200 benchmark (pinned) aligned by beta-scan offset ----
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
best_off<-0; best_cor<--2; for(off in -1:3){ e2<-copy(ew); e2[,key:=format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key"); if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret); if(cc>best_cor){best_cor<-cc;best_off<-off}} }
ew[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
bench <- merge(ew[,.(Date,key)], bmm[,.(key=ym,BM_Ret=bm_ret)], by="key")[,.(Date,BM_Ret)]
PG("[FORGE] benchmark aligned offset=%+d cor=%.3f  n_dates=%d", best_off, best_cor, length(dts))

## ============================================================================
## build_book: returns per-month net return + holdings log (ticker/weight/date)
##   K mega-cap anchors by size(PIT: uses same-month size cross-section; size is
##   a slow-moving cap rank so t vs t-1 equivalent for top-2 — placebo/lag1 test PIT)
##   fill (N-K) by score_eff, weighted:  A="ew" | B="lineartilt" | anti="bottom"
##   | placebo="random"
## ============================================================================
build_book <- function(K, anch_w, N=20L, fill="ew", useScore="eff", seed=1L){
  prevw<-NULL; prevtk<-NULL; prevfill<-NULL
  ret_out <- data.table(Date=dts, ret=NA_real_)
  hold_list <- vector("list", length(dts))
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size)]
    if(nrow(m)<N+2) next
    setorder(m,-size); anch<-if(K>0) m$Ticker[1:K] else character(0)
    ma<-m[!Ticker %in% anch]; nfill<-N-K
    scv <- if(useScore=="lag") ma$score_lag else ma$score_eff
    ord <- switch(fill,
      ew        = order(-scv),
      lineartilt= order(-scv),
      bottom    = order(scv),
      random    = order(((seq_len(nrow(ma))*7919L + i*104729L + seed*1299709L) %% 100000L)))
    sel <- ma[ord][1:nfill]
    sc_sel <- if(useScore=="lag") sel$score_lag else sel$score_eff
    if(fill=="lineartilt"){
      a_t <- sc_sel; names(a_t) <- sel$Ticker
      fw  <- linear_tilt_to_penalty_qd(a_t, lambda=1.5, w_prev=prevfill, phi=3.0, lb=0, ub=0.20)
      fill_total <- 1 - K*anch_w
      tk <- c(anch, names(fw)); w <- c(rep(anch_w,K), as.numeric(fw)*fill_total)
      rr <- c(if(K>0) m[match(anch,Ticker),Ret_1m] else numeric(0),
              sel$Ret_1m[match(names(fw), sel$Ticker)])
      prevfill <- fw
    } else {
      tk <- c(anch, sel$Ticker); w <- c(rep(anch_w,K), rep((1-K*anch_w)/nfill, nfill))
      rr <- c(if(K>0) m[match(anch,Ticker),Ret_1m] else numeric(0), sel$Ret_1m)
    }
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk)
      wc<-ifelse(allt%in%tk,w[match(allt,tk)],0); wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0); wp[is.na(wp)]<-0; turn<-sum(abs(wc-wp)) }
    ret_out$ret[i] <- sum(w*rr) - turn*COST
    hold_list[[i]] <- data.table(Date=D, Ticker=tk, Weight=w,
                                 is_anchor=tk %in% anch, Score=c(if(K>0) rep(NA_real_,K) else numeric(0), sc_sel))
    prevw<-w; prevtk<-tk
  }
  list(ret=ret_out[is.finite(ret)], holdings=rbindlist(hold_list))
}

## ---- NW t of mean (contract-consistent lag-3) ----
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<lag+2) return(NA_real_)
  mu<-mean(x); e<-x-mu; s<-sum(e^2)/n; for(l in 1:lag){w<-1-l/(lag+1); s<-s+2*w*sum(e[(l+1):n]*e[1:(n-l)])/n}
  if(s<=0) return(NA_real_); mu/sqrt(s/n) }
oos_median <- function(act){ n<-length(act)
  median(sapply(c(0.55,0.65,0.75), function(q){cut<-floor(n*q)
    (mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}), na.rm=TRUE) }

## ============================================================================
## STEP 1 — independent reproduction of C2 screening (EW-fill, cap-w bench)
## ============================================================================
repro_screen <- function(K, anch_w, tag){
  bk <- build_book(K, anch_w, 20L, fill="ew")
  pr <- merge(bk$ret, bench, by="Date"); act <- pr$ret - pr$BM_Ret
  prt <- data.table(date=pr$Date, ret_net=pr$ret, frequency="monthly")
  brt <- data.table(date=pr$Date, benchmark_ret=pr$BM_Ret, benchmark_id="KOSPI200")
  bc  <- build_benchmark_compare(prt, brt, tag, tag, annualization_factor=12)
  gv  <- function(n){v<-bc[metric_name==n,active_value]; if(length(v)) as.numeric(v[1]) else NA_real_}
  p2 <- pr[Date>=as.Date("2017-01-01")]; a2<-p2$ret-p2$BM_Ret
  data.table(tag=tag, n=nrow(pr), PORT_t=gv("Portfolio_Alpha_t_NW_lag3"),
    IR=gv("Information_Ratio"), oos_ret=oos_median(act), post2017_t=nw_t(a2))
}
scr <- rbindlist(list(
  repro_screen(0,0.00,"C0_no_anchor"),
  repro_screen(1,0.20,"C1_anchor1"),
  repro_screen(2,0.20,"C2_anchor2"),
  repro_screen(3,0.20,"C3_anchor3")
))
PG("[STEP1 REPRO SCREEN]"); print(scr[,.(tag,PORT_t=round(PORT_t,3),IR=round(IR,3),oos_ret=round(oos_ret,3),post2017_t=round(post2017_t,3))])
fwrite(scr, file.path(OUT,"step1_repro_screen.csv"))

## ============================================================================
## STEP 2 — build_bt_result 10-component AUTHORITATIVE (A=EW-fill, B=LinearTilt)
##   Construct sim_result shape: monthly strategy_xts + DAILY_NAV_DT(monthly grid)
##   + HOLDINGS_LOG + bm_xts. build_period_returns w/ frequency='monthly' keeps
##   apply.monthly(Return.cumulative) identity (returns already monthly).
## ============================================================================
make_sim_result <- function(bk){
  pr <- merge(bk$ret, bench, by="Date"); setorder(pr, Date)
  r_xts  <- xts(pr$ret,  order.by=pr$Date)
  bm_xts <- xts(pr$BM_Ret, order.by=pr$Date)
  nav_net   <- as.numeric(cumprod(1+pr$ret))
  nav_dt <- data.table(Date=pr$Date, NAV=nav_net, NAV_gross=as.numeric(cumprod(1+pr$ret)) )  # gross==net (cost already in ret; contract cum_cost=0)
  hl <- bk$holdings[Date %in% pr$Date]
  hl <- hl[, .(Signal_Date=Date, Ticker=Ticker, Weight=Weight, Score=Score)]
  list(strategy_xts=r_xts, bm_xts=bm_xts, DAILY_NAV_DT=nav_dt,
       HOLDINGS_LOG=split(hl, hl$Signal_Date), PORTFOLIO_LOG=data.table(Signal_Date=pr$Date))
}
spec_common <- list(
  strategy_name="mega_cap_anchor_top2", strategy_type="composition_lever",
  universe="KOSPI200_KOSDAQ150", rebalance="monthly", n_holdings=20L,
  weight_bounds="[0,0.20]", cost_bps=15, benchmark="KOSPI200_capw"
)
build_authoritative <- function(K, anch_w, fill, tag){
  bk <- build_book(K, anch_w, 20L, fill=fill)
  sim <- make_sim_result(bk)
  bt <- build_bt_result(sim, spec_common, run_id=tag, strategy_id=tag,
                        strategy_version="v1.0", benchmark_id="KOSPI200",
                        benchmark_name="KOSPI 200 cap-weighted",
                        transaction_cost_bps=15, slippage_bps=0, risk_free_rate=0,
                        frequency="monthly", annualization_factor=12,
                        universe_id="KOSPI200_KOSDAQ150", code_version="forge_authoritative_WT-P20260706_002",
                        created_by_agent="forge")
  bt <- audit_bt_result(bt)   # returns bt_result with $audit populated + manifest$integrity_status
  integrity <- bt$manifest$integrity_status[1]
  crit <- nrow(bt$audit[severity=="critical" & status=="FAIL"])
  list(bt=bt, audit=list(integrity=integrity, critical_fail_count=crit), bk=bk)
}
gv_bt <- function(bt, name){ v<-bt$benchmark_compare[metric_name==name, active_value]; if(length(v)) as.numeric(v[1]) else NA_real_ }
gm_bt <- function(bt, name){ v<-bt$metrics[metric_name==name, metric_value]; if(length(v)) as.numeric(v[1]) else NA_real_ }

authoritative_summary <- function(res, tag){
  bt <- res$bt
  pr <- data.table(date=bt$period_returns$date, ret=bt$period_returns$ret_net)
  brt <- bt$benchmark_returns[, .(date, benchmark_ret)]
  pr <- merge(pr, brt, by="date"); act <- pr$ret - pr$benchmark_ret
  p2 <- pr[date>=as.Date("2017-01-01")]; a2 <- p2$ret - p2$benchmark_ret
  data.table(tag=tag,
    audit_status = res$audit$integrity,
    audit_critical_fail = res$audit$critical_fail_count,
    PORT_t = gv_bt(bt,"Portfolio_Alpha_t_NW_lag3"),
    IR     = gv_bt(bt,"Information_Ratio"),
    Alpha_ann = gv_bt(bt,"Alpha_Annualized"),
    Beta   = gm_bt(bt,"Sharpe")*0 + as.numeric(bt$benchmark_compare[metric_name=="Beta_to_Benchmark", strategy_value][1]),
    Sharpe = gm_bt(bt,"Sharpe"),
    CAGR   = gm_bt(bt,"CAGR"),
    MDD    = gm_bt(bt,"MDD"),
    Calmar = gm_bt(bt,"Calmar"),
    oos_ret= oos_median(act),
    post2017_t = nw_t(a2),
    n=nrow(pr))
}

A <- build_authoritative(2, 0.20, "ew",         "C2_A_EWfill")
B <- build_authoritative(2, 0.20, "lineartilt", "C2_B_LinearTilt")
C0<- build_authoritative(0, 0.00, "lineartilt", "C0_LT_baseline")   # production-faithful no-anchor baseline
sumA <- authoritative_summary(A,"C2_A_EWfill")
sumB <- authoritative_summary(B,"C2_B_LinearTilt")
sumC0<- authoritative_summary(C0,"C0_LT_baseline")
authsum <- rbindlist(list(sumC0, sumA, sumB), fill=TRUE)
PG("[STEP2 AUTHORITATIVE build_bt_result]"); print(authsum[,.(tag,audit_status,PORT_t=round(PORT_t,3),IR=round(IR,3),Sharpe=round(Sharpe,3),CAGR=round(CAGR,3),MDD=round(MDD,3),Calmar=round(Calmar,3),oos_ret=round(oos_ret,3),post2017_t=round(post2017_t,3))])
fwrite(authsum, file.path(OUT,"step2_authoritative_summary.csv"))
saveRDS(A$bt, file.path(OUT,"bt_result_C2_A_EWfill.rds"))
saveRDS(B$bt, file.path(OUT,"bt_result_C2_B_LinearTilt.rds"))
# CSV export of key components (contract save-lite)
fwrite(A$bt$benchmark_compare, file.path(OUT,"benchmark_compare_C2_A.csv"))
fwrite(B$bt$benchmark_compare, file.path(OUT,"benchmark_compare_C2_B.csv"))
fwrite(A$bt$metrics, file.path(OUT,"metrics_C2_A.csv"))
fwrite(B$bt$metrics, file.path(OUT,"metrics_C2_B.csv"))

## ============================================================================
## STEP 3 — adversarial (placebo random-fill + lag1 PIT + alpha-edge vs bottom)
##   on production-faithful LinearTilt (B) — this is the authoritative fill.
## ============================================================================
port_t_book <- function(bk){ pr<-merge(bk$ret, bench, by="Date"); nw_t(pr$ret - pr$BM_Ret) }
port_t_win  <- function(bk, from){ pr<-merge(bk$ret, bench, by="Date"); pr<-pr[Date>=as.Date(from)]; nw_t(pr$ret - pr$BM_Ret) }
t_B      <- port_t_book(build_book(2,0.20,fill="lineartilt"))
t_bottom <- port_t_book(build_book(2,0.20,fill="bottom"))
t_B17    <- port_t_win(build_book(2,0.20,fill="lineartilt"),"2017-01-01")
t_bot17  <- port_t_win(build_book(2,0.20,fill="bottom"),"2017-01-01")
t_lag1   <- port_t_book(build_book(2,0.20,fill="lineartilt",useScore="lag"))
nullt <- sapply(1:40, function(s) port_t_book(build_book(2,0.20,fill="random",seed=s)))
p_emp <- mean(nullt >= t_B, na.rm=TRUE)
adv <- data.table(t_B_full=t_B, t_bottom_full=t_bottom, alpha_edge_full=t_B-t_bottom,
  t_B_2017=t_B17, t_bottom_2017=t_bot17, alpha_edge_2017=t_B17-t_bot17,
  t_lag1=t_lag1, placebo_null_mean=mean(nullt,na.rm=T), placebo_null_sd=sd(nullt,na.rm=T), placebo_p=p_emp)
PG("[STEP3 ADVERSARIAL] alpha=%.3f bottom=%.3f edge=%.3f | 2017+ edge=%.3f | lag1=%.3f | placebo null=%.3f p=%.3f",
   t_B, t_bottom, t_B-t_bottom, t_B17-t_bot17, t_lag1, mean(nullt,na.rm=T), p_emp)
fwrite(adv, file.path(OUT,"step3_adversarial.csv"))

## ============================================================================
## STEP 4 — DEPLOYMENT book-marginal: (anchor base) x actual m4 x R05 overlay
##   vs REAL incumbent IR=1.416. Both anchored & base-recon get SAME overlay.
##   ΔIR_recon = anchored_overlay_IR - base_recon_overlay_IR (isolates anchor lever)
##   ΔIR_incumbent = anchored_overlay_IR - 1.416 (SPEC gate: >=0.05)
## ============================================================================
ov <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))
ov <- ov[, .(return_ym, regime, ret_orig, m4=m4_weight_lag, r05=beta_R05_V5, ret_L5_V5)]
ov[, ovl := m4 * r05]; ov[, ym_key := return_ym]
chk <- ov[is.finite(ret_orig)&is.finite(ret_L5_V5)]; cc_ov <- cor(chk$ret_orig*chk$ovl, chk$ret_L5_V5)
PG("[STEP4] overlay scalar check cor(ret_orig*ovl, ret_L5_V5)=%.4f", cc_ov)

base_recon <- build_book(0L,0.0,fill="ew")   # EW-fill no-anchor = base for overlay marginal
anchored   <- build_book(2L,0.20,fill="ew")
align_join <- function(bk){ b<-copy(bk$ret); b[,ym:=format(Date,"%Y-%m")]; best<-0; bc<--2
  for(off in -2:2){ b2<-copy(b); b2[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(off),"%Y-%m")]
    mm<-merge(b2, ov[,.(key=ym_key, ret_orig)], by="key"); if(nrow(mm)>100){c2<-cor(mm$ret,mm$ret_orig); if(c2>bc){bc<-c2;best<-off}} }
  list(off=best, cor=bc) }
aj <- align_join(base_recon); OFF <- aj$off
mapov <- function(bk){ b<-copy(bk$ret); b[,ym:=format(Date,"%Y-%m")]; b[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(OFF),"%Y-%m")]
  merge(b, ov[,.(key=ym_key, ovl, regime)], by="key") }
Bd <- mapov(base_recon); Ad <- mapov(anchored)
Bd[, ret_ov := ret*ovl]; Ad[, ret_ov := ret*ovl]
bm2 <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm2[,Date:=as.Date(Date)]
bm2 <- bm2[is.finite(BM_Ret)]; bm2[,ym:=format(Date,"%Y-%m")]; bmm2<-bm2[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
addbm <- function(X) merge(X, bmm2[,.(key=ym, BM_Ret=bm_ret)], by="key")
Bd<-addbm(Bd); Ad<-addbm(Ad); setorder(Bd,key); setorder(Ad,key)

ov_gates <- function(X){ r<-X$ret_ov; d<-as.Date(paste0(X$key,"-01")); x<-xts(r,order.by=d)
  sr<-mean(r)/sd(r)*sqrt(12); cagr<-as.numeric(Return.annualized(x,scale=12)); mdd<-as.numeric(maxDrawdown(x)); calmar<-cagr/mdd
  act<-r-X$BM_Ret; ir<-mean(act)/sd(act)*sqrt(12); pt<-nw_t(act); oos<-oos_median(act)
  p2<-X[as.Date(paste0(key,"-01"))>=as.Date("2017-01-01")]; a2<-p2$ret_ov-p2$BM_Ret
  list(SR=sr,CAGR=cagr,MDD=mdd,Calmar=calmar,IR=ir,PORT_t=pt,oos=oos,post2017_t=nw_t(a2), act=act) }
gB<-ov_gates(Bd); gA<-ov_gates(Ad)
mrg<-merge(Ad[,.(key, aA=ret_ov-BM_Ret)], Bd[,.(key, aB=ret_ov-BM_Ret)], by="key")
paired_t <- nw_t(mrg$aA - mrg$aB)
dIR_recon <- gA$IR - gB$IR
dIR_incumbent <- gA$IR - INCUMBENT_IR
ovres <- data.table(
  book=c("base_recon+overlay","anchored+overlay(candidate)","INCUMBENT(book_state)"),
  SR=c(gB$SR,gA$SR,NA), CAGR=c(gB$CAGR,gA$CAGR,NA), MDD=c(gB$MDD,gA$MDD,NA),
  Calmar=c(gB$Calmar,gA$Calmar,NA), IR=c(gB$IR,gA$IR,INCUMBENT_IR),
  PORT_t=c(gB$PORT_t,gA$PORT_t,NA), oos=c(gB$oos,gA$oos,NA), post2017_t=c(gB$post2017_t,gA$post2017_t,NA))
PG("[STEP4 DEPLOYMENT overlay book]"); print(ovres)
PG("[STEP4] align off=%+d cor=%.3f | anchored_overlay_IR=%.3f", OFF, aj$cor, gA$IR)
PG("[STEP4] ΔIR vs base_recon=%.4f (anchor lever, paired NW-t=%.3f)", dIR_recon, paired_t)
PG("[STEP4] ΔIR vs INCUMBENT 1.416 = %.4f (SPEC GATE >=0.05: %s)", dIR_incumbent, dIR_incumbent>=0.05)
fwrite(ovres, file.path(OUT,"step4_overlay_book.csv"))

## ============================================================================
## STEP 5 — concentration / mega-cap regime-reversal stress
## ============================================================================
hlA <- A$bk$holdings
anch_w_realized <- hlA[is_anchor==TRUE, .(anchor_wt=sum(Weight)), by=Date]
top1_share <- hlA[, .(mx=max(Weight)), by=Date]
# HHI per month
hhi <- hlA[, .(HHI=sum(Weight^2)), by=Date]
# stress: anchors -20% simultaneously (approx one-month shock) — impact on that month's port return
pr_full <- merge(A$bk$ret, bench, by="Date")
stress_months <- hlA[is_anchor==TRUE][, .(anchor_wt=sum(Weight)), by=Date]
# mega-cap crash contribution: anchor_wt * (-0.20)
stress_impact <- mean(stress_months$anchor_wt) * (-0.20)
conc <- data.table(
  mean_anchor_weight=mean(anch_w_realized$anchor_wt),
  max_anchor_weight=max(anch_w_realized$anchor_wt),
  mean_top1_weight=mean(top1_share$mx),
  mean_HHI=mean(hhi$HHI),
  mean_effective_N=mean(1/hhi$HHI),
  stress_2anchor_minus20pct_month_impact=stress_impact)
PG("[STEP5 CONCENTRATION] mean_anchor_wt=%.3f HHI=%.3f effN=%.1f stress(-20%% both)=%.3f",
   conc$mean_anchor_weight, conc$mean_HHI, conc$mean_effective_N, conc$stress_2anchor_minus20pct_month_impact)
fwrite(conc, file.path(OUT,"step5_concentration.csv"))

## ---- save consolidated ----
saveRDS(list(scr=scr, authsum=authsum, adv=adv, ovres=ovres, conc=conc,
  book_marginal=list(dIR_recon=dIR_recon, dIR_incumbent=dIR_incumbent, paired_t=paired_t,
    align_off=OFF, align_cor=aj$cor, overlay_check=cc_ov),
  pin_tag=PIN_TAG), file.path(OUT,"forge_consolidated.rds"))
PG("[FORGE DONE] all steps complete.")
