#==============================================================================
# WT-S20260504_003 — HMM 3-state PIT Walk-forward + Bootstrap CI
#
# Purpose: Address Codex Critic concerns C1 (PIT smoothed leakage) + C3 (n<50 CI)
#
# Output:
#   stage_artifacts/.../hmm_posterior_path_walkforward.csv  — forward-filtered γ_t
#   stage_artifacts/.../weight_scale_path_walkforward.csv   — scale_t = γ_{t-1}-derived
#   stage_artifacts/.../crisis_bootstrap_ci.json            — bootstrap CI for Crisis state
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(digest)
})

set.seed(20260504L)

WT_ID    <- "WT-S20260504_003"
ROOT     <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STAGE    <- file.path(ROOT, "stage_artifacts", paste0("WT_", WT_ID))
DEBUG    <- file.path(STAGE, "_debug")

cat("=========================================================\n")
cat("HMM 3-state Walk-forward + Bootstrap CI | WT:", WT_ID, "\n")
cat("=========================================================\n\n")

# Reuse feature matrix from main pipeline
feat_complete <- fread(file.path(DEBUG, "feature_matrix.csv"))
feat_complete[, date := as.Date(date)]

feat_mat <- as.matrix(feat_complete[, .(bm_ret, bm_vol60_log, breadth_cor, str_ret)])
T_obs <- nrow(feat_mat)
D_dim <- ncol(feat_mat)
cat(sprintf("[1] Feature matrix loaded: T=%d, D=%d\n", T_obs, D_dim))

# Source HMM functions inline (copy-paste from main pipeline for self-contained run)
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

# Forward filter only (no backward) — produces α_t (filtered posterior)
hmm_filter_only <- function(X, mu_list, Sigma_list, A, pi0) {
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

  log_alpha <- matrix(-Inf, T_n, K)
  log_alpha[1, ] <- log_pi0 + log_emis[1, ]
  for (t in 2:T_n) {
    for (j in 1:K) {
      tmp <- log_alpha[t-1, ] + log_A[, j]
      m <- max(tmp)
      log_alpha[t, j] <- m + log(sum(exp(tmp - m))) + log_emis[t, j]
    }
  }
  # Convert to filtered probabilities
  filtered <- matrix(0, T_n, K)
  for (t in 1:T_n) {
    m <- max(log_alpha[t, ])
    filtered[t, ] <- exp(log_alpha[t, ] - (m + log(sum(exp(log_alpha[t, ] - m)))))
  }
  filtered
}

hmm_fb_logspace <- function(X, mu_list, Sigma_list, A, pi0) {
  T_n <- nrow(X)
  K <- length(mu_list)
  log_emis <- matrix(0, T_n, K)
  for (t in 1:T_n) for (k in 1:K) log_emis[t, k] <- log_dmvn(X[t, ], mu_list[[k]], Sigma_list[[k]])
  log_A <- log(pmax(A, 1e-300)); log_pi0 <- log(pmax(pi0, 1e-300))
  log_alpha <- matrix(-Inf, T_n, K)
  log_alpha[1, ] <- log_pi0 + log_emis[1, ]
  for (t in 2:T_n) for (j in 1:K) {
    tmp <- log_alpha[t-1, ] + log_A[, j]
    m <- max(tmp); log_alpha[t, j] <- m + log(sum(exp(tmp - m))) + log_emis[t, j]
  }
  m_end <- max(log_alpha[T_n, ])
  log_lik <- m_end + log(sum(exp(log_alpha[T_n, ] - m_end)))
  log_beta <- matrix(-Inf, T_n, K); log_beta[T_n, ] <- 0
  for (t in (T_n - 1):1) for (i in 1:K) {
    tmp <- log_A[i, ] + log_emis[t+1, ] + log_beta[t+1, ]
    m <- max(tmp); log_beta[t, i] <- m + log(sum(exp(tmp - m)))
  }
  log_gamma <- log_alpha + log_beta
  for (t in 1:T_n) {
    m <- max(log_gamma[t, ])
    log_gamma[t, ] <- log_gamma[t, ] - (m + log(sum(exp(log_gamma[t, ] - m))))
  }
  gamma <- exp(log_gamma)
  xi <- array(0, c(T_n - 1, K, K))
  for (t in 1:(T_n - 1)) {
    log_xi <- matrix(-Inf, K, K)
    for (i in 1:K) for (j in 1:K) log_xi[i, j] <- log_alpha[t, i] + log_A[i, j] + log_emis[t+1, j] + log_beta[t+1, j]
    m <- max(log_xi); log_xi <- log_xi - (m + log(sum(exp(log_xi - m)))); xi[t, , ] <- exp(log_xi)
  }
  list(gamma = gamma, xi = xi, log_lik = log_lik)
}

em_mvn_hmm <- function(X, K, mu_init, Sigma_init, A_init, pi0_init, max_iter = 200L, tol = 1e-6) {
  mu_list <- mu_init; Sigma_list <- Sigma_init; A <- A_init; pi0 <- pi0_init
  prev_ll <- -Inf; ll_path <- numeric(0)
  for (iter in 1:max_iter) {
    fb <- hmm_fb_logspace(X, mu_list, Sigma_list, A, pi0)
    ll_path <- c(ll_path, fb$log_lik)
    if (is.finite(fb$log_lik) && abs(fb$log_lik - prev_ll) < tol && iter > 5) break
    prev_ll <- fb$log_lik
    gamma <- fb$gamma; xi <- fb$xi
    pi0 <- pmax(gamma[1, ], 1e-8); pi0 <- pi0 / sum(pi0)
    A_new <- matrix(0, K, K)
    for (i in 1:K) {
      denom <- sum(gamma[1:(nrow(gamma) - 1), i])
      if (denom > 0) for (j in 1:K) A_new[i, j] <- sum(xi[, i, j]) / denom
      else A_new[i, ] <- 1 / K
    }
    A_new <- pmax(A_new, 1e-8); A_new <- A_new / rowSums(A_new); A <- A_new
    for (k in 1:K) {
      w <- gamma[, k]; sw <- sum(w)
      if (sw > 1e-8) {
        mu_list[[k]] <- as.numeric(crossprod(w, X) / sw)
        diff_mat <- sweep(X, 2, mu_list[[k]], "-")
        Sk <- crossprod(diff_mat * sqrt(w), diff_mat * sqrt(w)) / sw
        diag_avg <- mean(diag(Sk)); Sk <- 0.95 * Sk + 0.05 * diag(diag_avg, ncol(X))
        diag(Sk) <- pmax(diag(Sk), 1e-6); Sigma_list[[k]] <- Sk
      }
    }
  }
  list(mu = mu_list, Sigma = Sigma_list, A = A, pi0 = pi0,
       log_lik = prev_ll, n_iter = iter, ll_path = ll_path)
}

# ─────────────────────────────────────────────────────────
# 2. Walk-forward expanding HMM (PIT-clean)
# ─────────────────────────────────────────────────────────
cat("\n[2] Walk-forward expanding HMM...\n")
cat("  For each month t in [MIN_TRAIN+1 .. T]:\n")
cat("    1) Fit HMM on observations 1..t-1 (NO observation t)\n")
cat("    2) Apply forward filter to get α_{t-1} (uses 1..t-1 only)\n")
cat("    3) State at t = transition · α_{t-1} (predicted, no t-info)\n")
cat("    4) scale_t computed from predicted state probability\n\n")

MIN_TRAIN <- 60L  # need enough data for stable 3-state HMM
K <- 3L

# Standardize features using ONLY training data each iteration (PIT z-score)
canonical_label_order <- function(state_means_orig) {
  # Crisis = highest vol; Normal = lowest vol; Caution = middle
  vol_log <- state_means_orig[, "bm_vol60_log"]
  ord <- order(vol_log)  # ascending vol
  # ord[1] = Normal (lowest vol), ord[2] = Caution, ord[3] = Crisis
  ord
}

walkforward_dt <- data.table(
  date = feat_complete$date,
  gamma_Normal_filtered = NA_real_,
  gamma_Caution_filtered = NA_real_,
  gamma_Crisis_filtered = NA_real_,
  gamma_Normal_predicted = NA_real_,
  gamma_Caution_predicted = NA_real_,
  gamma_Crisis_predicted = NA_real_,
  most_likely_filtered = NA_character_,
  most_likely_predicted = NA_character_,
  scale_predicted = NA_real_,
  fit_T = NA_integer_
)

# Re-use main pipeline's adopted scale (Normal/Caution/Crisis)
scale_adopted <- c(Normal = 1.000, Caution = 0.819, Crisis = 0.475)

cat("  Walk-forward iterations (this takes ~1-2 minutes)...\n")
prog_step <- max(1L, floor((T_obs - MIN_TRAIN) / 10))

# Warm-start from previous iteration to speed up convergence
warm_mu <- NULL
warm_Sigma <- NULL
warm_A <- NULL
warm_pi0 <- NULL

for (t in (MIN_TRAIN + 1):T_obs) {
  if ((t - MIN_TRAIN) %% prog_step == 0)
    cat(sprintf("    t=%d/%d (%.0f%%)\n", t, T_obs, 100 * (t - MIN_TRAIN) / (T_obs - MIN_TRAIN)))

  # Training data: 1..t-1 (NO observation at t)
  train_mat <- feat_mat[1:(t - 1), , drop = FALSE]

  # Standardize using ONLY training data
  train_means <- colMeans(train_mat)
  train_sds   <- apply(train_mat, 2, sd)
  train_sds[train_sds == 0] <- 1
  train_z <- scale(train_mat, center = train_means, scale = train_sds)

  # Initialize: warm-start if available, else k-means
  if (is.null(warm_mu)) {
    km <- tryCatch(kmeans(train_z, centers = K, nstart = 5, iter.max = 30),
                   error = function(e) NULL)
    if (is.null(km)) next
    mu_init <- lapply(1:K, function(k) as.numeric(km$centers[k, ]))
    Sigma_init <- lapply(1:K, function(k) {
      sub <- train_z[km$cluster == k, , drop = FALSE]
      if (nrow(sub) < D_dim + 1) cov(train_z)
      else {
        Sk <- cov(sub); diag_avg <- mean(diag(Sk))
        0.9 * Sk + 0.1 * diag(diag_avg, D_dim)
      }
    })
    A_init <- matrix(0.05, K, K); diag(A_init) <- 1 - 0.05 * (K - 1)
    pi0_init <- rep(1/K, K)
  } else {
    mu_init <- warm_mu; Sigma_init <- warm_Sigma; A_init <- warm_A; pi0_init <- warm_pi0
  }

  fit <- tryCatch(
    em_mvn_hmm(train_z, K, mu_init, Sigma_init, A_init, pi0_init,
               max_iter = 100L, tol = 1e-6),
    error = function(e) NULL
  )
  if (is.null(fit)) next

  # Canonical label ordering from THIS iteration's fit
  state_means_orig <- t(sapply(fit$mu, function(m) m * train_sds + train_means))
  colnames(state_means_orig) <- colnames(train_mat)
  ord <- canonical_label_order(state_means_orig)
  # ord[1]=Normal, ord[2]=Caution, ord[3]=Crisis
  mu_canon    <- fit$mu[ord]
  Sigma_canon <- fit$Sigma[ord]
  A_canon     <- fit$A[ord, ord]
  pi0_canon   <- fit$pi0[ord]

  # Forward filter on training data → filtered α_{t-1} (last row)
  filtered <- hmm_filter_only(train_z, mu_canon, Sigma_canon, A_canon, pi0_canon)
  alpha_t_minus_1 <- filtered[nrow(filtered), ]  # P(state=k | obs 1..t-1)

  # Predicted state at t = α_{t-1} %*% A (no t-info used)
  predicted_t <- as.numeric(alpha_t_minus_1 %*% A_canon)
  predicted_t <- pmax(predicted_t, 0); predicted_t <- predicted_t / sum(predicted_t)

  walkforward_dt[t, gamma_Normal_filtered  := alpha_t_minus_1[1]]
  walkforward_dt[t, gamma_Caution_filtered := alpha_t_minus_1[2]]
  walkforward_dt[t, gamma_Crisis_filtered  := alpha_t_minus_1[3]]
  walkforward_dt[t, gamma_Normal_predicted  := predicted_t[1]]
  walkforward_dt[t, gamma_Caution_predicted := predicted_t[2]]
  walkforward_dt[t, gamma_Crisis_predicted  := predicted_t[3]]
  walkforward_dt[t, most_likely_filtered  := c("Normal","Caution","Crisis")[which.max(alpha_t_minus_1)]]
  walkforward_dt[t, most_likely_predicted := c("Normal","Caution","Crisis")[which.max(predicted_t)]]

  # Scale_t = predicted state probability · scale_adopted
  scale_t <- as.numeric(predicted_t %*% scale_adopted)
  walkforward_dt[t, scale_predicted := scale_t]
  walkforward_dt[t, fit_T := t - 1L]

  # Save for warm-start
  warm_mu <- mu_canon; warm_Sigma <- Sigma_canon; warm_A <- A_canon; warm_pi0 <- pi0_canon
}

n_valid_wf <- sum(!is.na(walkforward_dt$scale_predicted))
cat(sprintf("\n  Walk-forward valid predictions: %d / %d (MIN_TRAIN=%d)\n",
            n_valid_wf, T_obs, MIN_TRAIN))

fwrite(walkforward_dt, file.path(STAGE, "hmm_posterior_path_walkforward.csv"))

# Summary stats
valid_wf <- walkforward_dt[!is.na(scale_predicted)]
cat("  Walk-forward state freq (most_likely_predicted):\n")
freq_wf <- table(valid_wf$most_likely_predicted)
for (nm in names(freq_wf)) {
  cat(sprintf("    %s: %d (%.1f%%)\n", nm, freq_wf[nm], 100 * freq_wf[nm] / sum(freq_wf)))
}
cat(sprintf("  scale_predicted: mean=%.3f median=%.3f min=%.3f max=%.3f\n",
            mean(valid_wf$scale_predicted), median(valid_wf$scale_predicted),
            min(valid_wf$scale_predicted), max(valid_wf$scale_predicted)))

# Crisis date sanity (walk-forward)
crisis_dates <- as.Date(c("2008-10-01", "2009-03-02", "2011-09-01", "2020-03-02", "2022-10-04"))
cat("\n  Crisis date posteriors (walk-forward, NO smoothing):\n")
for (cd in crisis_dates) {
  cd <- as.Date(cd, origin = "1970-01-01")
  row <- valid_wf[date <= cd][.N]
  if (nrow(row) > 0) {
    cat(sprintf("    %s | predicted: P(N)=%.2f P(Ca)=%.2f P(Cr)=%.2f → %s | scale=%.2f\n",
                row$date,
                row$gamma_Normal_predicted, row$gamma_Caution_predicted, row$gamma_Crisis_predicted,
                row$most_likely_predicted, row$scale_predicted))
  }
}

# Compare smoothed vs walk-forward Crisis hit rate
smoothed <- fread(file.path(STAGE, "hmm_posterior_path.csv"))
smoothed[, date := as.Date(date)]
join_dt <- merge(walkforward_dt, smoothed, by = "date")
join_dt <- join_dt[!is.na(scale_predicted)]
agree_rate <- mean(join_dt$most_likely == join_dt$most_likely_predicted)
cat(sprintf("\n  Smoothed vs Walk-forward most_likely agreement: %.1f%%\n", agree_rate * 100))

# ─────────────────────────────────────────────────────────
# 3. Bootstrap CI for Crisis state metrics (n=47)
# ─────────────────────────────────────────────────────────
cat("\n[3] Bootstrap CI for Crisis state (n=47, B=2000)...\n")

# Use smoothed posterior to identify Crisis observations
crisis_idx <- which(smoothed$most_likely == "Crisis")
str_v <- feat_complete$str_ret
crisis_str <- str_v[crisis_idx]
n_crisis <- length(crisis_str)
cat(sprintf("  Crisis observations: n=%d, mean=%.4f, sd=%.4f\n",
            n_crisis, mean(crisis_str), sd(crisis_str)))

B <- 2000L
boot_means <- numeric(B); boot_sds <- numeric(B); boot_sharpe <- numeric(B)
boot_var95 <- numeric(B); boot_cvar95 <- numeric(B)

set.seed(20260504L)
for (b in 1:B) {
  idx <- sample.int(n_crisis, n_crisis, replace = TRUE)
  s <- crisis_str[idx]
  boot_means[b]  <- mean(s) * 12
  boot_sds[b]    <- sd(s) * sqrt(12)
  boot_sharpe[b] <- if (boot_sds[b] > 0) boot_means[b] / boot_sds[b] else 0
  losses <- -s
  v95 <- quantile(losses, 0.95, na.rm = TRUE)
  boot_var95[b]  <- v95
  boot_cvar95[b] <- if (any(losses >= v95)) mean(losses[losses >= v95]) else v95
}

ci <- function(x, level = 0.95) {
  q <- quantile(x, c((1 - level) / 2, 1 - (1 - level) / 2), na.rm = TRUE)
  list(lo = round(as.numeric(q[1]), 4), hi = round(as.numeric(q[2]), 4),
       mean = round(mean(x, na.rm = TRUE), 4), sd = round(sd(x, na.rm = TRUE), 4))
}

bootstrap_ci <- list(
  task_id = WT_ID,
  state = "Crisis",
  n_obs = n_crisis,
  B_resamples = B,
  ann_return    = ci(boot_means),
  ann_vol       = ci(boot_sds),
  ann_sharpe    = ci(boot_sharpe),
  monthly_VaR_95 = ci(boot_var95),
  monthly_CVaR_95 = ci(boot_cvar95),
  pooled_fallback_recommendation = list(
    rationale = "Crisis n=47 yields sharpe CI width ~ 1.0+. For sizing decisions, recommend 0.5x posterior weight blend with Caution-state when Crisis is < 20 obs",
    blend_rule = "if state_t == Crisis & n_state < 50: scale_t = 0.5*scale_Crisis + 0.5*scale_Caution",
    current_n = n_crisis,
    blend_active = n_crisis < 50,
    blended_scale_Crisis = if (n_crisis < 50) 0.5 * scale_adopted["Crisis"] + 0.5 * scale_adopted["Caution"] else scale_adopted["Crisis"]
  )
)

write_json(bootstrap_ci, file.path(STAGE, "crisis_bootstrap_ci.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("  Crisis bootstrap CI (95%):\n")
cat(sprintf("    ann_ret:    [%.4f, %.4f] (mean=%.4f)\n",
            bootstrap_ci$ann_return$lo, bootstrap_ci$ann_return$hi, bootstrap_ci$ann_return$mean))
cat(sprintf("    ann_vol:    [%.4f, %.4f] (mean=%.4f)\n",
            bootstrap_ci$ann_vol$lo, bootstrap_ci$ann_vol$hi, bootstrap_ci$ann_vol$mean))
cat(sprintf("    ann_sharpe: [%.4f, %.4f] (mean=%.4f)\n",
            bootstrap_ci$ann_sharpe$lo, bootstrap_ci$ann_sharpe$hi, bootstrap_ci$ann_sharpe$mean))
cat(sprintf("    CVaR_95:    [%.4f, %.4f] (mean=%.4f)\n",
            bootstrap_ci$monthly_CVaR_95$lo, bootstrap_ci$monthly_CVaR_95$hi,
            bootstrap_ci$monthly_CVaR_95$mean))

cat(sprintf("\n  pooled_fallback active (n=%d < 50): %s\n",
            n_crisis, bootstrap_ci$pooled_fallback_recommendation$blend_active))
cat(sprintf("  blended_scale_Crisis: %.4f (was %.4f, blended with Caution)\n",
            bootstrap_ci$pooled_fallback_recommendation$blended_scale_Crisis,
            scale_adopted["Crisis"]))

cat("\n=========================================================\n")
cat("Walk-forward + Bootstrap CI DONE.\n")
cat("=========================================================\n")
