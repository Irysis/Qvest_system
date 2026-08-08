suppressPackageStartupMessages({library(data.table); library(arrow)})
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Size","K200","KQ150")))
R[, Date := as.Date(Date)]
cat(sprintf("RAWDATA range: %s ~ %s (%d days)\n", min(R$Date), max(R$Date), uniqueN(R$Date)))
u <- R[K200==TRUE | KQ150==TRUE]
cat(sprintf("K200|KQ150 membership: %s ~ %s\n", min(u$Date), max(u$Date)))
sz <- u[!is.na(Size)]
cat(sprintf("Size non-missing: %s ~ %s\n", min(sz$Date), max(sz$Date)))
u[, ym := format(Date,"%Y-%m")]
cat(sprintf("universe months: %d\n", uniqueN(u$ym)))
sz[, ym := format(Date,"%Y-%m")]
cat(sprintf("months with Size: %d\n", uniqueN(sz$ym)))
