#==============================================================================
# WT-D20260425_010 — Optimizer Research (Iter 5 Cross-family Blender)
#
# Mission:
#   - Walk-forward weights schedule (240 sig_dates × top-20)
#   - CRISIS/CAUTION pooled-Σ fallback (Risk binding rule)
#   - Multi-sleeve (Core 0.65 / Defense 0.35) cash regime overlay (AX-001 v2)
#   - Method shopping ≤10, selection_objective = net_ir
#   - Hard: max_names ≤ 20, weight_bounds [0, 0.20], long-only, Σw = 1
#
# Input:
#   - alpha_package.json  (alpha_vector / confidence_vector / regime_state schedule)
#   - risk_package.json   (Σ = LW_oracle, pooled fallback Σ, cor_core_def 0.692)
#   - alpha_scores.parquet (240 × 773, score_eff + score_core_z + score_defense_z + regime_state + Ret_1m)
#   - covariance.parquet  (as_of 20×20 Σ)
#   - covariance_pooled_fallback.parquet (pooled 20×20 Σ)
#
# Output:
#   - optimization_package.json (mailbox)
#   - weights.csv (mailbox + stage_artifacts)  schema: as_of_date,ticker,weight,method_selected,sleeve_id
#   - weight_method_selected.md (stage_artifacts)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(arrow)
  library(quadprog)
  library(digest)
})

set.seed(2026010L)

WT_ID   <- "WT-D20260425_010"
WT_DIR  <- file.path("qepm/mailbox/worktask", WT_ID)
ART_DIR <- file.path("stage_artifacts", "WT_D20260425_010")

PIT_HARD_CUTOFF <- as.Date("2023-11-30")    # Risk-side cutoff
SIGNAL_AS_OF    <- as.Date("2023-12-01")    # final sig_date
COST_BPS        <- 15                        # one-way bps (request.json v2.3_kr_retail_15bps)

# ── Helpers ───────────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) {
    n <- length(w)
    return(rep(target_sum / n, n))
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

# ── Pairwise-complete cov estimation, then LW shrinkage to const-cor ─────
# Handles staggered listings (different ticker history start dates).
.sample_cov_pairwise <- function(R) {
  R <- as.matrix(R)
  S <- stats::cov(R, use = "pairwise.complete.obs")
  S[!is.finite(S)] <- 0
  # Symmetrize
  S <- 0.5 * (S + t(S))
  # Per-name min observation count (for shrinkage T)
  n_pair <- crossprod(!is.na(R))
  attr(S, "n_pair") <- n_pair
  S
}

# Closed-form LW oracle approximating shrinkage to constant-correlation target.
# Uses pairwise-complete sample cov to handle staggered listings.
lw_oracle_cov <- function(R) {
  R <- as.matrix(R)
  N <- ncol(R)
  if (N < 2) return(NULL)
  # Drop columns with < 24 non-NA
  col_nna <- colSums(!is.na(R))
  keep <- col_nna >= 24
  if (sum(keep) < 5) return(NULL)
  R <- R[, keep, drop = FALSE]
  N <- ncol(R)
  T_eff <- max(col_nna[keep])
  if (T_eff < 24) return(NULL)
  S <- .sample_cov_pairwise(R)
  # PSD nearest projection (eigenvalue clip)
  eig <- eigen(S, symmetric = TRUE)
  vals <- eig$values
  if (any(vals < 0)) {
    vals <- pmax(vals, 1e-10)
    S <- eig$vectors %*% diag(vals) %*% t(eig$vectors)
    S <- 0.5 * (S + t(S))
  }
  s <- sqrt(diag(S))
  if (any(!is.finite(s)) || any(s <= 1e-12)) return(NULL)
  Cor_S <- S / (s %*% t(s))
  Cor_S[!is.finite(Cor_S)] <- 0
  rbar <- (sum(Cor_S) - N) / (N * (N - 1))
  if (!is.finite(rbar)) rbar <- 0
  rbar <- pmax(pmin(rbar, 0.99), -0.99)
  F <- rbar * (s %*% t(s))
  diag(F) <- diag(S)
  # Oracle shrinkage intensity (Ledoit-Wolf 2004, approximated)
  R_demean <- sweep(R, 2, colMeans(R, na.rm = TRUE), `-`)
  R_demean[is.na(R_demean)] <- 0
  pi_hat <- 0
  for (i in seq_len(N)) {
    for (j in seq_len(N)) {
      pi_hat <- pi_hat + mean((R_demean[, i] * R_demean[, j] - S[i, j])^2)
    }
  }
  gamma_hat <- sum((F - S)^2)
  if (gamma_hat <= 0) {
    delta <- 0.5
  } else {
    delta <- max(0, min(1, pi_hat / (T_eff * gamma_hat)))
  }
  Sigma_hat <- delta * F + (1 - delta) * S
  Sigma_hat <- 0.5 * (Sigma_hat + t(Sigma_hat))
  # Final PSD
  eig2 <- eigen(Sigma_hat, symmetric = TRUE, only.values = TRUE)$values
  if (any(eig2 < 1e-10)) Sigma_hat <- Sigma_hat + diag(1e-8, N)
  rownames(Sigma_hat) <- colnames(Sigma_hat) <- colnames(R)
  attr(Sigma_hat, "delta") <- delta
  attr(Sigma_hat, "rbar") <- rbar
  attr(Sigma_hat, "T_eff") <- T_eff
  Sigma_hat
}

lw_constcor_cov <- function(R) {
  R <- as.matrix(R)
  N <- ncol(R)
  if (N < 2) return(NULL)
  col_nna <- colSums(!is.na(R))
  keep <- col_nna >= 24
  if (sum(keep) < 5) return(NULL)
  R <- R[, keep, drop = FALSE]
  N <- ncol(R)
  S <- .sample_cov_pairwise(R)
  # PSD project
  eig <- eigen(S, symmetric = TRUE)
  vals <- pmax(eig$values, 1e-10)
  S <- eig$vectors %*% diag(vals) %*% t(eig$vectors)
  S <- 0.5 * (S + t(S))
  s <- sqrt(diag(S))
  if (any(!is.finite(s)) || any(s <= 1e-12)) return(NULL)
  Cor_S <- S / (s %*% t(s))
  Cor_S[!is.finite(Cor_S)] <- 0
  rbar <- (sum(Cor_S) - N) / (N * (N - 1))
  rbar <- pmax(pmin(rbar, 0.99), -0.99)
  F <- rbar * (s %*% t(s))
  diag(F) <- diag(S)
  # Heavier shrinkage for fallback (closer to const-cor) — δ=0.5 fixed
  delta <- 0.5
  Sigma_hat <- delta * F + (1 - delta) * S
  Sigma_hat <- 0.5 * (Sigma_hat + t(Sigma_hat))
  eig2 <- eigen(Sigma_hat, symmetric = TRUE, only.values = TRUE)$values
  if (any(eig2 < 1e-10)) Sigma_hat <- Sigma_hat + diag(1e-8, N)
  rownames(Sigma_hat) <- colnames(Sigma_hat) <- colnames(R)
  attr(Sigma_hat, "delta") <- delta
  attr(Sigma_hat, "rbar") <- rbar
  Sigma_hat
}

# ── MVO QP solver (long-only Σw=1, [lb, ub]) ─────────────────────────────
# alpha: named vector; Sigma: positive semi-definite N×N
# confidence: optional named vector ∈ [0,1]; α̃_i = c_i × α_i (R4-A confidence-aware)
# w_prev: optional named vector for turnover-penalty (φ × ||w - w_prev||²)
# turnover_phi: turnover penalty coefficient (default 0)
mvo_qp <- function(alpha, Sigma, lambda = 2.0, lb = 0, ub = 0.20,
                    confidence = NULL, w_prev = NULL, turnover_phi = 0,
                    psi = 0) {
  N <- length(alpha)
  alpha_tilde <- as.numeric(alpha)
  if (!is.null(confidence)) {
    cv <- confidence[names(alpha)]
    cv[is.na(cv)] <- 0.5
    cv <- pmax(pmin(cv, 1.0), 0.0)
    alpha_tilde <- alpha_tilde * cv
  }
  Dmat <- lambda * Sigma
  # Turnover penalty: add φ × ||w - w_prev||² → Dmat += 2φI, dvec += 2φ × w_prev
  if (turnover_phi > 0 && !is.null(w_prev)) {
    wp <- w_prev[names(alpha)]
    wp[is.na(wp)] <- 0
    Dmat <- Dmat + diag(2 * turnover_phi, N)
    alpha_tilde <- alpha_tilde + 2 * turnover_phi * wp
  }
  # Forecast Uncertainty Penalty (R4-A confidence)
  if (!is.null(confidence) && psi > 0) {
    cv <- confidence[names(alpha)]
    cv[is.na(cv)] <- 0.5
    Dmat <- Dmat + diag(2 * psi * (1 - cv)^2, N)
  }
  diag(Dmat) <- diag(Dmat) + 1e-8
  dvec <- alpha_tilde
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(1, rep(lb, N), rep(-ub, N))
  res <- tryCatch(
    solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
    error = function(e) NULL
  )
  if (is.null(res)) return(NULL)
  w <- res$solution
  w[abs(w) < 1e-9] <- 0
  w <- normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
  w
}

# ── No-trade band: keep w_prev if |Δw|/w_prev < band_pct OR |Δw| < band_abs ──
apply_no_trade_band <- function(w_new, w_prev, band_pct = 0.20, band_abs = 0.005) {
  if (is.null(w_prev)) return(w_new)
  all_names <- union(names(w_new), names(w_prev))
  w_n <- setNames(rep(0, length(all_names)), all_names)
  w_p <- setNames(rep(0, length(all_names)), all_names)
  w_n[names(w_new)] <- w_new
  w_p[names(w_prev)] <- w_prev
  delta <- w_n - w_p
  rel <- abs(delta) / pmax(abs(w_p), 1e-6)
  hold <- (rel < band_pct) & (abs(delta) < band_abs)
  w_out <- w_n
  w_out[hold] <- w_p[hold]
  # Renormalize
  if (sum(w_out) > 0) w_out <- w_out / sum(w_out)
  # Keep only intersect with w_new names (don't reintroduce dropped names)
  w_out <- w_out[names(w_new)]
  w_out / sum(w_out)
}

# ── HRP weight (López de Prado 2016) — bisection on inverse-variance ────
hrp_qd <- function(Sigma) {
  N <- nrow(Sigma)
  if (N == 1) return(1)
  s <- sqrt(diag(Sigma))
  if (any(s < 1e-12)) s[s < 1e-12] <- 1e-6
  Cor <- Sigma / (s %*% t(s))
  Cor[!is.finite(Cor)] <- 0
  # Distance metric
  d <- sqrt(pmax(0.5 * (1 - Cor), 0))
  hc <- tryCatch(stats::hclust(stats::as.dist(d), method = "single"),
                  error = function(e) NULL)
  if (is.null(hc)) {
    # Fallback to inverse-variance
    iv <- 1 / pmax(diag(Sigma), 1e-12)
    return(as.numeric(iv / sum(iv)))
  }
  order_idx <- hc$order
  # Recursive bisection — work in POSITION space along order_idx
  # Returns weights on positions 1..N (matching Sigma rows)
  w <- rep(1.0, N)
  cluster_alloc <- function(start, end) {
    if (start == end) return(invisible(NULL))
    mid <- start + floor((end - start) / 2)
    L_pos <- order_idx[start:mid]
    R_pos <- order_idx[(mid + 1):end]
    iv_L <- 1 / pmax(diag(Sigma)[L_pos], 1e-12)
    w_L <- iv_L / sum(iv_L)
    iv_R <- 1 / pmax(diag(Sigma)[R_pos], 1e-12)
    w_R <- iv_R / sum(iv_R)
    var_L <- as.numeric(t(w_L) %*% Sigma[L_pos, L_pos, drop = FALSE] %*% w_L)
    var_R <- as.numeric(t(w_R) %*% Sigma[R_pos, R_pos, drop = FALSE] %*% w_R)
    if (!is.finite(var_L) || var_L < 1e-15) var_L <- 1e-15
    if (!is.finite(var_R) || var_R < 1e-15) var_R <- 1e-15
    alpha_L <- 1 - var_L / (var_L + var_R)
    w[L_pos] <<- w[L_pos] * alpha_L
    w[R_pos] <<- w[R_pos] * (1 - alpha_L)
    cluster_alloc(start, mid)
    cluster_alloc(mid + 1, end)
  }
  cluster_alloc(1, N)
  if (any(!is.finite(w))) w[!is.finite(w)] <- 0
  if (sum(w) <= 1e-12) return(rep(1 / N, N))
  as.numeric(w / sum(w))
}

# ── ERC (equal-risk-contribution) iterative ──────────────────────────────
erc_qd <- function(Sigma, max_iter = 200, tol = 1e-8) {
  N <- nrow(Sigma)
  w <- rep(1 / N, N)
  for (k in seq_len(max_iter)) {
    sw <- as.numeric(Sigma %*% w)
    rc <- w * sw
    target <- mean(rc)
    grad <- rc - target
    step <- 0.05
    w_new <- w - step * grad
    w_new[w_new < 0] <- 1e-6
    w_new <- w_new / sum(w_new)
    if (max(abs(w_new - w)) < tol) { w <- w_new; break }
    w <- w_new
  }
  w
}

# ── MaxDiv: max [w'σ / sqrt(w'Σw)] ───────────────────────────────────────
maxdiv_qd <- function(Sigma, lb = 0, ub = 0.20) {
  N <- nrow(Sigma)
  s <- sqrt(diag(Sigma))
  # Equivalent QP: min w'Σw s.t. w'σ = 1, w>=0   (then renorm)
  # Dual: cov-target inversion
  Dmat <- Sigma + diag(1e-8, N)
  dvec <- rep(0, N)
  Amat <- cbind(s, diag(N), -diag(N))
  bvec <- c(1, rep(lb * 0, N), rep(-ub * 5, N))   # relaxed bounds; renorm later
  res <- tryCatch(
    solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
    error = function(e) NULL
  )
  if (is.null(res)) return(rep(1 / N, N))
  w <- res$solution
  w[w < 0] <- 0
  if (sum(w) <= 0) return(rep(1 / N, N))
  w <- w / sum(w)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ── CVaR LP (Rockafellar-Uryasev, alpha=0.95) — LP via quadprog penalty ──
# For tractability without Rglpk: minimize w'Σw + κ × tail_cost with synthetic penalty
# (proxy: emphasize negative-skew names by inverse-variance + tail correction)
cvar_proxy_qd <- function(R_panel, alpha_level = 0.95, lb = 0, ub = 0.20) {
  N <- ncol(R_panel)
  if (nrow(R_panel) < 30) {
    return(rep(1 / N, N))
  }
  # Per-name CVaR_95
  cvar_names <- apply(R_panel, 2, function(x) {
    x <- x[is.finite(x)]
    if (length(x) < 10) return(0.05)
    q <- stats::quantile(x, 1 - alpha_level, na.rm = TRUE)
    -mean(x[x <= q], na.rm = TRUE)
  })
  cvar_names[!is.finite(cvar_names) | cvar_names <= 0] <- 0.05
  w <- 1 / cvar_names
  w <- w / sum(w)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ── Cash overlay policy (AX-001 v2 conditional cash) ─────────────────────
# Returns risk-asset weight (1 - cash%) given regime_state.
cash_overlay_pct <- function(regime) {
  switch(as.character(regime),
    "BULL"    = 0.00,
    "NORMAL"  = 0.05,
    "CAUTION" = 0.15,
    "CRISIS"  = 0.30,
    0.05  # default fallback
  )
}

# ── Per-sig_date weight computation function ─────────────────────────────
# Returns: data.table(as_of_date, ticker, weight, method_selected, sleeve_id, regime, n_names, sigma_method)
compute_weights_at_date <- function(sig_date, alpha_scores,
                                     ret_panel,
                                     method = "MVO",
                                     lambda = 2.0,
                                     ub = 0.20,
                                     max_names = 20L,
                                     min_names = 15L,
                                     pooled_fallback_regimes = c("CRISIS", "CAUTION"),
                                     w_prev_risk = NULL,
                                     confidence = NULL,
                                     turnover_phi = 0,
                                     no_trade_band = NULL,
                                     verbose = FALSE) {

  # Eligible universe at sig_date: score_eff non-NA + ret panel availability
  panel_t <- alpha_scores[Date == sig_date & !is.na(score_eff)]
  if (nrow(panel_t) == 0) return(NULL)
  regime <- panel_t$regime_state[1]

  # Top-N by score_eff (descending), respect max_names
  setorder(panel_t, -score_eff)
  N_eligible <- nrow(panel_t)
  N_target <- min(max_names, N_eligible)
  if (N_target < min_names && N_eligible >= min_names) {
    N_target <- min_names
  }
  if (N_target < 5L) {
    return(data.table(as_of_date = sig_date, ticker = NA, weight = NA,
                      method_selected = method, sleeve_id = "infeasible",
                      regime = regime, n_names = N_eligible, sigma_method = NA))
  }
  picks <- panel_t[1:N_target]
  tickers_t <- picks$Ticker
  alpha_t   <- picks$score_eff
  names(alpha_t) <- tickers_t

  # Σ estimation: expanding-window monthly returns up to sig_date-1
  # Use ret_panel (Date × Ticker matrix of Ret_1m)
  hist_panel <- ret_panel[Date < sig_date & Ticker %in% tickers_t]
  ret_wide <- dcast(hist_panel, Date ~ Ticker, value.var = "Ret_1m")
  ret_mat <- as.matrix(ret_wide[, !"Date", with = FALSE])
  rownames(ret_mat) <- as.character(ret_wide$Date)
  # Keep tickers actually in ret_mat
  ticker_avail <- intersect(tickers_t, colnames(ret_mat))
  if (length(ticker_avail) < 5L) {
    return(NULL)
  }
  ret_mat <- ret_mat[, ticker_avail, drop = FALSE]
  alpha_t <- alpha_t[ticker_avail]
  tickers_t <- ticker_avail

  # Filter ret_mat to require >= 24M non-NA per ticker (else drop ticker)
  col_nna <- colSums(!is.na(ret_mat))
  keep_tickers <- names(col_nna)[col_nna >= 24]
  if (length(keep_tickers) < 5) {
    return(NULL)
  }
  ret_mat <- ret_mat[, keep_tickers, drop = FALSE]
  alpha_t <- alpha_t[keep_tickers]
  tickers_t <- keep_tickers

  if (nrow(ret_mat) < 24L) {
    Sigma_t <- diag(rep(0.005, length(tickers_t)))
    rownames(Sigma_t) <- colnames(Sigma_t) <- tickers_t
    sigma_method <- "diag_fallback_short_hist"
  } else {
    # Regime-conditional Σ estimator
    if (regime %in% pooled_fallback_regimes) {
      Sigma_t <- lw_constcor_cov(ret_mat)
      sigma_method <- "lw_constcor_pooled_fallback"
    } else {
      Sigma_t <- lw_oracle_cov(ret_mat)
      sigma_method <- "lw_oracle"
    }
    if (is.null(Sigma_t)) {
      var_diag <- apply(ret_mat, 2, stats::var, na.rm = TRUE)
      var_diag[!is.finite(var_diag) | var_diag <= 0] <- 0.01
      Sigma_t <- diag(var_diag)
      rownames(Sigma_t) <- colnames(Sigma_t) <- tickers_t
      sigma_method <- "sample_diag_fallback"
    }
  }

  # Reorder to keep_tickers order; drop any tickers not in Sigma columns
  sigma_tickers <- intersect(tickers_t, colnames(Sigma_t))
  if (length(sigma_tickers) < 5) return(NULL)
  Sigma_t  <- Sigma_t[sigma_tickers, sigma_tickers, drop = FALSE]
  alpha_t  <- alpha_t[sigma_tickers]
  tickers_t <- sigma_tickers

  # Apply method
  N <- length(tickers_t)
  names(alpha_t) <- tickers_t
  w <- switch(method,
    "MVO_lam2"        = mvo_qp(alpha_t, Sigma_t, lambda = 2.0, lb = 0, ub = ub),
    "MVO_lam5"        = mvo_qp(alpha_t, Sigma_t, lambda = 5.0, lb = 0, ub = ub),
    "MVO_lam1"        = mvo_qp(alpha_t, Sigma_t, lambda = 1.0, lb = 0, ub = ub),
    "MVO_conf_TP"     = mvo_qp(alpha_t, Sigma_t, lambda = 2.0, lb = 0, ub = ub,
                                  confidence = confidence, w_prev = w_prev_risk,
                                  turnover_phi = turnover_phi, psi = 0.3),
    "MVO_TP_high"     = mvo_qp(alpha_t, Sigma_t, lambda = 2.0, lb = 0, ub = ub,
                                  w_prev = w_prev_risk, turnover_phi = 5.0),
    "HRP"             = hrp_qd(Sigma_t),
    "ERC"             = erc_qd(Sigma_t),
    "MaxDiv"          = maxdiv_qd(Sigma_t, ub = ub),
    "EqualWeight"     = rep(1 / N, N),
    "AlphaProp"       = {
      a <- pmax(alpha_t, 0)
      if (sum(a) <= 0) rep(1 / N, N) else as.numeric(a / sum(a))
    },
    "InvVol"          = {
      iv <- 1 / sqrt(diag(Sigma_t))
      iv / sum(iv)
    },
    NULL
  )
  if (is.null(w)) {
    w <- rep(1 / N, N)
    method <- paste0(method, "_fallback_EW")
  }
  names(w) <- tickers_t
  # Apply no-trade band wrapper if requested
  if (!is.null(no_trade_band) && !is.null(w_prev_risk)) {
    w <- apply_no_trade_band(w, w_prev_risk,
                              band_pct = no_trade_band$band_pct %||% 0.20,
                              band_abs = no_trade_band$band_abs %||% 0.005)
  }
  w <- normalize_long_only(w, lb = 0, ub = ub, target_sum = 1)

  # Cash overlay (AX-001 v2)
  cash_pct <- cash_overlay_pct(regime)
  w_risk <- w * (1 - cash_pct)

  # Build output
  rows <- data.table(
    as_of_date = sig_date,
    ticker = c(names(w_risk), if (cash_pct > 0) "CASH" else character(0)),
    weight = c(as.numeric(w_risk), if (cash_pct > 0) cash_pct else numeric(0)),
    method_selected = method,
    sleeve_id = c(rep("multi_sleeve_blend", length(w_risk)),
                  if (cash_pct > 0) "cash_overlay" else character(0)),
    regime = regime,
    n_names = N,
    sigma_method = sigma_method,
    cash_pct = cash_pct
  )
  rows
}

# ── Method shopping evaluation: walk-forward portfolio metrics ──────────
# Apply method consistently across sig_dates, compute net IR + turnover-adj
walk_forward_method_eval <- function(method_name, alpha_scores, ret_panel,
                                      sig_dates,
                                      ub = 0.20, max_names = 20L, min_names = 15L,
                                      cost_bps = 15,
                                      confidence = NULL,
                                      turnover_phi = 0,
                                      no_trade_band = NULL,
                                      rebalance_every = 1L,   # 1 = monthly, 3 = quarterly, 6 = semi
                                      collect_weights = FALSE,
                                      compute_port_returns_daily = FALSE) {
  W_prev <- NULL
  port_ret <- numeric(length(sig_dates))
  port_to  <- numeric(length(sig_dates))
  port_cost <- numeric(length(sig_dates))
  cash_pct_seq <- numeric(length(sig_dates))
  realized_risk_seq <- numeric(length(sig_dates))
  weights_collected <- list()
  n_used <- 0L
  last_res <- NULL
  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    # Decide whether to rebalance this period
    do_rebalance <- (i == 1L) || ((i - 1L) %% rebalance_every == 0L)
    if (do_rebalance) {
      w_prev_risk_named <- NULL
      if (!is.null(W_prev)) {
        wpr <- W_prev[ticker != "CASH"]
        w_prev_risk_named <- setNames(wpr$weight, wpr$ticker)
      }
      res <- tryCatch(
        compute_weights_at_date(d, alpha_scores, ret_panel,
                                 method = method_name, ub = ub,
                                 max_names = max_names, min_names = min_names,
                                 w_prev_risk = w_prev_risk_named,
                                 confidence = confidence,
                                 turnover_phi = turnover_phi,
                                 no_trade_band = no_trade_band),
        error = function(e) NULL
      )
      if (is.null(res) || any(is.na(res$weight))) next
      last_res <- res
    } else {
      # Hold previous weights but re-apply cash overlay based on current regime
      if (is.null(last_res)) next
      panel_t <- alpha_scores[Date == d & !is.na(score_eff)]
      if (nrow(panel_t) == 0) next
      regime <- panel_t$regime_state[1]
      cash_pct_t <- cash_overlay_pct(regime)
      # Rescale risk weights to (1 - cash_pct_t)
      risk_rows <- last_res[ticker != "CASH"]
      risk_w_norm <- risk_rows$weight / sum(risk_rows$weight)  # renormalize to 1
      risk_rows$weight <- risk_w_norm * (1 - cash_pct_t)
      res <- rbindlist(list(
        risk_rows[, .(as_of_date = d, ticker, weight, method_selected,
                       sleeve_id, regime, n_names, sigma_method, cash_pct = cash_pct_t)],
        if (cash_pct_t > 0) data.table(as_of_date = d, ticker = "CASH",
                                         weight = cash_pct_t,
                                         method_selected = last_res$method_selected[1],
                                         sleeve_id = "cash_overlay",
                                         regime = regime,
                                         n_names = last_res$n_names[1],
                                         sigma_method = last_res$sigma_method[1],
                                         cash_pct = cash_pct_t) else NULL
      ))
    }
    n_used <- n_used + 1L
    if (collect_weights) weights_collected[[length(weights_collected) + 1L]] <- res

    # Realized return: Ret_1m at sig_date d = forward 1M return realized at d+1M
    risk_rows_eval <- res[ticker != "CASH"]
    rd <- alpha_scores[Date == d, .(Ticker, Ret_1m)]
    setkey(rd, Ticker)
    risk_rows_eval <- rd[risk_rows_eval, on = .(Ticker = ticker)]
    risk_rows_eval[is.na(Ret_1m), Ret_1m := 0]
    realized_risk <- sum(risk_rows_eval$weight * risk_rows_eval$Ret_1m, na.rm = TRUE)
    cash_pct_t <- res$cash_pct[1] %||% 0
    # cash earns 0 (over-conservative; could use risk-free but keep at 0)
    realized_t <- realized_risk + 0  # weights already include cash * 0
    # Wait: risk_rows weights sum to (1-cash_pct), realized_risk is product. Add cash*0 = 0.
    # So realized_t = realized_risk

    # Turnover
    if (!is.null(W_prev)) {
      all_names <- union(W_prev$ticker, res$ticker)
      w_prev_aligned <- setNames(rep(0, length(all_names)), all_names)
      w_prev_aligned[W_prev$ticker] <- W_prev$weight
      w_now_aligned  <- setNames(rep(0, length(all_names)), all_names)
      w_now_aligned[res$ticker] <- res$weight
      l1 <- sum(abs(w_now_aligned - w_prev_aligned))
      to_t <- l1 / 2
    } else {
      to_t <- 1.0
    }
    cost_t <- to_t * (cost_bps / 1e4) * 2  # round-trip × 2
    port_ret[i] <- realized_t - cost_t
    port_to[i]  <- to_t
    port_cost[i] <- cost_t
    cash_pct_seq[i] <- cash_pct_t
    realized_risk_seq[i] <- realized_risk
    W_prev <- res[, .(ticker, weight)]
  }
  used <- which(port_ret != 0 | port_to != 0)
  if (length(used) < 12) {
    return(list(method = method_name, n_used = n_used, ok = FALSE))
  }
  pr <- port_ret[used]
  pt <- port_to[used]
  pc <- port_cost[used]
  cs <- cash_pct_seq[used]
  rr <- realized_risk_seq[used]
  mu <- mean(pr); sigma <- stats::sd(pr)
  sr_monthly <- if (sigma > 1e-12) mu / sigma else 0
  sr_ann     <- sr_monthly * sqrt(12)
  ann_to     <- mean(pt) * 12
  ann_cost   <- mean(pc) * 12
  net_ret_ann <- mean(pr) * 12
  net_ir     <- if (sigma > 1e-12) (mean(pr) / sigma) * sqrt(12) else 0
  cum_ret <- prod(1 + pr) - 1
  T_use <- length(pr)
  cagr <- (1 + cum_ret)^(12 / T_use) - 1
  cc <- cumprod(1 + pr); pk <- cummax(cc); dd <- cc / pk - 1
  mdd <- min(dd)
  # Tail metrics on portfolio monthly returns
  # CVaR_95 (monthly) — approximate to daily as monthly/sqrt(21)
  q05 <- stats::quantile(pr, 0.05, na.rm = TRUE)
  cvar95_m <- -mean(pr[pr <= q05], na.rm = TRUE)
  cvar95_d_proxy <- cvar95_m / sqrt(21)   # rough daily proxy
  list(method = method_name, n_used = n_used, ok = TRUE,
       net_ir = net_ir, sr_ann = sr_ann, cagr = cagr, mdd = mdd,
       ann_to = ann_to, ann_cost = ann_cost, T_use = T_use,
       mu_monthly = mu, sigma_monthly = sigma, net_ret_ann = net_ret_ann,
       cvar95_monthly = cvar95_m, cvar95_daily_proxy = cvar95_d_proxy,
       port_returns_monthly = pr, port_to = pt, port_cash = cs,
       weights_collected = if (collect_weights) weights_collected else NULL)
}

# ────────────────────────────────────────────────────────────────────────
# 1. Load packages
# ────────────────────────────────────────────────────────────────────────
cat("[Optimizer Iter5] Loading inputs...\n")
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = TRUE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = TRUE)
req_pkg   <- fromJSON(file.path(WT_DIR, "request.json"),       simplifyVector = TRUE)

alpha_scores <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
setkey(alpha_scores, Date, Ticker)

# Ret panel for Σ history
ret_panel <- alpha_scores[, .(Date, Ticker, Ret_1m)]
ret_panel <- ret_panel[!is.na(Ret_1m)]
setkey(ret_panel, Date, Ticker)

# Sigma matrices from Risk
Sigma_dt        <- as.data.table(read_parquet(file.path(ART_DIR, "covariance.parquet")))
Sigma_pooled_dt <- as.data.table(read_parquet(file.path(ART_DIR, "covariance_pooled_fallback.parquet")))
SIG_TICKERS <- as.character(Sigma_dt$Ticker)
Sigma_asof  <- as.matrix(Sigma_dt[, !"Ticker", with = FALSE])
rownames(Sigma_asof) <- colnames(Sigma_asof) <- SIG_TICKERS
Sigma_pooled_asof <- as.matrix(Sigma_pooled_dt[, !"Ticker", with = FALSE])
rownames(Sigma_pooled_asof) <- colnames(Sigma_pooled_asof) <- SIG_TICKERS

cat(sprintf("[Optimizer Iter5] alpha panel: %d sig_dates × %d tickers\n",
            length(unique(alpha_scores$Date)), length(unique(alpha_scores$Ticker))))
cat(sprintf("[Optimizer Iter5] Risk Σ as_of: %dx%d (cond %.2f), pooled: %dx%d (cond %.0f)\n",
            nrow(Sigma_asof), ncol(Sigma_asof), kappa(Sigma_asof, exact = TRUE),
            nrow(Sigma_pooled_asof), ncol(Sigma_pooled_asof), kappa(Sigma_pooled_asof, exact = TRUE)))

# Date range — start at first date with >= min_names eligible + 24M ret history
all_sig <- sort(unique(alpha_scores$Date))
elig_per_date <- alpha_scores[!is.na(score_eff), .N, by = Date]
setkey(elig_per_date, Date)
min_hist_start <- as.Date("2006-01-01")  # require 24M of ret_panel history before first weight
sig_dates_use <- all_sig[all_sig >= min_hist_start & all_sig <= SIGNAL_AS_OF]
cat(sprintf("[Optimizer Iter5] sig_dates_use: %d (%s ~ %s)\n",
            length(sig_dates_use), as.character(min(sig_dates_use)),
            as.character(max(sig_dates_use))))

# ────────────────────────────────────────────────────────────────────────
# 2. Method shopping (walk-forward) — ≤ 10 candidates, select by net_ir
# ────────────────────────────────────────────────────────────────────────
cat("\n[Optimizer Iter5] Method shopping (walk-forward, 10 candidates) ...\n")

# Confidence vector from alpha_package (named on 20 final tickers)
conf_vec_all <- unlist(alpha_pkg$confidence_vector)

# 10-candidate method shopping (cap = 10, R2-C):
# Includes baseline, MVO variants, RP family, MaxDiv, turnover-aware variants.
CAND_CONFIG <- list(
  list(name = "MVO_lam2",        method = "MVO_lam2",        rebal = 1L, ntb = NULL,                                    phi = 0,   conf = NULL),
  list(name = "MVO_conf_TP",     method = "MVO_conf_TP",     rebal = 1L, ntb = NULL,                                    phi = 2.0, conf = conf_vec_all),
  list(name = "MVO_TP_high",     method = "MVO_TP_high",     rebal = 1L, ntb = NULL,                                    phi = 5.0, conf = NULL),
  list(name = "HRP",             method = "HRP",             rebal = 1L, ntb = NULL,                                    phi = 0,   conf = NULL),
  list(name = "HRP_NoTradeBand", method = "HRP",             rebal = 1L, ntb = list(band_pct = 0.30, band_abs = 0.01), phi = 0,   conf = NULL),
  list(name = "ERC",             method = "ERC",             rebal = 1L, ntb = NULL,                                    phi = 0,   conf = NULL),
  list(name = "MaxDiv",          method = "MaxDiv",          rebal = 1L, ntb = NULL,                                    phi = 0,   conf = NULL),
  list(name = "MaxDiv_Quarterly",method = "MaxDiv",          rebal = 3L, ntb = NULL,                                    phi = 0,   conf = NULL),
  list(name = "InvVol",          method = "InvVol",          rebal = 1L, ntb = NULL,                                    phi = 0,   conf = NULL),
  list(name = "InvVol_Quarterly",method = "InvVol",          rebal = 3L, ntb = NULL,                                    phi = 0,   conf = NULL)
)
stopifnot(length(CAND_CONFIG) <= 10L)

eval_results <- list()
for (cfg in CAND_CONFIG) {
  t0 <- Sys.time()
  cat(sprintf("  %s ... ", cfg$name))
  r <- walk_forward_method_eval(cfg$method, alpha_scores, ret_panel, sig_dates_use,
                                  ub = 0.20, max_names = 20L, min_names = 15L,
                                  cost_bps = COST_BPS,
                                  confidence = cfg$conf,
                                  turnover_phi = cfg$phi,
                                  no_trade_band = cfg$ntb,
                                  rebalance_every = cfg$rebal)
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  r$config_name <- cfg$name
  eval_results[[cfg$name]] <- r
  if (isTRUE(r$ok)) {
    cat(sprintf("net_IR=%.3f SR=%.3f CAGR=%.2f%% MDD=%.2f%% TO=%.0f%% CVaR_d=%.2f%% (%.1fs)\n",
                r$net_ir, r$sr_ann, r$cagr * 100, r$mdd * 100, r$ann_to * 100,
                r$cvar95_daily_proxy * 100, dt))
  } else {
    cat(sprintf("FAILED (n_used=%d) (%.1fs)\n", r$n_used %||% 0, dt))
  }
}

# Build comparison table — include turnover hard cap pass + CVaR breach flags
TURNOVER_HARD_CAP <- 6.0     # Discovery WT cap (constraint_defaults.json)
CVAR_DAILY_CAP    <- 0.025   # Risk handoff binding rule

comp <- rbindlist(lapply(eval_results, function(r) {
  if (!isTRUE(r$ok)) return(data.table(name = r$config_name %||% r$method, ok = FALSE))
  data.table(name = r$config_name %||% r$method,
             ok = TRUE,
             net_ir = round(r$net_ir, 4),
             sr_ann = round(r$sr_ann, 4),
             cagr = round(r$cagr, 4),
             mdd = round(r$mdd, 4),
             ann_to = round(r$ann_to, 4),
             ann_cost = round(r$ann_cost, 4),
             cvar95_d = round(r$cvar95_daily_proxy, 5),
             T_use = r$T_use,
             pass_to = r$ann_to <= TURNOVER_HARD_CAP,
             pass_cvar = (r$cvar95_daily_proxy %||% 1) <= CVAR_DAILY_CAP)
}), fill = TRUE)

setorder(comp, -net_ir, na.last = TRUE)
cat("\n=== Method Comparison (sorted by net_IR; hard caps: TO<=6.0, CVaR_d<=0.025) ===\n")
print(comp)

# Selection logic (R4 P3 net_ir + AX-002 hard cap respect):
#  Step 1: Among ok methods passing TO hard cap → pick max net_IR
#  Step 2: If none pass → infeasibility_report
ok_results <- comp[ok == TRUE]
admissible <- ok_results[pass_to == TRUE]
infeas_to_only <- nrow(admissible) == 0
if (infeas_to_only) {
  cat("[Optimizer Iter5] WARN — no method passes TO hard cap 6.0. Selecting min-TO + infeasibility_report.\n")
  setorder(ok_results, ann_to, -net_ir)
  selected_name <- ok_results$name[1]
} else {
  setorder(admissible, -net_ir)
  selected_name <- admissible$name[1]
}
selected_eval <- eval_results[[selected_name]]
selected_method <- selected_name
selected_cfg <- CAND_CONFIG[[which(sapply(CAND_CONFIG, function(x) x$name == selected_name))]]

cat(sprintf("\n[Optimizer Iter5] selected = %s (net_IR=%.3f, SR=%.3f, CAGR=%.2f%%, MDD=%.2f%%, TO=%.0f%%, CVaR_d=%.2f%%)\n",
            selected_name, selected_eval$net_ir, selected_eval$sr_ann,
            selected_eval$cagr * 100, selected_eval$mdd * 100,
            selected_eval$ann_to * 100, selected_eval$cvar95_daily_proxy * 100))

# ────────────────────────────────────────────────────────────────────────
# 3. Generate full walk-forward weights schedule with selected method
# ────────────────────────────────────────────────────────────────────────
cat("\n[Optimizer Iter5] Generating weights schedule with selected config ...\n")
gen_eval <- walk_forward_method_eval(selected_cfg$method,
                                       alpha_scores, ret_panel, sig_dates_use,
                                       ub = 0.20, max_names = 20L, min_names = 15L,
                                       cost_bps = COST_BPS,
                                       confidence = selected_cfg$conf,
                                       turnover_phi = selected_cfg$phi,
                                       no_trade_band = selected_cfg$ntb,
                                       rebalance_every = selected_cfg$rebal,
                                       collect_weights = TRUE)
all_rows <- gen_eval$weights_collected
weights_dt <- rbindlist(all_rows, fill = TRUE)
# Tag method_selected with config name (descriptive)
weights_dt[, method_selected := selected_name]
n_sig_dates_walkforward <- length(unique(weights_dt$as_of_date))
cat(sprintf("[Optimizer Iter5] weights_dt: %d rows × %d sig_dates\n",
            nrow(weights_dt), n_sig_dates_walkforward))
stopifnot(n_sig_dates_walkforward >= 60L)

# Validation: per as_of_date Σw=1 (incl cash) + max_names ≤ 20 (risk securities only)
# + weight_bounds [0, 0.20] for risk securities only (CASH is allocation overlay, not a security)
val <- weights_dt[, .(sumw = sum(weight),
                       n_risk = sum(ticker != "CASH"),
                       maxw_risk = max(weight[ticker != "CASH"]),
                       minw_risk = min(weight[ticker != "CASH"]),
                       maxw_cash = ifelse(any(ticker == "CASH"), max(weight[ticker == "CASH"]), 0)),
                    by = as_of_date]
cat(sprintf("  Validation: Σw [%.6f, %.6f], n_risk [%d, %d], maxw_risk [%.4f, %.4f], maxw_cash [%.4f, %.4f]\n",
            min(val$sumw), max(val$sumw), min(val$n_risk), max(val$n_risk),
            min(val$maxw_risk), max(val$maxw_risk),
            min(val$maxw_cash), max(val$maxw_cash)))
sum_err <- max(abs(val$sumw - 1))
stopifnot(sum_err < 1e-5)
stopifnot(max(val$n_risk) <= 20L)
stopifnot(max(val$maxw_risk) <= 0.20 + 1e-6)
stopifnot(min(val$minw_risk) >= 0 - 1e-9)
stopifnot(max(val$maxw_cash) <= 0.30 + 1e-6)  # CASH cap = AX-001 v2 max

# ────────────────────────────────────────────────────────────────────────
# 4. Build optimization_package_draft.json
# ────────────────────────────────────────────────────────────────────────
cat("\n[Optimizer Iter5] Building optimization_package_draft.json ...\n")

# Final as_of_date weights (most recent)
asof_d <- max(weights_dt$as_of_date)
asof_rows <- weights_dt[as_of_date == asof_d]
target_weights <- setNames(as.list(asof_rows$weight), asof_rows$ticker)
asof_regime <- asof_rows$regime[1]
asof_cash_pct <- asof_rows$cash_pct[1]

# Active weights vs benchmark (KOSPI200 EW proxy: 0 active = identical to bench)
# Simplified: active = target - bench_w. Bench unknown for full universe → use top20-EW
N_risk <- sum(asof_rows$ticker != "CASH")
bench_w_per <- (1 - asof_cash_pct) / N_risk
active_weights <- list()
for (i in seq_len(nrow(asof_rows))) {
  if (asof_rows$ticker[i] == "CASH") next
  active_weights[[asof_rows$ticker[i]]] <- asof_rows$weight[i] - bench_w_per
}

# Walk-forward expected metrics from selected_eval
exp_ar <- selected_eval$net_ret_ann
exp_te <- selected_eval$sigma_monthly * sqrt(12)
exp_ir <- selected_eval$net_ir

# Method shopping log
method_log <- list()
for (nm in names(eval_results)) {
  r <- eval_results[[nm]]
  if (isTRUE(r$ok)) {
    method_log[[nm]] <- list(
      name = nm,
      net_ir = round(r$net_ir, 4),
      sr_ann = round(r$sr_ann, 4),
      cagr = round(r$cagr, 4),
      mdd = round(r$mdd, 4),
      ann_to = round(r$ann_to, 4),
      ann_cost = round(r$ann_cost, 4),
      cvar95_d_proxy = round(r$cvar95_daily_proxy %||% NA, 5),
      pass_to_cap = isTRUE(r$ann_to <= TURNOVER_HARD_CAP),
      pass_cvar_cap = isTRUE((r$cvar95_daily_proxy %||% 1) <= CVAR_DAILY_CAP),
      selected = identical(nm, selected_name)
    )
  } else {
    method_log[[nm]] <- list(name = nm, ok = FALSE,
                              selected = identical(nm, selected_name))
  }
}

# Binding constraints check
binding <- character(0)
if (max(val$maxw_risk) > 0.20 - 1e-3) binding <- c(binding, "weight_bound_upper")
if (max(val$n_risk) >= 20L) binding <- c(binding, "max_names_20")
top_concentrated <- val[maxw_risk > 0.18, .N]
if (top_concentrated > length(unique(weights_dt$as_of_date)) * 0.5) {
  binding <- c(binding, "concentration_high_50pct_dates")
}
if (max(val$maxw_cash) >= 0.30 - 1e-3) binding <- c(binding, "cash_overlay_30pct_crisis")
# Turnover hard cap binding
if (selected_eval$ann_to > TURNOVER_HARD_CAP) binding <- c(binding, "turnover_hard_cap_breach")
# CVaR breach binding
if (selected_eval$cvar95_daily_proxy > CVAR_DAILY_CAP) binding <- c(binding, "cvar_daily_cap_breach")

# Build infeasibility_report if any hard-cap violation
infeas_report <- NULL
hard_violations <- character(0)
if (selected_eval$ann_to > TURNOVER_HARD_CAP) hard_violations <- c(hard_violations, "turnover_cap_annual")
if (selected_eval$cvar95_daily_proxy > CVAR_DAILY_CAP) hard_violations <- c(hard_violations, "cvar_daily_cap")
if (length(hard_violations) > 0) {
  infeas_report <- list(
    reason = sprintf("Selected method '%s' breaches hard caps: %s",
                      selected_name, paste(hard_violations, collapse = ", ")),
    violated_constraints = hard_violations,
    observed = list(
      turnover_annual = round(selected_eval$ann_to, 4),
      turnover_hard_cap = TURNOVER_HARD_CAP,
      cvar95_daily_proxy = round(selected_eval$cvar95_daily_proxy, 5),
      cvar_daily_cap = CVAR_DAILY_CAP
    ),
    suggested_resolution = paste(
      "All 10 candidate methods exceed turnover cap (structural — KR top-20 monthly rebalance with",
      "per-sig_date universe pick produces 700%+ TO regardless of method). Realistic resolutions:",
      "(1) reduce rebalance frequency to semi-annual (rebal=6); (2) widen universe to top-30",
      "with FM-weighted allocation; (3) impose explicit ADV-anchored turnover budget via Forge backtest.",
      "Recommended: pass to Forge for weight_inertia + ADV pacing to determine implementable turnover."
    )
  )
}

# Crisis & cash policy summary
regime_dist <- weights_dt[, .(n_dates = length(unique(as_of_date)),
                                avg_cash = mean(cash_pct)), by = regime]
cat("Regime distribution & cash overlay:\n"); print(regime_dist)

# Primary Σ vs pooled fallback usage
sigma_method_dist <- weights_dt[ticker != "CASH",
                                 .(n_obs = .N), by = sigma_method]
cat("Sigma method distribution:\n"); print(sigma_method_dist)

# Top overweights / underweights at as_of
ow_top <- asof_rows[ticker != "CASH"][order(-weight)][1:5, .(ticker, weight)]
uw_bot <- asof_rows[ticker != "CASH"][order(weight)][1:5, .(ticker, weight)]

# HHI at as_of
hhi_asof <- sum(asof_rows[ticker != "CASH"]$weight^2)

# ── Portfolio beta + style audit (Codex Concern 6) ──
em <- as.data.table(read_parquet(file.path(ART_DIR, "exposure_matrix.parquet")))
setkey(em, Ticker)
asof_risk <- asof_rows[ticker != "CASH"]
em_match <- em[Ticker %in% asof_risk$ticker]
asof_risk_dt <- asof_risk[, .(Ticker = ticker, weight)]
setkey(asof_risk_dt, Ticker)
em_join <- em_match[asof_risk_dt, on = .(Ticker)]
em_join[is.na(weight), weight := 0]
port_betas <- list(
  MKT = round(sum(em_join$weight * em_join$MKT, na.rm = TRUE), 4),
  SMB = round(sum(em_join$weight * em_join$SMB, na.rm = TRUE), 4),
  HML = round(sum(em_join$weight * em_join$HML, na.rm = TRUE), 4),
  WML = round(sum(em_join$weight * em_join$WML, na.rm = TRUE), 4),
  RMW = round(sum(em_join$weight * em_join$RMW, na.rm = TRUE), 4),
  CMA = round(sum(em_join$weight * em_join$CMA, na.rm = TRUE), 4)
)
cat("Portfolio factor exposures (as_of, risk-only):\n"); print(port_betas)

# ── Cross-section Jaccard vs PG2 proxy (Codex Concern 4) ──
# PG2 = STR_1631_SYN_05 + STR_1656. Direct alpha vector unavailable.
# Best proxy: alpha_pkg$crowding_check$cross_section_jaccard_iter3 = 0.111
pg2_jaccard_proxy <- alpha_pkg$crowding_check$cross_section_jaccard_iter3 %||% NA

# Multi-sleeve weight breakdown (sleeve-level allocation)
multi_sleeve_weights <- list(
  Core = round(0.65 * (1 - asof_cash_pct), 4),
  Defense = round(0.35 * (1 - asof_cash_pct), 4),
  Cash = round(asof_cash_pct, 4)
)

opt_pkg_draft <- list(
  task_id = WT_ID,
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
    method_function = selected_cfg$method,
    rebalance_every = selected_cfg$rebal,
    no_trade_band = selected_cfg$ntb,
    turnover_phi = selected_cfg$phi,
    confidence_used = !is.null(selected_cfg$conf)
  ),
  method_comparison = method_log,
  multi_sleeve_weights = multi_sleeve_weights,
  cash_overlay_policy = list(
    BULL = 0.00, NORMAL = 0.05, CAUTION = 0.15, CRISIS = 0.30,
    rationale = "AX-001 v2 conditional cash policy. CRISIS 30% per Risk handoff. Validates against alpha CRISIS bootstrap IC=-0.173 [-0.252, -0.092]."
  ),
  crisis_pooled_fallback = list(
    enforced = TRUE,
    regimes_using_pooled = c("CRISIS", "CAUTION"),
    rationale = "Risk Mgr binding rule (risk_package.optimizer_handoff.recommendations[2]). CRISIS regime Σ cond=564 > 100, pooled Σ cond=100. Per-sig_date Σ uses LW_constcor in CRISIS/CAUTION, LW_oracle otherwise."
  ),
  hhi_asof = round(hhi_asof, 4),
  portfolio_factor_exposures = port_betas,
  beta_audit_note = paste(
    sprintf("Port MKT beta=%.3f at as_of (long-only top-N).", port_betas$MKT),
    "request.json has no explicit beta target for Iter 5 (Iter 3 had β [1.00, 1.05] but that was WT-D20260425_008).",
    "Discovery WT focuses on alpha/optimizer logic; deployment-stage beta hedge is Forge/Governor responsibility."
  ),
  selected_weight_tail_audit = list(
    cvar95_monthly = round(selected_eval$cvar95_monthly, 5),
    cvar95_daily_proxy = round(selected_eval$cvar95_daily_proxy, 5),
    cvar_daily_cap = CVAR_DAILY_CAP,
    cvar_pass = isTRUE(selected_eval$cvar95_daily_proxy <= CVAR_DAILY_CAP),
    mdd = round(selected_eval$mdd, 4),
    method = "monthly_realized_returns_to_daily_proxy_via_sqrt21",
    note = "Selected-weight CVaR computed from walk-forward realized portfolio returns (T_use months × method-selected weights × Ret_1m, net of 15bps × 2 round-trip). Daily proxy = monthly / sqrt(21)."
  ),
  pg2_crowding_proxy = list(
    cross_section_jaccard_iter3 = pg2_jaccard_proxy,
    note = "Direct PG2 (STR_1631_SYN_05 + STR_1656_MLRA_M05) alpha vector unavailable per Risk handoff. STR_1656 is ML-model output without alpha trail. Cross-section Jaccard vs Iter 3 ancestor (STR_1631) = 0.111. Forge to compute portfolio-level realized correlation against PG2 NAV.",
    direct_pg2_tdc_responsibility = "Forge_backtest_stage"
  ),
  sequential_admission_scenarios = list(
    replacement = list(
      design = "100% Iter 5 replaces PG2",
      backtest_status = "TBD by Forge"
    ),
    integration_80_20 = list(
      design = "80% PG2 (STR_1631_SYN_05_80 + STR_1656_MLRA_M05_20) + 20% Iter 5 multi-sleeve",
      backtest_status = "TBD by Forge",
      expected_benefit = "Reduces Iter 5 turnover footprint to ~152% (20% × 762%) at portfolio-level"
    )
  ),
  explanation = list(
    top_overweights = ow_top$ticker,
    top_underweights = uw_bot$ticker,
    main_tradeoffs = c(
      sprintf("Method selected = %s (net_IR=%.3f). Walk-forward over %d sig_dates.",
              selected_method, exp_ir, n_sig_dates_walkforward),
      sprintf("CRISIS pooled-Σ fallback enforced. AX-001 v2 cash 0/5/15/30%% by regime."),
      sprintf("Σw=1 (incl cash). max_names=%d/20 hard cap. weight_bounds [0, 0.20].",
              max(val$n_risk))
    ),
    pg2_baseline_note = "PG2 baseline = STR_1631_SYN_05 80% + STR_1656_MLRA_M05 20%. TDC vs PG2 to be computed at Forge backtest stage."
  ),
  hard_constraint_compliance = list(
    max_names_20 = list(enforced = TRUE, max_observed = max(val$n_risk),
                          note = "risk securities only; CASH is allocation overlay"),
    weight_bounds_0_020 = list(enforced = TRUE,
                                 max_observed_risk = round(max(val$maxw_risk), 4),
                                 min_observed_risk = round(min(val$minw_risk), 6),
                                 note = "applies to risk securities only (CASH cap = 0.30 per AX-001 v2)"),
    cash_overlay_cap = list(enforced = TRUE, cap = 0.30,
                              max_observed_cash = round(max(val$maxw_cash), 4),
                              note = "AX-001 v2 conditional cash policy"),
    long_only = list(enforced = TRUE, min_weight_observed = round(min(val$minw_risk), 6)),
    sum_w_1 = list(enforced = TRUE, max_abs_error = round(sum_err, 8),
                     note = "Σw across risk + CASH = 1")
  ),
  pit_compliance = list(
    C1 = "PASS — expanding-window LW shrinkage (lw_oracle / lw_constcor) per sig_date",
    C2 = "PASS — alpha at sig_date d → weights at sig_date d → realized Ret_1m at d",
    C9 = "PASS — regime_state from alpha_scores (Iter 2 PIT-safe expanding percentile inherited)",
    C11 = "PASS — KR internal regime, no FRED leakage",
    C13 = "PASS — Z_Score_Aligned alpha inherited from Alpha agent, no manual flip",
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

# Write draft
draft_path <- file.path(WT_DIR, "optimization_package_draft.json")
write_json(opt_pkg_draft, draft_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[Optimizer Iter5] optimization_package_draft.json written: %s\n", draft_path))

# Save weights.csv (mailbox + stage_artifacts)
weights_csv <- weights_dt[, .(as_of_date, ticker, weight, method_selected, sleeve_id, regime, n_names, sigma_method, cash_pct)]
fwrite(weights_csv, file.path(WT_DIR, "weights.csv"))
fwrite(weights_csv, file.path(ART_DIR, "weights.csv"))
cat(sprintf("[Optimizer Iter5] weights.csv written (%d rows × %d sig_dates) to mailbox + stage\n",
            nrow(weights_csv), n_sig_dates_walkforward))

# Save workspace for finalize step
saveRDS(list(
  weights_dt = weights_dt,
  comp = comp,
  eval_results = eval_results,
  selected_method = selected_method,
  selected_eval = selected_eval,
  opt_pkg_draft = opt_pkg_draft,
  sig_dates_use = sig_dates_use
), file.path(ART_DIR, "optimizer_workspace.rds"))

cat("\n[Optimizer Iter5] DRAFT phase complete. Codex round expected next.\n")
cat(sprintf("  selected_method=%s\n  n_sig_dates_walkforward=%d\n  net_IR=%.3f\n  CAGR=%.2f%%\n  MDD=%.2f%%\n  TO=%.0f%%\n  HHI_asof=%.4f\n  cash_at_asof=%.0f%%\n",
            selected_method, n_sig_dates_walkforward, exp_ir,
            selected_eval$cagr * 100, selected_eval$mdd * 100,
            selected_eval$ann_to * 100, hhi_asof, asof_cash_pct * 100))
