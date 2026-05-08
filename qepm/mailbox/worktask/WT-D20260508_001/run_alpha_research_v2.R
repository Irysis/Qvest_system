#==============================================================================
# WT-D20260508_001 Alpha Research v2 — VRP overlay alpha (CORRECTED)
#
# v1 self-diagnosis FAIL discovered (IC 0.957 ZSCORE = autocorrelation 측정,
# not alpha). r_vrp lag-1 autocor 0.404 confirmed structurally.
#
# v2 framework (Bollerslev-Tauchen-Zhou 2009 RFS authentic):
#   alpha_signal_t = f(VRP indicator at t-1)
#   target = forward 1M return of OTHER asset (KOSPI BM / Hybrid / AR)
# This is the proper VRP-as-predictor test.
#
# Predictor candidates:
#   (a) VRP_z_lag1: expanding z-score of r_vrp (signal level proxy for VRP↑)
#   (b) VRP_mom12_lag1: 12m momentum of r_vrp (signal trend)
#   (c) VRP_high_dummy_lag1: indicator for VRP > 75th percentile (regime classifier)
#
# Targets:
#   (1) r_AR_fwd1: STR_1715_AR forward 1M return (AR strategy hedge test)
#   (2) r_Hybrid_fwd1: PG2 Hybrid forward 1M return (book-level test)
#   (3) r_KOSPI_BM_fwd1: KOSPI200 BM forward 1M return (broad equity test)
#
# Note: BM_KOSPI not in master CSV. Use r_AR + r_Hybrid for primary tests.
# Add r_KR10y_fwd1 as secondary (does VRP predict bond)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_001"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts/WT_D20260508_001")
RISK_META_PATH <- file.path(ROOT, "qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv")

dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)
set.seed(20260508L)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

#==============================================================================
# Step 1: Hypothesis intake
#==============================================================================
cat("\n=== Step 1: Hypothesis intake ===\n")

request <- fromJSON(file.path(WT_DIR, "request.json"))
cat("task_id =", request$task_id, "\n")
cat("hypothesis: VRP signal at t-1 → forward 1M return of OTHER asset (proper alpha test)\n")

#==============================================================================
# Step 2: Factor sourcing (master_returns inheritance — cycle 2)
#==============================================================================
cat("\n=== Step 2: Factor sourcing ===\n")
master <- fread(RISK_META_PATH)
master[, date := as.Date(date)]
setorder(master, date)
n_all <- nrow(master)
cat("master rows:", n_all, " | date range:", as.character(master$date[1]), "~", as.character(master$date[n_all]), "\n")

# r_vrp interpretation: cycle 2 risk_candidates produced this from VRP signal returns.
# We want the underlying VRP indicator (cumulative r_vrp magnitude proxy).
# Since we only have r_vrp returns, construct VRP indicator from cumulative path.

#==============================================================================
# Step 3: Signal engineering — predictor signals from r_vrp series, target r_AR/r_Hybrid
#==============================================================================
cat("\n=== Step 3: Signal engineering ===\n")

dt <- master[, .(date, r_vrp, r_AR, r_KR10y, r_TSMOM, r_Hybrid)]

# Predictor 1: rolling 12m sum of r_vrp at t (signal level proxy, lag 1)
n <- nrow(dt)
dt[, vrp_idx := NA_real_]    # cumulative VRP signal level (12m)
for (i in 12:n) dt$vrp_idx[i] <- sum(dt$r_vrp[(i-11):i], na.rm = TRUE)
dt[, vrp_idx_lag1 := shift(vrp_idx, 1L, type = "lag")]

# Predictor 2: expanding z-score of vrp_idx (regime indicator, PIT)
dt[, vrp_idx_z := NA_real_]
burnin <- 36L
for (i in (burnin + 1):n) {
  past <- dt$vrp_idx[1:(i - 1)]
  if (sum(!is.na(past)) >= 24) {
    mu <- mean(past, na.rm = TRUE)
    sdv <- sd(past, na.rm = TRUE)
    if (!is.na(sdv) && sdv > 0) dt$vrp_idx_z[i] <- (dt$vrp_idx[i] - mu) / sdv
  }
}
dt[, vrp_idx_z_lag1 := shift(vrp_idx_z, 1L, type = "lag")]

# Predictor 3: VRP regime dummy — 1 if z>1 (high VRP risk, expect equity weakness)
dt[, vrp_high_dummy_lag1 := as.integer(vrp_idx_z_lag1 > 1)]

# Forward 1M targets (alpha return of other assets given VRP signal)
dt[, r_AR_fwd1 := shift(r_AR, -1L, type = "lead")]
dt[, r_Hybrid_fwd1 := shift(r_Hybrid, -1L, type = "lead")]
dt[, r_KR10y_fwd1 := shift(r_KR10y, -1L, type = "lead")]

# Restrict to PIT-usable rows
usable <- dt[!is.na(vrp_idx_lag1) & !is.na(vrp_idx_z_lag1), ]
cat("usable rows:", nrow(usable), " | date range:", as.character(usable$date[1]), "~",
    as.character(usable$date[nrow(usable)]), "\n")

#==============================================================================
# Step 4: Diagnostics — proper VRP-as-predictor framework
# For each (predictor, target) pair compute IC / ICIR / Harvey t-NW / DSR / sub_stab
#==============================================================================
cat("\n=== Step 4: Diagnostics ===\n")

# NW-HAC adjusted t for IC time series
nw_t <- function(ic_series) {
  ic_series <- na.omit(ic_series)
  N <- length(ic_series)
  if (N < 30) return(NA_real_)
  L <- max(1L, floor((4 * N / 100)^(2/9)))
  e <- ic_series - mean(ic_series)
  var0 <- sum(e^2) / N
  var_nw <- var0
  for (l in 1:L) {
    gamma_l <- sum(e[1:(N-l)] * e[(l+1):N]) / N
    w <- 1 - l / (L + 1)
    var_nw <- var_nw + 2 * w * gamma_l
  }
  se_nw <- sqrt(max(var_nw, 1e-12) / N)
  if (se_nw <= 0) return(NA_real_)
  mean(ic_series) / se_nw
}

# Bailey-LdP DSR (single trial, basic form)
dsr_calc <- function(rs) {
  rs <- na.omit(rs)
  N <- length(rs)
  if (N < 30) return(NA_real_)
  mu <- mean(rs); sdv <- sd(rs)
  if (is.na(sdv) || sdv <= 0) return(NA_real_)
  sk <- mean(((rs - mu) / sdv)^3)
  kt <- mean(((rs - mu) / sdv)^4)
  sr <- mu / sdv
  denom <- 1 - sk * sr + (kt - 1) / 4 * sr^2
  if (denom <= 0) return(NA_real_)
  sr * sqrt(N - 1) / sqrt(denom)
}

# Spec evaluator: predict_col → target_col
eval_spec <- function(d, pred_col, tgt_col, name) {
  sub <- d[!is.na(get(pred_col)) & !is.na(get(tgt_col)), ]
  if (nrow(sub) < 30) return(NULL)

  ic <- cor(sub[[pred_col]], sub[[tgt_col]], method = "spearman", use = "complete.obs")
  pearson_r <- cor(sub[[pred_col]], sub[[tgt_col]], method = "pearson", use = "complete.obs")

  # Rolling 36m IC for ICIR
  N <- nrow(sub)
  ic_series <- rep(NA_real_, N)
  if (N >= 48) {
    for (i in 36:N) {
      w <- sub[(i-35):i, ]
      ic_series[i] <- cor(w[[pred_col]], w[[tgt_col]], method = "spearman", use = "complete.obs")
    }
  }
  ic_series_clean <- na.omit(ic_series)
  icir <- if (length(ic_series_clean) >= 12) {
    mean(ic_series_clean) / sd(ic_series_clean)
  } else NA_real_

  t_NW <- nw_t(ic_series_clean)
  t_simple <- if (length(ic_series_clean) >= 12) {
    mean(ic_series_clean) / (sd(ic_series_clean) / sqrt(length(ic_series_clean)))
  } else NA_real_

  # Long-short return: sign(pred) * tgt (predict sign and trade)
  ls_ret <- sign(sub[[pred_col]]) * sub[[tgt_col]]
  dsr <- dsr_calc(ls_ret)
  ls_sr_ann <- mean(ls_ret, na.rm = TRUE) / sd(ls_ret, na.rm = TRUE) * sqrt(12)

  # Subperiod IC stability (sign agreement)
  sub[, year := as.integer(format(date, "%Y"))]
  ic_p1 <- tryCatch(cor(sub[year >= 2008 & year <= 2014, get(pred_col)],
                         sub[year >= 2008 & year <= 2014, get(tgt_col)],
                         method = "spearman", use = "complete.obs"),
                    error = function(e) NA_real_)
  ic_p2 <- tryCatch(cor(sub[year >= 2015 & year <= 2019, get(pred_col)],
                         sub[year >= 2015 & year <= 2019, get(tgt_col)],
                         method = "spearman", use = "complete.obs"),
                    error = function(e) NA_real_)
  ic_p3 <- tryCatch(cor(sub[year >= 2020 & year <= 2026, get(pred_col)],
                         sub[year >= 2020 & year <= 2026, get(tgt_col)],
                         method = "spearman", use = "complete.obs"),
                    error = function(e) NA_real_)
  signs <- sign(c(ic_p1, ic_p2, ic_p3))
  signs <- signs[!is.na(signs)]
  sub_stab <- if (length(signs) >= 2) abs(sum(signs)) / length(signs) else 0

  # Lag-1 autocor of predictor (sanity check — should not equal IC)
  pred_autocor <- cor(sub[[pred_col]][-1], sub[[pred_col]][-nrow(sub)], use = "complete.obs")
  tgt_autocor <- cor(sub[[tgt_col]][-1], sub[[tgt_col]][-nrow(sub)], use = "complete.obs")

  list(
    name = name, pred = pred_col, tgt = tgt_col, n = nrow(sub),
    ic = ic, pearson_r = pearson_r,
    icir = icir, t_simple = t_simple, t_NW = t_NW, dsr = dsr,
    ls_sr_ann = ls_sr_ann, sub_stab = sub_stab,
    ic_p1 = ic_p1, ic_p2 = ic_p2, ic_p3 = ic_p3,
    pred_autocor_lag1 = pred_autocor, tgt_autocor_lag1 = tgt_autocor
  )
}

# 9 specs: 3 predictors × 3 targets
specs <- list()
predictors <- c("vrp_idx_lag1", "vrp_idx_z_lag1", "vrp_high_dummy_lag1")
targets <- c("r_AR_fwd1", "r_Hybrid_fwd1", "r_KR10y_fwd1")

for (p in predictors) {
  for (t in targets) {
    name <- paste0("VRP_", sub("vrp_", "", sub("_lag1", "", p)),
                   "_predicts_", sub("_fwd1", "", sub("r_", "", t)))
    res <- eval_spec(copy(usable), p, t, name)
    if (!is.null(res)) specs <- append(specs, list(res))
  }
}

cat("\n--- Spec diagnostics (proper VRP-as-predictor) ---\n")
cat(sprintf("%-45s %3s %+8s %+8s %+8s %+8s %+8s %+6s %+6s %+6s %+6s\n",
            "spec", "n", "IC", "Pearson", "ICIR", "t_NW", "DSR", "LS_SR", "p1", "p2", "p3"))
for (s in specs) {
  cat(sprintf("%-45s %3d %+8.4f %+8.4f %+8.4f %+8.3f %+8.3f %+6.3f %+6.3f %+6.3f %+6.3f\n",
              s$name, s$n,
              s$ic %||% NA, s$pearson_r %||% NA, s$icir %||% NA,
              s$t_NW %||% NA, s$dsr %||% NA, s$ls_sr_ann %||% NA,
              s$ic_p1 %||% NA, s$ic_p2 %||% NA, s$ic_p3 %||% NA))
}
cat("\n--- Sanity (predictor autocor vs target autocor) ---\n")
for (s in specs[1:3]) {
  cat(sprintf("%-45s pred_autocor=%+.4f tgt_autocor=%+.4f\n",
              s$name, s$pred_autocor_lag1 %||% NA, s$tgt_autocor_lag1 %||% NA))
}

#==============================================================================
# Step 4b: ML comparison — XGBoost on full feature set predicting r_AR_fwd1
#==============================================================================
cat("\n=== Step 4b: ML vs Classical comparison (target = r_AR_fwd1) ===\n")

# Classical: vrp_idx_z_lag1 sign-flipped (risk-off when z high)
cls_dt <- usable[!is.na(vrp_idx_z_lag1) & !is.na(r_AR_fwd1), ]
cls_dt[, cls_signal := -sign(vrp_idx_z_lag1)]   # high VRP → defensive (negative tilt)
cls_dt[, cls_ret := cls_signal * r_AR_fwd1]
cls_sr_ann <- mean(cls_dt$cls_ret, na.rm = TRUE) / sd(cls_dt$cls_ret, na.rm = TRUE) * sqrt(12)
cat("Classical (sign-flip z): annual SR=", round(cls_sr_ann, 4), " n=", nrow(cls_dt), "\n")

naive_sr <- mean(usable$r_AR_fwd1, na.rm = TRUE) / sd(usable$r_AR_fwd1, na.rm = TRUE) * sqrt(12)
cat("Naive r_AR hold: annual SR=", round(naive_sr, 4), "\n")

ml_results <- list(method = "XGBoost", note = "see below")
have_xgb <- requireNamespace("xgboost", quietly = TRUE)
if (have_xgb) {
  library(xgboost)
  ml_dt <- usable[!is.na(vrp_idx_lag1) & !is.na(vrp_idx_z_lag1) & !is.na(r_AR) & !is.na(r_KR10y), ]
  ml_dt[, r_AR_lag1 := shift(r_AR, 1L, type = "lag")]
  ml_dt[, r_KR10y_lag1 := shift(r_KR10y, 1L, type = "lag")]
  ml_dt <- ml_dt[!is.na(r_AR_lag1) & !is.na(r_KR10y_lag1) & !is.na(r_AR_fwd1), ]

  feats <- c("vrp_idx_lag1", "vrp_idx_z_lag1", "vrp_high_dummy_lag1",
             "r_AR_lag1", "r_KR10y_lag1")
  X <- as.matrix(ml_dt[, ..feats])
  y <- ml_dt$r_AR_fwd1
  N <- nrow(X)
  cat("ML data: n=", N, " features=", length(feats), "\n")

  # 5-fold walk-forward
  n_folds <- 5L; fold_size <- floor(N / n_folds); preds <- rep(NA_real_, N)
  for (k in 1:n_folds) {
    test_start <- (k - 1) * fold_size + 1
    test_end <- if (k == n_folds) N else k * fold_size
    train_end <- test_start - 1
    if (train_end < 36) next
    dtrain <- xgb.DMatrix(data = X[1:train_end, , drop = FALSE], label = y[1:train_end])
    params <- list(objective = "reg:squarederror", eta = 0.05, max_depth = 3,
                   min_child_weight = 5, subsample = 0.8, colsample_bytree = 0.8,
                   lambda = 1.0, alpha = 0.1)
    model <- xgb.train(params, dtrain, nrounds = 100, verbose = 0)
    preds[test_start:test_end] <- predict(model,
      xgb.DMatrix(data = X[test_start:test_end, , drop = FALSE]))
  }
  preds_clean <- preds[!is.na(preds)]
  y_clean <- y[!is.na(preds)]
  ml_ic <- cor(preds_clean, y_clean, method = "spearman", use = "complete.obs")
  ml_ret <- sign(preds_clean) * y_clean
  ml_sr_ann <- mean(ml_ret, na.rm = TRUE) / sd(ml_ret, na.rm = TRUE) * sqrt(12)

  cat("ML XGBoost (5-fold WF): SR_ann=", round(ml_sr_ann, 4), " IC=", round(ml_ic, 4),
      " n_test=", length(preds_clean), "\n")

  ml_results <- list(method = "XGBoost", n_folds = n_folds,
                     n_test = length(preds_clean),
                     sr_annual = ml_sr_ann, rank_ic_oos = ml_ic,
                     features = feats)
}

#==============================================================================
# Step 5+6: Alpha forecast + confidence
#==============================================================================
cat("\n=== Step 5+6: Alpha forecast + confidence ===\n")

# Select best spec by |IC|
ic_vals <- sapply(specs, function(s) abs(s$ic %||% 0))
best_idx <- which.max(ic_vals)
best <- specs[[best_idx]]
cat("Best spec by |IC|:", best$name, "| IC=", round(best$ic, 4),
    "| ICIR=", round(best$icir %||% NA, 4), "| t_NW=", round(best$t_NW %||% NA, 3),
    "| sub_stab=", round(best$sub_stab, 3), "\n")

# Best AR-target spec specifically (most operationally relevant)
ar_specs <- Filter(function(s) grepl("AR$", s$name), specs)
ar_ics <- sapply(ar_specs, function(s) abs(s$ic %||% 0))
best_ar <- ar_specs[[which.max(ar_ics)]]
cat("Best vs r_AR target:", best_ar$name, "| IC=", round(best_ar$ic, 4), "\n")

# Last predictor signal (for alpha forecast)
last_row <- usable[nrow(usable), ]

# Alpha vector — VRP overlay signal magnitude as alpha tilt for the overlay sleeve
# The "alpha" is the expected forward 1M r_AR return given current VRP signal
# Sign convention: VRP high → expect r_AR weak → negative tilt
# alpha_pt = -beta * VRP_idx_z_lag1
beta_AR <- cov(usable$vrp_idx_z_lag1, usable$r_AR_fwd1, use = "complete.obs") /
           var(usable$vrp_idx_z_lag1, na.rm = TRUE)
last_z <- last_row$vrp_idx_z_lag1
alpha_pt <- beta_AR * last_z
cat("Last vrp_idx_z_lag1=", round(last_z %||% NA, 4),
    "| beta_AR=", round(beta_AR, 4),
    "| alpha_pt=", round(alpha_pt %||% NA, 4), "\n")

# Alpha vector
alpha_vector <- list("VRP_KOSPI_TS_OVERLAY" = alpha_pt %||% 0)
sig_sd <- sd(usable$vrp_idx_z_lag1, na.rm = TRUE)
sig_mag <- abs(last_z %||% 0) / max(sig_sd, 0.01)
confidence <- pmin(sig_mag / 2, 1)
confidence_vector <- list("VRP_KOSPI_TS_OVERLAY" = confidence)

#==============================================================================
# Step 6: Save artifacts
#==============================================================================
cat("\n=== Step 6: Save artifacts ===\n")

alpha_scores <- usable[, .(date, vrp_idx_lag1, vrp_idx_z_lag1, vrp_high_dummy_lag1,
                            r_AR, r_AR_fwd1, r_Hybrid_fwd1, r_KR10y_fwd1)]
alpha_scores[, ticker := "VRP_KOSPI_TS_OVERLAY"]
alpha_scores[, alpha_score := beta_AR * vrp_idx_z_lag1]
write_parquet(alpha_scores, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("alpha_scores.parquet saved: rows=", nrow(alpha_scores), "\n")

# Spec summary table
spec_summary <- rbindlist(lapply(specs, function(s) {
  data.table(
    name = s$name, n = s$n,
    ic = s$ic, pearson_r = s$pearson_r, icir = s$icir,
    t_NW = s$t_NW, dsr = s$dsr, ls_sr_ann = s$ls_sr_ann,
    sub_stab = s$sub_stab, ic_p1 = s$ic_p1, ic_p2 = s$ic_p2, ic_p3 = s$ic_p3,
    pred_autocor = s$pred_autocor_lag1, tgt_autocor = s$tgt_autocor_lag1
  )
}), fill = TRUE)
fwrite(spec_summary, file.path(STAGE_DIR, "spec_diagnostics.csv"))

alpha_validation <- list(
  task_id = WT_ID,
  as_of_date = as.character(request$as_of_date),
  v2_correction = "v1 IC 0.957 was r_vrp self-autocorrelation (lag-1 0.404) — not alpha. v2 uses VRP signal predicting OTHER asset (r_AR / r_Hybrid / r_KR10y).",
  hypothesis = "VRP signal at t-1 predicts forward 1M return of equity (Bollerslev-Tauchen-Zhou 2009 RFS)",
  source_papers = c(
    "Bollerslev-Tauchen-Zhou 2009 RFS (VRP predicts equity excess returns)",
    "Carr-Wu 2009 RFS (VRP theoretical framework)",
    "Bakshi-Kapadia-Madan 2003 RFS (risk-neutral skewness)"
  ),
  spec_diagnostics = lapply(specs, function(s) {
    list(name = s$name, n = s$n, ic = s$ic, pearson_r = s$pearson_r,
         icir = s$icir, t_NW = s$t_NW, dsr = s$dsr,
         ls_sr_ann = s$ls_sr_ann, sub_stab = s$sub_stab,
         ic_p1 = s$ic_p1, ic_p2 = s$ic_p2, ic_p3 = s$ic_p3,
         pred_autocor = s$pred_autocor_lag1, tgt_autocor = s$tgt_autocor_lag1)
  }),
  best_spec = best$name,
  best_ar_spec = best_ar$name,
  graduation_check = list(
    rank_ic = best_ar$ic,
    rank_ic_pass = abs(best_ar$ic %||% 0) >= 0.04,
    icir = best_ar$icir,
    icir_pass = abs(best_ar$icir %||% 0) >= 0.20,
    sub_stab = best_ar$sub_stab,
    sub_stab_pass = (best_ar$sub_stab %||% 0) >= 0.5,
    harvey_t_NW = best_ar$t_NW,
    harvey_t_pass = abs(best_ar$t_NW %||% 0) >= 3.0,
    dsr = best_ar$dsr,
    dsr_pass = abs(best_ar$dsr %||% 0) >= 0.5
  ),
  ml_comparison = ml_results,
  classical_baseline = list(method = "sign_flip_z_AR_target", sr_annual = cls_sr_ann),
  naive_baseline = list(method = "naive_AR_hold", sr_annual = naive_sr),
  caveats = list(
    "VRP_KOSPI_Proxy uses US VIX^2 - SPX RV (cycle 1 caveat). VKOSPI direct fetch deferred (KRX OpenAPI acquisition path).",
    "Predictor autocorrelations strong (vrp_idx_lag1 ~ 0.4) — be cautious about apparent IC inflation",
    "n_obs ~ 254m post-2005-02; IMF 1997 / DotCom 2000 unavailable",
    "Single-asset overlay alpha (VRP signal applied to AR/Hybrid book level)"
  )
)
write_json(alpha_validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("alpha_validation.json saved\n")

#==============================================================================
# Step 7: alpha_package_draft.json
#==============================================================================
cat("\n=== Step 7: alpha_package_draft.json ===\n")

# Factor specs (3 predictors as specs, all targeting r_AR_fwd1 as primary target)
ar_p1 <- ar_specs[[which(sapply(ar_specs, function(s) s$pred) == "vrp_idx_lag1")]]
ar_p2 <- ar_specs[[which(sapply(ar_specs, function(s) s$pred) == "vrp_idx_z_lag1")]]
ar_p3 <- ar_specs[[which(sapply(ar_specs, function(s) s$pred) == "vrp_high_dummy_lag1")]]

factor_specs <- list(
  list(
    factor_family = "VRP_VolatilityRiskPremium",
    proxy = "VRP_idx_lag1",
    formula = "rolling 12m sum of monthly r_vrp at t-1 (level proxy for VRP signal magnitude)",
    lag_rule = "t-1 month-end (PIT)",
    winsorization = "none",
    neutralization = "single-asset overlay (no cross-section neutralization)",
    economic_rationale = "Bollerslev-Tauchen-Zhou 2009 RFS — high VRP magnitude predicts equity return weakness via priced variance risk premium. Test: VRP_idx_lag1 → r_AR_fwd1 IC.",
    weight_theta = 0.0,
    references = c("Bollerslev-Tauchen-Zhou 2009 RFS"),
    source = "db_derived",
    selection_objective = "rank_ic",
    diagnostics = list(ic = ar_p1$ic, icir = ar_p1$icir, t_NW = ar_p1$t_NW, n = ar_p1$n)
  ),
  list(
    factor_family = "VRP_VolatilityRiskPremium",
    proxy = "VRP_idx_z_lag1",
    formula = "expanding-window z-score of vrp_idx, lagged 1 (PIT regime indicator)",
    lag_rule = "t-1 month-end (PIT, 36m burn-in)",
    winsorization = "implicit via z (no manual cap)",
    neutralization = "none",
    economic_rationale = "Regime-normalized VRP — when VRP is in extreme high regime (z>1), expect equity weakness next month (Carr-Wu 2009).",
    weight_theta = 1.0,
    references = c("Carr-Wu 2009 RFS", "Bollerslev-Tauchen-Zhou 2009 RFS"),
    source = "db_derived",
    selection_objective = "rank_ic",
    diagnostics = list(ic = ar_p2$ic, icir = ar_p2$icir, t_NW = ar_p2$t_NW, n = ar_p2$n)
  ),
  list(
    factor_family = "VRP_VolatilityRiskPremium",
    proxy = "VRP_high_dummy_lag1",
    formula = "indicator(vrp_idx_z > 1), lagged 1 (binary regime classifier)",
    lag_rule = "t-1 month-end",
    winsorization = "binary",
    neutralization = "none",
    economic_rationale = "Regime classifier — Bakshi-Kapadia-Madan 2003 framework risk-neutral moment based binary regime.",
    weight_theta = 0.0,
    references = c("Bakshi-Kapadia-Madan 2003 RFS"),
    source = "db_derived",
    selection_objective = "rank_ic",
    diagnostics = list(ic = ar_p3$ic, icir = ar_p3$icir, t_NW = ar_p3$t_NW, n = ar_p3$n)
  )
)

# Harvey-t pass count (target = r_AR)
harvey_t_pass <- sum(c(
  abs(ar_p1$t_NW %||% 0) >= 3.0,
  abs(ar_p2$t_NW %||% 0) >= 3.0,
  abs(ar_p3$t_NW %||% 0) >= 3.0
))

draft <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = as.character(request$as_of_date),
  forecast_horizon = "1M",
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260508_001/alpha_scores.parquet",
  factor_specs = factor_specs,
  diagnostics = list(
    rank_ic = best_ar$ic,
    icir = best_ar$icir,
    monotonicity = NA,
    subperiod_stability = best_ar$sub_stab,
    turnover_proxy = NA,
    harvey_t_stat = best_ar$t_simple,
    harvey_t_NW = best_ar$t_NW,
    deflated_sharpe_ratio = best_ar$dsr,
    post_neutralization_ic = best_ar$ic,
    n_obs = best_ar$n,
    ic_p1_2008_2014 = best_ar$ic_p1,
    ic_p2_2015_2019 = best_ar$ic_p2,
    ic_p3_2020_2026 = best_ar$ic_p3,
    spec_count = length(factor_specs),
    harvey_t_specs_pass_count = harvey_t_pass
  ),
  ml_comparison = ml_results,
  classical_baseline = list(method = "sign_flip_z_AR_target",
                            sr_annual = cls_sr_ann, n = nrow(cls_dt)),
  naive_baseline = list(method = "naive_AR_hold", sr_annual = naive_sr),
  selection_objective = "rank_ic",
  alpha_inheritance_cor = NA,
  candidates_tried = length(specs),
  method_log = lapply(specs, function(s) {
    list(name = s$name, rank_ic = s$ic, icir = s$icir,
         t_NW = s$t_NW, dsr = s$dsr, ls_sr_ann = s$ls_sr_ann,
         selected = (s$name == best_ar$name))
  }),
  challenge_flags = list(),
  rcpp_used = FALSE,
  parallel_exec = FALSE,
  hypothesis_source = "alpha_agent_discovered",
  hypothesis_title = "VRP_KOSPI_TS overlay — 4th orthogonal alpha source for SR 2.0 path",
  hypothesis_description_short = paste(
    "VRP-based time-series overlay. cycle 2 cor_hybrid -0.138 / cor_AR -0.155 /",
    "crisis_alpha 4/6 (66.7%). L-228 정합: cross-section ML 거부, time-series single overlay.",
    "Bollerslev-Tauchen-Zhou 2009 RFS framework — VRP as predictor of FORWARD r_AR/r_Hybrid."
  ),
  v2_self_audit_note = "v1 IC 0.957 was r_vrp lag-1 autocorrelation (0.404 verified). v2 corrects: predictor at t-1 → target = OTHER asset forward return.",
  caveats = list(
    "VRP_KOSPI_Proxy uses US VIX^2 - SPX RV (cycle 1 caveat). VKOSPI direct fetch deferred.",
    "Predictor autocorrelation 0.4 — moderate persistence retain; targets are OTHER asset forward returns, not r_vrp self.",
    "n_obs ~ 254m post-2005-02; IMF 1997 / DotCom 2000 BM unavailable.",
    "Single-asset overlay alpha applied to AR or Hybrid book.",
    "Harvey-t-NW critical threshold 3.0 — if best spec fails, hypothesis empirical FAIL despite theoretical strong basis."
  )
)

# Pre-flight Red Flag check
challenge_flags <- list()
if (length(factor_specs) <= 2) {
  challenge_flags <- append(challenge_flags, list(list(id = "RF-A1", severity = "HIGH",
    msg = "factor_specs <= 2")))
}
if (!is.na(best_ar$ic_p3) && !is.na(best_ar$ic) &&
    abs(best_ar$ic_p3) > abs(best_ar$ic) * 1.5) {
  challenge_flags <- append(challenge_flags, list(list(id = "RF-A3", severity = "HIGH",
    msg = "recent 3Y IC > overall * 1.5 (over-fit suspicion)")))
}
if (abs(best_ar$ic %||% 0) < 0.04) {
  challenge_flags <- append(challenge_flags, list(list(id = "GRADUATION_FAIL_IC", severity = "HIGH",
    msg = paste0("rank_ic ", round(best_ar$ic %||% NA, 4), " < 0.04 graduation threshold"))))
}
if (abs(best_ar$icir %||% 0) < 0.20) {
  challenge_flags <- append(challenge_flags, list(list(id = "GRADUATION_FAIL_ICIR", severity = "HIGH",
    msg = paste0("ICIR ", round(best_ar$icir %||% NA, 4), " < 0.20 Alpha Lab Gate"))))
}
if (abs(best_ar$t_NW %||% 0) < 3.0) {
  challenge_flags <- append(challenge_flags, list(list(id = "GRADUATION_FAIL_HARVEY", severity = "HIGH",
    msg = paste0("t_NW ", round(best_ar$t_NW %||% NA, 3), " < 3.0 Harvey threshold"))))
}
draft$challenge_flags <- challenge_flags

draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
write_json(draft, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("alpha_package_draft.json saved:", draft_path, "(", file.size(draft_path), "bytes)\n")

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
      package_type = "alpha_package_draft_v2",
      method_selected = best_ar$name,
      input_file_paths = c(RISK_META_PATH, file.path(STAGE_DIR, "alpha_scores.parquet"))
    )
    cat("Lineage v2 recorded\n")
  }, error = function(e) cat("Lineage warning:", conditionMessage(e), "\n"))
}

cat("\n=== Alpha research v2 complete ===\n")
cat("Best spec (vs r_AR):", best_ar$name, "\n")
cat("  IC=", round(best_ar$ic, 4), " | ICIR=", round(best_ar$icir %||% NA, 4),
    " | t_NW=", round(best_ar$t_NW %||% NA, 3),
    " | sub_stab=", round(best_ar$sub_stab, 3), "\n")
cat("Graduation: rank_ic_pass=", abs(best_ar$ic %||% 0) >= 0.04,
    " icir_pass=", abs(best_ar$icir %||% 0) >= 0.20,
    " harvey_pass=", abs(best_ar$t_NW %||% 0) >= 3.0, "\n")
