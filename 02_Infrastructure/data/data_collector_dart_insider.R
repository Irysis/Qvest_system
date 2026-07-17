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
# API: opendart.fss.or.kr/api/elestock.json (필수 파라미터 = corp_code — 2026-07-17 수리)
# Rate: 일 10,000건, 0.7초 간격
# ⚠ elestock 응답은 회사당 최근 ~2년 창만 반환 — 2005~ 역사 전구간은
#   dart_insider_backfill.R (document.xml 파서, .cache/dart/insider_backfill/) 담당.
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
#' Uses list.json with pblntf_ty=D (지분공시 — 임원·주요주주 특정증권 소유상황 포함)
#' ⚠ 버그수리 2026-06-30: 기존 "E"(=기타공시)는 insider 공시를 전혀 포함하지 않음(probe 실측 page1 insider 0).
#'   올바른 지분공시 = "D"(probe 실측 page1 임원·주요주주특정증권 42~76건).
.fetch_insider_list <- function(api_key, bgn_de, end_de, page_no = 1, page_count = 100) {
  url <- "https://opendart.fss.or.kr/api/list.json"
  resp <- GET(url, query = list(
    crtfc_key = api_key,
    bgn_de    = bgn_de,
    end_de    = end_de,
    pblntf_ty = "D",
    page_no   = page_no,
    page_count = page_count
  ))
  if (status_code(resp) != 200) return(NULL)
  parsed <- fromJSON(content(resp, "text", encoding = "UTF-8"), flatten = TRUE)
  if (parsed$status != "000") return(NULL)
  as.data.table(parsed$list)
}

#' Fetch elestock (임원 주요주주 특정증권 소유상황) for a company
#' ⚠ 버그수리 2026-07-17: elestock.json 필수 파라미터는 corp_code (rcept_no 아님).
#'   기존 rcept_no 호출은 status=100 "필수값이 누락되었습니다"로 전량 실패 —
#'   daily incremental이 한 번도 detail을 수집하지 못해 insider_trades.parquet
#'   max(Date)가 2026-03-20에 동결된 원인 (probe 실측 2026-07-17).
#'   corp_code 호출은 해당 회사의 최근(~2년 창) 소유상황보고 전체를 반환하므로
#'   회사당 1회 호출로 그 회사의 신규 filing 전부 커버.
#' @param status_counter optional environment — API status별 실패 집계(원인 은폐 방지)
.fetch_elestock <- function(api_key, corp_code, status_counter = NULL) {
  url <- "https://opendart.fss.or.kr/api/elestock.json"
  resp <- GET(url, query = list(
    crtfc_key = api_key,
    corp_code = corp_code
  ))
  if (status_code(resp) != 200) {
    if (!is.null(status_counter)) status_counter$http <- (status_counter$http %||% 0L) + 1L
    return(NULL)
  }
  parsed <- fromJSON(content(resp, "text", encoding = "UTF-8"), flatten = TRUE)
  if (parsed$status != "000") {
    if (!is.null(status_counter)) {
      k <- paste0("s", parsed$status)
      status_counter[[k]] <- (status_counter[[k]] %||% 0L) + 1L
    }
    return(NULL)
  }
  as.data.table(parsed$list)
}

#' Main: Fetch insider trades for given years
#'
#' 2026-07-17 재설계 (corp_code 버그수리 동반):
#'   - detail 수집 = 월별 list에서 모은 공시의 unique corp_code당 elestock 1회 호출
#'     (회사 응답이 그 회사 filing 전체를 담으므로 rcept_no in-list 필터로 창 scoping).
#'   - 구 "월 50건 샘플링 cap" 제거 — silent 부분수집이었음. 상한은 max_corp_fetch로
#'     명시하고 초과 시 로그로 절단 사실 고지 (no silent caps).
#'   - bgn_date 지정 시 그 날짜 이후 접수분만 (daily incremental 증분용 — 연 전체
#'     재수집으로 인한 일 수천 call 낭비 방지).
#'
#' @param years integer vector e.g. 2015:2025
#' @param delay numeric seconds between API calls
#' @param bgn_date optional Date — 이 날짜(포함) 이후 rcept_dt만 수집
#' @param max_corp_fetch integer — elestock 호출 회사 수 상한 (quota 가드, 초과 시 로그)
#' @return data.table of insider trades, also saved to parquet
dart_fetch_insider <- function(years = 2015:2025, delay = 0.7,
                               bgn_date = NULL, max_corp_fetch = 4000L) {
  api_key <- .load_dart_key()
  corpmap <- .load_corpcode_map()

  disc_all <- list()

  for (yr in years) {
    for (mo in 1:12) {
      m_start <- as.Date(sprintf("%04d-%02d-01", yr, mo))
      m_end <- seq.Date(m_start, by = "month", length.out = 2)[2] - 1

      # Skip future months + bgn_date 이전 완결 월
      if (m_start > Sys.Date()) next
      if (!is.null(bgn_date) && m_end < as.Date(bgn_date)) next

      bgn <- format(max(m_start, as.Date(bgn_date %||% m_start)), "%Y%m%d")
      end <- format(m_end, "%Y%m%d")

      cat(sprintf("[dart_insider] Listing %04d-%02d (%s ~ %s)...\n", yr, mo, bgn, end))

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
      cat(sprintf("  insider disclosures: %d\n", nrow(disc_dt)))
      if (nrow(disc_dt) > 0) disc_all[[length(disc_all) + 1L]] <- disc_dt
    }
  }

  if (length(disc_all) == 0) {
    cat("[dart_insider] No insider disclosures listed.\n")
    return(NULL)
  }
  disc_all <- unique(rbindlist(disc_all, fill = TRUE), by = "rcept_no")

  # ── Detail pass: unique corp_code당 elestock 1회 ──────────────────────────
  ccs <- unique(disc_all$corp_code)
  if (length(ccs) > max_corp_fetch) {
    cat(sprintf("[dart_insider][WARN] unique corp_code %d > max_corp_fetch %d — 최신 접수 우선 절단 (나머지는 다음 run에서 수집)\n",
                length(ccs), max_corp_fetch))
    ord <- disc_all[order(-rcept_dt)][!duplicated(corp_code)]
    ccs <- head(ord$corp_code, max_corp_fetch)
  }
  cat(sprintf("[dart_insider] Fetching elestock details: %d filings / %d companies...\n",
              nrow(disc_all), length(ccs)))

  sc <- new.env()
  all_results <- vector("list", length(ccs))
  for (j in seq_along(ccs)) {
    detail <- tryCatch(.fetch_elestock(api_key, ccs[j], status_counter = sc),
                       error = function(e) NULL)
    Sys.sleep(delay)
    if (!is.null(detail) && nrow(detail) > 0) all_results[[j]] <- detail
    if (j %% 100 == 0) cat(sprintf("  [%d/%d] companies...\n", j, length(ccs)))
  }
  fails <- mget(ls(sc), envir = sc)
  if (length(fails) > 0)
    cat(sprintf("[dart_insider] detail 실패 집계: %s\n",
                paste(sprintf("%s=%d", names(fails), unlist(fails)), collapse = " ")))

  all_results <- Filter(Negate(is.null), all_results)
  if (length(all_results) == 0) {
    cat("[dart_insider] No data collected.\n")
    return(NULL)
  }

  result <- rbindlist(all_results, fill = TRUE)

  # 수집 창 scoping: list에 잡힌 filing만 유지 (corp_code 응답은 ~2년 창 전체 반환)
  result <- result[rcept_no %in% disc_all$rcept_no]
  if (nrow(result) == 0) {
    cat("[dart_insider] No in-window details after rcept_no scoping.\n")
    return(NULL)
  }

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

  # Parse date — elestock corp_code 응답은 "2026-07-16"(dash), list.json은 "20260716" 양식 혼재
  result[, Date := fifelse(grepl("^[0-9]{8}$", rcept_dt),
                           as.Date(rcept_dt, format = "%Y%m%d"),
                           as.Date(rcept_dt))]

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
