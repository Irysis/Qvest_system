#==============================================================================
# evt_engine.R — Extreme Value Theory engine (FRM Pfaff Ch7)
#
# Algorithm reference: Pfaff (Financial Risk Modeling, 2016, Wiley)
#   - Ch7 Extreme Value Theory: GPD threshold (Peaks-Over-Threshold), Hill α,
#     mean residual life, parametric VaR/ES at high quantiles.
#   - R packages: fExtremes (CRAN, GPL-2) primary; evir (CRAN, GPL-2) fallback.
#
# Role: textbook-method PoC — supplements existing tail_risk_engine.R with a
#       formalized POT framework (3-threshold sensitivity grid). Diagnostic
#       only; does NOT modify alpha or weight artifacts (AX-002 separation).
#
# Charter v1.5 conformance:
#   - PerformanceAnalytics 표준 함수만 (no manual NAV synthesis).
#   - Returns input is consumed read-only; no PIT lookahead introduced.
#   - 한글 경로 normalize 금지 (이 모듈은 path 미사용).
#
# Usage:
#   source("02_Infrastructure/risk/textbook_methods/evt_engine.R")
#   res <- evt_analyze(returns_vec, threshold_quantiles = c(0.80, 0.90, 0.95))
#==============================================================================

suppressPackageStartupMessages({
  ok_fext <- requireNamespace("fExtremes", quietly = TRUE)
  ok_evir <- requireNamespace("evir", quietly = TRUE)
  if (ok_fext) library(fExtremes)
  if (!ok_fext && ok_evir) library(evir)
})

if (!exists("ok_fext")) ok_fext <- FALSE
if (!exists("ok_evir")) ok_evir <- FALSE

# Backend selector — fExtremes preferred (Pfaff's reference), evir fallback,
# else internal moment-method. Logged in result$backend.
.evt_backend <- function() {
  if (ok_fext) return("fExtremes")
  if (ok_evir) return("evir")
  "moment_method"
}

#' Hill tail-index estimator (manual fallback implementation)
#'
#' Hill (1975) maximum-likelihood estimator for tail index alpha.
#' alpha_hat = 1 / mean(log(X_(i)) - log(X_(k+1))) for i in 1..k
#' where X_(1) >= X_(2) >= ... are descending order statistics.
#'
#' @param losses numeric (positive losses)
#' @param k integer (number of upper order stats; default = floor(0.10 * n))
#' @return list(alpha, k, n)
.hill_estimator_manual <- function(losses, k = NULL) {
  losses <- losses[!is.na(losses) & losses > 0]
  n <- length(losses)
  if (n < 30) return(list(alpha = NA_real_, k = NA_integer_, n = n))
  if (is.null(k)) k <- max(20L, floor(0.10 * n))
  k <- min(k, n - 1L)
  ord <- sort(losses, decreasing = TRUE)
  log_excess <- log(ord[1:k]) - log(ord[k + 1L])
  alpha_hat <- 1 / mean(log_excess)
  list(alpha = as.numeric(alpha_hat), k = as.integer(k), n = as.integer(n))
}

#' Mean residual life function (for threshold diagnostic plot)
#'
#' MRL(u) = E[X - u | X > u]. Linearity above some u suggests GPD applicability.
#'
#' @param losses numeric (positive losses)
#' @param n_grid integer (grid points)
#' @return data.frame(threshold, mean_excess, n_above, ci_lower, ci_upper)
.mean_residual_life <- function(losses, n_grid = 30L) {
  losses <- losses[!is.na(losses)]
  q_grid <- seq(0.50, 0.98, length.out = n_grid)
  out <- data.frame(
    threshold   = numeric(n_grid),
    mean_excess = numeric(n_grid),
    n_above     = integer(n_grid),
    ci_lower    = numeric(n_grid),
    ci_upper    = numeric(n_grid)
  )
  for (i in seq_len(n_grid)) {
    u  <- as.numeric(quantile(losses, q_grid[i], na.rm = TRUE))
    ex <- losses[losses > u] - u
    n_above <- length(ex)
    if (n_above >= 5) {
      m  <- mean(ex)
      se <- sd(ex) / sqrt(n_above)
      out$threshold[i]   <- u
      out$mean_excess[i] <- m
      out$n_above[i]     <- n_above
      out$ci_lower[i]    <- m - 1.96 * se
      out$ci_upper[i]    <- m + 1.96 * se
    } else {
      out$threshold[i]   <- u
      out$mean_excess[i] <- NA_real_
      out$n_above[i]     <- n_above
      out$ci_lower[i]    <- NA_real_
      out$ci_upper[i]    <- NA_real_
    }
  }
  out
}

#' GPD fit at single threshold (Pfaff Ch7, fExtremes::gpdFit)
#'
#' Fits Generalized Pareto Distribution (xi, beta) to excesses over u.
#' VaR_q  = u + (beta/xi) * ((n/n_excess * (1-q))^(-xi) - 1)
#' ES_q   = (VaR_q + beta - xi*u) / (1 - xi)   [for xi < 1]
#'
#' @param losses numeric (positive losses)
#' @param threshold scalar (u)
#' @return list(threshold, xi, beta, n_excesses, var_99, es_99, var_995, es_995, method)
.gpd_fit_single <- function(losses, threshold) {
  ex <- losses[losses > threshold] - threshold
  n_ex <- length(ex)
  n_total <- length(losses)
  if (n_ex < 10) {
    return(list(
      threshold  = threshold,
      xi         = NA_real_,
      beta       = NA_real_,
      n_excesses = n_ex,
      var_99     = NA_real_,
      es_99      = NA_real_,
      var_995    = NA_real_,
      es_995     = NA_real_,
      method     = "insufficient_excesses"
    ))
  }

  xi <- NA_real_; beta <- NA_real_; method <- "moment_method"

  if (ok_fext) {
    fit <- tryCatch(
      fExtremes::gpdFit(losses, u = threshold, type = "mle"),
      error = function(e) NULL
    )
    if (!is.null(fit) && !is.null(fit@fit$par.ests)) {
      xi   <- as.numeric(fit@fit$par.ests["xi"])
      beta <- as.numeric(fit@fit$par.ests["beta"])
      method <- "fExtremes::gpdFit_mle"
    }
  } else if (ok_evir) {
    fit <- tryCatch(
      evir::gpd(losses, threshold = threshold, method = "ml"),
      error = function(e) NULL
    )
    if (!is.null(fit) && !is.null(fit$par.ests)) {
      xi   <- as.numeric(fit$par.ests["xi"])
      beta <- as.numeric(fit$par.ests["beta"])
      method <- "evir::gpd_ml"
    }
  }

  # Fallback method-of-moments
  if (is.na(xi) || is.na(beta)) {
    m <- mean(ex); v <- var(ex)
    if (v > 0 && !is.na(m) && m > 0) {
      xi   <- 0.5 * (1 - m^2 / v)
      beta <- 0.5 * m * (m^2 / v + 1)
      method <- "moment_method_fallback"
    }
  }

  # Risk measures (Pfaff eq. 7.9, 7.10)
  qp <- function(q) {
    if (is.na(xi) || is.na(beta) || beta <= 0) return(NA_real_)
    rate <- n_total / n_ex
    if (abs(xi) < 1e-8) {
      threshold + beta * log(rate * (1 - q))
    } else {
      threshold + (beta / xi) * ((rate * (1 - q))^(-xi) - 1)
    }
  }
  es_p <- function(q) {
    v <- qp(q)
    if (is.na(v) || is.na(xi) || xi >= 1) return(NA_real_)
    (v + beta - xi * threshold) / (1 - xi)
  }

  list(
    threshold  = as.numeric(threshold),
    xi         = as.numeric(xi),
    beta       = as.numeric(beta),
    n_excesses = as.integer(n_ex),
    var_99     = qp(0.99),
    es_99      = es_p(0.99),
    var_995    = qp(0.995),
    es_995     = es_p(0.995),
    method     = method
  )
}

#' Empirical (non-parametric) tail risk measures
#'
#' VaR_q  = -quantile(returns, 1 - q)  [returns convention]
#' ES_q   = -mean(returns[returns <= -VaR_q])
#'
#' @param returns numeric
#' @return list(var_99, es_99, var_995, es_995, n)
.empirical_risk <- function(returns) {
  r <- returns[!is.na(returns)]
  n <- length(r)
  if (n < 30) return(list(var_99 = NA_real_, es_99 = NA_real_,
                          var_995 = NA_real_, es_995 = NA_real_, n = n))
  q01  <- as.numeric(quantile(r, 0.01,  na.rm = TRUE))
  q005 <- as.numeric(quantile(r, 0.005, na.rm = TRUE))
  es_99  <- if (any(r <= q01,  na.rm = TRUE)) -mean(r[r <= q01],  na.rm = TRUE) else NA_real_
  es_995 <- if (any(r <= q005, na.rm = TRUE)) -mean(r[r <= q005], na.rm = TRUE) else NA_real_
  list(
    var_99  = -q01,
    es_99   = es_99,
    var_995 = -q005,
    es_995  = es_995,
    n       = as.integer(n)
  )
}

#' Run full EVT analysis on a return series
#'
#' @param returns numeric (returns; positive=gain, negative=loss)
#' @param threshold_quantiles numeric (quantiles to use as POT thresholds)
#' @return list with components:
#'   gpd_fit_per_threshold  : list of POT fits at each threshold
#'   hill_alpha             : list(alpha, k, n) tail index
#'   var_99_parametric      : GPD-implied VaR_99 (90% threshold baseline)
#'   es_99_parametric       : GPD-implied ES_99 (90% threshold baseline)
#'   var_99_empirical       : non-parametric VaR_99
#'   es_99_empirical        : non-parametric ES_99
#'   divergence_pp          : parametric vs empirical absolute diff (decimal pp)
#'   mean_residual_life_data: data.frame for plot/diagnostic
#'   backend                : which package was used
#'
#' @export
evt_analyze <- function(returns, threshold_quantiles = c(0.80, 0.90, 0.95)) {

  if (!is.numeric(returns)) stop("returns must be numeric")
  r_clean <- returns[!is.na(returns)]
  if (length(r_clean) < 60) {
    stop(sprintf("evt_analyze: insufficient observations (n=%d, need >=60)",
                 length(r_clean)))
  }

  losses <- -r_clean  # convert returns -> positive losses

  # Per-threshold GPD fits (POT)
  gpd_fits <- list()
  for (q in threshold_quantiles) {
    u <- as.numeric(quantile(losses, q, na.rm = TRUE))
    gpd_fits[[as.character(q)]] <- .gpd_fit_single(losses, u)
  }

  # Hill alpha (using fExtremes hillPlot if available, else manual)
  hill_alpha <- list(alpha = NA_real_, k = NA_integer_, n = length(losses))
  if (ok_fext) {
    hp <- tryCatch({
      h <- fExtremes::hillPlot(losses, doplot = FALSE)
      # h@hill is a matrix-like; grab tail-index estimate at k = floor(0.10 * n)
      k_target <- max(20L, floor(0.10 * length(losses)))
      n_avail <- length(h@hill$y)
      idx <- min(k_target, n_avail)
      list(alpha = as.numeric(h@hill$y[idx]), k = as.integer(idx), n = length(losses))
    }, error = function(e) .hill_estimator_manual(losses))
    hill_alpha <- hp
  } else if (ok_evir) {
    hp <- tryCatch({
      h <- evir::hill(losses, end = max(20, floor(0.10 * length(losses))),
                      reverse = FALSE, plot = FALSE)
      list(alpha = mean(h$y, na.rm = TRUE),
           k     = max(20L, floor(0.10 * length(losses))),
           n     = length(losses))
    }, error = function(e) .hill_estimator_manual(losses))
    hill_alpha <- hp
  } else {
    hill_alpha <- .hill_estimator_manual(losses)
  }

  # Empirical risk measures
  emp <- .empirical_risk(r_clean)

  # Parametric (90% threshold = baseline per plan)
  base_fit <- gpd_fits[[as.character(0.90)]]
  if (is.null(base_fit)) base_fit <- gpd_fits[[1L]]

  # Divergence (parametric vs empirical, absolute pp)
  divergence_pp <- list(
    var_99_pp = abs((base_fit$var_99 - emp$var_99) * 100),
    es_99_pp  = abs((base_fit$es_99  - emp$es_99 ) * 100)
  )

  # Mean residual life diagnostic
  mrl <- .mean_residual_life(losses, n_grid = 30L)

  out <- list(
    gpd_fit_per_threshold   = gpd_fits,
    hill_alpha              = hill_alpha,
    var_99_parametric       = base_fit$var_99,
    es_99_parametric        = base_fit$es_99,
    var_99_empirical        = emp$var_99,
    es_99_empirical         = emp$es_99,
    divergence_pp           = divergence_pp,
    mean_residual_life_data = mrl,
    n                       = length(r_clean),
    threshold_quantiles     = threshold_quantiles,
    backend                 = .evt_backend(),
    pfaff_reference         = "FRM Ch7 Peaks-Over-Threshold (POT)"
  )
  class(out) <- c("evt_analysis", "list")
  out
}

#' Print compact summary
#' @export
print.evt_analysis <- function(x, ...) {
  cat("[evt_engine] EVT Analysis Summary\n")
  cat(sprintf("  backend       : %s\n", x$backend))
  cat(sprintf("  n_observations: %d\n", x$n))
  cat(sprintf("  Hill alpha    : %.3f (k=%s)\n",
              x$hill_alpha$alpha,
              ifelse(is.na(x$hill_alpha$k), "NA", x$hill_alpha$k)))
  cat("  GPD fits per threshold:\n")
  for (q in names(x$gpd_fit_per_threshold)) {
    f <- x$gpd_fit_per_threshold[[q]]
    cat(sprintf("    q=%s u=%.4f xi=%.3f beta=%.4f n_ex=%d VaR99=%.4f ES99=%.4f [%s]\n",
                q, f$threshold, f$xi, f$beta, f$n_excesses,
                f$var_99, f$es_99, f$method))
  }
  cat(sprintf("  Empirical    VaR99=%.4f  ES99=%.4f\n",
              x$var_99_empirical, x$es_99_empirical))
  cat(sprintf("  Divergence pp: VaR99=%.2f  ES99=%.2f\n",
              x$divergence_pp$var_99_pp, x$divergence_pp$es_99_pp))
  invisible(x)
}

cat("[evt_engine] Loaded. backend =", .evt_backend(), "\n")
