suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RAWL <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad/RAWDATA_pin20260703_local.parquet"
suppressWarnings(try(arrow::set_io_thread_count(2L), silent=TRUE))
cat("io=",arrow::io_thread_count(),"\n"); flush.console()
cat("1 panel...\n"); flush.console()
p <- as.data.table(read_parquet(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/defense_factor_panel.parquet"))); cat("panel",nrow(p),"\n"); flush.console()
cat("2 AP...\n"); flush.console()
ap <- as.data.table(read_parquet(file.path(ED_ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))); cat("ap",nrow(ap),"\n"); flush.console()
cat("3 RAW local col_select...\n"); flush.console()
raw <- as.data.table(read_parquet(RAWL, col_select=c("Date","Ticker","Close","Vol","Ret"))); cat("raw",nrow(raw),"\n")
