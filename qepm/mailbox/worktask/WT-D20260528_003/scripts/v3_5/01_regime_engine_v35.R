#==============================================================================
# Step 1 — Regime Engine v3.5 (17 features + PIT-C9 t-1 lag strict)
#
# v1 lesson 적용:
#   - Regime feature t-1 lag 의무 (PIT-C9 strict). same-date 사용 = 신호 소실 mechanism.
#   - 17 features = P4 15 (mu/sigma/lam/var_05/p_minus_5pct × 3 horizon)
#                  + MA07_BusinessCycle_Composite (1)
#                  + RE_MRS (1)
#   - Walk-forward expanding K-means 9-cluster (monthly refit)
#
# Output:
#   - outputs/v3_5/regime_labels_daily_v35.parquet
#   - outputs/v3_5/regime_labels_monthly_v35.parquet
#   - outputs/v3_5/regime_classifier_diag_v35.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_5")
SHARED_OUT <- file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_5")
P4_PATH <- file.path(SHARED_OUT, "p4_multi_horizon.parquet")
FACTOR_DB_DAILY <- file.path(BASE, ".cache/factor_db_daily")
FACTOR_DB_MONTHLY <- file.path(BASE, ".cache/factor_db")

SIGNAL_CUTOFF <- as.Date("2023-12-22")
N_REGIMES <- 9L
WARMUP_DAYS <- 252L
REFIT_EVERY <- 21L
RANDOM_SEED <- 42L

cat("[Regime Engine v3.5] === START ===\n")
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

# ---- 2. Load MA07 from monthly factor_db (macro composite — Raw_Value field) ----
# Note: MA07 is macro composite. Z_Score column is NA (cross-sectional standardization doesn't apply to macro).
# We use Raw_Value (identical across all Tickers per Date) and compute expanding-window z-score below.
cat("[2] Loading MA07_BusinessCycle_Composite (macro Raw_Value) from monthly factor_db ...\n")

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
    # MA07는 macro composite — 모든 Ticker 동일 값. Per Date unique.
    tmp <- unique(tmp, by = "Date")
    ma07_dt[[length(ma07_dt) + 1L]] <- tmp
  }
}
MA07 <- rbindlist(ma07_dt, use.names = TRUE, fill = TRUE)
MA07 <- unique(MA07, by = "Date")
setorder(MA07, Date)

# Expanding-window z-score on macro Raw_Value (PIT-safe)
MA07[, MA07_Z := {
  x <- MA07_Raw
  n <- length(x)
  z <- rep(NA_real_, n)
  for (t in seq_len(n)) {
    if (t < 12L) next  # min 12 months
    mu <- mean(x[seq_len(t-1L)], na.rm = TRUE)
    sg <- sd(x[seq_len(t-1L)], na.rm = TRUE)
    if (!is.na(sg) && sg > 1e-12) z[t] <- (x[t] - mu) / sg
  }
  z
}]

cat("  MA07 rows:", nrow(MA07), " | range:", as.character(min(MA07$Date)), "~", as.character(max(MA07$Date)), "\n")
cat("  MA07 expanding-z NA rows (early period):", sum(is.na(MA07$MA07_Z)), "\n")

# ---- 3. Load RE_MRS from daily factor_db (daily macro) ----
cat("[3] Loading RE_MRS from daily factor_db ...\n")
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

# ---- 4. Merge P4 + MA07 (carry-forward monthly) + RE_MRS (daily) ----
cat("[4] Merging 17 regime features (P4 15 + MA07 1 + RE_MRS 1) ...\n")

# MA07는 monthly → daily carry-forward
all_dates <- p4$Date
ma07_daily <- data.table(Date = all_dates)
ma07_daily <- merge(ma07_daily, MA07, by = "Date", all.x = TRUE)
ma07_daily[, MA07_Z := nafill(MA07_Z, type = "locf")]

# P4 features + MA07_Z + RE_MRS join
regime_input <- merge(p4[, c("Date", p4_features), with = FALSE],
                       ma07_daily, by = "Date", all.x = TRUE)
regime_input <- merge(regime_input, RE_MRS, by = "Date", all.x = TRUE)

all_features <- c(p4_features, "MA07_Z", "RE_MRS")
stopifnot(length(all_features) == 17L)

cat("  All features (n=", length(all_features), "):", paste(all_features, collapse = ", "), "\n")

# Drop rows with any NA across 17 features
regime_clean <- regime_input[complete.cases(regime_input[, ..all_features])]
cat("  After NA drop:", nrow(regime_clean), " | first available Date:", as.character(min(regime_clean$Date)), "\n")

# ---- 5. PIT-C9 STRICT: t-1 lag of all 17 features ----
# Critical: at decision sig_date t, we use feature[t-1], NOT feature[t].
# v1 lesson: same-date regime IC 0.0121 → t-1 lag IC -0.0007. Mechanism artifact detected.
# v3.5: regime feature t-1 lag from start (sig_date t에서 t-1 trading day regime label 사용)
setorder(regime_clean, Date)
for (col in all_features) {
  regime_clean[, (paste0(col, "_lag1")) := shift(get(col), n = 1L, type = "lag")]
}
feature_cols_lag <- paste0(all_features, "_lag1")
regime_clean <- regime_clean[complete.cases(regime_clean[, ..feature_cols_lag])]
cat("  After t-1 lag NA drop:", nrow(regime_clean), " | first available Date:", as.character(min(regime_clean$Date)), "\n")

# ---- 6. Walk-forward expanding-window K-means with monthly refit ----
cat("[6] Walk-forward K-means (N_REGIMES=", N_REGIMES, ", WARMUP=", WARMUP_DAYS, ", REFIT_EVERY=", REFIT_EVERY, ") ...\n")

X_raw <- as.matrix(regime_clean[, ..feature_cols_lag])
dates <- regime_clean$Date
n_obs <- nrow(X_raw)
labels <- rep(NA_integer_, n_obs)
centroids_history <- list()

# Expanding-window z-score per feature (PIT, using only past data)
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

# Walk-forward K-means
set.seed(RANDOM_SEED)
last_fit_idx <- 0L
last_centroids <- NULL

for (t in seq_len(n_obs)) {
  if (t < WARMUP_DAYS) next
  if (any(is.na(X_z[t, ]))) next

  if ((t - last_fit_idx) >= REFIT_EVERY || is.null(last_centroids)) {
    train_idx <- which(!is.na(X_z[, 1]))
    train_idx <- train_idx[train_idx < t]
    if (length(train_idx) >= N_REGIMES * 10L) {
      X_train <- X_z[train_idx, , drop = FALSE]
      X_train <- X_train[complete.cases(X_train), , drop = FALSE]
      km_fit <- tryCatch(
        kmeans(X_train, centers = N_REGIMES, iter.max = 50L, nstart = 10L,
                algorithm = "Hartigan-Wong"),
        error = function(e) NULL
      )
      if (!is.null(km_fit)) {
        last_centroids <- km_fit$centers
        last_fit_idx <- t
        centroids_history[[length(centroids_history) + 1L]] <- list(
          t = t, date = as.character(dates[t]),
          tot_withinss = km_fit$tot.withinss, size = km_fit$size
        )
      }
    }
  }

  if (!is.null(last_centroids)) {
    x_t <- X_z[t, , drop = FALSE]
    if (all(!is.na(x_t))) {
      dists <- apply(last_centroids, 1, function(c) sqrt(sum((x_t - c)^2)))
      labels[t] <- which.min(dists)
    }
  }
}

regime_clean[, regime_state := labels]
cat("  Labeled rows:", sum(!is.na(labels)), " / ", n_obs, "\n")
cat("  First labeled Date:", as.character(dates[which(!is.na(labels))[1]]), "\n")

# ---- 7. Per-state freq + transition matrix ----
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
cat("  Per-state persistence (diag of transition matrix):\n")
print(round(persistence, 3))

# ---- 8. Monthly snapshot (last labeled day per month) ----
regime_clean[, ym := format(Date, "%Y-%m")]
monthly <- regime_clean[!is.na(regime_state), .SD[Date == max(Date)], by = ym]
keep_cols <- c("ym", "Date", "regime_state", feature_cols_lag)
monthly <- monthly[, ..keep_cols]
setorder(monthly, ym)
cat("  Monthly snapshot rows:", nrow(monthly), "\n")

# ---- 9. Output ----
cat("[9] Saving v3.5 outputs ...\n")
daily_out <- regime_clean[, c("Date", "regime_state", feature_cols_lag), with = FALSE]
write_parquet(daily_out, file.path(OUT_DIR, "regime_labels_daily_v35.parquet"))
write_parquet(monthly, file.path(OUT_DIR, "regime_labels_monthly_v35.parquet"))
write_parquet(daily_out, file.path(STAGE_DIR, "regime_labels_daily_v35.parquet"))
write_parquet(monthly, file.path(STAGE_DIR, "regime_labels_monthly_v35.parquet"))

diag_v35 <- list(
  method = "K-means N_REGIMES=9, walk-forward expanding window, refit every 21d",
  pit_correction_v35 = "All 17 regime features t-1 lag STRICT (PIT-C9)",
  feature_blocks = list(
    p4_multi_horizon_15 = p4_features,
    macro_business_cycle_1 = "MA07_BusinessCycle_Composite",
    fred_market_regime_1 = "RE_MRS"
  ),
  n_features = 17L,
  n_regimes = N_REGIMES,
  warmup_days = WARMUP_DAYS,
  refit_every = REFIT_EVERY,
  random_seed = RANDOM_SEED,
  n_daily_labeled = sum(!is.na(labels)),
  n_monthly_labeled = nrow(monthly),
  date_first_labeled = as.character(dates[which(!is.na(labels))[1]]),
  date_last_labeled = as.character(dates[max(which(!is.na(labels)))]),
  state_frequency = as.list(round(state_freq, 4)),
  state_persistence = setNames(round(persistence, 4), paste0("S", 1:N_REGIMES)),
  transition_matrix_row_norm = trans_mat_row_norm,
  signal_cutoff = as.character(SIGNAL_CUTOFF),
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(diag_v35, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "regime_classifier_diag_v35.json"))

cat("[Regime Engine v3.5] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
