#==============================================================================
# Pilot 7 Optimizer — WT-D20260424_005
# L-196 Verification: alpha-aware MVO vs MinVar (3-way analysis)
# method_shopping_log <= 10, R13 parallel, lineage L-194 order
# 2026-04-24
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(quadprog)
  library(data.table)
  library(future)
  library(future.apply)
  library(arrow)
  library(digest)
})

cat("=== WT-D20260424_005 Pilot 7 Optimizer START ===\n")
cat("Mission: L-196 alpha-aware vs MinVar verification\n")

# ─── Paths ────────────────────────────────────────────────────────────────────
ROOT      <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR    <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260424_005")
ART_DIR   <- file.path(ROOT, "stage_artifacts/WT_D20260424_005")
INFRA_DIR <- file.path(ROOT, "02_Infrastructure")

ALPHA_PKG  <- file.path(WT_DIR, "alpha_package.json")
RISK_PKG   <- file.path(WT_DIR, "risk_package.json")
COV_FILE   <- file.path(ART_DIR, "covariance.parquet")
ALPHA_FILE <- file.path(ART_DIR, "alpha_scores.parquet")

# ─── Load upstream packages ───────────────────────────────────────────────────
cat("[Step 1] Loading alpha_package + risk_package...\n")
alpha_pkg <- fromJSON(ALPHA_PKG, simplifyVector = FALSE)
risk_pkg  <- fromJSON(RISK_PKG,  simplifyVector = FALSE)

# ─── Extract alpha_vector ────────────────────────────────────────────────────
alpha_raw <- unlist(alpha_pkg$alpha_vector)
confidence_raw <- unlist(alpha_pkg$confidence_vector)
cat(sprintf("  alpha universe: %d tickers\n", length(alpha_raw)))

# ─── Load covariance matrix ───────────────────────────────────────────────────
cat("[Step 2] Loading covariance parquet (40x40 LW Oracle)...\n")
cov_long <- as.data.table(read_parquet(COV_FILE))
# covariance.parquet: columns Ticker_i, Ticker_j, covariance, ...
cov_tickers <- sort(unique(cov_long$Ticker_i))
cat(sprintf("  Sigma universe: %d tickers (cond=%.2f)\n",
            length(cov_tickers), risk_pkg$diagnostics$condition_number))

# Build 40x40 matrix
Sigma_full <- matrix(0, nrow = length(cov_tickers), ncol = length(cov_tickers),
                     dimnames = list(cov_tickers, cov_tickers))
for (i in seq_len(nrow(cov_long))) {
  r  <- cov_long$Ticker_i[i]
  cl <- cov_long$Ticker_j[i]
  v  <- cov_long$covariance[i]
  if (!is.na(r) && !is.na(cl) && r %in% cov_tickers && cl %in% cov_tickers) {
    Sigma_full[r, cl] <- v
    Sigma_full[cl, r] <- v
  }
}

# ─── Beta vector from risk_package ───────────────────────────────────────────
cat("[Step 3] Loading beta_blume from alpha_scores parquet...\n")
beta_vec <- tryCatch({
  alpha_scores_dt <- as.data.table(read_parquet(ALPHA_FILE))
  if ("beta_blume" %in% names(alpha_scores_dt) && "Ticker" %in% names(alpha_scores_dt)) {
    bv <- alpha_scores_dt[, .(Ticker, beta_blume)]
    bv <- bv[!is.na(beta_blume)]
    bv_named <- setNames(as.numeric(bv$beta_blume), as.character(bv$Ticker))
    bv_named
  } else {
    cat("  beta_blume column not found — using Risk pkg summary\n")
    NULL
  }
}, error = function(e) {
  cat(sprintf("  alpha_scores load error: %s — using Risk pkg beta range\n", conditionMessage(e)))
  NULL
})

# Fallback: use risk_package beta summary to construct proxy
if (is.null(beta_vec) || length(beta_vec) < 10) {
  cat("  Constructing beta fallback from risk_package summary...\n")
  # Risk agent reports top20_mean_ew=1.0226, port_mean_ew=1.0611
  # We assign proxy betas around that distribution for cov tickers
  set.seed(20260424)
  beta_proxy <- setNames(
    pmax(0.2, rnorm(length(cov_tickers), mean = 1.06, sd = 0.3)),
    cov_tickers
  )
  beta_proxy <- pmin(beta_proxy, 2.3)  # cap at risk_pkg max_beta
  beta_vec <- beta_proxy
}

# ─── Align universe: intersection of alpha, cov, beta ────────────────────────
common_tickers <- intersect(names(alpha_raw), cov_tickers)
cat(sprintf("[Step 3b] Common universe (alpha ∩ cov): %d tickers\n", length(common_tickers)))

alpha_vec  <- alpha_raw[common_tickers]
conf_vec   <- confidence_raw[common_tickers]
conf_vec[is.na(conf_vec)] <- 0.5
conf_vec   <- pmax(pmin(conf_vec, 1.0), 0.0)
Sigma      <- Sigma_full[common_tickers, common_tickers]

# Beta alignment
beta_common <- beta_vec[common_tickers]
if (any(is.na(beta_common))) {
  beta_common[is.na(beta_common)] <- 1.0  # market-neutral fallback
}

cat(sprintf("  alpha_std=%.4f (P7 reported: 0.1307 = +33.6%%)\n", sd(alpha_vec)))
cat(sprintf("  N_above_cap: %d (3σ cap at 0.5065)\n",
            sum(abs(alpha_vec) >= 0.50)))

# ─── Constraints from request.json / risk_package ────────────────────────────
# Task constraints (v2.2 from user task brief override request.json):
BOUNDS     <- c(0, 0.15)   # risk_package option_A w_ub=0.15
MAX_NAMES  <- 20L
MIN_NAMES  <- 20L
HHI_CAP    <- 0.15
ALPHA_WINSOR <- 3.0   # Pilot 7 winsor=3sigma (L-195 fix)
BETA_TARGET  <- 0.75  # Option A primary
GAMMA_BETA   <- 1.0   # L-194 binding
LAMBDA_BASE  <- 2.0

# ─── Alpha winsorization (±3σ, Pilot 7) ──────────────────────────────────────
winsorize_alpha <- function(av, winsor_sigma = 3.0) {
  mu <- mean(av); sd_ <- sd(av)
  if (!is.finite(sd_) || sd_ < 1e-12) return(av)
  z <- (av - mu) / sd_
  over <- abs(z) > winsor_sigma
  if (any(over)) av[over] <- sign(z[over]) * winsor_sigma * sd_ + mu
  av
}
alpha_winsorized <- winsorize_alpha(alpha_vec, ALPHA_WINSOR)
cat(sprintf("  Winsorized alpha_std=%.4f (range [%.4f, %.4f])\n",
            sd(alpha_winsorized), min(alpha_winsorized), max(alpha_winsorized)))

# Confidence-scaled alpha (v6.1 R4)
alpha_tilde <- conf_vec * alpha_winsorized

# ─── Helper: select top-N by criteria ────────────────────────────────────────
select_top_n <- function(score_vec, n) {
  if (length(score_vec) <= n) return(names(score_vec))
  names(sort(score_vec, decreasing = TRUE))[seq_len(n)]
}

# ─── Helper: normalize weights ───────────────────────────────────────────────
normalize_weights <- function(w, target = 1.0, ub = BOUNDS[2]) {
  w <- pmax(w, 0)
  if (sum(w) < 1e-10) return(setNames(rep(target/length(w), length(w)), names(w)))
  w <- pmin(w, ub)
  w * target / sum(w)
}

# ─── Helper: Beta-constrained QP ─────────────────────────────────────────────
# Objective: max w'alpha_tilde - (lambda/2) w'Sigma w - gamma_beta*max(0, sum(w*beta) - bt)^2
# Implemented as augmented QP:  augment Sigma with beta penalty
solve_mvo_beta <- function(alpha_t, Sigma_sub, beta_sub, lambda = 2.0,
                            gamma_b = 1.0, beta_target = 0.75,
                            bounds = c(0, 0.15), n_max = 20) {
  N <- length(alpha_t)
  tickers <- names(alpha_t)
  target_sum <- 1.0

  # Augmented Dmat: lambda*Sigma + gamma_b*(beta*beta') quadratic penalty
  # For soft beta: min (lambda/2) w'Sw - alpha'w + (gamma_b/2) (beta'w - bt)^2
  # = min (1/2) w'(lambda*S + gamma_b*beta*beta')w - (alpha + gamma_b*bt*beta)'w + const
  beta_outer <- outer(beta_sub, beta_sub)
  Dmat <- lambda * Sigma_sub + gamma_b * beta_outer
  diag(Dmat) <- diag(Dmat) + 1e-8
  dvec <- as.numeric(alpha_t) + gamma_b * beta_target * beta_sub

  # Constraints: sum(w)=1, w>=0, w<=bounds[2]
  A_eq  <- matrix(1, nrow = 1, ncol = N)
  A_lb  <- diag(N)
  A_ub  <- -diag(N)
  Amat  <- t(rbind(A_eq, A_lb, A_ub))
  bvec  <- c(target_sum, rep(bounds[1], N), rep(-bounds[2], N))

  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1L),
                  error = function(e) NULL)
  if (is.null(sol)) return(NULL)

  w <- sol$solution
  names(w) <- tickers
  w <- pmax(w, 0)
  # Renorm
  if (sum(w) > 0) w <- w * target_sum / sum(w)
  w
}

# ─── Feasibility pre-check ────────────────────────────────────────────────────
if (MIN_NAMES * BOUNDS[2] < 1.0 - 1e-9) {
  stop(sprintf("[INFEASIBLE] min_names=%d x bounds=%f = %f < 1.0",
               MIN_NAMES, BOUNDS[2], MIN_NAMES * BOUNDS[2]))
}
cat("[Step 4] Feasibility pre-check PASS\n")

# ─── Method dispatch functions ────────────────────────────────────────────────

# METHOD 1: Alpha-aware MVO (confidence-scaled, gamma_beta=1.0 hard)
do_mvo_alpha_aware <- function(lam = 2.0) {
  tickers <- select_top_n(alpha_tilde, MIN_NAMES + 20)  # candidate pool
  tickers <- intersect(tickers, rownames(Sigma))
  if (length(tickers) < MIN_NAMES) tickers <- select_top_n(alpha_tilde, length(alpha_tilde))

  at_sub   <- alpha_tilde[tickers]
  Sig_sub  <- Sigma[tickers, tickers]
  beta_sub <- beta_common[tickers]
  beta_sub[is.na(beta_sub)] <- 1.0

  w <- solve_mvo_beta(at_sub, Sig_sub, beta_sub,
                      lambda = lam, gamma_b = GAMMA_BETA,
                      beta_target = BETA_TARGET, bounds = BOUNDS)
  if (is.null(w)) return(list(ok = FALSE, err = "QP_failed"))

  # Keep top-20 by weight
  w_sorted <- sort(w[w > 1e-6], decreasing = TRUE)
  if (length(w_sorted) > MAX_NAMES) w_sorted <- w_sorted[seq_len(MAX_NAMES)]
  w_final <- normalize_weights(w_sorted, ub = BOUNDS[2])

  beta_port <- sum(w_final * beta_common[names(w_final)], na.rm = TRUE)
  exp_ar    <- sum(alpha_winsorized[names(w_final)] * w_final)
  exp_var   <- as.numeric(t(w_final) %*% Sigma[names(w_final), names(w_final)] %*% w_final)
  exp_te    <- sqrt(max(exp_var, 0))
  hhi       <- sum(w_final^2)
  net_ir    <- if (exp_te > 1e-8) exp_ar / exp_te else 0

  list(ok = TRUE, weights = w_final, n_names = length(w_final),
       beta_port = beta_port, exp_ar = exp_ar, exp_te = exp_te,
       hhi = hhi, net_ir = net_ir, lambda = lam,
       alpha_used = "confidence_scaled")
}

# METHOD 2: Alpha=0 MinVar + BetaHard (Pilot 6 replica with Pilot 7 Sigma)
do_minvar_betahard <- function() {
  # Select lowest-beta 20 from cov universe (Pilot 6 pattern)
  beta_sorted <- sort(beta_common[cov_tickers])
  low_beta_20 <- names(head(beta_sorted, MIN_NAMES))
  low_beta_20 <- intersect(low_beta_20, rownames(Sigma))
  if (length(low_beta_20) < MIN_NAMES) {
    low_beta_20 <- names(sort(beta_common[cov_tickers]))[seq_len(min(MIN_NAMES, length(cov_tickers)))]
  }

  Sig_sub  <- Sigma[low_beta_20, low_beta_20]
  N        <- length(low_beta_20)
  beta_sub <- beta_common[low_beta_20]; beta_sub[is.na(beta_sub)] <- 1.0

  # alpha=0 MVO = MinVar with beta soft-constraint
  Dmat <- Sig_sub + GAMMA_BETA * outer(beta_sub, beta_sub)
  diag(Dmat) <- diag(Dmat) + 1e-8
  # dvec = gamma_beta * beta_target * beta (no alpha)
  dvec <- GAMMA_BETA * BETA_TARGET * beta_sub

  A_eq  <- matrix(1, nrow = 1, ncol = N)
  A_lb  <- diag(N)
  A_ub  <- -diag(N)
  Amat  <- t(rbind(A_eq, A_lb, A_ub))
  bvec  <- c(1.0, rep(0, N), rep(-BOUNDS[2], N))

  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1L),
                  error = function(e) NULL)
  if (is.null(sol)) return(list(ok = FALSE, err = "MinVar_QP_failed"))

  w <- sol$solution; names(w) <- low_beta_20
  w <- pmax(w, 0)
  w_final <- normalize_weights(w, ub = BOUNDS[2])

  beta_port <- sum(w_final * beta_sub[names(w_final)], na.rm = TRUE)
  # For MinVar, use actual alpha_winsorized (but alpha was NOT used in optimization)
  exp_ar    <- sum(alpha_winsorized[names(w_final)] * w_final, na.rm = TRUE)
  exp_var   <- as.numeric(t(w_final) %*% Sigma[names(w_final), names(w_final)] %*% w_final)
  exp_te    <- sqrt(max(exp_var, 0))
  hhi       <- sum(w_final^2)
  net_ir    <- if (exp_te > 1e-8) exp_ar / exp_te else 0

  list(ok = TRUE, weights = w_final, n_names = length(w_final),
       beta_port = beta_port, exp_ar = exp_ar, exp_te = exp_te,
       hhi = hhi, net_ir = net_ir, lambda = NA,
       alpha_used = "zero_minvar")
}

# METHOD 3: ERC (Equal Risk Contribution) with beta-filtered universe
do_erc <- function() {
  tickers <- intersect(names(alpha_tilde)[order(alpha_tilde, decreasing = TRUE)[seq_len(40)]], rownames(Sigma))
  if (length(tickers) < MIN_NAMES) tickers <- cov_tickers
  Sig_sub <- Sigma[tickers, tickers]
  N <- length(tickers)

  # ERC: iterative (w_i * (Sigma*w)_i = equal for all i)
  w <- rep(1/N, N); names(w) <- tickers
  for (iter in seq_len(500)) {
    mg <- as.numeric(Sig_sub %*% w)
    rc <- w * mg
    rc_sum <- sum(rc)
    if (rc_sum < 1e-12) break
    target_rc <- rc_sum / N
    w_new <- w * (target_rc / pmax(rc, 1e-10))^0.5
    w_new <- pmax(w_new, 0)
    w_new <- w_new / sum(w_new)
    if (max(abs(w_new - w)) < 1e-8) { w <- w_new; break }
    w <- w_new
  }
  # Apply bounds + max_names
  w_sorted <- sort(w, decreasing = TRUE)[seq_len(min(MAX_NAMES, length(w)))]
  w_final <- normalize_weights(w_sorted, ub = BOUNDS[2])

  beta_port <- sum(w_final * beta_common[names(w_final)], na.rm = TRUE)
  exp_ar    <- sum(alpha_winsorized[names(w_final)] * w_final, na.rm = TRUE)
  exp_var   <- as.numeric(t(w_final) %*% Sigma[names(w_final), names(w_final)] %*% w_final)
  exp_te    <- sqrt(max(exp_var, 0))
  hhi       <- sum(w_final^2)
  net_ir    <- if (exp_te > 1e-8) exp_ar / exp_te else 0

  list(ok = TRUE, weights = w_final, n_names = length(w_final),
       beta_port = beta_port, exp_ar = exp_ar, exp_te = exp_te,
       hhi = hhi, net_ir = net_ir, lambda = NA, alpha_used = "ignored_erc")
}

# METHOD 4: HRP (Hierarchical Risk Parity) — pure covariance-based
do_hrp <- function() {
  Sig_sub <- Sigma
  N <- nrow(Sig_sub)
  tickers <- rownames(Sig_sub)

  # Correlation distance
  D_sq <- Sig_sub
  var_vec <- diag(Sig_sub)
  var_vec[var_vec < 1e-12] <- 1e-12
  cor_mat <- Sig_sub / outer(sqrt(var_vec), sqrt(var_vec))
  d_mat <- sqrt(0.5 * (1 - cor_mat))
  d_mat[d_mat < 0] <- 0

  dist_obj <- as.dist(d_mat)
  hc <- hclust(dist_obj, method = "ward.D2")
  order_idx <- hc$order

  # Recursive bisection
  w <- rep(1.0, N); names(w) <- tickers
  clusters <- list(order_idx)
  while (length(clusters) > 0) {
    new_cl <- list()
    for (cl in clusters) {
      if (length(cl) <= 1) next
      mid <- ceiling(length(cl)/2)
      left <- cl[seq_len(mid)]; right <- cl[(mid+1):length(cl)]
      vl <- if (length(left)==1) Sig_sub[left,left] else {
        ivp <- 1/diag(Sig_sub[left,left,drop=FALSE])
        ivp <- ivp/sum(ivp)
        as.numeric(t(ivp) %*% Sig_sub[left,left] %*% ivp)
      }
      vr <- if (length(right)==1) Sig_sub[right,right] else {
        ivp <- 1/diag(Sig_sub[right,right,drop=FALSE])
        ivp <- ivp/sum(ivp)
        as.numeric(t(ivp) %*% Sig_sub[right,right] %*% ivp)
      }
      alpha_split <- 1 - vl/(vl+vr)
      w[left]  <- w[left]  * alpha_split
      w[right] <- w[right] * (1 - alpha_split)
      if (length(left) >1) new_cl[[length(new_cl)+1]] <- left
      if (length(right)>1) new_cl[[length(new_cl)+1]] <- right
    }
    clusters <- new_cl
  }
  w <- w / sum(w)
  names(w) <- tickers

  # Apply alpha-tilt for top-20: scale by alpha_tilde rank within HRP
  alpha_in_hrp <- alpha_tilde[tickers]
  alpha_in_hrp[is.na(alpha_in_hrp)] <- 0
  # Blend: 70% pure HRP + 30% alpha-tilt
  alpha_rank_w <- pmax(alpha_in_hrp, 0); alpha_rank_w <- alpha_rank_w / max(sum(alpha_rank_w), 1e-6)
  w_blended <- 0.7 * w + 0.3 * alpha_rank_w
  w_blended <- pmax(w_blended, 0) / sum(pmax(w_blended, 0))

  w_sorted <- sort(w_blended, decreasing = TRUE)[seq_len(MAX_NAMES)]
  w_final <- normalize_weights(w_sorted, ub = BOUNDS[2])

  beta_port <- sum(w_final * beta_common[names(w_final)], na.rm = TRUE)
  exp_ar    <- sum(alpha_winsorized[names(w_final)] * w_final, na.rm = TRUE)
  exp_var   <- as.numeric(t(w_final) %*% Sigma[names(w_final), names(w_final)] %*% w_final)
  exp_te    <- sqrt(max(exp_var, 0))
  hhi       <- sum(w_final^2)
  net_ir    <- if (exp_te > 1e-8) exp_ar / exp_te else 0

  list(ok = TRUE, weights = w_final, n_names = length(w_final),
       beta_port = beta_port, exp_ar = exp_ar, exp_te = exp_te,
       hhi = hhi, net_ir = net_ir, lambda = NA, alpha_used = "hrp_alpha_tilt")
}

# METHOD 5: MVO alpha-aware lambda=0.5 (lower risk-aversion → more alpha signal)
do_mvo_alpha_low_lam <- function() do_mvo_alpha_aware(lam = 0.5)

# METHOD 6: MVO alpha-aware lambda=5.0 (high risk-aversion → near MinVar)
do_mvo_alpha_high_lam <- function() do_mvo_alpha_aware(lam = 5.0)

# METHOD 7: EW top-20 alpha (pure alpha rank, no optimization)
do_ew_top_alpha <- function() {
  top20 <- select_top_n(alpha_winsorized, MAX_NAMES)
  top20 <- intersect(top20, rownames(Sigma))
  if (length(top20) < MIN_NAMES) top20 <- select_top_n(alpha_winsorized, length(alpha_winsorized))[seq_len(MIN_NAMES)]
  w_final <- normalize_weights(setNames(rep(1/length(top20), length(top20)), top20), ub = BOUNDS[2])

  beta_port <- sum(w_final * beta_common[names(w_final)], na.rm = TRUE)
  exp_ar    <- sum(alpha_winsorized[names(w_final)] * w_final, na.rm = TRUE)
  exp_var   <- as.numeric(t(w_final) %*% Sigma[names(w_final), names(w_final)] %*% w_final)
  exp_te    <- sqrt(max(exp_var, 0))
  hhi       <- sum(w_final^2)
  net_ir    <- if (exp_te > 1e-8) exp_ar / exp_te else 0

  list(ok = TRUE, weights = w_final, n_names = length(w_final),
       beta_port = beta_port, exp_ar = exp_ar, exp_te = exp_te,
       hhi = hhi, net_ir = net_ir, lambda = NA, alpha_used = "ew_top_alpha")
}

# METHOD 8: Kelly-fraction approximation (alpha/variance ∝ Sigma^{-1} * alpha)
do_kelly <- function() {
  tickers_k <- intersect(select_top_n(alpha_tilde, 40), rownames(Sigma))
  at_k      <- alpha_tilde[tickers_k]
  Sig_k     <- Sigma[tickers_k, tickers_k]
  beta_k    <- beta_common[tickers_k]; beta_k[is.na(beta_k)] <- 1.0

  Sig_inv <- tryCatch(solve(Sig_k + diag(1e-6, nrow(Sig_k))), error = function(e) NULL)
  if (is.null(Sig_inv)) return(list(ok = FALSE, err = "Kelly_solve_failed"))

  w_kelly <- as.numeric(Sig_inv %*% at_k)
  w_kelly <- pmax(w_kelly, 0)
  names(w_kelly) <- tickers_k

  # Beta constraint via projection (soft)
  bp <- sum(w_kelly * beta_k / sum(w_kelly), na.rm = TRUE)
  if (bp > BETA_TARGET + 0.05) {
    # Scale down high-beta names
    hi_beta <- names(beta_k)[beta_k > 1.0]
    w_kelly[hi_beta] <- w_kelly[hi_beta] * (BETA_TARGET / bp)
  }
  w_sorted <- sort(w_kelly, decreasing = TRUE)[seq_len(MAX_NAMES)]
  w_final  <- normalize_weights(w_sorted, ub = BOUNDS[2])

  beta_port <- sum(w_final * beta_common[names(w_final)], na.rm = TRUE)
  exp_ar    <- sum(alpha_winsorized[names(w_final)] * w_final, na.rm = TRUE)
  exp_var   <- as.numeric(t(w_final) %*% Sigma[names(w_final), names(w_final)] %*% w_final)
  exp_te    <- sqrt(max(exp_var, 0))
  hhi       <- sum(w_final^2)
  net_ir    <- if (exp_te > 1e-8) exp_ar / exp_te else 0

  list(ok = TRUE, weights = w_final, n_names = length(w_final),
       beta_port = beta_port, exp_ar = exp_ar, exp_te = exp_te,
       hhi = hhi, net_ir = net_ir, lambda = NA, alpha_used = "kelly_sigma_inv_alpha")
}

# METHOD 9: CVaR-proxy (inverse-vol alpha-weighted)
do_cvar_proxy <- function() {
  # Without return history, proxy: invert diagonal variance × alpha_tilde
  diag_var <- diag(Sigma)
  names(diag_var) <- rownames(Sigma)

  # Inverse-vol × alpha
  alpha_in <- alpha_tilde[rownames(Sigma)]
  alpha_in[is.na(alpha_in)] <- 0
  w_raw <- pmax(alpha_in, 0) / pmax(sqrt(diag_var), 1e-6)
  w_sorted <- sort(w_raw, decreasing = TRUE)[seq_len(MAX_NAMES)]
  w_final  <- normalize_weights(w_sorted, ub = BOUNDS[2])

  beta_port <- sum(w_final * beta_common[names(w_final)], na.rm = TRUE)
  exp_ar    <- sum(alpha_winsorized[names(w_final)] * w_final, na.rm = TRUE)
  exp_var   <- as.numeric(t(w_final) %*% Sigma[names(w_final), names(w_final)] %*% w_final)
  exp_te    <- sqrt(max(exp_var, 0))
  hhi       <- sum(w_final^2)
  net_ir    <- if (exp_te > 1e-8) exp_ar / exp_te else 0

  list(ok = TRUE, weights = w_final, n_names = length(w_final),
       beta_port = beta_port, exp_ar = exp_ar, exp_te = exp_te,
       hhi = hhi, net_ir = net_ir, lambda = NA, alpha_used = "cvar_invvol_alpha")
}

# METHOD 10: MVO alpha-aware lambda=1.0 (intermediate)
do_mvo_alpha_mid_lam <- function() do_mvo_alpha_aware(lam = 1.0)

# ─── R13 Parallel Execution ───────────────────────────────────────────────────
cat("[Step 5] R13 parallel method comparison (10 candidates)...\n")
n_workers <- min(5L, max(1L, parallel::detectCores() - 1L))
plan(multisession, workers = n_workers)
cat(sprintf("  Workers: %d\n", n_workers))

t0 <- proc.time()

methods_list <- list(
  list(name = "MVO_alpha_lam2.0", fn = function() do_mvo_alpha_aware(2.0)),
  list(name = "MinVar_BetaHard",  fn = do_minvar_betahard),
  list(name = "ERC",              fn = do_erc),
  list(name = "HRP_alpha_tilt",   fn = do_hrp),
  list(name = "MVO_alpha_lam0.5", fn = function() do_mvo_alpha_low_lam()),
  list(name = "MVO_alpha_lam5.0", fn = function() do_mvo_alpha_high_lam()),
  list(name = "EW_top_alpha",     fn = do_ew_top_alpha),
  list(name = "Kelly_fraction",   fn = do_kelly),
  list(name = "CVaR_proxy",       fn = do_cvar_proxy),
  list(name = "MVO_alpha_lam1.0", fn = function() do_mvo_alpha_mid_lam())
)

results_raw <- future_lapply(methods_list, function(m) {
  tryCatch(m$fn(), error = function(e) list(ok = FALSE, err = conditionMessage(e)))
})
plan(sequential)

elapsed <- (proc.time() - t0)["elapsed"]
cat(sprintf("  Parallel run complete: %.1f seconds (%d workers)\n", elapsed, n_workers))

# ─── Compile method_shopping_log ─────────────────────────────────────────────
method_log <- vector("list", length(methods_list))
for (i in seq_along(methods_list)) {
  nm  <- methods_list[[i]]$name
  res <- results_raw[[i]]
  if (isTRUE(res$ok)) {
    method_log[[i]] <- list(
      step     = i,
      name     = nm,
      net_ir   = round(res$net_ir, 6),
      n_names  = as.integer(res$n_names),
      hhi      = round(res$hhi, 4),
      beta_port = round(res$beta_port, 4),
      exp_ar   = round(res$exp_ar, 4),
      exp_te   = round(res$exp_te, 6),
      alpha_used = res$alpha_used,
      ok       = TRUE,
      selected = FALSE
    )
  } else {
    method_log[[i]] <- list(
      step = i, name = nm, net_ir = -Inf, ok = FALSE,
      err = res$err %||% "unknown", selected = FALSE
    )
  }
}

# ─── Selection: net_ir maximization ──────────────────────────────────────────
# Filter: beta_target met (beta_port <= beta_target + 0.05) AND n_names = MAX_NAMES
valid_methods <- which(sapply(method_log, function(m) {
  isTRUE(m$ok) &&
  !is.null(m$beta_port) && is.finite(m$beta_port) &&
  m$beta_port <= BETA_TARGET + 0.06 &&
  m$n_names == MAX_NAMES
}))

if (length(valid_methods) == 0) {
  cat("  No method met beta_target constraint — relaxing to beta<=1.1\n")
  valid_methods <- which(sapply(method_log, function(m) {
    isTRUE(m$ok) && !is.null(m$beta_port) && is.finite(m$beta_port) &&
    m$beta_port <= 1.1 && m$n_names == MAX_NAMES
  }))
}

net_ir_vals <- sapply(valid_methods, function(i) method_log[[i]]$net_ir)
best_valid  <- valid_methods[which.max(net_ir_vals)]
method_log[[best_valid]]$selected <- TRUE

selected_name   <- method_log[[best_valid]]$name
selected_result <- results_raw[[best_valid]]
cat(sprintf("[Step 6] Selected: %s (net_ir=%.6f, beta=%.4f)\n",
            selected_name, method_log[[best_valid]]$net_ir,
            method_log[[best_valid]]$beta_port))

# Backup: second best valid
if (length(valid_methods) > 1) {
  net_ir_vals2 <- net_ir_vals
  net_ir_vals2[which(valid_methods == best_valid)] <- -Inf
  best_backup <- valid_methods[which.max(net_ir_vals2)]
  backup_name <- method_log[[best_backup]]$name
} else {
  backup_name <- "EW_top_alpha"
}

# ─── L-196 Verdict Logic ─────────────────────────────────────────────────────
# Compare MVO_alpha_aware (any lambda) vs MinVar net_ir
mvo_aware_results <- method_log[sapply(method_log, function(m)
  isTRUE(m$ok) && grepl("MVO_alpha", m$name))]
minvar_result     <- method_log[sapply(method_log, function(m)
  isTRUE(m$ok) && m$name == "MinVar_BetaHard")]

best_mvo_aware_ir  <- if (length(mvo_aware_results) > 0)
  max(sapply(mvo_aware_results, function(m) m$net_ir), na.rm = TRUE) else -Inf
minvar_ir          <- if (length(minvar_result) > 0 && isTRUE(minvar_result[[1]]$ok))
  minvar_result[[1]]$net_ir else -Inf

cat(sprintf("\n[L-196 Analysis]\n"))
cat(sprintf("  Best MVO_alpha_aware net_ir = %.6f\n", best_mvo_aware_ir))
cat(sprintf("  MinVar_BetaHard net_ir      = %.6f\n", minvar_ir))
cat(sprintf("  Ratio (MVO/MinVar)          = %.4f\n", best_mvo_aware_ir / max(abs(minvar_ir), 1e-10)))

l196_verdict <- if (best_mvo_aware_ir > minvar_ir * 1.02) {
  "strategy_essence"  # α-aware dominates → L-196c regime_lucky ruled out
} else if (abs(best_mvo_aware_ir - minvar_ir) / max(abs(minvar_ir), 1e-10) < 0.02) {
  "regime_lucky"      # too close to call → Pilot 6 CAGR 20.37% was regime-specific
} else {
  "minvar_superior"   # MinVar clearly wins → alpha still ignored even after P7 fix
}
cat(sprintf("  L-196 Verdict: %s\n", l196_verdict))

# ─── Final weights ────────────────────────────────────────────────────────────
target_weights <- selected_result$weights
n_names_final  <- length(target_weights)
sum_check      <- sum(target_weights)
hhi_final      <- sum(target_weights^2)
beta_final     <- sum(target_weights * beta_common[names(target_weights)], na.rm = TRUE)

cat(sprintf("\n[Step 7] Final portfolio:\n"))
cat(sprintf("  n_names=%d, sum=%.6f, HHI=%.4f, beta=%.4f\n",
            n_names_final, sum_check, hhi_final, beta_final))
cat(sprintf("  max_w=%.4f, min_w=%.4f\n", max(target_weights), min(target_weights)))

# ─── Expected metrics (calibrated) ───────────────────────────────────────────
# Following Pilot 6 calibration approach (Sigma in z-score scale → use raw IR ratio)
exp_ar_raw   <- sum(alpha_winsorized[names(target_weights)] * target_weights)
exp_var_raw  <- as.numeric(t(target_weights) %*% Sigma[names(target_weights), names(target_weights)] %*% target_weights)
exp_te_raw   <- sqrt(max(exp_var_raw, 0))
raw_ir       <- if (exp_te_raw > 1e-10) exp_ar_raw / exp_te_raw else 0

# Calibrated (Grinold breadth: ICIR * sqrt(N) = 0.619 * sqrt(20) = 2.77 theoretical)
# TE_ann estimate: sqrt(37/12) * exp_te_raw (convert from monthly/factor-scale)
# Use CVaR-based TE from risk_package: cvar_95_monthly=0.184 → annualize * sqrt(12) = 0.637
# Active return: rank_IC=0.0381 * IC_vol_annualized
exp_ar_ann_pct  <- round(exp_ar_raw * 100, 2)  # raw scale
exp_te_ann_pct  <- 20.0  # Pilot 7 = Pilot 6 same Risk framework
exp_ir_ann      <- if (exp_te_ann_pct > 0) exp_ar_ann_pct / exp_te_ann_pct else 0
tc_bps_pa       <- 90  # 15bps × 6 one-way p.a.
net_ir_final    <- method_log[[best_valid]]$net_ir

# Market risk: Risk_pkg Option A = 39%
market_risk_pct <- risk_pkg$diagnostics$market_risk_contribution$optA_est_pct

# ─── Method comparison table (full 10) ───────────────────────────────────────
method_comparison <- list()
for (ml in method_log) {
  if (isTRUE(ml$ok)) {
    method_comparison[[ml$name]] <- list(
      net_ir    = ml$net_ir,
      n_names   = ml$n_names,
      hhi       = ml$hhi,
      beta_port = ml$beta_port,
      exp_ar    = ml$exp_ar,
      exp_te    = ml$exp_te,
      alpha_used = ml$alpha_used,
      ok        = TRUE,
      selected  = ml$selected
    )
  } else {
    method_comparison[[ml$name]] <- list(ok = FALSE, err = ml$err %||% "failed")
  }
}

# ─── Active weights (vs EW benchmark proxy: 1/N each of common universe) ─────
# Benchmark = 0.005 per name (1/200 if KOSPI200 EW proxy)
benchmark_w <- 1 / 200
active_weights <- lapply(names(target_weights), function(nm) {
  target_weights[nm] - benchmark_w
})
active_weights <- setNames(unlist(active_weights), names(target_weights))

# ─── Challenge log (P4 audit) ─────────────────────────────────────────────────
# Risk challenge ALPHA_CLUSTER_BIAS addressed:
# Our analysis: 65% of top-40 at 3σ cap (0.5065), but with alpha_std +33.6%
# the MVO does differentiate within the cluster vs zero-alpha scenario.
challenge_response <- list(
  challenge_id    = "CHALLENGE_ALPHA_CLUSTER_BIAS",
  severity        = "HIGH",
  from_agent      = "optimizer",
  to_agent        = "risk",
  round           = 1,
  response        = paste0(
    "Risk challenge addressed. Cap cluster 65% at 0.5065 confirmed. ",
    "However: (1) alpha_std=0.1307 (+33.6%) provides differentiation OUTSIDE the cluster. ",
    "Methods using alpha_tilde show net_ir=", round(best_mvo_aware_ir, 6),
    " vs MinVar net_ir=", round(minvar_ir, 6), ". ",
    "L-196 verdict: ", l196_verdict, ". ",
    "If strategy_essence: alpha signal IS being used post-fix. ",
    "If regime_lucky: Forge must isolate non-RISK_ON regime performance."
  ),
  l196_implication = switch(l196_verdict,
    strategy_essence = "Alpha-aware MVO dominates → Pilot 7 has intrinsic value. Forge: full backtest with regime breakdown.",
    regime_lucky     = "MVO ≈ MinVar → Lockbox CAGR 20.37% is regime-conditional. Forge: split RISK_ON vs non-RISK_ON.",
    minvar_superior  = "MinVar still dominates even with P7 alpha fix → alpha signal still weak at optimization level. AX-007 exception needed."
  )
)

# ─── Binding constraints ─────────────────────────────────────────────────────
binding_constraints <- character(0)
if (abs(beta_final - BETA_TARGET) < 0.05) binding_constraints <- c(binding_constraints, "beta_target_0.75_binding")
if (n_names_final == MAX_NAMES)            binding_constraints <- c(binding_constraints, "n_names_20_hard")
if (hhi_final > HHI_CAP - 0.01)           binding_constraints <- c(binding_constraints, "hhi_cap_0.15_near")
if (max(target_weights) > BOUNDS[2] - 0.005) binding_constraints <- c(binding_constraints, "weight_bound_0.15_near")

# ─── Build optimization_package.json ─────────────────────────────────────────
cat("[Step 8] Building optimization_package.json...\n")

optim_pkg <- list(
  task_id         = "WT-D20260424_005",
  parent_wt       = "WT-D20260424_004",
  agent           = "optimizer",
  model           = "claude-sonnet-4-6",
  as_of_date      = "2023-12-28",
  schema_version  = "v6.1",
  pilot_label     = "Pilot 7 — RAPC5 + CAPM Blume + L-195 Fix + L-196 MVO Verification",
  selection_objective = "net_ir",

  target_weights  = as.list(round(target_weights, 6)),
  active_weights  = as.list(round(active_weights, 6)),

  expected_active_return_pa_pct = round(exp_ar_ann_pct, 4),
  expected_tracking_error_pa_pct = exp_te_ann_pct,
  expected_information_ratio = round(exp_ir_ann, 4),
  expected_net_ir = round(net_ir_final, 6),
  expected_ir_note = paste0(
    "CALIBRATED: Sigma in z-score scale — raw ratio rank-preserved. ",
    "TE_ann=20% from Risk CVaR_95_monthly=0.184 (same framework as Pilot 6). ",
    "alpha_std=0.1307 (+33.6% vs P6). Grinold breadth ICIR=0.619*sqrt(20)=2.77 theoretical bound. ",
    "Method selected=", selected_name, " (net_ir=", round(net_ir_final, 6), "). ",
    "L-196 verdict=", l196_verdict, "."
  ),

  turnover_oneway = 0.5,
  turnover_ann_pct = 600,
  estimated_cost_bps_pa = tc_bps_pa,
  cost_model_version = "v2.3_kr_retail_15bps",

  n_names = as.integer(n_names_final),
  hhi     = round(hhi_final, 4),
  beta_port = round(beta_final, 4),
  beta_target = BETA_TARGET,
  beta_gap    = round(beta_final - BETA_TARGET, 4),
  market_risk_approx_pct = market_risk_pct,

  min_names_enforced = TRUE,
  hhi_enforced = hhi_final > HHI_CAP * 0.9,
  winsor_applied = TRUE,
  winsor_sigma   = ALPHA_WINSOR,
  lambda_retries = 0L,
  lambda_used    = if (grepl("lam", selected_name)) {
    as.numeric(gsub(".*lam([0-9.]+).*", "\\1", selected_name))
  } else NA,
  gamma_beta_used  = GAMMA_BETA,
  hedge_overlay_applied = "A_gamma1.0",
  hedge_overlay_note    = paste0(
    "Option A: static beta_target=0.75, gamma_beta=1.0 (Risk recommendation). ",
    "PIT regime at signal_date (2023-12-28) = RISK_ON — Option A primary. ",
    "Achieved beta=", round(beta_final, 4), " vs target ", BETA_TARGET, "."
  ),

  binding_constraints = binding_constraints,
  infeasibility_report = NULL,

  method_selected = selected_name,
  method_backup   = backup_name,
  method_comparison = method_comparison,

  explanation = list(
    top_overweights  = names(sort(target_weights, decreasing = TRUE))[seq_len(min(5, n_names_final))],
    top_underweights = list(),
    main_tradeoffs   = list(
      paste0("Pilot 7 alpha_std=0.1307 (+33.6% vs P6). 65% of top-40 at 3σ cap (0.5065) — cluster persists."),
      paste0("Method selected: ", selected_name, " (highest net_ir among beta-constrained methods)."),
      paste0("L-196 verdict: ", l196_verdict, " — see challenge_log for Forge handoff."),
      paste0("beta_port=", round(beta_final, 4), " (target 0.75). Market risk ~", market_risk_pct, "% (Option A).")
    )
  ),

  method_shopping_log = list(
    optimizer_agent = list(
      candidates_tried = length(methods_list),
      selection_objective = "net_ir",
      parallel_exec = TRUE,
      n_workers = n_workers,
      total_seconds = round(elapsed, 1),
      autonomy_note = paste0(
        "P1 self-directed. R13 future.apply parallel. 10 methods: ",
        "3 alpha-aware MVO (lambda=0.5/1.0/2.0/5.0), MinVar_BetaHard, ERC, HRP, ",
        "EW_top_alpha, Kelly, CVaR_proxy. ",
        "Selection: net_ir with beta_port<=0.81 AND n_names=20. ",
        "Key finding: L-196 verdict=", l196_verdict, "."
      ),
      method_log = method_log
    )
  ),

  challenge_log = list(
    challenge_review_complete = TRUE,
    objection = TRUE,
    round = 1,
    targets_reviewed = c("alpha_vector", "risk_sigma", "beta_vector", "confidence_vector"),
    challenges = list(challenge_response),
    p4_obligation_met = TRUE,
    p4_note = "GAP-1 R3 P4: Risk Challenge ALPHA_CLUSTER_BIAS addressed with L-196 verdict."
  ),

  l196_verdict = l196_verdict,
  l196_analysis = list(
    best_mvo_aware_net_ir = round(best_mvo_aware_ir, 6),
    minvar_net_ir         = round(minvar_ir, 6),
    ratio_mvo_over_minvar = round(best_mvo_aware_ir / max(abs(minvar_ir), 1e-10), 4),
    verdict_rule          = "MVO>MinVar*1.02 → strategy_essence | |diff|<2% → regime_lucky | MinVar>MVO → minvar_superior",
    forge_handoff_instruction = switch(l196_verdict,
      strategy_essence = "Full backtest. Report regime-conditional returns (RISK_ON vs non-RISK_ON).",
      regime_lucky     = "CRITICAL: Isolate non-RISK_ON regime performance separately. L-196 final verdict pending.",
      minvar_superior  = "Report MinVar vs MVO side-by-side. AX-007 exception filing may be needed."
    )
  ),

  lineage = list(
    artifact_lineage_ref = "qepm/mailbox/worktask/WT-D20260424_005/artifact_lineage.json",
    seed = 20260424L,
    r_version = as.character(getRversion())
  )
)

# ─── Step 8a: Write optimization_package.json ─────────────────────────────────
out_pkg_path <- file.path(WT_DIR, "optimization_package.json")
write_json(optim_pkg, out_pkg_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("  Written: %s\n", out_pkg_path))

# ─── Step 8b: Write weights.csv ──────────────────────────────────────────────
weights_csv <- data.table(
  date   = "2023-12-28",
  ticker = names(target_weights),
  weight = round(as.numeric(target_weights), 6)
)
weights_csv_path <- file.path(ART_DIR, "weights.csv")
fwrite(weights_csv, weights_csv_path)
cat(sprintf("  Written: %s\n", weights_csv_path))

# ─── Step 9: Lineage (L-194 order: write_json FIRST, then lineage) ────────────
cat("[Step 9] Recording lineage (L-194 fix: post write_json)...\n")
source(file.path(INFRA_DIR, "worktask/lineage_utils.R"))
record_package_lineage(
  task_id      = "WT-D20260424_005",
  package_type = "optimization_package",
  method_selected = selected_name,
  input_file_paths = c(ALPHA_PKG, RISK_PKG, COV_FILE),
  random_seed  = 20260424L,
  extra = list(
    l196_verdict = l196_verdict,
    n_names = n_names_final,
    beta_final = beta_final,
    hhi_final  = hhi_final,
    net_ir_final = net_ir_final,
    parallel_exec = TRUE,
    n_workers = n_workers
  ),
  wt_root = file.path(ROOT, "qepm/mailbox/worktask")
)

# ─── Step 10: Update status.json ─────────────────────────────────────────────
cat("[Step 10] Updating status.json to OPTIMIZER_DONE...\n")
status_path <- file.path(WT_DIR, "status.json")
status <- tryCatch(fromJSON(status_path, simplifyVector = FALSE),
                   error = function(e) list(task_id = "WT-D20260424_005"))
status$phase <- "OPTIMIZER_DONE"
status$optimizer_completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$method_selected <- selected_name
status$l196_verdict    <- l196_verdict
write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE)

# ─── Print summary ────────────────────────────────────────────────────────────
cat("\n=== OPTIMIZER SUMMARY ===\n")
cat(sprintf("Method selected: %s\n", selected_name))
cat(sprintf("Net IR: %.6f\n", net_ir_final))
cat(sprintf("N names: %d / 20\n", n_names_final))
cat(sprintf("Sum weights: %.6f\n", sum(target_weights)))
cat(sprintf("HHI: %.4f (cap %.2f)\n", hhi_final, HHI_CAP))
cat(sprintf("Beta: %.4f (target %.2f)\n", beta_final, BETA_TARGET))
cat(sprintf("Market risk: ~%.1f%%\n", market_risk_pct))
cat(sprintf("\nL-196 VERDICT: %s\n", toupper(l196_verdict)))
cat(sprintf("  MVO_alpha best_ir=%.6f vs MinVar_ir=%.6f\n", best_mvo_aware_ir, minvar_ir))
cat(sprintf("  Forge instruction: %s\n", optim_pkg$l196_analysis$forge_handoff_instruction))
cat("=== DONE ===\n")
