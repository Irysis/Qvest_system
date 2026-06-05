#==============================================================================
# 24_d9_7way_dynamic.R — D9 7-way ensemble + M2 Regime-Conditional 통합
#
# 7 models: XGB + CatBoost + RF + LSTM + TFT + MTL-UNC + MTL-AUX
# 4 ensemble variants:
#   E1. EW7 (1/7 each)
#   E2. Weighted EW (GBDT 0.18 × 3, Deep 0.13 × 2, MTL 0.13 × 2)
#   E3. Performance-weighted (softmax of OOS PR-AUC)
#   E4. M2 Regime-Conditional Dynamic on 7-way
#
# Output: outputs/03_models/7way_dynamic/predictions_*.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
GBDT_DIR <- file.path(WS, "outputs/03_models/multi_algorithm")
LSTM_DIR <- file.path(WS, "outputs/03_models/lstm")
TFT_DIR <- file.path(WS, "outputs/03_models/transformer")
MTL_DIR <- file.path(WS, "outputs/03_models/mtl_variants")
DATA_DIR <- file.path(WS, "outputs/01_data")
OUT <- file.path(WS, "outputs/03_models/7way_dynamic")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

LOOKBACK <- 252; PURGE <- 21

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}
softmax <- function(x, beta = 5) {
  e <- exp(x * beta - max(x * beta)); e / sum(e)
}

run_7way <- function(target_col) {
  cat(sprintf("\n========== D9 7-way Dynamic: %s ==========\n", target_col))

  # Load 5-way OOS
  p5 <- as.data.table(read_parquet(
    file.path(WS, "outputs/03_models/5way_ensemble", sprintf("predictions_5way_%s.parquet", target_col))))
  p5[, Date := as.Date(Date)]

  # Load MTL variants
  unc <- as.data.table(read_parquet(file.path(MTL_DIR, sprintf("predictions_mtl_unc_%s.parquet", target_col))))
  unc[, Date := as.Date(Date)]
  aux <- as.data.table(read_parquet(file.path(MTL_DIR, sprintf("predictions_mtl_aux_%s.parquet", target_col))))
  aux[, Date := as.Date(Date)]

  # Merge: 7 model probs + y + Date
  oos <- merge(p5[, .(Date, p_xgb, p_cat, p_rf, p_lstm, p_tft, y)],
                unc[, .(Date, p_mtl_unc)], by = "Date", all = TRUE)
  oos <- merge(oos, aux[, .(Date, p_mtl_aux)], by = "Date", all = TRUE)
  oos <- oos[!is.na(y) & !is.na(p_xgb) & !is.na(p_mtl_unc) & !is.na(p_mtl_aux)]
  setorder(oos, Date)
  cat(sprintf("[D9] OOS merged N=%d / events=%d (%.2f%%)\n",
              nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  M_NAMES <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft", "p_mtl_unc", "p_mtl_aux")
  M <- as.matrix(oos[, ..M_NAMES])
  Y <- oos$y

  # Individual OOS PR-AUC
  pr_ind <- sapply(seq_len(7), function(m) pr_auc(M[, m], Y))
  names(pr_ind) <- M_NAMES
  cat("\n[D9] Individual OOS PR-AUC:\n"); print(round(pr_ind, 4))

  # ── E1: EW7 ──
  p_E1 <- rowMeans(M, na.rm = TRUE)
  pa_E1 <- pr_auc(p_E1, Y)
  cat(sprintf("\n[E1 EW7] PR-AUC=%.4f\n", pa_E1))

  # ── E2: Weighted EW (GBDT 0.18 ×3 / Deep 0.13 ×2 / MTL 0.13 ×2) ──
  w_E2 <- c(0.18, 0.18, 0.18, 0.13, 0.13, 0.10, 0.10)
  w_E2 <- w_E2 / sum(w_E2)
  p_E2 <- as.numeric(M %*% w_E2)
  pa_E2 <- pr_auc(p_E2, Y)
  cat(sprintf("[E2 Weighted EW (GBDT↑/Deep/MTL)] PR-AUC=%.4f\n", pa_E2))

  # ── E3: Performance-weighted (softmax β=5) ──
  w_E3 <- softmax(pr_ind, beta = 5)
  p_E3 <- as.numeric(M %*% w_E3)
  pa_E3 <- pr_auc(p_E3, Y)
  cat(sprintf("[E3 Performance-weighted (softmax β=5)] PR-AUC=%.4f\n", pa_E3))
  cat(sprintf("  weights: %s\n", paste(sprintf("%.3f", w_E3), collapse = " ")))

  # ── E4: M2 Regime-Conditional Dynamic on 7-way ──
  cat("\n[E4 M2 Regime-Conditional Dynamic on 7-way]\n")
  feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")))
  feat[, Date := as.Date(Date)]
  oos_r <- merge(oos, feat[, .(Date, bbva_macro_composite)], by = "Date", all.x = TRUE)
  setorder(oos_r, Date)
  M_r <- as.matrix(oos_r[, ..M_NAMES]); Y_r <- oos_r$y

  train_macro <- oos_r$bbva_macro_composite[seq_len(min(2000, nrow(oos_r)))]
  q33 <- quantile(train_macro, 0.33, na.rm = TRUE)
  q67 <- quantile(train_macro, 0.67, na.rm = TRUE)
  oos_r[, regime := fcase(
    is.na(bbva_macro_composite), NA_character_,
    bbva_macro_composite <= q33, "bull",
    bbva_macro_composite >= q67, "bear",
    default = "sideways"
  )]
  Regime <- oos_r$regime

  p_E4 <- rep(NA_real_, nrow(oos_r))
  for (i in seq_len(nrow(oos_r))) {
    cur_reg <- Regime[i]
    if (is.na(cur_reg)) next
    cutoff <- i - PURGE; start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    in_reg <- which(Regime[start:cutoff] == cur_reg) + (start - 1)
    if (length(in_reg) < 30) {
      p_E4[i] <- sum(M_r[i, ] * w_E2); next  # fallback
    }
    pr_models <- sapply(seq_len(7), function(m) pr_auc(M_r[in_reg, m], Y_r[in_reg]))
    pr_models[is.na(pr_models)] <- 0
    w <- softmax(pr_models, beta = 5)
    p_E4[i] <- sum(M_r[i, ] * w)
  }
  pa_E4 <- pr_auc(p_E4, Y_r)
  cat(sprintf("  PR-AUC=%.4f\n", pa_E4))

  # Old baselines for reference
  baseline_5way_static_wew <- pr_auc((M[,1]+M[,2]+M[,3])/3 * 0.75 + (M[,4]+M[,5])/2 * 0.25, Y)
  baseline_v13_M2 <- 0.6078  # constant from v1.3

  cat("\n============================================================\n")
  cat(sprintf("[D9 SUMMARY] target=%s\n", target_col))
  cat(sprintf("  v1.2 baseline (5-way Weighted EW)   = 0.5814\n"))
  cat(sprintf("  v1.3 baseline (5-way M2 Regime)     = %.4f\n", baseline_v13_M2))
  cat(sprintf("  E1 EW7                              = %.4f %s\n", pa_E1, ifelse(pa_E1 > baseline_v13_M2, "★", "")))
  cat(sprintf("  E2 Weighted EW7                     = %.4f %s\n", pa_E2, ifelse(pa_E2 > baseline_v13_M2, "★", "")))
  cat(sprintf("  E3 Performance-weighted             = %.4f %s\n", pa_E3, ifelse(pa_E3 > baseline_v13_M2, "★", "")))
  cat(sprintf("  E4 M2 Regime Dynamic on 7-way       = %.4f %s\n", pa_E4, ifelse(pa_E4 > baseline_v13_M2, "★", "")))

  oos_r[, p_E1 := p_E1]; oos_r[, p_E2 := p_E2]; oos_r[, p_E3 := p_E3]; oos_r[, p_E4_dyn := p_E4]
  write_parquet(oos_r, file.path(OUT, sprintf("predictions_7way_%s.parquet", target_col)))

  list(target = target_col,
       PRAUC = c(EW7 = pa_E1, WEW7 = pa_E2, Perf = pa_E3, Dyn7 = pa_E4),
       v13_M2 = baseline_v13_M2)
}

res_q15 <- run_7way("y_tail_q15")
res_onset <- run_7way("y_onset")

cat("\n============================================================\n")
cat("[FINAL — D9 7-way Dynamic SUMMARY]\n")
print(rbind(data.table(target = "y_tail_q15", t(as.list(res_q15$PRAUC))),
            data.table(target = "y_onset", t(as.list(res_onset$PRAUC)))))
