#==============================================================================
# Regime HMM Signal — Expanding-Window 2-State Hidden Markov Model
#
# Author: Forge Agent
# Date:   2026-03-17
#
# Fits a 2-state Gaussian HMM (Normal, Stress) on monthly BM returns.
# STRICTLY expanding-window: for month M, fit HMM on months 1..(M-1).
# Uses filtered probability P(Stress) at the last observation (M-1).
#
# ZERO LOOKAHEAD:
#   - For month M: uses BM returns from months 1..(M-1) ONLY
#   - HMM parameters (mu, sigma, transition matrix) estimated via EM
#     on the expanding window 1..(M-1)
#   - Output: P(Stress at M-1) = filtered probability after observing r_{M-1}
#   - No data from month M or later enters the estimate
#   - Minimum training window: 36 months
#
# Implementation: Manual Baum-Welch EM (no depmixS4 dependency)
#   State 1 (Normal): initialized mu ~ +0.5%/mo, sigma ~ 4%
#   State 2 (Stress): initialized mu ~ -2.0%/mo, sigma ~ 8%
#   Transition matrix estimated from data
#
# USAGE:
#   source("02_Infrastructure/regime_hmm.R")
#   hmm_sig <- compute_hmm_signal(month_ends)
#==============================================================================

cat("[regime_hmm] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

.qvest_root <- function() {
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[regime_hmm] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- .qvest_root()
}
if (!exists("CACHE_DIR")) {
  CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
}


#==============================================================================
# HELPER: Gaussian density for HMM
#==============================================================================
.dnorm_safe <- function(x, mu, sigma) {
  # Numerically safe Gaussian log-density
  if (sigma < 1e-8) sigma <- 1e-8
  dnorm(x, mean = mu, sd = sigma)
}


#==============================================================================
# HELPER: Forward algorithm — returns filtered state probabilities
#==============================================================================
.hmm_forward <- function(returns, mu, sigma, A, pi0) {
  # returns: vector of T observations
  # mu: c(mu1, mu2), sigma: c(sigma1, sigma2)
  # A: 2x2 transition matrix A[i,j] = P(state j at t | state i at t-1)
  # pi0: initial state distribution c(p1, p2)
  #
  # Returns: matrix T x 2 of filtered probabilities P(state | y_1:t)

  T_len <- length(returns)
  alpha <- matrix(0, nrow = T_len, ncol = 2)

  # t = 1
  for (j in 1:2) {
    alpha[1, j] <- pi0[j] * .dnorm_safe(returns[1], mu[j], sigma[j])
  }
  s <- sum(alpha[1, ])
  if (s > 0) alpha[1, ] <- alpha[1, ] / s

  # t = 2..T
  for (t in 2:T_len) {
    for (j in 1:2) {
      alpha[t, j] <- sum(alpha[t - 1, ] * A[, j]) *
        .dnorm_safe(returns[t], mu[j], sigma[j])
    }
    s <- sum(alpha[t, ])
    if (s > 0) alpha[t, ] <- alpha[t, ] / s else alpha[t, ] <- c(0.5, 0.5)
  }

  alpha
}


#==============================================================================
# HELPER: Forward-Backward algorithm for EM
#==============================================================================
.hmm_forward_backward <- function(returns, mu, sigma, A, pi0) {
  T_len <- length(returns)

  # --- Forward (scaled) ---
  alpha <- matrix(0, nrow = T_len, ncol = 2)
  scale <- numeric(T_len)

  for (j in 1:2) {
    alpha[1, j] <- pi0[j] * .dnorm_safe(returns[1], mu[j], sigma[j])
  }
  scale[1] <- sum(alpha[1, ])
  if (scale[1] > 0) alpha[1, ] <- alpha[1, ] / scale[1]

  for (t in 2:T_len) {
    for (j in 1:2) {
      alpha[t, j] <- sum(alpha[t - 1, ] * A[, j]) *
        .dnorm_safe(returns[t], mu[j], sigma[j])
    }
    scale[t] <- sum(alpha[t, ])
    if (scale[t] > 0) alpha[t, ] <- alpha[t, ] / scale[t]
    else alpha[t, ] <- c(0.5, 0.5)
  }

  # --- Backward (scaled) ---
  beta <- matrix(0, nrow = T_len, ncol = 2)
  beta[T_len, ] <- 1

  for (t in (T_len - 1):1) {
    for (i in 1:2) {
      beta[t, i] <- sum(A[i, ] *
                           sapply(1:2, function(j) .dnorm_safe(returns[t + 1], mu[j], sigma[j])) *
                           beta[t + 1, ])
    }
    if (scale[t + 1] > 0) beta[t, ] <- beta[t, ] / scale[t + 1]
  }

  # --- Gamma (smoothed state probabilities) ---
  gamma <- alpha * beta
  gamma_sum <- rowSums(gamma)
  gamma_sum[gamma_sum == 0] <- 1
  gamma <- gamma / gamma_sum

  # --- Xi (transition probabilities) ---
  xi <- array(0, dim = c(T_len - 1, 2, 2))
  for (t in 1:(T_len - 1)) {
    denom <- 0
    for (i in 1:2) {
      for (j in 1:2) {
        xi[t, i, j] <- alpha[t, i] * A[i, j] *
          .dnorm_safe(returns[t + 1], mu[j], sigma[j]) * beta[t + 1, j]
        denom <- denom + xi[t, i, j]
      }
    }
    if (denom > 0) xi[t, , ] <- xi[t, , ] / denom
  }

  list(alpha = alpha, beta = beta, gamma = gamma, xi = xi,
       log_lik = sum(log(pmax(scale, 1e-300))))
}


#==============================================================================
# HELPER: Baum-Welch EM for 2-state Gaussian HMM
#==============================================================================
.hmm_em <- function(returns, max_iter = 100L, tol = 1e-6,
                    mu_init = c(0.005, -0.02),
                    sigma_init = c(0.04, 0.08)) {
  # Initialize
  mu <- mu_init
  sigma <- sigma_init
  A <- matrix(c(0.95, 0.05,
                0.10, 0.90), nrow = 2, byrow = TRUE)
  pi0 <- c(0.8, 0.2)

  prev_ll <- -Inf

  for (iter in 1:max_iter) {
    # E-step
    fb <- .hmm_forward_backward(returns, mu, sigma, A, pi0)
    gamma <- fb$gamma
    xi    <- fb$xi

    # Check convergence
    if (abs(fb$log_lik - prev_ll) < tol && iter > 5) break
    prev_ll <- fb$log_lik

    # M-step
    # Update pi0
    pi0 <- gamma[1, ]
    pi0 <- pmax(pi0, 1e-6)
    pi0 <- pi0 / sum(pi0)

    # Update transition matrix
    for (i in 1:2) {
      denom <- sum(gamma[1:(nrow(gamma) - 1), i])
      if (denom > 0) {
        for (j in 1:2) {
          A[i, j] <- sum(xi[, i, j]) / denom
        }
      }
    }
    # Ensure rows sum to 1
    for (i in 1:2) {
      rs <- sum(A[i, ])
      if (rs > 0) A[i, ] <- A[i, ] / rs
    }

    # Update emission parameters
    for (j in 1:2) {
      w <- gamma[, j]
      sw <- sum(w)
      if (sw > 1e-8) {
        mu[j] <- sum(w * returns) / sw
        sigma[j] <- sqrt(sum(w * (returns - mu[j])^2) / sw)
        sigma[j] <- max(sigma[j], 1e-4)  # floor
      }
    }

    # Label identification: ensure state 1 = higher mean (Normal)
    if (mu[1] < mu[2]) {
      mu <- rev(mu)
      sigma <- rev(sigma)
      A <- A[2:1, 2:1]
      pi0 <- rev(pi0)
      gamma <- gamma[, 2:1]
    }
  }

  list(mu = mu, sigma = sigma, A = A, pi0 = pi0,
       gamma = gamma, log_lik = prev_ll, n_iter = iter)
}


#==============================================================================
# MAIN: compute_hmm_signal
#==============================================================================
compute_hmm_signal <- function(month_ends = NULL) {

  cat("[regime_hmm] Computing HMM signal...\n")

  # --- Load BM daily, compute monthly returns ---
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)

  bm[, YM := format(Date, "%Y-%m")]
  bm_monthly <- bm[, .(
    close_last  = last(BM_Close),
    close_first = first(BM_Close),
    last_date   = max(Date)
  ), by = YM]
  bm_monthly[, ret := close_last / close_first - 1]
  setorder(bm_monthly, YM)

  # --- Determine month_ends ---
  if (is.null(month_ends)) {
    # Use calendar month-ends
    fom_seq <- seq.Date(ANALYSIS_START_DATE, max(bm$Date), by = "month")
    month_ends <- sort(unique(as.Date(sapply(fom_seq, function(d) {
      as.Date(format(d, "%Y-%m-01")) - 1
    }), origin = "1970-01-01")))
    month_ends <- month_ends[month_ends >= ANALYSIS_START_DATE - 1]
  }
  month_ends <- sort(as.Date(month_ends))

  cat(sprintf("  Month-ends: %d (%s ~ %s)\n",
              length(month_ends), min(month_ends), max(month_ends)))
  cat(sprintf("  Monthly BM returns: %d months available\n", nrow(bm_monthly)))

  # --- Map month_ends to YM ---
  # month_end = last day of month M-1 => apply to month M
  # For HMM: we use returns up through the month ENDING at month_end
  me_dt <- data.table(month_end = month_ends)
  me_dt[, signal_YM := format(month_end, "%Y-%m")]  # the month that ended

  # --- Expanding-window HMM ---
  MIN_TRAIN <- 36L
  n_me <- nrow(me_dt)

  me_dt[, p_stress  := NA_real_]
  me_dt[, hmm_state := NA_integer_]  # 1=Normal, 2=Stress

  # Get ordered list of all YMs with returns
  all_ym <- bm_monthly[!is.na(ret), YM]

  cat(sprintf("  Running expanding-window HMM (%d month-ends, min_train=%d)...\n",
              n_me, MIN_TRAIN))

  # Cache: track last fit to warm-start
  last_mu <- c(0.005, -0.02)
  last_sigma <- c(0.04, 0.08)

  for (i in seq_len(n_me)) {
    sig_ym <- me_dt$signal_YM[i]

    # Returns available up through signal_YM
    avail <- bm_monthly[YM <= sig_ym & !is.na(ret)]
    if (nrow(avail) < MIN_TRAIN) next

    returns <- avail$ret

    # Fit HMM via EM
    fit <- tryCatch(
      .hmm_em(returns, max_iter = 100L, tol = 1e-6,
              mu_init = last_mu, sigma_init = last_sigma),
      error = function(e) NULL
    )

    if (is.null(fit)) next

    # Update warm-start
    last_mu    <- fit$mu
    last_sigma <- fit$sigma

    # Get filtered probability at last observation
    filtered <- .hmm_forward(returns, fit$mu, fit$sigma, fit$A, fit$pi0)
    p_stress_val <- filtered[nrow(filtered), 2]  # state 2 = Stress

    me_dt[i, p_stress  := p_stress_val]
    me_dt[i, hmm_state := ifelse(p_stress_val > 0.5, 2L, 1L)]
  }

  # --- Summary ---
  valid <- me_dt[!is.na(p_stress)]
  cat(sprintf("\n[regime_hmm] Done: %d/%d months with predictions\n",
              nrow(valid), n_me))

  if (nrow(valid) > 0) {
    cat(sprintf("  p_stress: mean=%.3f, median=%.3f, max=%.3f\n",
                mean(valid$p_stress), median(valid$p_stress), max(valid$p_stress)))
    cat(sprintf("  State distribution: Normal=%d (%.0f%%), Stress=%d (%.0f%%)\n",
                sum(valid$hmm_state == 1),
                mean(valid$hmm_state == 1) * 100,
                sum(valid$hmm_state == 2),
                mean(valid$hmm_state == 2) * 100))
  }

  # --- Crisis check ---
  cat("\n  Crisis date signals:\n")
  crisis_dates <- as.Date(c("2008-08-31", "2020-01-31", "2022-06-30"))
  for (cd in crisis_dates) {
    cd <- as.Date(cd, origin = "1970-01-01")
    row <- me_dt[month_end == cd]
    if (nrow(row) == 0) {
      # Find closest month_end <= cd
      row <- me_dt[month_end <= cd]
      if (nrow(row) > 0) row <- row[.N]
    }
    if (nrow(row) > 0) {
      cat(sprintf("    %s (month_end=%s): p_stress=%.3f, state=%s\n",
                  as.character(cd), as.character(row$month_end[1]),
                  row$p_stress[1],
                  ifelse(row$hmm_state[1] == 2, "STRESS", "NORMAL")))
    } else {
      cat(sprintf("    %s: No data\n", as.character(cd)))
    }
  }

  # --- Output ---
  out <- me_dt[, .(month_end, p_stress, hmm_state)]
  setorder(out, month_end)

  cat("\n[regime_hmm] Loaded. Use compute_hmm_signal(month_ends)\n")
  out
}

cat("[regime_hmm] Loaded.\n")
