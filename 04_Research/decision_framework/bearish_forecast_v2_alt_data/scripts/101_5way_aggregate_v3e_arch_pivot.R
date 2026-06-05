#==============================================================================
# 101_5way_aggregate_v3e_arch_pivot.R — Cycle 45E Step 4-8
#
# Steps:
#   Step 4: 5-way merge (XGB + CatBoost + RF + PatchTST + N-BEATS preds)
#   Step 5: Dynamic 5-method ensemble synthesis (Static WEW / M1~M5)
#   Step 6: Architecture pivot verdict
#           - PIVOT_PROVEN: PatchTST + N-BEATS individual 둘 다 개선 + M2/M3 dynamic 개선
#           - PIVOT_PARTIAL: 한 architecture만 개선
#           - PIVOT_FAIL: 둘 다 regression
#   Step 7: Compare vs Cycle 45D (M2 0.5917 / M3 0.6019 / LSTM 0.3253 / TFT 0.4508)
#           + v1.3 baseline (M2 0.6078)
#   Step 8: Save JSON + Chart
#
# Output:
#   outputs/03_models/v3e_arch_pivot/predictions_5way_{target}.parquet
#   outputs/03_models/v3e_arch_pivot/predictions_dynamic_{target}.parquet
#   outputs/04_evaluation/5way_retrain_v3e_arch_pivot.json
#   outputs/06_reports/charts/101_pr_curve_v3e_arch_pivot.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
V3E_DIR <- file.path(WS, "outputs/03_models/v3e_arch_pivot")
V3D_DIR <- file.path(WS, "outputs/03_models/v3d_walkforward")
BASE_DYN_DIR <- file.path(WS, "outputs/03_models/dynamic_ensemble")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(V3E_DIR, recursive = TRUE, showWarnings = FALSE)
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
# Step 4: 5-way merge
#   Reuses GBDT predictions from Cycle 45D (predictions_3way_*.parquet) since
#   walk-forward CV + v1.3 baseline GBDT identical to 45D (architecture only pivoted).
#==============================================================================
cat("\n========== Step 4: 5-way merge (XGB+Cat+RF + PatchTST + N-BEATS) ==========\n")
cat("[Reuse] GBDT preds = Cycle 45D outputs (walk-forward + v1.3 baseline 동일)\n")

make_5way <- function(target_col) {
  cat(sprintf("\n----- 5-way merge: %s -----\n", target_col))
  gbdt <- as.data.table(read_parquet(file.path(V3D_DIR, sprintf("predictions_3way_%s.parquet", target_col))))
  gbdt[, Date := as.Date(Date)]
  pt <- as.data.table(read_parquet(file.path(V3E_DIR, sprintf("predictions_patchtst_%s.parquet", target_col))))
  pt[, Date := as.Date(Date)]
  nb <- as.data.table(read_parquet(file.path(V3E_DIR, sprintf("predictions_nbeats_%s.parquet", target_col))))
  nb[, Date := as.Date(Date)]

  # Restrict to OOS window 2018-2026
  oos_gbdt <- gbdt[split == "oos" & Date >= OOS_START & Date <= OOS_END,
                    .(Date, p_xgb, p_cat, p_rf, y)]
  oos <- merge(oos_gbdt, pt[, .(Date, p_patchtst)], by = "Date", all = TRUE)
  oos <- merge(oos, nb[, .(Date, p_nbeats)], by = "Date", all = TRUE)
  oos <- oos[!is.na(y) & !is.na(p_xgb) & !is.na(p_patchtst) & !is.na(p_nbeats)]
  oos <- oos[Date >= OOS_START & Date <= OOS_END]
  cat(sprintf("[merge] OOS N=%d / events=%d (%.2f%%)\n",
              nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  pr_xgb <- pr_auc(oos$p_xgb, oos$y); pr_cat <- pr_auc(oos$p_cat, oos$y)
  pr_rf <- pr_auc(oos$p_rf, oos$y)
  pr_pt <- pr_auc(oos$p_patchtst, oos$y); pr_nb <- pr_auc(oos$p_nbeats, oos$y)

  ic_xgb <- ic_spearman(oos$p_xgb, oos$y); ic_cat <- ic_spearman(oos$p_cat, oos$y)
  ic_rf <- ic_spearman(oos$p_rf, oos$y)
  ic_pt <- ic_spearman(oos$p_patchtst, oos$y); ic_nb <- ic_spearman(oos$p_nbeats, oos$y)

  cat(sprintf("[v3e individual OOS PR-AUC] XGB=%.4f / CAT=%.4f / RF=%.4f / PatchTST=%.4f / N-BEATS=%.4f\n",
              pr_xgb, pr_cat, pr_rf, pr_pt, pr_nb))
  cat(sprintf("[v3e individual OOS IC   ] XGB=%.4f / CAT=%.4f / RF=%.4f / PatchTST=%.4f / N-BEATS=%.4f\n",
              ic_xgb, ic_cat, ic_rf, ic_pt, ic_nb))

  oos[, p_ew5 := (p_xgb + p_cat + p_rf + p_patchtst + p_nbeats) / 5]
  oos[, p_wew := 0.25 * p_xgb + 0.25 * p_cat + 0.25 * p_rf + 0.125 * p_patchtst + 0.125 * p_nbeats]
  pr_ew5 <- pr_auc(oos$p_ew5, oos$y); pr_wew <- pr_auc(oos$p_wew, oos$y)
  cat(sprintf("[v3e] EW5=%.4f / WEW=%.4f\n", pr_ew5, pr_wew))

  # Rename for downstream M-method matrices to mirror 45D column naming convention
  setnames(oos, c("p_patchtst", "p_nbeats"), c("p_lstm", "p_tft"))

  write_parquet(oos, file.path(V3E_DIR, sprintf("predictions_5way_%s.parquet", target_col)))
  list(individual = list(xgb=pr_xgb, cat=pr_cat, rf=pr_rf, patchtst=pr_pt, nbeats=pr_nb),
       individual_ic = list(xgb=ic_xgb, cat=ic_cat, rf=ic_rf, patchtst=ic_pt, nbeats=ic_nb),
       ew5 = pr_ew5, wew = pr_wew, oos = oos)
}

res_5w_q15 <- make_5way("y_tail_q15")
res_5w_onset <- make_5way("y_onset")

#==============================================================================
# Step 5: Dynamic 5-method synthesis (M1~M5)
#   Same algorithms as 45D; column names p_xgb / p_cat / p_rf / p_lstm (=PatchTST)
#   / p_tft (=N-BEATS) so M-method math is unchanged.
#==============================================================================
cat("\n========== Step 5: Dynamic 5-method ensemble synthesis ==========\n")

run_dynamic_v3e <- function(target_col, oos_in) {
  cat(sprintf("\n----- Dynamic 5-method: %s -----\n", target_col))
  p5 <- copy(oos_in); setorder(p5, Date); n_total <- nrow(p5)
  M_NAMES <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft")
  M <- as.matrix(p5[, ..M_NAMES]); Y <- p5$y

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
  cat(sprintf("[M1 Rolling]  PR-AUC=%.4f %s\n", pa_M1, ifelse(pa_M1 > pa_static, "*", "")))

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
  cat(sprintf("[M2 Regime]   PR-AUC=%.4f %s\n", pa_M2, ifelse(pa_M2 > pa_static, "*", "")))

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
  cat(sprintf("[M3 Hedge]    PR-AUC=%.4f %s\n", pa_M3, ifelse(pa_M3 > pa_static, "*", "")))

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
  cat(sprintf("[M4 Bayes]    PR-AUC=%.4f %s\n", pa_M4, ifelse(pa_M4 > pa_static, "*", "")))

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
  cat(sprintf("[M5 Bandit]   PR-AUC=%.4f %s\n", pa_M5, ifelse(pa_M5 > pa_static, "*", "")))

  out <- p5_r[, .(Date, y, regime,
                  p_static = p_static,
                  p_M1_rolling = p_M1,
                  p_M2_regime = p_M2,
                  p_M3_hedge = p_M3,
                  p_M4_bayes = p_M4,
                  p_M5_bandit = p_M5)]
  write_parquet(out, file.path(V3E_DIR, sprintf("predictions_dynamic_%s.parquet", target_col)))

  data.table(
    target = target_col,
    method = c("Static_WEW", "M1_Rolling", "M2_Regime", "M3_Hedge", "M4_Bayes", "M5_Bandit"),
    PRAUC = c(pa_static, pa_M1, pa_M2, pa_M3, pa_M4, pa_M5)
  )
}

dyn_q15 <- run_dynamic_v3e("y_tail_q15", res_5w_q15$oos)
dyn_onset <- run_dynamic_v3e("y_onset", res_5w_onset$oos)

cat("\n[Step 5 Dynamic SUMMARY]\n")
print(rbind(dyn_q15, dyn_onset))

#==============================================================================
# Step 6: Architecture pivot verdict
#==============================================================================
cat("\n========== Step 6: Architecture pivot verdict ==========\n")

py_diag_path <- file.path(EVAL_DIR, "5way_retrain_v3e_arch_pivot_python_diag.json")
py_diag <- if (file.exists(py_diag_path)) fromJSON(py_diag_path) else list(error = "missing python diag")

per_fold_path <- file.path(V3E_DIR, "per_fold_diagnostics.json")
per_fold <- if (file.exists(per_fold_path)) fromJSON(per_fold_path) else list(error = "missing per-fold")

# Baselines (Cycle 45D)
CYC45D_LSTM_OOS <- 0.3253
CYC45D_TFT_OOS  <- 0.4508
CYC45D_M2_Q15   <- 0.5917
CYC45D_M3_Q15   <- 0.6019
CYC45D_STATIC_Q15 <- 0.5875
CYC45D_M1_Q15   <- 0.5896

v3e_pt <- res_5w_q15$individual$patchtst
v3e_nb <- res_5w_q15$individual$nbeats

v3e_pt_ep <- tryCatch(py_diag$v3e_oos_y_tail_q15$patchtst_avg_ep, error = function(e) NA_integer_)
v3e_nb_ep <- tryCatch(py_diag$v3e_oos_y_tail_q15$nbeats_avg_ep, error = function(e) NA_integer_)
if (is.null(v3e_pt_ep)) v3e_pt_ep <- NA_integer_
if (is.null(v3e_nb_ep)) v3e_nb_ep <- NA_integer_

d_pt_pr <- v3e_pt - CYC45D_LSTM_OOS
d_nb_pr <- v3e_nb - CYC45D_TFT_OOS

cat(sprintf("\n[Per-model individual diagnosis y_tail_q15]\n"))
cat(sprintf("  PatchTST vs LSTM (45D): 0.3253 / ep=5  →  %.4f / avg_ep=%s\n",
            v3e_pt, ifelse(is.na(v3e_pt_ep), "NA", as.character(v3e_pt_ep))))
cat(sprintf("        Δ_PR=%+.4f\n", d_pt_pr))
cat(sprintf("  N-BEATS  vs TFT  (45D): 0.4508 / ep=10 →  %.4f / avg_ep=%s\n",
            v3e_nb, ifelse(is.na(v3e_nb_ep), "NA", as.character(v3e_nb_ep))))
cat(sprintf("        Δ_PR=%+.4f\n", d_nb_pr))

# Dynamic ensemble verdict
v3e_static_q15 <- dyn_q15[method == "Static_WEW", PRAUC]
v3e_m1_q15     <- dyn_q15[method == "M1_Rolling", PRAUC]
v3e_m2_q15     <- dyn_q15[method == "M2_Regime", PRAUC]
v3e_m3_q15     <- dyn_q15[method == "M3_Hedge", PRAUC]

delta_static_vs_45d <- v3e_static_q15 - CYC45D_STATIC_Q15
delta_m1_vs_45d     <- v3e_m1_q15 - CYC45D_M1_Q15
delta_m2_vs_45d     <- v3e_m2_q15 - CYC45D_M2_Q15
delta_m3_vs_45d     <- v3e_m3_q15 - CYC45D_M3_Q15

# Composite Pivot verdict (decision rule)
# PROVEN: both architectures improved (Δ_PR > 0.01) AND (M2 or M3) improved (Δ > 0.005)
# PARTIAL: one architecture improved
# FAIL: both regressed or no dynamic improvement
pt_individual_improved <- d_pt_pr > 0.01
nb_individual_improved <- d_nb_pr > 0.01
dynamic_improved <- (delta_m2_vs_45d > 0.005) || (delta_m3_vs_45d > 0.005)
both_individual_improved <- pt_individual_improved && nb_individual_improved

pivot_verdict <- if (both_individual_improved && dynamic_improved) {
  "PIVOT_PROVEN — PatchTST + N-BEATS individual 둘 다 개선 + dynamic 개선"
} else if (both_individual_improved && !dynamic_improved) {
  "PIVOT_INDIVIDUAL_ONLY — Individual 개선 but dynamic 미개선 (ensemble correlation 의심)"
} else if (pt_individual_improved || nb_individual_improved) {
  "PIVOT_PARTIAL — 한 architecture만 개선, 다른 axis 추가 교체 필요 (Informer/FEDformer)"
} else {
  "PIVOT_FAIL — 둘 다 regression. Time-series-native도 한계 (architecture 자체보다 signal saturation)"
}
cat(sprintf("\n[Pivot verdict] %s\n", pivot_verdict))

#==============================================================================
# Step 7: Compare vs Cycle 45D + v1.3 baseline
#==============================================================================
cat("\n========== Step 7: Compare vs Cycle 45D + V1.3 baseline ==========\n")

# v1.3 baseline (load from dynamic_ensemble_summary.csv)
baseline_csv <- file.path(BASE_DYN_DIR, "dynamic_ensemble_summary.csv")
baseline_dyn <- fread(baseline_csv)
bsl_q15 <- baseline_dyn[target == "y_tail_q15"]
bsl_static_q15 <- bsl_q15[method == "Static_WEW", PRAUC]
bsl_m1_q15     <- bsl_q15[method == "M1_Rolling", PRAUC]
bsl_m2_q15     <- bsl_q15[method == "M2_Regime", PRAUC]

# Δ vs v1.3
delta_static_vs_v13 <- v3e_static_q15 - bsl_static_q15
delta_m1_vs_v13     <- v3e_m1_q15 - bsl_m1_q15
delta_m2_vs_v13     <- v3e_m2_q15 - bsl_m2_q15

cat(sprintf("\n[Δ vs Cycle 45D — y_tail_q15]\n"))
cat(sprintf("  Static WEW: 45D=%.4f → 45E=%.4f  (Δ %+.4f)\n",
            CYC45D_STATIC_Q15, v3e_static_q15, delta_static_vs_45d))
cat(sprintf("  M1 Rolling: 45D=%.4f → 45E=%.4f  (Δ %+.4f)\n",
            CYC45D_M1_Q15, v3e_m1_q15, delta_m1_vs_45d))
cat(sprintf("  M2 Regime:  45D=%.4f → 45E=%.4f  (Δ %+.4f) *\n",
            CYC45D_M2_Q15, v3e_m2_q15, delta_m2_vs_45d))
cat(sprintf("  M3 Hedge:   45D=%.4f → 45E=%.4f  (Δ %+.4f) *\n",
            CYC45D_M3_Q15, v3e_m3_q15, delta_m3_vs_45d))

cat(sprintf("\n[Δ vs V1.3 baseline — y_tail_q15]\n"))
cat(sprintf("  Static WEW: V1.3=%.4f → 45E=%.4f  (Δ %+.4f)\n",
            bsl_static_q15, v3e_static_q15, delta_static_vs_v13))
cat(sprintf("  M1 Rolling: V1.3=%.4f → 45E=%.4f  (Δ %+.4f)\n",
            bsl_m1_q15, v3e_m1_q15, delta_m1_vs_v13))
cat(sprintf("  M2 Regime:  V1.3=%.4f → 45E=%.4f  (Δ %+.4f) *\n",
            bsl_m2_q15, v3e_m2_q15, delta_m2_vs_v13))

# Composite verdict M2 vs v1.3
m2_verdict <- if (v3e_m2_q15 >= 0.62) {
  "BEST_TIER_M2 — target ≥ 0.62 (v1.3 0.6078 능가)"
} else if (delta_m2_vs_v13 >= 0.005) {
  "ABOVE_V13 — M2 improvement +0.005 vs v1.3"
} else if (delta_m2_vs_v13 > 0) {
  "MARGINAL_ABOVE_V13"
} else {
  "BELOW_V13 — v1.3 baseline 미달"
}
cat(sprintf("\n[M2 vs v1.3 verdict] %s\n", m2_verdict))

#==============================================================================
# Step 8: Save JSON + Chart
#==============================================================================
cat("\n========== Step 8: Save outputs ==========\n")

# Load R-side step23 summary (45D GBDT, reused)
step23_path <- file.path(EVAL_DIR, "5way_retrain_v3d_walkforward_step23.json")
step23 <- if (file.exists(step23_path)) fromJSON(step23_path) else list(error = "missing step23 json")

result_json <- list(
  cycle = "45E_arch_pivot",
  approach = "TIME_SERIES_NATIVE_ARCHITECTURE_PIVOT",
  context = list(
    cycle_45d_finding = "MIXED_RESULT — LSTM REGRESSED (-0.0704) / TFT IMPROVED (+0.0736)",
    cycle_45d_avg_ep = "LSTM avg_ep=5 / TFT avg_ep=10 (patience 15 늘려도 빠른 stop)",
    cycle_45d_hypothesis = "Architecture 자체 부적합 — general-purpose LSTM/TFT not time-series-native",
    pivot_rationale = list(
      lstm_to_patchtst = "Recurrent inductive bias → patch-wise attention (Nie 2023). Channel-independence + 작은 데이터 효율",
      tft_to_nbeats = "Sequence transformer → deep FC residual stack (Oreshkin 2019). No recurrence, no attention. Time-series basis"
    )
  ),
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END),
                    note = "fold 5 valid 2016-2017 제외하여 leakage 방지"),
  baselines = list(
    cycle_45d = list(
      static_wew_y_tail_q15 = CYC45D_STATIC_Q15,
      m1_rolling_y_tail_q15 = CYC45D_M1_Q15,
      m2_regime_y_tail_q15 = CYC45D_M2_Q15,
      m3_hedge_y_tail_q15 = CYC45D_M3_Q15,
      lstm_individual_y_tail_q15 = CYC45D_LSTM_OOS,
      tft_individual_y_tail_q15 = CYC45D_TFT_OOS,
      lstm_avg_ep = 5L,
      tft_avg_ep = 10L
    ),
    v1_3 = list(
      static_wew_y_tail_q15 = round(bsl_static_q15, 4),
      m1_rolling_y_tail_q15 = round(bsl_m1_q15, 4),
      m2_regime_y_tail_q15 = round(bsl_m2_q15, 4)
    )
  ),
  v3e_arch_pivot = list(
    n_features = 69,
    architecture_pivot = list(
      lstm_to = "PatchTST (channel-independent patch transformer)",
      tft_to = "N-BEATS Generic (deep FC residual stack)"
    ),
    gbdt_reused_from_45D = TRUE,
    individual_OOS_PRAUC_y_tail_q15 = res_5w_q15$individual,
    individual_OOS_IC_y_tail_q15 = res_5w_q15$individual_ic,
    individual_OOS_PRAUC_y_onset = res_5w_onset$individual,
    individual_OOS_IC_y_onset = res_5w_onset$individual_ic,
    dnn_avg_best_epoch_y_tail_q15 = list(patchtst = v3e_pt_ep, nbeats = v3e_nb_ep),
    dynamic_PRAUC_y_tail_q15 = setNames(as.list(round(dyn_q15$PRAUC, 4)), dyn_q15$method),
    dynamic_PRAUC_y_onset = setNames(as.list(round(dyn_onset$PRAUC, 4)), dyn_onset$method),
    ew5_y_tail_q15 = round(res_5w_q15$ew5, 4),
    wew_y_tail_q15 = round(res_5w_q15$wew, 4)
  ),
  delta_vs_cycle_45d_y_tail_q15 = list(
    delta_static_wew = round(delta_static_vs_45d, 4),
    delta_m1_rolling = round(delta_m1_vs_45d, 4),
    delta_m2_regime = round(delta_m2_vs_45d, 4),
    delta_m3_hedge = round(delta_m3_vs_45d, 4),
    patchtst_vs_lstm_pr = round(d_pt_pr, 4),
    nbeats_vs_tft_pr = round(d_nb_pr, 4)
  ),
  delta_vs_v1_3_y_tail_q15 = list(
    delta_static_wew = round(delta_static_vs_v13, 4),
    delta_m1_rolling = round(delta_m1_vs_v13, 4),
    delta_m2_regime = round(delta_m2_vs_v13, 4)
  ),
  verdict_pivot = pivot_verdict,
  verdict_m2_vs_v13 = m2_verdict,
  decision_rules = list(
    pivot = list(
      PROVEN = "PatchTST Δ_PR > 0.01 AND N-BEATS Δ_PR > 0.01 AND (M2 OR M3) Δ > 0.005",
      INDIVIDUAL_ONLY = "Both individual improved BUT dynamic not improved",
      PARTIAL = "One architecture improved",
      FAIL = "Both regressed"
    ),
    m2_vs_v13 = list(
      BEST_TIER = "M2 ≥ 0.62",
      ABOVE = "Δ M2 vs v1.3 ≥ +0.005",
      MARGINAL = "0 < Δ M2 < +0.005",
      BELOW = "Δ M2 ≤ 0"
    )
  ),
  next_cycle_suggestion = if (grepl("PROVEN", pivot_verdict)) {
    "Cycle 48 — PatchTST/N-BEATS + 47B US macro features 통합 (architecture+features dual axis)"
  } else if (grepl("PARTIAL", pivot_verdict)) {
    "Cycle 45F — 약한 architecture 추가 교체 (Informer / FEDformer / TimeMixer)"
  } else if (grepl("INDIVIDUAL_ONLY", pivot_verdict)) {
    "Cycle 46 — Ensemble correlation analysis + stacking meta with new DNNs"
  } else {
    "Cycle 49 — GBDT-only ensemble 우선, signal saturation 인정 + new feature axis 모색"
  },
  python_diagnostics_summary = py_diag,
  gbdt_summary = step23,
  per_fold_diagnostics_path = per_fold_path,
  outputs = list(
    panel = file.path(DATA_DIR, "feature_panel_v1_3.parquet"),
    v3e_dir = V3E_DIR,
    chart = file.path(CHART_DIR, "101_pr_curve_v3e_arch_pivot.png")
  )
)

out_json <- file.path(EVAL_DIR, "5way_retrain_v3e_arch_pivot.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

# Chart: V1.3 baseline + Cycle 45D + v3e PR curve
v3e_dyn_q15 <- as.data.table(read_parquet(file.path(V3E_DIR, "predictions_dynamic_y_tail_q15.parquet")))
v3e_dyn_q15[, Date := as.Date(Date)]

v1_dyn_q15 <- as.data.table(read_parquet(file.path(BASE_DYN_DIR, "predictions_dynamic_y_tail_q15.parquet")))
v1_dyn_q15[, Date := as.Date(Date)]

v3d_dyn_q15_path <- file.path(V3D_DIR, "predictions_dynamic_y_tail_q15.parquet")
have_v3d <- file.exists(v3d_dyn_q15_path)
if (have_v3d) {
  v3d_dyn_q15 <- as.data.table(read_parquet(v3d_dyn_q15_path))
  v3d_dyn_q15[, Date := as.Date(Date)]
  v3d_dyn_q15 <- v3d_dyn_q15[Date >= OOS_START & Date <= OOS_END]
}

v1_dyn_q15 <- v1_dyn_q15[Date >= OOS_START & Date <= OOS_END]

ds_v1_static <- pr_curve(v1_dyn_q15$p_static, v1_dyn_q15$y)
ds_v1_static[, model := sprintf("V1.3 Static (PR-AUC=%.4f)", pr_auc(v1_dyn_q15$p_static, v1_dyn_q15$y))]
ds_v1_m2 <- pr_curve(v1_dyn_q15$p_M2_regime, v1_dyn_q15$y)
ds_v1_m2[, model := sprintf("V1.3 M2 Regime (PR-AUC=%.4f)", pr_auc(v1_dyn_q15$p_M2_regime, v1_dyn_q15$y))]

curves <- rbind(ds_v1_static, ds_v1_m2)

if (have_v3d && nrow(v3d_dyn_q15) > 0) {
  ds_v3d_m2 <- pr_curve(v3d_dyn_q15$p_M2_regime, v3d_dyn_q15$y)
  ds_v3d_m2[, model := sprintf("45D M2 Regime (PR-AUC=%.4f)", pr_auc(v3d_dyn_q15$p_M2_regime, v3d_dyn_q15$y))]
  curves <- rbind(curves, ds_v3d_m2)

  ds_v3d_m3 <- pr_curve(v3d_dyn_q15$p_M3_hedge, v3d_dyn_q15$y)
  ds_v3d_m3[, model := sprintf("45D M3 Hedge (PR-AUC=%.4f)", pr_auc(v3d_dyn_q15$p_M3_hedge, v3d_dyn_q15$y))]
  curves <- rbind(curves, ds_v3d_m3)
}

ds_v3e_static <- pr_curve(v3e_dyn_q15$p_static, v3e_dyn_q15$y)
ds_v3e_static[, model := sprintf("45E Static (PR-AUC=%.4f)", v3e_static_q15)]
ds_v3e_m2 <- pr_curve(v3e_dyn_q15$p_M2_regime, v3e_dyn_q15$y)
ds_v3e_m2[, model := sprintf("45E M2 Regime (PR-AUC=%.4f)", v3e_m2_q15)]
ds_v3e_m3 <- pr_curve(v3e_dyn_q15$p_M3_hedge, v3e_dyn_q15$y)
ds_v3e_m3[, model := sprintf("45E M3 Hedge (PR-AUC=%.4f)", v3e_m3_q15)]
curves <- rbind(curves, ds_v3e_static, ds_v3e_m2, ds_v3e_m3)

base_rate <- mean(v3e_dyn_q15$y, na.rm = TRUE)

g <- ggplot(curves, aes(x = recall, y = precision, color = model)) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = base_rate, linetype = "dashed", color = "gray40") +
  scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
  labs(title = sprintf("Cycle 45E Architecture Pivot — PatchTST + N-BEATS  [%s]",
                       substr(pivot_verdict, 1, 50)),
       subtitle = sprintf("y_tail_q15 OOS 2018-2026 / Δ M2 vs 45D %+.4f / vs V1.3 %+.4f / PatchTST avg_ep=%s / NBEATS avg_ep=%s",
                          delta_m2_vs_45d, delta_m2_vs_v13,
                          ifelse(is.na(v3e_pt_ep), "NA", as.character(v3e_pt_ep)),
                          ifelse(is.na(v3e_nb_ep), "NA", as.character(v3e_nb_ep))),
       x = "Recall", y = "Precision", color = NULL,
       caption = "Dashed = base rate. OOS restricted to 2018-2026 for fair compare across V1.3/45D/45E.") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", legend.text = element_text(size = 9)) +
  guides(color = guide_legend(ncol = 2))

ggsave(file.path(CHART_DIR, "101_pr_curve_v3e_arch_pivot.png"),
       plot = g, width = 11, height = 7, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "101_pr_curve_v3e_arch_pivot.png")))

cat("\n========== Cycle 45E DONE ==========\n")
cat(sprintf("Architecture pivot verdict: %s\n", pivot_verdict))
cat(sprintf("M2 vs V1.3 verdict: %s\n", m2_verdict))
cat(sprintf("Δ vs 45D — Static %+.4f / M1 %+.4f / M2 %+.4f / M3 %+.4f\n",
            delta_static_vs_45d, delta_m1_vs_45d, delta_m2_vs_45d, delta_m3_vs_45d))
cat(sprintf("Δ vs V1.3 — Static %+.4f / M1 %+.4f / M2 %+.4f\n",
            delta_static_vs_v13, delta_m1_vs_v13, delta_m2_vs_v13))
cat(sprintf("PatchTST: %.4f (Δ vs LSTM %+.4f, avg_ep=%s)  /  N-BEATS: %.4f (Δ vs TFT %+.4f, avg_ep=%s)\n",
            v3e_pt, d_pt_pr, ifelse(is.na(v3e_pt_ep), "NA", as.character(v3e_pt_ep)),
            v3e_nb, d_nb_pr, ifelse(is.na(v3e_nb_ep), "NA", as.character(v3e_nb_ep))))
