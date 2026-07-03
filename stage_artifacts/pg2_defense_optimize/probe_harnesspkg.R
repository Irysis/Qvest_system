suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
options(scipen=999); setDTthreads(1L)
suppressWarnings(try(arrow::set_io_thread_count(2L), silent=TRUE))
RAWL <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad/RAWDATA_pin20260703_local.parquet"
cat("reading col_select...\n"); flush.console()
raw <- as.data.table(read_parquet(RAWL, col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date := as.Date(Date)]
cat("read+asDate OK nrow=", nrow(raw), "\n"); flush.console()
raw <- raw[Date >= as.Date("2005-01-01")]
cat("sliced nrow=", nrow(raw), "\n"); flush.console()
raw[, TradingAmt := Close*Vol]; setkey(raw, Date, Ticker)
cat("keyed OK\n")
