#==============================================================================
# QEPM Mean-Variance Optimizer — v2.0 (v6.1 R4 Confidence-aware)
# 2026-04-23 v1.0 정통 MVO 복원
# 2026-04-24 v2.0 — Confidence-aware + ForecastUncertaintyPenalty
#
# 목적함수 (v2.0):
#   max x'α̃ - (λ/2) x'Σx - φ·TC(x) - ψ·FU(x, c)
#   where α̃_i = c_i · α̂_i (confidence scaled)
#         FU(x, c) = Σ_i x_i² (1-c_i)² (low confidence 집중 penalty)
#   subject to 1'x = 1 (absolute) or 1'x = 0 (active)
#
# v6.1 R4 개선:
#   - Alpha confidence가 weight 결정에 수학적 반영
#   - 불안정 alpha (낮은 c)에는 집중 penalty
#==============================================================================

suppressPackageStartupMessages({
  library(quadprog)
  library(data.table)
})

# ─── MVO Confidence-aware 구현 (v2.0) ────────────────────
# Inputs:
#   alpha: named vector (Ticker → expected active return)
#   confidence: named vector (Ticker → confidence [0,1]), optional
#   cov_matrix: symmetric PD matrix (Ticker × Ticker)
#   lambda: risk-aversion (default 1.0)
#   psi: forecast uncertainty penalty (default 0.3; 0 = disable)
#   bounds: c(min_w, max_w) = c(0, 0.20)
#   max_names: hard cap (default 20)
#   current_weights: named vector (for turnover penalty)
#   turnover_penalty: φ (default 0.0)
#   active: TRUE = active (Σw=0) / FALSE = absolute (Σw=1)
#
# v6.1 R4: confidence NULL이면 1.0으로 취급 (backward compat)
mvo_weights <- function(alpha,
                         cov_matrix,
                         confidence = NULL,
                         lambda = 1.0,
                         psi = 0.3,
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

  # Confidence vector (v6.1 R4)
  if (is.null(confidence)) {
    c_vec <- rep(1.0, D)
  } else {
    c_vec <- confidence[common]
    c_vec[is.na(c_vec)] <- 0.5  # missing → neutral
    c_vec <- pmax(pmin(c_vec, 1.0), 0.0)  # [0, 1] clip
  }
  names(c_vec) <- common

  # α̃_i = c_i · α̂_i (confidence-scaled alpha)
  alpha_tilde <- c_vec * alpha_vec

  # Forecast Uncertainty Penalty: FU(x, c) = Σ_i x_i² (1-c_i)²
  # Quadratic form: x' diag((1-c)²) x
  # → adds to Dmat: + 2·ψ·diag((1-c)²) (because 1/2 x'Dmat x convention)
  fu_diag <- psi * (1 - c_vec)^2

  # quadprog formulation:
  #   min  (1/2) x'Dmat x - d_vec'x
  # MVO v2: max x'α̃ - (λ/2) x'Σx - ψ·x' diag((1-c)²) x
  #  ⇔ min (1/2) x'(λΣ + 2·ψ·diag((1-c)²))x - α̃'x
  Dmat <- lambda * Sigma + diag(2 * fu_diag)
  dvec <- as.vector(alpha_tilde)

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
    method = sprintf("MVO_lambda_%.2f_psi_%.2f_phi_%.2f",
                     lambda, psi, turnover_penalty),
    expected_active_return = exp_ar,
    expected_tracking_error = exp_te,
    expected_information_ratio = if (exp_te > 1e-6) exp_ar / exp_te else NA,
    n_names = length(w_out),
    confidence_used = !is.null(confidence),
    mean_confidence = mean(c_vec[names(w_out)]),
    infeasible = FALSE,
    reason = NULL,
    selection_objective = "net_ir"  # R4 P3: Optimizer는 net_ir로 선택
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

cat("[mean_variance_optimizer.R] v2.0 Confidence-aware Loaded. Functions:\n")
cat("  mvo_weights(alpha, cov_matrix, confidence=NULL, lambda=1.0, psi=0.3, bounds=c(0,0.20), max_names=20)\n")
cat("  mvo_grid_search(alpha, cov_matrix, lambda_grid, phi_grid)\n")
