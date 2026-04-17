# Factor Engine: STR_1563_price_level_liquidity
# L27_Price_Level 단독 — Hwang & Lu (2007) price level effect
# S1 순수 팩터 테스트 (no overlay)

cat("[Factor Engine] L27_Price_Level standalone\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

# Monthly signal dates (month-end)
all_dates <- sort(unique(RAWDATA$Date))
RAWDATA[, YM_tmp := format(Date, "%Y-%m")]
sig_dates <- RAWDATA[, .(SigDate = max(Date)), by = YM_tmp][order(YM_tmp)]$SigDate
RAWDATA[, YM_tmp := NULL]

cat(sprintf("[Factor Engine] Processing %d signal dates...\n", length(sig_dates)))

FACTORS <- rbindlist(lapply(sig_dates, function(sd) {
  fdt <- tryCatch(
    load_month_factors(sd, coverage_min = 0.01),
    error = function(e) NULL
  )
  if (is.null(fdt) || nrow(fdt) == 0) return(NULL)

  fdt <- fdt[Factor_Name == "L27_Price_Level" & !is.na(Z_Score_Aligned)]
  if (nrow(fdt) == 0) return(NULL)

  data.table(Date = sd, Ticker = fdt$Ticker, Score = fdt$Z_Score_Aligned)
}))

cat(sprintf("[Factor Engine] FACTORS: %d rows, %d dates, %d tickers\n",
            nrow(FACTORS), length(unique(FACTORS$Date)), length(unique(FACTORS$Ticker))))
