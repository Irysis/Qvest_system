suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Close","Vol")))
rd[, Date := as.Date(Date)]; rd <- rd[Date >= as.Date("2015-11-01")]
setorder(rd, Ticker, Date)
rd[, trade_val := Vol * Close]
rd[, adv20 := frollmean(trade_val, 20, align="right"), by=Ticker]
rd[, ym := format(Date,"%Y-%m")]
adv <- rd[, .(adv20 = last(adv20)), by=.(Ticker, ym)]
saveRDS(adv, file.path(TMP,"wt008_adv.rds"))
cat("adv rows:", nrow(adv), "\n")
cat("adv20 KRW summary:\n"); print(summary(adv$adv20))
