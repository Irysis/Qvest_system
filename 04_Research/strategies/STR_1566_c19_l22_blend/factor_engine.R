# Factor Engine: STR_1566_c19_l22_blend
# C19 60% + L22 40% Score Blend — STR_1558 S5 M1
# Consensus Core Alpha + Microstructure Diversifier
# C19-L22 corr = -0.108 (음의 상관! 최적 diversification)

cat("[Factor Engine] C19 60% + L22 40% Score Blend\n")

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

  # Extract C19 and L22
  c19 <- fdt[Factor_Name == "C19_Composite_Earnings" & !is.na(Z_Score_Aligned),
             .(Ticker, C19_Z = Z_Score_Aligned)]
  l22 <- fdt[Factor_Name == "L22_Ret_Autocorr" & !is.na(Z_Score_Aligned),
             .(Ticker, L22_Z = Z_Score_Aligned)]

  if (nrow(c19) == 0 || nrow(l22) == 0) return(NULL)

  # Merge and blend
  blend <- merge(c19, l22, by = "Ticker")
  blend[, Score := 0.6 * C19_Z + 0.4 * L22_Z]
  blend[, Date := sd]

  blend[, .(Date, Ticker, Score)]
}))

cat(sprintf("[Factor Engine] FACTORS: %d rows, %d dates, %d tickers\n",
            nrow(FACTORS), length(unique(FACTORS$Date)), length(unique(FACTORS$Ticker))))
