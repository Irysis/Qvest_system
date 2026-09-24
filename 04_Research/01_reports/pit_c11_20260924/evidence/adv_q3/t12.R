suppressPackageStartupMessages({library(arrow); library(data.table); library(dplyr)})
C <- "C:/qm_cache"
g <- function(ym) as.data.table(open_dataset(file.path(C,"factor_db_daily",sprintf("fdb_daily_%s.parquet",ym))) %>% select(Date,Ticker,D08_Tail_Beta) %>% collect())
a <- g("200801"); b <- g("202003"); c <- g("202606")
x <- merge(a[, .(D08_2008=D08_Tail_Beta[1], nuniq08=uniqueN(D08_Tail_Beta)), by=Ticker], b[, .(D08_2020=D08_Tail_Beta[1]), by=Ticker], by="Ticker")
x <- merge(x, c[, .(D08_2026=D08_Tail_Beta[1]), by=Ticker], by="Ticker")
cat(sprintf("tickers in 2008,2020,2026: %d | share D08 identical 2008 vs 2026 (1e-12): %.3f | within-month unique values median: %s\n", nrow(x), mean(abs(x$D08_2008-x$D08_2026)<1e-12, na.rm=TRUE), median(x$nuniq08)))
print(head(x,3))
