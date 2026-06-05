#==============================================================================
# 08_alpha_enhancement.R — α1 Calibration recal + α2 Threshold tuning + α3 보강
#
# Plan v1.0 → v1.0.1 enhancement
#
# α1: Isotonic + Beta calibration (Platt 대체 / 보강)
# α2: Threshold tuning curve (top 5/10/20/30% precision-recall)
# α3: 04_model_runner XGBoost depth 4 + ntrees 1000 + pos_weight 8 (별도 적용)
#
# Input: outputs/03_models/stacking_ensemble/predictions_final.parquet
# Output:
#   outputs/04_evaluation/calibration_recal.parquet (Platt + Isotonic + Beta)
#   outputs/04_evaluation/threshold_curve.csv (precision/recall × top-k)
#   outputs/04_evaluation/y_tail_q15_primary_summary.md
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PREDS_PATH <- file.path(WS_DIR, "outputs/03_models/stacking_ensemble/predictions_final.parquet")
TGT_PATH   <- file.path(WS_DIR, "outputs/02_targets/targets_full.parquet")
OUT_DIR    <- file.path(WS_DIR, "outputs/04_evaluation")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ── α1.1 Platt scaling (기존 baseline) ────────────────────────
platt_cal <- function(p, y) {
  fit <- suppressWarnings(glm(y ~ p, family = binomial()))
  function(p_new) plogis(coef(fit)[1] + coef(fit)[2] * p_new)
}

# ── α1.2 Isotonic regression calibration ─────────────────────
isotonic_cal <- function(p, y) {
  ord <- order(p)
  iso <- isoreg(p[ord], y[ord])
  iso_fn <- approxfun(p[ord], iso$yf, rule = 2)
  function(p_new) pmax(pmin(iso_fn(p_new), 1), 0)
}

# ── α1.3 Beta calibration (Kull et al. 2017) ──────────────────
beta_cal <- function(p, y) {
  # logit(y) ~ logit(p) + log(p) + log(1-p)
  eps <- 1e-6
  p <- pmax(pmin(p, 1 - eps), eps)
  lp <- log(p / (1 - p))
  l_p <- log(p)
  l_1p <- log(1 - p)
  fit <- suppressWarnings(glm(y ~ lp + l_p + l_1p, family = binomial()))
  function(p_new) {
    p_new <- pmax(pmin(p_new, 1 - eps), eps)
    lp_n <- log(p_new / (1 - p_new))
    plogis(predict(fit, newdata = data.frame(lp = lp_n,
                                              l_p = log(p_new),
                                              l_1p = log(1 - p_new))))
  }
}

# ── Calibration metrics ──
calibration_metric <- function(p, y, n_bins = 10) {
  eps <- 1e-6
  p <- pmax(pmin(p, 1 - eps), eps)
  lp <- log(p / (1 - p))
  fit <- suppressWarnings(glm(y ~ lp, family = binomial()))
  slope <- unname(coef(fit)[2])
  intercept <- unname(coef(fit)[1])
  # ECE
  bins <- cut(p, breaks = seq(0, 1, length.out = n_bins + 1), include.lowest = TRUE)
  bin_dt <- data.table(p = p, y = y, bin = bins)
  bs <- bin_dt[, .(mean_p = mean(p), mean_y = mean(y), n = .N), by = bin]
  ece <- sum(bs$n * abs(bs$mean_p - bs$mean_y), na.rm = TRUE) / sum(bs$n)
  list(slope = slope, intercept = intercept, ECE = ece)
}

# ── PR-AUC ──
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

# ── α2 Threshold tuning curve ──
threshold_curve <- function(p, y, alert_pcts = c(0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50)) {
  n <- length(p)
  results <- lapply(alert_pcts, function(pct) {
    k <- ceiling(n * pct)
    alert_idx <- order(p, decreasing = TRUE)[1:k]
    tp <- sum(y[alert_idx] == 1, na.rm = TRUE)
    total_events <- sum(y == 1, na.rm = TRUE)
    list(alert_pct = pct, k_alerts = k, TP = tp,
         total_events = total_events,
         precision = tp / k,
         recall = tp / total_events,
         lift_vs_random = (tp / k) / (total_events / n))
  })
  rbindlist(results)
}

# ── 메인 ──
run_alpha_enhancement <- function(target_col = "y_tail_q15") {
  if (!file.exists(PREDS_PATH)) stop("predictions_final.parquet missing")
  if (!file.exists(TGT_PATH))   stop("targets_full.parquet missing")

  preds <- as.data.table(read_parquet(PREDS_PATH))
  targets <- as.data.table(read_parquet(TGT_PATH))

  preds <- preds[target == target_col]
  df <- merge(preds, targets[, c("Date", target_col), with = FALSE], by = "Date")
  setnames(df, target_col, "actual")

  # Use OOS only for evaluation, valid for calibration fit
  val <- df[split == "valid" & !is.na(prob_final) & !is.na(actual)]
  oos <- df[split == "oos" & !is.na(prob_final) & !is.na(actual)]

  cat(sprintf("\n[α1+α2] Target: %s | Valid N=%d / OOS N=%d / OOS events %d (%.2f%%)\n",
              target_col, nrow(val), nrow(oos),
              sum(oos$actual), 100 * mean(oos$actual)))

  # ── α1: 3-way calibration on valid → apply to OOS ──
  cal_platt    <- platt_cal(val$prob_final, val$actual)
  cal_isotonic <- isotonic_cal(val$prob_final, val$actual)
  cal_beta     <- tryCatch(beta_cal(val$prob_final, val$actual),
                            error = function(e) { cat("[α1] beta cal FAIL:", e$message, "\n"); NULL })

  oos[, p_platt    := cal_platt(prob_final)]
  oos[, p_isotonic := cal_isotonic(prob_final)]
  if (!is.null(cal_beta)) {
    oos[, p_beta := cal_beta(prob_final)]
    oos[, p_ensemble := (p_platt + p_isotonic + p_beta) / 3]
  } else {
    oos[, p_ensemble := (p_platt + p_isotonic) / 2]
  }

  # Calibration metrics 비교
  cat("\n[α1] Calibration metrics on OOS:\n")
  for (p_col in c("prob_final", "p_platt", "p_isotonic",
                  if ("p_beta" %in% names(oos)) "p_beta", "p_ensemble")) {
    m <- calibration_metric(oos[[p_col]], oos$actual)
    pa <- pr_auc(oos[[p_col]], oos$actual)
    cat(sprintf("  %-12s : slope=%.3f / intercept=%.3f / ECE=%.4f / PR-AUC=%.4f %s\n",
                p_col, m$slope, m$intercept, m$ECE, pa,
                ifelse(m$slope >= 0.8 & m$slope <= 1.2 & m$ECE < 0.05, "✅ PASS Gate 3", "")))
  }

  # ── α2: Threshold curve ──
  cat("\n[α2] Threshold curve (OOS, using p_ensemble):\n")
  curve <- threshold_curve(oos$p_ensemble, oos$actual)
  print(curve)

  fwrite(curve, file.path(OUT_DIR, sprintf("threshold_curve_%s.csv", target_col)))
  write_parquet(oos, file.path(OUT_DIR, sprintf("calibration_recal_%s.parquet", target_col)))

  # ── Summary markdown ──
  best_cal <- which.min(sapply(c("prob_final", "p_platt", "p_isotonic", "p_ensemble"),
                                function(c) {
                                  m <- calibration_metric(oos[[c]], oos$actual)
                                  abs(m$slope - 1) + m$ECE
                                }))
  best_name <- c("prob_final", "p_platt", "p_isotonic", "p_ensemble")[best_cal]
  cat(sprintf("\n[α1] Best calibration: %s\n", best_name))

  invisible(list(curve = curve, oos = oos, best_cal = best_name))
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  cat("\n========== y_tail_q15 (PRIMARY) ==========\n")
  res_q15 <- run_alpha_enhancement("y_tail_q15")
  cat("\n========== y_onset (SECONDARY) ==========\n")
  res_onset <- run_alpha_enhancement("y_onset")
}
