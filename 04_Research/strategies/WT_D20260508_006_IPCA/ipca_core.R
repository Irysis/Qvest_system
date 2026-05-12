#==============================================================================
# IPCA — Instrumented Principal Component Analysis (Kelly-Pruitt-Su 2019 JFE)
#
# Reference: Kelly, Pruitt, Su (2019) "Characteristics are Covariances: A
#   Unified Model of Risk and Return" Journal of Financial Economics 134.
#
# Model:
#   r_{i,t+1} = α_i + β_{i,t}' f_{t+1} + ε_{i,t+1}
#   β_{i,t} = z_{i,t}' Γ_β    (characteristics → factor exposure)
#   α_i (restricted=0) or α_i = z_{i,t}' Γ_α (unrestricted, mispricing)
#
# Estimation: Alternating Least Squares
#   Step A (fix Γ): F_t = (Z_t Γ)^+ R_t
#   Step B (fix F): vec(Γ) = (Σ_t [Z_t' R_t F_t' ⊗ I]) ... regression of stacked
#                          Z_t' R_t on Z_t' Z_t F_t F_t'
#
# In matrix form (KPS 2019 Appendix A):
#   Step A: F_t = (Γ' Z_t' Z_t Γ)^{-1} Γ' Z_t' R_t
#   Step B: vec(Γ) = (Σ_t F_t F_t' ⊗ Z_t' Z_t)^{-1} Σ_t (F_t ⊗ Z_t') R_t
#
# Restricted (α=0) vs Unrestricted (Γ_β + Γ_α):
#   Unrestricted: stack [F_t; 1] and [Γ_β; Γ_α]
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(Matrix)
})

#' Estimate IPCA via Alternating Least Squares (KPS 2019 Appendix A)
#'
#' @param Z_list list of T matrices (N_t × L) — characteristics per period
#' @param R_list list of T vectors (N_t × 1) — returns per period
#' @param K integer — number of latent factors
#' @param max_iter integer — ALS iterations
#' @param tol numeric — convergence tolerance for ‖Γ_new - Γ_old‖_F
#' @param unrestricted bool — if TRUE estimate Γ_α intercept
#'
#' @return list(Gamma_beta=L×K, Gamma_alpha=L×1 or NULL, F=K×T, ...)
ipca_fit <- function(Z_list, R_list, K = 6L,
                     max_iter = 200L, tol = 1e-6,
                     unrestricted = FALSE,
                     verbose = TRUE,
                     seed = 42L) {

  T_periods <- length(Z_list)
  stopifnot(length(R_list) == T_periods)
  L <- ncol(Z_list[[1L]])

  K_eff <- if (unrestricted) K + 1L else K  # extra column for α intercept

  # ---- Initialization (random orthonormal Γ) ----
  set.seed(seed)
  Gamma <- matrix(rnorm(L * K_eff), L, K_eff)
  Gamma <- qr.Q(qr(Gamma))[, 1:K_eff, drop = FALSE]

  # Pre-compute Z_t' Z_t and Z_t' R_t
  ZtZ_list <- vector("list", T_periods)
  ZtR_list <- vector("list", T_periods)
  for (t in seq_len(T_periods)) {
    Z_t <- Z_list[[t]]
    R_t <- R_list[[t]]
    ZtZ_list[[t]] <- crossprod(Z_t)              # L × L
    ZtR_list[[t]] <- crossprod(Z_t, R_t)         # L × 1
  }

  prev_loss <- Inf
  conv_iter <- NA_integer_

  F_mat <- matrix(0, K_eff, T_periods)

  for (iter in seq_len(max_iter)) {

    # ---- Step A: F_t = (Γ' Z_t' Z_t Γ)^{-1} Γ' Z_t' R_t ----
    for (t in seq_len(T_periods)) {
      A <- t(Gamma) %*% ZtZ_list[[t]] %*% Gamma   # K × K
      b <- t(Gamma) %*% ZtR_list[[t]]             # K × 1
      # ridge fallback for numeric stability
      A_reg <- A + 1e-8 * diag(K_eff)
      F_mat[, t] <- as.numeric(solve(A_reg, b))
    }

    if (unrestricted) {
      # Force last row of F to 1 (intercept)
      F_mat[K_eff, ] <- 1
    }

    # ---- Step B: vec(Γ) = (Σ F F' ⊗ Z'Z)^{-1} (Σ (F ⊗ Z') R) ----
    # Sum kron components
    LHS <- matrix(0, L * K_eff, L * K_eff)
    RHS <- numeric(L * K_eff)

    for (t in seq_len(T_periods)) {
      ff <- tcrossprod(F_mat[, t, drop = FALSE])          # K × K
      LHS <- LHS + kronecker(ff, ZtZ_list[[t]])
      RHS <- RHS + as.numeric(kronecker(F_mat[, t, drop = FALSE], ZtR_list[[t]]))
    }

    LHS_reg <- LHS + 1e-8 * diag(L * K_eff)
    vec_G <- solve(LHS_reg, RHS)
    Gamma_new <- matrix(vec_G, L, K_eff)

    # ---- Identification: orthonormal Γ_β columns ----
    # KPS 2019 normalize: Γ' Γ = I_K, F has unit variance scaling
    # Use QR
    qr_dec <- qr(Gamma_new[, seq_len(K), drop = FALSE])
    Q <- qr.Q(qr_dec)
    R_q <- qr.R(qr_dec)
    Gamma_new[, seq_len(K)] <- Q
    # Adjust F accordingly: F_new = R · F_old (for K columns)
    F_mat[seq_len(K), ] <- R_q %*% F_mat[seq_len(K), , drop = FALSE]

    # convergence check
    delta <- sqrt(sum((Gamma_new - Gamma)^2))
    Gamma <- Gamma_new

    # loss
    loss <- 0
    for (t in seq_len(T_periods)) {
      r_hat <- Z_list[[t]] %*% Gamma %*% F_mat[, t, drop = FALSE]
      loss <- loss + sum((R_list[[t]] - as.numeric(r_hat))^2)
    }

    if (verbose && (iter %% 10L == 0L || iter == 1L)) {
      cat(sprintf("[ipca] iter=%d delta=%.4e loss=%.4f\n", iter, delta, loss))
    }

    rel_loss_change <- if (is.finite(prev_loss)) {
      abs(prev_loss - loss) / max(abs(prev_loss), 1)
    } else {
      Inf
    }
    if (delta < tol || (iter > 1L && rel_loss_change < tol)) {
      conv_iter <- iter
      if (verbose) cat(sprintf("[ipca] CONVERGED iter=%d delta=%.4e\n", iter, delta))
      break
    }
    prev_loss <- loss
  }

  # ---- Decompose Γ into Γ_β (first K cols) and Γ_α (last col if unrestricted) ----
  Gamma_beta  <- Gamma[, seq_len(K), drop = FALSE]
  Gamma_alpha <- if (unrestricted) Gamma[, K + 1L, drop = FALSE] else NULL

  list(
    Gamma_beta  = Gamma_beta,
    Gamma_alpha = Gamma_alpha,
    F           = F_mat[seq_len(K), , drop = FALSE],   # K × T (without intercept row)
    F_full      = F_mat,                               # K_eff × T
    K           = K,
    L           = L,
    T_periods   = T_periods,
    iter_used   = if (is.na(conv_iter)) max_iter else conv_iter,
    converged   = !is.na(conv_iter),
    final_loss  = prev_loss,
    unrestricted = unrestricted
  )
}


#' Compute in-sample R^2 (KPS 2019 total / predictive)
ipca_r2 <- function(fit, Z_list, R_list) {
  T_periods <- length(Z_list)
  ss_tot <- 0
  ss_res <- 0
  for (t in seq_len(T_periods)) {
    Z_t <- Z_list[[t]]
    R_t <- R_list[[t]]
    if (fit$unrestricted) {
      r_hat <- Z_t %*% fit$Gamma_beta %*% fit$F[, t, drop = FALSE] +
               Z_t %*% fit$Gamma_alpha   # Γ_α is L×1
    } else {
      r_hat <- Z_t %*% fit$Gamma_beta %*% fit$F[, t, drop = FALSE]
    }
    ss_tot <- ss_tot + sum(R_t^2)
    ss_res <- ss_res + sum((R_t - as.numeric(r_hat))^2)
  }
  list(total_r2 = 1 - ss_res / ss_tot, ss_res = ss_res, ss_tot = ss_tot)
}


#' Predict next-period α for stocks (cross-sectional alpha forecast)
#'
#' Two flavors:
#'  (a) "alpha-only" (KPS unrestricted): α̂_{i} = z_{i,t}' Γ_α
#'  (b) "expected_factor": α̂_{i,t+1} = z_{i,t}' Γ_β · E[F_{t+1}]
#'      where E[F] = sample mean of in-sample F
#'
#' We use (a) when unrestricted (mispricing alpha — orthogonal to β load).
#' This is closer to the "characteristics generate alpha not exposure" reading.
ipca_predict_alpha <- function(fit, Z_next, mode = c("alpha_only", "expected_factor")) {
  mode <- match.arg(mode)
  if (mode == "alpha_only") {
    if (is.null(fit$Gamma_alpha)) {
      stop("Gamma_alpha not estimated (run ipca_fit with unrestricted=TRUE)")
    }
    as.numeric(Z_next %*% fit$Gamma_alpha)
  } else {
    Ef <- rowMeans(fit$F)  # K × 1
    as.numeric(Z_next %*% fit$Gamma_beta %*% Ef)
  }
}

# ---- Convenience wrapper: build Z_list + R_list from long data.table ----
build_ipca_panels <- function(panel_dt,
                              date_col = "Date",
                              ticker_col = "Ticker",
                              ret_col = "Ret_Forward",
                              char_cols) {
  setDT(panel_dt)
  setorderv(panel_dt, c(date_col, ticker_col))
  dates <- sort(unique(panel_dt[[date_col]]))
  Z_list <- vector("list", length(dates))
  R_list <- vector("list", length(dates))
  ticker_list <- vector("list", length(dates))
  for (i in seq_along(dates)) {
    d <- dates[i]
    sub <- panel_dt[get(date_col) == d]
    sub <- sub[complete.cases(sub[, ..char_cols]) & !is.na(get(ret_col))]
    if (nrow(sub) < length(char_cols) + 5L) {
      Z_list[[i]] <- matrix(0, 0, length(char_cols))
      R_list[[i]] <- numeric(0)
      ticker_list[[i]] <- character(0)
      next
    }
    Z_list[[i]] <- as.matrix(sub[, ..char_cols])
    R_list[[i]] <- sub[[ret_col]]
    ticker_list[[i]] <- sub[[ticker_col]]
  }
  # drop empty periods
  ok <- vapply(Z_list, nrow, integer(1)) > 0
  list(
    Z_list = Z_list[ok],
    R_list = R_list[ok],
    ticker_list = ticker_list[ok],
    dates = dates[ok]
  )
}

cat("[ipca_core] loaded — ipca_fit / ipca_r2 / ipca_predict_alpha / build_ipca_panels\n")
