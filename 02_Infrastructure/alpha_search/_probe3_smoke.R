PROJ <- "G:/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure/config.R"))
source(file.path(PROJ, "02_Infrastructure/backtest_harness.R"))
suppressMessages(library(data.table))
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; rm(res); gc(F)
if (!inherits(RAWDATA$Date,"Date")) RAWDATA[, Date := as.Date(Date)]
RAWDATA[, TradingValue := Close*Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align="right"), by=Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]
source(file.path(PROJ,"02_Infrastructure/alpha_search/fe_sector_spillover.R"), local=FALSE)
cat("FACTORS rows=", nrow(FACTORS), "dates=", uniqueN(FACTORS$Date), "tickers=", uniqueN(FACTORS$Ticker), "\n")
# restrict to 2005+ and K200|KQ150 to see effective breadth
F2 <- FACTORS[Date >= as.Date("2005-01-01")]
mem <- unique(RAWDATA[(K200==1|KQ150==1), .(Date, Ticker)])
F3 <- merge(F2, mem, by=c("Date","Ticker"))
cat("after 2005+ K200|KQ150 merge: rows=", nrow(F3), "dates=", uniqueN(F3$Date),
    "avg cand/month=", round(nrow(F3)/uniqueN(F3$Date)), "\n")
cat("Score distribution:\n"); print(summary(F3$Score))
# breadth per month: how many have non-degenerate score for top25?
bm <- F3[, .(n=.N, n_uniq_score=uniqueN(round(Score,6))), by=Date]
cat("median candidates/month=", median(bm$n), " min=", min(bm$n), "\n")
cat("median distinct scores/month=", median(bm$n_uniq_score), "(=n sectors active)\n")
