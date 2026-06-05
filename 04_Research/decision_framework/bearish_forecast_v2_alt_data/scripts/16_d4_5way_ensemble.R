#==============================================================================
# 16_d4_5way_ensemble.R — D4 5-way ensemble (XGB + CatBoost + RF + LSTM + TFT)
#
# Combine 5 model OOS predictions:
#   GBDT 3-way (outputs/03_models/multi_algorithm/predictions_3way_*.parquet)
#   LSTM       (outputs/03_models/lstm/predictions_lstm_*.parquet)
#   Transformer(outputs/03_models/transformer/predictions_tft_*.parquet)
#
# 4 ensemble variants:
#   E1. EW5: 1/5 each
#   E2. Weighted EW: GBDT 0.25 each, Deep 0.125 each (GBDT 우월 반영)
#   E3. Performance-weighted: softmax(valid PR-AUC)
#   E4. Stack meta: logistic on 5 probs (valid → OOS)
#
# Output: outputs/03_models/5way_ensemble/predictions_5way.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
GBDT_DIR <- file.path(WS_DIR, "outputs/03_models/multi_algorithm")
LSTM_DIR <- file.path(WS_DIR, "outputs/03_models/lstm")
TFT_DIR <- file.path(WS_DIR, "outputs/03_models/transformer")
OUT_DIR <- file.path(WS_DIR, "outputs/03_models/5way_ensemble")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

run_5way <- function(target_col) {
  cat(sprintf("\n========== 5-way ensemble: %s ==========\n", target_col))

  # Load GBDT 3-way (has XGB + Cat + RF + EW + train/valid/oos)
  gbdt <- as.data.table(read_parquet(
    file.path(GBDT_DIR, sprintf("predictions_3way_%s.parquet", target_col))))
  gbdt[, Date := as.Date(Date)]
  # Load LSTM (OOS only)
  lstm_path <- file.path(LSTM_DIR, sprintf("predictions_lstm_%s.parquet", target_col))
  lstm <- as.data.table(read_parquet(lstm_path))
  lstm[, Date := as.Date(Date)]
  # Load Transformer (OOS only)
  tft_path <- file.path(TFT_DIR, sprintf("predictions_tft_%s.parquet", target_col))
  tft <- as.data.table(read_parquet(tft_path))
  tft[, Date := as.Date(Date)]

  # OOS merge
  oos_gbdt <- gbdt[split == "oos", .(Date, p_xgb, p_cat, p_rf, y)]
  oos <- merge(oos_gbdt, lstm[, .(Date, p_lstm)], by = "Date", all = TRUE)
  oos <- merge(oos, tft[, .(Date, p_tft)], by = "Date", all = TRUE)
  oos <- oos[!is.na(y) & !is.na(p_xgb) & !is.na(p_lstm) & !is.na(p_tft)]
  cat(sprintf("[D4] OOS merged N=%d / events=%d (%.2f%%)\n",
              nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  # E1: EW5
  oos[, p_ew5 := (p_xgb + p_cat + p_rf + p_lstm + p_tft) / 5]
  # E2: Weighted EW (GBDT 0.25 / Deep 0.125)
  oos[, p_wew := 0.25 * p_xgb + 0.25 * p_cat + 0.25 * p_rf + 0.125 * p_lstm + 0.125 * p_tft]

  # E3: Performance-weighted (softmax of valid PR-AUC)
  # Compute valid PR-AUC per model — need valid splits
  valid_gbdt <- gbdt[split == "valid", .(Date, p_xgb, p_cat, p_rf, y)]
  pr_xgb_v <- pr_auc(valid_gbdt$p_xgb, valid_gbdt$y)
  pr_cat_v <- pr_auc(valid_gbdt$p_cat, valid_gbdt$y)
  pr_rf_v  <- pr_auc(valid_gbdt$p_rf,  valid_gbdt$y)
  # LSTM/TFT valid not in OOS-only files — use small valid sample if possible
  # (training script saved OOS only, so for now use OOS PR-AUC as proxy)
  pr_xgb_o <- pr_auc(oos$p_xgb, oos$y)
  pr_cat_o <- pr_auc(oos$p_cat, oos$y)
  pr_rf_o  <- pr_auc(oos$p_rf,  oos$y)
  pr_lstm_o <- pr_auc(oos$p_lstm, oos$y)
  pr_tft_o  <- pr_auc(oos$p_tft,  oos$y)

  cat(sprintf("\n[D4] Individual OOS PR-AUC:\n"))
  cat(sprintf("  XGBoost:    %.4f\n", pr_xgb_o))
  cat(sprintf("  CatBoost:   %.4f\n", pr_cat_o))
  cat(sprintf("  Ranger RF:  %.4f\n", pr_rf_o))
  cat(sprintf("  LSTM:       %.4f\n", pr_lstm_o))
  cat(sprintf("  Transformer:%.4f\n", pr_tft_o))

  # Performance-weighted (use OOS for proxy — note: data leak risk, only for benchmark)
  # 보수적으로 valid PR-AUC만 활용 (GBDT만 valid 있고 LSTM/TFT는 OOS 추정값 사용)
  # 실용성 위해 단순 valid GBDT + assumed equal LSTM/TFT
  w_proxy <- c(pr_xgb_v, pr_cat_v, pr_rf_v, mean(c(pr_xgb_v, pr_cat_v, pr_rf_v)),
                mean(c(pr_xgb_v, pr_cat_v, pr_rf_v)))
  w_softmax <- exp(w_proxy * 5) / sum(exp(w_proxy * 5))
  cat(sprintf("\n[D4] Performance-weighted (softmax β=5) weights:\n"))
  cat(sprintf("  XGB=%.3f CAT=%.3f RF=%.3f LSTM=%.3f TFT=%.3f (sum=%.3f)\n",
              w_softmax[1], w_softmax[2], w_softmax[3], w_softmax[4], w_softmax[5], sum(w_softmax)))
  oos[, p_perf := w_softmax[1] * p_xgb + w_softmax[2] * p_cat + w_softmax[3] * p_rf +
                  w_softmax[4] * p_lstm + w_softmax[5] * p_tft]

  # E4: Stack meta (use validation period - GBDT only has valid, LSTM/TFT don't)
  # Skip E4 due to LSTM/TFT valid 부재. EW + Weighted + Performance만 비교.

  # Final PR-AUC
  pr_ew5  <- pr_auc(oos$p_ew5, oos$y)
  pr_wew  <- pr_auc(oos$p_wew, oos$y)
  pr_perf <- pr_auc(oos$p_perf, oos$y)
  pr_ew3  <- pr_auc((oos$p_xgb + oos$p_cat + oos$p_rf) / 3, oos$y)  # 3-way baseline

  cat(sprintf("\n[D4] Ensemble OOS PR-AUC:\n"))
  cat(sprintf("  GBDT 3-way EW (baseline): %.4f\n", pr_ew3))
  cat(sprintf("  EW5 (1/5 each):           %.4f %s\n", pr_ew5, ifelse(pr_ew5 > pr_ew3, "★", "")))
  cat(sprintf("  Weighted EW (GBDT 0.25):  %.4f %s\n", pr_wew, ifelse(pr_wew > pr_ew3, "★", "")))
  cat(sprintf("  Performance-weighted:     %.4f %s\n", pr_perf, ifelse(pr_perf > pr_ew3, "★", "")))

  write_parquet(oos, file.path(OUT_DIR, sprintf("predictions_5way_%s.parquet", target_col)))

  list(
    target = target_col,
    individual = c(xgb=pr_xgb_o, cat=pr_cat_o, rf=pr_rf_o, lstm=pr_lstm_o, tft=pr_tft_o),
    ensembles = c(ew3=pr_ew3, ew5=pr_ew5, wew=pr_wew, perf=pr_perf)
  )
}

cat("[D4] 5-way ensemble (XGB + CatBoost + RF + LSTM + Transformer)\n")
res_q15 <- run_5way("y_tail_q15")
res_onset <- run_5way("y_onset")

cat("\n============================================================\n")
cat("[D4 SUMMARY]\n")
cat(sprintf("y_tail_q15: GBDT3=%.4f / EW5=%.4f / WEW=%.4f / PERF=%.4f\n",
            res_q15$ensembles[1], res_q15$ensembles[2],
            res_q15$ensembles[3], res_q15$ensembles[4]))
cat(sprintf("y_onset:    GBDT3=%.4f / EW5=%.4f / WEW=%.4f / PERF=%.4f\n",
            res_onset$ensembles[1], res_onset$ensembles[2],
            res_onset$ensembles[3], res_onset$ensembles[4]))
cat(sprintf("\nOutput: %s\n", OUT_DIR))
