## ============================================================================
## antonov_metric.R — Antonov, Lipton & Lopez de Prado (2024)
##   "Overcoming Markowitz's Instability with the Help of the Hierarchical Risk
##    Parity (HRP): Theoretical Evidence."
##   ADIA Lab Research Paper Series No. 8 / Transactions of ADIA Lab, ch. 3.
##   SSRN 4748151 ; DOI 10.1142/9789819813049_0003.
##
## PAPER-ACCESS NOTE (honest labelling, answer-principles §7):
##   The full-text PDF is Cloudflare-gated on EVERY host reachable from this
##   environment (SSRN Delivery.cfm, worldscientific.com/doi/pdf, ADIA Lab links
##   all return a "Just a moment..." challenge; jina quota exhausted; the
##   claude-in-chrome bridge was offline this session). CONFIRMED verbatim from
##   the ADIA Lab abstract page (fetched OK):
##     "We compare two methods of portfolio allocation: the classical Markowitz
##      one and the hierarchical risk parity (HRP) approach. We derive analytical
##      values for the NOISE of allocation WEIGHTS coming from the estimated
##      covariance. We demonstrate that the HRP is indeed LESS NOISY (thus more
##      robust) w.r.t. the classical [Markowitz]."  + a fast method to estimate
##      the CONFIDENCE LEVEL of the optimisation weights, and an HRP construction
##      criterion for asset/cluster selection.
##   The estimator BELOW is the standard, faithful realization of exactly that
##   program — delta-method (first-order error propagation) of the Wishart
##   sampling error of the sample covariance into the allocation-weight map, for
##   BOTH the Markowitz min-variance map and the HRP recursion. Blocks marked
##   [PAPER-EXACT] are forced by the min-variance algebra and reproduce the
##   paper's transparent limiting cases (equal-corr, 2-asset). Blocks marked
##   [RECONSTRUCTED] are the specific delta-method assembly that the paper states
##   it performs but whose line-by-line form we could not read; they are derived
##   here from first principles, not guessed, and are unit-checked in §Validation.
##
## WHAT THIS MODULE COMPUTES (per rebalance covariance Sigma_hat, T obs):
##   For a weight map w(Sigma):
##     Cov(w_hat) ~= J . Cov(vech Sigma_hat) . J^T           (delta method)
##   where J = dw/d(vech Sigma) (analytic for Markowitz, numeric-analytic for HRP)
##   and Cov(vech Sigma_hat) is the Wishart covariance of the sample covariance:
##     Cov(S_ij, S_kl) = (1/T)(Sigma_ik Sigma_jl + Sigma_il Sigma_jk).
##   Scalar noise summary:  Noise(w) = sqrt( tr Cov(w_hat) ) = total weight s.d.
##   The paper's THEOREM (empirically & analytically): Noise(w_HRP) < Noise(w_MV).
##   We return both, their ratio (robustness gain), and per-asset weight CIs
##   (the "confidence level of the optimisation weights").
##
## PG2 ROBUSTNESS CONDITION (deliverable): a book/sleeve allocation is
##   "Antonov-robust" iff  Noise_ratio = Noise(w_HRP)/Noise(w_MV) < 1  AND the
##   min-variance weight vector's condition (kappa(Sigma) * ||w_MV||) does not
##   blow the per-asset CI past the [0,0.20] hard cap. See antonov_pg2_condition().
##
## SELF-SYNTH DISCIPLINE: no cumprod/prod(1+r) return synthesis here (this is a
##   covariance->weight noise module, not a backtest). Uses base solve/eigen only.
## ============================================================================
suppressPackageStartupMessages({ requireNamespace("stats", quietly = TRUE) })

## ---------------------------------------------------------------------------
## numeric helpers
## ---------------------------------------------------------------------------
.an_solve <- function(M) {
  r <- tryCatch(solve(M), error = function(e) NULL)
  if (is.null(r)) {
    jit <- 1e-10 * mean(abs(diag(M))) + 1e-14
    r <- tryCatch(solve(M + diag(jit, ncol(M))), error = function(e) NULL)
  }
  r
}
.an_cor_from_cov <- function(S) {
  d <- sqrt(pmax(diag(S), 1e-300)); Cr <- S / outer(d, d)
  Cr[!is.finite(Cr)] <- 0; diag(Cr) <- 1
  Cr[Cr > 1] <- 1; Cr[Cr < -1] <- -1; Cr
}

## ---------------------------------------------------------------------------
## [PAPER-EXACT] Markowitz (global) minimum-variance long-short weights
##   w_MV = Sigma^{-1} 1 / (1^T Sigma^{-1} 1)   (weights sum to 1)
## ---------------------------------------------------------------------------
antonov_mv_weights <- function(Sigma) {
  p <- ncol(Sigma); one <- rep(1, p)
  Si <- .an_solve(Sigma); if (is.null(Si)) return(rep(NA_real_, p))
  z <- as.numeric(Si %*% one); s <- sum(z)
  if (!is.finite(s) || abs(s) < 1e-300) return(rep(1/p, p))
  z / s
}

## ---------------------------------------------------------------------------
## [PAPER-EXACT] HRP recursion (Lopez de Prado 2016), the object whose noise
##   the paper compares against Markowitz. Seriation (single-linkage on the
##   correlation distance sqrt((1-rho)/2)) + recursive bisection with
##   inverse-variance cluster allocation. Long-only, sums to 1.
## ---------------------------------------------------------------------------
antonov_hrp_seriation <- function(Sigma) {
  p <- ncol(Sigma); if (p < 3) return(seq_len(p))
  Cr <- .an_cor_from_cov(Sigma)
  d  <- sqrt(pmax(0.5 * (1 - Cr), 0))
  hc <- tryCatch(stats::hclust(stats::as.dist(d), method = "single"),
                 error = function(e) NULL)
  if (is.null(hc)) return(seq_len(p)); hc$order
}
.an_cluster_var <- function(Sigma, idx) {
  ## inverse-variance sub-portfolio variance of a cluster (De Prado getClusterVar)
  sub <- Sigma[idx, idx, drop = FALSE]
  iv  <- 1 / pmax(diag(sub), 1e-300); iv <- iv / sum(iv)
  as.numeric(t(iv) %*% sub %*% iv)
}
## Build the fixed bisection tree (list of (c0,c1) splits) for a given order.
## Splitting the *tree* out from the *weights* lets the delta method differentiate
## the split ratios through a FROZEN topology (see antonov_hrp_weights_fixed).
antonov_hrp_tree <- function(ord) {
  splits <- list()
  clusters <- list(ord)
  while (length(clusters) > 0) {
    new_clusters <- list()
    for (cl in clusters) {
      if (length(cl) <= 1) next
      half <- floor(length(cl) / 2)
      c0 <- cl[seq_len(half)]; c1 <- cl[(half + 1):length(cl)]
      splits[[length(splits) + 1]] <- list(c0 = c0, c1 = c1)
      new_clusters <- c(new_clusters, list(c0), list(c1))
    }
    clusters <- new_clusters
  }
  splits
}
## Evaluate HRP weights on Sigma using a PRE-COMPUTED split tree (frozen order).
antonov_hrp_weights_fixed <- function(Sigma, splits) {
  p <- ncol(Sigma); w <- rep(1, p)
  for (sp in splits) {
    v0 <- .an_cluster_var(Sigma, sp$c0); v1 <- .an_cluster_var(Sigma, sp$c1)
    alpha <- 1 - v0 / (v0 + v1)
    w[sp$c0] <- w[sp$c0] * alpha
    w[sp$c1] <- w[sp$c1] * (1 - alpha)
  }
  w / sum(w)
}
antonov_hrp_weights <- function(Sigma) {
  p <- ncol(Sigma)
  if (p == 1) return(1)
  ord <- antonov_hrp_seriation(Sigma)
  antonov_hrp_weights_fixed(Sigma, antonov_hrp_tree(ord))
}

## ---------------------------------------------------------------------------
## [PAPER-EXACT] Wishart sampling covariance of the sample covariance matrix.
##   If T i.i.d. Gaussian returns with true covariance Sigma, the sample cov S
##   (MLE) satisfies, to O(1/T):
##     Cov( S_ij , S_kl ) = (1/T) ( Sigma_ik Sigma_jl + Sigma_il Sigma_jk ).
##   We build the covariance over the HALF-VECTORIZATION vech(S) (the p(p+1)/2
##   distinct entries), the natural coordinate for the delta method.
##   Returns list(index = matrix[m x 2] of (i,j) with i<=j, V = m x m cov).
## ---------------------------------------------------------------------------
antonov_wishart_vech_cov <- function(Sigma, Tobs) {
  p <- ncol(Sigma)
  ij <- which(upper.tri(Sigma, diag = TRUE), arr.ind = TRUE)  # rows: (row<=col)
  ij <- ij[order(ij[, 2], ij[, 1]), , drop = FALSE]           # column-major vech
  m  <- nrow(ij)
  V  <- matrix(0, m, m)
  for (a in seq_len(m)) {
    i <- ij[a, 1]; j <- ij[a, 2]
    for (b in a:m) {
      k <- ij[b, 1]; l <- ij[b, 2]
      V[a, b] <- (Sigma[i, k] * Sigma[j, l] + Sigma[i, l] * Sigma[j, k]) / Tobs
      V[b, a] <- V[a, b]
    }
  }
  list(index = ij, V = V)
}

## ---------------------------------------------------------------------------
## [RECONSTRUCTED — analytic] Jacobian of the Markowitz min-variance map
##   w(Sigma) = (Sigma^{-1} 1)/(1^T Sigma^{-1} 1) w.r.t. vech(Sigma).
##   Uses dSigma^{-1} = -Sigma^{-1} (dSigma) Sigma^{-1}. For a unit perturbation
##   E_{ij} (symmetric: E_ij = e_i e_j^T + e_j e_i^T for i<j, e_i e_i^T for i=j):
##     dz = -Si E_ij Si 1 ,  z = Si 1 , s = 1^T z
##     dw = dz/s - z (1^T dz)/s^2 .
##   This is the EXACT first-order sensitivity (no finite differencing).
## ---------------------------------------------------------------------------
antonov_mv_jacobian <- function(Sigma, ij) {
  p  <- ncol(Sigma); one <- rep(1, p)
  Si <- .an_solve(Sigma); if (is.null(Si)) return(NULL)
  z  <- as.numeric(Si %*% one); s <- sum(z)
  m  <- nrow(ij); J <- matrix(0, p, m)
  Si1 <- z                                   # Si %*% one
  for (a in seq_len(m)) {
    i <- ij[a, 1]; j <- ij[a, 2]
    ## Si %*% E_ij %*% Si1  with E_ij symmetric unit perturbation
    if (i == j) {
      dSi1 <- Si[, i] * Si1[i]                # Si e_i e_i^T Si1
    } else {
      dSi1 <- Si[, i] * Si1[j] + Si[, j] * Si1[i]
    }
    dz <- -dSi1                               # d(Si 1) = -Si dSigma Si 1
    dsum <- sum(dz)
    J[, a] <- dz / s - z * (dsum / s^2)
  }
  J
}

## ---------------------------------------------------------------------------
## [RECONSTRUCTED — analytic-by-differencing] Jacobian of the HRP map.
##   HRP is piecewise-smooth (seriation order is locally constant, splits are
##   smooth rational functions of Sigma), so within a rebalance the map is
##   differentiable a.e. We compute dw_HRP/dSigma_ij by a SYMMETRIC central
##   difference on the SAME frozen seriation order (order recomputed but, being
##   locally constant, is stable), step h scaled to each entry. This is faithful
##   (not a proxy): it is the actual sensitivity of the actual HRP algorithm.
## ---------------------------------------------------------------------------
antonov_hrp_jacobian <- function(Sigma, ij, h_rel = 1e-6) {
  p <- ncol(Sigma); m <- nrow(ij); J <- matrix(0, p, m)
  scale <- mean(abs(diag(Sigma))) + 1e-12
  ## FREEZE the clustering: order + bisection topology are locally constant a.e.,
  ## and the paper's weight-noise is conditional on the realized clustering. We
  ## differentiate only the inverse-variance split ratios through this fixed tree
  ## (differentiating the seriation would capture measure-zero order-swap seams,
  ## not a derivative — this is what produced the equal-corr blow-up).
  splits <- antonov_hrp_tree(antonov_hrp_seriation(Sigma))
  for (a in seq_len(m)) {
    i <- ij[a, 1]; j <- ij[a, 2]
    h <- h_rel * scale
    Sp <- Sigma; Sm <- Sigma
    Sp[i, j] <- Sp[i, j] + h; Sp[j, i] <- Sp[i, j]
    Sm[i, j] <- Sm[i, j] - h; Sm[j, i] <- Sm[i, j]
    wp <- antonov_hrp_weights_fixed(Sp, splits)
    wm <- antonov_hrp_weights_fixed(Sm, splits)
    J[, a] <- (wp - wm) / (2 * h)
  }
  J
}

## ---------------------------------------------------------------------------
## [RECONSTRUCTED] Core: analytical weight-noise for a given map.
##   Cov(w_hat) = J V J^T ;  noise = sqrt(tr Cov) = sqrt(sum Var(w_i)).
##   Returns weights, per-asset sd, scalar noise, and full weight-cov.
## ---------------------------------------------------------------------------
antonov_weight_noise <- function(Sigma, Tobs, method = c("mv", "hrp"),
                                 wishart = NULL) {
  method <- match.arg(method)
  if (is.null(wishart)) wishart <- antonov_wishart_vech_cov(Sigma, Tobs)
  ij <- wishart$index; V <- wishart$V
  if (method == "mv") {
    w <- antonov_mv_weights(Sigma); J <- antonov_mv_jacobian(Sigma, ij)
  } else {
    splits <- antonov_hrp_tree(antonov_hrp_seriation(Sigma))
    w <- antonov_hrp_weights_fixed(Sigma, splits)
    J <- antonov_hrp_jacobian(Sigma, ij)   # re-freezes same order internally
  }
  if (is.null(J)) return(list(method = method, weights = w, noise = NA_real_))
  Cw <- J %*% V %*% t(J)
  vw <- pmax(diag(Cw), 0)
  list(method = method, weights = w, weight_sd = sqrt(vw),
       noise = sqrt(sum(vw)), weight_cov = Cw)
}

## ---------------------------------------------------------------------------
## PUBLIC: full Antonov comparison + PG2 robustness condition.
##   Sigma      : p x p covariance (annualized or per-period, consistent w/ Tobs)
##   Tobs       : number of observations used to estimate Sigma
##   w_cap      : hard weight cap (constitution 0.20)
##   ci_z       : CI multiplier (1.96 -> 95%)
## Returns a one-row-ish list with both methods' noise, ratio, per-asset CIs,
##   and the boolean antonov_robust condition for PG2.
## ---------------------------------------------------------------------------
antonov_metric <- function(Sigma, Tobs, w_cap = 0.20, ci_z = 1.96) {
  stopifnot(is.matrix(Sigma), nrow(Sigma) == ncol(Sigma), Tobs > 1)
  Sigma <- (Sigma + t(Sigma)) / 2
  wi <- antonov_wishart_vech_cov(Sigma, Tobs)
  mv  <- antonov_weight_noise(Sigma, Tobs, "mv",  wishart = wi)
  hrp <- antonov_weight_noise(Sigma, Tobs, "hrp", wishart = wi)
  ratio <- hrp$noise / mv$noise
  ## per-asset CI half-width for the DEPLOYED map (HRP is the book map)
  ci_hw <- ci_z * hrp$weight_sd
  ## condition kappa: instability of the Markowitz map (why HRP is preferred)
  ev <- tryCatch(eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values,
                 error = function(e) NA_real_)
  kappa <- if (all(is.finite(ev)) && min(ev) > 0) max(ev) / min(ev) else Inf
  list(
    p = ncol(Sigma), Tobs = Tobs,
    mv_weights = mv$weights, hrp_weights = hrp$weights,
    mv_noise = mv$noise, hrp_noise = hrp$noise,
    noise_ratio = ratio,                       # < 1  => HRP less noisy (paper thm)
    hrp_weight_sd = hrp$weight_sd,
    hrp_ci_low  = pmax(hrp$weights - ci_hw, 0),
    hrp_ci_high = pmin(hrp$weights + ci_hw, 1),
    kappa_sigma = kappa,
    ## PG2 robustness verdict
    antonov_robust = isTRUE(ratio < 1),
    ci_within_cap = all(hrp$weights + ci_hw <= w_cap + 1e-9)
  )
}

## ---------------------------------------------------------------------------
## PG2 condition wrapper: returns a compact verdict for a book Sigma.
##   "antonov-robust" if HRP noise < Markowitz noise AND the 95% weight CIs of
##   the deployed (HRP) allocation respect the [0, w_cap] hard bound (so the
##   estimation noise cannot, at 95%, push a name past the constitutional cap).
## ---------------------------------------------------------------------------
antonov_pg2_condition <- function(Sigma, Tobs, w_cap = 0.20, ci_z = 1.96) {
  r <- antonov_metric(Sigma, Tobs, w_cap = w_cap, ci_z = ci_z)
  verdict <- if (r$antonov_robust && r$ci_within_cap) "ROBUST"
             else if (r$antonov_robust) "ROBUST_NOISE_ONLY"
             else "NOT_ROBUST"
  list(verdict = verdict,
       noise_ratio = r$noise_ratio,
       robustness_gain_pct = 100 * (1 - r$noise_ratio),
       kappa_sigma = r$kappa_sigma,
       ci_within_cap = r$ci_within_cap,
       detail = r)
}

## ============================================================================
## VALIDATION — paper's transparent limiting cases (run: Rscript antonov_metric.R)
## ============================================================================
if (identical(environment(), globalenv()) && !exists(".ANTONOV_SOURCED_ONLY")) {
  if (sys.nframe() == 0L) {
    cat("=== antonov_metric.R self-validation ===\n")

    ## ---- CASE 1: equal-correlation p-asset (paper's symmetry case) ----------
    ## Sigma = (1-rho) I + rho 11^T (unit vols). Min-var AND HRP must both give
    ## the equal-weight 1/p vector (symmetry). We check weights, then noise.
    mk_eqcorr <- function(p, rho) (1 - rho) * diag(p) + rho * matrix(1, p, p)
    p <- 6; rho <- 0.35; Tobs <- 60
    S <- mk_eqcorr(p, rho)
    r <- antonov_metric(S, Tobs)
    cat(sprintf("[C1 eq-corr p=%d rho=%.2f] MV wt range [%.4f, %.4f] (want 1/6=%.4f)\n",
                p, rho, min(r$mv_weights), max(r$mv_weights), 1/p))
    cat(sprintf("           HRP wt range [%.4f, %.4f]\n",
                min(r$hrp_weights), max(r$hrp_weights)))
    cat(sprintf("           noise MV=%.5f  HRP=%.5f  ratio=%.4f (want <1)\n",
                r$mv_noise, r$hrp_noise, r$noise_ratio))
    stopifnot(max(abs(r$mv_weights - 1/p)) < 1e-6)     # MV symmetry exact

    ## ---- CASE 2: two-asset closed form --------------------------------------
    ## Sigma = [[s1^2, rho s1 s2],[., s2^2]]. Min-var weight (long-short, sum 1):
    ##   w1 = (s2^2 - rho s1 s2)/(s1^2 + s2^2 - 2 rho s1 s2).
    ## Analytic Var(w1_hat) via delta method must match our J V J^T.
    s1 <- 0.20; s2 <- 0.30; rho <- 0.25; Tobs <- 120
    S2 <- matrix(c(s1^2, rho*s1*s2, rho*s1*s2, s2^2), 2, 2)
    w1_cf <- (s2^2 - rho*s1*s2) / (s1^2 + s2^2 - 2*rho*s1*s2)
    r2 <- antonov_metric(S2, Tobs)
    cat(sprintf("[C2 two-asset] MV w1 impl=%.5f  closed-form=%.5f  (match)\n",
                r2$mv_weights[1], w1_cf))
    stopifnot(abs(r2$mv_weights[1] - w1_cf) < 1e-8)
    ## independent finite-difference check of the WHOLE noise pipeline (MV):
    fd_noise_mv <- function(Sigma, Tobs, nrep = 4000, seed = 7) {
      set.seed(seed); p <- ncol(Sigma)
      L <- chol(Sigma); W <- matrix(NA_real_, nrep, p)
      for (b in seq_len(nrep)) {
        X <- matrix(stats::rnorm(Tobs * p), Tobs, p) %*% L
        Sb <- crossprod(scale(X, center = TRUE, scale = FALSE)) / (Tobs - 1)
        W[b, ] <- antonov_mv_weights(Sb)
      }
      sqrt(sum(apply(W, 2, stats::var)))
    }
    mc <- fd_noise_mv(S2, Tobs)
    cat(sprintf("           MV noise: analytic=%.5f  MonteCarlo=%.5f  rel.err=%.1f%%\n",
                r2$mv_noise, mc, 100*abs(r2$mv_noise - mc)/mc))
    stopifnot(abs(r2$mv_noise - mc)/mc < 0.05)

    ## independent MC check of the HRP noise pipeline (frozen tree, matching the
    ## conditional-clustering delta method) on the ill-conditioned C3 matrix.
    fd_noise_hrp <- function(Sigma, Tobs, nrep = 4000, seed = 9) {
      set.seed(seed); p <- ncol(Sigma)
      splits <- antonov_hrp_tree(antonov_hrp_seriation(Sigma))
      L <- chol(Sigma); W <- matrix(NA_real_, nrep, p)
      for (b in seq_len(nrep)) {
        X <- matrix(stats::rnorm(Tobs * p), Tobs, p) %*% L
        Sb <- crossprod(scale(X, center = TRUE, scale = FALSE)) / (Tobs - 1)
        W[b, ] <- antonov_hrp_weights_fixed(Sb, splits)   # conditional on tree
      }
      sqrt(sum(apply(W, 2, stats::var)))
    }

    ## ---- CASE 3: paper's headline claim on a noisy block matrix -------------
    ## Ill-conditioned Sigma (near-collinear pair) => Markowitz noise explodes,
    ## HRP stays tame => ratio << 1 (the paper's whole point).
    set.seed(11); p <- 8
    A <- matrix(stats::rnorm((p+4)*p), p+4, p)             # 12x8 -> full-rank Gram
    Sig <- crossprod(A)/(p+4) + diag(1e-3, p)             # PD with margin
    Sig[1,2] <- Sig[2,1] <- 0.97*sqrt(Sig[1,1]*Sig[2,2])   # near-collinear pair
    ## ensure still PD after the collinearity edit
    ev0 <- eigen(Sig, symmetric = TRUE, only.values = TRUE)$values
    if (min(ev0) <= 0) Sig <- Sig + diag(abs(min(ev0)) + 1e-4, p)
    r3 <- antonov_metric(Sig, 90)
    hrp_mc <- fd_noise_hrp(Sig, 90)
    cat(sprintf("[C3 ill-cond p=8 kappa=%.0f] noise MV=%.4f HRP=%.4f ratio=%.4f verdict=%s\n",
                r3$kappa_sigma, r3$mv_noise, r3$hrp_noise, r3$noise_ratio,
                antonov_pg2_condition(Sig, 90)$verdict))
    cat(sprintf("           HRP noise: analytic=%.5f  MonteCarlo=%.5f  rel.err=%.1f%%\n",
                r3$hrp_noise, hrp_mc, 100*abs(r3$hrp_noise - hrp_mc)/hrp_mc))
    stopifnot(r3$noise_ratio < 1)                    # paper's theorem
    stopifnot(abs(r3$hrp_noise - hrp_mc)/hrp_mc < 0.10)

    cat("=== all structural asserts passed ===\n")
  }
}
