#==============================================================================
# 181_panel_v1_3_v4a_v5e_v5f_FIXED2.R — Cycle 57B Phase 3
#
# Mandate (Codex 57A_followup priority 1):
#   BBVA indirect ICSA contamination 해소를 위해 BBVA 의존 panel 전체 재구성.
#
#   FIXED2 suffix = "BBVA indirect ALSO fixed" (FIXED는 direct US FRED만 fixed 57A)
#
#   Cascade chain:
#     A6_bbva_macro_FIXED (Phase 2 output) — 4 raw BBVA z-scores
#       ↓ 01_feature_assembler_alt.R logic
#     feature_panel_v1_alt_FIXED2 (8 base) — A6 + A5 + A3 merged
#       ↓ 11_feature_engineering_enhanced.R logic
#     feature_panel_v1_alt_enhanced_FIXED2 (69 features)
#       ↓ direct copy (v1_3 == enhanced)
#     feature_panel_v1_3_FIXED2 (69 features)
#       ↓ 119 logic (add foreign_breadth_ad_ratio_5d_avg_lag1)
#     feature_panel_v4a_FIXED2 (70 features)
#       ↓ 173 logic (add 4 US macro FIXED, no BBVA inherit)
#     feature_panel_v5e_FIXED2 (74 features)
#       ↓ 173 logic (add 5 ECOS)
#     feature_panel_v5f_FIXED2 (79 features)
#
#   Logic 변경 절대 금지 (Forge Pure Function).
#   각 단계에서 BEFORE (cycle57a FIXED) vs AFTER (cycle57b FIXED2) 비교.
#
# Output:
#   outputs/01_data/feature_panel_v1_3_FIXED2.parquet (69)
#   outputs/01_data/feature_panel_v4a_FIXED2.parquet (70)
#   outputs/01_data/feature_panel_v5e_FIXED2.parquet (74)
#   outputs/01_data/feature_panel_v5f_FIXED2.parquet (79)
#   outputs/04_evaluation/cycle57b_panel_rebuild_FIXED2.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
DATA_DIR <- file.path(WS, "outputs/01_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")

cat("\n========== Cycle 57B Phase 3: Panel rebuild v1.3/v4a/v5e/v5f FIXED2 ==========\n")

# ---------------------------------------------------------------------------
# Step 1: Rebuild feature_panel_v1_alt (8 base features) using FIXED2 BBVA
# ---------------------------------------------------------------------------
cat("\n[Step 1] v1_alt rebuild (A6 FIXED2 + A5 + A3)\n")

# Use benchmark.parquet as date spine (01_feature_assembler_alt.R inherit)
bm_path <- file.path(CACHE_DIR, "benchmark.parquet")
if (!file.exists(bm_path)) stop(sprintf("missing benchmark: %s", bm_path))
bm <- as.data.table(read_parquet(bm_path))
bm[, Date := as.Date(Date)]
panel <- bm[, .(Date)]
cat(sprintf("  date spine: %d rows (%s ~ %s)\n",
            nrow(panel), min(panel$Date), max(panel$Date)))

# A6 FIXED2 (Phase 2 output) — replaces A6_bbva_macro.parquet
a6_path <- file.path(DATA_DIR, "A6_bbva_macro_FIXED.parquet")
if (!file.exists(a6_path)) stop(sprintf("missing A6 FIXED: %s — run Phase 2 (180) first", a6_path))
a6 <- as.data.table(read_parquet(a6_path))
panel <- merge(panel, a6, by = "Date", all.x = TRUE)
cat(sprintf("  A6 FIXED merged: 4 cols, composite non-NA=%d\n",
            sum(!is.na(panel$bbva_macro_composite))))

# A5 Options higher moments (unchanged)
a5_path <- file.path(DATA_DIR, "A5_options_higher_moments.parquet")
if (file.exists(a5_path)) {
  a5 <- as.data.table(read_parquet(a5_path))
  panel <- merge(panel, a5, by = "Date", all.x = TRUE)
  cat(sprintf("  A5 merged: %d cols, skew non-NA=%d\n",
              ncol(a5) - 1, sum(!is.na(panel$k200_implied_skew_z))))
} else {
  cat("  A5: MISSING\n")
}

# A3 US sector flow (unchanged)
a3_path <- file.path(DATA_DIR, "A3_us_sector_flow.parquet")
if (file.exists(a3_path)) {
  a3 <- as.data.table(read_parquet(a3_path))
  panel <- merge(panel, a3, by = "Date", all.x = TRUE)
  cat(sprintf("  A3 merged: %d cols, avg non-NA=%d\n",
              ncol(a3) - 1, sum(!is.na(panel$us_sector_avg_z))))
}

setorder(panel, Date)
v1_alt_FIXED2_path <- file.path(DATA_DIR, "feature_panel_v1_alt_FIXED2.parquet")
write_parquet(panel, v1_alt_FIXED2_path)
cat(sprintf("  Saved: %s (%d cols)\n", v1_alt_FIXED2_path, ncol(panel) - 1))

# ---------------------------------------------------------------------------
# Step 2: Rebuild v1_alt_enhanced (69 features) — 11_feature_engineering_enhanced.R logic
# ---------------------------------------------------------------------------
cat("\n[Step 2] v1_alt_enhanced rebuild (lag + rolling + interactions = 69)\n")

BASE_FEATURES <- c(
  "bbva_market_z", "bbva_sovereign_z",
  "bbva_transmission_z", "bbva_macro_composite",
  "k200_implied_skew_z", "k200_implied_kurt_z",
  "us_sector_avg_z", "us_sector_dispersion_z"
)
LAG_DAYS <- c(1, 5, 21)
ROLLING_WIN <- c(21, 63)

rolling_mean <- function(x, w) frollmean(x, w, na.rm = TRUE, align = "right")
rolling_sd <- function(x, w) frollapply(x, w, function(v) sd(v, na.rm = TRUE), align = "right")

feat <- copy(panel)

# Lag features
for (col in BASE_FEATURES) {
  if (!col %in% names(feat)) next
  for (lg in LAG_DAYS) {
    new_col <- sprintf("%s_lag%d", col, lg)
    feat[, (new_col) := shift(get(col), lg, type = "lag")]
  }
}

# Rolling mean + std
for (col in BASE_FEATURES) {
  if (!col %in% names(feat)) next
  for (w in ROLLING_WIN) {
    mean_col <- sprintf("%s_rm%d", col, w)
    sd_col   <- sprintf("%s_rsd%d", col, w)
    feat[, (mean_col) := rolling_mean(get(col), w)]
    feat[, (sd_col)   := rolling_sd(get(col), w)]
  }
}

# Cross-interactions (5 pairs)
if (all(c("us_sector_avg_z", "bbva_market_z") %in% names(feat)))
  feat[, intx_us_bbva_market := us_sector_avg_z * bbva_market_z]
if (all(c("us_sector_dispersion_z", "bbva_macro_composite") %in% names(feat)))
  feat[, intx_us_disp_bbva_comp := us_sector_dispersion_z * bbva_macro_composite]
if (all(c("k200_implied_skew_z", "bbva_market_z") %in% names(feat)))
  feat[, intx_skew_bbva_market := k200_implied_skew_z * bbva_market_z]
if (all(c("k200_implied_kurt_z", "us_sector_dispersion_z") %in% names(feat)))
  feat[, intx_kurt_us_disp := k200_implied_kurt_z * us_sector_dispersion_z]
if (all(c("bbva_transmission_z", "us_sector_avg_z") %in% names(feat)))
  feat[, intx_trans_us := bbva_transmission_z * us_sector_avg_z]

n_enhanced <- ncol(feat) - 1L
cat(sprintf("  v1_alt_enhanced FIXED2: %d cols (expected 69)\n", n_enhanced))
stopifnot(n_enhanced == 69L)

v1_enhanced_FIXED2_path <- file.path(DATA_DIR, "feature_panel_v1_alt_enhanced_FIXED2.parquet")
write_parquet(feat, v1_enhanced_FIXED2_path)
cat(sprintf("  Saved: %s\n", v1_enhanced_FIXED2_path))

# ---------------------------------------------------------------------------
# Step 3: v1_3_FIXED2 = direct copy of v1_alt_enhanced_FIXED2 (81 logic)
# ---------------------------------------------------------------------------
cat("\n[Step 3] v1_3_FIXED2 (direct copy of enhanced FIXED2)\n")
v1_3_FIXED2_path <- file.path(DATA_DIR, "feature_panel_v1_3_FIXED2.parquet")
write_parquet(feat, v1_3_FIXED2_path)
cat(sprintf("  Saved: %s (69 cols)\n", v1_3_FIXED2_path))

# Validate column structure matches v1.3 original
v1_3_orig <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_3.parquet")))
diff_cols_v1_3 <- setdiff(names(v1_3_orig), names(feat))
diff_cols_v1_3_rev <- setdiff(names(feat), names(v1_3_orig))
if (length(diff_cols_v1_3) > 0 || length(diff_cols_v1_3_rev) > 0) {
  cat(sprintf("  WARNING — col mismatch vs original v1.3:\n"))
  cat(sprintf("    in orig not in FIXED2: %s\n", paste(diff_cols_v1_3, collapse = ", ")))
  cat(sprintf("    in FIXED2 not in orig: %s\n", paste(diff_cols_v1_3_rev, collapse = ", ")))
} else {
  cat(sprintf("  col structure matches v1.3 original (69 cols)\n"))
}

# ---------------------------------------------------------------------------
# Step 4: v4a_FIXED2 — 119_feature_panel_v4a_combined.R logic
#   Adds foreign_breadth_ad_ratio_5d_avg_lag1 (1 feature from v2_2feat)
# ---------------------------------------------------------------------------
cat("\n[Step 4] v4a_FIXED2 (v1_3_FIXED2 + foreign_breadth_5d = 70)\n")
v22_path <- file.path(DATA_DIR, "feature_panel_v2_2feat.parquet")
if (!file.exists(v22_path)) stop(sprintf("missing v2_2feat: %s", v22_path))
v22 <- as.data.table(read_parquet(v22_path))
v22[, Date := as.Date(Date)]
winner <- v22[, .(Date, foreign_breadth_ad_ratio_5d_avg_lag1 = ad_ratio_5d_avg_lag1)]

v4a_FIXED2 <- merge(feat, winner, by = "Date", all.x = TRUE)
setorder(v4a_FIXED2, Date)
n_v4a <- ncol(v4a_FIXED2) - 1L
cat(sprintf("  v4a_FIXED2: %d cols (expected 70)\n", n_v4a))
stopifnot(n_v4a == 70L)

v4a_FIXED2_path <- file.path(DATA_DIR, "feature_panel_v4a_FIXED2.parquet")
write_parquet(v4a_FIXED2, v4a_FIXED2_path)
cat(sprintf("  Saved: %s\n", v4a_FIXED2_path))

# ---------------------------------------------------------------------------
# Step 5: Build 4 US macro features (FIXED publication-lag) — 173 logic
# ---------------------------------------------------------------------------
cat("\n[Step 5] US macro 4 features (FIXED CSV, 173 logic)\n")
fred_fixed_csv <- file.path(DATA_DIR, "fred_us_macro_daily_fixed.csv")
if (!file.exists(fred_fixed_csv)) stop(sprintf("missing FIXED FRED CSV: %s", fred_fixed_csv))
fred_us <- fread(fred_fixed_csv)
fred_us[, Date := as.Date(Date)]
setorder(fred_us, Date)
fred_us[, t10y2y_ff := nafill(t10y2y_raw, type = "locf")]
fred_us[, icsa_ff   := nafill(icsa_raw,   type = "locf")]
fred_us[, cfnai_ff  := nafill(cfnai_raw,  type = "locf")]
fred_us[, stlfsi_ff := nafill(stlfsi4_raw, type = "locf")]
fred_us[, icsa_4w_avg := frollmean(icsa_ff, n = 28, align = "right", na.rm = TRUE)]
fred_us[, us_t10y2y_spread_lag1 := shift(t10y2y_ff, 1L, type = "lag")]
fred_us[, us_initial_claims_4w_avg_lag1 := shift(icsa_4w_avg, 1L, type = "lag")]
fred_us[, us_cfnai_lag1 := shift(cfnai_ff, 1L, type = "lag")]
fred_us[, us_stlfsi_lag1 := shift(stlfsi_ff, 1L, type = "lag")]
us_macro_feats <- fred_us[, .(Date,
                              us_t10y2y_spread_lag1,
                              us_initial_claims_4w_avg_lag1,
                              us_cfnai_lag1,
                              us_stlfsi_lag1)]
cat(sprintf("  us_macro_feats: %d rows, 4 cols\n", nrow(us_macro_feats)))

# ---------------------------------------------------------------------------
# Step 6: v5e_FIXED2 (v4a_FIXED2 70 + US macro 4 = 74)
# ---------------------------------------------------------------------------
cat("\n[Step 6] v5e_FIXED2 (v4a_FIXED2 + US macro 4 = 74)\n")
v5e_FIXED2 <- merge(v4a_FIXED2, us_macro_feats, by = "Date", all.x = TRUE)
setorder(v5e_FIXED2, Date)
n_v5e <- ncol(v5e_FIXED2) - 1L
cat(sprintf("  v5e_FIXED2: %d cols (expected 74)\n", n_v5e))
stopifnot(n_v5e == 74L)

v5e_FIXED2_path <- file.path(DATA_DIR, "feature_panel_v5e_FIXED2.parquet")
write_parquet(v5e_FIXED2, v5e_FIXED2_path)
cat(sprintf("  Saved: %s\n", v5e_FIXED2_path))

# ---------------------------------------------------------------------------
# Step 7: v5f_FIXED2 (v5e_FIXED2 74 + 5 ECOS = 79)
# ---------------------------------------------------------------------------
cat("\n[Step 7] v5f_FIXED2 (v5e_FIXED2 + 5 ECOS = 79)\n")
ecos_path <- file.path(DATA_DIR, "ecos_kr_daily.csv")
if (!file.exists(ecos_path)) stop(sprintf("missing ECOS CSV: %s", ecos_path))
ecos <- fread(ecos_path)
ecos[, Date := as.Date(Date)]
setorder(ecos, Date)
ecos_features <- c(
  "ecos_m2_yoy_lag1",
  "ecos_krw_usd_change_5d_lag1",
  "ecos_base_rate_lag1",
  "ecos_industrial_production_yoy_lag1",
  "ecos_cpi_yoy_lag1"
)
stopifnot(all(ecos_features %in% names(ecos)))
v5f_FIXED2 <- merge(v5e_FIXED2, ecos[, c("Date", ecos_features), with = FALSE],
                    by = "Date", all.x = TRUE)
setorder(v5f_FIXED2, Date)
n_v5f <- ncol(v5f_FIXED2) - 1L
cat(sprintf("  v5f_FIXED2: %d cols (expected 79)\n", n_v5f))
stopifnot(n_v5f == 79L)

v5f_FIXED2_path <- file.path(DATA_DIR, "feature_panel_v5f_FIXED2.parquet")
write_parquet(v5f_FIXED2, v5f_FIXED2_path)
cat(sprintf("  Saved: %s\n", v5f_FIXED2_path))

# ---------------------------------------------------------------------------
# Step 8: Validation — BBVA contamination removed in v1.3/v4a
# ---------------------------------------------------------------------------
cat("\n[Step 8] Validation: v4a BEFORE (cycle57a / FIXED) vs AFTER (cycle57b / FIXED2)\n")
v4a_orig <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v4a_combined.parquet")))
v4a_orig[, Date := as.Date(Date)]
setorder(v4a_orig, Date)

# Sample BBVA columns BEFORE vs AFTER on COVID dates
covid_dates <- as.Date(c("2020-03-20", "2020-03-25", "2020-04-01", "2020-04-15"))
for (d in covid_dates) {
  d <- as.Date(d, origin = "1970-01-01")
  before_val <- v4a_orig[Date == d, bbva_market_z]
  after_val <- v4a_FIXED2[Date == d, bbva_market_z]
  cat(sprintf("  %s bbva_market_z: BEFORE=%s, AFTER=%s\n",
              as.character(d),
              ifelse(length(before_val)==0||is.na(before_val), "NA", sprintf("%.4f", before_val)),
              ifelse(length(after_val)==0||is.na(after_val), "NA", sprintf("%.4f", after_val))))
}

# Overall diff stats on BBVA market_z
both <- merge(v4a_orig[, .(Date, before = bbva_market_z)],
              v4a_FIXED2[, .(Date, after = bbva_market_z)],
              by = "Date", all = FALSE)
both_clean <- both[!is.na(before) & !is.na(after)]
diff <- abs(both_clean$before - both_clean$after)
cat(sprintf("\nv4a bbva_market_z diff stats (%d common dates):\n", nrow(both_clean)))
cat(sprintf("  mean=%.4f, max=%.4f, p95=%.4f, pct unchanged=%.1f%%\n",
            mean(diff, na.rm = TRUE), max(diff, na.rm = TRUE),
            quantile(diff, 0.95, na.rm = TRUE),
            100 * sum(diff < 1e-6, na.rm = TRUE) / nrow(both_clean)))

# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------
audit <- list(
  cycle = "57B_Phase3",
  description = "Panel rebuild v1.3/v4a/v5e/v5f FIXED2 (BBVA indirect ICSA also fixed)",
  inputs = list(
    fred_macro_wide_FIXED = file.path(CACHE_DIR, "fred_macro_wide.parquet"),
    a6_bbva_FIXED = a6_path,
    a5_options = a5_path,
    a3_us_sector = a3_path,
    v2_2feat = v22_path,
    fred_us_macro_daily_fixed_csv = fred_fixed_csv,
    ecos_kr_daily_csv = ecos_path
  ),
  outputs = list(
    v1_alt_FIXED2 = v1_alt_FIXED2_path,
    v1_alt_enhanced_FIXED2 = v1_enhanced_FIXED2_path,
    v1_3_FIXED2 = v1_3_FIXED2_path,
    v4a_FIXED2 = v4a_FIXED2_path,
    v5e_FIXED2 = v5e_FIXED2_path,
    v5f_FIXED2 = v5f_FIXED2_path
  ),
  feature_counts = list(
    v1_3_FIXED2 = ncol(feat) - 1L,
    v4a_FIXED2 = n_v4a,
    v5e_FIXED2 = n_v5e,
    v5f_FIXED2 = n_v5f
  ),
  bbva_contamination_removed = list(
    common_dates = nrow(both_clean),
    bbva_market_z_mean_abs_diff = round(mean(diff, na.rm = TRUE), 6),
    bbva_market_z_max_abs_diff = round(max(diff, na.rm = TRUE), 6),
    bbva_market_z_p95_abs_diff = round(quantile(diff, 0.95, na.rm = TRUE), 6),
    bbva_market_z_pct_unchanged = round(100 * sum(diff < 1e-6, na.rm = TRUE) / nrow(both_clean), 2)
  ),
  v1_3_col_validation = list(
    in_orig_not_FIXED2 = if (length(diff_cols_v1_3) == 0) "NONE" else paste(diff_cols_v1_3, collapse = ","),
    in_FIXED2_not_orig = if (length(diff_cols_v1_3_rev) == 0) "NONE" else paste(diff_cols_v1_3_rev, collapse = ",")
  ),
  next_step = "Phase 4: scripts/182-184 (5 q15 cycle retrain on FIXED2 panels)"
)
audit_path <- file.path(EVAL_DIR, "cycle57b_panel_rebuild_FIXED2.json")
write_json(audit, audit_path, auto_unbox = TRUE, pretty = TRUE, na = "string")
cat(sprintf("\n[audit] %s\n", audit_path))

cat("\n========== Cycle 57B Phase 3 DONE ==========\n")
cat("Panels rebuilt:\n")
cat(sprintf("  v1.3_FIXED2 (69)  → %s\n", v1_3_FIXED2_path))
cat(sprintf("  v4a_FIXED2 (70)  → %s\n", v4a_FIXED2_path))
cat(sprintf("  v5e_FIXED2 (74)  → %s\n", v5e_FIXED2_path))
cat(sprintf("  v5f_FIXED2 (79)  → %s\n", v5f_FIXED2_path))
