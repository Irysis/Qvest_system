#!/usr/bin/env Rscript
# Sanity multi-fold: check IC pattern across 4 OOS sig_dates (early-COVID / late-COVID / 2023 normal / 2025)
suppressMessages({
  library(arrow); library(data.table); library(dplyr); library(lubridate)
  library(glmnet); library(xgboost); library(ranger)
})
WT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(WT_ROOT)
OUT_DIR <- "stage_artifacts/WT_D20260514_009"
SEED_BASE <- 20260514L

panel <- read_parquet(file.path(OUT_DIR, "training_panel.parquet"))
setDT(panel); panel[, sig_date := as.Date(sig_date)]
non_feature_cols <- c("sig_date","Ticker","Sector_Lv2",
                       "ret_1m_fwd","bm_ret_1m_fwd","n_days_fwd",
                       "active_ret_1m_fwd","ret_1m_fwd_w")
feature_cols <- setdiff(names(panel), non_feature_cols)
panel <- panel[!is.na(ret_1m_fwd_w)]
sig_dates <- sort(unique(panel$sig_date))
cat(sprintf("panel %s rows × %s features × %d sig_dates\n",
            format(nrow(panel), big.mark=","), length(feature_cols), length(sig_dates)))

# Test folds: train end -> oos sig_date
test_folds <- list(
  list(train_end_idx = 48L,  label = "fold01_2020Feb_COVID_start"),  # 2020-02
  list(train_end_idx = 60L,  label = "fold02_2021Jan"),               # 2021-01
  list(train_end_idx = 84L,  label = "fold03_2023Jan"),               # 2023-01
  list(train_end_idx = 108L, label = "fold04_2025Jan")                # 2025-01
)

results <- data.table()
for (tf in test_folds) {
  train_sd <- sig_dates[1:tf$train_end_idx]
  oos_sd <- sig_dates[tf$train_end_idx + 1L]
  cat(sprintf("\n%s | train [1..%d] (%s..%s) -> oos %s\n",
              tf$label, tf$train_end_idx, train_sd[1], train_sd[length(train_sd)], oos_sd))

  td <- panel[sig_date %in% train_sd]
  od <- panel[sig_date %in% oos_sd]
  X_tr <- as.matrix(td[, ..feature_cols]); X_tr[!is.finite(X_tr)] <- 0
  y_tr <- td$ret_1m_fwd_w
  X_o <- as.matrix(od[, ..feature_cols]); X_o[!is.finite(X_o)] <- 0
  cat(sprintf("  train %d × %d | oos %d\n", nrow(X_tr), ncol(X_tr), nrow(X_o)))

  # Faster: LASSO + XGB + RF only (skip Ridge for speed)
  set.seed(SEED_BASE + 2L)
  cv_lasso <- cv.glmnet(X_tr, y_tr, alpha=1, nfolds=5, standardize=FALSE, type.measure="mse")
  pred_lasso <- as.numeric(predict(cv_lasso, X_o, s="lambda.min"))
  nz <- sum(as.numeric(coef(cv_lasso, s="lambda.min")) != 0)

  set.seed(SEED_BASE + 3L)
  cv_en <- cv.glmnet(X_tr, y_tr, alpha=0.5, nfolds=5, standardize=FALSE, type.measure="mse")
  pred_en <- as.numeric(predict(cv_en, X_o, s="lambda.min"))

  set.seed(SEED_BASE + 4L)
  dtr <- xgb.DMatrix(X_tr, label=y_tr); dp <- xgb.DMatrix(X_o)
  bst <- xgb.train(params=list(objective="reg:squarederror", eta=0.05, max_depth=4L,
                                subsample=0.7, colsample_bytree=0.5, lambda=1.0, alpha=0.5, nthread=4L),
                   data=dtr, nrounds=200L, verbose=0)
  pred_xgb <- predict(bst, dp)

  set.seed(SEED_BASE + 5L)
  trdf <- as.data.frame(X_tr); trdf$y <- y_tr
  rf <- ranger(y ~ ., data=trdf, num.trees=200L, max.depth=6L,
               mtry=floor(sqrt(length(feature_cols))), num.threads=4L, verbose=FALSE)
  pred_rf <- predict(rf, data=as.data.frame(X_o))$predictions

  y <- od$ret_1m_fwd_w
  ic_l <- cor(pred_lasso, y, method="spearman", use="pair")
  ic_e <- cor(pred_en, y, method="spearman", use="pair")
  ic_x <- cor(pred_xgb, y, method="spearman", use="pair")
  ic_r <- cor(pred_rf, y, method="spearman", use="pair")
  cat(sprintf("  LASSO ic=%+.4f nz=%d | EN ic=%+.4f | XGB ic=%+.4f | RF ic=%+.4f\n",
              ic_l, nz, ic_e, ic_x, ic_r))

  results <- rbind(results, data.table(
    label=tf$label, oos_sig_date=oos_sd,
    ic_lasso=ic_l, ic_en=ic_e, ic_xgb=ic_x, ic_rf=ic_r,
    n_train=nrow(X_tr), n_oos=nrow(X_o), lasso_nonzero=nz
  ))
}
cat("\n=== Multi-fold IC summary ===\n")
print(results)
fwrite(results, file.path(OUT_DIR, "sanity_multifold_ic.csv"))
