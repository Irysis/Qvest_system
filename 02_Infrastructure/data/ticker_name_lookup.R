#==============================================================================
# Ticker Name Lookup — RAWDATA 캐시에서 종목명 조회
# daily_refresh로 관리되는 DB 사용. 절대 수동 매핑 금지.
#==============================================================================

suppressPackageStartupMessages({library(data.table); library(arrow)})

.TICKER_NAME_CACHE <- NULL

#' Load ticker-name mapping from RAWDATA cache
ticker_name_load <- function() {
  if (!is.null(.TICKER_NAME_CACHE)) return(.TICKER_NAME_CACHE)
  
  rawdata_path <- file.path(PROJECT_ROOT, ".cache", "RAWDATA.parquet")
  if (!file.exists(rawdata_path)) {
    cat("[ticker_name] RAWDATA.parquet not found\n")
    return(data.table(Ticker=character(), Name=character()))
  }
  
  dt <- as.data.table(read_parquet(rawdata_path, col_select=c("Ticker","Name","Date")))
  # Latest date per ticker
  dt <- dt[Date == max(Date), .(Ticker, Name)]
  dt <- unique(dt[!is.na(Name) & Name != ""])
  
  .TICKER_NAME_CACHE <<- dt
  cat(sprintf("[ticker_name] Loaded %d tickers from RAWDATA cache\n", nrow(dt)))
  dt
}

#' Get name for a single ticker
ticker_name <- function(ticker) {
  dt <- ticker_name_load()
  nm <- dt[Ticker == ticker]$Name
  if (length(nm) == 0) return(ticker)
  nm[1]
}

#' Get names for multiple tickers
ticker_names <- function(tickers) {
  sapply(tickers, ticker_name, USE.NAMES = FALSE)
}

cat("[ticker_name_lookup] Loaded. Source: RAWDATA cache (daily_refresh 관리)\n")
cat("  ticker_name('A005930'), ticker_names(c('A005930','A000660'))\n")
