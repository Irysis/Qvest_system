# =============================================================
# WT-D20260529_001 FLOW — Optimizer Research
# Weight 결정만. alpha 재해석/risk 재정의 금지.
# Walk-forward weight schedule (RF-O9) + multi-sleeve blend (STR_1715 + FLOW)
# net-of-cost (15bps one-way) selection_objective = net_ir
# PIT: lockbox 2023-12-22 strict; trailing daily Σ (LW methodology = risk agent's estimator)
# =============================================================
suppressMessages({
  library(data.table); library(arrow); library(lubridate)
  library(PerformanceAnalytics); library(xts); library(quadprog)
})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260529_001_FLOW")
set.seed(42)

LOCKBOX   <- as.Date("2023-12-22")
COST_OW   <- 0.0015          # 15bps one-way (v2.3_kr_retail_15bps)
MAX_NAMES <- 20L
W_CAP     <- 0.20            # request hard bound [0,0.20]
LIQ_FLOOR <- 2e8            # 20d avg trading value
N_DAYS_COV<- 252L            # trailing daily window for rolling Σ
REBAL_FREQ<- "quarterly"     # alpha mandate (5.93/yr passes; monthly 10.66 fails)

# ---- weight infra ----
source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/portfolio/advanced_weights.R")
source("02_Infrastructure/portfolio/mean_variance_optimizer.R")

# =============================================================
# 1. LOAD INPUTS (read-only; no alpha/risk redefinition)
# =============================================================
alpha <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))  # Date,Ticker,alpha_score,confidence
alpha <- alpha[Date <= LOCKBOX]                                             # optimizer = 정규 리서치 → lockbox strict
sig_dates <- sort(unique(alpha$Date))
cat(sprintf("[load] alpha panel: %d rows, %d sig_dates (%s..%s)\n",
            nrow(alpha), length(sig_dates), min(sig_dates), max(sig_dates)))

# Handoff Σ (consistency anchor only — not redefining risk model)
cov_handoff <- as.data.table(read_parquet(file.path(OUT,"covariance.parquet")))
cov_tk <- cov_handoff$Ticker
Sig_handoff <- as.matrix(cov_handoff[, ..cov_tk]); rownames(Sig_handoff) <- cov_tk

# RAWDATA daily (price-derived Ret, label-free; liquidity TV)
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd <- rd[Date <= LOCKBOX, .(Date, Ticker, Ret, Close, Vol,
                            AdminStock, TradingHalt)]
rd[, TV := Close * Vol]
setkey(rd, Date, Ticker)

# STR_1715 monthly returns (existing PG2 baseline — lockbox 폐기 for baseline tracking,
# but here we restrict to overlapping pre-lockbox window for clean apples-to-apples blend)
s1715 <- fread("qepm/mailbox/governor/str_1715_full_reassessment/str_1715_monthly_returns_full.csv")
s1715[, Date := as.Date(Date)]
s1715[, ym := format(Date, "%Y-%m")]

# =============================================================
# 2. WALK-FORWARD SLEEVE BACKTEST (per method)
#    - quarterly rebalance; hold between
#    - top-20 selection by alpha (band-buffer keep_n=20, entry_n=15 Grinold breadth)
#    - liquidity floor 2e8 (t-1 20d avg TV)
#    - net 15bps one-way on realized turnover
# =============================================================

# rebalance dates: quarterly subset of sig_dates
all_idx <- seq_along(sig_dates)
q_dates <- sig_dates[month(sig_dates) %in% c(1,4,7,10)]
# ensure we have enough trailing daily data: first rebal needs N_DAYS_COV history
q_dates <- q_dates[q_dates >= (min(rd$Date) + 400)]
cat(sprintf("[wf] quarterly rebal dates: %d (%s..%s)\n", length(q_dates), min(q_dates), max(q_dates)))

# helper: trailing daily return matrix for a ticker set ending at date d (exclusive of d's same-day; PIT)
build_ret_dt <- function(tickers, d, n_days = N_DAYS_COV) {
  sub <- rd[Ticker %in% tickers & Date < d]   # strictly before rebal date (PIT C2)
  sub <- sub[order(Date)]
  keep_dates <- tail(sort(unique(sub$Date)), n_days)
  sub <- sub[Date %in% keep_dates, .(Date, Ticker, Ret)]
  sub <- sub[!is.na(Ret)]
  sub
}

# helper: select liquid top-20 at rebal date d (band-buffer keep 20, require liquidity)
select_names <- function(d) {
  a <- alpha[Date == d, .(Ticker, alpha_score, confidence)]
  if (nrow(a) == 0) return(NULL)
  # liquidity: trailing 20d avg TV strictly before d (t-1 PIT C10)
  liq <- rd[Date < d & Ticker %in% a$Ticker]
  liq <- liq[order(Ticker, Date)]
  liq20 <- liq[, .(avgTV = mean(tail(TV, 20), na.rm = TRUE),
                   admin = max(tail(AdminStock,1), 0, na.rm=TRUE),
                   halt  = max(tail(TradingHalt,1), 0, na.rm=TRUE)), by = Ticker]
  ok <- liq20[avgTV >= LIQ_FLOOR & (is.na(admin)|admin==0) & (is.na(halt)|halt==0), Ticker]
  a <- a[Ticker %in% ok]
  if (nrow(a) < 10) return(NULL)
  setorder(a, -alpha_score)
  a <- head(a, MAX_NAMES)
  a
}

# weighting dispatchers (all PIT: trailing-only ret_dt)
get_weights <- function(method, names_dt, d) {
  tk <- names_dt$Ticker
  n  <- length(tk)
  ret_dt <- build_ret_dt(tk, d)
  # ensure all tk have data; drop those without
  have <- intersect(tk, unique(ret_dt$Ticker))
  tk2  <- have; n <- length(tk2)
  if (n < 5) return(NULL)
  a_sub <- names_dt[Ticker %in% tk2]
  w <- switch(method,
    "EW" = {
      setNames(rep(1/n, n), tk2)
    },
    "MVO" = {
      # rolling Σ from trailing daily (LW shrinkage methodology = risk agent's estimator)
      rm <- dcast(ret_dt[Ticker %in% tk2], Date ~ Ticker, value.var="Ret")
      rmat <- as.matrix(rm[, -1]); rmat[is.na(rmat)] <- 0
      Sig <- tryCatch(corpcor::cov.shrink(rmat, verbose=FALSE), error=function(e) cov(rmat))
      Sig <- Sig * 252
      al <- setNames(a_sub$alpha_score, a_sub$Ticker)[colnames(rmat)]
      cf <- setNames(a_sub$confidence,  a_sub$Ticker)[colnames(rmat)]
      ww <- tryCatch(
        mvo_weights(alpha=al, cov_matrix=Sig, confidence=cf, lambda=2.0, psi=0.3,
                    bounds=c(0, W_CAP), max_names=MAX_NAMES, min_names=15L,
                    hhi_cap=0.15, alpha_winsor=2.0),
        error=function(e) NULL)
      if (is.null(ww)) return(NULL)
      wv <- ww$weights %||% ww$target_weights %||% ww
      if (is.list(wv)) wv <- unlist(wv)
      wv
    },
    "HRP" = {
      ww <- tryCatch(calc_hrp_weights(tk2, ret_dt, n_days=N_DAYS_COV, max_w=W_CAP),
                     error=function(e) NULL)
      ww
    },
    "ERC" = {
      rm <- dcast(ret_dt[Ticker %in% tk2], Date ~ Ticker, value.var="Ret")
      rmat <- as.matrix(rm[, -1]); rmat[is.na(rmat)] <- 0
      Sig <- tryCatch(corpcor::cov.shrink(rmat, verbose=FALSE), error=function(e) cov(rmat))
      erc_w(Sig, colnames(rmat))
    },
    "CVaR" = {
      ww <- tryCatch(calc_cvar_weights(tk2, ret_dt, n_days=N_DAYS_COV, max_w=W_CAP),
                     error=function(e) NULL)
      ww
    },
    "MinVar" = {
      rm <- dcast(ret_dt[Ticker %in% tk2], Date ~ Ticker, value.var="Ret")
      rmat <- as.matrix(rm[, -1]); rmat[is.na(rmat)] <- 0
      Sig <- tryCatch(corpcor::cov.shrink(rmat, verbose=FALSE), error=function(e) cov(rmat))
      minvar_w(Sig, colnames(rmat))
    },
    NULL)
  if (is.null(w) || length(w) == 0) return(NULL)
  w <- w[!is.na(w)]
  if (length(w) == 0) return(NULL)
  # enforce bounds + normalize
  w <- pmax(pmin(w, W_CAP), 0)
  if (sum(w) <= 0) return(NULL)
  w <- w / sum(w)
  # cap iteration if any > W_CAP after norm
  it <- 0
  while (any(w > W_CAP + 1e-9) && it < 200) {
    over <- w > W_CAP
    excess <- sum(w[over] - W_CAP)
    w[over] <- W_CAP
    under <- !over & w > 0
    if (!any(under)) break
    w[under] <- w[under] + excess * w[under]/sum(w[under])
    w <- w/sum(w); it <- it+1
  }
  w <- w/sum(w)
  w
}

`%||%` <- function(a,b) if (is.null(a)) b else a

# ERC (equal risk contribution) — quadprog-free Newton on log-barrier surrogate
erc_w <- function(Sig, tk) {
  n <- ncol(Sig); x <- rep(1/n, n)
  for (i in 1:300) {
    mrc <- as.numeric(Sig %*% x)
    rc  <- x * mrc
    tgt <- mean(rc)
    grad <- mrc + x*0   # marginal
    x <- x * (tgt / (rc + 1e-12))^0.5
    x <- pmax(x, 1e-8); x <- x/sum(x)
  }
  setNames(x, tk)
}
# Min variance via quadprog (long-only, sum=1, cap)
minvar_w <- function(Sig, tk) {
  n <- ncol(Sig)
  Dmat <- Sig + diag(1e-8, n)
  dvec <- rep(0, n)
  Amat <- cbind(rep(1,n), diag(n), -diag(n))
  bvec <- c(1, rep(0,n), rep(-W_CAP, n))
  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq=1)$solution, error=function(e) rep(1/n,n))
  sol <- pmax(sol, 0); sol <- sol/sum(sol)
  setNames(sol, tk)
}

methods <- c("EW","MVO","HRP","ERC","CVaR","MinVar")

# --- run walk-forward for each method; build monthly net sleeve returns ---
# At each quarterly rebal date d: weights held until next rebal.
# Monthly sleeve return = sum_i w_i(held) * monthly_ret_i over hold months (with monthly weight drift).
# We compute realized monthly returns from daily Ret compounded per month per ticker.

# monthly ticker returns (compounded daily within month)
rd[, ym := format(Date, "%Y-%m")]
mret <- rd[!is.na(Ret), .(mret = prod(1+Ret)-1), by=.(Ticker, ym)]
mret_dates <- sort(unique(alpha[, .(ym=format(Date,"%Y-%m"))]$ym))

# map each month -> active rebal date (most recent quarterly rebal <= that month)
month_to_rebal <- function(m) {
  md <- as.Date(paste0(m,"-01"))
  cand <- q_dates[q_dates <= (md + 31)]   # rebal in or before this month
  if (length(cand)==0) return(NA)
  max(cand)
}

run_method_wf <- function(method) {
  # precompute weights at each rebal date
  wlist <- list()
  for (d in as.character(q_dates)) {
    dd <- as.Date(d)
    nm <- select_names(dd)
    if (is.null(nm)) { wlist[[d]] <- NULL; next }
    w  <- get_weights(method, nm, dd)
    if (is.null(w)) { wlist[[d]] <- NULL; next }
    wlist[[d]] <- w
  }
  # walk months, compute net return + turnover
  months <- mret_dates
  out <- data.table(ym=character(), ret_gross=numeric(), ret_net=numeric(),
                    turnover=numeric(), nnames=integer())
  prev_w <- NULL
  cur_rebal <- NA
  for (m in months) {
    rb <- month_to_rebal(m)
    if (is.na(rb)) next
    w <- wlist[[as.character(rb)]]
    if (is.null(w)) next
    is_rebal_month <- !identical(as.character(rb), as.character(cur_rebal))
    # turnover only at rebal month
    to <- 0
    if (is_rebal_month) {
      if (is.null(prev_w)) {
        to <- sum(abs(w))               # initial build = full
      } else {
        alln <- union(names(prev_w), names(w))
        pw <- setNames(rep(0,length(alln)), alln); pw[names(prev_w)] <- prev_w
        nw <- setNames(rep(0,length(alln)), alln); nw[names(w)] <- w
        to <- sum(abs(nw - pw))         # one-way turnover (sum |Δw|)
      }
      cur_rebal <- rb
    }
    # gross monthly return
    mr <- mret[ym==m & Ticker %in% names(w)]
    if (nrow(mr)==0) next
    wv <- w[mr$Ticker]; wv[is.na(wv)] <- 0
    rg <- sum(wv * mr$mret, na.rm=TRUE)
    rn <- rg - to * COST_OW             # cost charged at rebal month
    out <- rbind(out, data.table(ym=m, ret_gross=rg, ret_net=rn,
                                 turnover=to, nnames=length(w)))
    prev_w <- w
  }
  out
}

cat("\n[wf] running walk-forward per method...\n")
res <- list()
for (mth in methods) {
  cat(sprintf("  - %s ...\n", mth))
  res[[mth]] <- run_method_wf(mth)
}
saveRDS(res, file.path(OUT,"opt_wf_results.rds"))

# =============================================================
# 3. METHOD COMPARISON (net_ir = net Sharpe of sleeve; benchmark-relative IR)
# =============================================================
bm_m <- rd[!is.na(BM_Ret), .(bm=prod(1+BM_Ret)-1), by=ym]
setkey(bm_m, ym)

sleeve_stats <- function(dt) {
  dt <- merge(dt, bm_m, by="ym", all.x=TRUE)
  dt[, active := ret_net - bm]
  rn <- dt$ret_net; ac <- dt$active
  ann_ret <- prod(1+rn)^(12/length(rn)) - 1
  ann_vol <- sd(rn)*sqrt(12)
  net_sr  <- mean(rn)/sd(rn)*sqrt(12)
  ir      <- mean(ac)/sd(ac)*sqrt(12)
  te      <- sd(ac)*sqrt(12)
  ann_to  <- sum(dt$turnover) / (length(rn)/12)   # one-way per year
  list(net_sr=net_sr, ir=ir, te=te, ann_ret=ann_ret, ann_vol=ann_vol,
       ann_to=ann_to, n=length(rn))
}

comp <- rbindlist(lapply(methods, function(m){
  s <- sleeve_stats(res[[m]])
  data.table(method=m, net_sr=round(s$net_sr,4), ir=round(s$ir,4),
             te=round(s$te,4), ann_ret=round(s$ann_ret,4),
             ann_vol=round(s$ann_vol,4), ann_to=round(s$ann_to,3), n=s$n)
}))
setorder(comp, -ir)
cat("\n=== SLEEVE-LEVEL METHOD COMPARISON (net-of-cost) ===\n")
print(comp)
fwrite(comp, file.path(OUT,"method_comparison.csv"))

# selection: net_ir; but disqualify TO>6.0/yr (Implementation Discipline)
comp[, to_pass := ann_to <= 6.0]
elig <- comp[to_pass == TRUE]
sel_method <- elig[which.max(ir), method]
cat(sprintf("\n[select] method (max net_ir among TO<=6.0): %s\n", sel_method))

saveRDS(list(comp=comp, sel_method=sel_method, res=res, bm_m=bm_m),
        file.path(OUT,"opt_stage2.rds"))
cat("\n[done stage 1-3]\n")
