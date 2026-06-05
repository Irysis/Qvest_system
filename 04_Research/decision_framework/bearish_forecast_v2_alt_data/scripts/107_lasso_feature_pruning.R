#==============================================================================
# 107_lasso_feature_pruning.R — Cycle 48B LASSO Feature Pruning
#
# Goal:
#   Capacity Allocation hypothesis: 73 features 수준에서 ML model이 weak signal
#   feature에 capacity 분산 → strong signal feature 활용 감소 (dilution).
#
#   LASSO logistic regression으로 informative feature subset 추출 → 3 variants:
#     - lambda.min : minimum CV error
#     - lambda.1se : 1 SE rule (more aggressive pruning)
#     - GBDT top30 union (XGB + CatBoost + RF importance rank)
#
# Steps:
#   Step 1: Load v3b_inst_suite (73 features) + y_tail_q15 target
#   Step 2: Train LASSO logistic regression (TRAIN only, 1995-2009)
#           cv.glmnet alpha=1.0 5-fold time-series CV
#   Step 3: Extract feature subset (lambda.min, lambda.1se)
#   Step 4: GBDT importance ranking (XGB + CatBoost + RF) → top 30 union
#   Step 5: Save 3 pruned panels + selection JSON
#
# PIT contract:
#   - LASSO/GBDT trained on TRAIN period only (1995-2009)
#   - NO valid/OOS data leakage
#   - All features inherit lag1 from v3b_inst_suite panel
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(glmnet)
  library(xgboost); library(catboost); library(ranger); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# Walk-forward splits
TRAIN_START <- as.Date("1995-01-01")
TRAIN_END   <- as.Date("2009-12-31")
VALID_START <- as.Date("2010-01-01")
VALID_END   <- as.Date("2015-12-31")
OOS_START   <- as.Date("2016-01-01")
OOS_END     <- as.Date("2026-04-30")

#==============================================================================
# Step 1: Load panel + target
#==============================================================================
cat("\n========== Step 1: Load v3b_inst_suite + target ==========\n")
panel_path <- file.path(DATA_DIR, "feature_panel_v3b_inst_suite.parquet")
panel <- as.data.table(read_parquet(panel_path))
panel[, Date := as.Date(Date)]
setorder(panel, Date)

tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
tgt[, Date := as.Date(Date)]
panel <- merge(panel, tgt[, .(Date, y_tail_q15)], by = "Date", all.x = TRUE)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15"))
cat(sprintf("[1a] Panel: %d rows / %d features / target y_tail_q15\n",
            nrow(panel), length(feature_cols)))

# TRAIN-only data for LASSO selection
panel_train <- panel[Date >= TRAIN_START & Date <= TRAIN_END]
panel_train <- panel_train[!is.na(y_tail_q15)]
cat(sprintf("[1b] TRAIN period: %d rows (1995-2009) / events=%d (%.2f%%)\n",
            nrow(panel_train), sum(panel_train$y_tail_q15),
            100 * mean(panel_train$y_tail_q15)))

# Median impute (TRAIN only) + standardize
X_train_raw <- as.matrix(panel_train[, feature_cols, with = FALSE])
col_meds <- apply(X_train_raw, 2, function(x) median(x, na.rm = TRUE))
col_meds[is.na(col_meds)] <- 0
for (j in seq_len(ncol(X_train_raw))) X_train_raw[is.na(X_train_raw[, j]), j] <- col_meds[j]

# Standardize on TRAIN (mean 0, sd 1)
col_means <- colMeans(X_train_raw)
col_sds <- apply(X_train_raw, 2, sd)
col_sds[col_sds < 1e-6] <- 1
X_train_std <- sweep(sweep(X_train_raw, 2, col_means, FUN = "-"), 2, col_sds, FUN = "/")
y_train <- panel_train$y_tail_q15

cat(sprintf("[1c] Standardized X_train: %d × %d\n",
            nrow(X_train_std), ncol(X_train_std)))

#==============================================================================
# Step 2: LASSO logistic regression (cv.glmnet alpha=1.0)
#==============================================================================
cat("\n========== Step 2: cv.glmnet LASSO (alpha=1.0, 5-fold time-series CV) ==========\n")

# Time-series CV folds (chronological)
n_train <- nrow(X_train_std)
fold_ids <- cut(seq_len(n_train), breaks = 5, labels = FALSE)
cat(sprintf("[2a] CV folds (chronological 5-fold): %s\n",
            paste(table(fold_ids), collapse = " / ")))

cat("[2b] Running cv.glmnet (binomial, alpha=1.0)...\n")
cv_fit <- cv.glmnet(
  x = X_train_std,
  y = y_train,
  family = "binomial",
  alpha = 1.0,
  nfolds = 5,
  foldid = fold_ids,
  type.measure = "deviance",
  standardize = FALSE,  # already standardized
  intercept = TRUE
)

cat(sprintf("[2c] cv.glmnet DONE / lambda.min=%.5f / lambda.1se=%.5f\n",
            cv_fit$lambda.min, cv_fit$lambda.1se))

# Extract feature subsets
coef_min <- coef(cv_fit, s = "lambda.min")
coef_1se <- coef(cv_fit, s = "lambda.1se")

# Drop intercept
feat_idx_min <- which(coef_min[-1, 1] != 0)
feat_idx_1se <- which(coef_1se[-1, 1] != 0)

features_lasso_min <- feature_cols[feat_idx_min]
features_lasso_1se <- feature_cols[feat_idx_1se]

cat(sprintf("[2d] LASSO lambda.min: %d / %d features selected\n",
            length(features_lasso_min), length(feature_cols)))
cat(sprintf("[2d] LASSO lambda.1se: %d / %d features selected\n",
            length(features_lasso_1se), length(feature_cols)))

# Coefficient magnitudes for the selected features (lambda.min)
coef_min_dt <- data.table(
  feature = feature_cols,
  coef = as.numeric(coef_min[-1, 1])
)
coef_min_dt <- coef_min_dt[coef != 0]
coef_min_dt[, abs_coef := abs(coef)]
setorder(coef_min_dt, -abs_coef)
cat("\n[2e] LASSO lambda.min top 15 (by |coef|):\n")
print(head(coef_min_dt[, .(feature, coef, abs_coef)], 15))

# Fallback for lambda.1se if 0 features selected — use next lambda 위 (less aggressive)
if (length(features_lasso_1se) == 0) {
  cat("\n[2d-fallback] lambda.1se yields 0 features — fallback to lambda midway between min and 1se\n")
  lambda_mid <- sqrt(cv_fit$lambda.min * cv_fit$lambda.1se)  # geometric mean
  coef_mid <- coef(cv_fit, s = lambda_mid)
  feat_idx_mid <- which(coef_mid[-1, 1] != 0)
  features_lasso_1se <- feature_cols[feat_idx_mid]
  cat(sprintf("[2d-fallback] lambda_mid=%.5f → %d features selected\n",
              lambda_mid, length(features_lasso_1se)))
  # Update the lambda_1se label to "lambda_mid" semantically
  cv_fit$lambda.1se <- lambda_mid
}

#==============================================================================
# Step 3: GBDT importance ranking (TRAIN only)
#==============================================================================
cat("\n========== Step 3: GBDT importance ranking (XGB + CatBoost + RF) ==========\n")

pos_weight <- sum(y_train == 0) / max(sum(y_train == 1), 1)
pos_weight <- min(pos_weight, 8)
cat(sprintf("[3a] pos_weight=%.2f\n", pos_weight))

# XGB
cat("[3b] XGBoost training (TRAIN only, no early stop)...\n")
dtrain_xgb <- xgb.DMatrix(X_train_std, label = y_train)
xgb_fit_imp <- xgb.train(
  params = list(
    booster = "gbtree", objective = "binary:logistic",
    eval_metric = "aucpr", max_depth = 4, eta = 0.04,
    subsample = 0.8, colsample_bytree = 0.6,
    min_child_weight = 5, scale_pos_weight = pos_weight, seed = 42
  ),
  data = dtrain_xgb, nrounds = 400, verbose = 0
)
imp_xgb <- as.data.table(xgb.importance(model = xgb_fit_imp))
setorder(imp_xgb, -Gain)
imp_xgb[, rank_xgb := seq_len(.N)]
cat(sprintf("[3b] XGB importance: %d features ranked\n", nrow(imp_xgb)))

# CatBoost
cat("[3c] CatBoost training...\n")
cat_pool_train <- catboost.load_pool(data = X_train_std, label = y_train)
cat_fit_imp <- catboost.train(
  learn_pool = cat_pool_train,
  params = list(
    loss_function = "Logloss",
    eval_metric = "PRAUC",
    iterations = 400,
    learning_rate = 0.04,
    depth = 5,
    class_weights = c(1, pos_weight),
    verbose = 0,
    random_seed = 42
  )
)
cat_imp_vec <- tryCatch({
  catboost.get_feature_importance(cat_fit_imp, pool = cat_pool_train, type = "FeatureImportance")
}, error = function(e) NULL)
if (!is.null(cat_imp_vec) && length(cat_imp_vec) > 0) {
  imp_cat <- data.table(Feature = feature_cols, Gain = as.numeric(cat_imp_vec))
  setorder(imp_cat, -Gain)
  imp_cat[, rank_cat := seq_len(.N)]
  cat(sprintf("[3c] CatBoost importance: %d features ranked\n", nrow(imp_cat)))
} else {
  imp_cat <- data.table(Feature = character(0), Gain = numeric(0), rank_cat = integer(0))
}

# Ranger RF
cat("[3d] Ranger RF training (500 trees, mtry=sqrt(p))...\n")
rf_data <- as.data.table(X_train_std)
rf_data[, y := y_train]
case_weights <- ifelse(rf_data$y == 1, pos_weight, 1)
rf_fit_imp <- ranger(
  formula = y ~ ., data = rf_data,
  num.trees = 500,
  mtry = floor(sqrt(length(feature_cols))),
  probability = TRUE,
  case.weights = case_weights,
  importance = "impurity",
  seed = 42, num.threads = 4
)
rf_imp_vec <- rf_fit_imp$variable.importance
imp_rf <- data.table(Feature = names(rf_imp_vec), Gain = as.numeric(rf_imp_vec))
setorder(imp_rf, -Gain)
imp_rf[, rank_rf := seq_len(.N)]
cat(sprintf("[3d] Ranger RF importance: %d features ranked\n", nrow(imp_rf)))

# Combine — find top 30 per model, then union
top30_xgb <- head(imp_xgb, 30)$Feature
top30_cat <- if (nrow(imp_cat) > 0) head(imp_cat, 30)$Feature else character(0)
top30_rf <- head(imp_rf, 30)$Feature

cat(sprintf("[3e] Top-30 per model: XGB=%d / CAT=%d / RF=%d\n",
            length(top30_xgb), length(top30_cat), length(top30_rf)))

features_gbdt_top30 <- unique(c(top30_xgb, top30_cat, top30_rf))
cat(sprintf("[3e] GBDT top-30 UNION: %d features\n", length(features_gbdt_top30)))

# Consensus (intersect: 모든 3 model top-30 공통)
features_gbdt_consensus <- Reduce(intersect, list(top30_xgb, top30_cat, top30_rf))
cat(sprintf("[3f] GBDT top-30 CONSENSUS (intersect): %d features\n", length(features_gbdt_consensus)))

#==============================================================================
# Step 4: Build 3 pruned panels
#==============================================================================
cat("\n========== Step 4: Build 3 pruned panels ==========\n")

# Panel base columns kept: Date + selected features
build_panel_subset <- function(feature_subset, variant_name) {
  keep_cols <- c("Date", feature_subset)
  panel_sub <- panel[, ..keep_cols]
  out_path <- file.path(DATA_DIR, sprintf("feature_panel_v3h_pruned_%s.parquet", variant_name))
  write_parquet(panel_sub, out_path)
  cat(sprintf("  [%s] %d cols (Date + %d features) → %s\n",
              variant_name, ncol(panel_sub), length(feature_subset), out_path))
  out_path
}

p_lasso_min <- build_panel_subset(features_lasso_min, "lasso_min")
p_lasso_1se <- build_panel_subset(features_lasso_1se, "lasso_1se")
p_gbdt_top30 <- build_panel_subset(features_gbdt_top30, "gbdt_top30")

#==============================================================================
# Step 5: Save selection JSON
#==============================================================================
cat("\n========== Step 5: Save selection JSON ==========\n")

# Dropped features per variant
dropped_lasso_min <- setdiff(feature_cols, features_lasso_min)
dropped_lasso_1se <- setdiff(feature_cols, features_lasso_1se)
dropped_gbdt_top30 <- setdiff(feature_cols, features_gbdt_top30)

# 4 institutional features — selected status
new_inst <- c("inst_ad_ratio_5d_avg_lag1", "inst_ad_ratio_20d_avg_lag1",
              "inst_hhi_buy_lag1", "inst_vs_foreign_divergence_5d_lag1")
inst_status <- data.table(
  feature = new_inst,
  in_lasso_min = new_inst %in% features_lasso_min,
  in_lasso_1se = new_inst %in% features_lasso_1se,
  in_gbdt_top30 = new_inst %in% features_gbdt_top30
)
cat("\n[5a] 4 institutional features retention across variants:\n")
print(inst_status)

# Save
sel_result <- list(
  cycle = "48B",
  approach = "LASSO_FEATURE_PRUNING",
  description = "Capacity Allocation hypothesis test — LASSO + GBDT importance pruning on v3b_inst_suite 73 features",
  panel_source = panel_path,
  n_features_full = length(feature_cols),
  target = "y_tail_q15",
  train_period = list(start = "1995-01-01", end = "2009-12-31"),
  lasso = list(
    alpha = 1.0,
    nfolds = 5,
    fold_type = "chronological_time_series",
    lambda_min = list(
      value = round(cv_fit$lambda.min, 6),
      n_features = length(features_lasso_min),
      features = features_lasso_min,
      dropped_n = length(dropped_lasso_min),
      dropped = dropped_lasso_min
    ),
    lambda_1se = list(
      value = round(cv_fit$lambda.1se, 6),
      n_features = length(features_lasso_1se),
      features = features_lasso_1se,
      dropped_n = length(dropped_lasso_1se),
      dropped = dropped_lasso_1se
    ),
    top15_coef_lambda_min = lapply(seq_len(min(15, nrow(coef_min_dt))), function(i) {
      list(feature = coef_min_dt$feature[i], coef = round(coef_min_dt$coef[i], 5))
    })
  ),
  gbdt = list(
    method = "XGB + CatBoost + RF top-30 union",
    n_features_union = length(features_gbdt_top30),
    n_features_consensus = length(features_gbdt_consensus),
    features_union = features_gbdt_top30,
    features_consensus = features_gbdt_consensus,
    top10_xgb = lapply(seq_len(min(10, nrow(imp_xgb))), function(i) {
      list(feature = imp_xgb$Feature[i], gain = round(imp_xgb$Gain[i], 4), rank = imp_xgb$rank_xgb[i])
    }),
    top10_cat = if (nrow(imp_cat) > 0) {
      lapply(seq_len(min(10, nrow(imp_cat))), function(i) {
        list(feature = imp_cat$Feature[i], gain = round(imp_cat$Gain[i], 4), rank = imp_cat$rank_cat[i])
      })
    } else list(),
    top10_rf = lapply(seq_len(min(10, nrow(imp_rf))), function(i) {
      list(feature = imp_rf$Feature[i], gain = round(imp_rf$Gain[i], 4), rank = imp_rf$rank_rf[i])
    })
  ),
  institutional_features_retention = lapply(seq_len(nrow(inst_status)), function(i) {
    list(
      feature = inst_status$feature[i],
      in_lasso_min = inst_status$in_lasso_min[i],
      in_lasso_1se = inst_status$in_lasso_1se[i],
      in_gbdt_top30 = inst_status$in_gbdt_top30[i]
    )
  }),
  output_panels = list(
    lasso_min = p_lasso_min,
    lasso_1se = p_lasso_1se,
    gbdt_top30 = p_gbdt_top30
  )
)

out_json <- file.path(EVAL_DIR, "lasso_feature_selection.json")
write_json(sel_result, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("\n[5b] Selection JSON saved: %s\n", out_json))

cat("\n========== Step 5 DONE — Run scripts/108_5way_retrain_v3h_pruned.R next ==========\n")
cat(sprintf("Summary: lasso_min=%d / lasso_1se=%d / gbdt_top30=%d (from 73)\n",
            length(features_lasso_min), length(features_lasso_1se), length(features_gbdt_top30)))
