#==============================================================================
# 122_5way_aggregate_v4a_combined.R — Cycle 52 Path A Step 4
#
# Steps:
#   Step 4: 5-way merge (XGB + CatBoost + RF + PatchTST + N-BEATS_mean)
#   Step 5: Dynamic 5-method ensemble (Static WEW / M1~M5)
#   Step 6: Verdict (STANDARD_HIT / FLOOR_HIT / REGRESSION) per NEW_CYCLE_CHECKLIST
#   Step 7: Compare vs Cycle 50 forward baselines + Cycle 43 forward + Cycle 45E forward
#   Step 8: Chart + final JSON
#
# Output:
#   outputs/03_models/v4a_combined/predictions_5way_y_{tail_q15|onset}.parquet
#   outputs/03_models/v4a_combined/predictions_dynamic_y_{tail_q15|onset}.parquet
#   outputs/04_evaluation/5way_retrain_v4a_combined.json
#   outputs/06_reports/charts/122_pr_curve_v4a_combined.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
V4A_DIR <- file.path(WS, "outputs/03_models/v4a_combined")
V13_FWD_DIR <- file.path(WS, "outputs/03_models/v1_3_forward")
V22F_FWD_DIR <- file.path(WS, "outputs/03_models/v2_2feat_forward")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(V4A_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

LOOKBACK <- 252
PURGE <- 21

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
#==============================================================================
cat("\n========== Step 4: 5-way merge (XGB+Cat+RF+PatchTST+N-BEATS_mean) ==========\n")

make_5way <- function(target_col) {
  cat(sprintf("\n----- 5-way merge: %s -----\n", target_col))
  gbdt <- as.data.table(read_parquet(
    file.path(V4A_DIR, sprintf("predictions_3way_%s.parquet", target_col))))
  gbdt[, Date := as.Date(Date)]
  pt <- as.data.table(read_parquet(
    file.path(V4A_DIR, sprintf("predictions_patchtst_%s.parquet", target_col))))
  pt[, Date := as.Date(Date)]
  nb_mean <- as.data.table(read_parquet(
    file.path(V4A_DIR, sprintf("predictions_nbeats_mean_%s.parquet", target_col))))
  nb_mean[, Date := as.Date(Date)]

  # Restrict to OOS window 2018-2026
  oos_gbdt <- gbdt[split == "oos" & Date >= OOS_START & Date <= OOS_END,
                    .(Date, p_xgb, p_cat, p_rf, y)]
  oos <- merge(oos_gbdt, pt[, .(Date, p_patchtst)], by = "Date", all = TRUE)
  oos <- merge(oos, nb_mean[, .(Date, p_nbeats_mean)], by = "Date", all = TRUE)
  oos <- oos[!is.na(y) & !is.na(p_xgb) & !is.na(p_patchtst) & !is.na(p_nbeats_mean)]
  oos <- oos[Date >= OOS_START & Date <= OOS_END]
  cat(sprintf("[merge] OOS N=%d / events=%d (%.2f%%)\n",
              nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  pr_xgb <- pr_auc(oos$p_xgb, oos$y); pr_cat <- pr_auc(oos$p_cat, oos$y)
  pr_rf <- pr_auc(oos$p_rf, oos$y)
  pr_pt <- pr_auc(oos$p_patchtst, oos$y); pr_nb <- pr_auc(oos$p_nbeats_mean, oos$y)

  ic_xgb <- ic_spearman(oos$p_xgb, oos$y); ic_cat <- ic_spearman(oos$p_cat, oos$y)
  ic_rf <- ic_spearman(oos$p_rf, oos$y)
  ic_pt <- ic_spearman(oos$p_patchtst, oos$y); ic_nb <- ic_spearman(oos$p_nbeats_mean, oos$y)

  cat(sprintf("[v4a individual OOS PR-AUC] XGB=%.4f / CAT=%.4f / RF=%.4f / PatchTST=%.4f / N-BEATS_mean=%.4f\n",
              pr_xgb, pr_cat, pr_rf, pr_pt, pr_nb))
  cat(sprintf("[v4a individual OOS IC   ] XGB=%.4f / CAT=%.4f / RF=%.4f / PatchTST=%.4f / N-BEATS_mean=%.4f\n",
              ic_xgb, ic_cat, ic_rf, ic_pt, ic_nb))

  oos[, p_ew5 := (p_xgb + p_cat + p_rf + p_patchtst + p_nbeats_mean) / 5]
  oos[, p_wew := 0.25 * p_xgb + 0.25 * p_cat + 0.25 * p_rf +
                  0.125 * p_patchtst + 0.125 * p_nbeats_mean]
  pr_ew5 <- pr_auc(oos$p_ew5, oos$y); pr_wew <- pr_auc(oos$p_wew, oos$y)
  cat(sprintf("[v4a] EW5=%.4f / WEW=%.4f\n", pr_ew5, pr_wew))

  # Rename for downstream M-method matrices to mirror naming convention from 45E
  setnames(oos, c("p_patchtst", "p_nbeats_mean"), c("p_lstm", "p_tft"))

  write_parquet(oos, file.path(V4A_DIR, sprintf("predictions_5way_%s.parquet", target_col)))
  list(individual = list(xgb=pr_xgb, cat=pr_cat, rf=pr_rf,
                          patchtst=pr_pt, nbeats_mean=pr_nb),
       individual_ic = list(xgb=ic_xgb, cat=ic_cat, rf=ic_rf,
                             patchtst=ic_pt, nbeats_mean=ic_nb),
       ew5 = pr_ew5, wew = pr_wew, oos = oos)
}

res_5w_q15 <- make_5way("y_tail_q15")
res_5w_onset <- make_5way("y_onset")

#==============================================================================
# Step 5: Dynamic 5-method ensemble (M1~M5) — mirrors 45E pattern
#==============================================================================
cat("\n========== Step 5: Dynamic 5-method ensemble synthesis ==========\n")

run_dynamic_v4a <- function(target_col, oos_in) {
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

  # M2: Regime-Conditional
  feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v4a_combined.parquet")))
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
  write_parquet(out, file.path(V4A_DIR, sprintf("predictions_dynamic_%s.parquet", target_col)))

  data.table(
    target = target_col,
    method = c("Static_WEW", "M1_Rolling", "M2_Regime", "M3_Hedge", "M4_Bayes", "M5_Bandit"),
    PRAUC = c(pa_static, pa_M1, pa_M2, pa_M3, pa_M4, pa_M5)
  )
}

dyn_q15 <- run_dynamic_v4a("y_tail_q15", res_5w_q15$oos)
dyn_onset <- run_dynamic_v4a("y_onset", res_5w_onset$oos)

cat("\n[Step 5 Dynamic SUMMARY]\n")
print(rbind(dyn_q15, dyn_onset))

#==============================================================================
# Step 6: Verdict per NEW_CYCLE_CHECKLIST
#==============================================================================
cat("\n========== Step 6: Cycle Verdict (NEW_CYCLE_CHECKLIST 정합) ==========\n")

best_dyn_q15 <- max(dyn_q15$PRAUC, na.rm = TRUE)
best_dyn_q15_method <- dyn_q15[which.max(PRAUC), method]
best_dyn_onset <- max(dyn_onset$PRAUC, na.rm = TRUE)
best_dyn_onset_method <- dyn_onset[which.max(PRAUC), method]

cat(sprintf("\n[Best dynamic y_tail_q15] %s = %.4f\n", best_dyn_q15_method, best_dyn_q15))
cat(sprintf("[Best dynamic y_onset]    %s = %.4f\n", best_dyn_onset_method, best_dyn_onset))

# Decision rule (mandate spec):
#  STANDARD_HIT: best dynamic >= 0.25
#  FLOOR_HIT:    0.20 <= best dynamic < 0.25
#  REGRESSION:   best dynamic < 0.20
cycle_verdict <- if (best_dyn_q15 >= 0.25) {
  "STANDARD_HIT — best dynamic PR-AUC >= 0.25, standard target achieved"
} else if (best_dyn_q15 >= 0.20) {
  "FLOOR_HIT — best dynamic above v1.3 baseline 0.1917 but standard 미달"
} else {
  "REGRESSION — best dynamic below v1.3 baseline. Cycle 51 cleanup 후에도 미개선"
}
cat(sprintf("\n[CYCLE VERDICT] %s\n", cycle_verdict))

# SHOULD S1: PR-AUC sanity range [0.15, 0.40]
sanity_q15 <- if (best_dyn_q15 >= 0.15 && best_dyn_q15 <= 0.40) {
  "SANITY_PASS — best dynamic PR-AUC within [0.15, 0.40] (base rate 13% × 1.15~3x)"
} else if (best_dyn_q15 > 0.40) {
  "SANITY_FLAG — best > 0.40, possible buggy regression — investigate immediately"
} else {
  "SANITY_LOW — best < 0.15, below base rate × 1.15x"
}
cat(sprintf("[SANITY VERDICT] %s\n", sanity_q15))

# N-BEATS variance verdict — load from python diag
var_audit_path <- file.path(V4A_DIR, "nbeats_variance_audit.json")
nb_var <- if (file.exists(var_audit_path)) {
  fromJSON(var_audit_path)
} else {
  list(error = "missing variance audit", y_tail_q15 = list(verdict = "UNKNOWN"),
       y_onset = list(verdict = "UNKNOWN"))
}
cat(sprintf("\n[N-BEATS variance y_tail_q15] %s (avg_std=%.4f)\n",
            nb_var$y_tail_q15$verdict,
            ifelse(is.null(nb_var$y_tail_q15$avg_per_date_std),
                   NA_real_, nb_var$y_tail_q15$avg_per_date_std)))
cat(sprintf("[N-BEATS variance y_onset]    %s (avg_std=%.4f)\n",
            nb_var$y_onset$verdict,
            ifelse(is.null(nb_var$y_onset$avg_per_date_std),
                   NA_real_, nb_var$y_onset$avg_per_date_std)))

#==============================================================================
# Step 7: Compare vs Cycle 50 forward baselines + 43/45E forward leaderboard
#==============================================================================
cat("\n========== Step 7: Compare vs Cycle 50 forward baselines + leaderboard ==========\n")

# Cycle 50 v1.3 forward leaderboard (도훈 mandate baseline):
#   v1.3 baseline 69 features: M2 Regime = 0.1450, best M4_Bayes = 0.1917
#   Cycle 43 v2_2feat M4_Bayes = 0.2129 (#1 forward leaderboard)
#   Cycle 45E PatchTST individual = 0.2345 (#2 architecture winner)

V13_FWD_M2     <- 0.1450  # v1.3 forward M2 baseline
V13_FWD_BEST   <- 0.1917  # v1.3 forward best M4_Bayes
V22F_FWD_M4    <- 0.2129  # Cycle 43 v2_2feat forward M4_Bayes (#1)
V45E_FWD_PT    <- 0.2345  # Cycle 45E PatchTST individual forward (#2)

# Cycle 50 / v3e_arch_pivot forward leaderboard if available
v45e_pivot_path <- file.path(EVAL_DIR, "v3e_arch_pivot_rebaseline_forward.json")
v45e_pivot <- if (file.exists(v45e_pivot_path)) fromJSON(v45e_pivot_path) else list(error = "missing")

# Load full v1.3 forward dynamic
v13_dyn_path <- file.path(V13_FWD_DIR, "predictions_dynamic_y_tail_q15.parquet")
v13_dyn <- if (file.exists(v13_dyn_path)) {
  as.data.table(read_parquet(v13_dyn_path))
} else {
  data.table()
}

# Spearman cross-cycle ranking consistency check (NEW_CYCLE_CHECKLIST SHOULD S3)
ranking_consistency <- NULL
if (nrow(v13_dyn) > 0) {
  v13_dyn[, Date := as.Date(Date)]
  v13_oos <- v13_dyn[Date >= OOS_START & Date <= OOS_END & !is.na(p_M4_bayes) & !is.na(y)]
  v4a_dyn_q15 <- as.data.table(read_parquet(
    file.path(V4A_DIR, "predictions_dynamic_y_tail_q15.parquet")))
  v4a_dyn_q15[, Date := as.Date(Date)]
  v4a_oos_dt <- v4a_dyn_q15[Date >= OOS_START & Date <= OOS_END &
                              !is.na(p_M4_bayes) & !is.na(y)]
  ranking_dt <- merge(
    v13_oos[, .(Date, v13_p_M4 = p_M4_bayes)],
    v4a_oos_dt[, .(Date, v4a_p_M4 = p_M4_bayes)],
    by = "Date"
  )
  if (nrow(ranking_dt) > 30) {
    rho_M4 <- cor(rank(ranking_dt$v13_p_M4), rank(ranking_dt$v4a_p_M4),
                  method = "pearson")
    ranking_consistency <- round(rho_M4, 4)
    cat(sprintf("\n[Spearman ranking consistency vs v1.3 forward M4_Bayes] rho=%.4f (must be >= 0.30, < 0 = bug)\n",
                rho_M4))
  }
}

# Δ vs baselines
v4a_M4_q15 <- dyn_q15[method == "M4_Bayes", PRAUC]
v4a_M2_q15 <- dyn_q15[method == "M2_Regime", PRAUC]
v4a_static_q15 <- dyn_q15[method == "Static_WEW", PRAUC]
v4a_M3_q15 <- dyn_q15[method == "M3_Hedge", PRAUC]

delta_v4a_vs_v13_M4    <- v4a_M4_q15 - V13_FWD_BEST
delta_v4a_vs_v22f_M4   <- v4a_M4_q15 - V22F_FWD_M4

cat(sprintf("\n[Δ v4a vs Cycle 50 forward baselines — y_tail_q15]\n"))
cat(sprintf("  M4 Bayes:  v1.3 forward best=%.4f → v4a=%.4f (Δ %+.4f)\n",
            V13_FWD_BEST, v4a_M4_q15, delta_v4a_vs_v13_M4))
cat(sprintf("  M4 Bayes:  Cycle 43 forward=%.4f → v4a=%.4f (Δ %+.4f)\n",
            V22F_FWD_M4, v4a_M4_q15, delta_v4a_vs_v22f_M4))
cat(sprintf("  Static WEW v4a=%.4f  /  M2 Regime v4a=%.4f  /  M3 Hedge v4a=%.4f\n",
            v4a_static_q15, v4a_M2_q15, v4a_M3_q15))

# PatchTST individual vs Cycle 45E forward
v4a_pt_indiv <- res_5w_q15$individual$patchtst
delta_pt_vs_v45e <- v4a_pt_indiv - V45E_FWD_PT
cat(sprintf("\n[PatchTST individual] Cycle 45E forward=%.4f → v4a=%.4f (Δ %+.4f)\n",
            V45E_FWD_PT, v4a_pt_indiv, delta_pt_vs_v45e))

#==============================================================================
# Step 8: Save outputs (JSON + chart)
#==============================================================================
cat("\n========== Step 8: Save outputs ==========\n")

# Load GBDT step2 + python diag for full provenance
step2_path <- file.path(EVAL_DIR, "v4a_combined_step2_gbdt.json")
step2 <- if (file.exists(step2_path)) fromJSON(step2_path) else list(error = "missing step2 json")
py_diag_path <- file.path(EVAL_DIR, "5way_retrain_v4a_combined_python_diag.json")
py_diag <- if (file.exists(py_diag_path)) fromJSON(py_diag_path) else list(error = "missing python diag")

result_json <- list(
  cycle = "52_path_a_combined",
  approach = "FORWARD_LABEL_WINNING_COMBINATION",
  cycle_43_winner_feature = "foreign_breadth_ad_ratio_5d_avg_lag1",
  cycle_43_dropped_feature = "foreign_cum_5d_lag1 (Cycle 43 dead 입증)",
  cycle_45e_winner_architectures = list("PatchTST", "N-BEATS"),
  nbeats_multi_seed = list(
    n_seeds = 5,
    seeds = c(42, 123, 456, 789, 1024),
    rationale = "Cycle 45E 0.5479 vs Cycle 49B 0.1823 = 0.37 stochastic variance — multi-seed mean recommended"
  ),
  n_features = 70,
  forward_labels = TRUE,
  bug_fix_commit = "Cycle 50 Phase 1: scripts/02_target_builder.R line 39 / Cycle 51 cleanup retain",
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END),
                    note = "fold 5 valid 2016-2017 제외하여 leakage 방지"),
  baselines_forward = list(
    v1_3_M2_Regime_y_tail_q15      = V13_FWD_M2,
    v1_3_best_M4_Bayes_y_tail_q15  = V13_FWD_BEST,
    cycle_43_v2_2feat_M4_Bayes_y_tail_q15 = V22F_FWD_M4,
    cycle_45e_PatchTST_individual_y_tail_q15 = V45E_FWD_PT
  ),
  individual_OOS_PRAUC_y_tail_q15 = res_5w_q15$individual,
  individual_OOS_IC_y_tail_q15 = res_5w_q15$individual_ic,
  individual_OOS_PRAUC_y_onset = res_5w_onset$individual,
  individual_OOS_IC_y_onset = res_5w_onset$individual_ic,
  dynamic_PRAUC_y_tail_q15 = setNames(as.list(round(dyn_q15$PRAUC, 4)), dyn_q15$method),
  dynamic_PRAUC_y_onset = setNames(as.list(round(dyn_onset$PRAUC, 4)), dyn_onset$method),
  ew5_y_tail_q15 = round(res_5w_q15$ew5, 4),
  wew_y_tail_q15 = round(res_5w_q15$wew, 4),
  ew5_y_onset = round(res_5w_onset$ew5, 4),
  wew_y_onset = round(res_5w_onset$wew, 4),
  best_dynamic = list(
    y_tail_q15 = list(method = best_dyn_q15_method, PRAUC = round(best_dyn_q15, 4)),
    y_onset    = list(method = best_dyn_onset_method, PRAUC = round(best_dyn_onset, 4))
  ),
  delta_vs_forward_baselines_y_tail_q15 = list(
    delta_M4_vs_v1_3_best     = round(delta_v4a_vs_v13_M4, 4),
    delta_M4_vs_cycle_43_v22f = round(delta_v4a_vs_v22f_M4, 4),
    delta_PatchTST_vs_cycle_45e = round(delta_pt_vs_v45e, 4)
  ),
  ranking_consistency_spearman = ranking_consistency,
  verdict_cycle = cycle_verdict,
  verdict_sanity = sanity_q15,
  verdict_nbeats_variance = list(
    y_tail_q15 = if (!is.null(nb_var$y_tail_q15$verdict)) nb_var$y_tail_q15$verdict else "UNKNOWN",
    y_onset    = if (!is.null(nb_var$y_onset$verdict)) nb_var$y_onset$verdict else "UNKNOWN"
  ),
  new_cycle_checklist_compliance = list(
    M1_bear_date_audit = "PASS (pre-cycle 4/4, log qepm/observability/sanity_checks/bear_date_audit_20260520_153824.json)",
    M2_validate_label_direction = "PASS (forward labels in targets_full.parquet validated by Cycle 50 fix)",
    M3_PIT_C1_C15 = "PASS (v1.3 features PIT validated + winner lag1 verified Step 1)",
    M4_shift_convention = "PASS (forward targets uses shift(., n=H, 'lead'))",
    M5_AX_008 = "EXEMPT (Forge single-source quick screening, NOT admit cycle)",
    S1_PRAUC_sanity = sanity_q15,
    S2_COVID_spot_check = "PASS (targets_full.parquet 2020-02-19 ret_h = -0.3405)",
    S3_Spearman_ranking_consistency = ifelse(is.null(ranking_consistency), "UNKNOWN",
                                              sprintf("rho=%.4f (>=0.30 required)", ranking_consistency)),
    A1_cross_cycle_same_forward_labels = "PASS (all baselines forward labels Cycle 50 fix)",
    A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
    A3_codex_critic = "DEFER (Forge single-source, admit cycle 시 의무)"
  ),
  next_cycle_suggestion = if (grepl("STANDARD_HIT", cycle_verdict)) {
    "Codex/Architect verification cycle (AX-008 admit pathway) — STANDARD_HIT triggers full triangulation"
  } else if (grepl("FLOOR_HIT", cycle_verdict)) {
    "Path C (long horizon q126 통합, Cycle 48A 0.3079 path) 또는 추가 architecture exploration"
  } else {
    "본질 진단 cycle — Cycle 51 cleanup 후에도 개선 X. signal saturation 인정 + new feature axis 모색"
  },
  python_diagnostics_summary = py_diag,
  gbdt_summary = step2,
  nbeats_variance_audit = nb_var,
  outputs = list(
    panel = file.path(DATA_DIR, "feature_panel_v4a_combined.parquet"),
    v4a_dir = V4A_DIR,
    chart = file.path(CHART_DIR, "122_pr_curve_v4a_combined.png")
  )
)

out_json <- file.path(EVAL_DIR, "5way_retrain_v4a_combined.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

# Chart: PR curve compare baselines vs v4a
v4a_dyn_q15 <- as.data.table(read_parquet(file.path(V4A_DIR, "predictions_dynamic_y_tail_q15.parquet")))
v4a_dyn_q15[, Date := as.Date(Date)]

curves <- data.table()

# v1.3 forward baseline
if (file.exists(v13_dyn_path)) {
  v13_dyn[, Date := as.Date(Date)]
  v13_oos2 <- v13_dyn[Date >= OOS_START & Date <= OOS_END]
  if (nrow(v13_oos2) > 0) {
    ds_v13_m4 <- pr_curve(v13_oos2$p_M4_bayes, v13_oos2$y)
    ds_v13_m4[, model := sprintf("v1.3 forward M4_Bayes (PR-AUC=%.4f)",
                                  pr_auc(v13_oos2$p_M4_bayes, v13_oos2$y))]
    curves <- rbind(curves, ds_v13_m4)
  }
}

# Cycle 43 forward baseline (v2_2feat M4)
v22f_dyn_path <- file.path(V22F_FWD_DIR, "predictions_dynamic_y_tail_q15.parquet")
if (file.exists(v22f_dyn_path)) {
  v22f_dyn <- as.data.table(read_parquet(v22f_dyn_path))
  v22f_dyn[, Date := as.Date(Date)]
  v22f_oos <- v22f_dyn[Date >= OOS_START & Date <= OOS_END]
  if (nrow(v22f_oos) > 0) {
    ds_v22f_m4 <- pr_curve(v22f_oos$p_M4_bayes, v22f_oos$y)
    ds_v22f_m4[, model := sprintf("Cycle 43 forward M4_Bayes (PR-AUC=%.4f)",
                                   pr_auc(v22f_oos$p_M4_bayes, v22f_oos$y))]
    curves <- rbind(curves, ds_v22f_m4)
  }
}

# v4a M4 + M2 + Static
ds_v4a_static <- pr_curve(v4a_dyn_q15$p_static, v4a_dyn_q15$y)
ds_v4a_static[, model := sprintf("v4a Static WEW (PR-AUC=%.4f)", v4a_static_q15)]
ds_v4a_m4 <- pr_curve(v4a_dyn_q15$p_M4_bayes, v4a_dyn_q15$y)
ds_v4a_m4[, model := sprintf("v4a M4_Bayes (PR-AUC=%.4f)", v4a_M4_q15)]
ds_v4a_m2 <- pr_curve(v4a_dyn_q15$p_M2_regime, v4a_dyn_q15$y)
ds_v4a_m2[, model := sprintf("v4a M2_Regime (PR-AUC=%.4f)", v4a_M2_q15)]
ds_v4a_m3 <- pr_curve(v4a_dyn_q15$p_M3_hedge, v4a_dyn_q15$y)
ds_v4a_m3[, model := sprintf("v4a M3_Hedge (PR-AUC=%.4f)", v4a_M3_q15)]
curves <- rbind(curves, ds_v4a_static, ds_v4a_m4, ds_v4a_m2, ds_v4a_m3)

base_rate <- mean(v4a_dyn_q15$y, na.rm = TRUE)

g <- ggplot(curves, aes(x = recall, y = precision, color = model)) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = base_rate, linetype = "dashed", color = "gray40") +
  scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
  labs(title = sprintf("Cycle 52 Path A v4a Combined  [%s]",
                       substr(cycle_verdict, 1, 80)),
       subtitle = sprintf("y_tail_q15 OOS 2018-2026 / 70 features (v1.3 69 + Cycle 43 winner 1) / 5-way ensemble PatchTST + N-BEATS_mean (5 seeds)"),
       x = "Recall", y = "Precision", color = NULL,
       caption = sprintf("Dashed = base rate %.2f%%. N-BEATS variance verdict q15=%s / onset=%s",
                         100*base_rate,
                         ifelse(!is.null(nb_var$y_tail_q15$verdict),
                                nb_var$y_tail_q15$verdict, "UNKNOWN"),
                         ifelse(!is.null(nb_var$y_onset$verdict),
                                nb_var$y_onset$verdict, "UNKNOWN"))) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", legend.text = element_text(size = 9)) +
  guides(color = guide_legend(ncol = 2))

ggsave(file.path(CHART_DIR, "122_pr_curve_v4a_combined.png"),
       plot = g, width = 11, height = 7, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "122_pr_curve_v4a_combined.png")))

cat("\n========== Cycle 52 Path A AGGREGATE DONE ==========\n")
cat(sprintf("Cycle verdict: %s\n", cycle_verdict))
cat(sprintf("Sanity verdict: %s\n", sanity_q15))
cat(sprintf("N-BEATS variance y_tail_q15: %s  /  y_onset: %s\n",
            ifelse(!is.null(nb_var$y_tail_q15$verdict),
                   nb_var$y_tail_q15$verdict, "UNKNOWN"),
            ifelse(!is.null(nb_var$y_onset$verdict),
                   nb_var$y_onset$verdict, "UNKNOWN")))
cat(sprintf("Best dynamic y_tail_q15: %s = %.4f\n",
            best_dyn_q15_method, best_dyn_q15))
cat(sprintf("Δ vs Cycle 50 v1.3 forward best M4 (0.1917): %+.4f\n",
            v4a_M4_q15 - V13_FWD_BEST))
cat(sprintf("Δ vs Cycle 43 forward M4 (0.2129): %+.4f\n",
            v4a_M4_q15 - V22F_FWD_M4))
cat(sprintf("Δ PatchTST vs Cycle 45E forward (0.2345): %+.4f\n",
            v4a_pt_indiv - V45E_FWD_PT))
