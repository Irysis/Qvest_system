#==============================================================================
# heuristic_opt.R — Heuristic optimization (Particle Swarm Optimization)
#                   NMF Gilli-Maringer Ch12
#
# Algorithm reference:
#   - Gilli, Maringer, Schumann (Numerical Methods and Optimization in Finance,
#     Academic Press 2011) Ch12 "Heuristic methods" — original Matlab.
#   - Kennedy & Eberhart (1995) Particle Swarm Optimization.
#   - R package: pso (CRAN, LGPL-3) primary; internal direct implementation
#     fallback when package unavailable. Internal version is a R reimplementation
#     of the Gilli-Maringer Matlab snippet.
#
# Role: textbook-method PoC — heuristic global solver for non-convex objectives
#       (e.g., negative-Sharpe with concentration penalty). Diagnostic /
#       sanity-check use; NOT a replacement for Optimizer Agent's HRP/MVO/CVaR.
#
# Charter v1.5 conformance:
#   - Pure deterministic seeds (n_seeds × replicate runs) for stability check.
#   - PerformanceAnalytics returns convention assumed where applicable
#     (caller supplies obj_fn closure).
#   - 한글 경로 normalize 금지 (이 모듈은 path 미사용).
#
# Usage:
#   source("02_Infrastructure/portfolio/textbook_methods/heuristic_opt.R")
#   res <- pso_optimize(obj_fn, lower, upper,
#                        n_particles = 50, n_iter = 1000, n_seeds = 10)
#==============================================================================

suppressPackageStartupMessages({
  ok_pso <- requireNamespace("pso", quietly = TRUE)
  if (ok_pso) library(pso)
})

if (!exists("ok_pso")) ok_pso <- FALSE

#' Internal PSO implementation (Kennedy-Eberhart 1995 / Gilli-Maringer Ch12)
#'
#' Standard inertia-weighted PSO with stagnation-aware termination.
#' Used as fallback when pso::psoptim is unavailable.
#'
#' Update rule per particle i, dimension d:
#'   v_id[t+1] = w*v_id[t] + c1*r1*(pbest_id - x_id[t]) + c2*r2*(gbest_d - x_id[t])
#'   x_id[t+1] = x_id[t] + v_id[t+1]
#'
#' @param obj_fn function(x) returning scalar (minimized)
#' @param lower numeric lower bounds (length D)
#' @param upper numeric upper bounds (length D)
#' @param n_particles integer
#' @param n_iter integer
#' @param w numeric inertia (0.7 default)
#' @param c1 numeric cognitive coef (1.5 default)
#' @param c2 numeric social coef (1.5 default)
#' @return list(par, value, convergence)
.pso_internal <- function(obj_fn, lower, upper,
                          n_particles = 50L, n_iter = 1000L,
                          w = 0.7, c1 = 1.5, c2 = 1.5) {
  D <- length(lower)
  v_max <- 0.2 * (upper - lower)

  # Initialize particles
  X <- matrix(NA_real_, nrow = n_particles, ncol = D)
  for (d in seq_len(D)) {
    X[, d] <- runif(n_particles, lower[d], upper[d])
  }
  V <- matrix(0, nrow = n_particles, ncol = D)

  # Personal best
  P_best  <- X
  P_value <- apply(X, 1L, function(p) tryCatch(obj_fn(p), error = function(e) Inf))

  # Global best
  g_idx   <- which.min(P_value)
  G_best  <- P_best[g_idx, ]
  G_value <- P_value[g_idx]

  conv_curve <- numeric(n_iter)

  for (t in seq_len(n_iter)) {
    r1 <- matrix(runif(n_particles * D), nrow = n_particles, ncol = D)
    r2 <- matrix(runif(n_particles * D), nrow = n_particles, ncol = D)

    # Velocity & position update
    V <- w * V + c1 * r1 * (P_best - X) + c2 * r2 *
         (matrix(G_best, nrow = n_particles, ncol = D, byrow = TRUE) - X)
    # Clamp velocity
    for (d in seq_len(D)) {
      V[, d] <- pmin(pmax(V[, d], -v_max[d]), v_max[d])
    }
    X <- X + V
    # Clamp position to bounds
    for (d in seq_len(D)) {
      X[, d] <- pmin(pmax(X[, d], lower[d]), upper[d])
    }

    # Evaluate
    new_value <- apply(X, 1L, function(p) tryCatch(obj_fn(p), error = function(e) Inf))

    # Update personal best
    improved <- new_value < P_value
    if (any(improved)) {
      P_best[improved, ]  <- X[improved, , drop = FALSE]
      P_value[improved]   <- new_value[improved]
    }

    # Update global best
    g_idx_new <- which.min(P_value)
    if (P_value[g_idx_new] < G_value) {
      G_best  <- P_best[g_idx_new, ]
      G_value <- P_value[g_idx_new]
    }

    conv_curve[t] <- G_value
  }

  list(par = G_best, value = G_value, convergence = conv_curve)
}

#' PSO with multi-seed averaging
#'
#' Runs n_seeds independent PSO runs with deterministic seeds and reports
#' best result + per-seed mean/sd of objective values (convergence stability).
#'
#' @param obj_fn function(x) returning scalar (minimized)
#' @param lower numeric lower bounds (length D)
#' @param upper numeric upper bounds (length D)
#' @param n_particles integer (default 50; Gilli-Maringer Ch12 typical)
#' @param n_iter integer (default 1000)
#' @param n_seeds integer (default 10)
#' @param backend character ("pso" or "internal" or "auto")
#' @return list (per Phase 5.3 spec):
#'   best_weights      : numeric (par at best seed)
#'   best_obj_value    : scalar
#'   convergence_curve : numeric of length n_iter (best seed)
#'   per_seed_results  : list with $values (n_seeds), $par_matrix
#'   per_seed_mean     : scalar (mean of best obj across seeds)
#'   per_seed_sd       : scalar (sd of best obj across seeds)
#'   backend           : actual backend used
#'
#' @export
pso_optimize <- function(obj_fn,
                          lower, upper,
                          n_particles = 50L,
                          n_iter      = 1000L,
                          n_seeds     = 10L,
                          backend     = c("auto", "pso", "internal")) {

  backend <- match.arg(backend)
  if (length(lower) != length(upper)) stop("length(lower) != length(upper)")
  if (any(upper <= lower)) stop("upper must be > lower elementwise")
  D <- length(lower)

  use_pkg <- (backend == "pso") || (backend == "auto" && ok_pso)
  if (backend == "pso" && !ok_pso) {
    warning("pso package unavailable — falling back to internal PSO")
    use_pkg <- FALSE
  }

  per_seed_values <- numeric(n_seeds)
  per_seed_pars   <- matrix(NA_real_, nrow = n_seeds, ncol = D)
  conv_curves     <- vector("list", n_seeds)

  for (s in seq_len(n_seeds)) {
    set.seed(s * 100L)
    if (use_pkg) {
      res <- tryCatch(
        pso::psoptim(
          par     = rep(NA_real_, D),
          fn      = obj_fn,
          lower   = lower,
          upper   = upper,
          control = list(
            maxit = n_iter,
            s     = n_particles,
            trace = 0L,
            REPORT = NA,
            trace.stats = TRUE
          )
        ),
        error = function(e) NULL
      )
      if (is.null(res)) {
        # fallback
        res <- .pso_internal(obj_fn, lower, upper, n_particles, n_iter)
      } else {
        # pso::psoptim with trace.stats=TRUE puts $stats$f (trace) — extract best so far
        if (!is.null(res$stats) && !is.null(res$stats$f)) {
          # res$stats$f is per-iteration mean fitness vector — use cumulative min as conv
          cm <- cummin(res$stats$f)
          # pad to n_iter length
          if (length(cm) < n_iter) cm <- c(cm, rep(tail(cm, 1), n_iter - length(cm)))
          if (length(cm) > n_iter) cm <- cm[seq_len(n_iter)]
          res$convergence <- cm
        } else {
          res$convergence <- rep(res$value, n_iter)
        }
      }
    } else {
      res <- .pso_internal(obj_fn, lower, upper, n_particles, n_iter)
    }
    per_seed_values[s] <- res$value
    per_seed_pars[s, ] <- res$par
    conv_curves[[s]]   <- res$convergence
  }

  best_idx <- which.min(per_seed_values)
  best_par <- per_seed_pars[best_idx, ]
  best_val <- per_seed_values[best_idx]

  out <- list(
    best_weights      = best_par,
    best_obj_value    = best_val,
    convergence_curve = conv_curves[[best_idx]],
    per_seed_results  = list(
      values     = per_seed_values,
      par_matrix = per_seed_pars
    ),
    per_seed_mean     = mean(per_seed_values, na.rm = TRUE),
    per_seed_sd       = sd(per_seed_values, na.rm = TRUE),
    n_seeds           = n_seeds,
    n_iter            = n_iter,
    n_particles       = n_particles,
    D                 = D,
    backend           = if (use_pkg) "pso::psoptim" else "internal_kennedy_eberhart",
    gilli_reference   = "NMF Ch12 Heuristic Methods (PSO)"
  )
  class(out) <- c("pso_result", "list")
  out
}

#' Build a portfolio objective: negative Sharpe with simplex projection penalty
#'
#' Helper: given a returns matrix, produces a closure obj_fn(w) returning
#' -Sharpe(w'r). Weights are projected to simplex (Σw=1, w>=0) before evaluation,
#' with a penalty for large violations from the input box bounds.
#'
#' @param returns T×N matrix
#' @param freq integer (12 monthly, 252 daily)
#' @param penalty scalar (added per unit deviation from Σw=1)
#' @return closure function(w) -> scalar
make_neg_sharpe_obj <- function(returns, freq = 12L, penalty = 1e3) {
  if (!is.matrix(returns)) returns <- as.matrix(returns)
  N <- ncol(returns)
  function(w) {
    if (length(w) != N) return(Inf)
    # Project to simplex: clip negatives, renormalize
    w_proj <- pmax(w, 0)
    s <- sum(w_proj)
    if (s <= 0) return(Inf)
    w_proj <- w_proj / s
    # Penalize deviation from raw input sum (encourages PSO to land near simplex)
    deviation <- abs(sum(w) - 1)
    pr <- as.numeric(returns %*% w_proj)
    mu <- mean(pr) * freq
    sg <- sd(pr) * sqrt(freq)
    if (sg <= 0) return(Inf)
    -(mu / sg) + penalty * deviation
  }
}

#' Print compact summary
#' @export
print.pso_result <- function(x, ...) {
  cat("[heuristic_opt] PSO Optimization Summary\n")
  cat(sprintf("  backend          : %s\n", x$backend))
  cat(sprintf("  n_particles      : %d\n", x$n_particles))
  cat(sprintf("  n_iter           : %d\n", x$n_iter))
  cat(sprintf("  n_seeds          : %d\n", x$n_seeds))
  cat(sprintf("  best_obj_value   : %.6f\n", x$best_obj_value))
  cat(sprintf("  per_seed_mean    : %.6f\n", x$per_seed_mean))
  cat(sprintf("  per_seed_sd      : %.6f\n", x$per_seed_sd))
  cat(sprintf("  best_weights[1:%d]:\n", min(5, length(x$best_weights))))
  for (i in seq_len(min(5L, length(x$best_weights)))) {
    cat(sprintf("    [%d] %.4f\n", i, x$best_weights[i]))
  }
  invisible(x)
}

cat("[heuristic_opt] Loaded. backend =",
    if (ok_pso) "pso (psoptim available) + internal" else "internal only",
    "\n")
