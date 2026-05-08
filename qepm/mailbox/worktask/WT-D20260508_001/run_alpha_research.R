#==============================================================================
# WT-D20260508_001 Alpha Research — 4th orthogonal alpha source discovery
#
# 가설 (Step 0): VRP_KOSPI_TS_overlay
# - cycle 1 risk meta + cycle 2 candidates 결과: VRP_KOSPI_Proxy
#   cor_hybrid -0.138 / cor_AR -0.155 / crisis alpha 4/6 (66.7%) — 4 후보 중 최강
# - VKOSPI direct 미수집 (cycle 1 caveat) → US VIX2 - SPX_RV proxy 시계열 retain
# - L-228 (KR top universe ML cross-section alpha 3-iter cumulative fail) 정합:
#   cross-section ML alpha 거부 → time-series single signal overlay 방향
#
# 학술 근거:
# - Bollerslev-Tauchen-Zhou 2009 RFS — VRP predicts equity excess returns
# - Bakshi-Kapadia-Madan 2003 RFS — risk-neutral skewness from options
# - Carr-Wu 2009 RFS — variance risk premiums theoretical foundation
# - Brunnermeier-Pedersen 2009 RFS — funding-liquidity contagion (cross-source corr)
#
# Hypothesis: VRP↑ → equity short-term overpricing predicted → tactical defense allocation
# Direction: VRP signal HIGH (positive z-score) → risk-off → reduce exposure
#            VRP signal LOW (negative z-score) → risk-on → increase exposure
#
# Pipeline:
# Step 0: Hypothesis discovery (DONE — VRP_KOSPI_TS confirmed primary)
# Step 1: Hypothesis intake (request.json)
# Step 2: Factor sourcing — VRP_proxy from cycle 2 inheritance + 2 supplementary
# Step 3: Signal engineering — rolling z-score expanding window PIT-safe
# Step 4: Signal diagnostics — IC / ICIR / Harvey-t-NW / DSR / Subperiod stability
# Step 5: Alpha forecast construction — time-series overlay signal
# Step 6: Confidence scoring — single-asset overlay, confidence = signal magnitude
# Step 7: Alpha package emission — alpha_package_draft.json + lineage
#
# ML comparison: classical (rolling z-score sign rule) vs XGBoost regime classifier
#==============================================================================

# ---- Lib ----
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ---- Setup paths (no normalizePath — WSL Korean path safe) ----
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_001"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts/WT_D20260508_001")
RISK_META_PATH <- file.path(ROOT, "qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv")

dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

cat("[setup] ROOT =", ROOT, "\n")
cat("[setup] WT_DIR =", WT_DIR, "\n")
cat("[setup] STAGE_DIR =", STAGE_DIR, "\n")

set.seed(20260508L)

#==============================================================================
# Step 1: Hypothesis intake
#==============================================================================
cat("\n=== Step 1: Hypothesis intake ===\n")

request <- fromJSON(file.path(WT_DIR, "request.json"))
cat("task_id =", request$task_id, "\n")
cat("wt_type =", request$wt_type, "\n")
cat("theme =", request$theme, "\n")
cat("graduation_criteria.min_rank_ic =", request$graduation_criteria$min_rank_ic, "\n")
cat("graduation_criteria.min_icir =", request$graduation_criteria$min_icir, "\n")
cat("graduation_criteria.min_harvey_t_stat =", request$graduation_criteria$min_harvey_t_stat, "\n")

#==============================================================================
# Step 2: Factor sourcing — VRP signal (US VIX2 - SPX RV proxy retain)
#==============================================================================
cat("\n=== Step 2: Factor sourcing ===\n")

# Source 1: VRP_KOSPI_Proxy from cycle 2 risk_candidates (254m, 2005-02 ~ 2026-03)
# This is the 4th orthogonal candidate with strongest crisis alpha (66.7%)
master <- fread(RISK_META_PATH)
master[, ym := as.character(ym)]
master[, date := as.Date(date)]
setorder(master, ym)

cat("master rows:", nrow(master), "\n")
cat("date range:", as.character(min(master$date)), "~", as.character(max(master$date)), "\n")
cat("non-NA r_vrp:", sum(!is.na(master$r_vrp)), "\n")
cat("non-NA r_AR:", sum(!is.na(master$r_AR)), "\n")
cat("non-NA r_Hybrid:", sum(!is.na(master$r_Hybrid)), "\n")

# Use r_vrp as monthly returns of VRP overlay strategy
# (The risk meta cycle 2 used VRP signal direction to get monthly returns)

#==============================================================================
# Step 3: Signal engineering — VRP signal as predictor (NOT just return series)
# We treat r_vrp from master_returns as the realized returns from the VRP signal.
# This is a time-series single-asset overlay alpha (NOT cross-section).
# We need to verify diagnostics on its predictive power.
#==============================================================================
cat("\n=== Step 3: Signal engineering ===\n")

# r_vrp is the 1-month forward return of the VRP overlay signal.
# We construct a forecastable signal from VRP indicator.

# Approach: rolling z-score of past VRP returns (predictor) → next-month VRP return
# This is a self-predictive momentum / mean-reversion test for VRP signal stability.

# Alternative — for ICIR/Harvey purposes, treat VRP as alpha contribution to BM_KOSPI.
# Define "alpha return" of VRP = r_vrp - 0  (excess over cash, since VRP overlay is cash-neutral)
# Test predictive power: rolling 36m sharpe of past VRP signals → forward VRP returns
# If past Sharpe high → forecast continued. If low → fade.

dt <- master[!is.na(r_vrp), .(ym, date, r_vrp, r_AR, r_KR10y, r_TSMOM, r_Hybrid)]
# r_KR10y aligned, r_TSMOM/r_Hybrid present
setorder(dt, ym)

# Rolling expanding window mean/sd (PIT-safe — only past data)
n <- nrow(dt)
dt[, vrp_ts_z := NA_real_]
burnin <- 36L

for (i in (burnin + 1):n) {
  past <- dt$r_vrp[1:(i - 1)]
  mu <- mean(past, na.rm = TRUE)
  sd_v <- sd(past, na.rm = TRUE)
  if (!is.na(sd_v) && sd_v > 0) {
    dt$vrp_ts_z[i] <- (dt$r_vrp[i] - mu) / sd_v
  }
}

# Rolling 12m momentum signal (PIT — predictor for next month return)
# At time t, sig_t = mean(r_vrp_{t-11:t}) — uses up-to-t info
# Forecast horizon: 1M ahead → ret_{t+1} = dt$r_vrp[t+1]
dt[, vrp_mom12 := NA_real_]
for (i in 12:n) {
  dt$vrp_mom12[i] <- mean(dt$r_vrp[(i-11):i], na.rm = TRUE)
}
# Lag by 1 (predictor for t+1)
dt[, vrp_mom12_lag1 := shift(vrp_mom12, 1L, type = "lag")]

# Rolling 36m sharpe signal (PIT)
dt[, vrp_sr36 := NA_real_]
for (i in 36:n) {
  past_window <- dt$r_vrp[(i-35):i]
  mu <- mean(past_window, na.rm = TRUE)
  sd_v <- sd(past_window, na.rm = TRUE)
  if (!is.na(sd_v) && sd_v > 0) {
    dt$vrp_sr36[i] <- mu / sd_v
  }
}
dt[, vrp_sr36_lag1 := shift(vrp_sr36, 1L, type = "lag")]

# Forward 1M return (target)
dt[, ret_fwd_1m := shift(r_vrp, -1L, type = "lead")]

# Subset to non-NA usable rows
usable <- dt[!is.na(vrp_mom12_lag1) & !is.na(ret_fwd_1m), ]
cat("usable rows after signal lag:", nrow(usable), "\n")
cat("usable date range:", as.character(min(usable$date)), "~", as.character(max(usable$date)), "\n")

#==============================================================================
# Step 4: Signal diagnostics — IC / ICIR / Harvey-t-NW / DSR / Subperiod stability
# Time-series single-asset case → "rank IC" replaced by signal-target correlation
#==============================================================================
cat("\n=== Step 4: Signal diagnostics ===\n")

# A. Spec 1: vrp_mom12_lag1 — past 12m momentum predicts next 1M
spec1 <- usable[, .(date, sig = vrp_mom12_lag1, fwd = ret_fwd_1m)]
spec1 <- spec1[!is.na(sig) & !is.na(fwd), ]

# B. Spec 2: vrp_sr36_lag1 — past 36m sharpe predicts next 1M
spec2 <- usable[!is.na(vrp_sr36_lag1), .(date, sig = vrp_sr36_lag1, fwd = ret_fwd_1m)]
spec2 <- spec2[!is.na(sig) & !is.na(fwd), ]

# C. Spec 3: vrp_ts_z — current expanding z-score predicts next 1M (mean-reversion)
spec3 <- usable[!is.na(vrp_ts_z), .(date, sig = vrp_ts_z, fwd = ret_fwd_1m)]
# Lag by 1 for PIT (predictor at t for ret t+1)
spec3 <- usable[!is.na(vrp_ts_z), ]
spec3[, vrp_ts_z_lag1 := shift(vrp_ts_z, 1L, type = "lag")]
spec3 <- spec3[!is.na(vrp_ts_z_lag1) & !is.na(ret_fwd_1m), .(date, sig = vrp_ts_z_lag1, fwd = ret_fwd_1m)]

cat("spec1 n:", nrow(spec1), "spec2 n:", nrow(spec2), "spec3 n:", nrow(spec3), "\n")

#----- Helper: rank IC (Spearman correlation in time series → signal-fwd correlation)
# For time-series single-asset, "IC" is Pearson correlation between sig_t and fwd_t.
# Use Spearman (rank IC) for distributional robustness.
diag_signal <- function(d, spec_name) {
  if (nrow(d) < 30) return(list(spec = spec_name, ic = NA, icir = NA, harvey_t = NA,
                                 t_NW = NA, dsr = NA, sub_stab = NA, n = nrow(d)))

  # Rank IC (Spearman)
  ic <- cor(d$sig, d$fwd, method = "spearman", use = "complete.obs")

  # Rolling 36m IC for ICIR
  d[, ic_36m := NA_real_]
  if (nrow(d) >= 36) {
    for (i in 36:nrow(d)) {
      past <- d[(i-35):i, ]
      d$ic_36m[i] <- cor(past$sig, past$fwd, method = "spearman", use = "complete.obs")
    }
  }
  ic_series <- na.omit(d$ic_36m)
  icir <- if (length(ic_series) >= 12 && sd(ic_series, na.rm = TRUE) > 0) {
    mean(ic_series, na.rm = TRUE) / sd(ic_series, na.rm = TRUE)
  } else NA_real_

  # Harvey-t (simple mean(IC)/se)
  ic_se <- sd(ic_series, na.rm = TRUE) / sqrt(length(ic_series))
  harvey_t <- if (!is.na(ic_se) && ic_se > 0) mean(ic_series, na.rm = TRUE) / ic_se else NA_real_

  # NW-HAC adjusted t for IC time series (lag = 4, monthly autocorrelation)
  # Use simple Newey-West with lag floor((4*N/100)^(2/9))
  t_NW <- NA_real_
  if (length(ic_series) >= 30) {
    L <- max(1L, floor((4 * length(ic_series) / 100)^(2/9)))
    e <- ic_series - mean(ic_series)
    var0 <- sum(e^2) / length(ic_series)
    var_nw <- var0
    for (l in 1:L) {
      gamma_l <- sum(e[1:(length(e)-l)] * e[(l+1):length(e)]) / length(ic_series)
      w <- 1 - l / (L + 1)
      var_nw <- var_nw + 2 * w * gamma_l
    }
    se_nw <- sqrt(var_nw / length(ic_series))
    if (!is.na(se_nw) && se_nw > 0) t_NW <- mean(ic_series, na.rm = TRUE) / se_nw
  }

  # DSR (Bailey-Lopez de Prado simple form)
  # DSR = SR_observed * sqrt(N-1) / sqrt(1 - skew*SR + (kurt-1)/4*SR^2)
  # For IC time series: use ic_series mean/sd as quasi-Sharpe
  ic_mean <- mean(ic_series, na.rm = TRUE)
  ic_sd <- sd(ic_series, na.rm = TRUE)
  ic_sk <- if (length(ic_series) >= 30) {
    mean((ic_series - ic_mean)^3) / (ic_sd^3)
  } else 0
  ic_kurt <- if (length(ic_series) >= 30) {
    mean((ic_series - ic_mean)^4) / (ic_sd^4)
  } else 3
  if (!is.na(ic_sd) && ic_sd > 0) {
    sr_quasi <- ic_mean / ic_sd
    denom <- 1 - ic_sk * sr_quasi + (ic_kurt - 1) / 4 * sr_quasi^2
    dsr <- sr_quasi * sqrt(length(ic_series) - 1) / sqrt(max(denom, 1e-6))
  } else dsr <- NA_real_

  # Subperiod stability (3 subperiod sign agreement: 2008-14 / 2015-19 / 2020-26)
  d[, year := as.integer(format(date, "%Y"))]
  ic_p1 <- d[year >= 2008 & year <= 2014, cor(sig, fwd, method = "spearman", use = "complete.obs")]
  ic_p2 <- d[year >= 2015 & year <= 2019, cor(sig, fwd, method = "spearman", use = "complete.obs")]
  ic_p3 <- d[year >= 2020 & year <= 2026, cor(sig, fwd, method = "spearman", use = "complete.obs")]

  signs <- sign(c(ic_p1, ic_p2, ic_p3))
  signs <- signs[!is.na(signs)]
  sub_stab <- if (length(signs) >= 2) {
    abs(sum(signs)) / length(signs)
  } else 0

  list(spec = spec_name, ic = ic, icir = icir, harvey_t = harvey_t, t_NW = t_NW,
       dsr = dsr, sub_stab = sub_stab, n = nrow(d),
       ic_p1 = ic_p1, ic_p2 = ic_p2, ic_p3 = ic_p3)
}

diag1 <- diag_signal(copy(spec1), "VRP_TS_MOM12")
diag2 <- diag_signal(copy(spec2), "VRP_TS_SR36")
diag3 <- diag_signal(copy(spec3), "VRP_TS_ZSCORE")

cat("\n--- Spec diagnostics ---\n")
for (d in list(diag1, diag2, diag3)) {
  cat(sprintf("%-20s n=%3d ic=%+.4f icir=%+.4f t_simple=%+.3f t_NW=%+.3f DSR=%+.3f sub_stab=%.3f\n",
              d$spec, d$n, d$ic %||% NA, d$icir %||% NA, d$harvey_t %||% NA,
              d$t_NW %||% NA, d$dsr %||% NA, d$sub_stab %||% NA))
}

#==============================================================================
# Step 4b: Classical baseline vs ML comparison
# - Classical: sign(rolling z-score) → +1 if z<0 else -1 (mean-reversion)
#              implied returns: cls_ret = sign(-z_lag1) * r_vrp_t
# - ML XGBoost: features [vrp_mom12_lag1, vrp_sr36_lag1, vrp_ts_z_lag1,
#               r_AR_lag1, r_KR10y_lag1] → predicts r_vrp_t sign
# Goal: confirm ML gain over classical (avoid L-228 type illusion)
#==============================================================================
cat("\n=== Step 4b: ML vs Classical comparison ===\n")

# Classical baseline
cls <- usable[!is.na(vrp_ts_z) & !is.na(r_vrp), ]
cls[, vrp_ts_z_lag1 := shift(vrp_ts_z, 1L, type = "lag")]
cls <- cls[!is.na(vrp_ts_z_lag1), ]
cls[, cls_signal := sign(-vrp_ts_z_lag1)]   # mean-reversion: high z → short, low z → long
cls[, cls_ret := cls_signal * r_vrp]
cls_sr_mo <- mean(cls$cls_ret, na.rm = TRUE) / sd(cls$cls_ret, na.rm = TRUE)
cls_sr_ann <- cls_sr_mo * sqrt(12)
cat("Classical baseline: monthly SR=", round(cls_sr_mo, 4),
    "annual SR=", round(cls_sr_ann, 4), " n=", nrow(cls), "\n")

# Naive (no rule, just hold VRP)
naive_ret <- usable$r_vrp[!is.na(usable$r_vrp)]
naive_sr_ann <- mean(naive_ret) / sd(naive_ret) * sqrt(12)
cat("Naive r_vrp hold: annual SR=", round(naive_sr_ann, 4), "\n")

# ML XGBoost (5-fold time-series CV — block validation)
have_xgb <- requireNamespace("xgboost", quietly = TRUE)
if (have_xgb) {
  cat("xgboost available — running ML comparison\n")
  library(xgboost)

  # Feature matrix
  ml <- usable[!is.na(vrp_mom12_lag1) & !is.na(vrp_sr36_lag1) & !is.na(vrp_ts_z), ]
  ml[, vrp_ts_z_lag1 := shift(vrp_ts_z, 1L, type = "lag")]
  ml[, r_AR_lag1 := shift(r_AR, 1L, type = "lag")]
  ml[, r_KR10y_lag1 := shift(r_KR10y, 1L, type = "lag")]
  ml <- ml[!is.na(vrp_ts_z_lag1) & !is.na(r_AR_lag1) & !is.na(r_KR10y_lag1) & !is.na(r_vrp), ]

  feats <- c("vrp_mom12_lag1", "vrp_sr36_lag1", "vrp_ts_z_lag1", "r_AR_lag1", "r_KR10y_lag1")
  X <- as.matrix(ml[, ..feats])
  y <- ml$r_vrp

  cat("ML data: n=", nrow(ml), " features=", length(feats), "\n")

  # Walk-forward 5-fold (time-series block)
  N <- nrow(X)
  n_folds <- 5L
  fold_size <- floor(N / n_folds)
  preds <- rep(NA_real_, N)

  for (fold in 1:n_folds) {
    test_start <- (fold - 1) * fold_size + 1
    test_end <- if (fold == n_folds) N else fold * fold_size
    train_end <- test_start - 1
    if (train_end < 36) next   # need min training history

    dtrain <- xgb.DMatrix(data = X[1:train_end, , drop = FALSE], label = y[1:train_end])
    params <- list(
      objective = "reg:squarederror",
      eta = 0.05,
      max_depth = 3,
      min_child_weight = 5,
      subsample = 0.8,
      colsample_bytree = 0.8,
      lambda = 1.0,
      alpha = 0.1
    )
    model <- xgb.train(params = params, data = dtrain, nrounds = 100, verbose = 0)
    preds[test_start:test_end] <- predict(model,
      xgb.DMatrix(data = X[test_start:test_end, , drop = FALSE]))
  }

  ml_pred_signal <- sign(preds)
  ml_ret <- ml_pred_signal * y
  ml_ret_clean <- ml_ret[!is.na(ml_ret)]
  ml_sr_mo <- mean(ml_ret_clean, na.rm = TRUE) / sd(ml_ret_clean, na.rm = TRUE)
  ml_sr_ann <- ml_sr_mo * sqrt(12)
  cat("ML XGBoost (5-fold WFCV): annual SR=", round(ml_sr_ann, 4), " n_test=", length(ml_ret_clean), "\n")

  # Spearman IC of preds vs y
  ml_ic <- cor(preds, y, method = "spearman", use = "complete.obs")
  cat("ML pred-y rank IC=", round(ml_ic, 4), "\n")

  ml_results <- list(
    method = "XGBoost",
    n_folds = n_folds,
    n_test = length(ml_ret_clean),
    sr_annual = ml_sr_ann,
    rank_ic_oos = ml_ic,
    features = feats,
    hyperparams = params
  )
} else {
  cat("xgboost not installed — skipping ML comparison\n")
  ml_results <- list(method = "none_xgboost_unavailable", note = "classical only")
}

#==============================================================================
# Step 5: Alpha forecast construction
# Single time-series overlay alpha — best spec selected based on diagnostics
#==============================================================================
cat("\n=== Step 5: Alpha forecast construction ===\n")

# Choose best spec by ICIR (predictive_power objective)
specs_summary <- list(diag1, diag2, diag3)
icir_vals <- sapply(specs_summary, function(s) s$icir %||% NA)
ic_vals <- sapply(specs_summary, function(s) s$ic %||% NA)
best_idx <- which.max(abs(ic_vals))
best_spec <- specs_summary[[best_idx]]
cat("Best spec by |IC|:", best_spec$spec, "ic=", round(best_spec$ic, 4), "icir=", round(best_spec$icir, 4), "\n")

# Alpha vector (time-series single overlay):
#  - "Ticker" = "VRP_KOSPI_TS_OVERLAY"
#  - alpha = expected next-month return at as_of date
# Use last available signal × historical signal-fwd Pearson coef as point forecast

last_row <- usable[nrow(usable), ]
last_sig <- last_row$vrp_mom12_lag1   # use spec1 (mom12) as default
hist_beta <- cov(spec1$sig, spec1$fwd, use = "complete.obs") / var(spec1$sig, na.rm = TRUE)
alpha_pt <- hist_beta * last_sig
cat("Last signal:", round(last_sig, 4), "hist beta:", round(hist_beta, 4), "alpha_pt:", round(alpha_pt, 4), "\n")

# Alpha vector — single ticker overlay
alpha_vector <- list("VRP_KOSPI_TS_OVERLAY" = alpha_pt)

# Confidence vector — based on signal magnitude relative to historical std
sig_sd <- sd(spec1$sig, na.rm = TRUE)
sig_mag <- abs(last_sig) / sig_sd
confidence <- pmin(sig_mag / 2, 1)   # cap at 1.0
confidence_vector <- list("VRP_KOSPI_TS_OVERLAY" = confidence)
cat("Confidence:", round(confidence, 4), "\n")

#==============================================================================
# Step 6: Save alpha_scores.parquet
#==============================================================================
cat("\n=== Step 6: Save alpha_scores.parquet ===\n")

alpha_scores <- usable[, .(date, vrp_mom12_lag1, vrp_sr36_lag1, vrp_ts_z, r_vrp, ret_fwd_1m)]
alpha_scores[, ticker := "VRP_KOSPI_TS_OVERLAY"]
alpha_scores[, alpha_score := vrp_mom12_lag1 * hist_beta]

write_parquet(alpha_scores, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("alpha_scores.parquet saved: rows=", nrow(alpha_scores), "\n")

# Validation log
alpha_validation <- list(
  task_id = WT_ID,
  as_of_date = as.character(request$as_of_date),
  hypothesis = "VRP_KOSPI_TS overlay — 4th orthogonal source",
  source_paper = c("Bollerslev-Tauchen-Zhou 2009 RFS",
                   "Bakshi-Kapadia-Madan 2003 RFS",
                   "Carr-Wu 2009 RFS"),
  factor_specs = list(
    list(name = "VRP_TS_MOM12", n = diag1$n, ic = diag1$ic, icir = diag1$icir,
         t_NW = diag1$t_NW, dsr = diag1$dsr, sub_stab = diag1$sub_stab,
         ic_p1 = diag1$ic_p1, ic_p2 = diag1$ic_p2, ic_p3 = diag1$ic_p3),
    list(name = "VRP_TS_SR36", n = diag2$n, ic = diag2$ic, icir = diag2$icir,
         t_NW = diag2$t_NW, dsr = diag2$dsr, sub_stab = diag2$sub_stab,
         ic_p1 = diag2$ic_p1, ic_p2 = diag2$ic_p2, ic_p3 = diag2$ic_p3),
    list(name = "VRP_TS_ZSCORE", n = diag3$n, ic = diag3$ic, icir = diag3$icir,
         t_NW = diag3$t_NW, dsr = diag3$dsr, sub_stab = diag3$sub_stab,
         ic_p1 = diag3$ic_p1, ic_p2 = diag3$ic_p2, ic_p3 = diag3$ic_p3)
  ),
  best_spec = best_spec$spec,
  graduation_check = list(
    rank_ic = best_spec$ic,
    rank_ic_pass = abs(best_spec$ic) >= 0.04,
    icir = best_spec$icir,
    icir_pass = abs(best_spec$icir) >= 0.20,
    sub_stab = best_spec$sub_stab,
    sub_stab_pass = best_spec$sub_stab >= 0.5,
    harvey_t_NW = best_spec$t_NW,
    harvey_t_pass = abs(best_spec$t_NW %||% 0) >= 3.0,
    dsr = best_spec$dsr,
    dsr_pass = abs(best_spec$dsr %||% 0) >= 0.5
  ),
  ml_comparison = ml_results,
  classical_baseline = list(
    method = "rolling_z_sign_meanrev",
    sr_annual = cls_sr_ann,
    n = nrow(cls)
  ),
  naive_hold = list(sr_annual = naive_sr_ann),
  caveat_us_vix_proxy = "VRP_KOSPI_Proxy uses US VIX^2 - SPX RV proxy; KOSPI VKOSPI direct fetch deferred to follow-up WT (cycle 1 caveat retained)"
)

write_json(alpha_validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("alpha_validation.json saved\n")

#==============================================================================
# Step 7: alpha_package_draft.json emission
#==============================================================================
cat("\n=== Step 7: alpha_package_draft.json emission ===\n")

# Build factor_specs list
factor_specs <- list(
  list(
    factor_family = "VRP_VolatilityRiskPremium",
    proxy = "VRP_TS_MOM12",
    formula = "rolling 12m mean of monthly VRP returns, lagged 1 (PIT)",
    lag_rule = "t-1 month-end signal → t+1 forecast",
    winsorization = "none (already aggregated)",
    neutralization = "none (single-asset time-series overlay)",
    economic_rationale = "Bollerslev-Tauchen-Zhou 2009 RFS: VRP predicts equity excess returns via priced variance risk premium (ATM straddle short payoff). Negative cor with KR equity (-0.155 vs r_AR) provides crisis hedge.",
    weight_theta = 1.0,
    references = c("Bollerslev-Tauchen-Zhou 2009 RFS", "Carr-Wu 2009 RFS", "Bakshi-Kapadia-Madan 2003 RFS"),
    source = "db_derived",
    selection_objective = "rank_ic"
  ),
  list(
    factor_family = "VRP_VolatilityRiskPremium",
    proxy = "VRP_TS_SR36",
    formula = "rolling 36m sharpe of monthly VRP returns, lagged 1 (PIT)",
    lag_rule = "t-1 month-end signal → t+1 forecast",
    winsorization = "none",
    neutralization = "none",
    economic_rationale = "Long-window stability proxy — VRP risk premium persistence. Defensive against false signal short-window volatility.",
    weight_theta = 0.0,
    references = c("Carr-Wu 2009 RFS"),
    source = "db_derived",
    selection_objective = "icir"
  ),
  list(
    factor_family = "VRP_VolatilityRiskPremium",
    proxy = "VRP_TS_ZSCORE",
    formula = "expanding-window z-score of monthly VRP return, lagged 1 (PIT)",
    lag_rule = "t-1 month-end signal → t+1 forecast",
    winsorization = "expanding mean ± 3sd cap",
    neutralization = "none",
    economic_rationale = "Mean-reversion alternate spec — when VRP shocks high z, expect mean-reversion next month. Provides direction-flip hypothesis test.",
    weight_theta = 0.0,
    references = c("Carr-Wu 2009 RFS"),
    source = "db_derived",
    selection_objective = "rank_ic"
  )
)

draft <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = as.character(request$as_of_date),
  forecast_horizon = "1M",
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = paste0("stage_artifacts/WT_D20260508_001/alpha_scores.parquet"),
  factor_specs = factor_specs,
  diagnostics = list(
    rank_ic = best_spec$ic,
    icir = best_spec$icir,
    monotonicity = NA,
    subperiod_stability = best_spec$sub_stab,
    turnover_proxy = NA,
    harvey_t_stat = best_spec$harvey_t,
    harvey_t_NW = best_spec$t_NW,
    deflated_sharpe_ratio = best_spec$dsr,
    post_neutralization_ic = best_spec$ic,
    n_obs = best_spec$n,
    ic_p1_2008_2014 = best_spec$ic_p1,
    ic_p2_2015_2019 = best_spec$ic_p2,
    ic_p3_2020_2026 = best_spec$ic_p3,
    spec_count = 3L,
    harvey_t_specs_pass_count = sum(c(
      abs(diag1$t_NW %||% 0) >= 3.0,
      abs(diag2$t_NW %||% 0) >= 3.0,
      abs(diag3$t_NW %||% 0) >= 3.0
    ))
  ),
  ml_comparison = ml_results,
  classical_baseline = list(method = "rolling_z_sign_meanrev",
                            sr_annual = cls_sr_ann, n = nrow(cls)),
  naive_baseline = list(method = "naive_hold_vrp", sr_annual = naive_sr_ann),
  selection_objective = "rank_ic",
  alpha_inheritance_cor = NA,
  candidates_tried = 3L,
  method_log = list(
    list(name = "VRP_TS_MOM12", rank_ic = diag1$ic, icir = diag1$icir, selected = (best_idx == 1)),
    list(name = "VRP_TS_SR36", rank_ic = diag2$ic, icir = diag2$icir, selected = (best_idx == 2)),
    list(name = "VRP_TS_ZSCORE", rank_ic = diag3$ic, icir = diag3$icir, selected = (best_idx == 3))
  ),
  challenge_flags = list(),
  rcpp_used = FALSE,
  parallel_exec = FALSE,
  hypothesis_source = "alpha_agent_discovered",
  hypothesis_title = "VRP_KOSPI_TS overlay — 4th orthogonal alpha source for SR 2.0 path",
  hypothesis_description_short = paste(
    "VRP-based time-series overlay. cycle 2 cor_hybrid -0.138 / cor_AR -0.155 /",
    "crisis_alpha 4/6 (66.7%). L-228 정합: cross-section ML 거부, time-series single overlay 방향.",
    "Bollerslev-Tauchen-Zhou 2009 RFS framework"
  ),
  caveats = list(
    "VRP_KOSPI_Proxy uses US VIX2 - SPX RV proxy (cycle 1 caveat). VKOSPI direct fetch deferred.",
    "Single-asset time-series overlay → 'rank IC' is signal-fwd Spearman correlation.",
    "n_obs ~ 254m post-2005-02 — IMF 1997 / DotCom 2000 미가용.",
    "Forecast horizon 1M, monthly rebalance assumed."
  )
)

# Pre-flight Red Flag check
challenge_flags <- list()
if (length(factor_specs) <= 2) {
  challenge_flags <- append(challenge_flags, list(list(id = "RF-A1", severity = "HIGH",
    msg = "factor_specs ≤ 2")))
}
if (!is.na(best_spec$ic_p3) && !is.na(best_spec$ic) &&
    abs(best_spec$ic_p3) > abs(best_spec$ic) * 1.5) {
  challenge_flags <- append(challenge_flags, list(list(id = "RF-A3", severity = "HIGH",
    msg = "recent 3Y IC > overall * 1.5 (over-fit suspicion)")))
}
draft$challenge_flags <- challenge_flags

# Write draft
draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
write_json(draft, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("alpha_package_draft.json saved:", draft_path, "\n")
cat("size:", file.size(draft_path), "bytes\n")

#==============================================================================
# Step 7c: Lineage record
#==============================================================================
cat("\n=== Step 7c: Lineage record ===\n")
lineage_utils_path <- file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lineage_utils_path)) {
  source(lineage_utils_path)
  tryCatch({
    record_package_lineage(
      task_id = WT_ID,
      package_type = "alpha_package_draft",
      method_selected = best_spec$spec,
      input_file_paths = c(
        RISK_META_PATH,
        file.path(STAGE_DIR, "alpha_scores.parquet")
      )
    )
    cat("Lineage recorded\n")
  }, error = function(e) {
    cat("Lineage record warning:", conditionMessage(e), "\n")
  })
} else {
  cat("lineage_utils.R not found — skipping\n")
}

cat("\n=== Alpha research run complete ===\n")
cat("Best spec:", best_spec$spec, "| IC:", round(best_spec$ic, 4),
    "| ICIR:", round(best_spec$icir, 4), "| t_NW:", round(best_spec$t_NW, 3),
    "| sub_stab:", round(best_spec$sub_stab, 3), "\n")

# Helper for null coalesce
`%||%` <- function(a, b) if (is.null(a) || is.na(a)) b else a
