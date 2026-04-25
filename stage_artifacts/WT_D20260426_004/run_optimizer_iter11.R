#==============================================================================
# WT-D20260426_004 — Optimizer Research (Iter 11 Linear Tilt monthly)
#
# Mission:
#   - Linear Tilt monthly Optimizer-only mutation (Iter 5 alpha + risk reused).
#   - User hypothesis: alpha rank 높을수록 weight ↑ (CAGR + SR ↑ 잠재).
#   - Q-Lead quick test: gross EW SR 1.41 / Linear λ1.0 SR 1.62. net (15bps) Linear λ1.0
#     SR 1.50 BUT TO 807%/yr — Hard cap 600% violation.
#   - Iter 11: monthly granularity 유지, TO < 600% PASS 방법 자율 탐색
#     (Linear Tilt + no-trade band + TO penalty + alpha-sticky 등).
#
# Method Shopping (≤10):
#   1. Linear_Tilt_lam1.0_monthly        (baseline, expected TO 비위반)
#   2. Linear_Tilt_lam0.5_monthly        (soft tilt)
#   3. Linear_Tilt_lam0.3_monthly        (softer tilt)
#   4. Linear_Tilt_lam1.0_NTB_monthly    (no-trade band 30% / 1% abs)
#   5. Linear_Tilt_lam1.0_TOphi3_monthly (turnover penalty φ=3 in optimizer)
#   6. Linear_Tilt_lam1.0_TOphi8_monthly (heavier TO penalty φ=8)
#   7. Score_Concentrated_top10_monthly  (rank-based, top10 EW)
#   8. HRP_alpha_overlay_monthly         (HRP base + 50/50 alpha tilt)
#   9. HRP_lw_monthly                    (Iter 5 reference baseline, monthly)
#  10. Linear_Tilt_lam1.0_StickyTopK     (top alpha rank persistence band)
#
# Hard Constraints (Hook + R stopifnot):
#   - max_names ≤ 20, weight_bounds [0, 0.20], long-only, Σw = 1
#   - turnover_cap_annual ≤ 6.0 (CRITICAL — Iter 3 violation lesson)
#   - liquidity inherited (alpha panel pre-filtered 5e7)
#
# Inputs (Pure Function — read-only):
#   - alpha_package.json  (alpha_vector / confidence_vector / 240-date schedule)
#   - risk_package.json   (Σ = LW_oracle, pooled fallback Σ, cor_core_def 0.692)
#   - alpha_scores.parquet (240 sig_dates × 773 tickers, score_eff + Ret_1m + regime_state)
#   - covariance.parquet  (as_of 20×20 Σ)
#   - covariance_pooled_fallback.parquet (pooled fallback Σ)
#
# Outputs:
#   - optimization_package.json (mailbox WT-D20260426_004)
#   - weights.csv (mailbox + stage_artifacts WT_D20260426_004)
#   - weight_method_selected.md (stage_artifacts)
#   - optimizer_challenge_note.md (mailbox)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(arrow)
  library(quadprog)
  library(digest)
})

set.seed(20260426L)

WT_ID         <- "WT-D20260426_004"
PARENT_WT_ID  <- "WT-D20260425_010"     # source of alpha_scores + Σ artifacts
WT_DIR        <- file.path("qepm/mailbox/worktask", WT_ID)
ART_DIR       <- file.path("stage_artifacts", "WT_D20260426_004")
SRC_ART_DIR   <- file.path("stage_artifacts", "WT_D20260425_010")  # parent alpha + Σ

PIT_HARD_CUTOFF   <- as.Date("2023-11-30")
SIGNAL_AS_OF      <- as.Date("2023-12-01")
COST_BPS          <- 15            # one-way bps
TURNOVER_HARD_CAP <- 6.0           # 600% annual — Discovery WT cap (CRITICAL)
CVAR_DAILY_CAP    <- 0.025

# ── Helpers ───────────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)[1]) a else b

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

# ── Pairwise-complete sample cov + LW oracle / const-cor shrinkage ────────
.sample_cov_pairwise <- function(R) {
  R <- as.matrix(R)
  S <- stats::cov(R, use = "pairwise.complete.obs")
  S[!is.finite(S)] <- 0
  S <- 0.5 * (S + t(S))
  S
}

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
  F <- rbar * (s %*% t(s)); diag(F) <- diag(S)
  R_demean <- sweep(R, 2, colMeans(R, na.rm = TRUE), `-`)
  R_demean[is.na(R_demean)] <- 0
  pi_hat <- 0
  for (i in seq_len(N)) {
    for (j in seq_len(N)) {
      pi_hat <- pi_hat + mean((R_demean[, i] * R_demean[, j] - S[i, j])^2)
    }
  }
  gamma_hat <- sum((F - S)^2)
  delta <- if (gamma_hat <= 0) 0.5 else max(0, min(1, pi_hat / (T_eff * gamma_hat)))
  Sigma_hat <- delta * F + (1 - delta) * S
  Sigma_hat <- 0.5 * (Sigma_hat + t(Sigma_hat))
  eig2 <- eigen(Sigma_hat, symmetric = TRUE, only.values = TRUE)$values
  if (any(eig2 < 1e-10)) Sigma_hat <- Sigma_hat + diag(1e-8, N)
  rownames(Sigma_hat) <- colnames(Sigma_hat) <- colnames(R)
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
  F <- rbar * (s %*% t(s)); diag(F) <- diag(S)
  delta <- 0.5
  Sigma_hat <- delta * F + (1 - delta) * S
  Sigma_hat <- 0.5 * (Sigma_hat + t(Sigma_hat))
  eig2 <- eigen(Sigma_hat, symmetric = TRUE, only.values = TRUE)$values
  if (any(eig2 < 1e-10)) Sigma_hat <- Sigma_hat + diag(1e-8, N)
  rownames(Sigma_hat) <- colnames(Sigma_hat) <- colnames(R)
  Sigma_hat
}

# ── HRP (López de Prado 2016) ─────────────────────────────────────────────
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
    cluster_alloc(start, mid)
    cluster_alloc(mid + 1, end)
  }
  cluster_alloc(1, N)
  if (any(!is.finite(w))) w[!is.finite(w)] <- 0
  if (sum(w) <= 1e-12) return(rep(1 / N, N))
  as.numeric(w / sum(w))
}

# ── Linear Tilt: w_i ∝ 1 + λ × (rank_i - mean_rank)/(N-1) ─────────────────
# alpha_t: numeric vector named on tickers
# lambda: tilt strength (0=EW, 1=full linear tilt where top - bottom = 2/N spread)
# bounds: [lb, ub] per-name
# ub_concentration: max-weight cap (0.20 default)
linear_tilt_qd <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  # Ranks: 1 = lowest alpha, N = highest alpha
  r <- rank(alpha_t, ties.method = "average")
  # Center ranks: (r - mean) / (N-1) ∈ [-0.5, 0.5]
  centered <- (r - mean(r)) / (N - 1)
  # tilt: 1 + lambda × 2 × centered ∈ [1-λ, 1+λ]
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ── HRP base + alpha tilt overlay (50/50 blend) ───────────────────────────
hrp_alpha_overlay_qd <- function(alpha_t, Sigma, lambda = 1.0, mix = 0.5,
                                   lb = 0, ub = 0.20) {
  w_hrp <- hrp_qd(Sigma); names(w_hrp) <- names(alpha_t)
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  w <- mix * w_hrp + (1 - mix) * w_tilt
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ── Score-concentrated top-K equal-weight ─────────────────────────────────
score_concentrated_qd <- function(alpha_t, top_k = 10, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= top_k) return(rep(1 / N, N))
  # Top K names by alpha
  sel_idx <- order(alpha_t, decreasing = TRUE)[seq_len(top_k)]
  w <- numeric(N)
  w[sel_idx] <- 1 / top_k
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ── Linear Tilt with no-trade band (relative + absolute) ──────────────────
apply_no_trade_band <- function(w_new, w_prev, band_pct = 0.30, band_abs = 0.01) {
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
  if (sum(w_out) > 0) w_out <- w_out / sum(w_out)
  w_out <- w_out[names(w_new)]
  w_out / sum(w_out)
}

# ── Linear Tilt with TO penalty (post-tilt projection) ────────────────────
# Projects raw tilt toward w_prev to reduce L1 turnover; uses simple shrink-toward-prev
# w_out = phi_blend * w_prev + (1 - phi_blend) * w_tilt where phi_blend ∈ [0, 1]
# phi_blend = 1 - 1/(1 + phi)  →  phi=0 → 0% blend (full tilt), phi=∞ → 100% prev (no trade)
linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.0,
                                       w_prev = NULL, phi = 5.0,
                                       lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  # Align w_prev to current universe
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  # Re-allocate dropped names' weight proportionally to w_tilt
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  wp <- wp / sum(wp)
  blend <- phi / (1 + phi)   # phi=5 → blend=0.833
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

# ── Sticky Top-K: keep prior top-K names if still in top-(K+5); else reweight tilt
sticky_top_k_qd <- function(alpha_t, w_prev = NULL,
                              top_k = 15, persistence_window = 5,
                              lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (is.null(w_prev) || N <= top_k) {
    return(linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub))
  }
  # Build sticky universe: prior top-K UNION current top-K + persistence buffer
  prior_held <- names(w_prev)[w_prev > 0]
  alpha_rank <- order(alpha_t, decreasing = TRUE)
  current_top_set <- names(alpha_t)[alpha_rank[seq_len(top_k)]]
  buffer_set <- names(alpha_t)[alpha_rank[seq_len(min(top_k + persistence_window, N))]]
  # Names to keep: current top-K UNION (prior held that still in buffer)
  retained_prior <- intersect(prior_held, buffer_set)
  sticky_set <- union(current_top_set, retained_prior)
  # Cap at top_k by alpha rank
  if (length(sticky_set) > top_k) {
    sticky_alpha <- alpha_t[sticky_set]
    sticky_set <- sticky_set[order(sticky_alpha, decreasing = TRUE)[seq_len(top_k)]]
  }
  # Apply linear tilt within sticky_set
  alpha_sub <- alpha_t[sticky_set]
  w_sub <- linear_tilt_qd(alpha_sub, lambda = lambda, lb = lb, ub = ub)
  names(w_sub) <- sticky_set
  # Build full-universe weight (zeros elsewhere) - return on the full alpha_t universe
  w_full <- numeric(N); names(w_full) <- names(alpha_t)
  w_full[sticky_set] <- w_sub
  if (sum(w_full) > 0) w_full <- w_full / sum(w_full)
  w_full
}

# ── Cash overlay (AX-001 v2 conditional) ─────────────────────────────────
cash_overlay_pct <- function(regime) {
  switch(as.character(regime),
    "BULL"    = 0.00,
    "NORMAL"  = 0.05,
    "CAUTION" = 0.15,
    "CRISIS"  = 0.30,
    0.05
  )
}

# ── Per-sig_date weight computation ───────────────────────────────────────
compute_weights_at_date <- function(sig_date, alpha_scores, ret_panel,
                                      method = "Linear_Tilt_lam1.0",
                                      method_params = list(),
                                      ub = 0.20,
                                      max_names = 20L,
                                      min_names = 15L,
                                      pooled_fallback_regimes = c("CRISIS", "CAUTION"),
                                      w_prev_risk = NULL) {
  panel_t <- alpha_scores[Date == sig_date & !is.na(score_eff)]
  if (nrow(panel_t) == 0) return(NULL)
  regime <- panel_t$regime_state[1]

  setorder(panel_t, -score_eff)
  N_eligible <- nrow(panel_t)
  N_target <- min(max_names, N_eligible)
  if (N_target < min_names && N_eligible >= min_names) N_target <- min_names
  if (N_target < 5L) {
    return(data.table(as_of_date = sig_date, ticker = NA, weight = NA,
                      method_selected = method, sleeve_id = "infeasible",
                      regime = regime, n_names = N_eligible, sigma_method = NA))
  }
  picks <- panel_t[1:N_target]
  tickers_t <- picks$Ticker
  alpha_t   <- picks$score_eff
  names(alpha_t) <- tickers_t

  # Σ from expanding monthly returns up to sig_date - 1
  hist_panel <- ret_panel[Date < sig_date & Ticker %in% tickers_t]
  ret_wide <- dcast(hist_panel, Date ~ Ticker, value.var = "Ret_1m")
  ret_mat <- as.matrix(ret_wide[, !"Date", with = FALSE])
  rownames(ret_mat) <- as.character(ret_wide$Date)
  ticker_avail <- intersect(tickers_t, colnames(ret_mat))
  if (length(ticker_avail) < 5L) return(NULL)
  ret_mat <- ret_mat[, ticker_avail, drop = FALSE]
  alpha_t <- alpha_t[ticker_avail]; tickers_t <- ticker_avail

  col_nna <- colSums(!is.na(ret_mat))
  keep_tickers <- names(col_nna)[col_nna >= 24]
  if (length(keep_tickers) < 5) return(NULL)
  ret_mat <- ret_mat[, keep_tickers, drop = FALSE]
  alpha_t <- alpha_t[keep_tickers]; tickers_t <- keep_tickers

  if (nrow(ret_mat) < 24L) {
    Sigma_t <- diag(rep(0.005, length(tickers_t)))
    rownames(Sigma_t) <- colnames(Sigma_t) <- tickers_t
    sigma_method <- "diag_fallback_short_hist"
  } else {
    if (regime %in% pooled_fallback_regimes) {
      Sigma_t <- lw_constcor_cov(ret_mat); sigma_method <- "lw_constcor_pooled_fallback"
    } else {
      Sigma_t <- lw_oracle_cov(ret_mat); sigma_method <- "lw_oracle"
    }
    if (is.null(Sigma_t)) {
      var_diag <- apply(ret_mat, 2, stats::var, na.rm = TRUE)
      var_diag[!is.finite(var_diag) | var_diag <= 0] <- 0.01
      Sigma_t <- diag(var_diag); rownames(Sigma_t) <- colnames(Sigma_t) <- tickers_t
      sigma_method <- "sample_diag_fallback"
    }
  }

  sigma_tickers <- intersect(tickers_t, colnames(Sigma_t))
  if (length(sigma_tickers) < 5) return(NULL)
  Sigma_t  <- Sigma_t[sigma_tickers, sigma_tickers, drop = FALSE]
  alpha_t  <- alpha_t[sigma_tickers]; tickers_t <- sigma_tickers

  # CRISIS small-sample weight shrinkage: tighten max-weight to 0.10
  ub_use <- if (regime == "CRISIS") min(ub, 0.10) else ub

  # Method dispatch
  N <- length(tickers_t)
  names(alpha_t) <- tickers_t
  w <- switch(method,
    "Linear_Tilt_lam1.0"        = linear_tilt_qd(alpha_t, lambda = 1.0, ub = ub_use),
    "Linear_Tilt_lam0.5"        = linear_tilt_qd(alpha_t, lambda = 0.5, ub = ub_use),
    "Linear_Tilt_lam0.3"        = linear_tilt_qd(alpha_t, lambda = 0.3, ub = ub_use),
    "Linear_Tilt_lam1.0_NTB"    = {
      w0 <- linear_tilt_qd(alpha_t, lambda = 1.0, ub = ub_use)
      names(w0) <- tickers_t
      if (!is.null(w_prev_risk))
        apply_no_trade_band(w0, w_prev_risk,
                              band_pct = method_params$band_pct %||% 0.30,
                              band_abs = method_params$band_abs %||% 0.01)
      else w0
    },
    "Linear_Tilt_lam1.0_TOphi3" = linear_tilt_to_penalty_qd(alpha_t, lambda = 1.0,
                                                              w_prev = w_prev_risk,
                                                              phi = 3.0, ub = ub_use),
    "Linear_Tilt_lam1.0_TOphi8" = linear_tilt_to_penalty_qd(alpha_t, lambda = 1.0,
                                                              w_prev = w_prev_risk,
                                                              phi = 8.0, ub = ub_use),
    "Score_Concentrated_top10"  = score_concentrated_qd(alpha_t, top_k = 10, ub = ub_use),
    "HRP_alpha_overlay"         = hrp_alpha_overlay_qd(alpha_t, Sigma_t,
                                                         lambda = 1.0, mix = 0.5, ub = ub_use),
    "HRP_lw"                    = { w0 <- hrp_qd(Sigma_t); names(w0) <- tickers_t; w0 },
    "Linear_Tilt_lam1.0_StickyTopK" = sticky_top_k_qd(alpha_t, w_prev = w_prev_risk,
                                                        top_k = 15, persistence_window = 5,
                                                        lambda = 1.0, ub = ub_use),
    NULL
  )
  if (is.null(w)) {
    w <- rep(1 / N, N); method <- paste0(method, "_fallback_EW")
  }
  names(w) <- tickers_t
  w <- normalize_long_only(w, lb = 0, ub = ub_use, target_sum = 1)

  # Cash overlay
  cash_pct <- cash_overlay_pct(regime)
  w_risk <- w * (1 - cash_pct)

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

# ── Walk-forward portfolio metrics (monthly granularity, all methods) ────
walk_forward_method_eval <- function(method_name, alpha_scores, ret_panel,
                                       sig_dates,
                                       method_params = list(),
                                       ub = 0.20, max_names = 20L, min_names = 15L,
                                       cost_bps = 15,
                                       collect_weights = FALSE,
                                       force_rebal_at_dates = NULL) {
  W_prev <- NULL
  port_ret <- numeric(length(sig_dates))
  port_to  <- numeric(length(sig_dates))
  port_cost <- numeric(length(sig_dates))
  cash_pct_seq <- numeric(length(sig_dates))
  realized_risk_seq <- numeric(length(sig_dates))
  weights_collected <- list()
  n_used <- 0L
  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    w_prev_risk_named <- NULL
    if (!is.null(W_prev)) {
      wpr <- W_prev[ticker != "CASH"]
      w_prev_risk_named <- setNames(wpr$weight, wpr$ticker)
    }
    res <- tryCatch(
      compute_weights_at_date(d, alpha_scores, ret_panel,
                                method = method_name,
                                method_params = method_params,
                                ub = ub, max_names = max_names, min_names = min_names,
                                w_prev_risk = w_prev_risk_named),
      error = function(e) NULL
    )
    if (is.null(res) || any(is.na(res$weight))) next
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
    cost_t <- to_t * (cost_bps / 1e4) * 2  # round-trip
    port_ret[i] <- realized_t - cost_t
    port_to[i]  <- to_t
    port_cost[i] <- cost_t
    cash_pct_seq[i] <- cash_pct_t
    realized_risk_seq[i] <- realized_risk
    W_prev <- res[, .(ticker, weight)]
  }
  used <- which(port_ret != 0 | port_to != 0)
  if (length(used) < 12) return(list(method = method_name, n_used = n_used, ok = FALSE))
  pr <- port_ret[used]; pt <- port_to[used]; pc <- port_cost[used]
  cs <- cash_pct_seq[used]; rr <- realized_risk_seq[used]
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
       port_returns_monthly = pr, port_to = pt, port_cash = cs,
       weights_collected = if (collect_weights) weights_collected else NULL)
}

# ────────────────────────────────────────────────────────────────────────
# 1. Load packages (read-only inheritance)
# ────────────────────────────────────────────────────────────────────────
cat("[Optimizer Iter11 Linear Tilt] Loading inputs...\n")
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = TRUE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = TRUE)
req_pkg   <- fromJSON(file.path(WT_DIR, "request.json"),       simplifyVector = TRUE)

# Source artifacts from parent WT (Iter 5)
alpha_scores <- as.data.table(read_parquet(file.path(SRC_ART_DIR, "alpha_scores.parquet")))
setkey(alpha_scores, Date, Ticker)

ret_panel <- alpha_scores[, .(Date, Ticker, Ret_1m)]
ret_panel <- ret_panel[!is.na(Ret_1m)]
setkey(ret_panel, Date, Ticker)

Sigma_dt        <- as.data.table(read_parquet(file.path(SRC_ART_DIR, "covariance.parquet")))
Sigma_pooled_dt <- as.data.table(read_parquet(file.path(SRC_ART_DIR, "covariance_pooled_fallback.parquet")))
SIG_TICKERS <- as.character(Sigma_dt$Ticker)
Sigma_asof  <- as.matrix(Sigma_dt[, !"Ticker", with = FALSE])
rownames(Sigma_asof) <- colnames(Sigma_asof) <- SIG_TICKERS
Sigma_pooled_asof <- as.matrix(Sigma_pooled_dt[, !"Ticker", with = FALSE])
rownames(Sigma_pooled_asof) <- colnames(Sigma_pooled_asof) <- SIG_TICKERS

cat(sprintf("[Iter11] alpha panel: %d sig_dates × %d tickers (inherited from %s)\n",
            length(unique(alpha_scores$Date)), length(unique(alpha_scores$Ticker)), PARENT_WT_ID))
cat(sprintf("[Iter11] Risk Σ as_of: %dx%d (cond %.2f), pooled: %dx%d (cond %.0f)\n",
            nrow(Sigma_asof), ncol(Sigma_asof), kappa(Sigma_asof, exact = TRUE),
            nrow(Sigma_pooled_asof), ncol(Sigma_pooled_asof), kappa(Sigma_pooled_asof, exact = TRUE)))

all_sig <- sort(unique(alpha_scores$Date))
min_hist_start <- as.Date("2006-01-01")
sig_dates_use <- all_sig[all_sig >= min_hist_start & all_sig <= SIGNAL_AS_OF]
cat(sprintf("[Iter11] sig_dates_use: %d (%s ~ %s)\n",
            length(sig_dates_use), as.character(min(sig_dates_use)),
            as.character(max(sig_dates_use))))

# ────────────────────────────────────────────────────────────────────────
# 2. Method shopping (10 candidates, monthly only) — net_IR + TO < 600%
# ────────────────────────────────────────────────────────────────────────
cat("\n[Iter11] Method shopping (10 candidates, monthly granularity) ...\n")

CAND_CONFIG <- list(
  list(name = "Linear_Tilt_lam1.0",          method = "Linear_Tilt_lam1.0",          params = list()),
  list(name = "Linear_Tilt_lam0.5",          method = "Linear_Tilt_lam0.5",          params = list()),
  list(name = "Linear_Tilt_lam0.3",          method = "Linear_Tilt_lam0.3",          params = list()),
  list(name = "Linear_Tilt_lam1.0_NTB",      method = "Linear_Tilt_lam1.0_NTB",
       params = list(band_pct = 0.30, band_abs = 0.01)),
  list(name = "Linear_Tilt_lam1.0_TOphi3",   method = "Linear_Tilt_lam1.0_TOphi3",   params = list()),
  list(name = "Linear_Tilt_lam1.0_TOphi8",   method = "Linear_Tilt_lam1.0_TOphi8",   params = list()),
  list(name = "Score_Concentrated_top10",    method = "Score_Concentrated_top10",    params = list()),
  list(name = "HRP_alpha_overlay",           method = "HRP_alpha_overlay",           params = list()),
  list(name = "HRP_lw_baseline",             method = "HRP_lw",                      params = list()),
  list(name = "Linear_Tilt_lam1.0_StickyTopK", method = "Linear_Tilt_lam1.0_StickyTopK", params = list())
)
stopifnot(length(CAND_CONFIG) <= 10L)

eval_results <- list()
for (cfg in CAND_CONFIG) {
  t0 <- Sys.time()
  cat(sprintf("  %s ... ", cfg$name))
  r <- walk_forward_method_eval(cfg$method, alpha_scores, ret_panel, sig_dates_use,
                                  method_params = cfg$params,
                                  ub = 0.20, max_names = 20L, min_names = 15L,
                                  cost_bps = COST_BPS,
                                  force_rebal_at_dates = c(SIGNAL_AS_OF))
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

# Selection: max net_IR among methods passing TO hard cap.
# If none pass — use min-TO (with infeasibility_report). AX-002 process honesty.
ok_results <- comp[ok == TRUE]
admissible <- ok_results[pass_to == TRUE]
infeas_to_only <- nrow(admissible) == 0
if (infeas_to_only) {
  cat("[Iter11] WARN — no method passes TO hard cap 6.0. Selecting min-TO + infeasibility_report.\n")
  setorder(ok_results, ann_to, -net_ir)
  selected_name <- ok_results$name[1]
} else {
  setorder(admissible, -net_ir)
  selected_name <- admissible$name[1]
}
selected_eval <- eval_results[[selected_name]]
selected_method <- selected_name
selected_cfg <- CAND_CONFIG[[which(sapply(CAND_CONFIG, function(x) x$name == selected_name))]]

cat(sprintf("\n[Iter11] selected = %s (net_IR=%.3f, SR=%.3f, CAGR=%.2f%%, MDD=%.2f%%, TO=%.0f%%, CVaR_d=%.2f%%)\n",
            selected_name, selected_eval$net_ir, selected_eval$sr_ann,
            selected_eval$cagr * 100, selected_eval$mdd * 100,
            selected_eval$ann_to * 100, selected_eval$cvar95_daily_proxy * 100))

# ────────────────────────────────────────────────────────────────────────
# 3. Generate full walk-forward weights schedule with selected method
# ────────────────────────────────────────────────────────────────────────
cat("\n[Iter11] Generating weights schedule with selected method ...\n")
gen_eval <- walk_forward_method_eval(selected_cfg$method,
                                       alpha_scores, ret_panel, sig_dates_use,
                                       method_params = selected_cfg$params,
                                       ub = 0.20, max_names = 20L, min_names = 15L,
                                       cost_bps = COST_BPS,
                                       collect_weights = TRUE,
                                       force_rebal_at_dates = c(SIGNAL_AS_OF))
all_rows <- gen_eval$weights_collected
weights_dt <- rbindlist(all_rows, fill = TRUE)

# At as_of_date — re-build using Risk's exact 20-ticker Σ artifact
cat("[Iter11] Aligning as_of weights with Risk's covariance artifact ...\n")
asof_panel <- alpha_scores[Date == SIGNAL_AS_OF & !is.na(score_eff)]
asof_regime <- asof_panel$regime_state[1]
asof_eligible <- intersect(asof_panel$Ticker, SIG_TICKERS)
cat(sprintf("  as_of regime=%s, Risk 20 tickers, eligible from alpha=%d, intersection=%d\n",
            asof_regime, length(SIG_TICKERS), length(asof_eligible)))
asof_use_pooled <- asof_regime %in% c("CRISIS", "CAUTION")
asof_Sigma <- if (asof_use_pooled) Sigma_pooled_asof else Sigma_asof
asof_sigma_method <- if (asof_use_pooled) "lw_constcor_pooled_fallback_risk_artifact" else "lw_oracle_risk_artifact"
asof_ub <- if (asof_regime == "CRISIS") 0.10 else 0.20

# Use alpha vector (top-20 named) from alpha_pkg for as_of
asof_alpha_vec <- setNames(unlist(alpha_pkg$alpha_vector)[SIG_TICKERS], SIG_TICKERS)
# Find prior weights from walk-forward weights_dt (last sig_date < SIGNAL_AS_OF in weights_dt)
prior_dates <- sort(unique(weights_dt$as_of_date[weights_dt$as_of_date < SIGNAL_AS_OF]))
if (length(prior_dates) > 0) {
  last_prior <- max(prior_dates)
  prior_w_dt <- weights_dt[as_of_date == last_prior & ticker != "CASH"]
  asof_prior_w <- setNames(prior_w_dt$weight, prior_w_dt$ticker)
} else {
  asof_prior_w <- NULL
}

asof_w <- switch(selected_cfg$method,
  "Linear_Tilt_lam1.0"        = linear_tilt_qd(asof_alpha_vec, lambda = 1.0, ub = asof_ub),
  "Linear_Tilt_lam0.5"        = linear_tilt_qd(asof_alpha_vec, lambda = 0.5, ub = asof_ub),
  "Linear_Tilt_lam0.3"        = linear_tilt_qd(asof_alpha_vec, lambda = 0.3, ub = asof_ub),
  "Linear_Tilt_lam1.0_NTB"    = {
    w0 <- linear_tilt_qd(asof_alpha_vec, lambda = 1.0, ub = asof_ub); names(w0) <- SIG_TICKERS
    if (!is.null(asof_prior_w))
      apply_no_trade_band(w0, asof_prior_w,
                            band_pct = selected_cfg$params$band_pct %||% 0.30,
                            band_abs = selected_cfg$params$band_abs %||% 0.01)
    else w0
  },
  "Linear_Tilt_lam1.0_TOphi3" = linear_tilt_to_penalty_qd(asof_alpha_vec, lambda = 1.0,
                                                            w_prev = asof_prior_w,
                                                            phi = 3.0, ub = asof_ub),
  "Linear_Tilt_lam1.0_TOphi8" = linear_tilt_to_penalty_qd(asof_alpha_vec, lambda = 1.0,
                                                            w_prev = asof_prior_w,
                                                            phi = 8.0, ub = asof_ub),
  "Score_Concentrated_top10"  = score_concentrated_qd(asof_alpha_vec, top_k = 10, ub = asof_ub),
  "HRP_alpha_overlay"         = hrp_alpha_overlay_qd(asof_alpha_vec, asof_Sigma,
                                                       lambda = 1.0, mix = 0.5, ub = asof_ub),
  "HRP_lw"                    = { w0 <- hrp_qd(asof_Sigma); names(w0) <- SIG_TICKERS; w0 },
  "Linear_Tilt_lam1.0_StickyTopK" = sticky_top_k_qd(asof_alpha_vec, w_prev = asof_prior_w,
                                                       top_k = 15, persistence_window = 5,
                                                       lambda = 1.0, ub = asof_ub),
  rep(1 / length(SIG_TICKERS), length(SIG_TICKERS))
)
asof_w <- normalize_long_only(asof_w, lb = 0, ub = asof_ub, target_sum = 1)
names(asof_w) <- SIG_TICKERS
asof_cash <- cash_overlay_pct(asof_regime)
asof_w_risk <- asof_w * (1 - asof_cash)

weights_dt <- weights_dt[as_of_date != SIGNAL_AS_OF]
asof_rows_new <- rbindlist(list(
  data.table(as_of_date = SIGNAL_AS_OF, ticker = SIG_TICKERS, weight = as.numeric(asof_w_risk),
              method_selected = selected_name, sleeve_id = "multi_sleeve_blend",
              regime = asof_regime, n_names = length(SIG_TICKERS),
              sigma_method = asof_sigma_method, cash_pct = asof_cash),
  if (asof_cash > 0) data.table(as_of_date = SIGNAL_AS_OF, ticker = "CASH", weight = asof_cash,
                                  method_selected = selected_name, sleeve_id = "cash_overlay",
                                  regime = asof_regime, n_names = length(SIG_TICKERS),
                                  sigma_method = asof_sigma_method, cash_pct = asof_cash) else NULL
))
weights_dt <- rbindlist(list(weights_dt, asof_rows_new), fill = TRUE)
setorder(weights_dt, as_of_date, -weight)

weights_dt[, method_selected := selected_name]
n_sig_dates_walkforward <- length(unique(weights_dt$as_of_date))
cat(sprintf("[Iter11] weights_dt: %d rows × %d sig_dates\n",
            nrow(weights_dt), n_sig_dates_walkforward))
stopifnot(n_sig_dates_walkforward >= 60L)

# ── Validation ──
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
stopifnot(max(val$maxw_cash) <= 0.30 + 1e-6)

# ────────────────────────────────────────────────────────────────────────
# 4. Build optimization_package_draft.json
# ────────────────────────────────────────────────────────────────────────
cat("\n[Iter11] Building optimization_package_draft.json ...\n")

asof_d <- max(weights_dt$as_of_date)
asof_rows <- weights_dt[as_of_date == asof_d]
target_weights <- setNames(as.list(asof_rows$weight), asof_rows$ticker)
asof_cash_pct_v <- asof_rows$cash_pct[1]

N_risk <- sum(asof_rows$ticker != "CASH")
bench_w_per <- (1 - asof_cash_pct_v) / N_risk
active_weights <- list()
for (i in seq_len(nrow(asof_rows))) {
  if (asof_rows$ticker[i] == "CASH") next
  active_weights[[asof_rows$ticker[i]]] <- asof_rows$weight[i] - bench_w_per
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
if (max(val$maxw_risk) > 0.20 - 1e-3) binding <- c(binding, "weight_bound_upper_020")
if (max(val$n_risk) >= 20L) binding <- c(binding, "max_names_20")
top_concentrated <- val[maxw_risk > 0.18, .N]
if (top_concentrated > length(unique(weights_dt$as_of_date)) * 0.5) {
  binding <- c(binding, "concentration_high_50pct_dates")
}
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
      sprintf("Of 10 candidates, %d pass turnover cap (≤%.0f%%), %d pass CVaR cap (≤%.1f%%).",
              to_pass_count, TURNOVER_HARD_CAP * 100, cvar_pass_count, CVAR_DAILY_CAP * 100),
      "Iter 11 monthly Linear Tilt mutation focuses on TO-cap-aware variants.",
      "If still breaching: (1) Score-Concentrated_top10 (smaller universe, less rebalance);",
      "(2) NTB widen band_pct 0.50/band_abs 0.02; (3) higher TO penalty phi=15+;",
      "(4) StickyTopK extend persistence_window=10."
    )
  )
}

regime_dist <- weights_dt[, .(n_dates = length(unique(as_of_date)),
                                avg_cash = mean(cash_pct)), by = regime]
cat("Regime distribution & cash overlay:\n"); print(regime_dist)

sigma_method_dist <- weights_dt[ticker != "CASH",
                                 .(n_obs = .N), by = sigma_method]
cat("Sigma method distribution:\n"); print(sigma_method_dist)

ow_top <- asof_rows[ticker != "CASH"][order(-weight)][1:5, .(ticker, weight)]
uw_bot <- asof_rows[ticker != "CASH"][order(weight)][1:5, .(ticker, weight)]
hhi_asof <- sum(asof_rows[ticker != "CASH"]$weight^2)

# Portfolio beta
em <- as.data.table(read_parquet(file.path(SRC_ART_DIR, "exposure_matrix.parquet")))
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

pg2_jaccard_proxy <- alpha_pkg$crowding_check$cross_section_jaccard_iter3 %||% NA

multi_sleeve_weights <- list(
  Core = round(0.65 * (1 - asof_cash_pct_v), 4),
  Defense = round(0.35 * (1 - asof_cash_pct_v), 4),
  Cash = round(asof_cash_pct_v, 4)
)

# HRP_lw_baseline reference
hrp_baseline_eval <- eval_results[["HRP_lw_baseline"]]
hrp_compare <- list()
if (isTRUE(hrp_baseline_eval$ok)) {
  hrp_compare <- list(
    HRP_lw_baseline = list(
      net_ir = round(hrp_baseline_eval$net_ir, 4),
      sr_ann = round(hrp_baseline_eval$sr_ann, 4),
      cagr = round(hrp_baseline_eval$cagr, 4),
      mdd = round(hrp_baseline_eval$mdd, 4),
      ann_to = round(hrp_baseline_eval$ann_to, 4)
    ),
    selected_vs_baseline_net_ir_diff = round(selected_eval$net_ir - hrp_baseline_eval$net_ir, 4),
    selected_vs_baseline_sr_diff = round(selected_eval$sr_ann - hrp_baseline_eval$sr_ann, 4),
    selected_vs_baseline_cagr_diff = round(selected_eval$cagr - hrp_baseline_eval$cagr, 4),
    note = "Iter 11 baseline reference: HRP_lw monthly (no Iter 5 Quarterly rebal). Direct comparison: alpha-tilted vs Σ-only."
  )
}

opt_pkg_draft <- list(
  task_id = WT_ID,
  parent_task_id = PARENT_WT_ID,
  iter_label = "Iter 11 — Linear Tilt monthly (Optimizer-only mutation of Iter 5)",
  as_of_date = as.character(asof_d),
  signal_as_of = as.character(SIGNAL_AS_OF),
  selection_objective = "net_ir",
  rebalance_frequency = "monthly",
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
  expected_sr_ann = round(selected_eval$sr_ann, 4),
  turnover = round(selected_eval$ann_to, 4),
  estimated_cost = round(selected_eval$ann_cost, 4),
  binding_constraints = binding,
  infeasibility_report = infeas_report,
  method_selected = selected_name,
  method_config = list(
    method_function = selected_cfg$method,
    rebalance_every = 1L,
    granularity = "monthly",
    params = selected_cfg$params,
    confidence_used = FALSE,
    description = sprintf("Linear Tilt mutation: %s. Monthly granularity. TO-cap-aware variant selection.", selected_name)
  ),
  method_comparison = method_log,
  hrp_baseline_compare = hrp_compare,
  multi_sleeve_weights = multi_sleeve_weights,
  cash_overlay_policy = list(
    BULL = 0.00, NORMAL = 0.05, CAUTION = 0.15, CRISIS = 0.30,
    rationale = "AX-001 v2 conditional cash policy. Inherited from Iter 5."
  ),
  crisis_pooled_fallback = list(
    enforced = TRUE,
    regimes_using_pooled = c("CRISIS", "CAUTION"),
    rationale = "Risk Mgr binding rule. CRISIS regime cond=564 > 100, pooled cond=100."
  ),
  hhi_asof = round(hhi_asof, 4),
  portfolio_factor_exposures = port_betas,
  beta_audit_note = paste(
    sprintf("Port MKT beta=%.3f at as_of (Linear Tilt monthly).", port_betas$MKT),
    "Iter 11 Optimizer-only mutation: alpha + risk inherited from Iter 5.",
    "Discovery WT focuses on Linear-Tilt monthly TO-cap-aware viability."
  ),
  selected_weight_tail_audit = list(
    cvar95_monthly = round(selected_eval$cvar95_monthly, 5),
    cvar95_daily_proxy = round(selected_eval$cvar95_daily_proxy, 5),
    cvar_daily_cap = CVAR_DAILY_CAP,
    cvar_pass = isTRUE(selected_eval$cvar95_daily_proxy <= CVAR_DAILY_CAP),
    mdd = round(selected_eval$mdd, 4),
    method = "monthly_realized_returns_to_daily_proxy_via_sqrt21",
    note = "Walk-forward portfolio returns net 15bps × 2 round-trip × Σw=1, daily proxy = monthly / sqrt(21)."
  ),
  pg2_crowding_proxy = list(
    cross_section_jaccard_iter3 = pg2_jaccard_proxy,
    note = "Inherited from Iter 5. Direct PG2 TDC: Forge backtest stage."
  ),
  iter11_hypothesis_audit = list(
    user_hypothesis = "alpha rank 높을수록 weight ↑ → CAGR + SR ↑",
    qlead_quick_test_baseline = list(
      gross_EW_SR = 1.41,
      gross_Linear_lam1.0_SR = 1.62,
      net_Linear_lam1.0_SR = 1.4981,
      net_Linear_lam1.0_TO = 8.07,
      net_Linear_lam1.0_TO_cap_breach = TRUE
    ),
    iter11_walkforward_result = list(
      selected_method = selected_name,
      net_ir = round(selected_eval$net_ir, 4),
      sr_ann = round(selected_eval$sr_ann, 4),
      ann_to = round(selected_eval$ann_to, 4),
      to_cap_pass = selected_eval$ann_to <= TURNOVER_HARD_CAP,
      hypothesis_validated = if (selected_eval$ann_to <= TURNOVER_HARD_CAP) "VALIDATED_TO_PASS" else "TO_CAP_BREACH"
    ),
    note = "monthly granularity 유지하면서 TO < 600% PASS 가능 여부 검증. 10-method shopping log 참조."
  ),
  sequential_admission_scenarios = list(
    replacement = list(
      design = "100% Iter 11 replaces PG2",
      backtest_status = "TBD by Forge"
    ),
    integration_80_20 = list(
      design = "80% PG2 + 20% Iter 11 Linear Tilt monthly",
      backtest_status = "TBD by Forge"
    )
  ),
  explanation = list(
    top_overweights = ow_top$ticker,
    top_underweights = uw_bot$ticker,
    main_tradeoffs = c(
      sprintf("Selected = %s (net_IR=%.3f). Walk-forward over %d sig_dates.",
              selected_method, exp_ir, n_sig_dates_walkforward),
      sprintf("Linear Tilt monthly: alpha rank-based weight tilt, TO-cap-aware selection."),
      sprintf("Σw=1 (incl cash). max_names=%d/20 hard cap. weight_bounds [0, 0.20].",
              max(val$n_risk))
    ),
    pg2_baseline_note = "PG2 = STR_1631_SYN_05 80% + STR_1656_MLRA_M05 20%."
  ),
  hard_constraint_compliance = list(
    max_names_20 = list(enforced = TRUE, max_observed = max(val$n_risk),
                          note = "risk securities only; CASH is allocation overlay"),
    weight_bounds_0_020 = list(enforced = TRUE,
                                 max_observed_risk = round(max(val$maxw_risk), 4),
                                 min_observed_risk = round(min(val$minw_risk), 6),
                                 note = "applies to risk securities only (CASH cap = 0.30)"),
    cash_overlay_cap = list(enforced = TRUE, cap = 0.30,
                              max_observed_cash = round(max(val$maxw_cash), 4),
                              note = "AX-001 v2 conditional cash"),
    long_only = list(enforced = TRUE, min_weight_observed = round(min(val$minw_risk), 6)),
    sum_w_1 = list(enforced = TRUE, max_abs_error = round(sum_err, 8),
                     note = "Σw across risk + CASH = 1"),
    turnover_hard_cap = list(cap = TURNOVER_HARD_CAP, observed = round(selected_eval$ann_to, 4),
                              pass = selected_eval$ann_to <= TURNOVER_HARD_CAP,
                              note = "Discovery WT cap. Iter 3 violation lesson encoded."),
    cvar_daily_cap = list(cap = CVAR_DAILY_CAP, observed = round(selected_eval$cvar95_daily_proxy, 5),
                            pass = selected_eval$cvar95_daily_proxy <= CVAR_DAILY_CAP,
                            note = "Risk handoff binding rule.")
  ),
  pit_compliance = list(
    C1 = "PASS — expanding-window LW shrinkage per sig_date",
    C2 = "PASS — alpha at sig_date d → weights at sig_date d",
    C9 = "PASS — regime_state inherited from Iter 5 PIT-safe",
    C11 = "PASS — KR internal regime, no FRED leakage",
    C13 = "PASS — Z_Score_Aligned alpha inherited",
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

draft_path <- file.path(WT_DIR, "optimization_package_draft.json")
write_json(opt_pkg_draft, draft_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[Iter11] optimization_package_draft.json written: %s\n", draft_path))

# Save weights.csv (mailbox + stage_artifacts)
weights_csv <- weights_dt[, .(as_of_date, ticker, weight, method_selected, sleeve_id,
                                regime, n_names, sigma_method, cash_pct)]
fwrite(weights_csv, file.path(WT_DIR, "weights.csv"))
fwrite(weights_csv, file.path(ART_DIR, "weights.csv"))
cat(sprintf("[Iter11] weights.csv written (%d rows × %d sig_dates) to mailbox + stage\n",
            nrow(weights_csv), n_sig_dates_walkforward))

saveRDS(list(
  weights_dt = weights_dt,
  comp = comp,
  eval_results = eval_results,
  selected_method = selected_method,
  selected_eval = selected_eval,
  opt_pkg_draft = opt_pkg_draft,
  sig_dates_use = sig_dates_use
), file.path(ART_DIR, "optimizer_workspace_iter11.rds"))

cat("\n[Iter11] DRAFT phase complete. Codex round expected next.\n")
cat(sprintf("  selected_method=%s\n  n_sig_dates_walkforward=%d\n  net_IR=%.3f\n  SR_ann=%.3f\n  CAGR=%.2f%%\n  MDD=%.2f%%\n  TO=%.0f%%\n  HHI_asof=%.4f\n",
            selected_method, n_sig_dates_walkforward, exp_ir, selected_eval$sr_ann,
            selected_eval$cagr * 100, selected_eval$mdd * 100,
            selected_eval$ann_to * 100, hhi_asof))
