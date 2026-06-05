#==============================================================================
# Step 1 — Regime Engine v3.6 HMM 4-state (Hamilton 1989)
#
# v3.5 → v3.6 fix:
#   - 9-state K-means → 4-state HMM (Markov-Switching, Hamilton 1989)
#   - depmixS4 Gaussian HMM: 17 features → state probability
#   - Walk-forward expanding fit (PIT, monthly refit)
#   - Fallback target: < 30% (v3.5 K-means 54.2% fallback resolved)
#   - Persistence target: ≥ 0.85 (Markov chain natural property)
#   - Per-state n ≥ 30 (v3.5 9-state cell sparsity resolved)
#   - 17 features retain (P4 15 + MA07_Z + RE_MRS, all t-1 lagged PIT-C9 strict)
#
# Methodology refs:
#   - Hamilton 1989 "A new approach to the economic analysis of nonstationary time
#     series and the business cycle" Econometrica 57(2): 357-384
#   - Visser-Speekenbrink 2010 "depmixS4: An R Package for Hidden Markov Models"
#     Journal of Statistical Software 36(7)
#   - Ang-Bekaert 2002 "International Asset Allocation with Regime Shifts" RFS
#
# Output:
#   - outputs/v3_6/regime_labels_daily_v36.parquet
#   - outputs/v3_6/regime_labels_monthly_v36.parquet
#   - outputs/v3_6/regime_classifier_diag_v36.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(depmixS4)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6")
SHARED_OUT <- file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_6")
P4_PATH <- file.path(SHARED_OUT, "p4_multi_horizon.parquet")
FACTOR_DB_DAILY <- file.path(BASE, ".cache/factor_db_daily")
FACTOR_DB_MONTHLY <- file.path(BASE, ".cache/factor_db")

SIGNAL_CUTOFF <- as.Date("2023-12-22")
N_REGIMES <- 4L      # v3.6: 9 → 4 (Hamilton 1989 standard BULL/NORMAL/CAUTION/CRISIS)
WARMUP_DAYS <- 504L  # ~2 years for HMM identification (more than K-means 252d)
REFIT_EVERY <- 63L   # quarterly refit (HMM is stable than K-means; refit less often)
RANDOM_SEED <- 42L
PCA_DIMS <- 6L       # depmixS4 17-d Gaussian unstable. Reduce to 6 PCs (~85% variance)

cat("[Regime Engine v3.6 HMM] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load P4 multi-horizon ----
cat("[1] Loading p4_multi_horizon.parquet ...\n")
p4 <- as.data.table(read_parquet(P4_PATH))
p4[, Date := as.Date(Date)]
setorder(p4, Date)
cat("  rows:", nrow(p4), " | Date range:", as.character(min(p4$Date)), "~", as.character(max(p4$Date)), "\n")

p4_features <- c()
for (h in c(22, 44, 66)) {
  p4_features <- c(p4_features,
                    paste0("mu_", h), paste0("sigma_", h), paste0("lam_", h),
                    paste0("var_05_", h), paste0("p_minus_5pct_", h))
}
stopifnot(length(p4_features) == 15)

# ---- 2. Load MA07 from monthly factor_db (macro composite Raw_Value) ----
cat("[2] Loading MA07 (macro Raw_Value) ...\n")
ym_list <- list.files(FACTOR_DB_MONTHLY, pattern = "^factor_db_\\d{6}\\.parquet$")
ym_list <- sort(ym_list)
ma07_dt <- list()
for (f in ym_list) {
  fpath <- file.path(FACTOR_DB_MONTHLY, f)
  tmp <- tryCatch(
    as.data.table(read_parquet(fpath, col_select = c("Date","Ticker","Factor_Name","Raw_Value","Coverage"))),
    error = function(e) NULL
  )
  if (is.null(tmp)) next
  tmp <- tmp[Factor_Name == "MA07_BusinessCycle_Composite" & Coverage == TRUE,
             .(Date = as.Date(Date), MA07_Raw = Raw_Value)]
  if (nrow(tmp) > 0) {
    tmp <- unique(tmp, by = "Date")
    ma07_dt[[length(ma07_dt) + 1L]] <- tmp
  }
}
MA07 <- rbindlist(ma07_dt, use.names = TRUE, fill = TRUE)
MA07 <- unique(MA07, by = "Date")
setorder(MA07, Date)
MA07[, MA07_Z := {
  x <- MA07_Raw
  n <- length(x)
  z <- rep(NA_real_, n)
  for (t in seq_len(n)) {
    if (t < 12L) next
    mu <- mean(x[seq_len(t-1L)], na.rm = TRUE)
    sg <- sd(x[seq_len(t-1L)], na.rm = TRUE)
    if (!is.na(sg) && sg > 1e-12) z[t] <- (x[t] - mu) / sg
  }
  z
}]
cat("  MA07 rows:", nrow(MA07), " | range:", as.character(min(MA07$Date)), "~", as.character(max(MA07$Date)), "\n")

# ---- 3. Load RE_MRS from daily factor_db ----
cat("[3] Loading RE_MRS ...\n")
ym_daily <- list.files(FACTOR_DB_DAILY, pattern = "^fdb_daily_\\d{6}\\.parquet$")
ym_daily <- sort(ym_daily)
re_mrs_dt <- list()
for (f in ym_daily) {
  fpath <- file.path(FACTOR_DB_DAILY, f)
  tmp <- tryCatch(
    as.data.table(read_parquet(fpath, col_select = c("Date","RE_MRS"))),
    error = function(e) NULL
  )
  if (is.null(tmp)) next
  tmp <- tmp[!is.na(RE_MRS), .(Date = as.Date(Date), RE_MRS)]
  tmp <- unique(tmp, by = "Date")
  if (nrow(tmp) > 0) re_mrs_dt[[length(re_mrs_dt) + 1L]] <- tmp
}
RE_MRS <- rbindlist(re_mrs_dt, use.names = TRUE, fill = TRUE)
RE_MRS <- unique(RE_MRS, by = "Date")
setorder(RE_MRS, Date)
cat("  RE_MRS rows:", nrow(RE_MRS), " | range:", as.character(min(RE_MRS$Date)), "~", as.character(max(RE_MRS$Date)), "\n")

# ---- 4. Merge P4 + MA07 (carry-forward) + RE_MRS ----
cat("[4] Merging 17 regime features ...\n")
all_dates <- p4$Date
ma07_daily <- data.table(Date = all_dates)
ma07_daily <- merge(ma07_daily, MA07, by = "Date", all.x = TRUE)
ma07_daily[, MA07_Z := nafill(MA07_Z, type = "locf")]

regime_input <- merge(p4[, c("Date", p4_features), with = FALSE],
                       ma07_daily, by = "Date", all.x = TRUE)
regime_input <- merge(regime_input, RE_MRS, by = "Date", all.x = TRUE)

all_features <- c(p4_features, "MA07_Z", "RE_MRS")
stopifnot(length(all_features) == 17L)

regime_clean <- regime_input[complete.cases(regime_input[, ..all_features])]
cat("  After NA drop:", nrow(regime_clean), " | first Date:", as.character(min(regime_clean$Date)), "\n")

# ---- 5. PIT-C9 STRICT t-1 lag ----
setorder(regime_clean, Date)
for (col in all_features) {
  regime_clean[, (paste0(col, "_lag1")) := shift(get(col), n = 1L, type = "lag")]
}
feature_cols_lag <- paste0(all_features, "_lag1")
regime_clean <- regime_clean[complete.cases(regime_clean[, ..feature_cols_lag])]
cat("  After t-1 lag NA drop:", nrow(regime_clean), " | first Date:", as.character(min(regime_clean$Date)), "\n")

# ---- 6. Walk-forward expanding HMM ----
# HMM via depmixS4: Gaussian observation model with PCA-reduced inputs.
# Rationale: 17-d Gaussian HMM has 4 × (17 + 17×18/2) = 680 params per state × 4 states = unstable.
#            PCA reduce to 6 PCs → 4 × (6 + 6×7/2) = 108 params → identifiable.
#            Walk-forward expanding fit (PIT). Viterbi decoding for state assignment.
cat("[6] Walk-forward HMM (N_REGIMES=", N_REGIMES, ", WARMUP=", WARMUP_DAYS,
    ", REFIT_EVERY=", REFIT_EVERY, ", PCA_DIMS=", PCA_DIMS, ") ...\n")

X_raw <- as.matrix(regime_clean[, ..feature_cols_lag])
dates <- regime_clean$Date
n_obs <- nrow(X_raw)
labels <- rep(NA_integer_, n_obs)
fit_history <- list()

# Expanding-window z-score per feature (PIT)
X_z <- matrix(NA_real_, nrow = n_obs, ncol = length(feature_cols_lag))
colnames(X_z) <- feature_cols_lag
for (j in seq_len(ncol(X_raw))) {
  x <- X_raw[, j]
  cum_sum <- cumsum(x)
  cum_sq <- cumsum(x^2)
  for (t in seq_len(n_obs)) {
    if (t < 60L) next
    mu_prev <- cum_sum[t - 1] / (t - 1)
    var_prev <- (cum_sq[t - 1] / (t - 1)) - mu_prev^2
    sd_prev <- sqrt(max(var_prev, 1e-10))
    X_z[t, j] <- (x[t] - mu_prev) / sd_prev
  }
}

set.seed(RANDOM_SEED)
last_fit_idx <- 0L
last_pca_rotation <- NULL
last_pca_center <- NULL
last_pca_scale <- NULL
last_model <- NULL
last_centroids <- NULL  # state centroids in PC space (Viterbi → assign by min dist)

assign_state <- function(x_t_z, pca_rot, pca_center, pca_scale, centroids) {
  if (any(is.na(x_t_z))) return(NA_integer_)
  pc <- ((x_t_z - pca_center) / pca_scale) %*% pca_rot
  dists <- apply(centroids, 1, function(c) sqrt(sum((pc - c)^2)))
  which.min(dists)
}

for (t in seq_len(n_obs)) {
  if (t < WARMUP_DAYS) next
  if (any(is.na(X_z[t, ]))) next

  if ((t - last_fit_idx) >= REFIT_EVERY || is.null(last_centroids)) {
    # Training data: past t-1 observations (expanding)
    train_idx <- which(!is.na(X_z[, 1]))
    train_idx <- train_idx[train_idx < t]
    if (length(train_idx) >= 200L) {
      X_train <- X_z[train_idx, , drop = FALSE]
      X_train <- X_train[complete.cases(X_train), , drop = FALSE]

      # PCA on train (PIT — no test leakage)
      pca_fit <- tryCatch(prcomp(X_train, center = TRUE, scale. = TRUE),
                           error = function(e) NULL)
      if (!is.null(pca_fit)) {
        pca_rot <- pca_fit$rotation[, 1:PCA_DIMS, drop = FALSE]
        pca_center <- pca_fit$center
        pca_scale <- pca_fit$scale
        pca_scale[pca_scale < 1e-10] <- 1
        train_pc <- pca_fit$x[, 1:PCA_DIMS, drop = FALSE]

        # Fit HMM via depmixS4 — Gaussian on each PC
        # response: list of Gaussian families per PC
        train_dt <- as.data.table(train_pc)
        setnames(train_dt, paste0("PC", 1:PCA_DIMS))
        rsp <- lapply(1:PCA_DIMS, function(k) {
          as.formula(paste0("PC", k, " ~ 1"))
        })
        fam <- replicate(PCA_DIMS, gaussian(), simplify = FALSE)

        hmm_mod <- tryCatch({
          mod <- depmix(rsp, data = train_dt, nstates = N_REGIMES, family = fam)
          fit_mod <- fit(mod, verbose = FALSE,
                          emcontrol = em.control(maxit = 100, tol = 1e-4))
          fit_mod
        }, error = function(e) NULL)

        if (!is.null(hmm_mod)) {
          # Viterbi state assignment on train data
          train_states <- posterior(hmm_mod, type = "viterbi")$state

          # Compute state centroids in PC space (for OOS state assignment)
          centroids <- matrix(NA_real_, nrow = N_REGIMES, ncol = PCA_DIMS)
          for (s in seq_len(N_REGIMES)) {
            idx_s <- which(train_states == s)
            if (length(idx_s) > 0) {
              centroids[s, ] <- colMeans(train_pc[idx_s, , drop = FALSE])
            } else {
              centroids[s, ] <- rep(0, PCA_DIMS)
            }
          }

          # Re-order states for stability: sort by 1st PC mean (BULL=high, CRISIS=low)
          ord <- order(centroids[, 1], decreasing = TRUE)
          centroids <- centroids[ord, , drop = FALSE]

          last_pca_rotation <- pca_rot
          last_pca_center <- pca_center
          last_pca_scale <- pca_scale
          last_centroids <- centroids
          last_fit_idx <- t

          # Fit diagnostic
          fit_history[[length(fit_history) + 1L]] <- list(
            t = t, date = as.character(dates[t]),
            n_train = nrow(X_train),
            train_state_freq = as.list(table(train_states)),
            logLik = as.numeric(logLik(hmm_mod)),
            BIC = BIC(hmm_mod)
          )
        }
      }
    }
  }

  # Assign state for current t using last model
  if (!is.null(last_centroids)) {
    labels[t] <- assign_state(X_z[t, ], last_pca_rotation, last_pca_center,
                               last_pca_scale, last_centroids)
  }
}

regime_clean[, regime_state := labels]
cat("  Labeled rows:", sum(!is.na(labels)), " / ", n_obs, "\n")
cat("  First labeled Date:", as.character(dates[which(!is.na(labels))[1]]), "\n")

# ---- 7. Per-state freq + transition matrix + persistence ----
labels_clean <- labels[!is.na(labels)]
state_freq <- table(labels_clean) / length(labels_clean)
cat("[7] State frequency:\n")
print(round(state_freq, 4))

trans_mat <- matrix(0, nrow = N_REGIMES, ncol = N_REGIMES,
                     dimnames = list(paste0("S", 1:N_REGIMES), paste0("S", 1:N_REGIMES)))
for (i in seq_len(length(labels_clean) - 1L)) {
  from <- labels_clean[i]
  to <- labels_clean[i + 1L]
  trans_mat[from, to] <- trans_mat[from, to] + 1
}
trans_mat_row_norm <- trans_mat / pmax(rowSums(trans_mat), 1)
persistence <- diag(trans_mat_row_norm)
cat("  Per-state persistence:\n")
print(round(persistence, 3))

# ---- 8. Monthly snapshot (last day per month) ----
regime_clean[, ym := format(Date, "%Y-%m")]
monthly <- regime_clean[!is.na(regime_state), .SD[Date == max(Date)], by = ym]
keep_cols <- c("ym", "Date", "regime_state", feature_cols_lag)
monthly <- monthly[, ..keep_cols]
setorder(monthly, ym)
cat("  Monthly snapshot rows:", nrow(monthly), "\n")
cat("  Per-state monthly counts:\n")
print(table(monthly$regime_state, useNA = "ifany"))

# ---- 9. Output + diagnostic ----
cat("[9] Saving v3.6 outputs ...\n")
daily_out <- regime_clean[, c("Date", "regime_state", feature_cols_lag), with = FALSE]
write_parquet(daily_out, file.path(OUT_DIR, "regime_labels_daily_v36.parquet"))
write_parquet(monthly, file.path(OUT_DIR, "regime_labels_monthly_v36.parquet"))
write_parquet(daily_out, file.path(STAGE_DIR, "regime_labels_daily_v36.parquet"))
write_parquet(monthly, file.path(STAGE_DIR, "regime_labels_monthly_v36.parquet"))

diag_v36 <- list(
  method = "HMM 4-state via depmixS4 (Hamilton 1989), walk-forward expanding fit, refit every 63d",
  pit_correction = "All 17 features t-1 lag STRICT (PIT-C9); PCA fit on past data only (no test leakage)",
  feature_blocks = list(
    p4_multi_horizon_15 = p4_features,
    macro_business_cycle_1 = "MA07_BusinessCycle_Composite",
    fred_market_regime_1 = "RE_MRS"
  ),
  n_features = 17L,
  pca_dims = PCA_DIMS,
  n_regimes = N_REGIMES,
  warmup_days = WARMUP_DAYS,
  refit_every = REFIT_EVERY,
  random_seed = RANDOM_SEED,
  n_daily_labeled = sum(!is.na(labels)),
  n_monthly_labeled = nrow(monthly),
  per_state_monthly_n = as.list(table(monthly$regime_state)),
  state_frequency = as.list(round(state_freq, 4)),
  state_persistence = setNames(round(persistence, 4), paste0("S", 1:N_REGIMES)),
  transition_matrix_row_norm = trans_mat_row_norm,
  n_hmm_fits = length(fit_history),
  signal_cutoff = as.character(SIGNAL_CUTOFF),
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(diag_v36, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "regime_classifier_diag_v36.json"))

cat("[Regime Engine v3.6 HMM] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
