suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCRATCH <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
src <- file.path(ED_ROOT,".cache/RAWDATA_pin20260703.parquet")
dst <- file.path(SCRATCH,"RAWDATA_pin20260703_local.parquet")
if(!file.exists(dst)){ cat("copying to local temp...\n"); flush.console(); file.copy(src,dst,overwrite=TRUE) }
cat("reading local copy col_select...\n"); flush.console()
raw <- as.data.table(read_parquet(dst, col_select=c("Date","Ticker","Close","Vol","Ret")))
cat("OK local nrow=", nrow(raw), "\n")
