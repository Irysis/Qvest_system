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

# [Track R fix 2026-06-12] trading_calendar 의무 로드 — naver_merge_rawdata()의
# 누락거래일 BLOCK 가드(get_trading_days/last_confirmed_trading_day)가 exists() 조건부라
# 미로드 시 조용히 죽은 코드가 됨 (2026-05 토요일 phantom 적재의 공범). 실패 시 명시 경고.
if (!exists("is_trading_day")) {
  tryCatch(source(file.path(DATA_DIR, "trading_calendar.R")),
           error = function(e) cat(sprintf(
             "[naver_data_collector][WARN] trading_calendar load FAILED (%s) - merge guards DEAD\n",
             e$message)))
}

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
  # 장마감 후(16:00+)면 당일(단, 거래일일 때만), 아니면 전 거래일
  # [Track R fix 2026-06-12] last_confirmed_trading_day() 단일 경로 — 토/일/공휴일에
  # Sys.Date() 직스탬프 금지 (phantom 세션 근원). 캘린더 부재 시 직전 평일 fallback + WARN.
  if (exists("last_confirmed_trading_day")) {
    all_dt[, Date := last_confirmed_trading_day()]
  } else {
    d <- Sys.Date()
    now_hour <- as.integer(format(Sys.time(), "%H"))
    if (now_hour < 16) d <- d - 1L
    while (as.POSIXlt(d)$wday %in% c(0L, 6L)) d <- d - 1L
    cat("[Naver][WARN] trading_calendar 미로드 - 직전 평일 fallback (공휴일 미대조)\n")
    all_dt[, Date := d]
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

  # [v8.0 fix (c) 2026-05-29] benchmark SOT = naver_benchmark_update.py (chart-API, 실제 종가+날짜).
  # naver_kospi200_close()는 live 현재가 + Sys.Date() → 장중 실행 시 phantom(오늘날짜에 intraday값) 생성.
  # 여기서 benchmark cache WRITE 제거 (phantom 근원 차단). new_rows BM_Ret은 cache(실제 종가)에서 date-lookup만.
  # 신규 거래일이 cache에 아직 없으면 BM_Ret=NA → naver_benchmark_update.py 갱신 후 채워짐 (daily_refresh [1pre]).
  bm_cache <- tryCatch(as.data.table(read_parquet(BM_CACHE)), error = function(e) NULL)
  if (!is.null(bm_cache) && "BM_Ret" %in% names(bm_cache)) {
    bm_cache[, Date := as.Date(Date)]
    new_rows <- merge(new_rows, bm_cache[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
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

  # [Track R fix 2026-06-12] 결함 원인: 구버전은 target = Sys.Date()를 무검증 스탬프.
  #   cron 00:03에 Naver 시세페이지가 보여주는 종가는 '직전 거래일' 종가이므로
  #   (1) 전 구간 +1일 시프트, (2) 토/일/공휴일(05-01, 05-05, 05-25, 06-03 등)에
  #   phantom 세션 + Vol/Close forward-fill 적재 발생 (2026-05~06 실증, DATA_INTEGRITY_001).
  # 수정: target = last_confirmed_trading_day() (16:00 이전엔 직전 거래일). 캘린더
  #   부재 시 fail-loud (조용한 오염 적재보다 RAWDATA 미전진 WARN이 옳은 실패 모드).
  if (is.null(target_date)) {
    if (!exists("last_confirmed_trading_day"))
      stop("[pipeline] trading_calendar not loaded - refuse to stamp Sys.Date() blindly (Track R fix)")
    target <- last_confirmed_trading_day()
  } else {
    target <- as.Date(target_date, "%Y%m%d")
  }

  # 거래일 검증 게이트: 주말 무조건 차단 + 캘린더 대조
  wd <- as.POSIXlt(target)$wday
  if (wd %in% c(0L, 6L)) {
    cat(sprintf("[pipeline] BLOCKED: target %s is a weekend - not a trading session\n", target))
    return(invisible(NULL))
  }
  if (exists("is_trading_day") && !is_trading_day(target)) {
    cat(sprintf("[pipeline] BLOCKED: target %s not in trading calendar (holiday?)\n", target))
    return(invisible(NULL))
  }

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
