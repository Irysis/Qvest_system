#==============================================================================
# robust_opt.R — Robust portfolio optimization (FRM Pfaff Ch10)
#
# Algorithm reference:
#   - Pfaff (Financial Risk Modeling, 2016, Wiley) Ch10 "Robust portfolio
#     optimization" (estimation uncertainty via robust covariance estimators).
#   - Robust covariance: Rousseeuw MCD / MVE (cov.rob, MASS, GPL-2),
#     Ledoit-Wolf shrinkage (corpcor::cov.shrink, GPL-3).
#   - Quadratic programming: Goldfarb-Idnani (quadprog::solve.QP, GPL-2).
#
# Role: textbook-method PoC — alternative covariance + min-variance solver
#       with weight-stability bootstrap. Diagnostic / sanity-check use only,
#       NOT a replacement for Optimizer Agent's HRP/MVO/CVaR pipeline.
#       (AX-002 / Charter §8: this module does not file optimization_package.)
#
# Charter v1.5 conformance:
#   - Long-only Σw=1 + max-weight cap default 0.20 (matches 20-stock hard).
#   - PerformanceAnalytics-compatible (returns input is monthly/daily ret matrix).
#   - 한글 경로 normalize 금지 (이 모듈은 path 미사용).
#
# Usage:
#   source("02_Infrastructure/portfolio/textbook_methods/robust_opt.R")
#   res <- robust_portfolio(returns_mat, method = "MCD",
#                            constraints = list(max_w = 0.20, long_only = TRUE))
#==============================================================================

suppressPackageStartupMessages({
  ok_mass     <- requireNamespace("MASS",     quietly = TRUE)
  ok_corpcor  <- requireNamespace("corpcor",  quietly = TRUE)
  ok_quadprog <- requireNamespace("quadprog", quietly = TRUE)
  if (ok_mass)     library(MASS)
  if (ok_corpcor)  library(corpcor)
  if (ok_quadprog) library(quadprog)
})

if (!ok_quadprog) {
  stop("[robust_opt] quadprog package required (CRAN, GPL-2). Install: install.packages('quadprog')")
}

#' Robust covariance estimator dispatcher
#'
#' Methods:
#'   - "MCD"       : Minimum Covariance Determinant (MASS::cov.rob method='mcd')
#'   - "MVE"       : Minimum Volume Ellipsoid     (MASS::cov.rob method='mve')
#'   - "shrinkage" : Ledoit-Wolf identity-target shrinkage (corpcor::cov.shrink)
#'   - "OLS"       : Sample covariance (base::cov)
#'
#' @param returns numeric matrix (T × N)
#' @param method character
#' @return N×N covariance matrix (named)
.robust_cov <- function(returns, method) {
  method <- match.arg(method, c("MCD", "MVE", "shrinkage", "OLS"))
  cm <- switch(
    method,
    "MCD" = {
      if (!ok_mass) stop("MASS missing for MCD")
      MASS::cov.rob(returns, method = "mcd")$cov
    },
    "MVE" = {
      if (!ok_mass) stop("MASS missing for MVE")
      MASS::cov.rob(returns, method = "mve")$cov
    },
    "shrinkage" = {
      if (!ok_corpcor) stop("corpcor missing for shrinkage")
      cs <- corpcor::cov.shrink(returns, verbose = FALSE)
      # cov.shrink returns object with attr(,'lambda'); coerce to plain matrix
      mat <- matrix(as.numeric(cs), nrow = ncol(returns), ncol = ncol(returns))
      colnames(mat) <- rownames(mat) <- colnames(returns)
      mat
    },
    "OLS" = stats::cov(returns)
  )
  # Ensure numeric, named, symmetric
  cm <- (cm + t(cm)) / 2
  if (is.null(colnames(cm))) colnames(cm) <- colnames(returns)
  if (is.null(rownames(cm))) rownames(cm) <- colnames(returns)
  cm
}

#' Solve min-variance with constraints (long-only + Σw=1 + max-weight cap)
#'
#' Goldfarb-Idnani QP:
#'   minimize    (1/2) w' (2 Σ) w - 0' w
#'   subject to  Σw = 1,    w >= 0,    -w >= -max_w
#'
#' @param Sigma N×N covariance
#' @param max_w scalar (per-asset weight cap)
#' @param long_only logical
#' @return numeric weight vector (length N)
.solve_min_var_qp <- function(Sigma, max_w = 0.20, long_only = TRUE) {
  N <- ncol(Sigma)
  # PSD safeguard: tiny ridge if min eigen < 0
  ev <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  if (min(ev) < 1e-10) {
    Sigma <- Sigma + diag(max(1e-10 - min(ev), 1e-10), N)
  }
  Dmat <- 2 * Sigma
  dvec <- rep(0, N)

  # Σw = 1 (eq)
  Aeq <- matrix(1, nrow = N, ncol = 1)
  beq <- 1
  # w >= 0 (long_only)
  if (long_only) {
    Aineq_lo <- diag(N)
    bineq_lo <- rep(0, N)
  } else {
    Aineq_lo <- matrix(0, nrow = N, ncol = 0)
    bineq_lo <- numeric(0)
  }
  # -w >= -max_w  (equiv: w <= max_w)
  Aineq_up <- -diag(N)
  bineq_up <- rep(-max_w, N)

  Amat <- cbind(Aeq, Aineq_lo, Aineq_up)
  bvec <- c(beq, bineq_lo, bineq_up)
  meq  <- 1L

  res <- tryCatch(
    quadprog::solve.QP(Dmat = Dmat, dvec = dvec, Amat = Amat, bvec = bvec, meq = meq),
    error = function(e) {
      # Fallback: 1/N
      list(solution = rep(1 / N, N), status = "fallback_equal_weight",
           error = conditionMessage(e))
    }
  )
  w <- res$solution
  # Numerical cleanup: clamp tiny negatives, renormalize
  w[w < 1e-8] <- 0
  if (sum(w) > 0) w <- w / sum(w)
  names(w) <- colnames(Sigma)
  w
}

#' Bootstrap weight stability
#'
#' Resample T rows with replacement B times, refit Σ + solve min-var,
#' return per-asset weight standard deviation.
#'
#' @param returns T×N matrix
#' @param method covariance method
#' @param max_w max-weight cap
#' @param B integer bootstrap reps
#' @return list(weight_sd, mean_weights, B)
.bootstrap_stability <- function(returns, method, max_w = 0.20, B = 100L) {
  T_obs <- nrow(returns)
  N <- ncol(returns)
  W <- matrix(NA_real_, nrow = B, ncol = N)
  for (b in seq_len(B)) {
    idx <- sample.int(T_obs, T_obs, replace = TRUE)
    rb <- returns[idx, , drop = FALSE]
    Sb <- tryCatch(.robust_cov(rb, method), error = function(e) NULL)
    if (is.null(Sb)) next
    wb <- tryCatch(.solve_min_var_qp(Sb, max_w = max_w), error = function(e) NULL)
    if (!is.null(wb)) W[b, ] <- wb
  }
  mean_w <- colMeans(W, na.rm = TRUE)
  sd_w   <- apply(W, 2L, sd, na.rm = TRUE)
  # Single-number stability score: 1 / (1 + mean weight std), higher = more stable
  stability_score <- 1 / (1 + mean(sd_w, na.rm = TRUE))
  list(
    weight_sd       = sd_w,
    mean_weights    = mean_w,
    B               = B,
    stability_score = stability_score
  )
}

#' Estimated Tracking Error and Information Ratio
#'
#' If alpha (expected returns) is supplied, IR = E[α'w] / sqrt(w'Σw).
#' Otherwise returns NA.
#'
#' @param w numeric weights
#' @param Sigma N×N
#' @param alpha numeric or NULL
#' @param freq integer (12 monthly, 252 daily)
#' @return list(te_ann, ir_ann, port_var)
.estimated_te_ir <- function(w, Sigma, alpha = NULL, freq = 12L) {
  port_var <- as.numeric(t(w) %*% Sigma %*% w)
  te_ann   <- sqrt(max(port_var, 0)) * sqrt(freq)
  ir_ann   <- NA_real_
  if (!is.null(alpha) && length(alpha) == length(w)) {
    expected_ret <- as.numeric(t(alpha) %*% w)
    ir_ann <- (expected_ret * freq) / te_ann
  }
  list(port_var = port_var, te_ann = te_ann, ir_ann = ir_ann)
}

#' Robust portfolio construction (main entry point)
#'
#' @param returns numeric matrix (T × N)
#' @param method  one of "MCD", "MVE", "shrinkage", "OLS"
#' @param constraints list(max_w = 0.20, long_only = TRUE)
#' @param alpha numeric (optional, for IR estimation)
#' @param freq integer (12 monthly, 252 daily)
#' @param bootstrap_B integer (0 to skip; default 100)
#' @return list with components (per Phase 5.2 spec):
#'   target_weights         : named numeric weights
#'   cov_estimate           : N×N
#'   cov_method             : method label
#'   condition_number       : kappa(Σ)
#'   estimated_TE           : annualized tracking error (scalar)
#'   estimated_IR           : information ratio (scalar, NA if alpha missing)
#'   weight_stability_score : 1/(1+mean(w_sd)) from bootstrap
#'   bootstrap              : list(weight_sd, mean_weights, B)
#'
#' @export
robust_portfolio <- function(returns,
                              method = c("MCD", "MVE", "shrinkage", "OLS"),
                              constraints = list(max_w = 0.20, long_only = TRUE),
                              alpha = NULL,
                              freq = 12L,
                              bootstrap_B = 100L) {

  method <- match.arg(method)
  if (!is.matrix(returns)) returns <- as.matrix(returns)
  if (any(is.na(returns))) {
    keep <- complete.cases(returns)
    returns <- returns[keep, , drop = FALSE]
  }
  if (nrow(returns) < 30) {
    stop(sprintf("robust_portfolio: too few rows (T=%d, need >=30)", nrow(returns)))
  }
  if (is.null(constraints$max_w))     constraints$max_w     <- 0.20
  if (is.null(constraints$long_only)) constraints$long_only <- TRUE

  # 1. Robust covariance
  Sigma <- .robust_cov(returns, method)

  # 2. Condition number
  ev <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  cond_num <- if (min(ev) > 0) max(ev) / min(ev) else Inf

  # 3. Min-variance QP with constraints
  w <- .solve_min_var_qp(
    Sigma,
    max_w     = constraints$max_w,
    long_only = constraints$long_only
  )

  # 4. TE / IR
  te_ir <- .estimated_te_ir(w, Sigma, alpha = alpha, freq = freq)

  # 5. Bootstrap weight stability
  if (bootstrap_B > 0) {
    boot <- .bootstrap_stability(returns, method,
                                  max_w = constraints$max_w,
                                  B = bootstrap_B)
  } else {
    boot <- list(weight_sd = NA, mean_weights = NA, B = 0L,
                 stability_score = NA_real_)
  }

  out <- list(
    target_weights         = w,
    cov_estimate           = Sigma,
    cov_method             = method,
    condition_number       = as.numeric(cond_num),
    min_eigenvalue         = as.numeric(min(ev)),
    estimated_TE           = te_ir$te_ann,
    estimated_IR           = te_ir$ir_ann,
    portfolio_variance     = te_ir$port_var,
    weight_stability_score = boot$stability_score,
    bootstrap              = boot,
    constraints            = constraints,
    n_obs                  = nrow(returns),
    n_assets               = ncol(returns),
    pfaff_reference        = "FRM Ch10 Robust Portfolio Optimization"
  )
  class(out) <- c("robust_portfolio", "list")
  out
}

#' Print compact summary
#' @export
print.robust_portfolio <- function(x, ...) {
  cat("[robust_opt] Robust Portfolio Summary\n")
  cat(sprintf("  method            : %s\n", x$cov_method))
  cat(sprintf("  T x N             : %d x %d\n", x$n_obs, x$n_assets))
  cat(sprintf("  condition_number  : %.2f\n", x$condition_number))
  cat(sprintf("  min_eigenvalue    : %.6f\n", x$min_eigenvalue))
  cat(sprintf("  port variance     : %.6e\n", x$portfolio_variance))
  cat(sprintf("  TE (annualized)   : %.4f\n", x$estimated_TE))
  if (!is.na(x$estimated_IR)) {
    cat(sprintf("  IR (annualized)   : %.4f\n", x$estimated_IR))
  }
  cat(sprintf("  stability_score   : %.4f (B=%d bootstrap)\n",
              x$weight_stability_score, x$bootstrap$B))
  cat("  weights (top 5):\n")
  ordw <- sort(x$target_weights, decreasing = TRUE)
  for (i in seq_len(min(5L, length(ordw)))) {
    cat(sprintf("    %s: %.4f\n", names(ordw)[i], ordw[i]))
  }
  invisible(x)
}

cat("[robust_opt] Loaded. quadprog =", ok_quadprog,
    "MASS =", ok_mass, "corpcor =", ok_corpcor, "\n")
