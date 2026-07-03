suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1L)
RAWL <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad/RAWDATA_pin20260703_local.parquet"
suppressWarnings(try(arrow::set_io_thread_count(2L), silent=TRUE))
# mimic harness: read two small OneDrive parquets first
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
p <- as.data.table(read_parquet(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/defense_factor_panel.parquet")))
ap <- as.data.table(read_parquet(file.path(ED_ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
cat("smalls ok. now RAW as_data_frame=FALSE then select...\n"); flush.console()
tb <- read_parquet(RAWL, as_data_frame=FALSE)
cat("table read, cols:", paste(names(tb),collapse=","), "\n"); flush.console()
raw <- as.data.table(as.data.frame(tb[c("Date","Ticker","Close","Vol","Ret")]))
cat("RAW ok nrow=", nrow(raw), "\n")
