#==============================================================================
# 11_feature_engineering_enhanced.R — E1 Feature engineering 강화
#
# 8 base alt features →  enhanced panel:
#   - lag (t-1, t-5, t-21) → 8 × 3 = 24 lag features
#   - rolling mean/std (21d, 63d) → 8 × 4 = 32 rolling features
#   - cross-interaction (US sector × BBVA + Options × BBVA + 5 pairs) → 5 interaction
#
# Total: 8 base + 24 lag + 32 rolling + 5 interaction = ~69 features
# Hard cap 검토: stability selection 또는 XGBoost 학습 시 자동 selection
#
# Output: outputs/01_data/feature_panel_v1_alt_enhanced.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS_DIR, "outputs/01_data")

BASE_FEATURES <- c(
  "bbva_market_z", "bbva_sovereign_z",
  "bbva_transmission_z", "bbva_macro_composite",
  "k200_implied_skew_z", "k200_implied_kurt_z",
  "us_sector_avg_z", "us_sector_dispersion_z"
)

LAG_DAYS <- c(1, 5, 21)
ROLLING_WIN <- c(21, 63)

# ── Helpers ──
rolling_mean <- function(x, w) frollmean(x, w, na.rm = TRUE, align = "right")
rolling_sd <- function(x, w) frollapply(x, w, function(v) sd(v, na.rm = TRUE), align = "right")

build_enhanced_panel <- function() {
  cat("[E1] Loading feature_panel_v1_alt.parquet...\n")
  feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v1_alt.parquet")))
  feat[, Date := as.Date(Date)]
  setorder(feat, Date)
  cat(sprintf("[E1] Base panel: %d rows × %d cols\n", nrow(feat), ncol(feat)))

  # ── Lag features (t-1, t-5, t-21) ──
  for (col in BASE_FEATURES) {
    if (!col %in% names(feat)) next
    for (lg in LAG_DAYS) {
      new_col <- sprintf("%s_lag%d", col, lg)
      feat[, (new_col) := shift(get(col), lg, type = "lag")]
    }
  }

  # ── Rolling mean + std (21d, 63d) ──
  for (col in BASE_FEATURES) {
    if (!col %in% names(feat)) next
    for (w in ROLLING_WIN) {
      mean_col <- sprintf("%s_rm%d", col, w)
      sd_col   <- sprintf("%s_rsd%d", col, w)
      feat[, (mean_col) := rolling_mean(get(col), w)]
      feat[, (sd_col)   := rolling_sd(get(col), w)]
    }
  }

  # ── Cross-interaction (5 pairs, domain-driven) ──
  if (all(c("us_sector_avg_z", "bbva_market_z") %in% names(feat))) {
    feat[, intx_us_bbva_market := us_sector_avg_z * bbva_market_z]
  }
  if (all(c("us_sector_dispersion_z", "bbva_macro_composite") %in% names(feat))) {
    feat[, intx_us_disp_bbva_comp := us_sector_dispersion_z * bbva_macro_composite]
  }
  if (all(c("k200_implied_skew_z", "bbva_market_z") %in% names(feat))) {
    feat[, intx_skew_bbva_market := k200_implied_skew_z * bbva_market_z]
  }
  if (all(c("k200_implied_kurt_z", "us_sector_dispersion_z") %in% names(feat))) {
    feat[, intx_kurt_us_disp := k200_implied_kurt_z * us_sector_dispersion_z]
  }
  if (all(c("bbva_transmission_z", "us_sector_avg_z") %in% names(feat))) {
    feat[, intx_trans_us := bbva_transmission_z * us_sector_avg_z]
  }

  out_path <- file.path(DATA_DIR, "feature_panel_v1_alt_enhanced.parquet")
  write_parquet(feat, out_path)

  cat(sprintf("\n[E1] DONE — enhanced panel: %d rows × %d cols\n", nrow(feat), ncol(feat)))
  cat(sprintf("  Output: %s\n", out_path))

  # Coverage summary (last 20 cols)
  cat("\n[E1] Coverage summary (last 20 cols):\n")
  feat_cols <- setdiff(names(feat), "Date")
  for (c in tail(feat_cols, 20)) {
    cov <- sum(!is.na(feat[[c]])) / nrow(feat)
    cat(sprintf("  %-40s : %.1f%% cover\n", c, 100 * cov))
  }

  invisible(feat)
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  build_enhanced_panel()
}
