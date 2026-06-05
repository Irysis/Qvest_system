#==============================================================================
# 13_stacking_meta.R — E3 Stacking meta-learner
#
# 3 model predictions (XGBoost + CatBoost + Ranger RF) → logistic meta-learner
#
# Valid split → train meta-learner (logistic on 3 probs + actual)
# OOS split → apply meta-learner → p_stack
# Compare: p_stack vs p_ew (단순 평균)
#
# Output: outputs/03_models/stacking_meta/predictions_stacked.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
MA_DIR <- file.path(WS_DIR, "outputs/03_models/multi_algorithm")
OUT_DIR <- file.path(WS_DIR, "outputs/03_models/stacking_meta")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

run_stacking <- function(target_col) {
  cat(sprintf("\n========== Stacking %s ==========\n", target_col))
  preds_path <- file.path(MA_DIR, sprintf("predictions_3way_%s.parquet", target_col))
  if (!file.exists(preds_path)) {
    cat("[E3] Missing predictions_3way file. Run E2 first.\n")
    return(NULL)
  }
  d <- as.data.table(read_parquet(preds_path))

  val <- d[split == "valid"]
  oos <- d[split == "oos"]
  cat(sprintf("Valid N=%d / OOS N=%d / OOS events %d\n",
              nrow(val), nrow(oos), sum(oos$y)))

  # Meta-learner: logistic on (p_xgb, p_cat, p_rf)
  meta_fit <- glm(y ~ p_xgb + p_cat + p_rf, data = val, family = binomial())
  cat("[E3] Meta-learner coefficients:\n")
  print(coef(meta_fit))

  oos[, p_stack := predict(meta_fit, newdata = oos, type = "response")]

  # Compare PR-AUC
  pr_xgb <- pr_auc(oos$p_xgb, oos$y)
  pr_cat <- pr_auc(oos$p_cat, oos$y)
  pr_rf <- pr_auc(oos$p_rf, oos$y)
  pr_ew <- pr_auc(oos$p_ew, oos$y)
  pr_stack <- pr_auc(oos$p_stack, oos$y)

  cat("\n[E3] OOS PR-AUC comparison:\n")
  cat(sprintf("  XGBoost only:  %.4f\n", pr_xgb))
  cat(sprintf("  CatBoost only: %.4f\n", pr_cat))
  cat(sprintf("  Ranger RF only:%.4f\n", pr_rf))
  cat(sprintf("  EW 3-way:      %.4f\n", pr_ew))
  cat(sprintf("  Stack meta:    %.4f %s\n", pr_stack,
              ifelse(pr_stack > pr_ew, "★ BEST", "")))

  write_parquet(oos, file.path(OUT_DIR, sprintf("predictions_stacked_%s.parquet", target_col)))
  list(stack = pr_stack, ew = pr_ew, xgb = pr_xgb, cat = pr_cat, rf = pr_rf)
}

cat("[E3] Stacking meta-learner (logistic)...\n")
res_q15 <- run_stacking("y_tail_q15")
res_onset <- run_stacking("y_onset")

if (!is.null(res_q15) && !is.null(res_onset)) {
  cat("\n============================================================\n")
  cat("[E3 SUMMARY]\n")
  cat(sprintf("y_tail_q15:  XGB=%.4f CAT=%.4f RF=%.4f EW=%.4f STACK=%.4f\n",
              res_q15$xgb, res_q15$cat, res_q15$rf, res_q15$ew, res_q15$stack))
  cat(sprintf("y_onset:     XGB=%.4f CAT=%.4f RF=%.4f EW=%.4f STACK=%.4f\n",
              res_onset$xgb, res_onset$cat, res_onset$rf, res_onset$ew, res_onset$stack))
}
