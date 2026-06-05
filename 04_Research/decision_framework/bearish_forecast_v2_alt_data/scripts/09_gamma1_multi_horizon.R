#==============================================================================
# 09_gamma1_multi_horizon.R — γ1 Multi-horizon ensemble (h=5/21/63)
#
# Plan v1.0 → v1.1 Step 3 γ1
#
# 단일 h=21 모델 → 3-horizon ensemble:
#   h=5d (단기 alert, 빠른 reaction)
#   h=21d (현재 primary, 1개월)
#   h=63d (분기, slow trend)
#
# 각 horizon별 model 학습 후 ensemble (Equal-weight 우선)
# y_tail 정의를 horizon별 (Q15 rolling 60m)
#
# Output:
#   outputs/02_targets/targets_multi_horizon.parquet
#   outputs/03_models/multi_horizon/predictions_h{5,21,63}.parquet
#   outputs/03_models/multi_horizon/ensemble_multi_horizon.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(glmnet)
  library(xgboost)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS_DIR, "outputs/01_data")
TGT_DIR <- file.path(WS_DIR, "outputs/02_targets")
MH_DIR <- file.path(WS_DIR, "outputs/03_models/multi_horizon")
dir.create(MH_DIR, recursive = TRUE, showWarnings = FALSE)

H_LIST <- c(5, 21, 63)
ROLLING_WIN_MONTHS <- 60
DATA_LAG <- 1

# Walk-forward (v1.0 retain)
TRAIN_START <- as.Date("1995-01-01")
TRAIN_END   <- as.Date("2009-12-31")
VALID_START <- as.Date("2010-01-01")
VALID_END   <- as.Date("2015-12-31")
OOS_START   <- as.Date("2016-01-01")
OOS_END     <- as.Date("2026-04-30")

FEATURE_COLS <- c(
  "bbva_market_z", "bbva_sovereign_z",
  "bbva_transmission_z", "bbva_macro_composite",
  "k200_implied_skew_z", "k200_implied_kurt_z",
  "us_sector_avg_z", "us_sector_dispersion_z"
)

# ── Helper: build Y_tail_Q15 per horizon ────────────────────
build_target_h <- function(bm, h) {
  bm[, ret_h := shift(BM_Close, -h, type = "lead") / BM_Close - 1]
  bm[, peak_252 := frollapply(BM_Close, 252, max, na.rm = TRUE, align = "right")]
  bm[, dd_252 := BM_Close / peak_252 - 1]

  # Purged quantile (h-1 future label 제외)
  win_days <- ROLLING_WIN_MONTHS * 21
  n <- nrow(bm)
  q15 <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    cutoff_idx <- i - h - DATA_LAG
    if (cutoff_idx < win_days) next
    start_idx <- cutoff_idx - win_days + 1
    hist <- bm$ret_h[start_idx:cutoff_idx]
    hist <- hist[!is.na(hist)]
    if (length(hist) < 100) next
    q15[i] <- quantile(hist, 0.15, na.rm = TRUE)
  }
  bm[, paste0("y_tail_q15_h", h) := as.integer(!is.na(ret_h) & !is.na(q15) & ret_h <= q15)]
  bm[]
}

# ── Helper: PR-AUC ──
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y)
  p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE)
  y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord)
  rec  <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec)
  sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

# ── Multi-horizon target build ────────────────────────────
cat("[γ1] Building multi-horizon targets (h=5/21/63)...\n")
bm <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
setorder(bm, Date)

for (h in H_LIST) {
  cat(sprintf("  h=%d ... ", h))
  bm <- build_target_h(bm, h)
  events <- sum(bm[[paste0("y_tail_q15_h", h)]], na.rm = TRUE)
  cat(sprintf("events=%d (%.2f%%)\n", events, 100 * events / nrow(bm)))
}
write_parquet(bm[, c("Date", paste0("y_tail_q15_h", H_LIST)), with = FALSE],
              file.path(TGT_DIR, "targets_multi_horizon.parquet"))

# ── Model train per horizon (XGBoost, FEATURE_COLS alt) ─────
feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt.parquet")))
feat[, Date := as.Date(Date)]

panel <- merge(feat, bm[, c("Date", paste0("y_tail_q15_h", H_LIST)), with = FALSE],
               by = "Date", all.x = TRUE)
panel <- panel[Date <= OOS_END]

avail_feats <- intersect(FEATURE_COLS, names(panel))
X_all <- as.matrix(panel[, avail_feats, with = FALSE])

# Impute median (train period)
idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
col_meds <- apply(X_all[idx_train, , drop = FALSE], 2, function(x) median(x, na.rm = TRUE))
for (j in seq_len(ncol(X_all))) {
  na_rows <- is.na(X_all[, j])
  X_all[na_rows, j] <- col_meds[j]
}

predictions_list <- list()

for (h in H_LIST) {
  target_col <- paste0("y_tail_q15_h", h)
  Y <- panel[[target_col]]
  Y[is.na(Y)] <- 0L  # impute 0 for missing (conservative)

  idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
  idx_valid <- which(panel$Date >= VALID_START & panel$Date <= VALID_END)
  idx_oos   <- which(panel$Date >= OOS_START & panel$Date <= OOS_END)

  pos_weight <- sum(Y[idx_train] == 0) / max(sum(Y[idx_train] == 1), 1)
  pos_weight <- min(pos_weight, 8)

  dtrain <- xgb.DMatrix(X_all[idx_train, , drop = FALSE], label = Y[idx_train])
  dvalid <- xgb.DMatrix(X_all[idx_valid, , drop = FALSE], label = Y[idx_valid])

  cat(sprintf("\n[γ1 h=%d] XGBoost training (pos_weight=%.2f)...\n", h, pos_weight))
  fit <- xgb.train(
    params = list(booster = "gbtree", objective = "binary:logistic",
                  eval_metric = "aucpr", max_depth = 4, eta = 0.04,
                  subsample = 0.8, colsample_bytree = 0.8,
                  min_child_weight = 5, scale_pos_weight = pos_weight, seed = 42),
    data = dtrain, nrounds = 1000,
    evals = list(train = dtrain, valid = dvalid),
    early_stopping_rounds = 80, verbose = 0
  )
  cat(sprintf("  best_iter=%d valid_aucpr=%.4f\n",
              fit$best_iteration, fit$evaluation_log[fit$best_iteration]$valid_aucpr))

  preds <- predict(fit, X_all)
  pr_oos <- pr_auc(preds[idx_oos], Y[idx_oos])
  cat(sprintf("  OOS PR-AUC: %.4f\n", pr_oos))

  result <- data.table(Date = panel$Date, p_h = preds, y = Y, horizon = h)
  result[, split := fcase(
    Date >= OOS_START & Date <= OOS_END, "oos",
    Date >= VALID_START & Date <= VALID_END, "valid",
    Date >= TRAIN_START & Date <= TRAIN_END, "train",
    default = "other"
  )]
  predictions_list[[as.character(h)]] <- result
  write_parquet(result, file.path(MH_DIR, sprintf("predictions_h%d.parquet", h)))
}

# ── Multi-horizon ensemble (Equal-weight) ────────────────
cat("\n[γ1] Multi-horizon ensemble (EW)...\n")
ens <- predictions_list[["5"]][, .(Date)]
for (h in H_LIST) {
  ens[, paste0("p_h", h) := predictions_list[[as.character(h)]]$p_h]
}
ens[, p_mh_ew := rowMeans(ens[, paste0("p_h", H_LIST), with = FALSE], na.rm = TRUE)]

# Use h=21 target for ensemble OOS evaluation (primary)
ens[, y_h21 := predictions_list[["21"]]$y]
ens[, split := predictions_list[["21"]]$split]

oos <- ens[split == "oos"]
pr_oos_ew <- pr_auc(oos$p_mh_ew, oos$y_h21)
cat(sprintf("\n[γ1] OOS PR-AUC (multi-horizon EW, evaluated on h=21 target): %.4f\n", pr_oos_ew))
cat(sprintf("  Baseline (h=21 prevalence): %.4f\n", mean(oos$y_h21, na.rm = TRUE)))
cat(sprintf("  Lift: %.2f%%\n", 100 * (pr_oos_ew - mean(oos$y_h21)) / mean(oos$y_h21)))

write_parquet(ens, file.path(MH_DIR, "ensemble_multi_horizon.parquet"))
cat(sprintf("\n[γ1] DONE. Output: %s\n", MH_DIR))
