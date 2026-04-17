source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/regime_kpi.R")
source("02_Infrastructure/telegram_notify.R")
library(data.table); library(arrow)

cat("=== Regime KPI Evaluation: v1 vs v2 ===\n")

# Load regime data
regime <- as.data.table(read_parquet(FRED_REGIME_CACHE))
setorder(regime, Date)

# Load benchmark
res <- load_rawdata(use_cache = TRUE)
bm <- unique(res$BM_DT[, .(Date, BM_Ret)])
setorder(bm, Date)
bm[, YM := format(Date, "%Y-%m")]
bm_m <- bm[, .(Ret = prod(1 + BM_Ret, na.rm=TRUE) - 1), by = YM]
bm_m[, Date := as.Date(cut(as.Date(paste0(YM,"-01")) + 31, "month")) - 1]
setorder(bm_m, Date)

# Reconstruct v1 scores
regime[, v1_score := 0L]
if ("VIX_Regime" %in% names(regime))
  regime[, v1_score := v1_score + fifelse(!is.na(VIX_Regime) & VIX_Regime=="crisis", 30L,
    fifelse(!is.na(VIX_Regime) & VIX_Regime=="elevated", 15L, 0L))]
if ("YC_Inversion" %in% names(regime))
  regime[, v1_score := v1_score + fifelse(!is.na(YC_Inversion) & YC_Inversion, 25L, 0L)]
if ("Credit_Stress" %in% names(regime))
  regime[, v1_score := v1_score + fifelse(!is.na(Credit_Stress) & Credit_Stress, 25L, 0L)]
if ("KRW_Stress" %in% names(regime))
  regime[, v1_score := v1_score + fifelse(!is.na(KRW_Stress) & KRW_Stress, 20L, 0L)]

# v1 signal
v1_signal <- regime[, .(Date, Score = v1_score)]
v1_signal[, Action := fifelse(Score >= 30, "SKIP", fifelse(Score >= 15, "HALF", "FULL"))]

# v2 signal (current Macro_Risk_Score)
v2_signal <- regime[, .(Date, Score = Macro_Risk_Score)]
v2_signal[, Action := fifelse(Score >= 40, "SKIP", fifelse(Score >= 10, "HALF", "FULL"))]

# v2 with v1 thresholds (for fair comparison)
v2_v1thresh <- regime[, .(Date, Score = Macro_Risk_Score)]
v2_v1thresh[, Action := fifelse(Score >= 30, "SKIP", fifelse(Score >= 15, "HALF", "FULL"))]

# Evaluate each
cat("\n--- v1 (4-axis, H15/S30) ---\n")
eval_v1 <- regime_evaluate(v1_signal, bm_m, "v1_4axis")
cat(sprintf("  SIR: %.3f | DAS: %.1f/100\n", eval_v1$sir_full, eval_v1$das))

cat("\n--- v2 (9-axis, H10/S40) ---\n")
eval_v2 <- regime_evaluate(v2_signal, bm_m, "v2_9axis_H10S40")
cat(sprintf("  SIR: %.3f | DAS: %.1f/100\n", eval_v2$sir_full, eval_v2$das))

cat("\n--- v2 (9-axis, H15/S30 for comparison) ---\n")
eval_v2b <- regime_evaluate(v2_v1thresh, bm_m, "v2_9axis_H15S30")
cat(sprintf("  SIR: %.3f | DAS: %.1f/100\n", eval_v2b$sir_full, eval_v2b$das))

# Compare
models <- list(v1_4axis = v1_signal, v2_H10S40 = v2_signal, v2_H15S30 = v2_v1thresh)
compare <- regime_compare(models, bm_m)
print(compare)

# Chart
out_dir <- file.path(PROJECT_ROOT, "research_output", "regime_analysis")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

# Generate charts for each model
for (nm in names(list(v1=eval_v1, v2=eval_v2, v2b=eval_v2b))) {
  ev <- list(v1=eval_v1, v2=eval_v2, v2b=eval_v2b)[[nm]]
  tryCatch(regime_kpi_chart(ev, out_dir), error=function(e) cat("Chart error:", e$message, "\n"))
}

# Telegram
tryCatch(regime_kpi_telegram(eval_v1, compare), error=function(e) cat("TG error:", e$message, "\n"))

cat("\n=== Evaluation Complete ===\n")
