#==============================================================================
# ECOS (한국은행) 데이터 수집기
#
# 원/달러 환율 (매매기준율, 서울외환시장 15:30 확정)
# → 시차 제로: 한국 장마감과 동시에 확정
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/data_collector_ecos.R")
#   ecos_fetch_krw()          # 전체 수집 + 캐시 저장
#   ecos_load_krw()           # 캐시에서 로드
#==============================================================================
cat("[ecos] Loading...\n")

suppressPackageStartupMessages({ library(data.table); library(arrow); library(httr); library(jsonlite) })

if (!exists("ECOS_API_KEY")) ECOS_API_KEY <- "AIQOGTG4QU4GWPCT8INK"
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
if (!exists("ECOS_KRW_CACHE")) ECOS_KRW_CACHE <- file.path(CACHE_DIR, "ecos_krw_usd.parquet")

#' Fetch KRW/USD daily exchange rate from ECOS
#'
#' 통계표코드: 731Y001 (일별 평균환율/기준환율)
#' 항목코드: 0000001 (원/미달러)
#' 주기: D (일별)
#'
#' @param start_date Start date (YYYYMMDD)
#' @param end_date End date (YYYYMMDD)
#' @return data.table(Date, KRW_USD)
#' @export
ecos_fetch_krw <- function(start_date = "20000101", end_date = NULL) {
  if (is.null(end_date)) end_date <- format(Sys.Date(), "%Y%m%d")
  
  # ECOS API endpoint
  # /api/StatisticSearch/{API_KEY}/{언어}/{요청유형}/{시작건수}/{끝건수}/{통계표코드}/{주기}/{검색시작일자}/{검색끝일자}/{항목코드1}
  base_url <- sprintf(
    "https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/1/10000/731Y001/D/%s/%s/0000001",
    ECOS_API_KEY, start_date, end_date
  )
  
  cat(sprintf("[ecos] Fetching KRW/USD: %s ~ %s\n", start_date, end_date))
  
  resp <- tryCatch({
    GET(base_url, timeout(30))
  }, error = function(e) {
    cat(sprintf("[ecos] HTTP error: %s\n", e$message))
    return(NULL)
  })
  
  if (is.null(resp) || status_code(resp) != 200) {
    cat(sprintf("[ecos] HTTP status: %s\n", status_code(resp)))
    return(NULL)
  }
  
  json <- fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  
  if (is.null(json$StatisticSearch$row)) {
    cat("[ecos] No data returned\n")
    if (!is.null(json$RESULT)) cat(sprintf("  RESULT: %s - %s\n", json$RESULT$CODE, json$RESULT$MESSAGE))
    return(NULL)
  }
  
  rows <- rbindlist(json$StatisticSearch$row, fill = TRUE)
  
  result <- data.table(
    Date = as.Date(rows$TIME, format = "%Y%m%d"),
    KRW_USD = as.numeric(rows$DATA_VALUE)
  )
  result <- result[!is.na(Date) & !is.na(KRW_USD)]
  setorder(result, Date)
  
  cat(sprintf("[ecos] KRW/USD: %d rows (%s ~ %s)\n", nrow(result), min(result$Date), max(result$Date)))
  cat(sprintf("  Latest: %s = %.2f\n", max(result$Date), result[.N, KRW_USD]))
  
  # Save to cache
  dir.create(dirname(ECOS_KRW_CACHE), recursive = TRUE, showWarnings = FALSE)
  write_parquet(result, ECOS_KRW_CACHE)
  cat(sprintf("[ecos] Cache saved: %s\n", ECOS_KRW_CACHE))
  
  result
}

#' Load KRW/USD from cache
#' @export
ecos_load_krw <- function() {
  if (!file.exists(ECOS_KRW_CACHE)) {
    cat("[ecos] Cache not found, fetching...\n")
    return(ecos_fetch_krw())
  }
  as.data.table(read_parquet(ECOS_KRW_CACHE))
}

cat("[ecos] Loaded. Functions: ecos_fetch_krw(), ecos_load_krw()\n")
