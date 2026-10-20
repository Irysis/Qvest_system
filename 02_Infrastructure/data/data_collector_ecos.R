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

# ── ECOS Bond Rates Collector (Plan v0.4.1 H4 자원, 2026-05-19 신규) ───
if (!exists("ECOS_BOND_CACHE")) ECOS_BOND_CACHE <- file.path(CACHE_DIR, "ecos_bond_rates.parquet")

# ECOS 시장금리 (817Y002 일별) + CPI (901Y010 월별) 통계표·항목 매핑
# 기존 ecos_bond_rates.parquet 7 series inherit
ECOS_BOND_SERIES <- list(
  list(name = "KR_Gov3Y",   stat = "817Y002", item = "010190000", freq = "D"),
  list(name = "KR_Gov10Y",  stat = "817Y002", item = "010210000", freq = "D"),
  # 2026-05-19 Q-Lead 자체 부정확 fix: CorpAA = 010300000 (3년 AA-), CorpBBB = 010320000 (3년 BBB-)
  # 이전 매핑 (010320000 / 010330000) 잘못. 기존 cache KR_CorpAA 3.906 정합 검증.
  list(name = "KR_CorpAA",  stat = "817Y002", item = "010300000", freq = "D"),
  list(name = "KR_CorpBBB", stat = "817Y002", item = "010320000", freq = "D"),
  list(name = "KR_CD91",    stat = "817Y002", item = "010150000", freq = "D"),
  list(name = "KR_Call1D",  stat = "817Y002", item = "010101000", freq = "D"),
  list(name = "KR_CPI",     stat = "901Y009", item = "0",         freq = "M")
)

#' Fetch single ECOS series
.ecos_fetch_series <- function(stat_code, item_code, freq, start, end) {
  url <- sprintf(
    "https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/1/100000/%s/%s/%s/%s/%s",
    ECOS_API_KEY, stat_code, freq, start, end, item_code
  )
  resp <- tryCatch(GET(url, timeout(60)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) return(NULL)
  json <- fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  if (is.null(json$StatisticSearch$row)) {
    if (!is.null(json$RESULT)) {
      cat(sprintf("  [ecos_bond] API msg: %s - %s\n", json$RESULT$CODE, json$RESULT$MESSAGE))
    }
    return(NULL)
  }
  rbindlist(json$StatisticSearch$row, fill = TRUE)
}

#' Fetch all ECOS bond rates + CPI series
#'
#' 통계표: 817Y002 (시장금리, 일별) + 901Y009 (소비자물가지수, 월별)
#' 7 series inherit 기존 ecos_bond_rates.parquet schema (Date, Value, Series)
#'
#' @param start_date YYYYMMDD (daily) — monthly series는 YYYYMM 변환
#' @param end_date YYYYMMDD (default: today)
#' @export
ecos_fetch_bond_rates <- function(start_date = "20010101", end_date = NULL) {
  if (is.null(end_date)) end_date <- format(Sys.Date(), "%Y%m%d")

  all_data <- list()
  for (s in ECOS_BOND_SERIES) {
    if (s$freq == "M") {
      st <- substr(start_date, 1, 6); en <- substr(end_date, 1, 6)
    } else {
      st <- start_date; en <- end_date
    }
    cat(sprintf("[ecos_bond] %-12s (%s/%s, freq=%s): ", s$name, s$stat, s$item, s$freq))
    rows <- .ecos_fetch_series(s$stat, s$item, s$freq, st, en)
    if (is.null(rows) || nrow(rows) == 0) {
      cat("FAIL\n"); next
    }
    parse_date <- if (s$freq == "M") {
      as.Date(paste0(rows$TIME, "01"), format = "%Y%m%d")
    } else {
      as.Date(rows$TIME, format = "%Y%m%d")
    }
    df <- data.table(
      Date = parse_date,
      Value = as.numeric(rows$DATA_VALUE),
      Series = s$name
    )[!is.na(Date) & !is.na(Value)]
    cat(sprintf("OK %d rows (latest %s = %.3f)\n",
                nrow(df), as.character(max(df$Date)), tail(df$Value, 1)))
    all_data[[s$name]] <- df
  }
  if (length(all_data) == 0) {
    cat("[ecos_bond] No series fetched. Abort.\n")
    return(NULL)
  }
  result <- rbindlist(all_data)
  setorder(result, Series, Date)
  dir.create(dirname(ECOS_BOND_CACHE), recursive = TRUE, showWarnings = FALSE)
  # [fix 2026-06-17] Windows arrow mmap(error 1224) 회피 — 동일 경로 mmap holder가 있어도
  # write 가능하도록 temp-rename (KRX/consensus 동일 패턴, OneDrive+arrow 플레이키 대응)
  .bond_tmp <- paste0(ECOS_BOND_CACHE, ".tmp")
  write_parquet(result, .bond_tmp)
  if (file.exists(ECOS_BOND_CACHE)) file.remove(ECOS_BOND_CACHE)
  file.rename(.bond_tmp, ECOS_BOND_CACHE)
  cat(sprintf("[ecos_bond] Cache saved: %s (%d rows, %d series)\n",
              ECOS_BOND_CACHE, nrow(result), length(unique(result$Series))))
  result
}

#' Load bond rates from cache
#' @export
ecos_load_bond_rates <- function() {
  if (!file.exists(ECOS_BOND_CACHE)) {
    cat("[ecos_bond] Cache not found, fetching...\n")
    return(ecos_fetch_bond_rates())
  }
  as.data.table(read_parquet(ECOS_BOND_CACHE))
}

#==============================================================================
# 주요국 통화의 대미달러 환율(731Y002 · 일간) 6종 + DXY 프록시 (2026-10-20 · 도훈 'DXY는 ECOS 프록시로 만들자')
#
# 왜: THGNN(2601.04602) 거시 입력 DXY. ICE DXY 는 무료 일간 원천이 없고, 연준 달러지수(H.10)는 주간 공표 · 사후 수정이다
#     (퀀티 '달러인덱스(FRB)' = FRED DTWEXAFEGS 와 761/761일 일치 · 2006~) → 일간 PIT 변수가 못 된다.
# 공식: ICE FX Indexes Methodology(2018-04) §5.1 p.11 — Index = 상수 × Π(외화/USD)^w ·
#       DXY 상수 50.14348112 · w = EUR .576 · JPY .136 · GBP .119 · CAD .091 · SEK .042 · CHF .036
#       https://www.nyse.com/publicdocs/nyse/indices/ICE_FX_Indexes_Methodology.pdf
# 시각: 731Y002 의 d 값 = 서울 d 오전 스냅숏(10-20 실측 · 2015~2024: FRED 뉴욕 정오 d−1 과 수익 상관 0.79 · 수준 차 중앙 0.09% ·
#       d 와는 0.18 · 0.26%) → 가용일 규칙 kr_trading_days_after 0(06_Registry/fred_availability_rules.json ECOS_DXY_PROXY).
# 유로 출범(1999-01-04) 전 바스켓은 마르크 · 프랑 등이라 이 공식이 아니다 → 프록시는 1999-01-04 부터만 만든다.
# 호가 방향은 ECOS 단위로 확인한다('통화당 달러' = USD/외화 · '달러당 통화' = 외화/USD) — 선언과 다르면 멈춘다(fail-closed).
#==============================================================================
if (!exists("ECOS_FX_CACHE")) ECOS_FX_CACHE <- file.path(CACHE_DIR, "ecos_fx_majors.parquet")
ECOS_FX_SERIES <- list(
  list(name = "ECOS_USD_PER_EUR", item = "0000003", quote = "usd_per_ccy", w = 0.576),
  list(name = "ECOS_JPY_PER_USD", item = "0000002", quote = "ccy_per_usd", w = 0.136),
  list(name = "ECOS_USD_PER_GBP", item = "0000012", quote = "usd_per_ccy", w = 0.119),
  list(name = "ECOS_CAD_PER_USD", item = "0000013", quote = "ccy_per_usd", w = 0.091),
  list(name = "ECOS_SEK_PER_USD", item = "0000016", quote = "ccy_per_usd", w = 0.042),
  list(name = "ECOS_CHF_PER_USD", item = "0000014", quote = "ccy_per_usd", w = 0.036)
)
ECOS_DXY_CONST <- 50.14348112
ECOS_DXY_START <- as.Date("1999-01-04")

#' 6통화 원시값으로 DXY 프록시(ICE §5.1)를 만든다 — 6통화가 모두 있는 날 · 1999-01-04 부터만
ecos_dxy_proxy <- function(fx) {
  w <- dcast(fx[Series %in% vapply(ECOS_FX_SERIES, `[[`, "", "name")], Date ~ Series, value.var = "Value")
  w <- w[Date >= ECOS_DXY_START]
  w <- w[stats::complete.cases(w)]
  lg <- rep(log(ECOS_DXY_CONST), nrow(w))
  for (s in ECOS_FX_SERIES) {
    x <- w[[s$name]]
    lg <- lg + s$w * log(if (s$quote == "ccy_per_usd") x else 1 / x)
  }
  data.table(Date = w$Date, Value = exp(lg), Series = "ECOS_DXY_PROXY")
}

#' Fetch 731Y002 6 currencies + DXY proxy → .cache/ecos_fx_majors.parquet (Date, Value, Series)
#' @export
ecos_fetch_fx_majors <- function(start_date = "19990101", end_date = NULL) {
  if (is.null(end_date)) end_date <- format(Sys.Date(), "%Y%m%d")
  parts <- list()
  for (s in ECOS_FX_SERIES) {
    rows <- .ecos_fetch_series("731Y002", s$item, "D", start_date, end_date)
    if (is.null(rows) || nrow(rows) == 0) stop(sprintf("[ecos_fx] %s (731Y002/%s) 수급 실패", s$name, s$item))
    unit <- unique(rows$UNIT_NAME)
    q <- if (all(grepl("통화당 달러", unit))) "usd_per_ccy" else if (all(grepl("달러당 통화", unit))) "ccy_per_usd" else NA_character_
    if (!identical(q, s$quote)) stop(sprintf("[ecos_fx] %s 호가 방향 불일치 — 단위 '%s' · 선언 %s", s$name, paste(unit, collapse = ","), s$quote))
    parts[[s$name]] <- data.table(Date = as.Date(rows$TIME, format = "%Y%m%d"), Value = as.numeric(rows$DATA_VALUE),
                                  Series = s$name)[!is.na(Date) & !is.na(Value)]
    cat(sprintf("[ecos_fx] %-17s %s %d행 (%s ~ %s)\n", s$name, rows$ITEM_NAME1[1], nrow(parts[[s$name]]),
                min(parts[[s$name]]$Date), max(parts[[s$name]]$Date)))
  }
  fx <- rbindlist(parts)
  out <- rbindlist(list(fx, ecos_dxy_proxy(fx)))
  setorder(out, Series, Date)
  dir.create(dirname(ECOS_FX_CACHE), recursive = TRUE, showWarnings = FALSE)
  .fx_tmp <- paste0(ECOS_FX_CACHE, ".tmp")   # ecos_fetch_bond_rates 와 같은 temp-rename(OneDrive · arrow mmap 회피)
  write_parquet(out, .fx_tmp)
  if (file.exists(ECOS_FX_CACHE)) file.remove(ECOS_FX_CACHE)
  file.rename(.fx_tmp, ECOS_FX_CACHE)
  px <- out[Series == "ECOS_DXY_PROXY"]
  cat(sprintf("[ecos_fx] Cache saved: %s (%d rows · DXY 프록시 %d일 %s ~ %s · 끝 %.3f)\n", ECOS_FX_CACHE, nrow(out),
              nrow(px), min(px$Date), max(px$Date), tail(px$Value, 1)))
  out
}

#' Load 731Y002 6 currencies + DXY proxy from cache
#' @export
ecos_load_fx_majors <- function() {
  if (!file.exists(ECOS_FX_CACHE)) {
    cat("[ecos_fx] Cache not found, fetching...\n")
    return(ecos_fetch_fx_majors())
  }
  as.data.table(read_parquet(ECOS_FX_CACHE))
}

cat("[ecos] Loaded. Functions: ecos_fetch_krw(), ecos_load_krw(), ecos_fetch_bond_rates(), ecos_load_bond_rates(), ecos_fetch_fx_majors(), ecos_load_fx_majors()\n")
