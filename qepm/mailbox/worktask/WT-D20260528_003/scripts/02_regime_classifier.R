#==============================================================================
# Step 3 — P4 Multi-Horizon Regime Classifier (K-means 9-cluster, walk-forward PIT)
#
# Input: outputs/p4_multi_horizon.parquet
#   Daily P4 statistics (mu/sigma/lam/var_05/var_01/p_minus_5pct + ACI) × 3 horizons
#
# Method:
#   1. Feature engineering: 15 raw features (5 stat × 3 horizon) at sig_date
#   2. Per-feature standardization (expanding window z-score, PIT-safe)
#   3. K-means 9-cluster (Hamilton 1989 motivation: ~9 regimes typical KR equity)
#   4. Walk-forward: warm-up = 252 trading days (~1y), then expanding fit + assign
#      per sig_date; PIT-safe (cluster fit only on past data <= sig_date)
#   5. Monthly snapshot: month-end sig_dates aligned with Phase 1 v3
#
# Output:
#   - outputs/regime_labels_daily.parquet (daily sig_date × regime_state ∈ {1..9})
#   - outputs/regime_labels_monthly.parquet (month-end snapshot)
#   - outputs/regime_classifier_diag.json (transition matrix + per-state freq)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs")
SHARED_OUT <- file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs")
P4_PATH <- file.path(SHARED_OUT, "p4_multi_horizon.parquet")

N_REGIMES <- 9L
WARMUP_DAYS <- 252L   # 1y warm-up before first regime assignment
RANDOM_SEED <- 42L

cat("[Regime Classifier] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load P4 multi-horizon ----
cat("[1] Loading p4_multi_horizon.parquet ...\n")
p4 <- as.data.table(read_parquet(P4_PATH))
p4[, Date := as.Date(Date)]
setorder(p4, Date)
cat("  rows:", nrow(p4), " | Date range:", as.character(min(p4$Date)), "~", as.character(max(p4$Date)), "\n")

# ---- 2. Feature engineering: 15 features = 5 stat × 3 horizon ----
# stats: mu, sigma, lam, var_05, p_minus_5pct
# horizons: 22, 44, 66
feature_cols <- c()
for (h in c(22, 44, 66)) {
  feature_cols <- c(feature_cols,
                     paste0("mu_", h), paste0("sigma_", h), paste0("lam_", h),
                     paste0("var_05_", h), paste0("p_minus_5pct_", h))
}
cat("  Features (n=", length(feature_cols), "):", paste(feature_cols, collapse = ", "), "\n")

# Drop rows with any NA across all 15 features (multi-horizon 44/66 has 22-44 day warm-up)
p4_clean <- p4[complete.cases(p4[, ..feature_cols])]
cat("  After NA drop:", nrow(p4_clean), " | first available Date:", as.character(min(p4_clean$Date)), "\n")

X_raw <- as.matrix(p4_clean[, ..feature_cols])
dates <- p4_clean$Date

# ---- 3. Walk-forward expanding window K-means ----
# Per t:
#   if t < WARMUP_DAYS: assign NA
#   else: fit K-means on X_raw[1..t-1], then predict X_raw[t]
#         (PIT: t에서 결정 시 t-1까지의 데이터로 학습)
#
# Practical: re-fit kmeans every K days (e.g., 21 trading days = ~1M) to avoid
# instability; assign label using nearest centroid for in-between days.
# This is PIT-safe (no future data) + computationally feasible.

cat("[3] Walk-forward K-means (N_REGIMES =", N_REGIMES, ", WARMUP =", WARMUP_DAYS, ") ...\n")

REFIT_EVERY <- 21L  # 21 trading days = monthly refit

n_obs <- nrow(X_raw)
labels <- rep(NA_integer_, n_obs)
centroids_history <- list()

# Standardize features using expanding window z-score (PIT)
# Per t: z[t] = (X[t] - mean(X[1..t-1])) / sd(X[1..t-1])
X_z <- matrix(NA_real_, nrow = n_obs, ncol = length(feature_cols))
colnames(X_z) <- feature_cols

# Compute expanding stats efficiently
for (j in seq_len(ncol(X_raw))) {
  x <- X_raw[, j]
  cum_sum <- cumsum(x)
  cum_sq <- cumsum(x^2)
  for (t in seq_len(n_obs)) {
    if (t < 60L) next  # need at least 60 obs for stable z
    mu_prev <- cum_sum[t - 1] / (t - 1)
    var_prev <- (cum_sq[t - 1] / (t - 1)) - mu_prev^2
    sd_prev <- sqrt(max(var_prev, 1e-10))
    X_z[t, j] <- (x[t] - mu_prev) / sd_prev
  }
}

# Walk-forward K-means
set.seed(RANDOM_SEED)
last_fit_idx <- 0L
last_centroids <- NULL

for (t in seq_len(n_obs)) {
  if (t < WARMUP_DAYS) next  # warm-up
  if (any(is.na(X_z[t, ]))) next

  # Refit centroids every REFIT_EVERY days
  if ((t - last_fit_idx) >= REFIT_EVERY || is.null(last_centroids)) {
    train_idx <- which(!is.na(X_z[, 1]))
    train_idx <- train_idx[train_idx < t]  # strictly past
    if (length(train_idx) >= N_REGIMES * 10L) {
      X_train <- X_z[train_idx, , drop = FALSE]
      X_train <- X_train[complete.cases(X_train), , drop = FALSE]
      # Robust kmeans with multiple starts
      km_fit <- tryCatch(
        kmeans(X_train, centers = N_REGIMES, iter.max = 50L, nstart = 10L,
                algorithm = "Hartigan-Wong"),
        error = function(e) NULL
      )
      if (!is.null(km_fit)) {
        last_centroids <- km_fit$centers
        last_fit_idx <- t
        centroids_history[[length(centroids_history) + 1]] <- list(
          t = t, date = as.character(dates[t]), centroids = last_centroids,
          tot_withinss = km_fit$tot.withinss, size = km_fit$size
        )
      }
    }
  }

  # Assign label using nearest centroid
  if (!is.null(last_centroids)) {
    x_t <- X_z[t, , drop = FALSE]
    if (all(!is.na(x_t))) {
      dists <- apply(last_centroids, 1, function(c) sqrt(sum((x_t - c)^2)))
      labels[t] <- which.min(dists)
    }
  }
}

p4_clean[, regime_state := labels]
cat("  Labeled rows:", sum(!is.na(labels)), " / ", n_obs, "\n")
cat("  First label Date:", as.character(dates[which(!is.na(labels))[1]]), "\n")

# ---- 4. Per-state freq + transition matrix ----
labels_clean <- labels[!is.na(labels)]
state_freq <- table(labels_clean) / length(labels_clean)
cat("[4] Per-state empirical frequency:\n")
print(round(state_freq, 4))

# Transition matrix
trans_mat <- matrix(0, nrow = N_REGIMES, ncol = N_REGIMES,
                     dimnames = list(paste0("S", 1:N_REGIMES), paste0("S", 1:N_REGIMES)))
for (i in seq_len(length(labels_clean) - 1L)) {
  from <- labels_clean[i]
  to <- labels_clean[i + 1L]
  trans_mat[from, to] <- trans_mat[from, to] + 1
}
trans_mat_row_norm <- trans_mat / pmax(rowSums(trans_mat), 1)
cat("Transition matrix (row-normalized):\n")
print(round(trans_mat_row_norm, 3))

# ---- 5. Monthly snapshot (last labeled day per month) ----
p4_clean[, ym := format(Date, "%Y-%m")]
monthly <- p4_clean[!is.na(regime_state), .SD[Date == max(Date)], by = ym]
monthly <- monthly[, .(ym, Date, regime_state, mu_22, sigma_22, lam_22,
                        var_05_22, p_minus_5pct_22,
                        mu_44, sigma_44, lam_44, var_05_44, p_minus_5pct_44,
                        mu_66, sigma_66, lam_66, var_05_66, p_minus_5pct_66)]
setorder(monthly, ym)
cat("  Monthly snapshot rows:", nrow(monthly), "\n")

# ---- 6. Persist outputs ----
cat("[6] Saving outputs ...\n")
daily_out <- p4_clean[, .(Date, regime_state, mu_22, sigma_22, lam_22, var_05_22,
                           p_minus_5pct_22, mu_44, sigma_44, lam_44, var_05_44,
                           p_minus_5pct_44, mu_66, sigma_66, lam_66, var_05_66,
                           p_minus_5pct_66)]
write_parquet(daily_out, file.path(OUT_DIR, "regime_labels_daily.parquet"))
write_parquet(monthly, file.path(OUT_DIR, "regime_labels_monthly.parquet"))
write_parquet(daily_out, file.path(SHARED_OUT, "regime_labels_daily.parquet"))
write_parquet(monthly, file.path(SHARED_OUT, "regime_labels_monthly.parquet"))

# Diagnostic
diag <- list(
  method = "K-means N_REGIMES=9, walk-forward expanding window, refit every 21d",
  n_regimes = N_REGIMES,
  warmup_days = WARMUP_DAYS,
  refit_every = REFIT_EVERY,
  random_seed = RANDOM_SEED,
  n_daily_labeled = sum(!is.na(labels)),
  n_monthly_labeled = nrow(monthly),
  date_first_labeled = as.character(dates[which(!is.na(labels))[1]]),
  date_last_labeled = as.character(dates[max(which(!is.na(labels)))]),
  state_frequency = as.list(round(state_freq, 4)),
  transition_matrix_row_normalized = trans_mat_row_norm,
  state_persistence_diag = diag(trans_mat_row_norm),
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(diag, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "regime_classifier_diag.json"))

cat("[Regime Classifier] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
