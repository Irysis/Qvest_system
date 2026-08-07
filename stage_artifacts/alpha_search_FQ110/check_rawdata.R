source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
cat(paste0("COLS=", paste(names(RAWDATA), collapse="|"), "\n"))
cat(paste0("NROW=", nrow(RAWDATA), "\n"))
cat(paste0("DATE_MIN=", as.character(min(RAWDATA$Date)), "\n"))
cat(paste0("DATE_MAX=", as.character(max(RAWDATA$Date)), "\n"))
cat(paste0("HAS_RET=", ("Ret" %in% names(RAWDATA)), "\n"))
cat(paste0("HAS_K200=", ("K200" %in% names(RAWDATA)), "\n"))
cat(paste0("HAS_KQ150=", ("KQ150" %in% names(RAWDATA)), "\n"))
cat(paste0("HAS_SIZE=", ("Size" %in% names(RAWDATA)), "\n"))
# sample head
print(head(RAWDATA[, .(Date, Ticker, Close, Vol)], 3))
