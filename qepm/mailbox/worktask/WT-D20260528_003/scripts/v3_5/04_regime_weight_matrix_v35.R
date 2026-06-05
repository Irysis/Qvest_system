#==============================================================================
# Step 4 — Regime → 8-Family Weight Matrix Derivation v3.5
#
# Algorithm:
#   1. Join family L-S returns (Step 3) with regime_state monthly (Step 1, t-1 lag).
#   2. Per state s, per family f: walk-forward expanding mean return + SE (PIT-safe).
#   3. Black-Litterman style shrinkage: per family, scale by 1/(variance + ridge).
#   4. Normalize per state: weights sum to 1, non-negative (clip + renormalize).
#
# PIT-C9 compliant: regime_state(t-1) decides weight to apply at sig_date t.
#                   But weight matrix itself uses returns BEFORE sig_date t only.
#
# Output:
#   - outputs/v3_5/regime_factor_weight_matrix_v35_walkforward.parquet
#     columns: sig_date, regime_state, family, weight
#   - outputs/v3_5/regime_factor_weight_matrix_v35.meta.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_5")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_5")
FAMILY_RET_PATH <- file.path(OUT_DIR, "k200_family_lsret_v35.parquet")
REGIME_MONTHLY_PATH <- file.path(OUT_DIR, "regime_labels_monthly_v35.parquet")

SIGNAL_CUTOFF <- as.Date("2023-12-22")
N_REGIMES <- 9L
RIDGE_LAMBDA <- 0.0001  # BL-style shrinkage to mean

cat("[Weight Matrix v3.5] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load family returns + regime_state monthly ----
fr <- as.data.table(read_parquet(FAMILY_RET_PATH))
fr[, Date := as.Date(Date)]
setorder(fr, Date, family)
cat("[1] family_ret rows:", nrow(fr), " | sig_dates:", length(unique(fr$Date)), "\n")

reg <- as.data.table(read_parquet(REGIME_MONTHLY_PATH))
reg[, Date := as.Date(Date)]
cat("    regime monthly rows:", nrow(reg), " | range:", as.character(min(reg$Date)), "~", as.character(max(reg$Date)), "\n")

# PIT-C9 enforcement: at sig_date t, use regime_state from PREVIOUS sig_date (t-1)
# (regime feature itself already t-1 lag in Step 1; here we also lag regime_state by 1 sig_date
# to ensure the weight matrix doesn't peek at same-month regime label)
setorder(reg, Date)
reg[, regime_state_lag1 := shift(regime_state, n = 1L, type = "lag")]

# ---- 2. Join family_ret + regime_state_lag1 by sig_date ----
# At sig_date t: family_ret realized between t and t+1M (forward).
# We want to KNOW (state(t-1), family return(t→t+1M)) for weight derivation.
# Then at decision sig_date t': we look at past observations with state==state(t'-1).

# First, attach state(t-1) to each sig_date in family_ret.
date_state_map <- reg[!is.na(regime_state_lag1), .(Date, state_used = regime_state_lag1)]
fr <- merge(fr, date_state_map, by = "Date", all.x = FALSE)
cat("[2] joined rows:", nrow(fr), " | unique state:", paste(sort(unique(fr$state_used)), collapse=","), "\n")

# ---- 3. Walk-forward state-conditional weight matrix ----
sig_dates_all <- sort(unique(fr$Date))
weight_list <- list()

cat("[3] Walk-forward weight derivation (RIDGE_LAMBDA=", RIDGE_LAMBDA, ") ...\n")
for (i in seq_along(sig_dates_all)) {
  decision_d <- sig_dates_all[i]
  # Train data: ALL observations with sig_date < decision_d (PIT strict)
  train_dt <- fr[Date < decision_d]
  if (nrow(train_dt) < 24L) next  # minimum 24 obs ≈ 2y

  # state at decision: regime_state_lag1 from reg matching decision_d
  decision_state_row <- reg[Date == decision_d, regime_state_lag1]
  if (length(decision_state_row) == 0L || is.na(decision_state_row[1])) next
  decision_state <- decision_state_row[1]

  # Per family: mean + variance in train_dt restricted to state==decision_state (with fallback to all states)
  for (fam in unique(train_dt$family)) {
    state_obs <- train_dt[family == fam & state_used == decision_state]
    all_obs <- train_dt[family == fam]
    if (nrow(state_obs) >= 5L) {
      mu <- mean(state_obs$ls_simple_ret, na.rm = TRUE)
      sig2 <- var(state_obs$ls_simple_ret, na.rm = TRUE)
      basis <- "state_specific"
      n_state <- nrow(state_obs)
    } else {
      # Fallback to overall mean
      mu <- mean(all_obs$ls_simple_ret, na.rm = TRUE)
      sig2 <- var(all_obs$ls_simple_ret, na.rm = TRUE)
      basis <- "all_state_fallback"
      n_state <- nrow(all_obs)
    }
    if (is.na(sig2) || sig2 < 0) sig2 <- 0
    weight_list[[length(weight_list) + 1L]] <- data.table(
      sig_date = decision_d, regime_state = decision_state,
      family = fam, mu = mu, sig2 = sig2,
      n_obs_in_state = n_state, basis = basis
    )
  }
}

w <- rbindlist(weight_list, use.names = TRUE)
cat("  weight rows pre-norm:", nrow(w), " | unique sig_dates:", length(unique(w$sig_date)), "\n")

# ---- 4. BL-style weight: weight ∝ mu/(sig2 + ridge), clip negatives, normalize sum=1 ----
cat("[4] BL-style shrinkage + normalize ...\n")
w[, raw_weight := mu / (sig2 + RIDGE_LAMBDA)]
# Clip negatives (long-only constraint within composite signal — equivalent to setting weight=0 for short family)
w[raw_weight < 0, raw_weight := 0]
# Per sig_date normalize sum to 1; if all zero, set equal-weight fallback
w[, sum_w := sum(raw_weight, na.rm = TRUE), by = sig_date]
w[sum_w > 1e-9, weight := raw_weight / sum_w]
w[sum_w <= 1e-9, weight := 1 / length(unique(family))]
w[, c("raw_weight","sum_w") := NULL]

cat("  per-sig_date weight rows:", nrow(w), "\n")

# Per-family aggregate weight (overall)
fam_avg <- w[, .(avg_weight = mean(weight, na.rm = TRUE)), by = family]
setorder(fam_avg, -avg_weight)
cat("\n--- Average family weight across all sig_dates ---\n")
print(fam_avg)

# Per-state per-family average weight
state_fam_avg <- w[, .(avg_weight = mean(weight, na.rm = TRUE)), by = .(regime_state, family)]
setorder(state_fam_avg, regime_state, -avg_weight)
cat("\n--- State × family weight (first 5 states) ---\n")
print(state_fam_avg[regime_state <= 5L])

# ---- 5. Output ----
write_parquet(w, file.path(OUT_DIR, "regime_factor_weight_matrix_v35_walkforward.parquet"))
write_parquet(w, file.path(STAGE_DIR, "regime_factor_weight_matrix_v35_walkforward.parquet"))

meta <- list(
  spec = "v3.5 regime-conditional 8-family weight matrix (BL-style shrinkage, walk-forward PIT)",
  pit_correction = "regime_state_lag1 used at decision_d; train data sig_date < decision_d (strict)",
  ridge_lambda = RIDGE_LAMBDA,
  long_only_clip = "raw_weight=mu/(sig2+ridge), clip<0 to 0, normalize sum=1",
  n_regimes = N_REGIMES,
  families = sort(unique(w$family)),
  n_decision_dates = length(unique(w$sig_date)),
  n_weight_rows = nrow(w),
  family_avg_weight = fam_avg,
  state_fam_avg = state_fam_avg,
  basis_distribution = w[, .N, by = basis],
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(meta, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "regime_factor_weight_matrix_v35.meta.json"))

cat("\n[Weight Matrix v3.5] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
