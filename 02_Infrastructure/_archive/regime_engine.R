#==============================================================================
# Quant Module — Endogenous Market Regime Engine
# Version: 1.0.0
#
# Identifies 4 market regimes from RAWDATA using ONLY endogenous (price-based)
# features: cross-sectional dispersion, market breadth, vol term structure,
# momentum/liquidity. No external macro data required.
#
# Method: 14 features → PCA(3D) → Custom EM-GMM(4 regimes)
# Regimes: Expansion / Compression / Stress / Transition
#
# Usage:
#   source("config.R")
#   source("backtest_harness.R")
#   source("regime_engine.R")
#   res <- load_rawdata()
#   regime_dt <- run_regime_pipeline(res$RAWDATA, save_cache = TRUE)
#   FACTORS   <- merge_regime_to_strategy(FACTORS, regime_dt)
#
# Dependencies: data.table, arrow, stats, MASS, cluster (all pre-installed)
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(sys.frame(1)$ofile %||% "."), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(MASS)       # ginv()
  library(cluster)    # pam()
})

cat("[regime_engine] Loaded.\n")

#==============================================================================
# CONSTANTS — Factor weight matrix and portfolio params by regime
#==============================================================================

# Rows: Expansion, Compression, Stress, Transition
# Cols: Momentum, LowVol, Quality, Value, Defensive
REGIME_FACTOR_WEIGHTS <- matrix(
  c(0.30, 0.15, 0.15, 0.20, 0.05,   # Expansion
    0.10, 0.35, 0.30, 0.15, 0.10,   # Compression
    0.00, 0.50, 0.30, 0.10, 0.10,   # Stress
    0.15, 0.30, 0.25, 0.15, 0.15),  # Transition
  nrow = 4, byrow = TRUE,
  dimnames = list(
    c("Expansion", "Compression", "Stress", "Transition"),
    c("Momentum", "LowVol", "Quality", "Value", "Defensive")
  )
)

# Cash allocation: min/max by regime
REGIME_CASH_RANGE <- list(
  Expansion   = c(0.00, 0.00),
  Compression = c(0.00, 0.00),
  Stress      = c(0.00, 0.30),
  Transition  = c(0.00, 0.15)
)

# Portfolio params by regime
REGIME_PORTFOLIO_PARAMS <- list(
  Expansion   = list(n_holdings = 30L, weight_method = "ivol",  vol_target = NULL),
  Compression = list(n_holdings = 20L, weight_method = "ivol",  vol_target = 0.15),
  Stress      = list(n_holdings = 15L, weight_method = "equal", vol_target = 0.10),
  Transition  = list(n_holdings = 20L, weight_method = "ivol",  vol_target = 0.12)
)


#==============================================================================
# 1. compute_regime_features() — 14 endogenous features from RAWDATA
#==============================================================================
#
# Returns: data.table with columns: Date + 14 feature columns
#          One row per trading day (daily granularity, monthly signals
#          are extracted later by the caller or run_regime_pipeline)
#
# RAWDATA columns used: Date, Ticker, Open, High, Low, Close, Vol, Size,
#                       Ret, Sector, BM_Ret
#==============================================================================

compute_regime_features <- function(RAWDATA) {

  cat("[regime_engine] Computing 14 endogenous features...\n")

  # Ensure sorted
  setorder(RAWDATA, Date, Ticker)
  all_dates <- sort(unique(RAWDATA$Date))

  # ── Pre-compute daily GK volatility per ticker-date ──
  # Garman-Klass: 0.5*(log(H/L))^2 - (2*log(2)-1)*(log(C/O))^2
  RAWDATA[, GK_daily := fifelse(
    High > 0 & Low > 0 & Close > 0 & Open > 0,
    0.5 * (log(High / Low))^2 - (2 * log(2) - 1) * (log(Close / Open))^2,
    NA_real_
  )]
  # GK can be negative in rare cases; floor at 0

  RAWDATA[, GK_daily := pmax(GK_daily, 0, na.rm = TRUE)]

  # ── Pre-compute turnover per ticker-date ──
  RAWDATA[, Turnover := fifelse(Size > 0, Vol / Size, NA_real_)]

  # ── Pre-compute 252-day rolling max of Close per ticker ──
  # Used for NewHigh_Pct
  setorder(RAWDATA, Ticker, Date)
  RAWDATA[, RollMax252 := frollapply(Close, n = 252, FUN = max, align = "right",
                                      fill = NA_real_),
          by = Ticker]

  # ── Pre-compute 21-day sector return ──
  # Sector-level: average Ret per sector per day, then 21d cumulative
  sector_daily <- RAWDATA[, .(Sector_Ret_daily = mean(Ret, na.rm = TRUE)),
                          by = .(Date, Sector)]
  setorder(sector_daily, Sector, Date)
  sector_daily[, Sector_Ret_21d := frollapply(
    1 + Sector_Ret_daily, n = 21, FUN = function(x) prod(x, na.rm = TRUE) - 1,
    align = "right", fill = NA_real_
  ), by = Sector]

  # ── Pre-compute momentum quintile returns for MomCrash ──
  # 63-day momentum per ticker
  setorder(RAWDATA, Ticker, Date)
  RAWDATA[, Mom63 := frollapply(
    1 + Ret, n = 63, FUN = function(x) prod(x, na.rm = TRUE) - 1,
    align = "right", fill = NA_real_
  ), by = Ticker]

  # ── Build daily cross-sectional features ──
  cat("[regime_engine]   Layer A: Cross-Sectional Dispersion...\n")

  # CS_RetDisp: sd(Ret_i) across tickers per day
  cs_daily <- RAWDATA[!is.na(Ret), .(
    CS_RetDisp_raw = sd(Ret, na.rm = TRUE),
    CS_VolDisp_raw = sd(GK_daily, na.rm = TRUE),
    N_tickers      = .N
  ), by = Date]
  setorder(cs_daily, Date)

  # Trailing 21d average of CS_RetDisp and CS_VolDisp
  cs_daily[, CS_RetDisp := frollmean(CS_RetDisp_raw, n = 21, align = "right",
                                      fill = NA_real_)]
  cs_daily[, CS_VolDisp := frollmean(CS_VolDisp_raw, n = 21, align = "right",
                                      fill = NA_real_)]

  # Disp_Ratio: CS_RetDisp(21d) / CS_RetDisp(252d)
  cs_daily[, CS_RetDisp_252 := frollmean(CS_RetDisp_raw, n = 252,
                                          align = "right", fill = NA_real_)]
  cs_daily[, Disp_Ratio := fifelse(CS_RetDisp_252 > 0,
                                    CS_RetDisp / CS_RetDisp_252, NA_real_)]

  cat("[regime_engine]   Layer B: Market Breadth...\n")

  # AD_Ratio: fraction of tickers with positive return per day
  breadth_daily <- RAWDATA[!is.na(Ret), .(
    AD_raw      = sum(Ret > 0, na.rm = TRUE) / .N,
    NewHigh_raw = sum(!is.na(RollMax252) & abs(Close - RollMax252) < 1e-6, na.rm = TRUE) / .N
  ), by = Date]
  setorder(breadth_daily, Date)

  # AD_Ratio: 10d EMA
  # EMA via recursive filter: alpha = 2/(10+1)
  .ema <- function(x, span) {
    alpha <- 2 / (span + 1)
    result <- numeric(length(x))
    result[1] <- x[1]
    for (i in 2:length(x)) {
      if (is.na(x[i])) {
        result[i] <- result[i - 1]
      } else if (is.na(result[i - 1])) {
        result[i] <- x[i]
      } else {
        result[i] <- alpha * x[i] + (1 - alpha) * result[i - 1]
      }
    }
    result
  }

  breadth_daily[, AD_Ratio := .ema(AD_raw, 10)]

  # AD_Thrust: max(AD_Ratio, 10d) - min(AD_Ratio, 10d)
  breadth_daily[, AD_max10 := frollapply(AD_Ratio, n = 10, FUN = max,
                                          align = "right", fill = NA_real_)]
  breadth_daily[, AD_min10 := frollapply(AD_Ratio, n = 10, FUN = min,
                                          align = "right", fill = NA_real_)]
  breadth_daily[, AD_Thrust := AD_max10 - AD_min10]

  # NewHigh_Pct: already computed as NewHigh_raw
  breadth_daily[, NewHigh_Pct := NewHigh_raw]

  # Sector_Breadth: fraction of sectors with positive 21d return
  sector_breadth <- sector_daily[!is.na(Sector_Ret_21d),
                                  .(Sector_Breadth = sum(Sector_Ret_21d > 0) / .N),
                                  by = Date]

  cat("[regime_engine]   Layer C: Volatility Term Structure...\n")

  # Vol_Short: mean(GK_daily) across universe, trailing 5d
  # Vol_Long: mean(GK_daily) across universe, trailing 63d
  vol_daily <- RAWDATA[!is.na(GK_daily), .(Vol_mean = mean(GK_daily, na.rm = TRUE)),
                       by = Date]
  setorder(vol_daily, Date)

  vol_daily[, Vol_Short := frollmean(Vol_mean, n = 5, align = "right",
                                      fill = NA_real_)]
  vol_daily[, Vol_Long := frollmean(Vol_mean, n = 63, align = "right",
                                     fill = NA_real_)]
  vol_daily[, Vol_Ratio := fifelse(Vol_Long > 0, Vol_Short / Vol_Long, NA_real_)]

  # Vol_Acceleration: diff(Vol_Short, lag=5) / Vol_Long
  vol_daily[, Vol_Short_lag5 := shift(Vol_Short, n = 5, type = "lag")]
  vol_daily[, Vol_Acceleration := fifelse(
    Vol_Long > 0 & !is.na(Vol_Short_lag5),
    (Vol_Short - Vol_Short_lag5) / Vol_Long,
    NA_real_
  )]

  cat("[regime_engine]   Layer D: Momentum / Liquidity...\n")

  # BM_Mom: 63d cumulative BM return
  bm_daily <- RAWDATA[!is.na(BM_Ret), .(BM_Ret = BM_Ret[1]), by = Date]
  setorder(bm_daily, Date)
  bm_daily[, BM_Mom := frollapply(
    1 + BM_Ret, n = 63, FUN = function(x) prod(x, na.rm = TRUE) - 1,
    align = "right", fill = NA_real_
  )]

  # MomCrash_Ind: top quintile 63d mom - bottom quintile 63d mom
  momcrash_daily <- RAWDATA[!is.na(Mom63), {
    q <- quantile(Mom63, probs = c(0.2, 0.8), na.rm = TRUE)
    bot <- mean(Mom63[Mom63 <= q[1]], na.rm = TRUE)
    top <- mean(Mom63[Mom63 >= q[2]], na.rm = TRUE)
    .(MomCrash_Ind = top - bot)
  }, by = Date]

  # Agg_Turnover_Ratio: aggregate turnover(5d) / aggregate turnover(63d)
  to_daily <- RAWDATA[!is.na(Turnover), .(Agg_TO = mean(Turnover, na.rm = TRUE)),
                      by = Date]
  setorder(to_daily, Date)
  to_daily[, TO_5d := frollmean(Agg_TO, n = 5, align = "right", fill = NA_real_)]
  to_daily[, TO_63d := frollmean(Agg_TO, n = 63, align = "right", fill = NA_real_)]
  to_daily[, Agg_Turnover_Ratio := fifelse(TO_63d > 0, TO_5d / TO_63d, NA_real_)]

  # ── Merge all features ──
  cat("[regime_engine]   Merging feature layers...\n")

  feat <- cs_daily[, .(Date, CS_RetDisp, CS_VolDisp, Disp_Ratio)]
  feat <- merge(feat, breadth_daily[, .(Date, AD_Ratio, AD_Thrust, NewHigh_Pct)],
                by = "Date", all.x = TRUE)
  feat <- merge(feat, sector_breadth, by = "Date", all.x = TRUE)
  feat <- merge(feat, vol_daily[, .(Date, Vol_Short, Vol_Long, Vol_Ratio, Vol_Acceleration)],
                by = "Date", all.x = TRUE)
  feat <- merge(feat, bm_daily[, .(Date, BM_Mom)], by = "Date", all.x = TRUE)
  feat <- merge(feat, momcrash_daily, by = "Date", all.x = TRUE)
  feat <- merge(feat, to_daily[, .(Date, Agg_Turnover_Ratio)], by = "Date", all.x = TRUE)

  setorder(feat, Date)

  # ── Clean up temporary columns in RAWDATA ──
  RAWDATA[, c("GK_daily", "Turnover", "RollMax252", "Mom63") := NULL]

  feature_cols <- c("CS_RetDisp", "CS_VolDisp", "Disp_Ratio",
                    "AD_Ratio", "AD_Thrust", "NewHigh_Pct", "Sector_Breadth",
                    "Vol_Short", "Vol_Long", "Vol_Ratio", "Vol_Acceleration",
                    "BM_Mom", "MomCrash_Ind", "Agg_Turnover_Ratio")

  n_complete <- sum(complete.cases(feat[, ..feature_cols]))
  cat(sprintf("[regime_engine] Feature computation done. %d/%d complete rows.\n",
              n_complete, nrow(feat)))

  feat
}


#==============================================================================
# 2. fit_regime_model() — PCA + Custom EM-GMM
#==============================================================================
#
# Input:  feature_dt — data.table with Date + 14 feature columns (window)
# Output: list(pca_center, pca_scale, pca_rotation, gmm) where gmm contains
#         mu (K x D), sigma (list of D x D), pi_k (K), labels (ordered names)
#==============================================================================

fit_regime_model <- function(feature_dt, n_regimes = 4L, n_pcs = 3L,
                             max_iter = 100L, tol = 1e-6) {

  feature_cols <- c("CS_RetDisp", "CS_VolDisp", "Disp_Ratio",
                    "AD_Ratio", "AD_Thrust", "NewHigh_Pct", "Sector_Breadth",
                    "Vol_Short", "Vol_Long", "Vol_Ratio", "Vol_Acceleration",
                    "BM_Mom", "MomCrash_Ind", "Agg_Turnover_Ratio")

  # Extract complete-case matrix
  X_raw <- as.matrix(feature_dt[, ..feature_cols])
  complete_mask <- complete.cases(X_raw)
  X_raw <- X_raw[complete_mask, ]

  if (nrow(X_raw) < n_regimes * 10) {
    warning("[fit_regime_model] Insufficient data: ", nrow(X_raw), " rows.")
    return(NULL)
  }

  # Standardize
  mu_x <- colMeans(X_raw)
  sd_x <- apply(X_raw, 2, sd)
  sd_x[sd_x < 1e-12] <- 1  # prevent div/0
  X_std <- scale(X_raw, center = mu_x, scale = sd_x)

  # PCA
  pca <- prcomp(X_std, center = FALSE, scale. = FALSE)
  Z <- pca$x[, 1:n_pcs, drop = FALSE]  # N x n_pcs

  N <- nrow(Z)
  D <- ncol(Z)
  K <- n_regimes

  # ── Initialize with PAM (k-medoids) ──
  pam_fit <- pam(Z, k = K, variant = "faster")
  init_labels <- pam_fit$clustering  # 1..K

  mu_k    <- matrix(0, K, D)
  sigma_k <- vector("list", K)
  pi_k    <- numeric(K)

  for (k in 1:K) {
    idx <- which(init_labels == k)
    pi_k[k] <- length(idx) / N
    mu_k[k, ] <- colMeans(Z[idx, , drop = FALSE])
    if (length(idx) > D) {
      sigma_k[[k]] <- cov(Z[idx, , drop = FALSE]) + diag(1e-6, D)
    } else {
      sigma_k[[k]] <- diag(1, D)
    }
  }

  # ── Custom EM-GMM ──
  # Helper: log of multivariate normal density
  .log_mvn_density <- function(x, mu, sigma) {
    # x: N x D, mu: length D, sigma: D x D
    D <- length(mu)
    diff <- sweep(x, 2, mu)
    # Use Cholesky for numerical stability; fall back to ginv
    chol_ok <- tryCatch({
      L <- chol(sigma)
      log_det <- 2 * sum(log(diag(L)))
      # solve(L, t(diff)) gives L^{-1} * diff^T
      tmp <- backsolve(L, t(diff), transpose = TRUE)  # D x N
      mahal <- colSums(tmp^2)  # N
      list(log_det = log_det, mahal = mahal)
    }, error = function(e) NULL)

    if (is.null(chol_ok)) {
      # Fallback: pseudo-inverse
      sigma_inv <- ginv(sigma)
      log_det <- as.numeric(determinant(sigma, logarithm = TRUE)$modulus)
      if (is.na(log_det) || is.infinite(log_det)) log_det <- 0
      mahal <- rowSums((diff %*% sigma_inv) * diff)
      list(log_det = log_det, mahal = mahal)
    } else {
      chol_ok
    }
  }

  log_lik_prev <- -Inf

  for (iter in 1:max_iter) {
    # ── E-step: compute responsibilities ──
    log_resp <- matrix(0, N, K)
    for (k in 1:K) {
      res <- .log_mvn_density(Z, mu_k[k, ], sigma_k[[k]])
      log_resp[, k] <- log(pi_k[k] + 1e-300) - 0.5 * D * log(2 * pi) -
                        0.5 * res$log_det - 0.5 * res$mahal
    }

    # Log-sum-exp trick for numerical stability
    log_resp_max <- apply(log_resp, 1, max)
    log_resp_shifted <- log_resp - log_resp_max
    log_sum <- log_resp_max + log(rowSums(exp(log_resp_shifted)))
    resp <- exp(log_resp - log_sum)  # N x K

    # Log-likelihood
    log_lik <- sum(log_sum)

    # Check convergence
    if (abs(log_lik - log_lik_prev) / (abs(log_lik) + 1e-10) < tol) {
      cat(sprintf("[regime_engine]   EM converged at iteration %d (LL=%.2f)\n",
                  iter, log_lik))
      break
    }
    log_lik_prev <- log_lik

    # ── M-step: update parameters ──
    N_k <- colSums(resp)  # K

    for (k in 1:K) {
      if (N_k[k] < 1e-6) next  # skip empty components
      pi_k[k] <- N_k[k] / N
      w_k <- resp[, k] / N_k[k]
      mu_k[k, ] <- colSums(Z * w_k)
      diff <- sweep(Z, 2, mu_k[k, ])
      sigma_k[[k]] <- t(diff * w_k) %*% diff + diag(1e-6, D)
    }
  }

  if (iter == max_iter) {
    cat(sprintf("[regime_engine]   EM reached max iterations (%d). LL=%.2f\n",
                max_iter, log_lik))
  }

  # ── Anchor regime labels to centroid properties ──
  # Logic: use PC1 (market direction proxy) and vol level (Vol_Ratio proxy via PC loadings)
  # PC1 positive & low vol → Expansion
  # PC1 negative & high vol → Stress
  # PC1 near zero & low vol → Compression
  # Remaining → Transition
  #
  # Simplified: rank by PC1 centroid value
  # Highest PC1 → Expansion, Lowest PC1 → Stress
  # Among middle two: lower vol (PC2 proxy) → Compression, other → Transition

  pc1_order <- order(mu_k[, 1])  # ascending PC1

  # Load the vol-related features into PCA to understand PC interpretation

  # We rank centroids: lowest PC1 = Stress, highest = Expansion
  # Middle two sorted by Vol_Ratio loading contribution
  label_map <- character(K)
  label_map[pc1_order[1]] <- "Stress"       # lowest PC1
  label_map[pc1_order[K]] <- "Expansion"    # highest PC1

  if (K >= 4) {
    # Among middle components, the one with higher vol centroid → Transition
    mid_indices <- pc1_order[2:(K - 1)]
    # Use PC2 or PC3 as tiebreaker (vol structure)
    if (D >= 2) {
      vol_proxy <- mu_k[mid_indices, 2]  # PC2 values
      label_map[mid_indices[which.min(vol_proxy)]] <- "Compression"
      label_map[mid_indices[which.max(vol_proxy)]] <- "Transition"
    } else {
      label_map[mid_indices[1]] <- "Compression"
      label_map[mid_indices[2]] <- "Transition"
    }
  } else if (K == 3) {
    label_map[pc1_order[2]] <- "Compression"
  }

  model <- list(
    pca_center   = mu_x,
    pca_scale    = sd_x,
    pca_rotation = pca$rotation[, 1:n_pcs, drop = FALSE],
    gmm = list(
      mu      = mu_k,
      sigma   = sigma_k,
      pi_k    = pi_k,
      K       = K,
      D       = D,
      labels  = label_map
    )
  )

  cat(sprintf("[regime_engine] Model fit: K=%d, D=%d, N=%d observations.\n",
              K, D, N))

  model
}


#==============================================================================
# 3. classify_regime() — Classify a single observation or batch
#==============================================================================
#
# Input:  feature_row — data.table/matrix with 14 feature columns (1+ rows)
#         model       — output of fit_regime_model()
# Output: data.table with columns: Regime (char), prob_Expansion, prob_Compression,
#         prob_Stress, prob_Transition
#==============================================================================

classify_regime <- function(feature_row, model) {

  feature_cols <- c("CS_RetDisp", "CS_VolDisp", "Disp_Ratio",
                    "AD_Ratio", "AD_Thrust", "NewHigh_Pct", "Sector_Breadth",
                    "Vol_Short", "Vol_Long", "Vol_Ratio", "Vol_Acceleration",
                    "BM_Mom", "MomCrash_Ind", "Agg_Turnover_Ratio")

  X_raw <- as.matrix(feature_row[, ..feature_cols])

  # Standardize with training parameters
  X_std <- sweep(X_raw, 2, model$pca_center)
  X_std <- sweep(X_std, 2, model$pca_scale, "/")

  # Project to PCA space
  Z <- X_std %*% model$pca_rotation  # N x D

  N <- nrow(Z)
  K <- model$gmm$K
  D <- model$gmm$D

  # Compute responsibilities (same as E-step)
  log_resp <- matrix(0, N, K)
  for (k in 1:K) {
    mu  <- model$gmm$mu[k, ]
    sig <- model$gmm$sigma[[k]]
    diff <- sweep(Z, 2, mu)

    chol_ok <- tryCatch({
      L <- chol(sig)
      log_det <- 2 * sum(log(diag(L)))
      tmp <- backsolve(L, t(diff), transpose = TRUE)
      mahal <- colSums(tmp^2)
      list(log_det = log_det, mahal = mahal)
    }, error = function(e) {
      sig_inv <- ginv(sig)
      log_det <- as.numeric(determinant(sig, logarithm = TRUE)$modulus)
      if (is.na(log_det) || is.infinite(log_det)) log_det <- 0
      mahal <- rowSums((diff %*% sig_inv) * diff)
      list(log_det = log_det, mahal = mahal)
    })

    log_resp[, k] <- log(model$gmm$pi_k[k] + 1e-300) -
                     0.5 * D * log(2 * pi) -
                     0.5 * chol_ok$log_det -
                     0.5 * chol_ok$mahal
  }

  # Softmax
  log_resp_max <- apply(log_resp, 1, max)
  log_resp_shifted <- log_resp - log_resp_max
  denom <- log_resp_max + log(rowSums(exp(log_resp_shifted)))
  probs <- exp(log_resp - denom)  # N x K

  # Map to named regimes
  labels <- model$gmm$labels  # character vector length K
  regime_names <- c("Expansion", "Compression", "Stress", "Transition")

  # Build output
  result <- data.table(
    Regime = labels[apply(probs, 1, which.max)]
  )

  for (rn in regime_names) {
    k_idx <- which(labels == rn)
    if (length(k_idx) == 1) {
      set(result, j = paste0("prob_", rn), value = probs[, k_idx])
    } else {
      set(result, j = paste0("prob_", rn), value = 0)
    }
  }

  result
}


#==============================================================================
# 4. get_factor_weights() — Blend factor weights by regime probabilities
#==============================================================================
#
# Input:  regime_probs — named vector: prob_Expansion, prob_Compression, etc.
#         weight_matrix — (default: REGIME_FACTOR_WEIGHTS)
# Output: named numeric vector (Momentum, LowVol, Quality, Value, Defensive)
#==============================================================================

get_factor_weights <- function(regime_probs,
                               weight_matrix = REGIME_FACTOR_WEIGHTS) {

  regime_names <- c("Expansion", "Compression", "Stress", "Transition")
  prob_vec <- numeric(4)
  for (i in seq_along(regime_names)) {
    pname <- paste0("prob_", regime_names[i])
    prob_vec[i] <- if (!is.null(regime_probs[[pname]])) regime_probs[[pname]] else 0
  }

  # Normalize probs (should already sum to 1, but safety)
  if (sum(prob_vec) > 0) prob_vec <- prob_vec / sum(prob_vec)

  # Weighted average across regimes
  blended <- as.numeric(t(prob_vec) %*% weight_matrix)
  names(blended) <- colnames(weight_matrix)

  blended
}


#==============================================================================
# 5. get_portfolio_params() — Portfolio construction params by regime
#==============================================================================
#
# Input:  regime_probs — named list/vector with prob_Expansion, etc.
# Output: list(n_holdings, weight_method, vol_target, cash_pct, regime_label)
#==============================================================================

get_portfolio_params <- function(regime_probs) {

  regime_names <- c("Expansion", "Compression", "Stress", "Transition")
  prob_vec <- numeric(4)
  for (i in seq_along(regime_names)) {
    pname <- paste0("prob_", regime_names[i])
    prob_vec[i] <- if (!is.null(regime_probs[[pname]])) regime_probs[[pname]] else 0
  }
  if (sum(prob_vec) > 0) prob_vec <- prob_vec / sum(prob_vec)
  names(prob_vec) <- regime_names

  dominant <- regime_names[which.max(prob_vec)]
  dom_params <- REGIME_PORTFOLIO_PARAMS[[dominant]]

  # Blend n_holdings (probability-weighted)
  n_vec <- sapply(regime_names, function(rn) REGIME_PORTFOLIO_PARAMS[[rn]]$n_holdings)
  n_holdings <- round(sum(prob_vec * n_vec))

  # Weight method from dominant regime
  weight_method <- dom_params$weight_method

  # Vol target: probability-weighted (NULL treated as no-target → use max vol)
  vol_targets <- sapply(regime_names, function(rn) {
    vt <- REGIME_PORTFOLIO_PARAMS[[rn]]$vol_target
    if (is.null(vt)) NA_real_ else vt
  })
  if (all(is.na(vol_targets[prob_vec > 0.1]))) {
    # All dominant regimes have no vol target
    vol_target <- NULL
  } else {
    # Weighted average of non-NULL targets
    mask <- !is.na(vol_targets)
    if (sum(prob_vec[mask]) > 0) {
      vol_target <- sum(prob_vec[mask] * vol_targets[mask]) / sum(prob_vec[mask])
    } else {
      vol_target <- NULL
    }
  }

  # Cash allocation: probability-weighted linear interp within each regime's range
  # Higher stress prob → more cash within the stress range
  cash_pct <- 0
  for (i in seq_along(regime_names)) {
    rn <- regime_names[i]
    cr <- REGIME_CASH_RANGE[[rn]]
    # Within regime, use prob as intensity: higher prob → closer to max
    regime_cash <- cr[1] + prob_vec[i] * (cr[2] - cr[1])
    cash_pct <- cash_pct + prob_vec[i] * regime_cash
  }
  cash_pct <- min(cash_pct, 0.30)  # hard cap

  list(
    n_holdings    = as.integer(n_holdings),
    weight_method = weight_method,
    vol_target    = vol_target,
    cash_pct      = round(cash_pct, 4),
    regime_label  = dominant
  )
}


#==============================================================================
# 6. run_regime_pipeline() — Full pipeline: features → model → classify
#==============================================================================
#
# Rolling approach: at each monthly signal date, use trailing 60-month window
# to fit PCA + GMM, then classify current month.
#
# Returns: data.table with Date, Regime, prob_*, factor weights, portfolio params
# Optionally saves to .cache/market_regime_endo.parquet
#==============================================================================

run_regime_pipeline <- function(RAWDATA,
                                save_cache    = TRUE,
                                rolling_months = 60L,
                                min_months     = 36L,
                                n_regimes      = 4L,
                                n_pcs          = 3L) {

  cat("[regime_engine] ═══ Starting Endogenous Regime Pipeline ═══\n")

  # ── Step 1: Compute all daily features ──
  feat_dt <- compute_regime_features(RAWDATA)

  feature_cols <- c("CS_RetDisp", "CS_VolDisp", "Disp_Ratio",
                    "AD_Ratio", "AD_Thrust", "NewHigh_Pct", "Sector_Breadth",
                    "Vol_Short", "Vol_Long", "Vol_Ratio", "Vol_Acceleration",
                    "BM_Mom", "MomCrash_Ind", "Agg_Turnover_Ratio")

  # ── Step 2: Identify monthly signal dates (last trading day per month) ──
  feat_dt[, YM := format(Date, "%Y-%m")]
  month_ends <- feat_dt[, .(Date = max(Date)), by = YM]
  setorder(month_ends, Date)
  signal_dates <- month_ends$Date

  cat(sprintf("[regime_engine] %d monthly signal dates: %s ~ %s\n",
              length(signal_dates), min(signal_dates), max(signal_dates)))

  # ── Step 3: Rolling classification ──
  results <- vector("list", length(signal_dates))

  for (i in seq_along(signal_dates)) {
    sig_date <- signal_dates[i]

    # Define window: trailing rolling_months months of daily data
    window_start <- sig_date - rolling_months * 30  # approximate
    window_dt <- feat_dt[Date >= window_start & Date <= sig_date]
    window_complete <- window_dt[complete.cases(window_dt[, ..feature_cols])]

    # Check minimum data requirement
    n_months_avail <- uniqueN(format(window_complete$Date, "%Y-%m"))
    if (n_months_avail < min_months) {
      # Not enough history yet — skip
      next
    }

    # Fit model on window
    model <- tryCatch(
      fit_regime_model(window_complete, n_regimes = n_regimes, n_pcs = n_pcs),
      error = function(e) {
        cat(sprintf("[regime_engine] WARN: Model fit failed for %s: %s\n",
                    sig_date, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(model)) next

    # Classify current date
    current_row <- feat_dt[Date == sig_date]
    if (nrow(current_row) == 0 || !complete.cases(current_row[, ..feature_cols])) next

    regime_class <- classify_regime(current_row, model)

    # Get factor weights and portfolio params
    regime_probs <- as.list(regime_class[1])
    fw <- get_factor_weights(regime_probs)
    pp <- get_portfolio_params(regime_probs)

    results[[i]] <- data.table(
      Date             = sig_date,
      Regime           = regime_class$Regime[1],
      prob_Expansion   = regime_class$prob_Expansion[1],
      prob_Compression = regime_class$prob_Compression[1],
      prob_Stress      = regime_class$prob_Stress[1],
      prob_Transition  = regime_class$prob_Transition[1],
      fw_Momentum      = fw["Momentum"],
      fw_LowVol        = fw["LowVol"],
      fw_Quality       = fw["Quality"],
      fw_Value         = fw["Value"],
      fw_Defensive     = fw["Defensive"],
      n_holdings       = pp$n_holdings,
      weight_method    = pp$weight_method,
      vol_target       = if (is.null(pp$vol_target)) NA_real_ else pp$vol_target,
      cash_pct         = pp$cash_pct
    )

    # Progress
    if (i %% 24 == 0 || i == length(signal_dates)) {
      cat(sprintf("[regime_engine]   %d/%d dates classified. Current: %s → %s\n",
                  i, length(signal_dates), sig_date, regime_class$Regime[1]))
    }
  }

  regime_dt <- rbindlist(results[!sapply(results, is.null)])

  if (nrow(regime_dt) == 0) {
    warning("[regime_engine] No regimes classified. Check data coverage.")
    return(data.table())
  }

  setorder(regime_dt, Date)

  # ── Summary ──
  cat("\n[regime_engine] ═══ Regime Distribution ═══\n")
  regime_summary <- regime_dt[, .N, by = Regime]
  regime_summary[, Pct := round(N / sum(N) * 100, 1)]
  print(regime_summary)
  cat(sprintf("[regime_engine] Total: %d months classified (%s ~ %s)\n",
              nrow(regime_dt), min(regime_dt$Date), max(regime_dt$Date)))

  # ── Save cache ──
  if (save_cache) {
    cache_path <- if (exists("REGIME_ENDO_CACHE")) {
      REGIME_ENDO_CACHE
    } else {
      file.path(CACHE_DIR, "market_regime_endo.parquet")
    }
    write_parquet(regime_dt, cache_path)
    cat(sprintf("[regime_engine] Saved to: %s\n", cache_path))
  }

  regime_dt
}


#==============================================================================
# 7. merge_regime_to_strategy() — Rolling join regime data to FACTORS
#==============================================================================
#
# Joins the most recent regime classification to each signal date in FACTORS.
# Uses data.table rolling join (roll = TRUE) so each FACTORS$Date picks up
# the latest regime on or before that date.
#
# Input:  FACTORS   — data.table with Date, Ticker, Score (+ optional cols)
#         regime_dt — output of run_regime_pipeline() or loaded from cache
# Output: FACTORS with added columns: Regime, prob_*, fw_*, n_holdings, etc.
#==============================================================================

merge_regime_to_strategy <- function(FACTORS, regime_dt) {

  if (is.null(regime_dt) || nrow(regime_dt) == 0) {
    cat("[regime_engine] No regime data to merge. Returning FACTORS unchanged.\n")
    return(FACTORS)
  }

  # Prepare regime_dt for rolling join
  regime_join <- copy(regime_dt)
  setkey(regime_join, Date)

  # Get unique signal dates from FACTORS
  sig_dates <- unique(FACTORS$Date)
  sig_dt <- data.table(Date = sig_dates)
  setkey(sig_dt, Date)

  # Rolling join: for each signal date, get the latest regime on or before
  matched <- regime_join[sig_dt, roll = TRUE]

  # Merge back into FACTORS
  merge_cols <- setdiff(names(regime_dt), "Date")
  FACTORS <- merge(FACTORS, matched[, c("Date", merge_cols), with = FALSE],
                   by = "Date", all.x = TRUE)

  n_matched <- sum(!is.na(FACTORS$Regime))
  n_total   <- nrow(FACTORS)
  cat(sprintf("[regime_engine] Merged regime data: %d/%d rows matched (%.1f%%)\n",
              n_matched, n_total, n_matched / n_total * 100))

  FACTORS
}


#==============================================================================
# 8. load_regime_cache() — Load cached regime data
#==============================================================================

load_regime_cache <- function() {
  cache_path <- if (exists("REGIME_ENDO_CACHE")) {
    REGIME_ENDO_CACHE
  } else {
    file.path(CACHE_DIR, "market_regime_endo.parquet")
  }

  if (!file.exists(cache_path)) {
    cat("[regime_engine] No cached regime data found. Run run_regime_pipeline() first.\n")
    return(NULL)
  }

  dt <- as.data.table(read_parquet(cache_path))
  cat(sprintf("[regime_engine] Loaded regime cache: %d months | %s ~ %s\n",
              nrow(dt), min(dt$Date), max(dt$Date)))
  dt
}


#==============================================================================
# 9. apply_regime_to_simulation() — Helper to apply regime params to backtest
#==============================================================================
#
# For strategies that want regime-adaptive construction, call this before
# run_monthly_simulation() to get per-rebalance parameters.
#
# Input:  sig_date   — Date of current signal
#         regime_dt  — regime data.table
# Output: list(n_holdings, weight_method, vol_target, cash_pct, regime_label,
#              factor_weights)
#==============================================================================

apply_regime_to_simulation <- function(sig_date, regime_dt) {

  if (is.null(regime_dt) || nrow(regime_dt) == 0) {
    # Default (no regime info): conservative Transition params
    return(list(
      n_holdings    = 20L,
      weight_method = "ivol",
      vol_target    = 0.12,
      cash_pct      = 0,
      regime_label  = "Unknown",
      factor_weights = c(Momentum = 0.15, LowVol = 0.30, Quality = 0.25,
                         Value = 0.15, Defensive = 0.15)
    ))
  }

  # Find latest regime on or before sig_date
  regime_row <- regime_dt[Date <= sig_date]
  if (nrow(regime_row) == 0) {
    return(list(
      n_holdings    = 20L,
      weight_method = "ivol",
      vol_target    = 0.12,
      cash_pct      = 0,
      regime_label  = "Unknown",
      factor_weights = c(Momentum = 0.15, LowVol = 0.30, Quality = 0.25,
                         Value = 0.15, Defensive = 0.15)
    ))
  }

  regime_row <- regime_row[.N]  # latest row

  # Extract probabilities
  regime_probs <- list(
    prob_Expansion   = regime_row$prob_Expansion,
    prob_Compression = regime_row$prob_Compression,
    prob_Stress      = regime_row$prob_Stress,
    prob_Transition  = regime_row$prob_Transition
  )

  fw <- get_factor_weights(regime_probs)
  pp <- get_portfolio_params(regime_probs)

  list(
    n_holdings     = pp$n_holdings,
    weight_method  = pp$weight_method,
    vol_target     = pp$vol_target,
    cash_pct       = pp$cash_pct,
    regime_label   = pp$regime_label,
    factor_weights = fw
  )
}

cat("[regime_engine] All functions defined.\n")
