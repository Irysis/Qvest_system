#==============================================================================
# Step 4 — Regime → 6-Family Weight Matrix (walk-forward PIT, hybrid w_f)
#
# Input:
#   - outputs/regime_labels_monthly.parquet  (month-end × regime_state)
#   - outputs/k200_factor_returns_v3.parquet (month-end × 6 family simple_ret)
#
# Method:
#   1. Merge by (ym ≈ Date_snap month). Phase 1 v3 month-end = end of month last
#      trading day, regime monthly = same.
#   2. Walk-forward: per sig_date t, compute factor weight w_f(t) using ONLY
#      training data t' < t (PIT-safe).
#   3. Per-state conditional mean factor return:
#         μ_{f, s} = mean(ret_f | regime=s, t' < t)
#         se_{f, s} = sd(ret_f | regime=s, t' < t) / sqrt(n_{s})
#   4. Shrinkage Black-Litterman style:
#         μ_BL_{f, s} = ρ * μ_{f, s} + (1-ρ) * μ_grand_{f}
#         where ρ = n_{s} / (n_{s} + κ), κ = 12 (1 year of monthly obs)
#      Behmaram 2024 + Acadian 2026 risk model 정합 (shrinkage to grand mean
#      mitigates state-conditioned overfitting).
#   5. Weight:
#         w_BL_{f, s} = max(0, μ_BL_{f, s}) (long-only smart beta)
#         normalize across families: w_f(s) = w_BL / sum_f w_BL_{f, s}
#         if sum = 0 → equal weight 1/6 (degenerate state).
#
# Output:
#   - outputs/regime_factor_weight_matrix_walkforward.parquet
#         columns: ym, sig_date, regime_state, plus w_value, w_quality, ...
#   - outputs/regime_factor_weights_avg.json (state x family long-term weight)
#
# PIT:
#   - C1: walk-forward expanding (no full sample)
#   - C14: regime label at t already PIT (Step 3 walk-forward)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs")
SHARED_OUT <- file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs")

FAMILIES_LIST <- c("value", "quality", "momentum", "low_vol", "size", "dividend")
N_REGIMES <- 9L
SHRINKAGE_KAPPA <- 12L  # months — equivalent to 1y of "prior" observations

cat("[Step 4 Weight Matrix] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load Phase 1 v3 + regime labels ----
cat("[1] Loading Phase 1 v3 + regime labels (monthly) ...\n")
fr <- as.data.table(read_parquet(file.path(SHARED_OUT, "k200_factor_returns_v3.parquet")))
fr[, sig_date := as.Date(sig_date)]
fr[, ym := format(sig_date, "%Y-%m")]

rl <- as.data.table(read_parquet(file.path(SHARED_OUT, "regime_labels_monthly.parquet")))
rl[, Date := as.Date(Date)]

# Merge by ym
mer <- merge(fr, rl[, .(ym, regime_date = Date, regime_state)], by = "ym", all = FALSE)
mer <- mer[!is.na(regime_state)]
setorder(mer, sig_date)
cat("  Merged month-end obs:", nrow(mer), " | ym range:",
    min(mer$ym), "~", max(mer$ym), "\n")

# Sanity: state distribution in merged
cat("  Merged regime_state distribution:\n")
print(round(table(mer$regime_state) / nrow(mer), 3))

# ---- 2. Walk-forward per-state conditional mean + BL shrinkage ----
cat("[2] Walk-forward per-state factor return analysis ...\n")
weights_rows <- list()
fam_simple_cols <- paste0(FAMILIES_LIST, "_simple")

# Grand mean across all training data (computed walk-forward as well)
for (i in seq_len(nrow(mer))) {
  t_sig <- mer$sig_date[i]
  s_t <- mer$regime_state[i]
  train <- mer[sig_date < t_sig]
  if (nrow(train) < 12L) {
    # too few obs — use equal weights
    w <- setNames(rep(1/6, 6), FAMILIES_LIST)
    weights_rows[[i]] <- c(
      list(ym = mer$ym[i], sig_date = t_sig, regime_state = s_t,
            n_train = nrow(train), n_train_in_state = 0L,
            method = "ew_warmup"),
      as.list(w)
    )
    next
  }
  # Grand mean per family (over all training data)
  grand_means <- sapply(fam_simple_cols, function(c) mean(train[[c]], na.rm = TRUE))

  # State-conditioned mean
  train_in_state <- train[regime_state == s_t]
  n_state <- nrow(train_in_state)

  if (n_state >= 3L) {
    state_means <- sapply(fam_simple_cols, function(c) mean(train_in_state[[c]], na.rm = TRUE))
    # BL shrinkage
    rho <- n_state / (n_state + SHRINKAGE_KAPPA)
    bl_means <- rho * state_means + (1 - rho) * grand_means
    method <- "bl_shrink"
  } else {
    bl_means <- grand_means
    rho <- 0
    method <- "grand_mean_fallback"
  }

  # Long-only: w_BL = max(0, μ_BL)
  w_pos <- pmax(0, bl_means)
  s_sum <- sum(w_pos)
  if (s_sum > 0) {
    w <- w_pos / s_sum
  } else {
    # all negative → equal weight (degenerate)
    w <- setNames(rep(1/6, 6), FAMILIES_LIST)
    method <- paste0(method, "_neg_all_ew")
  }
  names(w) <- FAMILIES_LIST

  weights_rows[[i]] <- c(
    list(ym = mer$ym[i], sig_date = t_sig, regime_state = s_t,
          n_train = nrow(train), n_train_in_state = n_state,
          shrinkage_rho = rho, method = method),
    as.list(w)
  )
}

W <- rbindlist(weights_rows, fill = TRUE)
setorder(W, sig_date)
cat("  Walk-forward weight rows:", nrow(W), "\n")
cat("  Summary weights (mean across all sig_dates):\n")
print(round(W[, lapply(.SD, mean), .SDcols = FAMILIES_LIST], 4))
cat("  Method distribution:\n")
print(table(W$method))

# ---- 3. Average weight per state (terminal walk-forward, post-warmup) ----
# Use only last 60 sig_dates worth of walk-forward weights for stable per-state avg
cat("[3] Long-run state x family weights (last 60 obs) ...\n")
W_late <- tail(W, 60L)
state_x_fam <- W_late[, lapply(.SD, mean), by = regime_state, .SDcols = FAMILIES_LIST]
setorder(state_x_fam, regime_state)
print(state_x_fam)

# ---- 4. Save outputs ----
cat("[4] Saving outputs ...\n")
write_parquet(W, file.path(OUT_DIR, "regime_factor_weight_matrix_walkforward.parquet"))
write_parquet(W, file.path(SHARED_OUT, "regime_factor_weight_matrix_walkforward.parquet"))

state_x_fam_json <- list(
  description = "Long-run avg state x family weights (last 60 walk-forward sig_dates)",
  shrinkage_kappa = SHRINKAGE_KAPPA,
  n_regimes = N_REGIMES,
  families = FAMILIES_LIST,
  state_weights = state_x_fam,
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
writeLines(toJSON(state_x_fam_json, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "regime_factor_weight_matrix.json"))
writeLines(toJSON(state_x_fam_json, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(SHARED_OUT, "regime_factor_weight_matrix.json"))

cat("[Step 4] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
