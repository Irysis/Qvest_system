## Validation for dynamic_regime_rp.R — [PKM 2009.11367] artifact reproduction.
## Run: Rscript _validate_dynamic_regime_rp.R   (NO korean in -e; file-source only)
## Rewritten 2026-07-03 to validate the FAITHFUL MRS-MNTS-GARCH pipeline:
##   [A] stdNTS density (Sec 2.3): FFT-inverted char fn integrates to 1, mean0/var1.
##   [B] CTS subordinator (Sec 2.3/3.3): E[T]=1, Var[T]=(1-a)/theta exact.
##   [C] NTS MLE recovery (Sec 3.2 Step 2/4): recover known (lambda,theta,beta).
##   [D] NTS beats t on fat tails (Table 1 stylized fact): NTS KS-fit >> t on skewed
##       fat-tailed data.
##   [E] MS-GARCH regime extraction (Sec 3.1 Step 1): 2-state GARCH regime + Table2
##       transition persistence (high self-transition), regime2 higher vol.
##   [F] Sigma_DeltaD Step-5 formula (Sec 3.2 Step 5): PD, symmetric, skew-removal
##       term applied (differs from raw sample cov). Table3 stylized fact: regime2
##       (volatile) has higher joint-innovation correlation than regime1.
##   [G] CVaR / CDaR LP optimizers (Sec 4): valid long-only box weights; CVaR/CDaR
##       optimal beats equal-weight on tail risk (Table4 ordering: risk-optimized <
##       EW risk). 0.3-CDaR & 0.5-CVaR are the paper's best.
##   [H] End-to-end MRS-MNTS-GARCH fit -> simulate -> optimize -> weights.
##   [I] Legacy ERC/HRP allocators (explicitly non-paper) still valid.
options(warn = 1, drp.verbose_load = FALSE)
suppressPackageStartupMessages(library(data.table))
this_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA_character_)
if (is.na(this_dir)) this_dir <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/portfolio/frontier_hrp"
source(file.path(this_dir, "dynamic_regime_rp.R"))

pass <- 0L; fail <- 0L
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { cat(sprintf("  PASS  %-52s %s\n", name, detail)); pass <<- pass + 1L }
  else { cat(sprintf("  FAIL  %-52s %s\n", name, detail)); fail <<- fail + 1L }
}
set.seed(20260703)

cat("\n=== [A] stdNTS density (Sec 2.3): FFT char-fn inversion ===\n")
lambda <- 0.8; theta <- 1.5; beta <- 0.3
f <- nts_pdf_fft(lambda, theta, beta)
xs <- seq(-15, 15, by = 0.002); dxq <- 0.002; dd <- f(xs)
integ <- sum(dd) * dxq; mn <- sum(xs * dd) * dxq; vr <- sum(xs^2 * dd) * dxq
chk("stdNTS density integrates to 1", abs(integ - 1) < 0.01, sprintf("integral=%.4f", integ))
chk("stdNTS mean = 0", abs(mn) < 0.01, sprintf("mean=%.4f", mn))
chk("stdNTS variance = 1", abs(vr - 1) < 0.02, sprintf("var=%.4f", vr))
sk <- sum(xs^3 * dd) * dxq
chk("stdNTS skew sign tracks beta>0", sk > 0, sprintf("skew=%.3f", sk))
f_neg <- nts_pdf_fft(lambda, theta, -0.3)
sk_neg <- sum(xs^3 * f_neg(xs)) * dxq
chk("stdNTS skew sign flips with beta<0", sk_neg < 0, sprintf("skew=%.3f", sk_neg))

cat("\n=== [B] CTS subordinator (Sec 2.3): exact cumulants ===\n")
a <- lambda / 2
T <- rcts_subordinator(3e5, lambda, theta)
chk("subordinator all positive", all(T > 0))
chk("E[T] = 1", abs(mean(T) - 1) < 0.02, sprintf("E[T]=%.4f", mean(T)))
chk("Var[T] = (1-a)/theta", abs(var(T) - (1 - a) / theta) < 0.03,
    sprintf("Var=%.4f want=%.4f", var(T), (1 - a) / theta))

cat("\n=== [C] NTS MLE recovery (Sec 3.2 Step 2/4) ===\n")
g <- .nts_gamma(lambda, theta, beta)
X <- beta * (T - 1) + sqrt(T) * g * rnorm(length(T))
fp <- fit_stdnts_mle(X, init = c(1.0, 1.0, 0.1), fit_skew = TRUE)
chk("MLE lambda recovered (<0.10 abs)", abs(fp$lambda - lambda) < 0.10, sprintf("est=%.3f true=%.2f", fp$lambda, lambda))
chk("MLE theta recovered (<0.30 abs)", abs(fp$theta - theta) < 0.30, sprintf("est=%.3f true=%.2f", fp$theta, theta))
chk("MLE beta (skew) recovered (<0.08 abs)", abs(fp$beta - beta) < 0.08, sprintf("est=%.3f true=%.2f", fp$beta, beta))
## fixed-(lambda,theta) skew curve-fit (Step 4) recovers beta
b4 <- fit_asset_skew(X, lambda, theta)
chk("Step-4 skew curve-fit recovers beta", abs(b4 - beta) < 0.08, sprintf("est=%.3f true=%.2f", b4, beta))

cat("\n=== [D] NTS beats t on fat/skew tails (Table 1 stylized fact) ===\n")
## data = fat-tailed skewed (true NTS). KS distance of best-fit NTS vs best-fit t.
Xd <- X[1:20000]
Fn <- ecdf(Xd)
## NTS fit cdf
fn2 <- nts_pdf_fft(fp$lambda, fp$theta, fp$beta)
gx <- seq(-12, 12, by = 0.01); dn <- fn2(gx); cdf_nts <- cumsum(dn) * 0.01
cdf_nts <- cdf_nts / max(cdf_nts)
ks_nts <- max(abs(approx(gx, cdf_nts, Xd, rule = 2)$y - Fn(Xd)))
## t fit (MLE dof + scale) via fitdistr-like on standardized data
tll <- function(nu) -sum(dt(Xd * sqrt(nu / (nu - 2)), df = nu, log = TRUE) + 0.5 * log(nu / (nu - 2)))
nu <- optimize(tll, c(2.5, 30))$minimum
sc <- sqrt(nu / (nu - 2))
ks_t <- max(abs(pt(Xd * sc, df = nu) - Fn(Xd)))
chk("NTS KS distance < t KS distance (Table1)", ks_nts < ks_t,
    sprintf("KS_NTS=%.4f KS_t=%.4f nu=%.2f", ks_nts, ks_t, nu))

cat("\n=== [E] MS-GARCH regime extraction (Sec 3.1 Step1; Table2) ===\n")
## simulate a 2-regime GARCH-ish index: low-vol block, high-vol block.
gen_regime_ret <- function() {
  n1 <- 900; n2 <- 300; n3 <- 900
  s <- c(rep(1L, n1), rep(2L, n2), rep(1L, n3))
  x <- numeric(length(s)); sig <- 0.008
  for (t in seq_along(s)) {
    base <- if (s[t] == 2L) 0.022 else 0.007
    sig <- sqrt(0.05 * base^2 + 0.10 * (if (t > 1) x[t-1]^2 else base^2) + 0.85 * sig^2)
    x[t] <- rt(1, df = 6) / sqrt(6 / 4) * sig
  }
  list(x = x, s = s)
}
gi <- gen_regime_ret()
mf <- fit_msgarch(gi$x, K = 2L, dist = "std")
chk("MS-GARCH backend = MSGARCH", identical(mf$backend, "MSGARCH"), sprintf("backend=%s", mf$backend))
chk("2 states fitted", mf$K == 2L)
chk("transition self-persistence high (Table2 style)",
    all(diag(mf$P) > 0.90), sprintf("P11=%.3f P22=%.3f", mf$P[1,1], mf$P[2,2]))
## regime2 (by unc-vol) more volatile; conditional sigma higher when true s==2
sig_hi <- mean(mf$sigma_t[gi$s == 2L]); sig_lo <- mean(mf$sigma_t[gi$s == 1L])
chk("conditional sigma higher in true high-vol block", sig_hi > sig_lo,
    sprintf("hi=%.4f lo=%.4f", sig_hi, sig_lo))

cat("\n=== [F] Sigma_DeltaD Step-5 formula + Table3 stylized fact ===\n")
## N-asset panel: high-vol regime injects strong common factor -> higher corr (Table3).
Nass <- 8L; Tn <- length(gi$x)
common <- rnorm(Tn)
R <- matrix(0, Tn, Nass)
for (t in 1:Tn) {
  if (gi$s[t] == 2L) R[t, ] <- 0.9 * common[t] * 0.022 + rnorm(Nass, 0, 0.006)
  else               R[t, ] <- 0.2 * common[t] * 0.007 + rnorm(Nass, 0, 0.007)
}
colnames(R) <- paste0("A", 1:Nass)
mdl <- fit_mrs_mnts_garch(gi$x, R, K_grid = c(2L, 3L), denoise = TRUE)
chk("MRS-MNTS-GARCH fitted K>=2", mdl$K >= 2L, sprintf("K=%d", mdl$K))
## every regime has stdMNTS params + PD Sigma_D
allpd <- all(vapply(mdl$regimes, function(r) !is.null(r) && .drp_is_pd(r$Sigma), logical(1)))
chk("all regime Sigma_DeltaD are PD", allpd)
haspar <- all(vapply(mdl$regimes, function(r) is.finite(r$lambda) && is.finite(r$theta) && length(r$beta) == Nass, logical(1)))
chk("all regimes have (lambda,theta,beta) stdMNTS params", haspar)
## Step-5 skew-removal term actually applied: Sigma_D != raw Sigma_X when beta!=0
diff_applied <- any(vapply(mdl$regimes, function(r) {
  if (is.null(r)) return(FALSE)
  coef <- (2 - r$lambda) / (2 * r$theta)
  removed <- coef * outer(r$beta, r$beta)
  max(abs(removed)) > 1e-6
}, logical(1)))
chk("Step-5 skew-removal term nonzero (not raw sample cov)", diff_applied)
## Table3: regime with higher vol has higher mean innovation correlation
offcor <- function(S) { s <- sqrt(diag(S)); C <- S / outer(s, s); mean(C[upper.tri(C)]) }
## identify volatile regime by index unc vol ordering: regime index with higher realized vol
regvol <- vapply(seq_len(mdl$K), function(k) {
  ik <- which(mdl$path == k); if (length(ik) < 2) return(NA_real_)
  mean(mdl$index_fit$sigma_t[ik])
}, numeric(1))
kv <- order(regvol)
c_lo <- offcor(mdl$regimes[[kv[1]]]$Sigma_X)
c_hi <- offcor(mdl$regimes[[kv[length(kv)]]]$Sigma_X)
chk("volatile regime higher joint-innov corr (Table3)", c_hi > c_lo,
    sprintf("corr_lo=%.3f corr_hi=%.3f", c_lo, c_hi))

cat("\n=== [G] CVaR / CDaR LP optimizers (Sec 4; Table4 ordering) ===\n")
## build synthetic scenario asset compounded returns [S,N]: one asset fat left tail.
set.seed(31); Ssc <- 3000L; Nsc <- 6L
mu_sc <- c(0.012, 0.010, 0.008, 0.006, 0.004, -0.002)
L <- matrix(rt(Ssc * Nsc, df = 5), Ssc, Nsc) * 0.02
L[, 6] <- L[, 6] - 0.03 * (runif(Ssc) < 0.1)   # asset6 fat left tail
A <- sweep(L, 2, mu_sc, "+"); colnames(A) <- paste0("Z", 1:Nsc)
r_cvar <- cvar_optimize(A, alpha = 0.5, d = NULL, lb = 0.01, ub = 0.30)
chk("CVaR LP solved (status 0)", r_cvar$status == 0)
chk("CVaR weights sum to 1", abs(sum(r_cvar$weights) - 1) < 1e-6)
chk("CVaR weights in box [0.01,0.30]", all(r_cvar$weights >= 0.01 - 1e-9) && all(r_cvar$weights <= 0.30 + 1e-9))
## CVaR portfolio has lower loss-CVaR than equal weight (Table4: optimized beats EW)
ew <- rep(1 / Nsc, Nsc)
cvar_of <- function(w, al) { L2 <- -as.numeric(A %*% w); z <- quantile(L2, al); z + mean(pmax(L2 - z, 0)) / (1 - al) }
chk("CVaR-opt lower tail risk than EW (Table4)", cvar_of(r_cvar$weights, 0.5) < cvar_of(ew, 0.5),
    sprintf("opt=%.4f ew=%.4f", cvar_of(r_cvar$weights, 0.5), cvar_of(ew, 0.5)))
## CDaR LP on a small simulated path array [S,H,N]
set.seed(32); Sp <- 40L; Hp <- 10L; Np <- 5L
simA <- array(rt(Sp * Hp * Np, df = 6) * 0.015, dim = c(Sp, Hp, Np))
for (n in 1:Np) simA[, , n] <- simA[, , n] + mu_sc[n] / Hp
dimnames(simA) <- list(NULL, NULL, paste0("Z", 1:Np))
r_cdar <- cdar_optimize(simA, alpha = 0.3, d = NULL, lb = 0.01, ub = 0.40)
chk("CDaR LP solved (status 0)", r_cdar$status == 0)
chk("CDaR weights sum to 1", abs(sum(r_cdar$weights) - 1) < 1e-6)
chk("CDaR weights long-only in box", all(r_cdar$weights >= 0.01 - 1e-9) && all(r_cdar$weights <= 0.40 + 1e-9))

cat("\n=== [H] End-to-end MRS-MNTS-GARCH -> simulate -> optimize ===\n")
## reuse mdl from [F]; add regime means then simulate + optimize both risk measures.
pth <- mdl$path
rm_mat <- matrix(0, mdl$K, Nass)
for (k in seq_len(mdl$K)) { ik <- which(pth == k); if (length(ik) >= 5) rm_mat[k, ] <- colMeans(R[ik, , drop = FALSE]) }
mdl$regime_means <- rm_mat
sim <- simulate_mrs_mnts(mdl, S = 2000L, H = 10L, seed = 7L)
chk("simulation dims [S,H,N]", all(dim(sim) == c(2000L, 10L, Nass)), paste(dim(sim), collapse = "x"))
chk("simulated returns finite", all(is.finite(sim)))
## simulated returns fat-tailed (kurtosis > 3 from NTS)
kurt <- mean(apply(sim, 3, function(m) { v <- as.numeric(m); mean((v - mean(v))^4) / var(v)^2 }))
chk("simulated innovations fat-tailed (kurt>3)", kurt > 3.0, sprintf("mean kurt=%.2f", kurt))
w_cdar <- optimize_pkm_portfolio(sim, measure = "0.3-CDaR", lb = 0.01, ub = 0.30)
w_cvar <- optimize_pkm_portfolio(sim, measure = "0.5-CVaR", lb = 0.01, ub = 0.30)
chk("0.3-CDaR portfolio valid", abs(sum(w_cdar$weights) - 1) < 1e-6 && all(w_cdar$weights >= 0))
chk("0.5-CVaR portfolio valid", abs(sum(w_cvar$weights) - 1) < 1e-6 && all(w_cvar$weights >= 0))
## full single-shot wrapper
out <- dynamic_regime_rp_weights(R, gi$x, method = "cdar", measure = "0.3-CDaR",
                                 S = 1500L, H = 10L, lb = 0.01, ub = 0.20, max_w = 0.20, seed = 11L)
chk("dynamic_regime_rp_weights(cdar) valid", abs(sum(out$weights) - 1) < 1e-6 && all(out$weights >= 0))
chk("weights respect max_w cap", max(out$weights) <= 0.20 + 1e-9, sprintf("max=%.4f", max(out$weights)))

cat("\n=== [I] Legacy non-paper allocators (ERC/HRP) — explicitly labelled ===\n")
Sig <- matrix(c(0.10,0.02,0.01, 0.02,0.20,0.03, 0.01,0.03,0.30), 3, 3, byrow = TRUE)
colnames(Sig) <- rownames(Sig) <- c("x","y","z")
w_erc <- erc_weights(Sig); rcf <- risk_contributions(Sig, w_erc)$rc_frac
chk("ERC equalizes risk contributions", (max(rcf) - min(rcf)) < 1e-6,
    sprintf("rcf spread=%.2e", max(rcf) - min(rcf)))
Sd <- diag(c(0.04, 0.09, 0.16)); colnames(Sd) <- rownames(Sd) <- c("a","b","c")
iv <- (1/sqrt(diag(Sd))); iv <- iv/sum(iv)
chk("ERC(diag)==inverse-vol", max(abs(erc_weights(Sd) - iv)) < 1e-6)
set.seed(1); Xh <- cbind(rnorm(800), rnorm(800), rnorm(800), rnorm(800))
Xh[,2] <- Xh[,1] + rnorm(800, 0, 0.1); colnames(Xh) <- c("c1a","c1b","c2","ind")
w_hrp <- hrp_weights(cov(Xh))
chk("HRP weights valid", abs(sum(w_hrp) - 1) < 1e-8 && all(w_hrp > 0))
out_leg <- dynamic_regime_rp_weights(R, gi$x, method = "hrp", max_w = 0.20)
chk("legacy path labels non-paper", grepl("LEGACY", out_leg$note))

cat(sprintf("\n==== RESULT: %d PASS / %d FAIL ====\n", pass, fail))
if (fail > 0) quit(status = 1)
