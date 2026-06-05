#==============================================================================
# 149_xgb_meta_ecos_stage2.R — Cycle 56-2stage Stage 2 XGB Meta (3 variants)
#
# Goal: Combine PatchTST v5e q126 (Stage 1, seed=42, OOS 2018-01-02~2026-04-30)
#       with ECOS KR macro + US macro under 3 ensemble variants. Test whether
#       2-stage tree+DNN ensemble beats 53H PatchTST-only baseline PR-AUC=0.4012.
#
# Inputs (PIT-clean):
#   outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet
#     (Stage 1 OOS predictions, 53H reuse, seed=42)
#   outputs/01_data/ecos_kr_daily.csv (5 ECOS_lag1 features, 53I verified)
#   outputs/01_data/feature_panel_v5e_q126_usmacro.parquet (4 US macro lag1)
#
# 3 Variants:
#   V1 (naive concat 6): XGB(p_patchtst + 5 ECOS_lag1)
#   V2 (augmented concat 10): XGB(p_patchtst + 5 ECOS + 4 US_lag1)
#   V3 (weighted blend): α grid search on blend(p_patchtst, p_xgb_ecos_only)
#                         where p_xgb_ecos_only := XGB(5 ECOS only, time-series CV)
#                         α grid: 0.0~1.0 step 0.05 (21 points)
#                         α SELECTION trained on TRAIN-fold ONLY (forward-looking
#                         avoidance critical — α optimized per-fold)
#
# CV scheme (Stage 2, OOS-only):
#   5-fold expanding window time-series CV on the 2042-day OOS span
#   Fold boundaries chronological, train = pre-test-fold OOS rows
#   (Stage 1 in-sample 1995-2015 absent here → no leakage path)
#
# Outputs:
#   outputs/03_models/v6c_2stage_q126/predictions_stage2_naive_y_tail_q126.parquet
#   outputs/03_models/v6c_2stage_q126/predictions_stage2_augmented_y_tail_q126.parquet
#   outputs/03_models/v6c_2stage_q126/predictions_stage2_blend_y_tail_q126.parquet
#   outputs/03_models/v6c_2stage_q126/stage2_diagnostics.json
#
# PIT integrity:
#   - Stage 1 preds OOS only (no in-sample leakage)
#   - ECOS lag1 (53I verified)
#   - US macro lag1 (47B/48A verified)
#   - Time-series CV: train_idx < test_idx (chronological)
#   - α grid: train-fold-only selection (no future α leakage)
#   - bear_date_audit PASS (Fold3 zero events skipped in 53H Stage 1)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(xgboost)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
STAGE1_FILE <- file.path(WS_DIR,
  "outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet")
ECOS_FILE   <- file.path(WS_DIR, "outputs/01_data/ecos_kr_daily.csv")
V5E_PANEL   <- file.path(WS_DIR, "outputs/01_data/feature_panel_v5e_q126_usmacro.parquet")
OUT_DIR     <- file.path(WS_DIR, "outputs/03_models/v6c_2stage_q126")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

SEED  <- 20260521
set.seed(SEED)

ECOS5 <- c("ecos_m2_yoy_lag1", "ecos_krw_usd_change_5d_lag1",
           "ecos_base_rate_lag1", "ecos_industrial_production_yoy_lag1",
           "ecos_cpi_yoy_lag1")
US4   <- c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
           "us_cfnai_lag1", "us_stlfsi_lag1")

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

ic_spearman <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  suppressWarnings(cor(p, y, method = "spearman"))
}

#-------- 2. Load + merge OOS panel --------
cat("[149-1] Loading Stage 1 + ECOS + US macro...\n")
stage1 <- as.data.table(read_parquet(STAGE1_FILE))
ecos   <- fread(ECOS_FILE)
v5e    <- as.data.table(read_parquet(V5E_PANEL))

stage1[, Date := as.Date(Date)]
ecos[,   Date := as.Date(Date)]
v5e[,    Date := as.Date(Date)]

stopifnot(all(c("Date", "p_patchtst", "y", "split", "target") %in% colnames(stage1)))
stopifnot(all(ECOS5 %in% colnames(ecos)))
stopifnot(all(US4   %in% colnames(v5e)))

# Stage1 is OOS only (split == 'oos') — confirm
stopifnot(all(stage1$split == "oos"))
stopifnot(all(stage1$target == "y_tail_q126"))

# Merge: Stage1 (OOS) ← ECOS ← US macro
d <- merge(stage1[, .(Date, p_patchtst, y)],
           ecos[, c("Date", ECOS5), with = FALSE], by = "Date", all.x = TRUE)
d <- merge(d, v5e[, c("Date", US4), with = FALSE], by = "Date", all.x = TRUE)
setorder(d, Date)

cat(sprintf("[149-1] Merged OOS panel: N=%d (%s..%s) events=%d (%.2f%%)\n",
            nrow(d), as.character(min(d$Date)), as.character(max(d$Date)),
            sum(d$y), 100 * mean(d$y)))

# NaN sanity
for (c in c("p_patchtst", ECOS5, US4)) {
  nna <- sum(is.na(d[[c]]))
  if (nna > 0) cat(sprintf("  WARN: NaN in %s: %d\n", c, nna))
}

#-------- 3. CV folds (OOS-only chronological) --------
# 5-fold expanding window time-series CV on OOS span
# Fold k: test = chronological k-th quintile; train = all rows before test_start
N <- nrow(d)
fold_size <- floor(N / 5)
folds <- list()
for (k in 1:5) {
  te_start <- (k - 1) * fold_size + 1
  te_end   <- if (k == 5) N else k * fold_size
  tr_end   <- te_start - 1
  folds[[k]] <- list(
    fold = k,
    train_idx = if (tr_end >= 1) 1:tr_end else integer(0),
    test_idx  = te_start:te_end,
    test_dates = c(as.character(d$Date[te_start]),
                   as.character(d$Date[te_end]))
  )
}

cat("[149-2] Time-series CV folds (OOS-only, expanding):\n")
for (f in folds) {
  cat(sprintf("  Fold %d: train_n=%d, test_n=%d (%s..%s)\n",
              f$fold, length(f$train_idx), length(f$test_idx),
              f$test_dates[1], f$test_dates[2]))
}

#-------- 4. XGB trainer (shared) --------
fit_xgb <- function(X_tr, y_tr, X_te, n_est = 300, max_depth = 3, lr = 0.05) {
  pos <- sum(y_tr); neg <- length(y_tr) - pos
  spw <- if (pos > 0) neg / pos else 1
  dtr <- xgb.DMatrix(X_tr, label = y_tr)
  dte <- xgb.DMatrix(X_te)
  mdl <- xgb.train(
    params = list(
      objective = "binary:logistic",
      eval_metric = "aucpr",
      max_depth = max_depth,
      eta = lr,
      subsample = 0.9,
      colsample_bytree = 0.9,
      scale_pos_weight = spw,
      nthread = 4,
      seed = SEED
    ),
    data = dtr,
    nrounds = n_est,
    verbose = 0
  )
  list(model = mdl, p_te = predict(mdl, dte))
}

#-------- 5. Run 3 variants per-fold (OOF predictions) --------
# Initialize OOF cols
d[, p_v1_naive    := NA_real_]
d[, p_v2_augment  := NA_real_]
d[, p_v3_blend    := NA_real_]
d[, p_xgb_ecos_only := NA_real_]  # intermediate for V3
d[, alpha_per_fold := NA_real_]   # V3 selected α per fold

variant_log <- list()

cat("\n[149-3] Training 3 variants per-fold...\n")
for (f in folds) {
  if (length(f$train_idx) < 200) {
    cat(sprintf("  Fold %d: SKIP (insufficient train n=%d)\n", f$fold,
                length(f$train_idx)))
    next
  }
  train_d <- d[f$train_idx]
  test_d  <- d[f$test_idx]
  y_tr <- train_d$y; y_te <- test_d$y
  if (sum(y_tr) < 10) {
    cat(sprintf("  Fold %d: SKIP (insufficient events tr=%d te=%d)\n",
                f$fold, sum(y_tr), sum(y_te)))
    next
  }

  # V1: naive concat 6
  X_tr_v1 <- as.matrix(train_d[, c("p_patchtst", ECOS5), with = FALSE])
  X_te_v1 <- as.matrix(test_d[,  c("p_patchtst", ECOS5), with = FALSE])
  r_v1 <- fit_xgb(X_tr_v1, y_tr, X_te_v1)
  d[f$test_idx, p_v1_naive := r_v1$p_te]
  pr_v1 <- pr_auc(r_v1$p_te, y_te); roc_v1 <- roc_auc(r_v1$p_te, y_te)

  # V2: augmented concat 10
  X_tr_v2 <- as.matrix(train_d[, c("p_patchtst", ECOS5, US4), with = FALSE])
  X_te_v2 <- as.matrix(test_d[,  c("p_patchtst", ECOS5, US4), with = FALSE])
  r_v2 <- fit_xgb(X_tr_v2, y_tr, X_te_v2)
  d[f$test_idx, p_v2_augment := r_v2$p_te]
  pr_v2 <- pr_auc(r_v2$p_te, y_te); roc_v2 <- roc_auc(r_v2$p_te, y_te)

  # V3: weighted blend
  #   Step A: train XGB on ECOS-only (5 features) — train fold only
  #   Step B: emit p_xgb_ecos_only on test
  #   Step C: α grid 0..1 step 0.05 — select via PR-AUC on TRAIN-fold OOF
  #           (We use a held-out tail of the train fold for α selection to
  #            avoid forward-looking α on the test fold.)
  X_tr_v3 <- as.matrix(train_d[, ECOS5, with = FALSE])
  X_te_v3 <- as.matrix(test_d[,  ECOS5, with = FALSE])
  r_v3_ecos_te <- fit_xgb(X_tr_v3, y_tr, X_te_v3)$p_te
  d[f$test_idx, p_xgb_ecos_only := r_v3_ecos_te]

  # α selection: hold out last 20% of train fold for α grid scoring
  n_tr <- length(f$train_idx)
  alpha_sel_cut <- floor(n_tr * 0.8)
  alpha_sel_tr_idx <- f$train_idx[1:alpha_sel_cut]
  alpha_sel_val_idx <- f$train_idx[(alpha_sel_cut + 1):n_tr]
  if (length(alpha_sel_val_idx) < 50 || sum(d$y[alpha_sel_val_idx]) < 5) {
    # fallback: equal-weight α = 0.5 (no train-tail to score)
    best_alpha <- 0.5
    alpha_grid_log <- list(fallback = "insufficient_alpha_val_n_or_events",
                           default_alpha = 0.5)
  } else {
    # Refit XGB-ECOS on alpha-train-tail subset to score grid
    X_at_tr  <- as.matrix(d[alpha_sel_tr_idx,  ECOS5, with = FALSE])
    y_at_tr  <- d$y[alpha_sel_tr_idx]
    X_at_val <- as.matrix(d[alpha_sel_val_idx, ECOS5, with = FALSE])
    y_at_val <- d$y[alpha_sel_val_idx]
    p_ecos_val <- fit_xgb(X_at_tr, y_at_tr, X_at_val)$p_te
    p_patchtst_val <- d$p_patchtst[alpha_sel_val_idx]
    alpha_grid <- seq(0, 1, by = 0.05)
    alpha_pr <- sapply(alpha_grid, function(a) {
      pr_auc(a * p_patchtst_val + (1 - a) * p_ecos_val, y_at_val)
    })
    best_alpha <- alpha_grid[which.max(alpha_pr)]
    alpha_grid_log <- list(
      grid = alpha_grid,
      pr_auc_per_alpha = alpha_pr,
      best_alpha = best_alpha,
      best_pr_train_tail = max(alpha_pr, na.rm = TRUE)
    )
  }
  d[f$test_idx, alpha_per_fold := best_alpha]
  p_v3 <- best_alpha * d$p_patchtst[f$test_idx] + (1 - best_alpha) * r_v3_ecos_te
  d[f$test_idx, p_v3_blend := p_v3]
  pr_v3 <- pr_auc(p_v3, y_te); roc_v3 <- roc_auc(p_v3, y_te)

  # Baseline reference on this fold: pure PatchTST
  pr_p1 <- pr_auc(test_d$p_patchtst, y_te); roc_p1 <- roc_auc(test_d$p_patchtst, y_te)

  variant_log[[length(variant_log) + 1]] <- list(
    fold = f$fold,
    test_dates = f$test_dates,
    train_n = length(f$train_idx), test_n = length(f$test_idx),
    train_events = sum(y_tr), test_events = sum(y_te),
    stage1_baseline = list(pr_auc = pr_p1, roc_auc = roc_p1),
    v1_naive_6      = list(pr_auc = pr_v1, roc_auc = roc_v1),
    v2_augmented_10 = list(pr_auc = pr_v2, roc_auc = roc_v2),
    v3_blend        = list(pr_auc = pr_v3, roc_auc = roc_v3,
                           best_alpha = best_alpha,
                           alpha_grid = alpha_grid_log)
  )

  cat(sprintf("  Fold %d: PR  S1=%.4f  V1=%.4f  V2=%.4f  V3=%.4f (α=%.2f)\n",
              f$fold, pr_p1, pr_v1, pr_v2, pr_v3, best_alpha))
}

#-------- 6. Aggregate OOS PR-AUC (concatenate OOF preds across folds) --------
cat("\n[149-4] Aggregate OOS metrics (concatenated OOF predictions)...\n")
oos <- d[!is.na(p_v1_naive)]
agg <- list(
  baseline_53H_patchtst = list(
    pr_auc  = pr_auc(oos$p_patchtst, oos$y),
    roc_auc = roc_auc(oos$p_patchtst, oos$y),
    ic_spearman = ic_spearman(oos$p_patchtst, oos$y),
    n = nrow(oos), events = sum(oos$y)
  ),
  v1_naive_concat_6 = list(
    pr_auc  = pr_auc(oos$p_v1_naive, oos$y),
    roc_auc = roc_auc(oos$p_v1_naive, oos$y),
    ic_spearman = ic_spearman(oos$p_v1_naive, oos$y)
  ),
  v2_augmented_concat_10 = list(
    pr_auc  = pr_auc(oos$p_v2_augment, oos$y),
    roc_auc = roc_auc(oos$p_v2_augment, oos$y),
    ic_spearman = ic_spearman(oos$p_v2_augment, oos$y)
  ),
  v3_weighted_blend = list(
    pr_auc  = pr_auc(oos$p_v3_blend, oos$y),
    roc_auc = roc_auc(oos$p_v3_blend, oos$y),
    ic_spearman = ic_spearman(oos$p_v3_blend, oos$y),
    alpha_per_fold = unique(oos$alpha_per_fold)
  )
)
cat(sprintf("  Baseline 53H PatchTST OOS-concat PR=%.4f  ROC=%.4f  IC=%.4f\n",
            agg$baseline_53H_patchtst$pr_auc,
            agg$baseline_53H_patchtst$roc_auc,
            agg$baseline_53H_patchtst$ic_spearman))
cat(sprintf("  V1 naive 6         OOS-concat PR=%.4f  ROC=%.4f  IC=%.4f\n",
            agg$v1_naive_concat_6$pr_auc, agg$v1_naive_concat_6$roc_auc,
            agg$v1_naive_concat_6$ic_spearman))
cat(sprintf("  V2 augmented 10    OOS-concat PR=%.4f  ROC=%.4f  IC=%.4f\n",
            agg$v2_augmented_concat_10$pr_auc, agg$v2_augmented_concat_10$roc_auc,
            agg$v2_augmented_concat_10$ic_spearman))
cat(sprintf("  V3 weighted blend  OOS-concat PR=%.4f  ROC=%.4f  IC=%.4f\n",
            agg$v3_weighted_blend$pr_auc, agg$v3_weighted_blend$roc_auc,
            agg$v3_weighted_blend$ic_spearman))

#-------- 7. Feature importance (V2 augmented, refit on all OOS for diagnostic only) --------
# NOTE: refit on full OOS for importance only — not used for predictions
# (predictions already saved per-fold OOF above)
cat("\n[149-5] Diagnostic feature importance (V2 augmented, full-OOS refit)...\n")
X_all_v2 <- as.matrix(d[, c("p_patchtst", ECOS5, US4), with = FALSE])
y_all <- d$y
dall <- xgb.DMatrix(X_all_v2, label = y_all)
mdl_all <- xgb.train(
  params = list(objective = "binary:logistic", eval_metric = "aucpr",
                max_depth = 3, eta = 0.05, subsample = 0.9,
                colsample_bytree = 0.9, nthread = 4, seed = SEED),
  data = dall, nrounds = 300, verbose = 0
)
imp <- xgb.importance(model = mdl_all)
imp_list <- lapply(seq_len(nrow(imp)), function(i) {
  list(feature = imp$Feature[i], gain = imp$Gain[i],
       cover = imp$Cover[i], frequency = imp$Frequency[i])
})
for (i in seq_along(imp_list)) {
  cat(sprintf("  rank %d  %s  gain=%.4f\n", i,
              imp_list[[i]]$feature, imp_list[[i]]$gain))
}

#-------- 8. Save per-variant predictions + diagnostics --------
cat("\n[149-6] Saving outputs...\n")
save_pred <- function(dt, col, fname) {
  out <- dt[!is.na(get(col)), .(Date, p_meta = get(col), y, split = "oos",
                                target = "y_tail_q126")]
  write_parquet(out, file.path(OUT_DIR, fname))
  cat(sprintf("  Saved %s: %d rows\n", fname, nrow(out)))
}
save_pred(d, "p_v1_naive",   "predictions_stage2_naive_y_tail_q126.parquet")
save_pred(d, "p_v2_augment", "predictions_stage2_augmented_y_tail_q126.parquet")
save_pred(d, "p_v3_blend",   "predictions_stage2_blend_y_tail_q126.parquet")

diagnostics <- list(
  cycle = "56-2stage Stage 2 XGB meta",
  seed = SEED,
  stage1_source = "53H PatchTST v5e q126 (seed=42, reuse)",
  stage1_oos_window = c(as.character(min(d$Date)), as.character(max(d$Date))),
  stage1_oos_n = nrow(d),
  stage1_oos_events = sum(d$y),
  ecos_features = ECOS5,
  us_macro_features = US4,
  cv_scheme = "5-fold expanding chronological time-series (OOS-only)",
  bear_date_audit = "PASS (Fold3 q126 zero events confirmed; Stage 1 53H skipped Fold3)",
  baseline_reference_53H_full_oos_pr_auc = 0.40121427848134816,
  per_fold = variant_log,
  aggregate_oos = agg,
  feature_importance_v2_full_oos_refit = imp_list,
  pit_integrity_notes = c(
    "Stage 1 preds OOS only — no in-sample leakage",
    "ECOS lag1 (53I verified)",
    "US macro lag1 (47B/48A verified)",
    "Time-series CV train_idx < test_idx (chronological)",
    "V3 α grid selected on train-fold tail (no test-fold information)",
    "Feature importance refit is DIAGNOSTIC only; predictions are per-fold OOF"
  )
)

write_json(diagnostics, file.path(OUT_DIR, "stage2_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")
cat(sprintf("  Saved stage2_diagnostics.json\n"))

cat("\n[149] DONE.\n")
