#==============================================================================
# WT-D20260528_003 D_PROD — Optimizer Research Pipeline
# Role: weights only. alpha/risk read-only. Σw=1 / [0,0.20] / max20 / long-only.
# Method comparison (>=3) + walk-forward net-SR + RF-R1 MKT exposure control.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(quadprog)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
WT  <- "WT-D20260528_003"
ABASE <- "stage_artifacts/WT_D20260528_003"
RBASE <- "stage_artifacts/WT_D20260528_003_risk_PROD"
OUT_MB <- file.path("qepm/mailbox/worktask", WT)
OUT_SA <- ABASE
COMMISSION <- 0.0015            # 15 bps one-way
TOP_N      <- 20L
WMAX       <- 0.20
WMIN       <- 0.0

set.seed(20260529)
AS_OF <- as.Date("2023-11-30")   # risk snapshot as_of date

# Ledoit-Wolf shrinkage covariance (annualized) from daily return matrix (T x n).
# Shrinks sample cov toward constant-correlation target. PSD guaranteed via diag floor.
shrink_cov <- function(hh, tk){
  n <- length(tk)
  if(is.null(hh) || ncol(hh) < n || nrow(hh) < 20){
    # insufficient history -> diagonal from available vol (annualized), PSD
    dv <- if(is.null(hh)) rep(0.30, n) else { v<-apply(hh,2,sd,na.rm=TRUE)*sqrt(252); v[!is.finite(v)]<-0.30; v }
    if(length(dv)!=n) dv <- rep(0.30, n)
    M <- diag(dv^2, n); dimnames(M)<-list(tk,tk); return(M)
  }
  hh <- hh[, tk, drop=FALSE]; hh[!is.finite(hh)] <- 0
  S  <- cov(hh) * 252                                  # annualized sample cov
  d  <- sqrt(diag(S)); d[!is.finite(d)|d<=0] <- mean(d[is.finite(d)&d>0])
  R  <- S/(d %o% d); R[!is.finite(R)] <- 0; diag(R) <- 1
  rbar <- (sum(R)-n)/(n*(n-1))                          # avg off-diag corr
  Rtgt <- matrix(rbar, n, n); diag(Rtgt) <- 1
  Ftgt <- Rtgt * (d %o% d)                              # constant-corr target
  lam  <- 0.30                                          # fixed shrinkage intensity (robust)
  Sigma <- lam*Ftgt + (1-lam)*S
  Sigma <- (Sigma+t(Sigma))/2 + diag(1e-8, n)
  dimnames(Sigma) <- list(tk, tk)
  Sigma
}

# ── 1) Load inputs ──────────────────────────────────────────────────────────
alpha <- as.data.table(read_parquet(file.path(ABASE,"alpha_scores.parquet")))
alpha[, Date := as.Date(Date)]
sig_dates <- sort(unique(alpha$Date))
N_SIG <- length(sig_dates)
cat(sprintf("[load] alpha_scores: %d rows, %d sig_dates (%s .. %s)\n",
            nrow(alpha), N_SIG, min(sig_dates), max(sig_dates)))

# Alpha-agent bandbuffer holdings schedule (keep50/entry20/cooldown3m -> turnover 5.30/yr).
# Optimizer scope = re-SIZE these committed names, NOT re-select. Preserves turnover discipline.
sched <- as.data.table(read_parquet(file.path(ABASE,"weights_schedule.parquet")))
sched[, Date := as.Date(Date)]
setkey(sched, Date, Ticker)
cat(sprintf("[load] bandbuffer schedule: %d rows, %d dates (names/date=20)\n",
            nrow(sched), uniqueN(sched$Date)))

# Risk snapshot (as_of 2023-11-30)
cov_dt <- as.data.table(read_parquet(file.path(RBASE,"covariance.parquet")))
cov_tk <- cov_dt$Ticker
covM   <- as.matrix(cov_dt[, -1, with=FALSE]); rownames(covM) <- cov_tk
B_dt   <- as.data.table(read_parquet(file.path(RBASE,"B_loadings.parquet")))
sr_dt  <- as.data.table(read_parquet(file.path(RBASE,"specific_risk.parquet")))
setkey(B_dt, Ticker); setkey(sr_dt, Ticker)
cat(sprintf("[load] Sigma snapshot %dx%d, B_loadings %d, specific_risk %d\n",
            nrow(covM), ncol(covM), nrow(B_dt), nrow(sr_dt)))

# RAWDATA daily returns + BM
raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))[, .(Date, Ticker, Ret, BM_Ret)]
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2014-01-01") & Date <= as.Date("2024-01-31")]
setkey(raw, Ticker, Date)
cat(sprintf("[load] RAWDATA daily rows (2014-2024): %d\n", nrow(raw)))

# Monthly forward returns: from sig_date(t) to sig_date(t+1), per ticker (compounded daily Ret)
# Map each sig_date to next sig_date; realized holding-period return = prod(1+Ret)-1 over (sig_t, sig_{t+1}]
all_dates <- sort(unique(raw$Date))
fwd_ret_for <- function(tk, d0, d1){
  r <- raw[Ticker==tk & Date > d0 & Date <= d1, Ret]
  if(length(r)==0L) return(NA_real_)
  prod(1+r[!is.na(r)]) - 1
}

# Benchmark monthly fwd returns (BM_Ret is daily benchmark return, same for all tickers)
bm_daily <- unique(raw[, .(Date, BM_Ret)])[order(Date)]
bm_fwd <- function(d0,d1){
  r <- bm_daily[Date> d0 & Date<=d1, BM_Ret]
  if(length(r)==0L) return(NA_real_); prod(1+r[!is.na(r)])-1
}

# ── 2) Weight methods (cross-section, top-20) ───────────────────────────────
.normalize <- function(w){ w[w<0]<-0; if(sum(w)<=0) w<-rep(1,length(w)); w/sum(w) }
.cap_iter <- function(w, wmax=WMAX){           # iterative cap to [0,wmax], renorm, Σ=1
  for(i in 1:200){
    w <- .normalize(w); over <- w>wmax+1e-12
    if(!any(over)) break
    excess <- sum(w[over]-wmax); w[over]<-wmax
    under <- !over & w>0
    if(!any(under)) { w<-w/sum(w); break }
    w[under] <- w[under] + excess*w[under]/sum(w[under])
  }
  .normalize(pmin(w,wmax))
}

# EW (alpha-agent baseline equivalent)
m_ew <- function(tk, a, cm, bload, spv){ .cap_iter(rep(1/length(tk), length(tk))) }

# alpha-tilt softmax (alpha-agent style, temperature)
m_alpha_softmax <- function(tk, a, cm, bload, spv, temp=1.0){
  z <- (a-mean(a))/ (sd(a)+1e-9); w <- exp(z/temp); .cap_iter(w)
}

# MVO: max wα - λ/2 wΣw, long-only, [0,wmax], Σw=1 (quadprog). confidence-scaled alpha.
m_mvo <- function(tk, a, cm, bload, spv, lambda=8.0, conf=NULL){
  n <- length(tk)
  S <- cm
  S <- (S+t(S))/2 + diag(1e-6, n)
  if(!is.null(conf)) a <- a*conf
  Dmat <- lambda * S
  dvec <- a
  # constraints: sum=1 ; w>=0 ; w<=wmax
  Amat <- cbind(rep(1,n), diag(n), -diag(n))
  bvec <- c(1, rep(WMIN,n), rep(-WMAX,n))
  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq=1)$solution,
                  error=function(e) rep(1/n,n))
  .cap_iter(sol)
}

# ERC (equal risk contribution) — cyclical, then cap
m_erc <- function(tk, a, cm, bload, spv){
  n <- length(tk); S <- (cm+t(cm))/2 + diag(1e-8,n)
  w <- rep(1/n,n)
  for(it in 1:500){
    mrc <- as.numeric(S %*% w); rc <- w*mrc; tgt <- sum(rc)/n
    w <- w * (tgt/(rc+1e-12))^0.5; w <- .normalize(w)
  }
  .cap_iter(w)
}

# HRP — hierarchical risk parity (corr dist + recursive bisection)
m_hrp <- function(tk, a, cm, bload, spv){
  n <- length(tk); S <- (cm+t(cm))/2
  if(n < 2) return(.normalize(rep(1,max(n,1))))
  d <- sqrt(diag(S)); R <- S/(d %o% d); R[is.na(R)]<-0
  diag(R) <- 1
  # if cov is diagonal (fallback), HRP collapses to inverse-variance; guard hclust
  # NOTE: pmax() strips matrix dims -> rebuild matrix explicitly before diag()<-
  dist <- matrix(sqrt(pmax(0,(1-R)/2)), n, n); diag(dist) <- 0
  if(any(!is.finite(dist)) || nrow(dist)!=ncol(dist)){
    iv <- 1/diag(S); return(.cap_iter(.normalize(iv)))
  }
  hc <- hclust(as.dist(dist), method="single")
  ord <- hc$order
  ivp <- function(idx){ iv <- 1/diag(S)[idx]; iv/sum(iv) }
  recurse <- function(items){
    if(length(items)==1) return(setNames(1, items))
    half <- floor(length(items)/2)
    L <- items[1:half]; Rr <- items[(half+1):length(items)]
    varc <- function(g){ wv<-ivp(g); as.numeric(t(wv)%*%S[g,g,drop=FALSE]%*%wv) }
    vl <- varc(L); vr <- varc(Rr); aL <- 1 - vl/(vl+vr)
    c(recurse(L)*aL, recurse(Rr)*(1-aL))
  }
  w_named <- recurse(ord)
  w <- numeric(n); w[as.integer(names(w_named))] <- w_named
  .cap_iter(.normalize(w))
}

# CVaR-min LP (Rockafellar-Uryasev) using daily returns history pre sig_date
m_cvar <- function(tk, a, cm, bload, spv, hist){
  # hist: matrix T x n of daily returns (loss = -ret); fallback to ERC if infeasible
  n <- length(tk)
  if(is.null(hist) || nrow(hist) < 30) return(m_erc(tk,a,cm,bload,spv))
  Rmat <- hist; Tn <- nrow(Rmat); beta <- 0.95
  # vars: w(n), VaR(1), u(T). min VaR + 1/((1-beta)T) sum u
  if(!requireNamespace("Rglpk", quietly=TRUE)) return(m_erc(tk,a,cm,bload,spv))
  obj <- c(rep(0,n), 1, rep(1/((1-beta)*Tn), Tn))
  # u_t >= -R_t w - VaR  -> -R_t w - VaR - u_t <= 0  => R_t w + VaR + u_t >=0
  A1 <- cbind(Rmat, rep(1,Tn), diag(Tn))      # >= 0  (u_t + VaR + R_t w >=0)
  A2 <- cbind(diag(n), matrix(0,n,1+Tn))      # w >= 0
  A3 <- c(rep(1,n), 0, rep(0,Tn))             # sum w = 1
  A4 <- cbind(diag(n), matrix(0,n,1+Tn))      # w <= wmax
  mat <- rbind(A1, A3, A4); dir <- c(rep(">=",Tn), "==", rep("<=",n))
  rhs <- c(rep(0,Tn), 1, rep(WMAX,n))
  bnd <- list(lower=list(ind=1:(n+1+Tn), val=c(rep(0,n), -Inf, rep(0,Tn))))
  sol <- tryCatch(Rglpk::Rglpk_solve_LP(obj, mat, dir, rhs, bounds=bnd, max=FALSE),
                  error=function(e) NULL)
  if(is.null(sol) || sol$status!=0) return(m_erc(tk,a,cm,bload,spv))
  .cap_iter(.normalize(sol$solution[1:n]))
}

# MVO + MKT-beta neutral tilt (RF-R1): penalize portfolio MKT beta toward target
m_mvo_betaneutral <- function(tk, a, cm, bload, spv, lambda=8.0, beta_pen=40, beta_tgt=0.90, conf=NULL){
  n <- length(tk); S <- (cm+t(cm))/2 + diag(1e-6,n)
  if(!is.null(conf)) a <- a*conf
  bk <- bload[match(tk, bload$Ticker), MKT]; bk[is.na(bk)] <- mean(bk,na.rm=TRUE)
  # add beta_pen*(b'w - beta_tgt)^2 to objective => quad term beta_pen*bb', linear 2*beta_pen*beta_tgt*b
  Dmat <- lambda*S + beta_pen*(bk %o% bk)
  dvec <- a + beta_pen*beta_tgt*bk
  Amat <- cbind(rep(1,n), diag(n), -diag(n)); bvec <- c(1, rep(0,n), rep(-WMAX,n))
  sol <- tryCatch(solve.QP(Dmat,dvec,Amat,bvec,meq=1)$solution, error=function(e) rep(1/n,n))
  .cap_iter(sol)
}

# ── 3) Walk-forward simulation engine ───────────────────────────────────────
# One-time wide daily-return matrix (Date x Ticker) for fast PIT history slicing.
cat("[prep] building wide daily-return matrix cache...\n")
held_tickers <- sort(unique(sched$Ticker))
raw_held <- raw[Ticker %in% held_tickers]
WIDE <- dcast(raw_held, Date ~ Ticker, value.var="Ret")
WIDE_dates <- WIDE$Date
WIDE_mat <- as.matrix(WIDE[, -1, with=FALSE])
WIDE_cols <- colnames(WIDE_mat)
WIDE_mat[!is.finite(WIDE_mat)] <- NA
cat(sprintf("[prep] WIDE matrix %d days x %d tickers\n", nrow(WIDE_mat), ncol(WIDE_mat)))

# PIT-strict history: daily returns with Date < d0 (no same-day, C9). Returns T x n matrix aligned to tk.
build_hist <- function(tk, d0, lookback=252){
  ridx <- which(WIDE_dates < d0)                       # STRICT < d0 (PIT C9 t-1)
  if(length(ridx) < 20) return(NULL)
  ridx <- tail(ridx, lookback)
  cidx <- match(tk, WIDE_cols)
  m <- matrix(0, length(ridx), length(tk), dimnames=list(NULL, tk))
  ok <- !is.na(cidx)
  if(any(ok)) m[, ok] <- WIDE_mat[ridx, cidx[ok], drop=FALSE]
  m[!is.finite(m)] <- 0
  m
}

simulate <- function(method_fn, use_hist=FALSE, use_conf=FALSE, use_d0=FALSE, ...){
  port_ret <- numeric(0); bm_ret <- numeric(0); dts <- as.Date(character(0))
  prev_w <- NULL; prev_tk <- NULL; turn_list <- numeric(0)
  hold_list <- list()
  for(i in 1:(N_SIG-1)){
    d0 <- sig_dates[i]; d1 <- sig_dates[i+1]
    # NAME SET = alpha-agent bandbuffer holdings at d0 (turnover-disciplined). Optimizer re-sizes only.
    tk <- sched[Date==d0, Ticker]
    if(length(tk)==0){ next }                      # no schedule names this date
    ad <- alpha[Date==d0 & Ticker %in% tk]
    a  <- ad$pred[match(tk, ad$Ticker)]; a[is.na(a)] <- 0
    # Covariance per rebalance date.
    # as_of snapshot (2023-11-30): use risk-agent Σ (BΩB'+D, cond100) for the names it covers.
    # All other dates: rolling Ledoit-Wolf shrinkage Σ from daily history STRICTLY < d0 (PIT C9 t-1).
    common <- intersect(tk, rownames(covM))
    if(d0 == AS_OF && length(common)==length(tk) && length(tk)>1){
      cm <- covM[tk, tk, drop=FALSE]                       # risk-agent Σ at as_of
      cov_src <- "risk_snapshot"
    } else {
      hh <- build_hist(tk, d0, 252)                        # daily rets, Date < d0 (PIT)
      cm <- shrink_cov(hh, tk)
      cov_src <- "rolling_LW_252d"
    }
    conf <- if(use_conf) pmax(0.3, pmin(1, (a-min(a))/(max(a)-min(a)+1e-9))) else NULL
    hist <- if(use_hist) build_hist(tk, d0, 120) else NULL
    w <- tryCatch({
      if(use_d0) method_fn(tk, a, cm, B_dt, sr_dt, hist=hist, conf=conf, d0=d0, ...)
      else       method_fn(tk, a, cm, B_dt, sr_dt, hist=hist, conf=conf, ...)
    }, error=function(e){ message("  method err: ", conditionMessage(e)); .normalize(rep(1,length(tk))) })
    names(w) <- tk
    # turnover vs previous (one-way Σ|Δw|)
    if(is.null(prev_w)){ turn <- 1.0 } else {
      allk <- union(names(w), names(prev_w))
      wv <- setNames(numeric(length(allk)), allk); wv[names(w)]<-w
      pv <- setNames(numeric(length(allk)), allk); pv[names(prev_w)]<-prev_w
      turn <- sum(abs(wv-pv))/2
    }
    turn_list <- c(turn_list, turn)
    # realized forward return per ticker over (d0, d1]: compound daily Ret from WIDE matrix
    fwin <- which(WIDE_dates > d0 & WIDE_dates <= d1)
    cidx <- match(tk, WIDE_cols)
    fr <- sapply(seq_along(tk), function(j){
      ci <- cidx[j]; if(is.na(ci)) return(NA_real_)
      rr <- WIDE_mat[fwin, ci]; rr <- rr[is.finite(rr)]
      if(length(rr)==0) return(NA_real_); prod(1+rr)-1
    })
    names(fr) <- tk
    valid <- !is.na(fr)
    if(sum(valid)==0){ prev_w<-w; next }
    wv2 <- w[valid]/sum(w[valid]); pr <- sum(wv2*fr[valid])
    # net of cost: charge one-way turnover * commission at entry (round-trip handled across periods)
    pr_net <- pr - turn*COMMISSION
    port_ret <- c(port_ret, pr_net); bm_ret <- c(bm_ret, bm_fwd(d0,d1)); dts <- c(dts, d1)
    hold_list[[as.character(d0)]] <- data.table(Date=d0, Ticker=tk, weight=as.numeric(w))
    prev_w <- w; prev_tk <- tk
  }
  list(port=port_ret, bm=bm_ret, dates=dts, turn=turn_list, holds=rbindlist(hold_list))
}

# Annualized turnover (round-trip). turn_list = monthly ONE-WAY sum|Δw|/2.
# round-trip per rebalance = one-way * 2 ; annualize * 12 monthly rebalances.
# NO spurious *12-only inflation (Iter 3 violation): factor is 2 (round-trip) * 12 (months).
ann_turnover <- function(turn_list){
  t2 <- turn_list[-1]          # exclude initialization period (turn=1.0)
  mean(t2) * 2 * 12
}

metrics_of <- function(sim){
  r <- sim$port; b <- sim$bm; d <- as.Date(sim$dates)
  rx <- xts(r, order.by=d); bx <- xts(b, order.by=d)
  ar <- table.AnnualizedReturns(rx, scale=12, Rf=0)
  sr_net <- as.numeric(ar["Annualized Sharpe (Rf=0%)",1])
  cagr   <- as.numeric(ar["Annualized Return",1])
  vol    <- as.numeric(ar["Annualized Std Dev",1])
  active <- rx - bx
  ir <- as.numeric(mean(active)/sd(active)*sqrt(12))
  te <- as.numeric(sd(active)*sqrt(12))
  mdd <- as.numeric(maxDrawdown(rx))
  to  <- ann_turnover(sim$turn)
  list(sr_net=sr_net, cagr=cagr, vol=vol, ir=ir, te=te, mdd=mdd, turnover_yr=to,
       n_periods=length(r), net_active_ret=as.numeric(mean(active)*12))
}

cat("\n[sim] Running method comparison (walk-forward 115 periods)...\n")
# Schedule = alpha-agent verbatim bandbuffer softmax weights (canonical baseline for net-SR comparison)
m_schedule <- function(tk,a,cm,bl,sp,d0){
  sw <- sched[Date==d0]; w <- sw$weight[match(tk, sw$Ticker)]; w[is.na(w)]<-0; .cap_iter(.normalize(w))
}

methods <- list(
  Schedule_EWbase= list(fn=function(tk,a,cm,bl,sp,hist=NULL,conf=NULL,d0=NULL) m_schedule(tk,a,cm,bl,sp,d0), use_d0=TRUE),
  EW             = list(fn=function(tk,a,cm,bl,sp,hist=NULL,conf=NULL) m_ew(tk,a,cm,bl,sp)),
  AlphaSoftmax   = list(fn=function(tk,a,cm,bl,sp,hist=NULL,conf=NULL) m_alpha_softmax(tk,a,cm,bl,sp,temp=1.0)),
  MVO_conf       = list(fn=function(tk,a,cm,bl,sp,hist=NULL,conf=NULL) m_mvo(tk,a,cm,bl,sp,lambda=8,conf=conf), use_conf=TRUE),
  ERC            = list(fn=function(tk,a,cm,bl,sp,hist=NULL,conf=NULL) m_erc(tk,a,cm,bl,sp)),
  HRP            = list(fn=function(tk,a,cm,bl,sp,hist=NULL,conf=NULL) m_hrp(tk,a,cm,bl,sp)),
  CVaR_LP        = list(fn=function(tk,a,cm,bl,sp,hist=NULL,conf=NULL) m_cvar(tk,a,cm,bl,sp,hist), use_hist=TRUE),
  MVO_betaneutral= list(fn=function(tk,a,cm,bl,sp,hist=NULL,conf=NULL) m_mvo_betaneutral(tk,a,cm,bl,sp,lambda=8,beta_pen=40,beta_tgt=0.90,conf=conf), use_conf=TRUE)
)

results <- list()
for(nm in names(methods)){
  cfg <- methods[[nm]]
  uh <- isTRUE(cfg$use_hist); uc <- isTRUE(cfg$use_conf); ud <- isTRUE(cfg$use_d0)
  sim <- simulate(cfg$fn, use_hist=uh, use_conf=uc, use_d0=ud)
  mt <- metrics_of(sim)
  mt$sim <- sim
  results[[nm]] <- mt
  cat(sprintf("  %-16s netSR %.4f | netAR %.4f | IR %.3f | TE %.3f | MDD %.3f | TO/yr %.2f\n",
              nm, mt$sr_net, mt$net_active_ret, mt$ir, mt$te, mt$mdd, mt$turnover_yr))
}

saveRDS(results, file.path(OUT_MB,"optimizer_method_results.rds"))
cat("\n[sim] done. results saved.\n")
