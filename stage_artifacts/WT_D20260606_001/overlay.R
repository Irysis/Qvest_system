## WT-D20260606_001 Optimizer — OVERLAY + UNCERTAINTY test (the WT core question)
## Does beta/regime overlay + uncertainty sizing lift BOOK SR toward 2.5?
suppressMessages({library(arrow); library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite)})
options(warn=1); root <- "G:/Quant_Module_Moltbot"; setwd(root); set.seed(606)
OUT <- "stage_artifacts/WT_D20260606_001"
S <- readRDS(file.path(OUT,"opt_intermediate.rds"))
sl <- S$sl; inc <- S$inc; m_r05 <- S$m_r05

metrics_xts <- function(x, scale=12){
  ar <- as.numeric(Return.annualized(x, scale=scale)); sd <- as.numeric(StdDev.annualized(x, scale=scale))
  list(CAGR=ar, Vol=sd, SR=ar/sd, MDD=as.numeric(maxDrawdown(x)))
}

# ---- align combined panel: R05 ret_net + sleeve(EW) + regime overlay signals (all from inc series) ----
sleeve <- sl[["EW"]]$series[, .(ym, sleeve_net)]
inc2 <- inc[, .(ym, Date, r05_net=ret_net, combined_regime, MSM_Crisis_Prob_lag, Regime_Score_lag, weight_cash)]
J <- merge(sleeve, inc2, by="ym"); J <- J[is.finite(sleeve_net)&is.finite(r05_net)]; setorder(J, Date)
cat("panel months:", nrow(J), "\n")

mk_xts <- function(v, dt=J$Date) xts(v, order.by=dt)

# ===== Baseline book combos (no overlay) =====
book_static <- function(a){ R <- xts(as.matrix(J[,.(R05=r05_net, SL=sleeve_net)]), order.by=J$Date)
  Return.portfolio(R, weights=c(1-a,a), rebalance_on="months") }
b015 <- book_static(0.15); m015 <- metrics_xts(b015)
cat(sprintf("\n[baseline] static a=0.15 book: SR %.3f CAGR %.3f Vol %.3f MDD %.3f\n", m015$SR,m015$CAGR,m015$Vol,m015$MDD))

# =====================================================================
# OVERLAY 1: REGIME de-risk overlay on the BOOK (beta/regime timing)
#   when crisis prob high OR defensive-regime fraction high -> scale total book exposure down (to cash)
#   PIT: signals are *_lag (already t-1). exposure applied to next month return.
# =====================================================================
test_regime_overlay <- function(a, crisis_thr, exposure_low){
  R <- xts(as.matrix(J[,.(R05=r05_net, SL=sleeve_net)]), order.by=J$Date)
  combo <- (1-a)*J$r05_net + a*J$sleeve_net   # 2-asset monthly (rebalanced) approx == Return.portfolio for fixed a (close enough for exposure scan)
  # exposure signal from lagged crisis prob / combined_regime
  sig <- pmax(J$MSM_Crisis_Prob_lag, J$combined_regime, na.rm=TRUE)
  sig[is.na(sig)] <- 0
  expo <- ifelse(sig >= crisis_thr, exposure_low, 1.0)
  # PIT: signal is already _lag (t-1). Apply same-month exposure to same-month forward return (no extra shift needed; lag built-in).
  book_ov <- expo*combo   # de-risked portion -> cash (0 return)
  list(x=mk_xts(book_ov), expo=expo, avg_expo=mean(expo))
}

cat("\n=== OVERLAY 1: regime de-risk on book (a=0.15) ===\n")
for(thr in c(0.4,0.5,0.6,0.7)) for(el in c(0.0,0.3,0.5)){
  o <- test_regime_overlay(0.15, thr, el); m <- metrics_xts(o$x)
  cat(sprintf(" thr=%.1f exp_low=%.1f  SR %.3f CAGR %.3f Vol %.3f MDD %.3f  avg_expo %.2f  dSR(vsR05) %+.3f\n",
      thr, el, m$SR, m$CAGR, m$Vol, m$MDD, o$avg_expo, m$SR-m_r05$SR))
}

# =====================================================================
# OVERLAY 2: UNCERTAINTY-aware sleeve sizing (mu_tilde = mu_hat - k*SE)
#   size sleeve allocation by its trailing risk-adjusted edge with uncertainty haircut
#   PIT: use EXPANDING trailing window of realized sleeve excess (no lookahead)
# =====================================================================
cat("\n=== OVERLAY 2: uncertainty-aware dynamic sleeve sizing (k haircut) ===\n")
test_uncertainty_sizing <- function(k, a_max=0.20, win=36L){
  n <- nrow(J); a_t <- numeric(n)
  for(t in 1:n){
    if(t <= 12){ a_t[t] <- 0.05; next }   # warm-up small
    lo <- max(1, t-win); hist <- J$sleeve_net[lo:(t-1)]   # STRICTLY past
    mu <- mean(hist); se <- sd(hist)/sqrt(length(hist))
    mu_tilde <- mu - k*se                  # uncertainty haircut
    # map to allocation: positive haircut edge -> scale toward a_max; else floor
    a_t[t] <- pmin(a_max, pmax(0, a_max * (mu_tilde / (abs(mu)+1e-6)) ))
    if(!is.finite(a_t[t])) a_t[t] <- 0.05
  }
  book <- (1-a_t)*J$r05_net + a_t*J$sleeve_net
  list(x=mk_xts(book), a_t=a_t, avg_a=mean(a_t))
}
for(k in c(0,0.5,1.0,1.5,2.0)){
  o <- test_uncertainty_sizing(k); m <- metrics_xts(o$x)
  cat(sprintf(" k=%.1f  SR %.3f CAGR %.3f Vol %.3f MDD %.3f  avg_a %.3f  dSR %+.3f\n",
      k, m$SR, m$CAGR, m$Vol, m$MDD, o$avg_a, m$SR-m_r05$SR))
}

# =====================================================================
# OVERLAY 3: COMBINED  regime de-risk + uncertainty sizing  (best-of attempt)
# =====================================================================
cat("\n=== OVERLAY 3: regime de-risk(thr0.6,exp0.3) + uncertainty sizing(k1.0) ===\n")
us <- test_uncertainty_sizing(1.0)
a_t <- us$a_t
combo <- (1-a_t)*J$r05_net + a_t*J$sleeve_net
sig <- pmax(J$MSM_Crisis_Prob_lag, J$combined_regime, na.rm=TRUE); sig[is.na(sig)]<-0
expo <- ifelse(sig>=0.6, 0.3, 1.0)
book_c <- expo*combo
mc <- metrics_xts(mk_xts(book_c))
cat(sprintf(" COMBINED  SR %.3f CAGR %.3f Vol %.3f MDD %.3f  dSR %+.3f\n", mc$SR,mc$CAGR,mc$Vol,mc$MDD,mc$SR-m_r05$SR))

# ===== Reference: apply SAME regime overlay to R05 ALONE (is overlay value from sleeve or from re-timing R05?) =====
cat("\n=== CONTROL: regime de-risk applied to R05 ALONE (no sleeve) ===\n")
for(thr in c(0.6,0.7)) for(el in c(0.0,0.3)){
  expo <- ifelse(sig>=thr, el, 1.0); xr05ov <- mk_xts(expo*J$r05_net); m <- metrics_xts(xr05ov)
  cat(sprintf(" thr=%.1f exp_low=%.1f  R05-only-overlay SR %.3f (vs R05 base %.3f) dSR %+.3f\n",
      thr, el, m$SR, m_r05$SR, m$SR-m_r05$SR))
}

saveRDS(list(J=J, m015=m015), file.path(OUT,"overlay_intermediate.rds"))
cat("\n[done overlay]\n")
