#==============================================================================
# 214_panel_v5l_alt_data_full.R — Cycle 58M
#
# 종합 alt-data panel: v5g (86) + 3 alt sources:
#   1. Investor breadth (개인/기관/기타외인): 12 features (gaein/inst/kita
#      각 ad_ratio_z_lag1, hhi_buy_z_lag1, ad_ratio_z_rm21, ad_ratio_z_rsd21)
#   2. ETF flow: 4 features (inv/lev ratio, bond/eq ratio, k200 vol, 2x-inv vol)
#   3. KR yield curve: 10 features (10y level, term premium, steepness,
#      curvature, credit spread, key changes)
#
# Total: 86 + 12 + 4 + 10 = 112 features
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_DIR <- file.path(WS, "outputs/01_data")
OUT_PATH <- file.path(WS, "outputs/01_data/feature_panel_v5l_alt_full.parquet")

cat(sprintf("[%s] Loading v5g base + v5j (investor breadth)...\n",
            format(Sys.time(), "%H:%M:%S")))
# v5j already has v5g + investor breadth (built as 58K)
d <- as.data.table(read_parquet(file.path(IN_DIR,
                                          "feature_panel_v5j_investor_breadth.parquet")))
d[, Date := as.Date(Date)]
setorder(d, Date)
cat(sprintf("  v5j base: %d rows × %d cols\n", nrow(d), ncol(d)))

# Add ETF flow
cat(sprintf("[%s] Adding ETF flow features...\n",
            format(Sys.time(), "%H:%M:%S")))
etf <- as.data.table(read_parquet(file.path(IN_DIR, "etf_flow_features.parquet")))
etf[, Date := as.Date(Date)]
d <- merge(d, etf, by = "Date", all.x = TRUE)
cat(sprintf("  After ETF: %d cols\n", ncol(d)))

# Add KR yield curve
cat(sprintf("[%s] Adding KR yield curve features...\n",
            format(Sys.time(), "%H:%M:%S")))
yc <- as.data.table(read_parquet(file.path(IN_DIR,
                                            "kr_yield_curve_features.parquet")))
yc[, Date := as.Date(Date)]
d <- merge(d, yc, by = "Date", all.x = TRUE)
cat(sprintf("  After YC: %d cols (Date + %d features)\n",
            ncol(d), ncol(d) - 1))

# Validation
n_v5g <- 86
n_invest <- 12
n_etf <- 4
n_yc <- 10
n_total <- ncol(d) - 1
cat(sprintf("\n=== Panel composition ===\n"))
cat(sprintf("  v5g base:        %d features\n", n_v5g))
cat(sprintf("  investor breadth: %d features\n", n_invest))
cat(sprintf("  ETF flow:        %d features\n", n_etf))
cat(sprintf("  KR yield curve:  %d features\n", n_yc))
cat(sprintf("  Total:           %d features (expected %d)\n",
            n_total, n_v5g + n_invest + n_etf + n_yc))

# Save
write_parquet(d, OUT_PATH)
cat(sprintf("\n[%s] Saved: %s\n  %d rows × %d cols\n",
            format(Sys.time(), "%H:%M:%S"), OUT_PATH, nrow(d), ncol(d)))

audit <- list(
  cycle = "58M_panel_v5l_alt_full",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  n_features_total = n_total,
  composition = list(
    v5g = n_v5g, investor = n_invest, etf = n_etf, yield_curve = n_yc
  ),
  n_rows = nrow(d)
)
jsonlite::write_json(audit,
  file.path(WS, "outputs/04_evaluation/cycle58m_panel_v5l_build.json"),
  auto_unbox = TRUE, pretty = TRUE)
