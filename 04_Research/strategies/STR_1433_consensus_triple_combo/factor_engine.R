# STR_1433: Consensus Triple Combo (C19 + C13 + C10)
# 3-factor RankCombo: "earnings level + breadth + persistence" = 3-dimensional consensus
# C19_Composite_Earnings (ICIR 0.575, Grade A 14 passes)
# C13_Revision_Breadth (ICIR 0.412)
# C10_SUE_Persistence (ICIR 0.389)
# Intra-category combo for alpha decay resistance via multi-axis diversification.
#
# PIT: All consensus-based (immediate, no lag). Z_Score_Aligned (C13). C14/C15.

cat("[factor_engine] STR_1433: Consensus Triple Combo (C19+C13+C10)...\n")
set.seed(1433)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD  <- 2e8
NEEDED_FACTORS <- c("C19_Composite_Earnings", "C13_Revision_Breadth", "C10_SUE_Persistence")

ds <- open_dataset(file.path(CACHE_DIR, "factor_db"), format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows | factors: %s\n", nrow(FDB_ALL),
            paste(unique(FDB_ALL$Factor_Name), collapse = ", ")))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

fdb_dates <- sort(unique(FDB_ALL$Date))
factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  valid_fdb <- fdb_dates[fdb_dates <= sig_d]
  if (length(valid_fdb) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdb_d <- max(valid_fdb)
  fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  # 3-factor RankCombo: EW average of percentile ranks
  fdt_wide[, Score := 0.0]
  nc <- 0L
  for (fn in NEEDED_FACTORS) {
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) >= 10L) {
      fdt_wide[, (paste0("r_", fn)) :=
        frank(get(fn), na.last = "keep", ties.method = "average") / sum(!is.na(get(fn)))]
      fdt_wide[, Score := Score + fifelse(is.na(get(paste0("r_", fn))), 0.5,
                                          get(paste0("r_", fn)))]
      nc <- nc + 1L
    }
  }
  if (nc == 0L) { n_skipped <- n_skipped + 1L; next }
  fdt_wide[, Score := Score / nc]

  fdt_wide[, Date := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

for (col in c("YM", "TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_ALL, ds); gc(verbose = FALSE)

cat(sprintf("[factor_engine] STR_1433 Consensus Triple: %d rows | %d dates (skipped %d)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped))
