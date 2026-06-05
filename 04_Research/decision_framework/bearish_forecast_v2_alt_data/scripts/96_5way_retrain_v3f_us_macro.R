#==============================================================================
# 96_5way_retrain_v3f_us_macro.R — Cycle 47B US Macro Family (FRED orthogonal axis)
#
# Goal:
#   feature_panel_v1_3 (69) + 4 US macro features (FRED lag1) = 73 features panel
#   → 5-way ensemble retrain (XGB / CatBoost / RF / LSTM / TFT)
#   → Dynamic M2 Regime synthesis
#   → OOS PR-AUC compare vs V1.3 baseline 0.6078
#   → Orthogonality diagnostic vs KR-specific macro
#
# Hypothesis:
#   US macro shares latent factor with KR-specific bbva_macro via global crisis,
#   but lag/composition different → potential additive gain or dilution risk.
#
# New features (all lag-1 daily, forward-filled from raw FRED CSV):
#   us_t10y2y_spread_lag1     daily  (10Y - 2Y, recession leading)
#   us_initial_claims_4w_avg_lag1  weekly→daily ffill→4w MA→lag1
#   us_cfnai_lag1             monthly→daily ffill→lag1 (NAPM 대체)
#   us_stlfsi_lag1            weekly→daily ffill→lag1
#
# Steps:
#   Step 1: Build v3f_us_macro panel (73 features)
#   Step 2: 3-way GBDT retrain
#   Step 3: (LSTM/TFT in 97 Python)
#   Step 4-6: aggregator in 98 R
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(catboost);
  library(ranger); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
OUT_DIR <- file.path(WS, "outputs/03_models/v3f_us_macro")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)
set.seed(42)

# Walk-forward splits — identical to 68 / 96
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
# Step 0: Build 4 US macro lag1 features from FRED CSV (PIT enforced)
#==============================================================================
cat("\n========== Step 0: FRED → 4 US macro lag1 features ==========\n")

fred <- fread(file.path(DATA_DIR, "fred_us_macro_daily.csv"))
fred[, Date := as.Date(Date)]
setorder(fred, Date)
cat(sprintf("[fred] rows=%d  cols=%s\n", nrow(fred), paste(names(fred), collapse=", ")))

# Forward-fill weekly/monthly to daily (carry last observation forward)
# nafill type "locf" = Last Observation Carried Forward
fred[, t10y2y_ff := nafill(t10y2y_raw, type = "locf")]
fred[, icsa_ff   := nafill(icsa_raw,   type = "locf")]
fred[, cfnai_ff  := nafill(cfnai_raw,  type = "locf")]
fred[, stlfsi_ff := nafill(stlfsi4_raw, type = "locf")]

# ICSA 4-week MA (after forward-fill, equivalent to 28-day MA)
fred[, icsa_4w_avg := frollmean(icsa_ff, n = 28, align = "right", na.rm = TRUE)]

# lag-1 (PIT C2 — yesterday's value usable today at KR open)
fred[, us_t10y2y_spread_lag1 := shift(t10y2y_ff, 1L, type = "lag")]
fred[, us_initial_claims_4w_avg_lag1 := shift(icsa_4w_avg, 1L, type = "lag")]
fred[, us_cfnai_lag1 := shift(cfnai_ff, 1L, type = "lag")]
fred[, us_stlfsi_lag1 := shift(stlfsi_ff, 1L, type = "lag")]

us_macro_feats <- fred[, .(Date,
                            us_t10y2y_spread_lag1,
                            us_initial_claims_4w_avg_lag1,
                            us_cfnai_lag1,
                            us_stlfsi_lag1)]

cat("\n[us_macro feats cover after lag1]:\n")
for (col in c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
              "us_cfnai_lag1", "us_stlfsi_lag1")) {
  n_valid <- sum(!is.na(us_macro_feats[[col]]))
  first_valid <- if (n_valid > 0) as.character(us_macro_feats$Date[which(!is.na(us_macro_feats[[col]]))[1]]) else "n/a"
  cat(sprintf("  %-35s valid=%d (%.1f%%)  first=%s\n",
              col, n_valid, 100 * n_valid / nrow(us_macro_feats), first_valid))
}

#==============================================================================
# Step 1: Build v3f_us_macro panel (69 + 4 = 73 features)
#==============================================================================
cat("\n========== Step 1: Build v3f_us_macro panel (73 features) ==========\n")

feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_3.parquet")))
feat[, Date := as.Date(Date)]
setorder(feat, Date)
cat(sprintf("[1a] v1.3 baseline panel: %d rows × %d cols (69 features)\n",
            nrow(feat), ncol(feat) - 1))

# Merge US macro features
panel_v3f <- merge(feat, us_macro_feats, by = "Date", all.x = TRUE)
setorder(panel_v3f, Date)
cat(sprintf("[1b] v3f_us_macro panel: %d rows × %d cols (73 features)\n",
            nrow(panel_v3f), ncol(panel_v3f) - 1))

for (c in c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
            "us_cfnai_lag1", "us_stlfsi_lag1")) {
  cov <- sum(!is.na(panel_v3f[[c]])) / nrow(panel_v3f)
  cat(sprintf("  %-35s: %.1f%% cover (n=%d)\n", c, 100 * cov, sum(!is.na(panel_v3f[[c]]))))
}

panel_path <- file.path(DATA_DIR, "feature_panel_v3f_us_macro.parquet")
write_parquet(panel_v3f, panel_path)
cat(sprintf("[1c] Saved: %s\n", panel_path))

#==============================================================================
# Step 1.5: Orthogonality diagnostic
#==============================================================================
cat("\n========== Step 1.5: Orthogonality diagnostic ==========\n")

# 4 US macro features vs KR-specific macro/sector features
kr_macro_cols <- c("bbva_market_z", "bbva_sovereign_z", "bbva_transmission_z",
                    "bbva_macro_composite", "us_sector_avg_z", "us_sector_dispersion_z")
us_macro_cols <- c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
                    "us_cfnai_lag1", "us_stlfsi_lag1")

# Compute correlation on common period (TRAIN_START ~ OOS_END, with both features non-NA)
diag_period <- panel_v3f[Date >= TRAIN_START & Date <= OOS_END]
cor_us_kr <- matrix(NA_real_, nrow = length(us_macro_cols), ncol = length(kr_macro_cols),
                     dimnames = list(us_macro_cols, kr_macro_cols))
for (uc in us_macro_cols) for (kc in kr_macro_cols) {
  x <- diag_period[[uc]]; y <- diag_period[[kc]]
  ok <- !is.na(x) & !is.na(y)
  if (sum(ok) > 100) cor_us_kr[uc, kc] <- cor(x[ok], y[ok])
}

cat("\n[Correlation US macro vs KR macro/sector features]:\n")
print(round(cor_us_kr, 3))

max_abs_cor <- max(abs(cor_us_kr), na.rm = TRUE)
cat(sprintf("\n[Max |cor| US-KR]: %.3f\n", max_abs_cor))
ortho_verdict <- if (max_abs_cor < 0.3) {
  "TRULY_ORTHOGONAL (max cor < 0.3 — additive gain likely)"
} else if (max_abs_cor < 0.5) {
  "MODERATELY_ORTHOGONAL (max cor 0.3~0.5 — mixed)"
} else {
  "REDUNDANT (max cor > 0.5 — dilution risk)"
}
cat(sprintf("[Ortho verdict]: %s\n", ortho_verdict))

# Inter US macro correlation
cor_us_us <- matrix(NA_real_, nrow = length(us_macro_cols), ncol = length(us_macro_cols),
                     dimnames = list(us_macro_cols, us_macro_cols))
for (i in seq_along(us_macro_cols)) for (j in seq_along(us_macro_cols)) {
  x <- diag_period[[us_macro_cols[i]]]; y <- diag_period[[us_macro_cols[j]]]
  ok <- !is.na(x) & !is.na(y)
  if (sum(ok) > 100) cor_us_us[i, j] <- cor(x[ok], y[ok])
}
cat("\n[Inter US macro correlation]:\n")
print(round(cor_us_us, 3))

cor_json <- list(
  US_vs_KR = lapply(seq_len(nrow(cor_us_kr)), function(i) {
    setNames(as.list(round(cor_us_kr[i, ], 4)), colnames(cor_us_kr))
  }) |> setNames(rownames(cor_us_kr)),
  US_inter = lapply(seq_len(nrow(cor_us_us)), function(i) {
    setNames(as.list(round(cor_us_us[i, ], 4)), colnames(cor_us_us))
  }) |> setNames(rownames(cor_us_us)),
  max_abs_us_kr_cor = round(max_abs_cor, 4),
  orthogonality_verdict = ortho_verdict
)
write_json(cor_json,
           file.path(EVAL_DIR, "5way_retrain_v3f_us_macro_correlations.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[saved correlations] %s\n",
            file.path(EVAL_DIR, "5way_retrain_v3f_us_macro_correlations.json")))

#==============================================================================
# Step 2: 3-way GBDT retrain (XGB / CatBoost / RF)
#==============================================================================
cat("\n========== Step 2: 3-way GBDT retrain ==========\n")

tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
tgt[, Date := as.Date(Date)]
panel <- merge(panel_v3f, tgt[, .(Date, y_tail_q15, y_onset)], by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

feature_cols <- setdiff(names(panel), c("Date", "y_tail_q15", "y_onset"))
cat(sprintf("[2a] Panel for training: %d rows / %d features\n", nrow(panel), length(feature_cols)))

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
  imp_cat <- as.data.table(catboost.get_feature_importance(cat_fit))
  if (ncol(imp_cat) >= 1) {
    setnames(imp_cat, 1, "Gain")
    imp_cat[, Feature := feature_cols]
    setorder(imp_cat, -Gain)
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

  # New US macro features importance rank
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

  cat("\n[New US macro features importance — XGB]:\n"); print(imp_new_xgb)
  cat("\n[New US macro features importance — CatBoost]:\n");
  if (nrow(imp_new_cat) > 0) print(imp_new_cat) else cat("  (Cat importance not computed)\n")
  cat("\n[New US macro features importance — RF]:\n");
  if (nrow(imp_new_rf) > 0) print(imp_new_rf) else cat("  (RF importance not computed)\n")

  list(pr_xgb = pr_xgb, pr_cat = pr_cat, pr_rf = pr_rf, pr_ew = pr_ew,
       imp_new_xgb = imp_new_xgb, imp_new_cat = imp_new_cat, imp_new_rf = imp_new_rf)
}

res_q15 <- run_target_3way("y_tail_q15")
res_onset <- run_target_3way("y_onset")

cat("\n============================================================\n")
cat("[Step 2 SUMMARY] 3-way GBDT retrain on v3f_us_macro (73 features)\n")
cat(sprintf("y_tail_q15:  XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_q15$pr_xgb, res_q15$pr_cat, res_q15$pr_rf, res_q15$pr_ew))
cat(sprintf("y_onset:     XGB=%.4f / CAT=%.4f / RF=%.4f / EW=%.4f\n",
            res_onset$pr_xgb, res_onset$pr_cat, res_onset$pr_rf, res_onset$pr_ew))

# Save intermediate Step 2 summary
imp_to_list <- function(dt) {
  if (nrow(dt) == 0) return(list())
  lapply(seq_len(nrow(dt)), function(i) {
    list(feature = dt$Feature[i],
         gain = round(dt$Gain[i], 4),
         rank = as.integer(dt$rank[i]),
         total = as.integer(dt$total[i]))
  })
}

step2_summary <- list(
  step = "step2_3way_gbdt_retrain",
  cycle = "47B",
  approach = "US_MACRO_FAMILY_FRED_orthogonal_axis",
  panel = panel_path,
  n_features = length(feature_cols),
  new_features = c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
                    "us_cfnai_lag1", "us_stlfsi_lag1"),
  napm_substitute = "CFNAI used in place of NAPM (FRED API 400 — NAPM deprecated)",
  orthogonality_verdict = ortho_verdict,
  max_abs_us_kr_cor = round(max_abs_cor, 4),
  y_tail_q15 = list(
    xgb = round(res_q15$pr_xgb, 4),
    cat = round(res_q15$pr_cat, 4),
    rf  = round(res_q15$pr_rf, 4),
    ew3 = round(res_q15$pr_ew, 4),
    imp_new_xgb = imp_to_list(res_q15$imp_new_xgb),
    imp_new_cat = imp_to_list(res_q15$imp_new_cat),
    imp_new_rf = imp_to_list(res_q15$imp_new_rf)
  ),
  y_onset = list(
    xgb = round(res_onset$pr_xgb, 4),
    cat = round(res_onset$pr_cat, 4),
    rf  = round(res_onset$pr_rf, 4),
    ew3 = round(res_onset$pr_ew, 4)
  )
)
write_json(step2_summary,
           file.path(EVAL_DIR, "5way_retrain_v3f_us_macro_step2.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Step 2] Summary JSON: %s\n",
            file.path(EVAL_DIR, "5way_retrain_v3f_us_macro_step2.json")))

cat("\n========== Step 2 DONE — Run scripts/97_5way_retrain_v3f_us_macro.py next ==========\n")
