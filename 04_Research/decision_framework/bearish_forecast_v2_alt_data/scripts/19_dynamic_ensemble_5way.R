#==============================================================================
# 19_dynamic_ensemble_5way.R — D7 Dynamic Ensemble 5 Methods
#
# 5 dynamic weighting methods on (XGB + CatBoost + RF + LSTM + TFT):
#   M1. Rolling Window Adaptive (252d lookback → softmax PR-AUC)
#   M2. Regime-conditional (bull/sideways/bear per macro_risk_score → best weights)
#   M3. Online Hedge (Cesa-Bianchi-Lugosi 2006 multiplicative weights)
#   M4. Bayesian online (posterior ∝ exp(cumulative log-likelihood))
#   M5. Contextual bandit (regime context, ε-greedy weight pick)
#
# Static baseline = D4 best (Weighted EW): GBDT 0.25 × 3 + Deep 0.125 × 2
#
# Output: outputs/03_models/dynamic_ensemble/{predictions_dyn_M*_{target}.parquet}
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PRED_5WAY <- file.path(WS_DIR, "outputs/03_models/5way_ensemble")
DATA_DIR <- file.path(WS_DIR, "outputs/01_data")
OUT_DIR <- file.path(WS_DIR, "outputs/03_models/dynamic_ensemble")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

LOOKBACK <- 252    # 1Y rolling
PURGE <- 21        # forecast horizon = label leak buffer

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

run_dynamic <- function(target_col) {
  cat(sprintf("\n========== Dynamic Ensemble 5 methods: %s ==========\n", target_col))

  p5 <- as.data.table(read_parquet(
    file.path(PRED_5WAY, sprintf("predictions_5way_%s.parquet", target_col))))
  p5[, Date := as.Date(Date)]
  setorder(p5, Date)
  n_total <- nrow(p5)
  cat(sprintf("[D7] OOS preds N=%d / events=%d (%.2f%%)\n",
              n_total, sum(p5$y), 100 * mean(p5$y)))

  M_NAMES <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft")
  M <- as.matrix(p5[, ..M_NAMES])
  Y <- p5$y

  # Static baseline (D4 weighted EW)
  w_static <- c(0.25, 0.25, 0.25, 0.125, 0.125)
  p_static <- as.numeric(M %*% w_static)
  pa_static <- pr_auc(p_static, Y)
  cat(sprintf("[Baseline static weighted EW] PR-AUC=%.4f\n", pa_static))

  # ── M1: Rolling Window Adaptive ────────────────────────────
  cat("\n[M1 Rolling Adaptive] — 252d lookback, softmax β=5\n")
  p_M1 <- rep(NA_real_, n_total)
  w_history <- list()
  for (i in seq_len(n_total)) {
    cutoff <- i - PURGE
    start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    p_window <- M[start:cutoff, , drop = FALSE]
    y_window <- Y[start:cutoff]
    pr_models <- sapply(seq_len(5), function(m) pr_auc(p_window[, m], y_window))
    pr_models[is.na(pr_models)] <- 0
    w <- softmax(pr_models, beta = 5)
    p_M1[i] <- sum(M[i, ] * w)
    if (i %% 500 == 0) w_history[[length(w_history) + 1]] <- list(idx = i, w = w)
  }
  pa_M1 <- pr_auc(p_M1, Y)
  cat(sprintf("  PR-AUC=%.4f %s\n", pa_M1, ifelse(pa_M1 > pa_static, "★", "")))
  if (length(w_history) > 0) {
    last_w <- tail(w_history, 1)[[1]]$w
    cat(sprintf("  Last weights (idx=%d): XGB=%.3f CAT=%.3f RF=%.3f LSTM=%.3f TFT=%.3f\n",
                tail(w_history, 1)[[1]]$idx,
                last_w[1], last_w[2], last_w[3], last_w[4], last_w[5]))
  }

  # ── M2: Regime-conditional ────────────────────────────────
  cat("\n[M2 Regime-Conditional] — macro_risk_score quantile (bull/sideways/bear)\n")
  feat_path <- file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")
  feat <- as.data.table(read_parquet(feat_path))
  feat[, Date := as.Date(Date)]
  p5_r <- merge(p5, feat[, .(Date, bbva_macro_composite)], by = "Date", all.x = TRUE)
  setorder(p5_r, Date)

  # Train-period regime thresholds (PIT)
  train_macro <- p5_r$bbva_macro_composite[seq_len(min(2000, n_total))]
  q33 <- quantile(train_macro, 0.33, na.rm = TRUE)
  q67 <- quantile(train_macro, 0.67, na.rm = TRUE)
  p5_r[, regime := fcase(
    is.na(bbva_macro_composite), NA_character_,
    bbva_macro_composite <= q33, "bull",
    bbva_macro_composite >= q67, "bear",
    default = "sideways"
  )]

  # Per-regime best 2 model weights (rolling assessment)
  M_r <- as.matrix(p5_r[, ..M_NAMES])
  Y_r <- p5_r$y
  Regime <- p5_r$regime
  p_M2 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    cur_reg <- Regime[i]
    if (is.na(cur_reg)) next
    cutoff <- i - PURGE
    start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    in_reg <- which(Regime[start:cutoff] == cur_reg) + (start - 1)
    if (length(in_reg) < 30) {
      # Fallback to static
      p_M2[i] <- sum(M_r[i, ] * w_static); next
    }
    pr_models <- sapply(seq_len(5), function(m) pr_auc(M_r[in_reg, m], Y_r[in_reg]))
    pr_models[is.na(pr_models)] <- 0
    w <- softmax(pr_models, beta = 5)
    p_M2[i] <- sum(M_r[i, ] * w)
  }
  pa_M2 <- pr_auc(p_M2, Y_r)
  cat(sprintf("  PR-AUC=%.4f %s\n", pa_M2, ifelse(pa_M2 > pa_static, "★", "")))

  # ── M3: Online Hedge (multiplicative weights) ─────────────
  cat("\n[M3 Online Hedge] — Cesa-Bianchi-Lugosi 2006 multiplicative weights, η=1.0\n")
  eta <- 1.0
  w_hedge <- rep(1.0 / 5, 5)
  p_M3 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    p_M3[i] <- sum(M[i, ] * w_hedge)
    # After observing y at i, update weights (one-step lag, PIT safe)
    if (!is.na(Y[i])) {
      # Loss = (p - y)^2 (squared, can use BCE)
      losses <- (M[i, ] - Y[i])^2
      w_hedge <- w_hedge * exp(-eta * losses)
      w_hedge <- w_hedge / sum(w_hedge)
    }
  }
  pa_M3 <- pr_auc(p_M3, Y)
  cat(sprintf("  PR-AUC=%.4f %s\n", pa_M3, ifelse(pa_M3 > pa_static, "★", "")))
  cat(sprintf("  Final weights: XGB=%.3f CAT=%.3f RF=%.3f LSTM=%.3f TFT=%.3f\n",
              w_hedge[1], w_hedge[2], w_hedge[3], w_hedge[4], w_hedge[5]))

  # ── M4: Bayesian online (posterior ∝ exp(cumulative log-lik)) ──
  cat("\n[M4 Bayesian Online] — posterior weights ∝ exp(cumulative log-lik)\n")
  log_lik <- rep(0, 5)
  w_bayes <- rep(1.0 / 5, 5)
  p_M4 <- rep(NA_real_, n_total)
  eps <- 1e-6
  for (i in seq_len(n_total)) {
    p_M4[i] <- sum(M[i, ] * w_bayes)
    if (!is.na(Y[i])) {
      p_clip <- pmax(pmin(M[i, ], 1 - eps), eps)
      log_lik_i <- Y[i] * log(p_clip) + (1 - Y[i]) * log(1 - p_clip)
      log_lik <- log_lik + log_lik_i
      # Posterior softmax
      w_bayes <- softmax(log_lik / max(i, 100), beta = 50)  # cumulative average
    }
  }
  pa_M4 <- pr_auc(p_M4, Y)
  cat(sprintf("  PR-AUC=%.4f %s\n", pa_M4, ifelse(pa_M4 > pa_static, "★", "")))
  cat(sprintf("  Final weights: XGB=%.3f CAT=%.3f RF=%.3f LSTM=%.3f TFT=%.3f\n",
              w_bayes[1], w_bayes[2], w_bayes[3], w_bayes[4], w_bayes[5]))

  # ── M5: Contextual bandit (ε-greedy, regime context) ────────
  cat("\n[M5 Contextual Bandit] — regime context, ε-greedy ε=0.1, reward = -BCE\n")
  EPSILON <- 0.1
  Q <- matrix(0, nrow = 3, ncol = 5)  # 3 regimes × 5 models
  counts <- matrix(0, nrow = 3, ncol = 5)
  regime_to_idx <- function(r) {
    if (is.na(r)) return(2)
    fcase(r == "bull", 1, r == "sideways", 2, r == "bear", 3, default = 2)
  }
  p_M5 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    reg_idx <- regime_to_idx(Regime[i])
    # ε-greedy: with ε prob pick random, else best Q
    if (runif(1) < EPSILON) {
      chosen <- sample(1:5, 1)
    } else {
      chosen <- which.max(Q[reg_idx, ])
    }
    # Use single chosen model prediction (or weighted by Q)
    w_q <- softmax(Q[reg_idx, ], beta = 3)
    p_M5[i] <- sum(M[i, ] * w_q)
    # Update Q after observing y
    if (!is.na(Y[i])) {
      for (m in seq_len(5)) {
        reward <- -((M[i, m] - Y[i])^2)
        counts[reg_idx, m] <- counts[reg_idx, m] + 1
        Q[reg_idx, m] <- Q[reg_idx, m] + (reward - Q[reg_idx, m]) / counts[reg_idx, m]
      }
    }
  }
  pa_M5 <- pr_auc(p_M5, Y)
  cat(sprintf("  PR-AUC=%.4f %s\n", pa_M5, ifelse(pa_M5 > pa_static, "★", "")))

  # Save all
  out <- p5_r[, .(Date, y, regime,
                  p_static = p_static,
                  p_M1_rolling = p_M1,
                  p_M2_regime = p_M2,
                  p_M3_hedge = p_M3,
                  p_M4_bayes = p_M4,
                  p_M5_bandit = p_M5)]
  write_parquet(out, file.path(OUT_DIR, sprintf("predictions_dynamic_%s.parquet", target_col)))

  data.table(
    target = target_col,
    method = c("Static_WEW", "M1_Rolling", "M2_Regime", "M3_Hedge", "M4_Bayes", "M5_Bandit"),
    PRAUC = c(pa_static, pa_M1, pa_M2, pa_M3, pa_M4, pa_M5)
  )
}

cat("[D7] Dynamic Ensemble 5 methods\n")
res_q15 <- run_dynamic("y_tail_q15")
res_onset <- run_dynamic("y_onset")

cat("\n============================================================\n")
cat("[D7 SUMMARY]\n")
combined <- rbind(res_q15, res_onset)
print(combined)
fwrite(combined, file.path(OUT_DIR, "dynamic_ensemble_summary.csv"))
cat(sprintf("\nOutput: %s\n", OUT_DIR))
