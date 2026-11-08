#==============================================================================
# build_fundamental_derived.R
# Compute 140 derived fundamental items from XLSX raw items (2000~2015)
# and merge into fundamental_merged.parquet for continuous 2000~2026 series.
#
# Logic:
#   1. Load fundamental_xlsx.parquet (41 raw items, long format)
#   2. Pivot to wide (Ticker x Period), compute averages, derive 140 items
#   3. Melt back to long, mark Source = "xlsx_derived"
#   4. Merge with existing fundamental_merged.parquet (DART priority 2016+)
#   5. Save updated fundamental_merged.parquet
#
# Formulas replicate data_collector_dart.R exactly.
# Growth/delta items use shift() by Ticker (need consecutive periods).
#==============================================================================

cat("=== build_fundamental_derived.R ===\n")
cat("Start:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ---- Paths ----
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
XLSX_PATH    <- file.path(CACHE_DIR, "fundamental_xlsx.parquet")
MERGED_PATH  <- file.path(CACHE_DIR, "fundamental_merged.parquet")
BACKUP_PATH  <- file.path(CACHE_DIR, "fundamental_merged_backup.parquet")

stopifnot(file.exists(XLSX_PATH), file.exists(MERGED_PATH))

# ---- 1. Load XLSX raw data ----
cat("[1/5] Loading fundamental_xlsx.parquet...\n")
xlsx_long <- as.data.table(read_parquet(XLSX_PATH))
cat(sprintf("  Rows: %s | Tickers: %d | Items: %d | Periods: %d\n",
            format(nrow(xlsx_long), big.mark = ","),
            uniqueN(xlsx_long$Ticker),
            uniqueN(xlsx_long$Item),
            uniqueN(xlsx_long$Period)))

# ---- 2-4. Derived items (formulas moved verbatim to fundamental_derive_items.R, 2026-11-09) ----
source(file.path(PROJECT_ROOT, "02_Infrastructure", "data", "fundamental_derive_items.R"))
xlsx_long <- xlsx_long[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value)]  # as the moved step 2 did
derived_long <- derive_fundamental_items(xlsx_long)

# ---- 5. Rebuild merged from XLSX raw + DART + derived ----
cat("[5/5] Rebuilding merged from source data...\n")

# Strategy: rebuild from scratch to avoid corrupted file reads.
# Load DART and XLSX raw separately, then combine with derived.

# Load DART data
DART_PATH <- file.path(CACHE_DIR, "fundamental_dart.parquet")
if (file.exists(DART_PATH)) {
  dt_dart <- as.data.table(read_parquet(DART_PATH))
  cat(sprintf("  DART loaded: %s rows x %d cols\n", format(nrow(dt_dart), big.mark=","), ncol(dt_dart)))
  # DART: wide -> long
  dart_id <- c("Ticker", "bsns_year", "Factor_Date")
  dart_val <- setdiff(names(dt_dart), dart_id)
  dart_num <- dart_val[sapply(dart_val, function(x) is.numeric(dt_dart[[x]]))]
  # Coerce all to double before melt
  for (col in dart_num) {
    if (!is.double(dt_dart[[col]])) dt_dart[, (col) := as.double(get(col))]
  }
  dart_long <- melt(dt_dart, id.vars = dart_id, measure.vars = dart_num,
                    variable.name = "Item", value.name = "Value",
                    variable.factor = FALSE)
  dart_long <- dart_long[!is.na(Value)]
  dart_long[, Source := "DART"]
  dart_long[, Period := paste0(bsns_year, "12")]
  dart_long[, Period_Date := as.Date(paste0(bsns_year, "-12-31"))]
  dart_long[, bsns_year := NULL]
  cat(sprintf("  DART long: %s rows, %d items\n", format(nrow(dart_long), big.mark=","), uniqueN(dart_long$Item)))
} else {
  dart_long <- data.table(Ticker=character(), Period=character(), Period_Date=as.Date(character()),
                          Factor_Date=as.Date(character()), Item=character(), Value=numeric(), Source=character())
  cat("  DART: NOT FOUND (skipping)\n")
}

# Load XLSX raw data (already loaded as xlsx_long at top)
xlsx_raw <- copy(xlsx_long)
xlsx_raw[, Source := "XLSX"]
cat(sprintf("  XLSX raw: %s rows\n", format(nrow(xlsx_raw), big.mark=",")))

# DART takes priority: remove XLSX-derived rows that overlap with DART
# First, remove derived rows overlapping with DART (Ticker + Item + Factor_Date)
if (nrow(dart_long) > 0) {
  dart_keys <- unique(dart_long[, .(Ticker, Item, Factor_Date)])
  setkeyv(dart_keys, c("Ticker", "Item", "Factor_Date"))
  setkeyv(derived_long, c("Ticker", "Item", "Factor_Date"))
  n_before <- nrow(derived_long)
  derived_long <- derived_long[!dart_keys]
  n_removed <- n_before - nrow(derived_long)
  cat(sprintf("  Removed %s DART-overlapping derived rows\n", format(n_removed, big.mark=",")))
}

# Ensure consistent column set
cols_keep <- c("Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value", "Source")
xlsx_raw <- xlsx_raw[, ..cols_keep]
dart_out <- dart_long[, ..cols_keep]
derived_out <- derived_long[, ..cols_keep]

# Combine all three sources
merged <- rbindlist(list(xlsx_raw, dart_out, derived_out), use.names = TRUE)

# Deduplicate: same Ticker + Period + Item -> DART > xlsx_derived > XLSX
# Assign priority: DART=1, xlsx_derived=2, XLSX=3
merged[, src_priority := fifelse(Source == "DART", 1L,
                           fifelse(Source == "xlsx_derived", 2L, 3L))]
setorder(merged, Ticker, Period, Item, src_priority)
merged[, rank := seq_len(.N), by = .(Ticker, Period, Item)]
merged <- merged[rank == 1L]
merged[, c("src_priority", "rank") := NULL]
setorder(merged, Ticker, Item, Factor_Date)

cat(sprintf("  Final merged: %s rows | %d unique items | %d tickers\n",
            format(nrow(merged), big.mark = ","),
            uniqueN(merged$Item),
            uniqueN(merged$Ticker)))

# Verify derived items now have pre-2016 coverage
pre2016_derived <- merged[Source == "xlsx_derived" & Factor_Date < as.Date("2016-01-01")]
cat(sprintf("  Pre-2016 derived rows: %s\n", format(nrow(pre2016_derived), big.mark = ",")))
cat(sprintf("  Pre-2016 derived items: %d\n", uniqueN(pre2016_derived$Item)))

# Spot check key items
for (item in c("GPA", "ROE", "ROA", "Accrual", "PiotroskiF", "AltmanZ", "CurrentRatio")) {
  item_rows <- merged[Item == item]
  if (nrow(item_rows) > 0) {
    cat(sprintf("  %-15s: %s~%s (%s rows, %d tickers)\n",
                item,
                as.character(min(item_rows$Factor_Date)),
                as.character(max(item_rows$Factor_Date)),
                format(nrow(item_rows), big.mark = ","),
                uniqueN(item_rows$Ticker)))
  }
}

# Arrow has a thrift metadata size limit for single-parquet files.
# 19M rows exceeds this limit. Strategy:
#
# 1. Save ALL derived items to fundamental_xlsx_derived.parquet (backup/reference)
# 2. For fundamental_merged.parquet (used by factor_db_builder):
#    - Keep XLSX raw (41 items) + DART (181 items, 2016+)
#    - Add ONLY the key derived intermediates that compute_*.R modules actually
#      request from FUND via Item lookup: NetIncome, TotalDebt, NOPAT
#    - This keeps the file under the thrift limit while enabling all factor computation
#
# The compute modules (compute_quality.R, compute_accrual.R, etc.) compute
# GPA/ROE/Accrual etc. themselves from raw items. They only need raw FUND Items
# plus NetIncome (= PretaxIncome - TaxExpense) as a derived intermediate.

DERIVED_PATH <- file.path(CACHE_DIR, "fundamental_xlsx_derived.parquet")

# Save ALL 140 derived items separately (full reference file)
write_parquet(derived_out, DERIVED_PATH,
              compression = "zstd", compression_level = 3L,
              write_statistics = FALSE)
cat(sprintf("\n  Derived (all 140) saved to: %s (%.1f MB)\n",
            DERIVED_PATH, file.info(DERIVED_PATH)$size / 1024^2))

# For the merged file, include only items that compute modules need from FUND:
# - All 41 raw XLSX items (already in xlsx_raw)
# - Key derived intermediates the compute modules request by Item name
compute_needed_derived <- c("NetIncome", "TotalDebt", "NOPAT")
slim_derived <- derived_out[Item %in% compute_needed_derived]
cat(sprintf("  Slim derived (items compute modules need): %s rows\n",
            format(nrow(slim_derived), big.mark = ",")))

# Combine: XLSX raw + DART + slim derived
merged_slim <- rbindlist(list(xlsx_raw, dart_out, slim_derived), use.names = TRUE)

# Deduplicate
merged_slim[, src_priority := fifelse(Source == "DART", 1L,
                                fifelse(Source == "xlsx_derived", 2L, 3L))]
setorder(merged_slim, Ticker, Period, Item, src_priority)
merged_slim[, rank := seq_len(.N), by = .(Ticker, Period, Item)]
merged_slim <- merged_slim[rank == 1L]
merged_slim[, c("src_priority", "rank") := NULL]

cat(sprintf("  Slim merged: %s rows | %d items\n",
            format(nrow(merged_slim), big.mark = ","),
            uniqueN(merged_slim$Item)))

# Save
write_parquet(merged_slim, MERGED_PATH,
              compression = "zstd", compression_level = 5L,
              write_statistics = FALSE)
cat(sprintf("  Saved to: %s (%.1f MB)\n",
            MERGED_PATH, file.info(MERGED_PATH)$size / 1024^2))

cat("\n=== build_fundamental_derived.R COMPLETE ===\n")
cat("End:", as.character(Sys.time()), "\n")
