## STR_1469 Phase 1d: Consensus 4F sleeve (replaces ConsGate Pure)
## C19+C13+C10+C04(ESBR) from Factor DB
## C13: Z_Score_Aligned. C15: Arrow Dataset.
cat("[factor_engine] STR_1469 Consensus 4F sleeve (C19+C13+C10+C04)...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
NEEDED_FACTORS <- c("C19_Composite_Earnings", "C13_Revision_Breadth_3m",
                     "C10_SUE_Persistence", "C04_ESBR")
WEIGHTS <- c(0.25, 0.25, 0.25, 0.25)

FDB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db")
library(arrow)
ds <- open_dataset(FDB_DIR, format = "parquet")
FDB_RAW <- ds |>
  dplyr::filter(Factor_Name %in% NEEDED_FACTORS) |>
  dplyr::collect() |>
  as.data.table()

registry <- .load_registry()
FDB_ALL <- align_factor_direction(FDB_RAW, registry)
FDB_ALL[, Date := as.Date(Date)]
setkey(FDB_ALL, Date, Ticker)
rm(FDB_RAW, ds); gc(verbose = FALSE)

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
signal_dates <- signal_dates[signal_dates >= as.Date("2005-07-01")]

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

  dt[, Score := 0]
  for (j in seq_along(NEEDED_FACTORS)) {
    fn <- NEEDED_FACTORS[j]
    if (fn %in% names(dt)) {
      vals <- dt[[fn]]; vals[is.na(vals)] <- 0
      dt[, Score := Score + WEIGHTS[j] * vals]
    }
  }
  dt <- dt[!is.na(Score)]
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

cat(sprintf("  Consensus 4F FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip))
