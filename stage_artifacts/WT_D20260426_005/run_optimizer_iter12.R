#==============================================================================
# WT-D20260426_005 — Optimizer Research (Iter 12 ambitious stack)
#
# Inheritance: alpha_package + risk_package from WT-D20260425_010 (Iter 5 STR_1699)
#
# Stack design (most ambitious):
#   Layer 1: Linear Tilt (alpha-rank weighted, λ=1.0/1.5 grid)
#   Layer 2: Kelly_frac05 sizing (vol scaling, 50% fractional)
#   Layer 3: 3-Layer Overlay
#     3a: DD Brake 6/8/20 (drawdown trigger, Korean L-122 style)
#     3b: VolReg 12% target (vol scaling)
#     3c: FM regime cash (BULL 0% / NORMAL 5% / CAUTION 15% / CRISIS 30%)
#   Layer 4: Pooled-Σ fallback (CRISIS/CAUTION + max_w 0.10 shrink)
#
# Method shopping (≤10): full stack vs ablations vs Iter 5 baseline.
# Selection objective: net_ir (R4 P3 hard).
# Hard constraints: max_names ≤ 20, weight_bounds [0,0.20], Σw=1, TO < 600%.
#
# Outputs:
#   - qepm/mailbox/worktask/WT-D20260426_005/optimization_package.json
#   - stage_artifacts/WT_D20260426_005/weights.csv  (mailbox + stage)
#   - stage_artifacts/WT_D20260426_005/regime_specific_weights.json
#   - stage_artifacts/WT_D20260426_005/weight_method_selected.md
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(arrow)
  library(quadprog)
  library(digest)
})

set.seed(20260426L)

WT_ID         <- "WT-D20260426_005"
PARENT_WT     <- "WT-D20260425_010"   # alpha+risk inheritance
WT_DIR        <- file.path("qepm/mailbox/worktask", WT_ID)
PARENT_WT_DIR <- file.path("qepm/mailbox/worktask", PARENT_WT)
ART_DIR       <- file.path("stage_artifacts", "WT_D20260426_005")
PARENT_ART    <- file.path("stage_artifacts", "WT_D20260425_010")
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

PIT_HARD_CUTOFF <- as.Date("2023-11-30")
SIGNAL_AS_OF    <- as.Date("2023-12-01")
COST_BPS        <- 15
TURNOVER_HARD_CAP <- 6.00
CVAR_DAILY_CAP    <- 0.025
VOLREG_TARGET     <- 0.12   # 12% annualized vol target
DD_TRIGGER_LO     <- 0.06   # 6% MDD → reduce
DD_TRIGGER_MID    <- 0.08   # 8% MDD → moderate cut
DD_TRIGGER_HI     <- 0.20   # 20% MDD → max cut

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

# ─── Long-only normalize ────────────────────────────────
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) {
    n <- length(w); return(rep(target_sum / n, n))
  }
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) {
      w <- w * (target_sum / sum(w)); break
    }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}

# ─── Pairwise-complete LW shrinkage Σ (oracle) ─────────────
.sample_cov_pairwise <- function(R) {
  R <- as.matrix(R)
  S <- stats::cov(R, use = "pairwise.complete.obs")
  S[!is.finite(S)] <- 0
  S <- 0.5 * (S + t(S))
  S
}

lw_oracle_cov <- function(R) {
  R <- as.matrix(R); N <- ncol(R)
  if (N < 2) return(NULL)
  col_nna <- colSums(!is.na(R))
  keep <- col_nna >= 24
  if (sum(keep) < 5) return(NULL)
  R <- R[, keep, drop = FALSE]; N <- ncol(R)
  T_eff <- max(col_nna[keep])
  if (T_eff < 24) return(NULL)
  S <- .sample_cov_pairwise(R)
  eig <- eigen(S, symmetric = TRUE)
  vals <- eig$values
  if (any(vals < 0)) {
    vals <- pmax(vals, 1e-10)
    S <- eig$vectors %*% diag(vals) %*% t(eig$vectors)
    S <- 0.5 * (S + t(S))
  }
  s <- sqrt(diag(S))
  if (any(!is.finite(s)) || any(s <= 1e-12)) return(NULL)
  Cor_S <- S / (s %*% t(s)); Cor_S[!is.finite(Cor_S)] <- 0
  rbar <- (sum(Cor_S) - N) / (N * (N - 1))
  if (!is.finite(rbar)) rbar <- 0
  rbar <- pmax(pmin(rbar, 0.99), -0.99)
  Fmat <- rbar * (s %*% t(s)); diag(Fmat) <- diag(S)
  R_dem <- sweep(R, 2, colMeans(R, na.rm = TRUE), `-`); R_dem[is.na(R_dem)] <- 0
  pi_hat <- 0
  for (i in seq_len(N)) for (j in seq_len(N)) {
    pi_hat <- pi_hat + mean((R_dem[, i] * R_dem[, j] - S[i, j])^2)
  }
  gamma_hat <- sum((Fmat - S)^2)
  delta <- if (gamma_hat <= 0) 0.5 else max(0, min(1, pi_hat / (T_eff * gamma_hat)))
  Sig <- delta * Fmat + (1 - delta) * S
  Sig <- 0.5 * (Sig + t(Sig))
  if (any(eigen(Sig, symmetric = TRUE, only.values = TRUE)$values < 1e-10)) Sig <- Sig + diag(1e-8, N)
  rownames(Sig) <- colnames(Sig) <- colnames(R)
  Sig
}

lw_constcor_cov <- function(R) {
  R <- as.matrix(R); N <- ncol(R)
  if (N < 2) return(NULL)
  col_nna <- colSums(!is.na(R))
  keep <- col_nna >= 24
  if (sum(keep) < 5) return(NULL)
  R <- R[, keep, drop = FALSE]; N <- ncol(R)
  S <- .sample_cov_pairwise(R)
  eig <- eigen(S, symmetric = TRUE); vals <- pmax(eig$values, 1e-10)
  S <- eig$vectors %*% diag(vals) %*% t(eig$vectors); S <- 0.5*(S+t(S))
  s <- sqrt(diag(S))
  if (any(!is.finite(s)) || any(s <= 1e-12)) return(NULL)
  Cor_S <- S / (s %*% t(s)); Cor_S[!is.finite(Cor_S)] <- 0
  rbar <- (sum(Cor_S) - N) / (N * (N - 1))
  rbar <- pmax(pmin(rbar, 0.99), -0.99)
  Fmat <- rbar * (s %*% t(s)); diag(Fmat) <- diag(S)
  delta <- 0.5
  Sig <- delta * Fmat + (1 - delta) * S
  Sig <- 0.5 * (Sig + t(Sig))
  if (any(eigen(Sig, symmetric = TRUE, only.values = TRUE)$values < 1e-10)) Sig <- Sig + diag(1e-8, N)
  rownames(Sig) <- colnames(Sig) <- colnames(R)
  Sig
}

# ─── LAYER 1: Linear Tilt weight (alpha-rank-proportional) ──────────
# w_i ∝ max(0, alpha_i)^lambda_tilt × (1/sigma_i)^kappa_inv_vol
# lambda_tilt: 1.0 (linear) or 1.5 (mildly convex). Higher = more concentration.
# kappa_inv_vol: 0 = pure alpha tilt. 0.5 = mild risk-aware. 1.0 = HRP-like.
# Returns weight vector [0,1] with Σw=1 normalized at end.
linear_tilt_qd <- function(alpha, Sigma, lambda_tilt = 1.0, kappa_inv_vol = 0.5,
                            lb = 0, ub = 0.20) {
  N <- length(alpha)
  if (N == 0) return(NULL)
  # Cross-section z-score then winsor ±2σ
  a <- as.numeric(alpha)
  a_med <- stats::median(a, na.rm = TRUE)
  a_mad <- stats::mad(a, na.rm = TRUE) * 1.4826
  a_mad <- if (!is.finite(a_mad) || a_mad < 1e-12) stats::sd(a, na.rm = TRUE) else a_mad
  if (!is.finite(a_mad) || a_mad < 1e-12) a_mad <- 1
  z <- (a - a_med) / a_mad
  z <- pmax(pmin(z, 2.0), -2.0)
  # rank-based tilt: convert z to rank percentile [0,1]
  r <- rank(z, ties.method = "average") / N
  # Tilt: w_pre ∝ r^lambda_tilt × (1/σ)^kappa_inv_vol
  s <- sqrt(diag(Sigma))
  s[!is.finite(s) | s <= 1e-12] <- 1e-3
  w_pre <- (r ^ lambda_tilt) * ((1 / s) ^ kappa_inv_vol)
  if (sum(w_pre) <= 1e-12) return(rep(1/N, N))
  w_pre <- w_pre / sum(w_pre)
  normalize_long_only(w_pre, lb = lb, ub = ub, target_sum = 1)
}

# ─── LAYER 2: Kelly-fractional sizing ──────────────────────────
# Full Kelly for portfolio: w_kelly = Σ^(-1) μ. Fractional-Kelly uses 0.5 (Thorp).
# Combined with input weight w_in (e.g., from Linear Tilt):
#   w_kelly_full = solve(Σ) %*% alpha_vec
#   w_blend = (1-frac) × w_in + frac × w_kelly_norm
# Then renormalize long-only.
kelly_fractional <- function(w_in, alpha, Sigma, frac = 0.5, lb = 0, ub = 0.20) {
  N <- length(alpha)
  if (N == 0) return(w_in)
  # Solve Kelly portfolio (long-only QP, Σw=1)
  # min 0.5 w'Σw - alpha'w  s.t. Σw=1, w in [lb, ub]
  Dmat <- Sigma + diag(1e-8, N)
  dvec <- as.numeric(alpha)
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(1, rep(lb, N), rep(-ub, N))
  res <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1), error = function(e) NULL)
  if (is.null(res)) return(w_in)
  w_k <- res$solution
  w_k[abs(w_k) < 1e-9] <- 0
  w_k <- normalize_long_only(w_k, lb = lb, ub = ub, target_sum = 1)
  w_blend <- (1 - frac) * w_in + frac * w_k
  normalize_long_only(w_blend, lb = lb, ub = ub, target_sum = 1)
}

# ─── LAYER 3a: DD Brake (6/8/20) ──────────────────────────────
# Given current portfolio drawdown |dd|, apply scaling factor on risk weight.
# dd <= 6%      → scale 1.00
# 6% < dd <= 8%  → scale 0.85
# 8% < dd <= 20% → linear from 0.85 down to 0.50
# dd > 20%       → scale 0.40
dd_brake_scale <- function(dd_abs) {
  if (!is.finite(dd_abs) || dd_abs <= 0) return(1.0)
  if (dd_abs <= DD_TRIGGER_LO) return(1.0)
  if (dd_abs <= DD_TRIGGER_MID) return(0.85)
  if (dd_abs <= DD_TRIGGER_HI) {
    span <- DD_TRIGGER_HI - DD_TRIGGER_MID
    pos  <- (dd_abs - DD_TRIGGER_MID) / span
    return(0.85 - pos * (0.85 - 0.50))
  }
  return(0.40)
}

# ─── LAYER 3b: VolReg (12% annualized target) ──────────────────
# port_vol_realized: trailing realized portfolio vol (annualized)
# Target vol = 12%. scale = min(1.0, target / max(realized, eps))
volreg_scale <- function(port_vol_realized, target = VOLREG_TARGET,
                          floor = 0.50, ceiling = 1.0) {
  if (!is.finite(port_vol_realized) || port_vol_realized <= 1e-6) return(ceiling)
  s <- target / port_vol_realized
  pmax(pmin(s, ceiling), floor)
}

# ─── LAYER 3c: FM regime cash (AX-001 v2) ─────────────────────
fm_regime_cash_pct <- function(regime) {
  switch(as.character(regime),
    "BULL"    = 0.00,
    "NORMAL"  = 0.05,
    "CAUTION" = 0.15,
    "CRISIS"  = 0.30,
    0.05
  )
}

# ─── Combined 3-Layer Overlay Application ─────────────────────
# Inputs:
#   w_risk: long-only risk-side weights, Σ=1
#   regime: BULL/NORMAL/CAUTION/CRISIS
#   trailing_dd: current trailing drawdown (positive number, e.g. 0.07 for -7%)
#   trailing_vol_ann: trailing portfolio vol (annualized)
# Output:
#   list(w_risk_scaled, cash_pct, dd_scale, volreg_scale, regime_cash)
apply_overlay_3layer <- function(w_risk, regime, trailing_dd, trailing_vol_ann,
                                  enable_dd = TRUE, enable_volreg = TRUE,
                                  enable_regime_cash = TRUE) {
  s_dd  <- if (enable_dd) dd_brake_scale(trailing_dd) else 1.0
  s_vol <- if (enable_volreg) volreg_scale(trailing_vol_ann) else 1.0
  base_cash <- if (enable_regime_cash) fm_regime_cash_pct(regime) else 0.0
  # Total scaling on risk: combine multiplicatively, additional cash from each layer
  # final risk fraction = base_invested × s_dd × s_vol
  # then cap with regime_cash (so cash >= regime_cash baseline)
  base_inv <- 1 - base_cash
  s_total  <- s_dd * s_vol
  invested <- base_inv * s_total
  invested <- pmax(pmin(invested, 1.0), 0.0)
  cash_total <- 1 - invested
  # Cap cash at 0.30 (AX-001 v2 max)
  if (cash_total > 0.30) {
    cash_total <- 0.30
    invested   <- 0.70
  }
  list(
    w_risk_scaled = w_risk * invested,
    cash_pct      = cash_total,
    dd_scale      = s_dd,
    volreg_scale  = s_vol,
    regime_cash   = base_cash,
    invested      = invested
  )
}

# ─── HRP for baseline comparison ─────────────────────────
hrp_qd <- function(Sigma) {
  N <- nrow(Sigma)
  if (N == 1) return(1)
  s <- sqrt(diag(Sigma)); s[s < 1e-12] <- 1e-6
  Cor <- Sigma / (s %*% t(s)); Cor[!is.finite(Cor)] <- 0
  d <- sqrt(pmax(0.5 * (1 - Cor), 0))
  hc <- tryCatch(stats::hclust(stats::as.dist(d), method = "single"), error = function(e) NULL)
  if (is.null(hc)) {
    iv <- 1 / pmax(diag(Sigma), 1e-12); return(as.numeric(iv / sum(iv)))
  }
  order_idx <- hc$order
  w <- rep(1.0, N)
  cluster_alloc <- function(start, end) {
    if (start == end) return(invisible(NULL))
    mid <- start + floor((end - start) / 2)
    L_pos <- order_idx[start:mid]; R_pos <- order_idx[(mid + 1):end]
    iv_L <- 1 / pmax(diag(Sigma)[L_pos], 1e-12); w_L <- iv_L / sum(iv_L)
    iv_R <- 1 / pmax(diag(Sigma)[R_pos], 1e-12); w_R <- iv_R / sum(iv_R)
    var_L <- as.numeric(t(w_L) %*% Sigma[L_pos, L_pos, drop = FALSE] %*% w_L)
    var_R <- as.numeric(t(w_R) %*% Sigma[R_pos, R_pos, drop = FALSE] %*% w_R)
    if (!is.finite(var_L) || var_L < 1e-15) var_L <- 1e-15
    if (!is.finite(var_R) || var_R < 1e-15) var_R <- 1e-15
    alpha_L <- 1 - var_L / (var_L + var_R)
    w[L_pos] <<- w[L_pos] * alpha_L
    w[R_pos] <<- w[R_pos] * (1 - alpha_L)
    cluster_alloc(start, mid); cluster_alloc(mid + 1, end)
  }
  cluster_alloc(1, N)
  if (any(!is.finite(w))) w[!is.finite(w)] <- 0
  if (sum(w) <= 1e-12) return(rep(1 / N, N))
  as.numeric(w / sum(w))
}

# ─── MVO (alpha-aware) for ablation comparison ──────────
mvo_qp <- function(alpha, Sigma, lambda = 2.0, lb = 0, ub = 0.20) {
  N <- length(alpha)
  Dmat <- lambda * Sigma + diag(1e-8, N)
  dvec <- as.numeric(alpha)
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(1, rep(lb, N), rep(-ub, N))
  res <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1), error = function(e) NULL)
  if (is.null(res)) return(NULL)
  w <- res$solution; w[abs(w) < 1e-9] <- 0
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ─── InvVol baseline ──────────
invvol_qd <- function(Sigma) {
  iv <- 1 / sqrt(diag(Sigma))
  iv / sum(iv)
}

# ─── Per-sig_date weight construction (full stack assembler) ─────
# Returns: data.table(as_of_date, ticker, weight, method_selected, regime,
#                       n_names, sigma_method, cash_pct, dd_scale, volreg_scale)
compute_weights_at_date <- function(sig_date, alpha_scores, ret_panel, daily_ret_panel,
                                     stack_cfg,
                                     max_names = 20L,
                                     min_names = 10L,
                                     ub = 0.20,
                                     trailing_nav,   # numeric: cumprod NAV vector up to prev sig_date
                                     w_prev_risk_named = NULL) {

  panel_t <- alpha_scores[Date == sig_date & !is.na(score_eff)]
  if (nrow(panel_t) == 0) return(NULL)
  regime <- panel_t$regime_state[1]
  setorder(panel_t, -score_eff)
  N_eligible <- nrow(panel_t)
  N_target <- min(max_names, N_eligible)
  if (N_target < min_names) return(NULL)
  picks <- panel_t[1:N_target]
  tickers_t <- picks$Ticker
  alpha_t   <- picks$score_eff
  names(alpha_t) <- tickers_t

  # Build Σ from history < sig_date
  hist_panel <- ret_panel[Date < sig_date & Ticker %in% tickers_t]
  ret_wide <- dcast(hist_panel, Date ~ Ticker, value.var = "Ret_1m")
  ret_mat  <- as.matrix(ret_wide[, !"Date", with = FALSE])
  rownames(ret_mat) <- as.character(ret_wide$Date)
  ticker_avail <- intersect(tickers_t, colnames(ret_mat))
  if (length(ticker_avail) < min_names) return(NULL)
  ret_mat <- ret_mat[, ticker_avail, drop = FALSE]
  alpha_t <- alpha_t[ticker_avail]
  tickers_t <- ticker_avail
  col_nna <- colSums(!is.na(ret_mat))
  keep_t <- names(col_nna)[col_nna >= 24]
  if (length(keep_t) < min_names) return(NULL)
  ret_mat <- ret_mat[, keep_t, drop = FALSE]
  alpha_t <- alpha_t[keep_t]
  tickers_t <- keep_t

  # Σ: pooled fallback in CRISIS/CAUTION (Risk Mgr binding rule)
  if (regime %in% c("CRISIS", "CAUTION")) {
    Sigma_t <- lw_constcor_cov(ret_mat)
    sigma_method <- "lw_constcor_pooled_fallback"
    ub_use <- min(ub, 0.10)        # max_w 0.10 shrink in CRISIS/CAUTION
  } else {
    Sigma_t <- lw_oracle_cov(ret_mat)
    sigma_method <- "lw_oracle"
    ub_use <- ub
  }
  if (is.null(Sigma_t)) {
    var_diag <- apply(ret_mat, 2, stats::var, na.rm = TRUE)
    var_diag[!is.finite(var_diag) | var_diag <= 0] <- 0.01
    Sigma_t <- diag(var_diag)
    rownames(Sigma_t) <- colnames(Sigma_t) <- tickers_t
    sigma_method <- "diag_fallback"
  }
  sigma_tickers <- intersect(tickers_t, colnames(Sigma_t))
  if (length(sigma_tickers) < min_names) return(NULL)
  Sigma_t  <- Sigma_t[sigma_tickers, sigma_tickers, drop = FALSE]
  alpha_t  <- alpha_t[sigma_tickers]
  tickers_t <- sigma_tickers
  N <- length(tickers_t)

  # ── Build base weight per stack config ─────
  base_method <- stack_cfg$base_method
  w0 <- switch(base_method,
    "LinearTilt"   = linear_tilt_qd(alpha_t, Sigma_t,
                                       lambda_tilt = stack_cfg$tilt_lambda %||% 1.0,
                                       kappa_inv_vol = stack_cfg$tilt_kappa %||% 0.5,
                                       lb = 0, ub = ub_use),
    "MVO_alpha"    = mvo_qp(alpha_t, Sigma_t, lambda = 2.0, lb = 0, ub = ub_use),
    "HRP"          = hrp_qd(Sigma_t),
    "InvVol"       = invvol_qd(Sigma_t),
    "EW"           = rep(1 / N, N),
    NULL
  )
  if (is.null(w0)) w0 <- rep(1 / N, N)
  names(w0) <- tickers_t

  # ── Layer 2: Kelly fractional ─────
  if (isTRUE(stack_cfg$enable_kelly)) {
    w0 <- kelly_fractional(w0, alpha_t, Sigma_t,
                            frac = stack_cfg$kelly_frac %||% 0.5,
                            lb = 0, ub = ub_use)
    names(w0) <- tickers_t
  }
  w0 <- normalize_long_only(w0, lb = 0, ub = ub_use, target_sum = 1)
  names(w0) <- tickers_t

  # ── Layer 3: 3-Layer Overlay ─────
  # Trailing DD: from cumulative NAV
  if (length(trailing_nav) > 0 && all(is.finite(trailing_nav))) {
    pk <- max(trailing_nav, na.rm = TRUE)
    if (is.finite(pk) && pk > 0) {
      cur_nav <- trailing_nav[length(trailing_nav)]
      if (is.finite(cur_nav) && cur_nav > 0) {
        trailing_dd <- 1 - cur_nav / pk
      } else trailing_dd <- 0
    } else trailing_dd <- 0
  } else trailing_dd <- 0

  # Trailing portfolio vol (annualized) from MONTHLY portfolio returns last 12M
  port_vol_ann <- if (length(trailing_nav) >= 13) {
    mret <- diff(log(pmax(trailing_nav, 1e-9)))
    mret_recent <- tail(mret, 12)
    mret_recent <- mret_recent[is.finite(mret_recent)]
    if (length(mret_recent) >= 6) stats::sd(mret_recent) * sqrt(12) else NA_real_
  } else NA_real_

  ov <- apply_overlay_3layer(w0, regime, trailing_dd, port_vol_ann,
                              enable_dd     = isTRUE(stack_cfg$enable_dd),
                              enable_volreg = isTRUE(stack_cfg$enable_volreg),
                              enable_regime_cash = isTRUE(stack_cfg$enable_regime_cash))
  w_risk <- ov$w_risk_scaled
  cash_pct <- ov$cash_pct

  rows <- data.table(
    as_of_date     = sig_date,
    ticker         = c(names(w_risk), if (cash_pct > 0) "CASH" else character(0)),
    weight         = c(as.numeric(w_risk), if (cash_pct > 0) cash_pct else numeric(0)),
    method_selected = stack_cfg$name,
    sleeve_id      = c(rep("multi_sleeve_blend", length(w_risk)),
                       if (cash_pct > 0) "cash_overlay" else character(0)),
    regime         = regime,
    n_names        = N,
    sigma_method   = sigma_method,
    cash_pct       = cash_pct,
    dd_scale       = ov$dd_scale,
    volreg_scale   = ov$volreg_scale,
    trailing_dd    = trailing_dd,
    trailing_vol_ann = port_vol_ann %||% NA_real_
  )
  rows
}

# ─── Walk-forward evaluation ────────────────────────
walk_forward_eval <- function(stack_cfg, alpha_scores, ret_panel, sig_dates,
                               max_names = 20L, min_names = 10L,
                               ub = 0.20, cost_bps = 15,
                               rebalance_every = 1L,
                               collect_weights = FALSE) {
  W_prev <- NULL
  port_ret <- numeric(length(sig_dates))
  port_to  <- numeric(length(sig_dates))
  port_cost <- numeric(length(sig_dates))
  cash_pct_seq <- numeric(length(sig_dates))
  dd_scale_seq <- numeric(length(sig_dates))
  vol_scale_seq <- numeric(length(sig_dates))
  regime_seq <- character(length(sig_dates))
  weights_collected <- list()
  trailing_nav <- 1.0   # cumulative
  nav_seq <- numeric(length(sig_dates))
  n_used <- 0L
  last_res <- NULL
  prev_regime <- NULL

  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    do_rebalance <- (i == 1L) || ((i - 1L) %% rebalance_every == 0L)
    # Force rebalance on regime transition
    if (!is.null(prev_regime)) {
      panel_t <- alpha_scores[Date == d & !is.na(score_eff)]
      if (nrow(panel_t) > 0) {
        cur_regime <- panel_t$regime_state[1]
        cur_in_pool  <- cur_regime %in% c("CRISIS", "CAUTION")
        prev_in_pool <- prev_regime %in% c("CRISIS", "CAUTION")
        if (cur_in_pool != prev_in_pool) do_rebalance <- TRUE
      }
    }

    if (do_rebalance) {
      w_prev_risk_named <- NULL
      if (!is.null(W_prev)) {
        wpr <- W_prev[ticker != "CASH"]
        w_prev_risk_named <- setNames(wpr$weight, wpr$ticker)
      }
      res <- tryCatch(
        compute_weights_at_date(d, alpha_scores, ret_panel, NULL,
                                 stack_cfg = stack_cfg,
                                 max_names = max_names, min_names = min_names,
                                 ub = ub,
                                 trailing_nav = nav_seq[seq_len(max(i - 1, 0))],
                                 w_prev_risk_named = w_prev_risk_named),
        error = function(e) NULL
      )
      if (is.null(res) || any(is.na(res$weight))) next
      last_res <- res
    } else {
      # Held month: refresh universe + cash overlay
      panel_t <- alpha_scores[Date == d & !is.na(score_eff)]
      if (nrow(panel_t) == 0 || is.null(last_res)) next
      regime <- panel_t$regime_state[1]
      eligible_t <- panel_t$Ticker
      held_risk <- last_res[ticker != "CASH"]
      keep_names <- intersect(held_risk$ticker, eligible_t)
      drop_names <- setdiff(held_risk$ticker, eligible_t)
      if (length(keep_names) < min_names) {
        # collapse → force rebalance
        w_prev_risk_named <- setNames(held_risk$weight, held_risk$ticker)
        res <- tryCatch(
          compute_weights_at_date(d, alpha_scores, ret_panel, NULL,
                                   stack_cfg = stack_cfg,
                                   max_names = max_names, min_names = min_names,
                                   ub = ub,
                                   trailing_nav = nav_seq[seq_len(max(i - 1, 0))],
                                   w_prev_risk_named = w_prev_risk_named),
          error = function(e) NULL)
        if (is.null(res) || any(is.na(res$weight))) next
        last_res <- res
      } else {
        # Reallocate dropped weight to kept names; refresh cash via overlay
        kept_dt <- held_risk[ticker %in% keep_names]
        dropped_w <- sum(held_risk[ticker %in% drop_names]$weight)
        kept_w_sum <- sum(kept_dt$weight)
        if (kept_w_sum > 0) {
          kept_dt$weight <- kept_dt$weight + dropped_w * (kept_dt$weight / kept_w_sum)
        }
        # Enforce per-name cap [0,0.20] (or 0.10 in CRISIS/CAUTION) AFTER reallocation, BEFORE overlay
        ub_held <- if (regime %in% c("CRISIS", "CAUTION")) min(ub, 0.10) else ub
        w_norm <- normalize_long_only(kept_dt$weight / sum(kept_dt$weight),
                                        lb = 0, ub = ub_held, target_sum = 1)
        kept_dt$weight <- w_norm
        # compute trailing dd/vol from nav_seq
        nav_hist <- nav_seq[seq_len(max(i - 1, 0))]
        if (length(nav_hist) > 0) {
          pk <- max(nav_hist, na.rm = TRUE)
          cur_nav <- nav_hist[length(nav_hist)]
          trailing_dd <- if (is.finite(pk) && is.finite(cur_nav) && pk > 0) 1 - cur_nav/pk else 0
        } else trailing_dd <- 0
        port_vol_ann <- if (length(nav_hist) >= 13) {
          mret <- diff(log(pmax(nav_hist, 1e-9)))
          mret_recent <- tail(mret, 12); mret_recent <- mret_recent[is.finite(mret_recent)]
          if (length(mret_recent) >= 6) stats::sd(mret_recent) * sqrt(12) else NA_real_
        } else NA_real_
        ov <- apply_overlay_3layer(setNames(w_norm, kept_dt$ticker),
                                    regime, trailing_dd, port_vol_ann,
                                    enable_dd     = isTRUE(stack_cfg$enable_dd),
                                    enable_volreg = isTRUE(stack_cfg$enable_volreg),
                                    enable_regime_cash = isTRUE(stack_cfg$enable_regime_cash))
        w_risk_held <- ov$w_risk_scaled
        cash_pct_t  <- ov$cash_pct
        res <- rbindlist(list(
          data.table(as_of_date = d, ticker = names(w_risk_held), weight = as.numeric(w_risk_held),
                      method_selected = last_res$method_selected[1], sleeve_id = "multi_sleeve_blend",
                      regime = regime, n_names = length(keep_names),
                      sigma_method = paste0("held_", last_res$sigma_method[1]),
                      cash_pct = cash_pct_t, dd_scale = ov$dd_scale,
                      volreg_scale = ov$volreg_scale, trailing_dd = trailing_dd,
                      trailing_vol_ann = port_vol_ann %||% NA_real_),
          if (cash_pct_t > 0) data.table(as_of_date = d, ticker = "CASH",
                                          weight = cash_pct_t,
                                          method_selected = last_res$method_selected[1],
                                          sleeve_id = "cash_overlay", regime = regime,
                                          n_names = length(keep_names),
                                          sigma_method = paste0("held_", last_res$sigma_method[1]),
                                          cash_pct = cash_pct_t, dd_scale = ov$dd_scale,
                                          volreg_scale = ov$volreg_scale, trailing_dd = trailing_dd,
                                          trailing_vol_ann = port_vol_ann %||% NA_real_) else NULL
        ))
        last_res <- res
      }
    }

    # Realized 1M return: portfolio = Σ w_i × Ret_1m; CASH yields 0
    risk_rows_eval <- res[ticker != "CASH"]
    rd <- alpha_scores[Date == d, .(Ticker, Ret_1m)]
    setkey(rd, Ticker)
    risk_rows_eval <- rd[risk_rows_eval, on = .(Ticker = ticker)]
    risk_rows_eval[is.na(Ret_1m), Ret_1m := 0]
    realized_t <- sum(risk_rows_eval$weight * risk_rows_eval$Ret_1m, na.rm = TRUE)
    # Turnover
    if (!is.null(W_prev)) {
      all_names <- union(W_prev$ticker, res$ticker)
      w_prev_aligned <- setNames(rep(0, length(all_names)), all_names)
      w_prev_aligned[W_prev$ticker] <- W_prev$weight
      w_now_aligned  <- setNames(rep(0, length(all_names)), all_names)
      w_now_aligned[res$ticker] <- res$weight
      to_t <- sum(abs(w_now_aligned - w_prev_aligned)) / 2
    } else {
      to_t <- 1.0
    }
    cost_t <- to_t * (cost_bps / 1e4) * 2
    n_used <- n_used + 1L
    port_ret[i] <- realized_t - cost_t
    port_to[i]  <- to_t
    port_cost[i] <- cost_t
    cash_pct_seq[i] <- res$cash_pct[1] %||% 0
    dd_scale_seq[i] <- res$dd_scale[1] %||% 1
    vol_scale_seq[i] <- res$volreg_scale[1] %||% 1
    regime_seq[i]   <- res$regime[1] %||% "NORMAL"
    # Update NAV
    if (i == 1L) nav_seq[i] <- 1 + port_ret[i]
    else         nav_seq[i] <- nav_seq[i - 1L] * (1 + port_ret[i])
    if (collect_weights) weights_collected[[length(weights_collected) + 1L]] <- res
    W_prev <- res[, .(ticker, weight)]
    prev_regime <- res$regime[1]
  }

  used <- which(port_ret != 0 | port_to != 0)
  if (length(used) < 12) return(list(name = stack_cfg$name, ok = FALSE, n_used = n_used))
  pr <- port_ret[used]; pt <- port_to[used]; pc <- port_cost[used]; cs <- cash_pct_seq[used]
  ds <- dd_scale_seq[used]; vs <- vol_scale_seq[used]; rg <- regime_seq[used]
  mu <- mean(pr); sigma <- stats::sd(pr)
  sr_monthly <- if (sigma > 1e-12) mu / sigma else 0
  sr_ann     <- sr_monthly * sqrt(12)
  ann_to     <- mean(pt) * 12
  ann_cost   <- mean(pc) * 12
  net_ret_ann <- mean(pr) * 12
  net_ir     <- if (sigma > 1e-12) (mean(pr) / sigma) * sqrt(12) else 0
  cum_ret <- prod(1 + pr) - 1
  T_use <- length(pr)
  cagr <- (1 + cum_ret) ^ (12 / T_use) - 1
  cc <- cumprod(1 + pr); pk <- cummax(cc); dd <- cc / pk - 1
  mdd <- min(dd)
  q05 <- stats::quantile(pr, 0.05, na.rm = TRUE)
  cvar95_m <- -mean(pr[pr <= q05], na.rm = TRUE)
  cvar95_d_proxy <- cvar95_m / sqrt(21)

  # Layer attribution: avg dd_scale, vol_scale, cash_pct
  list(
    name = stack_cfg$name, ok = TRUE,
    net_ir = net_ir, sr_ann = sr_ann, cagr = cagr, mdd = mdd,
    ann_to = ann_to, ann_cost = ann_cost, T_use = T_use,
    mu_monthly = mu, sigma_monthly = sigma, net_ret_ann = net_ret_ann,
    cvar95_monthly = cvar95_m, cvar95_daily_proxy = cvar95_d_proxy,
    avg_dd_scale = mean(ds), avg_volreg_scale = mean(vs), avg_cash_pct = mean(cs),
    pct_dd_active = mean(ds < 0.999), pct_volreg_active = mean(vs < 0.999),
    pct_cash_gt0 = mean(cs > 0.001),
    regime_dist = table(rg),
    port_returns_monthly = pr, port_to = pt, port_cash = cs,
    weights_collected = if (collect_weights) weights_collected else NULL
  )
}

# ════════════════════════════════════════════════════════════════════
# 1. Load inheritance
# ════════════════════════════════════════════════════════════════════
cat("[Optimizer Iter12] Loading inheritance from", PARENT_WT, "...\n")
alpha_pkg <- fromJSON(file.path(PARENT_WT_DIR, "alpha_package.json"), simplifyVector = TRUE)
risk_pkg  <- fromJSON(file.path(PARENT_WT_DIR, "risk_package.json"),  simplifyVector = TRUE)
req_pkg   <- fromJSON(file.path(WT_DIR, "request.json"),              simplifyVector = TRUE)

alpha_scores <- as.data.table(read_parquet(file.path(PARENT_ART, "alpha_scores.parquet")))
setkey(alpha_scores, Date, Ticker)
ret_panel <- alpha_scores[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
setkey(ret_panel, Date, Ticker)

Sigma_dt        <- as.data.table(read_parquet(file.path(PARENT_ART, "covariance.parquet")))
Sigma_pooled_dt <- as.data.table(read_parquet(file.path(PARENT_ART, "covariance_pooled_fallback.parquet")))
SIG_TICKERS  <- as.character(Sigma_dt$Ticker)
Sigma_asof   <- as.matrix(Sigma_dt[, !"Ticker", with = FALSE])
rownames(Sigma_asof)   <- colnames(Sigma_asof)   <- SIG_TICKERS
Sigma_pooled_asof <- as.matrix(Sigma_pooled_dt[, !"Ticker", with = FALSE])
rownames(Sigma_pooled_asof) <- colnames(Sigma_pooled_asof) <- SIG_TICKERS

cat(sprintf("[Optimizer Iter12] alpha panel: %d sig_dates × %d tickers\n",
            length(unique(alpha_scores$Date)), length(unique(alpha_scores$Ticker))))
cat(sprintf("[Optimizer Iter12] Risk Σ as_of: %dx%d cond=%.2f, pooled cond=%.2f\n",
            nrow(Sigma_asof), ncol(Sigma_asof), kappa(Sigma_asof, exact = TRUE),
            kappa(Sigma_pooled_asof, exact = TRUE)))

all_sig <- sort(unique(alpha_scores$Date))
min_hist_start <- as.Date("2006-01-01")
sig_dates_use <- all_sig[all_sig >= min_hist_start & all_sig <= SIGNAL_AS_OF]
cat(sprintf("[Optimizer Iter12] sig_dates_use: %d (%s ~ %s)\n",
            length(sig_dates_use), as.character(min(sig_dates_use)),
            as.character(max(sig_dates_use))))

# ════════════════════════════════════════════════════════════════════
# 2. Method shopping (≤10 candidates)
# ════════════════════════════════════════════════════════════════════
# Candidates ordered to test the ambitious stack vs ablations vs baselines
CANDIDATES <- list(
  # 1. FULL STACK (Linear Tilt + Kelly + 3-Layer Overlay) — ambitious primary
  list(name = "LinTilt_Kelly_Overlay_FULL",
        base_method = "LinearTilt", tilt_lambda = 1.0, tilt_kappa = 0.5,
        enable_kelly = TRUE,  kelly_frac = 0.5,
        enable_dd = TRUE, enable_volreg = TRUE, enable_regime_cash = TRUE,
        rebalance_every = 1L),

  # 2. Linear Tilt + Kelly only (no Overlay) — Layer 1+2 ablation
  list(name = "LinTilt_Kelly_only",
        base_method = "LinearTilt", tilt_lambda = 1.0, tilt_kappa = 0.5,
        enable_kelly = TRUE,  kelly_frac = 0.5,
        enable_dd = FALSE, enable_volreg = FALSE, enable_regime_cash = FALSE,
        rebalance_every = 1L),

  # 3. Linear Tilt + Overlay only (no Kelly) — Layer 1+3
  list(name = "LinTilt_Overlay_only",
        base_method = "LinearTilt", tilt_lambda = 1.0, tilt_kappa = 0.5,
        enable_kelly = FALSE, kelly_frac = 0,
        enable_dd = TRUE, enable_volreg = TRUE, enable_regime_cash = TRUE,
        rebalance_every = 1L),

  # 4. MVO_alpha + Kelly + Overlay — replace L1 with MVO
  list(name = "MVO_Kelly_Overlay",
        base_method = "MVO_alpha", tilt_lambda = NA, tilt_kappa = NA,
        enable_kelly = TRUE,  kelly_frac = 0.5,
        enable_dd = TRUE, enable_volreg = TRUE, enable_regime_cash = TRUE,
        rebalance_every = 1L),

  # 5. HRP_lw + Overlay (Iter 5 baseline + machinery)
  list(name = "HRP_Overlay",
        base_method = "HRP", tilt_lambda = NA, tilt_kappa = NA,
        enable_kelly = FALSE,
        enable_dd = TRUE, enable_volreg = TRUE, enable_regime_cash = TRUE,
        rebalance_every = 1L),

  # 6. Iter 6 STR_1700-style (InvVol_Quarterly + Overlay, monthly rebalance)
  list(name = "InvVol_Overlay",
        base_method = "InvVol", tilt_lambda = NA, tilt_kappa = NA,
        enable_kelly = FALSE,
        enable_dd = TRUE, enable_volreg = TRUE, enable_regime_cash = TRUE,
        rebalance_every = 1L),

  # 7. Iter 5 HRP_lw baseline (no overlay, monthly)
  list(name = "HRP_baseline_Iter5",
        base_method = "HRP", tilt_lambda = NA, tilt_kappa = NA,
        enable_kelly = FALSE,
        enable_dd = FALSE, enable_volreg = FALSE, enable_regime_cash = FALSE,
        rebalance_every = 1L),

  # 8. FULL STACK Quarterly rebalance (TO reduction)
  list(name = "LinTilt_Kelly_Overlay_Quarterly",
        base_method = "LinearTilt", tilt_lambda = 1.0, tilt_kappa = 0.5,
        enable_kelly = TRUE,  kelly_frac = 0.5,
        enable_dd = TRUE, enable_volreg = TRUE, enable_regime_cash = TRUE,
        rebalance_every = 3L),

  # 9. Tilt only (Layer 1 alone) — diagnostic
  list(name = "LinTilt_only",
        base_method = "LinearTilt", tilt_lambda = 1.0, tilt_kappa = 0.5,
        enable_kelly = FALSE,
        enable_dd = FALSE, enable_volreg = FALSE, enable_regime_cash = FALSE,
        rebalance_every = 1L),

  # 10. Higher-tilt λ=1.5 + Kelly + Overlay (more concentrated)
  list(name = "LinTilt15_Kelly_Overlay",
        base_method = "LinearTilt", tilt_lambda = 1.5, tilt_kappa = 0.5,
        enable_kelly = TRUE,  kelly_frac = 0.5,
        enable_dd = TRUE, enable_volreg = TRUE, enable_regime_cash = TRUE,
        rebalance_every = 1L)
)
stopifnot(length(CANDIDATES) <= 10L)

cat("\n[Optimizer Iter12] Method shopping (10 candidates) ...\n")
eval_results <- list()
for (cfg in CANDIDATES) {
  t0 <- Sys.time()
  cat(sprintf("  %-40s ", cfg$name))
  r <- walk_forward_eval(cfg, alpha_scores, ret_panel, sig_dates_use,
                          max_names = 20L, min_names = 10L,
                          ub = 0.20, cost_bps = COST_BPS,
                          rebalance_every = cfg$rebalance_every,
                          collect_weights = FALSE)
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  eval_results[[cfg$name]] <- r
  if (isTRUE(r$ok)) {
    cat(sprintf("netIR=%.3f SR=%.3f CAGR=%.2f%% MDD=%.2f%% TO=%.0f%% CVaR_d=%.2f%% (%.1fs)\n",
                r$net_ir, r$sr_ann, r$cagr*100, r$mdd*100, r$ann_to*100,
                r$cvar95_daily_proxy*100, dt))
  } else {
    cat(sprintf("FAILED (%.1fs)\n", dt))
  }
}

# Build comparison table
comp <- rbindlist(lapply(eval_results, function(r) {
  if (!isTRUE(r$ok)) return(data.table(name = r$name, ok = FALSE))
  data.table(name = r$name, ok = TRUE,
              net_ir = round(r$net_ir, 4), sr_ann = round(r$sr_ann, 4),
              cagr = round(r$cagr, 4), mdd = round(r$mdd, 4),
              ann_to = round(r$ann_to, 4), ann_cost = round(r$ann_cost, 4),
              cvar95_d = round(r$cvar95_daily_proxy, 5),
              avg_cash = round(r$avg_cash_pct, 4),
              avg_dd_scale = round(r$avg_dd_scale, 4),
              avg_vol_scale = round(r$avg_volreg_scale, 4),
              T_use = r$T_use,
              pass_to = r$ann_to <= TURNOVER_HARD_CAP,
              pass_cvar = (r$cvar95_daily_proxy %||% 1) <= CVAR_DAILY_CAP)
}), fill = TRUE)
setorder(comp, -net_ir, na.last = TRUE)
cat("\n=== Method Comparison (sorted by net_IR) ===\n"); print(comp)

# Selection: pass TO cap → max net_IR
ok_results <- comp[ok == TRUE]
admissible <- ok_results[pass_to == TRUE]
if (nrow(admissible) == 0L) {
  cat("[Optimizer Iter12] WARN — no method passes TO cap. Selecting min-TO.\n")
  setorder(ok_results, ann_to, -net_ir)
  selected_name <- ok_results$name[1]
} else {
  setorder(admissible, -net_ir)
  selected_name <- admissible$name[1]
}
selected_eval <- eval_results[[selected_name]]
selected_cfg  <- CANDIDATES[[which(sapply(CANDIDATES, function(x) x$name == selected_name))]]

cat(sprintf("\n[Optimizer Iter12] selected = %s\n  netIR=%.3f SR=%.3f CAGR=%.2f%% MDD=%.2f%% TO=%.0f%%\n",
            selected_name, selected_eval$net_ir, selected_eval$sr_ann,
            selected_eval$cagr*100, selected_eval$mdd*100, selected_eval$ann_to*100))

# ════════════════════════════════════════════════════════════════════
# 3. Generate full walk-forward weights with selected cfg + collect schedule
# ════════════════════════════════════════════════════════════════════
cat("\n[Optimizer Iter12] Generating walk-forward weights schedule ...\n")
gen_eval <- walk_forward_eval(selected_cfg, alpha_scores, ret_panel, sig_dates_use,
                               max_names = 20L, min_names = 10L, ub = 0.20,
                               cost_bps = COST_BPS,
                               rebalance_every = selected_cfg$rebalance_every,
                               collect_weights = TRUE)
all_rows <- gen_eval$weights_collected
weights_dt <- rbindlist(all_rows, fill = TRUE)

# ─── At as_of_date, rebuild target_weights using Risk's exact 20-ticker Σ ──
cat("[Optimizer Iter12] Aligning as_of weights with Risk Σ artifact (20 tickers)...\n")
asof_panel <- alpha_scores[Date == SIGNAL_AS_OF & !is.na(score_eff)]
asof_regime <- asof_panel$regime_state[1]
asof_eligible <- intersect(asof_panel$Ticker, SIG_TICKERS)
asof_alpha_full <- setNames(unlist(alpha_pkg$alpha_vector)[SIG_TICKERS], SIG_TICKERS)
asof_use_pooled <- asof_regime %in% c("CRISIS", "CAUTION")
asof_Sigma <- if (asof_use_pooled) Sigma_pooled_asof else Sigma_asof
asof_sigma_method <- if (asof_use_pooled) "lw_constcor_pooled_fallback_risk_artifact" else "lw_oracle_risk_artifact"
asof_ub <- if (asof_regime %in% c("CRISIS", "CAUTION")) 0.10 else 0.20

# Layer 1
asof_w0 <- switch(selected_cfg$base_method,
  "LinearTilt" = linear_tilt_qd(asof_alpha_full, asof_Sigma,
                                   lambda_tilt = selected_cfg$tilt_lambda,
                                   kappa_inv_vol = selected_cfg$tilt_kappa,
                                   lb = 0, ub = asof_ub),
  "MVO_alpha"  = mvo_qp(asof_alpha_full, asof_Sigma, lambda = 2.0, lb = 0, ub = asof_ub),
  "HRP"        = hrp_qd(asof_Sigma),
  "InvVol"     = invvol_qd(asof_Sigma),
  "EW"         = rep(1/length(SIG_TICKERS), length(SIG_TICKERS))
)
names(asof_w0) <- SIG_TICKERS
# Layer 2
if (isTRUE(selected_cfg$enable_kelly)) {
  asof_w0 <- kelly_fractional(asof_w0, asof_alpha_full, asof_Sigma,
                                 frac = selected_cfg$kelly_frac, lb = 0, ub = asof_ub)
  names(asof_w0) <- SIG_TICKERS
}
asof_w0 <- normalize_long_only(asof_w0, lb = 0, ub = asof_ub, target_sum = 1)
names(asof_w0) <- SIG_TICKERS

# Layer 3 (use trailing nav from gen_eval)
nav_full <- numeric(length(sig_dates_use))
nav_full[1] <- 1 + gen_eval$port_returns_monthly[1]
for (i in 2:length(gen_eval$port_returns_monthly)) {
  nav_full[i] <- nav_full[i-1] * (1 + gen_eval$port_returns_monthly[i])
}
nav_hist_asof <- nav_full[seq_len(length(gen_eval$port_returns_monthly) - 1L)]
trailing_dd_asof <- if (length(nav_hist_asof) > 0) {
  pk <- max(nav_hist_asof, na.rm = TRUE)
  cur <- nav_hist_asof[length(nav_hist_asof)]
  if (is.finite(pk) && is.finite(cur) && pk > 0) 1 - cur/pk else 0
} else 0
trailing_vol_asof <- if (length(nav_hist_asof) >= 13) {
  mret <- diff(log(pmax(nav_hist_asof, 1e-9)))
  mret_recent <- tail(mret, 12); mret_recent <- mret_recent[is.finite(mret_recent)]
  if (length(mret_recent) >= 6) stats::sd(mret_recent) * sqrt(12) else NA_real_
} else NA_real_
ov_asof <- apply_overlay_3layer(asof_w0, asof_regime, trailing_dd_asof, trailing_vol_asof,
                                 enable_dd = isTRUE(selected_cfg$enable_dd),
                                 enable_volreg = isTRUE(selected_cfg$enable_volreg),
                                 enable_regime_cash = isTRUE(selected_cfg$enable_regime_cash))
asof_w_risk <- ov_asof$w_risk_scaled
asof_cash   <- ov_asof$cash_pct

# Replace as_of rows in weights_dt
weights_dt <- weights_dt[as_of_date != SIGNAL_AS_OF]
asof_rows_new <- rbindlist(list(
  data.table(as_of_date = SIGNAL_AS_OF, ticker = SIG_TICKERS, weight = as.numeric(asof_w_risk),
              method_selected = selected_name, sleeve_id = "multi_sleeve_blend",
              regime = asof_regime, n_names = length(SIG_TICKERS),
              sigma_method = asof_sigma_method, cash_pct = asof_cash,
              dd_scale = ov_asof$dd_scale, volreg_scale = ov_asof$volreg_scale,
              trailing_dd = trailing_dd_asof,
              trailing_vol_ann = trailing_vol_asof %||% NA_real_),
  if (asof_cash > 0) data.table(as_of_date = SIGNAL_AS_OF, ticker = "CASH", weight = asof_cash,
                                  method_selected = selected_name, sleeve_id = "cash_overlay",
                                  regime = asof_regime, n_names = length(SIG_TICKERS),
                                  sigma_method = asof_sigma_method, cash_pct = asof_cash,
                                  dd_scale = ov_asof$dd_scale, volreg_scale = ov_asof$volreg_scale,
                                  trailing_dd = trailing_dd_asof,
                                  trailing_vol_ann = trailing_vol_asof %||% NA_real_) else NULL
))
weights_dt <- rbindlist(list(weights_dt, asof_rows_new), fill = TRUE)
setorder(weights_dt, as_of_date, -weight)
weights_dt[, method_selected := selected_name]
n_sig_dates_walkforward <- length(unique(weights_dt$as_of_date))
cat(sprintf("[Optimizer Iter12] weights_dt: %d rows × %d sig_dates\n",
            nrow(weights_dt), n_sig_dates_walkforward))

# Validation
val <- weights_dt[, .(sumw = sum(weight),
                       n_risk = sum(ticker != "CASH"),
                       maxw_risk = max(weight[ticker != "CASH"]),
                       minw_risk = min(weight[ticker != "CASH"]),
                       maxw_cash = ifelse(any(ticker == "CASH"), max(weight[ticker == "CASH"]), 0)),
                   by = as_of_date]
cat(sprintf("Validation: Σw [%.6f, %.6f], n_risk [%d, %d], maxw_risk [%.4f, %.4f]\n",
            min(val$sumw), max(val$sumw), min(val$n_risk), max(val$n_risk),
            min(val$maxw_risk), max(val$maxw_risk)))
sum_err <- max(abs(val$sumw - 1))
stopifnot(sum_err < 1e-5)
stopifnot(max(val$n_risk) <= 20L)
stopifnot(max(val$maxw_risk) <= 0.20 + 1e-6)
stopifnot(min(val$minw_risk) >= 0 - 1e-9)
stopifnot(max(val$maxw_cash) <= 0.30 + 1e-6)

# ════════════════════════════════════════════════════════════════════
# 4. Build optimization_package.json
# ════════════════════════════════════════════════════════════════════
cat("\n[Optimizer Iter12] Building optimization_package.json ...\n")
asof_d <- max(weights_dt$as_of_date)
asof_rows <- weights_dt[as_of_date == asof_d]
target_weights <- setNames(as.list(asof_rows$weight), asof_rows$ticker)
asof_cash_pct <- asof_rows$cash_pct[1]
N_risk <- sum(asof_rows$ticker != "CASH")
bench_w_per <- (1 - asof_cash_pct) / N_risk
active_weights <- list()
for (i in seq_len(nrow(asof_rows))) {
  if (asof_rows$ticker[i] == "CASH") next
  active_weights[[asof_rows$ticker[i]]] <- asof_rows$weight[i] - bench_w_per
}

exp_ar <- selected_eval$net_ret_ann
exp_te <- selected_eval$sigma_monthly * sqrt(12)
exp_ir <- selected_eval$net_ir

# Method shopping log (≤10)
method_log <- list()
for (nm in names(eval_results)) {
  r <- eval_results[[nm]]
  if (isTRUE(r$ok)) {
    method_log[[nm]] <- list(
      name = nm, ok = TRUE,
      net_ir = round(r$net_ir, 4), sr_ann = round(r$sr_ann, 4),
      cagr = round(r$cagr, 4), mdd = round(r$mdd, 4),
      ann_to = round(r$ann_to, 4), ann_cost = round(r$ann_cost, 4),
      cvar95_d_proxy = round(r$cvar95_daily_proxy %||% NA, 5),
      avg_cash_pct = round(r$avg_cash_pct, 4),
      avg_dd_scale = round(r$avg_dd_scale, 4),
      avg_volreg_scale = round(r$avg_volreg_scale, 4),
      pct_dd_active = round(r$pct_dd_active, 4),
      pct_volreg_active = round(r$pct_volreg_active, 4),
      pct_cash_gt0 = round(r$pct_cash_gt0, 4),
      pass_to_cap = isTRUE(r$ann_to <= TURNOVER_HARD_CAP),
      pass_cvar_cap = isTRUE((r$cvar95_daily_proxy %||% 1) <= CVAR_DAILY_CAP),
      selected = identical(nm, selected_name)
    )
  } else {
    method_log[[nm]] <- list(name = nm, ok = FALSE, selected = identical(nm, selected_name))
  }
}

binding <- character(0)
if (max(val$maxw_risk) > 0.20 - 1e-3) binding <- c(binding, "weight_bound_upper")
if (max(val$n_risk) >= 20L) binding <- c(binding, "max_names_20")
if (max(val$maxw_cash) >= 0.30 - 1e-3) binding <- c(binding, "cash_overlay_30pct_crisis")
if (selected_eval$ann_to > TURNOVER_HARD_CAP) binding <- c(binding, "turnover_hard_cap_breach")
if (selected_eval$cvar95_daily_proxy > CVAR_DAILY_CAP) binding <- c(binding, "cvar_daily_cap_breach")

infeas_report <- NULL
hard_violations <- character(0)
if (selected_eval$ann_to > TURNOVER_HARD_CAP) hard_violations <- c(hard_violations, "turnover_cap_annual")
if (selected_eval$cvar95_daily_proxy > CVAR_DAILY_CAP) hard_violations <- c(hard_violations, "cvar_daily_cap")
if (length(hard_violations) > 0) {
  to_pass_count <- sum(sapply(eval_results, function(r) isTRUE(r$ok) && r$ann_to <= TURNOVER_HARD_CAP))
  cvar_pass_count <- sum(sapply(eval_results, function(r)
    isTRUE(r$ok) && (r$cvar95_daily_proxy %||% 1) <= CVAR_DAILY_CAP))
  infeas_report <- list(
    reason = sprintf("Selected '%s' breaches hard caps: %s",
                      selected_name, paste(hard_violations, collapse = ", ")),
    violated_constraints = hard_violations,
    observed = list(
      turnover_annual = round(selected_eval$ann_to, 4),
      turnover_hard_cap = TURNOVER_HARD_CAP,
      turnover_pass_methods_count = to_pass_count,
      turnover_pass_methods_total = length(eval_results),
      cvar95_daily_proxy = round(selected_eval$cvar95_daily_proxy, 5),
      cvar_daily_cap = CVAR_DAILY_CAP,
      cvar_pass_methods_count = cvar_pass_count
    ),
    suggested_resolution = "Forge to verify CVaR via daily portfolio returns; consider quarterly rebalance variant."
  )
}

# Layer attribution breakdown for selected method
machinery_breakdown <- list(
  layer_1_linear_tilt = list(
    enabled = identical(selected_cfg$base_method, "LinearTilt"),
    tilt_lambda = selected_cfg$tilt_lambda %||% NA,
    tilt_kappa  = selected_cfg$tilt_kappa  %||% NA,
    note = "Alpha-rank winsorized z, w_pre ∝ rank^λ × (1/σ)^κ"
  ),
  layer_2_kelly_fractional = list(
    enabled = isTRUE(selected_cfg$enable_kelly),
    kelly_frac = selected_cfg$kelly_frac %||% NA,
    note = "w_blend = (1-frac)*w_in + frac*solve(Σ)·alpha_QP"
  ),
  layer_3a_dd_brake = list(
    enabled = isTRUE(selected_cfg$enable_dd),
    triggers_pct = list(low = DD_TRIGGER_LO, mid = DD_TRIGGER_MID, hi = DD_TRIGGER_HI),
    avg_scale = round(selected_eval$avg_dd_scale, 4),
    pct_active = round(selected_eval$pct_dd_active, 4)
  ),
  layer_3b_volreg = list(
    enabled = isTRUE(selected_cfg$enable_volreg),
    target_vol_ann = VOLREG_TARGET,
    avg_scale = round(selected_eval$avg_volreg_scale, 4),
    pct_active = round(selected_eval$pct_volreg_active, 4)
  ),
  layer_3c_fm_regime_cash = list(
    enabled = isTRUE(selected_cfg$enable_regime_cash),
    policy = list(BULL = 0.0, NORMAL = 0.05, CAUTION = 0.15, CRISIS = 0.30),
    avg_cash_pct = round(selected_eval$avg_cash_pct, 4),
    pct_dates_cash_gt0 = round(selected_eval$pct_cash_gt0, 4)
  ),
  layer_4_pooled_sigma_fallback = list(
    enabled = TRUE,
    regimes = c("CRISIS", "CAUTION"),
    max_w_shrink = 0.10,
    note = "Risk Mgr binding rule"
  )
)

# Top overweights / underweights
ow_top <- asof_rows[ticker != "CASH"][order(-weight)][1:5, .(ticker, weight)]
uw_bot <- asof_rows[ticker != "CASH"][order(weight)][1:5, .(ticker, weight)]
hhi_asof <- sum(asof_rows[ticker != "CASH"]$weight^2)

# Regime distribution
regime_dist <- weights_dt[, .(n_dates = length(unique(as_of_date)),
                                avg_cash = round(mean(cash_pct), 4),
                                avg_dd_scale = round(mean(dd_scale, na.rm=TRUE), 4),
                                avg_vol_scale = round(mean(volreg_scale, na.rm=TRUE), 4)),
                            by = regime]

# HRP baseline comparison
hrp_baseline <- eval_results[["HRP_baseline_Iter5"]]
iter6_baseline <- eval_results[["InvVol_Overlay"]]
hrp_baseline_compare <- if (isTRUE(hrp_baseline$ok)) list(
    hrp_baseline_net_ir = round(hrp_baseline$net_ir, 4),
    hrp_baseline_sr_ann = round(hrp_baseline$sr_ann, 4),
    hrp_baseline_cagr = round(hrp_baseline$cagr, 4),
    hrp_baseline_mdd = round(hrp_baseline$mdd, 4),
    selected_vs_hrp_net_ir_delta = round(selected_eval$net_ir - hrp_baseline$net_ir, 4),
    selected_vs_hrp_sr_delta = round(selected_eval$sr_ann - hrp_baseline$sr_ann, 4)
  ) else list(note = "HRP_baseline_Iter5 not ok")
iter6_compare <- if (isTRUE(iter6_baseline$ok)) list(
    iter6_invvol_overlay_net_ir = round(iter6_baseline$net_ir, 4),
    iter6_invvol_overlay_sr_ann = round(iter6_baseline$sr_ann, 4),
    iter6_invvol_overlay_cagr = round(iter6_baseline$cagr, 4),
    iter6_invvol_overlay_mdd = round(iter6_baseline$mdd, 4),
    selected_vs_iter6_net_ir_delta = round(selected_eval$net_ir - iter6_baseline$net_ir, 4)
  ) else list(note = "InvVol_Overlay not ok")

# Regime-specific weights JSON (for as_of stage_artifacts only — last per-regime weights snapshot)
regime_specific_weights <- list()
for (rg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  rg_rows <- weights_dt[regime == rg]
  if (nrow(rg_rows) == 0) next
  last_d <- max(rg_rows$as_of_date)
  last_rows <- rg_rows[as_of_date == last_d]
  regime_specific_weights[[rg]] <- list(
    last_sig_date = as.character(last_d),
    n_names_risk = sum(last_rows$ticker != "CASH"),
    cash_pct = last_rows$cash_pct[1],
    dd_scale = last_rows$dd_scale[1],
    volreg_scale = last_rows$volreg_scale[1],
    weights = setNames(as.list(last_rows$weight), last_rows$ticker)
  )
}

opt_pkg <- list(
  task_id = WT_ID,
  inheritance_from = PARENT_WT,
  iter_label = "Iter 12 — Linear Tilt + Kelly + 3-Layer Overlay (ambitious stack)",
  as_of_date = as.character(asof_d),
  signal_as_of = as.character(SIGNAL_AS_OF),
  selection_objective = "net_ir",
  walk_forward = TRUE,
  n_sig_dates_walkforward = n_sig_dates_walkforward,
  walk_forward_date_range = c(as.character(min(weights_dt$as_of_date)),
                                as.character(max(weights_dt$as_of_date))),
  target_weights = target_weights,
  active_weights = active_weights,
  expected_active_return = round(exp_ar, 4),
  expected_tracking_error = round(exp_te, 4),
  expected_information_ratio = round(exp_ir, 4),
  expected_cagr = round(selected_eval$cagr, 4),
  expected_mdd = round(selected_eval$mdd, 4),
  turnover = round(selected_eval$ann_to, 4),
  estimated_cost = round(selected_eval$ann_cost, 4),
  binding_constraints = binding,
  infeasibility_report = infeas_report,
  method_selected = selected_name,
  method_config = list(
    base_method = selected_cfg$base_method,
    tilt_lambda = selected_cfg$tilt_lambda %||% NA,
    tilt_kappa  = selected_cfg$tilt_kappa  %||% NA,
    enable_kelly = isTRUE(selected_cfg$enable_kelly),
    kelly_frac = selected_cfg$kelly_frac %||% NA,
    enable_dd = isTRUE(selected_cfg$enable_dd),
    enable_volreg = isTRUE(selected_cfg$enable_volreg),
    enable_regime_cash = isTRUE(selected_cfg$enable_regime_cash),
    rebalance_every = selected_cfg$rebalance_every,
    pooled_fallback_regimes = c("CRISIS", "CAUTION"),
    crisis_max_w_shrink = 0.10
  ),
  method_comparison = method_log,
  machinery_layer_breakdown = machinery_breakdown,
  hrp_baseline_compare = hrp_baseline_compare,
  iter6_compare = iter6_compare,
  multi_sleeve_weights = list(
    Core = round(0.65 * (1 - asof_cash_pct), 4),
    Defense = round(0.35 * (1 - asof_cash_pct), 4),
    Cash = round(asof_cash_pct, 4)
  ),
  cash_overlay_policy = list(
    BULL = 0.00, NORMAL = 0.05, CAUTION = 0.15, CRISIS = 0.30,
    rationale = "AX-001 v2 conditional cash. CRISIS 30% per Risk handoff. Validates against alpha CRISIS bootstrap IC=-0.173 [-0.252, -0.092]."
  ),
  crisis_pooled_fallback = list(
    enforced = TRUE,
    regimes_using_pooled = c("CRISIS", "CAUTION"),
    rationale = "Risk Mgr binding rule. CRISIS regime Σ cond=564 > 100; pooled cond=100. Per-sig_date Σ uses LW_constcor in CRISIS/CAUTION + max_w 0.10 shrink."
  ),
  hhi_asof = round(hhi_asof, 4),
  regime_distribution = setNames(as.list(regime_dist$n_dates), regime_dist$regime),
  regime_specific_weights_ref = "stage_artifacts/WT_D20260426_005/regime_specific_weights.json",
  selected_weight_tail_audit = list(
    cvar95_monthly = round(selected_eval$cvar95_monthly, 5),
    cvar95_daily_proxy = round(selected_eval$cvar95_daily_proxy, 5),
    cvar_daily_cap = CVAR_DAILY_CAP,
    cvar_pass = isTRUE(selected_eval$cvar95_daily_proxy <= CVAR_DAILY_CAP),
    mdd = round(selected_eval$mdd, 4),
    method = "monthly_realized_returns_to_daily_proxy_via_sqrt21"
  ),
  pg2_crowding_proxy = list(
    cross_section_jaccard_iter3 = alpha_pkg$crowding_check$cross_section_jaccard_iter3 %||% NA,
    note = "Direct PG2 alpha vector unavailable. STR_1656 ML output without trail. TDC vs PG2 to be computed at Forge backtest stage.",
    direct_pg2_tdc_responsibility = "Forge_backtest_stage"
  ),
  sequential_admission_scenarios = list(
    replacement = list(design = "100% Iter 12 replaces PG2", backtest_status = "TBD by Forge"),
    integration_80_20 = list(
      design = "80% PG2 (STR_1631_SYN_05_80 + STR_1656_MLRA_M05_20) + 20% Iter 12",
      backtest_status = "TBD by Forge",
      expected_benefit_text = sprintf("Iter 12 portfolio-level TO ≈ %.0f%% × 0.20 = %.0f%% book-level — within deployment 300%% cap.",
                                       selected_eval$ann_to * 100, selected_eval$ann_to * 0.20 * 100)
    )
  ),
  explanation = list(
    top_overweights = ow_top$ticker,
    top_underweights = uw_bot$ticker,
    main_tradeoffs = c(
      sprintf("Selected %s (netIR=%.3f). Walk-forward over %d sig_dates.",
              selected_name, exp_ir, n_sig_dates_walkforward),
      sprintf("Stack: %s | Kelly=%s | DD=%s | VolReg=%s | RegimeCash=%s | Rebal=%dM",
              selected_cfg$base_method,
              if (isTRUE(selected_cfg$enable_kelly)) sprintf("frac%.2f", selected_cfg$kelly_frac %||% 0) else "off",
              if (isTRUE(selected_cfg$enable_dd)) "on" else "off",
              if (isTRUE(selected_cfg$enable_volreg)) sprintf("%.0f%%", VOLREG_TARGET*100) else "off",
              if (isTRUE(selected_cfg$enable_regime_cash)) "on" else "off",
              selected_cfg$rebalance_every),
      sprintf("CRISIS pooled-Σ + 0.10 max_w shrink. AX-001 v2 cash 0/5/15/30%% by regime."),
      sprintf("Σw=1 (incl cash). max_names=%d/20. weight_bounds [0,0.20].", max(val$n_risk))
    ),
    pg2_baseline_note = "PG2 = STR_1631_SYN_05 80% + STR_1656_MLRA_M05 20%. TDC at Forge."
  ),
  hard_constraint_compliance = list(
    max_names_20 = list(enforced = TRUE, max_observed = max(val$n_risk),
                          note = "risk securities only; CASH overlay"),
    weight_bounds_0_020 = list(enforced = TRUE,
                                 max_observed_risk = round(max(val$maxw_risk), 4),
                                 min_observed_risk = round(min(val$minw_risk), 6),
                                 note = "risk securities only; CASH cap 0.30 per AX-001 v2"),
    cash_overlay_cap = list(enforced = TRUE, cap = 0.30,
                              max_observed_cash = round(max(val$maxw_cash), 4)),
    long_only = list(enforced = TRUE, min_weight_observed = round(min(val$minw_risk), 6)),
    sum_w_1 = list(enforced = TRUE, max_abs_error = round(sum_err, 8))
  ),
  pit_compliance = list(
    C1 = "PASS — expanding-window LW shrinkage per sig_date",
    C2 = "PASS — alpha at sig_date d → weights at d → realized Ret_1m at d",
    C9 = "PASS — regime_state from alpha_scores (Iter 2 PIT-safe expanding percentile)",
    C11 = "PASS — KR internal regime, no FRED leakage",
    C13 = "PASS — Z_Score_Aligned alpha inherited; no manual flip",
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    lockbox = "ENFORCED — last sig_date 2023-12-01 strictly before lockbox 2024-01-23"
  ),
  red_flags = list(
    RF_O3_turnover_low = if (selected_eval$ann_to < 0.02) "TRIGGERED" else "PASS",
    RF_O5_max_names = if (max(val$n_risk) > 20) "TRIGGERED_BLOCK" else "PASS",
    RF_O6_sum_w = if (sum_err > 0.001) "TRIGGERED_BLOCK" else "PASS",
    RF_O7_long_only_or_bound = if (min(val$minw_risk) < 0 || max(val$maxw_risk) > 0.20)
      "TRIGGERED_BLOCK" else "PASS"
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

# Write package
opt_path <- file.path(WT_DIR, "optimization_package.json")
write_json(opt_pkg, opt_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[Optimizer Iter12] optimization_package.json written: %s\n", opt_path))

# weights.csv (mailbox + stage)
weights_csv <- weights_dt[, .(as_of_date, ticker, weight, method_selected, sleeve_id, regime,
                               n_names, sigma_method, cash_pct, dd_scale, volreg_scale,
                               trailing_dd, trailing_vol_ann)]
fwrite(weights_csv, file.path(WT_DIR, "weights.csv"))
fwrite(weights_csv, file.path(ART_DIR, "weights.csv"))
cat(sprintf("[Optimizer Iter12] weights.csv written (%d rows × %d sig_dates)\n",
            nrow(weights_csv), n_sig_dates_walkforward))

# regime_specific_weights.json
write_json(regime_specific_weights,
            file.path(ART_DIR, "regime_specific_weights.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("[Optimizer Iter12] regime_specific_weights.json written\n")

# weight_method_selected.md
md_lines <- c(
  sprintf("# Optimizer Iter 12 — Method Selection Rationale  \n## %s\n", WT_ID),
  sprintf("**Selected**: `%s`", selected_name),
  sprintf("**Selection objective**: net_ir (R4 P3 hard)\n"),
  "## Method shopping summary (10 candidates)\n",
  sprintf("| Method | netIR | SR | CAGR | MDD | TO | CVaR_d | passTO | passCVaR | selected |"),
  sprintf("|---|---|---|---|---|---|---|---|---|---|"),
  sapply(comp$name, function(nm) {
    rr <- comp[name == nm]
    if (!isTRUE(rr$ok)) return(sprintf("| %s | FAILED |  |  |  |  |  |  |  |  |", nm))
    sprintf("| %s | %.3f | %.3f | %.2f%% | %.2f%% | %.0f%% | %.2f%% | %s | %s | %s |",
            nm, rr$net_ir, rr$sr_ann, rr$cagr*100, rr$mdd*100, rr$ann_to*100,
            rr$cvar95_d*100, ifelse(rr$pass_to,"YES","NO"),
            ifelse(rr$pass_cvar,"YES","NO"),
            ifelse(nm == selected_name, "**YES**",""))
  }),
  "",
  "## Stack Layer breakdown (selected)\n",
  sprintf("- Layer 1 Linear Tilt: enabled=%s, λ=%s, κ=%s",
          identical(selected_cfg$base_method, "LinearTilt"),
          format(selected_cfg$tilt_lambda %||% NA), format(selected_cfg$tilt_kappa %||% NA)),
  sprintf("- Layer 2 Kelly fractional: enabled=%s, frac=%s",
          isTRUE(selected_cfg$enable_kelly), format(selected_cfg$kelly_frac %||% NA)),
  sprintf("- Layer 3a DD Brake: enabled=%s, avg_scale=%.3f, pct_active=%.1f%%",
          isTRUE(selected_cfg$enable_dd), selected_eval$avg_dd_scale, selected_eval$pct_dd_active*100),
  sprintf("- Layer 3b VolReg %.0f%%: enabled=%s, avg_scale=%.3f, pct_active=%.1f%%",
          VOLREG_TARGET*100, isTRUE(selected_cfg$enable_volreg),
          selected_eval$avg_volreg_scale, selected_eval$pct_volreg_active*100),
  sprintf("- Layer 3c FM regime cash: enabled=%s, avg_cash=%.2f%%, pct_dates_cash>0=%.1f%%",
          isTRUE(selected_cfg$enable_regime_cash),
          selected_eval$avg_cash_pct*100, selected_eval$pct_cash_gt0*100),
  "- Layer 4 Pooled-Σ fallback: enforced (CRISIS/CAUTION) + max_w 0.10 shrink",
  "",
  "## HRP baseline (Iter 5) comparison\n",
  if (isTRUE(hrp_baseline$ok)) {
    sprintf("- HRP baseline (no overlay): netIR=%.3f SR=%.3f CAGR=%.2f%% MDD=%.2f%%\n- Selected vs HRP: ΔnetIR=%+.3f, ΔSR=%+.3f",
             hrp_baseline$net_ir, hrp_baseline$sr_ann, hrp_baseline$cagr*100, hrp_baseline$mdd*100,
             selected_eval$net_ir - hrp_baseline$net_ir, selected_eval$sr_ann - hrp_baseline$sr_ann)
  } else "HRP_baseline_Iter5 evaluation failed",
  "",
  "## Iter 6 (InvVol_Overlay) comparison\n",
  if (isTRUE(iter6_baseline$ok)) {
    sprintf("- InvVol_Overlay (Iter 6 STR_1700-style): netIR=%.3f SR=%.3f CAGR=%.2f%% MDD=%.2f%%\n- Selected vs Iter 6: ΔnetIR=%+.3f",
             iter6_baseline$net_ir, iter6_baseline$sr_ann, iter6_baseline$cagr*100, iter6_baseline$mdd*100,
             selected_eval$net_ir - iter6_baseline$net_ir)
  } else "InvVol_Overlay evaluation failed",
  "",
  "## Hard constraints (compliance)",
  sprintf("- max_names = %d / 20 ✓", max(val$n_risk)),
  sprintf("- weight_bounds [0, 0.20]: max_observed = %.4f ✓", max(val$maxw_risk)),
  sprintf("- Σw = 1: max_abs_error = %.2e ✓", sum_err),
  sprintf("- long_only: min_observed = %.6f ✓", min(val$minw_risk)),
  sprintf("- cash overlay cap 0.30: max_observed = %.4f ✓", max(val$maxw_cash))
)
writeLines(md_lines, file.path(ART_DIR, "weight_method_selected.md"))
cat("[Optimizer Iter12] weight_method_selected.md written\n")

# Save workspace
saveRDS(list(weights_dt = weights_dt, comp = comp, eval_results = eval_results,
              selected_name = selected_name, selected_cfg = selected_cfg,
              selected_eval = selected_eval, opt_pkg = opt_pkg,
              sig_dates_use = sig_dates_use),
         file.path(ART_DIR, "optimizer_workspace.rds"))

# ════════════════════════════════════════════════════════════════════
# 5. Lineage
# ════════════════════════════════════════════════════════════════════
cat("\n[Optimizer Iter12] Recording lineage ...\n")
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = WT_ID,
  package_type = "optimization_package",
  method_selected = selected_name,
  input_file_paths = c(
    file.path(PARENT_WT_DIR, "alpha_package.json"),
    file.path(PARENT_WT_DIR, "risk_package.json"),
    file.path(PARENT_ART, "alpha_scores.parquet"),
    file.path(PARENT_ART, "covariance.parquet"),
    file.path(PARENT_ART, "covariance_pooled_fallback.parquet")
  ),
  windows = list(
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    signal_as_of = as.character(SIGNAL_AS_OF),
    walk_forward_range = c(as.character(min(weights_dt$as_of_date)),
                            as.character(max(weights_dt$as_of_date)))
  ),
  random_seed = 20260426L,
  extra = list(
    iter_label = "Iter 12 — LinearTilt + Kelly + 3-Layer Overlay (ambitious stack)",
    n_sig_dates_walkforward = n_sig_dates_walkforward,
    selected_net_ir = round(selected_eval$net_ir, 4),
    selected_sr_ann = round(selected_eval$sr_ann, 4),
    selected_cagr = round(selected_eval$cagr, 4),
    selected_mdd = round(selected_eval$mdd, 4),
    selected_turnover = round(selected_eval$ann_to, 4),
    parent_wt = PARENT_WT
  )
)

cat("\n[Optimizer Iter12] DRAFT phase COMPLETE.\n")
cat(sprintf("  selected_method=%s\n  netIR=%.3f  SR=%.3f  CAGR=%.2f%%  MDD=%.2f%%  TO=%.0f%%  HHI_asof=%.4f  cash_at_asof=%.0f%%\n",
            selected_name, exp_ir, selected_eval$sr_ann,
            selected_eval$cagr*100, selected_eval$mdd*100,
            selected_eval$ann_to*100, hhi_asof, asof_cash_pct*100))
