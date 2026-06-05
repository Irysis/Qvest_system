#==============================================================================
# 68_5way_retrain_v2_2feat.R — Cycle 43 B안 PARTIAL_RETAIN
#
# Goal:
#   feature_panel_v1_alt_enhanced (69) + 2 valuable features (breadth + foreign)
#   → 71 features panel (v2_2feat)
#   → 5-way ensemble retrain (XGB / CatBoost / RF / LSTM / TFT)
#   → 5-way Dynamic M2 Regime ensemble synthesis
#   → OOS PR-AUC compare vs V1.3 baseline 0.608
#
# Decision rule:
#   ΔPR-AUC ≥ +0.03 → admit cycle 권고
#   0 ~ +0.03 → 보존만, deploy 미반영
#   < 0 → 신규 features 무가치
#
# Steps in this R script:
#   Step 1: Build v2_2feat panel (69 + breadth + foreign = 71 features)
#   Step 2: Multi-algorithm 3-way retrain (XGB / CatBoost / RF)
#   Step 3: (LSTM/TFT는 별도 Python script 69)
#   Step 4: 5-way merge after Python 완료
#   Step 5: Dynamic M2 Regime synthesis
#   Step 6: Compare + verdict
#
# PIT contract:
#   - 모든 신규 features lag-1 적용
#   - foreign 2020-01부터 → pre-2020 NA fill으로 imputed median
#   - breadth 1990-01부터 (n_active≥100 filter)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v2_2feat")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# Walk-forward splits (same as 12_multi_algorithm_ensemble.R)
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
# Step 1: Build v2_2feat panel (69 + 2 valuable features = 71)
#==============================================================================
cat("\n========== Step 1: Build v2_2feat panel (71 features) ==========\n")

feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")))
feat[, Date := as.Date(Date)]
setorder(feat, Date)
cat(sprintf("[1a] Enhanced baseline panel: %d rows × %d cols (69 features)\n",
            nrow(feat), ncol(feat) - 1))

# Breadth: ad_ratio_5d_avg (already a derivative, compute fresh from raw)
br <- fread(file.path(DATA_DIR, "investor_breadth_daily.csv"))
br[, Date := as.Date(Date)]
br <- br[n_active >= 100]
setorder(br, Date)
br[, ad_ratio_5d_avg := frollmean(ad_ratio, n = 5, align = "right", na.rm = TRUE)]
br[, ad_ratio_5d_avg_lag1 := shift(ad_ratio_5d_avg, 1L, type = "lag")]
cat(sprintf("[1b] Breadth ad_ratio_5d_avg_lag1: %d obs, %s ~ %s\n",
            sum(!is.na(br$ad_ratio_5d_avg_lag1)),
            as.character(min(br$Date)), as.character(max(br$Date))))

# Foreign cum_5d (already saved from prototype)
fr <- fread(file.path(DATA_DIR, "foreign_cum_5d.csv"))
fr[, Date := as.Date(Date)]
setorder(fr, Date)
fr[, foreign_cum_5d_lag1 := shift(foreign_cum_5d, 1L, type = "lag")]
cat(sprintf("[1c] Foreign cum_5d_lag1: %d obs, %s ~ %s\n",
            sum(!is.na(fr$foreign_cum_5d_lag1)),
            as.character(min(fr$Date)), as.character(max(fr$Date))))

# Merge to panel
panel_v2 <- merge(feat,
                   br[, .(Date, ad_ratio_5d_avg_lag1)],
                   by = "Date", all.x = TRUE)
panel_v2 <- merge(panel_v2,
                   fr[, .(Date, foreign_cum_5d_lag1)],
                   by = "Date", all.x = TRUE)
setorder(panel_v2, Date)

cat(sprintf("[1d] v2_2feat panel: %d rows × %d cols (71 features)\n",
            nrow(panel_v2), ncol(panel_v2) - 1))

for (c in c("ad_ratio_5d_avg_lag1", "foreign_cum_5d_lag1")) {
  cov <- sum(!is.na(panel_v2[[c]])) / nrow(panel_v2)
  cat(sprintf("  %-30s: %.1f%% cover (n=%d)\n", c, 100 * cov, sum(!is.na(panel_v2[[c]]))))
}

panel_path <- file.path(DATA_DIR, "feature_panel_v2_2feat.parquet")
write_parquet(panel_v2, panel_path)
cat(sprintf("[1e] Saved: %s\n", panel_path))

#==============================================================================
# Step 2: Multi-algorithm 3-way retrain (XGB / CatBoost / RF)
#==============================================================================
cat("\n========== Step 2: Multi-algorithm 3-way retrain ==========\n")

tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
tgt[, Date := as.Date(Date)]
panel <- merge(panel_v2, tgt[, .(Date, y_tail_q15, y_onset)], by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15", "y_onset"))
cat(sprintf("[2a] Panel for training: %d rows / %d features\n", nrow(panel), length(feature_cols)))

# Median impute (train period)
X_all <- as.matrix(panel[, feature_cols, with = FALSE])
idx_train_all <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
col_meds <- apply(X_all[idx_train_all, , drop = FALSE], 2, function(x) median(x, na.rm = TRUE))
# For columns where train period has all NA (eg foreign 2020+), use 0
col_meds[is.na(col_meds)] <- 0
for (j in seq_len(ncol(X_all))) X_all[is.na(X_all[, j]), j] <- col_meds[j]

idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
idx_valid <- which(panel$Date >= VALID_START & panel$Date <= VALID_END)
idx_oos   <- which(panel$Date >= OOS_START & panel$Date <= OOS_END)

run_target_3way <- function(target_col) {
  cat(sprintf("\n========== Target: %s (3-way GBDT) ==========\n", target_col))
  Y_all <- panel[[target_col]]
  Y_all[is.na(Y_all)] <- 0L
  pos_weight <- sum(Y_all[idx_train] == 0) / max(sum(Y_all[idx_train] == 1), 1)
  pos_weight <- min(pos_weight, 8)

  # M1: XGBoost
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

  # XGB feature importance
  imp_xgb <- as.data.table(xgb.importance(model = xgb_fit))

  # M2: CatBoost
  cat("[M2 CatBoost] training...\n")
  cat_pool_train <- catboost.load_pool(data = X_all[idx_train, ], label = Y_all[idx_train])
  cat_pool_valid <- catboost.load_pool(data = X_all[idx_valid, ], label = Y_all[idx_valid])
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

  # RF importance — ranger returns NULL by default (importance not set).
  # Use NULL-safe fallback to skip RF importance if not computed.
  rf_imp_vec <- rf_fit$variable.importance
  if (is.null(rf_imp_vec) || length(rf_imp_vec) == 0) {
    imp_rf <- data.table(Feature = character(0), Gain = numeric(0), rank = integer(0))
  } else {
    imp_rf <- data.table(Feature = names(rf_imp_vec), Gain = as.numeric(rf_imp_vec))
    setorder(imp_rf, -Gain)
  }

  # 3-way EW baseline
  pred_ew <- (pred_xgb + pred_cat + pred_rf_all) / 3
  pr_ew <- pr_auc(pred_ew[idx_oos], Y_all[idx_oos])
  cat(sprintf("\n[3way EW] OOS PR-AUC: %.4f\n", pr_ew))

  # Save predictions (Date + 4 cols + split + y)
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

  # New features importance ranks
  new_cols <- c("ad_ratio_5d_avg_lag1", "foreign_cum_5d_lag1")
  imp_xgb[, rank := seq_len(.N)]
  imp_new_xgb <- imp_xgb[Feature %in% new_cols, .(Feature, Gain, rank, total = nrow(imp_xgb))]
  if (nrow(imp_rf) > 0) {
    imp_rf[, rank := seq_len(.N)]
    imp_new_rf  <- imp_rf[Feature %in% new_cols, .(Feature, Gain, rank, total = nrow(imp_rf))]
  } else {
    imp_new_rf <- data.table(Feature = character(0), Gain = numeric(0),
                              rank = integer(0), total = integer(0))
  }

  cat("\n[New features importance — XGB]:\n"); print(imp_new_xgb)
  cat("\n[New features importance — RF]:\n");
  if (nrow(imp_new_rf) > 0) print(imp_new_rf) else cat("  (RF importance not computed)\n")

  list(pr_xgb = pr_xgb, pr_cat = pr_cat, pr_rf = pr_rf, pr_ew = pr_ew,
       imp_new_xgb = imp_new_xgb, imp_new_rf = imp_new_rf)
}

res_q15 <- run_target_3way("y_tail_q15")
res_onset <- run_target_3way("y_onset")

cat("\n============================================================\n")
cat("[Step 2 SUMMARY] 3-way GBDT retrain on v2_2feat (71 features)\n")
cat(sprintf("y_tail_q15:  XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_q15$pr_xgb, res_q15$pr_cat, res_q15$pr_rf, res_q15$pr_ew))
cat(sprintf("y_onset:     XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_onset$pr_xgb, res_onset$pr_cat, res_onset$pr_rf, res_onset$pr_ew))
cat(sprintf("\n[Step 2] 3-way preds saved: %s\n", OUT_DIR))

# Save intermediate Step 2 summary for Python script consumption
step2_summary <- list(
  step = "step2_3way_gbdt_retrain",
  panel = panel_path,
  n_features = length(feature_cols),
  new_features = c("ad_ratio_5d_avg_lag1", "foreign_cum_5d_lag1"),
  y_tail_q15 = list(
    xgb = round(res_q15$pr_xgb, 4),
    cat = round(res_q15$pr_cat, 4),
    rf  = round(res_q15$pr_rf, 4),
    ew3 = round(res_q15$pr_ew, 4),
    imp_new_xgb = lapply(seq_len(nrow(res_q15$imp_new_xgb)), function(i) {
      list(feature = res_q15$imp_new_xgb$Feature[i],
           gain = round(res_q15$imp_new_xgb$Gain[i], 4),
           rank = res_q15$imp_new_xgb$rank[i],
           total = res_q15$imp_new_xgb$total[i])
    }),
    imp_new_rf = lapply(seq_len(nrow(res_q15$imp_new_rf)), function(i) {
      list(feature = res_q15$imp_new_rf$Feature[i],
           gain = round(res_q15$imp_new_rf$Gain[i], 4),
           rank = res_q15$imp_new_rf$rank[i],
           total = res_q15$imp_new_rf$total[i])
    })
  ),
  y_onset = list(
    xgb = round(res_onset$pr_xgb, 4),
    cat = round(res_onset$pr_cat, 4),
    rf  = round(res_onset$pr_rf, 4),
    ew3 = round(res_onset$pr_ew, 4)
  )
)
write_json(step2_summary,
           file.path(EVAL_DIR, "5way_retrain_v2_2feat_step2.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Step 2] Summary JSON: %s\n",
            file.path(EVAL_DIR, "5way_retrain_v2_2feat_step2.json")))

cat("\n========== Step 2 DONE — Run scripts/69_5way_retrain_v2_2feat.py next ==========\n")
