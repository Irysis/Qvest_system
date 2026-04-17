# STR_1555: C19(50%) + V14(30%) + D01(20%) Score Blend
# 종목레벨 score 합산 → Top 30 단일 포트폴리오
# Asness et al.(2013) multifactor, Score blend (B2)
# PIT: Factor DB Z_Score_Aligned (C13)

cat("[factor_engine] STR_1555: Score Blend 3F (C19+V14+D01)...\n")
set.seed(1555)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD <- 2e8
NEEDED_FACTORS <- c("C19_Composite_Earnings", "V14_EBIT_EV", "D01_IdioVol")
WEIGHTS <- c(C19_Composite_Earnings = 0.50, V14_EBIT_EV = 0.30, D01_IdioVol = 0.20)

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

  # Weighted RankCombo score blend
  fdt_wide[, Score := 0.0]
  total_w <- 0
  for (fn in NEEDED_FACTORS) {
    w <- WEIGHTS[fn]
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      fdt_wide[, paste0("R_", fn) := frank(get(fn), na.last = "keep", ties.method = "average") /
                   sum(!is.na(get(fn)))]
      fdt_wide[, Score := Score + w * get(paste0("R_", fn))]
      total_w <- total_w + w
    }
  }
  if (total_w == 0) { n_skipped <- n_skipped + 1L; next }
  fdt_wide[, Score := Score / total_w]

  fdt_wide[, Date := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_ALL); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))
