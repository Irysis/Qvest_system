#==============================================================================
# 71_5way_retrain_v3_breadth_suite.R — Cycle 44 Breadth Suite Extension
#
# Goal:
#   feature_panel_v1_alt_enhanced (69) + 5 breadth-family features (retain ad_ratio_5d
#   + 4 new) → drop foreign_cum_5d (dead)
#   = 74 features panel (v3_breadth_suite)
#   → 5-way ensemble retrain (XGB / CatBoost / RF / LSTM / TFT)
#   → Compare vs Cycle 43 v2_2feat baseline (M2 Regime 0.6390 / M1 Rolling 0.6459)
#
# Cycle 43 outcome:
#   ad_ratio_5d_avg_lag1: XGB rank 4/44, RF rank 4/71 — VALUABLE, retain
#   foreign_cum_5d_lag1: XGB unused (0 splits), RF gain 0.00 — DEAD, drop
#
# New 4 features (all lag(1), PIT-safe):
#   1. ad_ratio_20d_avg_lag1 — 20일 rolling mean (smoother)
#   2. ad_ratio_60d_avg_lag1 — 60일 rolling mean (quarterly)
#   3. hhi_buy_lag1 — foreign buy distribution HHI concentration
#   4. n_active_z20_lag1 — z-score of n_active over 20d rolling (mean/sd past 20d only)
#
# Decision rule (vs Cycle 43 v2_2feat M2 Regime 0.6390 baseline):
#   Δ ≥ +0.01 → CONTINUE (keep extending breadth suite)
#   0 < Δ < +0.01 → MARGINAL (preserve, next family)
#   Δ ≤ 0 → REGRESSION (drop breadth, pivot)
#
# Steps in this R script:
#   Step 1: Build v3_breadth_suite panel (69 + 5 breadth = 74 features)
#   Step 2: Multi-algorithm 3-way retrain (XGB / CatBoost / RF)
#   Step 3: (LSTM/TFT는 별도 Python script 72)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v3_breadth_suite")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# Walk-forward splits (identical to Cycle 43 for fair comparison)
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
# Step 1: Build v3_breadth_suite panel (69 + 5 breadth = 74 features)
#==============================================================================
cat("\n========== Step 1: Build v3_breadth_suite panel (74 features) ==========\n")

feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")))
feat[, Date := as.Date(Date)]
setorder(feat, Date)
cat(sprintf("[1a] Enhanced baseline panel: %d rows × %d cols (69 features)\n",
            nrow(feat), ncol(feat) - 1))

# Breadth: load raw + compute 5d/20d/60d MA + hhi + n_active z-score
br <- fread(file.path(DATA_DIR, "investor_breadth_daily.csv"))
br[, Date := as.Date(Date)]
br <- br[n_active >= 100]   # filter sparse early years (1990~2000-01-03)
setorder(br, Date)

# 1) ad_ratio rolling means (5d retained from Cycle 43; 20d, 60d new)
br[, ad_ratio_5d_avg  := frollmean(ad_ratio, n = 5,  align = "right", na.rm = TRUE)]
br[, ad_ratio_20d_avg := frollmean(ad_ratio, n = 20, align = "right", na.rm = TRUE)]
br[, ad_ratio_60d_avg := frollmean(ad_ratio, n = 60, align = "right", na.rm = TRUE)]

# 2) n_active 20d rolling z-score (mean and sd over past 20d only — strict PIT)
#    Use frollapply with custom function — last point of window z-scored within own window
roll_z <- function(x) {
  if (length(x) < 5 || sum(!is.na(x)) < 5) return(NA_real_)
  mu <- mean(x, na.rm = TRUE); sg <- sd(x, na.rm = TRUE)
  if (is.na(sg) || sg < 1e-6) return(0.0)
  (x[length(x)] - mu) / sg
}
br[, n_active_z20 := frollapply(n_active, n = 20, FUN = roll_z, align = "right", fill = NA_real_)]

# Apply lag(1) to all 5 breadth signals (PIT contract: t-1 for sig_date t decision)
br[, ad_ratio_5d_avg_lag1  := shift(ad_ratio_5d_avg,  1L, type = "lag")]
br[, ad_ratio_20d_avg_lag1 := shift(ad_ratio_20d_avg, 1L, type = "lag")]
br[, ad_ratio_60d_avg_lag1 := shift(ad_ratio_60d_avg, 1L, type = "lag")]
br[, hhi_buy_lag1          := shift(hhi_buy,          1L, type = "lag")]
br[, n_active_z20_lag1     := shift(n_active_z20,     1L, type = "lag")]

cat("[1b] Breadth suite (5 features lag1) coverage:\n")
for (c in c("ad_ratio_5d_avg_lag1", "ad_ratio_20d_avg_lag1", "ad_ratio_60d_avg_lag1",
            "hhi_buy_lag1", "n_active_z20_lag1")) {
  n_obs <- sum(!is.na(br[[c]]))
  cat(sprintf("  %-30s: %5d obs (%s ~ %s)\n",
              c, n_obs,
              as.character(min(br$Date[!is.na(br[[c]])])),
              as.character(max(br$Date[!is.na(br[[c]])]))))
}

# Merge to panel — 5 breadth features (NOT foreign_cum_5d)
panel_v3 <- merge(feat,
                  br[, .(Date,
                         ad_ratio_5d_avg_lag1,
                         ad_ratio_20d_avg_lag1,
                         ad_ratio_60d_avg_lag1,
                         hhi_buy_lag1,
                         n_active_z20_lag1)],
                  by = "Date", all.x = TRUE)
setorder(panel_v3, Date)

cat(sprintf("\n[1c] v3_breadth_suite panel: %d rows × %d cols (74 features)\n",
            nrow(panel_v3), ncol(panel_v3) - 1))

# Coverage report
for (c in c("ad_ratio_5d_avg_lag1", "ad_ratio_20d_avg_lag1", "ad_ratio_60d_avg_lag1",
            "hhi_buy_lag1", "n_active_z20_lag1")) {
  cov <- sum(!is.na(panel_v3[[c]])) / nrow(panel_v3)
  cat(sprintf("  %-30s: %.1f%% cover (n=%d)\n",
              c, 100 * cov, sum(!is.na(panel_v3[[c]]))))
}

panel_path <- file.path(DATA_DIR, "feature_panel_v3_breadth_suite.parquet")
write_parquet(panel_v3, panel_path)
cat(sprintf("\n[1d] Saved: %s\n", panel_path))

#==============================================================================
# Step 2: Multi-algorithm 3-way retrain (XGB / CatBoost / RF)
#==============================================================================
cat("\n========== Step 2: Multi-algorithm 3-way retrain ==========\n")

tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
tgt[, Date := as.Date(Date)]
panel <- merge(panel_v3, tgt[, .(Date, y_tail_q15, y_onset)], by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15", "y_onset"))
cat(sprintf("[2a] Panel for training: %d rows / %d features\n",
            nrow(panel), length(feature_cols)))

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

  # CatBoost feature importance (PredictionValuesChange — analog of XGB gain)
  cat_imp_raw <- catboost.get_feature_importance(cat_fit, pool = cat_pool_train,
                                                  type = "PredictionValuesChange")
  imp_cat <- data.table(Feature = feature_cols, Gain = as.numeric(cat_imp_raw))
  setorder(imp_cat, -Gain)

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
  write_parquet(preds, file.path(OUT_DIR, sprintf("predictions_3way_%s.parquet", target_col)))

  # New + retained breadth features importance rank
  breadth_cols <- c("ad_ratio_5d_avg_lag1",
                    "ad_ratio_20d_avg_lag1",
                    "ad_ratio_60d_avg_lag1",
                    "hhi_buy_lag1",
                    "n_active_z20_lag1")

  imp_xgb[, rank := seq_len(.N)]
  imp_new_xgb <- imp_xgb[Feature %in% breadth_cols, .(Feature, Gain, rank, total = nrow(imp_xgb))]
  # XGB doesn't include unused features in importance — flag dead
  for (bc in breadth_cols) {
    if (!(bc %in% imp_new_xgb$Feature)) {
      imp_new_xgb <- rbind(imp_new_xgb,
                            data.table(Feature = bc, Gain = 0, rank = nrow(imp_xgb) + 1L,
                                       total = nrow(imp_xgb)))
    }
  }
  setorder(imp_new_xgb, rank)

  imp_cat[, rank := seq_len(.N)]
  imp_new_cat <- imp_cat[Feature %in% breadth_cols, .(Feature, Gain, rank, total = nrow(imp_cat))]

  if (nrow(imp_rf) > 0) {
    imp_rf[, rank := seq_len(.N)]
    imp_new_rf  <- imp_rf[Feature %in% breadth_cols, .(Feature, Gain, rank, total = nrow(imp_rf))]
  } else {
    imp_new_rf <- data.table(Feature = character(0), Gain = numeric(0),
                              rank = integer(0), total = integer(0))
  }

  cat("\n[Breadth features importance — XGB]:\n"); print(imp_new_xgb)
  cat("\n[Breadth features importance — CatBoost]:\n"); print(imp_new_cat)
  cat("\n[Breadth features importance — RF]:\n");
  if (nrow(imp_new_rf) > 0) print(imp_new_rf) else cat("  (RF importance not computed)\n")

  list(pr_xgb = pr_xgb, pr_cat = pr_cat, pr_rf = pr_rf, pr_ew = pr_ew,
       imp_new_xgb = imp_new_xgb, imp_new_cat = imp_new_cat, imp_new_rf = imp_new_rf)
}

res_q15 <- run_target_3way("y_tail_q15")
res_onset <- run_target_3way("y_onset")

cat("\n============================================================\n")
cat("[Step 2 SUMMARY] 3-way GBDT retrain on v3_breadth_suite (74 features)\n")
cat(sprintf("y_tail_q15:  XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_q15$pr_xgb, res_q15$pr_cat, res_q15$pr_rf, res_q15$pr_ew))
cat(sprintf("y_onset:     XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_onset$pr_xgb, res_onset$pr_cat, res_onset$pr_rf, res_onset$pr_ew))
cat(sprintf("\n[Step 2] 3-way preds saved: %s\n", OUT_DIR))

# Save intermediate Step 2 summary
imp_to_list <- function(dt) {
  if (nrow(dt) == 0) return(list())
  lapply(seq_len(nrow(dt)), function(i) {
    list(feature = dt$Feature[i],
         gain = round(dt$Gain[i], 4),
         rank = dt$rank[i],
         total = dt$total[i])
  })
}

step2_summary <- list(
  step = "step2_3way_gbdt_retrain",
  cycle = 44,
  panel = panel_path,
  n_features = length(feature_cols),
  new_features = c("ad_ratio_20d_avg_lag1", "ad_ratio_60d_avg_lag1",
                    "hhi_buy_lag1", "n_active_z20_lag1"),
  retained_features = c("ad_ratio_5d_avg_lag1"),
  dropped_features = c("foreign_cum_5d_lag1"),
  y_tail_q15 = list(
    xgb = round(res_q15$pr_xgb, 4),
    cat = round(res_q15$pr_cat, 4),
    rf  = round(res_q15$pr_rf, 4),
    ew3 = round(res_q15$pr_ew, 4),
    imp_breadth_xgb = imp_to_list(res_q15$imp_new_xgb),
    imp_breadth_cat = imp_to_list(res_q15$imp_new_cat),
    imp_breadth_rf  = imp_to_list(res_q15$imp_new_rf)
  ),
  y_onset = list(
    xgb = round(res_onset$pr_xgb, 4),
    cat = round(res_onset$pr_cat, 4),
    rf  = round(res_onset$pr_rf, 4),
    ew3 = round(res_onset$pr_ew, 4),
    imp_breadth_xgb = imp_to_list(res_onset$imp_new_xgb),
    imp_breadth_cat = imp_to_list(res_onset$imp_new_cat),
    imp_breadth_rf  = imp_to_list(res_onset$imp_new_rf)
  )
)
write_json(step2_summary,
           file.path(EVAL_DIR, "5way_retrain_v3_breadth_suite_step2.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Step 2] Summary JSON: %s\n",
            file.path(EVAL_DIR, "5way_retrain_v3_breadth_suite_step2.json")))

cat("\n========== Step 2 DONE — Run scripts/72_5way_retrain_v3_breadth_suite.py next ==========\n")
