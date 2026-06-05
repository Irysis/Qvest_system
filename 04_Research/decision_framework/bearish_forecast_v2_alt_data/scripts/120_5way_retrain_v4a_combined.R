#==============================================================================
# 120_5way_retrain_v4a_combined.R — Cycle 52 Path A Step 2
#
# GBDT walk-forward 5-fold CV on v4a combined panel (70 features).
# Mirror scripts/92_5way_retrain_v3d_walkforward.R / 114_v1_3_rebaseline_forward.R.
#
# Forward labels (targets_full.parquet — Cycle 50 forward fix).
# walk-forward expanding 5-fold CV (Cycle 45D pattern).
#
# Output:
#   outputs/03_models/v4a_combined/predictions_3way_y_tail_q15.parquet
#   outputs/03_models/v4a_combined/predictions_3way_y_onset.parquet
#   outputs/04_evaluation/v4a_combined_step2_gbdt.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v4a_combined")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# OOS window
OOS_START   <- as.Date("2018-01-01")
OOS_END     <- as.Date("2026-04-30")

FULL_TRAIN_START <- as.Date("1995-01-01")
FULL_TRAIN_END   <- as.Date("2015-12-31")

# Walk-forward expanding 5-fold CV
FOLDS <- list(
  list(name = "Fold1_Lehman",     train_start = "1995-01-01", train_end = "2007-12-31",
       valid_start = "2008-01-01", valid_end = "2009-12-31"),
  list(name = "Fold2_EuroAfter",  train_start = "1995-01-01", train_end = "2009-12-31",
       valid_start = "2010-01-01", valid_end = "2011-12-31"),
  list(name = "Fold3_CyprusTT",   train_start = "1995-01-01", train_end = "2011-12-31",
       valid_start = "2012-01-01", valid_end = "2013-12-31"),
  list(name = "Fold4_KRLowVol",   train_start = "1995-01-01", train_end = "2013-12-31",
       valid_start = "2014-01-01", valid_end = "2015-12-31"),
  list(name = "Fold5_BestSignal", train_start = "1995-01-01", train_end = "2015-12-31",
       valid_start = "2016-01-01", valid_end = "2017-12-31")
)

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

cat("\n========== Cycle 52 Step 2: GBDT walk-forward 5-fold CV (70 features) ==========\n")

# Load v4a combined panel
panel_path <- file.path(DATA_DIR, "feature_panel_v4a_combined.parquet")
if (!file.exists(panel_path)) {
  stop(sprintf("missing v4a combined panel: %s — run scripts/119_feature_panel_v4a_combined.R first",
               panel_path))
}
feat <- as.data.table(read_parquet(panel_path))
feat[, Date := as.Date(Date)]
setorder(feat, Date)
n_feat <- ncol(feat) - 1L
cat(sprintf("[Load] v4a combined panel: %d rows × %d features\n", nrow(feat), n_feat))
stopifnot(n_feat == 70L)

# Forward labels (Cycle 50 fix)
tgt_path <- file.path(TGT_DIR, "targets_full.parquet")
if (!file.exists(tgt_path)) stop(sprintf("missing target: %s", tgt_path))
tgt <- as.data.table(read_parquet(tgt_path))
tgt[, Date := as.Date(Date)]
cat(sprintf("[Load] Forward labels y_tail_q15=%.2f%% / y_onset=%.2f%%\n",
            100*mean(tgt$y_tail_q15, na.rm=TRUE),
            100*mean(tgt$y_onset, na.rm=TRUE)))

panel <- merge(feat, tgt[, .(Date, y_tail_q15, y_onset)], by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15", "y_onset"))
cat(sprintf("[Panel] %d rows / %d features\n", nrow(panel), length(feature_cols)))
stopifnot(length(feature_cols) == 70L)

# Median impute (full pre-OOS train period)
X_all <- as.matrix(panel[, feature_cols, with = FALSE])
idx_full_train <- which(panel$Date >= FULL_TRAIN_START & panel$Date <= FULL_TRAIN_END)
col_meds <- apply(X_all[idx_full_train, , drop = FALSE], 2, function(x) median(x, na.rm = TRUE))
col_meds[is.na(col_meds)] <- 0
for (j in seq_len(ncol(X_all))) X_all[is.na(X_all[, j]), j] <- col_meds[j]

# Per-fold training helper
fold_train_gbdt <- function(target_col, model_type, fold_info) {
  fold_name <- fold_info$name
  train_start <- as.Date(fold_info$train_start)
  train_end <- as.Date(fold_info$train_end)
  valid_start <- as.Date(fold_info$valid_start)
  valid_end <- as.Date(fold_info$valid_end)

  Y_all <- panel[[target_col]]
  Y_all[is.na(Y_all)] <- 0L

  idx_tr <- which(panel$Date >= train_start & panel$Date <= train_end)
  idx_vl <- which(panel$Date >= valid_start & panel$Date <= valid_end)

  pos_weight <- sum(Y_all[idx_tr] == 0) / max(sum(Y_all[idx_tr] == 1), 1)
  pos_weight <- min(pos_weight, 8)

  bear_count <- sum(Y_all[idx_vl])

  if (model_type == "xgb") {
    dtrain <- xgb.DMatrix(X_all[idx_tr, ], label = Y_all[idx_tr])
    dvalid <- xgb.DMatrix(X_all[idx_vl, ], label = Y_all[idx_vl])
    fit <- xgb.train(
      params = list(booster = "gbtree", objective = "binary:logistic",
                    eval_metric = "aucpr", max_depth = 4, eta = 0.04,
                    subsample = 0.8, colsample_bytree = 0.6,
                    min_child_weight = 5, scale_pos_weight = pos_weight, seed = 42),
      data = dtrain, nrounds = 1000,
      evals = list(train = dtrain, valid = dvalid),
      early_stopping_rounds = 80, verbose = 0
    )
    best_iter <- tryCatch({
      bi <- fit$best_iteration
      if (is.null(bi)) bi <- fit$best_ntreelimit
      if (is.null(bi)) bi <- fit$niter
      if (is.null(bi)) bi <- 500L
      as.integer(bi)
    }, error = function(e) 500L)
    if (is.na(best_iter) || best_iter <= 0) best_iter <- 500L
    pred_vl <- predict(fit, X_all[idx_vl, ])
    valid_pr <- pr_auc(pred_vl, Y_all[idx_vl])
    return(list(fold = fold_name, model = "xgb", target = target_col,
                best_iter = as.integer(best_iter), valid_pr = round(valid_pr, 4),
                bear_count = as.integer(bear_count), n_valid = length(idx_vl),
                pos_weight = round(pos_weight, 2)))
  }

  if (model_type == "cat") {
    cat_pool_train <- catboost.load_pool(data = X_all[idx_tr, ], label = Y_all[idx_tr])
    cat_pool_valid <- catboost.load_pool(data = X_all[idx_vl, ], label = Y_all[idx_vl])
    cat_params <- list(
      loss_function = "Logloss", eval_metric = "PRAUC",
      iterations = 1000, learning_rate = 0.04, depth = 5,
      od_type = "Iter", od_wait = 80,
      class_weights = c(1, pos_weight),
      verbose = 0, random_seed = 42
    )
    fit <- catboost.train(learn_pool = cat_pool_train, test_pool = cat_pool_valid,
                          params = cat_params)
    best_iter <- 500L
    tc_try <- tryCatch({
      if ("tree_count_" %in% names(fit)) as.integer(fit$tree_count_)
      else if ("treeCount" %in% names(fit)) as.integer(fit$treeCount)
      else 500L
    }, error = function(e) 500L, warning = function(w) 500L)
    if (!is.null(tc_try) && !is.na(tc_try) && tc_try > 0) best_iter <- as.integer(tc_try)
    pred_vl <- catboost.predict(fit, cat_pool_valid, prediction_type = "Probability")
    valid_pr <- pr_auc(pred_vl, Y_all[idx_vl])
    return(list(fold = fold_name, model = "cat", target = target_col,
                best_iter = as.integer(best_iter),
                valid_pr = round(valid_pr, 4),
                bear_count = as.integer(bear_count), n_valid = length(idx_vl),
                pos_weight = round(pos_weight, 2)))
  }

  if (model_type == "rf") {
    rf_data <- as.data.table(X_all[idx_tr, ])
    rf_data[, y := Y_all[idx_tr]]
    case_weights <- ifelse(rf_data$y == 1, pos_weight, 1)
    fit <- ranger(
      formula = y ~ ., data = rf_data,
      num.trees = 1000,
      mtry = floor(sqrt(length(feature_cols))),
      probability = TRUE,
      case.weights = case_weights,
      importance = "none",
      seed = 42, num.threads = 4
    )
    pred_vl <- predict(fit, data = as.data.table(X_all[idx_vl, ]))$predictions[, 2]
    valid_pr <- pr_auc(pred_vl, Y_all[idx_vl])
    return(list(fold = fold_name, model = "rf", target = target_col,
                best_iter = 1000L, valid_pr = round(valid_pr, 4),
                bear_count = as.integer(bear_count), n_valid = length(idx_vl),
                pos_weight = round(pos_weight, 2)))
  }
}

run_fold_grid <- function(target_col) {
  cat(sprintf("\n----- Target: %s (5-fold CV) -----\n", target_col))
  diag_list <- list()
  for (fi in FOLDS) {
    for (mt in c("xgb", "cat", "rf")) {
      cat(sprintf("  %s × %s... ", fi$name, toupper(mt)))
      flush.console()
      res <- fold_train_gbdt(target_col, mt, fi)
      diag_list[[length(diag_list) + 1]] <- res
      cat(sprintf("best_iter=%d / valid_pr=%.4f / bear=%d/%d\n",
                  res$best_iter, res$valid_pr, res$bear_count, res$n_valid))
    }
  }
  diag_list
}

cat("\n--- 5-fold CV for y_tail_q15 (FORWARD) ---\n")
fold_diag_q15 <- run_fold_grid("y_tail_q15")
cat("\n--- 5-fold CV for y_onset (FORWARD) ---\n")
fold_diag_onset <- run_fold_grid("y_onset")

avg_best_iter <- function(diag_list, model_type, fallback = 500L) {
  best_iters <- sapply(diag_list, function(x) {
    if (is.null(x$model) || x$model != model_type) return(NA_integer_)
    if (is.null(x$best_iter)) return(NA_integer_)
    bi <- suppressWarnings(as.integer(x$best_iter))
    if (is.na(bi) || bi <= 0) return(NA_integer_)
    bi
  })
  best_iters <- best_iters[!is.na(best_iters) & best_iters > 0]
  if (length(best_iters) == 0) return(as.integer(fallback))
  as.integer(round(mean(best_iters)))
}

avg_iter_xgb_q15   <- avg_best_iter(fold_diag_q15, "xgb")
avg_iter_cat_q15   <- avg_best_iter(fold_diag_q15, "cat")
avg_iter_rf_q15    <- avg_best_iter(fold_diag_q15, "rf")
avg_iter_xgb_onset <- avg_best_iter(fold_diag_onset, "xgb")
avg_iter_cat_onset <- avg_best_iter(fold_diag_onset, "cat")

cat(sprintf("\n[Avg best_iter from 5-fold CV]\n"))
cat(sprintf("  y_tail_q15: XGB=%d / Cat=%d / RF=%d\n",
            avg_iter_xgb_q15, avg_iter_cat_q15, avg_iter_rf_q15))
cat(sprintf("  y_onset:    XGB=%d / Cat=%d / RF=%d\n",
            avg_iter_xgb_onset, avg_iter_cat_onset, avg_iter_rf_q15))

# Final training + OOS evaluation
cat("\n========== Step 3: Final model train + OOS (2018-2026) ==========\n")

idx_final_train <- which(panel$Date >= FULL_TRAIN_START & panel$Date <= FULL_TRAIN_END)
idx_oos <- which(panel$Date >= OOS_START & panel$Date <= OOS_END)
cat(sprintf("[Final train] %d rows / OOS: %d rows\n",
            length(idx_final_train), length(idx_oos)))

run_final_3way <- function(target_col, n_iter_xgb, n_iter_cat, n_iter_rf) {
  cat(sprintf("\n----- Final 3-way GBDT: %s -----\n", target_col))
  Y_all <- panel[[target_col]]
  Y_all[is.na(Y_all)] <- 0L
  pos_weight <- sum(Y_all[idx_final_train] == 0) / max(sum(Y_all[idx_final_train] == 1), 1)
  pos_weight <- min(pos_weight, 8)

  cat(sprintf("[XGB] pos_weight=%.2f / nrounds=%d (avg from 5-fold)...\n", pos_weight, n_iter_xgb))
  dtrain <- xgb.DMatrix(X_all[idx_final_train, ], label = Y_all[idx_final_train])
  xgb_fit <- xgb.train(
    params = list(booster = "gbtree", objective = "binary:logistic",
                  eval_metric = "aucpr", max_depth = 4, eta = 0.04,
                  subsample = 0.8, colsample_bytree = 0.6,
                  min_child_weight = 5, scale_pos_weight = pos_weight, seed = 42),
    data = dtrain, nrounds = n_iter_xgb,
    verbose = 0
  )
  pred_xgb <- predict(xgb_fit, X_all)
  pr_xgb <- pr_auc(pred_xgb[idx_oos], Y_all[idx_oos])
  cat(sprintf("[XGB] OOS PR-AUC: %.4f\n", pr_xgb))

  cat(sprintf("[CatBoost] iterations=%d...\n", n_iter_cat))
  cat_pool_train <- catboost.load_pool(data = X_all[idx_final_train, ], label = Y_all[idx_final_train])
  cat_params <- list(
    loss_function = "Logloss", eval_metric = "PRAUC",
    iterations = n_iter_cat, learning_rate = 0.04, depth = 5,
    class_weights = c(1, pos_weight),
    verbose = 0, random_seed = 42
  )
  cat_fit <- catboost.train(learn_pool = cat_pool_train, params = cat_params)
  pred_cat <- catboost.predict(cat_fit, catboost.load_pool(data = X_all),
                                prediction_type = "Probability")
  pr_cat <- pr_auc(pred_cat[idx_oos], Y_all[idx_oos])
  cat(sprintf("[CatBoost] OOS PR-AUC: %.4f\n", pr_cat))

  cat(sprintf("[Ranger RF] num.trees=%d...\n", n_iter_rf))
  rf_data <- as.data.table(X_all[idx_final_train, ])
  rf_data[, y := Y_all[idx_final_train]]
  case_weights <- ifelse(rf_data$y == 1, pos_weight, 1)
  rf_fit <- ranger(
    formula = y ~ ., data = rf_data,
    num.trees = n_iter_rf,
    mtry = floor(sqrt(length(feature_cols))),
    probability = TRUE,
    case.weights = case_weights,
    importance = "impurity",
    seed = 42, num.threads = 4
  )
  pred_rf_all <- predict(rf_fit, data = as.data.table(X_all))$predictions[, 2]
  pr_rf <- pr_auc(pred_rf_all[idx_oos], Y_all[idx_oos])
  cat(sprintf("[Ranger RF] OOS PR-AUC: %.4f\n", pr_rf))

  pred_ew <- (pred_xgb + pred_cat + pred_rf_all) / 3
  pr_ew <- pr_auc(pred_ew[idx_oos], Y_all[idx_oos])
  cat(sprintf("\n[3way EW] OOS PR-AUC: %.4f\n", pr_ew))

  preds <- data.table(
    Date = panel$Date,
    split = fcase(
      panel$Date >= OOS_START & panel$Date <= OOS_END, "oos",
      panel$Date >= FULL_TRAIN_START & panel$Date <= FULL_TRAIN_END, "train",
      default = "other"
    ),
    target = target_col,
    y = Y_all,
    p_xgb = pred_xgb,
    p_cat = pred_cat,
    p_rf  = pred_rf_all,
    p_ew  = pred_ew
  )
  write_parquet(preds, file.path(OUT_DIR, sprintf("predictions_3way_%s.parquet", target_col)))

  # Also save individual model predictions to mirror naming convention from Cycle 50 baselines
  for (m_name in c("xgb", "cat", "rf")) {
    p_col <- sprintf("p_%s", m_name)
    df_m <- data.table(
      Date = panel$Date,
      split = preds$split,
      target = target_col,
      y = Y_all
    )
    df_m[[p_col]] <- preds[[p_col]]
    write_parquet(df_m, file.path(OUT_DIR, sprintf("predictions_%s_%s.parquet", m_name, target_col)))
  }

  list(pr_xgb = pr_xgb, pr_cat = pr_cat, pr_rf = pr_rf, pr_ew = pr_ew)
}

res_q15 <- run_final_3way("y_tail_q15", avg_iter_xgb_q15, avg_iter_cat_q15, 1000L)
res_onset <- run_final_3way("y_onset", avg_iter_xgb_onset, avg_iter_cat_onset, 1000L)

cat("\n============================================================\n")
cat("[Step 2+3 SUMMARY] Final 3-way GBDT on v4a combined (70 features) FORWARD\n")
cat(sprintf("y_tail_q15:  XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_q15$pr_xgb, res_q15$pr_cat, res_q15$pr_rf, res_q15$pr_ew))
cat(sprintf("y_onset:     XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_onset$pr_xgb, res_onset$pr_cat, res_onset$pr_rf, res_onset$pr_ew))

gbdt_diag <- list(
  cycle = "52_path_a_combined",
  step = "step2_3_gbdt_walkforward_FORWARD",
  panel = panel_path,
  target_file = tgt_path,
  n_features = length(feature_cols),
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END),
                    note = "fold 5 valid 2016-2017 제외하여 leakage 방지"),
  folds = lapply(FOLDS, function(f) list(
    name = f$name,
    train_start = f$train_start, train_end = f$train_end,
    valid_start = f$valid_start, valid_end = f$valid_end
  )),
  fold_diagnostics_y_tail_q15 = fold_diag_q15,
  fold_diagnostics_y_onset = fold_diag_onset,
  avg_best_iter = list(
    y_tail_q15 = list(xgb = avg_iter_xgb_q15, cat = avg_iter_cat_q15, rf = avg_iter_rf_q15),
    y_onset    = list(xgb = avg_iter_xgb_onset, cat = avg_iter_cat_onset, rf = avg_iter_rf_q15)
  ),
  final_oos_y_tail_q15 = list(
    xgb = round(res_q15$pr_xgb, 4),
    cat = round(res_q15$pr_cat, 4),
    rf  = round(res_q15$pr_rf, 4),
    ew3 = round(res_q15$pr_ew, 4)
  ),
  final_oos_y_onset = list(
    xgb = round(res_onset$pr_xgb, 4),
    cat = round(res_onset$pr_cat, 4),
    rf  = round(res_onset$pr_rf, 4),
    ew3 = round(res_onset$pr_ew, 4)
  )
)
write_json(gbdt_diag,
           file.path(EVAL_DIR, "v4a_combined_step2_gbdt.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Step 2 JSON] %s\n",
            file.path(EVAL_DIR, "v4a_combined_step2_gbdt.json")))

cat("\n========== Cycle 52 Step 2 DONE — Run scripts/121_5way_retrain_v4a_combined.py next ==========\n")
