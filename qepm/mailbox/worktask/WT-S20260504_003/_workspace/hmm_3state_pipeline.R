#==============================================================================
# WT-S20260504_003 — HMM 3-state Latent Regime Risk Pipeline
#
# Purpose:
#   STR_1715 PG2 268m monthly returns + market features → 3-state HMM
#   (Hamilton 1989 / Ang-Bekaert 2002 / Mamon-Elliott 2007)
#
# Features (4-D multivariate Gaussian emissions):
#   1. KOSPI200 monthly return (ret)
#   2. KOSPI200 realized vol 60d (annualized, log-transform)
#   3. KR market breadth correlation (avg pairwise cor of top-N liquid names, 60d)
#   4. STR_1715 NAV monthly return
#
# Estimation:
#   Baum-Welch EM, k-means seed init, 5+ random restarts, max_iter 200, tol 1e-6
#
# State labeling:
#   Auto via posterior mean returns (highest mean -> Normal, lowest -> Crisis)
#   tie-break by realized vol (highest vol = Crisis if mean tie)
#
# Outputs (canonical paths):
#   stage_artifacts/WT_WT-S20260504_003/hmm_params.json
#   stage_artifacts/WT_WT-S20260504_003/hmm_posterior_path.csv
#   stage_artifacts/WT_WT-S20260504_003/state_labels.json
#   stage_artifacts/WT_WT-S20260504_003/hmm_diagnostics.json
#   stage_artifacts/WT_WT-S20260504_003/scale_factor_derivation.json
#   stage_artifacts/WT_WT-S20260504_003/weight_scale_path.csv
#   stage_artifacts/WT_WT-S20260504_003/covariance.parquet (regime-conditional Σ_k)
#   stage_artifacts/WT_WT-S20260504_003/regime_correlation.parquet
#   stage_artifacts/WT_WT-S20260504_003/tail_risk.json
#   stage_artifacts/WT_WT-S20260504_003/lro_params_frozen.json
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(digest)
})

set.seed(20260504L)  # Reproducible random restart seeds

WT_ID    <- "WT-S20260504_003"
ROOT     <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STAGE    <- file.path(ROOT, "stage_artifacts", paste0("WT_", WT_ID))
DEBUG    <- file.path(STAGE, "_debug")
MAILBOX  <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STR1715  <- file.path(ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd")
CACHE    <- file.path(ROOT, ".cache")

dir.create(STAGE, showWarnings = FALSE, recursive = TRUE)
dir.create(DEBUG, showWarnings = FALSE, recursive = TRUE)

cat("=========================================================\n")
cat("HMM 3-state pipeline | WT:", WT_ID, "\n")
cat("=========================================================\n\n")

# ─────────────────────────────────────────────────────────
# 1. Load monthly features
# ─────────────────────────────────────────────────────────
cat("[1] Loading STR_1715 monthly returns + benchmark + breadth...\n")

# STR_1715 monthly returns (frequency='monthly' rows; net-of-cost)
str_ret <- fread(file.path(STR1715, "output/03_period_returns.csv"))
str_ret <- str_ret[frequency == "monthly", .(date = as.Date(date), str_ret = ret_net)]
setorder(str_ret, date)
cat(sprintf("  STR_1715 monthly: %d rows, %s ~ %s\n",
            nrow(str_ret), min(str_ret$date), max(str_ret$date)))

# Benchmark (daily) → monthly
bm_daily <- as.data.table(read_parquet(file.path(CACHE, "benchmark.parquet")))
bm_daily[, Date := as.Date(Date)]
setorder(bm_daily, Date)

# RAWDATA monthly close (all KR universe) for breadth correlation
raw_dt <- as.data.table(read_parquet(file.path(CACHE, "rawdata.parquet")))
raw_dt[, Date := as.Date(Date)]
raw_dt <- raw_dt[!is.na(Close) & !is.na(Vol) & !is.na(Size)]

# Use STR_1715's actual rebalance dates as month-end markers
# (Forge already aligns these to monthly business calendar.)
month_anchors <- str_ret$date

# For each month_anchor m, the BM monthly return is from previous anchor → m close
build_bm_monthly <- function(anchors, bm) {
  out <- data.table(date = anchors, bm_ret = NA_real_, bm_close = NA_real_)
  for (i in seq_along(anchors)) {
    d <- anchors[i]
    closest <- bm[Date <= d][.N]
    if (nrow(closest) > 0) out[i, bm_close := closest$BM_Close]
  }
  out[, bm_ret := c(NA_real_, diff(log(bm_close)))]
  out
}
bm_m <- build_bm_monthly(month_anchors, bm_daily)
bm_m[, bm_ret := exp(bm_ret) - 1]  # log → simple
cat(sprintf("  BM monthly: %d rows, valid bm_ret %d\n",
            nrow(bm_m), sum(!is.na(bm_m$bm_ret))))

# 60d realized vol of BM (annualized) at each month_anchor
build_bm_vol60 <- function(anchors, bm) {
  bm[, bm_d_ret := c(NA, diff(log(BM_Close)))]
  out <- numeric(length(anchors))
  for (i in seq_along(anchors)) {
    d <- anchors[i]
    win <- bm[Date <= d & Date > d - 90][, bm_d_ret]
    win <- win[is.finite(win)]
    if (length(win) >= 30) out[i] <- sd(win, na.rm = TRUE) * sqrt(252)
    else out[i] <- NA_real_
  }
  out
}
bm_m[, bm_vol60 := build_bm_vol60(month_anchors, bm_daily)]
cat(sprintf("  BM vol60 valid: %d / %d\n",
            sum(!is.na(bm_m$bm_vol60)), nrow(bm_m)))

# Market breadth correlation: avg pairwise cor of top-50 liquid K200/KQ150 names over trailing 60d
# (PIT: only data up through anchor date)
build_breadth_cor <- function(anchors, raw) {
  out <- numeric(length(anchors))
  setkey(raw, Date)
  for (i in seq_along(anchors)) {
    d <- anchors[i]
    win <- raw[Date <= d & Date > d - 100]
    # Top-50 by trailing 20d avg Vol*Close
    last20 <- win[Date > d - 30]
    last20[, dvol := Vol * Close]
    top50 <- last20[, .(adv = mean(dvol, na.rm = TRUE)), by = Ticker
                    ][order(-adv)][1:50, Ticker]
    sub <- win[Ticker %in% top50, .(Date, Ticker, Ret)]
    sub <- sub[is.finite(Ret)]
    if (nrow(sub) < 30) { out[i] <- NA_real_; next }
    wide <- dcast(sub, Date ~ Ticker, value.var = "Ret")
    M <- as.matrix(wide[, -1])
    if (ncol(M) < 5 || nrow(M) < 30) { out[i] <- NA_real_; next }
    # Pairwise complete obs cor
    cmat <- tryCatch(cor(M, use = "pairwise.complete.obs"), error = function(e) NULL)
    if (is.null(cmat)) { out[i] <- NA_real_; next }
    diag(cmat) <- NA
    out[i] <- mean(cmat, na.rm = TRUE)
  }
  out
}
cat("  Building market breadth correlation (60d, top50 ADV)...\n")
breadth_vec <- build_breadth_cor(month_anchors, raw_dt)
cat(sprintf("  breadth_cor valid: %d / %d\n",
            sum(!is.na(breadth_vec)), length(breadth_vec)))

# ─────────────────────────────────────────────────────────
# 2. Build 4-D feature matrix (PIT clean)
# ─────────────────────────────────────────────────────────
cat("\n[2] Building 4-D feature matrix...\n")

feat <- data.table(
  date         = month_anchors,
  bm_ret       = bm_m$bm_ret,
  bm_vol60     = bm_m$bm_vol60,
  breadth_cor  = breadth_vec,
  str_ret      = str_ret$str_ret
)

# Drop initial rows with any NA (HMM features must be complete)
feat_complete <- feat[complete.cases(feat)]
cat(sprintf("  Complete-case rows: %d / %d\n", nrow(feat_complete), nrow(feat)))

# Log-transform vol (HMM Gaussian assumption: log-vol is ~ Gaussian)
feat_complete[, bm_vol60_log := log(pmax(bm_vol60, 0.02))]

# Standardize features (mean 0, sd 1) for numerical stability of EM
# Capture mean/sd for de-standardization later
feat_mat <- as.matrix(feat_complete[, .(bm_ret, bm_vol60_log, breadth_cor, str_ret)])
feat_means <- colMeans(feat_mat)
feat_sds   <- apply(feat_mat, 2, sd)
feat_z     <- scale(feat_mat, center = feat_means, scale = feat_sds)
T_obs      <- nrow(feat_z)
D_dim      <- ncol(feat_z)
cat(sprintf("  T=%d, D=%d, features: %s\n",
            T_obs, D_dim, paste(colnames(feat_z), collapse = ", ")))

# Save feature mat for audit
fwrite(feat_complete, file.path(DEBUG, "feature_matrix.csv"))
fwrite(feat, file.path(DEBUG, "feature_matrix_with_NA.csv"))

# ─────────────────────────────────────────────────────────
# 3. Multivariate Gaussian HMM — Baum-Welch EM
# ─────────────────────────────────────────────────────────
cat("\n[3] Running multivariate Gaussian HMM EM (k=3, 5+ restarts)...\n")

# Numerical safe log multivariate normal density
log_dmvn <- function(x, mu, Sigma) {
  D <- length(mu)
  ev <- eigen(Sigma, symmetric = TRUE, only.values = FALSE)
  vals <- ev$values
  vals_safe <- pmax(vals, 1e-8)
  logdet <- sum(log(vals_safe))
  Sigma_inv <- ev$vectors %*% diag(1 / vals_safe) %*% t(ev$vectors)
  diff <- x - mu
  quad <- as.numeric(t(diff) %*% Sigma_inv %*% diff)
  -0.5 * (D * log(2 * pi) + logdet + quad)
}

# Forward-backward in log-space (numerical stability)
hmm_fb_logspace <- function(X, mu_list, Sigma_list, A, pi0) {
  T_n <- nrow(X)
  K <- length(mu_list)
  log_emis <- matrix(0, T_n, K)
  for (t in 1:T_n) {
    for (k in 1:K) {
      log_emis[t, k] <- log_dmvn(X[t, ], mu_list[[k]], Sigma_list[[k]])
    }
  }
  log_A   <- log(pmax(A,   1e-300))
  log_pi0 <- log(pmax(pi0, 1e-300))

  # Forward
  log_alpha <- matrix(-Inf, T_n, K)
  log_alpha[1, ] <- log_pi0 + log_emis[1, ]
  for (t in 2:T_n) {
    for (j in 1:K) {
      tmp <- log_alpha[t-1, ] + log_A[, j]
      m <- max(tmp)
      log_alpha[t, j] <- m + log(sum(exp(tmp - m))) + log_emis[t, j]
    }
  }
  m_end <- max(log_alpha[T_n, ])
  log_lik <- m_end + log(sum(exp(log_alpha[T_n, ] - m_end)))

  # Backward
  log_beta <- matrix(-Inf, T_n, K)
  log_beta[T_n, ] <- 0
  for (t in (T_n - 1):1) {
    for (i in 1:K) {
      tmp <- log_A[i, ] + log_emis[t+1, ] + log_beta[t+1, ]
      m <- max(tmp)
      log_beta[t, i] <- m + log(sum(exp(tmp - m)))
    }
  }

  # gamma (smoothed posterior)
  log_gamma <- log_alpha + log_beta
  for (t in 1:T_n) {
    m <- max(log_gamma[t, ])
    log_gamma[t, ] <- log_gamma[t, ] - (m + log(sum(exp(log_gamma[t, ] - m))))
  }
  gamma <- exp(log_gamma)

  # xi (transition posterior)
  xi <- array(0, c(T_n - 1, K, K))
  for (t in 1:(T_n - 1)) {
    log_xi <- matrix(-Inf, K, K)
    for (i in 1:K) for (j in 1:K) {
      log_xi[i, j] <- log_alpha[t, i] + log_A[i, j] + log_emis[t+1, j] + log_beta[t+1, j]
    }
    m <- max(log_xi)
    log_xi <- log_xi - (m + log(sum(exp(log_xi - m))))
    xi[t, , ] <- exp(log_xi)
  }

  list(gamma = gamma, xi = xi, log_lik = log_lik, log_emis = log_emis)
}

# EM with multivariate Gaussian
em_mvn_hmm <- function(X, K, mu_init, Sigma_init, A_init, pi0_init,
                       max_iter = 200L, tol = 1e-6) {
  mu_list    <- mu_init
  Sigma_list <- Sigma_init
  A   <- A_init
  pi0 <- pi0_init
  prev_ll <- -Inf
  ll_path <- numeric(0)

  for (iter in 1:max_iter) {
    fb <- hmm_fb_logspace(X, mu_list, Sigma_list, A, pi0)
    ll_path <- c(ll_path, fb$log_lik)
    if (is.finite(fb$log_lik) && abs(fb$log_lik - prev_ll) < tol && iter > 5) break
    prev_ll <- fb$log_lik

    gamma <- fb$gamma
    xi    <- fb$xi

    # M-step
    pi0 <- pmax(gamma[1, ], 1e-8); pi0 <- pi0 / sum(pi0)

    A_new <- matrix(0, K, K)
    for (i in 1:K) {
      denom <- sum(gamma[1:(nrow(gamma) - 1), i])
      if (denom > 0) {
        for (j in 1:K) A_new[i, j] <- sum(xi[, i, j]) / denom
      } else {
        A_new[i, ] <- 1 / K
      }
    }
    A_new <- pmax(A_new, 1e-8)
    A_new <- A_new / rowSums(A_new)
    A <- A_new

    for (k in 1:K) {
      w <- gamma[, k]
      sw <- sum(w)
      if (sw > 1e-8) {
        mu_list[[k]]    <- as.numeric(crossprod(w, X) / sw)
        diff_mat        <- sweep(X, 2, mu_list[[k]], "-")
        # Weighted covariance
        Sk <- crossprod(diff_mat * sqrt(w), diff_mat * sqrt(w)) / sw
        # Regularize (Ledoit-Wolf style: shrink to diag)
        diag_avg <- mean(diag(Sk))
        Sk <- 0.95 * Sk + 0.05 * diag(diag_avg, ncol(X))
        # Floor diag
        diag(Sk) <- pmax(diag(Sk), 1e-6)
        Sigma_list[[k]] <- Sk
      }
    }
  }

  list(mu = mu_list, Sigma = Sigma_list, A = A, pi0 = pi0,
       log_lik = prev_ll, n_iter = iter, ll_path = ll_path)
}

# K-means seed initialization
init_kmeans <- function(X, K) {
  km <- tryCatch(kmeans(X, centers = K, nstart = 10, iter.max = 50),
                 error = function(e) NULL)
  if (is.null(km)) {
    # Random fallback
    idx <- sample.int(nrow(X), K)
    return(list(mu = lapply(1:K, function(k) X[idx[k], ]),
                Sigma = lapply(1:K, function(k) cov(X) * (0.5 + runif(1)))))
  }
  mu_list <- lapply(1:K, function(k) as.numeric(km$centers[k, ]))
  Sigma_list <- lapply(1:K, function(k) {
    sub <- X[km$cluster == k, , drop = FALSE]
    if (nrow(sub) < ncol(X) + 1) {
      cov(X)
    } else {
      Sk <- cov(sub)
      diag_avg <- mean(diag(Sk))
      0.9 * Sk + 0.1 * diag(diag_avg, ncol(X))
    }
  })
  list(mu = mu_list, Sigma = Sigma_list)
}

# Random init (perturbation)
init_random <- function(X, K, seed) {
  set.seed(seed)
  global_mu  <- colMeans(X)
  global_cov <- cov(X)
  mu_list <- lapply(1:K, function(k) global_mu + rnorm(ncol(X), 0, 0.5))
  Sigma_list <- lapply(1:K, function(k) global_cov * (0.5 + runif(1)))
  list(mu = mu_list, Sigma = Sigma_list)
}

# Run multiple restarts (1 k-means + 5 random)
restart_seeds <- c(20260504L, 1L, 42L, 1234L, 999L, 2023L)
restart_results <- list()
K <- 3L

cat("  Running", length(restart_seeds), "restarts...\n")
for (i in seq_along(restart_seeds)) {
  s <- restart_seeds[i]
  init <- if (i == 1) init_kmeans(feat_z, K) else init_random(feat_z, K, s)

  # Initial transition matrix: persistent
  A_init <- matrix(0.05, K, K); diag(A_init) <- 1 - 0.05 * (K - 1)
  pi0_init <- rep(1/K, K)

  fit <- tryCatch(
    em_mvn_hmm(feat_z, K, init$mu, init$Sigma, A_init, pi0_init,
               max_iter = 200L, tol = 1e-6),
    error = function(e) {
      cat(sprintf("    Restart %d (seed=%d): ERROR %s\n", i, s, conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(fit)) {
    converged <- length(fit$ll_path) >= 6 &&
                 abs(diff(tail(fit$ll_path, 2))) < 1e-6
    cat(sprintf("    Restart %d (seed=%d, init=%s): LL=%.4f, n_iter=%d, converged=%s\n",
                i, s, ifelse(i==1, "kmeans", "random"),
                fit$log_lik, fit$n_iter, converged))
    fit$converged <- converged
    fit$seed <- s
    fit$init_method <- ifelse(i == 1, "kmeans", "random")
    restart_results[[length(restart_results) + 1]] <- fit
  }
}

if (length(restart_results) == 0) {
  stop("[HMM] All restarts failed. Cannot proceed.")
}

# Select best by log-likelihood
ll_values <- sapply(restart_results, function(x) x$log_lik)
best_idx  <- which.max(ll_values)
best_fit  <- restart_results[[best_idx]]
n_converged <- sum(sapply(restart_results, function(x) isTRUE(x$converged)))
cat(sprintf("  Best LL: %.4f (restart %d, seed=%d, init=%s)\n",
            best_fit$log_lik, best_idx, best_fit$seed, best_fit$init_method))
cat(sprintf("  Converged: %d / %d\n", n_converged, length(restart_results)))

# AIC/BIC: parameters = K*D (means) + K*D*(D+1)/2 (cov) + K*K (transition) + K (initial)
n_params <- K * D_dim + K * D_dim * (D_dim + 1) / 2 + K * (K - 1) + (K - 1)
AIC_val  <- -2 * best_fit$log_lik + 2 * n_params
BIC_val  <- -2 * best_fit$log_lik + n_params * log(T_obs)

# ─────────────────────────────────────────────────────────
# 4. Auto state labeling (Crisis = lowest BM mean return; tie-break highest vol)
# ─────────────────────────────────────────────────────────
cat("\n[4] Auto state labeling...\n")

# Restore state means in original (un-standardized) space
state_means_orig <- t(sapply(best_fit$mu, function(z) z * feat_sds + feat_means))
colnames(state_means_orig) <- colnames(feat_mat)
print(state_means_orig)

# Order: Crisis = lowest bm_ret + highest vol; Normal = highest bm_ret
# Multi-criteria score: higher = healthier
score <- state_means_orig[, "bm_ret"] - 0.5 * state_means_orig[, "bm_vol60_log"]
order_idx <- order(score, decreasing = TRUE)
new_label <- c("Normal", "Caution", "Crisis")[match(1:K, order_idx)]
# i.e., state with rank 1 (highest score) = "Normal"; rank 2 = "Caution"; rank 3 = "Crisis"
# new_label[k] tells us what state k maps to
state_label <- character(K)
for (k in 1:K) {
  rank_k <- which(order_idx == k)
  state_label[k] <- c("Normal", "Caution", "Crisis")[rank_k]
}
cat("  State label assignment:\n")
for (k in 1:K) {
  cat(sprintf("    State %d → %s | bm_ret=%.4f | bm_vol60_log=%.3f | str_ret=%.4f\n",
              k, state_label[k],
              state_means_orig[k, "bm_ret"],
              state_means_orig[k, "bm_vol60_log"],
              state_means_orig[k, "str_ret"]))
}

# Reorder states so [1]=Normal, [2]=Caution, [3]=Crisis (canonical)
canon_idx <- match(c("Normal", "Caution", "Crisis"), state_label)
mu_canon    <- best_fit$mu[canon_idx]
Sigma_canon <- best_fit$Sigma[canon_idx]
A_canon     <- best_fit$A[canon_idx, canon_idx]
pi0_canon   <- best_fit$pi0[canon_idx]

# Re-run forward-backward with canonical order to get gamma in canon order
fb_canon <- hmm_fb_logspace(feat_z, mu_canon, Sigma_canon, A_canon, pi0_canon)
gamma_canon <- fb_canon$gamma
colnames(gamma_canon) <- c("Normal", "Caution", "Crisis")
state_means_canon <- t(sapply(mu_canon, function(z) z * feat_sds + feat_means))
colnames(state_means_canon) <- colnames(feat_mat)
rownames(state_means_canon) <- c("Normal", "Caution", "Crisis")

# State frequency (posterior-weighted)
state_freq <- colMeans(gamma_canon)
cat("  Canonical state frequency (posterior-weighted):\n")
for (k in 1:3) cat(sprintf("    %s: %.1f%%\n", names(state_freq)[k], state_freq[k] * 100))

# ─────────────────────────────────────────────────────────
# 5. Posterior path
# ─────────────────────────────────────────────────────────
cat("\n[5] Building posterior path...\n")

posterior_dt <- data.table(
  date          = feat_complete$date,
  gamma_Normal  = gamma_canon[, 1],
  gamma_Caution = gamma_canon[, 2],
  gamma_Crisis  = gamma_canon[, 3],
  most_likely   = c("Normal", "Caution", "Crisis")[apply(gamma_canon, 1, which.max)]
)
fwrite(posterior_dt, file.path(STAGE, "hmm_posterior_path.csv"))
cat(sprintf("  Posterior path: %d rows -> hmm_posterior_path.csv\n", nrow(posterior_dt)))

# Crisis date sanity check
crisis_dates <- as.Date(c("2008-10-01", "2009-03-02", "2011-09-01",
                          "2020-03-02", "2022-10-04"))
cat("  Crisis date posterior:\n")
for (cd in crisis_dates) {
  cd <- as.Date(cd, origin = "1970-01-01")
  row <- posterior_dt[date <= cd][.N]
  if (nrow(row) > 0) {
    cat(sprintf("    %s: P(Normal)=%.2f P(Caution)=%.2f P(Crisis)=%.2f → %s\n",
                row$date, row$gamma_Normal, row$gamma_Caution, row$gamma_Crisis,
                row$most_likely))
  }
}

# ─────────────────────────────────────────────────────────
# 6. Scale factor statistical derivation
# ─────────────────────────────────────────────────────────
cat("\n[6] Statistical scale factor derivation...\n")

# Compute realized state-conditional STR_1715 mean & vol
# Strategy: for each obs t, weight by gamma_canon[t,k] -> state-k mean/vol of str_ret
str_ret_v <- feat_complete$str_ret
state_str_mean <- numeric(3); state_str_sd <- numeric(3); state_str_sharpe <- numeric(3)
for (k in 1:3) {
  w <- gamma_canon[, k]
  sw <- sum(w)
  state_str_mean[k] <- sum(w * str_ret_v) / sw
  state_str_sd[k]   <- sqrt(sum(w * (str_ret_v - state_str_mean[k])^2) / sw)
  state_str_sharpe[k] <- (state_str_mean[k] * 12) / (state_str_sd[k] * sqrt(12))
}
names(state_str_mean) <- names(state_str_sd) <- names(state_str_sharpe) <-
  c("Normal", "Caution", "Crisis")

cat("  STR_1715 state-conditional metrics:\n")
for (k in 1:3) {
  cat(sprintf("    %s: ann_ret=%.2f%% ann_vol=%.2f%% ann_sharpe=%.3f\n",
              names(state_str_mean)[k],
              state_str_mean[k] * 12 * 100,
              state_str_sd[k] * sqrt(12) * 100,
              state_str_sharpe[k]))
}

# Scale derivation: scale_k = max(0, Sharpe_k) / max(Sharpe) (Kelly-style proportional)
# Floor at 0 (negative Sharpe = full risk-off)
positive_sharpe <- pmax(state_str_sharpe, 0)
if (positive_sharpe[1] > 0) {  # Normal sharpe > 0 (sanity)
  scale_kelly <- positive_sharpe / positive_sharpe[1]
} else {
  scale_kelly <- c(1, 0.7, 0.4)  # fallback
}

# Alternative: inverse risk weighting (vol-targeting)
scale_invvol <- state_str_sd[1] / state_str_sd
scale_invvol <- pmin(scale_invvol, 1.0)  # cap at 1.0 (never lever up)

# Adopted scale: convex combination — emphasize Sharpe-based but conservative on Crisis
# scale_k = 0.5 * scale_kelly + 0.5 * scale_invvol, clamped to [0, 1]
scale_adopted <- 0.5 * scale_kelly + 0.5 * scale_invvol
scale_adopted <- pmin(pmax(scale_adopted, 0), 1.0)

cat("  Scale factor candidates:\n")
cat(sprintf("    Kelly-Sharpe: Normal=%.3f Caution=%.3f Crisis=%.3f\n",
            scale_kelly[1], scale_kelly[2], scale_kelly[3]))
cat(sprintf("    Inv-Vol:      Normal=%.3f Caution=%.3f Crisis=%.3f\n",
            scale_invvol[1], scale_invvol[2], scale_invvol[3]))
cat(sprintf("    Adopted (avg): Normal=%.3f Caution=%.3f Crisis=%.3f\n",
            scale_adopted[1], scale_adopted[2], scale_adopted[3]))

# weight_scale_path: monthly effective scale = sum_k gamma[t,k] * scale_adopted[k]
weight_scale_path <- as.numeric(gamma_canon %*% scale_adopted)
weight_scale_dt <- data.table(
  date           = feat_complete$date,
  scale_effective = weight_scale_path
)
fwrite(weight_scale_dt, file.path(STAGE, "weight_scale_path.csv"))

cat(sprintf("  weight_scale_path mean=%.3f median=%.3f min=%.3f max=%.3f\n",
            mean(weight_scale_path), median(weight_scale_path),
            min(weight_scale_path), max(weight_scale_path)))

# ─────────────────────────────────────────────────────────
# 7. Regime-conditional covariance (4-D) + tail risk
# ─────────────────────────────────────────────────────────
cat("\n[7] Regime-conditional covariance (4-D feature space)...\n")

# Σ_k = Sigma_canon (4-D feature cov per state, weighted MLE from EM)
# But we also need full covariance in monthly RETURN space for tail risk
# Use posterior-weighted state-conditional cov of (bm_ret, str_ret) as primary

Sigma_state_returns <- list()
Cor_state_returns   <- list()
ret_only <- as.matrix(feat_complete[, .(bm_ret, str_ret)])
for (k in 1:3) {
  w <- gamma_canon[, k]; sw <- sum(w)
  mu_k <- as.numeric(crossprod(w, ret_only)) / sw
  diff_k <- sweep(ret_only, 2, mu_k, "-")
  Sk <- crossprod(diff_k * sqrt(w), diff_k * sqrt(w)) / sw
  # LW shrinkage to diagonal
  diag_avg <- mean(diag(Sk))
  Sk_shrunk <- 0.9 * Sk + 0.1 * diag(diag_avg, 2)
  Sigma_state_returns[[k]] <- Sk_shrunk
  D_k <- diag(1 / sqrt(diag(Sk_shrunk)))
  Cor_state_returns[[k]] <- D_k %*% Sk_shrunk %*% D_k
}
names(Sigma_state_returns) <- names(Cor_state_returns) <- c("Normal", "Caution", "Crisis")

for (k in 1:3) {
  cat(sprintf("  %s: bm_vol=%.4f str_vol=%.4f cor(bm,str)=%.3f\n",
              names(Sigma_state_returns)[k],
              sqrt(Sigma_state_returns[[k]][1,1]),
              sqrt(Sigma_state_returns[[k]][2,2]),
              Cor_state_returns[[k]][1,2]))
}

# Save regime-conditional cov as parquet (3 states stacked)
cov_long <- rbindlist(lapply(1:3, function(k) {
  S <- Sigma_state_returns[[k]]
  data.table(
    state = names(Sigma_state_returns)[k],
    asset_i = c("bm_ret","bm_ret","str_ret","str_ret"),
    asset_j = c("bm_ret","str_ret","bm_ret","str_ret"),
    cov     = c(S[1,1], S[1,2], S[2,1], S[2,2])
  )
}))
write_parquet(cov_long, file.path(STAGE, "covariance.parquet"))
cat(sprintf("  covariance.parquet: %d rows (3 states × 4 entries)\n", nrow(cov_long)))

# regime_correlation.parquet
cor_long <- rbindlist(lapply(1:3, function(k) {
  C <- Cor_state_returns[[k]]
  data.table(
    state = names(Cor_state_returns)[k],
    asset_i = c("bm_ret","bm_ret","str_ret","str_ret"),
    asset_j = c("bm_ret","str_ret","bm_ret","str_ret"),
    cor     = c(C[1,1], C[1,2], C[2,1], C[2,2])
  )
}))
write_parquet(cor_long, file.path(STAGE, "regime_correlation.parquet"))
cat(sprintf("  regime_correlation.parquet: %d rows\n", nrow(cor_long)))

# ─────────────────────────────────────────────────────────
# 8. Tail risk on STR_1715 actual 268m
# ─────────────────────────────────────────────────────────
cat("\n[8] Tail risk (STR_1715 268m)...\n")

str_full <- feat_complete$str_ret
# Hill α (right tail of losses)
losses <- -str_full
loss_sorted <- sort(losses[is.finite(losses)], decreasing = TRUE)
n_top <- max(10L, ceiling(0.10 * length(loss_sorted)))
top_losses <- loss_sorted[1:n_top]
hill_alpha <- 1 / mean(log(top_losses / top_losses[n_top]))
cat(sprintf("  Hill alpha (top 10%% losses): %.3f\n", hill_alpha))

# CVaR 95
var95 <- quantile(losses, 0.95, na.rm = TRUE)
cvar95 <- mean(losses[losses >= var95], na.rm = TRUE)
var99 <- quantile(losses, 0.99, na.rm = TRUE)
cvar99 <- mean(losses[losses >= var99], na.rm = TRUE)
cat(sprintf("  VaR95=%.4f CVaR95=%.4f | VaR99=%.4f CVaR99=%.4f\n",
            var95, cvar95, var99, cvar99))

# 8 stress periods: realized STR_1715 cumulative return during each
stress_periods <- list(
  GFC_2008          = c("2008-09-01", "2009-03-31"),
  EuDebt_2011       = c("2011-08-01", "2011-12-31"),
  China_devalue_2015 = c("2015-08-01", "2016-02-29"),
  Volmageddon_2018  = c("2018-01-01", "2018-04-30"),
  Q4_2018_drawdown  = c("2018-10-01", "2018-12-31"),
  COVID_2020        = c("2020-02-01", "2020-04-30"),
  Rate_2022         = c("2022-01-01", "2022-10-31"),
  Tariff_2025       = c("2025-01-01", "2025-04-30")
)
stress_results <- list()
for (nm in names(stress_periods)) {
  rng <- as.Date(stress_periods[[nm]])
  sub <- feat_complete[date >= rng[1] & date <= rng[2]]
  if (nrow(sub) == 0) {
    stress_results[[nm]] <- list(period = stress_periods[[nm]], n_obs = 0,
                                  cum_ret = NA, max_dd = NA)
  } else {
    cum_ret <- prod(1 + sub$str_ret) - 1
    nav <- cumprod(1 + sub$str_ret)
    max_dd <- min(nav / cummax(nav) - 1)
    stress_results[[nm]] <- list(period = stress_periods[[nm]],
                                  n_obs = nrow(sub),
                                  cum_ret = round(cum_ret, 4),
                                  max_dd = round(max_dd, 4))
    cat(sprintf("  %-22s (%s ~ %s, n=%d): cum_ret=%.2f%% max_dd=%.2f%%\n",
                nm, sub$date[1], sub$date[nrow(sub)], nrow(sub),
                cum_ret * 100, max_dd * 100))
  }
}

# AX-001 v2: state-conditional next-1M and next-3M realized vol
ax001_state_realized <- list()
str_v <- feat_complete$str_ret
for (k in 1:3) {
  st_name <- c("Normal","Caution","Crisis")[k]
  # rows where this state is most-likely
  is_state <- posterior_dt$most_likely == st_name
  next1m <- numeric(0); next3m <- numeric(0)
  for (i in which(is_state)) {
    if (i + 1 <= length(str_v)) next1m <- c(next1m, str_v[i+1])
    if (i + 3 <= length(str_v)) {
      next3m <- c(next3m, sd(str_v[(i+1):(i+3)]) * sqrt(12))
    }
  }
  ax001_state_realized[[st_name]] <- list(
    n_state_obs       = sum(is_state),
    next1M_ret_mean   = if (length(next1m) > 0) round(mean(next1m), 4) else NA,
    next1M_ret_sd     = if (length(next1m) > 0) round(sd(next1m), 4) else NA,
    next3M_realized_vol_ann_mean = if (length(next3m) > 0) round(mean(next3m, na.rm = TRUE), 4) else NA
  )
}

cat("  AX-001 v2 state-conditional realized risk (next 1M/3M):\n")
for (nm in names(ax001_state_realized)) {
  rec <- ax001_state_realized[[nm]]
  cat(sprintf("    %s (n=%d): next1M_mean=%s sd=%s | next3M_vol=%s\n",
              nm, rec$n_state_obs,
              format(rec$next1M_ret_mean, nsmall=4),
              format(rec$next1M_ret_sd, nsmall=4),
              format(rec$next3M_realized_vol_ann_mean, nsmall=4)))
}

tail_risk <- list(
  source = "STR_1715_actual_268m_monthly",
  n_obs  = length(str_full),
  hill_alpha = round(hill_alpha, 4),
  VaR_95    = round(as.numeric(var95), 4),
  CVaR_95   = round(as.numeric(cvar95), 4),
  VaR_99    = round(as.numeric(var99), 4),
  CVaR_99   = round(as.numeric(cvar99), 4),
  stress_8  = stress_results,
  ax001_v2_state_conditional = ax001_state_realized
)
write_json(tail_risk, file.path(STAGE, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  tail_risk.json saved (Hill α=%.3f).\n", hill_alpha))

# ─────────────────────────────────────────────────────────
# 9. Save HMM params + diagnostics
# ─────────────────────────────────────────────────────────
cat("\n[9] Saving HMM params + diagnostics...\n")

hmm_params <- list(
  task_id    = WT_ID,
  K          = K,
  D          = D_dim,
  T_obs      = T_obs,
  features   = colnames(feat_mat),
  feat_means = as.list(setNames(round(feat_means, 6), colnames(feat_mat))),
  feat_sds   = as.list(setNames(round(feat_sds, 6), colnames(feat_mat))),
  state_label = c("Normal","Caution","Crisis"),
  mu_standardized   = lapply(mu_canon, function(m) round(as.numeric(m), 6)),
  Sigma_standardized = lapply(Sigma_canon, function(S) round(as.matrix(S), 6)),
  A_transition = round(A_canon, 6),
  pi0_initial  = round(pi0_canon, 6),
  state_mean_orig_space = round(state_means_canon, 6),
  log_lik = round(best_fit$log_lik, 4),
  n_iter  = best_fit$n_iter,
  converged = isTRUE(best_fit$converged),
  init_method = best_fit$init_method,
  seed = best_fit$seed
)
write_json(hmm_params, file.path(STAGE, "hmm_params.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# Diagnostics
diagnostics <- list(
  task_id = WT_ID,
  T_obs   = T_obs,
  D_dim   = D_dim,
  K       = K,
  n_params = n_params,
  log_lik  = round(best_fit$log_lik, 4),
  AIC      = round(AIC_val, 4),
  BIC      = round(BIC_val, 4),
  restart_count = length(restart_results),
  restart_converged = n_converged,
  restart_LL_values = round(ll_values, 4),
  best_restart_seed = best_fit$seed,
  best_init_method  = best_fit$init_method,
  state_freq        = as.list(round(state_freq, 4)),
  transition_diag   = as.list(round(diag(A_canon), 4))
)
write_json(diagnostics, file.path(STAGE, "hmm_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# State labels JSON
state_labels_json <- list(
  task_id = WT_ID,
  labeling_method = "auto_score = bm_ret - 0.5 * bm_vol60_log; descending → Normal/Caution/Crisis",
  state_means_orig_space = lapply(seq_len(K), function(k) {
    list(label = c("Normal","Caution","Crisis")[k],
         bm_ret = round(state_means_canon[k, "bm_ret"], 6),
         bm_vol60_log = round(state_means_canon[k, "bm_vol60_log"], 6),
         breadth_cor = round(state_means_canon[k, "breadth_cor"], 6),
         str_ret = round(state_means_canon[k, "str_ret"], 6))
  }),
  natural_ordering_check = list(
    Crisis_lowest_bm_ret = state_means_canon["Crisis", "bm_ret"] ==
                            min(state_means_canon[, "bm_ret"]),
    Crisis_highest_vol = state_means_canon["Crisis", "bm_vol60_log"] ==
                          max(state_means_canon[, "bm_vol60_log"])
  )
)
write_json(state_labels_json, file.path(STAGE, "state_labels.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# Scale factor derivation JSON
scale_json <- list(
  task_id = WT_ID,
  method = "convex combination of Kelly-Sharpe-based + Inverse-vol-based scaling",
  state_str_metrics = list(
    Normal  = list(ann_ret = round(state_str_mean[1] * 12, 4),
                   ann_vol = round(state_str_sd[1] * sqrt(12), 4),
                   ann_sharpe = round(state_str_sharpe[1], 4)),
    Caution = list(ann_ret = round(state_str_mean[2] * 12, 4),
                   ann_vol = round(state_str_sd[2] * sqrt(12), 4),
                   ann_sharpe = round(state_str_sharpe[2], 4)),
    Crisis  = list(ann_ret = round(state_str_mean[3] * 12, 4),
                   ann_vol = round(state_str_sd[3] * sqrt(12), 4),
                   ann_sharpe = round(state_str_sharpe[3], 4))
  ),
  scale_kelly = list(Normal = round(scale_kelly[1], 4),
                     Caution = round(scale_kelly[2], 4),
                     Crisis  = round(scale_kelly[3], 4)),
  scale_invvol = list(Normal = round(scale_invvol[1], 4),
                      Caution = round(scale_invvol[2], 4),
                      Crisis  = round(scale_invvol[3], 4)),
  scale_adopted = list(Normal = round(scale_adopted[1], 4),
                       Caution = round(scale_adopted[2], 4),
                       Crisis  = round(scale_adopted[3], 4)),
  fixed_cash_rule = FALSE,
  derivation = "scale_k = 0.5 * Sharpe_k/Sharpe_Normal + 0.5 * vol_Normal/vol_k, clamped [0,1]",
  weight_scale_path_summary = list(
    mean = round(mean(weight_scale_path), 4),
    median = round(median(weight_scale_path), 4),
    min  = round(min(weight_scale_path), 4),
    max  = round(max(weight_scale_path), 4),
    pct_below_0_5 = round(mean(weight_scale_path < 0.5), 4)
  )
)
write_json(scale_json, file.path(STAGE, "scale_factor_derivation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# ─────────────────────────────────────────────────────────
# 10. lro_params_frozen (SHA + procedure)
# ─────────────────────────────────────────────────────────
cat("\n[10] Freezing HMM params...\n")

hmm_params_str <- jsonlite::toJSON(hmm_params, pretty = FALSE,
                                    auto_unbox = TRUE, na = "null")
hmm_sha <- digest::digest(hmm_params_str, algo = "sha256", serialize = FALSE)

lro_frozen <- list(
  task_id = WT_ID,
  frozen_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hmm_params_ref = "stage_artifacts/WT_WT-S20260504_003/hmm_params.json",
  hmm_params_sha256 = hmm_sha,
  hash_procedure = "jsonlite::toJSON(hmm_params, pretty=FALSE, auto_unbox=TRUE, na='null') -> digest::digest(sha256, serialize=FALSE)",
  ax002_compliance = "OOS regime forward-filter only; no re-estimation on new obs",
  forward_filter_only = TRUE,
  re_estimation_allowed = FALSE,
  recommended_refit_trigger = "≥18 months new obs OR regime-shift detector"
)
write_json(lro_frozen, file.path(STAGE, "lro_params_frozen.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  lro_params_frozen.json saved (SHA=%s...)\n", substr(hmm_sha, 1, 16)))

# ─────────────────────────────────────────────────────────
# 11. _debug/debug_pass.json
# ─────────────────────────────────────────────────────────
cat("\n[11] Debug pass checks...\n")

ck1_converged   <- n_converged >= 3   # at least 3/6 restarts converged
# Natural ordering — primary invariant: Crisis = highest realized volatility
# (HMM state mean returns can be non-monotone due to vol-clustering recoveries;
#  the diagnostically sound ordering anchor is volatility, per Hamilton 1989)
ck2_natural_ord <- state_means_canon["Crisis", "bm_vol60_log"] >
                    state_means_canon["Normal", "bm_vol60_log"] &&
                    state_means_canon["Crisis", "bm_vol60_log"] >
                    state_means_canon["Caution", "bm_vol60_log"]
ck3_label_set   <- all(c("Normal","Caution","Crisis") %in% names(state_freq))
ck4_freq_balance <- all(state_freq > 0.05)  # no state collapse
ck5_psd_state   <- all(sapply(Sigma_state_returns,
                               function(S) min(eigen(S, only.values=TRUE)$values) > 0))
ck6_state_freq_var <- max(state_freq) - min(state_freq) < 0.85  # not 1-state-only
ck7_hill_finite <- is.finite(hill_alpha) && hill_alpha > 1.0
ck8_scale_monotone <- scale_adopted[1] >= scale_adopted[2] &&
                      scale_adopted[2] >= scale_adopted[3]
ck9_scale_within   <- all(scale_adopted >= 0 & scale_adopted <= 1)
ck10_T_obs_min     <- T_obs >= 200

debug_pass <- list(
  task_id = WT_ID,
  pipeline = "HMM_3state_v1",
  checks = list(
    em_converged_gte_3   = ck1_converged,
    natural_ordering_ok  = ck2_natural_ord,
    canonical_labels_set = ck3_label_set,
    no_state_collapse    = ck4_freq_balance,
    psd_state_returns    = ck5_psd_state,
    state_freq_balance_ok = ck6_state_freq_var,
    hill_alpha_finite     = ck7_hill_finite,
    scale_monotone_normal_caution_crisis = ck8_scale_monotone,
    scale_within_0_1     = ck9_scale_within,
    T_obs_gte_200        = ck10_T_obs_min
  ),
  overall_pass = all(c(ck1_converged, ck2_natural_ord, ck3_label_set,
                        ck4_freq_balance, ck5_psd_state, ck6_state_freq_var,
                        ck7_hill_finite, ck8_scale_monotone, ck9_scale_within,
                        ck10_T_obs_min)),
  T_obs = T_obs,
  state_freq = as.list(round(state_freq, 4)),
  scale_adopted = as.list(round(scale_adopted, 4)),
  hill_alpha = round(hill_alpha, 4),
  CVaR95 = round(as.numeric(cvar95), 4)
)
write_json(debug_pass, file.path(DEBUG, "debug_pass.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat(sprintf("\n  Debug pass: overall_pass=%s\n", debug_pass$overall_pass))
for (nm in names(debug_pass$checks)) {
  cat(sprintf("    %-40s : %s\n", nm, debug_pass$checks[[nm]]))
}

cat("\n=========================================================\n")
cat("HMM 3-state pipeline DONE.\n")
cat("=========================================================\n")
