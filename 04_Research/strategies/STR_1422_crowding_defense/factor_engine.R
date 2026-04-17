## STR_1422: Crowding x Defense 2-Factor Score Blend
## CR08_Volume_Price_Divergence + D01_IdioVol (L-554: crowding untried)
## C13: Z_Score_Aligned via align_factor_direction(). No manual NEGATE.
## C15: Arrow Dataset bulk load (NOT load_month_factors loop).

cat("[factor_engine] STR_1422: CR08(VolPriceDivergence) + D01(IdioVol) score blend...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

NEEDED_FACTORS <- c("CR08_Volume_Price_Divergence", "D01_IdioVol")
W1 <- 0.5; W2 <- 0.5

FDB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db")
cat(sprintf("  Factor DB: %s\n", FDB_DIR))

library(arrow)
ds <- open_dataset(FDB_DIR, format = "parquet")
FDB_RAW <- ds |>
  dplyr::filter(Factor_Name %in% NEEDED_FACTORS) |>
  dplyr::collect() |>
  as.data.table()
cat(sprintf("  Loaded: %s rows, %d factors\n",
            format(nrow(FDB_RAW), big.mark = ","), uniqueN(FDB_RAW$Factor_Name)))

registry <- .load_registry()
FDB_ALL <- align_factor_direction(FDB_RAW, registry)
FDB_ALL[, Date := as.Date(Date)]
setkey(FDB_ALL, Date, Ticker)
rm(FDB_RAW, ds); gc(verbose = FALSE)

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]
cat(sprintf("  Signal dates: %d (%s ~ %s)\n",
            length(signal_dates), min(signal_dates), max(signal_dates)))

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"),
                            1L, type = "lag"), by = Ticker]

factor_list <- vector("list", length(signal_dates))
n_done <- 0L; n_skip <- 0L

for (i in seq_along(signal_dates)) {
  sig_d <- as.Date(signal_dates[i])
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector)]
  snap <- snap[!is.na(Close) & Close > 0 & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 30) { n_skip <- n_skip + 1L; next }

  fdt <- FDB_ALL[Date == sig_d & Factor_Name %in% NEEDED_FACTORS,
                 .(Ticker, Factor_Name, Z_Score_Aligned)]
  if (nrow(fdt) == 0) { n_skip <- n_skip + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  dt <- merge(snap, fdt_wide, by = "Ticker")

  f1 <- NEEDED_FACTORS[1]; f2 <- NEEDED_FACTORS[2]
  if (!(f1 %in% names(dt)) || !(f2 %in% names(dt))) { n_skip <- n_skip + 1L; next }

  dt <- dt[!is.na(get(f1)) & !is.na(get(f2))]
  if (nrow(dt) < 30) { n_skip <- n_skip + 1L; next }

  dt[, Score := W1 * get(f1) + W2 * get(f2)]
  dt[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  dt[, Date := sig_d]
  factor_list[[i]] <- dt[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_ALL); gc(verbose = FALSE)

cat(sprintf("  FACTORS: %s rows | %d signal dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip))
