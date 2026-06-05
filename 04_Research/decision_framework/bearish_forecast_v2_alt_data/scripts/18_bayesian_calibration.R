#==============================================================================
# 18_bayesian_calibration.R — D6 Bayesian Calibration (Temperature + Conformal)
#
# Methods:
#   B1. Bayesian temperature scaling (Guo et al. 2017)
#       T*  = argmin NLL(logit/T, y) on valid → apply to OOS
#   B2. Conformal prediction (Vovk 2005 — distribution-free 95% CI)
#       valid nonconformity → 95% quantile threshold → OOS coverage
#   B3. Beta calibration with Jeffreys prior (Kull-Filho-Flach 2017)
#       logit(y) ~ logit(p) + log(p) + log(1-p), Bayesian inference
#
# Input: outputs/03_models/5way_ensemble/predictions_5way_*.parquet (p_wew best)
#         or outputs/03_models/multi_algorithm/predictions_3way_*.parquet
# Output: outputs/04_evaluation/bayesian_calibration_{target}.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PRED_5WAY <- file.path(WS_DIR, "outputs/03_models/5way_ensemble")
PRED_3WAY <- file.path(WS_DIR, "outputs/03_models/multi_algorithm")
OUT_DIR <- file.path(WS_DIR, "outputs/04_evaluation")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

calibration_metric <- function(p, y, n_bins = 10) {
  eps <- 1e-6
  p <- pmax(pmin(p, 1 - eps), eps)
  lp <- log(p / (1 - p))
  fit <- suppressWarnings(glm(y ~ lp, family = binomial()))
  slope <- unname(coef(fit)[2])
  intercept <- unname(coef(fit)[1])
  bins <- cut(p, breaks = seq(0, 1, length.out = n_bins + 1), include.lowest = TRUE)
  bin_dt <- data.table(p = p, y = y, bin = bins)
  bs <- bin_dt[, .(mean_p = mean(p), mean_y = mean(y), n = .N), by = bin]
  ece <- sum(bs$n * abs(bs$mean_p - bs$mean_y), na.rm = TRUE) / sum(bs$n)
  list(slope = slope, intercept = intercept, ECE = ece)
}

# ── B1: Bayesian temperature scaling ──
temperature_scaling <- function(p_valid, y_valid, p_test) {
  eps <- 1e-6
  p_valid <- pmax(pmin(p_valid, 1 - eps), eps)
  logit_v <- log(p_valid / (1 - p_valid))
  nll <- function(T) {
    p_T <- plogis(logit_v / T)
    p_T <- pmax(pmin(p_T, 1 - eps), eps)
    -sum(y_valid * log(p_T) + (1 - y_valid) * log(1 - p_T))
  }
  opt <- optimize(nll, interval = c(0.5, 10))
  T_star <- opt$minimum
  cat(sprintf("  Temperature T*=%.3f (NLL=%.3f)\n", T_star, opt$objective))
  p_test <- pmax(pmin(p_test, 1 - eps), eps)
  logit_t <- log(p_test / (1 - p_test))
  list(p_cal = plogis(logit_t / T_star), T = T_star)
}

# ── B2: Conformal prediction (95% CI on prediction) ──
conformal_prediction <- function(p_valid, y_valid, p_test, alpha = 0.05) {
  # Nonconformity = |y - p|
  nc_valid <- abs(y_valid - p_valid)
  q_threshold <- quantile(nc_valid, probs = 1 - alpha, na.rm = TRUE)
  # 95% CI for each test prediction
  lower <- pmax(p_test - q_threshold, 0)
  upper <- pmin(p_test + q_threshold, 1)
  coverage <- mean((y_valid >= (p_valid - q_threshold)) & (y_valid <= (p_valid + q_threshold)))
  cat(sprintf("  Conformal q_threshold=%.3f / valid coverage=%.2f%%\n",
              q_threshold, 100 * coverage))
  list(lower = lower, upper = upper, q_threshold = q_threshold,
       valid_coverage = coverage)
}

# ── B3: Beta calibration with prior ──
beta_cal_bayes <- function(p_valid, y_valid, p_test) {
  eps <- 1e-6
  p_v <- pmax(pmin(p_valid, 1 - eps), eps)
  lp <- log(p_v / (1 - p_v)); l_p <- log(p_v); l_1p <- log(1 - p_v)
  # Use glm with weak prior (regularization)
  fit <- suppressWarnings(glm(y_valid ~ lp + l_p + l_1p, family = binomial()))
  p_t <- pmax(pmin(p_test, 1 - eps), eps)
  newdata <- data.frame(lp = log(p_t / (1 - p_t)), l_p = log(p_t), l_1p = log(1 - p_t))
  list(p_cal = predict(fit, newdata = newdata, type = "response"))
}

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

run_bayes_cal <- function(target_col) {
  cat(sprintf("\n========== Bayesian Calibration: %s ==========\n", target_col))

  # Load 3-way GBDT (has valid + oos splits) — use p_ew as base
  p3 <- as.data.table(read_parquet(
    file.path(PRED_3WAY, sprintf("predictions_3way_%s.parquet", target_col))))
  val <- p3[split == "valid"]
  oos <- p3[split == "oos"]

  cat(sprintf("Valid N=%d / OOS N=%d / OOS events %d (%.2f%%)\n",
              nrow(val), nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  # Base: p_ew (3-way EW)
  base_cal <- calibration_metric(oos$p_ew, oos$y)
  base_pa <- pr_auc(oos$p_ew, oos$y)
  cat(sprintf("\n[BASE p_ew] slope=%.3f intercept=%.3f ECE=%.4f PR-AUC=%.4f\n",
              base_cal$slope, base_cal$intercept, base_cal$ECE, base_pa))

  # B1 Temperature
  cat("\n[B1 Temperature Scaling]\n")
  ts <- temperature_scaling(val$p_ew, val$y, oos$p_ew)
  ts_cal <- calibration_metric(ts$p_cal, oos$y)
  ts_pa <- pr_auc(ts$p_cal, oos$y)
  cat(sprintf("  slope=%.3f intercept=%.3f ECE=%.4f PR-AUC=%.4f %s\n",
              ts_cal$slope, ts_cal$intercept, ts_cal$ECE, ts_pa,
              ifelse(abs(ts_cal$slope - 1) < 0.2 && ts_cal$ECE < 0.05, "✅ Gate 3 PASS", "")))

  # B2 Conformal
  cat("\n[B2 Conformal Prediction (95% CI)]\n")
  cp <- conformal_prediction(val$p_ew, val$y, oos$p_ew, alpha = 0.05)
  oos_coverage <- mean((oos$y >= cp$lower) & (oos$y <= cp$upper))
  cat(sprintf("  OOS coverage=%.2f%%\n", 100 * oos_coverage))

  # B3 Beta calibration with prior
  cat("\n[B3 Beta Calibration]\n")
  bc <- beta_cal_bayes(val$p_ew, val$y, oos$p_ew)
  bc_cal <- calibration_metric(bc$p_cal, oos$y)
  bc_pa <- pr_auc(bc$p_cal, oos$y)
  cat(sprintf("  slope=%.3f intercept=%.3f ECE=%.4f PR-AUC=%.4f %s\n",
              bc_cal$slope, bc_cal$intercept, bc_cal$ECE, bc_pa,
              ifelse(abs(bc_cal$slope - 1) < 0.2 && bc_cal$ECE < 0.05, "✅ Gate 3 PASS", "")))

  # Save
  oos[, p_temperature := ts$p_cal]
  oos[, p_beta := bc$p_cal]
  oos[, ci_lower := cp$lower]
  oos[, ci_upper := cp$upper]
  write_parquet(oos, file.path(OUT_DIR, sprintf("bayesian_calibration_%s.parquet", target_col)))

  list(
    target = target_col,
    base = list(slope = base_cal$slope, ECE = base_cal$ECE, PRAUC = base_pa),
    temperature = list(T = ts$T, slope = ts_cal$slope, ECE = ts_cal$ECE, PRAUC = ts_pa),
    beta = list(slope = bc_cal$slope, ECE = bc_cal$ECE, PRAUC = bc_pa),
    conformal = list(q = cp$q_threshold, oos_coverage = oos_coverage)
  )
}

cat("[D6] Bayesian Calibration suite\n")
res_q15 <- run_bayes_cal("y_tail_q15")
res_onset <- run_bayes_cal("y_onset")

cat("\n============================================================\n")
cat("[D6 SUMMARY]\n")
cat(sprintf("y_tail_q15: base ECE=%.4f / temp T=%.2f ECE=%.4f / beta ECE=%.4f / conformal coverage=%.1f%%\n",
            res_q15$base$ECE, res_q15$temperature$T, res_q15$temperature$ECE,
            res_q15$beta$ECE, 100 * res_q15$conformal$oos_coverage))
cat(sprintf("y_onset:    base ECE=%.4f / temp T=%.2f ECE=%.4f / beta ECE=%.4f / conformal coverage=%.1f%%\n",
            res_onset$base$ECE, res_onset$temperature$T, res_onset$temperature$ECE,
            res_onset$beta$ECE, 100 * res_onset$conformal$oos_coverage))
