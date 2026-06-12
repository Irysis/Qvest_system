#==============================================================================
# KRX Build RAWDATA — Transform KRX API data into RAWDATA format
#
# Pipeline: detect gap → collect via API → transform → merge → update cache
#
# Usage:
#   source("config.R")
#   source("krx_data_collector.R")
#   source("krx_build_rawdata.R")
#   krx_run_pipeline()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
if (!exists("krx_api")) source(file.path(DATA_DIR, "krx_data_collector.R"))
# [Track R fix 2026-06-12] trading_calendar 의무 로드 — krx_detect_interior_gaps()/
# krx_merge_rawdata()의 거래일 가드가 exists() 조건부라 미로드 시 죽은 코드였음
# (daily_refresh [2]가 본 파일만 source → interior gap 감지 0건 고정, 06-04~09 누락 영구화).
if (!exists("is_trading_day")) {
  tryCatch(source(file.path(DATA_DIR, "trading_calendar.R")),
           error = function(e) cat(sprintf(
             "[krx_build_rawdata][WARN] trading_calendar load FAILED (%s) - calendar guards DEAD\n",
             e$message)))
}

#──────────────────────────────────────────────────────────────────────────────
# 1. Detect gap between RAWDATA and current date
#──────────────────────────────────────────────────────────────────────────────
krx_detect_gap <- function() {
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  last_date <- max(raw$Date)

  # last_confirmed_trading_day() 사용 (있으면), 없으면 T-1
  if (exists("last_confirmed_trading_day")) {
    target <- last_confirmed_trading_day()
  } else {
    target <- Sys.Date() - 1
  }

  list(
    last_rawdata_date = last_date,
    start = format(last_date + 1, "%Y%m%d"),
    end   = format(target, "%Y%m%d"),
    n_calendar_days = as.integer(target - last_date)
  )
}

#──────────────────────────────────────────────────────────────────────────────
# 1b. Interior gap 탐지 — RAWDATA 내 누락 거래일 전수 탐색
#──────────────────────────────────────────────────────────────────────────────
krx_detect_interior_gaps <- function(lookback_days = 60L) {
  if (!exists("get_trading_days")) {
    cat("[interior_gap] trading_calendar 미로드. 스킵.\n")
    return(character(0))
  }

  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  existing_dates <- sort(unique(raw$Date))

  cutoff <- Sys.Date() - lookback_days
  recent_existing <- existing_dates[existing_dates >= cutoff]
  if (length(recent_existing) < 2) return(character(0))

  confirmed <- if (exists("last_confirmed_trading_day")) last_confirmed_trading_day() else Sys.Date() - 1
  expected <- get_trading_days(min(recent_existing), confirmed)

  missing <- setdiff(as.character(expected), as.character(recent_existing))
  if (length(missing) > 0) {
    cat(sprintf("[interior_gap] %d 누락 거래일: %s\n", length(missing), paste(missing, collapse = ", ")))
  }
  missing
}

#──────────────────────────────────────────────────────────────────────────────
# 2. Transform a single date's KRX data → RAWDATA format
#──────────────────────────────────────────────────────────────────────────────
krx_transform_daily <- function(date_str) {
  # Load KOSPI + KOSDAQ OHLCV
  stk_file <- file.path(KRX_CACHE_DIR, "stk_ohlcv", sprintf("stk_ohlcv_%s.parquet", date_str))
  ksq_file <- file.path(KRX_CACHE_DIR, "ksq_ohlcv", sprintf("ksq_ohlcv_%s.parquet", date_str))

  stk <- if (file.exists(stk_file)) as.data.table(read_parquet(stk_file)) else NULL
  ksq <- if (file.exists(ksq_file)) as.data.table(read_parquet(ksq_file)) else NULL

  if (is.null(stk) && is.null(ksq)) return(NULL)

  ohlcv <- rbindlist(list(stk, ksq), fill = TRUE)

  # Column mapping (KRX API → RAWDATA)
  # ISU_CD → Ticker (prefix "A" to match RAWDATA format A000010)
  # ISU_NM → Name
  # Market → Market (already added in krx_collect_daily)
  # SECT_TP_NM → Sector
  # TDD_OPNPRC → Open, TDD_HGPRC → High, TDD_LWPRC → Low, TDD_CLSPRC → Close
  # ACC_TRDVOL → Vol, MKTCAP → Size

  .num <- function(x) as.numeric(gsub(",", "", x))

  dt <- ohlcv[, .(
    Date   = as.Date(date_str, "%Y%m%d"),
    Ticker = paste0("A", ISU_CD),
    Name   = ISU_NM,
    Market = fifelse(is.na(Market) | Market == "", MKT_NM, Market),
    Sector = fifelse(is.na(SECT_TP_NM) | SECT_TP_NM == "", NA_character_, SECT_TP_NM),
    Open   = .num(TDD_OPNPRC),
    High   = .num(TDD_HGPRC),
    Low    = .num(TDD_LWPRC),
    Close  = .num(TDD_CLSPRC),
    Vol    = .num(ACC_TRDVOL),
    Size   = .num(MKTCAP)
  )]

  # Remove rows with zero/NA Close
  dt <- dt[!is.na(Close) & Close > 0]

  dt
}

#──────────────────────────────────────────────────────────────────────────────
# 3. Compute BM_Ret from KOSPI 200 index
#──────────────────────────────────────────────────────────────────────────────
krx_compute_bm_ret <- function(date_strs) {
  idx_dir <- file.path(KRX_CACHE_DIR, "kospi_index")
  if (!dir.exists(idx_dir)) return(NULL)

  idx_list <- list()
  for (ds in date_strs) {
    f <- file.path(idx_dir, sprintf("kospi_index_%s.parquet", ds))
    if (file.exists(f)) {
      dt <- as.data.table(read_parquet(f))
      # Filter for KOSPI 200 index
      # BM = KOSPI(전체). "^코스피$" = 전체 지수, "코스피 200" = 다른 지수.
      k200 <- dt[grepl("^코스피$", IDX_NM)]
      if (nrow(k200) > 0) {
        idx_list[[length(idx_list) + 1]] <- data.table(
          Date     = as.Date(ds, "%Y%m%d"),
          BM_Close = as.numeric(gsub(",", "", k200$CLSPRC_IDX[1]))
        )
      }
    }
  }

  if (length(idx_list) == 0) return(NULL)
  bm_new <- rbindlist(idx_list)
  setorder(bm_new, Date)
  bm_new
}

#──────────────────────────────────────────────────────────────────────────────
# 4. Merge new data into RAWDATA.parquet
#──────────────────────────────────────────────────────────────────────────────
krx_merge_rawdata <- function() {
  gap <- krx_detect_gap()
  if (gap$n_calendar_days <= 0) {
    cat("[krx_merge] RAWDATA is up to date.\n")
    return(invisible(NULL))
  }

  dates <- seq(as.Date(gap$start, "%Y%m%d"), as.Date(gap$end, "%Y%m%d"), by = "day")
  # [Track R fix 2026-06-12] locale 무관 주말 필터 (한국어 locale에서 weekdays() 비교 무력)
  dates <- dates[!as.POSIXlt(dates)$wday %in% c(0L, 6L)]
  date_strs <- format(dates, "%Y%m%d")

  # Filter out known holidays
  date_strs <- date_strs[!sapply(date_strs, .krx_is_holiday)]

  # Transform each date
  cat(sprintf("[krx_merge] Transforming %d dates...\n", length(date_strs)))
  new_rows <- rbindlist(lapply(date_strs, function(ds) {
    tryCatch(krx_transform_daily(ds), error = function(e) {
      cat(sprintf("  [WARN] Transform failed for %s: %s\n", ds, e$message))
      NULL
    })
  }), fill = TRUE)

  if (is.null(new_rows) || nrow(new_rows) == 0) {
    cat("[krx_merge] No new data to merge.\n")
    return(invisible(NULL))
  }

  # Load existing RAWDATA — accept new tickers (신규 상장 반영)
  old_raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  known_tickers <- unique(old_raw$Ticker)
  new_tickers <- setdiff(unique(new_rows$Ticker), known_tickers)
  if (length(new_tickers) > 0) {
    cat(sprintf("[krx_merge] New tickers detected: %d (e.g. %s)\n",
                length(new_tickers), paste(head(new_tickers, 5), collapse = ", ")))
  }
  cat(sprintf("[krx_merge] Total tickers: %d (existing %d + new %d)\n",
              uniqueN(new_rows$Ticker), length(known_tickers), length(new_tickers)))

  # Compute daily returns per ticker
  # Get previous Close from existing RAWDATA for the first day
  last_closes <- old_raw[Date == max(Date), .(Ticker, Prev_Close = Close)]
  setorder(new_rows, Ticker, Date)

  # For each ticker, compute Ret = Close / lag(Close) - 1
  new_rows[, Ret := Close / shift(Close) - 1, by = Ticker]
  # Fix first day: use previous RAWDATA Close
  first_day <- min(new_rows$Date)
  first_rows <- new_rows[Date == first_day]
  first_rows <- merge(first_rows, last_closes, by = "Ticker", all.x = TRUE)
  first_rows[!is.na(Prev_Close) & Prev_Close > 0, Ret := Close / Prev_Close - 1]
  new_rows[Date == first_day, Ret := first_rows[match(new_rows[Date == first_day, Ticker], Ticker), Ret]]

  # Compute BM_Ret from KOSPI 200 index
  bm_new <- krx_compute_bm_ret(date_strs)
  if (!is.null(bm_new) && nrow(bm_new) > 0) {
    # Get previous BM_Close for first day's return
    old_bm <- as.data.table(read_parquet(BM_CACHE))
    last_bm_close <- old_bm[Date == max(Date)]$BM_Close[1]

    bm_new[, BM_Ret := BM_Close / shift(BM_Close) - 1]
    if (!is.na(last_bm_close) && last_bm_close > 0) {
      bm_new[1, BM_Ret := BM_Close / last_bm_close - 1]
    }

    # Join BM_Ret to new_rows
    new_rows <- merge(new_rows, bm_new[, .(Date, BM_Ret)], by = "Date", all.x = TRUE,
                      suffixes = c(".old", ""))
    if ("BM_Ret.old" %in% names(new_rows)) new_rows[, BM_Ret.old := NULL]

    # Update benchmark cache
    old_bm_ext <- rbind(old_bm, bm_new[!is.na(BM_Ret)], fill = TRUE)
    old_bm_ext <- unique(old_bm_ext, by = "Date")
    setorder(old_bm_ext, Date)
    setkey(old_bm_ext, Date)
    write_parquet(old_bm_ext, BM_CACHE)
    cat(sprintf("[krx_merge] Benchmark updated: %s ~ %s\n",
                min(old_bm_ext$Date), max(old_bm_ext$Date)))
  } else {
    new_rows[, BM_Ret := NA_real_]
    cat("[krx_merge] WARNING: No KOSPI 200 index data. BM_Ret = NA.\n")
  }

  # BM_Ret fallback: NA면 0 sentinel (날짜 전체 삭제 방지)
  bm_na <- sum(is.na(new_rows$BM_Ret))
  if (bm_na > 0) {
    cat(sprintf("[krx_merge] BM_Ret NA: %d rows → sentinel 0 적용 (삭제 안 함)\n", bm_na))
    new_rows[is.na(BM_Ret), BM_Ret := 0]
  }

  # Ret NA만 제거 (BM_Ret는 sentinel 처리했으므로 제거 안 함)
  new_rows <- new_rows[!is.na(Ret)]

  # 거래일 검증 gate
  if (exists("is_trading_day")) {
    non_td <- new_rows[!sapply(Date, is_trading_day)]
    if (nrow(non_td) > 0) {
      cat(sprintf("[krx_merge] 비거래일 %d rows 차단\n", nrow(non_td)))
      new_rows <- new_rows[sapply(Date, is_trading_day)]
    }
  }

  # source 태그
  if (!"source" %in% names(new_rows)) new_rows[, source := "krx_api"]

  # Ensure column order matches RAWDATA
  rawdata_cols <- c("Date", "BM_Ret", "Ticker", "Name", "Market", "Sector",
                    "Open", "High", "Low", "Close", "Vol", "Size", "Ret", "source")
  # Keep only existing columns
  keep_cols <- intersect(rawdata_cols, names(new_rows))
  new_rows <- new_rows[, ..keep_cols]

  # Add missing columns as NA
  for (col in setdiff(rawdata_cols, names(new_rows))) {
    new_rows[, (col) := NA]
  }
  setcolorder(new_rows, rawdata_cols)

  # Append to existing RAWDATA
  combined <- rbind(old_raw, new_rows, fill = TRUE)
  combined <- unique(combined, by = c("Date", "Ticker"))
  setorder(combined, Date, Ticker)

  write_parquet(combined, RAWDATA_CACHE)

  cat(sprintf("[krx_merge] RAWDATA extended: +%d rows | now %s ~ %s | %d total\n",
              nrow(new_rows), min(combined$Date), max(combined$Date), nrow(combined)))

  invisible(combined)
}

#──────────────────────────────────────────────────────────────────────────────
# 5. Orchestrator: full pipeline
#──────────────────────────────────────────────────────────────────────────────
krx_run_pipeline <- function() {
  cat("=== KRX Data Pipeline ===\n")

  # 1. Detect gap
  gap <- krx_detect_gap()
  cat(sprintf("Last RAWDATA date: %s\n", gap$last_rawdata_date))
  cat(sprintf("Target range: %s ~ %s (%d calendar days)\n",
              gap$start, gap$end, gap$n_calendar_days))

  if (gap$n_calendar_days <= 0) {
    cat("[pipeline] RAWDATA is already up to date.\n")
    return(invisible(NULL))
  }

  # 2. Collect from KRX API
  cat("\n[Step 1/3] Collecting from KRX API...\n")
  krx_collect_range(gap$start, gap$end)

  # 3. Transform + Merge
  cat("\n[Step 2/3] Transforming and merging...\n")
  result <- krx_merge_rawdata()

  # 4. Validate
  cat("\n[Step 3/3] Validation...\n")
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  cat(sprintf("  RAWDATA: %d rows | %d tickers | %s ~ %s\n",
              nrow(raw), uniqueN(raw$Ticker), min(raw$Date), max(raw$Date)))

  # Spot-check: last 3 dates
  last_dates <- tail(sort(unique(raw$Date)), 3)
  for (d in last_dates) {
    n <- nrow(raw[Date == d])
    cat(sprintf("  %s: %d tickers\n", d, n))
  }

  cat("\n=== KRX Pipeline Complete ===\n")
  invisible(result)
}

cat("[krx_build_rawdata] Loaded.\n")
