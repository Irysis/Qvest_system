# STR_1435: Earnings Stability Gate on Defense (D01+D02 scoring, Q07 bottom gate)
# RC_05 simplified: instead of regime-conditional weighting, use Q07 as gate.
# Defense (D01+D02) with Q07_Earnings_Stability bottom 15% excluded.
# Rationale: Q07 ICIR=0.382 overall but 0.929 recent 3Y. Remove unstable-earnings stocks
# from Defense universe to improve quality without adding complexity.
#
# PIT: D01/D02 price (t-1). Q07 quarterly -> 45d lag (C4). C13/C15.

cat("[factor_engine] STR_1435: Earnings Stability Gate on Defense...\n")
set.seed(1435)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD  <- 2e8
SCORING_FACTORS <- c("D01_IdioVol", "D02_Beta")
GATE_FACTOR <- "Q07_Earnings_Stability"
GATE_EXCLUDE_PCT <- 0.15  # Bottom 15% excluded
NEEDED_FACTORS <- c(SCORING_FACTORS, GATE_FACTOR)

ds <- open_dataset(file.path(CACHE_DIR, "factor_db"), format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows\n", nrow(FDB_ALL)))

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

  # Gate: exclude bottom 15% of Q07
  if (GATE_FACTOR %in% names(fdt_wide)) {
    q_vals <- fdt_wide[[GATE_FACTOR]]
    q_valid <- !is.na(q_vals)
    if (sum(q_valid) >= 20L) {
      threshold <- quantile(q_vals[q_valid], probs = GATE_EXCLUDE_PCT, na.rm = TRUE)
      fdt_wide <- fdt_wide[is.na(get(GATE_FACTOR)) | get(GATE_FACTOR) >= threshold]
    }
  }

  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  # Defense scoring: EW percentile rank of D01 + D02
  fdt_wide[, Score := 0.0]
  nc <- 0L
  for (fn in SCORING_FACTORS) {
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

cat(sprintf("[factor_engine] STR_1435 Defense+EarningsGate: %d rows | %d dates (skipped %d)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped))
