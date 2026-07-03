suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1L)
RAWL <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad/RAWDATA_pin20260703_local.parquet"
tb <- read_parquet(RAWL, as_data_frame=FALSE)
raw <- as.data.table(as.data.frame(tb[c("Date","Ticker","Close","Vol","Ret")]))
cat("via table: "); print(sapply(raw, class))
cat("Ret NA frac:", mean(is.na(raw$Ret)), " Close NA:", mean(is.na(raw$Close)), "\n")
cat("Date class:", class(raw$Date), " sample:", as.character(raw$Date[1]), "\n")
