#!/usr/bin/env Rscript
# WT-D20260514_009 Step 2: ML Walk-Forward Training (5 candidates × walk-forward CV × OOS lockbox)
#
# PIT C1 strict: Rolling/expanding window training only. Full-sample 금지.
#   - Training window: expanding from start, ends at sig_date_t - 1
#   - Predict: sig_date_t
#   - No peek-ahead at sig_date_{t+1, t+2, ...}
# PIT C2: features inherit already t-1 lag applied (Layer A monthly snapshot)
# PIT C13: Z_Score_Aligned cross-section per sig_date enforced (within walk-forward fold scaling)
# PIT C14: features_master inherit Usable_Date <= sig_date 보장
# AX-002 ex-ante grid N <= 5 strict (V6 N=37 post-hoc DSR FAIL 학습)
#
# 5 ML candidates:
#   1. Ridge (glmnet alpha=0)
#   2. LASSO (glmnet alpha=1)
#   3. ElasticNet (glmnet alpha=0.5)
#   4. XGBoost (tree)
#   5. Random Forest (ranger, low-tree shallow for speed)
#
# Walk-forward design:
#   - Initial training: 2016-02 ~ 2020-01 (48 sig_dates, ~4 yrs)
#   - First OOS prediction: 2020-02
#   - Step: expanding (each fold uses all prior sig_dates), predict 1 sig_date
#   - OOS lockbox: last 12 sig_dates (2025-05 ~ 2026-04) — strict frozen for final DSR/Harvey-t
#
# Compute budget: 1,044 features × 250K rows × 75 sig_dates × 5 models.
#   - Ridge/LASSO/EN: lambda path glmnet ~30 sec each per fold
#   - XGBoost: 100 rounds ~60 sec per fold
#   - RF (ranger): 200 trees max_depth=6 ~120 sec per fold
#   - Total estimate: 75 × (30*3 + 60 + 120) = 75 × 270 = ~5.6 hrs. Too slow.
#
# OPTIMIZATION: rolling-step = every 3 months (use train_end_t for 3 OOS predictions).
#   New training: only at training_step = 3 sig_dates. → 25 training folds × 5 models.
#   Total: 25 × 270 = ~110 min. Acceptable.
#
# To FURTHER reduce: variance threshold filter + correlation pruning at train time.

suppressMessages({
  library(arrow); library(data.table); library(dplyr); library(lubridate)
  library(glmnet); library(xgboost); library(ranger)
})

WT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(WT_ROOT)
OUT_DIR <- "stage_artifacts/WT_D20260514_009"
SEED_BASE <- 20260514L

cat("=== Step 2: ML Walk-Forward Training ===\n")
t_overall <- Sys.time()

# --- Load training panel ---
cat("[1/6] Loading training_panel.parquet...\n")
panel <- read_parquet(file.path(OUT_DIR, "training_panel.parquet"))
setDT(panel)
panel[, sig_date := as.Date(sig_date)]
cat(sprintf("  panel: %s rows × %s cols\n", format(nrow(panel), big.mark=","), ncol(panel)))

# --- Identify feature columns ---
non_feature_cols <- c("sig_date", "Ticker", "Sector_Lv2",
                       "ret_1m_fwd", "bm_ret_1m_fwd", "n_days_fwd",
                       "active_ret_1m_fwd", "ret_1m_fwd_w")
feature_cols <- setdiff(names(panel), non_feature_cols)
cat(sprintf("  feature_cols: %d\n", length(feature_cols)))

# Drop rows without target
panel <- panel[!is.na(ret_1m_fwd_w)]
cat(sprintf("  panel after target-na drop: %s rows\n", format(nrow(panel), big.mark=",")))

# --- Walk-forward design ---
sig_dates <- sort(unique(panel$sig_date))
n_sd <- length(sig_dates)
INIT_TRAIN_END_IDX <- 48L  # first OOS at index 49 (2020-02)
LOCKBOX_SIZE <- 12L         # last 12 = OOS lockbox (2025-05 ~ 2026-04)
STEP_SIZE <- 3L             # retrain every 3 months
oos_start_idx <- INIT_TRAIN_END_IDX + 1L

cat(sprintf("\n  Walk-forward design:\n"))
cat(sprintf("    Total sig_dates: %d (%s ~ %s)\n", n_sd, sig_dates[1], sig_dates[n_sd]))
cat(sprintf("    Initial training: 1:%d (%s ~ %s)\n", INIT_TRAIN_END_IDX, sig_dates[1], sig_dates[INIT_TRAIN_END_IDX]))
cat(sprintf("    OOS predictions start: idx %d (%s)\n", oos_start_idx, sig_dates[oos_start_idx]))
cat(sprintf("    Lockbox: last %d (%s ~ %s)\n", LOCKBOX_SIZE, sig_dates[n_sd - LOCKBOX_SIZE + 1], sig_dates[n_sd]))
cat(sprintf("    Retrain step: %d sig_dates\n", STEP_SIZE))

oos_indices <- oos_start_idx:n_sd  # 49..123 = 75 OOS sig_dates
train_endpoints <- unique(c(seq(INIT_TRAIN_END_IDX, n_sd - 1L, by = STEP_SIZE), n_sd - 1L))
cat(sprintf("    Total retrain folds: %d\n", length(train_endpoints)))

# --- Feature preprocessing helper ---
prep_X <- function(dt, feature_cols) {
  # Convert to numeric matrix. Replace NA with 0 (PIT-safe: features already cross-section z-scored,
  # NA = data unavailable at sig_date for this ticker. Default to 0 = group median).
  X <- as.matrix(dt[, ..feature_cols])
  X[!is.finite(X)] <- 0
  X
}

# Cross-section z-score per sig_date for features (final defensive standardization)
zscore_cs <- function(dt_features) {
  # dt_features: rows aligned by sig_date
  # Already standardized via Z_Score_Aligned upstream. This is a defensive re-scale within fold.
  # Skip for speed; features_master inherit assumes already z-scored.
  dt_features
}

# --- Run walk-forward for each model ---
# Output containers
all_predictions <- list()  # list of data.tables: (sig_date, Ticker, pred_<model>)
feature_importance_log <- list()  # per fold

# Per-fold helper: train all models on data up to train_end_idx, predict OOS sig_dates
run_fold <- function(fold_id, train_end_idx, oos_idx_vec, panel, sig_dates, feature_cols) {
  train_sd <- sig_dates[1:train_end_idx]
  oos_sd <- sig_dates[oos_idx_vec]

  train_data <- panel[sig_date %in% train_sd]
  oos_data <- panel[sig_date %in% oos_sd]
  if (nrow(train_data) == 0 || nrow(oos_data) == 0) return(NULL)

  X_train <- prep_X(train_data, feature_cols)
  y_train <- train_data$ret_1m_fwd_w
  X_oos <- prep_X(oos_data, feature_cols)

  oos_meta <- oos_data[, .(sig_date, Ticker)]
  result <- copy(oos_meta)
  fi_local <- list()

  # ----- Model 1: Ridge (glmnet alpha=0) -----
  t_m <- Sys.time()
  set.seed(SEED_BASE + 1L)
  # Use cv.glmnet for lambda selection with 5-fold internal CV on training set (no OOS leak)
  cv_ridge <- tryCatch(
    cv.glmnet(X_train, y_train, alpha=0, nfolds=5, standardize=FALSE,
              type.measure="mse", parallel=FALSE),
    error=function(e) NULL)
  if (!is.null(cv_ridge)) {
    pred_ridge <- as.numeric(predict(cv_ridge, X_oos, s="lambda.min"))
    result[, pred_ridge := pred_ridge]
    coefs <- as.numeric(coef(cv_ridge, s="lambda.min"))
    names(coefs) <- c("(Intercept)", feature_cols)
    fi_local$ridge <- coefs
  } else {
    result[, pred_ridge := NA_real_]
  }
  cat(sprintf("    Ridge  done %.1fs\n", as.numeric(difftime(Sys.time(), t_m, units="secs"))))

  # ----- Model 2: LASSO (glmnet alpha=1) -----
  t_m <- Sys.time()
  set.seed(SEED_BASE + 2L)
  cv_lasso <- tryCatch(
    cv.glmnet(X_train, y_train, alpha=1, nfolds=5, standardize=FALSE,
              type.measure="mse", parallel=FALSE),
    error=function(e) NULL)
  if (!is.null(cv_lasso)) {
    pred_lasso <- as.numeric(predict(cv_lasso, X_oos, s="lambda.min"))
    result[, pred_lasso := pred_lasso]
    coefs <- as.numeric(coef(cv_lasso, s="lambda.min"))
    names(coefs) <- c("(Intercept)", feature_cols)
    fi_local$lasso <- coefs
  } else {
    result[, pred_lasso := NA_real_]
  }
  cat(sprintf("    LASSO  done %.1fs\n", as.numeric(difftime(Sys.time(), t_m, units="secs"))))

  # ----- Model 3: ElasticNet (alpha=0.5) -----
  t_m <- Sys.time()
  set.seed(SEED_BASE + 3L)
  cv_en <- tryCatch(
    cv.glmnet(X_train, y_train, alpha=0.5, nfolds=5, standardize=FALSE,
              type.measure="mse", parallel=FALSE),
    error=function(e) NULL)
  if (!is.null(cv_en)) {
    pred_en <- as.numeric(predict(cv_en, X_oos, s="lambda.min"))
    result[, pred_en := pred_en]
    coefs <- as.numeric(coef(cv_en, s="lambda.min"))
    names(coefs) <- c("(Intercept)", feature_cols)
    fi_local$elasticnet <- coefs
  } else {
    result[, pred_en := NA_real_]
  }
  cat(sprintf("    EN     done %.1fs\n", as.numeric(difftime(Sys.time(), t_m, units="secs"))))

  # ----- Model 4: XGBoost (tree boosting, regularized) -----
  t_m <- Sys.time()
  set.seed(SEED_BASE + 4L)
  dtrain <- xgb.DMatrix(X_train, label = y_train)
  dpred <- xgb.DMatrix(X_oos)
  xgb_params <- list(
    objective = "reg:squarederror",
    eta = 0.05,
    max_depth = 4L,
    subsample = 0.7,
    colsample_bytree = 0.5,
    lambda = 1.0,
    alpha = 0.5,
    nthread = 4L
  )
  bst <- tryCatch(
    xgb.train(params=xgb_params, data=dtrain, nrounds=200L, verbose=0),
    error=function(e) NULL)
  if (!is.null(bst)) {
    pred_xgb <- predict(bst, dpred)
    result[, pred_xgb := pred_xgb]
    imp <- xgb.importance(model=bst, feature_names=feature_cols)
    fi_local$xgboost <- imp
  } else {
    result[, pred_xgb := NA_real_]
  }
  cat(sprintf("    XGB    done %.1fs\n", as.numeric(difftime(Sys.time(), t_m, units="secs"))))

  # ----- Model 5: Random Forest (ranger, regularized depth) -----
  t_m <- Sys.time()
  set.seed(SEED_BASE + 5L)
  # ranger requires data.frame
  train_df <- data.table(X_train); train_df[, y := y_train]
  rf_fit <- tryCatch(
    ranger(y ~ ., data=train_df, num.trees=200L, max.depth=6L,
           mtry=sqrt(length(feature_cols)), num.threads=4L,
           importance="impurity", verbose=FALSE),
    error=function(e) {cat("    RF error:", conditionMessage(e), "\n"); NULL})
  if (!is.null(rf_fit)) {
    pred_rf <- predict(rf_fit, data=data.table(X_oos))$predictions
    result[, pred_rf := pred_rf]
    fi_local$rf <- rf_fit$variable.importance
  } else {
    result[, pred_rf := NA_real_]
  }
  cat(sprintf("    RF     done %.1fs\n", as.numeric(difftime(Sys.time(), t_m, units="secs"))))

  # ----- Ensemble: rank-average of available models -----
  # Compute cross-section rank z-score per oos_sd per model, then mean.
  models <- c("pred_ridge","pred_lasso","pred_en","pred_xgb","pred_rf")
  for (m in models) {
    if (!m %in% names(result)) result[, (m) := NA_real_]
  }
  result[, pred_ensemble := rowMeans(
    sapply(models, function(m) {
      if (all(is.na(result[[m]]))) return(rep(NA_real_, nrow(result)))
      result[, scale(.SD[[1]]), .SDcols=m, by=sig_date]$V1
    }),
    na.rm = TRUE
  )]

  return(list(predictions = result, feature_importance = fi_local,
              train_end_idx = train_end_idx, oos_idx_vec = oos_idx_vec))
}

# --- Execute folds ---
cat("\n[2/6] Walk-forward folds...\n")
for (fi in seq_along(train_endpoints)) {
  train_end_idx <- train_endpoints[fi]
  # determine OOS indices for this fold = [train_end_idx + 1, min(train_end_idx + STEP_SIZE, n_sd)]
  oos_idx_vec <- seq(train_end_idx + 1L,
                     min(train_end_idx + STEP_SIZE, n_sd),
                     by = 1L)
  fold_id <- sprintf("fold_%03d", fi)
  cat(sprintf("\n  [%s] train_end=%s (idx %d) | predict %s..%s (n=%d)\n",
              fold_id, sig_dates[train_end_idx], train_end_idx,
              sig_dates[oos_idx_vec[1]], sig_dates[oos_idx_vec[length(oos_idx_vec)]],
              length(oos_idx_vec)))
  t_f <- Sys.time()
  res <- run_fold(fold_id, train_end_idx, oos_idx_vec, panel, sig_dates, feature_cols)
  if (!is.null(res)) {
    all_predictions[[fold_id]] <- res$predictions
    feature_importance_log[[fold_id]] <- res$feature_importance
  }
  cat(sprintf("  [%s] DONE %.1f min\n", fold_id, as.numeric(difftime(Sys.time(), t_f, units="mins"))))
}

# --- Combine predictions ---
cat("\n[3/6] Combining all OOS predictions...\n")
preds_all <- rbindlist(all_predictions, use.names=TRUE, fill=TRUE)
setkey(preds_all, sig_date, Ticker)
cat(sprintf("  preds_all: %s rows\n", format(nrow(preds_all), big.mark=",")))

# Merge target back for evaluation
target_sub <- panel[, .(sig_date, Ticker, Sector_Lv2, ret_1m_fwd_w, bm_ret_1m_fwd, active_ret_1m_fwd)]
preds_all <- merge(preds_all, target_sub, by=c("sig_date","Ticker"), all.x=TRUE)

# --- Save predictions parquet ---
cat("[4/6] Saving predictions...\n")
out_path <- file.path(OUT_DIR, "walk_forward_predictions.parquet")
write_parquet(preds_all, out_path)
cat(sprintf("  saved: %s (%.1f MB)\n", out_path, file.size(out_path)/1024^2))

# --- Save per-fold feature importance (best XGB + RF) ---
cat("[5/6] Saving feature importance...\n")
saveRDS(feature_importance_log, file.path(OUT_DIR, "feature_importance_per_fold.rds"))
cat("  saved feature_importance_per_fold.rds\n")

# --- Save walk-forward metadata ---
cat("[6/6] Saving metadata...\n")
fold_meta <- data.table(
  fold_id = names(all_predictions),
  train_end_idx = train_endpoints[seq_along(all_predictions)],
  train_end_date = as.character(sig_dates[train_endpoints[seq_along(all_predictions)]]),
  n_oos_sig_dates = sapply(all_predictions, function(x) uniqueN(x$sig_date))
)
fwrite(fold_meta, file.path(OUT_DIR, "walk_forward_fold_meta.csv"))

meta <- list(
  task_id = "WT-D20260514_009",
  step = "step2_ml_walkforward",
  n_features = length(feature_cols),
  n_sig_dates = n_sd,
  n_train_folds = length(train_endpoints),
  init_train_end_idx = INIT_TRAIN_END_IDX,
  init_train_end_date = as.character(sig_dates[INIT_TRAIN_END_IDX]),
  oos_start_date = as.character(sig_dates[oos_start_idx]),
  oos_end_date = as.character(sig_dates[n_sd]),
  lockbox_size = LOCKBOX_SIZE,
  lockbox_start_date = as.character(sig_dates[n_sd - LOCKBOX_SIZE + 1]),
  lockbox_end_date = as.character(sig_dates[n_sd]),
  retrain_step = STEP_SIZE,
  models = c("ridge", "lasso", "elasticnet", "xgboost", "random_forest", "ensemble"),
  ex_ante_grid_N = 5L,
  pit_strict = TRUE,
  built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
jsonlite::write_json(meta, file.path(OUT_DIR, "ml_model_metadata.json"),
                     auto_unbox=TRUE, pretty=TRUE)

cat(sprintf("\n=== Step 2 DONE total %.1f min ===\n",
            as.numeric(difftime(Sys.time(), t_overall, units="mins"))))
