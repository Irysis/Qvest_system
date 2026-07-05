Sys.setenv(LC_ALL = "English_United States.utf8")
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
data.table::setDTthreads(1L)
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
FDB_MIN <- as.Date("2005-01-01")
res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
cat("CK1 loaded\n"); flush.console()
if (!inherits(RAWDATA$Date,"Date")) RAWDATA[, Date := as.Date(Date)]
rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
rm(RAWDATA); gc(FALSE)
cat("CK2 rd rows=", nrow(rd), "\n"); flush.console()
setorder(rd, Ticker, Date)
rd[, ym := format(Date, "%Y-%m")]
me_dates <- sort(rd[, .(Date=max(Date)), by=ym]$Date)
me_dates <- me_dates[me_dates >= FDB_MIN]
rd[, ym := NULL]
cat("CK3 me_dates=", length(me_dates), "\n"); flush.console()
rd[, TV := Close * Vol]
rd[, AvgTV20 := frollmean(TV, 20L, align="right"), by=Ticker]
cat("CK4 frollmean done\n"); flush.console()
me <- rd[Date %in% me_dates, .(Date, Ticker, Close, K200, KQ150, AvgTV20)]
setorder(me, Ticker, Date)
me[, Ret_1m := shift(Close, -1L)/Close - 1, by=Ticker]
cat("CK5 forward ret done rows=", nrow(me), "\n"); flush.console()
me[, in_univ := (K200==TRUE | KQ150==TRUE) & !is.na(AvgTV20) & AvgTV20 >= 2e8]
cat("CK6 univ. n_univ_rows=", me[in_univ==TRUE,.N], "\n"); flush.console()
