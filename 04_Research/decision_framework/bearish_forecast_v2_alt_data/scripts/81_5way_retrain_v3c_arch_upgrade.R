#==============================================================================
# 81_5way_retrain_v3c_arch_upgrade.R — Cycle 45C Architecture Upgrade
#
# Goal:
#   v1.3 baseline 69 features (NO new features) + DNN architecture upgrade only
#   → 3-way GBDT 재학습 (Cycle 43 baseline 재현 검증) + LSTM/TFT upgraded (별도 Python 82)
#   → Dynamic 5-way ensemble (83에서) → vs v1.3 baseline 0.6078 비교
#
# Architecture upgrade is in Python (script 82). R only:
#   Step 1: feature_panel_v1_3.parquet 확보 (v1_alt_enhanced 그대로 — 69 features)
#   Step 2: GBDT 3-way 재학습 (XGB / CatBoost / RF) — Cycle 43 baseline 재현
#
# PIT contract:
#   - 모든 features lag-1 (이미 v1_alt_enhanced에서 처리됨)
#   - Train 1995-01 ~ 2009-12 / Valid 2010-01 ~ 2015-12 / OOS 2016-01 ~ 2026-04
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v3c_arch_upgrade")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# Walk-forward splits (identical to scripts 68/71/74/78)
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

#==============================================================================
# Step 1: feature_panel_v1_3.parquet 확보 (v1_alt_enhanced 69 features = v1.3 baseline)
#==============================================================================
cat("\n========== Step 1: v1.3 baseline panel (69 features, NO new features) ==========\n")

src_path <- file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")
dst_path <- file.path(DATA_DIR, "feature_panel_v1_3.parquet")

feat <- as.data.table(read_parquet(src_path))
feat[, Date := as.Date(Date)]
setorder(feat, Date)
n_feat <- ncol(feat) - 1L
cat(sprintf("[1a] Source v1_alt_enhanced: %d rows × %d features\n", nrow(feat), n_feat))

stopifnot(n_feat == 69L)
write_parquet(feat, dst_path)
cat(sprintf("[1b] Saved v1_3 panel (canonical baseline 69 features): %s\n", dst_path))

#==============================================================================
# Step 2: 3-way GBDT retrain (Cycle 43 baseline 재현 검증)
#==============================================================================
cat("\n========== Step 2: 3-way GBDT retrain (재현 검증) ==========\n")

tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
tgt[, Date := as.Date(Date)]
panel <- merge(feat, tgt[, .(Date, y_tail_q15, y_onset)], by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15", "y_onset"))
cat(sprintf("[2a] Panel for training: %d rows / %d features\n", nrow(panel), length(feature_cols)))
stopifnot(length(feature_cols) == 69L)

# Median impute (train period)
X_all <- as.matrix(panel[, feature_cols, with = FALSE])
idx_train_all <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
col_meds <- apply(X_all[idx_train_all, , drop = FALSE], 2, function(x) median(x, na.rm = TRUE))
col_meds[is.na(col_meds)] <- 0
for (j in seq_len(ncol(X_all))) X_all[is.na(X_all[, j]), j] <- col_meds[j]

idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
idx_valid <- which(panel$Date >= VALID_START & panel$Date <= VALID_END)
idx_oos   <- which(panel$Date >= OOS_START & panel$Date <= OOS_END)

run_target_3way <- function(target_col) {
  cat(sprintf("\n========== Target: %s (3-way GBDT v1.3 reproduction) ==========\n", target_col))
  Y_all <- panel[[target_col]]
  Y_all[is.na(Y_all)] <- 0L
  pos_weight <- sum(Y_all[idx_train] == 0) / max(sum(Y_all[idx_train] == 1), 1)
  pos_weight <- min(pos_weight, 8)

  # M1: XGBoost (identical hyperparams to script 68)
  cat(sprintf("[M1 XGB] pos_weight=%.2f / training...\n", pos_weight))
  dtrain <- xgb.DMatrix(X_all[idx_train, ], label = Y_all[idx_train])
  dvalid <- xgb.DMatrix(X_all[idx_valid, ], label = Y_all[idx_valid])
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
  cat_pool_train <- catboost.load_pool(data = X_all[idx_train, ], label = Y_all[idx_train])
  cat_pool_valid <- catboost.load_pool(data = X_all[idx_valid, ], label = Y_all[idx_valid])
  cat_params <- list(
    loss_function = "Logloss", eval_metric = "PRAUC",
    iterations = 1000, learning_rate = 0.04, depth = 5,
    od_type = "Iter", od_wait = 80,
    class_weights = c(1, pos_weight),
    verbose = 0, random_seed = 42
  )
  cat_fit <- catboost.train(learn_pool = cat_pool_train, test_pool = cat_pool_valid,
                            params = cat_params)
  pred_cat <- catboost.predict(cat_fit, catboost.load_pool(data = X_all),
                                prediction_type = "Probability")
  pr_cat <- pr_auc(pred_cat[idx_oos], Y_all[idx_oos])
  cat(sprintf("[M2 CatBoost] OOS PR-AUC: %.4f\n", pr_cat))

  # M3: Ranger RF
  cat("[M3 Ranger RF] training (1000 trees, mtry=sqrt(p))...\n")
  rf_data <- as.data.table(X_all[idx_train, ])
  rf_data[, y := Y_all[idx_train]]
  case_weights <- ifelse(rf_data$y == 1, pos_weight, 1)
  rf_fit <- ranger(
    formula = y ~ ., data = rf_data,
    num.trees = 1000,
    mtry = floor(sqrt(length(feature_cols))),
    probability = TRUE,
    case.weights = case_weights,
    importance = "impurity",
    seed = 42, num.threads = 4
  )
  pred_rf_all <- predict(rf_fit, data = as.data.table(X_all))$predictions[, 2]
  pr_rf <- pr_auc(pred_rf_all[idx_oos], Y_all[idx_oos])
  cat(sprintf("[M3 Ranger RF] OOS PR-AUC: %.4f\n", pr_rf))

  pred_ew <- (pred_xgb + pred_cat + pred_rf_all) / 3
  pr_ew <- pr_auc(pred_ew[idx_oos], Y_all[idx_oos])
  cat(sprintf("\n[3way EW] OOS PR-AUC: %.4f\n", pr_ew))

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
  write_parquet(preds, file.path(OUT_DIR, sprintf("predictions_3way_%s.parquet", target_col)))

  list(pr_xgb = pr_xgb, pr_cat = pr_cat, pr_rf = pr_rf, pr_ew = pr_ew)
}

res_q15 <- run_target_3way("y_tail_q15")
res_onset <- run_target_3way("y_onset")

cat("\n============================================================\n")
cat("[Step 2 SUMMARY] 3-way GBDT retrain on v1.3 baseline (69 features)\n")
cat(sprintf("y_tail_q15:  XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_q15$pr_xgb, res_q15$pr_cat, res_q15$pr_rf, res_q15$pr_ew))
cat(sprintf("y_onset:     XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_onset$pr_xgb, res_onset$pr_cat, res_onset$pr_rf, res_onset$pr_ew))

# Reproduction check: Cycle 43 v2_2feat 3-way EW was 0.6077 (with 71 features)
# v1.3 baseline 69 features → 0.6078 expected (per Cycle 43 baseline reference)
cat(sprintf("\n[Reproduction check] EW3 y_tail_q15: %.4f (expected ≈ 0.6078 ± 0.005)\n",
            res_q15$pr_ew))
delta_repro <- abs(res_q15$pr_ew - 0.6078)
cat(sprintf("  |Δ| vs expected baseline = %.4f %s\n",
            delta_repro, ifelse(delta_repro <= 0.005, "PASS", "WARN")))

step2_summary <- list(
  step = "step2_3way_gbdt_reproduction",
  panel = dst_path,
  n_features = length(feature_cols),
  baseline_v1_3 = TRUE,
  new_features = "none — architecture upgrade only (orthogonal to Cycle 44/45A/45B)",
  y_tail_q15 = list(
    xgb = round(res_q15$pr_xgb, 4),
    cat = round(res_q15$pr_cat, 4),
    rf  = round(res_q15$pr_rf, 4),
    ew3 = round(res_q15$pr_ew, 4)
  ),
  y_onset = list(
    xgb = round(res_onset$pr_xgb, 4),
    cat = round(res_onset$pr_cat, 4),
    rf  = round(res_onset$pr_rf, 4),
    ew3 = round(res_onset$pr_ew, 4)
  ),
  reproduction = list(
    expected_ew3_y_tail_q15 = 0.6078,
    observed_ew3_y_tail_q15 = round(res_q15$pr_ew, 4),
    abs_delta = round(delta_repro, 4),
    verdict = ifelse(delta_repro <= 0.005, "PASS_REPRODUCED", "WARN_DRIFT")
  )
)
write_json(step2_summary,
           file.path(EVAL_DIR, "5way_retrain_v3c_arch_upgrade_step2.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Step 2] Summary JSON: %s\n",
            file.path(EVAL_DIR, "5way_retrain_v3c_arch_upgrade_step2.json")))

cat("\n========== Step 2 DONE — Run scripts/82_5way_retrain_v3c_arch_upgrade.py next ==========\n")
