#==============================================================================
# WT-D20260508_012 — Regime-conditional KOSPI return diagnostic
#
# Purpose: regime_state별 conditional 평균/std/Sharpe 계산 → "regime indicator
#          가 실제로 KOSPI return distribution을 분리하는가" 정량 확인.
#          Codex C2 (rank_IC/ICIR 부재) 대응 — regime indicator-specific
#          diagnostic. AFT 2017 JF Eq.(29) "high-LJV days" 검증과 동일
#          methodology.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260508_012")

# Load regime_state daily timeseries (output from build_option_tail_regime.R)
ts <- as.data.table(read_parquet(
  file.path(ART_DIR, "regime_indicator_timeseries.parquet")))
ts[, Date := as.Date(Date)]

# Load KOSPI BM_Ret (daily)
rd <- as.data.table(read_parquet(
  file.path(PROJECT_ROOT, ".cache/rawdata.parquet"),
  col_select = c("Date", "BM_Ret")))
rd <- unique(rd[!is.na(BM_Ret)])
setkey(rd, Date)
setkey(ts, Date)

# join: ts.regime_state @ Date ↔ rd.BM_Ret @ same Date
# regime_state already lagged (regime_state_t = f(O_{t-1}))
# To compute "expected KOSPI return CONDITIONAL on regime announced before
# market open at t", we use ts.regime_state[t] as predictor of rd.BM_Ret[t].
joined <- ts[rd, on = "Date"]
joined <- joined[!is.na(regime_state) & !is.na(BM_Ret)]

cat(sprintf("[diag] %d regime × KOSPI joined days\n", nrow(joined)))

# Per-state conditional stats
diag_tbl <- joined[, .(
  n_days = .N,
  mean_daily_ret = mean(BM_Ret),
  std_daily_ret = sd(BM_Ret),
  median_daily_ret = median(BM_Ret),
  q05 = quantile(BM_Ret, 0.05),
  q95 = quantile(BM_Ret, 0.95),
  skew = (function(x) {
    m <- mean(x); n <- length(x)
    n / ((n - 1) * (n - 2)) * sum(((x - m) / sd(x)) ^ 3)
  })(BM_Ret),
  ann_ret = mean(BM_Ret) * 252,
  ann_vol = sd(BM_Ret) * sqrt(252),
  sharpe_ann = mean(BM_Ret) / sd(BM_Ret) * sqrt(252),
  hit_neg = mean(BM_Ret < 0),
  hit_neg_2pct = mean(BM_Ret < -0.02)
), by = regime_state][order(factor(regime_state,
                                     levels = c("PEACE", "WARNING", "TAIL_STRESS")))]

cat("\n[regime-conditional KOSPI diagnostic]\n")
print(diag_tbl)

# Overall (unconditional)
overall <- data.table(
  regime_state = "OVERALL",
  n_days = nrow(joined),
  mean_daily_ret = mean(joined$BM_Ret),
  std_daily_ret = sd(joined$BM_Ret),
  median_daily_ret = median(joined$BM_Ret),
  q05 = quantile(joined$BM_Ret, 0.05),
  q95 = quantile(joined$BM_Ret, 0.95),
  skew = (function(x) {
    m <- mean(x); n <- length(x)
    n / ((n - 1) * (n - 2)) * sum(((x - m) / sd(x)) ^ 3)
  })(joined$BM_Ret),
  ann_ret = mean(joined$BM_Ret) * 252,
  ann_vol = sd(joined$BM_Ret) * sqrt(252),
  sharpe_ann = mean(joined$BM_Ret) / sd(joined$BM_Ret) * sqrt(252),
  hit_neg = mean(joined$BM_Ret < 0),
  hit_neg_2pct = mean(joined$BM_Ret < -0.02)
)
diag_full <- rbind(diag_tbl, overall, fill = TRUE)
print(diag_full)

# Save parquet
write_parquet(diag_full, file.path(ART_DIR, "regime_state_summary.parquet"))
cat(sprintf("\n[save] regime_state_summary.parquet (%d rows)\n", nrow(diag_full)))

# Significance test: TAIL_STRESS vs PEACE difference (Welch t-test)
peace <- joined[regime_state == "PEACE", BM_Ret]
stress <- joined[regime_state == "TAIL_STRESS", BM_Ret]
warn <- joined[regime_state == "WARNING", BM_Ret]
tt_stress_vs_peace <- t.test(stress, peace)
tt_warn_vs_peace <- t.test(warn, peace)

cat("\n[diff test] TAIL_STRESS vs PEACE (Welch):\n")
cat(sprintf("  Stress mean: %.4f, Peace mean: %.4f, diff: %.4f\n",
            mean(stress), mean(peace), mean(stress) - mean(peace)))
cat(sprintf("  t = %.3f, p = %.4f, df = %.1f\n",
            tt_stress_vs_peace$statistic, tt_stress_vs_peace$p.value,
            tt_stress_vs_peace$parameter))

# Save JSON diagnostic
diag_json <- list(
  task_id = "WT-D20260508_012",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  type = "regime_state conditional KOSPI return analysis",
  reference = "Andersen-Fusari-Todorov 2017 JF Eq.(29) 'high-LJV days' methodology",
  per_state = lapply(seq_len(nrow(diag_full)), function(i) {
    as.list(diag_full[i])
  }),
  diff_tests = list(
    TAIL_STRESS_vs_PEACE = list(
      mean_TAIL_STRESS = mean(stress),
      mean_PEACE = mean(peace),
      diff = mean(stress) - mean(peace),
      t_stat = unname(tt_stress_vs_peace$statistic),
      p_value = tt_stress_vs_peace$p.value,
      df = unname(tt_stress_vs_peace$parameter),
      conclusion = if (tt_stress_vs_peace$p.value < 0.01) "HIGHLY_SIGNIFICANT"
                   else if (tt_stress_vs_peace$p.value < 0.05) "SIGNIFICANT"
                   else "INSIGNIFICANT"
    ),
    WARNING_vs_PEACE = list(
      mean_WARNING = mean(warn),
      mean_PEACE = mean(peace),
      diff = mean(warn) - mean(peace),
      t_stat = unname(tt_warn_vs_peace$statistic),
      p_value = tt_warn_vs_peace$p.value,
      df = unname(tt_warn_vs_peace$parameter)
    )
  )
)

write_json(diag_json,
           file.path(ART_DIR, "regime_conditional_diagnostic.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("[save] regime_conditional_diagnostic.json\n"))
