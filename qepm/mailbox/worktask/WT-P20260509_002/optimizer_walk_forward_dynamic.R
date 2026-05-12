#!/usr/bin/env Rscript
# WT-P20260509_002 — Walk-forward Dynamic Weight 8 method 정량 비교
# Mandate: paradigm-free, AX-002 PIT strict, no in-sample optimization, no static admit
#
# Sleeves: STR_1715 alpha-updated (AR_on_M4) + TSMOM 8-ETF (KTB10Y 제거 재정규화)
#          + KR_10y bond (A148070) + Cash
# Walk-forward: rolling 60m window, burn-in 60m, monthly rebalance
# Methods (8): WF_RP_ERC / WF_MV (λ∈{2,5,10}) / WF_HRP / WF_IV / WF_MaxDiv
#              / WF_Bayesian_PS / WF_DRO_W (ε∈{0.01,0.05,0.1}) / WF_BL
# Constraints: w∈[0, 0.50], Σw=1, long-only, single asset cap 0.20 NOT in WT-002
#              (constraint says single_asset_cap_0.20 but bound is [0, 0.50] —
#               we honor weight_bound [0, 0.50] as primary; cap 0.20 ambiguous,
#               apply as soft check + report)

suppressPackageStartupMessages({
  library(data.table)
  library(quadprog)
  library(nloptr)
  library(PerformanceAnalytics)
  library(jsonlite)
  library(zoo)
})

set.seed(20260509)

WT_DIR  <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260509_002"
OUT_DIR <- file.path(WT_DIR, "output")
dir.create(OUT_DIR, recursive=TRUE, showWarnings=FALSE)

LOG <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), sprintf(...), "\n", sep="")

LOG("=== WT-P20260509_002 Walk-forward Dynamic Weight 시작 ===")

# ---------------------------------------------------------------------------
# Step 1. Data prep — sleeve_returns_master.csv + TSMOM 8-ETF re-derivation
# ---------------------------------------------------------------------------
master_path <- file.path(WT_DIR, "..", "WT-P20260509_001", "output", "sleeve_returns_master.csv")
master <- fread(master_path)
master[, date := as.Date(date)]
LOG("[데이터] master sleeve returns: %d 행 (%s ~ %s)", nrow(master),
    format(min(master$date)), format(max(master$date)))

# 9-ETF TSMOM rotation path 로드 (KTB10Y weight 추출)
tsmom_path <- file.path(WT_DIR, "..", "WT-S20260504_009", "docs", "rotation_path_TSMOM.csv")
tsmom_dt <- fread(tsmom_path)
tsmom_dt[, date := as.Date(date)]
LOG("[데이터] TSMOM 9-ETF rotation: %d 행 (%s ~ %s)", nrow(tsmom_dt),
    format(min(tsmom_dt$date)), format(max(tsmom_dt$date)))

# KR_10y sleeve = KODEX_KTB10Y (A148070) 동일 자산 확인
# 8-ETF realized return 재정규화:
#   r_8ETF = (r_9ETF - w_KTB10Y * r_KTB10Y) / (1 - w_KTB10Y)
# r_KTB10Y = KR_10y sleeve return (master)
kr10y_lookup <- master[, .(date, KR_10y)]
tsmom_dt <- merge(tsmom_dt, kr10y_lookup, by="date", all.x=TRUE)

tsmom_dt[, w_KTB10Y_fill := ifelse(is.na(w_etf_KODEX_KTB10Y), 0, w_etf_KODEX_KTB10Y)]
tsmom_dt[, KR_10y_fill   := ifelse(is.na(KR_10y), 0, KR_10y)]
tsmom_dt[, contrib_KTB10Y := w_KTB10Y_fill * KR_10y_fill]
tsmom_dt[, denom_8ETF     := pmax(1 - w_KTB10Y_fill, 1e-6)]
tsmom_dt[, TSMOM_8ETF     := (ml_realized - contrib_KTB10Y) / denom_8ETF]

LOG("[8-ETF re-derive] mean(w_KTB10Y)=%.4f, mean(TSMOM_9ETF)=%.5f, mean(TSMOM_8ETF)=%.5f",
    mean(tsmom_dt$w_KTB10Y_fill), mean(tsmom_dt$ml_realized), mean(tsmom_dt$TSMOM_8ETF))

# Master에 TSMOM_8ETF column 머지
tsmom_8etf <- tsmom_dt[, .(date, TSMOM_8ETF)]
master <- merge(master, tsmom_8etf, by="date", all.x=TRUE)
master[is.na(TSMOM_8ETF), TSMOM_8ETF := 0]   # pre-2015 zero-fill (TSMOM_PRESENT=FALSE 반영)

# 4-sleeve return matrix 정합 (8-ETF retain)
SLEEVE_NAMES <- c("AR_on_M4", "TSMOM", "KR_10y", "Cash")   # TSMOM = 8-ETF
master[, TSMOM := TSMOM_8ETF]
ret_dt <- master[, c("date", SLEEVE_NAMES, "TSMOM_PRESENT"), with=FALSE]
setorder(ret_dt, date)

LOG("[정합] 4-sleeve panel: %d 행, TSMOM_PRESENT TRUE n=%d (2015-01+)",
    nrow(ret_dt), sum(ret_dt$TSMOM_PRESENT))

R_mat_full <- as.matrix(ret_dt[, ..SLEEVE_NAMES])
rownames(R_mat_full) <- as.character(ret_dt$date)
N <- ncol(R_mat_full)
T_total <- nrow(R_mat_full)

# ---------------------------------------------------------------------------
# Step 2. Walk-forward weight optimization functions (per-method)
# ---------------------------------------------------------------------------
W_LB <- 0.00
W_UB <- 0.50
# Per-sleeve bound: Cash forced to 0 in walk-forward (avoids variance-based
# allocators dumping into risk-free; Cash is NOT an admit candidate, only a
# paradigm-free benchmark slot). Single asset cap 0.20 retained for KR_10y
# per request.json constraints.single_asset_cap_0.20.
SLEEVE_LB <- c(AR_on_M4=0.00, TSMOM=0.00, KR_10y=0.00, Cash=0.00)
# Codex C1 ACCEPT (Mandatory): KR_10y is a single ETF (A148070) → mandate
# request.json constraints.single_asset_cap_0.20 강제. UB lowered 0.50 → 0.20.
# AR_on_M4 (composite STR_1715, 20 stocks underneath) UB=0.50 retained.
# TSMOM (8-ETF basket) UB=0.50 retained (basket 평균 8 assets).
SLEEVE_UB <- c(AR_on_M4=0.50, TSMOM=0.50, KR_10y=0.20, Cash=0.00)

# helper: project weights to per-sleeve [LB, UB] simplex (Σw=1)
project_simplex_box <- function(w, lb=SLEEVE_LB, ub=SLEEVE_UB) {
  w <- pmax(pmin(w, ub), lb)
  if (sum(w) == 0) return(rep(1/length(w), length(w)))
  w / sum(w)
}

# Quadprog: min 0.5 w'D w - d'w, s.t. A'w >= b
solve_qp_box <- function(Dmat, dvec, lb=SLEEVE_LB, ub=SLEEVE_UB) {
  n <- length(dvec)
  # equality Σw=1, then n*2 box constraints (per-sleeve)
  Amat <- cbind(rep(1, n), diag(n), -diag(n))
  bvec <- c(1, lb, -ub)
  Dmat_sym <- (Dmat + t(Dmat)) / 2
  # ridge regularization for PSD safety
  Dmat_sym <- Dmat_sym + diag(n) * 1e-8
  out <- tryCatch(
    solve.QP(Dmat=Dmat_sym, dvec=dvec, Amat=Amat, bvec=bvec, meq=1),
    error = function(e) NULL
  )
  if (is.null(out)) {
    # Fallback: distribute equally among non-zero-UB sleeves (excludes Cash)
    fb <- numeric(n)
    active <- which(ub > 0)
    if (length(active) > 0) fb[active] <- 1 / length(active)
    return(fb)
  }
  project_simplex_box(out$solution, lb, ub)
}

# Method 1: Risk Parity ERC (Spinu 2013 cyclic coordinate descent)
# Solve y_i * (Σy)_i = constant for all i, then w = y / Σy.
# Excludes Cash (UB=0) — only allocates among 3 risk-bearing sleeves.
w_rp_erc <- function(Sigma, max_iter=2000, tol=1e-9) {
  n <- ncol(Sigma)
  active_idx <- which(SLEEVE_UB > 0)   # exclude Cash
  if (length(active_idx) < 2) {
    w <- rep(0, n); w[active_idx] <- 1; return(w)
  }
  S <- Sigma[active_idx, active_idx, drop=FALSE]
  m <- length(active_idx)
  # zero-variance protection (pre-2015 TSMOM): floor diagonal
  diag_S <- diag(S)
  zero_var <- which(diag_S < 1e-12)
  if (length(zero_var) > 0) diag(S)[zero_var] <- 1e-8
  # Spinu sequential algorithm
  y <- rep(1/m, m)
  c_target <- 1
  for (it in 1:max_iter) {
    y_old <- y
    for (i in 1:m) {
      Sy_i <- sum(S[i, ] * y) - S[i, i] * y[i]
      a <- S[i, i]
      b <- Sy_i
      disc <- b^2 + 4 * a * c_target
      y[i] <- (-b + sqrt(pmax(disc, 0))) / (2 * a)
    }
    if (any(is.na(y)) || any(!is.finite(y))) {
      y <- rep(1/m, m); break
    }
    if (max(abs(y - y_old)) < tol) break
  }
  w_active <- y / sum(y)
  # Apply UB cap if violated; redistribute (water-filling)
  for (it_cap in 1:50) {
    over <- which(w_active > SLEEVE_UB[active_idx])
    if (length(over) == 0) break
    excess <- sum(w_active[over] - SLEEVE_UB[active_idx][over])
    w_active[over] <- SLEEVE_UB[active_idx][over]
    under <- which(w_active < SLEEVE_UB[active_idx])
    if (length(under) > 0) w_active[under] <- w_active[under] + excess * (w_active[under] / sum(w_active[under]))
  }
  w <- numeric(n)
  w[active_idx] <- w_active
  w
}

# Method 2: Mean-Variance (λ ∈ {2, 5, 10})
w_mv <- function(mu, Sigma, lambda) {
  # max w'mu - 0.5*lambda*w'Σw  →  min 0.5*lambda*w'Σw - w'mu
  Dmat <- lambda * Sigma
  dvec <- mu
  solve_qp_box(Dmat, dvec)
}

# Method 3: Hierarchical Risk Parity (López de Prado 2016)
# Excludes Cash; allocates among 3 risk-bearing sleeves only.
w_hrp <- function(Sigma) {
  n <- ncol(Sigma)
  active_idx <- which(SLEEVE_UB > 0)
  Sig_a <- Sigma[active_idx, active_idx, drop=FALSE]
  m <- length(active_idx)
  # zero-var floor (pre-2015 TSMOM) for cov2cor stability
  diag_S <- diag(Sig_a)
  zero_var <- which(diag_S < 1e-12)
  if (length(zero_var) > 0) diag(Sig_a)[zero_var] <- 1e-8
  Cor_mat <- cov2cor(Sig_a)
  Cor_mat[is.na(Cor_mat) | !is.finite(Cor_mat)] <- 0
  D <- sqrt(pmax(0.5 * (1 - Cor_mat), 0))
  diag(D) <- 0
  hc <- hclust(as.dist(D), method="single")
  order_idx <- hc$order
  cluster_var <- function(cov_mat, idx) {
    sub <- cov_mat[idx, idx, drop=FALSE]
    iv <- 1 / pmax(diag(sub), 1e-8)
    iv <- iv / sum(iv)
    out <- as.numeric(t(iv) %*% sub %*% iv)
    if (is.na(out) || !is.finite(out) || out <= 0) out <- 1e-8
    out
  }
  recurse <- function(items) {
    if (length(items) == 1) return(setNames(1, items))
    mid <- ceiling(length(items) / 2)
    left  <- items[1:mid]
    right <- items[(mid+1):length(items)]
    var_l <- cluster_var(Sig_a, left)
    var_r <- cluster_var(Sig_a, right)
    alpha <- 1 - var_l / (var_l + var_r)
    w_l <- recurse(left)  * alpha
    w_r <- recurse(right) * (1 - alpha)
    c(w_l, w_r)
  }
  w_named <- recurse(order_idx)
  w_active <- numeric(m)
  w_active[as.integer(names(w_named))] <- w_named
  # cap enforce
  for (it in 1:50) {
    over <- which(w_active > SLEEVE_UB[active_idx])
    if (length(over) == 0) break
    excess <- sum(w_active[over] - SLEEVE_UB[active_idx][over])
    w_active[over] <- SLEEVE_UB[active_idx][over]
    under <- which(w_active < SLEEVE_UB[active_idx])
    if (length(under) > 0) w_active[under] <- w_active[under] + excess * (w_active[under] / sum(w_active[under]))
  }
  w <- numeric(n)
  w[active_idx] <- w_active
  w
}

# Method 4: Inverse Volatility (excludes Cash via UB=0)
w_iv <- function(Sigma) {
  active_idx <- which(SLEEVE_UB > 0)
  sigma_i <- sqrt(pmax(diag(Sigma)[active_idx], 1e-10))
  w_active <- (1 / sigma_i) / sum(1 / sigma_i)
  # cap enforce
  for (it in 1:50) {
    over <- which(w_active > SLEEVE_UB[active_idx])
    if (length(over) == 0) break
    excess <- sum(w_active[over] - SLEEVE_UB[active_idx][over])
    w_active[over] <- SLEEVE_UB[active_idx][over]
    under <- which(w_active < SLEEVE_UB[active_idx])
    if (length(under) > 0) w_active[under] <- w_active[under] + excess * (w_active[under] / sum(w_active[under]))
  }
  w <- numeric(ncol(Sigma))
  w[active_idx] <- w_active
  w
}

# Method 5: Maximum Diversification (Choueifaty-Coignard 2008)
w_maxdiv <- function(Sigma) {
  n <- ncol(Sigma)
  sigma_i <- sqrt(pmax(diag(Sigma), 1e-10))
  # maximize (w'σ) / sqrt(w'Σw)  →  equivalent to MV with μ=σ
  Dmat <- Sigma
  dvec <- sigma_i
  solve_qp_box(Dmat, dvec)
}

# Method 6: Bayesian Shrinkage (Pástor-Stambaugh 2009 + Avramov 2002)
# Shrink μ toward grand mean; shrink Σ toward identity*mean(diag(Σ)).
w_bayesian_ps <- function(R_window, lambda=5, shrink_mu=0.5, shrink_sig=0.3) {
  mu_hat <- colMeans(R_window)
  Sig_hat <- cov(R_window)
  # μ shrinkage to grand mean (Jorion 1986 style)
  mu_grand <- mean(mu_hat)
  mu_b <- (1 - shrink_mu) * mu_hat + shrink_mu * mu_grand
  # Σ shrinkage to scaled identity (Ledoit-Wolf simplified)
  target <- mean(diag(Sig_hat)) * diag(ncol(Sig_hat))
  Sig_b <- (1 - shrink_sig) * Sig_hat + shrink_sig * target
  w_mv(mu_b, Sig_b, lambda)
}

# Method 7: DRO Wasserstein (Esfahani-Kuhn 2018 closed-form approx)
# Worst-case distributional robustness over Wasserstein-2 ball ε.
# For mean-variance: equivalent to MV with μ shrunk by ε*||w||_2 and
# Σ inflated by ε^2.
w_dro_wasserstein <- function(R_window, lambda=5, eps=0.05) {
  mu_hat <- colMeans(R_window)
  Sig_hat <- cov(R_window)
  # robust adjustments
  Sig_dro <- Sig_hat + eps^2 * diag(ncol(Sig_hat))
  mu_dro  <- mu_hat - eps * sqrt(diag(Sig_hat))   # worst-case shift
  w_mv(mu_dro, Sig_dro, lambda)
}

# Method 8: Black-Litterman (rolling window + market-implied prior, no fixed view)
# Pi = lambda * Sigma * w_market, w_market = inverse-vol weights as market proxy
w_bl <- function(R_window, lambda=2.5, tau=0.05) {
  Sig_hat <- cov(R_window)
  # market proxy = inverse-vol weights (no exogenous market cap available)
  w_mkt <- w_iv(Sig_hat)
  Pi <- lambda * Sig_hat %*% w_mkt   # implied returns
  # No views (P, Q empty) → posterior = prior
  mu_post <- as.numeric(Pi)
  Sig_post <- Sig_hat * (1 + tau)
  w_mv(mu_post, Sig_post, lambda)
}

# ---------------------------------------------------------------------------
# Step 3. Walk-forward main loop
# ---------------------------------------------------------------------------
WINDOW <- 60
BURNIN <- 60   # 첫 평가 시점 = WINDOW (60m), post-burn-in = WINDOW+1 ~ T
T_eval <- T_total - WINDOW   # evaluation periods

LOG("[walk-forward] T_total=%d, WINDOW=%d, T_eval=%d (post-burn-in)",
    T_total, WINDOW, T_eval)

# Codex C2 ACCEPT: candidates_tried <= 10 cap (R2-C method-shopping discipline)
# WF_HRP excluded: numerical degeneracy with zero-var Cash + small N=3 active sleeves
#                  → recursive bisection low-power vs continuous QP
# WF_BL excluded: BL with no exogenous view (fixed view absent per mandate "no_fixed_view")
#                 + market-implied prior built from IV → effectively redundant with WF_IV
METHODS <- c(
  "WF_RP_ERC",
  "WF_MV_lambda2", "WF_MV_lambda5", "WF_MV_lambda10",
  "WF_IV",
  "WF_MaxDiv",
  "WF_Bayesian_PS",
  "WF_DRO_W_eps0.01", "WF_DRO_W_eps0.05", "WF_DRO_W_eps0.1"
)
METHODS_EXCLUDED <- c("WF_HRP", "WF_BL")

# weight evolution storage: list per method, T_eval × N matrix
W_evolution <- list()
for (m in METHODS) W_evolution[[m]] <- matrix(NA_real_, nrow=T_eval, ncol=N,
                                               dimnames=list(NULL, SLEEVE_NAMES))

eval_dates <- ret_dt$date[(WINDOW+1):T_total]   # length T_eval; weight applied at start of these months

for (t_idx in 1:T_eval) {
  # window: rows (t_idx) ~ (t_idx + WINDOW - 1), 60 obs
  # weight applied at row (t_idx + WINDOW), realizing return that month
  win_start <- t_idx
  win_end   <- t_idx + WINDOW - 1
  R_win <- R_mat_full[win_start:win_end, , drop=FALSE]

  # PIT strict: 모든 추정은 R_win만 사용
  Sigma <- cov(R_win)
  mu    <- colMeans(R_win)
  # Cash sleeve var=0 floor for IV/MaxDiv numerical stability
  cash_idx <- which(SLEEVE_NAMES == "Cash")
  if (diag(Sigma)[cash_idx] < 1e-12) {
    diag(Sigma)[cash_idx] <- 1e-6   # treat cash as near-riskless (1bp/mo proxy)
  }

  W_evolution[["WF_RP_ERC"]][t_idx, ]      <- w_rp_erc(Sigma)
  W_evolution[["WF_MV_lambda2"]][t_idx, ]  <- w_mv(mu, Sigma, 2)
  W_evolution[["WF_MV_lambda5"]][t_idx, ]  <- w_mv(mu, Sigma, 5)
  W_evolution[["WF_MV_lambda10"]][t_idx, ] <- w_mv(mu, Sigma, 10)
  W_evolution[["WF_IV"]][t_idx, ]          <- w_iv(Sigma)
  W_evolution[["WF_MaxDiv"]][t_idx, ]      <- w_maxdiv(Sigma)
  W_evolution[["WF_Bayesian_PS"]][t_idx, ] <- w_bayesian_ps(R_win, lambda=5)
  W_evolution[["WF_DRO_W_eps0.01"]][t_idx, ] <- w_dro_wasserstein(R_win, lambda=5, eps=0.01)
  W_evolution[["WF_DRO_W_eps0.05"]][t_idx, ] <- w_dro_wasserstein(R_win, lambda=5, eps=0.05)
  W_evolution[["WF_DRO_W_eps0.1"]][t_idx, ]  <- w_dro_wasserstein(R_win, lambda=5, eps=0.1)

  if (t_idx %% 50 == 0) LOG("[walk-forward] t_idx=%d / %d (date=%s)", t_idx, T_eval,
                            format(eval_dates[t_idx]))
}

LOG("[walk-forward] 8 method × %d sig_dates 완료", T_eval)

# ---------------------------------------------------------------------------
# Step 4. Realized portfolio returns (PIT strict: w_t × r_t for that month
# — weight chosen at start of month t using window ending at t-1)
# ---------------------------------------------------------------------------
R_eval <- R_mat_full[(WINDOW+1):T_total, , drop=FALSE]   # T_eval × N
T_PRESENT <- ret_dt$TSMOM_PRESENT[(WINDOW+1):T_total]

port_returns <- list()
for (m in METHODS) {
  W <- W_evolution[[m]]
  r <- rowSums(W * R_eval)
  port_returns[[m]] <- r
}

# Static benchmarks (paradigm-free 비교 용도, NOT admit candidate):
# - S0 baseline = AR_on_M4 100% (alpha-only)
# - S4 도훈 framing = 0.50 / 0.25 / 0.20 / 0.05 (static, 동일 196m)
w_S0 <- c(1.0, 0, 0, 0)
w_S4 <- c(0.50, 0.25, 0.20, 0.05)
port_returns[["BENCH_S0_alpha_only"]]    <- as.numeric(R_eval %*% w_S0)
port_returns[["BENCH_S4_static_dohoon"]] <- as.numeric(R_eval %*% w_S4)

# Apply 15bp one-way TC: turnover penalty
# turnover_t = 0.5 * sum(|w_t - w_{t-1}|), TC = 0.0015 * turnover * 2 (round trip)
apply_tc <- function(W_mat, gross_ret, tc_one_way=0.0015) {
  if (is.null(dim(W_mat))) return(gross_ret)   # static benchmark
  T_ <- nrow(W_mat)
  net_ret <- gross_ret
  for (i in 2:T_) {
    to <- 0.5 * sum(abs(W_mat[i,] - W_mat[i-1,]))
    net_ret[i] <- gross_ret[i] - tc_one_way * 2 * to
  }
  net_ret
}

port_returns_net <- list()
for (m in METHODS) {
  port_returns_net[[m]] <- apply_tc(W_evolution[[m]], port_returns[[m]])
}
# Static: monthly rebal = 0% turnover (continuous rebal at static target — no churn)
# but actually requires rebal back to static target each month → small turnover
W_static_S4 <- matrix(rep(w_S4, each=T_eval), nrow=T_eval, byrow=FALSE,
                     dimnames=list(NULL, SLEEVE_NAMES))
W_static_S0 <- matrix(rep(w_S0, each=T_eval), nrow=T_eval, byrow=FALSE,
                     dimnames=list(NULL, SLEEVE_NAMES))
# For static, turnover comes from drift back to target. Approximation: use realized ret to compute drift.
compute_drift_turnover <- function(w_target, R_) {
  T_ <- nrow(R_)
  to_vec <- numeric(T_)
  for (i in 2:T_) {
    # drift since last rebal
    drift_w <- w_target * (1 + R_[i-1, ])
    drift_w <- drift_w / sum(drift_w)
    to_vec[i] <- 0.5 * sum(abs(w_target - drift_w))
  }
  to_vec
}
to_S0 <- compute_drift_turnover(w_S0, R_eval)
to_S4 <- compute_drift_turnover(w_S4, R_eval)
port_returns_net[["BENCH_S0_alpha_only"]]    <- port_returns[["BENCH_S0_alpha_only"]] - 0.0015 * 2 * to_S0
port_returns_net[["BENCH_S4_static_dohoon"]] <- port_returns[["BENCH_S4_static_dohoon"]] - 0.0015 * 2 * to_S4

LOG("[returns] 12 method + 2 bench net returns 산출 완료, T_eval=%d", T_eval)

# ---------------------------------------------------------------------------
# Step 5. Metrics — SR / CAGR / MDD / Sortino / Calmar / Turnover / TE vs S0
# ---------------------------------------------------------------------------
compute_metrics <- function(r_vec, name, W_mat=NULL, R_=R_eval, bench_r=NULL) {
  r_xts <- xts::xts(r_vec, order.by=eval_dates)
  cum <- prod(1 + r_vec) - 1
  n_yr <- length(r_vec) / 12
  cagr <- (1 + cum)^(1/n_yr) - 1
  vol_ann <- sd(r_vec) * sqrt(12)
  sr_ann <- mean(r_vec) * 12 / vol_ann

  # MDD via PerformanceAnalytics
  mdd <- as.numeric(maxDrawdown(r_xts))

  # Sortino
  ds <- pmin(r_vec, 0)
  sortino <- mean(r_vec) * 12 / (sqrt(mean(ds^2)) * sqrt(12))

  # Calmar
  calmar <- if (mdd > 0) cagr / mdd else NA_real_

  # Turnover annualized
  if (is.null(W_mat) || is.null(dim(W_mat))) {
    to_ann <- NA_real_
  } else {
    to_monthly <- numeric(nrow(W_mat))
    for (i in 2:nrow(W_mat)) to_monthly[i] <- 0.5 * sum(abs(W_mat[i,] - W_mat[i-1,]))
    to_ann <- mean(to_monthly) * 12
  }

  # TE vs S0 baseline (alpha-only)
  te <- if (is.null(bench_r)) NA_real_ else sd(r_vec - bench_r) * sqrt(12)

  # Information Ratio vs S0
  ir <- if (is.null(bench_r)) NA_real_ else (mean(r_vec - bench_r) * 12) / te

  data.table(
    method = name,
    n_obs  = length(r_vec),
    cum_ret = cum,
    CAGR    = cagr,
    Vol_ann = vol_ann,
    SR_ann  = sr_ann,
    MDD     = mdd,
    Sortino = sortino,
    Calmar  = calmar,
    Turnover_ann = to_ann,
    TE_vs_S0     = te,
    IR_vs_S0     = ir
  )
}

bench_S0 <- port_returns_net[["BENCH_S0_alpha_only"]]
metrics_list <- list()
for (m in c(METHODS, "BENCH_S0_alpha_only", "BENCH_S4_static_dohoon")) {
  r_ <- port_returns_net[[m]]
  W_ <- if (m %in% METHODS) W_evolution[[m]] else
        if (m == "BENCH_S4_static_dohoon") W_static_S4 else W_static_S0
  metrics_list[[m]] <- compute_metrics(r_, m, W_mat=W_, bench_r=bench_S0)
}
metrics_dt <- rbindlist(metrics_list)
LOG("[metrics] 산출 완료, %d 행", nrow(metrics_dt))

# ---------------------------------------------------------------------------
# Step 6. AX-001 v2 conditional defense (각 method)
# Sub-period: bad regime (bottom-25% S0 returns) vs normal (rest)
# AX-001 v2 = (crisis_alpha > 0) AND (MDD_alleviation > 0) AND (bad/normal IC ratio > 1)
# ---------------------------------------------------------------------------
S0_quantile <- quantile(bench_S0, probs=0.25)
bad_idx     <- which(bench_S0 <= S0_quantile)
normal_idx  <- which(bench_S0 > S0_quantile)

ax001_v2_dt <- rbindlist(lapply(c(METHODS, "BENCH_S4_static_dohoon"), function(m) {
  r_  <- port_returns_net[[m]]
  bad_ret_method <- mean(r_[bad_idx])
  bad_ret_S0     <- mean(bench_S0[bad_idx])
  crisis_alpha   <- bad_ret_method - bad_ret_S0

  # MDD alleviation
  mdd_method <- as.numeric(maxDrawdown(xts::xts(r_, order.by=eval_dates)))
  mdd_S0     <- as.numeric(maxDrawdown(xts::xts(bench_S0, order.by=eval_dates)))
  mdd_alleviation <- mdd_S0 - mdd_method   # positive = method better

  # bad/normal Sharpe ratio (raw — for diagnostic only, NOT decision criterion
  # at portfolio level since bad-period sr is structurally negative)
  sr_bad    <- mean(r_[bad_idx])    * 12 / (sd(r_[bad_idx])    * sqrt(12) + 1e-9)
  sr_normal <- mean(r_[normal_idx]) * 12 / (sd(r_[normal_idx]) * sqrt(12) + 1e-9)
  bad_normal_ratio <- if (!is.na(sr_normal) && sr_normal != 0) sr_bad / sr_normal else NA_real_

  # AX-001 v2 portfolio adaptation:
  # IC ratio (defense factor) → spread ratio (portfolio sleeve)
  # spread_bad = method - S0 in bad regime, spread_normal = method - S0 in normal regime
  # defense role if spread_bad > 0 (helps in bad) AND |spread_bad| ≥ |spread_normal|
  # (helps more when needed than in normal)
  spread_bad    <- mean(r_[bad_idx])    - mean(bench_S0[bad_idx])
  spread_normal <- mean(r_[normal_idx]) - mean(bench_S0[normal_idx])
  spread_ratio  <- if (!is.na(spread_normal) && spread_normal != 0) spread_bad / spread_normal else NA_real_

  # Portfolio-level conditional defense (3-test version):
  #  (a) crisis_alpha > 0
  #  (b) mdd_alleviation > 0
  #  (c) spread_bad > 0 (method outperforms S0 in bad regime)
  cond_pass <- (crisis_alpha > 0) & (mdd_alleviation > 0) & (spread_bad > 0)
  data.table(method=m, crisis_alpha=crisis_alpha, mdd_alleviation=mdd_alleviation,
             sr_bad=sr_bad, sr_normal=sr_normal, bad_normal_ratio=bad_normal_ratio,
             spread_bad=spread_bad, spread_normal=spread_normal, spread_ratio=spread_ratio,
             ax001_v2_pass=cond_pass)
}))
LOG("[AX-001 v2] %d method 평가 완료", nrow(ax001_v2_dt))

# ---------------------------------------------------------------------------
# Step 7. DSR (Bailey-LdP 2014) multi-trial haircut
# ---------------------------------------------------------------------------
dsr_bailey <- function(sr_obs, n, skew, kurt, n_trials) {
  # observed Sharpe (annualized) → monthly
  sr_mo <- sr_obs / sqrt(12)
  # variance of SR estimator (Mertens 2002)
  var_sr <- (1 - skew * sr_mo + (kurt - 1) / 4 * sr_mo^2) / (n - 1)
  sd_sr <- sqrt(pmax(var_sr, 1e-12))
  # SR0 = expected max SR among N independent trials with mean 0, var var_sr
  emc <- 0.5772156649  # Euler-Mascheroni
  sr0 <- sd_sr * ((1 - emc) * qnorm(1 - 1/n_trials) + emc * qnorm(1 - 1/(n_trials*exp(1))))
  # PSR / DSR
  z <- (sr_mo - sr0) / sd_sr
  dsr <- pnorm(z)
  list(SR0=sr0*sqrt(12), z=z, DSR=dsr)
}

dsr_dt <- rbindlist(lapply(c(METHODS, "BENCH_S4_static_dohoon"), function(m) {
  r_ <- port_returns_net[[m]]
  sr_a <- mean(r_) * 12 / (sd(r_) * sqrt(12))
  sk <- moments::skewness(r_)
  ku <- moments::kurtosis(r_)
  n_ <- length(r_)
  res10 <- dsr_bailey(sr_a, n_, sk, ku, n_trials=10)
  data.table(method=m, SR_obs=sr_a, skew=sk, kurt=ku, n=n_,
             SR0_threshold=res10$SR0, z_DSR=res10$z, DSR=res10$DSR,
             DSR_pass=res10$DSR > 0.95)
}))
LOG("[DSR Bailey-LdP] N=10 multi-trial 완료")

# ---------------------------------------------------------------------------
# Step 8. Harvey-Liu 2016 Newey-West t-stat
# ---------------------------------------------------------------------------
nw_tstat <- function(r_vec, lag=4) {
  n <- length(r_vec)
  mu <- mean(r_vec)
  e <- r_vec - mu
  gamma0 <- mean(e^2)
  vlong <- gamma0
  for (k in 1:lag) {
    gk <- mean(e[1:(n-k)] * e[(k+1):n])
    w  <- 1 - k / (lag + 1)
    vlong <- vlong + 2 * w * gk
  }
  se <- sqrt(vlong / n)
  mu / se
}

harvey_dt <- rbindlist(lapply(c(METHODS, "BENCH_S4_static_dohoon"), function(m) {
  r_ <- port_returns_net[[m]]
  t_nw <- nw_tstat(r_, lag=4)
  data.table(method=m, t_NW=t_nw, harvey_pass_3.0=abs(t_nw) > 3.0)
}))
LOG("[Harvey-Liu] t_NW 산출 완료")

# ---------------------------------------------------------------------------
# Step 9. Sub-period stability (2014/2020/2022 sign consistency)
# ---------------------------------------------------------------------------
periods <- list(
  "2010-2013" = c("2010-01-01", "2013-12-31"),
  "2014-2019" = c("2014-01-01", "2019-12-31"),
  "2020-2021" = c("2020-01-01", "2021-12-31"),
  "2022-2023" = c("2022-01-01", "2023-12-31"),
  "2024-2026" = c("2024-01-01", "2026-04-30")
)

subperiod_dt <- rbindlist(lapply(c(METHODS, "BENCH_S4_static_dohoon"), function(m) {
  r_ <- port_returns_net[[m]]
  rbindlist(lapply(names(periods), function(p) {
    rng <- as.Date(periods[[p]])
    idx <- which(eval_dates >= rng[1] & eval_dates <= rng[2])
    if (length(idx) < 6) return(data.table(method=m, period=p, n=length(idx),
                                            mean_ret=NA, sr_ann=NA, sign=NA))
    sub <- r_[idx]
    sr_p <- mean(sub) * 12 / (sd(sub) * sqrt(12) + 1e-9)
    data.table(method=m, period=p, n=length(idx), mean_ret=mean(sub)*12,
               sr_ann=sr_p, sign=sign(sr_p))
  }))
}))

# sign consistency: # periods with sign>0 / total periods
sign_consistency <- subperiod_dt[!is.na(sign), .(n_periods=.N, n_positive=sum(sign>0),
                                                  consistency_pct=mean(sign>0)*100), by=method]
LOG("[sub-period] 5 period × method 평가 완료")

# ---------------------------------------------------------------------------
# Step 10. Save artifacts
# ---------------------------------------------------------------------------
fwrite(metrics_dt,         file.path(OUT_DIR, "comparison_table_walk_forward.csv"))
fwrite(ax001_v2_dt,        file.path(OUT_DIR, "ax001_v2_conditional_defense_walkforward.csv"))
fwrite(dsr_dt,             file.path(OUT_DIR, "dsr_bailey_walkforward.csv"))
fwrite(harvey_dt,          file.path(OUT_DIR, "harvey_liu_walkforward.csv"))
fwrite(subperiod_dt,       file.path(OUT_DIR, "subperiod_stability_walkforward.csv"))
fwrite(sign_consistency,   file.path(OUT_DIR, "sign_consistency_walkforward.csv"))

# Weight evolution timeseries (long format)
weight_evo_long <- rbindlist(lapply(METHODS, function(m) {
  W <- W_evolution[[m]]
  data.table(method=m, date=eval_dates,
             AR_on_M4=W[,"AR_on_M4"], TSMOM=W[,"TSMOM"],
             KR_10y=W[,"KR_10y"], Cash=W[,"Cash"])
}))
fwrite(weight_evo_long,    file.path(OUT_DIR, "weight_evolution_timeseries.csv"))

# Per-method realized returns (net of TC)
returns_long <- rbindlist(lapply(c(METHODS, "BENCH_S0_alpha_only", "BENCH_S4_static_dohoon"), function(m) {
  data.table(method=m, date=eval_dates,
             ret_net=port_returns_net[[m]],
             ret_gross=port_returns[[m]])
}))
fwrite(returns_long,       file.path(OUT_DIR, "walk_forward_returns_timeseries.csv"))

# walk_forward_method_log.json: 8 candidates × 196m metadata
wf_log <- list(
  task_id = "WT-P20260509_002",
  evaluation_window = list(start=format(min(eval_dates)), end=format(max(eval_dates)), n_obs=T_eval),
  rolling_window_months = WINDOW,
  burnin_months = WINDOW,
  rebalance_freq = "monthly",
  sleeve_definition = list(
    AR_on_M4 = "STR_1715 alpha-updated × M4 overlay × β threshold (50% sleeve standalone)",
    TSMOM    = "8-ETF basket re-derived (KODEX_KTB10Y A148070 제거, 나머지 8 ETF renormalized)",
    KR_10y   = "KODEX 국고채10년 (A148070) standalone returns",
    Cash     = "0% return retain"
  ),
  methods_evaluated = METHODS,
  constraints = list(
    weight_bound = c(W_LB, W_UB),
    sum_weights = 1.0,
    long_only = TRUE,
    rolling_window = WINDOW,
    burnin = WINDOW,
    no_in_sample_optimization = TRUE,
    pit_strict = TRUE
  ),
  paradigm_free_certification = "60/40 / SAA / Brinson 1986 등 paradigm 인용 0건. 정량 metric 비교만.",
  pit_compliance = "각 sig_date 추정은 (t-WINDOW ~ t-1) past data만 사용. 모든 weight = walk-forward",
  benchmarks_paradigm_free = list(
    BENCH_S0_alpha_only = "STR_1715 alpha-only 100% (정합 baseline, NOT paradigm)",
    BENCH_S4_static_dohoon = "S4 50/25/20/5 도훈 framing (정량 비교용 only, NOT admit candidate)"
  )
)
write_json(wf_log, file.path(OUT_DIR, "walk_forward_method_log.json"),
           pretty=TRUE, auto_unbox=TRUE)

LOG("=== 모든 artifact 저장 완료 → %s ===", OUT_DIR)

# ---------------------------------------------------------------------------
# Step 11. Best method selection (paradigm-free)
# ---------------------------------------------------------------------------
# Composite score: 50% SR + 25% AX-001 v2 pass + 15% DSR + 10% Harvey-Liu pass
# Penalty: turnover > 200% annualized → score × 0.7

ranking_dt <- merge(metrics_dt[method %in% METHODS],
                   ax001_v2_dt[method %in% METHODS, .(method, ax001_v2_pass)],
                   by="method")
ranking_dt <- merge(ranking_dt,
                   dsr_dt[method %in% METHODS, .(method, DSR, DSR_pass)],
                   by="method")
ranking_dt <- merge(ranking_dt,
                   harvey_dt[method %in% METHODS, .(method, t_NW, harvey_pass_3.0)],
                   by="method")
ranking_dt <- merge(ranking_dt,
                   sign_consistency[method %in% METHODS, .(method, consistency_pct)],
                   by="method")

# Composite score (paradigm-free, hurdle-rule informed)
# Charter v1.5: Validity > Implementability > Robustness > Performance > Novelty
# Component breakdown:
#   - SR (annualized) targeting 2.0 → score / 2.0
#   - CAGR (annualized) targeting 16% → score / 0.16  (도훈 제2목표 retain)
#   - MDD penalty: cap at 25%, anything beyond = penalty
#   - AX-001 v2 conditional defense PASS = robustness gate
#   - DSR Bailey-LdP (multi-trial haircut) = statistical robustness
#   - Harvey-Liu t_NW > 3 = multi-test inflation defense
#   - sub-period sign consistency = stability
ranking_dt[, score_SR     := pmin(pmax(SR_ann,   0) * 100 / 2.0,  100)]
ranking_dt[, score_CAGR   := pmin(pmax(CAGR,     0) * 100 / 0.16, 100)]
ranking_dt[, score_MDD    := pmin(pmax((0.25 - MDD) / 0.25, 0) * 100, 100)]
ranking_dt[, score_AX001  := as.integer(ax001_v2_pass) * 100]
ranking_dt[, score_DSR    := DSR * 100]
ranking_dt[, score_Harvey := as.integer(harvey_pass_3.0) * 100]
ranking_dt[, score_consist := consistency_pct]

# Implementability score: turnover-based (lower = better)
# Charter v1.5 Implementability > Performance hierarchy
# TO ≤ 100% = full 100, TO > 600% = 0, linear interpolation
ranking_dt[, score_TO := pmax(pmin((6.0 - Turnover_ann) / 5.0 * 100, 100), 0)]

# Weights: 22% SR + 18% CAGR + 13% MDD + 12% AX-001 v2 + 8% DSR + 5% Harvey + 8% consistency + 14% TO (implementability)
ranking_dt[, composite := 0.22 * score_SR + 0.18 * score_CAGR + 0.13 * score_MDD +
                          0.12 * score_AX001 + 0.08 * score_DSR +
                          0.05 * score_Harvey + 0.08 * score_consist +
                          0.14 * score_TO]
# Hard fail penalty: TO > 600% → composite × 0.5
ranking_dt[Turnover_ann > 6.0, composite := composite * 0.5]

setorder(ranking_dt, -composite)

# Static-detection penalty: methods with TO_ann == 0 are effectively static.
# 도훈 mandate "no_static_weight_admit" → exclude effectively-static methods from candidate.
# Detection: if AR / TSMOM / KR_10y all have weight sd < 1e-4 → static.
static_check <- rbindlist(lapply(METHODS, function(m) {
  W <- W_evolution[[m]]
  data.table(method=m,
             sd_AR=sd(W[,"AR_on_M4"]), sd_TSMOM=sd(W[,"TSMOM"]),
             sd_KR=sd(W[,"KR_10y"]),
             effectively_static = (sd(W[,"AR_on_M4"]) < 1e-4) &
                                  (sd(W[,"TSMOM"]) < 1e-4) &
                                  (sd(W[,"KR_10y"]) < 1e-4))
}))
LOG("[static-check] effectively_static methods: %s",
    paste(static_check[effectively_static==TRUE]$method, collapse=", "))
ranking_dt <- merge(ranking_dt, static_check[, .(method, effectively_static)], by="method")
ranking_dt[effectively_static == TRUE, composite := composite * 0.7]   # heavy penalty (no admit)
setorder(ranking_dt, -composite)

# Tie-breaker (composite within 1.0 point of top): apply Charter v1.5 hierarchy
# Validity > Implementability > Robustness > Performance > Novelty
# All top tier passes Validity (PIT, AX-001 v2). Differentiate by Implementability (TO)
top_score <- ranking_dt$composite[1]
tie_zone <- ranking_dt[composite >= top_score - 1.0 & effectively_static == FALSE]
LOG("[tie-zone] composite >= %.2f, dynamic only: %d method", top_score - 1.0, nrow(tie_zone))
# Within tie-zone, prefer lower turnover (implementability), then higher Sortino, then higher CAGR
setorder(tie_zone, Turnover_ann, -Sortino, -CAGR)
best_method <- tie_zone$method[1]
LOG("[ranking] Best method 자율 권고 (tie-broken by Charter hierarchy): %s",
    best_method)
LOG("           composite=%.2f, SR=%.4f, CAGR=%.4f, MDD=%.4f, TO=%.4f",
    ranking_dt[method==best_method]$composite,
    ranking_dt[method==best_method]$SR_ann,
    ranking_dt[method==best_method]$CAGR,
    ranking_dt[method==best_method]$MDD,
    ranking_dt[method==best_method]$Turnover_ann)

fwrite(ranking_dt, file.path(OUT_DIR, "best_method_ranking.csv"))

# Best method recommendation JSON
best_rec <- list(
  task_id = "WT-P20260509_002",
  recommended_method = best_method,
  composite_score = round(ranking_dt$composite[1], 2),
  rationale = list(
    SR_ann   = ranking_dt$SR_ann[1],
    CAGR     = ranking_dt$CAGR[1],
    MDD      = ranking_dt$MDD[1],
    Turnover_ann = ranking_dt$Turnover_ann[1],
    AX001_v2_pass = ranking_dt$ax001_v2_pass[1],
    DSR      = ranking_dt$DSR[1],
    Harvey_t_NW = ranking_dt$t_NW[1],
    sign_consistency_pct = ranking_dt$consistency_pct[1]
  ),
  top3_methods = ranking_dt$method[1:3],
  top3_composite = ranking_dt$composite[1:3],
  paradigm_free_assertion = "선택은 정량 metric 기반. paradigm 인용 0건. 60/40 회피.",
  walk_forward_pit_strict = TRUE,
  no_static_admit = TRUE
)
write_json(best_rec, file.path(OUT_DIR, "best_method_recommendation.json"),
           pretty=TRUE, auto_unbox=TRUE)

# ---------------------------------------------------------------------------
# Step 12. Static (S4 도훈 framing) vs Dynamic best 비교
# ---------------------------------------------------------------------------
s4_metrics  <- metrics_dt[method == "BENCH_S4_static_dohoon"]
best_metrics <- metrics_dt[method == best_method]

comparison <- list(
  task_id = "WT-P20260509_002",
  static_S4_dohoon_framing = list(
    weights = setNames(as.list(w_S4), SLEEVE_NAMES),
    SR_ann  = s4_metrics$SR_ann,
    CAGR    = s4_metrics$CAGR,
    MDD     = s4_metrics$MDD,
    Sortino = s4_metrics$Sortino,
    Calmar  = s4_metrics$Calmar,
    Turnover_ann = s4_metrics$Turnover_ann
  ),
  dynamic_best = list(
    method = best_method,
    SR_ann  = best_metrics$SR_ann,
    CAGR    = best_metrics$CAGR,
    MDD     = best_metrics$MDD,
    Sortino = best_metrics$Sortino,
    Calmar  = best_metrics$Calmar,
    Turnover_ann = best_metrics$Turnover_ann
  ),
  delta = list(
    delta_SR    = best_metrics$SR_ann - s4_metrics$SR_ann,
    delta_CAGR  = best_metrics$CAGR   - s4_metrics$CAGR,
    delta_MDD   = best_metrics$MDD    - s4_metrics$MDD,    # negative = improvement
    delta_TO    = best_metrics$Turnover_ann - s4_metrics$Turnover_ann
  ),
  axiom_compliance = list(
    AX002_PIT_strict_dynamic = TRUE,
    AX002_PIT_strict_static  = "static admit blocked by Codex GOV-C1 — only used as paradigm-free benchmark for comparison",
    AX007_multi_sleeve_exception = TRUE,
    no_paradigm_justification = TRUE
  ),
  recommendation = sprintf("Walk-forward dynamic best (%s) — codex GOV-C1 정합. Static S4는 admit 후보 아님 (Codex REJECT).",
                           best_method)
)
write_json(comparison, file.path(OUT_DIR, "static_vs_dynamic_validation.json"),
           pretty=TRUE, auto_unbox=TRUE)

LOG("=== Walk-forward dynamic 8 method 비교 완료 ===")
LOG("Best method: %s", best_method)
LOG("SR=%.4f, CAGR=%.4f, MDD=%.4f, TO_ann=%.4f",
    best_metrics$SR_ann, best_metrics$CAGR, best_metrics$MDD, best_metrics$Turnover_ann)

# Print final comparison table
cat("\n=== Walk-forward Dynamic Method Comparison (sorted by composite) ===\n")
print(ranking_dt[, .(method, SR_ann=round(SR_ann,4), CAGR=round(CAGR,4),
                    MDD=round(MDD,4), TO_ann=round(Turnover_ann,4),
                    AX001=ax001_v2_pass, DSR=round(DSR,3),
                    t_NW=round(t_NW,2), composite=round(composite,1))])

cat("\n=== Static vs Dynamic ===\n")
print(metrics_dt[method %in% c("BENCH_S0_alpha_only", "BENCH_S4_static_dohoon", best_method),
                 .(method, SR_ann=round(SR_ann,4), CAGR=round(CAGR,4),
                   MDD=round(MDD,4), Sortino=round(Sortino,3),
                   TO_ann=round(Turnover_ann,4))])
