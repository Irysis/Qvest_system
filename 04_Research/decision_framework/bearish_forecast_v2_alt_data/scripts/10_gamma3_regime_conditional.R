#==============================================================================
# 10_gamma3_regime_conditional.R — γ3 Regime-conditional model
#
# Plan v1.0 → v1.1 Step 3 γ3
#
# 시장 국면 (bull/bear/sideways) 분류 → 국면별 별도 XGBoost
# 현재 regime에 맞는 model의 prediction 사용 (gating)
#
# Regime 정의 (간단):
#   bear:     bbva_macro_composite top 30%
#   bull:     bbva_macro_composite bottom 30%
#   sideways: middle 40%
#
# Output: outputs/03_models/regime_conditional/{models_per_regime.rds, predictions_gated.parquet}
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(xgboost)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS_DIR, "outputs/01_data")
TGT_DIR <- file.path(WS_DIR, "outputs/02_targets")
OUT_DIR <- file.path(WS_DIR, "outputs/03_models/regime_conditional")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

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

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

# ── Load data ──
cat("[γ3] Loading feature panel + targets...\n")
feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt.parquet")))
tgt <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
feat[, Date := as.Date(Date)]; tgt[, Date := as.Date(Date)]
panel <- merge(feat, tgt[, .(Date, y_tail_q15)], by = "Date", all.x = TRUE)
setorder(panel, Date)
panel <- panel[Date <= OOS_END]

# ── Regime classification (using bbva_macro_composite) ──
# Use train period only to define thresholds (PIT-safe)
train_macro <- panel[Date >= TRAIN_START & Date <= TRAIN_END & !is.na(bbva_macro_composite),
                     bbva_macro_composite]
q33 <- quantile(train_macro, 0.33, na.rm = TRUE)
q67 <- quantile(train_macro, 0.67, na.rm = TRUE)
cat(sprintf("[γ3] Regime thresholds (train-derived): q33=%.3f / q67=%.3f\n", q33, q67))

panel[, regime := fcase(
  is.na(bbva_macro_composite), NA_character_,
  bbva_macro_composite <= q33, "bull",
  bbva_macro_composite >= q67, "bear",
  default = "sideways"
)]

# regime distribution per split
cat("\n[γ3] Regime distribution:\n")
print(panel[, .N, by = .(split = fcase(
  Date >= OOS_START & Date <= OOS_END, "oos",
  Date >= VALID_START & Date <= VALID_END, "valid",
  Date >= TRAIN_START & Date <= TRAIN_END, "train",
  default = "other"
), regime)][order(split, regime)])

# ── Train one XGBoost per regime ──
avail_feats <- intersect(FEATURE_COLS, names(panel))
X_all <- as.matrix(panel[, avail_feats, with = FALSE])

# Impute median
idx_train_all <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
col_meds <- apply(X_all[idx_train_all, , drop = FALSE], 2, function(x) median(x, na.rm = TRUE))
for (j in seq_len(ncol(X_all))) X_all[is.na(X_all[, j]), j] <- col_meds[j]

Y_all <- panel$y_tail_q15
Y_all[is.na(Y_all)] <- 0L

regime_predictions <- list()

for (rgm in c("bull", "sideways", "bear")) {
  idx_train_rgm <- which(panel$regime == rgm &
                          panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
  idx_valid_rgm <- which(panel$regime == rgm &
                          panel$Date >= VALID_START & panel$Date <= VALID_END)

  if (length(idx_train_rgm) < 100 || length(idx_valid_rgm) < 30) {
    cat(sprintf("[γ3 %s] Insufficient data (train=%d/valid=%d). Skip.\n",
                rgm, length(idx_train_rgm), length(idx_valid_rgm)))
    next
  }

  pos_weight <- sum(Y_all[idx_train_rgm] == 0) /
                max(sum(Y_all[idx_train_rgm] == 1), 1)
  pos_weight <- min(pos_weight, 8)

  dtrain <- xgb.DMatrix(X_all[idx_train_rgm, , drop = FALSE], label = Y_all[idx_train_rgm])
  dvalid <- xgb.DMatrix(X_all[idx_valid_rgm, , drop = FALSE], label = Y_all[idx_valid_rgm])

  cat(sprintf("\n[γ3 %s] Training (train=%d / valid=%d / pos_weight=%.2f)...\n",
              rgm, length(idx_train_rgm), length(idx_valid_rgm), pos_weight))
  fit <- xgb.train(
    params = list(booster = "gbtree", objective = "binary:logistic",
                  eval_metric = "aucpr", max_depth = 4, eta = 0.04,
                  subsample = 0.8, colsample_bytree = 0.8,
                  min_child_weight = 5, scale_pos_weight = pos_weight, seed = 42),
    data = dtrain, nrounds = 1000,
    evals = list(train = dtrain, valid = dvalid),
    early_stopping_rounds = 80, verbose = 0
  )

  # Predict on entire X (all regimes) — gating applies only at OOS use
  preds <- predict(fit, X_all)
  regime_predictions[[rgm]] <- preds
}

# ── Gated predictions (use regime-matched model at each row) ──
panel[, p_gated := NA_real_]
for (rgm in names(regime_predictions)) {
  match_idx <- which(panel$regime == rgm)
  panel[match_idx, p_gated := regime_predictions[[rgm]][match_idx]]
}

# OOS evaluation
oos <- panel[Date >= OOS_START & Date <= OOS_END & !is.na(p_gated) & !is.na(y_tail_q15)]
pr_oos <- pr_auc(oos$p_gated, oos$y_tail_q15)
baseline <- mean(oos$y_tail_q15)
cat(sprintf("\n[γ3 Regime-Conditional] OOS PR-AUC: %.4f (baseline %.4f, lift %.2f%%)\n",
            pr_oos, baseline, 100 * (pr_oos - baseline) / baseline))

# OOS per regime
cat("\n[γ3] OOS PR-AUC per regime:\n")
for (rgm in c("bull", "sideways", "bear")) {
  sub <- oos[regime == rgm]
  if (nrow(sub) < 30) { cat(sprintf("  %-10s: insufficient\n", rgm)); next }
  pa <- pr_auc(sub$p_gated, sub$y_tail_q15)
  cat(sprintf("  %-10s: N=%d / events=%d (%.2f%%) / PR-AUC=%.4f\n",
              rgm, nrow(sub), sum(sub$y_tail_q15),
              100 * mean(sub$y_tail_q15), pa))
}

write_parquet(panel[, .(Date, regime, p_gated, y_tail_q15)],
              file.path(OUT_DIR, "predictions_gated.parquet"))

cat(sprintf("\n[γ3] DONE. Output: %s\n", OUT_DIR))
