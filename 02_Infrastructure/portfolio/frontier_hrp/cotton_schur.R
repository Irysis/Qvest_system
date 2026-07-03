## ============================================================================
## cotton_schur.R — Cotton (2024) Schur Complementary Allocation (HMV)
## arXiv:2411.05807v1. "A Unification of Hierarchical Risk Parity and
## Minimum Variance Portfolios." HMV continuum: gamma=0 -> HRP, gamma=1 -> MVP.
## Knowledge: 04_Research/pg2_schur_weight/cotton2024_schur_knowledge.md
## ----------------------------------------------------------------------------
## CANONICAL, FAITHFUL implementation. Supersedes the Table-1-literal transcription
## in schur_hmv.R (which failed the paper's own replication theorem — see below).
##
## FAITHFULNESS NOTE (why this differs from a naive Table-1 read):
##   The paper (Appendix A, eq 8.1) proves the recursion is the block-inversion of
##   Sigma^{-1} 1. A LITERAL reading of Table 1 — intra-group A'' = Ac/(bA bA^T)
##   element-wise + inter-group fitness bA^T Ac^{-1} bA + per-level renormalization —
##   does NOT reproduce min-variance (verified: max wt error 0.048 on a 6-asset
##   case, and it breaks the 3-asset equal-corr symmetry, giving 0.263/0.368/0.368
##   instead of 1/3). Reason: A'' produces the within-group shape diag(bA) Ac^{-1} bA,
##   off by a diag(bA) factor from the true min-var subvector Ac^{-1} bA (eq 8.1).
##
##   The mathematically-exact realization propagates the rhs vector b through the
##   recursion (b starts as ones at the root, and at each split becomes
##   bA = b[A] - gamma * B D^{-1} b[D]) and does NOT renormalize between levels.
##   Terminal solves min-var against the propagated rhs: wterm = S^{-1} b (unnorm).
##   This reproduces Sigma^{-1} 1 EXACTLY at gamma=1 (verified max err 8e-17) and
##   recovers 3-asset symmetry exactly. gamma=0 recovers the classic HRP recursion
##   (inverse-variance splits on untouched sub-blocks).
##
## Equations (paper):
##   Ac(g) = A - g B D^{-1} C            (gamma-scaled Schur complement; eq 5.2)
##   bA(g) = b[A] - g B D^{-1} b[D]       (conditional rhs; eq 5.3 with rhs propagated)
##   inter-group mass(A) = sum( Ac^{-1} bA )   (= 1^T Ac^{-1} bA; block-inv eq 8.1)
##   terminal (dim<=term)  = Ac^{-1} bA         (unnormalized min-var subvector)
##   adaptive gamma: per-level cap g so Ac(g) stays PD (footnote 2)
##   weak shrinkage: off-diag *= xi minimizing long-only realized var vs orig Sigma
##                   (Appendix C; used for terminal solve + nu when shrink=TRUE, g<1)
## ============================================================================
suppressPackageStartupMessages({ requireNamespace("stats", quietly = TRUE) })

## ---- numeric helpers -------------------------------------------------------
.cs_solve <- function(M) {
  r <- tryCatch(solve(M), error = function(e) NULL)
  if (is.null(r)) {
    jit <- 1e-8 * mean(abs(diag(M))) + 1e-12
    r <- tryCatch(solve(M + diag(jit, ncol(M))), error = function(e) NULL)
  }
  r
}
.cs_is_pd <- function(M) {
  ev <- tryCatch(eigen((M + t(M)) / 2, symmetric = TRUE, only.values = TRUE)$values,
                 error = function(e) -1)
  all(is.finite(ev)) && all(ev > 1e-10)
}

## ---- seriation: correlation-distance single-linkage order (HRP standard) ----
cotton_seriation <- function(S) {
  p <- ncol(S); if (p < 3) return(seq_len(p))
  sdv <- sqrt(pmax(diag(S), 1e-16))
  Cr <- S / outer(sdv, sdv); Cr[!is.finite(Cr)] <- 0; diag(Cr) <- 1
  Cr[Cr >  1] <- 1; Cr[Cr < -1] <- -1
  d <- sqrt(pmax(0.5 * (1 - Cr), 0))
  hc <- tryCatch(stats::hclust(stats::as.dist(d), method = "single"),
                 error = function(e) NULL)
  if (is.null(hc)) return(seq_len(p)); hc$order
}

## ---- Appendix C: weak adaptive off-diagonal shrinkage -----------------------
## Multiply off-diagonals by xi; pick the xi minimizing the LONG-ONLY realized
## variance (short positions nullified + mass redistributed), variance judged by
## the ORIGINAL Sigma (not the shrunk one). Reproduces paper's xi=0.97 example.
cotton_weak_shrink_xi <- function(S, grid = seq(1, 0.5, by = -0.01)) {
  p <- ncol(S); if (p < 2) return(1)
  onevec <- rep(1, p); best_xi <- 1; best_v <- Inf
  for (xi in grid) {
    Sx <- S; off <- row(Sx) != col(Sx); Sx[off] <- Sx[off] * xi
    inv <- .cs_solve(Sx + diag(1e-12 * mean(abs(diag(Sx))) + 1e-14, p))
    if (is.null(inv)) next
    w <- as.numeric(inv %*% onevec)
    w <- pmax(w, 0); s <- sum(w); if (s <= 1e-12) next; w <- w / s   # nullify+redistribute
    v <- as.numeric(t(w) %*% S %*% w)                                # judged by original S
    if (is.finite(v) && v < best_v) { best_v <- v; best_xi <- xi }
  }
  best_xi
}
cotton_weak_shrink <- function(S, grid = seq(1, 0.5, by = -0.01)) {
  xi <- cotton_weak_shrink_xi(S, grid)
  Sx <- S; off <- row(Sx) != col(Sx); Sx[off] <- Sx[off] * xi; Sx
}

## ---- adaptive gamma (footnote 2): largest g<=g_user with Ac(g) PD -----------
.cs_adapt_gamma <- function(A, BDinvC, g_user) {
  if (g_user <= 0) return(0)
  if (.cs_is_pd(A - g_user * BDinvC)) return(g_user)
  g <- g_user
  for (k in 1:40) { g <- g * 0.9; if (g < 1e-6) return(0); if (.cs_is_pd(A - g * BDinvC)) return(g) }
  0
}

## ---- core recursion (Formulation 1: exact min-var replication at g=1) --------
## Returns the UNNORMALIZED min-var subvector for this block given rhs `b`.
## Do NOT renormalize between levels — scale carries the inter-group mass.
.cs_recurse <- function(S, b, gamma, term, shrink, adaptive) {
  p <- ncol(S)
  if (p <= term) {
    Su <- if (shrink && gamma < 1 - 1e-12 && p >= 2) cotton_weak_shrink(S) else S
    inv <- .cs_solve(Su + diag(1e-12 * mean(abs(diag(Su))) + 1e-14, p))
    if (is.null(inv)) return(rep(sum(b) / p, p))            # degenerate fallback
    w <- as.numeric(inv %*% b)
    if (!all(is.finite(w))) return(rep(sum(b) / p, p))
    return(w)
  }
  half <- floor(p / 2); ia <- 1:half; id <- (half + 1):p
  A <- S[ia, ia, drop = FALSE]; D <- S[id, id, drop = FALSE]
  B <- S[ia, id, drop = FALSE]; C <- t(B)
  bAin <- b[ia]; bDin <- b[id]
  Dinv <- .cs_solve(D); Ainv <- .cs_solve(A)
  if (is.null(Dinv) || is.null(Ainv)) {
    ## fallback to gamma=0 (classic HRP: untouched sub-blocks, rhs unchanged)
    Ac <- A; Dc <- D; bA <- bAin; bD <- bDin
  } else {
    BDinvC <- B %*% Dinv %*% C; CAinvB <- C %*% Ainv %*% B
    gA <- if (adaptive) .cs_adapt_gamma(A, BDinvC, gamma) else gamma
    gD <- if (adaptive) .cs_adapt_gamma(D, CAinvB, gamma) else gamma
    Ac <- A - gA * BDinvC
    Dc <- D - gD * CAinvB
    bA <- as.numeric(bAin - gA * (B %*% (Dinv %*% bDin)))   # eq 5.3 with rhs propagation
    bD <- as.numeric(bDin - gD * (C %*% (Ainv %*% bAin)))
  }
  wA <- .cs_recurse(Ac, bA, gamma, term, shrink, adaptive)
  wD <- .cs_recurse(Dc, bD, gamma, term, shrink, adaptive)
  out <- numeric(p); out[ia] <- wA; out[id] <- wD; out
}

## ---- public API ------------------------------------------------------------
## cotton_schur(S, gamma):
##   S        : covariance matrix (p x p), symmetric PD (symmetrized internally)
##   gamma    : [0,1]. 0 = HRP recursion, 1 = minimum-variance (rank permitting).
##   term     : recursion terminal dimension (paper m=5). Terminal = min-var subvector.
##   shrink   : apply Appendix C weak shrinkage at terminal solves (only when gamma<1).
##   adaptive : cap gamma per-level so the Schur complement stays PD (footnote 2).
##   long_only: TRUE -> nullify shorts + redistribute + box cap [0,ub] (PG2 default).
##              FALSE -> raw signed weights (validation / exact min-var replication).
##   ub       : per-name upper bound when long_only.
## Returns a length-p weight vector (sums to 1).
cotton_schur <- function(S, gamma = 0.5, term = 5, shrink = TRUE,
                         adaptive = TRUE, long_only = TRUE, ub = 0.20) {
  S <- as.matrix(S); S <- (S + t(S)) / 2; p <- ncol(S)
  gamma <- max(0, min(1, gamma))
  if (p == 1) { w <- 1 }
  else if (p == 2) {
    inv <- .cs_solve(S); w <- if (is.null(inv)) c(.5, .5) else as.numeric(inv %*% c(1, 1))
    if (!all(is.finite(w)) || abs(sum(w)) < 1e-12) w <- c(.5, .5) else w <- w / sum(w)
  } else {
    ord <- cotton_seriation(S)
    w_ord <- .cs_recurse(S[ord, ord, drop = FALSE], rep(1, p), gamma, term, shrink, adaptive)
    s <- sum(w_ord)
    if (!is.finite(s) || abs(s) < 1e-12) w_ord <- rep(1 / p, p) else w_ord <- w_ord / s
    w <- numeric(p); w[ord] <- w_ord
  }
  if (!long_only) return(w / sum(w))
  ## long-only projection: nullify shorts, redistribute, box-cap [0, ub]
  w <- pmax(w, 0); if (sum(w) <= 0) w <- rep(1 / p, p); w <- w / sum(w)
  for (it in 1:100) {
    over <- w > ub + 1e-12; if (!any(over)) break
    ex <- sum(w[over] - ub); w[over] <- ub
    fr <- which(!over & w > 1e-12)
    if (!length(fr)) { w <- w / sum(w); break }
    w[fr] <- w[fr] + ex * w[fr] / sum(w[fr])
  }
  w[w > ub] <- ub; w / sum(w)
}

## ---- validation gates (paper reproduction) ---------------------------------
cotton_schur_validate <- function(verbose = TRUE) {
  res <- list()

  ## G1: 3-asset equal-correlation -> symmetry (Appendix B). HMV(g=1) must be 1/3;1/3;1/3.
  rho <- 0.4; S3 <- matrix(rho, 3, 3); diag(S3) <- 1
  w_hmv <- cotton_schur(S3, gamma = 1.0, term = 2, shrink = FALSE, adaptive = FALSE, long_only = FALSE)
  w_hrp <- cotton_schur(S3, gamma = 0.0, term = 2, shrink = FALSE, adaptive = FALSE, long_only = FALSE)
  res$G1_hmv <- w_hmv; res$G1_hrp <- w_hrp
  res$G1_pass <- max(abs(w_hmv - 1 / 3)) < 1e-8
  ## HRP (gamma=0) on equal-corr should give the paper's asymmetric (1/(3+rho))(1,1,1+rho)
  ## after the {1,2},{3} split — sanity that gamma=0 is genuinely NOT symmetric.
  res$G1_hrp_asym <- max(abs(w_hrp - 1 / 3)) > 1e-6

  ## G2: gamma=0 recovers HRP's DEFINING property — the off-block B is discarded.
  ## Perturbing only the top-level off-diagonal block must leave gamma=0 weights
  ## unchanged (HRP throws away B), while gamma=1 weights DO shift (uses B).
  set.seed(5); X2 <- matrix(rnorm(200 * 6), 200, 6); S4 <- cov(X2)
  ord2 <- cotton_seriation(S4); So2 <- S4[ord2, ord2, drop = FALSE]
  ia2 <- 1:3; id2 <- 4:6; S2b <- So2
  S2b[ia2, id2] <- So2[ia2, id2] * 0.5; S2b[id2, ia2] <- So2[id2, ia2] * 0.5
  pd_ok <- all(eigen(S2b, symmetric = TRUE, only.values = TRUE)$values > 0)
  w0a <- cotton_schur(So2, 0, term = 2, shrink = FALSE, adaptive = FALSE, long_only = FALSE)
  w0b <- cotton_schur(S2b, 0, term = 2, shrink = FALSE, adaptive = FALSE, long_only = FALSE)
  w1a <- cotton_schur(So2, 1, term = 2, shrink = FALSE, adaptive = FALSE, long_only = FALSE)
  w1b <- cotton_schur(S2b, 1, term = 2, shrink = FALSE, adaptive = FALSE, long_only = FALSE)
  res$G2_g0_offblock_dw <- max(abs(w0a - w0b))
  res$G2_g1_offblock_dw <- max(abs(w1a - w1b))
  res$G2_pass <- pd_ok && res$G2_g0_offblock_dw < 1e-10 && res$G2_g1_offblock_dw > 1e-4

  ## G3: gamma=1 reproduces minimum variance Sigma^{-1}1 (rank permitting), no shrink.
  set.seed(1); X <- matrix(rnorm(60 * 6), 60, 6); S6 <- cov(X)
  mv <- as.numeric(.cs_solve(S6) %*% rep(1, 6)); mv <- mv / sum(mv)
  w_g1 <- cotton_schur(S6, gamma = 1.0, term = 2, shrink = FALSE, adaptive = FALSE, long_only = FALSE)
  res$G3_ref <- mv; res$G3_hmv_g1 <- w_g1
  res$G3_pass <- max(abs(w_g1 - mv)) < 1e-8

  ## G3b: larger p, terminal=5 (paper default), still exact at gamma=1.
  set.seed(3); X3 <- matrix(rnorm(200 * 20), 200, 20); S20 <- cov(X3)
  mv20 <- as.numeric(.cs_solve(S20) %*% rep(1, 20)); mv20 <- mv20 / sum(mv20)
  w20 <- cotton_schur(S20, gamma = 1.0, term = 5, shrink = FALSE, adaptive = FALSE, long_only = FALSE)
  res$G3b_pass <- max(abs(w20 - mv20)) < 1e-7; res$G3b_maxerr <- max(abs(w20 - mv20))

  ## G4: Appendix C weak-shrinkage argmin xi ~ 0.97 on the paper's 4x4 example.
  Sc <- matrix(c(
     1.09948514, -1.02926114,  0.22402055,  0.10727343,
    -1.02926114,  2.54302628,  1.05338531, -0.12481515,
     0.22402055,  1.05338531,  1.79162765, -0.78962956,
     0.10727343, -0.12481515, -0.78962956,  0.86316527), 4, 4, byrow = TRUE)
  xi <- cotton_weak_shrink_xi(Sc, grid = seq(1, 0.90, by = -0.005))
  res$G4_xi <- xi; res$G4_pass <- abs(xi - 0.97) <= 0.01

  res$ALL_PASS <- isTRUE(res$G1_pass) && isTRUE(res$G1_hrp_asym) && isTRUE(res$G2_pass) &&
                  isTRUE(res$G3_pass) && isTRUE(res$G3b_pass) && isTRUE(res$G4_pass)

  if (verbose) {
    cat(sprintf("[G1 symmetry]  HMV(g=1): %s | PASS %s\n",
                paste(round(w_hmv, 4), collapse = " "), res$G1_pass))
    cat(sprintf("               HRP(g=0): %s | genuinely asymmetric %s\n",
                paste(round(w_hrp, 4), collapse = " "), res$G1_hrp_asym))
    cat(sprintf("[G2 g=0=HRP]   off-block discarded @g=0: dw=%.2e (expect ~0) | used @g=1: dw=%.2e (>0) | PASS %s\n",
                res$G2_g0_offblock_dw, res$G2_g1_offblock_dw, res$G2_pass))
    cat(sprintf("[G3 min-var]   HMV(g=1): %s\n               ref     : %s | PASS %s\n",
                paste(round(w_g1, 4), collapse = " "),
                paste(round(mv, 4), collapse = " "), res$G3_pass))
    cat(sprintf("[G3b p=20 g=1] max err %.2e | PASS %s\n", res$G3b_maxerr, res$G3b_pass))
    cat(sprintf("[G4 weakshrink] argmin xi = %.3f (paper 0.97) | PASS %s\n", xi, res$G4_pass))
    cat(sprintf("=== ALL_PASS: %s ===\n", res$ALL_PASS))
  }
  invisible(res)
}

## ---- Section 6 simulation reproduction (Figure 1) --------------------------
## Short-sample synthetic Sigma regime where HRP is preferred. Verifies that
## OOS portfolio variance decreases (roughly monotonically) as gamma: 0 -> 1.
## Mirrors paper steps: anchor const-off-diag corr -> Sigma_true (a samples) ->
## Sigma_est (o samples) -> allocate for each gamma -> measure w' Sigma_true w.
cotton_schur_simulate <- function(p = 60, rho = 0.35, a = 50, o = 60,
                                   gammas = seq(0, 1, by = 0.1), term = 5,
                                   n_reps = 3, seed = 20260702, verbose = TRUE) {
  set.seed(seed)
  gen_anchor <- function(p, rho) { M <- matrix(rho, p, p); diag(M) <- 1; M }
  samp_cov <- function(Sig, n) {
    L <- chol((Sig + t(Sig)) / 2 + diag(1e-10, ncol(Sig)))
    Z <- matrix(rnorm(n * ncol(Sig)), n, ncol(Sig)); X <- Z %*% L; cov(X)
  }
  curves <- matrix(NA_real_, n_reps, length(gammas))
  for (r in 1:n_reps) {
    anchor  <- gen_anchor(p, rho)
    Sig_true <- samp_cov(anchor, a)      # "true" cov = empirical cov of a samples
    Sig_est  <- samp_cov(Sig_true, o)    # estimate from o samples
    for (j in seq_along(gammas)) {
      w <- cotton_schur(Sig_est, gamma = gammas[j], term = term, shrink = TRUE,
                        adaptive = TRUE, long_only = FALSE)
      curves[r, j] <- as.numeric(t(w) %*% Sig_true %*% w)
    }
    curves[r, ] <- curves[r, ] / curves[r, 1]   # normalize to gamma=0 (paper convention)
  }
  mean_curve <- colMeans(curves, na.rm = TRUE)
  ## monotone-ish check: variance at gamma=1 below gamma=0, and mostly non-increasing
  frac_decreasing <- mean(diff(mean_curve) <= 1e-6)
  end_reduction   <- 1 - mean_curve[length(mean_curve)]
  pass <- (mean_curve[length(mean_curve)] < mean_curve[1]) && (frac_decreasing >= 0.6)
  if (verbose) {
    cat("[Sim §6] normalized OOS variance vs gamma (mean over", n_reps, "reps):\n")
    cat("  gamma:", paste(sprintf("%.1f", gammas), collapse = "  "), "\n")
    cat("  var  :", paste(sprintf("%.3f", mean_curve), collapse = " "), "\n")
    cat(sprintf("  end reduction (1 - var@g=1) = %.3f | frac non-increasing = %.2f | PASS %s\n",
                end_reduction, frac_decreasing, pass))
  }
  invisible(list(gammas = gammas, mean_curve = mean_curve, curves = curves,
                 end_reduction = end_reduction, frac_decreasing = frac_decreasing, pass = pass))
}

if (identical(environment(), globalenv()) && !interactive() &&
    length(commandArgs(trailingOnly = TRUE)) && commandArgs(trailingOnly = TRUE)[1] == "selftest") {
  cotton_schur_validate(TRUE); cat("\n"); cotton_schur_simulate(verbose = TRUE)
}
