#==============================================================================
# 216_panel_v5p_etf_yield_only.R — Cycle 58N preparation
#
# v5p = v5g (86) + ETF flow (4) + KR yield curve (10) = 100 features
# 58K investor breadth noise (PR-AUC 0.148) 제외 → 더 깨끗한 alt-data test.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_DIR <- file.path(WS, "outputs/01_data")
OUT_PATH <- file.path(IN_DIR, "feature_panel_v5p_etf_yield.parquet")

cat(sprintf("[%s] Loading v5g + ETF + yield curve...\n",
            format(Sys.time(), "%H:%M:%S")))
d <- as.data.table(read_parquet(file.path(IN_DIR,
                                          "feature_panel_v5g_cross_market.parquet")))
d[, Date := as.Date(Date)]
setorder(d, Date)
cat(sprintf("  v5g: %d × %d\n", nrow(d), ncol(d)))

etf <- as.data.table(read_parquet(file.path(IN_DIR, "etf_flow_features.parquet")))
etf[, Date := as.Date(Date)]
d <- merge(d, etf, by = "Date", all.x = TRUE)
cat(sprintf("  + ETF: %d cols\n", ncol(d)))

yc <- as.data.table(read_parquet(file.path(IN_DIR, "kr_yield_curve_features.parquet")))
yc[, Date := as.Date(Date)]
d <- merge(d, yc, by = "Date", all.x = TRUE)
cat(sprintf("  + yield curve: %d cols (= 86 + 4 + 10 = 100 features expected)\n",
            ncol(d)))

write_parquet(d, OUT_PATH)
cat(sprintf("\n[%s] Saved: %s\n  %d rows × %d cols\n",
            format(Sys.time(), "%H:%M:%S"), OUT_PATH, nrow(d), ncol(d)))
