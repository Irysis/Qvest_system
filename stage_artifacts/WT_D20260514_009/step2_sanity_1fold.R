#!/usr/bin/env Rscript
# Sanity check: run ONE fold only with all 5 models. Verify compute budget.

suppressMessages({
  library(arrow); library(data.table); library(dplyr); library(lubridate)
  library(glmnet); library(xgboost); library(ranger)
})

WT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(WT_ROOT)
OUT_DIR <- "stage_artifacts/WT_D20260514_009"
SEED_BASE <- 20260514L

cat("=== Sanity 1-fold ===\n")

panel <- read_parquet(file.path(OUT_DIR, "training_panel.parquet"))
setDT(panel)
panel[, sig_date := as.Date(sig_date)]
non_feature_cols <- c("sig_date","Ticker","Sector_Lv2",
                       "ret_1m_fwd","bm_ret_1m_fwd","n_days_fwd",
                       "active_ret_1m_fwd","ret_1m_fwd_w")
feature_cols <- setdiff(names(panel), non_feature_cols)
panel <- panel[!is.na(ret_1m_fwd_w)]
cat(sprintf("panel: %s rows × %s features\n", format(nrow(panel), big.mark=","), length(feature_cols)))

sig_dates <- sort(unique(panel$sig_date))
INIT_TRAIN_END_IDX <- 48L
train_sd <- sig_dates[1:INIT_TRAIN_END_IDX]
oos_sd <- sig_dates[INIT_TRAIN_END_IDX + 1L]

train_data <- panel[sig_date %in% train_sd]
oos_data <- panel[sig_date %in% oos_sd]
cat(sprintf("train: %s rows | oos: %s rows\n", nrow(train_data), nrow(oos_data)))

X_train <- as.matrix(train_data[, ..feature_cols])
X_train[!is.finite(X_train)] <- 0
y_train <- train_data$ret_1m_fwd_w
X_oos <- as.matrix(oos_data[, ..feature_cols])
X_oos[!is.finite(X_oos)] <- 0

cat(sprintf("X_train dim: %s × %s | y range: [%.4f, %.4f]\n",
            nrow(X_train), ncol(X_train), min(y_train), max(y_train)))

# Ridge
t0 <- Sys.time()
set.seed(SEED_BASE + 1L)
cv_ridge <- cv.glmnet(X_train, y_train, alpha=0, nfolds=5, standardize=FALSE,
                      type.measure="mse", parallel=FALSE)
pred_ridge <- as.numeric(predict(cv_ridge, X_oos, s="lambda.min"))
cat(sprintf("Ridge %.1fs | pred range [%.4f, %.4f] | mean %.4f\n",
            as.numeric(difftime(Sys.time(), t0, units="secs")),
            min(pred_ridge), max(pred_ridge), mean(pred_ridge)))

# LASSO
t0 <- Sys.time()
set.seed(SEED_BASE + 2L)
cv_lasso <- cv.glmnet(X_train, y_train, alpha=1, nfolds=5, standardize=FALSE,
                      type.measure="mse", parallel=FALSE)
pred_lasso <- as.numeric(predict(cv_lasso, X_oos, s="lambda.min"))
n_nonzero <- sum(as.numeric(coef(cv_lasso, s="lambda.min")) != 0)
cat(sprintf("LASSO %.1fs | n_nonzero %d | pred range [%.4f, %.4f]\n",
            as.numeric(difftime(Sys.time(), t0, units="secs")),
            n_nonzero, min(pred_lasso), max(pred_lasso)))

# XGB
t0 <- Sys.time()
set.seed(SEED_BASE + 4L)
dtrain <- xgb.DMatrix(X_train, label = y_train)
dpred <- xgb.DMatrix(X_oos)
bst <- xgb.train(params=list(objective="reg:squarederror", eta=0.05, max_depth=4L,
                              subsample=0.7, colsample_bytree=0.5, lambda=1.0, alpha=0.5, nthread=4L),
                 data=dtrain, nrounds=200L, verbose=0)
pred_xgb <- predict(bst, dpred)
cat(sprintf("XGB %.1fs | pred range [%.4f, %.4f] | mean %.4f\n",
            as.numeric(difftime(Sys.time(), t0, units="secs")),
            min(pred_xgb), max(pred_xgb), mean(pred_xgb)))

# RF
t0 <- Sys.time()
set.seed(SEED_BASE + 5L)
train_df <- as.data.frame(X_train); train_df$y <- y_train
rf_fit <- ranger(y ~ ., data=train_df, num.trees=200L, max.depth=6L,
                 mtry=floor(sqrt(length(feature_cols))), num.threads=4L,
                 importance="none", verbose=FALSE)
pred_rf <- predict(rf_fit, data=as.data.frame(X_oos))$predictions
cat(sprintf("RF %.1fs | pred range [%.4f, %.4f] | mean %.4f\n",
            as.numeric(difftime(Sys.time(), t0, units="secs")),
            min(pred_rf), max(pred_rf), mean(pred_rf)))

# Quick IC check
oos_data[, pred_ridge := pred_ridge]
oos_data[, pred_lasso := pred_lasso]
oos_data[, pred_xgb := pred_xgb]
oos_data[, pred_rf := pred_rf]
oos_data[, y_true := ret_1m_fwd_w]
ic_ridge <- cor(oos_data$pred_ridge, oos_data$y_true, method="spearman", use="pairwise.complete.obs")
ic_lasso <- cor(oos_data$pred_lasso, oos_data$y_true, method="spearman", use="pairwise.complete.obs")
ic_xgb <- cor(oos_data$pred_xgb, oos_data$y_true, method="spearman", use="pairwise.complete.obs")
ic_rf <- cor(oos_data$pred_rf, oos_data$y_true, method="spearman", use="pairwise.complete.obs")
cat(sprintf("\n=== Fold 1 OOS IC (1 sig_date %s) ===\n", oos_sd))
cat(sprintf("  Ridge   = %.4f\n", ic_ridge))
cat(sprintf("  LASSO   = %.4f\n", ic_lasso))
cat(sprintf("  XGB     = %.4f\n", ic_xgb))
cat(sprintf("  RF      = %.4f\n", ic_rf))
