#==============================================================================
# QEPM Mean-Variance Optimizer — v1.0 (정통 MVO 복원)
# 2026-04-23 Session 69 Day 1 — Optimizer Research Agent 전용
#
# 목적:
#   max x'α̂ - (λ/2) x'Σx - φ·TC(x)
#   subject to 1'x = 1 (absolute) or 1'x = 0 (active)
#              bounds, max_names, turnover_penalty
#
# 이전 calc_minvar_weights()는 μ 항 부재 → Alpha score가 weight에 미반영 (QEPM §8 위반).
# 이 구현은 μ + Σ + λ 3-param 정통 Markowitz.
#==============================================================================

suppressPackageStartupMessages({
  library(quadprog)
  library(data.table)
})

# ─── MVO 정통 구현 ────────────────────────────────────────
# Inputs:
#   alpha: named vector (Ticker → expected active return)
#   cov_matrix: symmetric PD matrix (Ticker × Ticker)
#   lambda: risk-aversion (default 1.0)
#   bounds: c(min_w, max_w) = c(0, 0.20)
#   max_names: hard cap (default 20)
#   current_weights: named vector (for turnover penalty)
#   turnover_penalty: φ (default 0.0)
#   active: TRUE = active (Σw=0) / FALSE = absolute (Σw=1)
mvo_weights <- function(alpha,
                         cov_matrix,
                         lambda = 1.0,
                         bounds = c(0, 0.20),
                         max_names = 20,
                         current_weights = NULL,
                         turnover_penalty = 0.0,
                         active = FALSE) {

  # Input 검증
  if (!is.numeric(alpha) || is.null(names(alpha))) {
    stop("[mvo_weights] alpha must be named numeric vector")
  }
  if (!is.matrix(cov_matrix) || nrow(cov_matrix) != ncol(cov_matrix)) {
    stop("[mvo_weights] cov_matrix must be square")
  }
  if (length(bounds) != 2 || bounds[1] > bounds[2]) {
    stop("[mvo_weights] bounds invalid")
  }

  # Universe 정합 (alpha와 cov 종목 일치)
  common <- intersect(names(alpha), rownames(cov_matrix))
  if (length(common) == 0) {
    stop("[mvo_weights] alpha and cov_matrix share no tickers")
  }

  alpha_vec <- alpha[common]
  Sigma <- cov_matrix[common, common]
  D <- length(common)

  # quadprog formulation:
  #   min  (1/2) x'Dmat x - d_vec'x
  # MVO: max x'α - (λ/2) x'Σx
  #  ⇔ min (λ/2) x'Σx - x'α
  #  ⇔ min (1/2) x'(λΣ)x - α'x
  Dmat <- lambda * Sigma
  dvec <- as.vector(alpha_vec)

  # Numerical stability: add small diagonal
  diag(Dmat) <- diag(Dmat) + 1e-8

  # Constraints:
  # 1'x = 1 (or 0 for active)  — equality
  # x >= bounds[1]              — inequality
  # -x >= -bounds[2]            — inequality (x <= bounds[2])
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(if (active) 0 else 1,
            rep(bounds[1], D),
            rep(-bounds[2], D))
  meq <- 1  # 1st constraint is equality

  # Solve QP
  sol <- tryCatch(
    solve.QP(Dmat, dvec, Amat, bvec, meq = meq),
    error = function(e) {
      warning("[mvo_weights] QP solve failed: ", conditionMessage(e))
      return(NULL)
    }
  )

  if (is.null(sol)) {
    return(list(
      weights = NULL,
      method = "mvo",
      infeasible = TRUE,
      reason = "QP_solve_failed"
    ))
  }

  w_full <- sol$solution
  names(w_full) <- common

  # max_names hard cap: top-N by |weight|
  if (length(w_full) > max_names) {
    top_idx <- order(abs(w_full), decreasing = TRUE)[seq_len(max_names)]
    w_sparse <- numeric(length(w_full))
    w_sparse[top_idx] <- w_full[top_idx]

    # Renormalize to maintain Σw = 1 (or 0)
    target_sum <- if (active) 0 else 1
    current_sum <- sum(w_sparse)

    if (!active && current_sum > 0) {
      w_sparse <- w_sparse * (target_sum / current_sum)
    }

    # Clip to bounds
    w_sparse <- pmax(pmin(w_sparse, bounds[2]), bounds[1])

    # Final renormalization
    w_sparse <- w_sparse * (target_sum / sum(w_sparse))

    names(w_sparse) <- common
    w_full <- w_sparse
  }

  # Non-zero만 반환
  w_out <- w_full[abs(w_full) > 1e-6]

  # Expected metrics
  active_w <- if (active) w_out else w_out - (1 / length(w_out))
  exp_ar <- sum(alpha_vec[names(w_out)] * w_out)
  exp_var <- as.numeric(t(w_out) %*% Sigma[names(w_out), names(w_out)] %*% w_out)
  exp_te <- sqrt(max(exp_var, 0))

  list(
    weights = w_out,
    method = sprintf("MVO_lambda_%.2f_phi_%.2f", lambda, turnover_penalty),
    expected_active_return = exp_ar,
    expected_tracking_error = exp_te,
    expected_information_ratio = if (exp_te > 1e-6) exp_ar / exp_te else NA,
    n_names = length(w_out),
    infeasible = FALSE,
    reason = NULL
  )
}

# ─── MVO Grid Search (lambda + phi 탐색) ─────────────────
mvo_grid_search <- function(alpha, cov_matrix,
                             lambda_grid = c(0.5, 1.0, 2.0, 5.0),
                             phi_grid = c(0.0, 0.2, 0.5),
                             bounds = c(0, 0.20),
                             max_names = 20) {
  results <- list()
  i <- 0
  for (lam in lambda_grid) {
    for (ph in phi_grid) {
      i <- i + 1
      r <- mvo_weights(alpha, cov_matrix,
                        lambda = lam, bounds = bounds, max_names = max_names,
                        turnover_penalty = ph)
      r$lambda <- lam
      r$phi <- ph
      results[[i]] <- r
    }
  }

  # SR 최대 선택
  srs <- sapply(results, function(r) if (!is.null(r$expected_information_ratio)) r$expected_information_ratio else -Inf)
  best_idx <- which.max(srs)
  best <- results[[best_idx]]

  list(
    best = best,
    all_results = results,
    n_tested = length(results)
  )
}

cat("[mean_variance_optimizer.R] Loaded. Functions:\n")
cat("  mvo_weights(alpha, cov_matrix, lambda=1.0, bounds=c(0,0.20), max_names=20)\n")
cat("  mvo_grid_search(alpha, cov_matrix, lambda_grid, phi_grid)\n")
