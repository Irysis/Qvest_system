#==============================================================================
# 74_5way_retrain_v3a_vkospi_suite.R — Cycle 45A VKOSPI Suite Extension
#
# Goal:
#   feature_panel_v1_alt_enhanced (69) + 4 VKOSPI-family features (all lag1 PIT)
#   = 73 features panel (v3a_vkospi_suite)
#   → 5-way ensemble retrain (XGB / CatBoost / RF / LSTM / TFT)
#   → Compare vs v1.3 baseline M2 Regime PR-AUC 0.6078
#
# 4 new features (all lag1, PIT-safe):
#   1. vkospi_lag1                — VKOSPI level (Korean fear gauge)
#   2. vkospi_change_5d_lag1      — 5-day momentum (VKOSPI / lag5 - 1)
#   3. vkospi_vix_spread_lag1     — VKOSPI - VIX (Korean specific risk premium)
#   4. vkospi_z60_lag1            — 60-day rolling z-score (expanding mean/sd until t-60)
#
# Source data:
#   outputs/01_data/vkospi_daily.csv (Date, VKOSPI, 2003-01-02 ~ 2026-05-15)
#   outputs/01_data/vix_daily_fred.csv (Date, vix_close, 1990+)
#
# Pre-2003 NA handling: VKOSPI history begins 2003-01-02 → pre-2003 rows have NA
# for all 4 VKOSPI features. Training period 2009-01+ → no overlap. Median impute on
# train period (2009+) used for GBDT (numpy median of available rows).
#
# Decision rule (vs v1.3 baseline M2 Regime 0.6078):
#   Δ M2 Regime ≥ +0.01 → CONTINUE
#   0 < Δ < +0.01 → MARGINAL
#   Δ ≤ 0 → REGRESSION
#
# Steps (R):
#   Step 1: Build v3a_vkospi_suite panel (69 + 4 VKOSPI = 73 features)
#   Step 2: Multi-algorithm 3-way retrain (XGB / CatBoost / RF)
#   Step 3+ (Python script 75)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v3a_vkospi_suite")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# Walk-forward splits (identical to Cycle 43/44 for fair comparison)
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
# Step 1: Build v3a_vkospi_suite panel (69 + 4 VKOSPI = 73 features)
#==============================================================================
cat("\n========== Step 1: Build v3a_vkospi_suite panel (73 features) ==========\n")

feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")))
feat[, Date := as.Date(Date)]
setorder(feat, Date)
cat(sprintf("[1a] v1_alt_enhanced baseline panel: %d rows x %d cols (69 features + Date)\n",
            nrow(feat), ncol(feat) - 1))

# Load VKOSPI
vk <- fread(file.path(DATA_DIR, "vkospi_daily.csv"))
vk[, Date := as.Date(Date)]
setnames(vk, "VKOSPI", "vkospi_close")
setorder(vk, Date)
cat(sprintf("[1b] VKOSPI raw: %d rows (%s ~ %s)\n",
            nrow(vk), as.character(min(vk$Date)), as.character(max(vk$Date))))

# Load VIX (FRED)
vx <- fread(file.path(DATA_DIR, "vix_daily_fred.csv"))
vx[, Date := as.Date(Date)]
setorder(vx, Date)
cat(sprintf("[1c] VIX raw: %d rows (%s ~ %s)\n",
            nrow(vx), as.character(min(vx$Date)), as.character(max(vx$Date))))

# 1) vkospi level (raw)
# 2) 5-day momentum
vk[, vkospi_change_5d := vkospi_close / shift(vkospi_close, 5L, type = "lag") - 1]

# 3) Merge VIX for spread
vk2 <- merge(vk, vx[, .(Date, vix_close)], by = "Date", all.x = TRUE)
setorder(vk2, Date)
vk2[, vkospi_vix_spread := vkospi_close - vix_close]

# 4) 60-day rolling z-score (causal — mean and sd over past 60d only, strict PIT)
roll_z60 <- function(x) {
  if (length(x) < 30 || sum(!is.na(x)) < 30) return(NA_real_)
  mu <- mean(x, na.rm = TRUE); sg <- sd(x, na.rm = TRUE)
  if (is.na(sg) || sg < 1e-8) return(0.0)
  (x[length(x)] - mu) / sg
}
vk2[, vkospi_z60 := frollapply(vkospi_close, n = 60, FUN = roll_z60, align = "right", fill = NA_real_)]

# Apply lag(1) to all 4 VKOSPI signals (PIT contract: t-1 for sig_date t decision)
vk2[, vkospi_lag1               := shift(vkospi_close,        1L, type = "lag")]
vk2[, vkospi_change_5d_lag1     := shift(vkospi_change_5d,    1L, type = "lag")]
vk2[, vkospi_vix_spread_lag1    := shift(vkospi_vix_spread,   1L, type = "lag")]
vk2[, vkospi_z60_lag1           := shift(vkospi_z60,          1L, type = "lag")]

cat("\n[1d] VKOSPI suite (4 features lag1) coverage on raw VKOSPI dates:\n")
for (c in c("vkospi_lag1", "vkospi_change_5d_lag1", "vkospi_vix_spread_lag1", "vkospi_z60_lag1")) {
  n_obs <- sum(!is.na(vk2[[c]]))
  cat(sprintf("  %-28s: %5d obs (%s ~ %s)\n",
              c, n_obs,
              as.character(min(vk2$Date[!is.na(vk2[[c]])])),
              as.character(max(vk2$Date[!is.na(vk2[[c]])]))))
}

# Merge to main panel — 4 VKOSPI features only (no foreign / institutional)
panel_v3a <- merge(feat,
                   vk2[, .(Date,
                           vkospi_lag1,
                           vkospi_change_5d_lag1,
                           vkospi_vix_spread_lag1,
                           vkospi_z60_lag1)],
                   by = "Date", all.x = TRUE)
setorder(panel_v3a, Date)

cat(sprintf("\n[1e] v3a_vkospi_suite panel: %d rows x %d cols (%d features + Date)\n",
            nrow(panel_v3a), ncol(panel_v3a), ncol(panel_v3a) - 1))

# Coverage report on full panel
for (c in c("vkospi_lag1", "vkospi_change_5d_lag1", "vkospi_vix_spread_lag1", "vkospi_z60_lag1")) {
  cov_full <- sum(!is.na(panel_v3a[[c]])) / nrow(panel_v3a)
  cov_train <- sum(!is.na(panel_v3a[[c]][panel_v3a$Date >= TRAIN_START & panel_v3a$Date <= TRAIN_END])) /
    sum(panel_v3a$Date >= TRAIN_START & panel_v3a$Date <= TRAIN_END)
  cov_oos <- sum(!is.na(panel_v3a[[c]][panel_v3a$Date >= OOS_START & panel_v3a$Date <= OOS_END])) /
    sum(panel_v3a$Date >= OOS_START & panel_v3a$Date <= OOS_END)
  cat(sprintf("  %-28s: full=%.1f%% / train_1995_2009=%.1f%% / OOS_2016_2026=%.1f%%\n",
              c, 100*cov_full, 100*cov_train, 100*cov_oos))
}

panel_path <- file.path(DATA_DIR, "feature_panel_v3a_vkospi_suite.parquet")
write_parquet(panel_v3a, panel_path)
cat(sprintf("\n[1f] Saved: %s\n", panel_path))

#==============================================================================
# Step 2: Multi-algorithm 3-way retrain (XGB / CatBoost / RF)
#==============================================================================
cat("\n========== Step 2: Multi-algorithm 3-way retrain ==========\n")

tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
tgt[, Date := as.Date(Date)]
panel <- merge(panel_v3a, tgt[, .(Date, y_tail_q15, y_onset)], by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15", "y_onset"))
cat(sprintf("[2a] Panel for training: %d rows / %d features\n",
            nrow(panel), length(feature_cols)))

# Median impute (train period)
X_all <- as.matrix(panel[, feature_cols, with = FALSE])
idx_train_all <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
col_meds <- apply(X_all[idx_train_all, , drop = FALSE], 2, function(x) median(x, na.rm = TRUE))
col_meds[is.na(col_meds)] <- 0  # for VKOSPI cols pre-2009: median NA → 0 fallback
for (j in seq_len(ncol(X_all))) X_all[is.na(X_all[, j]), j] <- col_meds[j]

cat(sprintf("[2b] Train-period medians for 4 VKOSPI features (pre-2003 = NA on full panel):\n"))
for (vk_col in c("vkospi_lag1", "vkospi_change_5d_lag1", "vkospi_vix_spread_lag1", "vkospi_z60_lag1")) {
  j <- which(feature_cols == vk_col)
  cat(sprintf("  %-28s: train_median=%.4f (NA-fill applied to pre-2003 rows)\n",
              vk_col, col_meds[j]))
}

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

  # 3-way EW
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

  # VKOSPI feature importance rank per model
  vkospi_cols <- c("vkospi_lag1", "vkospi_change_5d_lag1",
                   "vkospi_vix_spread_lag1", "vkospi_z60_lag1")

  imp_xgb[, rank := seq_len(.N)]
  imp_new_xgb <- imp_xgb[Feature %in% vkospi_cols, .(Feature, Gain, rank, total = nrow(imp_xgb))]
  # XGB doesn't include unused features in importance — flag dead
  for (bc in vkospi_cols) {
    if (!(bc %in% imp_new_xgb$Feature)) {
      imp_new_xgb <- rbind(imp_new_xgb,
                            data.table(Feature = bc, Gain = 0, rank = nrow(imp_xgb) + 1L,
                                       total = nrow(imp_xgb)))
    }
  }
  setorder(imp_new_xgb, rank)

  imp_cat[, rank := seq_len(.N)]
  imp_new_cat <- imp_cat[Feature %in% vkospi_cols, .(Feature, Gain, rank, total = nrow(imp_cat))]

  if (nrow(imp_rf) > 0) {
    imp_rf[, rank := seq_len(.N)]
    imp_new_rf  <- imp_rf[Feature %in% vkospi_cols, .(Feature, Gain, rank, total = nrow(imp_rf))]
  } else {
    imp_new_rf <- data.table(Feature = character(0), Gain = numeric(0),
                              rank = integer(0), total = integer(0))
  }

  cat("\n[VKOSPI features importance - XGB]:\n"); print(imp_new_xgb)
  cat("\n[VKOSPI features importance - CatBoost]:\n"); print(imp_new_cat)
  cat("\n[VKOSPI features importance - RF]:\n")
  if (nrow(imp_new_rf) > 0) print(imp_new_rf) else cat("  (RF importance not computed)\n")

  # Top 10 per model for global context
  cat("\n[Top 10 features - XGB]:\n"); print(head(imp_xgb[, .(Feature, Gain, rank)], 10))
  cat("\n[Top 10 features - CatBoost]:\n"); print(head(imp_cat[, .(Feature, Gain, rank)], 10))
  if (nrow(imp_rf) > 0) {
    cat("\n[Top 10 features - RF]:\n"); print(head(imp_rf[, .(Feature, Gain, rank)], 10))
  }

  list(pr_xgb = pr_xgb, pr_cat = pr_cat, pr_rf = pr_rf, pr_ew = pr_ew,
       imp_new_xgb = imp_new_xgb, imp_new_cat = imp_new_cat, imp_new_rf = imp_new_rf,
       top10_xgb = head(imp_xgb[, .(Feature, Gain, rank)], 10),
       top10_cat = head(imp_cat[, .(Feature, Gain, rank)], 10),
       top10_rf  = if (nrow(imp_rf) > 0) head(imp_rf[, .(Feature, Gain, rank)], 10) else data.table())
}

res_q15 <- run_target_3way("y_tail_q15")
res_onset <- run_target_3way("y_onset")

cat("\n============================================================\n")
cat("[Step 2 SUMMARY] 3-way GBDT retrain on v3a_vkospi_suite (73 features)\n")
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
  cycle = "45A",
  panel = panel_path,
  n_features = length(feature_cols),
  vkospi_features_new = c("vkospi_lag1", "vkospi_change_5d_lag1",
                           "vkospi_vix_spread_lag1", "vkospi_z60_lag1"),
  pre_2003_NA_handling = "median-impute on train-period (1995-2009) — VKOSPI starts 2003-01-02",
  y_tail_q15 = list(
    xgb = round(res_q15$pr_xgb, 4),
    cat = round(res_q15$pr_cat, 4),
    rf  = round(res_q15$pr_rf, 4),
    ew3 = round(res_q15$pr_ew, 4),
    imp_vkospi_xgb = imp_to_list(res_q15$imp_new_xgb),
    imp_vkospi_cat = imp_to_list(res_q15$imp_new_cat),
    imp_vkospi_rf  = imp_to_list(res_q15$imp_new_rf),
    top10_xgb = imp_to_list(res_q15$top10_xgb),
    top10_cat = imp_to_list(res_q15$top10_cat),
    top10_rf  = imp_to_list(res_q15$top10_rf)
  ),
  y_onset = list(
    xgb = round(res_onset$pr_xgb, 4),
    cat = round(res_onset$pr_cat, 4),
    rf  = round(res_onset$pr_rf, 4),
    ew3 = round(res_onset$pr_ew, 4),
    imp_vkospi_xgb = imp_to_list(res_onset$imp_new_xgb),
    imp_vkospi_cat = imp_to_list(res_onset$imp_new_cat),
    imp_vkospi_rf  = imp_to_list(res_onset$imp_new_rf),
    top10_xgb = imp_to_list(res_onset$top10_xgb),
    top10_cat = imp_to_list(res_onset$top10_cat),
    top10_rf  = imp_to_list(res_onset$top10_rf)
  )
)
write_json(step2_summary,
           file.path(EVAL_DIR, "5way_retrain_v3a_vkospi_suite_step2.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Step 2] Summary JSON: %s\n",
            file.path(EVAL_DIR, "5way_retrain_v3a_vkospi_suite_step2.json")))

cat("\n========== Step 2 DONE - Run scripts/75_5way_retrain_v3a_vkospi_suite.py next ==========\n")
