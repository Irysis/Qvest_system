#==============================================================================
# DART Insider Trading Data Collector
#
# DART OpenAPI 지분공시(임원/대주주 특정증권 소유상황)를 수집하여
# insider_trades.parquet 캐시로 저장.
#
# Usage:
#   source("02_Infrastructure/data_collector_dart_insider.R")
#   dart_fetch_insider(years = 2015:2025)
#   insider_dt <- dart_load_insider()
#
# API: opendart.fss.or.kr/api/elestock.json
# Rate: 일 10,000건, 0.7초 간격
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(httr)
  library(jsonlite)
})

cat("[dart_insider] Loaded.\n")

DART_CACHE_DIR     <- file.path(CACHE_DIR, "dart")
INSIDER_CACHE_PATH <- file.path(DART_CACHE_DIR, "insider_trades.parquet")
CORPCODE_PATH      <- file.path(DART_CACHE_DIR, "corpcode_map.parquet")

if (!dir.exists(DART_CACHE_DIR)) dir.create(DART_CACHE_DIR, recursive = TRUE)

.load_dart_key <- function() {
  env_path <- file.path(PROJECT_ROOT, ".env")
  lines <- readLines(env_path, warn = FALSE)
  for (line in lines) {
    if (grepl("^DART_API_KEY=", line)) return(sub("^DART_API_KEY=", "", line))
  }
  stop("[dart_insider] DART_API_KEY not found in .env")
}

# Load corpcode → ticker mapping
.load_corpcode_map <- function() {
  if (!file.exists(CORPCODE_PATH)) stop("[dart_insider] corpcode_map.parquet not found. Run dart_update_corpcode() first.")
  dt <- as.data.table(read_parquet(CORPCODE_PATH))
  dt[, .(corp_code, stock_code, corp_name)]
}

#' Fetch insider disclosure list for a given date range
#' Uses list.json with pblntf_ty=E (지분공시)
.fetch_insider_list <- function(api_key, bgn_de, end_de, page_no = 1, page_count = 100) {
  url <- "https://opendart.fss.or.kr/api/list.json"
  resp <- GET(url, query = list(
    crtfc_key = api_key,
    bgn_de    = bgn_de,
    end_de    = end_de,
    pblntf_ty = "E",
    page_no   = page_no,
    page_count = page_count
  ))
  if (status_code(resp) != 200) return(NULL)
  parsed <- fromJSON(content(resp, "text", encoding = "UTF-8"), flatten = TRUE)
  if (parsed$status != "000") return(NULL)
  as.data.table(parsed$list)
}

#' Fetch elestock (임원 주요주주 특정증권 소유상황) for a single report
.fetch_elestock <- function(api_key, rcept_no) {
  url <- "https://opendart.fss.or.kr/api/elestock.json"
  resp <- GET(url, query = list(
    crtfc_key = api_key,
    rcept_no  = rcept_no
  ))
  if (status_code(resp) != 200) return(NULL)
  parsed <- fromJSON(content(resp, "text", encoding = "UTF-8"), flatten = TRUE)
  if (parsed$status != "000") return(NULL)
  as.data.table(parsed$list)
}

#' Main: Fetch insider trades for given years
#'
#' @param years integer vector e.g. 2015:2025
#' @param delay numeric seconds between API calls
#' @return data.table of insider trades, also saved to parquet
dart_fetch_insider <- function(years = 2015:2025, delay = 0.7) {
  api_key <- .load_dart_key()
  corpmap <- .load_corpcode_map()

  all_results <- list()
  total_fetched <- 0L

  for (yr in years) {
    for (mo in 1:12) {
      bgn <- sprintf("%04d%02d01", yr, mo)
      last_day <- as.integer(format(
        seq.Date(as.Date(sprintf("%04d-%02d-01", yr, mo)), by = "month", length.out = 2)[2] - 1, "%d"))
      end <- sprintf("%04d%02d%02d", yr, mo, last_day)

      # Skip future months
      if (as.Date(sprintf("%04d-%02d-01", yr, mo)) > Sys.Date()) next

      cat(sprintf("[dart_insider] Fetching %04d-%02d (%s ~ %s)...\n", yr, mo, bgn, end))

      # Get disclosure list
      page <- 1L; month_disclosures <- list()
      repeat {
        dl <- .fetch_insider_list(api_key, bgn, end, page_no = page, page_count = 100)
        Sys.sleep(delay)
        if (is.null(dl) || nrow(dl) == 0) break
        month_disclosures[[length(month_disclosures) + 1L]] <- dl
        if (nrow(dl) < 100) break
        page <- page + 1L
      }

      if (length(month_disclosures) == 0) {
        cat(sprintf("  No disclosures for %04d-%02d\n", yr, mo))
        next
      }

      disc_dt <- rbindlist(month_disclosures, fill = TRUE)

      # Filter for stock ownership reports (report_nm containing 임원 or 주요주주)
      disc_dt <- disc_dt[grepl("임원|주요주주|특정증권", report_nm, ignore.case = TRUE)]

      if (nrow(disc_dt) == 0) {
        cat(sprintf("  No insider disclosures for %04d-%02d\n", yr, mo))
        next
      }

      cat(sprintf("  Found %d insider disclosures. Fetching details...\n", nrow(disc_dt)))

      # Fetch elestock details for each report (sample max 50 per month to respect rate limit)
      n_fetch <- min(nrow(disc_dt), 50L)
      for (j in seq_len(n_fetch)) {
        rcept_no <- disc_dt$rcept_no[j]
        corp_code <- disc_dt$corp_code[j]
        rcept_dt_str <- disc_dt$rcept_dt[j]

        detail <- tryCatch(.fetch_elestock(api_key, rcept_no), error = function(e) NULL)
        Sys.sleep(delay)

        if (!is.null(detail) && nrow(detail) > 0) {
          detail[, rcept_dt := rcept_dt_str]
          detail[, corp_code := corp_code]
          all_results[[length(all_results) + 1L]] <- detail
          total_fetched <- total_fetched + nrow(detail)
        }
      }

      cat(sprintf("  Total records so far: %d\n", total_fetched))
    }
  }

  if (length(all_results) == 0) {
    cat("[dart_insider] No data collected.\n")
    return(NULL)
  }

  result <- rbindlist(all_results, fill = TRUE)

  # Map corp_code to Ticker
  result <- merge(result, corpmap[, .(corp_code, Ticker = stock_code)],
                  by = "corp_code", all.x = TRUE)
  result <- result[!is.na(Ticker) & Ticker != ""]

  # Parse trade type
  if ("change_on" %in% names(result)) {
    result[, trade_type := fcase(
      grepl("매수|취득", change_on), "buy",
      grepl("매도|처분", change_on), "sell",
      default = "other"
    )]
  } else {
    result[, trade_type := "unknown"]
  }

  # Parse date
  result[, Date := as.Date(rcept_dt, format = "%Y%m%d")]

  # Parse quantity
  for (col in c("bftr_cg_qty", "bftr_cg_ratio")) {
    if (col %in% names(result)) {
      result[, (col) := as.numeric(gsub("[^0-9.-]", "", get(col)))]
    }
  }

  # Save
  write_parquet(result, INSIDER_CACHE_PATH)
  cat(sprintf("[dart_insider] Saved %d records to %s\n", nrow(result), INSIDER_CACHE_PATH))

  result
}

#' Load cached insider trades
dart_load_insider <- function() {
  if (!file.exists(INSIDER_CACHE_PATH)) {
    cat("[dart_insider] No cache. Run dart_fetch_insider() first.\n")
    return(NULL)
  }
  dt <- as.data.table(read_parquet(INSIDER_CACHE_PATH))
  dt[, Date := as.Date(Date)]
  cat(sprintf("[dart_insider] Loaded %d records (%s ~ %s)\n",
              nrow(dt), min(dt$Date, na.rm = TRUE), max(dt$Date, na.rm = TRUE)))
  dt
}

#' Compute monthly insider signal
#' @param insider_dt data.table from dart_load_insider()
#' @param trailing_months integer rolling window (default 3)
#' @return data.table with Date, Ticker, net_buy_count, net_buy_ratio, buyer_count
dart_insider_signal <- function(insider_dt, trailing_months = 3L) {
  # Filter: only buy/sell (exclude gift, inheritance)
  trades <- insider_dt[trade_type %in% c("buy", "sell")]
  trades[, YM := format(Date, "%Y-%m")]

  # Monthly aggregation per Ticker
  monthly <- trades[, .(
    buy_count  = sum(trade_type == "buy"),
    sell_count = sum(trade_type == "sell"),
    buy_ratio  = sum(fifelse(trade_type == "buy" & !is.na(bftr_cg_ratio), bftr_cg_ratio, 0)),
    sell_ratio = sum(fifelse(trade_type == "sell" & !is.na(bftr_cg_ratio), bftr_cg_ratio, 0))
  ), by = .(Ticker, YM)]

  setorder(monthly, Ticker, YM)

  # Rolling 3-month aggregation
  monthly[, net_buy_count := frollsum(buy_count - sell_count, n = trailing_months, align = "right"), by = Ticker]
  monthly[, net_buy_ratio := frollsum(buy_ratio - sell_ratio, n = trailing_months, align = "right"), by = Ticker]
  monthly[, buyer_count := frollsum(buy_count, n = trailing_months, align = "right"), by = Ticker]

  # Convert YM to Date (last day of month)
  monthly[, Date := as.Date(paste0(YM, "-01"))]
  monthly[, Date := seq.Date(Date, by = "month", length.out = 2)[2] - 1, by = seq_len(nrow(monthly))]

  monthly[!is.na(net_buy_count), .(Date, Ticker, net_buy_count, net_buy_ratio, buyer_count)]
}

cat("[dart_insider] Functions: dart_fetch_insider(), dart_load_insider(), dart_insider_signal()\n")
