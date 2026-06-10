## WT-D20260606_001 Optimizer Research
## Honest question: does residual-mom multi-sleeve + regime/uncertainty overlay lift BOOK SR toward 2.5?
## Constraints: long-only, w in [0,0.20], Sigma w = 1, max 25 names, 15bps, LIQ 2e8 (universe already filtered)
suppressMessages({library(arrow); library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite)})
options(warn=1)
root <- "G:/Quant_Module_Moltbot"; setwd(root)
set.seed(606)

COST_BPS <- 0.0015   # 15bps one-way
OUT <- "stage_artifacts/WT_D20260606_001"

# ============ INPUTS ============
ap <- fromJSON("qepm/mailbox/worktask/WT-D20260606_001/alpha_package.json")
scores <- as.data.table(read_parquet("stage_artifacts/WT_WT-D20260606_001/alpha_scores.parquet"))
scores[, Date := as.Date(Date)]
r05dt <- as.data.table(read_parquet("qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
inc <- copy(r05dt)[!is.na(ret_net)]
setorder(inc, Date)
inc[, ym := format(Date,"%Y-%m")]
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
setkey(RAW, Ticker, Date)   # fast subsetting for per-month cov windows

# ============ STEP 1: build residual-mom sleeve forward 1M returns (contract path, no hand-synth) ============
me <- RAW[!is.na(Close), .SD[.N], by=.(Ticker,ym), .SDcols=c("Date","Close")]
setorder(me, Ticker, Date)
me[, fwd_ret := shift(Close,1L,type="lead")/Close - 1, by=Ticker]
me <- me[is.na(fwd_ret) | (fwd_ret > -0.99 & fwd_ret < 9.0)]
me[!is.na(fwd_ret), fwd_ret := {lo<-quantile(fwd_ret,.01,na.rm=TRUE); hi<-quantile(fwd_ret,.99,na.rm=TRUE); pmin(pmax(fwd_ret,lo),hi)}, by=ym]
ret1m <- me[, .(Ticker, ym, Ret_1m=fwd_ret)]
ret1m_d <- merge(ret1m, unique(scores[,.(ym=format(Date,"%Y-%m"), Date)]), by="ym")
ret1m_d <- ret1m_d[, .(Date, Ticker, Ret_1m)]

# ============ self-contained Ledoit-Wolf shrinkage (2004, constant-correlation target) ============
cov_lw <- function(R){
  # R: T x N return matrix (NA->0 already)
  T <- nrow(R); N <- ncol(R)
  S <- cov(R)
  # shrinkage target: constant correlation
  d <- sqrt(diag(S)); d[d==0] <- 1e-8
  Cor <- S / (d %o% d)
  rbar <- (sum(Cor) - N) / (N*(N-1))
  Target <- rbar * (d %o% d); diag(Target) <- diag(S)
  # shrinkage intensity (simplified Ledoit-Wolf)
  Xc <- scale(R, center=TRUE, scale=FALSE)
  pi_mat <- matrix(0,N,N)
  for(t in 1:T){ xt <- Xc[t,]; M <- (xt %o% xt) - S; pi_mat <- pi_mat + M^2 }
  pi_hat <- sum(pi_mat)/T
  gamma_hat <- sum((Target - S)^2)
  rho_hat <- pi_hat  # diagonal approx for rho (conservative)
  kappa <- (pi_hat - rho_hat)/gamma_hat
  delta <- max(0, min(1, (pi_hat/gamma_hat)/T))
  Sig <- delta*Target + (1-delta)*S
  attr(Sig,"delta") <- delta
  Sig
}
# HRP allocation (Lopez de Prado 2016)
hrp_alloc <- function(cov_mat){
  cor_mat <- cov2cor(cov_mat)
  dist <- sqrt(0.5*(1-cor_mat)); dist[!is.finite(dist)] <- 1
  hc <- hclust(as.dist(dist), method="single")
  sortIx <- hc$order
  getClusterVar <- function(cov, idx){ cI <- cov[idx,idx,drop=FALSE]; iv <- 1/diag(cI); w <- iv/sum(iv); as.numeric(t(w)%*%cI%*%w) }
  w <- rep(1, ncol(cov_mat)); names(w) <- colnames(cov_mat)
  clusters <- list(sortIx)
  while(length(clusters)>0){
    cl <- clusters[[1]]; clusters[[1]] <- NULL
    if(length(cl)<=1) next
    half <- floor(length(cl)/2)
    c1 <- cl[1:half]; c2 <- cl[(half+1):length(cl)]
    v1 <- getClusterVar(cov_mat,c1); v2 <- getClusterVar(cov_mat,c2)
    alpha <- 1 - v1/(v1+v2)
    w[c1] <- w[c1]*alpha; w[c2] <- w[c2]*(1-alpha)
    clusters <- c(clusters, list(c1), list(c2))
  }
  w/sum(w)
}

# ============ helper: build sleeve net monthly series for a chosen internal-weight scheme ============
# scheme in {"EW","MVO","HRP","ERC"} applied to top-N names per month; default top-20
build_sleeve <- function(scheme="EW", topN=20L){
  setorder(scores, Date, -alpha_score)
  hold <- scores[, head(.SD, topN), by=Date]
  # pre-filter RAW to only ever-held tickers (fast)
  held_tk <- unique(hold$Ticker)
  RAWh <- RAW[Ticker %in% held_tk, .(Ticker, Date, Ret)]
  setkey(RAWh, Ticker, Date)
  # internal weights per month
  wlist <- list()
  dates <- sort(unique(hold$Date))
  # precompute daily returns wide for cov when needed
  for(di in seq_along(dates)){
    d <- dates[di]
    h <- hold[Date==d]
    tk <- h$Ticker
    if(scheme=="EW"){
      w <- rep(1/length(tk), length(tk)); names(w) <- tk
    } else {
      # need a trailing daily return cov for these names up to d
      win <- RAWh[.(tk)][Date <= d & Date > (d-400)]
      wide <- dcast(win, Date~Ticker, value.var="Ret")
      mat <- as.matrix(wide[,-1]); mat <- mat[, colSums(!is.na(mat))>120, drop=FALSE]
      mat[is.na(mat)] <- 0
      tk2 <- colnames(mat)
      if(length(tk2) < 3){ w <- rep(1/length(tk),length(tk)); names(w)<-tk } else {
        cm <- tryCatch(cov_lw(mat), error=function(e) cov(mat))
        if(scheme=="MVO"){
          # min-variance long-only via inverse-cov clipped
          ic <- tryCatch(solve(cm + diag(1e-6,nrow(cm))), error=function(e) diag(nrow(cm)))
          raw <- ic %*% rep(1, nrow(cm)); raw <- pmax(raw, 0)
          w0 <- if(sum(raw)>0) raw/sum(raw) else rep(1/nrow(cm),nrow(cm))
          w <- as.numeric(w0); names(w) <- tk2
        } else if(scheme=="HRP"){
          w <- tryCatch(hrp_alloc(cm), error=function(e){v<-rep(1/nrow(cm),nrow(cm));names(v)<-tk2;v})
          names(w) <- tk2
        } else if(scheme=="ERC"){
          # equal risk contribution via simple iteration
          vol <- sqrt(diag(cm)); w <- (1/vol)/sum(1/vol); names(w) <- tk2
        }
        # names dropped for lack of data -> EW fill missing to keep topN
        miss <- setdiff(tk, tk2)
        if(length(miss)>0){ add <- rep(min(w)*0.5, length(miss)); names(add)<-miss; w <- c(w, add) }
      }
    }
    # cap at 0.20 then renormalize (hard constraint)
    w <- pmin(w, 0.20); w <- w/sum(w)
    wlist[[as.character(d)]] <- data.table(Date=d, Ticker=names(w), w=as.numeric(w))
  }
  W <- rbindlist(wlist)
  WR <- merge(W, ret1m_d, by=c("Date","Ticker"), all.x=TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  # gross monthly = sum w*ret ; turnover cost via |w_t - w_{t-1 drifted}| approx -> use simple turnover
  setorder(WR, Date, Ticker)
  port <- WR[, .(gross=sum(w*Ret_1m)), by=Date]
  # turnover: sum abs weight change vs prior month holdings (round-trip handled at book level later)
  Wprev <- copy(W); Wprev[, Date := NA]
  # compute monthly turnover
  Wc <- dcast(W, Date~Ticker, value.var="w", fill=0)
  wm <- as.matrix(Wc[,-1]);
  to <- c(NA, rowSums(abs(wm[-1,,drop=FALSE]-wm[-nrow(wm),,drop=FALSE])))
  port[, turnover_oneway := to]
  port[, cost := fifelse(is.na(turnover_oneway),0, turnover_oneway*COST_BPS)]
  port[, sleeve_net := gross - cost]
  port[, ym := format(Date,"%Y-%m")]
  list(series=port[is.finite(sleeve_net)], weights=W)
}

cat("=== building sleeve series for 4 internal schemes ===\n")
schemes <- c("EW","MVO","HRP","ERC")
sl <- lapply(schemes, function(s){ cat(" scheme",s,"...\n"); build_sleeve(s, 20L) })
names(sl) <- schemes

# ============ STEP 2: align sleeve <-> R05 book ; report standalone & combos ============
metrics_xts <- function(x, scale=12){
  ar <- as.numeric(Return.annualized(x, scale=scale))
  sd <- as.numeric(StdDev.annualized(x, scale=scale))
  sr <- ar/sd
  list(CAGR=ar, Vol=sd, SR=sr, MDD=as.numeric(maxDrawdown(x)))
}
incx <- xts(inc$ret_net, order.by=inc$Date); colnames(incx)<-"R05"
m_r05 <- metrics_xts(incx)
cat(sprintf("\nR05 incumbent book: SR %.3f CAGR %.3f Vol %.3f MDD %.3f (n=%d)\n",
            m_r05$SR,m_r05$CAGR,m_r05$Vol,m_r05$MDD,nrow(inc)))

# function: combine book = (1-a)*R05 + a*sleeve, monthly rebalanced (Return.portfolio 2-asset)
combo_metrics <- function(sleeve_series, a){
  J <- merge(sleeve_series[,.(ym, sleeve_net)], inc[,.(ym, r05_net=ret_net)], by="ym")
  J <- J[is.finite(sleeve_net)&is.finite(r05_net)]
  setorder(J, ym)
  R <- xts(as.matrix(J[,.(R05=r05_net, SLEEVE=sleeve_net)]),
           order.by=as.Date(paste0(J$ym,"-01")))
  bk <- Return.portfolio(R, weights=c(1-a, a), rebalance_on="months")
  list(metrics=metrics_xts(bk), n=nrow(J), book=bk, J=J)
}

cat("\n=== sleeve standalone (4 schemes) ===\n")
for(s in schemes){
  ms <- metrics_xts(xts(sl[[s]]$series$sleeve_net, order.by=sl[[s]]$series$Date))
  cat(sprintf(" %-4s sleeve: SR %.3f CAGR %.3f Vol %.3f MDD %.3f | TO_ann %.2f\n",
      s, ms$SR, ms$CAGR, ms$Vol, ms$MDD, mean(sl[[s]]$series$turnover_oneway,na.rm=TRUE)*12*2))
}

cat("\n=== book = (1-a)R05 + a*sleeve(EW)  : ΔIR scan ===\n")
base_ir <- m_r05$SR  # active-vs-cash proxy; book IR baseline = R05 SR (no benchmark deduction at book level here)
for(a in c(0.05,0.10,0.15,0.20,0.30)){
  cm <- combo_metrics(sl[["EW"]]$series, a)
  cat(sprintf(" a=%.2f  book SR %.3f CAGR %.3f Vol %.3f MDD %.3f  dSR %+.3f\n",
      a, cm$metrics$SR, cm$metrics$CAGR, cm$metrics$Vol, cm$metrics$MDD, cm$metrics$SR-m_r05$SR))
}

saveRDS(list(sl=sl, inc=inc, m_r05=m_r05), file.path(OUT,"opt_intermediate.rds"))
cat("\n[saved opt_intermediate.rds]\n")
