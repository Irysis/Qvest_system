#==============================================================================
# Naver Finance — Investor Type (거래주체) Data Collector
# 투자자별 매매동향 (시장/종목), 프로그램매매 수집
#
# 사용법:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/naver_investor_collector.R")
#   naver_investor_market("20260312")                  # 시장별 투자자 매매동향
#   naver_investor_stock("005930", pages = 5)          # 종목별 투자자 매매동향
#   naver_program_trading("20260312")                  # 프로그램매매
#   naver_collect_investor_daily("20260312")            # 일별 수집 + 캐시
#   naver_collect_investor_range("20260301","20260312") # 기간 수집
#   naver_load_investor()                              # 캐시 로드 (parquet)
#==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(rvest)
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))

INVESTOR_CACHE_DIR <- file.path(PROJECT_ROOT, ".cache", "investor")
if (!dir.exists(INVESTOR_CACHE_DIR)) dir.create(INVESTOR_CACHE_DIR, recursive = TRUE)

INVESTOR_PARQUET <- file.path(INVESTOR_CACHE_DIR, "investor_market.parquet")

# ─── Rate Limiter ────────────────────────────────────────────────────────────
.naver_last_req <- new.env(parent = emptyenv())
.naver_last_req$ts <- 0

.naver_rate_limit <- function(min_interval = 1.0) {
  elapsed <- as.numeric(Sys.time()) - .naver_last_req$ts
  if (elapsed < min_interval) Sys.sleep(min_interval - elapsed)
  .naver_last_req$ts <- as.numeric(Sys.time())
}

# ─── Helper: fetch Naver page ───────────────────────────────────────────────
.naver_fetch <- function(url, encoding = "EUC-KR") {
  .naver_rate_limit()
  resp <- tryCatch(
    GET(url, user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)")),
    error = function(e) { message("[NAVER] HTTP error: ", e$message); NULL }
  )
  if (is.null(resp) || status_code(resp) != 200) {
    message("[NAVER] Failed to fetch: ", url, " (status: ",
            if (!is.null(resp)) status_code(resp) else "NA", ")")
    return(NULL)
  }
  tryCatch(
    read_html(content(resp, "text", encoding = encoding)),
    error = function(e) { message("[NAVER] Parse error: ", e$message); NULL }
  )
}

# ─── Helper: parse comma-separated Korean number ────────────────────────────
.parse_krnum <- function(x) {
  x <- trimws(x)
  x <- gsub(",", "", x)
  x <- gsub("\\+", "", x)
  suppressWarnings(as.numeric(x))
}

# ─── Holiday cache (shared with krx) ────────────────────────────────────────
.naver_holidays_file <- file.path(INVESTOR_CACHE_DIR, "known_holidays.rds")

.naver_is_holiday <- function(date_str) {
  if (!file.exists(.naver_holidays_file)) return(FALSE)
  date_str %in% readRDS(.naver_holidays_file)
}

.naver_mark_holiday <- function(date_str) {
  holidays <- if (file.exists(.naver_holidays_file)) readRDS(.naver_holidays_file) else character(0)
  holidays <- unique(c(holidays, date_str))
  saveRDS(holidays, .naver_holidays_file)
}

#==============================================================================
# 1. Market-level investor trading (코스피/코스닥 전체 투자자별 매매동향)
#==============================================================================
#' @param date_str Character "YYYYMMDD" — 기준일 (이 날짜 포함 과거 데이터 반환)
#' @param market "kospi" or "kosdaq"
#' @param pages Number of pages to scrape (each page ~ 10 trading days)
#' @return data.table with columns:
#'   Date, 개인, 외국인, 기관계, 기타법인, 금융투자, 보험, 투신, 은행, 기타금융, 연기금
#'   (순매수금액, 단위: 억원)
naver_investor_market <- function(date_str, market = "kospi", pages = 1) {
  sosession <- switch(tolower(market), kospi = "02", kosdaq = "03", "02")

  col_names <- c("Date", "개인", "외국인", "기관계", "기타법인",
                  "금융투자", "보험", "투신", "은행", "기타금융", "연기금")

  all_rows <- list()

  for (pg in seq_len(pages)) {
    url <- sprintf(
      "https://finance.naver.com/sise/investorDealTrendDay.naver?bizdate=%s&sosession=%s&page=%d",
      date_str, sosession, pg
    )
    page <- .naver_fetch(url)
    if (is.null(page)) next

    tbl <- tryCatch(html_nodes(page, "table.type_1"), error = function(e) NULL)
    if (is.null(tbl) || length(tbl) == 0) next

    trs <- html_nodes(tbl[[1]], "tr")

    for (tr in trs) {
      tds <- html_nodes(tr, "td")
      if (length(tds) != 11) next  # skip header/separator rows

      vals <- html_text(tds, trim = TRUE)
      date_val <- trimws(vals[1])
      if (nchar(date_val) == 0 || !grepl("^\\d{2}\\.\\d{2}\\.\\d{2}$", date_val)) next

      # Parse date: "26.03.12" → "2026-03-12"
      parts <- strsplit(date_val, "\\.")[[1]]
      date_parsed <- sprintf("20%s-%s-%s", parts[1], parts[2], parts[3])

      nums <- sapply(vals[2:11], .parse_krnum, USE.NAMES = FALSE)

      row_dt <- data.table(
        Date = as.Date(date_parsed),
        t(nums)
      )
      setnames(row_dt, col_names)
      all_rows[[length(all_rows) + 1]] <- row_dt
    }
  }

  if (length(all_rows) == 0) {
    message("[NAVER] No investor data found for ", date_str, " (", market, ")")
    return(data.table(
      Date = as.Date(character(0)),
      `개인` = numeric(0), `외국인` = numeric(0), `기관계` = numeric(0),
      `기타법인` = numeric(0), `금융투자` = numeric(0), `보험` = numeric(0),
      `투신` = numeric(0), `은행` = numeric(0), `기타금융` = numeric(0),
      `연기금` = numeric(0)
    ))
  }

  dt <- rbindlist(all_rows)
  setorder(dt, -Date)
  unique(dt, by = "Date")
}

#==============================================================================
# 2. Stock-level investor trading (종목별 투자자 매매동향)
#==============================================================================
#' @param stock_code 6-digit stock code (e.g., "005930")
#' @param pages Number of pages to scrape
#' @return data.table with: Date, 종가, 전일비, 등락률, 거래량, 기관, 외국인, 외국인보유주수, 외국인보유율
naver_investor_stock <- function(stock_code, pages = 5) {
  col_names <- c("Date", "종가", "전일비", "등락률", "거래량",
                 "기관", "외국인", "외국인보유주수", "외국인보유율")

  all_rows <- list()

  for (pg in seq_len(pages)) {
    url <- sprintf(
      "https://finance.naver.com/item/frgn.naver?code=%s&page=%d",
      stock_code, pg
    )
    page <- .naver_fetch(url)
    if (is.null(page)) next

    # The investor table has summary containing "외국인 기관 순매매"
    tbls <- html_nodes(page, "table.type2")
    if (length(tbls) < 2) next

    # The second type2 table contains investor data
    tbl <- tbls[[2]]
    trs <- html_nodes(tbl, "tr")

    for (tr in trs) {
      tds <- html_nodes(tr, "td")
      if (length(tds) < 8) next

      vals <- html_text(tds, trim = TRUE)
      date_val <- trimws(vals[1])

      # Date format: "2026.03.13"
      if (!grepl("^\\d{4}\\.\\d{2}\\.\\d{2}$", date_val)) next

      date_parsed <- as.Date(gsub("\\.", "-", date_val))
      close_price <- .parse_krnum(vals[2])
      change <- .parse_krnum(vals[3])
      pct_change <- .parse_krnum(gsub("%", "", vals[4]))
      volume <- .parse_krnum(vals[5])
      inst_net <- .parse_krnum(vals[6])
      frgn_net <- .parse_krnum(vals[7])
      frgn_hold <- .parse_krnum(vals[8])
      frgn_pct <- .parse_krnum(gsub("%", "", vals[9]))

      row_dt <- data.table(
        Date = date_parsed,
        종가 = close_price,
        전일비 = change,
        등락률 = pct_change,
        거래량 = volume,
        기관 = inst_net,
        외국인 = frgn_net,
        외국인보유주수 = frgn_hold,
        외국인보유율 = frgn_pct
      )
      all_rows[[length(all_rows) + 1]] <- row_dt
    }
  }

  if (length(all_rows) == 0) {
    message("[NAVER] No stock investor data for ", stock_code)
    return(data.table(
      Date = as.Date(character(0)), 종가 = numeric(0), 전일비 = numeric(0),
      등락률 = numeric(0), 거래량 = numeric(0), 기관 = numeric(0),
      외국인 = numeric(0), 외국인보유주수 = numeric(0), 외국인보유율 = numeric(0)
    ))
  }

  dt <- rbindlist(all_rows)
  # Derive 개인 = -(기관 + 외국인) as approximation
  dt[, 개인 := -(기관 + 외국인)]
  setorder(dt, -Date)
  unique(dt, by = "Date")
}

#==============================================================================
# 3. Program trading (프로그램매매 — intraday summary for latest day)
#==============================================================================
#' @param date_str Character "YYYYMMDD" (not directly used as URL param;
#'   Naver shows latest trading day data)
#' @return data.table with: 시간, 차익_매수, 차익_매도, 차익_순매수,
#'   비차익_매수, 비차익_매도, 비차익_순매수, 전체_매수, 전체_매도, 전체_순매수
naver_program_trading <- function(date_str = NULL) {
  url <- "https://finance.naver.com/sise/programDealTrendDay.naver"
  page <- .naver_fetch(url)
  if (is.null(page)) {
    message("[NAVER] Failed to fetch program trading page")
    return(data.table())
  }

  tbls <- html_nodes(page, "table")
  if (length(tbls) == 0) {
    message("[NAVER] No program trading tables found")
    return(data.table())
  }

  tbl <- tbls[[1]]
  trs <- html_nodes(tbl, "tr")

  col_names <- c("시간", "차익_매수", "차익_매도", "차익_순매수",
                 "비차익_매수", "비차익_매도", "비차익_순매수",
                 "전체_매수", "전체_매도", "전체_순매수")

  all_rows <- list()
  for (tr in trs) {
    tds <- html_nodes(tr, "td")
    if (length(tds) < 9) next

    vals <- html_text(tds, trim = TRUE)
    time_val <- trimws(vals[1])
    if (nchar(time_val) == 0) next

    nums <- sapply(vals[2:10], .parse_krnum, USE.NAMES = FALSE)

    row_dt <- data.table(
      시간 = time_val,
      차익_매수 = nums[1], 차익_매도 = nums[2], 차익_순매수 = nums[3],
      비차익_매수 = nums[4], 비차익_매도 = nums[5], 비차익_순매수 = nums[6],
      전체_매수 = nums[7], 전체_매도 = nums[8], 전체_순매수 = nums[9]
    )
    all_rows[[length(all_rows) + 1]] <- row_dt
  }

  if (length(all_rows) == 0) {
    message("[NAVER] No program trading data (market may be closed)")
    return(data.table())
  }

  # Add date column
  dt <- rbindlist(all_rows)
  if (!is.null(date_str)) {
    dt[, Date := as.Date(date_str, format = "%Y%m%d")]
  }
  dt
}

#==============================================================================
# 4. Daily collection (market-level + cache)
#==============================================================================
#' @param date_str "YYYYMMDD"
#' @param market "kospi" or "kosdaq" or "both"
naver_collect_investor_daily <- function(date_str, market = "both") {
  d <- as.Date(date_str, format = "%Y%m%d")

  # Skip weekends
  if (weekdays(d) %in% c("Saturday", "Sunday", "토요일", "일요일")) {
    message("[NAVER] Skipping weekend: ", date_str)
    return(invisible(NULL))
  }

  # Skip known holidays
  if (.naver_is_holiday(date_str)) {
    message("[NAVER] Skipping known holiday: ", date_str)
    return(invisible(NULL))
  }

  markets <- if (market == "both") c("kospi", "kosdaq") else market

  for (mkt in markets) {
    cache_file <- file.path(INVESTOR_CACHE_DIR, sprintf("investor_%s_%s.csv", mkt, date_str))
    if (file.exists(cache_file)) {
      message("[NAVER] Already cached: ", basename(cache_file))
      next
    }

    dt <- naver_investor_market(date_str, market = mkt, pages = 1)

    if (nrow(dt) == 0) {
      message("[NAVER] No data for ", date_str, " (", mkt, ") — may be holiday")
      .naver_mark_holiday(date_str)
      next
    }

    # Filter to only the target date
    target_date <- as.Date(date_str, format = "%Y%m%d")
    dt_target <- dt[Date == target_date]

    if (nrow(dt_target) == 0) {
      # The target date isn't in the results — likely a holiday
      message("[NAVER] Date ", date_str, " not found in results (holiday?) — caching available dates")
      .naver_mark_holiday(date_str)
      # Still save whatever dates we got
      for (i in seq_len(nrow(dt))) {
        row_date <- format(dt$Date[i], "%Y%m%d")
        row_file <- file.path(INVESTOR_CACHE_DIR, sprintf("investor_%s_%s.csv", mkt, row_date))
        if (!file.exists(row_file)) {
          fwrite(dt[i], row_file)
        }
      }
      next
    }

    dt_target[, market := mkt]
    fwrite(dt_target, cache_file)
    message("[NAVER] Saved: ", basename(cache_file))
  }

  invisible(NULL)
}

#==============================================================================
# 5. Range collection with rate limiting
#==============================================================================
naver_collect_investor_range <- function(start_str, end_str, market = "both") {
  start_d <- as.Date(start_str, format = "%Y%m%d")
  end_d   <- as.Date(end_str, format = "%Y%m%d")
  dates   <- seq(start_d, end_d, by = "day")

  cat(sprintf("[NAVER] Collecting investor data: %s ~ %s (%d days)\n",
              start_str, end_str, length(dates)))

  # More efficient: use multi-page fetch from end_date,

  # which returns ~10 dates per page
  markets <- if (market == "both") c("kospi", "kosdaq") else market

  for (mkt in markets) {
    cat(sprintf("[NAVER] Market: %s\n", mkt))

    # Check which dates are already cached
    cached <- list.files(INVESTOR_CACHE_DIR,
                         pattern = sprintf("investor_%s_\\d{8}\\.csv", mkt))
    cached_dates <- gsub(sprintf("investor_%s_(\\d{8})\\.csv", mkt), "\\1", cached)

    needed_dates <- format(dates, "%Y%m%d")
    # Remove weekends
    needed_dates <- needed_dates[!weekdays(as.Date(needed_dates, "%Y%m%d")) %in%
                                   c("Saturday", "Sunday", "토요일", "일요일")]
    # Remove already cached
    needed_dates <- setdiff(needed_dates, cached_dates)
    # Remove known holidays
    if (file.exists(.naver_holidays_file)) {
      holidays <- readRDS(.naver_holidays_file)
      needed_dates <- setdiff(needed_dates, holidays)
    }

    if (length(needed_dates) == 0) {
      cat(sprintf("[NAVER] All dates already cached for %s\n", mkt))
      next
    }

    # Fetch pages starting from end_date, going backwards
    # Each page has ~10 trading days, so estimate pages needed
    pages_needed <- ceiling(length(needed_dates) / 10) + 1

    dt_all <- naver_investor_market(end_str, market = mkt, pages = pages_needed)

    if (nrow(dt_all) == 0) {
      cat("[NAVER] No data returned\n")
      next
    }

    # Filter to date range
    dt_all <- dt_all[Date >= start_d & Date <= end_d]

    # Save individual daily CSV files
    saved <- 0
    for (i in seq_len(nrow(dt_all))) {
      row_date <- format(dt_all$Date[i], "%Y%m%d")
      cache_file <- file.path(INVESTOR_CACHE_DIR,
                              sprintf("investor_%s_%s.csv", mkt, row_date))
      if (!file.exists(cache_file)) {
        row_dt <- dt_all[i]
        row_dt[, market := mkt]
        fwrite(row_dt, cache_file)
        saved <- saved + 1
      }
    }
    cat(sprintf("[NAVER] Saved %d new records for %s\n", saved, mkt))
  }

  invisible(NULL)
}

#==============================================================================
# 6. Load all cached data as consolidated data.table (+ parquet)
#==============================================================================
naver_load_investor <- function(market = "both", rebuild_parquet = FALSE) {
  markets <- if (market == "both") c("kospi", "kosdaq") else market

  all_dt <- list()
  for (mkt in markets) {
    pattern <- sprintf("investor_%s_\\d{8}\\.csv", mkt)
    files <- list.files(INVESTOR_CACHE_DIR, pattern = pattern, full.names = TRUE)

    if (length(files) == 0) next

    dt <- rbindlist(lapply(files, fread), fill = TRUE)
    if (!"market" %in% names(dt)) dt[, market := mkt]
    all_dt[[mkt]] <- dt
  }

  if (length(all_dt) == 0) {
    message("[NAVER] No cached investor data found")
    return(data.table())
  }

  result <- rbindlist(all_dt, fill = TRUE)
  result[, Date := as.Date(Date)]
  setorder(result, market, Date)
  result <- unique(result, by = c("market", "Date"))

  # Save consolidated parquet
  if (rebuild_parquet || !file.exists(INVESTOR_PARQUET) || nrow(result) > 0) {
    write_parquet(result, INVESTOR_PARQUET)
    message("[NAVER] Saved parquet: ", INVESTOR_PARQUET, " (", nrow(result), " rows)")
  }

  result
}

cat("[NAVER Investor Collector] Loaded. Functions: naver_investor_market(), ",
    "naver_investor_stock(), naver_program_trading(), ",
    "naver_collect_investor_daily(), naver_collect_investor_range(), ",
    "naver_load_investor()\n")
