#==============================================================================
# 73_5way_aggregate_v3_breadth_suite.R — Cycle 44 Step 4-6
#
# Steps:
#   Step 4: 5-way merge (XGB + CatBoost + RF + LSTM + TFT v3_breadth_suite preds)
#   Step 5: Dynamic 5-method ensemble synthesis (M1~M5)
#   Step 6: Compare vs Cycle 43 v2_2feat baseline (M2 0.6390 / M1 0.6459)
#
# Output:
#   outputs/03_models/v3_breadth_suite/predictions_5way_{target}.parquet
#   outputs/03_models/v3_breadth_suite/predictions_dynamic_{target}.parquet
#   outputs/04_evaluation/5way_retrain_v3_breadth_suite.json
#   outputs/06_reports/charts/73_pr_curve_v3_breadth_suite.png
#
# Decision rule:
#   Δ M2 Regime ≥ +0.01 → CONTINUE (extend breadth suite)
#   0 < Δ < +0.01 → MARGINAL (preserve, next family)
#   Δ ≤ 0 → REGRESSION (drop additions, diagnose)
#
# NOTE: V10 trigger evaluation skipped (도훈 mandate Cycle 44 — model performance only)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
V3_DIR <- file.path(WS, "outputs/03_models/v3_breadth_suite")
V2_DIR <- file.path(WS, "outputs/03_models/v2_2feat")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(V3_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

LOOKBACK <- 252
PURGE <- 21

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

roc_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5 || sum(y) == length(y)) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  TPR <- cumsum(y_ord) / sum(y_ord)
  FPR <- cumsum(1 - y_ord) / sum(1 - y_ord)
  n <- length(TPR); sum(diff(FPR) * (TPR[-1] + TPR[-n]) / 2)
}

softmax <- function(x, beta = 5) {
  e <- exp(x * beta - max(x * beta))
  e / sum(e)
}

pr_curve <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  data.table(recall = rec, precision = prec)
}

#==============================================================================
# Step 4: 5-way merge
#==============================================================================
cat("\n========== Step 4: 5-way merge (XGB+Cat+RF + LSTM + TFT v3_breadth_suite) ==========\n")

make_5way <- function(target_col) {
  cat(sprintf("\n----- 5-way merge: %s -----\n", target_col))
  gbdt <- as.data.table(read_parquet(file.path(V3_DIR, sprintf("predictions_3way_%s.parquet", target_col))))
  gbdt[, Date := as.Date(Date)]
  lstm <- as.data.table(read_parquet(file.path(V3_DIR, sprintf("predictions_lstm_%s.parquet", target_col))))
  lstm[, Date := as.Date(Date)]
  tft <- as.data.table(read_parquet(file.path(V3_DIR, sprintf("predictions_tft_%s.parquet", target_col))))
  tft[, Date := as.Date(Date)]

  oos_gbdt <- gbdt[split == "oos", .(Date, p_xgb, p_cat, p_rf, y)]
  oos <- merge(oos_gbdt, lstm[, .(Date, p_lstm)], by = "Date", all = TRUE)
  oos <- merge(oos, tft[, .(Date, p_tft)], by = "Date", all = TRUE)
  oos <- oos[!is.na(y) & !is.na(p_xgb) & !is.na(p_lstm) & !is.na(p_tft)]
  cat(sprintf("[merge] OOS N=%d / events=%d (%.2f%%)\n",
              nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  pr_xgb <- pr_auc(oos$p_xgb, oos$y); pr_cat <- pr_auc(oos$p_cat, oos$y)
  pr_rf <- pr_auc(oos$p_rf, oos$y); pr_lstm <- pr_auc(oos$p_lstm, oos$y); pr_tft <- pr_auc(oos$p_tft, oos$y)

  roc_xgb <- roc_auc(oos$p_xgb, oos$y); roc_cat <- roc_auc(oos$p_cat, oos$y)
  roc_rf <- roc_auc(oos$p_rf, oos$y); roc_lstm <- roc_auc(oos$p_lstm, oos$y); roc_tft <- roc_auc(oos$p_tft, oos$y)

  cat(sprintf("[v3_breadth_suite individual OOS PR-AUC] XGB=%.4f / CAT=%.4f / RF=%.4f / LSTM=%.4f / TFT=%.4f\n",
              pr_xgb, pr_cat, pr_rf, pr_lstm, pr_tft))
  cat(sprintf("[v3_breadth_suite individual OOS ROC-AUC] XGB=%.4f / CAT=%.4f / RF=%.4f / LSTM=%.4f / TFT=%.4f\n",
              roc_xgb, roc_cat, roc_rf, roc_lstm, roc_tft))

  # EW + Weighted EW for reference
  oos[, p_ew5 := (p_xgb + p_cat + p_rf + p_lstm + p_tft) / 5]
  oos[, p_wew := 0.25 * p_xgb + 0.25 * p_cat + 0.25 * p_rf + 0.125 * p_lstm + 0.125 * p_tft]
  pr_ew5 <- pr_auc(oos$p_ew5, oos$y); pr_wew <- pr_auc(oos$p_wew, oos$y)
  cat(sprintf("[v3_breadth_suite] EW5=%.4f / WEW=%.4f\n", pr_ew5, pr_wew))

  write_parquet(oos, file.path(V3_DIR, sprintf("predictions_5way_%s.parquet", target_col)))
  list(individual = list(xgb=pr_xgb, cat=pr_cat, rf=pr_rf, lstm=pr_lstm, tft=pr_tft),
       roc_individual = list(xgb=roc_xgb, cat=roc_cat, rf=roc_rf, lstm=roc_lstm, tft=roc_tft),
       ew5 = pr_ew5, wew = pr_wew, oos = oos)
}

res_5w_q15 <- make_5way("y_tail_q15")
res_5w_onset <- make_5way("y_onset")

#==============================================================================
# Step 5: Dynamic 5-method synthesis (M1~M5) — identical algos to Cycle 43
#==============================================================================
cat("\n========== Step 5: Dynamic 5-method ensemble synthesis ==========\n")

run_dynamic_v3 <- function(target_col, oos_in) {
  cat(sprintf("\n----- Dynamic 5-method: %s -----\n", target_col))
  p5 <- copy(oos_in); setorder(p5, Date); n_total <- nrow(p5)
  M_NAMES <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft")
  M <- as.matrix(p5[, ..M_NAMES]); Y <- p5$y

  # Static baseline (Weighted EW — GBDT-favored same as Cycle 43)
  w_static <- c(0.25, 0.25, 0.25, 0.125, 0.125)
  p_static <- as.numeric(M %*% w_static)
  pa_static <- pr_auc(p_static, Y)
  cat(sprintf("[Static WEW] PR-AUC=%.4f\n", pa_static))

  # M1: Rolling Adaptive — softmax of per-model rolling PR-AUC
  p_M1 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    cutoff <- i - PURGE; start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    p_w <- M[start:cutoff, , drop = FALSE]; y_w <- Y[start:cutoff]
    pr_m <- sapply(seq_len(5), function(m) pr_auc(p_w[, m], y_w))
    pr_m[is.na(pr_m)] <- 0
    w <- softmax(pr_m, beta = 5)
    p_M1[i] <- sum(M[i, ] * w)
  }
  pa_M1 <- pr_auc(p_M1, Y)
  cat(sprintf("[M1 Rolling]  PR-AUC=%.4f %s\n", pa_M1, ifelse(pa_M1 > pa_static, "★", "")))

  # M2: Regime-Conditional (bbva_macro_composite quantile)
  feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v3_breadth_suite.parquet")))
  feat[, Date := as.Date(Date)]
  p5_r <- merge(p5, feat[, .(Date, bbva_macro_composite)], by = "Date", all.x = TRUE)
  setorder(p5_r, Date)
  train_macro <- p5_r$bbva_macro_composite[seq_len(min(2000, n_total))]
  q33 <- quantile(train_macro, 0.33, na.rm = TRUE)
  q67 <- quantile(train_macro, 0.67, na.rm = TRUE)
  p5_r[, regime := fcase(
    is.na(bbva_macro_composite), NA_character_,
    bbva_macro_composite <= q33, "bull",
    bbva_macro_composite >= q67, "bear",
    default = "sideways"
  )]
  M_r <- as.matrix(p5_r[, ..M_NAMES]); Y_r <- p5_r$y; Regime <- p5_r$regime
  p_M2 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    cur_reg <- Regime[i]
    if (is.na(cur_reg)) next
    cutoff <- i - PURGE; start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    in_reg <- which(Regime[start:cutoff] == cur_reg) + (start - 1)
    if (length(in_reg) < 30) {
      p_M2[i] <- sum(M_r[i, ] * w_static); next
    }
    pr_m <- sapply(seq_len(5), function(m) pr_auc(M_r[in_reg, m], Y_r[in_reg]))
    pr_m[is.na(pr_m)] <- 0
    w <- softmax(pr_m, beta = 5)
    p_M2[i] <- sum(M_r[i, ] * w)
  }
  pa_M2 <- pr_auc(p_M2, Y_r)
  cat(sprintf("[M2 Regime]   PR-AUC=%.4f %s\n", pa_M2, ifelse(pa_M2 > pa_static, "★", "")))

  # M3: Online Hedge
  eta <- 1.0; w_hedge <- rep(1/5, 5)
  p_M3 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    p_M3[i] <- sum(M[i, ] * w_hedge)
    if (!is.na(Y[i])) {
      losses <- (M[i, ] - Y[i])^2
      w_hedge <- w_hedge * exp(-eta * losses); w_hedge <- w_hedge / sum(w_hedge)
    }
  }
  pa_M3 <- pr_auc(p_M3, Y)
  cat(sprintf("[M3 Hedge]    PR-AUC=%.4f %s\n", pa_M3, ifelse(pa_M3 > pa_static, "★", "")))

  # M4: Bayesian Online
  log_lik <- rep(0, 5); w_bayes <- rep(1/5, 5)
  p_M4 <- rep(NA_real_, n_total); eps <- 1e-6
  for (i in seq_len(n_total)) {
    p_M4[i] <- sum(M[i, ] * w_bayes)
    if (!is.na(Y[i])) {
      p_clip <- pmax(pmin(M[i, ], 1 - eps), eps)
      log_lik_i <- Y[i] * log(p_clip) + (1 - Y[i]) * log(1 - p_clip)
      log_lik <- log_lik + log_lik_i
      w_bayes <- softmax(log_lik / max(i, 100), beta = 50)
    }
  }
  pa_M4 <- pr_auc(p_M4, Y)
  cat(sprintf("[M4 Bayes]    PR-AUC=%.4f %s\n", pa_M4, ifelse(pa_M4 > pa_static, "★", "")))

  # M5: Contextual Bandit
  EPSILON <- 0.1
  Q <- matrix(0, nrow = 3, ncol = 5); counts <- matrix(0, nrow = 3, ncol = 5)
  regime_to_idx <- function(r) {
    if (is.na(r)) return(2)
    fcase(r == "bull", 1, r == "sideways", 2, r == "bear", 3, default = 2)
  }
  p_M5 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    reg_idx <- regime_to_idx(Regime[i])
    if (runif(1) < EPSILON) chosen <- sample(1:5, 1) else chosen <- which.max(Q[reg_idx, ])
    w_q <- softmax(Q[reg_idx, ], beta = 3)
    p_M5[i] <- sum(M[i, ] * w_q)
    if (!is.na(Y[i])) {
      for (m in seq_len(5)) {
        reward <- -((M[i, m] - Y[i])^2)
        counts[reg_idx, m] <- counts[reg_idx, m] + 1
        Q[reg_idx, m] <- Q[reg_idx, m] + (reward - Q[reg_idx, m]) / counts[reg_idx, m]
      }
    }
  }
  pa_M5 <- pr_auc(p_M5, Y)
  cat(sprintf("[M5 Bandit]   PR-AUC=%.4f %s\n", pa_M5, ifelse(pa_M5 > pa_static, "★", "")))

  out <- p5_r[, .(Date, y, regime,
                  p_static = p_static,
                  p_M1_rolling = p_M1,
                  p_M2_regime = p_M2,
                  p_M3_hedge = p_M3,
                  p_M4_bayes = p_M4,
                  p_M5_bandit = p_M5)]
  write_parquet(out, file.path(V3_DIR, sprintf("predictions_dynamic_%s.parquet", target_col)))

  data.table(
    target = target_col,
    method = c("Static_WEW", "M1_Rolling", "M2_Regime", "M3_Hedge", "M4_Bayes", "M5_Bandit"),
    PRAUC = c(pa_static, pa_M1, pa_M2, pa_M3, pa_M4, pa_M5)
  )
}

dyn_q15 <- run_dynamic_v3("y_tail_q15", res_5w_q15$oos)
dyn_onset <- run_dynamic_v3("y_onset", res_5w_onset$oos)

cat("\n[Step 5 Dynamic SUMMARY]\n")
print(rbind(dyn_q15, dyn_onset))

#==============================================================================
# Step 6: Compare vs Cycle 43 v2_2feat baseline
#==============================================================================
cat("\n========== Step 6: Compare vs Cycle 43 v2_2feat baseline ==========\n")

# Cycle 43 known values
bsl_static_q15 <- 0.5827
bsl_m1_q15     <- 0.6459
bsl_m2_q15     <- 0.6390

v3_static_q15  <- dyn_q15[method == "Static_WEW", PRAUC]
v3_m1_q15      <- dyn_q15[method == "M1_Rolling", PRAUC]
v3_m2_q15      <- dyn_q15[method == "M2_Regime", PRAUC]

delta_static <- v3_static_q15 - bsl_static_q15
delta_m1     <- v3_m1_q15 - bsl_m1_q15
delta_m2     <- v3_m2_q15 - bsl_m2_q15

cat(sprintf("\n[Δ vs Cycle 43 v2_2feat baseline on y_tail_q15]\n"))
cat(sprintf("  Static WEW:  v2_2feat=%.4f → v3_breadth_suite=%.4f  (Δ %+.4f)\n",
            bsl_static_q15, v3_static_q15, delta_static))
cat(sprintf("  M1 Rolling:  v2_2feat=%.4f → v3_breadth_suite=%.4f  (Δ %+.4f) ★\n",
            bsl_m1_q15, v3_m1_q15, delta_m1))
cat(sprintf("  M2 Regime:   v2_2feat=%.4f → v3_breadth_suite=%.4f  (Δ %+.4f) ★\n",
            bsl_m2_q15, v3_m2_q15, delta_m2))

# Verdict based on M2 Regime (primary measure, same as Cycle 43)
verdict <- if (delta_m2 >= 0.01) {
  "CONTINUE"
} else if (delta_m2 > 0.0) {
  "MARGINAL"
} else {
  "REGRESSION"
}
cat(sprintf("\n[Verdict (5-way M2 Regime)] %s\n", verdict))

#==============================================================================
# Step 6b: Breadth feature correlation matrix (regression diagnostic)
#==============================================================================
cat("\n========== Step 6b: Breadth feature correlation matrix ==========\n")

feat_v3 <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v3_breadth_suite.parquet")))
feat_v3[, Date := as.Date(Date)]
breadth_cols <- c("ad_ratio_5d_avg_lag1",
                  "ad_ratio_20d_avg_lag1",
                  "ad_ratio_60d_avg_lag1",
                  "hhi_buy_lag1",
                  "n_active_z20_lag1")
br_mat <- feat_v3[, ..breadth_cols]
cor_mat <- cor(br_mat, use = "pairwise.complete.obs")
cat("\n[Breadth features 5x5 correlation matrix]:\n")
print(round(cor_mat, 3))

#==============================================================================
# Step 7: Save JSON + Chart
#==============================================================================
cat("\n========== Step 7: Save outputs ==========\n")

# Load Step 2 summary for feature importance
step2_path <- file.path(EVAL_DIR, "5way_retrain_v3_breadth_suite_step2.json")
step2 <- if (file.exists(step2_path)) fromJSON(step2_path) else list(error = "missing step2 json")

# Load Cycle 43 v2_2feat dynamic for comparison
v2_dyn_path <- file.path(V2_DIR, "predictions_dynamic_y_tail_q15.parquet")
if (file.exists(v2_dyn_path)) {
  v2_dyn_q15 <- as.data.table(read_parquet(v2_dyn_path))
  v2_dyn_q15[, Date := as.Date(Date)]
} else {
  v2_dyn_q15 <- NULL
}

# Load current v3 dynamic
v3_dyn_q15 <- as.data.table(read_parquet(file.path(V3_DIR, "predictions_dynamic_y_tail_q15.parquet")))
v3_dyn_q15[, Date := as.Date(Date)]

result_json <- list(
  cycle = 44,
  approach = "BREADTH_SUITE_EXTENSION",
  features_added_4 = c("ad_ratio_20d_avg_lag1", "ad_ratio_60d_avg_lag1",
                        "hhi_buy_lag1", "n_active_z20_lag1"),
  features_retained = c("ad_ratio_5d_avg_lag1"),
  features_dropped = c("foreign_cum_5d_lag1"),
  baseline_v2_2feat = list(
    n_features = 71,
    static_wew_y_tail_q15 = bsl_static_q15,
    m1_rolling_y_tail_q15 = bsl_m1_q15,
    m2_regime_y_tail_q15 = bsl_m2_q15
  ),
  v3_breadth_suite = list(
    n_features = 74,
    individual_OOS_PRAUC_y_tail_q15 = res_5w_q15$individual,
    individual_OOS_ROC_y_tail_q15 = res_5w_q15$roc_individual,
    individual_OOS_PRAUC_y_onset = res_5w_onset$individual,
    individual_OOS_ROC_y_onset = res_5w_onset$roc_individual,
    dynamic_PRAUC_y_tail_q15 = setNames(dyn_q15$PRAUC, dyn_q15$method),
    dynamic_PRAUC_y_onset = setNames(dyn_onset$PRAUC, dyn_onset$method),
    feature_importance_y_tail_q15 = step2$y_tail_q15
  ),
  delta_vs_baseline_y_tail_q15 = list(
    delta_static_wew = round(delta_static, 4),
    delta_m1_rolling = round(delta_m1, 4),
    delta_m2_regime = round(delta_m2, 4)
  ),
  breadth_correlation_matrix_5x5 = as.list(as.data.frame(round(cor_mat, 4))),
  verdict = verdict,
  decision_rule = list(
    continue = "Δ M2 Regime ≥ +0.01",
    marginal = "0 < Δ < +0.01",
    regression = "Δ ≤ 0"
  ),
  v10_skip_note = "V10 trigger evaluation skipped per 도훈 mandate (Cycle 44 model performance only)",
  outputs = list(
    panel = file.path(DATA_DIR, "feature_panel_v3_breadth_suite.parquet"),
    v3_dir = V3_DIR,
    chart = file.path(CHART_DIR, "73_pr_curve_v3_breadth_suite.png")
  )
)

out_json <- file.path(EVAL_DIR, "5way_retrain_v3_breadth_suite.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

# Chart: 4-curve compare (baseline static / baseline M2 / v3 WEW / v3 M2)
ds_v3_static <- pr_curve(v3_dyn_q15$p_static, v3_dyn_q15$y)
ds_v3_static[, model := sprintf("v3 Static WEW (PR-AUC=%.4f)", v3_static_q15)]
ds_v3_m1 <- pr_curve(v3_dyn_q15$p_M1_rolling, v3_dyn_q15$y)
ds_v3_m1[, model := sprintf("v3 M1 Rolling (PR-AUC=%.4f)", v3_m1_q15)]
ds_v3_m2 <- pr_curve(v3_dyn_q15$p_M2_regime, v3_dyn_q15$y)
ds_v3_m2[, model := sprintf("v3 M2 Regime (PR-AUC=%.4f)", v3_m2_q15)]

if (!is.null(v2_dyn_q15)) {
  ds_v2_m2 <- pr_curve(v2_dyn_q15$p_M2_regime, v2_dyn_q15$y)
  ds_v2_m2[, model := sprintf("v2_2feat M2 Regime baseline (PR-AUC=%.4f)", bsl_m2_q15)]
  curves <- rbind(ds_v2_m2, ds_v3_static, ds_v3_m1, ds_v3_m2)
} else {
  curves <- rbind(ds_v3_static, ds_v3_m1, ds_v3_m2)
}

base_rate <- mean(v3_dyn_q15$y, na.rm = TRUE)

g <- ggplot(curves, aes(x = recall, y = precision, color = model)) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = base_rate, linetype = "dashed", color = "gray40") +
  scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
  labs(title = sprintf("5-way Dynamic Ensemble — Cycle 44 v3_breadth_suite (74) vs v2_2feat (71)  [%s]",
                       verdict),
       subtitle = sprintf("y_tail_q15 OOS  /  Δ Static %+.4f  /  Δ M1 %+.4f  /  Δ M2 %+.4f",
                          delta_static, delta_m1, delta_m2),
       x = "Recall", y = "Precision", color = NULL,
       caption = "Dashed = base rate (positive rate)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", legend.text = element_text(size = 9)) +
  guides(color = guide_legend(ncol = 2))

ggsave(file.path(CHART_DIR, "73_pr_curve_v3_breadth_suite.png"),
       plot = g, width = 11, height = 7, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "73_pr_curve_v3_breadth_suite.png")))

cat("\n========== Cycle 44 DONE ==========\n")
cat(sprintf("Verdict: %s\n", verdict))
cat(sprintf("Δ Static: %+.4f  /  Δ M1 Rolling: %+.4f  /  Δ M2 Regime: %+.4f\n",
            delta_static, delta_m1, delta_m2))
