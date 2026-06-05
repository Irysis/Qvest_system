#==============================================================================
# 01_feature_assembler_alt.R — Plan v1.0 alt features panel merge
#
# Merge A3 (US sector flow) + A5 (Options higher moments) + A6 (BBVA macro)
# Output: outputs/01_data/feature_panel_v1_alt.parquet
#
# v1.0 Sprint 2~3 features (max 8):
#   A6_bbva: bbva_market_z + bbva_sovereign_z + bbva_transmission_z + bbva_macro_composite
#   A5_options: k200_implied_skew_z + k200_implied_kurt_z
#   A3_sector: us_sector_avg_z + us_sector_dispersion_z
#
# PIT 의무: 각 A6/A5/A3 builder 이미 lag1 적용. assembler는 단순 merge.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
DATA_DIR <- file.path(WS_DIR, "outputs/01_data")

source(file.path(WS_DIR, "scripts/00_pit_manifest_loader.R"))

assemble_alt_features <- function() {
  cat("[assembler_alt] Merging A3 + A5 + A6 features...\n")

  # Use benchmark dates as base
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  panel <- bm[, .(Date)]

  # ── A6 BBVA ──
  a6_path <- file.path(DATA_DIR, "A6_bbva_macro.parquet")
  if (file.exists(a6_path)) {
    a6 <- as.data.table(read_parquet(a6_path))
    panel <- merge(panel, a6, by = "Date", all.x = TRUE)
    cat(sprintf("  A6 BBVA merged: %d cols, non-NA composite=%d\n",
                ncol(a6) - 1, sum(!is.na(a6$bbva_macro_composite))))
  } else {
    cat("  A6 BBVA: MISSING\n")
  }

  # ── A5 Options ──
  a5_path <- file.path(DATA_DIR, "A5_options_higher_moments.parquet")
  if (file.exists(a5_path)) {
    a5 <- as.data.table(read_parquet(a5_path))
    panel <- merge(panel, a5, by = "Date", all.x = TRUE)
    cat(sprintf("  A5 Options merged: %d cols, non-NA skew=%d\n",
                ncol(a5) - 1, sum(!is.na(a5$k200_implied_skew_z))))
  } else {
    cat("  A5 Options: MISSING\n")
  }

  # ── A3 US sector flow ──
  a3_path <- file.path(DATA_DIR, "A3_us_sector_flow.parquet")
  if (file.exists(a3_path)) {
    a3 <- as.data.table(read_parquet(a3_path))
    panel <- merge(panel, a3, by = "Date", all.x = TRUE)
    cat(sprintf("  A3 US sector merged: %d cols, non-NA avg=%d\n",
                ncol(a3) - 1, sum(!is.na(a3$us_sector_avg_z))))
  } else {
    cat("  A3 US sector: MISSING\n")
  }

  setorder(panel, Date)

  out_path <- file.path(DATA_DIR, "feature_panel_v1_alt.parquet")
  write_parquet(panel, out_path)

  cat(sprintf("\n[assembler_alt] Saved: %s\n", out_path))
  cat(sprintf("  Total: %d rows × %d cols\n", nrow(panel), ncol(panel)))
  cat(sprintf("  Date range: %s ~ %s\n",
              as.character(min(panel$Date)), as.character(max(panel$Date))))

  # PIT denylist re-check
  tryCatch(validate_no_leakage(out_path), error = function(e) cat("LEAKAGE CHECK:", e$message, "\n"))

  cat("\n── Coverage summary ──\n")
  feat_cols <- setdiff(names(panel), "Date")
  for (c in feat_cols) {
    cov <- sum(!is.na(panel[[c]])) / nrow(panel)
    first_nna <- min(panel$Date[!is.na(panel[[c]])])
    cat(sprintf("  %-30s : %.1f%% cover, first %s\n",
                c, 100 * cov, as.character(first_nna)))
  }

  invisible(panel)
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  assemble_alt_features()
}
