#==============================================================================
# 84_5way_retrain_v3d_combined_axes.R — Cycle 46A Combined Multi-Axis
#
# Goal:
#   feature_panel_v1_alt_enhanced (69) + 1 FOREIGN + 4 INST = 74 features
#   → 5-way ensemble retrain (XGB / CatBoost / RF / LSTM / TFT)
#   → 5-way Dynamic M1~M5 ensemble synthesis
#   → OOS PR-AUC compare vs:
#       - V1.3 baseline 0.6078 (Δ vs baseline)
#       - Cycle 43 v2_2feat 0.6390 (foreign-only)
#       - Cycle 45B v3b_inst_suite 0.6417 (inst-only, BEST SINGLE-AXIS)
#
# 5 NEW features (all lag1 PIT-safe, all from prior cycles verified):
#   FOREIGN (Cycle 43 admitted):
#     1. foreign_breadth_ad_ratio_5d_avg_lag1
#   INSTITUTIONAL (Cycle 45B admitted, 4건 그대로):
#     2. inst_ad_ratio_5d_avg_lag1
#     3. inst_ad_ratio_20d_avg_lag1
#     4. inst_hhi_buy_lag1
#     5. inst_vs_foreign_divergence_5d_lag1
#
# Additivity hypothesis:
#   Best case (additive): 0.6078 + 0.0313 + 0.0339 = 0.6730
#   Realistic (partial overlap): Δ +0.04 ~ +0.05 (M2 Regime ~0.65)
#   Worst (over-fit / saturation): regression vs Cycle 45B 0.6417
#
# Decision rule (vs Cycle 45B best previous):
#   ADDITIVE_STRONG  : Δ vs 45B > +0.015
#   ADDITIVE_WEAK    : 0 ~ +0.015
#   SATURATED        : Δ vs 45B ≈ 0 (±0.005)
#   DILUTION         : Δ vs 45B < -0.005
#
# AX-008: Forge single-source quick screening only. Admit cycle 필요 시 Codex + Architect 2/3.
# PIT: lag-1 strict / Train 1995~2009 / Valid 2010~2015 / OOS 2016~2026-04
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v3d_combined")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# Walk-forward splits (identical to 68 / 78 — Cycle 45A 진단 confirmed)
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
# Step 1: Build v3d_combined panel (69 + 1 foreign + 4 inst = 74 features)
#==============================================================================
cat("\n========== Step 1: Build v3d_combined panel (74 features) ==========\n")

feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")))
feat[, Date := as.Date(Date)]
setorder(feat, Date)
cat(sprintf("[1a] Enhanced baseline panel: %d rows × %d cols (69 features)\n",
            nrow(feat), ncol(feat) - 1))

# ── Foreign breadth (Cycle 43 admitted) ──
fr_br <- fread(file.path(DATA_DIR, "investor_breadth_daily.csv"))
fr_br[, Date := as.Date(Date)]
fr_br <- fr_br[n_active >= 100]
setorder(fr_br, Date)
fr_br[, foreign_breadth_ad_ratio_5d_avg := frollmean(ad_ratio, n = 5, align = "right", na.rm = TRUE)]
fr_br[, foreign_breadth_ad_ratio_5d_avg_lag1 := shift(foreign_breadth_ad_ratio_5d_avg, 1L, type = "lag")]
cat(sprintf("[1b] Foreign breadth (n_active>=100): %d obs, %s ~ %s\n",
            nrow(fr_br),
            as.character(min(fr_br$Date)), as.character(max(fr_br$Date))))
cat(sprintf("  foreign_breadth_ad_ratio_5d_avg_lag1: %d non-NA\n",
            sum(!is.na(fr_br$foreign_breadth_ad_ratio_5d_avg_lag1))))

# ── Institutional breadth (Cycle 45B admitted, 4건 그대로) ──
inst_br <- fread(file.path(DATA_DIR, "inst_breadth_daily.csv"))
inst_br[, Date := as.Date(Date)]
inst_br <- inst_br[n_active >= 100]
setorder(inst_br, Date)

inst_br[, inst_ad_ratio_5d_avg := frollmean(ad_ratio, n = 5, align = "right", na.rm = TRUE)]
inst_br[, inst_ad_ratio_20d_avg := frollmean(ad_ratio, n = 20, align = "right", na.rm = TRUE)]
inst_br[, inst_ad_ratio_5d_avg_lag1 := shift(inst_ad_ratio_5d_avg, 1L, type = "lag")]
inst_br[, inst_ad_ratio_20d_avg_lag1 := shift(inst_ad_ratio_20d_avg, 1L, type = "lag")]
inst_br[, inst_hhi_buy_lag1 := shift(hhi_buy, 1L, type = "lag")]

cat(sprintf("[1c] Inst breadth (n_active>=100): %d obs, %s ~ %s\n",
            nrow(inst_br),
            as.character(min(inst_br$Date)), as.character(max(inst_br$Date))))
cat(sprintf("  inst_ad_ratio_5d_avg_lag1:   %d non-NA\n", sum(!is.na(inst_br$inst_ad_ratio_5d_avg_lag1))))
cat(sprintf("  inst_ad_ratio_20d_avg_lag1:  %d non-NA\n", sum(!is.na(inst_br$inst_ad_ratio_20d_avg_lag1))))
cat(sprintf("  inst_hhi_buy_lag1:           %d non-NA\n", sum(!is.na(inst_br$inst_hhi_buy_lag1))))

# ── Inst vs Foreign Divergence (Cycle 45B admitted) ──
div_dt <- merge(
  inst_br[, .(Date, inst_ad_ratio = ad_ratio)],
  fr_br[, .(Date, foreign_ad_ratio = ad_ratio)],
  by = "Date", all = FALSE
)
setorder(div_dt, Date)
div_dt[, divergence_raw := inst_ad_ratio - foreign_ad_ratio]
div_dt[, inst_vs_foreign_divergence_5d := frollmean(divergence_raw, n = 5, align = "right", na.rm = TRUE)]
div_dt[, inst_vs_foreign_divergence_5d_lag1 := shift(inst_vs_foreign_divergence_5d, 1L, type = "lag")]

cat(sprintf("[1d] Inst-Foreign divergence merge: %d obs, %s ~ %s\n",
            nrow(div_dt),
            as.character(min(div_dt$Date)), as.character(max(div_dt$Date))))

# ── Correlation analysis (foreign + inst features) ──
cor_dt <- merge(
  fr_br[, .(Date, foreign_breadth_ad_ratio_5d_avg_lag1)],
  inst_br[, .(Date, inst_ad_ratio_5d_avg_lag1, inst_ad_ratio_20d_avg_lag1, inst_hhi_buy_lag1)],
  by = "Date", all = FALSE
)
cor_dt <- merge(cor_dt,
                div_dt[, .(Date, inst_vs_foreign_divergence_5d_lag1)],
                by = "Date", all = FALSE)
cor_dt <- cor_dt[complete.cases(cor_dt)]
cat("\n[1e] Correlation matrix among 5 NEW features (Cycle 46A combined axes):\n")
print(round(cor(cor_dt[, -1]), 3))

# Specific cross-axis correlation: foreign vs each inst feature
cat("\n[1e2] Foreign-Inst pair correlations (Cycle 46A direct check):\n")
foreign_col <- "foreign_breadth_ad_ratio_5d_avg_lag1"
for (inst_col in c("inst_ad_ratio_5d_avg_lag1", "inst_ad_ratio_20d_avg_lag1",
                    "inst_hhi_buy_lag1", "inst_vs_foreign_divergence_5d_lag1")) {
  r <- cor(cor_dt[[foreign_col]], cor_dt[[inst_col]])
  cat(sprintf("  cor(%s, %s) = %.4f\n", foreign_col, inst_col, r))
}

# Merge all to panel
panel_v3d <- merge(feat,
                   fr_br[, .(Date, foreign_breadth_ad_ratio_5d_avg_lag1)],
                   by = "Date", all.x = TRUE)
panel_v3d <- merge(panel_v3d,
                   inst_br[, .(Date, inst_ad_ratio_5d_avg_lag1,
                               inst_ad_ratio_20d_avg_lag1,
                               inst_hhi_buy_lag1)],
                   by = "Date", all.x = TRUE)
panel_v3d <- merge(panel_v3d,
                   div_dt[, .(Date, inst_vs_foreign_divergence_5d_lag1)],
                   by = "Date", all.x = TRUE)
setorder(panel_v3d, Date)

cat(sprintf("\n[1f] v3d_combined panel: %d rows × %d cols\n",
            nrow(panel_v3d), ncol(panel_v3d) - 1))
cat(sprintf("  Total features = 69 base + 1 foreign + 4 inst = %d\n",
            ncol(panel_v3d) - 1))

new_cols_v3d <- c(
  "foreign_breadth_ad_ratio_5d_avg_lag1",
  "inst_ad_ratio_5d_avg_lag1",
  "inst_ad_ratio_20d_avg_lag1",
  "inst_hhi_buy_lag1",
  "inst_vs_foreign_divergence_5d_lag1"
)
for (c in new_cols_v3d) {
  cov <- sum(!is.na(panel_v3d[[c]])) / nrow(panel_v3d)
  cat(sprintf("  %-42s: %.1f%% cover (n=%d)\n", c, 100 * cov, sum(!is.na(panel_v3d[[c]]))))
}

panel_path <- file.path(DATA_DIR, "feature_panel_v3d_combined.parquet")
write_parquet(panel_v3d, panel_path)
cat(sprintf("\n[1g] Saved: %s\n", panel_path))

#==============================================================================
# Step 2: Multi-algorithm 3-way retrain (XGB / CatBoost / RF)
#==============================================================================
cat("\n========== Step 2: Multi-algorithm 3-way retrain ==========\n")

tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
tgt[, Date := as.Date(Date)]
panel <- merge(panel_v3d, tgt[, .(Date, y_tail_q15, y_onset)], by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15", "y_onset"))
cat(sprintf("[2a] Panel for training: %d rows / %d features\n", nrow(panel), length(feature_cols)))

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

  cat_imp_vec <- tryCatch({
    catboost.get_feature_importance(cat_fit, pool = cat_pool_train, type = "FeatureImportance")
  }, error = function(e) NULL)
  if (!is.null(cat_imp_vec) && length(cat_imp_vec) > 0) {
    imp_cat <- data.table(Feature = feature_cols, Gain = as.numeric(cat_imp_vec))
    setorder(imp_cat, -Gain)
  } else {
    imp_cat <- data.table(Feature = character(0), Gain = numeric(0))
  }

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

  # New features importance per model + top 10 overall
  new_cols <- new_cols_v3d
  imp_xgb[, rank := seq_len(.N)]
  imp_new_xgb <- imp_xgb[Feature %in% new_cols, .(Feature, Gain, rank, total = nrow(imp_xgb))]
  setorder(imp_new_xgb, rank)
  top10_xgb <- head(imp_xgb[, .(Feature, Gain, rank)], 10)

  if (nrow(imp_cat) > 0) {
    imp_cat[, rank := seq_len(.N)]
    imp_new_cat <- imp_cat[Feature %in% new_cols, .(Feature, Gain, rank, total = nrow(imp_cat))]
    setorder(imp_new_cat, rank)
    top10_cat <- head(imp_cat[, .(Feature, Gain, rank)], 10)
  } else {
    imp_new_cat <- data.table(Feature = character(0), Gain = numeric(0),
                               rank = integer(0), total = integer(0))
    top10_cat <- data.table(Feature = character(0), Gain = numeric(0), rank = integer(0))
  }

  if (nrow(imp_rf) > 0) {
    imp_rf[, rank := seq_len(.N)]
    imp_new_rf  <- imp_rf[Feature %in% new_cols, .(Feature, Gain, rank, total = nrow(imp_rf))]
    setorder(imp_new_rf, rank)
    top10_rf <- head(imp_rf[, .(Feature, Gain, rank)], 10)
  } else {
    imp_new_rf <- data.table(Feature = character(0), Gain = numeric(0),
                              rank = integer(0), total = integer(0))
    top10_rf <- data.table(Feature = character(0), Gain = numeric(0), rank = integer(0))
  }

  cat("\n[NEW features importance — XGB]:\n"); print(imp_new_xgb)
  cat("\n[NEW features importance — CatBoost]:\n");
  if (nrow(imp_new_cat) > 0) print(imp_new_cat) else cat("  (not computed)\n")
  cat("\n[NEW features importance — RF]:\n");
  if (nrow(imp_new_rf) > 0) print(imp_new_rf) else cat("  (not computed)\n")

  cat("\n[Top 10 features — XGB]:\n"); print(top10_xgb)
  if (nrow(top10_cat) > 0) { cat("\n[Top 10 features — CatBoost]:\n"); print(top10_cat) }
  if (nrow(top10_rf) > 0) { cat("\n[Top 10 features — RF]:\n"); print(top10_rf) }

  list(pr_xgb = pr_xgb, pr_cat = pr_cat, pr_rf = pr_rf, pr_ew = pr_ew,
       imp_new_xgb = imp_new_xgb, imp_new_cat = imp_new_cat, imp_new_rf = imp_new_rf,
       top10_xgb = top10_xgb, top10_cat = top10_cat, top10_rf = top10_rf)
}

res_q15 <- run_target_3way("y_tail_q15")
res_onset <- run_target_3way("y_onset")

cat("\n============================================================\n")
cat("[Step 2 SUMMARY] 3-way GBDT retrain on v3d_combined (74 features)\n")
cat(sprintf("y_tail_q15:  XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_q15$pr_xgb, res_q15$pr_cat, res_q15$pr_rf, res_q15$pr_ew))
cat(sprintf("y_onset:     XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_onset$pr_xgb, res_onset$pr_cat, res_onset$pr_rf, res_onset$pr_ew))

# Per-model compare vs Cycle 45B
cat("\n[Per-model PR-AUC vs Cycle 45B (4 inst features)]:\n")
cat(sprintf("  XGB: v3d=%.4f vs 45B=0.5307 (Δ %+.4f)\n", res_q15$pr_xgb, res_q15$pr_xgb - 0.5307))
cat(sprintf("  CAT: v3d=%.4f vs 45B=0.6156 (Δ %+.4f)\n", res_q15$pr_cat, res_q15$pr_cat - 0.6156))
cat(sprintf("  RF:  v3d=%.4f vs 45B=0.5693 (Δ %+.4f)\n", res_q15$pr_rf, res_q15$pr_rf - 0.5693))

# Save Step 2 summary
step2_summary <- list(
  step = "step2_3way_gbdt_retrain_v3d_combined",
  panel = panel_path,
  n_features = length(feature_cols),
  new_features = new_cols_v3d,
  axis_composition = list(
    foreign_axis = "foreign_breadth_ad_ratio_5d_avg_lag1 (1, Cycle 43 admitted)",
    inst_axis = "inst_ad_ratio_5d/20d + hhi + vs_foreign_divergence (4, Cycle 45B admitted)"
  ),
  baseline_compare = list(
    v1_3_baseline_M2_Regime = 0.6078,
    cycle_43_v2_2feat_M2_Regime = 0.6390,
    cycle_45B_v3b_inst_suite_M2_Regime = 0.6417
  ),
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
    imp_new_cat = lapply(seq_len(nrow(res_q15$imp_new_cat)), function(i) {
      list(feature = res_q15$imp_new_cat$Feature[i],
           gain = round(res_q15$imp_new_cat$Gain[i], 4),
           rank = res_q15$imp_new_cat$rank[i],
           total = res_q15$imp_new_cat$total[i])
    }),
    imp_new_rf = lapply(seq_len(nrow(res_q15$imp_new_rf)), function(i) {
      list(feature = res_q15$imp_new_rf$Feature[i],
           gain = round(res_q15$imp_new_rf$Gain[i], 4),
           rank = res_q15$imp_new_rf$rank[i],
           total = res_q15$imp_new_rf$total[i])
    }),
    top10_xgb = lapply(seq_len(nrow(res_q15$top10_xgb)), function(i) {
      list(feature = res_q15$top10_xgb$Feature[i],
           gain = round(res_q15$top10_xgb$Gain[i], 4),
           rank = res_q15$top10_xgb$rank[i])
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
           file.path(EVAL_DIR, "5way_retrain_v3d_combined_step2.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Step 2] Summary JSON: %s\n",
            file.path(EVAL_DIR, "5way_retrain_v3d_combined_step2.json")))

cat("\n========== Step 2 DONE — Run scripts/85_5way_retrain_v3d_combined_axes.py next ==========\n")
