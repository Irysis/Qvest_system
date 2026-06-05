#==============================================================================
# 218_extract_consensus_aggregate.R — Cycle 58O preparation
#
# Consensus.xlsx 다중 sheets에서 market-wide aggregate features 추출.
# 약세 leading indicator (analyst downgrade wave = bear precursor).
#
# 5 key sheets × per-day aggregate:
#   1. EPS_Chg_3M (analyst 3-month revision)
#   2. EPS_Chg_1M (analyst 1-month revision)
#   3. SUE_지배 (standardized unexpected earnings, 지배주주)
#   4. ESBR(지배) (earnings surprise broad rate)
#   5. 커버리지 (analyst coverage)
#
# Per-day aggregates (PIT-safe, lag1):
#   - median (market consensus revision)
#   - % downgrade (< -5%)
#   - % upgrade (> +5%)
#   - dispersion (std)
#==============================================================================

suppressPackageStartupMessages({
  library(readxl); library(data.table); library(arrow)
})
options(warn = -1)

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
SRC <- file.path(PROJECT_ROOT, "03_Universe/Consensus.xlsx")
OUT_PATH <- file.path(WS, "outputs/01_data/consensus_aggregate_features.parquet")

# Read one sheet, return aggregate per-day features
extract_aggregate <- function(sheet_name, prefix) {
  cat(sprintf("[%s] Reading %s...\n",
              format(Sys.time(), "%H:%M:%S"), sheet_name))
  d <- as.data.table(read_excel(SRC, sheet = sheet_name, skip = 13,
                                col_names = FALSE, col_types = "text"))
  old_names <- names(d)
  setnames(d, old_names[1], "Date")
  # Date parsing
  d[, Date := as.Date(as.numeric(Date), origin = "1899-12-30")]
  d <- d[!is.na(Date)]
  # Convert all stock cols to numeric (NA for empty)
  stock_cols <- setdiff(names(d), "Date")
  for (col in stock_cols) {
    d[[col]] <- as.numeric(d[[col]])
  }
  cat(sprintf("  %d dates × %d stocks\n", nrow(d), length(stock_cols)))

  # Aggregate per row (per day)
  agg <- data.table(
    Date = d$Date,
    median = apply(d[, ..stock_cols], 1, median, na.rm = TRUE),
    sd_val = apply(d[, ..stock_cols], 1, sd, na.rm = TRUE),
    n_obs = apply(d[, ..stock_cols], 1, function(x) sum(!is.na(x)))
  )
  # downgrade/upgrade rate (threshold -5% / +5%)
  agg$pct_down <- apply(d[, ..stock_cols], 1, function(x) {
    if (sum(!is.na(x)) < 30) return(NA_real_)
    mean(x < -0.05, na.rm = TRUE)
  })
  agg$pct_up <- apply(d[, ..stock_cols], 1, function(x) {
    if (sum(!is.na(x)) < 30) return(NA_real_)
    mean(x > 0.05, na.rm = TRUE)
  })

  # PIT lag1
  setorder(agg, Date)
  out_cols <- c("median", "sd_val", "pct_down", "pct_up")
  for (col in out_cols) {
    agg[[paste0(prefix, "_", col, "_lag1")]] <- shift(agg[[col]], 1)
    agg[[col]] <- NULL
  }
  agg[, n_obs := NULL]

  cat(sprintf("  PIT features: %s\n",
              paste(paste0(prefix, "_", out_cols, "_lag1"), collapse=", ")))
  return(agg)
}

# Extract 5 key sheets
all_features <- NULL
for (item in list(
  list(sheet = "EPS_Chg_3M", prefix = "cons_eps_chg3m"),
  list(sheet = "EPS_Chg_1M", prefix = "cons_eps_chg1m"),
  list(sheet = "SUE_지배", prefix = "cons_sue"),
  list(sheet = "ESBR(지배)", prefix = "cons_esbr"),
  list(sheet = "커버리지", prefix = "cons_cov")
)) {
  tryCatch({
    f <- extract_aggregate(item$sheet, item$prefix)
    if (is.null(all_features)) {
      all_features <- f
    } else {
      all_features <- merge(all_features, f, by = "Date", all = TRUE)
    }
  }, error = function(e) {
    cat(sprintf("  ERROR in %s: %s\n", item$sheet, e$message))
  })
}

setorder(all_features, Date)
cat(sprintf("\n[%s] Final aggregate: %d dates × %d features\n",
            format(Sys.time(), "%H:%M:%S"),
            nrow(all_features), ncol(all_features) - 1))

# Validation
for (c in setdiff(names(all_features), "Date")) {
  v <- all_features[[c]]
  cat(sprintf("  %-32s n=%d  range=[%.4f, %.4f]\n", c, sum(!is.na(v)),
              min(v, na.rm = TRUE), max(v, na.rm = TRUE)))
}

write_parquet(all_features, OUT_PATH)
cat(sprintf("\n[%s] Saved: %s\n",
            format(Sys.time(), "%H:%M:%S"), OUT_PATH))
