## STR_1500: R01_VaR_95 Single Factor (S1 Pure)
## C13: Z_Score_Aligned only. C15: Arrow Dataset bulk load.
cat("[factor_engine] STR_1500: R01_VaR_95 standalone...\n")
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
NEEDED_FACTORS <- c("R01_VaR_95")
FDB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db"); library(arrow)
ds <- open_dataset(FDB_DIR, format = "parquet")
FDB_RAW <- ds |> dplyr::filter(Factor_Name %in% NEEDED_FACTORS) |> dplyr::collect() |> as.data.table()
cat(sprintf("  Loaded: %s rows\n", format(nrow(FDB_RAW), big.mark = ",")))
registry <- .load_registry(); FDB_ALL <- align_factor_direction(FDB_RAW, registry)
FDB_ALL[, Date := as.Date(Date)]; setkey(FDB_ALL, Date, Ticker); rm(FDB_RAW, ds); gc(verbose = FALSE)
setorder(RAWDATA, Ticker, Date); RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"), 1L, type = "lag"), by = Ticker]
factor_list <- vector("list", length(signal_dates)); n_done <- 0L; n_skip <- 0L
for (i in seq_along(signal_dates)) {
  sig_d <- as.Date(signal_dates[i])
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector)]
  snap <- snap[!is.na(Close) & Close > 0 & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 30) { n_skip <- n_skip + 1L; next }
  fdt <- FDB_ALL[Date == sig_d & Factor_Name %in% NEEDED_FACTORS, .(Ticker, Factor_Name, Z_Score_Aligned)]
  if (nrow(fdt) == 0) { n_skip <- n_skip + 1L; next }
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  dt <- merge(snap, fdt_wide, by = "Ticker")
  fcols <- intersect(NEEDED_FACTORS, names(dt)); if (length(fcols) == 0) { n_skip <- n_skip + 1L; next }
  dt[, Score := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]; dt <- dt[!is.na(Score)]
  dt[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]; dt[, Date := sig_d]
  factor_list[[i]] <- dt[!is.na(Score), .(Date, Ticker, Score)]; n_done <- n_done + 1L
}
FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)]); setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) { if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL] }
rm(FDB_ALL); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n", format(nrow(FACTORS), big.mark = ","), n_done, n_skip))
