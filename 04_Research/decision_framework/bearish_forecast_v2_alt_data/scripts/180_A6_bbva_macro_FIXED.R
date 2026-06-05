#==============================================================================
# 180_A6_bbva_macro_FIXED.R — Cycle 57B Phase 2
#
# Mandate (Codex 57A_followup priority 1):
#   A6_bbva_macro_builder.R 로직 그대로 inherit (no formula change).
#   단 입력만 fred_macro_wide.parquet → fred_macro_wide_FIXED.parquet (Phase 1 output) 교체.
#   결과: A6_bbva_macro_FIXED.parquet (BBVA z-scores with clean inputs)
#
#   Logic 변경 절대 금지 (Forge Pure Function):
#     - rolling_zscore_expanding (expanding window, min 252)
#     - bbva_market_z = mean(vix_d_z, -copper_d_z, claims_d_z) row-wise
#     - bbva_sovereign_z = mean(bbb_d_z, hy_d_z) row-wise
#     - bbva_transmission_z = mean(-term_d_z, krw_d_z, dgs10_d_z) row-wise
#     - bbva_macro_composite = mean of 3 z-scores row-wise
#     - lag1 final (PIT C2 — next-day usable at KR open)
#
# Output:
#   outputs/01_data/A6_bbva_macro_FIXED.parquet
#   outputs/04_evaluation/cycle57b_A6_bbva_macro_FIXED.json
#
# PIT contract:
#   - 모든 z-score expanding window (C1) 유지
#   - lag1 (decision_time = next_open) 유지
#   - 입력 Init_Claims가 Sat→Thu shift된 fixed CSV 사용 → 5d lookahead 해소
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(zoo); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS_DIR, "outputs/01_data")
EVAL_DIR <- file.path(WS_DIR, "outputs/04_evaluation")

cat("\n========== Cycle 57B Phase 2: A6 BBVA macro FIXED rebuild ==========\n")

# ── Rolling z-score (expanding, min 252) — A6 inherit ───────
rolling_zscore_expanding <- function(x, min_obs = 252) {
  n <- length(x)
  z <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    vals <- x[1:i]; vals <- vals[!is.na(vals)]
    if (length(vals) < min_obs) next
    mu <- mean(vals); sg <- sd(vals)
    if (is.na(sg) || sg < 1e-10) next
    z[i] <- (x[i] - mu) / sg
  }
  z
}
lag1 <- function(x) c(NA, head(x, -1))

# ── Load FIXED FRED (Phase 1 output) ──
fred_path <- file.path(DATA_DIR, "fred_macro_wide_FIXED.parquet")
if (!file.exists(fred_path)) stop(sprintf("missing: %s — run Phase 1 (179) first", fred_path))
fred <- as.data.table(read_parquet(fred_path))
fred[, Date := as.Date(Date)]
setorder(fred, Date)
cat(sprintf("[loaded FIXED FRED] %d rows × %d cols (%s ~ %s)\n",
            nrow(fred), ncol(fred), min(fred$Date), max(fred$Date)))

# ── Forward-fill monthly/weekly series (A6 inherit) ──
for (col in c("Copper_Price", "Init_Claims", "BBB_Spread", "HY_Spread",
              "Fed_Funds_Rate", "Bank_Lending_Std", "Housing_Permits",
              "UMich_Sentiment", "US_M2", "US_CPI", "US_IndProd", "US_Unemployment")) {
  if (col %in% names(fred)) {
    fred[, (col) := zoo::na.locf(get(col), na.rm = FALSE)]
  }
}

# ── Channel 1: Markets ──
fred[, vix_d := c(NA, diff(VIX))]
fred[, copper_d := c(NA, diff(log(pmax(Copper_Price, 1e-3))))]
fred[, claims_d := c(NA, diff(Init_Claims))]

fred[, vix_d_z := rolling_zscore_expanding(vix_d)]
fred[, copper_d_z := rolling_zscore_expanding(copper_d)]
fred[, claims_d_z := rolling_zscore_expanding(claims_d)]

fred[, bbva_market_z := (vix_d_z - copper_d_z + claims_d_z) / 3]

# ── Channel 2: Sovereign ──
fred[, bbb_d := c(NA, diff(BBB_Spread))]
fred[, hy_d := c(NA, diff(HY_Spread))]
fred[, bbb_d_z := rolling_zscore_expanding(bbb_d)]
fred[, hy_d_z := rolling_zscore_expanding(hy_d)]
fred[, bbva_sovereign_z := (bbb_d_z + hy_d_z) / 2]

# ── Channel 3: Transmission ──
fred[, term_d := c(NA, diff(Term_Spread))]
fred[, krw_d := c(NA, diff(log(KRW_USD)))]
fred[, dgs10_d := c(NA, diff(US_10Y_Yield))]

fred[, term_d_z := rolling_zscore_expanding(term_d)]
fred[, krw_d_z := rolling_zscore_expanding(krw_d)]
fred[, dgs10_d_z := rolling_zscore_expanding(dgs10_d)]

fred[, bbva_transmission_z := (-term_d_z + krw_d_z + dgs10_d_z) / 3]

# ── Row-wise na.rm (A6 inherit) ──
fred[, bbva_market_z := rowMeans(cbind(vix_d_z, -copper_d_z, claims_d_z), na.rm = TRUE)]
fred[, bbva_market_z := ifelse(is.nan(bbva_market_z), NA_real_, bbva_market_z)]

fred[, bbva_sovereign_z := rowMeans(cbind(bbb_d_z, hy_d_z), na.rm = TRUE)]
fred[, bbva_sovereign_z := ifelse(is.nan(bbva_sovereign_z), NA_real_, bbva_sovereign_z)]

fred[, bbva_transmission_z := rowMeans(cbind(-term_d_z, krw_d_z, dgs10_d_z), na.rm = TRUE)]
fred[, bbva_transmission_z := ifelse(is.nan(bbva_transmission_z), NA_real_, bbva_transmission_z)]

# ── Composite (4-channel = 3-channel avg, A6 inherit) ──
fred[, bbva_macro_composite := rowMeans(
  cbind(bbva_market_z, bbva_sovereign_z, bbva_transmission_z), na.rm = TRUE)]
fred[, bbva_macro_composite := ifelse(is.nan(bbva_macro_composite), NA_real_, bbva_macro_composite)]

# ── lag1 (PIT C2) ──
fred[, bbva_market_z_lag1 := lag1(bbva_market_z)]
fred[, bbva_sovereign_z_lag1 := lag1(bbva_sovereign_z)]
fred[, bbva_transmission_z_lag1 := lag1(bbva_transmission_z)]
fred[, bbva_macro_composite_lag1 := lag1(bbva_macro_composite)]

result <- fred[, .(Date,
                   bbva_market_z = bbva_market_z_lag1,
                   bbva_sovereign_z = bbva_sovereign_z_lag1,
                   bbva_transmission_z = bbva_transmission_z_lag1,
                   bbva_macro_composite = bbva_macro_composite_lag1)]

out_path <- file.path(DATA_DIR, "A6_bbva_macro_FIXED.parquet")
write_parquet(result, out_path)

cat(sprintf("[A6 FIXED] %d rows / %s ~ %s\n",
            nrow(result), as.character(min(result$Date)), as.character(max(result$Date))))
cat(sprintf("  bbva_market_z non-NA: %d\n", sum(!is.na(result$bbva_market_z))))
cat(sprintf("  bbva_sovereign_z non-NA: %d\n", sum(!is.na(result$bbva_sovereign_z))))
cat(sprintf("  bbva_transmission_z non-NA: %d\n", sum(!is.na(result$bbva_transmission_z))))
cat(sprintf("  bbva_macro_composite non-NA: %d\n", sum(!is.na(result$bbva_macro_composite))))
cat(sprintf("  Output: %s\n", out_path))

# ── Compare A6 BEFORE vs AFTER (BBVA contamination impact estimate) ──
cat("\n[BBVA BEFORE vs AFTER comparison]\n")
a6_before <- as.data.table(read_parquet(file.path(DATA_DIR, "A6_bbva_macro.parquet")))
a6_before[, Date := as.Date(Date)]
setorder(a6_before, Date)

merged <- merge(a6_before[, .(Date, before_market = bbva_market_z, before_comp = bbva_macro_composite)],
                result[, .(Date, after_market = bbva_market_z, after_comp = bbva_macro_composite)],
                by = "Date", all.x = TRUE)

# COVID 2020-03 sample
covid_sample <- merged[Date >= as.Date("2020-03-01") & Date <= as.Date("2020-04-30")]
cat("\nCOVID 2020-03~04 BBVA market_z (BEFORE vs AFTER, sample):\n")
print(covid_sample[seq(1, nrow(covid_sample), by = 5)])

# Overall diff stats
clean_merged <- merged[!is.na(before_market) & !is.na(after_market)]
diff_market <- abs(clean_merged$before_market - clean_merged$after_market)
diff_comp <- abs(clean_merged$before_comp - clean_merged$after_comp)
cat(sprintf("\nDiff stats over %d common dates:\n", nrow(clean_merged)))
cat(sprintf("  bbva_market_z      |Δ|: mean=%.4f, max=%.4f, p95=%.4f\n",
            mean(diff_market, na.rm = TRUE), max(diff_market, na.rm = TRUE),
            quantile(diff_market, 0.95, na.rm = TRUE)))
cat(sprintf("  bbva_macro_composite |Δ|: mean=%.4f, max=%.4f, p95=%.4f\n",
            mean(diff_comp, na.rm = TRUE), max(diff_comp, na.rm = TRUE),
            quantile(diff_comp, 0.95, na.rm = TRUE)))
n_unchanged_market <- sum(diff_market < 1e-6, na.rm = TRUE)
n_unchanged_comp <- sum(diff_comp < 1e-6, na.rm = TRUE)
cat(sprintf("  pct unchanged (|Δ|<1e-6): market=%.1f%%, composite=%.1f%%\n",
            100 * n_unchanged_market / nrow(clean_merged),
            100 * n_unchanged_comp / nrow(clean_merged)))

# ── Audit log ──
audit <- list(
  cycle = "57B_Phase2",
  description = "A6 BBVA macro rebuild using fred_macro_wide_FIXED (Phase 1 output)",
  formula_change = "NONE — Forge Pure Function (logic 100% identical to A6_bbva_macro_builder.R)",
  input = fred_path,
  output = out_path,
  n_rows = nrow(result),
  date_range = paste(min(result$Date), "~", max(result$Date)),
  bbva_non_na = list(
    market_z = sum(!is.na(result$bbva_market_z)),
    sovereign_z = sum(!is.na(result$bbva_sovereign_z)),
    transmission_z = sum(!is.na(result$bbva_transmission_z)),
    composite = sum(!is.na(result$bbva_macro_composite))
  ),
  before_vs_after_diff = list(
    common_dates = nrow(clean_merged),
    market_z_mean_abs_diff = round(mean(diff_market, na.rm = TRUE), 6),
    market_z_max_abs_diff = round(max(diff_market, na.rm = TRUE), 6),
    market_z_p95_abs_diff = round(quantile(diff_market, 0.95, na.rm = TRUE), 6),
    composite_mean_abs_diff = round(mean(diff_comp, na.rm = TRUE), 6),
    composite_max_abs_diff = round(max(diff_comp, na.rm = TRUE), 6),
    composite_p95_abs_diff = round(quantile(diff_comp, 0.95, na.rm = TRUE), 6),
    pct_unchanged_market = round(100 * n_unchanged_market / nrow(clean_merged), 2),
    pct_unchanged_composite = round(100 * n_unchanged_comp / nrow(clean_merged), 2)
  ),
  next_step = "Phase 3: scripts/181_panel_v1_3_v4a_v5e_v5f_FIXED2.R"
)
audit_path <- file.path(EVAL_DIR, "cycle57b_A6_bbva_macro_FIXED.json")
write_json(audit, audit_path, auto_unbox = TRUE, pretty = TRUE, na = "string")
cat(sprintf("\n[audit] %s\n", audit_path))

cat("\n========== Cycle 57B Phase 2 DONE ==========\n")
