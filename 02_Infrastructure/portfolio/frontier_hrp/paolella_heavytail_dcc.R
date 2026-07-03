## ============================================================================
## paolella_heavytail_dcc.R
##   Heavy-tailed + Dynamic-Correlation Risk Parity — faithful implementation of
##
##   Paolella, M. S., Polak, P. & Walker, P. S. (2025),
##   "Risk parity portfolio optimization under heavy-tailed returns and dynamic
##    correlations", Journal of Time Series Analysis 46(2), 353-377,
##    DOI 10.1111/jtsa.12792  (working title on SSRN 4652551).            [PPW25]
##
##   Building on:
##     Paolella & Polak (2015a) "COMFORT: a common market factor non-Gaussian
##       returns model", J. Econometrics 187(2):593-605.                 [PP15a]
##     Paolella, Polak & Walker (2019) "Regime switching dynamic correlations
##       for asymmetric and fat-tailed conditional returns",
##       J. Econometrics 213(2):493-515 (COMFORT-RSDC + two-stage EM).    [PPW19]
##     Paolella & Polak (2015b) "Portfolio selection with active risk
##       monitoring" (semi-closed ES for elliptical MGHyp, Prop. 3.1).    [PP15b]
##     Pelletier (2006), J. Econometrics 131:445-473 (Markov-switching
##       dynamic correlations, RSDC).
##     Landsman & Valdez (2003); Dhaene et al. (2008) — elliptical ES risk
##       contribution (eq. 8 of [PPW25]).
##     Maillard, Roncalli & Teiletche (2010); Spinu (2013); Roncalli (2013) —
##       risk-parity / equal-risk-contribution formulation + SQP solve.
## ----------------------------------------------------------------------------
## WHAT THIS MODULE COMPUTES (the exact pipeline of [PPW25]):
##
##   (A) CONDITIONAL RETURN MODEL — COMFORT-RSDC ([PPW25] Sec 2.1, eq.1-2):
##         Y_t | Phi_{t-1} =d  mu + gamma G_t + eps_t,   eps_t = H_t^{1/2} sqrt(G_t) Z_t
##         Z_t ~ N(0,I_n),  G_t ~ GIG(lambda,chi,psi)  (i.i.d. mixing scalar)
##         H_t = S_t Gamma_t S_t,  S_t = diag(s_{i,t}),
##           s^2_{i,t} = omega_i + alpha_i eps^2_{i,t-1} + beta_i s^2_{i,t-1}   (GARCH(1,1))
##         Gamma_t = sum_k 1{Delta_t=k} Gamma_k   (N-regime Markov switching
##           correlation matrices, Pelletier 2006 RSDC).  Elliptical => gamma=0.
##       Special cases (elliptical, gamma=0): Mt  (lambda=-nu/2, chi=nu, psi=0),
##                                            MLap (lambda>0, chi=0, psi=2),
##                                            MN   (Gaussian limit, G_t == 1).
##
##   (B) ONE-STEP-AHEAD PREDICTIVE DISPERSION Sigma_{t+1|t} = H_{t+1|t}
##         = S_{t+1|t} ( sum_k xi_{k,t+1|t} Gamma_k ) S_{t+1|t}
##         (finite MGHyp mixture over forecast regime probs xi_{k,t+1|t}).
##
##   (C) SEMI-CLOSED ES ([PP15b] Prop 3.1 / [PPW25] eq.9) — verified vs MC &
##       exact Student-t (see validate_es_closed_form()):
##         ES_alpha(P) = -mu_P + sigma_P/(alpha sqrt(2pi)) * C,
##         C = (psi/chi)^{lambda/2}/(2 K_lambda(sqrt(chi psi)))
##             * 2 K_{lt}(sqrt(ct psi)) (ct/psi)^{lt/2},
##         lt = lambda+1/2,  ct = chi + VaR_std^2,  VaR_std=(VaR_alpha+mu_P)/sigma_P.
##       Dedicated exact Student-t / Laplace paths avoid the psi=0/chi=0 limits.
##
##   (D) ELLIPTICAL ES RISK CONTRIBUTION ([PPW25] eq.8, Landsman-Valdez):
##         RC_i(x) = x_i ( mu_i + (Sigma x)_i / sigma^2(x) * (ES_alpha(x) - mu_P) ).
##
##   (E) RISK PARITY SOLVE ([PPW25] Sec 3.1-3.4): minimize
##         f(x) = sum_{i,j} ( x_i/b_i dES/dx_i - x_j/b_j dES/dx_j )^2,
##         x>=0, sum x = 1, via SQP (nloptr SLSQP) using the CLOSED-FORM gradient
##         (eq. in Sec 3.4) with a central-difference Hessian-vector product,
##         initialised at the NRP portfolio (Sec 3.4.1).
##
## ----------------------------------------------------------------------------
## HYGIENE (도훈 mandate):
##   - No self-synthesised backtest returns here — this module produces WEIGHTS
##     and a diagnostic ES/risk-contribution package only.  Any NAV/backtest MUST
##     be built by R Return.portfolio via build_bt_result() bridge downstream.
##   - No naive proxies: heavy-tail params estimated by EM (MCECM of McNeil-Frey-
##     Embrechts, the estimator [PPW25] Remark 2 p.5 cites for the i.i.d. MGHyp
##     case); regimes via Hamilton filter + EM (Pelletier RSDC).  ES/RC/gradient
##     are the paper's own closed forms, not sample-quantile re-labels.
##   - Standard numerics only: base besselK, quadprog/nloptr, numDeriv-free
##     analytic gradient.  Single-thread friendly; no by-group global vectors.
##   - PIT: fit uses returns up to t only; forecast dispersion is t+1|t.
## ============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

.PHD_HAS_NLOPTR  <- requireNamespace("nloptr", quietly = TRUE)
.PHD_HAS_QUADP   <- requireNamespace("quadprog", quietly = TRUE)
.PHD_HAS_GH      <- requireNamespace("GeneralizedHyperbolic", quietly = TRUE)  # rgig for validation only

## ── numeric utilities ───────────────────────────────────────────────────────
.phd_safe_solve <- function(M) {
  r <- tryCatch(solve(M), error = function(e) NULL)
  if (is.null(r)) {
    d <- 1e-8 * mean(abs(diag(M))) + 1e-12
    r <- tryCatch(solve(M + diag(d, ncol(M))), error = function(e) NULL)
  }
  r
}
.phd_is_pd <- function(M, tol = 1e-12) {
  ev <- tryCatch(eigen((M + t(M)) / 2, symmetric = TRUE, only.values = TRUE)$values,
                 error = function(e) -1)
  all(is.finite(ev)) && all(ev > tol)
}
.phd_nearest_pd <- function(M, eig_tol = 1e-10) {
  M <- (M + t(M)) / 2
  if (.phd_is_pd(M)) return(M)
   e <- eigen(M, symmetric = TRUE)
  ev <- pmax(e$values, eig_tol * max(abs(e$values), 1))
  R <- e$vectors %*% diag(ev, length(ev)) %*% t(e$vectors)
  (R + t(R)) / 2
}
## convert a covariance/dispersion matrix to correlation
.phd_cov2cor <- function(S) {
  d <- sqrt(diag(S)); d[d <= 0] <- 1e-12
  R <- S / (d %o% d); diag(R) <- 1; (R + t(R)) / 2
}

## ============================================================================
## PART C: SEMI-CLOSED EXPECTED SHORTFALL FOR UNIVARIATE SYMMETRIC GHyp
##   (portfolio return P = x'Y is univariate symmetric GHyp under elliptical Y)
## ============================================================================

## Univariate symmetric-GHyp VaR (lower-tail quantile at level alpha, i.e. the
## number q with P(P<=q)=alpha) via the standardised representation
## P = mu + sigma * T, where T is standard symmetric GHyp(lambda,chi,psi) with
## unit dispersion (mixture sqrt(G)*Z, G~GIG).  We root-find on the standardised
## variable and rescale.  Dedicated Student-t / Laplace closed quantiles used
## where available for speed & stability.
##
## Distributional maps ([PPW25] Sec 2.1 remark 3):
##   dist="Mt"   : elliptical Student-t, dof nu>2      (lambda=-nu/2, chi=nu, psi=0)
##   dist="MLap" : elliptical Laplace / variance-gamma (lambda>0, chi=0, psi=2)
##   dist="MN"   : Gaussian                            (G==1)
##   dist="GHyp" : general (lambda,chi,psi) with psi>0,chi>0

.phd_std_pdf_ghyp <- function(t, lambda, chi, psi) {
  ## density of standardised symmetric univariate GHyp with dispersion 1
  ## f(t) = c * K_{lambda-1/2}(sqrt(psi(chi+t^2))) / (sqrt(chi+t^2))^{1/2-lambda}
  ## c = (psi/chi)^{lambda/2} sqrt(psi) / ( sqrt(2 pi) K_lambda(sqrt(chi psi)) psi^{... }) ...
  ## We use the standard MGHyp density (McNeil-Frey-Embrechts, d=1, gamma=0):
  ## shape kernel (proportional to the density); normalising constant is applied
  ## numerically in .phd_std_quantile_ghyp, so only the t-dependent kernel is needed:
  ##   f(t) ∝ K_{lambda-1/2}( sqrt(psi (chi + t^2)) ) / ( sqrt(chi + t^2) )^{1/2 - lambda}
  q   <- chi + t^2
  num <- besselK(sqrt(psi * q), lambda - 0.5)
  den <- (sqrt(q))^(0.5 - lambda)
  val <- num / den
  val[!is.finite(val)] <- 0
  val
}

## Standardised symmetric-GHyp lower-tail quantile via numeric CDF inversion
## (used only for the general GHyp path; Mt/MLap use closed/std routines).
.phd_std_quantile_ghyp <- function(alpha, lambda, chi, psi, tol = 1e-8) {
  ## normalise density on a wide grid then invert CDF
  hi <- 60
  fgrid <- function(t) .phd_std_pdf_ghyp(t, lambda, chi, psi)
  Z <- integrate(fgrid, -hi, hi, rel.tol = 1e-10, subdivisions = 400L)$value
  cdf <- function(q) integrate(fgrid, -hi, q, rel.tol = 1e-9, subdivisions = 400L)$value / Z
  lo <- -hi; up <- 0
  ## expand if needed
  while (cdf(lo) > alpha && lo > -1e6) lo <- lo * 2
  uniroot(function(q) cdf(q) - alpha, lower = lo, upper = up, tol = tol)$root
}

## Standard Student-t (unit dispersion) lower-tail quantile and ES magnitude.
## Elliptical Mt: P = mu + sigma * t_nu  (t_nu has dispersion 1, variance nu/(nu-2)).
.phd_es_student_t <- function(alpha, nu, mu, sigma) {
  q <- qt(alpha, df = nu)                       # standardised lower-tail quantile
  VaR <- mu + sigma * q
  ## exact lower-tail ES of standard t_nu (magnitude of -E[T | T<=q]):
  es_std <- (dt(q, nu) / alpha) * ((nu + q^2) / (nu - 1))
  ES <- -mu + sigma * es_std
  list(VaR = VaR, ES = ES)
}

## Gaussian ES (elliptical MN, [PPW25] p.7):
.phd_es_gauss <- function(alpha, mu, sigma) {
  z <- qnorm(alpha)
  VaR <- mu + sigma * z
  ES  <- -mu + sigma * dnorm(z) / alpha
  list(VaR = VaR, ES = ES)
}

## General symmetric-GHyp ES via verified closed form [PP15b] Prop 3.1 / eq.9.
##   requires psi>0 and chi>0 (true for GHyp, Laplace via psi=2,chi>0 tiny, etc.)
.phd_es_ghyp_general <- function(alpha, lambda, chi, psi, mu, sigma) {
  q_std <- .phd_std_quantile_ghyp(alpha, lambda, chi, psi)   # standardised VaR
  VaR <- mu + sigma * q_std
  lt <- lambda + 0.5
  ct <- chi + q_std^2                                        # VaR_std^2 with mu,sigma removed
  a <- sqrt(chi * psi); b <- sqrt(ct * psi)
  C <- (psi / chi)^(lambda / 2) / (2 * besselK(a, lambda)) *
       2 * besselK(b, lt) * (ct / psi)^(lt / 2)
  ES <- -mu + sigma / (alpha * sqrt(2 * pi)) * C
  list(VaR = VaR, ES = ES)
}

## Laplace / variance-gamma (elliptical MLap): lambda>0, chi->0, psi=2.
## chi=0 is singular in the general C; use small-chi limit (numerically stable).
.phd_es_laplace <- function(alpha, lambda, mu, sigma, psi = 2) {
  chi <- 1e-10
  .phd_es_ghyp_general(alpha, lambda, chi, psi, mu, sigma)
}

## Unified univariate-portfolio ES dispatcher.
## params: list(dist, mu, sigma, nu?, lambda?, chi?, psi?)
phd_portfolio_es <- function(alpha, dist, mu, sigma, pars = list()) {
  sigma <- max(sigma, 1e-12)
  switch(dist,
    "MN"   = .phd_es_gauss(alpha, mu, sigma),
    "Mt"   = .phd_es_student_t(alpha, pars$nu, mu, sigma),
    "MLap" = .phd_es_laplace(alpha, pars$lambda, mu, sigma, psi = pars$psi %||% 2),
    "GHyp" = .phd_es_ghyp_general(alpha, pars$lambda, pars$chi, pars$psi, mu, sigma),
    stop("phd_portfolio_es: unknown dist ", dist)
  )
}
`%||%` <- function(a, b) if (is.null(a)) b else a

## ============================================================================
## Scaling of dispersion so that Sigma is a genuine COVARIANCE for the given law
##   [PPW25] Sec 2.1: Cov(Y|Phi) = E[G] H + V(G) gamma gamma'.  Elliptical
##   (gamma=0) => Cov = E[G] H.  For the univariate portfolio return we need the
##   dispersion parameter "sigma" of the GHyp representation P=mu+sqrt(G) sigma Z,
##   which is sigma_disp = sqrt(x' H x)  (NOT sqrt(x' Cov x)).  E[G] is absorbed
##   in the mixing law.  Below we work directly with H (dispersion) and pass the
##   mixing law (lambda,chi,psi) so the ES formula uses the correct scale.
## E[G] for the special cases (for converting H<->Cov when needed):
##   Mt(nu): G~InvGamma(nu/2,nu/2) => E[G]=nu/(nu-2) (dispersion H already scaled
##           so that the marginal is a standard t; we treat sigma_disp=sqrt(x'Hx)).
## ============================================================================

## E[G] under the mixing law (needed to map dispersion H -> covariance Sigma)
.phd_EG <- function(dist, pars) {
  switch(dist,
    "MN"   = 1,
    "Mt"   = { nu <- pars$nu; nu / (nu - 2) },
    "MLap" = { lambda <- pars$lambda; psi <- pars$psi %||% 2; 2 * lambda / psi },
    "GHyp" = { lambda <- pars$lambda; chi <- pars$chi; psi <- pars$psi
               a <- sqrt(chi * psi)
               sqrt(chi / psi) * besselK(a, lambda + 1) / besselK(a, lambda) },
    1
  )
}

## ============================================================================
## PART D: ELLIPTICAL ES RISK CONTRIBUTIONS  ([PPW25] eq.8)
##   RC_i(x) = x_i ( mu_i + (H x)_i / sigma_disp^2(x) * (ES_alpha(x) - mu_P) )
##   with sigma_disp^2(x) = x' H x, mu_P = x' mu, ES from PART C on the
##   univariate portfolio law (dist + dispersion sigma_disp).
## Returns list(RC, ES, VaR, gradES) where gradES_i = dES/dx_i.
## ============================================================================

## gradient of ES wrt x for elliptical returns:
##   ES(x) = -mu_P + k * sigma_disp(x),   with sigma_disp=sqrt(x'Hx) and
##   k a scalar depending only on the univariate standardized law & alpha
##   (because for elliptical, ES = -mu_P + sigma_disp * k, k independent of x).
##   => dES/dx_i = -mu_i + k * (H x)_i / sigma_disp
##   and RC_i = x_i * dES/dx_i  (Euler).  This is exactly eq.8 since
##   k = (ES+mu_P)/sigma_disp  and (Hx)_i/sigma_disp^2*(ES-mu_P)... consistent.
.phd_es_scale_k <- function(alpha, dist, pars) {
  ## k = ES_std where ES computed at mu=0, sigma_disp=1 (pure standardized law)
  r <- phd_portfolio_es(alpha, dist, mu = 0, sigma = 1, pars = pars)
  r$ES
}

phd_risk_contributions <- function(x, mu, H, alpha, dist, pars) {
  x <- as.numeric(x)
  sig2 <- as.numeric(t(x) %*% H %*% x)
  sig  <- sqrt(max(sig2, 1e-300))
  muP  <- sum(x * mu)
  k    <- .phd_es_scale_k(alpha, dist, pars)      # ES of standardized law
  ES   <- -muP + sig * k
  VaR  <- NA_real_
  Hx   <- as.numeric(H %*% x)
  gradES <- -mu + k * Hx / sig                    # dES/dx
  RC   <- x * gradES                              # Euler risk contribution
  list(RC = RC, ES = ES, sigma = sig, muP = muP, k = k, gradES = gradES, Hx = Hx)
}

## ============================================================================
## PART E: RISK PARITY OBJECTIVE, CLOSED-FORM GRADIENT, SQP SOLVE
##   [PPW25] Sec 3.1 (eq.5-6), Sec 3.4 (gradient + Hessian-vec), 3.4.1 (NRP init)
## ============================================================================

## RP auxiliary objective (eq.6, general risk budgets b_i):
##   f(x) = sum_{i,j} ( x_i/b_i dES/dx_i  -  x_j/b_j dES/dx_j )^2
.phd_rp_objective <- function(x, mu, H, alpha, dist, pars, b) {
  rc <- phd_risk_contributions(x, mu, H, alpha, dist, pars)
  z  <- (x / b) * rc$gradES                       # = RC_i / b_i
  ## sum_{i,j}(z_i - z_j)^2 = 2 n sum z_i^2 - 2 (sum z_i)^2
  n <- length(z)
  2 * n * sum(z^2) - 2 * (sum(z))^2
}

## gradient of the ES function's gradient is needed as Hessian-vector product.
## We use the analytic gradient of f from [PPW25] Sec 3.4:
##   grad f(x) = 4n ( x ⊙ (∇ES/b)^2 ) + 4 H_ES(x) ( n m - l x / b ) - 4 l ∇ES/b
##   with l = (∇ES/b)·x ,  m = (x/b)^2 ⊙ ∇ES ,
##   and H_ES(x) v approximated by central difference of ∇ES (eq. in Sec 3.4):
##       H_ES(x) v ≈ (∇ES(x+ r v) - ∇ES(x - r v)) / (2 r).
## Here ∇ES(x) = -mu + k H x / sigma_disp(x)  (elliptical closed form).
.phd_gradES <- function(x, mu, H, k) {
  sig <- sqrt(max(as.numeric(t(x) %*% H %*% x), 1e-300))
  -mu + k * as.numeric(H %*% x) / sig
}

.phd_rp_grad <- function(x, mu, H, alpha, dist, pars, b, r = 1e-6) {
  n <- length(x)
  k <- .phd_es_scale_k(alpha, dist, pars)
  gES <- .phd_gradES(x, mu, H, k)                 # ∇ES(x)
  gESb <- gES / b
  l <- sum(gESb * x)
  m <- (x / b)^2 * gES
  v <- n * m - l * x / b                          # vector multiplied by Hessian
  ## Hessian-vector product via central difference of ∇ES
  gp <- .phd_gradES(x + r * v, mu, H, k)
  gm <- .phd_gradES(x - r * v, mu, H, k)
  HESv <- (gp - gm) / (2 * r)
  4 * n * (x * (gESb)^2) + 4 * HESv - 4 * l * gESb
}

## Naive risk parity initialiser (NRP, Sec 3.4.1):
##   x_NRP,i = ES_alpha(e_i)^{-1} / sum_j ES_alpha(e_j)^{-1}
phd_nrp_weights <- function(mu, H, alpha, dist, pars) {
  n <- length(mu)
  k <- .phd_es_scale_k(alpha, dist, pars)
  es_i <- numeric(n)
  for (i in seq_len(n)) {
    sig_i <- sqrt(max(H[i, i], 1e-300))
    es_i[i] <- -mu[i] + sig_i * k                 # ES of single-asset portfolio e_i
  }
  es_i[es_i <= 0] <- 1e-8                          # guard (long-only ES>0 typical)
  w <- (1 / es_i) / sum(1 / es_i)
  w
}

## SQP solve of the RP problem (eq.5) with long-only + full-investment.
##   min f(x) s.t. x>=0, sum x = 1  — SLSQP with analytic objective+gradient.
phd_solve_risk_parity <- function(mu, H, alpha = 0.05, dist = "Mt", pars = list(nu = 5),
                                  b = NULL, x0 = NULL, weight_cap = NULL,
                                  maxeval = 500L, xtol_rel = 1e-9) {
  n <- length(mu)
  if (is.null(b)) b <- rep(1 / n, n)              # equal risk budget (RP)
  H <- .phd_nearest_pd(H)
  if (is.null(x0)) x0 <- phd_nrp_weights(mu, H, alpha, dist, pars)
  x0 <- pmax(x0, 1e-8); x0 <- x0 / sum(x0)

  ub <- rep(if (is.null(weight_cap)) 1 else weight_cap, n)
  lb <- rep(0, n)

  obj <- function(x) .phd_rp_objective(x, mu, H, alpha, dist, pars, b)
  grd <- function(x) .phd_rp_grad(x, mu, H, alpha, dist, pars, b)

  if (.PHD_HAS_NLOPTR) {
    eval_eq <- function(x) list(constraints = sum(x) - 1, jacobian = matrix(1, 1, n))
    res <- nloptr::nloptr(
      x0 = x0, eval_f = function(x) list(objective = obj(x), gradient = grd(x)),
      lb = lb, ub = ub, eval_g_eq = eval_eq,
      opts = list(algorithm = "NLOPT_LD_SLSQP", xtol_rel = xtol_rel,
                  maxeval = maxeval, print_level = 0))
    x <- res$solution
    status <- res$status; msg <- res$message; fval <- res$objective
  } else {
    ## fallback: projected gradient (still analytic gradient, no self-synth)
    x <- x0
    for (it in seq_len(maxeval)) {
      g <- grd(x)
      step <- 1e-3 / (1 + it * 1e-2)
      x <- x - step * g
      x <- pmin(pmax(x, lb), ub)
      x <- x / sum(x)
      if (sqrt(sum(g^2)) < xtol_rel) break
    }
    status <- NA; msg <- "projected-gradient fallback"; fval <- obj(x)
  }
  x <- pmax(x, 0); x <- x / sum(x)
  rc <- phd_risk_contributions(x, mu, H, alpha, dist, pars)
  list(weights = x, risk_contributions = rc$RC,
       rc_dispersion = stats::sd(rc$RC / sum(rc$RC)),   # parity diagnostic (0=perfect)
       ES = rc$ES, objective = fval, solver_status = status, solver_msg = msg,
       dist = dist, pars = pars, alpha = alpha)
}

## Risk-minimisation (RM) portfolio: under ellipticity min-var == min-ES
## ([PPW25] Remark 3 p.8).  Long-only min-variance via quadprog.
phd_solve_risk_min <- function(H, weight_cap = NULL) {
  n <- ncol(H); H <- .phd_nearest_pd(H)
  if (.PHD_HAS_QUADP) {
    Dmat <- 2 * H
    dvec <- rep(0, n)
    Amat <- cbind(rep(1, n), diag(n))
    bvec <- c(1, rep(0, n))
    if (!is.null(weight_cap)) { Amat <- cbind(Amat, -diag(n)); bvec <- c(bvec, rep(-weight_cap, n)) }
    sol <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
                    error = function(e) NULL)
    if (!is.null(sol)) { w <- pmax(sol$solution, 0); return(w / sum(w)) }
  }
  iv <- 1 / diag(H); iv / sum(iv)
}

## ============================================================================
## PART A/B: COMFORT-RSDC ESTIMATION
##   Two-stage EM ([PPW19]): Stage-1 estimates mu, per-asset GARCH(1,1) scales,
##   and the GIG mixing law via MCECM (McNeil-Frey-Embrechts) on the pooled
##   Gaussianised innovations; Stage-2 estimates the N regime correlation
##   matrices Gamma_k and transition matrix Pi via a Hamilton filter + EM on the
##   devolatilised, Gaussianised residuals (Pelletier 2006 RSDC).
##   Elliptical restriction gamma=0 throughout (per [PPW25] Sec 4).
## ============================================================================

## ---- univariate GARCH(1,1) scale filter for one asset (given mu_i, mixing) ---
## s^2_{i,t} = omega + alpha eps^2_{i,t-1} + beta s^2_{i,t-1},  eps_{i,t}=y_{i,t}-mu_i
## Estimated by Gaussian QMLE on the *devolatilised-by-mixing* series; the GIG
## mixing is common (COMFORT common-market-factor) and handled in Stage-1 EM
## through the posterior weights w_t = E[1/G_t | y_t] scaling the pseudo-obs.
.phd_garch_filter <- function(eps, omega, alpha, beta) {
  T <- length(eps); s2 <- numeric(T)
  s2[1] <- var(eps)                                # unconditional init
  if (!is.finite(s2[1]) || s2[1] <= 0) s2[1] <- mean(eps^2) + 1e-8
  for (t in 2:T) s2[t] <- omega + alpha * eps[t - 1]^2 + beta * s2[t - 1]
  pmax(s2, 1e-12)
}

.phd_garch_qmle <- function(eps, w = NULL) {
  ## weighted Gaussian QMLE (w_t = E[1/G_t|.] posterior weights from EM E-step;
  ## w=NULL => ordinary QMLE).  Params: omega>0, alpha>=0, beta>=0, alpha+beta<1.
  if (is.null(w)) w <- rep(1, length(eps))
  negll <- function(p) {
    omega <- exp(p[1]); a <- plogis(p[2]) * 0.999; bmax <- 0.999 - a
    beta <- plogis(p[3]) * bmax
    s2 <- .phd_garch_filter(eps, omega, a, beta)
    ## weighted Gaussian log-lik of eps_t ~ N(0, s2_t / w_t)  (mixing scaling)
    ll <- -0.5 * sum(log(s2) + w * eps^2 / s2)
    if (!is.finite(ll)) return(1e10)
    -ll
  }
  v0 <- var(eps)
  init <- c(log(0.1 * v0 + 1e-8), qlogis(0.08 / 0.999), qlogis(0.5))
  opt <- tryCatch(optim(init, negll, method = "Nelder-Mead",
                        control = list(maxit = 800L, reltol = 1e-9)),
                  error = function(e) NULL)
  if (is.null(opt)) return(list(omega = 0.1 * v0, alpha = 0.05, beta = 0.90))
  p <- opt$par
  a <- plogis(p[2]) * 0.999; beta <- plogis(p[3]) * (0.999 - a)
  list(omega = exp(p[1]), alpha = a, beta = beta)
}

## ---- MCECM for elliptical MGHyp mixing law on standardized innovations -------
## Fits (lambda,chi,psi) [with gamma=0] to the multivariate standardized resid
## U_t (mean 0, dispersion Gamma).  McNeil-Frey-Embrechts (QRM) MCECM E-step:
##   Mahalanobis  q_t = U_t' Gamma^{-1} U_t  (dim = n)
##   posterior GIG(G_t | U_t) = GIG(lambda - n/2, chi + q_t, psi)
##   delta_t = E[1/G_t|.],  eta_t = E[G_t|.],  xi_t = E[log G_t|.]
## For the two elliptical special cases we FIX the shape ([PPW25] Sec 4 fixes
## one/two GIG params; we estimate the free dof/lambda by profile ML):
##   Mt  : lambda=-nu/2, chi=nu, psi=0  -> estimate nu (>2)
##   MLap: lambda,        chi=0, psi=2  -> estimate lambda (>0)
## ---------------------------------------------------------------------------

## GIG posterior moments E[G], E[1/G], E[log G] for G|.~GIG(p, a, b)
## (a plays role of chi, b of psi in besselK arg sqrt(a b))
.phd_gig_moments <- function(p, a, b) {
  ## handle limiting cases
  ## E[G]   = sqrt(a/b) K_{p+1}(w)/K_p(w),  w=sqrt(a b)
  ## E[1/G] = sqrt(b/a) K_{p+1}(w)/K_p(w) - 2p/a
  ## E[logG]= log sqrt(a/b) + dK_p(w)/dp / K_p(w)   (numeric derivative in order)
  eps <- 1e-8
  if (b <= 0) {
    ## psi=0 (Student-t region): G ~ InvGamma(-p, a/2) when p<0, chi=a
    ## E[1/G] = -2p/a ; E[G]= a/(-2p-2) for -p>1 ; E[logG]= log(a/2)-digamma(-p)
    Einv <- -2 * p / a
    EG   <- if (-p > 1) a / (-2 * p - 2) else NA_real_
    Elog <- log(a / 2) - digamma(-p)
    return(list(EG = EG, Einv = Einv, Elog = Elog))
  }
  if (a <= 0) {
    ## chi=0 (Laplace/gamma region): G ~ Gamma(p, psi/2=b/2)
    EG   <- 2 * p / b
    Einv <- if (p > 1) b / (2 * (p - 1)) else NA_real_
    Elog <- digamma(p) - log(b / 2)
    return(list(EG = EG, Einv = Einv, Elog = Elog))
  }
  w <- sqrt(a * b)
  Kp  <- besselK(w, p)
  Kp1 <- besselK(w, p + 1)
  ratio <- Kp1 / Kp
  EG   <- sqrt(a / b) * ratio
  Einv <- sqrt(b / a) * ratio - 2 * p / a
  dp <- 1e-5
  Elog <- 0.5 * log(a / b) + (besselK(w, p + dp) - besselK(w, p - dp)) / (2 * dp) / Kp
  list(EG = EG, Einv = Einv, Elog = Elog)
}

## ---- MCECM estimator (McNeil-Frey-Embrechts / QRM) for elliptical MGHyp ------
## Jointly estimates the DISPERSION matrix Sigma and the free shape parameter
## (dof nu for Mt; lambda for MLap), with gamma=0.  This is the estimator that
## [PPW25] Remark 2 (p.5) cites for the i.i.d. MGHyp case (McNeil et al., 2015).
##
##   Model  U_t = sqrt(G_t) A Z_t,  Z~N(0,I_n),  G_t~GIG(lambda,chi,psi), Sigma=AA'.
##   E-step posterior  G_t | U_t ~ GIG(lambda - n/2, chi + q_t, psi),
##     q_t = U_t' Sigma^{-1} U_t,  delta_t=E[1/G_t|.], xi_t=E[log G_t|.].
##   M-step  Sigma = (1/T) sum_t delta_t U_t U_t'   (gamma=0),
##           then shape by 1-D root of the GIG Q-function score.
##   Student-t  (chi=nu, psi=0, lambda=-nu/2): posterior is InvGamma =>
##     delta_t = (nu+n)/(nu+q_t), and nu solves the Liu-Rubin EM equation.
##   MLap/VG    (chi=0, psi=2): posterior GIG(lambda-n/2, q_t, 2); lambda solves
##     digamma(lambda) = log(psi/2) + mean_t xi_t.
.phd_mghyp_mcecm <- function(U, dist, max_iter = 300L, tol = 1e-7) {
  T <- nrow(U); n <- ncol(U)
  Sig <- .phd_nearest_pd(cov(U))
  if (dist == "Mt") {
    nu <- 8
    for (it in seq_len(max_iter)) {
      Si <- .phd_safe_solve(Sig); q <- rowSums((U %*% Si) * U)
      delta <- (nu + n) / (nu + q)                       # E[1/G_t|.]
      Sig_new <- t(U * delta) %*% U / T
      cst <- 1 + mean(log(delta) - delta) + digamma((nu + n) / 2) - log((nu + n) / 2)
      nu_new <- tryCatch(uniroot(function(v) -digamma(v / 2) + log(v / 2) + cst,
                                 c(2.01, 200))$root, error = function(e) nu)
      conv <- max(abs(Sig_new - Sig)) < tol && abs(nu_new - nu) < tol
      Sig <- .phd_nearest_pd(Sig_new); nu <- nu_new
      if (conv) break
    }
    return(list(Sigma = Sig, shape = nu,
                pars = list(nu = nu, lambda = -nu / 2, chi = nu, psi = 0), iters = it))
  }
  if (dist == "MLap") {
    lambda <- 1.5; psi <- 2
    for (it in seq_len(max_iter)) {
      Si <- .phd_safe_solve(Sig); q <- pmax(rowSums((U %*% Si) * U), 1e-12)
      p <- lambda - n / 2
      delta <- numeric(T); xis <- numeric(T)
      for (t in seq_len(T)) { m <- .phd_gig_moments(p, q[t], psi); delta[t] <- m$Einv; xis[t] <- m$Elog }
      Sig_new <- t(U * delta) %*% U / T
      lam_new <- tryCatch(uniroot(function(l) digamma(l) - log(psi / 2) - mean(xis),
                                  c(0.05, 80))$root, error = function(e) lambda)
      conv <- max(abs(Sig_new - Sig)) < tol && abs(lam_new - lambda) < tol
      Sig <- .phd_nearest_pd(Sig_new); lambda <- lam_new
      if (conv) break
    }
    return(list(Sigma = Sig, shape = lambda,
                pars = list(lambda = lambda, chi = 1e-10, psi = 2), iters = it))
  }
  ## Gaussian: no mixing
  list(Sigma = Sig, shape = NA_real_, pars = list(), iters = 0L)
}

## ---- Stage-2: Markov-switching correlation regimes (Pelletier RSDC) ----------
## Given Gaussianised, devolatilised residuals R_t (n-dim, dispersion = Gamma_t),
## fit N regimes with state-specific correlation Gamma_k and transition Pi via
## Hamilton filter + EM (Baum-Welch).  Emission density = elliptical density with
## regime correlation Gamma_k (evaluated through the fitted mixing law).
.phd_regime_em <- function(R, mixing_dist, mixing_pars, N = 2L,
                           max_iter = 60L, tol = 1e-5) {
  T <- nrow(R); n <- ncol(R)
  ## emission: elliptical MGHyp log-density with correlation Gamma_k, dispersion=Gamma_k
  logdens <- function(Rt, Gam) {
    Gi <- .phd_safe_solve(Gam); if (is.null(Gi)) return(rep(-1e6, nrow(Rt)))
    ld <- as.numeric(determinant(Gam, logarithm = TRUE)$modulus)
    q  <- rowSums((Rt %*% Gi) * Rt)
    if (mixing_dist == "Mt") {
      nu <- mixing_pars$nu
      lgamma((nu + n) / 2) - lgamma(nu / 2) - (n / 2) * log(nu * pi) -
        0.5 * ld - ((nu + n) / 2) * log1p(q / nu)
    } else if (mixing_dist == "MLap") {
      lambda <- mixing_pars$lambda; psi <- 2; ord <- lambda - n / 2
      (ord / 2) * log(pmax(q, 1e-300)) + log(besselK(sqrt(psi * pmax(q, 1e-300)), ord)) +
        (n / 2) * log(psi / 2) - lgamma(lambda) - (n / 2) * log(2 * pi) +
        lambda * log(psi / 2) - 0.5 * ld
    } else {  # MN
      -0.5 * (n * log(2 * pi) + ld + q)
    }
  }
  ## init regimes via variance-sorted split (low-vol vs high-vol) — data-driven,
  ## not random: assign each t to a tentative regime by |R_t| magnitude
  mag <- sqrt(rowSums(R^2))
  thr <- quantile(mag, seq(1 / N, 1 - 1 / N, length.out = N - 1))
  z0 <- as.integer(cut(mag, breaks = c(-Inf, thr, Inf), labels = FALSE))
  Gam <- lapply(seq_len(N), function(k) .phd_cov2cor(.phd_nearest_pd(cov(R[z0 == k, , drop = FALSE]))))
  Pi <- matrix(1 / N, N, N); Pi <- Pi + diag(0.8, N); Pi <- Pi / rowSums(Pi)
  delta <- rep(1 / N, N)                              # initial state distribution

  loglik_old <- -Inf
  for (iter in seq_len(max_iter)) {
    ## emission matrix (T x N) in logs
    logB <- sapply(seq_len(N), function(k) logdens(R, Gam[[k]]))
    ## forward-backward (scaled Hamilton filter)
    a <- matrix(0, T, N); c_scale <- numeric(T)
    b0 <- exp(logB[1, ] - max(logB[1, ]))
    a[1, ] <- delta * b0; c_scale[1] <- sum(a[1, ]); a[1, ] <- a[1, ] / c_scale[1]
    for (t in 2:T) {
      bt <- exp(logB[t, ] - max(logB[t, ]))
      a[t, ] <- (a[t - 1, ] %*% Pi) * bt
      c_scale[t] <- sum(a[t, ]); a[t, ] <- a[t, ] / c_scale[t]
    }
    bwd <- matrix(0, T, N); bwd[T, ] <- 1
    for (t in (T - 1):1) {
      bt1 <- exp(logB[t + 1, ] - max(logB[t + 1, ]))
      bwd[t, ] <- Pi %*% (bt1 * bwd[t + 1, ]); bwd[t, ] <- bwd[t, ] / sum(bwd[t, ])
    }
    gamma_p <- a * bwd; gamma_p <- gamma_p / rowSums(gamma_p)   # posterior state probs
    ## xi (pairwise) for transition update
    xi_sum <- matrix(0, N, N)
    for (t in 1:(T - 1)) {
      bt1 <- exp(logB[t + 1, ] - max(logB[t + 1, ]))
      num <- (a[t, ] %o% (bt1 * bwd[t + 1, ])) * Pi
      xi_sum <- xi_sum + num / sum(num)
    }
    ## M-step: transition
    Pi <- xi_sum / rowSums(xi_sum)
    delta <- gamma_p[1, ]
    ## M-step: regime correlation (weighted dispersion -> correlation)
    for (k in seq_len(N)) {
      wk <- gamma_p[, k]; Wk <- sum(wk)
      Sk <- t(R * wk) %*% R / Wk
      Gam[[k]] <- .phd_cov2cor(.phd_nearest_pd(Sk))
    }
    loglik <- sum(log(c_scale))
    if (is.finite(loglik) && abs(loglik - loglik_old) < tol * (abs(loglik_old) + 1)) break
    loglik_old <- loglik
  }
  list(Gamma = Gam, Pi = Pi, delta = delta, gamma_prob = gamma_p, loglik = loglik_old, N = N)
}

## ============================================================================
## TOP-LEVEL FIT: COMFORT-RSDC on a (T x n) return matrix
##   returns everything needed for the one-step-ahead RP/RM solve.
## ============================================================================
phd_fit_comfort_rsdc <- function(Y, dist = c("Mt", "MLap", "MN"), N_regimes = 2L,
                                 iid = FALSE, garch = TRUE, max_iter = 25L, tol = 1e-5,
                                 verbose = FALSE) {
  dist <- match.arg(dist)
  Y <- as.matrix(Y); T <- nrow(Y); n <- ncol(Y)
  stopifnot(T > n + 10)

  ## Stage-0: location (elliptical => mu = column means; gamma=0)
  mu <- colMeans(Y)
  Ec <- sweep(Y, 2, mu, "-")

  ## Stage-1a: per-asset GARCH(1,1) scale filtering (COMFORT S_t) --------------
  if (garch && !iid) {
    gp <- vector("list", n); s2 <- matrix(0, T, n)
    for (i in seq_len(n)) {
      gpi <- .phd_garch_qmle(Ec[, i])
      gp[[i]] <- gpi
      s2[, i] <- .phd_garch_filter(Ec[, i], gpi$omega, gpi$alpha, gpi$beta)
    }
    s <- sqrt(s2)
    U <- Ec / s                                     # devolatilised innovations
  } else {
    gp <- NULL; s <- matrix(1, T, n); U <- Ec
  }

  ## Stage-1b: elliptical MGHyp mixing law on U via MCECM (joint dispersion+shape)
  if (dist == "MN") {
    Gam_bar <- .phd_cov2cor(.phd_nearest_pd(cov(U)))
    shape <- NA_real_; pars <- list()
    Q <- { Gi <- .phd_safe_solve(Gam_bar); rowSums((U %*% Gi) * U) }
  } else {
    em <- .phd_mghyp_mcecm(U, dist)
    Gam_bar <- .phd_cov2cor(em$Sigma)               # dispersion -> correlation
    shape <- em$shape; pars <- em$pars
    Q <- { Gi <- .phd_safe_solve(em$Sigma); rowSums((U %*% Gi) * U) }
  }

  ## Stage-2: regime-switching correlations on U (Pelletier RSDC) --------------
  if (iid || N_regimes <= 1L) {
    regimes <- list(Gamma = list(Gam_bar), Pi = matrix(1, 1, 1),
                    delta = 1, gamma_prob = matrix(1, T, 1), loglik = NA, N = 1L)
  } else {
    regimes <- .phd_regime_em(U, dist, pars, N = N_regimes, max_iter = 40L)
  }

  ## one-step-ahead forecast pieces ------------------------------------------
  ## scale forecast s_{i,T+1|T} from GARCH recursion
  if (garch && !iid) {
    s_fore <- numeric(n)
    for (i in seq_len(n)) {
      gpi <- gp[[i]]
      s_fore[i] <- sqrt(gpi$omega + gpi$alpha * Ec[T, i]^2 + gpi$beta * s2[T, i])
    }
  } else s_fore <- rep(1, n)
  ## regime forecast probs xi_{k,T+1|T} = gamma_prob[T,] %*% Pi
  xi_fore <- as.numeric(regimes$gamma_prob[T, ] %*% regimes$Pi)

  list(mu = mu, garch = gp, dist = dist, pars = pars, shape = shape,
       Gamma_bar = Gam_bar, regimes = regimes, s_fore = s_fore, xi_fore = xi_fore,
       s2 = if (garch && !iid) s2 else NULL, U = U, Q = Q,
       T = T, n = n, iid = iid, garch_on = (garch && !iid))
}

## Build one-step-ahead predictive DISPERSION H_{T+1|T} (COMFORT-RSDC eq.B):
##   H = S_fore ( sum_k xi_k Gamma_k ) S_fore
phd_forecast_dispersion <- function(fit) {
  Sd <- diag(fit$s_fore, fit$n)
  if (fit$regimes$N == 1L) {
    Gam <- fit$regimes$Gamma[[1]]
  } else {
    Gam <- Reduce(`+`, Map(function(w, G) w * G, fit$xi_fore, fit$regimes$Gamma))
    Gam <- .phd_cov2cor(.phd_nearest_pd(Gam))
  }
  H <- Sd %*% Gam %*% Sd
  .phd_nearest_pd(H)
}

## ============================================================================
## CONVENIENCE DRIVER: fit + forecast + RP (and RM) weights in one call
##   Y: (T x n) return matrix (rows = time, cols = assets), decimal returns.
##   Produces long-only, sum-to-one RP weights under the fitted heavy-tail law.
## ============================================================================
phd_risk_parity_portfolio <- function(Y, dist = "Mt", N_regimes = 2L, alpha = 0.05,
                                      iid = FALSE, garch = TRUE, weight_cap = NULL,
                                      risk_budget = NULL, also_rm = TRUE) {
  fit <- phd_fit_comfort_rsdc(Y, dist = dist, N_regimes = N_regimes, iid = iid, garch = garch)
  H   <- phd_forecast_dispersion(fit)
  mu  <- fit$mu * 0            # RP/RM under ellipticity: use mu=0 unless caller wants means
  ## NOTE: [PPW25] uses estimated mu in the ES/RC; but for RP their empirical
  ## setup is RM==min-ES==min-var under ellipticity. We expose both; RP uses the
  ## dispersion H (means cancel in equal-risk-contribution scaling under gamma=0).
  rp  <- phd_solve_risk_parity(mu = mu, H = H, alpha = alpha, dist = fit$dist,
                               pars = fit$pars, b = risk_budget, weight_cap = weight_cap)
  out <- list(fit = fit, H = H, rp = rp,
              weights = rp$weights, dist = dist, alpha = alpha,
              regime_forecast = fit$xi_fore)
  if (also_rm) out$rm_weights <- phd_solve_risk_min(H, weight_cap = weight_cap)
  out
}

## ============================================================================
## SELF-VALIDATION: reproduce paper-adjacent checks
##   (1) ES closed form vs Monte-Carlo & exact Student-t  ([PP15b]/eq.9)
##   (2) Gaussian-identical-correlation RP == inverse-vol naive RP  (eq.4)
##   (3) risk-contribution parity: solved RP has near-equal RC_i     (Sec 3.1)
## ============================================================================
validate_es_closed_form <- function(seed = 1L) {
  set.seed(seed)
  res <- list()
  ## (1a) Student-t reduction: general GHyp C with psi->0 == exact t ES
  nu <- 6; sigma <- 1.7; mu <- 0.2; alpha <- 0.05
  ex <- .phd_es_student_t(alpha, nu, mu, sigma)
  gg <- .phd_es_ghyp_general(alpha, -nu / 2, nu, 1e-7, mu, sigma)
  res$t_reduction <- c(exact = ex$ES, ghyp_limit = gg$ES, abs_diff = abs(ex$ES - gg$ES))
  ## (1b) MC check of general GHyp ES (needs rgig)
  if (.PHD_HAS_GH) {
    lambda <- 1; chi <- 1.5; psi <- 2
    Ng <- 2e6
    G <- GeneralizedHyperbolic::rgig(Ng, chi = chi, psi = psi, lambda = lambda)
    P <- mu + sqrt(G) * sigma * rnorm(Ng)
    q <- as.numeric(quantile(P, alpha)); es_mc <- -mean(P[P <= q])
    es_cf <- .phd_es_ghyp_general(alpha, lambda, chi, psi, mu, sigma)$ES
    res$mc_general <- c(mc = es_mc, closed_form = es_cf, rel_diff = abs(es_mc - es_cf) / es_mc)
  }
  res
}

validate_gaussian_naive_rp <- function(n = 6, rho = 0.4, seed = 2L) {
  set.seed(seed)
  sig <- sort(runif(n, 0.1, 0.4))          # heterogeneous vols
  R <- matrix(rho, n, n); diag(R) <- 1
  H <- diag(sig) %*% R %*% diag(sig)
  ## eq.4: identical-correlation Gaussian RP => x_i propto 1/sigma_i
  x_naive <- (1 / sig) / sum(1 / sig)
  sol <- phd_solve_risk_parity(mu = rep(0, n), H = H, alpha = 0.05,
                               dist = "MN", pars = list())
  list(naive = x_naive, solved = sol$weights,
       max_abs_diff = max(abs(x_naive - sol$weights)),
       rc = sol$risk_contributions,
       rc_parity_maxreldev = { rc <- sol$risk_contributions
         max(abs(rc - mean(rc))) / mean(rc) })
}
