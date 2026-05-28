#==============================================================================
# Naver Finance Data Collector — T+0 한국주식 종가 수집
#
# KRX Open API(T+1 지연)의 보완 수집기.
# 장 마감(15:30) 후 당일 종가 즉시 수집 가능.
#
# 수집 루트:
#   1) Naver Finance 시세 페이지 (전종목 Close+Vol+Size, ~30초)
#   2) Naver Finance 개별종목 (OHLCV, 소수 종목용)
#
# 사용법:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/naver_data_collector.R")
#   naver_collect_all()                    # 전종목 최신 종가 수집
#   naver_quick_price("005930")            # 삼성전자 최근 5일 OHLCV
#   naver_run_pipeline()                   # 수집→RAWDATA 병합→검증
#   naver_run_pipeline("20260312")         # 특정일 기준 파이프라인
#==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(data.table)
  library(arrow)
  library(rvest)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))

NAVER_CACHE_DIR <- file.path(PROJECT_ROOT, ".cache", "naver")
if (!dir.exists(NAVER_CACHE_DIR)) dir.create(NAVER_CACHE_DIR, recursive = TRUE)

#──────────────────────────────────────────────────────────────────────────────
# Internal: Naver 시세 페이지 1페이지 파싱
#──────────────────────────────────────────────────────────────────────────────
.naver_sise_page <- function(sosok, page) {
  url <- sprintf(
    "https://finance.naver.com/sise/sise_market_sum.naver?sosok=%d&page=%d",
    sosok, page
  )
  resp <- tryCatch(
    GET(url, add_headers(`User-Agent` = "Mozilla/5.0")),
    error = function(e) NULL
  )
  if (is.null(resp) || status_code(resp) != 200) return(NULL)

  txt <- iconv(rawToChar(content(resp, "raw")), from = "EUC-KR", to = "UTF-8")
  html <- read_html(txt)

  # Parse table
  tbl <- tryCatch(
    html %>% html_node("table.type_2") %>% html_table(fill = TRUE),
    error = function(e) NULL
  )
  if (is.null(tbl)) return(NULL)

  # Extract ticker codes from links
  codes <- tryCatch({
    links <- html %>% html_nodes("a.tltle") %>% html_attr("href")
    gsub(".*code=([0-9]+).*", "\\1", links)
  }, error = function(e) character(0))

  # Clean table: remove spacer rows
  tbl <- as.data.table(tbl)
  tbl <- tbl[!is.na(tbl[[2]]) & tbl[[2]] != ""]
  if (nrow(tbl) == 0 || length(codes) == 0) return(NULL)

  # Match codes to rows (should be same length)
  n <- min(nrow(tbl), length(codes))
  tbl <- tbl[1:n]

  .num <- function(x) as.numeric(gsub("[^0-9.-]", "", x))

  data.table(
    Ticker = paste0("A", codes[1:n]),
    Name   = as.character(tbl[[2]]),
    Close  = .num(tbl[[3]]),
    Vol    = .num(tbl[[10]]),
    Size   = .num(tbl[[7]]) * 1e6,  # 시가총액: 억원 → 원 (Naver는 백만원 단위)
    Market = fifelse(sosok == 0, "KOSPI", "KOSDAQ")
  )
}

#──────────────────────────────────────────────────────────────────────────────
# Internal: 마지막 페이지 번호 확인
#──────────────────────────────────────────────────────────────────────────────
.naver_last_page <- function(sosok) {
  url <- sprintf("https://finance.naver.com/sise/sise_market_sum.naver?sosok=%d&page=1", sosok)
  resp <- tryCatch(
    GET(url, add_headers(`User-Agent` = "Mozilla/5.0")),
    error = function(e) NULL
  )
  if (is.null(resp)) return(1L)
  txt <- iconv(rawToChar(content(resp, "raw")), from = "EUC-KR", to = "UTF-8")
  html <- read_html(txt)
  paging <- html %>% html_nodes("td.pgRR a") %>% html_attr("href")
  if (length(paging) > 0) {
    as.integer(gsub(".*page=([0-9]+).*", "\\1", paging[1]))
  } else 1L
}

#──────────────────────────────────────────────────────────────────────────────
# 전종목 최신 종가 수집 (T+0)
# Close + Vol + Size (Open/High/Low 미포함 — 시세 페이지 한계)
#──────────────────────────────────────────────────────────────────────────────
naver_collect_all <- function() {
  cat("[Naver] 전종목 최신 종가 수집 시작...\n")
  t0 <- Sys.time()

  results <- list()
  for (sosok in c(0, 1)) {
    mkt <- if (sosok == 0) "KOSPI" else "KOSDAQ"
    last_page <- .naver_last_page(sosok)
    cat(sprintf("[Naver] %s: %d페이지\n", mkt, last_page))

    for (pg in 1:last_page) {
      dt <- tryCatch(.naver_sise_page(sosok, pg), error = function(e) NULL)
      if (!is.null(dt) && nrow(dt) > 0) {
        results[[length(results) + 1]] <- dt
      }
      Sys.sleep(0.3)
    }
  }

  if (length(results) == 0) {
    cat("[Naver] 데이터 수집 실패\n")
    return(NULL)
  }

  all_dt <- rbindlist(results, fill = TRUE)
  all_dt <- all_dt[!is.na(Close) & Close > 0]
  # 장마감 후(16:00+)면 당일, 아니면 전 거래일
  # (00:03 cron에서 실행 시 Sys.Date()는 오늘이지만 종가는 전일 것)
  now_hour <- as.integer(format(Sys.time(), "%H"))
  if (now_hour >= 16) {
    all_dt[, Date := Sys.Date()]
  } else {
    # trading_calendar 있으면 사용, 없으면 단순 -1일
    if (exists("get_prev_trading_day")) {
      all_dt[, Date := get_prev_trading_day(Sys.Date())]
    } else {
      all_dt[, Date := Sys.Date() - 1L]
    }
  }

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("[Naver] 수집 완료: %d종목 (KOSPI %d + KOSDAQ %d) | %.1f초\n",
              nrow(all_dt),
              sum(all_dt$Market == "KOSPI"),
              sum(all_dt$Market == "KOSDAQ"),
              elapsed))

  # Save to cache
  out_dir <- file.path(NAVER_CACHE_DIR, "snapshot")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  date_str <- format(Sys.Date(), "%Y%m%d")
  write_parquet(all_dt, file.path(out_dir, sprintf("snapshot_%s.parquet", date_str)))

  invisible(all_dt)
}

#──────────────────────────────────────────────────────────────────────────────
# 개별종목 최근 OHLCV (Naver 일별 시세)
# Open/High/Low 포함, 최대 10일
#──────────────────────────────────────────────────────────────────────────────
NAVER_SISE_DAY_URL <- "https://finance.naver.com/item/sise_day.naver"

naver_quick_price <- function(code, n = 5) {
  url <- sprintf("%s?code=%s&page=1", NAVER_SISE_DAY_URL, code)
  resp <- tryCatch(
    GET(url, add_headers(
      `User-Agent` = "Mozilla/5.0",
      `Referer` = sprintf("https://finance.naver.com/item/main.naver?code=%s", code)
    )),
    error = function(e) NULL
  )
  if (is.null(resp) || status_code(resp) != 200) {
    cat(sprintf("[Naver] %s: fetch failed\n", code))
    return(NULL)
  }

  txt <- iconv(rawToChar(content(resp, "raw")), from = "EUC-KR", to = "UTF-8")
  html <- read_html(txt)
  tbl <- tryCatch(html %>% html_table(fill = TRUE), error = function(e) list())
  if (length(tbl) < 1) return(NULL)

  raw_tbl <- as.data.frame(tbl[[1]])
  raw_tbl <- raw_tbl[complete.cases(raw_tbl), ]
  if (nrow(raw_tbl) == 0) return(NULL)

  .num <- function(x) as.numeric(gsub("[^0-9.-]", "", x))

  # Columns: 날짜, 종가, 전일비, 시가, 고가, 저가, 거래량
  result <- data.table(
    Date  = as.Date(raw_tbl[[1]], "%Y.%m.%d"),
    Close = .num(raw_tbl[[2]]),
    Open  = .num(raw_tbl[[4]]),
    High  = .num(raw_tbl[[5]]),
    Low   = .num(raw_tbl[[6]]),
    Vol   = .num(raw_tbl[[7]])
  )
  result <- result[!is.na(Date)]
  result <- head(result[order(-Date)], n)
  cat(sprintf("[Naver] %s: %d일 (최신 %s, %s원)\n",
              code, nrow(result), result$Date[1], format(result$Close[1], big.mark = ",")))
  result
}

#──────────────────────────────────────────────────────────────────────────────
# KOSPI 200 지수 종가 (Naver)
#──────────────────────────────────────────────────────────────────────────────
naver_kospi200_close <- function() {
  # BM = KOSPI(전체), NOT 코스피200. QuantiWise IKS200 = KOSPI 전체 지수.
  # code=KOSPI → 코스피 전체 (~5,500), code=KPI200 → 코스피200 (~821)
  url <- "https://finance.naver.com/sise/sise_index.naver?code=KOSPI"
  resp <- tryCatch(
    GET(url, add_headers(`User-Agent` = "Mozilla/5.0")),
    error = function(e) NULL
  )
  if (is.null(resp) || status_code(resp) != 200) return(NULL)

  txt <- iconv(rawToChar(content(resp, "raw")), from = "EUC-KR", to = "UTF-8")
  html <- read_html(txt)

  # 현재가 추출
  now_val <- tryCatch({
    html %>% html_node("#now_value") %>% html_text() %>%
      gsub("[^0-9.]", "", .) %>% as.numeric()
  }, error = function(e) NA_real_)

  if (is.na(now_val)) return(NULL)
  cat(sprintf("[Naver] KOSPI: %.2f\n", now_val))

  data.table(Date = Sys.Date(), BM_Close = now_val)
}

#──────────────────────────────────────────────────────────────────────────────
# RAWDATA 병합 파이프라인
# Naver snapshot → RAWDATA.parquet 업데이트
#──────────────────────────────────────────────────────────────────────────────
naver_merge_rawdata <- function(snapshot = NULL) {
  if (!file.exists(RAWDATA_CACHE)) {
    cat("[naver_merge] RAWDATA.parquet not found.\n")
    return(invisible(NULL))
  }

  old_raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  last_date <- max(old_raw$Date)
  known_tickers <- unique(old_raw$Ticker)

  # Load snapshot (from naver_collect_all)
  if (is.null(snapshot)) {
    snap_dir <- file.path(NAVER_CACHE_DIR, "snapshot")
    if (!dir.exists(snap_dir)) return(invisible(NULL))
    files <- list.files(snap_dir, pattern = "\\.parquet$", full.names = TRUE)
    if (length(files) == 0) return(invisible(NULL))

    # Get latest snapshot
    file_dates <- as.Date(gsub(".*snapshot_([0-9]{8})\\.parquet", "\\1", basename(files)), "%Y%m%d")
    new_files <- files[file_dates > last_date]
    if (length(new_files) == 0) {
      cat("[naver_merge] No new snapshot beyond RAWDATA.\n")
      return(invisible(NULL))
    }
    snapshot <- rbindlist(lapply(new_files, function(f) {
      tryCatch(as.data.table(read_parquet(f)), error = function(e) NULL)
    }), fill = TRUE)
  }

  if (is.null(snapshot) || nrow(snapshot) == 0) return(invisible(NULL))

  # Filter to known universe & dates after RAWDATA
  # Forward-skip 방지: 중간에 누락 거래일 있으면 삽입 차단
  if (exists("get_trading_days") && exists("last_confirmed_trading_day")) {
    confirmed <- last_confirmed_trading_day()
    snapshot <- snapshot[Date <= confirmed]  # 미래 날짜 차단

    expected <- get_trading_days(last_date + 1L, confirmed)
    if (length(expected) > 0) {
      snap_dates <- sort(unique(snapshot$Date))
      missing <- setdiff(as.character(expected), as.character(snap_dates))
      if (length(missing) > 0) {
        cat(sprintf("[naver_merge] BLOCKED: %d 누락 거래일 발견. KRX gap-fill 먼저 필요.\n", length(missing)))
        cat(sprintf("  누락: %s\n", paste(missing, collapse = ", ")))
        return(invisible(NULL))
      }
    }
  }
  new_rows <- snapshot[Ticker %in% known_tickers & Date > last_date]
  if (nrow(new_rows) == 0) {
    cat("[naver_merge] No new rows to merge.\n")
    return(invisible(NULL))
  }

  cat(sprintf("[naver_merge] %d rows for %d new date(s)\n",
              nrow(new_rows), uniqueN(new_rows$Date)))

  # Compute returns
  setorder(new_rows, Ticker, Date)
  last_closes <- old_raw[Date == max(Date), .(Ticker, Prev_Close = Close)]

  new_rows[, Ret := Close / shift(Close) - 1, by = Ticker]

  # Fix first day using previous RAWDATA close
  first_day <- min(new_rows$Date)
  first_match <- merge(
    new_rows[Date == first_day, .(Ticker, Close)],
    last_closes, by = "Ticker", all.x = TRUE
  )
  first_match[!is.na(Prev_Close) & Prev_Close > 0, Ret := Close / Prev_Close - 1]
  new_rows[Date == first_day,
           Ret := first_match[match(new_rows[Date == first_day, Ticker], Ticker), Ret]]

  # BM_Ret from KOSPI 200
  bm <- naver_kospi200_close()
  if (!is.null(bm) && nrow(bm) > 0) {
    old_bm <- as.data.table(read_parquet(BM_CACHE))
    last_bm_close <- old_bm[Date == max(Date)]$BM_Close[1]

    if (!is.na(last_bm_close) && last_bm_close > 0) {
      bm[, BM_Ret := BM_Close / last_bm_close - 1]
      new_rows <- merge(new_rows, bm[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

      # Update benchmark cache
      # parquet round-trip Date↔IDate class 불일치 방지 (data.table 1.15+ rbind class-attr check)
      old_bm[, Date := as.Date(Date)]; bm[, Date := as.Date(Date)]
      old_bm_ext <- rbind(old_bm, bm[!is.na(BM_Ret)], fill = TRUE, ignore.attr = TRUE)
      old_bm_ext <- unique(old_bm_ext, by = "Date")
      setorder(old_bm_ext, Date)
      write_parquet(old_bm_ext, BM_CACHE)
    }
  }
  if (!"BM_Ret" %in% names(new_rows)) new_rows[, BM_Ret := NA_real_]

  # Drop incomplete rows
  new_rows <- new_rows[!is.na(Ret)]

  # Naver snapshot doesn't have Open/High/Low — fill NA
  for (col in c("Open", "High", "Low", "Sector")) {
    if (!col %in% names(new_rows)) new_rows[, (col) := NA]
  }

  # Match RAWDATA column order
  rawdata_cols <- c("Date", "BM_Ret", "Ticker", "Name", "Market", "Sector",
                    "Open", "High", "Low", "Close", "Vol", "Size", "Ret")
  for (col in setdiff(rawdata_cols, names(new_rows))) new_rows[, (col) := NA]
  new_rows <- new_rows[, ..rawdata_cols]

  # Append
  # parquet round-trip Date↔IDate class 불일치 방지 (data.table 1.15+ rbind class-attr check)
  old_raw[, Date := as.Date(Date)]; new_rows[, Date := as.Date(Date)]
  combined <- rbind(old_raw, new_rows, fill = TRUE, ignore.attr = TRUE)
  combined <- unique(combined, by = c("Date", "Ticker"))
  setorder(combined, Date, Ticker)
  write_parquet(combined, RAWDATA_CACHE)

  cat(sprintf("[naver_merge] RAWDATA: +%d rows | %s ~ %s | total %d\n",
              nrow(new_rows), min(combined$Date), max(combined$Date), nrow(combined)))
  invisible(combined)
}

#──────────────────────────────────────────────────────────────────────────────
# Full Pipeline: 수집 → 병합 → 검증
#──────────────────────────────────────────────────────────────────────────────
naver_run_pipeline <- function(target_date = NULL) {
  cat("=== Naver Data Pipeline ===\n")

  old_raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  last_date <- max(old_raw$Date)

  if (is.null(target_date)) target_date <- format(Sys.Date(), "%Y%m%d")
  target <- as.Date(target_date, "%Y%m%d")

  if (target <= last_date) {
    cat(sprintf("[pipeline] RAWDATA (%s) already >= target (%s)\n", last_date, target))
    return(invisible(NULL))
  }

  cat(sprintf("Last RAWDATA: %s | Target: %s\n", last_date, target))

  # Step 1: Collect
  cat("\n[1/3] 수집...\n")
  snapshot <- naver_collect_all()
  if (is.null(snapshot)) {
    cat("[pipeline] 수집 실패.\n")
    return(invisible(NULL))
  }

  # Override Date with target (Naver always returns latest prices)
  snapshot[, Date := target]

  # Step 2: Merge
  cat("\n[2/3] 병합...\n")
  result <- naver_merge_rawdata(snapshot)

  # Step 3: Validate
  cat("\n[3/3] 검증...\n")
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  last_dates <- tail(sort(unique(raw$Date)), 3)
  for (d in last_dates) {
    cat(sprintf("  %s: %d tickers\n", d, nrow(raw[Date == d])))
  }

  cat("\n=== Pipeline Complete ===\n")
  invisible(result)
}

cat("[naver_data_collector] Loaded. Cache:", NAVER_CACHE_DIR, "\n")
cat("[naver_data_collector] Functions: naver_collect_all(), naver_quick_price(), naver_run_pipeline()\n")
