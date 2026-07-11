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
# ─── Internal: Benchmark 거래일 추출 (benchmark.parquet — chart-API 실세션 날짜) ──
# [Track R fix 2026-06-12] 구버전 Layer 2는 RAWDATA 자기참조(.extract_naver_dates)였음.
#   RAWDATA가 오염되면 캘린더도 따라 오염되는 순환 구조 (예: +1일 시프트로 05-01 노동절이
#   '평일'로 통과, 06-04~09 누락이 캘린더에서도 누락 → naver/krx 가드 전부 무력화).
#   benchmark.parquet은 naver_benchmark_update.py chart-API가 '실제 세션 날짜'로만 적재
#   (2026-06 위기주간 포함 무결 검증, T+30 review DATA_INTEGRITY_001) → 이를 Layer 2로 사용.
.extract_bm_dates <- function(start_after = NULL) {
  bm_path <- file.path(CACHE_DIR, "benchmark.parquet")
  if (!file.exists(bm_path)) return(as.Date(character(0)))

  bm <- as.data.table(read_parquet(bm_path, col_select = "Date"))
  bm[, Date := as.Date(Date)]
  dates <- sort(unique(bm$Date))

  # 주말 방어 (정상이라면 0건)
  wday <- as.POSIXlt(dates)$wday
  dates <- dates[wday >= 1 & wday <= 5]

  if (!is.null(start_after)) {
    dates <- dates[dates > as.Date(start_after)]
  }
  dates
}

# (구) RAWDATA 자기참조 추출 — 순환 오염으로 Layer 2에서 퇴출. 진단용으로만 보존.
.extract_naver_dates <- function(start_after = NULL) {
  rawdata_path <- file.path(CACHE_DIR, "rawdata.parquet")
  if (!file.exists(rawdata_path)) return(as.Date(character(0)))

  rd <- as.data.table(read_parquet(rawdata_path, col_select = "Date"))
  rd[, Date := as.Date(Date)]
  dates <- sort(unique(rd$Date))

  # weekday only (토일은 anomaly로 간주)
  wday <- as.POSIXlt(dates)$wday
  dates <- dates[wday >= 1 & wday <= 5]

  if (!is.null(start_after)) {
    dates <- dates[dates > as.Date(start_after)]
  }
  dates
}

# ─── Internal: KRX OpenAPI 거래일 (T+1 lag 감안 — 보조 검증용) ───────────────
.extract_krx_dates <- function(start = NULL, end = NULL) {
  krx_holidays_file <- file.path(CACHE_DIR, "krx", "known_holidays.rds")
  if (!file.exists(krx_holidays_file)) return(as.Date(character(0)))
  # KRX는 휴일 cache만 존재 — 거래일은 weekday minus holidays
  hol <- tryCatch(readRDS(krx_holidays_file), error = function(e) as.Date(character(0)))
  if (length(hol) == 0) return(as.Date(character(0)))

  if (is.null(start) || is.null(end)) {
    start <- min(hol) - 365
    end   <- max(hol) + 365
  }
  all_d <- seq.Date(as.Date(start), as.Date(end), by = "day")
  wday  <- as.POSIXlt(all_d)$wday
  trading <- all_d[wday >= 1 & wday <= 5 & !(all_d %in% hol)]
  trading
}

# ─── Internal: 한국 공휴일 manual list (KRX 임시 휴장 + 대체 휴일) ───────────
.korean_market_closures_manual <- function() {
  as.Date(c(
    # 2024 KRX 임시 휴장
    "2024-12-30",
    # 향후 추가 시 여기에
    NULL
  ))
}

# ─── Layer-priority 통합 캘린더 빌드 ─────────────────────────────────────────
# Layer 1: QuantiWise (있으면 ground truth)
# Layer 2: Naver T+0 (QW max(date) 이후 구간만 보충)
# Layer 3: KRX OpenAPI (T+1 lag, cross-check 검증용)
# Layer 4: 한국 공휴일 manual list (KRX 임시 휴장 등)
build_trading_calendar <- function(force = FALSE, verbose = TRUE) {
  if (file.exists(CALENDAR_CACHE) && !force) {
    if (verbose) cat("[calendar] 캐시 로드:", CALENDAR_CACHE, "\n")
    cal <- as.data.table(read_parquet(CALENDAR_CACHE))
    return(invisible(cal))
  }

  if (verbose) cat("[calendar] Layer-priority build 시작\n")

  # ─── Layer 1: QuantiWise (1차 ground truth) ────────────────────────────
  base_path   <- file.path(PROJECT_ROOT, "03_Universe", "OHLCVS.xlsx")
  update_path <- file.path(PROJECT_ROOT, "03_Universe", "Update_File", "OHLCVS_update.xlsx")
  qw_base_dates   <- .extract_qw_dates(base_path)
  qw_update_dates <- .extract_qw_dates(update_path)
  qw_dates <- sort(unique(c(qw_base_dates, qw_update_dates)))
  qw_max <- if (length(qw_dates) > 0) max(qw_dates) else NA
  if (verbose) {
    cat(sprintf("  [Layer 1] QuantiWise: %d일", length(qw_dates)))
    if (length(qw_dates) > 0) cat(sprintf(" (%s ~ %s)", min(qw_dates), qw_max))
    cat("\n")
  }

  # ─── Layer 2: Benchmark (chart-API 실세션) — QW max 이후 구간만 보충 ──────
  # [Track R fix 2026-06-12] RAWDATA 자기참조 → benchmark.parquet 교체 (순환 오염 차단)
  naver_supplement <- if (!is.na(qw_max)) {
    .extract_bm_dates(start_after = qw_max)
  } else {
    .extract_bm_dates()
  }
  if (verbose && length(naver_supplement) > 0) {
    cat(sprintf("  [Layer 2] Benchmark 보충: %d일 (%s ~ %s)\n",
                length(naver_supplement), min(naver_supplement), max(naver_supplement)))
  } else if (verbose) {
    cat(sprintf("  [Layer 2] Benchmark 보충: 0일 (QW가 최신)\n"))
  }

  # ─── Layer 3: KRX OpenAPI (T+1 lag 감안 cross-check) ─────────────────────
  if (length(qw_dates) > 0 && length(naver_supplement) > 0) {
    krx_check_dates <- .extract_krx_dates(start = qw_max, end = max(naver_supplement))
    # T+1 lag 감안: KRX max(Date) ≤ Naver max(Date) - 1
    naver_only_recent_2d <- tail(sort(naver_supplement), 2)
    krx_supports <- intersect(krx_check_dates, naver_supplement)
    krx_missing  <- setdiff(naver_supplement, krx_check_dates)
    krx_missing  <- as.Date(krx_missing[!krx_missing %in% naver_only_recent_2d])  # T+1/T+2는 lag로 정상
    if (verbose) {
      cat(sprintf("  [Layer 3] KRX cross-check: %d 일치 / %d 비일치 (T+1 lag 제외)\n",
                  length(krx_supports), length(krx_missing)))
      if (length(krx_missing) > 0) {
        cat(sprintf("    [WARN] Naver-only (KRX 부재): %s\n",
                    paste(head(krx_missing, 5), collapse=", ")))
      }
    }
  }

  # ─── Layer 2b: QW 커버리지 내부 공백 보충 (2026-07-11 fix — 4월 소실 사고) ──
  # QuantiWise base/update 수출 커버리지에 이음매 구멍이 생기면(실사고: base ~03-27 +
  # update 04-30~ → 2026-03-30~04-29가 어느 파일에도 없음) 그 구간 실거래일이 캘린더에서
  # 통째로 빠져 '비거래일'로 오판된다. 이 캘린더 구멍이 build_cache/incremental_ohlcvs
  # 리빌드 시 rawdata 4월 한 달 삭제(~72k rows)를 침묵 통과시켰고, interior gap 감지 등
  # 캘린더 기준 가드 전부의 사각지대가 됐다. benchmark.parquet은 chart-API 실세션
  # 날짜(2026-06 위기주간 무결 검증)이므로 QW 범위 '내부'의 누락 거래일을 보충한다.
  bm_interior <- as.Date(character(0))
  if (length(qw_dates) > 0) {
    bm_all <- .extract_bm_dates()
    bm_interior <- bm_all[bm_all > min(qw_dates) & bm_all < qw_max & !bm_all %in% qw_dates]
    if (verbose && length(bm_interior) > 0) {
      cat(sprintf("  [Layer 2b][WARN] QW 수출 커버리지 내부 공백 %d일 → benchmark로 보충 (%s ~ %s) — QuantiWise 재수출로 근본 해소 권장\n",
                  length(bm_interior), min(bm_interior), max(bm_interior)))
    }
  }

  # ─── Layer 4: 공휴일 manual 제외 ─────────────────────────────────────────
  closures <- .korean_market_closures_manual()
  qw_dates <- setdiff(qw_dates, closures)
  naver_supplement <- setdiff(naver_supplement, closures)
  bm_interior <- setdiff(bm_interior, closures)

  # ─── 통합 + 우선순위 source 라벨링 ───────────────────────────────────────
  if (length(qw_dates) > 0) {
    cal_qw <- data.table(Date = as.Date(qw_dates), source = "quantiwise")
    cal_qw[Date %in% as.Date(qw_update_dates) & Date > max(as.Date(qw_base_dates), na.rm = TRUE),
           source := "quantiwise_update"]
  } else {
    cal_qw <- data.table(Date = as.Date(character(0)), source = character(0))
  }
  cal_naver <- if (length(naver_supplement) > 0) {
    data.table(Date = as.Date(naver_supplement), source = "benchmark")
  } else {
    data.table(Date = as.Date(character(0)), source = character(0))
  }
  cal_interior <- if (length(bm_interior) > 0) {
    data.table(Date = as.Date(bm_interior), source = "benchmark_interior")
  } else {
    data.table(Date = as.Date(character(0)), source = character(0))
  }

  cal <- rbind(cal_qw, cal_naver, cal_interior)
  setorder(cal, Date)
  cal <- unique(cal, by = "Date")  # QW가 우선 (rbind 순서)

  write_parquet(cal, CALENDAR_CACHE)
  if (verbose) {
    cat(sprintf("[calendar] 저장 완료: %d 거래일 (%s ~ %s)\n",
                nrow(cal), min(cal$Date), max(cal$Date)))
    src_dist <- cal[, .N, by = source]
    cat(sprintf("  Source 분포: %s\n",
                paste(src_dist[, sprintf("%s=%d", source, N)], collapse = ", ")))
  }
  invisible(cal)
}

# ─── 캘린더 로드 (메모리 캐싱) ────────────────────────────────────────────────
.CALENDAR <- NULL

.load_calendar <- function() {
  if (!is.null(.CALENDAR)) return(.CALENDAR)
  if (file.exists(CALENDAR_CACHE)) {
    .CALENDAR <<- as.data.table(read_parquet(CALENDAR_CACHE))
    # [Track R fix 2026-06-12] staleness self-heal: 캐시 max(Date)가 benchmark max(Date)보다
    # 뒤처지면 자동 재빌드. (실증: 캐시가 2026-04-28에 동결된 채 6주 방치 →
    # last_confirmed_trading_day()가 4월을 반환, 모든 가드가 무의미해짐)
    bm_max <- tryCatch(max(.extract_bm_dates(), na.rm = TRUE), error = function(e) as.Date(NA))
    cal_max <- suppressWarnings(max(as.Date(.CALENDAR$Date), na.rm = TRUE))
    if (!is.na(bm_max) && !is.na(cal_max) && bm_max > cal_max) {
      cat(sprintf("[calendar] 캐시 stale (cal_max=%s < bm_max=%s) - 자동 재빌드\n", cal_max, bm_max))
      .CALENDAR <<- build_trading_calendar(force = TRUE, verbose = FALSE)
    }
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
  # ★TZ 버그 수정(2026-06-19): as.Date(now)는 기본 UTC 변환이라 09시(KST) 이전엔 전일로 롤백
  #   → today가 하루 일찍 잡혀 last_confirmed가 T-2 반환 → RAWDATA/KTRI/regime 매일 1일 stale.
  #   format(now,"%Y-%m-%d")는 로컬 tz(=hour 계산과 동일) 사용해 정합.
  today <- as.Date(format(now, "%Y-%m-%d"))
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
