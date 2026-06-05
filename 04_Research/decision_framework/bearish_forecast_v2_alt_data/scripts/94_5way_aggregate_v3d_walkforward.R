#==============================================================================
# 94_5way_aggregate_v3d_walkforward.R — Cycle 45D Step 4-8
#
# Steps:
#   Step 4: 5-way merge (XGB + CatBoost + RF + LSTM_walkforward + TFT_walkforward preds)
#   Step 5: Dynamic 5-method ensemble synthesis (Static WEW / M1 Rolling / M2 Regime
#           / M3 Hedge / M4 Bayes / M5 Bandit)
#   Step 6: Under-training hypothesis verdict
#           - PROVEN: ep 증가 + per-model individual PR-AUC 개선
#           - REJECTED: ep 증가했으나 individual 미개선
#           - NULL: ep 비슷
#   Step 7: Compare vs Cycle 45C (M2 0.6003) + v1.3 baseline (0.6078)
#   Step 8: Save JSON + Chart
#
# Output:
#   outputs/03_models/v3d_walkforward/predictions_5way_{target}.parquet
#   outputs/03_models/v3d_walkforward/predictions_dynamic_{target}.parquet
#   outputs/04_evaluation/5way_retrain_v3d_walkforward.json
#   outputs/06_reports/charts/94_pr_curve_v3d_walkforward.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
V3D_DIR <- file.path(WS, "outputs/03_models/v3d_walkforward")
V3C_DIR <- file.path(WS, "outputs/03_models/v3c_arch_upgrade")
BASE_DYN_DIR <- file.path(WS, "outputs/03_models/dynamic_ensemble")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(V3D_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

LOOKBACK <- 252
PURGE <- 21

# OOS window (fold 5 valid 2016-2017 제외)
OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
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

ic_spearman <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  cor(rank(p), rank(y), method = "pearson")
}

#==============================================================================
# Step 4: 5-way merge (restrict to OOS 2018-2026)
#==============================================================================
cat("\n========== Step 4: 5-way merge (XGB+Cat+RF + LSTM_wf + TFT_wf) ==========\n")

make_5way <- function(target_col) {
  cat(sprintf("\n----- 5-way merge: %s -----\n", target_col))
  gbdt <- as.data.table(read_parquet(file.path(V3D_DIR, sprintf("predictions_3way_%s.parquet", target_col))))
  gbdt[, Date := as.Date(Date)]
  lstm <- as.data.table(read_parquet(file.path(V3D_DIR, sprintf("predictions_lstm_%s.parquet", target_col))))
  lstm[, Date := as.Date(Date)]
  tft <- as.data.table(read_parquet(file.path(V3D_DIR, sprintf("predictions_tft_%s.parquet", target_col))))
  tft[, Date := as.Date(Date)]

  # Restrict to OOS window 2018-2026
  oos_gbdt <- gbdt[split == "oos" & Date >= OOS_START & Date <= OOS_END,
                    .(Date, p_xgb, p_cat, p_rf, y)]
  oos <- merge(oos_gbdt, lstm[, .(Date, p_lstm)], by = "Date", all = TRUE)
  oos <- merge(oos, tft[, .(Date, p_tft)], by = "Date", all = TRUE)
  oos <- oos[!is.na(y) & !is.na(p_xgb) & !is.na(p_lstm) & !is.na(p_tft)]
  oos <- oos[Date >= OOS_START & Date <= OOS_END]
  cat(sprintf("[merge] OOS N=%d / events=%d (%.2f%%)\n",
              nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  pr_xgb <- pr_auc(oos$p_xgb, oos$y); pr_cat <- pr_auc(oos$p_cat, oos$y)
  pr_rf <- pr_auc(oos$p_rf, oos$y); pr_lstm <- pr_auc(oos$p_lstm, oos$y); pr_tft <- pr_auc(oos$p_tft, oos$y)

  ic_xgb <- ic_spearman(oos$p_xgb, oos$y); ic_cat <- ic_spearman(oos$p_cat, oos$y)
  ic_rf <- ic_spearman(oos$p_rf, oos$y); ic_lstm <- ic_spearman(oos$p_lstm, oos$y); ic_tft <- ic_spearman(oos$p_tft, oos$y)

  cat(sprintf("[v3d individual OOS PR-AUC] XGB=%.4f / CAT=%.4f / RF=%.4f / LSTM=%.4f / TFT=%.4f\n",
              pr_xgb, pr_cat, pr_rf, pr_lstm, pr_tft))
  cat(sprintf("[v3d individual OOS IC   ] XGB=%.4f / CAT=%.4f / RF=%.4f / LSTM=%.4f / TFT=%.4f\n",
              ic_xgb, ic_cat, ic_rf, ic_lstm, ic_tft))

  oos[, p_ew5 := (p_xgb + p_cat + p_rf + p_lstm + p_tft) / 5]
  oos[, p_wew := 0.25 * p_xgb + 0.25 * p_cat + 0.25 * p_rf + 0.125 * p_lstm + 0.125 * p_tft]
  pr_ew5 <- pr_auc(oos$p_ew5, oos$y); pr_wew <- pr_auc(oos$p_wew, oos$y)
  cat(sprintf("[v3d] EW5=%.4f / WEW=%.4f\n", pr_ew5, pr_wew))

  write_parquet(oos, file.path(V3D_DIR, sprintf("predictions_5way_%s.parquet", target_col)))
  list(individual = list(xgb=pr_xgb, cat=pr_cat, rf=pr_rf, lstm=pr_lstm, tft=pr_tft),
       individual_ic = list(xgb=ic_xgb, cat=ic_cat, rf=ic_rf, lstm=ic_lstm, tft=ic_tft),
       ew5 = pr_ew5, wew = pr_wew, oos = oos)
}

res_5w_q15 <- make_5way("y_tail_q15")
res_5w_onset <- make_5way("y_onset")

#==============================================================================
# Step 5: Dynamic 5-method synthesis (M1~M5)
#==============================================================================
cat("\n========== Step 5: Dynamic 5-method ensemble synthesis ==========\n")

run_dynamic_v3d <- function(target_col, oos_in) {
  cat(sprintf("\n----- Dynamic 5-method: %s -----\n", target_col))
  p5 <- copy(oos_in); setorder(p5, Date); n_total <- nrow(p5)
  M_NAMES <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft")
  M <- as.matrix(p5[, ..M_NAMES]); Y <- p5$y

  # Static baseline (Weighted EW)
  w_static <- c(0.25, 0.25, 0.25, 0.125, 0.125)
  p_static <- as.numeric(M %*% w_static)
  pa_static <- pr_auc(p_static, Y)
  cat(sprintf("[Static WEW] PR-AUC=%.4f\n", pa_static))

  # M1: Rolling Adaptive
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
  feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_3.parquet")))
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
  write_parquet(out, file.path(V3D_DIR, sprintf("predictions_dynamic_%s.parquet", target_col)))

  data.table(
    target = target_col,
    method = c("Static_WEW", "M1_Rolling", "M2_Regime", "M3_Hedge", "M4_Bayes", "M5_Bandit"),
    PRAUC = c(pa_static, pa_M1, pa_M2, pa_M3, pa_M4, pa_M5)
  )
}

dyn_q15 <- run_dynamic_v3d("y_tail_q15", res_5w_q15$oos)
dyn_onset <- run_dynamic_v3d("y_onset", res_5w_onset$oos)

cat("\n[Step 5 Dynamic SUMMARY]\n")
print(rbind(dyn_q15, dyn_onset))

#==============================================================================
# Step 6: Under-training hypothesis verdict
#==============================================================================
cat("\n========== Step 6: Under-training hypothesis verdict ==========\n")

# Load Python per-fold + summary
py_diag_path <- file.path(EVAL_DIR, "5way_retrain_v3d_walkforward_python_diag.json")
py_diag <- if (file.exists(py_diag_path)) fromJSON(py_diag_path) else list(error = "missing python diag")

per_fold_path <- file.path(V3D_DIR, "per_fold_diagnostics.json")
per_fold <- if (file.exists(per_fold_path)) fromJSON(per_fold_path) else list(error = "missing per-fold")

# Baselines (Cycle 45C)
CYC45C_LSTM_OOS <- 0.3957
CYC45C_TFT_OOS  <- 0.3772
CYC45C_LSTM_EP  <- 13   # ep stop @ patience 8
CYC45C_TFT_EP   <- 22

v3d_lstm <- res_5w_q15$individual$lstm
v3d_tft  <- res_5w_q15$individual$tft

# Try to extract avg epoch from py_diag; fallback NA
v3d_lstm_ep <- tryCatch(py_diag$v3d_oos_y_tail_q15$lstm_avg_ep, error = function(e) NA_integer_)
v3d_tft_ep  <- tryCatch(py_diag$v3d_oos_y_tail_q15$tft_avg_ep, error = function(e) NA_integer_)
if (is.null(v3d_lstm_ep)) v3d_lstm_ep <- NA_integer_
if (is.null(v3d_tft_ep))  v3d_tft_ep <- NA_integer_

d_lstm_pr <- v3d_lstm - CYC45C_LSTM_OOS
d_tft_pr  <- v3d_tft  - CYC45C_TFT_OOS
d_lstm_ep <- ifelse(is.na(v3d_lstm_ep), NA_integer_, v3d_lstm_ep - CYC45C_LSTM_EP)
d_tft_ep  <- ifelse(is.na(v3d_tft_ep), NA_integer_, v3d_tft_ep - CYC45C_TFT_EP)

cat(sprintf("\n[Per-model individual diagnosis y_tail_q15]\n"))
cat(sprintf("  LSTM: 45C OOS=%.4f / ep=%d  →  45D OOS=%.4f / avg_ep=%s\n",
            CYC45C_LSTM_OOS, CYC45C_LSTM_EP, v3d_lstm,
            ifelse(is.na(v3d_lstm_ep), "NA", as.character(v3d_lstm_ep))))
cat(sprintf("        Δ_PR=%+.4f  /  Δ_ep=%s\n", d_lstm_pr,
            ifelse(is.na(d_lstm_ep), "NA", sprintf("%+d", d_lstm_ep))))
cat(sprintf("  TFT : 45C OOS=%.4f / ep=%d  →  45D OOS=%.4f / avg_ep=%s\n",
            CYC45C_TFT_OOS, CYC45C_TFT_EP, v3d_tft,
            ifelse(is.na(v3d_tft_ep), "NA", as.character(v3d_tft_ep))))
cat(sprintf("        Δ_PR=%+.4f  /  Δ_ep=%s\n", d_tft_pr,
            ifelse(is.na(d_tft_ep), "NA", sprintf("%+d", d_tft_ep))))

# Verdict logic:
# - PROVEN: ep 증가 (target LSTM ≥ 25, TFT ≥ 35) AND individual PR-AUC 개선 AND M2 개선
# - REJECTED: ep 증가 BUT individual 개선 X → architecture pivot
# - NULL: ep 비슷 (Δ_ep < 5)

# Use a conservative composite: average ep delta + average PR delta
avg_dep <- mean(c(d_lstm_ep, d_tft_ep), na.rm = TRUE)
avg_dpr <- mean(c(d_lstm_pr, d_tft_pr), na.rm = TRUE)
ep_target_met <- (!is.na(v3d_lstm_ep) && v3d_lstm_ep >= 25) || (!is.na(v3d_tft_ep) && v3d_tft_ep >= 35)
individual_improved <- (d_lstm_pr > 0.01) && (d_tft_pr > 0.01)

verdict_individual <- if (is.na(avg_dep) || abs(avg_dep) < 5) {
  "NULL_PATIENCE_CHANGE_INEFFECTIVE"
} else if (avg_dep >= 5 && individual_improved) {
  "HYPOTHESIS_PROVEN — Under-training was the cause"
} else if (avg_dep >= 5 && !individual_improved) {
  "HYPOTHESIS_REJECTED — Architecture is the real bottleneck (Cycle 45E PatchTST/N-BEATS/Informer)"
} else {
  "MIXED_RESULT — Re-examine training stability"
}
cat(sprintf("\n[Per-model verdict] %s\n", verdict_individual))

#==============================================================================
# Step 7: Compare vs Cycle 45C (M2 0.6003) + V1.3 baseline (0.6078)
#==============================================================================
cat("\n========== Step 7: Compare vs Cycle 45C + V1.3 baseline ==========\n")

# v1.3 baseline (load from dynamic_ensemble_summary.csv)
baseline_csv <- file.path(BASE_DYN_DIR, "dynamic_ensemble_summary.csv")
baseline_dyn <- fread(baseline_csv)

# Cycle 45C M2 = 0.6003 (hardcoded from 5way_retrain_v3c_arch_upgrade.json)
CYC45C_M2_Q15 <- 0.6003
CYC45C_STATIC_Q15 <- 0.5641
CYC45C_M1_Q15 <- 0.5919

# v1.3 baseline
bsl_q15 <- baseline_dyn[target == "y_tail_q15"]
bsl_static_q15 <- bsl_q15[method == "Static_WEW", PRAUC]
bsl_m1_q15     <- bsl_q15[method == "M1_Rolling", PRAUC]
bsl_m2_q15     <- bsl_q15[method == "M2_Regime", PRAUC]

v3d_static_q15 <- dyn_q15[method == "Static_WEW", PRAUC]
v3d_m1_q15     <- dyn_q15[method == "M1_Rolling", PRAUC]
v3d_m2_q15     <- dyn_q15[method == "M2_Regime", PRAUC]

# Δ vs 45C
delta_static_vs_45c <- v3d_static_q15 - CYC45C_STATIC_Q15
delta_m1_vs_45c     <- v3d_m1_q15 - CYC45C_M1_Q15
delta_m2_vs_45c     <- v3d_m2_q15 - CYC45C_M2_Q15

# Δ vs v1.3
delta_static_vs_v13 <- v3d_static_q15 - bsl_static_q15
delta_m1_vs_v13     <- v3d_m1_q15 - bsl_m1_q15
delta_m2_vs_v13     <- v3d_m2_q15 - bsl_m2_q15

cat(sprintf("\n[Δ vs Cycle 45C — y_tail_q15]\n"))
cat(sprintf("  Static WEW: 45C=%.4f → 45D=%.4f  (Δ %+.4f)\n",
            CYC45C_STATIC_Q15, v3d_static_q15, delta_static_vs_45c))
cat(sprintf("  M1 Rolling: 45C=%.4f → 45D=%.4f  (Δ %+.4f)\n",
            CYC45C_M1_Q15, v3d_m1_q15, delta_m1_vs_45c))
cat(sprintf("  M2 Regime:  45C=%.4f → 45D=%.4f  (Δ %+.4f) ★\n",
            CYC45C_M2_Q15, v3d_m2_q15, delta_m2_vs_45c))

cat(sprintf("\n[Δ vs V1.3 baseline — y_tail_q15]\n"))
cat(sprintf("  Static WEW: V1.3=%.4f → 45D=%.4f  (Δ %+.4f)\n",
            bsl_static_q15, v3d_static_q15, delta_static_vs_v13))
cat(sprintf("  M1 Rolling: V1.3=%.4f → 45D=%.4f  (Δ %+.4f)\n",
            bsl_m1_q15, v3d_m1_q15, delta_m1_vs_v13))
cat(sprintf("  M2 Regime:  V1.3=%.4f → 45D=%.4f  (Δ %+.4f) ★\n",
            bsl_m2_q15, v3d_m2_q15, delta_m2_vs_v13))

# Composite verdict M2
m2_verdict <- if (delta_m2_vs_45c >= 0.01) {
  "WALKFORWARD_VALIDATED — Cycle 45C M2 recovered + improved"
} else if (delta_m2_vs_45c > 0) {
  "WALKFORWARD_MARGINAL"
} else {
  "WALKFORWARD_REGRESSION — Patience relaxation did not recover M2"
}
cat(sprintf("\n[M2 Regime verdict] %s\n", m2_verdict))

#==============================================================================
# Step 8: Save JSON + Chart
#==============================================================================
cat("\n========== Step 8: Save outputs ==========\n")

# Load R-side step23 summary
step23_path <- file.path(EVAL_DIR, "5way_retrain_v3d_walkforward_step23.json")
step23 <- if (file.exists(step23_path)) fromJSON(step23_path) else list(error = "missing step23 json")

result_json <- list(
  cycle = "45D_walkforward",
  approach = "WALK_FORWARD_5_FOLD_CV_UNDER_TRAINING_TEST",
  context = list(
    cycle_45c_finding = "M2 Regime PR-AUC 0.6003 vs v1.3 baseline 0.6078 = Δ-0.0075 REGRESSION",
    cycle_45c_under_training_signal = "best_valid_pr (LSTM 0.298 / TFT 0.260) << oos_pr (0.396/0.377)",
    cycle_45c_early_stop = "LSTM ep 13 / TFT ep 22 @ patience 8 → DNN under-trained",
    hypothesis = "Validation strategy 자체 결함 (2010-2015 KR 저변동 안정기 noise) → walk-forward 5-fold CV로 검증"
  ),
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END),
                    note = "fold 5 valid 2016-2017 제외하여 leakage 방지"),
  baselines = list(
    cycle_45c = list(
      static_wew_y_tail_q15 = CYC45C_STATIC_Q15,
      m1_rolling_y_tail_q15 = CYC45C_M1_Q15,
      m2_regime_y_tail_q15 = CYC45C_M2_Q15,
      lstm_individual_y_tail_q15 = CYC45C_LSTM_OOS,
      tft_individual_y_tail_q15 = CYC45C_TFT_OOS,
      lstm_ep_stop = CYC45C_LSTM_EP,
      tft_ep_stop = CYC45C_TFT_EP
    ),
    v1_3 = list(
      static_wew_y_tail_q15 = round(bsl_static_q15, 4),
      m1_rolling_y_tail_q15 = round(bsl_m1_q15, 4),
      m2_regime_y_tail_q15 = round(bsl_m2_q15, 4)
    )
  ),
  v3d_walkforward = list(
    n_features = 69,
    training_relaxation = list(
      patience = "8 → 15",
      min_delta = "0 → 0.0005",
      max_epochs = "50 → 80"
    ),
    architecture_unchanged_from_45C = TRUE,
    gbdt_walkforward = step23,
    individual_OOS_PRAUC_y_tail_q15 = res_5w_q15$individual,
    individual_OOS_IC_y_tail_q15 = res_5w_q15$individual_ic,
    individual_OOS_PRAUC_y_onset = res_5w_onset$individual,
    individual_OOS_IC_y_onset = res_5w_onset$individual_ic,
    dnn_avg_best_epoch_y_tail_q15 = list(lstm = v3d_lstm_ep, tft = v3d_tft_ep),
    dynamic_PRAUC_y_tail_q15 = setNames(as.list(round(dyn_q15$PRAUC, 4)), dyn_q15$method),
    dynamic_PRAUC_y_onset = setNames(as.list(round(dyn_onset$PRAUC, 4)), dyn_onset$method)
  ),
  delta_vs_cycle_45c_y_tail_q15 = list(
    delta_static_wew = round(delta_static_vs_45c, 4),
    delta_m1_rolling = round(delta_m1_vs_45c, 4),
    delta_m2_regime = round(delta_m2_vs_45c, 4),
    lstm_individual_delta = round(d_lstm_pr, 4),
    tft_individual_delta = round(d_tft_pr, 4),
    lstm_ep_delta = d_lstm_ep,
    tft_ep_delta = d_tft_ep
  ),
  delta_vs_v1_3_y_tail_q15 = list(
    delta_static_wew = round(delta_static_vs_v13, 4),
    delta_m1_rolling = round(delta_m1_vs_v13, 4),
    delta_m2_regime = round(delta_m2_vs_v13, 4)
  ),
  verdict_under_training_hypothesis = verdict_individual,
  verdict_m2_regime_recovery = m2_verdict,
  decision_rules = list(
    under_training = list(
      PROVEN = "avg_ep_delta ≥ 5 AND (LSTM Δ_PR > 0.01 AND TFT Δ_PR > 0.01)",
      REJECTED = "avg_ep_delta ≥ 5 BUT individual NOT improved",
      NULL_RES = "|avg_ep_delta| < 5"
    ),
    m2_regime = list(
      VALIDATED = "Δ M2 vs 45C ≥ +0.01",
      MARGINAL = "0 < Δ M2 < +0.01",
      REGRESSION = "Δ M2 ≤ 0"
    )
  ),
  next_cycle_suggestion = if (verdict_individual == "HYPOTHESIS_PROVEN — Under-training was the cause") {
    "Cycle 47 — features + walk-forward CV 조합"
  } else if (verdict_individual == "HYPOTHESIS_REJECTED — Architecture is the real bottleneck (Cycle 45E PatchTST/N-BEATS/Informer)") {
    "Cycle 45E — Architecture pivot (PatchTST / N-BEATS / Informer)"
  } else if (startsWith(verdict_individual, "NULL")) {
    "다른 axis 통합 (stacking 45F 결과 / 46A combined multi-axis / 46B 개인+기타법인)"
  } else {
    "Re-examine training stability + selective fold re-run"
  },
  python_diagnostics_summary = py_diag,
  per_fold_diagnostics_path = per_fold_path,
  outputs = list(
    panel = file.path(DATA_DIR, "feature_panel_v1_3.parquet"),
    v3d_dir = V3D_DIR,
    chart = file.path(CHART_DIR, "94_pr_curve_v3d_walkforward.png")
  )
)

out_json <- file.path(EVAL_DIR, "5way_retrain_v3d_walkforward.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

# Chart: V1.3 baseline + Cycle 45C + v3d PR curve
v3d_dyn_q15 <- as.data.table(read_parquet(file.path(V3D_DIR, "predictions_dynamic_y_tail_q15.parquet")))
v3d_dyn_q15[, Date := as.Date(Date)]

v1_dyn_q15 <- as.data.table(read_parquet(file.path(BASE_DYN_DIR, "predictions_dynamic_y_tail_q15.parquet")))
v1_dyn_q15[, Date := as.Date(Date)]

v3c_dyn_q15_path <- file.path(V3C_DIR, "predictions_dynamic_y_tail_q15.parquet")
have_v3c <- file.exists(v3c_dyn_q15_path)
if (have_v3c) {
  v3c_dyn_q15 <- as.data.table(read_parquet(v3c_dyn_q15_path))
  v3c_dyn_q15[, Date := as.Date(Date)]
  # Restrict v3c to common OOS 2018-2026 for fair compare
  v3c_dyn_q15 <- v3c_dyn_q15[Date >= OOS_START & Date <= OOS_END]
}

# Restrict v1.3 to common OOS 2018-2026 for fair compare
v1_dyn_q15 <- v1_dyn_q15[Date >= OOS_START & Date <= OOS_END]

ds_v1_static <- pr_curve(v1_dyn_q15$p_static, v1_dyn_q15$y)
ds_v1_static[, model := sprintf("V1.3 Static (PR-AUC=%.4f)", pr_auc(v1_dyn_q15$p_static, v1_dyn_q15$y))]
ds_v1_m2 <- pr_curve(v1_dyn_q15$p_M2_regime, v1_dyn_q15$y)
ds_v1_m2[, model := sprintf("V1.3 M2 Regime (PR-AUC=%.4f)", pr_auc(v1_dyn_q15$p_M2_regime, v1_dyn_q15$y))]

curves <- rbind(ds_v1_static, ds_v1_m2)

if (have_v3c && nrow(v3c_dyn_q15) > 0) {
  ds_v3c_m2 <- pr_curve(v3c_dyn_q15$p_M2_regime, v3c_dyn_q15$y)
  ds_v3c_m2[, model := sprintf("45C M2 Regime (PR-AUC=%.4f)", pr_auc(v3c_dyn_q15$p_M2_regime, v3c_dyn_q15$y))]
  curves <- rbind(curves, ds_v3c_m2)
}

ds_v3d_static <- pr_curve(v3d_dyn_q15$p_static, v3d_dyn_q15$y)
ds_v3d_static[, model := sprintf("45D Static (PR-AUC=%.4f)", v3d_static_q15)]
ds_v3d_m2 <- pr_curve(v3d_dyn_q15$p_M2_regime, v3d_dyn_q15$y)
ds_v3d_m2[, model := sprintf("45D M2 Regime (PR-AUC=%.4f)", v3d_m2_q15)]
curves <- rbind(curves, ds_v3d_static, ds_v3d_m2)

base_rate <- mean(v3d_dyn_q15$y, na.rm = TRUE)

g <- ggplot(curves, aes(x = recall, y = precision, color = model)) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = base_rate, linetype = "dashed", color = "gray40") +
  scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
  labs(title = sprintf("Cycle 45D Walk-forward CV — under-training test  [%s]",
                       verdict_individual),
       subtitle = sprintf("y_tail_q15 OOS 2018-2026 / Δ M2 vs 45C %+.4f / vs V1.3 %+.4f / LSTM avg_ep=%s / TFT avg_ep=%s",
                          delta_m2_vs_45c, delta_m2_vs_v13,
                          ifelse(is.na(v3d_lstm_ep), "NA", as.character(v3d_lstm_ep)),
                          ifelse(is.na(v3d_tft_ep), "NA", as.character(v3d_tft_ep))),
       x = "Recall", y = "Precision", color = NULL,
       caption = "Dashed = base rate (positive rate). OOS restricted to 2018-2026 for fair compare across V1.3/45C/45D.") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", legend.text = element_text(size = 9)) +
  guides(color = guide_legend(ncol = 2))

ggsave(file.path(CHART_DIR, "94_pr_curve_v3d_walkforward.png"),
       plot = g, width = 11, height = 7, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "94_pr_curve_v3d_walkforward.png")))

cat("\n========== Cycle 45D DONE ==========\n")
cat(sprintf("Under-training hypothesis: %s\n", verdict_individual))
cat(sprintf("M2 Regime recovery: %s\n", m2_verdict))
cat(sprintf("Δ vs 45C — Static %+.4f / M1 %+.4f / M2 %+.4f\n",
            delta_static_vs_45c, delta_m1_vs_45c, delta_m2_vs_45c))
cat(sprintf("Δ vs V1.3 — Static %+.4f / M1 %+.4f / M2 %+.4f\n",
            delta_static_vs_v13, delta_m1_vs_v13, delta_m2_vs_v13))
cat(sprintf("LSTM: %.4f (Δ %+.4f, avg_ep=%s, Δ_ep=%s)  /  TFT: %.4f (Δ %+.4f, avg_ep=%s, Δ_ep=%s)\n",
            v3d_lstm, d_lstm_pr,
            ifelse(is.na(v3d_lstm_ep), "NA", as.character(v3d_lstm_ep)),
            ifelse(is.na(d_lstm_ep), "NA", sprintf("%+d", d_lstm_ep)),
            v3d_tft, d_tft_pr,
            ifelse(is.na(v3d_tft_ep), "NA", as.character(v3d_tft_ep)),
            ifelse(is.na(d_tft_ep), "NA", sprintf("%+d", d_tft_ep))))
