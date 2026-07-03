suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1L)
cat("io threads default:", arrow::io_thread_count(), "\n"); flush.console()
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
cat("reading pinned RAWDATA col_select...\n"); flush.console()
raw <- as.data.table(read_parquet(file.path(ED_ROOT,".cache/RAWDATA_pin20260703.parquet"),
         col_select=c("Date","Ticker","Close","Vol","Ret")))
cat("OK nrow=", nrow(raw), "\n")
