#==============================================================================
# Trading Calendar — KRX 거래일 캘린더 (QuantiWise Ground Truth)
#
# QuantiWise OHLCVS.xlsx의 날짜 열을 ground truth로 사용.
# 모든 데이터 삽입/조회 시 이 캘린더로 검증.
#
# 사용법:
#   source("02_Infrastructure/trading_calendar.R")
#   is_trading_day(as.Date("2026-03-31"))
#   get_trading_days(as.Date("2026-03-01"), as.Date("2026-03-31"))
#   get_prev_trading_day(as.Date("2026-04-01"))
#   last_confirmed_trading_day()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(openxlsx)
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

CALENDAR_CACHE <- file.path(CACHE_DIR, "trading_calendar.parquet")

# ─── Internal: QuantiWise xlsx에서 날짜 추출 ──────────────────────────────────
.extract_qw_dates <- function(xlsx_path) {
  if (!file.exists(xlsx_path)) return(as.Date(character(0)))
  raw <- read.xlsx(xlsx_path, sheet = 4, cols = 1, skipEmptyRows = FALSE)
  vals <- raw[-1:-5, 1]
  serials <- suppressWarnings(as.numeric(vals))
  dates <- as.Date(serials[!is.na(serials)], origin = "1899-12-30")
  sort(unique(dates))
}

# ─── Build / Load 캘린더 ─────────────────────────────────────────────────────
build_trading_calendar <- function(force = FALSE) {
  if (file.exists(CALENDAR_CACHE) && !force) {
    cat("[calendar] 캐시 로드:", CALENDAR_CACHE, "\n")
    cal <- as.data.table(read_parquet(CALENDAR_CACHE))
    return(invisible(cal))
  }

  cat("[calendar] QuantiWise에서 거래일 추출 중...\n")

  # 1. Base OHLCVS.xlsx (1990~)
  base_path <- file.path(PROJECT_ROOT, "03_Universe", "OHLCVS.xlsx")
  base_dates <- .extract_qw_dates(base_path)
  cat(sprintf("  base: %d일 (%s ~ %s)\n", length(base_dates),
              min(base_dates), max(base_dates)))

  # 2. Update_File OHLCVS_update.xlsx (증분)
  update_path <- file.path(PROJECT_ROOT, "03_Universe", "Update_File", "OHLCVS_update.xlsx")
  update_dates <- .extract_qw_dates(update_path)
  if (length(update_dates) > 0) {
    cat(sprintf("  update: %d일 (%s ~ %s)\n", length(update_dates),
                min(update_dates), max(update_dates)))
  }

  # 3. 병합 (중복 제거)
  all_dates <- sort(unique(c(base_dates, update_dates)))

  cal <- data.table(
    Date = all_dates,
    source = fifelse(all_dates <= max(base_dates), "quantiwise", "quantiwise_update")
  )
  # Update_File 범위 내 날짜는 quantiwise_update로 마킹
  if (length(update_dates) > 0) {
    cal[Date %in% update_dates & Date > max(base_dates), source := "quantiwise_update"]
  }

  write_parquet(cal, CALENDAR_CACHE)
  cat(sprintf("[calendar] 저장 완료: %d 거래일 (%s ~ %s)\n",
              nrow(cal), min(cal$Date), max(cal$Date)))
  invisible(cal)
}

# ─── 캘린더 로드 (메모리 캐싱) ────────────────────────────────────────────────
.CALENDAR <- NULL

.load_calendar <- function() {
  if (!is.null(.CALENDAR)) return(.CALENDAR)
  if (file.exists(CALENDAR_CACHE)) {
    .CALENDAR <<- as.data.table(read_parquet(CALENDAR_CACHE))
  } else {
    .CALENDAR <<- build_trading_calendar()
  }
  .CALENDAR
}

# ─── KRX API 응답일로 임시 보충 ──────────────────────────────────────────────
add_krx_trading_day <- function(date) {
  cal <- .load_calendar()
  d <- as.Date(date)
  if (d %in% cal$Date) return(invisible(NULL))

  cal <- rbind(cal, data.table(Date = d, source = "krx_api"))
  setorder(cal, Date)
  .CALENDAR <<- cal
  write_parquet(cal, CALENDAR_CACHE)
  cat(sprintf("[calendar] KRX 임시 거래일 추가: %s\n", d))
}

# ─── Public 함수 ─────────────────────────────────────────────────────────────

#' 해당 날짜가 거래일인지 확인
is_trading_day <- function(date) {
  cal <- .load_calendar()
  as.Date(date) %in% cal$Date
}

#' 기간 내 거래일 벡터 반환
get_trading_days <- function(start, end) {
  cal <- .load_calendar()
  cal[Date >= as.Date(start) & Date <= as.Date(end)]$Date
}

#' 직전 거래일
get_prev_trading_day <- function(date) {
  cal <- .load_calendar()
  d <- as.Date(date)
  prev <- cal[Date < d]
  if (nrow(prev) == 0) return(NA_Date_)
  max(prev$Date)
}

#' 다음 거래일
get_next_trading_day <- function(date) {
  cal <- .load_calendar()
  d <- as.Date(date)
  nxt <- cal[Date > d]
  if (nrow(nxt) == 0) return(NA_Date_)
  min(nxt$Date)
}

#' 종가가 확정된 가장 최근 거래일
#' 16:00 이후 → 오늘 (장마감 후, 오늘이 거래일이면)
#' 그 외 → 직전 거래일
last_confirmed_trading_day <- function() {
  cal <- .load_calendar()
  now <- Sys.time()
  today <- as.Date(now)
  hour <- as.integer(format(now, "%H"))

  if (hour >= 16 && today %in% cal$Date) {
    return(today)
  }
  get_prev_trading_day(today)
}

#' 캘린더 요약 출력
calendar_summary <- function() {
  cal <- .load_calendar()
  cat(sprintf("=== Trading Calendar ===\n"))
  cat(sprintf("거래일: %d일 (%s ~ %s)\n", nrow(cal), min(cal$Date), max(cal$Date)))
  cat(sprintf("Source: %s\n", paste(cal[, .N, by=source][, sprintf("%s=%d", source, N)], collapse=", ")))
  cat(sprintf("마지막 확정 거래일: %s\n", last_confirmed_trading_day()))
}

cat("[trading_calendar] Loaded. Functions: is_trading_day(), get_trading_days(), get_prev/next_trading_day(), last_confirmed_trading_day()\n")
