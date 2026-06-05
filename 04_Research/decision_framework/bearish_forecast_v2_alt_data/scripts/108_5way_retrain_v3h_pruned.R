#==============================================================================
# 108_5way_retrain_v3h_pruned.R — Cycle 48B Step 2 (GBDT 3-way per variant)
#
# Goal:
#   Train XGB + CatBoost + RF on 3 LASSO-pruned panels:
#     - v3h_pruned_lasso_min (6 features)
#     - v3h_pruned_lasso_1se (4 features, mid fallback)
#     - v3h_pruned_gbdt_top30 (31 features)
#
#   Mirror scripts/78 structure: 5-fold walk-forward CV (TRAIN only),
#   final OOS PR-AUC measurement.
#
# Output:
#   outputs/03_models/v3h_pruned/predictions_3way_{variant}_y_tail_q15.parquet
#   outputs/04_evaluation/5way_retrain_v3h_pruned_step2.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v3h_pruned")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

TRAIN_START <- as.Date("1995-01-01")
TRAIN_END   <- as.Date("2009-12-31")
VALID_START <- as.Date("2010-01-01")
VALID_END   <- as.Date("2015-12-31")
OOS_START   <- as.Date("2016-01-01")
OOS_END     <- as.Date("2026-04-30")

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

train_variant_3way <- function(variant_name, panel_path) {
  cat(sprintf("\n========== VARIANT: %s ==========\n", variant_name))
  cat(sprintf("Panel: %s\n", panel_path))

  panel_v <- as.data.table(read_parquet(panel_path))
  panel_v[, Date := as.Date(Date)]
  setorder(panel_v, Date)

  tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
  tgt[, Date := as.Date(Date)]
  panel <- merge(panel_v, tgt[, .(Date, y_tail_q15, y_onset)], by = "Date", all.x = TRUE)
  setorder(panel, Date)
  panel <- panel[Date <= OOS_END]

  feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15", "y_onset"))
  cat(sprintf("[2a] Panel rows: %d / features: %d\n", nrow(panel), length(feature_cols)))

  # Impute median (TRAIN only)
  X_all <- as.matrix(panel[, feature_cols, with = FALSE])
  idx_train_all <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
  col_meds <- apply(X_all[idx_train_all, , drop = FALSE], 2, function(x) median(x, na.rm = TRUE))
  col_meds[is.na(col_meds)] <- 0
  for (j in seq_len(ncol(X_all))) X_all[is.na(X_all[, j]), j] <- col_meds[j]

  idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
  idx_valid <- which(panel$Date >= VALID_START & panel$Date <= VALID_END)
  idx_oos   <- which(panel$Date >= OOS_START & panel$Date <= OOS_END)

  target_col <- "y_tail_q15"
  Y_all <- panel[[target_col]]
  Y_all[is.na(Y_all)] <- 0L
  pos_weight <- sum(Y_all[idx_train] == 0) / max(sum(Y_all[idx_train] == 1), 1)
  pos_weight <- min(pos_weight, 8)

  # M1: XGBoost
  cat(sprintf("[M1 XGB] pos_weight=%.2f / training...\n", pos_weight))
  dtrain <- xgb.DMatrix(X_all[idx_train, , drop = FALSE], label = Y_all[idx_train])
  dvalid <- xgb.DMatrix(X_all[idx_valid, , drop = FALSE], label = Y_all[idx_valid])
  xgb_fit <- xgb.train(
    params = list(booster = "gbtree", objective = "binary:logistic",
                  eval_metric = "aucpr", max_depth = 4, eta = 0.04,
                  subsample = 0.8, colsample_bytree = 0.6,
                  min_child_weight = 5, scale_pos_weight = pos_weight, seed = 42),
    data = dtrain, nrounds = 1000,
    evals = list(train = dtrain, valid = dvalid),
    early_stopping_rounds = 80, verbose = 0
  )
  pred_xgb <- predict(xgb_fit, X_all)
  pr_xgb <- pr_auc(pred_xgb[idx_oos], Y_all[idx_oos])
  cat(sprintf("[M1 XGB] OOS PR-AUC: %.4f\n", pr_xgb))

  # M2: CatBoost
  cat("[M2 CatBoost] training...\n")
  cat_pool_train <- catboost.load_pool(data = X_all[idx_train, , drop = FALSE], label = Y_all[idx_train])
  cat_pool_valid <- catboost.load_pool(data = X_all[idx_valid, , drop = FALSE], label = Y_all[idx_valid])
  cat_params <- list(
    loss_function = "Logloss",
    eval_metric = "PRAUC",
    iterations = 1000,
    learning_rate = 0.04,
    depth = 5,
    od_type = "Iter",
    od_wait = 80,
    class_weights = c(1, pos_weight),
    verbose = 0,
    random_seed = 42
  )
  cat_fit <- catboost.train(learn_pool = cat_pool_train, test_pool = cat_pool_valid, params = cat_params)
  pred_cat <- catboost.predict(cat_fit, catboost.load_pool(data = X_all),
                                prediction_type = "Probability")
  pr_cat <- pr_auc(pred_cat[idx_oos], Y_all[idx_oos])
  cat(sprintf("[M2 CatBoost] OOS PR-AUC: %.4f\n", pr_cat))

  # M3: Ranger RF
  cat("[M3 Ranger RF] training (1000 trees, mtry=sqrt(p))...\n")
  rf_data <- as.data.table(X_all[idx_train, , drop = FALSE])
  rf_data[, y := Y_all[idx_train]]
  case_weights <- ifelse(rf_data$y == 1, pos_weight, 1)
  mtry_val <- max(1, floor(sqrt(length(feature_cols))))
  rf_fit <- ranger(
    formula = y ~ ., data = rf_data,
    num.trees = 1000,
    mtry = mtry_val,
    probability = TRUE,
    case.weights = case_weights,
    importance = "impurity",
    seed = 42, num.threads = 4
  )
  pred_rf_all <- predict(rf_fit, data = as.data.table(X_all))$predictions[, 2]
  pr_rf <- pr_auc(pred_rf_all[idx_oos], Y_all[idx_oos])
  cat(sprintf("[M3 Ranger RF] OOS PR-AUC: %.4f\n", pr_rf))

  # 3-way EW
  pred_ew <- (pred_xgb + pred_cat + pred_rf_all) / 3
  pr_ew <- pr_auc(pred_ew[idx_oos], Y_all[idx_oos])
  cat(sprintf("[3way EW] OOS PR-AUC: %.4f\n", pr_ew))

  # Save predictions
  preds <- data.table(
    Date = panel$Date,
    split = fcase(
      panel$Date >= OOS_START & panel$Date <= OOS_END, "oos",
      panel$Date >= VALID_START & panel$Date <= VALID_END, "valid",
      panel$Date >= TRAIN_START & panel$Date <= TRAIN_END, "train",
      default = "other"
    ),
    target = target_col,
    y = Y_all,
    p_xgb = pred_xgb,
    p_cat = pred_cat,
    p_rf  = pred_rf_all,
    p_ew  = pred_ew
  )
  out_pred_path <- file.path(OUT_DIR, sprintf("predictions_3way_%s_%s.parquet",
                                                variant_name, target_col))
  write_parquet(preds, out_pred_path)

  list(
    variant = variant_name,
    n_features = length(feature_cols),
    pr_xgb = pr_xgb,
    pr_cat = pr_cat,
    pr_rf = pr_rf,
    pr_ew = pr_ew,
    out_pred_path = out_pred_path
  )
}

# Run 3 variants
variants <- list(
  list(name = "lasso_min", path = file.path(DATA_DIR, "feature_panel_v3h_pruned_lasso_min.parquet")),
  list(name = "lasso_1se", path = file.path(DATA_DIR, "feature_panel_v3h_pruned_lasso_1se.parquet")),
  list(name = "gbdt_top30", path = file.path(DATA_DIR, "feature_panel_v3h_pruned_gbdt_top30.parquet"))
)

results <- list()
for (v in variants) {
  res <- train_variant_3way(v$name, v$path)
  results[[v$name]] <- res
}

cat("\n============================================================\n")
cat("[Step 2 SUMMARY] GBDT 3-way per variant (y_tail_q15)\n")
for (vname in names(results)) {
  r <- results[[vname]]
  cat(sprintf("  %-14s (n=%2d):  XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
              vname, r$n_features, r$pr_xgb, r$pr_cat, r$pr_rf, r$pr_ew))
}

# Save summary
summary_json <- list(
  cycle = "48B",
  step = "step2_3way_gbdt_per_variant",
  baseline_v3b = list(n_features = 73, m2_regime = 0.6417),
  variants = lapply(results, function(r) {
    list(
      variant = r$variant,
      n_features = r$n_features,
      xgb = round(r$pr_xgb, 4),
      cat = round(r$pr_cat, 4),
      rf = round(r$pr_rf, 4),
      ew = round(r$pr_ew, 4)
    )
  })
)
write_json(summary_json,
           file.path(EVAL_DIR, "5way_retrain_v3h_pruned_step2.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[Step 2] Summary JSON saved.\n"))
cat("\n========== Step 2 DONE — Run scripts/109_5way_retrain_v3h_pruned.py next ==========\n")
