#==============================================================================
# 67_xgb_prototype_v2.R — Cycle 42 v1.3 Alt Data XGBoost retrain prototype (B path)
#
# Goal:
#   기존 enhanced feature panel (69 features, 8 base + lag/rolling/intx)
#   + 신규 4 features (VIX / 외국인 cum_5d / breadth ad_ratio_5d_avg / VKOSPI)
#   → XGBoost 1-way retrain (5-way 아님)
#   → OOS PR-AUC 비교 (baseline 69 vs extended 73)
#
# Decision rule:
#   ΔPR-AUC ≥ +0.03 → 5-way full retrain 권고
#   0 ~ +0.03 → marginal, 일부 features 유지
#   < 0 → 신규 feature 무가치
#
# PIT contract:
#   - 모든 신규 features daily Date 기준 lag-1 적용 (기존 panel 이미 lag-1)
#   - investor cum_5d = sum(t-5..t-1) → 자동 lag-1 안전
#   - VIX/VKOSPI/breadth raw daily값 → join 시 lag1 강제
#   - Coverage 제약: 외국인 데이터 2020-01부터 → OOS 2021-2026 fair test
#
# Walk-forward (simplified, single train/test split):
#   Train: 2016-01-01 ~ 2020-12-31 (외국인 부재 구간 — 외국인 = imputed median)
#         WAIT: 외국인은 2020-01부터만 가용 → 정직한 train/test split:
#         Train: 2020-01-01 ~ 2023-12-31 (4Y train)
#         Test:  2024-01-01 ~ 2026-04-30 (2.3Y OOS, 외국인 자체적으로 풍부)
#
# XGBoost params:
#   max_depth=4, eta=0.05, ntrees=500, early_stop=50, pos_weight=auto
#
# Output:
#   outputs/01_data/vix_daily_fred.csv
#   outputs/01_data/foreign_cum_5d.csv
#   outputs/01_data/feature_panel_v2_extended.parquet
#   outputs/04_evaluation/xgb_prototype_v2.json
#   outputs/06_reports/charts/67_pr_curve_v2_comparison.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
TARGET_DIR <- file.path(WS, "outputs/02_targets")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
INV_CACHE <- file.path(PROJECT_ROOT, ".cache/investor")

dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# ── PR-AUC helper ────────────────────────────────────────────────────────────
compute_prauc <- function(probs, labels) {
  if (sum(labels, na.rm = TRUE) == 0) return(NA_real_)
  ok <- !is.na(probs) & !is.na(labels)
  probs <- probs[ok]; labels <- labels[ok]
  if (length(probs) < 2) return(NA_real_)
  ord <- order(probs, decreasing = TRUE)
  labels_ord <- labels[ord]
  prec <- cumsum(labels_ord) / seq_along(labels_ord)
  rec  <- cumsum(labels_ord) / sum(labels_ord)
  n <- length(prec)
  if (n < 2) return(NA_real_)
  sum(diff(rec) * (prec[-1] + prec[-n]) / 2, na.rm = TRUE)
}

pr_curve_points <- function(probs, labels) {
  ok <- !is.na(probs) & !is.na(labels)
  probs <- probs[ok]; labels <- labels[ok]
  ord <- order(probs, decreasing = TRUE)
  labels_ord <- labels[ord]
  prec <- cumsum(labels_ord) / seq_along(labels_ord)
  rec  <- cumsum(labels_ord) / sum(labels_ord)
  data.table(recall = rec, precision = prec)
}

#==============================================================================
# Step 1: 신규 4 features 추출
#==============================================================================
cat("\n========== Step 1: Build new 4 features ==========\n")

# ── (1a) VIX daily FRED ──
cat("[1a] Parsing VIX FRED raw file...\n")
vix_raw <- readLines(file.path(DATA_DIR, "vixcls_fred_raw.txt"))
vix_lines <- vix_raw[grepl("^\\d{4}-\\d{2}-\\d{2}:", vix_raw)]
vix_dt <- data.table(
  Date = as.Date(substr(vix_lines, 1, 10)),
  vix_close = as.numeric(sub("^\\d{4}-\\d{2}-\\d{2}: ", "", vix_lines))
)
vix_dt <- vix_dt[!is.na(vix_close) & vix_close > 0]
setorder(vix_dt, Date)
fwrite(vix_dt, file.path(DATA_DIR, "vix_daily_fred.csv"))
cat(sprintf("  VIX daily: %d obs, %s ~ %s\n",
            nrow(vix_dt), as.character(min(vix_dt$Date)), as.character(max(vix_dt$Date))))

# ── (1b) 외국인 net cum_5d (KOSPI) ──
cat("[1b] Loading KOSPI investor net flow (cum_5d)...\n")
inv_market_path <- file.path(INV_CACHE, "investor_market.parquet")
if (file.exists(inv_market_path)) {
  inv_all <- as.data.table(read_parquet(inv_market_path))
  inv_kospi <- inv_all[market == "kospi", .(Date, foreign_net = 외국인)]
} else {
  # Fallback: parse daily CSVs (slower)
  files <- list.files(INV_CACHE, pattern = "^investor_kospi_\\d{8}\\.csv$", full.names = TRUE)
  inv_kospi <- rbindlist(lapply(files, function(f) {
    d <- tryCatch(fread(f), error = function(e) NULL)
    if (is.null(d) || nrow(d) == 0) return(NULL)
    d[, .(Date = as.Date(Date), foreign_net = 외국인)]
  }))
}
setorder(inv_kospi, Date)
inv_kospi[, foreign_cum_5d := frollsum(foreign_net, n = 5, align = "right", na.rm = TRUE)]
# Save
fwrite(inv_kospi[, .(Date, foreign_net, foreign_cum_5d)], file.path(DATA_DIR, "foreign_cum_5d.csv"))
cat(sprintf("  KOSPI foreign cum_5d: %d obs, %s ~ %s\n",
            nrow(inv_kospi), as.character(min(inv_kospi$Date)), as.character(max(inv_kospi$Date))))

# ── (1c) Breadth ad_ratio_5d_avg ──
cat("[1c] Computing breadth ad_ratio_5d_avg...\n")
br <- fread(file.path(DATA_DIR, "investor_breadth_daily.csv"))
br[, Date := as.Date(Date)]
br <- br[n_active >= 100]  # only meaningful breadth
setorder(br, Date)
br[, ad_ratio_5d_avg := frollmean(ad_ratio, n = 5, align = "right", na.rm = TRUE)]
cat(sprintf("  Breadth ad_ratio_5d_avg: %d obs, %s ~ %s\n",
            nrow(br), as.character(min(br$Date)), as.character(max(br$Date))))

# ── (1d) VKOSPI ──
cat("[1d] Loading VKOSPI daily...\n")
vk <- fread(file.path(DATA_DIR, "vkospi_daily.csv"))
vk[, Date := as.Date(Date)]
setnames(vk, "VKOSPI", "vkospi")
setorder(vk, Date)
cat(sprintf("  VKOSPI: %d obs, %s ~ %s\n",
            nrow(vk), as.character(min(vk$Date)), as.character(max(vk$Date))))

#==============================================================================
# Step 2: Join & PIT lag-1
#==============================================================================
cat("\n========== Step 2: Build extended feature panel ==========\n")

# Load enhanced panel (69 features, 이미 lag-1 적용)
feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")))
feat[, Date := as.Date(Date)]
setorder(feat, Date)
cat(sprintf("[2a] Enhanced panel base: %d rows × %d cols\n", nrow(feat), ncol(feat)))

# PIT lag-1 신규 features (raw daily값 → shift forward 1 row when joined by Date)
# 가장 안전한 방법: 신규 features 자체에 lag-1 적용 → Date join
add_lag1 <- function(dt, col) {
  setorder(dt, Date)
  newcol <- paste0(col, "_lag1")
  dt[, (newcol) := shift(get(col), 1L, type = "lag")]
  dt
}

vix_dt <- add_lag1(vix_dt, "vix_close")
inv_kospi <- add_lag1(inv_kospi, "foreign_cum_5d")
br <- add_lag1(br, "ad_ratio_5d_avg")
vk <- add_lag1(vk, "vkospi")

# Join: feat ← left join + 4 new lag1 features
feat_ext <- feat[vix_dt[, .(Date, vix_close_lag1)], on = "Date"]
feat_ext <- feat_ext[inv_kospi[, .(Date, foreign_cum_5d_lag1)], on = "Date"]
feat_ext <- feat_ext[br[, .(Date, ad_ratio_5d_avg_lag1)], on = "Date"]
feat_ext <- feat_ext[vk[, .(Date, vkospi_lag1)], on = "Date"]

# After joins via [..] it returned modified — but those return new copy with NA for unmatched. Re-do via merge to be safe.
feat_ext <- merge(feat,
                  vix_dt[, .(Date, vix_close_lag1)],
                  by = "Date", all.x = TRUE)
feat_ext <- merge(feat_ext,
                  inv_kospi[, .(Date, foreign_cum_5d_lag1)],
                  by = "Date", all.x = TRUE)
feat_ext <- merge(feat_ext,
                  br[, .(Date, ad_ratio_5d_avg_lag1)],
                  by = "Date", all.x = TRUE)
feat_ext <- merge(feat_ext,
                  vk[, .(Date, vkospi_lag1)],
                  by = "Date", all.x = TRUE)
setorder(feat_ext, Date)

cat(sprintf("[2b] Extended panel: %d rows × %d cols\n", nrow(feat_ext), ncol(feat_ext)))
new_cols <- c("vix_close_lag1", "foreign_cum_5d_lag1", "ad_ratio_5d_avg_lag1", "vkospi_lag1")
for (c in new_cols) {
  cov <- sum(!is.na(feat_ext[[c]])) / nrow(feat_ext)
  cat(sprintf("  %-30s : %.1f%% cover (n=%d)\n", c, 100 * cov, sum(!is.na(feat_ext[[c]]))))
}

write_parquet(feat_ext, file.path(DATA_DIR, "feature_panel_v2_extended.parquet"))
cat(sprintf("[2c] Saved: %s\n", file.path(DATA_DIR, "feature_panel_v2_extended.parquet")))

#==============================================================================
# Step 3: Merge target + define train/test split
#==============================================================================
cat("\n========== Step 3: Merge target + split ==========\n")

tgt <- as.data.table(read_parquet(file.path(TARGET_DIR, "targets_full.parquet")))
tgt[, Date := as.Date(Date)]
panel <- merge(feat_ext, tgt[, .(Date, y_tail_q15)], by = "Date", all.x = TRUE)
setorder(panel, Date)

# Bound: 외국인 가용 2020-01부터 → fair test
# Train: 2020-01-01 ~ 2023-12-31, Test: 2024-01-01 ~ 2026-04-30
TRAIN_START <- as.Date("2020-01-01")
TRAIN_END   <- as.Date("2023-12-31")
TEST_START  <- as.Date("2024-01-01")
TEST_END    <- as.Date("2026-04-30")

idx_train <- which(panel$Date >= TRAIN_START & panel$Date <= TRAIN_END)
idx_test  <- which(panel$Date >= TEST_START & panel$Date <= TEST_END)

# Filter rows with valid target
idx_train <- idx_train[!is.na(panel$y_tail_q15[idx_train])]
idx_test  <- idx_test[!is.na(panel$y_tail_q15[idx_test])]

cat(sprintf("[3a] Train (2020-01 ~ 2023-12): %d rows, %d positives (%.2f%%)\n",
            length(idx_train), sum(panel$y_tail_q15[idx_train]),
            100 * mean(panel$y_tail_q15[idx_train])))
cat(sprintf("[3b] Test (2024-01 ~ 2026-04): %d rows, %d positives (%.2f%%)\n",
            length(idx_test), sum(panel$y_tail_q15[idx_test]),
            100 * mean(panel$y_tail_q15[idx_test])))

#==============================================================================
# Step 4: XGBoost retrain — baseline (69 features) vs extended (73 features)
#==============================================================================
cat("\n========== Step 4: XGBoost retrain ==========\n")

# Define feature lists
base_cols <- setdiff(names(feat), "Date")  # 69 features
ext_cols  <- c(base_cols, new_cols)        # 73 features

cat(sprintf("[4a] Baseline features: %d\n", length(base_cols)))
cat(sprintf("[4b] Extended features: %d (+ %d new)\n", length(ext_cols), length(new_cols)))

# Train XGBoost
train_xgb <- function(cols, label = "baseline") {
  X_train <- as.matrix(panel[idx_train, cols, with = FALSE])
  Y_train <- panel$y_tail_q15[idx_train]
  X_test  <- as.matrix(panel[idx_test, cols, with = FALSE])
  Y_test  <- panel$y_tail_q15[idx_test]

  pos_w <- sum(Y_train == 0, na.rm = TRUE) / max(sum(Y_train == 1, na.rm = TRUE), 1)
  pos_w <- min(pos_w, 8)
  cat(sprintf("\n[%s] X_train %dx%d / X_test %dx%d / pos_w=%.2f\n",
              label, nrow(X_train), ncol(X_train), nrow(X_test), ncol(X_test), pos_w))

  dtrain <- xgb.DMatrix(data = X_train, label = Y_train)
  dtest  <- xgb.DMatrix(data = X_test, label = Y_test)

  # Use last 20% of train as internal validation for early stopping
  n_tr <- nrow(X_train)
  cut <- floor(n_tr * 0.8)
  dtrain_in <- xgb.DMatrix(data = X_train[1:cut, , drop = FALSE], label = Y_train[1:cut])
  dvalid_in <- xgb.DMatrix(data = X_train[(cut + 1):n_tr, , drop = FALSE], label = Y_train[(cut + 1):n_tr])

  params <- list(
    booster = "gbtree", objective = "binary:logistic", eval_metric = "aucpr",
    max_depth = 4, eta = 0.05, subsample = 0.8, colsample_bytree = 0.8,
    min_child_weight = 5, scale_pos_weight = pos_w, seed = 42
  )

  set.seed(42)
  fit <- xgb.train(
    params = params, data = dtrain_in, nrounds = 500,
    evals = list(train = dtrain_in, valid = dvalid_in),
    early_stopping_rounds = 50, verbose = 0
  )
  cat(sprintf("[%s] best_iter=%d / valid_aucpr=%.4f\n",
              label, fit$best_iteration, fit$best_score))

  pred_test <- predict(fit, dtest)
  prauc_test <- compute_prauc(pred_test, Y_test)
  cat(sprintf("[%s] OOS PR-AUC (2024-01~2026-04): %.4f\n", label, prauc_test))

  # Refit on full train (no internal val) for final reported model — for fair compare
  refit_iters <- max(fit$best_iteration, 50)
  fit_full <- xgb.train(
    params = params, data = dtrain, nrounds = refit_iters,
    verbose = 0
  )
  pred_test_full <- predict(fit_full, dtest)
  prauc_test_full <- compute_prauc(pred_test_full, Y_test)
  cat(sprintf("[%s] OOS PR-AUC (full-train refit): %.4f\n", label, prauc_test_full))

  imp <- as.data.table(xgb.importance(model = fit_full))

  list(fit = fit_full, best_iter = fit$best_iteration,
       prauc_test_es = prauc_test, prauc_test = prauc_test_full,
       pred_test = pred_test_full, Y_test = Y_test,
       Date_test = panel$Date[idx_test], imp = imp, cols = cols, label = label)
}

res_base <- train_xgb(base_cols, "BASELINE_69")
res_ext  <- train_xgb(ext_cols,  "EXTENDED_73")

#==============================================================================
# Step 5: Compare + Verdict
#==============================================================================
cat("\n========== Step 5: Compare + Verdict ==========\n")
delta <- res_ext$prauc_test - res_base$prauc_test
cat(sprintf("\nBaseline OOS PR-AUC : %.4f\n", res_base$prauc_test))
cat(sprintf("Extended OOS PR-AUC : %.4f\n", res_ext$prauc_test))
cat(sprintf("Delta              : %+.4f\n", delta))

verdict <- if (delta >= 0.03) {
  "5_WAY_FULL_RECOMMENDED"
} else if (delta >= 0) {
  "MARGINAL_PARTIAL_FEATURES"
} else {
  "NEW_FEATURES_NOT_VALUABLE"
}
cat(sprintf("Verdict            : %s\n", verdict))

# Feature importance — new 4 features 위치
cat("\n[Feature importance — Extended top 15]\n")
print(head(res_ext$imp, 15))
cat("\n[New 4 features position in Extended importance]\n")
imp_ext <- res_ext$imp
imp_ext[, rank := seq_len(.N)]
new_in_imp <- imp_ext[Feature %in% new_cols, .(Feature, Gain, rank, total_features = nrow(imp_ext))]
print(new_in_imp)
n_missing <- length(setdiff(new_cols, imp_ext$Feature))
if (n_missing > 0) {
  cat(sprintf("  (Missing from importance — never used by splits: %d feature(s))\n", n_missing))
  cat("  Not-used new features:", paste(setdiff(new_cols, imp_ext$Feature), collapse = ", "), "\n")
}

#==============================================================================
# Step 6: Save JSON + PR curve chart
#==============================================================================
cat("\n========== Step 6: Save outputs ==========\n")

out <- list(
  prototype_name = "67_xgb_prototype_v2",
  cycle = 42,
  run_timestamp = as.character(Sys.time()),
  train_window = list(start = as.character(TRAIN_START), end = as.character(TRAIN_END),
                       n_rows = length(idx_train),
                       n_positives = sum(panel$y_tail_q15[idx_train]),
                       pos_rate = unname(round(mean(panel$y_tail_q15[idx_train]), 4))),
  test_window = list(start = as.character(TEST_START), end = as.character(TEST_END),
                      n_rows = length(idx_test),
                      n_positives = sum(panel$y_tail_q15[idx_test]),
                      pos_rate = unname(round(mean(panel$y_tail_q15[idx_test]), 4))),
  xgb_params = list(max_depth = 4, eta = 0.05, ntrees_cap = 500,
                     early_stopping = 50, pos_weight_cap = 8),
  baseline_69 = list(
    n_features = length(base_cols),
    best_iter = res_base$best_iter,
    prauc_oos = round(res_base$prauc_test, 4),
    prauc_oos_es = round(res_base$prauc_test_es, 4)
  ),
  extended_73 = list(
    n_features = length(ext_cols),
    best_iter = res_ext$best_iter,
    prauc_oos = round(res_ext$prauc_test, 4),
    prauc_oos_es = round(res_ext$prauc_test_es, 4),
    new_features = new_cols
  ),
  delta = round(delta, 4),
  verdict = verdict,
  decision_rule = list(
    full_5way = "ΔPR-AUC ≥ +0.03",
    marginal = "0 ~ +0.03",
    reject = "< 0"
  ),
  new_features_importance = lapply(seq_len(nrow(new_in_imp)), function(i) {
    list(feature = new_in_imp$Feature[i],
         gain = round(new_in_imp$Gain[i], 4),
         rank = new_in_imp$rank[i],
         total = new_in_imp$total_features[i])
  }),
  new_features_unused = setdiff(new_cols, imp_ext$Feature),
  outputs = list(
    vix_csv = file.path(DATA_DIR, "vix_daily_fred.csv"),
    foreign_csv = file.path(DATA_DIR, "foreign_cum_5d.csv"),
    panel_parquet = file.path(DATA_DIR, "feature_panel_v2_extended.parquet"),
    pr_curve_chart = file.path(CHART_DIR, "67_pr_curve_v2_comparison.png")
  )
)
out_path <- file.path(EVAL_DIR, "xgb_prototype_v2.json")
write_json(out, out_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[JSON] %s\n", out_path))

# PR curve comparison
curve_base <- pr_curve_points(res_base$pred_test, res_base$Y_test)
curve_base[, model := sprintf("Baseline 69 (PR-AUC=%.4f)", res_base$prauc_test)]
curve_ext  <- pr_curve_points(res_ext$pred_test, res_ext$Y_test)
curve_ext[, model  := sprintf("Extended 73 (PR-AUC=%.4f)", res_ext$prauc_test)]
curves <- rbind(curve_base, curve_ext)

base_rate <- mean(res_base$Y_test, na.rm = TRUE)
g <- ggplot(curves, aes(x = recall, y = precision, color = model)) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = base_rate, linetype = "dashed", color = "gray40") +
  scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
  labs(title = sprintf("XGBoost 1-way PR Curve — Baseline 69 vs Extended 73 (Δ %+.4f, %s)",
                       delta, verdict),
       subtitle = sprintf("OOS 2024-01 ~ 2026-04 (n=%d, pos_rate=%.2f%%)",
                          length(idx_test), 100 * base_rate),
       x = "Recall", y = "Precision", color = NULL,
       caption = "Dashed = baseline (random precision = positive rate)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(CHART_DIR, "67_pr_curve_v2_comparison.png"),
       plot = g, width = 11, height = 6, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "67_pr_curve_v2_comparison.png")))

cat("\n========== DONE ==========\n")
