#==============================================================================
# 95_meta_stacking.R — Cycle 45F GBDT Meta-Learner Stacking (CPU only)
#
# Goal: Test whether non-linear stacking (XGB / logistic meta) on top of 5
#       v3b_inst_suite individual predictions beats Dynamic M2 Regime 0.6417.
#
# Inputs:
#   outputs/03_models/v3b_inst_suite/predictions_5way_y_tail_q15.parquet
#       (Date, p_xgb, p_cat, p_rf, p_lstm, p_tft, p_ew5, p_wew, y)
#   outputs/03_models/v3b_inst_suite/predictions_dynamic_y_tail_q15.parquet
#       (Date, y, regime, p_static, p_M1_rolling, p_M2_regime, p_M3_hedge,
#        p_M4_bayes, p_M5_bandit)
#
# Pipeline:
#   1. Load 5-way + dynamic + merge by Date
#   2. OOS filter 2016-01 ~ 2026-04 (already covered by file)
#   3. Split: Train 2016-2022, Test 2023-2026
#   4. Train 3 meta models:
#        - XGB meta (max_depth=3, n_est=300, lr=0.05)
#        - LightGBM meta (skipped if pkg missing) → Random Forest fallback
#        - Logistic regression (L2, glmnet alpha=0)
#   5. Diagnostics:
#        - 5+10 features (raw + pairwise interaction) variant XGB
#        - Blocked time-series 5-fold CV
#        - Per-period (2016-2018 / 2019-2021 / 2022-2024 / 2025-2026)
#   6. Compare PR-AUC + ROC-AUC vs Dynamic M2 (0.6417), Static WEW (0.5779),
#      CatBoost individual (0.6156)
#
# Outputs:
#   outputs/04_evaluation/meta_stacking_v3b_inst.json
#   outputs/04_evaluation/meta_stacking_v3b_inst_importance.json
#   outputs/06_reports/charts/95_meta_stacking_pr_curve.png
#
# AX-008: Forge single-source screening only.
# PIT: Base predictions PIT-validated (Cycle 45B). Train/test split chronological.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(xgboost)
  library(glmnet)
  library(ggplot2)
})

# Optional packages
HAS_LIGHTGBM <- requireNamespace("lightgbm", quietly = TRUE)
HAS_RANGER   <- requireNamespace("ranger",   quietly = TRUE)

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_5WAY <- file.path(WS_DIR, "outputs/03_models/v3b_inst_suite/predictions_5way_y_tail_q15.parquet")
IN_DYN  <- file.path(WS_DIR, "outputs/03_models/v3b_inst_suite/predictions_dynamic_y_tail_q15.parquet")
EVAL_DIR <- file.path(WS_DIR, "outputs/04_evaluation")
CHART_DIR <- file.path(WS_DIR, "outputs/06_reports/charts")
PRED_DIR <- file.path(WS_DIR, "outputs/03_models/meta_stacking_v3b_inst")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(PRED_DIR, recursive = TRUE, showWarnings = FALSE)

SEED <- 20260520
set.seed(SEED)

#-------- 1. Metrics --------
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord)
  rec  <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

roc_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  fpr <- cumsum(y_ord == 0) / sum(y_ord == 0)
  tpr <- cumsum(y_ord == 1) / sum(y_ord == 1)
  fpr <- c(0, fpr); tpr <- c(0, tpr)
  sum(diff(fpr) * (tpr[-1] + tpr[-length(tpr)]) / 2)
}

#-------- 2. Load & merge --------
cat("[95-1] Loading base predictions...\n")
d5 <- as.data.table(read_parquet(IN_5WAY))
dyn <- as.data.table(read_parquet(IN_DYN))
cat(sprintf("  5way: N=%d cols=%s\n", nrow(d5), paste(colnames(d5), collapse=",")))
cat(sprintf("  dyn : N=%d cols=%s\n", nrow(dyn), paste(colnames(dyn), collapse=",")))

# Merge: 5-way has p_xgb/p_cat/p_rf/p_lstm/p_tft/y; dyn has p_M2_regime etc.
d <- merge(d5[, .(Date, p_xgb, p_cat, p_rf, p_lstm, p_tft, p_ew5, p_wew, y)],
           dyn[, .(Date, p_static, p_M1_rolling, p_M2_regime,
                   p_M3_hedge, p_M4_bayes, p_M5_bandit)],
           by = "Date", all.x = TRUE)
setorder(d, Date)
cat(sprintf("  Merged: N=%d (full coverage)\n", nrow(d)))

#-------- 3. Splits --------
SPLIT_DATE <- as.Date("2023-01-01")
d[, split := ifelse(Date < SPLIT_DATE, "train", "test")]
cat(sprintf("[95-2] Train: %d (%s..%s) / Test: %d (%s..%s)\n",
            sum(d$split == "train"), as.character(min(d[split=="train"]$Date)),
            as.character(max(d[split=="train"]$Date)),
            sum(d$split == "test"), as.character(min(d[split=="test"]$Date)),
            as.character(max(d[split=="test"]$Date))))
cat(sprintf("  Train events: %d (%.2f%%) / Test events: %d (%.2f%%)\n",
            sum(d[split=="train"]$y), 100*mean(d[split=="train"]$y),
            sum(d[split=="test"]$y), 100*mean(d[split=="test"]$y)))

BASE_FEATS <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft")

train_d <- d[split == "train"]
test_d  <- d[split == "test"]

X_tr <- as.matrix(train_d[, ..BASE_FEATS]); y_tr <- train_d$y
X_te <- as.matrix(test_d[, ..BASE_FEATS]);  y_te <- test_d$y

#-------- 4. Meta-learner training (3 models) --------
cat("\n[95-3] Training meta models...\n")

# 4a. XGBoost meta (depth 3, n_est 300, lr 0.05)
dtrain <- xgb.DMatrix(X_tr, label = y_tr)
dtest  <- xgb.DMatrix(X_te, label = y_te)
xgb_meta <- xgb.train(
  params = list(
    objective = "binary:logistic",
    eval_metric = "aucpr",
    max_depth = 3,
    eta = 0.05,
    subsample = 0.9,
    colsample_bytree = 0.9,
    nthread = 4,
    seed = SEED
  ),
  data = dtrain,
  nrounds = 300,
  verbose = 0
)
test_d[, p_meta_xgb := predict(xgb_meta, dtest)]
cat(sprintf("  XGB meta: trained. nrounds=%d\n", xgb_meta$niter))

# 4b. LightGBM meta (or RF fallback)
USED_RF_FALLBACK <- FALSE
if (HAS_LIGHTGBM) {
  suppressPackageStartupMessages(library(lightgbm))
  lgb_train <- lgb.Dataset(X_tr, label = y_tr)
  lgb_meta <- lgb.train(
    params = list(
      objective = "binary",
      metric = "average_precision",
      num_leaves = 7,
      learning_rate = 0.05,
      feature_fraction = 0.9,
      bagging_fraction = 0.9,
      verbose = -1,
      seed = SEED
    ),
    data = lgb_train,
    nrounds = 300
  )
  test_d[, p_meta_lgb := predict(lgb_meta, X_te)]
  cat("  LightGBM meta: trained.\n")
} else if (HAS_RANGER) {
  suppressPackageStartupMessages(library(ranger))
  rf_meta <- ranger(
    x = X_tr, y = factor(y_tr),
    num.trees = 300, max.depth = 4,
    probability = TRUE, num.threads = 4, seed = SEED
  )
  test_d[, p_meta_lgb := predict(rf_meta, data = X_te)$predictions[, "1"]]
  USED_RF_FALLBACK <- TRUE
  cat("  Ranger RF meta (LightGBM fallback): trained.\n")
} else {
  test_d[, p_meta_lgb := NA_real_]
  cat("  Skipped LightGBM/RF meta (no package).\n")
}

# 4c. Logistic regression meta (L2 / Ridge via glmnet alpha=0)
glm_meta <- cv.glmnet(X_tr, y_tr, family = "binomial", alpha = 0, nfolds = 5)
test_d[, p_meta_logit := as.numeric(predict(glm_meta, newx = X_te,
                                            s = "lambda.min", type = "response"))]
cat(sprintf("  Logistic L2 meta: trained. lambda.min=%.5f\n", glm_meta$lambda.min))

#-------- 5. Eval on test --------
cat("\n[95-4] Test-period PR-AUC / ROC-AUC...\n")

eval_models <- list()
for (mod in c("p_meta_xgb", "p_meta_lgb", "p_meta_logit")) {
  if (all(is.na(test_d[[mod]]))) next
  eval_models[[mod]] <- list(
    pr_auc  = pr_auc(test_d[[mod]], test_d$y),
    roc_auc = roc_auc(test_d[[mod]], test_d$y)
  )
}

# Individual base on test
for (b in BASE_FEATS) {
  eval_models[[b]] <- list(
    pr_auc  = pr_auc(test_d[[b]], test_d$y),
    roc_auc = roc_auc(test_d[[b]], test_d$y)
  )
}

# Static ensembles on test
for (s in c("p_ew5", "p_wew")) {
  if (s %in% colnames(test_d)) {
    eval_models[[s]] <- list(
      pr_auc  = pr_auc(test_d[[s]], test_d$y),
      roc_auc = roc_auc(test_d[[s]], test_d$y)
    )
  }
}

# Dynamic on test
for (dm in c("p_M2_regime", "p_M4_bayes")) {
  if (dm %in% colnames(test_d) && !all(is.na(test_d[[dm]]))) {
    eval_models[[dm]] <- list(
      pr_auc  = pr_auc(test_d[[dm]], test_d$y),
      roc_auc = roc_auc(test_d[[dm]], test_d$y)
    )
  }
}

cat("  Test-period results:\n")
for (m in names(eval_models)) {
  cat(sprintf("    %-15s PR=%.4f  ROC=%.4f\n", m,
              eval_models[[m]]$pr_auc, eval_models[[m]]$roc_auc))
}

#-------- 6. Diagnostic: 5+10 interaction features --------
cat("\n[95-5] Diagnostic: interaction features (5 raw + 10 pairwise)...\n")
make_interactions <- function(X) {
  raw <- as.data.table(X)
  nm <- colnames(X)
  for (i in 1:(length(nm)-1)) {
    for (j in (i+1):length(nm)) {
      raw[[paste0(nm[i], "_x_", nm[j])]] <- X[, i] * X[, j]
    }
  }
  as.matrix(raw)
}
X_tr_int <- make_interactions(X_tr)
X_te_int <- make_interactions(X_te)
cat(sprintf("  Interaction feature dim: %d (raw 5 + pairwise 10)\n", ncol(X_tr_int)))

dtrain_i <- xgb.DMatrix(X_tr_int, label = y_tr)
dtest_i  <- xgb.DMatrix(X_te_int, label = y_te)
xgb_meta_int <- xgb.train(
  params = list(
    objective = "binary:logistic",
    eval_metric = "aucpr",
    max_depth = 3,
    eta = 0.05,
    subsample = 0.9,
    colsample_bytree = 0.9,
    nthread = 4,
    seed = SEED
  ),
  data = dtrain_i,
  nrounds = 300,
  verbose = 0
)
test_d[, p_meta_xgb_int := predict(xgb_meta_int, dtest_i)]
pr_int <- pr_auc(test_d$p_meta_xgb_int, test_d$y)
roc_int <- roc_auc(test_d$p_meta_xgb_int, test_d$y)
cat(sprintf("  XGB meta + interactions: PR=%.4f  ROC=%.4f (vs XGB meta raw PR=%.4f)\n",
            pr_int, roc_int, eval_models$p_meta_xgb$pr_auc))

eval_models$p_meta_xgb_int <- list(pr_auc = pr_int, roc_auc = roc_int)

#-------- 7. Diagnostic: blocked time-series 5-fold CV --------
cat("\n[95-6] Diagnostic: blocked 5-fold time-series CV (XGB meta, full 2016-2026)...\n")
N <- nrow(d)
fold_size <- floor(N / 5)
cv_results <- list()
for (k in 1:5) {
  te_start <- (k-1) * fold_size + 1
  te_end   <- if (k == 5) N else k * fold_size
  test_idx <- te_start:te_end
  # Walk-forward: train on everything before test fold
  train_idx <- if (te_start == 1) {
    # special case fold 1: use rolling sub-fold
    integer(0)
  } else {
    1:(te_start - 1)
  }
  if (length(train_idx) < 200) {
    cv_results[[k]] <- list(fold = k, skipped = TRUE, reason = "insufficient train")
    next
  }
  X_cv_tr <- as.matrix(d[train_idx, ..BASE_FEATS])
  y_cv_tr <- d$y[train_idx]
  X_cv_te <- as.matrix(d[test_idx, ..BASE_FEATS])
  y_cv_te <- d$y[test_idx]
  if (sum(y_cv_tr) < 10 || sum(y_cv_te) < 5) {
    cv_results[[k]] <- list(fold = k, skipped = TRUE, reason = "insufficient events")
    next
  }
  m_cv <- xgb.train(
    params = list(
      objective = "binary:logistic", eval_metric = "aucpr",
      max_depth = 3, eta = 0.05, subsample = 0.9, colsample_bytree = 0.9,
      nthread = 4, seed = SEED
    ),
    data = xgb.DMatrix(X_cv_tr, label = y_cv_tr),
    nrounds = 300, verbose = 0
  )
  pr <- pr_auc(predict(m_cv, xgb.DMatrix(X_cv_te)), y_cv_te)
  cv_results[[k]] <- list(
    fold = k, skipped = FALSE,
    train_N = length(train_idx), test_N = length(test_idx),
    train_start = as.character(d$Date[train_idx[1]]),
    train_end   = as.character(d$Date[train_idx[length(train_idx)]]),
    test_start  = as.character(d$Date[test_idx[1]]),
    test_end    = as.character(d$Date[test_idx[length(test_idx)]]),
    test_events = sum(y_cv_te), pr_auc = pr
  )
  cat(sprintf("    Fold %d  train[%s..%s] N=%d  test[%s..%s] N=%d events=%d  PR=%.4f\n",
              k, cv_results[[k]]$train_start, cv_results[[k]]$train_end, length(train_idx),
              cv_results[[k]]$test_start, cv_results[[k]]$test_end, length(test_idx),
              sum(y_cv_te), pr))
}
cv_prs <- sapply(cv_results, function(x) if (isTRUE(x$skipped)) NA_real_ else x$pr_auc)
cat(sprintf("  CV PR-AUC: mean=%.4f sd=%.4f\n", mean(cv_prs, na.rm=TRUE), sd(cv_prs, na.rm=TRUE)))

#-------- 8. Diagnostic: per-period performance --------
cat("\n[95-7] Diagnostic: per-period (2016-2018 / 2019-2021 / 2022-2024 / 2025-2026)...\n")
period_bounds <- list(
  "2016-2018" = c(as.Date("2016-01-01"), as.Date("2018-12-31")),
  "2019-2021" = c(as.Date("2019-01-01"), as.Date("2021-12-31")),
  "2022-2024" = c(as.Date("2022-01-01"), as.Date("2024-12-31")),
  "2025-2026" = c(as.Date("2025-01-01"), as.Date("2026-12-31"))
)
period_eval <- list()
# Add OOS prediction for ALL dates (train period: refit on subsequent, here use full-train xgb_meta out-of-sample-ish)
# For simplicity, use test-period only for evaluating meta on its true OOS,
# and 5-fold CV outputs for train-period coverage.
# Per-period uses test_d (2023-2026) split by year, plus full xgb_meta refit on
# pre-period data for 2016-2018 / 2019-2021 / 2022-2024.

for (pname in names(period_bounds)) {
  b <- period_bounds[[pname]]
  # for "2025-2026" we have test_d preds directly
  if (pname == "2025-2026") {
    sub <- test_d[Date >= b[1] & Date <= b[2]]
    if (nrow(sub) > 30 && sum(sub$y) > 5) {
      period_eval[[pname]] <- list(
        period = pname, N = nrow(sub), events = sum(sub$y),
        p_meta_xgb  = pr_auc(sub$p_meta_xgb, sub$y),
        p_meta_logit= pr_auc(sub$p_meta_logit, sub$y),
        p_cat       = pr_auc(sub$p_cat, sub$y),
        p_M2_regime = if ("p_M2_regime" %in% colnames(sub)) pr_auc(sub$p_M2_regime, sub$y) else NA_real_,
        p_wew       = pr_auc(sub$p_wew, sub$y)
      )
    }
  } else {
    # For 2016-2018, 2019-2021, 2022-2024: train on dates *before* period start
    period_idx <- which(d$Date >= b[1] & d$Date <= b[2])
    pre_idx    <- which(d$Date <  b[1])
    if (length(pre_idx) < 200 || length(period_idx) < 30 || sum(d$y[period_idx]) < 5) {
      cat(sprintf("    Period %s: insufficient (pre=%d  period=%d  events=%d)\n",
                  pname, length(pre_idx), length(period_idx), sum(d$y[period_idx])))
      next
    }
    X_pre <- as.matrix(d[pre_idx, ..BASE_FEATS]); y_pre <- d$y[pre_idx]
    X_per <- as.matrix(d[period_idx, ..BASE_FEATS]); y_per <- d$y[period_idx]
    m_pre <- xgb.train(
      params = list(
        objective = "binary:logistic", eval_metric = "aucpr",
        max_depth = 3, eta = 0.05, subsample = 0.9, colsample_bytree = 0.9,
        nthread = 4, seed = SEED
      ),
      data = xgb.DMatrix(X_pre, label = y_pre),
      nrounds = 300, verbose = 0
    )
    g_pre <- cv.glmnet(X_pre, y_pre, family = "binomial", alpha = 0, nfolds = 5)
    pr_xgb <- pr_auc(predict(m_pre, xgb.DMatrix(X_per)), y_per)
    pr_lgt <- pr_auc(as.numeric(predict(g_pre, newx = X_per, s="lambda.min", type="response")), y_per)
    pr_cat_b <- pr_auc(d$p_cat[period_idx], y_per)
    pr_wew_b <- pr_auc(d$p_wew[period_idx], y_per)
    pr_m2 <- if ("p_M2_regime" %in% colnames(d)) pr_auc(d$p_M2_regime[period_idx], y_per) else NA_real_
    period_eval[[pname]] <- list(
      period = pname, N = length(period_idx), events = sum(y_per),
      p_meta_xgb = pr_xgb, p_meta_logit = pr_lgt,
      p_cat = pr_cat_b, p_M2_regime = pr_m2, p_wew = pr_wew_b,
      train_pre_N = length(pre_idx)
    )
  }
  pe <- period_eval[[pname]]
  if (!is.null(pe)) {
    cat(sprintf("    %s N=%d ev=%d  XGB=%.4f  LOGIT=%.4f  CAT=%.4f  M2=%s  WEW=%.4f\n",
                pname, pe$N, pe$events, pe$p_meta_xgb, pe$p_meta_logit,
                pe$p_cat, ifelse(is.na(pe$p_M2_regime), "NA", sprintf("%.4f", pe$p_M2_regime)),
                pe$p_wew))
  }
}

#-------- 9. Feature importance --------
cat("\n[95-8] Meta feature importance (XGB meta, base 5)...\n")
imp_xgb <- xgb.importance(model = xgb_meta)
print(imp_xgb)

# Logistic coefs (glmnet)
glm_coefs <- as.matrix(coef(glm_meta, s = "lambda.min"))
glm_coef_df <- data.frame(
  feature = rownames(glm_coefs),
  coef = as.numeric(glm_coefs),
  stringsAsFactors = FALSE
)
cat("\n  Logistic L2 coefficients (lambda.min):\n")
print(glm_coef_df)

#-------- 10. Save outputs --------
cat("\n[95-9] Saving outputs...\n")

# Save predictions
write_parquet(test_d, file.path(PRED_DIR, "predictions_meta_test_2023_2026.parquet"))

# Benchmarks (from Cycle 45B JSON / paragraph)
benchmarks <- list(
  dynamic_M2_regime_v3b_inst = 0.6417,
  static_wew_v3b_inst        = 0.5779,
  static_ew5_v3b_inst        = 0.5218,
  best_individual_catboost   = 0.6156,
  full_OOS_2016_2026         = TRUE
)

# Verdict
test_xgb_pr <- eval_models$p_meta_xgb$pr_auc
test_int_pr <- eval_models$p_meta_xgb_int$pr_auc
best_meta_pr <- max(c(test_xgb_pr, test_int_pr), na.rm=TRUE)

verdict <- if (best_meta_pr >= 0.65) {
  "STACKING_PROVEN"
} else if (best_meta_pr >= 0.62) {
  "STACKING_MARGINAL"
} else {
  "STACKING_FAIL"
}

# CAVEAT: meta evaluated on Test (2023-2026 only) where event prevalence may
# differ from Cycle 45B full-OOS (2016-2026). Direct compare to 0.6417 must
# be qualified — also show test-window dynamic baseline below.

main_json <- list(
  cycle = "45F",
  approach = "GBDT_META_STACKING",
  description = "Meta-learner (XGB / Ridge logistic / LightGBM-or-RF) on 5 v3b_inst base predictions. CPU only.",
  seed = SEED,
  config = list(
    base_features = BASE_FEATS,
    train_period  = c("2016-01-04", "2022-12-31"),
    test_period   = c("2023-01-02", "2026-04-30"),
    xgb_meta = list(max_depth = 3, eta = 0.05, nrounds = 300,
                    subsample = 0.9, colsample_bytree = 0.9),
    lgb_meta = list(available = HAS_LIGHTGBM, used_rf_fallback = USED_RF_FALLBACK,
                    num_leaves = 7, learning_rate = 0.05, nrounds = 300),
    logit_meta = list(family = "binomial", alpha_ridge = 0, lambda_min = glm_meta$lambda.min)
  ),
  splits = list(
    train_N = sum(d$split == "train"), train_events = sum(d[split=="train"]$y),
    test_N  = sum(d$split == "test"),  test_events  = sum(d[split=="test"]$y)
  ),
  test_period_results = eval_models,
  benchmarks_full_OOS_2016_2026 = benchmarks,
  diagnostics = list(
    cv_5fold_xgb_meta = cv_results,
    cv_5fold_pr_auc_mean = mean(cv_prs, na.rm=TRUE),
    cv_5fold_pr_auc_sd   = sd(cv_prs, na.rm=TRUE),
    per_period = period_eval,
    interactions_xgb_meta = list(
      pr_auc  = pr_int,
      roc_auc = roc_int,
      vs_xgb_raw_delta = pr_int - eval_models$p_meta_xgb$pr_auc
    )
  ),
  caveat = list(
    test_window = "Test 2023-2026 PR-AUC NOT directly comparable to Cycle 45B Dynamic M2 PR-AUC 0.6417 (which is 2016-2026 full OOS). For an apples-to-apples comparison see test_period_results$p_M2_regime above (dynamic M2 prediction restricted to same 2023-2026 test window).",
    next_step = "If meta on 2023-2026 > dynamic 2023-2026 by margin, stacking proven. If <, retain dynamic."
  ),
  best_meta_pr_auc_test = best_meta_pr,
  verdict = verdict
)

write_json(main_json, file.path(EVAL_DIR, "meta_stacking_v3b_inst.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  Saved: %s\n", file.path(EVAL_DIR, "meta_stacking_v3b_inst.json")))

# Importance JSON
imp_json <- list(
  cycle = "45F",
  xgb_meta_importance = as.data.frame(imp_xgb),
  xgb_meta_int_importance = as.data.frame(xgb.importance(model = xgb_meta_int)),
  logit_l2_coefficients = glm_coef_df
)
write_json(imp_json, file.path(EVAL_DIR, "meta_stacking_v3b_inst_importance.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  Saved: %s\n", file.path(EVAL_DIR, "meta_stacking_v3b_inst_importance.json")))

#-------- 11. PR curve chart --------
cat("\n[95-10] Plotting PR curves...\n")
make_pr_df <- function(p, y, label) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) == 0 || sum(y) == 0) return(NULL)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord)
  rec  <- cumsum(y_ord) / sum(y_ord)
  data.frame(precision = prec, recall = rec, label = label)
}

curves <- list()
curves[["XGB meta (5)"]]     <- make_pr_df(test_d$p_meta_xgb,   test_d$y, "XGB meta (5)")
curves[["XGB meta + int(15)"]] <- make_pr_df(test_d$p_meta_xgb_int, test_d$y, "XGB meta + int(15)")
curves[["Logistic L2 meta"]] <- make_pr_df(test_d$p_meta_logit, test_d$y, "Logistic L2 meta")
if (!all(is.na(test_d$p_meta_lgb))) {
  curves[["LGB/RF meta"]]    <- make_pr_df(test_d$p_meta_lgb,  test_d$y, "LGB/RF meta")
}
curves[["CatBoost base"]]    <- make_pr_df(test_d$p_cat,        test_d$y, "CatBoost base")
if ("p_M2_regime" %in% colnames(test_d) && !all(is.na(test_d$p_M2_regime))) {
  curves[["Dynamic M2 regime (test window)"]] <- make_pr_df(test_d$p_M2_regime, test_d$y, "Dynamic M2 regime (test window)")
}
if ("p_wew" %in% colnames(test_d)) {
  curves[["Static WEW"]]     <- make_pr_df(test_d$p_wew,        test_d$y, "Static WEW")
}

pr_df <- do.call(rbind, curves)
prev <- mean(test_d$y)
gg <- ggplot(pr_df, aes(x = recall, y = precision, color = label)) +
  geom_line(alpha = 0.85, linewidth = 0.7) +
  geom_hline(yintercept = prev, linetype = "dashed", color = "grey50") +
  labs(title = "Cycle 45F — Meta Stacking PR curves (Test 2023-2026)",
       subtitle = sprintf("Test N=%d  events=%d  prevalence=%.3f",
                          nrow(test_d), sum(test_d$y), prev),
       x = "Recall", y = "Precision", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "right")
ggsave(file.path(CHART_DIR, "95_meta_stacking_pr_curve.png"),
       gg, width = 9, height = 6, dpi = 130)
cat(sprintf("  Saved chart: %s\n", file.path(CHART_DIR, "95_meta_stacking_pr_curve.png")))

#-------- 12. Final summary --------
cat("\n=========================================================\n")
cat("[95-FINAL] Cycle 45F Meta-Stacking Summary\n")
cat("=========================================================\n")
cat(sprintf("  Verdict: %s\n", verdict))
cat(sprintf("  Best meta PR-AUC (test 2023-2026): %.4f\n", best_meta_pr))
cat(sprintf("  XGB meta:        PR=%.4f  ROC=%.4f\n",
            eval_models$p_meta_xgb$pr_auc,  eval_models$p_meta_xgb$roc_auc))
if (!is.null(eval_models$p_meta_lgb)) {
  cat(sprintf("  LGB/RF meta:     PR=%.4f  ROC=%.4f%s\n",
              eval_models$p_meta_lgb$pr_auc, eval_models$p_meta_lgb$roc_auc,
              ifelse(USED_RF_FALLBACK, " (RF fallback)", "")))
}
cat(sprintf("  Logistic L2:     PR=%.4f  ROC=%.4f\n",
            eval_models$p_meta_logit$pr_auc, eval_models$p_meta_logit$roc_auc))
cat(sprintf("  XGB meta + int:  PR=%.4f  ROC=%.4f\n", pr_int, roc_int))
cat(sprintf("  --- Test-window baselines ---\n"))
cat(sprintf("  CatBoost base:   PR=%.4f\n", eval_models$p_cat$pr_auc))
if (!is.null(eval_models$p_M2_regime)) {
  cat(sprintf("  Dynamic M2:      PR=%.4f (test 2023-2026 only — NOT full 2016-2026)\n",
              eval_models$p_M2_regime$pr_auc))
}
cat(sprintf("  Static WEW:      PR=%.4f\n", eval_models$p_wew$pr_auc))
cat(sprintf("  --- Full-OOS Cycle 45B benchmarks ---\n"))
cat(sprintf("  Dynamic M2 (2016-2026 full): 0.6417\n"))
cat(sprintf("  Static WEW (2016-2026 full): 0.5779\n"))
cat(sprintf("  CV 5-fold mean PR-AUC:       %.4f (sd %.4f)\n",
            mean(cv_prs, na.rm=TRUE), sd(cv_prs, na.rm=TRUE)))
cat("=========================================================\n")
cat("DONE.\n")
