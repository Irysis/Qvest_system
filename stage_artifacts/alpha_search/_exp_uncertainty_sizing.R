## ============================================================
## EXPERIMENT: STR_1715 consensus core + uncertainty-aware sizing
## Optimizer-research (sizing-only; STR_1715 frozen). Measurement-only.
## μ̃ = μ̂ − k·SE(μ̂),  SE from cross-sleeve disagreement (PIT-safe)
## ============================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(PerformanceAnalytics); library(xts)
})
options(warn=1)
BASE <- "G:/Quant_Module_Moltbot"
PROD <- file.path(BASE,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe")
OUT  <- file.path(BASE,"stage_artifacts/alpha_search")

## ---- Load alpha scores (per-stock per-month consensus) ----
a <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_str1715_268m.parquet")))
# r05 panel has confidence column
r05 <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_r05_panel.parquet")))
a <- merge(a, r05[,.(Date,Ticker,confidence)], by=c("Date","Ticker"), all.x=TRUE)
setkey(a, Date, Ticker)

## ---- Load RAWDATA + benchmark ----
raw <- as.data.table(read_parquet(file.path(BASE,".cache/rawdata.parquet"),
        col_select=c("Date","Ticker","Close","Vol","Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
bm <- as.data.table(read_parquet(file.path(BASE,".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; setorder(bm, Date)

sig_dates <- sort(unique(a[!is.na(score_eff), Date]))
cat(sprintf("sig_dates: %d (%s ~ %s)\n", length(sig_dates),
            as.character(min(sig_dates)), as.character(max(sig_dates))))

## ---- baseline sizing functions (EXACT copy from production run_all.R) ----
normalize_long_only <- function(w, lb=0, ub=0.20, target_sum=1, max_iter=50){
  w[!is.finite(w)] <- 0; w[w<lb] <- lb; w[w>ub] <- ub
  s <- sum(w); if(s<=1e-12){ n<-length(w); return(rep(target_sum/n,n)) }
  w <- w*(target_sum/s)
  for(k in seq_len(max_iter)){
    over <- w>ub+1e-12; if(!any(over)) break
    excess <- sum(w[over]-ub); w[over] <- ub
    free <- which(!over & w>lb+1e-12)
    if(length(free)==0){ w <- w*(target_sum/sum(w)); break }
    w[free] <- w[free]+excess*(w[free]/sum(w[free]))
  }
  w/sum(w)*target_sum
}
linear_tilt_qd <- function(alpha_t, lambda=1.0, lb=0, ub=0.20){
  N <- length(alpha_t); if(N<=1) return(rep(1,N))
  r <- rank(alpha_t, ties.method="average")
  centered <- (r-mean(r))/(N-1)
  w_raw <- pmax(1+lambda*2*centered, 1e-6)
  w <- w_raw/sum(w_raw)
  normalize_long_only(w, lb=lb, ub=ub, target_sum=1)
}
linear_tilt_to_penalty_qd <- function(alpha_t, lambda=1.5, w_prev=NULL, phi=3.0, lb=0, ub=0.20){
  w_tilt <- linear_tilt_qd(alpha_t, lambda=lambda, lb=lb, ub=ub); names(w_tilt) <- names(alpha_t)
  if(is.null(w_prev)||phi<=0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev)); wp[common] <- w_prev[common]
  dropped <- 1-sum(wp); if(dropped>0) wp <- wp+dropped*w_tilt
  if(sum(wp)>0) wp <- wp/sum(wp)
  blend <- phi/(1+phi); w_out <- blend*wp+(1-blend)*w_tilt
  normalize_long_only(w_out, lb=lb, ub=ub, target_sum=1)
}

LIQ <- 2e8; BPS <- 15; MAXN <- 20L; MINN <- 15L; UB <- 0.20
LAMBDA <- 1.5; TOPHI <- 3.0

## ---- core walk-forward engine, sizing_mode parameterised ----
## sizing_mode: "baseline" | "uncertainty" with k
## se_kind: "sleeve" (cross-sleeve disagreement) | "confidence"
run_wf <- function(sizing_mode="baseline", k=0.0, se_kind="sleeve"){
  res <- vector("list", length(sig_dates)-1L)
  w_prev <- NULL
  for(i in seq_len(length(sig_dates)-1L)){
    sig_label <- sig_dates[i]; next_label <- sig_dates[i+1L]
    start_d <- suppressWarnings(min(raw[Date>=sig_label]$Date))
    if(!is.finite(start_d)) next
    nxt <- suppressWarnings(min(raw[Date>=next_label]$Date))
    end_d <- if(is.finite(nxt)) nxt else max(raw$Date)

    panel <- a[Date==sig_label & !is.na(score_eff)]
    if(nrow(panel)==0L) next
    setorder(panel, -score_eff)
    Nelig <- nrow(panel); Nt <- min(MAXN, Nelig)
    if(Nt<MINN && Nelig>=MINN) Nt <- MINN
    if(Nt<5L) next
    picks <- panel[seq_len(Nt)]
    tk <- picks$Ticker
    alpha_t <- picks$score_eff; names(alpha_t) <- tk

    ## uncertainty-aware adjustment of the SCORE used for sizing (sizing-only)
    if(sizing_mode=="uncertainty" && k>0){
      if(se_kind=="sleeve"){
        # cross-sleeve disagreement: SE of the 2-component consensus mean
        se <- abs(picks$score_core_z - picks$score_defense_z)/sqrt(2)
        se[!is.finite(se)] <- 0
        # standardise SE cross-sectionally so k is comparable to score units
        se_z <- (se - mean(se, na.rm=TRUE)); sds <- sd(se, na.rm=TRUE)
        if(is.finite(sds) && sds>0) se_z <- se_z/sds else se_z <- se*0
        alpha_t <- alpha_t - k*se_z
      } else if(se_kind=="confidence"){
        # lower confidence => larger SE; SE proxy = (1-confidence)
        cf <- picks$confidence; cf[!is.finite(cf)] <- mean(cf,na.rm=TRUE)
        se <- (1-cf); se_z <- (se-mean(se,na.rm=TRUE)); sds <- sd(se,na.rm=TRUE)
        if(is.finite(sds)&&sds>0) se_z <- se_z/sds else se_z <- se*0
        alpha_t <- alpha_t - k*se_z
      }
      names(alpha_t) <- tk
    }

    ## liquidity PIT t-30..t-1
    lw0 <- start_d-30L
    liq <- raw[Date>=lw0 & Date<start_d, .(A=mean(TradingAmt,na.rm=TRUE)), by=Ticker]
    lqtk <- liq[A>=LIQ, Ticker]
    tkl <- intersect(tk, lqtk); if(length(tkl)<5L) tkl <- tk
    alpha_l <- alpha_t[tkl]; if(length(alpha_l)<5L) next

    w_raw <- tryCatch(linear_tilt_to_penalty_qd(alpha_l, lambda=LAMBDA, w_prev=w_prev, phi=TOPHI, lb=0, ub=UB),
                      error=function(e) linear_tilt_qd(alpha_l, lambda=LAMBDA, lb=0, ub=UB))
    names(w_raw) <- names(alpha_l)
    w <- normalize_long_only(w_raw, lb=0, ub=UB, target_sum=1)

    ## period returns
    pd <- raw[Date>start_d & Date<=end_d, .(Date,Ticker,Ret)]
    if(nrow(pd)==0L) next
    sr <- pd[, .(sret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    mg <- merge(data.table(ticker=names(w), wt=as.numeric(w)), sr, by.x="ticker", by.y="Ticker", all.x=TRUE)
    mg[is.na(sret), sret:=0]
    port_gross <- sum(mg$wt*mg$sret, na.rm=TRUE)

    ## turnover (round-trip /2)
    if(is.null(w_prev)||length(w_prev)==0L){ to <- 1.0 } else {
      an <- union(names(w), names(w_prev))
      wa <- setNames(rep(0,length(an)),an); wpa <- setNames(rep(0,length(an)),an)
      wa[names(w)] <- w; wpa[names(w_prev)] <- w_prev
      to <- sum(abs(wa-wpa))/2
    }
    cost <- (BPS/1e4)*to*2   # round-trip ×2 (one-way 15bps both legs), NOT ×12
    port_net <- port_gross - cost

    ## benchmark return over the SAME period
    bsub <- bm[Date>start_d & Date<=end_d]
    bm_ret <- if(nrow(bsub)>0) prod(1+bsub$BM_Ret, na.rm=TRUE)-1 else 0

    res[[i]] <- data.table(period_end=end_d, port_net=port_net, port_gross=port_gross,
                           bm_ret=bm_ret, turnover=to, n=nrow(mg))
    w_prev <- w
  }
  out <- rbindlist(res, use.names=TRUE, fill=TRUE)
  out <- out[!is.na(port_net)]; setorder(out, period_end)
  out
}

## ---- metrics via PerformanceAnalytics (no self-synthesis) ----
metrics_of <- function(dt, label){
  if(nrow(dt)<12) return(NULL)
  rx <- xts(dt$port_net, order.by=as.Date(dt$period_end))
  bx <- xts(dt$bm_ret,  order.by=as.Date(dt$period_end))
  ax <- rx - bx   # active series
  sr_tot <- as.numeric(SharpeRatio.annualized(rx, Rf=0, scale=12))
  sr_act <- as.numeric(SharpeRatio.annualized(ax, Rf=0, scale=12))
  cagr   <- as.numeric(Return.annualized(rx, scale=12))
  mdd    <- as.numeric(maxDrawdown(rx))
  calmar <- if(mdd>0) cagr/mdd else NA_real_
  list(label=label, n=nrow(dt), sr_total=sr_tot, sr_active=sr_act,
       cagr=cagr, mdd=mdd, calmar=calmar,
       ann_to=mean(dt$turnover,na.rm=TRUE)*12,
       mean_to_perperiod=mean(dt$turnover,na.rm=TRUE))
}

split_report <- function(dt, name){
  full <- metrics_of(dt, paste0(name,"_FULL"))
  # DPL window OOS = 2010-2023; IS = pre-2010
  is_dpl  <- dt[period_end <  as.Date("2010-01-01")]
  oos_dpl <- dt[period_end >= as.Date("2010-01-01") & period_end <= as.Date("2023-12-31")]
  # early/late split (oos_retention) — first half vs second half of FULL
  mid <- dt$period_end[ceiling(nrow(dt)/2)]
  early <- dt[period_end<=mid]; late <- dt[period_end>mid]
  m_is  <- metrics_of(is_dpl, paste0(name,"_IS_pre2010"))
  m_oos <- metrics_of(oos_dpl, paste0(name,"_OOS_2010_2023"))
  m_e   <- metrics_of(early, paste0(name,"_EARLY"))
  m_l   <- metrics_of(late,  paste0(name,"_LATE"))
  # oos_retention: late active SR / early active SR (active basis, like dpl eval used total)
  ret_act <- if(!is.null(m_e)&&!is.null(m_l)&&m_e$sr_active!=0) m_l$sr_active/m_e$sr_active else NA
  ret_tot <- if(!is.null(m_e)&&!is.null(m_l)&&m_e$sr_total!=0) m_l$sr_total/m_e$sr_total else NA
  list(full=full, is=m_is, oos=m_oos, early=m_e, late=m_l,
       oos_retention_active=ret_act, oos_retention_total=ret_tot)
}

## ===== RUN =====
cat("\n===== BASELINE (linear tilt) =====\n")
base_dt <- run_wf("baseline")
base_rep <- split_report(base_dt, "baseline")
saveRDS(list(dt=base_dt, rep=base_rep), file.path(OUT,"_exp_baseline.rds"))

pr <- function(m){ if(is.null(m)){cat("  (insufficient)\n");return(invisible())}
  cat(sprintf("  %-26s n=%3d | SR_tot=%.4f SR_act=%.4f CAGR=%.4f MDD=%.4f Calmar=%.3f TO=%.2f\n",
      m$label,m$n,m$sr_total,m$sr_active,m$cagr,m$mdd,ifelse(is.na(m$calmar),-99,m$calmar),m$ann_to)) }
pr(base_rep$full); pr(base_rep$is); pr(base_rep$oos); pr(base_rep$early); pr(base_rep$late)
cat(sprintf("  oos_retention(active)=%.4f  oos_retention(total)=%.4f\n",
            base_rep$oos_retention_active, base_rep$oos_retention_total))

## ===== uncertainty sweep =====
ks <- c(0.5,1.0,1.5,2.0)
sweep <- list()
for(se_kind in c("sleeve","confidence")){
  for(k in ks){
    tag <- sprintf("unc_%s_k%.1f", se_kind, k)
    cat(sprintf("\n===== %s =====\n", tag))
    dt <- run_wf("uncertainty", k=k, se_kind=se_kind)
    rep <- split_report(dt, tag)
    pr(rep$full); pr(rep$oos)
    cat(sprintf("  oos_retention(active)=%.4f total=%.4f\n", rep$oos_retention_active, rep$oos_retention_total))
    sweep[[tag]] <- list(dt=dt, rep=rep, k=k, se_kind=se_kind)
  }
}
saveRDS(sweep, file.path(OUT,"_exp_uncertainty_sweep.rds"))
cat("\n[DONE] saved _exp_baseline.rds + _exp_uncertainty_sweep.rds\n")
