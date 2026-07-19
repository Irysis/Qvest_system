# probe_info_theoretic.R — 정보이론 선별/구성 probe (info_theoretic_selection)
# (a) MI-weighted family combination — 비선형 factor→fwd_ret 상호정보로 family 가중 (linear IC 대비)
# (b) entropy/diversification weighting — top-25 선택 후 max-div/inv-vol/min-var 가중 → calmar/MDD
# ★PIT: MI·covariance 전부 trailing window(month < t). metric_type 계약 경유(자체합성 금지).
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)})
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")

cat("\n================ BASELINES ================\n")
res_static <- .canon(.FAM[,.(Date,Ticker,score=score_ew)])
res_mom    <- .canon(.score_from_theta(.mom_theta))
cat(sprintf("static_EW    port_t=%.3f calmar=%.3f net_sr=%.3f oos=%.3f\n",
    res_static$portfolio_alpha_t_nw_lag3, .calmar_of(res_static$period_returns), res_static$net_sr, .oos_ret_of(res_static$period_returns)))
cat(sprintf("family_mom   port_t=%.3f calmar=%.3f net_sr=%.3f oos=%.3f\n",
    res_mom$portfolio_alpha_t_nw_lag3, .calmar_of(res_mom$period_returns), res_mom$net_sr, .oos_ret_of(res_mom$period_returns)))

# ============================================================
# Test A: MI-weighted family combination
# ============================================================
cat("\n================ TEST A: MI-weighted family ================\n")
# stock-level (Date,Ticker, per-family z) + fwd_ret(Ret_1m)
FZ <- merge(.FAM[, c("Date","Ticker",.fams), with=FALSE], .Rg[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
alldts <- sort(unique(FZ$Date))

# MI helper: discretize x,y into q quantile bins, MI in nats
.mi_bin <- function(x, y, q=5L){
  ok <- is.finite(x) & is.finite(y); x<-x[ok]; y<-y[ok]; n<-length(x)
  if(n < 100L) return(NA_real_)
  bx <- cut(x, breaks=quantile(x, probs=seq(0,1,length.out=q+1), na.rm=TRUE, type=8), include.lowest=TRUE, labels=FALSE)
  by <- cut(y, breaks=quantile(y, probs=seq(0,1,length.out=q+1), na.rm=TRUE, type=8), include.lowest=TRUE, labels=FALSE)
  ok2 <- is.finite(bx) & is.finite(by); bx<-bx[ok2]; by<-by[ok2]; n<-length(bx)
  if(n < 100L) return(NA_real_)
  tab <- table(bx, by); p <- tab/n
  px <- rowSums(p); py <- colSums(p)
  mi <- 0
  for(i in seq_len(nrow(p))) for(j in seq_len(ncol(p))){
    if(p[i,j] > 0) mi <- mi + p[i,j]*log(p[i,j]/(px[i]*py[j]))
  }
  max(mi, 0)
}
# Spearman IC helper (linear rank comparison)
.ic_sp <- function(x,y){ ok<-is.finite(x)&is.finite(y); if(sum(ok)<100L) return(NA_real_); abs(suppressWarnings(cor(x[ok],y[ok],method="spearman"))) }

WIN <- 60L  # trailing months cap
mi_theta_rows <- list(); ic_theta_rows <- list()
for(t in .oos_dates){
  hist <- FZ[Date < t]
  if(length(unique(hist$Date)) >= WIN){ keepd <- tail(sort(unique(hist$Date)), WIN); hist <- hist[Date %in% keepd] }
  if(length(unique(hist$Date)) < 24L) next
  mis <- sapply(.fams, function(fk) .mi_bin(hist[[fk]], hist$Ret_1m))
  ics <- sapply(.fams, function(fk) .ic_sp(hist[[fk]], hist$Ret_1m))
  mis[!is.finite(mis)] <- 0; ics[!is.finite(ics)] <- 0
  if(sum(mis)<=0) mis <- rep(1,length(.fams)); if(sum(ics)<=0) ics <- rep(1,length(.fams))
  mi_theta_rows[[as.character(t)]] <- data.table(date=t, family=.fams, theta=as.numeric(mis/sum(mis)))
  ic_theta_rows[[as.character(t)]] <- data.table(date=t, family=.fams, theta=as.numeric(ics/sum(ics)))
}
mi_theta <- rbindlist(mi_theta_rows); ic_theta <- rbindlist(ic_theta_rows)
eA_mi <- eval_theta(mi_theta, "MI_weighted")
eA_ic <- eval_theta(ic_theta, "IC_weighted")
cat(sprintf("MI_weighted  port_t=%.3f ew_uni_t=%.3f calmar=%.3f net_sr=%.3f oos=%.3f turn=%.1f lag1=%.3f  vs_mom_t=%.3f vs_static_t=%.3f n=%d\n",
    eA_mi$port_t, eA_mi$ew_uni_t, eA_mi$calmar, eA_mi$net_sr, eA_mi$oos_ret, eA_mi$turnover, eA_mi$lag1_port_t, eA_mi$paired_vs_mom_t, eA_mi$paired_vs_static_t, eA_mi$n_months))
cat(sprintf("IC_weighted  port_t=%.3f ew_uni_t=%.3f calmar=%.3f net_sr=%.3f oos=%.3f turn=%.1f lag1=%.3f  vs_mom_t=%.3f vs_static_t=%.3f n=%d\n",
    eA_ic$port_t, eA_ic$ew_uni_t, eA_ic$calmar, eA_ic$net_sr, eA_ic$oos_ret, eA_ic$turnover, eA_ic$lag1_port_t, eA_ic$paired_vs_mom_t, eA_ic$paired_vs_static_t, eA_ic$n_months))

# ============================================================
# Test B: entropy/diversification weighting of EW-selected top-25
# ============================================================
cat("\n================ TEST B: diversification weighting ================\n")
# selection (same as canonical static_EW): score_ew, liq filter, top-25
SEL <- .FAM[,.(Date,Ticker,score=score_ew)][Date %in% .Rg$Date & Date %in% .oos_dates]
SEL <- merge(SEL, .LQg[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
SEL <- SEL[is.na(adv) | adv>=2e8]; SEL[,adv:=NULL]
setorder(SEL, Date, -score)
HOLD <- SEL[, .(Ticker=Ticker[seq_len(min(25L,.N))]), by=Date]

# trailing monthly return matrix helper
Rmat_cache <- .Rg[,.(Date,Ticker,Ret_1m)]
seldts <- sort(unique(HOLD$Date))
COVWIN <- 36L
.divweights <- function(t, ticks, method){
  hd <- tail(sort(unique(Rmat_cache[Date < t, Date])), COVWIN)
  M <- Rmat_cache[Date %in% hd & Ticker %in% ticks]
  if(nrow(M)==0) return(data.table(Ticker=ticks, w=1/length(ticks)))
  W <- dcast(M, Date ~ Ticker, value.var="Ret_1m")
  mat <- as.matrix(W[,-1]); cn <- colnames(mat)
  # tickers with <8 obs → drop from cov, EW fallback handled by renorm over present
  keep <- cn[colSums(is.finite(mat)) >= 8L]
  present <- intersect(ticks, keep)
  miss <- setdiff(ticks, present)
  if(length(present) < 3L) return(data.table(Ticker=ticks, w=1/length(ticks)))
  mm <- mat[, present, drop=FALSE]
  S <- cov(mm, use="pairwise.complete.obs")
  S[!is.finite(S)] <- 0
  vol <- sqrt(pmax(diag(S), 1e-8))
  # shrink to diagonal (stabilize inversion)
  lam <- 0.3; Ssh <- lam*diag(diag(S)) + (1-lam)*S
  Sinv <- tryCatch(solve(Ssh + diag(1e-6, nrow(Ssh))), error=function(e) NULL)
  w <- switch(method,
    invvol = 1/vol,
    minvar = if(is.null(Sinv)) 1/vol else as.numeric(Sinv %*% rep(1,length(present))),
    maxdiv = if(is.null(Sinv)) 1/vol else as.numeric(Sinv %*% vol),
    rep(1,length(present)))
  w[!is.finite(w)] <- 0; w[w<0] <- 0
  if(sum(w)<=0) w <- rep(1,length(present))
  w <- w/sum(w); w <- pmin(w, 0.20); w <- w/sum(w)   # cap 0.20, renorm
  dt <- data.table(Ticker=present, w=w)
  if(length(miss)>0) dt <- rbind(dt, data.table(Ticker=miss, w=0))  # missing-cov ticks → 0 (dropped)
  dt[w>0][, w:=w/sum(w)]
}
run_method <- function(method){
  wl <- list()
  for(t in seldts){ ticks <- HOLD[Date==t, Ticker]; dt <- .divweights(t, ticks, method); dt[, Date:=t]; wl[[as.character(t)]] <- dt }
  W <- rbindlist(wl)[, .(Date,Ticker,w)]
  W[, Date := as.Date(Date, origin="1970-01-01")]   # for-loop coerces Date->numeric; restore
  r <- weighted_screen_bt(W, .Rg[,.(Date,Ticker,Ret_1m)], .BMg[,.(Date,BM_Ret)], cost_bps_oneway=15,
                          run_id=paste0("wt006_div_",method), strategy_id=paste0("div_",method))
  cal <- if(is.finite(r$abs_mdd) && r$abs_mdd<0) r$abs_cagr/abs(r$abs_mdd) else NA_real_
  cat(sprintf("%-8s port_t=%.3f IR=%.3f net_sr=%.3f abs_cagr=%.3f abs_mdd=%.3f calmar=%.3f turn=%.1f n=%d\n",
      method, r$portfolio_alpha_t_nw_lag3, r$information_ratio, r$net_sr, r$abs_cagr, r$abs_mdd, cal, r$turnover_annual, r$n_months))
  list(method=method, r=r, calmar=cal)
}
# EW anchor via weighted_screen_bt (should match canonical selection)
Wew <- copy(HOLD); Wew[, w:=1/.N, by=Date]
rew <- weighted_screen_bt(Wew[,.(Date,Ticker,w)], .Rg[,.(Date,Ticker,Ret_1m)], .BMg[,.(Date,BM_Ret)], cost_bps_oneway=15, run_id="wt006_div_ew", strategy_id="div_ew")
cal_ew <- if(is.finite(rew$abs_mdd)&&rew$abs_mdd<0) rew$abs_cagr/abs(rew$abs_mdd) else NA_real_
cat(sprintf("%-8s port_t=%.3f IR=%.3f net_sr=%.3f abs_cagr=%.3f abs_mdd=%.3f calmar=%.3f turn=%.1f n=%d\n",
    "EW", rew$portfolio_alpha_t_nw_lag3, rew$information_ratio, rew$net_sr, rew$abs_cagr, rew$abs_mdd, cal_ew, rew$turnover_annual, rew$n_months))
mv <- run_method("minvar"); iv <- run_method("invvol"); md <- run_method("maxdiv")

cat("\n================ SUMMARY JSON ================\n")
library(jsonlite)
out <- list(
  baselines=list(
    static_EW=list(port_t=res_static$portfolio_alpha_t_nw_lag3, calmar=.calmar_of(res_static$period_returns)),
    family_mom=list(port_t=res_mom$portfolio_alpha_t_nw_lag3, calmar=.calmar_of(res_mom$period_returns))),
  testA=list(MI=eA_mi, IC=eA_ic),
  testB=list(
    EW=list(port_t=rew$portfolio_alpha_t_nw_lag3, abs_mdd=rew$abs_mdd, calmar=cal_ew, net_sr=rew$net_sr),
    minvar=list(port_t=mv$r$portfolio_alpha_t_nw_lag3, abs_mdd=mv$r$abs_mdd, calmar=mv$calmar, net_sr=mv$r$net_sr),
    invvol=list(port_t=iv$r$portfolio_alpha_t_nw_lag3, abs_mdd=iv$r$abs_mdd, calmar=iv$calmar, net_sr=iv$r$net_sr),
    maxdiv=list(port_t=md$r$portfolio_alpha_t_nw_lag3, abs_mdd=md$r$abs_mdd, calmar=md$calmar, net_sr=md$r$net_sr)))
writeLines(toJSON(out, auto_unbox=TRUE, digits=4, na="null"), "04_Research/method_frontier/wt006_exog_forecast/probe_info_theoretic_result.json")
cat("written probe_info_theoretic_result.json\n")
