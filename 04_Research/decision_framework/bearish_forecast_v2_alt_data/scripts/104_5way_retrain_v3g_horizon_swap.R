#==============================================================================
# 104_5way_retrain_v3g_horizon_swap.R — Cycle 48A Target Horizon Swap (R portion)
#
# Goal:
#   Cycle 47B v3f_us_macro panel (73 features, identical, frozen) +
#   3 targets {y_tail_q15 control, y_tail_q63, y_tail_q126}
#   → 3-way GBDT retrain (XGB / CatBoost / Ranger RF)
#
# Hypothesis (Cycle 48A):
#   US macro features (CFNAI / yield curve / claims / financial stress) are
#   12-24m leading. 47B q15 (21d) dilution may be horizon mismatch.
#   Expected: q63/q126 PR-AUC > q15 → US macro signal aligned with longer horizons.
#
# Mirror: scripts/96_5way_retrain_v3f_us_macro.R (Step 2 only — panel build
# in 96 already saved feature_panel_v3f_us_macro.parquet)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v3g_horizon_swap")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)
set.seed(42)

# Walk-forward splits — identical to 96 / 47B
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
# Load frozen v3f panel + new long-horizon targets
#==============================================================================
cat("\n========== Cycle 48A: Load panel + 3 targets ==========\n")

panel_v3f <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v3f_us_macro.parquet")))
panel_v3f[, Date := as.Date(Date)]
setorder(panel_v3f, Date)
cat(sprintf("[panel] v3f_us_macro: %d rows × %d cols (73 features)\n",
            nrow(panel_v3f), ncol(panel_v3f) - 1))

tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_long_horizon.parquet")))
tgt[, Date := as.Date(Date)]
cat(sprintf("[targets] long_horizon: %d rows × %d cols (y_tail_q15/q63/q126)\n",
            nrow(tgt), ncol(tgt) - 1))

panel <- merge(panel_v3f,
                tgt[, .(Date, y_tail_q15, y_tail_q63, y_tail_q126)],
                by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel),
                         c("Date", "y_tail_q15", "y_tail_q63", "y_tail_q126"))
cat(sprintf("[merged] rows=%d  feature_cols=%d\n", nrow(panel), length(feature_cols)))

#==============================================================================
# Median impute (TRAIN_window medians) + indexing
#==============================================================================
X_all <- as.matrix(panel[, feature_cols, with = FALSE])
idx_train_all <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
col_meds <- apply(X_all[idx_train_all, , drop = FALSE], 2, function(x) median(x, na.rm = TRUE))
col_meds[is.na(col_meds)] <- 0
for (j in seq_len(ncol(X_all))) X_all[is.na(X_all[, j]), j] <- col_meds[j]

idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
idx_valid <- which(panel$Date >= VALID_START & panel$Date <= VALID_END)
idx_oos   <- which(panel$Date >= OOS_START & panel$Date <= OOS_END)
cat(sprintf("[indices] train=%d / valid=%d / oos=%d\n",
            length(idx_train), length(idx_valid), length(idx_oos)))

#==============================================================================
# Per-target 3-way GBDT
#==============================================================================
run_target_3way <- function(target_col) {
  cat(sprintf("\n========== Target: %s (3-way GBDT) ==========\n", target_col))

  Y_all <- panel[[target_col]]
  # Trim NA targets at OOS tail (last N days have no future return)
  # For training: NA → 0 (safe, since we restrict to TRAIN/VALID windows where
  # forward return is realized: latest realized for q63 is 2026-02-23,
  # q126 is 2025-11-18 — both well within OOS_END 2026-04-30 means we lose
  # last ~3m or ~6m of OOS sample, which we explicitly mask).
  oos_valid_mask <- !is.na(Y_all[idx_oos])
  idx_oos_eff <- idx_oos[oos_valid_mask]
  cat(sprintf("[%s] OOS effective: %d (full %d - %d NA tail)\n",
              target_col, length(idx_oos_eff), length(idx_oos),
              length(idx_oos) - length(idx_oos_eff)))

  Y_train <- Y_all[idx_train]; Y_train[is.na(Y_train)] <- 0L
  Y_valid <- Y_all[idx_valid]; Y_valid[is.na(Y_valid)] <- 0L
  pos_weight <- sum(Y_train == 0) / max(sum(Y_train == 1), 1)
  pos_weight <- min(pos_weight, 8)

  # M1: XGBoost
  cat(sprintf("[M1 XGB] pos_weight=%.2f / training...\n", pos_weight))
  dtrain <- xgb.DMatrix(X_all[idx_train, ], label = Y_train)
  dvalid <- xgb.DMatrix(X_all[idx_valid, ], label = Y_valid)
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
  pr_xgb <- pr_auc(pred_xgb[idx_oos_eff], Y_all[idx_oos_eff])
  cat(sprintf("[M1 XGB] OOS PR-AUC: %.4f (best_iter=%d)\n",
              pr_xgb, xgb_fit$best_iteration))
  imp_xgb <- as.data.table(xgb.importance(model = xgb_fit))

  # M2: CatBoost
  cat("[M2 CatBoost] training...\n")
  cat_pool_train <- catboost.load_pool(data = X_all[idx_train, ], label = Y_train)
  cat_pool_valid <- catboost.load_pool(data = X_all[idx_valid, ], label = Y_valid)
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
  pr_cat <- pr_auc(pred_cat[idx_oos_eff], Y_all[idx_oos_eff])
  cat(sprintf("[M2 CatBoost] OOS PR-AUC: %.4f\n", pr_cat))
  imp_cat <- as.data.table(catboost.get_feature_importance(cat_fit))
  if (ncol(imp_cat) >= 1) {
    setnames(imp_cat, 1, "Gain")
    imp_cat[, Feature := feature_cols]
    setorder(imp_cat, -Gain)
  }

  # M3: Ranger RF
  cat("[M3 Ranger RF] training (1000 trees, mtry=sqrt(p))...\n")
  rf_data <- as.data.table(X_all[idx_train, ])
  rf_data[, y := Y_train]
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
  pr_rf <- pr_auc(pred_rf_all[idx_oos_eff], Y_all[idx_oos_eff])
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
  pr_ew <- pr_auc(pred_ew[idx_oos_eff], Y_all[idx_oos_eff])
  cat(sprintf("\n[3way EW] OOS PR-AUC: %.4f\n", pr_ew))

  # Save predictions (full panel, mark split + target). Aggregator (106) selects oos.
  preds <- data.table(
    Date = panel$Date,
    split = fcase(
      panel$Date >= OOS_START & panel$Date <= OOS_END, "oos",
      panel$Date >= VALID_START & panel$Date <= VALID_END, "valid",
      panel$Date >= TRAIN_START & panel$Date <= TRAIN_END, "train",
      default = "other"
    ),
    target = target_col,
    y = Y_all,                # may contain NA in trailing window
    p_xgb = pred_xgb,
    p_cat = pred_cat,
    p_rf  = pred_rf_all,
    p_ew  = pred_ew
  )
  write_parquet(preds, file.path(OUT_DIR, sprintf("predictions_3way_%s.parquet", target_col)))

  # US macro features importance rank
  new_cols <- c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
                "us_cfnai_lag1", "us_stlfsi_lag1")
  imp_xgb[, rank := seq_len(.N)]
  imp_new_xgb <- imp_xgb[Feature %in% new_cols, .(Feature, Gain, rank, total = nrow(imp_xgb))]

  if (nrow(imp_cat) > 0) {
    imp_cat[, rank := seq_len(.N)]
    imp_new_cat <- imp_cat[Feature %in% new_cols, .(Feature, Gain, rank, total = nrow(imp_cat))]
  } else {
    imp_new_cat <- data.table(Feature = character(0), Gain = numeric(0),
                               rank = integer(0), total = integer(0))
  }

  if (nrow(imp_rf) > 0) {
    imp_rf[, rank := seq_len(.N)]
    imp_new_rf  <- imp_rf[Feature %in% new_cols, .(Feature, Gain, rank, total = nrow(imp_rf))]
  } else {
    imp_new_rf <- data.table(Feature = character(0), Gain = numeric(0),
                              rank = integer(0), total = integer(0))
  }

  cat("\n[US macro features importance — XGB]:\n"); print(imp_new_xgb)
  cat("\n[US macro features importance — CatBoost]:\n");
  if (nrow(imp_new_cat) > 0) print(imp_new_cat) else cat("  (Cat importance not computed)\n")
  cat("\n[US macro features importance — RF]:\n");
  if (nrow(imp_new_rf) > 0) print(imp_new_rf) else cat("  (RF importance not computed)\n")

  list(pr_xgb = pr_xgb, pr_cat = pr_cat, pr_rf = pr_rf, pr_ew = pr_ew,
       n_oos_eff = length(idx_oos_eff),
       imp_new_xgb = imp_new_xgb, imp_new_cat = imp_new_cat, imp_new_rf = imp_new_rf)
}

res_q15  <- run_target_3way("y_tail_q15")
res_q63  <- run_target_3way("y_tail_q63")
res_q126 <- run_target_3way("y_tail_q126")

cat("\n============================================================\n")
cat("[Step R SUMMARY] 3-way GBDT — 73 features × 3 horizons\n")
cat(sprintf("y_tail_q15   (21d) : XGB=%.4f / CAT=%.4f / RF=%.4f / EW3=%.4f / n_oos=%d\n",
            res_q15$pr_xgb, res_q15$pr_cat, res_q15$pr_rf, res_q15$pr_ew, res_q15$n_oos_eff))
cat(sprintf("y_tail_q63   (63d) : XGB=%.4f / CAT=%.4f / RF=%.4f / EW3=%.4f / n_oos=%d\n",
            res_q63$pr_xgb, res_q63$pr_cat, res_q63$pr_rf, res_q63$pr_ew, res_q63$n_oos_eff))
cat(sprintf("y_tail_q126  (126d): XGB=%.4f / CAT=%.4f / RF=%.4f / EW3=%.4f / n_oos=%d\n",
            res_q126$pr_xgb, res_q126$pr_cat, res_q126$pr_rf, res_q126$pr_ew, res_q126$n_oos_eff))

# Save intermediate Step R summary
imp_to_list <- function(dt) {
  if (nrow(dt) == 0) return(list())
  lapply(seq_len(nrow(dt)), function(i) {
    list(feature = dt$Feature[i],
         gain = round(dt$Gain[i], 4),
         rank = as.integer(dt$rank[i]),
         total = as.integer(dt$total[i]))
  })
}

pack_res <- function(r) list(
  xgb = round(r$pr_xgb, 4),
  cat = round(r$pr_cat, 4),
  rf  = round(r$pr_rf, 4),
  ew3 = round(r$pr_ew, 4),
  n_oos_eff = r$n_oos_eff,
  imp_new_xgb = imp_to_list(r$imp_new_xgb),
  imp_new_cat = imp_to_list(r$imp_new_cat),
  imp_new_rf  = imp_to_list(r$imp_new_rf)
)

step_summary <- list(
  step = "step_R_3way_gbdt_retrain",
  cycle = "48A",
  approach = "TARGET_HORIZON_SWAP_y_tail_q15_q63_q126_on_v3f_us_macro_panel",
  panel = file.path(DATA_DIR, "feature_panel_v3f_us_macro.parquet"),
  targets = file.path(TGT_DIR, "targets_long_horizon.parquet"),
  n_features = length(feature_cols),
  walk_forward_splits = list(
    train = "1995-01-01 ~ 2009-12-31",
    valid = "2010-01-01 ~ 2015-12-31",
    oos   = "2016-01-01 ~ 2026-04-30 (trim trailing NA per horizon)"
  ),
  y_tail_q15  = pack_res(res_q15),
  y_tail_q63  = pack_res(res_q63),
  y_tail_q126 = pack_res(res_q126)
)
write_json(step_summary,
           file.path(EVAL_DIR, "5way_retrain_v3g_horizon_swap_step_R.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Step R] Summary JSON: %s\n",
            file.path(EVAL_DIR, "5way_retrain_v3g_horizon_swap_step_R.json")))

cat("\n========== Step R DONE — Run scripts/105_5way_retrain_v3g_horizon_swap.py next ==========\n")
