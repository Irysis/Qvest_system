suppressMessages({library(arrow); library(data.table)})
p <- file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), ".cache/dart/dart_raw_quarterly.parquet")
sch <- arrow::open_dataset(p)$schema
cat("COLS:\n"); print(names(sch))
dt <- as.data.table(arrow::read_parquet(p))
cat("\nNROW:", nrow(dt), "\n")
cat("\nreprt_code:\n"); print(table(dt$reprt_code, useNA="always"))
cat("\nbsns_year:\n"); print(table(dt$bsns_year, useNA="always"))
cat("\nfs_div:\n"); print(table(dt$fs_div, useNA="always"))
cat("\nsj_div:\n"); print(table(dt$sj_div, useNA="always"))
cat("\nrcept_no sample (first 8 chars = receipt date):\n"); print(head(unique(dt$rcept_no), 10))
cat("\nTicker sample:\n"); print(head(unique(dt$Ticker), 10))
cat("\nTicker class:", class(dt$Ticker), " | nchar sample:", nchar(head(dt$Ticker,3)), "\n")
# receipt date range
rd <- as.Date(substr(dt$rcept_no, 1, 8), format="%Y%m%d")
cat("\nreceipt date range:", as.character(min(rd, na.rm=TRUE)), "->", as.character(max(rd, na.rm=TRUE)), "\n")
cat("NA receipt dates:", sum(is.na(rd)), "\n")
# rows per (rcept_no) -> account count distribution
acc <- dt[, .N, by=.(rcept_no)]
cat("\naccount rows per filing (rcept_no) summary:\n"); print(summary(acc$N))
# distinct filings per year
filings <- unique(dt[, .(rcept_no, bsns_year, reprt_code)])
cat("\ndistinct filings per bsns_year:\n"); print(filings[, .N, by=bsns_year][order(bsns_year)])
