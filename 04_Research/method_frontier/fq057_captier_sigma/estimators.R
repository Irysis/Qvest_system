# =============================================================================
# FQ-057 estimator library
# Candidates (method shopping cap = 5, R2-C):
#   1. sample            — cov() baseline
#   2. lw_linear         — hrp_core .get_cor_cov("ledoit_wolf") REUSE (mandated)
#   3. lw_nls            — Ledoit-Wolf 2020 analytical nonlinear shrinkage
#                          (own port of analytical_shrinkage.m; nlshrink pkg absent)
#   4. block_lw          — cap-tier block: within-tier lw_linear blocks +
#                          cross-tier 1-factor (market) implied cov + PSD repair
#   5. block_nls         — cap-tier block: within-tier lw_nls blocks +
#                          cross-tier 1-factor (market) implied cov + PSD repair
# All estimation-quality only. No SR/IR/alpha anywhere in this file.
# =============================================================================

# ---- hrp_core reuse (defines .get_cor_cov) ----------------------------------
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/portfolio/hrp_core.R")

est_sample <- function(R) {
  S <- cov(R, use = "pairwise.complete.obs")
  S[is.na(S)] <- 0
  S
}

est_lw_linear <- function(R) {
  .get_cor_cov(R, "ledoit_wolf")$cov
}

# ---- Ledoit-Wolf (2020) analytical nonlinear shrinkage ----------------------
# Port of analytical_shrinkage.m (Ledoit & Wolf 2020, Annals of Statistics 48(5)).
# Epanechnikov kernel density + Hilbert transform on sample eigenvalues.
est_lw_nls <- function(R) {
  n <- nrow(R); p <- ncol(R)
  X <- scale(R, center = TRUE, scale = FALSE)
  n_eff <- n - 1                              # effective sample size (paper)
  S <- crossprod(X) / n_eff
  eg <- eigen(S, symmetric = TRUE)
  lambda_all <- rev(eg$values)                # ascending
  u <- eg$vectors[, rev(seq_len(p)), drop = FALSE]
  keep <- max(1, p - n_eff + 1):p
  lambda <- lambda_all[keep]
  lambda[lambda < .Machine$double.eps] <- .Machine$double.eps
  m <- length(lambda)                         # = min(p, n_eff)
  L  <- matrix(lambda, nrow = m, ncol = m)    # lambda in rows repeated cols
  Ht <- (n_eff^(-1/3)) * t(L)                 # bandwidth matrix H = h * lambda_j
  x  <- (L - t(L)) / Ht
  ftilde <- (3 / (4 * sqrt(5))) * rowMeans(pmax(1 - x^2 / 5, 0) / Ht)
  Hftemp <- (-3 / (10 * pi)) * x +
            (3 / (4 * sqrt(5) * pi)) * (1 - x^2 / 5) *
            log(abs((sqrt(5) - x) / (sqrt(5) + x)))
  sel <- abs(x) == sqrt(5)
  if (any(sel)) Hftemp[sel] <- (-3 / (10 * pi)) * x[sel]
  Hftemp[!is.finite(Hftemp)] <- 0
  Hftilde <- rowMeans(Hftemp / Ht)
  c_ratio <- p / n_eff
  if (p <= n_eff) {
    dtilde <- lambda / ((pi * c_ratio * lambda * ftilde)^2 +
                        (1 - c_ratio - pi * c_ratio * lambda * Hftilde)^2)
  } else {
    h <- n_eff^(-1/3)
    Hftilde0 <- (1 / pi) * (3 / (10 * h^2) +
                 3 / (4 * sqrt(5) * h) * (1 - 1 / (5 * h^2)) *
                 log((1 + sqrt(5) * h) / (1 - sqrt(5) * h))) * mean(1 / lambda)
    dtilde0 <- 1 / (pi * (p - n_eff) / n_eff * Hftilde0)
    dtilde1 <- lambda / (pi^2 * lambda^2 * (ftilde^2 + Hftilde^2))
    dtilde  <- c(rep(dtilde0, p - n_eff), dtilde1)
  }
  Sig <- u %*% diag(dtilde) %*% t(u)
  Sig <- (Sig + t(Sig)) / 2
  dimnames(Sig) <- dimnames(S)
  Sig
}

# ---- PSD repair (eigenvalue clip) + violation report ------------------------
psd_repair <- function(Sig, eps_rel = 1e-10) {
  eg <- eigen(Sig, symmetric = TRUE)
  min_ev <- min(eg$values)
  max_ev <- max(eg$values)
  violated <- min_ev < -1e-8 * max(1, max_ev)
  if (min_ev < eps_rel * max_ev) {
    ev <- pmax(eg$values, eps_rel * max_ev)
    Sig2 <- eg$vectors %*% diag(ev) %*% t(eg$vectors)
    Sig2 <- (Sig2 + t(Sig2)) / 2
    dimnames(Sig2) <- dimnames(Sig)
  } else Sig2 <- Sig
  list(Sig = Sig2, min_ev_pre = min_ev, psd_violated_pre = violated)
}

# ---- cap-tier block estimator -----------------------------------------------
# R      : n x p return matrix (colnames = tickers)
# tier   : character vector length p in {"MEGA","MID","SMALL"}
# mkt    : n-vector market (cap-weighted universe) return over same window
# inner  : "lw" (linear, hrp_core reuse) or "nls" (analytical NLS)
# Cross-tier blocks replaced by 1-factor implied cov: beta_i beta_j var(mkt).
# Within-tier blocks keep full shrunk structure. PSD via eigenvalue clip.
est_block <- function(R, tier, mkt, inner = c("lw", "nls")) {
  inner <- match.arg(inner)
  p <- ncol(R)
  stopifnot(length(tier) == p, length(mkt) == nrow(R))
  Sig <- matrix(0, p, p, dimnames = list(colnames(R), colnames(R)))
  for (tr in unique(tier)) {
    idx <- which(tier == tr)
    if (length(idx) == 1) {
      Sig[idx, idx] <- var(R[, idx])
    } else {
      sub <- R[, idx, drop = FALSE]
      Sig[idx, idx] <- if (inner == "lw") est_lw_linear(sub) else est_lw_nls(sub)
    }
  }
  vm <- var(mkt)
  b  <- as.numeric(cov(R, mkt)) / vm          # OLS betas on window
  Fmat <- outer(b, b) * vm
  cross <- outer(tier, tier, FUN = `!=`)
  Sig[cross] <- Fmat[cross]
  Sig <- (Sig + t(Sig)) / 2
  psd_repair(Sig)
}

# ---- diagnostics helpers ----------------------------------------------------
cond_number <- function(Sig) {
  ev <- eigen(Sig, symmetric = TRUE, only.values = TRUE)$values
  if (min(ev) <= 0) return(Inf)
  max(ev) / min(ev)
}

mvp_weights <- function(Sig) {
  # minimum-variance portfolio weights (unconstrained) — ESTIMATION-QUALITY
  # INSTRUMENT ONLY (Ledoit-Wolf horse-race convention), not an allocation.
  ones <- rep(1, ncol(Sig))
  wi <- tryCatch(solve(Sig, ones), error = function(e) {
    as.numeric(MASS::ginv(Sig) %*% ones)
  })
  as.numeric(wi) / sum(wi)
}

frob_rel <- function(A, B) {
  common <- intersect(colnames(A), colnames(B))
  a <- A[common, common]; b <- B[common, common]
  sqrt(sum((a - b)^2)) / length(common)
}

cor_offdiag_rmse <- function(A, B) {
  common <- intersect(colnames(A), colnames(B))
  a <- cov2cor(A[common, common]); b <- cov2cor(B[common, common])
  lt <- lower.tri(a)
  sqrt(mean((a[lt] - b[lt])^2))
}
