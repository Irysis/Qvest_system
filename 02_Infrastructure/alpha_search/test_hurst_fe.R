suppressWarnings(suppressMessages(library(data.table)))
Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
cat("[test] load_rawdata...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)
cat("[test] rows:", nrow(RAWDATA), "\n")
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]
# 서브셋: 2023년 이후
RAWDATA <- RAWDATA[Date >= as.Date("2023-01-01")]
cat("[test] subset rows:", nrow(RAWDATA), "\n")
source("02_Infrastructure/alpha_search/fe_spectral_persistence_hurst.R")
cat("[test] FACTORS rows:", nrow(FACTORS), "\n")
print(head(FACTORS))
