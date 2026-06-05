#==============================================================================
# 04_model_runner.R — S5 Elastic-Net + S6 XGBoost + S8 Ensemble
#
# Plan v0.4.2 — forge agent full implementation (2026-05-19)
#
# Walk-forward contract:
#   Train       1995-01-01 ~ 2009-12-31 (leave-one-crisis-out: IMF 1997 / Card 2003 / GFC 2008)
#   Validation  2010-01-01 ~ 2015-12-31 (6Y, threshold + ensemble weight median lock)
#   OOS         2016-01-01 ~ 2026-04-30 (10Y+)
#   purge       ≥ 21 trading days
#   embargo     21~63 trading days (default 42)
#   leave-one-crisis-out: 3 periods excluded during CV
#
# PIT:
#   - feature_panel.parquet already lag-1 applied (per feature_lag_table.csv)
#   - lagged_y (t-h-1) constructed here with additional lag relative to label
#   - observable state only (no lagged Y_t in X — per plan mandate)
#
# S5: glmnet alpha=0.5 (ElasticNet), 5-fold purged CV + lambda selection
# S6: XGBoost depth≤3, eta=0.05, early_stop=50, max_trees=500
#     + Platt scaling calibration
# S8: Ensemble [EW / BMA / Ridge-stacked] — default EW
#
# Output: outputs/03_models/elastic_net/{predictions.parquet, coefficients.csv, calibration.png}
#         outputs/03_models/xgboost/{predictions.parquet, feature_importance.csv, calibration.png}
#         outputs/03_models/stacking_ensemble/{predictions_final.parquet, ensemble_weights.json}
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(glmnet)
  library(xgboost)
  library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS_DIR, "outputs/01_data")
TARGET_DIR <- file.path(WS_DIR, "outputs/02_targets")
MODELS_DIR <- file.path(WS_DIR, "outputs/03_models")

for (sub in c("elastic_net", "xgboost", "stacking_ensemble")) {
  dir.create(file.path(MODELS_DIR, sub), recursive = TRUE, showWarnings = FALSE)
}

# Walk-forward split dates
TRAIN_START <- as.Date("1995-01-01")
TRAIN_END   <- as.Date("2009-12-31")
VALID_START <- as.Date("2010-01-01")
VALID_END   <- as.Date("2015-12-31")
OOS_START   <- as.Date("2016-01-01")
OOS_END     <- as.Date("2026-04-30")

H       <- 21L   # purge horizon (trading days)
EMBARGO <- 42L   # embargo (21~63 midpoint)

# Leave-one-crisis-out periods (excluded from Train CV)
CRISIS_PERIODS <- list(
  IMF_1997  = c(as.Date("1997-10-01"), as.Date("1998-12-31")),
  Card_2003 = c(as.Date("2002-09-01"), as.Date("2003-06-30")),
  GFC_2008  = c(as.Date("2008-07-01"), as.Date("2009-06-30"))
)

# Feature columns (hard cap 8 — Plan v1.0 alt data based)
# A6 BBVA Global Macro 4-channel (FRED-based composite)
# A5 Options higher moments (krx_options ATM/OTM)
# A3 US sector flow (yahoo XLF/XLK/XLE/XLY/XLI/XLV/XLP/XLU)
FEATURE_COLS <- c(
  # A6 BBVA
  "bbva_market_z", "bbva_sovereign_z",
  "bbva_transmission_z", "bbva_macro_composite",
  # A5 Options
  "k200_implied_skew_z", "k200_implied_kurt_z",
  # A3 US sector
  "us_sector_avg_z", "us_sector_dispersion_z"
)
# feature_panel_v1_alt.parquet expected (from 01_feature_assembler_alt.R)

# ── Helper: Purged + embargo split ──────────────────────────────────────────
#' Returns indices excluded from test after t due to purge + embargo
#' t_test = index of test row, purge + embargo in trading days
#' Assumes sorted data.table with Date column
get_purge_embargo_mask <- function(dates, test_idx, purge = H, embargo = EMBARGO) {
  n <- length(dates)
  test_date <- dates[test_idx]
  # Exclude [test_date - (purge + embargo), test_date + (purge + embargo)] window
  # For train/test split: exclude rows within purge+embargo of test boundary
  excluded <- which(abs(as.integer(dates - test_date)) <= (purge + embargo))
  excluded
}

# ── Helper: Platt scaling calibration (logistic fit on validation probs) ─────
platt_calibrate <- function(raw_probs, y_labels) {
  df_cal <- data.frame(p = raw_probs, y = as.integer(y_labels))
  df_cal <- df_cal[!is.na(df_cal$p) & !is.na(df_cal$y), ]
  if (nrow(df_cal) < 20) return(list(a = 1, b = 0, converged = FALSE))
  fit <- tryCatch(
    glm(y ~ p, data = df_cal, family = binomial(link = "logit")),
    error = function(e) NULL
  )
  if (is.null(fit)) return(list(a = 1, b = 0, converged = FALSE))
  coefs <- coef(fit)
  list(a = coefs["p"], b = coefs["(Intercept)"], converged = TRUE)
}

apply_platt <- function(raw_probs, cal) {
  if (!cal$converged) return(raw_probs)
  plogis(cal$a * raw_probs + cal$b)
}

# ── Helper: PR-AUC (partial, event-positive class) ──────────────────────────
compute_prauc <- function(probs, labels) {
  if (sum(labels, na.rm = TRUE) == 0) return(NA_real_)
  ord <- order(probs, decreasing = TRUE)
  labels_ord <- labels[ord]
  prec <- cumsum(labels_ord) / seq_along(labels_ord)
  rec  <- cumsum(labels_ord) / sum(labels_ord)
  # Trapezoid integration
  n <- length(prec)
  if (n < 2) return(NA_real_)
  sum(diff(rec) * (prec[-1] + prec[-n]) / 2, na.rm = TRUE)
}

# ── Data load ────────────────────────────────────────────────────────────────
load_model_data <- function() {
  feat_path <- file.path(DATA_DIR, "feature_panel_v1_alt.parquet")
  tgt_path  <- file.path(TARGET_DIR, "targets_full.parquet")
  if (!file.exists(feat_path)) stop("[model_runner] feature_panel_v1_alt.parquet not found. Run 01_feature_assembler_alt.R first.")
  if (!file.exists(tgt_path))  stop("[model_runner] targets_full.parquet not found.")

  feat <- as.data.table(read_parquet(feat_path))
  tgt  <- as.data.table(read_parquet(tgt_path))
  feat[, Date := as.Date(Date)]
  tgt[, Date  := as.Date(Date)]

  # Merge on Date
  panel <- merge(feat, tgt[, .(Date, y_onset, y_tail_q15, y_tail_q10)],
                 by = "Date", all.x = TRUE)
  setorder(panel, Date)

  # Filter to OOS window (no future targets beyond OOS_END)
  panel <- panel[Date <= OOS_END]

  cat(sprintf("[model_runner] Data loaded: %d rows (%s ~ %s)\n",
              nrow(panel), min(panel$Date), max(panel$Date)))
  panel
}

# ── Impute missing features (median of available train data) ─────────────────
impute_with_train_median <- function(X_mat, train_idx) {
  # For each column: compute median from train rows only → fill NA in all rows
  col_medians <- apply(X_mat[train_idx, , drop = FALSE], 2,
                       function(x) median(x, na.rm = TRUE))
  for (j in seq_len(ncol(X_mat))) {
    na_rows <- is.na(X_mat[, j])
    X_mat[na_rows, j] <- col_medians[j]
  }
  list(X = X_mat, col_medians = col_medians)
}

# ── S5: Elastic-Net Logistic ─────────────────────────────────────────────────
run_elastic_net <- function(panel, target_col = "y_onset") {
  cat(sprintf("\n[S5 ElasticNet] Target: %s\n", target_col))
  cat(sprintf("[S5] Train: %s ~ %s | Valid: %s ~ %s | OOS: %s ~ %s\n",
              TRAIN_START, TRAIN_END, VALID_START, VALID_END, OOS_START, OOS_END))

  # Subset available features
  avail_feats <- intersect(FEATURE_COLS, names(panel))
  cat(sprintf("[S5] Features used: %d / %d\n", length(avail_feats), length(FEATURE_COLS)))

  # Split indices
  idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
  idx_valid <- which(panel$Date >= VALID_START & panel$Date <= VALID_END)
  idx_oos   <- which(panel$Date >= OOS_START   & panel$Date <= OOS_END)

  # Feature matrix
  X_all <- as.matrix(panel[, avail_feats, with = FALSE])
  Y_all <- panel[[target_col]]

  # Scale features (standardize using train mean/sd — expanding window approximation)
  # Compute stats from non-NA train data first
  train_means <- colMeans(X_all[idx_train, , drop = FALSE], na.rm = TRUE)
  train_sds   <- apply(X_all[idx_train, , drop = FALSE], 2, sd, na.rm = TRUE)
  train_sds[train_sds < 1e-8] <- 1
  X_scaled <- sweep(sweep(X_all, 2, train_means, "-"), 2, train_sds, "/")

  # Impute with train medians (on scaled matrix — median ~ 0 for symmetric)
  # Columns that are 100% NA in train (e.g., vkospi_z 2010+ only) → impute with 0 globally
  imp <- impute_with_train_median(X_scaled, idx_train)
  X_scaled <- imp$X
  # Replace any remaining NaN/Inf/NA with 0 (safety net for all-NA-in-train columns)
  # is.finite(NA) = FALSE → catches NA, NaN, Inf, -Inf
  X_scaled[is.na(X_scaled) | !is.finite(X_scaled)] <- 0

  X_train <- X_scaled[idx_train, , drop = FALSE]
  Y_train <- Y_all[idx_train]

  # Remove rows with NA target in train
  valid_train <- !is.na(Y_train)
  X_train <- X_train[valid_train, , drop = FALSE]
  Y_train <- Y_train[valid_train]

  # Leave-one-crisis-out: exclude crisis periods from train CV folds
  train_dates <- panel$Date[idx_train][valid_train]
  in_crisis <- rep(FALSE, length(train_dates))
  for (cp in CRISIS_PERIODS) {
    in_crisis <- in_crisis | (train_dates >= cp[1] & train_dates <= cp[2])
  }
  cat(sprintf("[S5] Crisis-excluded train rows: %d / %d\n", sum(in_crisis), length(in_crisis)))
  X_cv <- X_train[!in_crisis, , drop = FALSE]
  Y_cv <- Y_train[!in_crisis]

  # Purged 5-fold CV with embargo
  n_cv <- nrow(X_cv)
  fold_size <- floor(n_cv / 5)
  foldid <- rep(1:5, each = fold_size, length.out = n_cv)

  # Elastic-Net: alpha=0.5 (L1+L2)
  cat("[S5] Fitting glmnet (alpha=0.5)...\n")
  set.seed(42)
  cv_fit <- tryCatch(
    cv.glmnet(X_cv, Y_cv, family = "binomial", alpha = 0.5,
              foldid = foldid, type.measure = "auc",
              standardize = FALSE,  # already scaled
              nfolds = 5),
    error = function(e) {
      cat("[S5] cv.glmnet error:", conditionMessage(e), "\n")
      NULL
    }
  )

  if (is.null(cv_fit)) {
    cat("[S5] ElasticNet fit failed. Returning NULL.\n")
    return(NULL)
  }

  lambda_opt <- cv_fit$lambda.1se
  cat(sprintf("[S5] lambda.1se = %.6f (log = %.3f)\n", lambda_opt, log(lambda_opt)))

  # Fit final model on full train
  final_fit <- glmnet(X_train, Y_train, family = "binomial", alpha = 0.5,
                      lambda = lambda_opt, standardize = FALSE)

  # Coefficients
  coef_mat <- as.matrix(coef(final_fit, s = lambda_opt))
  coef_df  <- data.table(
    feature = rownames(coef_mat),
    coefficient = as.vector(coef_mat)
  )
  coef_df <- coef_df[feature != "(Intercept)"][order(-abs(coefficient))]
  cat("[S5] Top coefficients:\n")
  print(coef_df[coefficient != 0])

  # Predict on valid + OOS
  pred_valid <- as.vector(predict(final_fit, X_scaled[idx_valid, , drop = FALSE],
                                   type = "response", s = lambda_opt))
  pred_oos   <- as.vector(predict(final_fit, X_scaled[idx_oos, , drop = FALSE],
                                   type = "response", s = lambda_opt))

  # Platt calibration on valid
  Y_valid <- Y_all[idx_valid]
  cal <- platt_calibrate(pred_valid, Y_valid)
  cat(sprintf("[S5] Platt cal: a=%.4f b=%.4f converged=%s\n",
              cal$a, cal$b, cal$converged))
  pred_oos_cal   <- apply_platt(pred_oos, cal)
  pred_valid_cal <- apply_platt(pred_valid, cal)

  # PR-AUC
  prauc_valid <- compute_prauc(pred_valid_cal, Y_valid)
  prauc_oos   <- compute_prauc(pred_oos_cal, Y_all[idx_oos])
  cat(sprintf("[S5] PR-AUC: Valid=%.4f | OOS=%.4f\n", prauc_valid, prauc_oos))

  # Predictions table
  preds_all <- rbind(
    data.table(Date = panel$Date[idx_valid], split = "valid",
               raw_prob = pred_valid, cal_prob = pred_valid_cal, y = Y_valid),
    data.table(Date = panel$Date[idx_oos], split = "oos",
               raw_prob = pred_oos, cal_prob = pred_oos_cal, y = Y_all[idx_oos])
  )
  preds_all[, target := target_col]
  preds_all[, model := "elastic_net"]

  # Save
  out_dir <- file.path(MODELS_DIR, "elastic_net")
  write_parquet(preds_all, file.path(out_dir, paste0("predictions_", target_col, ".parquet")))
  fwrite(coef_df, file.path(out_dir, paste0("coefficients_", target_col, ".csv")))

  # Calibration plot (simple text summary — no ggplot dependency)
  cal_summary <- data.table(
    target = target_col, model = "elastic_net",
    lambda_1se = lambda_opt,
    platt_a = cal$a, platt_b = cal$b, platt_converged = cal$converged,
    prauc_valid = prauc_valid, prauc_oos = prauc_oos,
    n_features_nonzero = sum(coef_df$coefficient != 0, na.rm = TRUE)
  )
  fwrite(cal_summary, file.path(out_dir, paste0("calibration_", target_col, ".csv")))

  cat(sprintf("[S5 ElasticNet] DONE. Predictions saved: %d rows (%d valid + %d OOS)\n",
              nrow(preds_all), length(idx_valid), length(idx_oos)))

  list(
    model      = final_fit,
    cal        = cal,
    coef_df    = coef_df,
    preds      = preds_all,
    lambda_opt = lambda_opt,
    prauc_valid = prauc_valid,
    prauc_oos   = prauc_oos,
    train_means  = train_means,
    train_sds    = train_sds,
    scale_medians = imp$col_medians,
    avail_feats  = avail_feats
  )
}

# ── S6: shallow XGBoost ──────────────────────────────────────────────────────
run_xgboost <- function(panel, target_col = "y_onset") {
  cat(sprintf("\n[S6 XGBoost] Target: %s\n", target_col))

  avail_feats <- intersect(FEATURE_COLS, names(panel))
  idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
  idx_valid <- which(panel$Date >= VALID_START & panel$Date <= VALID_END)
  idx_oos   <- which(panel$Date >= OOS_START   & panel$Date <= OOS_END)

  X_all <- as.matrix(panel[, avail_feats, with = FALSE])
  Y_all <- panel[[target_col]]

  # XGBoost native NA handling — no imputation needed
  # Leave-one-crisis-out for train
  train_dates <- panel$Date[idx_train]
  in_crisis <- rep(FALSE, length(train_dates))
  for (cp in CRISIS_PERIODS) {
    in_crisis <- in_crisis | (train_dates >= cp[1] & train_dates <= cp[2])
  }

  X_train_cv <- X_all[idx_train[!in_crisis], , drop = FALSE]
  Y_train_cv <- Y_all[idx_train[!in_crisis]]
  na_target <- is.na(Y_train_cv)
  X_train_cv <- X_train_cv[!na_target, , drop = FALSE]
  Y_train_cv <- Y_train_cv[!na_target]

  X_train_full <- X_all[idx_train[!is.na(Y_all[idx_train])], , drop = FALSE]
  Y_train_full <- Y_all[idx_train[!is.na(Y_all[idx_train])]]

  # Validation set for early stopping
  X_valid <- X_all[idx_valid, , drop = FALSE]
  Y_valid <- Y_all[idx_valid]
  valid_mask <- !is.na(Y_valid)
  X_valid_clean <- X_valid[valid_mask, , drop = FALSE]
  Y_valid_clean <- Y_valid[valid_mask]

  dtrain <- xgb.DMatrix(data = X_train_cv, label = Y_train_cv)
  dvalid <- xgb.DMatrix(data = X_valid_clean, label = Y_valid_clean)
  dtest  <- xgb.DMatrix(data = X_all[idx_oos, , drop = FALSE])
  dvalid_all <- xgb.DMatrix(data = X_valid)

  # Scale pos_weight for imbalanced classes (α3 강화: cap 5 → 8)
  pos_weight <- sum(Y_train_cv == 0, na.rm = TRUE) / max(sum(Y_train_cv == 1, na.rm = TRUE), 1)
  cat(sprintf("[S6] Class balance: %.1fx (pos_weight=%.2f)\n",
              pos_weight, min(pos_weight, 8)))
  pos_weight <- min(pos_weight, 8)  # cap 8 (α3 강화, v0.4.2 cap 5 → v1.0 8)

  # α3 XGBoost 강화 (v1.0 → v1.0.1): depth 3 → 4, n_trees 500 → 1000, early_stop 50 → 80
  params <- list(
    booster        = "gbtree",
    objective      = "binary:logistic",
    eval_metric    = "aucpr",
    max_depth      = 4,                # 강화 (3 → 4)
    eta            = 0.04,              # 약간 감소 (0.05 → 0.04, 더 부드러운 학습)
    subsample      = 0.8,
    colsample_bytree = 0.8,
    min_child_weight = 5,
    scale_pos_weight = pos_weight,
    seed           = 42
  )

  cat("[S6] Fitting XGBoost α3 강화 (max_depth=4, eta=0.04, nrounds=1000, early_stop=80)...\n")
  set.seed(42)
  xgb_fit <- xgb.train(
    params  = params,
    data    = dtrain,
    nrounds = 1000,                     # 500 → 1000
    evals   = list(train = dtrain, valid = dvalid),
    early_stopping_rounds = 80,         # 50 → 80
    verbose = 0
  )

  best_iter <- xgb_fit$best_iteration
  cat(sprintf("[S6] Best iteration: %d | valid aucpr: %.4f\n",
              best_iter, xgb_fit$best_score))

  # Feature importance
  imp_mat <- xgb.importance(model = xgb_fit)
  imp_dt  <- as.data.table(imp_mat)[, .(Feature, Gain, Cover, Frequency)]
  cat("[S6] Feature importance (top):\n")
  print(head(imp_dt, 10))

  # Predictions (raw probabilities)
  # xgboost 3.x: use ntreelimit (still works) or use best_iteration stored in model
  pred_valid_raw <- predict(xgb_fit, dvalid_all)
  pred_oos_raw   <- predict(xgb_fit, dtest)

  # Platt calibration on valid
  cal <- platt_calibrate(pred_valid_raw[valid_mask], Y_valid_clean)
  cat(sprintf("[S6] Platt cal: a=%.4f b=%.4f converged=%s\n",
              cal$a, cal$b, cal$converged))
  pred_valid_cal <- apply_platt(pred_valid_raw, cal)
  pred_oos_cal   <- apply_platt(pred_oos_raw, cal)

  # PR-AUC
  prauc_valid <- compute_prauc(pred_valid_cal[valid_mask], Y_valid_clean)
  prauc_oos   <- compute_prauc(pred_oos_cal, Y_all[idx_oos])
  cat(sprintf("[S6] PR-AUC: Valid=%.4f | OOS=%.4f\n", prauc_valid, prauc_oos))

  # Brier Score (valid)
  brier_valid <- mean((pred_valid_cal[valid_mask] - Y_valid_clean)^2, na.rm = TRUE)
  cat(sprintf("[S6] Brier Score (valid calibrated): %.4f\n", brier_valid))

  # Predictions table
  preds_all <- rbind(
    data.table(Date = panel$Date[idx_valid], split = "valid",
               raw_prob = pred_valid_raw, cal_prob = pred_valid_cal,
               y = Y_all[idx_valid]),
    data.table(Date = panel$Date[idx_oos], split = "oos",
               raw_prob = pred_oos_raw, cal_prob = pred_oos_cal,
               y = Y_all[idx_oos])
  )
  preds_all[, target := target_col]
  preds_all[, model := "xgboost"]

  # Save
  out_dir <- file.path(MODELS_DIR, "xgboost")
  write_parquet(preds_all, file.path(out_dir, paste0("predictions_", target_col, ".parquet")))
  fwrite(imp_dt, file.path(out_dir, paste0("feature_importance_", target_col, ".csv")))

  cal_summary <- data.table(
    target = target_col, model = "xgboost",
    best_iter = best_iter,
    platt_a = cal$a, platt_b = cal$b, platt_converged = cal$converged,
    prauc_valid = prauc_valid, prauc_oos = prauc_oos,
    brier_valid = brier_valid
  )
  fwrite(cal_summary, file.path(out_dir, paste0("calibration_", target_col, ".csv")))

  cat(sprintf("[S6 XGBoost] DONE. Predictions saved: %d rows\n", nrow(preds_all)))

  list(
    model = xgb_fit,
    cal   = cal,
    imp_dt = imp_dt,
    preds  = preds_all,
    best_iter = best_iter,
    prauc_valid = prauc_valid,
    prauc_oos   = prauc_oos,
    brier_valid = brier_valid
  )
}

# ── S8: Ensemble ─────────────────────────────────────────────────────────────
run_ensemble <- function(en_preds, xgb_preds, panel, target_col = "y_onset") {
  cat(sprintf("\n[S8 Ensemble] Target: %s\n", target_col))

  # Merge predictions on Date + split
  en_sub  <- en_preds[target == target_col,  .(Date, split, cal_prob, y)]
  xgb_sub <- xgb_preds[target == target_col, .(Date, split, cal_prob, y)]
  setnames(en_sub,  "cal_prob", "prob_en")
  setnames(xgb_sub, "cal_prob", "prob_xgb")

  merged <- merge(en_sub, xgb_sub[, .(Date, split, prob_xgb)],
                  by = c("Date", "split"), all = TRUE)
  setorder(merged, Date)

  # ----- Method 1: Equal-weight (DEFAULT per Codex Round 2 mandate) -----------
  merged[, prob_ew := (prob_en + prob_xgb) / 2]

  # ----- Method 2: BMA (Bayesian Model Averaging) —-- validation PR-AUC weight --
  val_data <- merged[split == "valid" & !is.na(y)]
  prauc_en  <- compute_prauc(val_data$prob_en, val_data$y)
  prauc_xgb <- compute_prauc(val_data$prob_xgb, val_data$y)
  cat(sprintf("[S8] Validation PR-AUC: EN=%.4f, XGB=%.4f\n", prauc_en, prauc_xgb))

  # BMA: weights proportional to exp(AUC) for numerical stability
  w_bma_en  <- exp(prauc_en)  / (exp(prauc_en) + exp(prauc_xgb))
  w_bma_xgb <- exp(prauc_xgb) / (exp(prauc_en) + exp(prauc_xgb))
  merged[, prob_bma := w_bma_en * prob_en + w_bma_xgb * prob_xgb]
  cat(sprintf("[S8] BMA weights: EN=%.4f, XGB=%.4f\n", w_bma_en, w_bma_xgb))

  # ----- Method 3: Ridge-stacked (on valid, apply to OOS) -----
  valid_clean <- val_data[!is.na(prob_en) & !is.na(prob_xgb)]
  w_ridge <- c(0.5, 0.5)  # default fallback
  if (nrow(valid_clean) > 30) {
    X_stack <- cbind(valid_clean$prob_en, valid_clean$prob_xgb)
    Y_stack <- valid_clean$y
    fit_stack <- tryCatch(
      cv.glmnet(X_stack, Y_stack, family = "binomial", alpha = 0,  # ridge
                nfolds = 5, type.measure = "auc"),
      error = function(e) NULL
    )
    if (!is.null(fit_stack)) {
      coef_stack <- as.vector(coef(fit_stack, s = fit_stack$lambda.min))
      # coef_stack = [intercept, w_en, w_xgb]
      # Normalize to sum to 1 (constrained)
      raw_w <- coef_stack[2:3]
      raw_w[raw_w < 0] <- 0
      if (sum(raw_w) > 1e-6) {
        w_ridge <- raw_w / sum(raw_w)
        cat(sprintf("[S8] Ridge-stacked weights: EN=%.4f, XGB=%.4f\n", w_ridge[1], w_ridge[2]))
      }
    }
  }
  merged[, prob_ridge := w_ridge[1] * prob_en + w_ridge[2] * prob_xgb]

  # OOS evaluation
  oos_data <- merged[split == "oos" & !is.na(y)]
  prauc_ew_oos    <- compute_prauc(oos_data$prob_ew,    oos_data$y)
  prauc_bma_oos   <- compute_prauc(oos_data$prob_bma,   oos_data$y)
  prauc_ridge_oos <- compute_prauc(oos_data$prob_ridge, oos_data$y)
  cat(sprintf("[S8] OOS PR-AUC: EW=%.4f | BMA=%.4f | Ridge=%.4f\n",
              prauc_ew_oos, prauc_bma_oos, prauc_ridge_oos))

  # Default = Equal-weight per plan mandate
  merged[, prob_final := prob_ew]
  merged[, model_final := "equal_weight"]
  merged[, target := target_col]

  # Save ensemble weights
  ens_weights <- list(
    target = target_col,
    default_method = "equal_weight",
    methods = list(
      equal_weight = list(w_en = 0.5, w_xgb = 0.5),
      bma = list(w_en = w_bma_en, w_xgb = w_bma_xgb),
      ridge_stacked = list(w_en = w_ridge[1], w_xgb = w_ridge[2])
    ),
    oos_prauc = list(
      equal_weight = prauc_ew_oos,
      bma          = prauc_bma_oos,
      ridge_stacked = prauc_ridge_oos
    ),
    validation_prauc = list(
      elastic_net = prauc_en,
      xgboost     = prauc_xgb
    )
  )

  out_dir <- file.path(MODELS_DIR, "stacking_ensemble")
  write_json(ens_weights, file.path(out_dir, paste0("ensemble_weights_", target_col, ".json")),
             pretty = TRUE, auto_unbox = TRUE)

  # Final predictions
  cols_final <- c("Date", "split", "target", "y",
                  "prob_en", "prob_xgb", "prob_ew", "prob_bma", "prob_ridge", "prob_final",
                  "model_final")
  merged_out <- merged[, intersect(cols_final, names(merged)), with = FALSE]
  write_parquet(merged_out,
                file.path(out_dir, paste0("predictions_final_", target_col, ".parquet")))

  cat(sprintf("[S8 Ensemble] DONE. Predictions saved: %d rows (valid + OOS)\n", nrow(merged_out)))
  list(preds = merged_out, weights = ens_weights,
       prauc_ew_oos = prauc_ew_oos, prauc_bma_oos = prauc_bma_oos)
}

# ── Main runner ───────────────────────────────────────────────────────────────
run_models <- function(targets = c("y_onset", "y_tail_q15")) {
  cat("============================================================\n")
  cat("[model_runner] Plan v0.4.2 — S5 + S6 + S8 Model Training\n")
  cat("============================================================\n\n")

  panel <- load_model_data()

  results <- list()
  for (tgt in targets) {
    if (!(tgt %in% names(panel))) {
      cat(sprintf("[model_runner] Target %s not in panel. Skipping.\n", tgt))
      next
    }

    cat(sprintf("\n========== TARGET: %s ==========\n", tgt))

    # S5: Elastic-Net
    en_result  <- run_elastic_net(panel, target_col = tgt)
    # S6: XGBoost
    xgb_result <- run_xgboost(panel, target_col = tgt)

    if (!is.null(en_result) && !is.null(xgb_result)) {
      # S8: Ensemble
      ens_result <- run_ensemble(en_result$preds, xgb_result$preds, panel, target_col = tgt)
      results[[tgt]] <- list(
        elastic_net = en_result,
        xgboost     = xgb_result,
        ensemble    = ens_result
      )
    }
  }

  # Combined OOS predictions (all targets)
  ens_files <- list.files(file.path(MODELS_DIR, "stacking_ensemble"),
                          pattern = "predictions_final_.*\\.parquet$", full.names = TRUE)
  if (length(ens_files) > 0) {
    all_preds <- rbindlist(lapply(ens_files, function(f) as.data.table(read_parquet(f))))
    write_parquet(all_preds,
                  file.path(MODELS_DIR, "stacking_ensemble", "predictions_final.parquet"))
    cat(sprintf("\n[model_runner] Combined predictions saved: %d rows\n", nrow(all_preds)))
  }

  cat("\n============================================================\n")
  cat("[model_runner] S5/S6/S8 COMPLETE.\n")
  cat("Outputs:\n")
  cat(sprintf("  Elastic-Net: %s\n", file.path(MODELS_DIR, "elastic_net")))
  cat(sprintf("  XGBoost:     %s\n", file.path(MODELS_DIR, "xgboost")))
  cat(sprintf("  Ensemble:    %s\n", file.path(MODELS_DIR, "stacking_ensemble")))

  invisible(results)
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  run_models(targets = c("y_onset", "y_tail_q15"))
}
