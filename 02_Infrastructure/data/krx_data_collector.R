#==============================================================================
# KRX Data Collector — Official Open API (data-dbg.krx.co.kr)
# PER/PBR/배당수익률, 전종목시세, 공매도, 외국인 보유 수집
#
# 사용법:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/krx_data_collector.R")
#   krx_collect_daily("20260303")              # 특정일 전체 수집
#   krx_collect_range("20260101", "20260303")   # 기간 수집
#   krx_load("stk_ohlcv")                      # 수집된 데이터 로드
#
# API 문서: https://openapi.krx.co.kr
# 일 호출 한도: 10,000건
#==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))

KRX_CACHE_DIR <- file.path(PROJECT_ROOT, ".cache", "krx")
if (!dir.exists(KRX_CACHE_DIR)) dir.create(KRX_CACHE_DIR, recursive = TRUE)

# ─── Holiday cache ──────────────────────────────────────────────────────────
.krx_holidays_file <- file.path(KRX_CACHE_DIR, "known_holidays.rds")

.krx_is_holiday <- function(date_str) {
  if (!file.exists(.krx_holidays_file)) return(FALSE)
  date_str %in% readRDS(.krx_holidays_file)
}

.krx_mark_holiday <- function(date_str) {
  holidays <- if (file.exists(.krx_holidays_file)) readRDS(.krx_holidays_file) else character(0)
  holidays <- unique(c(holidays, date_str))
  saveRDS(holidays, .krx_holidays_file)
}

# Load API key from .env
KRX_API_KEY <- Sys.getenv("KRX_API_KEY")
if (KRX_API_KEY == "") {
  env_file <- file.path(PROJECT_ROOT, ".env")
  if (file.exists(env_file)) {
    env_lines <- readLines(env_file, warn = FALSE)
    key_line <- grep("^KRX_API_KEY=", env_lines, value = TRUE)
    if (length(key_line) > 0) KRX_API_KEY <- sub("^KRX_API_KEY=", "", key_line[1])
  }
}
if (KRX_API_KEY == "") cat("[KRX] WARNING: KRX_API_KEY not found in .env\n")

#──────────────────────────────────────────────────────────────────────────────
# Core: KRX Open API request
# Base URL: https://data-dbg.krx.co.kr/svc/apis/
# Auth: AUTH_KEY header
#──────────────────────────────────────────────────────────────────────────────
KRX_API_BASE <- "https://data-dbg.krx.co.kr/svc/apis"

krx_api <- function(endpoint, params = list(), max_retry = 3) {
  url <- paste0(KRX_API_BASE, endpoint)

  for (attempt in 1:max_retry) {
    resp <- tryCatch({
      POST(url,
           body = toJSON(params, auto_unbox = TRUE),
           add_headers(
             `AUTH_KEY` = trimws(KRX_API_KEY),
             `Content-Type` = "application/json",
             `Accept` = "application/json"
           ),
           encode = "raw",
           content_type_json())
    }, error = function(e) { Sys.sleep(2); NULL })

    if (!is.null(resp)) {
      sc <- status_code(resp)
      if (sc == 200) {
        txt <- content(resp, "text", encoding = "UTF-8")
        parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
        if (!is.null(parsed)) {
          dt <- if (!is.null(parsed$OutBlock_1)) as.data.table(parsed$OutBlock_1)
                else if (!is.null(parsed$output))  as.data.table(parsed$output)
                else if (is.data.frame(parsed))    as.data.table(parsed)
                else NULL
          Sys.sleep(0.5)  # rate limit (~10k/day)
          return(dt)
        }
      } else if (sc == 401) {
        cat(sprintf("[KRX API] 401 Unauthorized — check AUTH_KEY\n"))
        return(NULL)
      } else {
        cat(sprintf("[KRX API] HTTP %d on attempt %d for %s\n", sc, attempt, endpoint))
      }
    }
    cat(sprintf("[KRX API] Attempt %d failed for %s. Retrying...\n", attempt, endpoint))
    Sys.sleep(2)
  }
  cat(sprintf("[KRX API] FAILED after %d attempts: %s\n", max_retry, endpoint))
  return(NULL)
}

#──────────────────────────────────────────────────────────────────────────────
# 1. KOSPI 전종목 일별 시세
#──────────────────────────────────────────────────────────────────────────────
krx_stk_ohlcv <- function(date_str) {
  cat(sprintf("[KRX] KOSPI OHLCV: %s\n", date_str))
  krx_api("/sto/stk_bydd_trd", list(basDd = date_str))
}

#──────────────────────────────────────────────────────────────────────────────
# 2. KOSDAQ 전종목 일별 시세
#──────────────────────────────────────────────────────────────────────────────
krx_ksq_ohlcv <- function(date_str) {
  cat(sprintf("[KRX] KOSDAQ OHLCV: %s\n", date_str))
  krx_api("/sto/ksq_bydd_trd", list(basDd = date_str))
}

#──────────────────────────────────────────────────────────────────────────────
# 3. KOSPI 지수 일별 시세
#──────────────────────────────────────────────────────────────────────────────
krx_kospi_index <- function(date_str) {
  cat(sprintf("[KRX] KOSPI Index: %s\n", date_str))
  krx_api("/idx/kospi_dd_trd", list(basDd = date_str))
}

#──────────────────────────────────────────────────────────────────────────────
# 4. KOSDAQ 지수 일별 시세
#──────────────────────────────────────────────────────────────────────────────
krx_kosdaq_index <- function(date_str) {
  cat(sprintf("[KRX] KOSDAQ Index: %s\n", date_str))
  krx_api("/idx/kosdaq_dd_trd", list(basDd = date_str))
}

#──────────────────────────────────────────────────────────────────────────────
# 5. 종목기본정보 (KOSPI)
#──────────────────────────────────────────────────────────────────────────────
krx_stk_info <- function(date_str) {
  cat(sprintf("[KRX] KOSPI stock info: %s\n", date_str))
  krx_api("/sto/stk_isu_base_info", list(basDd = date_str))
}

#──────────────────────────────────────────────────────────────────────────────
# 6. 종목기본정보 (KOSDAQ)
#──────────────────────────────────────────────────────────────────────────────
krx_ksq_info <- function(date_str) {
  cat(sprintf("[KRX] KOSDAQ stock info: %s\n", date_str))
  krx_api("/sto/ksq_isu_base_info", list(basDd = date_str))
}

#──────────────────────────────────────────────────────────────────────────────
# Daily collection: 하루치 전체 수집 + Parquet 저장
#──────────────────────────────────────────────────────────────────────────────
krx_collect_daily <- function(date_str) {
  cat(sprintf("\n=== KRX Daily Collection: %s ===\n", date_str))

  results <- list()

  # KOSPI OHLCV
  stk <- krx_stk_ohlcv(date_str)
  if (!is.null(stk) && nrow(stk) > 0) {
    stk[, `:=`(Date = date_str, Market = "KOSPI")]
    results$stk_ohlcv <- stk
    cat(sprintf("  KOSPI stocks: %d\n", nrow(stk)))
  }

  # KOSDAQ OHLCV
  ksq <- krx_ksq_ohlcv(date_str)
  if (!is.null(ksq) && nrow(ksq) > 0) {
    ksq[, `:=`(Date = date_str, Market = "KOSDAQ")]
    results$ksq_ohlcv <- ksq
    cat(sprintf("  KOSDAQ stocks: %d\n", nrow(ksq)))
  }

  # KOSPI Index
  idx <- krx_kospi_index(date_str)
  if (!is.null(idx) && nrow(idx) > 0) {
    idx[, Date := date_str]
    results$kospi_index <- idx
    cat(sprintf("  KOSPI indices: %d\n", nrow(idx)))
  }

  # Stock info (KOSPI)
  info <- krx_stk_info(date_str)
  if (!is.null(info) && nrow(info) > 0) {
    info[, Date := date_str]
    results$stk_info <- info
    cat(sprintf("  KOSPI stock info: %d\n", nrow(info)))
  }

  # Stock info (KOSDAQ)
  ksq_info <- krx_ksq_info(date_str)
  if (!is.null(ksq_info) && nrow(ksq_info) > 0) {
    ksq_info[, Date := date_str]
    results$ksq_info <- ksq_info
    cat(sprintf("  KOSDAQ stock info: %d\n", nrow(ksq_info)))
  }

  # KOSDAQ Index
  ksq_idx <- krx_kosdaq_index(date_str)
  if (!is.null(ksq_idx) && nrow(ksq_idx) > 0) {
    ksq_idx[, Date := date_str]
    results$kosdaq_index <- ksq_idx
    cat(sprintf("  KOSDAQ indices: %d\n", nrow(ksq_idx)))
  }

  # No data check: skip saving but do NOT mark as holiday

  # (API delay can cause false holiday marking — removed auto-mark per user feedback)
  if (is.null(results$stk_ohlcv) && is.null(results$ksq_ohlcv)) {
    cat(sprintf("[KRX] %s → no data returned (API delay or holiday). Skipping.\n", date_str))
    return(invisible(list()))
  }

  # Save to Parquet (append-friendly by date partition)
  for (nm in names(results)) {
    out_dir <- file.path(KRX_CACHE_DIR, nm)
    if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
    out_file <- file.path(out_dir, sprintf("%s_%s.parquet", nm, date_str))
    write_parquet(results[[nm]], out_file)
  }

  cat(sprintf("[KRX] Daily collection complete: %d datasets saved\n", length(results)))
  invisible(results)
}

#──────────────────────────────────────────────────────────────────────────────
# Range collection: 기간 수집 (영업일만)
#──────────────────────────────────────────────────────────────────────────────
krx_collect_range <- function(start_str, end_str) {
  dates <- seq(as.Date(start_str, "%Y%m%d"), as.Date(end_str, "%Y%m%d"), by = "day")
  dates <- dates[!weekdays(dates) %in% c("Saturday", "Sunday")]
  date_strs <- format(dates, "%Y%m%d")

  cat(sprintf("[KRX] Range collection: %s ~ %s (%d business days)\n",
              start_str, end_str, length(date_strs)))

  for (i in seq_along(date_strs)) {
    # Skip holidays and already collected
    if (.krx_is_holiday(date_strs[i])) {
      cat(sprintf("  [%d/%d] %s -- known holiday, skip\n", i, length(date_strs), date_strs[i]))
      next
    }
    stk_file <- file.path(KRX_CACHE_DIR, "stk_ohlcv", sprintf("stk_ohlcv_%s.parquet", date_strs[i]))
    if (file.exists(stk_file)) {
      cat(sprintf("  [%d/%d] %s -- already collected, skip\n", i, length(date_strs), date_strs[i]))
      next
    }
    cat(sprintf("  [%d/%d] %s\n", i, length(date_strs), date_strs[i]))
    tryCatch(krx_collect_daily(date_strs[i]), error = function(e) {
      cat(sprintf("  [ERROR] %s: %s\n", date_strs[i], e$message))
    })
  }
  cat("[KRX] Range collection complete.\n")
}

#──────────────────────────────────────────────────────────────────────────────
# Load collected data: Parquet files → single data.table
#──────────────────────────────────────────────────────────────────────────────
krx_load <- function(dataset = "stk_ohlcv") {
  dir_path <- file.path(KRX_CACHE_DIR, dataset)
  if (!dir.exists(dir_path)) {
    cat(sprintf("[KRX] No data for %s\n", dataset))
    return(data.table())
  }
  files <- list.files(dir_path, pattern = "\\.parquet$", full.names = TRUE)
  if (length(files) == 0) return(data.table())
  dt <- rbindlist(lapply(files, read_parquet), fill = TRUE)
  cat(sprintf("[KRX] Loaded %s: %d rows from %d files\n", dataset, nrow(dt), length(files)))
  dt
}

cat("[krx_data_collector] Loaded. Cache:", KRX_CACHE_DIR, "\n")
cat("[krx_data_collector] API key:", ifelse(nchar(KRX_API_KEY) > 0, "SET", "MISSING"), "\n")
