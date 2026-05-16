#!/usr/bin/env Rscript
# WT-D20260514_009 Step 3: Evaluate ML predictions against all graduation gates
# Inputs: walk_forward_predictions.parquet
# Outputs:
#   - alpha_validation.json (full evaluation suite)
#   - alpha_scores.parquet (best model output for downstream stages)
#   - orthogonality_six_axis.json
#   - str1715_overlap_audit.json
#   - feature_importance_top50.csv

suppressMessages({
  library(arrow); library(data.table); library(dplyr); library(lubridate)
  library(sandwich); library(lmtest); library(jsonlite)
})

WT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(WT_ROOT)
OUT_DIR <- "stage_artifacts/WT_D20260514_009"

source(file.path(OUT_DIR, "evaluation_helpers.R"))

cat("\n=== Step 3: Evaluate ML predictions ===\n")
t_overall <- Sys.time()

cat("[1/8] Loading predictions...\n")
preds <- as.data.table(read_parquet(file.path(OUT_DIR, "walk_forward_predictions.parquet")))
preds[, sig_date := as.Date(sig_date)]
cat(sprintf("  preds: %s rows × %d cols (%d sig_dates)\n",
            format(nrow(preds), big.mark=","), ncol(preds), uniqueN(preds$sig_date)))

# Pred columns
pred_cols <- intersect(names(preds), c("pred_lasso","pred_en","pred_xgb","pred_rf","pred_ensemble"))
cat("  pred_cols:", paste(pred_cols, collapse=", "), "\n")

# Lockbox split: last 12 sig_dates
LOCKBOX_SIZE <- 12L
sig_dates_oos <- sort(unique(preds$sig_date))
n_oos <- length(sig_dates_oos)
lockbox_start <- sig_dates_oos[max(1, n_oos - LOCKBOX_SIZE + 1L)]
lockbox_end <- sig_dates_oos[n_oos]
is_lock <- preds$sig_date >= lockbox_start

cat(sprintf("  OOS range: %s..%s (%d sig_dates)\n", sig_dates_oos[1], sig_dates_oos[n_oos], n_oos))
cat(sprintf("  Lockbox: %s..%s (last %d sig_dates, %d rows)\n",
            lockbox_start, lockbox_end, LOCKBOX_SIZE, sum(is_lock)))

# ===========================================================
# [2/8] Rank IC + ICIR for each model
# ===========================================================
cat("\n[2/8] Computing rank IC + ICIR per model...\n")
ic_summary <- list()
for (pc in pred_cols) {
  full_ic <- compute_rank_ic(preds, pc)
  pre_lock_ic <- compute_rank_ic(preds[!is_lock], pc)
  lock_ic <- compute_rank_ic(preds[is_lock], pc)
  ic_summary[[pc]] <- list(
    full = full_ic[c("mean_ic","median_ic","sd_ic","icir","pct_positive","n_sig_dates")],
    pre_lockbox = pre_lock_ic[c("mean_ic","median_ic","sd_ic","icir","pct_positive","n_sig_dates")],
    lockbox = lock_ic[c("mean_ic","median_ic","sd_ic","icir","pct_positive","n_sig_dates")]
  )
  cat(sprintf("  %s: full IC=%+.4f ICIR=%+.3f (n=%d) | pre_lockbox IC=%+.4f ICIR=%+.3f | lockbox IC=%+.4f ICIR=%+.3f\n",
              pc, full_ic$mean_ic, full_ic$icir, full_ic$n_sig_dates,
              pre_lock_ic$mean_ic, pre_lock_ic$icir,
              lock_ic$mean_ic, lock_ic$icir))
}

# Choose best model by FULL ICIR
icir_vec <- sapply(pred_cols, function(pc) ic_summary[[pc]]$full$icir)
best_model <- pred_cols[which.max(icir_vec)]
cat(sprintf("\n  >>> Best model by full ICIR: %s (ICIR=%+.3f, IC=%+.4f)\n",
            best_model, icir_vec[best_model], ic_summary[[best_model]]$full$mean_ic))

# ===========================================================
# [3/8] Decile monotonicity (best model)
# ===========================================================
cat("\n[3/8] Computing decile monotonicity (best model)...\n")
mono_full <- compute_decile_monotonicity(preds, best_model)
mono_pre <- compute_decile_monotonicity(preds[!is_lock], best_model)
mono_lock <- compute_decile_monotonicity(preds[is_lock], best_model)
cat("  Decile means (full OOS):\n")
print(mono_full$decile_means)
cat(sprintf("  Monotonicity corr full=%.3f | pre_lockbox=%.3f | lockbox=%.3f\n",
            mono_full$monotonicity_corr, mono_pre$monotonicity_corr, mono_lock$monotonicity_corr))
cat(sprintf("  Q10-Q1 spread full=%.4f | pre_lockbox=%.4f | lockbox=%.4f\n",
            mono_full$q10_q1_spread, mono_pre$q10_q1_spread, mono_lock$q10_q1_spread))

# Also compute monotonicity for all models (for table)
mono_all_models <- list()
for (pc in pred_cols) {
  m <- compute_decile_monotonicity(preds, pc)
  mono_all_models[[pc]] <- list(
    monotonicity_corr = m$monotonicity_corr,
    q10_q1_spread = m$q10_q1_spread,
    decile_means = m$decile_means
  )
}

# ===========================================================
# [4/8] Long-short monthly returns + KR factor regressions (Harvey-t)
# ===========================================================
cat("\n[4/8] Building KR FF factors + Harvey 5-spec regressions...\n")
# Build LS monthly for best_model
ls_monthly <- build_ls_monthly(preds, best_model)
lo_monthly <- build_long_only_monthly(preds, best_model)
cat(sprintf("  LS monthly returns: %d months\n", nrow(ls_monthly)))
cat(sprintf("  LS mean=%.4f sd=%.4f SR=%.3f (annualized %.3f)\n",
            mean(ls_monthly$LS, na.rm=TRUE),
            sd(ls_monthly$LS, na.rm=TRUE),
            mean(ls_monthly$LS)/sd(ls_monthly$LS),
            mean(ls_monthly$LS)/sd(ls_monthly$LS)*sqrt(12)))
cat(sprintf("  LongOnly Q10 mean=%.4f sd=%.4f SR=%.3f (annualized %.3f)\n",
            mean(lo_monthly$ret_top, na.rm=TRUE),
            sd(lo_monthly$ret_top, na.rm=TRUE),
            mean(lo_monthly$ret_top)/sd(lo_monthly$ret_top),
            mean(lo_monthly$ret_top)/sd(lo_monthly$ret_top)*sqrt(12)))

cat("\n  Building KR FF5/Carhart factors (this may take a minute)...\n")
kr_fac <- tryCatch(
  build_kr_factors_monthly(date_min = "2016-01-01", date_max = "2026-05-31"),
  error = function(e) {cat("  WARN: factor build failed:", conditionMessage(e), "\n"); NULL})

harvey_LS <- NULL; harvey_LO <- NULL
if (!is.null(kr_fac)) {
  cat(sprintf("  KR factors: %d months (cols: %s)\n", nrow(kr_fac), paste(names(kr_fac), collapse=", ")))
  cat("\n  Harvey 5-spec LS (Q10-Q1):\n")
  harvey_LS <- harvey_5spec(ls_monthly, kr_fac, ret_col = "LS", nw_lag = 6L)
  for (sp in names(harvey_LS$specs)) {
    r <- harvey_LS$specs[[sp]]
    cat(sprintf("    %-8s: t_NW=%+.3f (p=%.4f) alpha_m=%+.4f r2=%.4f pass_t3=%s\n",
                r$spec, r$t_NW, r$p_NW, r$alpha_monthly, r$r_squared, r$pass_t3))
  }
  cat(sprintf("    >>> LS pass count: %d / %d (3of5 = %s)\n",
              harvey_LS$pass_count, harvey_LS$total_specs, harvey_LS$pass_3of5))

  cat("\n  Harvey 5-spec Long-Only Q10:\n")
  lo_dt <- lo_monthly[, .(sig_date, LS = ret_top)]
  harvey_LO <- harvey_5spec(lo_dt, kr_fac, ret_col = "LS", nw_lag = 6L)
  for (sp in names(harvey_LO$specs)) {
    r <- harvey_LO$specs[[sp]]
    cat(sprintf("    %-8s: t_NW=%+.3f (p=%.4f) alpha_m=%+.4f r2=%.4f pass_t3=%s\n",
                r$spec, r$t_NW, r$p_NW, r$alpha_monthly, r$r_squared, r$pass_t3))
  }
  cat(sprintf("    >>> LO pass count: %d / %d (3of5 = %s)\n",
              harvey_LO$pass_count, harvey_LO$total_specs, harvey_LO$pass_3of5))
}

# ===========================================================
# [5/8] DSR (Bailey-Lopez de Prado)
# ===========================================================
cat("\n[5/8] Computing DSR (Bailey-Lopez de Prado, N_trials=5)...\n")
dsr_LS <- compute_dsr(ls_monthly$LS, N_trials = 5L, ann_factor = 12)
dsr_LO <- compute_dsr(lo_monthly$ret_top, N_trials = 5L, ann_factor = 12)
cat(sprintf("  LS DSR: %.4f | z=%.3f | SR_hat_ann=%.3f | SR_max_exp_ann=%.3f | N=5 T=%d\n",
            dsr_LS$dsr, dsr_LS$z, dsr_LS$sr_hat_annual, dsr_LS$sr_max_expected_annual, dsr_LS$T))
cat(sprintf("  LO DSR: %.4f | z=%.3f | SR_hat_ann=%.3f | SR_max_exp_ann=%.3f | N=5 T=%d\n",
            dsr_LO$dsr, dsr_LO$z, dsr_LO$sr_hat_annual, dsr_LO$sr_max_expected_annual, dsr_LO$T))

# ===========================================================
# [6/8] Pareto 6-axis orthogonality vs STR_1715 score_eff
# ===========================================================
cat("\n[6/8] Pareto 6-axis vs STR_1715...\n")
str1715_path <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
str1715 <- tryCatch({
  s <- as.data.table(read_parquet(str1715_path))
  s[, sig_date := as.Date(Date)]
  s
}, error=function(e) {cat("WARN: STR_1715 load fail:", conditionMessage(e), "\n"); NULL})

ortho_result <- NULL; portfolio_cor <- NULL
if (!is.null(str1715)) {
  cat(sprintf("  STR_1715 loaded: %d rows, %d sig_dates\n",
              nrow(str1715), uniqueN(str1715$sig_date)))
  # Axes 1-5 (alpha-vector level)
  ortho_result <- pareto_6axis(preds, str1715,
                                key_cols=c("sig_date","Ticker"),
                                ml_col = best_model, ref_col = "score_eff")
  cat(sprintf("  Alpha-vector axes:\n"))
  cat(sprintf("    1. Pearson cor (pooled): %+.4f\n", ortho_result$pearson))
  cat(sprintf("    2. Spearman cor (pooled): %+.4f\n", ortho_result$spearman))
  cat(sprintf("    3. Kendall tau (pooled): %+.4f\n", ortho_result$kendall))
  cat(sprintf("    4. Lower-tail dependence (q10): %+.4f\n", ortho_result$tdc_lower_q10))
  cat(sprintf("    4b. Upper-tail dependence (q10): %+.4f\n", ortho_result$tdc_upper_q10))
  cat(sprintf("    5. Mean per-sig_date Spearman: %+.4f\n", ortho_result$mean_per_sigdate_spearman))

  # Axis 6: portfolio realized cor — build Q10 EW return series for both and ts-correlate
  ml_q10 <- build_long_only_monthly(preds, best_model)
  str_dt <- str1715[!is.na(score_eff) & !is.na(Ret_1m), .(sig_date, Ticker, score_eff, ret_real = Ret_1m)]
  setorder(str_dt, sig_date, -score_eff)
  str_dt[, decile := cut(frank(score_eff, na.last="keep")/.N,
                          breaks=seq(0,1,length.out=11),
                          labels=1:10, include.lowest=TRUE), by=sig_date]
  str_q10 <- str_dt[decile == 10, .(ret_str = mean(ret_real, na.rm=TRUE)), by=sig_date]
  str_q10[, sig_date := as.Date(sig_date)]
  ml_q10[, sig_date := as.Date(sig_date)]
  ts <- merge(ml_q10[, .(sig_date, ret_ml = ret_top)],
              str_q10[, .(sig_date, ret_str)], by="sig_date")
  ts <- ts[!is.na(ret_ml) & !is.na(ret_str)]
  if (nrow(ts) >= 12) {
    portfolio_cor <- cor(ts$ret_ml, ts$ret_str, method="pearson")
    portfolio_cor_spearman <- cor(ts$ret_ml, ts$ret_str, method="spearman")
    cat(sprintf("    6. Portfolio realized cor (Q10 EW, n=%d months): Pearson=%+.4f Spearman=%+.4f\n",
                nrow(ts), portfolio_cor, portfolio_cor_spearman))
  } else cat("    6. Portfolio realized cor: SKIP (too few months)\n")

  ortho_result$portfolio_realized_cor_pearson <- portfolio_cor
  ortho_result$portfolio_n_months <- nrow(ts)
}

# ===========================================================
# [7/8] Sub-period stability
# ===========================================================
cat("\n[7/8] Sub-period stability...\n")
stab <- compute_subperiod_stability(preds, best_model)
print(stab$by_period)
cat(sprintf("  Positive periods: %d/%d | Stability ratio (min/max IC): %+.3f\n",
            stab$positive_periods, stab$n_periods, stab$stability_ratio))

# ===========================================================
# [7.5/8] STR_1715 overlap audit (feature importance top-50 — STR_1715 7 factors check)
# ===========================================================
cat("\n[7.5/8] STR_1715 overlap audit (XGB top features)...\n")
fi_path <- file.path(OUT_DIR, "feature_importance_per_fold.rds")
fi_all <- if (file.exists(fi_path)) readRDS(fi_path) else NULL
str1715_factors <- c("fdb_m_C01_SUE","fdb_m_C02_EPS_Chg_1m","fdb_m_C04_ESBR",
                      "fdb_m_C06_TP_Gap","fdb_m_Q07_Earnings_Stability",
                      "fdb_m_M08_Residual_Mom","fdb_m_Q25_Ohlson_O")
overlap_top10 <- NULL
overlap_top50 <- NULL
top_features_xgb <- NULL
if (!is.null(fi_all) && length(fi_all) > 0) {
  # Aggregate XGB importance across folds
  imp_list <- lapply(fi_all, function(x) x$xgb_importance)
  imp_list <- imp_list[!sapply(imp_list, is.null)]
  if (length(imp_list) > 0) {
    imp_all <- rbindlist(imp_list, idcol="fold_id")
    agg_imp <- imp_all[, .(mean_gain = mean(Gain, na.rm=TRUE),
                            n_folds = .N), by=Feature]
    setorder(agg_imp, -mean_gain)
    top_features_xgb <- head(agg_imp, 50)
    fwrite(top_features_xgb, file.path(OUT_DIR, "feature_importance_top50.csv"))
    overlap_top10 <- sum(head(agg_imp$Feature, 10) %in% str1715_factors)
    overlap_top50 <- sum(head(agg_imp$Feature, 50) %in% str1715_factors)
    cat(sprintf("  XGB top-10 features: %s\n", paste(head(agg_imp$Feature, 10), collapse=", ")))
    cat(sprintf("  STR_1715 H1 7 factors overlap in top-10: %d/10\n", overlap_top10))
    cat(sprintf("  STR_1715 H1 7 factors overlap in top-50: %d/50\n", overlap_top50))
  }
}

# ===========================================================
# [8/8] Save outputs (alpha_validation.json + alpha_scores.parquet)
# ===========================================================
cat("\n[8/8] Saving outputs...\n")

# alpha_scores: use best_model predictions on full OOS
alpha_scores <- preds[, c("sig_date","Ticker", best_model), with=FALSE]
setnames(alpha_scores, best_model, "alpha_score")
alpha_scores <- alpha_scores[!is.na(alpha_score)]
# Cross-section z-score within sig_date (final standardization for downstream)
alpha_scores[, alpha_score_z := scale(alpha_score)[,1], by=sig_date]
alpha_scores[, alpha_score := alpha_score_z]; alpha_scores[, alpha_score_z := NULL]
write_parquet(alpha_scores, file.path(OUT_DIR, "alpha_scores.parquet"))
cat(sprintf("  alpha_scores.parquet (%.1f MB, %d rows)\n",
            file.size(file.path(OUT_DIR,"alpha_scores.parquet"))/1024^2,
            nrow(alpha_scores)))

# alpha_validation.json
val <- list(
  task_id = "WT-D20260514_009",
  step = "step3_evaluate",
  evaluation_date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  best_model = best_model,
  best_model_full_icir = unname(icir_vec[best_model]),
  ic_summary = ic_summary,
  decile_monotonicity = list(
    full_oos = list(corr = mono_full$monotonicity_corr,
                    q10_q1_spread = mono_full$q10_q1_spread,
                    decile_means = mono_full$decile_means),
    pre_lockbox = list(corr = mono_pre$monotonicity_corr,
                       q10_q1_spread = mono_pre$q10_q1_spread),
    lockbox = list(corr = mono_lock$monotonicity_corr,
                   q10_q1_spread = mono_lock$q10_q1_spread),
    all_models = mono_all_models
  ),
  long_short_monthly = list(
    n_months = nrow(ls_monthly),
    mean = mean(ls_monthly$LS, na.rm=TRUE),
    sd = sd(ls_monthly$LS, na.rm=TRUE),
    sr_monthly = mean(ls_monthly$LS, na.rm=TRUE) / sd(ls_monthly$LS, na.rm=TRUE),
    sr_annualized = mean(ls_monthly$LS, na.rm=TRUE) / sd(ls_monthly$LS, na.rm=TRUE) * sqrt(12)
  ),
  long_only_q10_monthly = list(
    n_months = nrow(lo_monthly),
    mean = mean(lo_monthly$ret_top, na.rm=TRUE),
    sd = sd(lo_monthly$ret_top, na.rm=TRUE),
    sr_monthly = mean(lo_monthly$ret_top, na.rm=TRUE) / sd(lo_monthly$ret_top, na.rm=TRUE),
    sr_annualized = mean(lo_monthly$ret_top, na.rm=TRUE) / sd(lo_monthly$ret_top, na.rm=TRUE) * sqrt(12)
  ),
  harvey_5spec_LS = harvey_LS,
  harvey_5spec_LO = harvey_LO,
  dsr_LS = dsr_LS,
  dsr_LO = dsr_LO,
  orthogonality_pareto_6_axis = ortho_result,
  subperiod_stability = stab,
  str1715_overlap_audit = list(
    str1715_factors = str1715_factors,
    overlap_in_xgb_top10 = overlap_top10,
    overlap_in_xgb_top50 = overlap_top50,
    interpretation = if (!is.null(overlap_top50))
      ifelse(overlap_top50 >= 5, "HIGH overlap - STR_1715 dominance suspected",
             ifelse(overlap_top50 >= 3, "MODERATE overlap - some component reuse",
                    "LOW overlap - independent feature set"))
      else "could not compute"
  ),
  graduation_gate_check = list(
    gate_1_rank_ic_ge_0_04 = list(
      threshold = 0.04,
      observed = unname(sapply(pred_cols, function(p) ic_summary[[p]]$full$mean_ic)),
      best_observed = ic_summary[[best_model]]$full$mean_ic,
      pass = ic_summary[[best_model]]$full$mean_ic >= 0.04
    ),
    gate_2_icir_ge_0_20 = list(
      threshold = 0.20,
      observed = unname(sapply(pred_cols, function(p) ic_summary[[p]]$full$icir)),
      best_observed = ic_summary[[best_model]]$full$icir,
      pass = ic_summary[[best_model]]$full$icir >= 0.20
    ),
    gate_3_harvey_t_3of5 = list(
      threshold = "3/5 specs pass |t_NW| > 3.0",
      LS_pass_count = if (!is.null(harvey_LS)) harvey_LS$pass_count else NA,
      LS_pass = if (!is.null(harvey_LS)) harvey_LS$pass_3of5 else NA,
      LO_pass_count = if (!is.null(harvey_LO)) harvey_LO$pass_count else NA,
      LO_pass = if (!is.null(harvey_LO)) harvey_LO$pass_3of5 else NA
    ),
    gate_4_dsr_ge_0_5 = list(
      threshold = 0.5,
      observed_LS = dsr_LS$dsr,
      observed_LO = dsr_LO$dsr,
      pass_LS = !is.na(dsr_LS$dsr) && dsr_LS$dsr >= 0.5,
      pass_LO = !is.na(dsr_LO$dsr) && dsr_LO$dsr >= 0.5
    ),
    gate_5_monotonicity_ge_0_70 = list(
      threshold = 0.70,
      observed_full = mono_full$monotonicity_corr,
      pass = mono_full$monotonicity_corr >= 0.70
    ),
    gate_6_pareto_cor_lt_0_40 = list(
      threshold = 0.40,
      observed_alpha_pooled_pearson = if (!is.null(ortho_result)) ortho_result$pearson else NA,
      observed_alpha_pooled_spearman = if (!is.null(ortho_result)) ortho_result$spearman else NA,
      observed_mean_per_sigdate_spearman = if (!is.null(ortho_result)) ortho_result$mean_per_sigdate_spearman else NA,
      observed_portfolio_realized_cor = if (!is.null(ortho_result)) ortho_result$portfolio_realized_cor_pearson else NA,
      pass_alpha_pearson = !is.null(ortho_result) && abs(ortho_result$pearson) < 0.40,
      pass_portfolio_realized = !is.null(portfolio_cor) && abs(portfolio_cor) < 0.40
    ),
    gate_7_subperiod_stability_ge_0_5 = list(
      threshold = 0.5,
      observed = stab$stability_ratio,
      positive_periods = stab$positive_periods,
      pass = !is.na(stab$stability_ratio) && stab$stability_ratio >= 0.5 && stab$positive_periods >= 2
    )
  )
)

write_json(val, file.path(OUT_DIR, "alpha_validation.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=6)
cat("  alpha_validation.json saved\n")

# Save orthogonality + str1715_overlap separately
if (!is.null(ortho_result)) {
  write_json(ortho_result, file.path(OUT_DIR, "orthogonality_six_axis.json"),
             auto_unbox=TRUE, pretty=TRUE, na="null", digits=6)
  cat("  orthogonality_six_axis.json saved\n")
}

write_json(val$str1715_overlap_audit, file.path(OUT_DIR, "str1715_overlap_audit.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=6)
cat("  str1715_overlap_audit.json saved\n")

# Walk-forward CV scores (per-fold mean IC) parquet
cv_scores <- data.table()
for (pc in pred_cols) {
  per_sd <- compute_rank_ic(preds, pc)$ic_by_sd
  per_sd[, model := pc]
  cv_scores <- rbind(cv_scores, per_sd)
}
write_parquet(cv_scores, file.path(OUT_DIR, "walk_forward_cv_scores.parquet"))
cat("  walk_forward_cv_scores.parquet saved\n")

cat(sprintf("\n=== Step 3 DONE %.1f min ===\n",
            as.numeric(difftime(Sys.time(), t_overall, units="mins"))))

# Summary print
cat("\n============================================\n")
cat("GRADUATION GATE SUMMARY\n")
cat("============================================\n")
g <- val$graduation_gate_check
cat(sprintf("Gate 1 rank_IC>=0.04: %s (best=%+.4f, threshold=%.2f)\n",
            ifelse(g$gate_1_rank_ic_ge_0_04$pass, "PASS", "FAIL"),
            g$gate_1_rank_ic_ge_0_04$best_observed, 0.04))
cat(sprintf("Gate 2 ICIR>=0.20:    %s (best=%+.3f, threshold=%.2f)\n",
            ifelse(g$gate_2_icir_ge_0_20$pass, "PASS", "FAIL"),
            g$gate_2_icir_ge_0_20$best_observed, 0.20))
cat(sprintf("Gate 3 Harvey 3/5:   LS=%s (%s/5), LO=%s (%s/5)\n",
            ifelse(isTRUE(g$gate_3_harvey_t_3of5$LS_pass), "PASS", "FAIL"),
            as.character(g$gate_3_harvey_t_3of5$LS_pass_count),
            ifelse(isTRUE(g$gate_3_harvey_t_3of5$LO_pass), "PASS", "FAIL"),
            as.character(g$gate_3_harvey_t_3of5$LO_pass_count)))
cat(sprintf("Gate 4 DSR>=0.5:     LS=%s (%.3f), LO=%s (%.3f)\n",
            ifelse(g$gate_4_dsr_ge_0_5$pass_LS, "PASS", "FAIL"),
            ifelse(is.na(g$gate_4_dsr_ge_0_5$observed_LS), 0, g$gate_4_dsr_ge_0_5$observed_LS),
            ifelse(g$gate_4_dsr_ge_0_5$pass_LO, "PASS", "FAIL"),
            ifelse(is.na(g$gate_4_dsr_ge_0_5$observed_LO), 0, g$gate_4_dsr_ge_0_5$observed_LO)))
cat(sprintf("Gate 5 Monotonicity>=0.70: %s (%+.3f, threshold=%.2f)\n",
            ifelse(g$gate_5_monotonicity_ge_0_70$pass, "PASS", "FAIL"),
            g$gate_5_monotonicity_ge_0_70$observed_full, 0.70))
cat(sprintf("Gate 6 Pareto cor<0.40: alpha_pearson=%s (%+.4f), portfolio_realized=%s (%+.4f)\n",
            ifelse(isTRUE(g$gate_6_pareto_cor_lt_0_40$pass_alpha_pearson), "PASS", "FAIL"),
            ifelse(is.na(g$gate_6_pareto_cor_lt_0_40$observed_alpha_pooled_pearson), 0, g$gate_6_pareto_cor_lt_0_40$observed_alpha_pooled_pearson),
            ifelse(isTRUE(g$gate_6_pareto_cor_lt_0_40$pass_portfolio_realized), "PASS", "FAIL"),
            ifelse(is.na(g$gate_6_pareto_cor_lt_0_40$observed_portfolio_realized_cor), 0, g$gate_6_pareto_cor_lt_0_40$observed_portfolio_realized_cor)))
cat(sprintf("Gate 7 Subperiod>=0.5: %s (ratio=%+.3f, positive=%d/3)\n",
            ifelse(g$gate_7_subperiod_stability_ge_0_5$pass, "PASS", "FAIL"),
            ifelse(is.na(g$gate_7_subperiod_stability_ge_0_5$observed), 0, g$gate_7_subperiod_stability_ge_0_5$observed),
            g$gate_7_subperiod_stability_ge_0_5$positive_periods))
cat("============================================\n")
