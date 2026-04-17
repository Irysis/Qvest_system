## STR_1471: S5 M2_D01_R10_GATE — D01 Scoring + R10 Bottom Gate
## D01_IdioVol scoring + R10_Cokurtosis bottom 10% exclusion gate
## S5: R10 standalone alpha 부재 → 종목 제외용으로 전환. D01 = 검증된 primary alpha.
## C13: Z_Score_Aligned. C15: Arrow Dataset bulk load.

cat("[factor_engine] STR_1471 S5: D01 scoring + R10 gate(bottom 10% excl)...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

NEEDED_FACTORS <- c("D01_IdioVol", "R10_Cokurtosis")
GATE_FACTOR    <- "R10_Cokurtosis"
SCORE_FACTOR   <- "D01_IdioVol"
GATE_EXCL_PCT  <- 0.10  # exclude bottom 10% by R10 (worst cokurtosis)

FDB_DIR <- file.path(CACHE_DIR, "factor_db")
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

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"),
                            1L, type = "lag"), by = Ticker]

factor_list <- vector("list", length(signal_dates))
n_done <- 0L; n_skip <- 0L; n_gate_stats <- integer(0)

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

  if (!(GATE_FACTOR %in% names(dt)) || !(SCORE_FACTOR %in% names(dt))) {
    n_skip <- n_skip + 1L; next
  }

  dt <- dt[!is.na(get(GATE_FACTOR)) & !is.na(get(SCORE_FACTOR))]
  if (nrow(dt) < 30) { n_skip <- n_skip + 1L; next }

  # Gate: exclude bottom 10% by R10 (worst tail risk)
  gate_cutoff <- quantile(dt[[GATE_FACTOR]], probs = GATE_EXCL_PCT, na.rm = TRUE)
  dt_gated <- dt[get(GATE_FACTOR) >= gate_cutoff]
  n_gate_stats <- c(n_gate_stats, nrow(dt_gated))

  if (nrow(dt_gated) < 15) { n_skip <- n_skip + 1L; next }

  # Score: rank by D01 (IdioVol — verified primary alpha)
  dt_gated[, Score := get(SCORE_FACTOR)]
  dt_gated[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  dt_gated[, Date := sig_d]
  factor_list[[i]] <- dt_gated[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_ALL); gc(verbose = FALSE)

cat(sprintf("  FACTORS: %s rows | %d dates (skip %d) | gate median: %d stocks\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip,
            as.integer(median(n_gate_stats, na.rm = TRUE))))
