#==============================================================================
# WT-D20260425_011 — Optimizer Research (Iter 6 MEGA_06: STR_1699 + Kelly + 3-Layer Overlay)
#
# Mission:
#   - Walk-forward weights schedule (≥60 sig_dates)
#   - Method shopping ≤10 — selection objective net_ir
#   - Kelly_frac05 sizing per-name ub
#   - 3-Layer Overlay: DD Brake 6/8/20 + VolReg 12% + FM Regime cash 0/5/15/30
#   - CRISIS/CAUTION pooled-Σ fallback (Risk binding rule)
#   - Hard: max_names ≤ 20, weight_bounds [0, 0.20], long-only, Σw = 1
#
# Output:
#   - optimization_package_draft.json (mailbox)
#   - weights.csv (mailbox + stage_artifacts)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(arrow)
  library(quadprog)
})

set.seed(2026011L)

WT_ID   <- "WT-D20260425_011"
WT_DIR  <- file.path("qepm/mailbox/worktask", WT_ID)
ART_DIR <- file.path("stage_artifacts", "WT_D20260425_011")

PIT_HARD_CUTOFF <- as.Date("2023-10-31")    # Risk-side cutoff (Iter 6 tighter)
SIGNAL_AS_OF    <- as.Date("2023-11-01")    # final sig_date
COST_BPS        <- 15                        # one-way bps
TURNOVER_HARD_CAP <- 6.0
CVAR_DAILY_CAP    <- 0.025

# Iter 6 Kelly + Overlay specs (from alpha_package handoff_to_optimizer)
KELLY_FRACTION       <- 0.5
KELLY_BASE_CAP       <- 0.10
VOL_TARGET_ANN       <- 0.12
VOL_WINDOW_MONTHS    <- 12
DD_THRESHOLD_LIGHT   <- 0.06
DD_THRESHOLD_MEDIUM  <- 0.08
DD_THRESHOLD_HEAVY   <- 0.20
DD_CASH_LIGHT        <- 0.10
DD_CASH_MEDIUM       <- 0.30
DD_CASH_HEAVY        <- 0.50
FM_CASH_BULL         <- 0.00
FM_CASH_NORMAL       <- 0.05
FM_CASH_CAUTION      <- 0.15
FM_CASH_CRISIS       <- 0.30
WEIGHT_UB_DEFAULT    <- 0.20
WEIGHT_UB_CRISIS     <- 0.10  # AX-001 v2 small-sample shrink

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

.sample_cov_pairwise <- function(R) {
  R <- as.matrix(R)
  S <- stats::cov(R, use = "pairwise.complete.obs")
  S[!is.finite(S)] <- 0
  S <- 0.5 * (S + t(S))
  S
}

# Closed-form LW oracle approximating shrinkage to constant-correlation target.
lw_oracle_cov <- function(R) {
  R <- as.matrix(R)
  N <- ncol(R)
  if (N < 2) return(NULL)
  col_nna <- colSums(!is.na(R))
  keep <- col_nna >= 24
  if (sum(keep) < 5) return(NULL)
  R <- R[, keep, drop = FALSE]
  N <- ncol(R)
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
  Cor_S <- S / (s %*% t(s))
  Cor_S[!is.finite(Cor_S)] <- 0
  rbar <- (sum(Cor_S) - N) / (N * (N - 1))
  if (!is.finite(rbar)) rbar <- 0
  rbar <- pmax(pmin(rbar, 0.99), -0.99)
  Fmat <- rbar * (s %*% t(s))
  diag(Fmat) <- diag(S)
  R_demean <- sweep(R, 2, colMeans(R, na.rm = TRUE), `-`)
  R_demean[is.na(R_demean)] <- 0
  pi_hat <- 0
  for (i in seq_len(N)) {
    for (j in seq_len(N)) {
      pi_hat <- pi_hat + mean((R_demean[, i] * R_demean[, j] - S[i, j])^2)
    }
  }
  gamma_hat <- sum((Fmat - S)^2)
  if (gamma_hat <= 0) {
    delta <- 0.5
  } else {
    delta <- max(0, min(1, pi_hat / (T_eff * gamma_hat)))
  }
  Sigma_hat <- delta * Fmat + (1 - delta) * S
  Sigma_hat <- 0.5 * (Sigma_hat + t(Sigma_hat))
  eig2 <- eigen(Sigma_hat, symmetric = TRUE, only.values = TRUE)$values
  if (any(eig2 < 1e-10)) Sigma_hat <- Sigma_hat + diag(1e-8, N)
  rownames(Sigma_hat) <- colnames(Sigma_hat) <- colnames(R)
  attr(Sigma_hat, "delta") <- delta
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
  Fmat <- rbar * (s %*% t(s))
  diag(Fmat) <- diag(S)
  delta <- 0.5
  Sigma_hat <- delta * Fmat + (1 - delta) * S
  Sigma_hat <- 0.5 * (Sigma_hat + t(Sigma_hat))
  eig2 <- eigen(Sigma_hat, symmetric = TRUE, only.values = TRUE)$values
  if (any(eig2 < 1e-10)) Sigma_hat <- Sigma_hat + diag(1e-8, N)
  rownames(Sigma_hat) <- colnames(Sigma_hat) <- colnames(R)
  Sigma_hat
}

# ── MVO QP solver (long-only Σw=1, [lb, ub]) ─────────────────────────────
mvo_qp <- function(alpha, Sigma, lambda = 2.0, lb = 0, ub = 0.20,
                    confidence = NULL, w_prev = NULL, turnover_phi = 0,
                    psi = 0, ub_per_name = NULL) {
  N <- length(alpha)
  alpha_tilde <- as.numeric(alpha)
  if (!is.null(confidence)) {
    cv <- confidence[names(alpha)]
    cv[is.na(cv)] <- 0.5
    cv <- pmax(pmin(cv, 1.0), 0.0)
    alpha_tilde <- alpha_tilde * cv
  }
  Dmat <- lambda * Sigma
  if (turnover_phi > 0 && !is.null(w_prev)) {
    wp <- w_prev[names(alpha)]
    wp[is.na(wp)] <- 0
    Dmat <- Dmat + diag(2 * turnover_phi, N)
    alpha_tilde <- alpha_tilde + 2 * turnover_phi * wp
  }
  if (!is.null(confidence) && psi > 0) {
    cv <- confidence[names(alpha)]
    cv[is.na(cv)] <- 0.5
    Dmat <- Dmat + diag(2 * psi * (1 - cv)^2, N)
  }
  diag(Dmat) <- diag(Dmat) + 1e-8
  dvec <- alpha_tilde
  # Per-name ub: vector if provided, else scalar
  if (is.null(ub_per_name)) {
    ub_vec <- rep(ub, N)
  } else {
    ub_vec <- pmin(ub_per_name[names(alpha)], ub)
    ub_vec[!is.finite(ub_vec)] <- ub
  }
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(1, rep(lb, N), -ub_vec)
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

# ── HRP weight ────────────────────────────────────────────────────────────
hrp_qd <- function(Sigma) {
  N <- nrow(Sigma)
  if (N == 1) return(1)
  s <- sqrt(diag(Sigma))
  if (any(s < 1e-12)) s[s < 1e-12] <- 1e-6
  Cor <- Sigma / (s %*% t(s))
  Cor[!is.finite(Cor)] <- 0
  d <- sqrt(pmax(0.5 * (1 - Cor), 0))
  hc <- tryCatch(stats::hclust(stats::as.dist(d), method = "single"),
                  error = function(e) NULL)
  if (is.null(hc)) {
    iv <- 1 / pmax(diag(Sigma), 1e-12)
    return(as.numeric(iv / sum(iv)))
  }
  order_idx <- hc$order
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

maxdiv_qd <- function(Sigma, lb = 0, ub = 0.20) {
  N <- nrow(Sigma)
  s <- sqrt(diag(Sigma))
  Dmat <- Sigma + diag(1e-8, N)
  dvec <- rep(0, N)
  Amat <- cbind(s, diag(N), -diag(N))
  bvec <- c(1, rep(lb * 0, N), rep(-ub * 5, N))
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

# ── 3-Layer Overlay components ────────────────────────────────────────────
# DD cash from BM rolling DD (PIT-safe t-1 lag)
dd_brake_cash <- function(dd_lag) {
  if (!is.finite(dd_lag) || dd_lag <= DD_THRESHOLD_LIGHT) return(0)
  if (dd_lag <= DD_THRESHOLD_MEDIUM) return(DD_CASH_LIGHT)
  if (dd_lag <= DD_THRESHOLD_HEAVY) return(DD_CASH_MEDIUM)
  return(DD_CASH_HEAVY)
}

# VolReg scale: scale = min(1.0, vol_target / max(vol_lag, eps))
volreg_scale <- function(vol_lag) {
  if (!is.finite(vol_lag) || vol_lag <= 1e-6) return(1.0)
  s <- VOL_TARGET_ANN / vol_lag
  pmin(1.0, pmax(0, s))
}

# FM Regime cash
fm_regime_cash <- function(regime) {
  switch(as.character(regime),
    "BULL"    = FM_CASH_BULL,
    "NORMAL"  = FM_CASH_NORMAL,
    "CAUTION" = FM_CASH_CAUTION,
    "CRISIS"  = FM_CASH_CRISIS,
    FM_CASH_NORMAL
  )
}

# Combine the 3 layers: max(DD, FM) cash + VolReg scaling on the risk-asset side
# returns list(cash_pct, dd_cash, fm_cash, vol_scale, layer_audit)
overlay_combine <- function(dd_lag, vol_lag, regime) {
  dd_c <- dd_brake_cash(dd_lag)
  fm_c <- fm_regime_cash(regime)
  base_cash <- pmax(dd_c, fm_c)
  vs <- volreg_scale(vol_lag)
  # After base_cash, risk side is (1 - base_cash). VolReg scales that down by vs.
  # Additional cash from VolReg = (1 - base_cash) * (1 - vs)
  total_cash <- base_cash + (1 - base_cash) * (1 - vs)
  # Cap at 0.95 (safety; full cash 100% would break sleeve weight)
  total_cash <- pmin(total_cash, 0.95)
  list(cash_pct = total_cash,
        dd_cash = dd_c,
        fm_cash = fm_c,
        vol_scale = vs,
        base_cash = base_cash,
        binding_layer = if (total_cash <= 1e-9) "none"
                          else if (dd_c >= fm_c && dd_c > 0) {
                            if ((1 - base_cash) * (1 - vs) > base_cash * 0.2) "DD+VolReg"
                            else "DD"
                          } else if (fm_c > 0) {
                            if ((1 - base_cash) * (1 - vs) > base_cash * 0.2) "FM+VolReg"
                            else "FM"
                          } else "VolReg")
}

# ── Per-sig_date weight computation ─────────────────────────────────────
# Returns: data.table(as_of_date, ticker, weight, method_selected, sleeve_id, regime, n_names, sigma_method, cash_pct,
#                     dd_cash, fm_cash, vol_scale, dd_lag, vol_lag)
compute_weights_at_date <- function(sig_date, alpha_scores, ret_panel, bm_overlay,
                                     method = "MVO_lam2",
                                     ub = WEIGHT_UB_DEFAULT,
                                     max_names = 20L,
                                     min_names = 15L,
                                     pooled_fallback_regimes = c("CRISIS", "CAUTION"),
                                     w_prev_risk = NULL,
                                     confidence = NULL,
                                     turnover_phi = 0,
                                     kelly_apply = TRUE) {

  panel_t <- alpha_scores[Date == sig_date & !is.na(score_eff)]
  if (nrow(panel_t) == 0) return(NULL)
  regime <- panel_t$regime_state[1]

  setorder(panel_t, -score_eff)
  N_eligible <- nrow(panel_t)
  N_target <- min(max_names, N_eligible)
  if (N_target < min_names && N_eligible >= min_names) {
    N_target <- min_names
  }
  if (N_target < 5L) return(NULL)
  picks <- panel_t[1:N_target]
  tickers_t <- picks$Ticker
  alpha_t   <- picks$score_eff
  names(alpha_t) <- tickers_t

  # Σ estimation
  hist_panel <- ret_panel[Date < sig_date & Ticker %in% tickers_t]
  if (nrow(hist_panel) == 0) return(NULL)
  ret_wide <- dcast(hist_panel, Date ~ Ticker, value.var = "Ret_1m")
  ret_mat <- as.matrix(ret_wide[, !"Date", with = FALSE])
  ticker_avail <- intersect(tickers_t, colnames(ret_mat))
  if (length(ticker_avail) < 5L) return(NULL)
  ret_mat <- ret_mat[, ticker_avail, drop = FALSE]
  alpha_t <- alpha_t[ticker_avail]
  tickers_t <- ticker_avail
  col_nna <- colSums(!is.na(ret_mat))
  keep_tickers <- names(col_nna)[col_nna >= 24]
  if (length(keep_tickers) < 5) return(NULL)
  ret_mat <- ret_mat[, keep_tickers, drop = FALSE]
  alpha_t <- alpha_t[keep_tickers]
  tickers_t <- keep_tickers

  if (nrow(ret_mat) < 24L) {
    Sigma_t <- diag(rep(0.005, length(tickers_t)))
    rownames(Sigma_t) <- colnames(Sigma_t) <- tickers_t
    sigma_method <- "diag_fallback_short_hist"
  } else {
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
  sigma_tickers <- intersect(tickers_t, colnames(Sigma_t))
  if (length(sigma_tickers) < 5) return(NULL)
  Sigma_t  <- Sigma_t[sigma_tickers, sigma_tickers, drop = FALSE]
  alpha_t  <- alpha_t[sigma_tickers]
  tickers_t <- sigma_tickers

  # CRISIS small-sample shrink: per-name ub 0.10
  ub_use <- if (regime == "CRISIS") min(ub, WEIGHT_UB_CRISIS) else ub

  # ── Kelly fractional per-name ub (Iter 6 NEW) ─────────────────────────
  # f* ∝ alpha / sigma^2 (one-period Kelly proxy). frac = 0.5.
  # Scale to make average ub_kelly = ub_use (so ranking dominates when alphas equal).
  ub_kelly_vec <- NULL
  if (kelly_apply) {
    sigma_diag <- pmax(diag(Sigma_t), 1e-6)
    a_pos <- pmax(alpha_t, 0)
    if (sum(a_pos) > 0) {
      kelly_raw <- (a_pos / sigma_diag) * KELLY_FRACTION
      # Scale: target average kelly_ub equal to ub_use × (avg kelly_raw / max kelly_raw)
      # Simpler: cap at min(ub_use, KELLY_BASE_CAP)
      # Then scale so max(kelly_ub) = min(ub_use, KELLY_BASE_CAP) and floor at 0.02
      max_kelly <- max(kelly_raw)
      if (max_kelly > 0) {
        ub_kelly_vec <- kelly_raw / max_kelly * min(ub_use, KELLY_BASE_CAP)
        ub_kelly_vec <- pmax(ub_kelly_vec, 0.02)  # floor 2% per name
        ub_kelly_vec <- pmin(ub_kelly_vec, ub_use)
        names(ub_kelly_vec) <- tickers_t
      }
    }
  }

  N <- length(tickers_t)
  names(alpha_t) <- tickers_t
  w <- switch(method,
    "MVO_lam2"        = mvo_qp(alpha_t, Sigma_t, lambda = 2.0, lb = 0, ub = ub_use,
                                 ub_per_name = ub_kelly_vec),
    "MVO_lam5"        = mvo_qp(alpha_t, Sigma_t, lambda = 5.0, lb = 0, ub = ub_use,
                                 ub_per_name = ub_kelly_vec),
    "MVO_conf_TP"     = mvo_qp(alpha_t, Sigma_t, lambda = 2.0, lb = 0, ub = ub_use,
                                  confidence = confidence, w_prev = w_prev_risk,
                                  turnover_phi = turnover_phi, psi = 0.3,
                                  ub_per_name = ub_kelly_vec),
    "MVO_TP_high"     = mvo_qp(alpha_t, Sigma_t, lambda = 2.0, lb = 0, ub = ub_use,
                                  w_prev = w_prev_risk, turnover_phi = 5.0,
                                  ub_per_name = ub_kelly_vec),
    "HRP"             = hrp_qd(Sigma_t),
    "ERC"             = erc_qd(Sigma_t),
    "MaxDiv"          = maxdiv_qd(Sigma_t, ub = ub_use),
    "EqualWeight"     = rep(1 / N, N),
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

  # Cap per-name (post-method) — Kelly cap already enforced inside MVO_qp
  if (!is.null(ub_kelly_vec) && method %in% c("HRP","ERC","MaxDiv","InvVol","EqualWeight")) {
    # Apply Kelly cap projection for non-MVO methods
    cap_vec <- ub_kelly_vec[names(w)]
    over <- w > cap_vec
    if (any(over)) {
      excess <- sum(w[over] - cap_vec[over])
      w[over] <- cap_vec[over]
      free <- which(!over)
      if (length(free) > 0 && sum(w[free]) > 0) {
        w[free] <- w[free] + excess * (w[free] / sum(w[free]))
      }
    }
  }
  w <- normalize_long_only(w, lb = 0, ub = ub_use, target_sum = 1)

  # ── Apply 3-Layer Overlay (Iter 6 NEW) ───────────────────────────────
  ymd <- format(sig_date, "%Y-%m-01")
  bm_row <- bm_overlay[Date_M == ymd]
  if (nrow(bm_row) > 0) {
    dd_lag <- bm_row$dd_lag[1]
    vol_lag <- bm_row$vol_lag[1]
  } else {
    dd_lag <- 0; vol_lag <- VOL_TARGET_ANN  # neutral
  }
  ov <- overlay_combine(dd_lag, vol_lag, regime)
  cash_pct <- ov$cash_pct

  w_risk <- w * (1 - cash_pct)

  rows <- data.table(
    as_of_date = sig_date,
    ticker = c(names(w_risk), if (cash_pct > 1e-9) "CASH" else character(0)),
    weight = c(as.numeric(w_risk), if (cash_pct > 1e-9) cash_pct else numeric(0)),
    method_selected = method,
    sleeve_id = c(rep("multi_sleeve_blend", length(w_risk)),
                  if (cash_pct > 1e-9) "cash_overlay" else character(0)),
    regime = regime,
    n_names = N,
    sigma_method = sigma_method,
    cash_pct = cash_pct,
    dd_cash = ov$dd_cash,
    fm_cash = ov$fm_cash,
    vol_scale = ov$vol_scale,
    binding_layer = ov$binding_layer,
    dd_lag = dd_lag,
    vol_lag = vol_lag
  )
  rows
}

# ── Walk-forward method evaluator ────────────────────────────────────────
walk_forward_method_eval <- function(method_name, alpha_scores, ret_panel, bm_overlay,
                                      sig_dates, ub = WEIGHT_UB_DEFAULT,
                                      max_names = 20L, min_names = 15L,
                                      cost_bps = 15,
                                      confidence = NULL, turnover_phi = 0,
                                      rebalance_every = 1L,
                                      collect_weights = FALSE,
                                      force_rebal_on_regime_change = TRUE,
                                      force_rebal_at_dates = NULL,
                                      kelly_apply = TRUE) {
  W_prev <- NULL
  port_ret <- numeric(length(sig_dates))
  port_to  <- numeric(length(sig_dates))
  port_cost <- numeric(length(sig_dates))
  cash_pct_seq <- numeric(length(sig_dates))
  weights_collected <- list()
  n_used <- 0L
  last_res <- NULL
  prev_regime <- NULL

  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    do_rebalance <- (i == 1L) || ((i - 1L) %% rebalance_every == 0L)
    if (!is.null(force_rebal_at_dates) && d %in% force_rebal_at_dates) {
      do_rebalance <- TRUE
    }
    if (force_rebal_on_regime_change && !is.null(prev_regime)) {
      panel_t <- alpha_scores[Date == d & !is.na(score_eff)]
      if (nrow(panel_t) > 0) {
        cur_regime <- panel_t$regime_state[1]
        cur_in_pool <- cur_regime %in% c("CRISIS", "CAUTION")
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
        compute_weights_at_date(d, alpha_scores, ret_panel, bm_overlay,
                                 method = method_name, ub = ub,
                                 max_names = max_names, min_names = min_names,
                                 w_prev_risk = w_prev_risk_named,
                                 confidence = confidence,
                                 turnover_phi = turnover_phi,
                                 kelly_apply = kelly_apply),
        error = function(e) NULL
      )
      if (is.null(res) || any(is.na(res$weight))) next
      last_res <- res
    } else {
      panel_t <- alpha_scores[Date == d & !is.na(score_eff)]
      if (nrow(panel_t) == 0 || is.null(last_res)) next
      regime <- panel_t$regime_state[1]
      # Recompute overlay at this date with t-1 BM lag (since DD/Vol changes monthly)
      ymd <- format(d, "%Y-%m-01")
      bm_row <- bm_overlay[Date_M == ymd]
      dd_lag <- if (nrow(bm_row) > 0) bm_row$dd_lag[1] else 0
      vol_lag <- if (nrow(bm_row) > 0) bm_row$vol_lag[1] else VOL_TARGET_ANN
      ov <- overlay_combine(dd_lag, vol_lag, regime)
      cash_pct_t <- ov$cash_pct
      eligible_t <- panel_t$Ticker

      held_risk <- last_res[ticker != "CASH"]
      keep_names <- intersect(held_risk$ticker, eligible_t)
      drop_names <- setdiff(held_risk$ticker, eligible_t)

      if (length(keep_names) < 5) {
        w_prev_risk_named <- setNames(held_risk$weight, held_risk$ticker)
        res <- tryCatch(
          compute_weights_at_date(d, alpha_scores, ret_panel, bm_overlay,
                                   method = method_name, ub = ub,
                                   max_names = max_names, min_names = min_names,
                                   w_prev_risk = w_prev_risk_named,
                                   confidence = confidence,
                                   turnover_phi = turnover_phi,
                                   kelly_apply = kelly_apply),
          error = function(e) NULL
        )
        if (is.null(res) || any(is.na(res$weight))) next
        last_res <- res
      } else {
        kept_dt <- held_risk[ticker %in% keep_names]
        dropped_w <- sum(held_risk[ticker %in% drop_names]$weight)
        kept_w_sum <- sum(kept_dt$weight)
        if (kept_w_sum > 0) {
          kept_dt$weight <- kept_dt$weight + dropped_w * (kept_dt$weight / kept_w_sum)
        }
        kept_w <- kept_dt$weight / sum(kept_dt$weight)
        kept_w <- normalize_long_only(kept_w, lb = 0, ub = ub, target_sum = 1)
        kept_dt$weight <- kept_w * (1 - cash_pct_t)
        res <- rbindlist(list(
          data.table(as_of_date = d, ticker = kept_dt$ticker, weight = kept_dt$weight,
                      method_selected = last_res$method_selected[1],
                      sleeve_id = "multi_sleeve_blend",
                      regime = regime,
                      n_names = length(keep_names),
                      sigma_method = paste0("held_", last_res$sigma_method[1]),
                      cash_pct = cash_pct_t,
                      dd_cash = ov$dd_cash, fm_cash = ov$fm_cash,
                      vol_scale = ov$vol_scale, binding_layer = ov$binding_layer,
                      dd_lag = dd_lag, vol_lag = vol_lag),
          if (cash_pct_t > 1e-9) data.table(as_of_date = d, ticker = "CASH",
                                              weight = cash_pct_t,
                                              method_selected = last_res$method_selected[1],
                                              sleeve_id = "cash_overlay",
                                              regime = regime,
                                              n_names = length(keep_names),
                                              sigma_method = paste0("held_", last_res$sigma_method[1]),
                                              cash_pct = cash_pct_t,
                                              dd_cash = ov$dd_cash, fm_cash = ov$fm_cash,
                                              vol_scale = ov$vol_scale, binding_layer = ov$binding_layer,
                                              dd_lag = dd_lag, vol_lag = vol_lag) else NULL
        ))
        last_res <- res
      }
    }
    n_used <- n_used + 1L
    if (collect_weights) weights_collected[[length(weights_collected) + 1L]] <- res

    risk_rows_eval <- res[ticker != "CASH"]
    rd <- alpha_scores[Date == d, .(Ticker, Ret_1m)]
    setkey(rd, Ticker)
    risk_rows_eval <- rd[risk_rows_eval, on = .(Ticker = ticker)]
    risk_rows_eval[is.na(Ret_1m), Ret_1m := 0]
    realized_risk <- sum(risk_rows_eval$weight * risk_rows_eval$Ret_1m, na.rm = TRUE)
    cash_pct_t <- res$cash_pct[1] %||% 0
    realized_t <- realized_risk

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
    W_prev <- res[, .(ticker, weight)]
    prev_regime <- res$regime[1]
  }
  used <- which(port_ret != 0 | port_to != 0)
  if (length(used) < 12) {
    return(list(method = method_name, n_used = n_used, ok = FALSE))
  }
  pr <- port_ret[used]
  pt <- port_to[used]
  pc <- port_cost[used]
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
  q05 <- stats::quantile(pr, 0.05, na.rm = TRUE)
  cvar95_m <- -mean(pr[pr <= q05], na.rm = TRUE)
  cvar95_d_proxy <- cvar95_m / sqrt(21)
  list(method = method_name, n_used = n_used, ok = TRUE,
       net_ir = net_ir, sr_ann = sr_ann, cagr = cagr, mdd = mdd,
       ann_to = ann_to, ann_cost = ann_cost, T_use = T_use,
       mu_monthly = mu, sigma_monthly = sigma, net_ret_ann = net_ret_ann,
       cvar95_monthly = cvar95_m, cvar95_daily_proxy = cvar95_d_proxy,
       port_returns_monthly = pr, port_to = pt,
       weights_collected = if (collect_weights) weights_collected else NULL)
}

# ────────────────────────────────────────────────────────────────────────
# 1. Load inputs
# ────────────────────────────────────────────────────────────────────────
cat("[Optimizer Iter6] Loading inputs...\n")
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = TRUE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = TRUE)
req_pkg   <- fromJSON(file.path(WT_DIR, "request.json"),       simplifyVector = TRUE)

alpha_scores <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
setkey(alpha_scores, Date, Ticker)

ret_panel <- alpha_scores[, .(Date, Ticker, Ret_1m)][!is.na(Ret_1m)]
setkey(ret_panel, Date, Ticker)

Sigma_dt        <- as.data.table(read_parquet(file.path(ART_DIR, "covariance.parquet")))
Sigma_pooled_dt <- as.data.table(read_parquet(file.path(ART_DIR, "covariance_pooled_fallback.parquet")))
SIG_TICKERS <- as.character(Sigma_dt$Ticker)
Sigma_asof  <- as.matrix(Sigma_dt[, !"Ticker", with = FALSE])
rownames(Sigma_asof) <- colnames(Sigma_asof) <- SIG_TICKERS
Sigma_pooled_asof <- as.matrix(Sigma_pooled_dt[, !"Ticker", with = FALSE])
rownames(Sigma_pooled_asof) <- colnames(Sigma_pooled_asof) <- SIG_TICKERS

# ── Build BM Overlay (DD + Vol with t-1 lag) ─────────────────────────────
cat("[Optimizer Iter6] Building BM overlay (DD + Vol with t-1 lag)...\n")
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm <- bm[Date <= PIT_HARD_CUTOFF]
setorder(bm, Date)
# Daily BM cumret
bm[, cumret := cumprod(1 + ifelse(is.na(BM_Ret), 0, BM_Ret))]
# Monthly aggregation: month-end values
bm[, ym := format(Date, "%Y-%m")]
bm_m <- bm[, .(Date_M = max(Date), cumret_m = cumret[.N], BM_Close_m = BM_Close[.N]), by = ym]
setorder(bm_m, Date_M)
bm_m[, Date_M := as.Date(format(Date_M, "%Y-%m-01"))]
# 12M rolling DD: peak over trailing 12 months / current - 1 (negative -> drawdown)
bm_m[, peak_12m := frollapply(cumret_m, n = 12, FUN = max, align = "right", fill = NA)]
bm_m[, dd_12m := pmax(0, 1 - cumret_m / peak_12m)]
# 12M monthly returns + annualized vol
bm_m[, ret_m := c(NA, diff(log(cumret_m)))]
bm_m[, vol_12m_ann := frollapply(ret_m, n = 12, FUN = function(x) stats::sd(x, na.rm = TRUE), align = "right", fill = NA) * sqrt(12)]
# t-1 lag (PIT-safe)
bm_m[, dd_lag := shift(dd_12m, n = 1L)]
bm_m[, vol_lag := shift(vol_12m_ann, n = 1L)]
bm_overlay <- bm_m[, .(Date_M = as.character(Date_M), dd_lag, vol_lag)]
bm_overlay[is.na(dd_lag), dd_lag := 0]
bm_overlay[is.na(vol_lag), vol_lag := VOL_TARGET_ANN]

cat(sprintf("[Optimizer Iter6] alpha panel: %d sig_dates × %d tickers\n",
            length(unique(alpha_scores$Date)), length(unique(alpha_scores$Ticker))))
cat(sprintf("[Optimizer Iter6] Risk Σ as_of: %dx%d (cond %.2f), pooled: %dx%d (cond %.0f)\n",
            nrow(Sigma_asof), ncol(Sigma_asof), kappa(Sigma_asof, exact = TRUE),
            nrow(Sigma_pooled_asof), ncol(Sigma_pooled_asof), kappa(Sigma_pooled_asof, exact = TRUE)))
cat(sprintf("[Optimizer Iter6] BM overlay rows: %d (date_range %s ~ %s, dd_lag mean=%.3f vol_lag mean=%.3f)\n",
            nrow(bm_overlay), min(bm_overlay$Date_M), max(bm_overlay$Date_M),
            mean(bm_overlay$dd_lag, na.rm = TRUE), mean(bm_overlay$vol_lag, na.rm = TRUE)))

all_sig <- sort(unique(alpha_scores$Date))
min_hist_start <- as.Date("2006-01-01")
sig_dates_use <- all_sig[all_sig >= min_hist_start & all_sig <= SIGNAL_AS_OF]
cat(sprintf("[Optimizer Iter6] sig_dates_use: %d (%s ~ %s)\n",
            length(sig_dates_use), as.character(min(sig_dates_use)),
            as.character(max(sig_dates_use))))

# ────────────────────────────────────────────────────────────────────────
# 2. Method shopping (10 candidates, walk-forward, Kelly+Overlay enabled)
# ────────────────────────────────────────────────────────────────────────
cat("\n[Optimizer Iter6] Method shopping (walk-forward, 10 candidates) ...\n")

conf_vec_all <- unlist(alpha_pkg$confidence_vector)

CAND_CONFIG <- list(
  list(name = "MVO_lam2_KO",                method = "MVO_lam2",        rebal = 1L, phi = 0,    conf = NULL),
  list(name = "MVO_conf_TP_KO",             method = "MVO_conf_TP",     rebal = 1L, phi = 2.0,  conf = conf_vec_all),
  list(name = "MVO_conf_TP_Quarterly_KO",   method = "MVO_conf_TP",     rebal = 3L, phi = 2.0,  conf = conf_vec_all),
  list(name = "MVO_TP_high_KO",             method = "MVO_TP_high",     rebal = 1L, phi = 5.0,  conf = NULL),
  list(name = "HRP_KO",                     method = "HRP",             rebal = 1L, phi = 0,    conf = NULL),
  list(name = "HRP_Quarterly_KO",           method = "HRP",             rebal = 3L, phi = 0,    conf = NULL),
  list(name = "ERC_KO",                     method = "ERC",             rebal = 1L, phi = 0,    conf = NULL),
  list(name = "MaxDiv_Quarterly_KO",        method = "MaxDiv",          rebal = 3L, phi = 0,    conf = NULL),
  list(name = "InvVol_KO",                  method = "InvVol",          rebal = 1L, phi = 0,    conf = NULL),
  list(name = "InvVol_Quarterly_KO",        method = "InvVol",          rebal = 3L, phi = 0,    conf = NULL)
)
stopifnot(length(CAND_CONFIG) <= 10L)

eval_results <- list()
for (cfg in CAND_CONFIG) {
  t0 <- Sys.time()
  cat(sprintf("  %s ... ", cfg$name))
  r <- walk_forward_method_eval(cfg$method, alpha_scores, ret_panel, bm_overlay,
                                  sig_dates_use, ub = WEIGHT_UB_DEFAULT,
                                  max_names = 20L, min_names = 15L,
                                  cost_bps = COST_BPS,
                                  confidence = cfg$conf,
                                  turnover_phi = cfg$phi,
                                  rebalance_every = cfg$rebal,
                                  force_rebal_on_regime_change = TRUE,
                                  force_rebal_at_dates = c(SIGNAL_AS_OF),
                                  kelly_apply = TRUE)
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

ok_results <- comp[ok == TRUE]
admissible <- ok_results[pass_to == TRUE]
infeas_to_only <- nrow(admissible) == 0
if (infeas_to_only) {
  cat("[Optimizer Iter6] WARN — no method passes TO hard cap. Selecting min-TO + report.\n")
  setorder(ok_results, ann_to, -net_ir)
  selected_name <- ok_results$name[1]
} else {
  setorder(admissible, -net_ir)
  selected_name <- admissible$name[1]
}
selected_eval <- eval_results[[selected_name]]
selected_method <- selected_name
selected_cfg <- CAND_CONFIG[[which(sapply(CAND_CONFIG, function(x) x$name == selected_name))]]

cat(sprintf("\n[Optimizer Iter6] selected = %s (net_IR=%.3f, SR=%.3f, CAGR=%.2f%%, MDD=%.2f%%, TO=%.0f%%, CVaR_d=%.2f%%)\n",
            selected_name, selected_eval$net_ir, selected_eval$sr_ann,
            selected_eval$cagr * 100, selected_eval$mdd * 100,
            selected_eval$ann_to * 100, selected_eval$cvar95_daily_proxy * 100))

# ────────────────────────────────────────────────────────────────────────
# 3. Generate full walk-forward weights with selected config
# ────────────────────────────────────────────────────────────────────────
cat("\n[Optimizer Iter6] Generating weights schedule with selected config ...\n")
gen_eval <- walk_forward_method_eval(selected_cfg$method,
                                       alpha_scores, ret_panel, bm_overlay,
                                       sig_dates_use, ub = WEIGHT_UB_DEFAULT,
                                       max_names = 20L, min_names = 15L,
                                       cost_bps = COST_BPS,
                                       confidence = selected_cfg$conf,
                                       turnover_phi = selected_cfg$phi,
                                       rebalance_every = selected_cfg$rebal,
                                       collect_weights = TRUE,
                                       force_rebal_on_regime_change = TRUE,
                                       force_rebal_at_dates = c(SIGNAL_AS_OF),
                                       kelly_apply = TRUE)
weights_dt <- rbindlist(gen_eval$weights_collected, fill = TRUE)

# As-of replacement: align with Risk's covariance.parquet 20-ticker artifact
cat("[Optimizer Iter6] Aligning as_of weights with Risk covariance artifact ...\n")
asof_panel <- alpha_scores[Date == SIGNAL_AS_OF & !is.na(score_eff)]
asof_regime <- asof_panel$regime_state[1]
asof_eligible <- intersect(asof_panel$Ticker, SIG_TICKERS)
cat(sprintf("  as_of regime=%s, Risk 20 tickers, eligible from alpha=%d, intersection=%d\n",
            asof_regime, length(SIG_TICKERS), length(asof_eligible)))

asof_use_pooled <- asof_regime %in% c("CRISIS", "CAUTION")
asof_Sigma <- if (asof_use_pooled) Sigma_pooled_asof else Sigma_asof
asof_sigma_method <- if (asof_use_pooled) "lw_constcor_pooled_fallback_risk_artifact" else "lw_oracle_risk_artifact"
asof_ub <- if (asof_regime == "CRISIS") WEIGHT_UB_CRISIS else WEIGHT_UB_DEFAULT

# Kelly per-name ub on Risk artifact 20 tickers
asof_alpha <- setNames(unlist(alpha_pkg$alpha_vector)[SIG_TICKERS], SIG_TICKERS)
asof_alpha[is.na(asof_alpha)] <- 0
sigma_diag <- pmax(diag(asof_Sigma), 1e-6)
a_pos <- pmax(asof_alpha, 0)
ub_kelly_asof <- NULL
if (sum(a_pos) > 0) {
  kelly_raw <- (a_pos / sigma_diag) * KELLY_FRACTION
  if (max(kelly_raw) > 0) {
    ub_kelly_asof <- kelly_raw / max(kelly_raw) * min(asof_ub, KELLY_BASE_CAP)
    ub_kelly_asof <- pmax(ub_kelly_asof, 0.02)
    ub_kelly_asof <- pmin(ub_kelly_asof, asof_ub)
    names(ub_kelly_asof) <- SIG_TICKERS
  }
}

asof_w <- switch(selected_cfg$method,
  "HRP"     = hrp_qd(asof_Sigma),
  "MaxDiv"  = maxdiv_qd(asof_Sigma, ub = asof_ub),
  "ERC"     = erc_qd(asof_Sigma),
  "InvVol"  = { iv <- 1 / sqrt(diag(asof_Sigma)); iv / sum(iv) },
  "MVO_lam2"     = mvo_qp(asof_alpha, asof_Sigma, lambda = 2.0, lb = 0, ub = asof_ub,
                            ub_per_name = ub_kelly_asof),
  "MVO_conf_TP"  = mvo_qp(asof_alpha, asof_Sigma, lambda = 2.0, lb = 0, ub = asof_ub,
                            confidence = setNames(unlist(alpha_pkg$confidence_vector)[SIG_TICKERS], SIG_TICKERS),
                            turnover_phi = 2.0, psi = 0.3, ub_per_name = ub_kelly_asof),
  "MVO_TP_high"  = mvo_qp(asof_alpha, asof_Sigma, lambda = 2.0, lb = 0, ub = asof_ub,
                            turnover_phi = 5.0, ub_per_name = ub_kelly_asof),
  rep(1 / length(SIG_TICKERS), length(SIG_TICKERS))
)
names(asof_w) <- SIG_TICKERS

# Apply Kelly cap projection for non-MVO
if (!is.null(ub_kelly_asof) && selected_cfg$method %in% c("HRP","ERC","MaxDiv","InvVol","EqualWeight")) {
  cap_vec <- ub_kelly_asof[names(asof_w)]
  over <- asof_w > cap_vec
  if (any(over)) {
    excess <- sum(asof_w[over] - cap_vec[over])
    asof_w[over] <- cap_vec[over]
    free <- which(!over)
    if (length(free) > 0 && sum(asof_w[free]) > 0) {
      asof_w[free] <- asof_w[free] + excess * (asof_w[free] / sum(asof_w[free]))
    }
  }
}
asof_w <- normalize_long_only(asof_w, lb = 0, ub = asof_ub, target_sum = 1)
names(asof_w) <- SIG_TICKERS

# Apply 3-Layer Overlay at as_of
ymd_asof <- format(SIGNAL_AS_OF, "%Y-%m-01")
bm_row_asof <- bm_overlay[Date_M == ymd_asof]
asof_dd_lag <- if (nrow(bm_row_asof) > 0) bm_row_asof$dd_lag[1] else 0
asof_vol_lag <- if (nrow(bm_row_asof) > 0) bm_row_asof$vol_lag[1] else VOL_TARGET_ANN
ov_asof <- overlay_combine(asof_dd_lag, asof_vol_lag, asof_regime)
asof_cash <- ov_asof$cash_pct
asof_w_risk <- asof_w * (1 - asof_cash)

cat(sprintf("  as_of overlay: dd_lag=%.4f vol_lag=%.4f → dd_cash=%.0f%% fm_cash=%.0f%% vol_scale=%.3f → final_cash=%.1f%% (binding=%s)\n",
            asof_dd_lag, asof_vol_lag, ov_asof$dd_cash * 100, ov_asof$fm_cash * 100,
            ov_asof$vol_scale, asof_cash * 100, ov_asof$binding_layer))

# Replace as_of rows
weights_dt <- weights_dt[as_of_date != SIGNAL_AS_OF]
asof_rows_new <- rbindlist(list(
  data.table(as_of_date = SIGNAL_AS_OF, ticker = SIG_TICKERS, weight = as.numeric(asof_w_risk),
              method_selected = selected_name, sleeve_id = "multi_sleeve_blend",
              regime = asof_regime, n_names = length(SIG_TICKERS),
              sigma_method = asof_sigma_method, cash_pct = asof_cash,
              dd_cash = ov_asof$dd_cash, fm_cash = ov_asof$fm_cash,
              vol_scale = ov_asof$vol_scale, binding_layer = ov_asof$binding_layer,
              dd_lag = asof_dd_lag, vol_lag = asof_vol_lag),
  if (asof_cash > 1e-9) data.table(as_of_date = SIGNAL_AS_OF, ticker = "CASH", weight = asof_cash,
                                      method_selected = selected_name, sleeve_id = "cash_overlay",
                                      regime = asof_regime, n_names = length(SIG_TICKERS),
                                      sigma_method = asof_sigma_method, cash_pct = asof_cash,
                                      dd_cash = ov_asof$dd_cash, fm_cash = ov_asof$fm_cash,
                                      vol_scale = ov_asof$vol_scale, binding_layer = ov_asof$binding_layer,
                                      dd_lag = asof_dd_lag, vol_lag = asof_vol_lag) else NULL
))
weights_dt <- rbindlist(list(weights_dt, asof_rows_new), fill = TRUE)
setorder(weights_dt, as_of_date, -weight)
weights_dt[, method_selected := selected_name]

n_sig_dates_walkforward <- length(unique(weights_dt$as_of_date))
cat(sprintf("[Optimizer Iter6] weights_dt: %d rows × %d sig_dates\n",
            nrow(weights_dt), n_sig_dates_walkforward))
stopifnot(n_sig_dates_walkforward >= 60L)

# Validation
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
stopifnot(max(val$maxw_cash) <= 0.95 + 1e-6)  # Iter 6 overlay can stack to ≤95%

# ────────────────────────────────────────────────────────────────────────
# 4. Regime-specific weight schedules (4 schedule for BULL/NORMAL/CAUTION/CRISIS)
# ────────────────────────────────────────────────────────────────────────
regime_dist <- weights_dt[, .(n_dates = length(unique(as_of_date)),
                                avg_cash = mean(cash_pct),
                                avg_dd_cash = mean(dd_cash, na.rm = TRUE),
                                avg_fm_cash = mean(fm_cash, na.rm = TRUE),
                                avg_vol_scale = mean(vol_scale, na.rm = TRUE)),
                            by = regime]
cat("Regime distribution & overlay components:\n"); print(regime_dist)

# Regime-specific snapshot: latest sig_date per regime
regime_snapshots <- list()
for (rg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  rg_dates <- unique(weights_dt[regime == rg]$as_of_date)
  if (length(rg_dates) == 0) {
    regime_snapshots[[rg]] <- list(n_dates = 0, latest_date = NA, weights = list(),
                                    avg_cash = NA, note = "no sig_dates with this regime")
    next
  }
  latest_d <- max(rg_dates)
  rg_rows <- weights_dt[as_of_date == latest_d]
  rg_w <- setNames(as.list(rg_rows$weight), rg_rows$ticker)
  regime_snapshots[[rg]] <- list(
    n_dates = length(rg_dates),
    latest_date = as.character(latest_d),
    avg_cash = round(mean(weights_dt[regime == rg]$cash_pct), 4),
    avg_dd_cash = round(mean(weights_dt[regime == rg]$dd_cash, na.rm = TRUE), 4),
    avg_fm_cash = round(mean(weights_dt[regime == rg]$fm_cash, na.rm = TRUE), 4),
    avg_vol_scale = round(mean(weights_dt[regime == rg]$vol_scale, na.rm = TRUE), 4),
    weights = rg_w,
    binding_layer_dist = as.list(table(weights_dt[regime == rg]$binding_layer))
  )
}

# Sigma method distribution
sigma_method_dist <- weights_dt[ticker != "CASH",
                                 .(n_obs = .N), by = sigma_method]
cat("Sigma method distribution:\n"); print(sigma_method_dist)

# ────────────────────────────────────────────────────────────────────────
# 5. Build optimization_package_draft.json
# ────────────────────────────────────────────────────────────────────────
cat("\n[Optimizer Iter6] Building optimization_package_draft.json ...\n")

asof_d <- max(weights_dt$as_of_date)
asof_rows <- weights_dt[as_of_date == asof_d]
target_weights <- setNames(as.list(asof_rows$weight), asof_rows$ticker)
asof_regime <- asof_rows$regime[1]
asof_cash_pct <- asof_rows$cash_pct[1]

N_risk <- sum(asof_rows$ticker != "CASH")
bench_w_per <- (1 - asof_cash_pct) / N_risk
active_weights <- list()
for (i in seq_len(nrow(asof_rows))) {
  if (asof_rows$ticker[i] == "CASH") next
  active_weights[[asof_rows$ticker[i]]] <- round(asof_rows$weight[i] - bench_w_per, 4)
}

exp_ar <- selected_eval$net_ret_ann
exp_te <- selected_eval$sigma_monthly * sqrt(12)
exp_ir <- selected_eval$net_ir

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

binding <- character(0)
if (max(val$maxw_risk) > 0.20 - 1e-3) binding <- c(binding, "weight_bound_upper")
if (max(val$n_risk) >= 20L) binding <- c(binding, "max_names_20")
top_concentrated <- val[maxw_risk > 0.18, .N]
if (top_concentrated > length(unique(weights_dt$as_of_date)) * 0.5) {
  binding <- c(binding, "concentration_high_50pct_dates")
}
if (max(val$maxw_cash) >= 0.50 - 1e-3) binding <- c(binding, "cash_overlay_50pct_dd_heavy")
if (max(val$maxw_cash) >= 0.30 - 1e-3) binding <- c(binding, "cash_overlay_30pct_crisis")
if (selected_eval$ann_to > TURNOVER_HARD_CAP) binding <- c(binding, "turnover_hard_cap_breach")
if (selected_eval$cvar95_daily_proxy > CVAR_DAILY_CAP) binding <- c(binding, "cvar_daily_cap_breach")

infeas_report <- NULL
hard_violations <- character(0)
if (selected_eval$ann_to > TURNOVER_HARD_CAP) hard_violations <- c(hard_violations, "turnover_cap_annual")
if (selected_eval$cvar95_daily_proxy > CVAR_DAILY_CAP) hard_violations <- c(hard_violations, "cvar_daily_cap")
if (length(hard_violations) > 0) {
  to_pass_count <- sum(sapply(eval_results, function(r) {
    isTRUE(r$ok) && r$ann_to <= TURNOVER_HARD_CAP
  }))
  cvar_pass_count <- sum(sapply(eval_results, function(r) {
    isTRUE(r$ok) && (r$cvar95_daily_proxy %||% 1) <= CVAR_DAILY_CAP
  }))
  infeas_report <- list(
    reason = sprintf("Selected method '%s' breaches hard caps: %s",
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
    suggested_resolution = paste(
      sprintf("Of %d candidates, %d pass turnover cap (≤%.0f%%), %d pass CVaR cap (≤%.1f%%).",
              length(eval_results), to_pass_count, TURNOVER_HARD_CAP * 100,
              cvar_pass_count, CVAR_DAILY_CAP * 100),
      "CVaR daily proxy = monthly_realized / sqrt(21) — overstates daily tail under heavy fat tails (Hill α=3.00).",
      "Forge: verify CVaR via actual daily portfolio returns at backtest stage.",
      "DD Brake heavy 20% threshold + cash 50% binding in deep-DD periods may further compress realized CVaR.",
      "Sequential admission scenarios: replacement / 80_20 / 50_50 — TBD by Forge."
    )
  )
}

# HHI at as_of (risk-only)
hhi_asof <- sum(asof_rows[ticker != "CASH"]$weight^2)

# Top OW/UW
ow_top <- asof_rows[ticker != "CASH"][order(-weight)][1:min(5, N_risk), .(ticker, weight)]
uw_bot <- asof_rows[ticker != "CASH"][order(weight)][1:min(5, N_risk), .(ticker, weight)]

# Portfolio factor exposures (load exposure_matrix.parquet)
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

pg2_jaccard_proxy <- alpha_pkg$crowding_check$cross_section_jaccard_iter5 %||% NA

multi_sleeve_weights <- list(
  Core = round(0.65 * (1 - asof_cash_pct), 4),
  Defense = round(0.35 * (1 - asof_cash_pct), 4),
  Cash = round(asof_cash_pct, 4)
)

# Kelly + Overlay implementation block
kelly_overlay_implementation <- list(
  kelly_sizing = list(
    fraction = KELLY_FRACTION,
    base_cap = KELLY_BASE_CAP,
    weight_ub_formula = "ub_kelly_i = max(0.02, min(ub_use, kelly_raw_i / max(kelly_raw) * min(ub_use, KELLY_BASE_CAP)))  where kelly_raw_i = max(alpha_i, 0) / sigma_ii^2 * fraction",
    qp_integration = "MVO QP per-name upper bound vector (Amat row -I, bvec -ub_kelly_vec). Non-MVO methods (HRP/ERC/MaxDiv/InvVol/EW) post-projected to Kelly cap.",
    crisis_override = sprintf("CRISIS regime ub_use = %.2f (AX-001 v2 small-sample shrink).", WEIGHT_UB_CRISIS),
    asof_kelly_diagnostics = list(
      kelly_proxy_full = alpha_pkg$handoff_to_optimizer$kelly_sizing_spec$kelly_proxy$full_kelly,
      kelly_proxy_frac = alpha_pkg$handoff_to_optimizer$kelly_sizing_spec$kelly_proxy$frac_kelly,
      asof_max_ub_kelly = if (!is.null(ub_kelly_asof)) round(max(ub_kelly_asof), 4) else 0.10,
      asof_min_ub_kelly = if (!is.null(ub_kelly_asof)) round(min(ub_kelly_asof), 4) else 0.02
    )
  ),
  dd_brake = list(
    thresholds = list(light = DD_THRESHOLD_LIGHT,
                       medium = DD_THRESHOLD_MEDIUM,
                       heavy = DD_THRESHOLD_HEAVY),
    cash_actions = list(light = DD_CASH_LIGHT,
                         medium = DD_CASH_MEDIUM,
                         heavy = DD_CASH_HEAVY),
    bm_source = "benchmark.parquet KOSPI200 daily",
    pit_compliance = "PASS: dd_lag = shift(dd_12m, 1L) one-month lag; computed from BM cumret peak/12M",
    asof_dd_lag = round(asof_dd_lag, 4),
    n_dates_dd_active = sum(weights_dt$dd_cash > 0, na.rm = TRUE) / N_risk
  ),
  volreg = list(
    vol_target_ann = VOL_TARGET_ANN,
    vol_window_months = VOL_WINDOW_MONTHS,
    scale_formula = "scale = min(1.0, vol_target / max(vol_lag, eps))",
    bm_source = "benchmark.parquet 12M rolling sd × sqrt(12)",
    pit_compliance = "PASS: vol_lag = shift(vol_12m_ann, 1L) one-month lag",
    asof_vol_lag = round(asof_vol_lag, 4),
    asof_vol_scale = round(ov_asof$vol_scale, 4),
    avg_vol_scale_overall = round(mean(weights_dt$vol_scale, na.rm = TRUE), 4)
  ),
  fm_regime = list(
    cash_policy = list(BULL = FM_CASH_BULL, NORMAL = FM_CASH_NORMAL,
                        CAUTION = FM_CASH_CAUTION, CRISIS = FM_CASH_CRISIS),
    data_source = "alpha_scores.parquet::regime_state column (Iter 2 PIT expanding percentile)",
    pit_compliance = "PASS: t-1 regime applied at t (Iter 2 inheritance)",
    asof_regime = asof_regime,
    asof_fm_cash = ov_asof$fm_cash
  ),
  combine_rule = list(
    formula = "total_cash = max(dd_cash, fm_cash) + (1 - max(dd_cash, fm_cash)) * (1 - vol_scale); cap 0.95",
    rationale = "DD Brake AND FM Regime each set a baseline cash floor (max). VolReg then proportionally reduces the remaining risk-asset exposure by (1 - vol_scale).",
    asof_total_cash = round(asof_cash, 4),
    asof_binding_layer = ov_asof$binding_layer
  )
)

# Pooled fallback usage
pooled_usage <- weights_dt[ticker != "CASH" & grepl("constcor|pooled", sigma_method)]
n_pooled_dates <- length(unique(pooled_usage$as_of_date))

opt_pkg_draft <- list(
  task_id = WT_ID,
  iter = 6,
  iter_name = "MEGA_06_STR1699_Kelly_Overlay",
  as_of_date = as.character(asof_d),
  signal_as_of = as.character(SIGNAL_AS_OF),
  selection_objective = "net_ir",
  walk_forward = TRUE,
  n_sig_dates_walkforward = n_sig_dates_walkforward,
  walk_forward_date_range = c(as.character(min(weights_dt$as_of_date)),
                                as.character(max(weights_dt$as_of_date))),
  deploy_cutoff = as.character(SIGNAL_AS_OF),  # v6.2 mandate
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
    turnover_phi = selected_cfg$phi,
    confidence_used = !is.null(selected_cfg$conf),
    kelly_applied = TRUE,
    overlay_applied = TRUE
  ),
  method_comparison = method_log,
  method_shopping_log = list(
    candidates_tried = length(eval_results),
    cap = 10L,
    parallel_exec = FALSE,
    rcpp_used = FALSE,
    method_log = method_log
  ),
  multi_sleeve_weights = multi_sleeve_weights,
  kelly_overlay_implementation = kelly_overlay_implementation,
  regime_specific_weights = regime_snapshots,
  cash_overlay_policy = list(
    BULL = FM_CASH_BULL, NORMAL = FM_CASH_NORMAL,
    CAUTION = FM_CASH_CAUTION, CRISIS = FM_CASH_CRISIS,
    rationale = "AX-001 v2 conditional cash policy + DD Brake (path-dependent override) + VolReg (12% target) — Iter 6 3-Layer Overlay."
  ),
  pooled_fallback_usage = list(
    enforced = TRUE,
    regimes_using_pooled = c("CRISIS", "CAUTION"),
    n_dates_pooled = n_pooled_dates,
    n_dates_total = n_sig_dates_walkforward,
    pct_dates_pooled = round(n_pooled_dates / n_sig_dates_walkforward, 4),
    binding_rule = "Risk handoff (risk_package.optimizer_handoff.recommendations[2]). CRISIS Σ cond=108, pooled Σ cond=100. Per-sig_date Σ uses LW_constcor in CRISIS/CAUTION, LW_oracle otherwise.",
    crisis_max_w_shrink = sprintf("ub_use = %.2f in CRISIS regime (vs %.2f default).", WEIGHT_UB_CRISIS, WEIGHT_UB_DEFAULT)
  ),
  hhi_asof = round(hhi_asof, 4),
  portfolio_factor_exposures = port_betas,
  beta_audit_note = paste(
    sprintf("Port MKT beta=%.3f at as_of (long-only top-N).", port_betas$MKT),
    "Discovery WT focuses on alpha/optimizer logic; deployment-stage beta hedge is Forge/Governor responsibility."
  ),
  selected_weight_tail_audit = list(
    cvar95_monthly = round(selected_eval$cvar95_monthly, 5),
    cvar95_daily_proxy = round(selected_eval$cvar95_daily_proxy, 5),
    cvar_daily_cap = CVAR_DAILY_CAP,
    cvar_pass = isTRUE(selected_eval$cvar95_daily_proxy <= CVAR_DAILY_CAP),
    mdd = round(selected_eval$mdd, 4),
    method = "monthly_realized_returns_to_daily_proxy_via_sqrt21",
    note = "Iter 6 includes Kelly + 3-Layer Overlay applied per sig_date. Daily proxy from monthly returns (cost-net 15bps × 2 round-trip)."
  ),
  pg2_crowding_proxy = list(
    cross_section_jaccard_iter5 = pg2_jaccard_proxy,
    note = "Direct PG2 (STR_1631_SYN_05 + STR_1656_MLRA_M05) alpha vector unavailable (STR_1656 ML-model output without alpha trail). Cross-section Jaccard vs Iter 5 = 0.111. Forge: portfolio-level realized correlation against PG2 NAV.",
    direct_pg2_tdc_responsibility = "Forge_backtest_stage"
  ),
  sequential_admission_scenarios = list(
    replacement = list(
      design = "100% Iter 6 (STR_1699 + Kelly + 3-Layer Overlay) replaces PG2",
      backtest_status = "TBD by Forge",
      expected_benefit = "Combined alpha robustness (STR_1699 5-spec FF5 PASS) + machinery boost (MEGA_05 SR 1.110)"
    ),
    integration_80_20 = list(
      design = "80% MEGA_05 + 20% Iter 6 — note: Iter 6 IS MEGA_05 machinery layer; may be redundant",
      backtest_status = "TBD by Forge"
    ),
    integration_50_50 = list(
      design = "50% Iter 6 STR_1699+Kelly+Overlay / 50% STR_1656_MLRA_M05",
      backtest_status = "TBD by Forge",
      expected_benefit = "Maintain ML diversifier (STR_1656) while introducing Iter 6 robust alpha base"
    )
  ),
  explanation = list(
    top_overweights = ow_top$ticker,
    top_underweights = uw_bot$ticker,
    main_tradeoffs = c(
      sprintf("Method selected = %s (net_IR=%.3f). Walk-forward over %d sig_dates.",
              selected_name, exp_ir, n_sig_dates_walkforward),
      sprintf("Kelly_frac05 + 3-Layer Overlay applied: DD Brake 6/8/20 + VolReg %.0f%% target + FM regime cash 0/5/15/30%%.",
              VOL_TARGET_ANN * 100),
      sprintf("CRISIS pooled-Σ fallback enforced (%d / %d sig_dates). AX-001 v2 CRISIS ub=%.2f.",
              n_pooled_dates, n_sig_dates_walkforward, WEIGHT_UB_CRISIS),
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
                                 note = "applies to risk securities only (CASH cap = 0.95 max from 3-Layer stack)"),
    cash_overlay_cap = list(enforced = TRUE, cap = 0.95,
                              max_observed_cash = round(max(val$maxw_cash), 4),
                              note = "Iter 6 3-Layer Overlay (DD heavy 50% + VolReg can stack); typical FM-only ≤ 0.30"),
    long_only = list(enforced = TRUE, min_weight_observed = round(min(val$minw_risk), 6)),
    sum_w_1 = list(enforced = TRUE, max_abs_error = round(sum_err, 8),
                     note = "Σw across risk + CASH = 1")
  ),
  pit_compliance = list(
    C1 = "PASS — expanding-window LW shrinkage (lw_oracle / lw_constcor) per sig_date",
    C2 = "PASS — alpha at sig_date d → weights at sig_date d → realized Ret_1m at d",
    C9 = "PASS — DD/Vol t-1 lag (dd_lag = shift(dd_12m, 1L), vol_lag = shift(vol_12m_ann, 1L))",
    C11 = "PASS — KR internal regime + KOSPI200 BM only, no FRED leakage",
    C13 = "PASS — Z_Score_Aligned alpha inherited from Alpha agent, no manual flip",
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    lockbox = "ENFORCED — last sig_date 2023-11-01 strictly before lockbox 2024-01-23"
  ),
  red_flags = list(
    RF_O3_turnover_low = if (selected_eval$ann_to < 0.02) "TRIGGERED" else "PASS",
    RF_O5_max_names = if (max(val$n_risk) > 20) "TRIGGERED_BLOCK" else "PASS",
    RF_O6_sum_w = if (sum_err > 0.001) "TRIGGERED_BLOCK" else "PASS",
    RF_O7_long_only_or_bound = if (min(val$minw_risk) < 0 || max(val$maxw_risk) > 0.20)
      "TRIGGERED_BLOCK" else "PASS",
    RF_O9_walk_forward = if (n_sig_dates_walkforward >= 60L) "PASS" else "TRIGGERED_BLOCK"
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

draft_path <- file.path(WT_DIR, "optimization_package_draft.json")
write_json(opt_pkg_draft, draft_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[Optimizer Iter6] optimization_package_draft.json written: %s\n", draft_path))

# Save weights.csv (mailbox + stage_artifacts) — required schema
weights_csv <- weights_dt[, .(as_of_date, ticker, weight, method_selected, sleeve_id,
                              cash_pct, regime, n_names, sigma_method,
                              dd_cash, fm_cash, vol_scale, binding_layer, dd_lag, vol_lag)]
fwrite(weights_csv, file.path(WT_DIR, "weights.csv"))
fwrite(weights_csv, file.path(ART_DIR, "weights.csv"))
cat(sprintf("[Optimizer Iter6] weights.csv written (%d rows × %d sig_dates) to mailbox + stage\n",
            nrow(weights_csv), n_sig_dates_walkforward))

saveRDS(list(
  weights_dt = weights_dt,
  comp = comp,
  eval_results = eval_results,
  selected_method = selected_method,
  selected_eval = selected_eval,
  opt_pkg_draft = opt_pkg_draft,
  sig_dates_use = sig_dates_use,
  bm_overlay = bm_overlay
), file.path(ART_DIR, "optimizer_workspace.rds"))

cat("\n[Optimizer Iter6] DRAFT phase complete.\n")
cat(sprintf("  selected_method=%s\n  n_sig_dates_walkforward=%d\n  net_IR=%.3f\n  CAGR=%.2f%%\n  MDD=%.2f%%\n  TO=%.0f%%\n  HHI_asof=%.4f\n  cash_at_asof=%.0f%%\n  n_pooled_dates=%d\n",
            selected_method, n_sig_dates_walkforward, exp_ir,
            selected_eval$cagr * 100, selected_eval$mdd * 100,
            selected_eval$ann_to * 100, hhi_asof, asof_cash_pct * 100, n_pooled_dates))
