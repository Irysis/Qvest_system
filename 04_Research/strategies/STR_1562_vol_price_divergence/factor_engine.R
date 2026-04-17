# Factor Engine: STR_1562_vol_price_divergence
# CR08_Volume_Price_Divergence 단독 — Blume et al (1994) volume information
# Factor DB ICIR 0.917. S1 순수 팩터 테스트 (no overlay)

cat("[Factor Engine] CR08_Volume_Price_Divergence standalone (ICIR 0.917)\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

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
  fdt <- fdt[Factor_Name == "CR08_Volume_Price_Divergence" & !is.na(Z_Score_Aligned)]
  if (nrow(fdt) == 0) return(NULL)
  data.table(Date = sd, Ticker = fdt$Ticker, Score = fdt$Z_Score_Aligned)
}))

cat(sprintf("[Factor Engine] FACTORS: %d rows, %d dates, %d tickers\n",
            nrow(FACTORS), length(unique(FACTORS$Date)), length(unique(FACTORS$Ticker))))
