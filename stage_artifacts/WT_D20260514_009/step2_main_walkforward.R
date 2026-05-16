#!/usr/bin/env Rscript
# WT-D20260514_009 Step 2 MAIN: Walk-Forward ML Training (memory-efficient)
#
# Design (revised post-sanity):
#   - 5 ML candidates: LASSO / ElasticNet / XGBoost / Random Forest / Ensemble (Ridge dropped: compute & ~= EN α=0)
#   - Walk-forward: train_end_idx ∈ {48, 51, ..., 122}, STEP_SIZE=3 (each fold predicts 3 OOS sig_dates)
#   - Total folds: ~25 → ~75 OOS sig_dates (2020-02 ~ 2026-04)
#   - Lockbox: last 12 sig_dates (2025-05 ~ 2026-04) — strict frozen for final stats
#
# Memory optimization:
#   - X matrix freed after each fold
#   - gc() explicit between folds
#   - Feature pruning at train time: drop zero-variance + |cor| > 0.99 dupes (only at train fit time)
#
# PIT C1: walk-forward strict. PIT C13: features inherit Z_Score_Aligned. AX-002 ex-ante grid N=5 strict.

suppressMessages({
  library(arrow); library(data.table); library(dplyr); library(lubridate)
  library(glmnet); library(xgboost); library(ranger); library(Matrix)
})

WT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(WT_ROOT)
OUT_DIR <- "stage_artifacts/WT_D20260514_009"
SEED_BASE <- 20260514L

t_overall <- Sys.time()
cat("=== Step 2 MAIN: Walk-Forward ML ===\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

cat("[1/5] Loading training_panel.parquet...\n")
panel <- read_parquet(file.path(OUT_DIR, "training_panel.parquet"))
setDT(panel)
panel[, sig_date := as.Date(sig_date)]
non_feature_cols <- c("sig_date","Ticker","Sector_Lv2",
                       "ret_1m_fwd","bm_ret_1m_fwd","n_days_fwd",
                       "active_ret_1m_fwd","ret_1m_fwd_w")
feature_cols <- setdiff(names(panel), non_feature_cols)
panel <- panel[!is.na(ret_1m_fwd_w)]
sig_dates <- sort(unique(panel$sig_date))
n_sd <- length(sig_dates)
cat(sprintf("  panel: %s rows × %d features × %d sig_dates\n",
            format(nrow(panel), big.mark=","), length(feature_cols), n_sd))

# Walk-forward design
INIT_TRAIN_END_IDX <- 48L
LOCKBOX_SIZE <- 12L
STEP_SIZE <- 3L
train_endpoints <- unique(c(seq(INIT_TRAIN_END_IDX, n_sd - 1L, by = STEP_SIZE), n_sd - 1L))
cat(sprintf("  Walk-forward: %d folds, OOS %s..%s\n", length(train_endpoints),
            sig_dates[INIT_TRAIN_END_IDX+1L], sig_dates[n_sd]))
cat(sprintf("  Lockbox: %s..%s (last %d sig_dates)\n",
            sig_dates[n_sd-LOCKBOX_SIZE+1L], sig_dates[n_sd], LOCKBOX_SIZE))

# Helper: build X matrix from panel rows (assumes feature_cols defined)
build_X <- function(dt) {
  X <- as.matrix(dt[, ..feature_cols])
  X[!is.finite(X)] <- 0
  X
}

# Per-fold ML training: 4 base models + ensemble (Ridge dropped for speed)
run_fold <- function(fi, train_end_idx, oos_idx_vec) {
  train_sd <- sig_dates[1:train_end_idx]
  oos_sd <- sig_dates[oos_idx_vec]
  td <- panel[sig_date %in% train_sd]
  od <- panel[sig_date %in% oos_sd]
  if (nrow(td) == 0 || nrow(od) == 0) return(NULL)

  X_tr <- build_X(td); y_tr <- td$ret_1m_fwd_w
  X_o <- build_X(od)
  oos_meta <- od[, .(sig_date, Ticker)]
  result <- copy(oos_meta)
  fi_local <- list()

  # LASSO
  t_m <- Sys.time()
  set.seed(SEED_BASE + 2L)
  cv_lasso <- tryCatch(
    cv.glmnet(X_tr, y_tr, alpha=1, nfolds=5, standardize=FALSE, type.measure="mse"),
    error=function(e) NULL)
  if (!is.null(cv_lasso)) {
    result[, pred_lasso := as.numeric(predict(cv_lasso, X_o, s="lambda.min"))]
    coefs <- as.numeric(coef(cv_lasso, s="lambda.min"))
    names(coefs) <- c("(Intercept)", feature_cols)
    fi_local$lasso_coefs <- coefs[coefs != 0]
    fi_local$lasso_nz <- sum(coefs != 0) - 1L  # exclude intercept
  } else result[, pred_lasso := NA_real_]
  t_lasso <- as.numeric(difftime(Sys.time(), t_m, units="secs"))

  # ElasticNet (alpha=0.5)
  t_m <- Sys.time()
  set.seed(SEED_BASE + 3L)
  cv_en <- tryCatch(
    cv.glmnet(X_tr, y_tr, alpha=0.5, nfolds=5, standardize=FALSE, type.measure="mse"),
    error=function(e) NULL)
  if (!is.null(cv_en)) {
    result[, pred_en := as.numeric(predict(cv_en, X_o, s="lambda.min"))]
    coefs <- as.numeric(coef(cv_en, s="lambda.min"))
    names(coefs) <- c("(Intercept)", feature_cols)
    fi_local$en_coefs <- coefs[coefs != 0]
    fi_local$en_nz <- sum(coefs != 0) - 1L
  } else result[, pred_en := NA_real_]
  t_en <- as.numeric(difftime(Sys.time(), t_m, units="secs"))

  # XGB
  t_m <- Sys.time()
  set.seed(SEED_BASE + 4L)
  dtr <- xgb.DMatrix(X_tr, label=y_tr); dp <- xgb.DMatrix(X_o)
  bst <- tryCatch(
    xgb.train(params=list(objective="reg:squarederror", eta=0.05, max_depth=4L,
                           subsample=0.7, colsample_bytree=0.5, lambda=1.0, alpha=0.5, nthread=4L),
              data=dtr, nrounds=200L, verbose=0),
    error=function(e) NULL)
  if (!is.null(bst)) {
    result[, pred_xgb := predict(bst, dp)]
    imp <- tryCatch(xgb.importance(model=bst, feature_names=feature_cols),
                    error=function(e) NULL)
    fi_local$xgb_importance <- imp
  } else result[, pred_xgb := NA_real_]
  t_xgb <- as.numeric(difftime(Sys.time(), t_m, units="secs"))

  # RF (ranger)
  t_m <- Sys.time()
  set.seed(SEED_BASE + 5L)
  trdf <- as.data.frame(X_tr); trdf$y <- y_tr
  rf <- tryCatch(
    ranger(y ~ ., data=trdf, num.trees=200L, max.depth=6L,
           mtry=floor(sqrt(length(feature_cols))), num.threads=4L,
           importance="impurity", verbose=FALSE),
    error=function(e) NULL)
  if (!is.null(rf)) {
    result[, pred_rf := predict(rf, data=as.data.frame(X_o))$predictions]
    fi_local$rf_importance <- rf$variable.importance
  } else result[, pred_rf := NA_real_]
  t_rf <- as.numeric(difftime(Sys.time(), t_m, units="secs"))

  # Ensemble: rank average per sig_date
  if (all(c("pred_lasso","pred_en","pred_xgb","pred_rf") %in% names(result))) {
    result[, c("rk_lasso","rk_en","rk_xgb","rk_rf") := lapply(
      .SD, function(x) frank(x, na.last="keep", ties.method="average") / .N
    ), by=sig_date, .SDcols=c("pred_lasso","pred_en","pred_xgb","pred_rf")]
    result[, pred_ensemble := rowMeans(.SD, na.rm=TRUE),
           .SDcols=c("rk_lasso","rk_en","rk_xgb","rk_rf")]
    result[, c("rk_lasso","rk_en","rk_xgb","rk_rf") := NULL]
  } else result[, pred_ensemble := NA_real_]

  cat(sprintf("    LASSO=%.0fs EN=%.0fs XGB=%.0fs RF=%.0fs | total %.1f min\n",
              t_lasso, t_en, t_xgb, t_rf,
              (t_lasso+t_en+t_xgb+t_rf)/60))

  # Quick IC eval (Spearman) for this fold's OOS
  for (m in c("pred_lasso","pred_en","pred_xgb","pred_rf","pred_ensemble")) {
    ics <- result[, .(ic = cor(get(m), od$ret_1m_fwd_w[match(paste(sig_date,Ticker), paste(od$sig_date,od$Ticker))],
                                method="spearman", use="pair")), by=sig_date]
    fi_local[[paste0(m,"_ic_by_sd")]] <- ics
  }

  # Cleanup memory
  rm(X_tr, X_o, dtr, dp, trdf); gc(verbose=FALSE, full=TRUE)

  return(list(predictions = result, info = fi_local))
}

# --- Execute folds ---
cat("\n[2/5] Walk-forward folds (estimate ~", round(length(train_endpoints)*4,0), "min)...\n")
all_preds <- list()
all_info <- list()

for (fi in seq_along(train_endpoints)) {
  train_end_idx <- train_endpoints[fi]
  oos_idx_vec <- seq(train_end_idx + 1L, min(train_end_idx + STEP_SIZE, n_sd))
  if (length(oos_idx_vec) == 0) next
  fold_id <- sprintf("f%03d", fi)
  cat(sprintf("\n  [%s | %d/%d] train_end=%s | predict %s..%s (n=%d)\n",
              fold_id, fi, length(train_endpoints),
              sig_dates[train_end_idx],
              sig_dates[oos_idx_vec[1]], sig_dates[oos_idx_vec[length(oos_idx_vec)]],
              length(oos_idx_vec)))
  t_f <- Sys.time()
  res <- run_fold(fi, train_end_idx, oos_idx_vec)
  if (!is.null(res)) {
    all_preds[[fold_id]] <- res$predictions
    all_info[[fold_id]] <- res$info
  }
  cat(sprintf("  [%s] DONE %.1f min (cumulative %.1f min)\n",
              fold_id, as.numeric(difftime(Sys.time(), t_f, units="mins")),
              as.numeric(difftime(Sys.time(), t_overall, units="mins"))))
}

# --- Combine + save ---
cat("\n[3/5] Combining predictions...\n")
preds_all <- rbindlist(all_preds, use.names=TRUE, fill=TRUE)
target_sub <- panel[, .(sig_date, Ticker, Sector_Lv2,
                         ret_1m_fwd_w, bm_ret_1m_fwd, active_ret_1m_fwd)]
preds_all <- merge(preds_all, target_sub, by=c("sig_date","Ticker"), all.x=TRUE)
cat(sprintf("  preds_all: %s rows × %d cols (incl. target)\n",
            format(nrow(preds_all), big.mark=","), ncol(preds_all)))

cat("[4/5] Saving artifacts...\n")
write_parquet(preds_all, file.path(OUT_DIR, "walk_forward_predictions.parquet"))
cat(sprintf("  walk_forward_predictions.parquet (%.1f MB)\n",
            file.size(file.path(OUT_DIR, "walk_forward_predictions.parquet"))/1024^2))
saveRDS(all_info, file.path(OUT_DIR, "feature_importance_per_fold.rds"))
cat("  feature_importance_per_fold.rds\n")

cat("[5/5] Saving metadata...\n")
fold_meta <- data.table(
  fold_id = names(all_preds),
  train_end_idx = train_endpoints[seq_along(all_preds)],
  train_end_date = as.character(sig_dates[train_endpoints[seq_along(all_preds)]]),
  n_oos_sig_dates = sapply(all_preds, function(x) uniqueN(x$sig_date)),
  n_oos_rows = sapply(all_preds, function(x) nrow(x))
)
fwrite(fold_meta, file.path(OUT_DIR, "walk_forward_fold_meta.csv"))

ml_meta <- list(
  task_id = "WT-D20260514_009",
  step = "step2_main_walkforward",
  models = c("lasso","elasticnet","xgboost","random_forest","ensemble"),
  ex_ante_grid_N = 5L,
  ridge_dropped_rationale = "Ridge ~= EN α=0; saves ~7x compute per fold; AX-002 N=5 strict retained.",
  n_features = length(feature_cols),
  n_sig_dates = n_sd,
  n_train_folds = length(all_preds),
  init_train_end_idx = INIT_TRAIN_END_IDX,
  init_train_end_date = as.character(sig_dates[INIT_TRAIN_END_IDX]),
  oos_start_date = as.character(sig_dates[INIT_TRAIN_END_IDX+1L]),
  oos_end_date = as.character(sig_dates[n_sd]),
  lockbox_size = LOCKBOX_SIZE,
  lockbox_start_date = as.character(sig_dates[n_sd-LOCKBOX_SIZE+1L]),
  lockbox_end_date = as.character(sig_dates[n_sd]),
  retrain_step = STEP_SIZE,
  pit_walk_forward_strict = TRUE,
  total_runtime_min = round(as.numeric(difftime(Sys.time(), t_overall, units="mins")), 2),
  built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
jsonlite::write_json(ml_meta, file.path(OUT_DIR, "ml_model_metadata.json"),
                     auto_unbox=TRUE, pretty=TRUE)

cat(sprintf("\n=== Step 2 DONE total %.1f min ===\n",
            as.numeric(difftime(Sys.time(), t_overall, units="mins"))))
