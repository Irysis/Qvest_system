#==============================================================================
# Naver Finance Data Collector — 개별종목 **수정주가(adjusted)** 일별 OHLCV 수집
#
# 도훈 지시 2026-09-07: "네이버크롤링으로 개별종목은 수정주가 기준으로 쌓고,
#   벤치마크는 종가기준으로 쌓으면 되는데? 다른 원천은 삭제해. 퀀티와이즈만 남겨놓고"
#   ⇒ 확정 구성 = quantiwise(1990-01-05~2026-08-28) + naver 수정주가(2026-08-31~) **2단**.
#      세 번째 원천을 앞으로 만들지 않는다. (벤치는 naver_benchmark_update.py = 종가, 불변)
#
# ─── 경로 교체의 실측 근거 (2026-09-07) ─────────────────────────────────────
# 구판은 **시세 페이지**(sise_market_sum)에서 당일 **종가만** 긁었다. Open/High/Low 없음,
# 원주가(unadjusted). 그 결과 두 가지가 동시에 있었다:
#   ① OHL 전량 결측 — naver 구간 12,563행의 Open non-null = 0.0%
#   ② 날짜 오각인 — 2026-09-01 행 70종 표본 중 **5종만** 진짜 09-01 종가였고
#      61종은 어느 날 종가와도 안 맞았다(거래량 중앙값이 09-02 종일 거래량의 55%).
#      = 09-02 **장중 스냅샷**을 09-01 로 찍었다. 진짜 09-01 세션은 rawdata 에 없다.
#      (예: A005930 09-01 = 252,250/7,128,524 인데 실제 종가 261,000/15,319,615)
#
# ★그리고 '일별시세(item/sise_day.naver)로 바꾸면 수정주가' 라는 전제는 **반증됐다**:
#   삼성전자 50:1 분할(2018-05-04) 직전일 2018-04-27 종가가
#     item/sise_day.naver          → 2,650,000   (원주가)
#     api.finance.naver.com/siseJson.naver → 53,000  (수정주가)
#   ⇒ 수정주가 정본은 **siseJson** 이다. 이 API 계열은 벤치 배관이 이미 쓰고 있으므로
#     새 원천이 아니라 **이미 있는 원천의 종목 축 확장**이다.
#
# 수집 루트 (소관이 겹치지 않는다 — 겹치면 그게 이음매다):
#   [가격] siseJson (수정주가 OHLCV, 종목x날짜범위 1요청)      ← 가격은 여기서만
#   [Size] 시세 페이지 (시가총액, 전종목 1스캔)                 ← 시총은 여기서만
#          시총은 조정기준 불변량이라 두 경로가 같은 양을 다른 기준으로 내지 않는다.
#          근거 전문 = naver_collector_config.json::_size_source_decision
#
# 사용법:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/data/naver_data_collector.R")
#   naver_daily_adjusted("005930", "20260820", "20260904")   # 1종목 수정주가 OHLCV
#   naver_collect_adjusted(codes, start, end)                # 다종목 + 실패 집계
#   naver_backfill_range("2026-08-31", "2026-09-04")         # dry-run 기본
#   naver_run_pipeline()                                     # 일상 T+0 파이프라인
#==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(data.table)
  library(arrow)
  library(rvest)
  library(jsonlite)
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

# 원천 우선순위 정본 리졸버 — 이 배관의 병합 지점이 **설정을 경유**한다(부재 = stop).
if (!exists("rawdata_priority_decide")) source(file.path(DATA_DIR, "rawdata_source_priority.R"))

NAVER_CACHE_DIR <- file.path(PROJECT_ROOT, ".cache", "naver")
if (!dir.exists(NAVER_CACHE_DIR)) dir.create(NAVER_CACHE_DIR, recursive = TRUE)

NAVER_COLLECTOR_CONFIG_PATH <- file.path(DATA_DIR, "naver_collector_config.json")

.naver_cfg_cache <- new.env(parent = emptyenv())

#' 수집기 설정 — 단일 정본 JSON. 부재 = 조용한 기본값이 아니라 stop
#' (seam_guard_config 와 같은 규약 — 문턱을 코드에 되살리지 않는다).
naver_collector_config <- function(path = NAVER_COLLECTOR_CONFIG_PATH, reload = FALSE) {
  if (!reload && !is.null(.naver_cfg_cache[[path]])) return(.naver_cfg_cache[[path]])
  if (!file.exists(path))
    stop("[naver_collector] 설정 부재: ", path, " — 상수를 코드에 되살리지 말 것(하드코딩 금지)")
  cfg <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  req <- c("price_endpoint", "size_endpoint", "request_sleep_sec", "request_jitter_sec",
           "request_timeout_sec", "max_retries", "retry_backoff_base_sec", "workers",
           "max_failure_rate", "no_trade_ohl_policy", "seam_mode", "seam_verify_tol",
           "size_shares_tol")
  miss <- setdiff(req, names(cfg))
  if (length(miss)) stop("[naver_collector] 설정 키 결손: ", paste(miss, collapse = ", "))
  cfg$config_path <- path
  .naver_cfg_cache[[path]] <- cfg
  cfg
}

#──────────────────────────────────────────────────────────────────────────────
# siseJson 파서 — **순수 함수**(네트워크 없음). 검사기가 고정 픽스처로 부른다.
#
# 응답 형태(EUC-KR):
#   [['날짜','시가','고가','저가','종가','거래량','외국인소진율'],
#    ["20180425", 49220, 50500, 49220, 50400, 332292, 52.07],
#    ...]
# ★바이트로 매칭한다 — 헤더는 EUC-KR 이라 UTF-8 로 디코드하면 깨지지만 데이터 행은
#   순수 ASCII 다. iconv 를 태우면 깨진 헤더가 파싱을 죽일 수 있는데 그건 인코딩
#   문제이지 데이터 문제가 아니다(계기가 잴 것을 안 재고 재기 쉬운 것을 잰다).
#──────────────────────────────────────────────────────────────────────────────
.naver_empty_price_dt <- function() {
  data.table(Date = as.Date(character(0)), Open = numeric(0), High = numeric(0),
             Low = numeric(0), Close = numeric(0), Vol = numeric(0),
             ForeignRatio = numeric(0))
}

.naver_parse_sisejson <- function(txt) {
  if (is.null(txt) || length(txt) != 1L || is.na(txt) || !nzchar(txt))
    return(.naver_empty_price_dt())
  m <- gregexpr("\\[\"[0-9]{8}\",[^\\]]*\\]", txt, perl = TRUE, useBytes = TRUE)
  rows <- regmatches(txt, m)[[1]]
  if (!length(rows)) return(.naver_empty_price_dt())

  core <- substr(rows, 2L, nchar(rows) - 1L)            # 바깥 대괄호 제거
  core <- gsub("\"", "", core, fixed = TRUE)
  parts <- strsplit(core, ",", fixed = TRUE)
  keep <- lengths(parts) >= 6L
  parts <- parts[keep]
  if (!length(parts)) return(.naver_empty_price_dt())

  fld <- function(i) suppressWarnings(as.numeric(trimws(vapply(parts, function(p) p[i], ""))))
  d <- as.Date(trimws(vapply(parts, function(p) p[1], "")), format = "%Y%m%d")
  out <- data.table(Date = d, Open = fld(2), High = fld(3), Low = fld(4),
                    Close = fld(5), Vol = fld(6),
                    ForeignRatio = if (all(lengths(parts) >= 7L)) fld(7) else NA_real_)
  out <- out[!is.na(Date)]
  setorder(out, Date)
  unique(out, by = "Date")
}

#' 무거래/거래정지 행 규약 — Open=High=Low=0 & Vol=0 은 '가격 0' 이 아니라 센티널.
#' quantiwise 는 같은 상태를 O=H=L=C 로 적재하므로 그 규약에 맞춘다(정책은 설정에서).
.naver_apply_no_trade_policy <- function(dt, cfg = naver_collector_config()) {
  if (!nrow(dt)) { dt[, `:=`(no_trade = logical(0), ohl_absent = logical(0))]; return(dt) }
  # ★두 사실을 갈라 둔다 — 응답의 무거래 표기가 **한 가지가 아니다**(2026-09-07 실측):
  #     A032860 2026-08-27 = (3450, 3450, 3450, 3450, Vol 0)  ← OHL 을 종가로 채워 보낸다
  #     A005930 2018-04-30 = (0, 0, 0, 53000, Vol 0)          ← OHL 을 0 으로 보낸다
  #   'Vol 0 = 무거래' 와 'OHL 0 = 값 부재' 는 다른 명제다. 하나로 접으면 둘 중 하나를
  #   놓친다 — 구판 판정은 후자만 봐서 전자를 '정상 거래일' 로 읽었다.
  dt[, no_trade   := !is.finite(Vol) | Vol <= 0]
  dt[, ohl_absent := (!is.finite(Open) | Open <= 0) & (!is.finite(High) | High <= 0) &
       (!is.finite(Low) | Low <= 0)]
  idx <- which(dt$ohl_absent & is.finite(dt$Close) & dt$Close > 0)
  if (identical(cfg$no_trade_ohl_policy, "fill_from_close")) {
    if (length(idx)) {
      set(dt, i = idx, j = "Open", value = dt$Close[idx])
      set(dt, i = idx, j = "High", value = dt$Close[idx])
      set(dt, i = idx, j = "Low",  value = dt$Close[idx])
    }
  } else if (identical(cfg$no_trade_ohl_policy, "as_na")) {
    if (length(idx)) for (cc in c("Open", "High", "Low")) set(dt, i = idx, j = cc, value = NA_real_)
  } else {
    stop("[naver_collector] 미지원 no_trade_ohl_policy: ", cfg$no_trade_ohl_policy)
  }
  # 남은 0 (Close 까지 0/결측) 은 채우지 않는다 — 미측정을 값으로 위장하지 않는다.
  for (cc in c("Open", "High", "Low", "Close")) {
    z <- which(is.finite(dt[[cc]]) & dt[[cc]] <= 0)
    if (length(z)) set(dt, i = z, j = cc, value = NA_real_)
  }
  dt
}

#──────────────────────────────────────────────────────────────────────────────
# 단일 종목 수정주가 OHLCV — 재시도 + 백오프 + 사유 있는 실패
#
# ★반환은 항상 list(data=, ok=, reason=, http_status=, attempts=) — NULL 로 뭉개면
#   호출자가 '없음' 과 '못 받음' 을 구분할 수 없다(부재 != 정상).
#──────────────────────────────────────────────────────────────────────────────
.naver_fetch_sisejson <- function(code, start_yyyymmdd, end_yyyymmdd, cfg) {
  url <- sprintf("%s?symbol=%s&requestType=1&startTime=%s&endTime=%s&timeframe=day",
                 cfg$price_endpoint, code, start_yyyymmdd, end_yyyymmdd)
  ref <- sprintf("https://finance.naver.com/item/main.naver?code=%s", code)
  tries <- as.integer(cfg$max_retries) + 1L
  last_status <- NA_integer_; last_reason <- "unknown"

  for (k in seq_len(tries)) {
    resp <- tryCatch(
      httr::GET(url, httr::add_headers(`User-Agent` = "Mozilla/5.0", Referer = ref),
                httr::timeout(as.numeric(cfg$request_timeout_sec))),
      error = function(e) structure(list(msg = conditionMessage(e)), class = "naver_neterr")
    )
    if (inherits(resp, "naver_neterr")) {
      last_status <- NA_integer_; last_reason <- "network_error"
    } else {
      last_status <- httr::status_code(resp)
      if (last_status == 200L) {
        txt <- rawToChar(httr::content(resp, "raw"))
        dt <- .naver_parse_sisejson(txt)
        if (nrow(dt) > 0L)
          return(list(data = dt, ok = TRUE, reason = NA_character_,
                      http_status = last_status, attempts = k))
        # 200 인데 행 0 = 상장폐지/미상장/기간 밖. 재시도해도 안 바뀐다.
        return(list(data = .naver_empty_price_dt(), ok = FALSE, reason = "empty_range",
                    http_status = last_status, attempts = k))
      }
      if (last_status >= 400L && last_status < 500L && last_status != 429L)
        return(list(data = .naver_empty_price_dt(), ok = FALSE,
                    reason = sprintf("http_%d", last_status),
                    http_status = last_status, attempts = k))
      last_reason <- sprintf("http_%d", last_status)
    }
    if (k < tries) {
      wait <- as.numeric(cfg$retry_backoff_base_sec) * (2^(k - 1L)) +
        stats::runif(1, 0, as.numeric(cfg$request_jitter_sec))
      Sys.sleep(wait)
    }
  }
  list(data = .naver_empty_price_dt(), ok = FALSE, reason = paste0("exhausted_retries:", last_reason),
       http_status = last_status, attempts = tries)
}

#' 1종목 수정주가 OHLCV (편의 함수)
naver_daily_adjusted <- function(code, start, end, cfg = naver_collector_config()) {
  code <- .naver_bare_code(code)
  r <- .naver_fetch_sisejson(code, .naver_ymd(start), .naver_ymd(end), cfg)
  if (!isTRUE(r$ok)) {
    cat(sprintf("[naver_adj] %s: FAIL (%s)\n", code, r$reason))
    return(NULL)
  }
  dt <- .naver_apply_no_trade_policy(copy(r$data), cfg)
  dt[, Ticker := paste0("A", code)]
  setcolorder(dt, c("Date", "Ticker"))
  dt[]
}

.naver_bare_code <- function(x) sub("^A", "", as.character(x))
.naver_ymd <- function(x) {
  if (inherits(x, "Date")) return(format(x, "%Y%m%d"))
  x <- as.character(x)
  if (grepl("-", x, fixed = TRUE)) format(as.Date(x), "%Y%m%d") else x
}

#──────────────────────────────────────────────────────────────────────────────
# 다종목 수정주가 수집 — 동시성 + 페이싱 + **실패 사유별 집계**
#
# ★실패 종목을 조용히 빠뜨리지 않는다. 반환 failures 는 (Ticker, reason, http_status,
#   attempts) 로 남고, 실패율이 설정 상한을 넘으면 호출자가 병합을 차단한다.
#──────────────────────────────────────────────────────────────────────────────
.naver_collect_chunk <- function(codes, start_ymd, end_ymd, cfg) {
  # ★워커에서도 도는 자기완결 루틴 — 파일 전역에 기대지 않는다(PSOCK 은 빈 세션이다).
  suppressPackageStartupMessages({ library(httr); library(data.table) })
  out <- vector("list", length(codes))
  fail <- vector("list", length(codes))
  for (i in seq_along(codes)) {
    r <- .naver_fetch_sisejson(codes[i], start_ymd, end_ymd, cfg)
    if (isTRUE(r$ok)) {
      d <- .naver_apply_no_trade_policy(copy(r$data), cfg)
      d[, Ticker := paste0("A", codes[i])]
      out[[i]] <- d
    } else {
      fail[[i]] <- data.table(Ticker = paste0("A", codes[i]), reason = r$reason,
                              http_status = r$http_status, attempts = r$attempts)
    }
    Sys.sleep(as.numeric(cfg$request_sleep_sec) +
                stats::runif(1, 0, as.numeric(cfg$request_jitter_sec)))
  }
  list(data = rbindlist(out, fill = TRUE), failures = rbindlist(fail, fill = TRUE))
}

naver_collect_adjusted <- function(codes, start, end, cfg = naver_collector_config(),
                                   workers = NULL, verbose = TRUE) {
  codes <- unique(.naver_bare_code(codes))
  codes <- codes[nzchar(codes) & !is.na(codes)]
  start_ymd <- .naver_ymd(start); end_ymd <- .naver_ymd(end)
  nw <- as.integer(workers %||% cfg$workers)
  if (!is.finite(nw) || nw < 1L) nw <- 1L
  t0 <- Sys.time()
  if (verbose)
    cat(sprintf("[naver_adj] %d종목 x %s~%s | workers=%d | endpoint=%s\n",
                length(codes), start_ymd, end_ymd, nw, cfg$price_endpoint))

  res <- NULL
  if (nw > 1L && length(codes) > nw) {
    cl <- tryCatch(parallel::makePSOCKcluster(nw), error = function(e) NULL)
    if (is.null(cl)) {
      cat("[naver_adj][WARN] 클러스터 기동 실패 — 순차로 폴백\n")
    } else {
      ok <- tryCatch({
        parallel::clusterExport(cl, c(".naver_fetch_sisejson", ".naver_parse_sisejson",
                                      ".naver_empty_price_dt", ".naver_apply_no_trade_policy",
                                      ".naver_collect_chunk"),
                                envir = environment(.naver_collect_chunk))
        chunks <- split(codes, (seq_along(codes) - 1L) %% nw)
        parts <- parallel::parLapply(cl, chunks, function(ch)
          .naver_collect_chunk(ch, start_ymd, end_ymd, cfg))
        res <- list(data = rbindlist(lapply(parts, `[[`, "data"), fill = TRUE),
                    failures = rbindlist(lapply(parts, `[[`, "failures"), fill = TRUE))
        TRUE
      }, error = function(e) { cat(sprintf("[naver_adj][WARN] 병렬 실패(%s) — 순차로 폴백\n",
                                           conditionMessage(e))); FALSE })
      try(parallel::stopCluster(cl), silent = TRUE)
      if (!isTRUE(ok)) res <- NULL
    }
  }
  if (is.null(res)) res <- .naver_collect_chunk(codes, start_ymd, end_ymd, cfg)

  dat <- res$data; fails <- res$failures
  if (nrow(dat)) setcolorder(dat, c("Date", "Ticker"))
  n_ok <- if (nrow(dat)) uniqueN(dat$Ticker) else 0L
  n_req <- length(codes)
  # ★요청했는데 데이터도 실패기록도 없는 종목이 있으면 그것이 조용한 누락이다.
  seen <- unique(c(if (nrow(dat)) dat$Ticker else character(0),
                   if (nrow(fails)) fails$Ticker else character(0)))
  lost <- setdiff(paste0("A", codes), seen)
  if (length(lost))
    fails <- rbindlist(list(fails, data.table(Ticker = lost, reason = "unaccounted",
                                              http_status = NA_integer_, attempts = NA_integer_)),
                       fill = TRUE)
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  rate <- if (n_req > 0L) nrow(fails) / n_req else 0
  if (verbose) {
    cat(sprintf("[naver_adj] 완료: %d/%d종 · %d행 · %.1f초 · 실패 %d (%.2f%%)\n",
                n_ok, n_req, nrow(dat), elapsed, nrow(fails), 100 * rate))
    if (nrow(fails)) {
      fc <- fails[, .N, by = reason][order(-N)]
      for (i in seq_len(nrow(fc))) cat(sprintf("    %-28s %5d\n", fc$reason[i], fc$N[i]))
    }
  }
  list(data = dat, failures = fails, n_requested = n_req, n_ok = n_ok,
       failure_rate = rate, elapsed_sec = elapsed,
       over_cap = rate > as.numeric(cfg$max_failure_rate),
       start = start_ymd, end = end_ymd, endpoint = cfg$price_endpoint)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#──────────────────────────────────────────────────────────────────────────────
# 시세 페이지 — **Size(시가총액) 전용**. 가격으로 쓰지 않는다.
#
# ★2026-09-07: 이 페이지의 Close 는 **원주가 + 장중 현재가**다. 구판이 이걸 종가로
#   적재해 09-01 오각인 사고가 났다. 여기서 나오는 값에는 price_basis 스탬프를 박고
#   병합기가 Close 로 쓰지 못하게 막는다(소관 분리 = 이음매 예방).
#──────────────────────────────────────────────────────────────────────────────
.naver_sise_page <- function(sosok, page, cfg = naver_collector_config()) {
  url <- sprintf("%s?sosok=%d&page=%d", cfg$size_endpoint, sosok, page)
  resp <- tryCatch(GET(url, add_headers(`User-Agent` = "Mozilla/5.0")), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) return(NULL)

  txt <- iconv(rawToChar(content(resp, "raw")), from = "EUC-KR", to = "UTF-8")
  html <- read_html(txt)

  tbl <- tryCatch(html %>% html_node("table.type_2") %>% html_table(fill = TRUE),
                  error = function(e) NULL)
  if (is.null(tbl)) return(NULL)

  codes <- tryCatch({
    links <- html %>% html_nodes("a.tltle") %>% html_attr("href")
    vapply(regmatches(links, regexpr("[0-9]{6}", links, perl = TRUE)), function(x) x, "")
  }, error = function(e) character(0))

  tbl <- as.data.table(tbl)
  tbl <- tbl[!is.na(tbl[[2]]) & tbl[[2]] != ""]
  if (nrow(tbl) == 0 || length(codes) == 0) return(NULL)
  n <- min(nrow(tbl), length(codes))
  tbl <- tbl[1:n]

  .num <- function(x) as.numeric(gsub("[^0-9.-]", "", x))

  data.table(
    Ticker = paste0("A", codes[1:n]),
    Name   = as.character(tbl[[2]]),
    # ★Close/Vol 은 **진단용**이다 — 이름부터 가격이 아니게 둔다(오사용 차단).
    #   snap_close 는 원주가이자 장중값일 수 있다. 종가 정본 = siseJson.
    snap_close = .num(tbl[[3]]),
    snap_vol   = .num(tbl[[10]]),
    # 시가총액: Naver 시세 페이지는 **억원** 단위 → 원 = x 1e8.
    #   ★2026-08-09 수리: 구판이 `* 1e6` 이었고 주석이 "억원 → 원 (Naver는 백만원 단위)" 로
    #     **두 단위를 한 줄에 적어 자기모순** 이었다(억원→원이면 1e8, 백만원이면 1e6). 1e6 을
    #     적용해 **정확히 100배 축소**된 값이 2026-07~08 에 43,013 행 기록됐다.
    #   ★배율은 주석이 아니라 **실측으로 확정**: 판별축 shares = Size/Close 의 두 writer 간
    #     비율 중앙값 100.0001 (94.3% 가 99.9~100.1) ⇒ 1e6 x 100 = 1e8.
    #   ⚠단위를 바꿀 일이 생기면 주석을 고치지 말고 위 실측을 다시 돌릴 것.
    Size   = .num(tbl[[7]]) * 1e8,
    Market = fifelse(sosok == 0, "KOSPI", "KOSDAQ")
  )
}

.naver_last_page <- function(sosok, cfg = naver_collector_config()) {
  url <- sprintf("%s?sosok=%d&page=1", cfg$size_endpoint, sosok)
  resp <- tryCatch(GET(url, add_headers(`User-Agent` = "Mozilla/5.0")), error = function(e) NULL)
  if (is.null(resp)) return(1L)
  txt <- iconv(rawToChar(content(resp, "raw")), from = "EUC-KR", to = "UTF-8")
  html <- read_html(txt)
  paging <- html %>% html_nodes("td.pgRR a") %>% html_attr("href")
  if (length(paging) > 0) {
    m <- regmatches(paging[1], regexpr("page=[0-9]+", paging[1], perl = TRUE))
    if (length(m)) as.integer(sub("page=", "", m, fixed = TRUE)) else 1L
  } else 1L
}

#' 전종목 **시가총액 스냅샷** (구 naver_collect_all — 역할 축소).
#' 반환 열: Ticker/Name/snap_close/snap_vol/Size/Market/Date/price_basis
naver_collect_size_snapshot <- function(cfg = naver_collector_config()) {
  cat("[naver_size] 전종목 시가총액 스냅샷 수집...\n")
  t0 <- Sys.time()
  results <- list()
  for (sosok in c(0, 1)) {
    mkt <- if (sosok == 0) "KOSPI" else "KOSDAQ"
    last_page <- .naver_last_page(sosok, cfg)
    cat(sprintf("[naver_size] %s: %d페이지\n", mkt, last_page))
    for (pg in 1:last_page) {
      dt <- tryCatch(.naver_sise_page(sosok, pg, cfg), error = function(e) NULL)
      if (!is.null(dt) && nrow(dt) > 0) results[[length(results) + 1]] <- dt
      Sys.sleep(0.3)
    }
  }
  if (length(results) == 0) { cat("[naver_size] 수집 실패\n"); return(NULL) }

  all_dt <- rbindlist(results, fill = TRUE)
  all_dt <- all_dt[!is.na(Size) & Size > 0]
  if (exists("last_confirmed_trading_day")) {
    all_dt[, Date := last_confirmed_trading_day()]
  } else {
    d <- Sys.Date()
    if (as.integer(format(Sys.time(), "%H")) < 16L) d <- d - 1L
    while (as.POSIXlt(d)$wday %in% c(0L, 6L)) d <- d - 1L
    cat("[naver_size][WARN] trading_calendar 미로드 - 직전 평일 fallback (공휴일 미대조)\n")
    all_dt[, Date := d]
  }
  # ★스탬프: 이 표의 가격은 원주가이며 장중값일 수 있다. 소비자가 Close 로 쓰면 안 된다.
  all_dt[, price_basis := "unadjusted_intraday_snapshot"]

  cat(sprintf("[naver_size] 완료: %d종목 | %.1f초\n", nrow(all_dt),
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  out_dir <- file.path(NAVER_CACHE_DIR, "snapshot")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  write_parquet(all_dt, file.path(out_dir, sprintf("size_snapshot_%s.parquet",
                                                   format(Sys.Date(), "%Y%m%d"))))
  invisible(all_dt)
}

# 구명 별칭 — 호출자 호환. 구판 semantics(전종목 '종가')는 폐기됐다.
naver_collect_all <- function(...) {
  cat("[naver_collect_all] ⚠ 이 함수는 Size 스냅샷으로 축소됐다 — 반환의 snap_close 는\n")
  cat("   원주가/장중값이라 가격 정본이 아니다. 가격은 naver_collect_adjusted() 를 쓸 것.\n")
  naver_collect_size_snapshot(...)
}

#' 개별종목 최근 OHLCV — ★**원주가(unadjusted)**. 눈으로 보는 용도지 적재용이 아니다.
#' (2026-09-07 실증: 삼성전자 2018-04-27 이 여기서는 2,650,000 = 분할 미반영)
NAVER_SISE_DAY_URL <- "https://finance.naver.com/item/sise_day.naver"
naver_quick_price <- function(code, n = 5) {
  code <- .naver_bare_code(code)
  url <- sprintf("%s?code=%s&page=1", NAVER_SISE_DAY_URL, code)
  resp <- tryCatch(
    GET(url, add_headers(`User-Agent` = "Mozilla/5.0",
                         `Referer` = sprintf("https://finance.naver.com/item/main.naver?code=%s", code))),
    error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) {
    cat(sprintf("[Naver] %s: fetch failed\n", code)); return(NULL)
  }
  txt <- iconv(rawToChar(content(resp, "raw")), from = "EUC-KR", to = "UTF-8")
  tbl <- tryCatch(read_html(txt) %>% html_table(fill = TRUE), error = function(e) list())
  if (length(tbl) < 1) return(NULL)
  raw_tbl <- as.data.frame(tbl[[1]])
  raw_tbl <- raw_tbl[complete.cases(raw_tbl), ]
  if (nrow(raw_tbl) == 0) return(NULL)
  .num <- function(x) as.numeric(gsub("[^0-9.-]", "", x))
  result <- data.table(Date = as.Date(raw_tbl[[1]], "%Y.%m.%d"), Close = .num(raw_tbl[[2]]),
                       Open = .num(raw_tbl[[4]]), High = .num(raw_tbl[[5]]),
                       Low = .num(raw_tbl[[6]]), Vol = .num(raw_tbl[[7]]))
  result <- result[!is.na(Date)]
  result[, price_basis := "unadjusted"]
  head(result[order(-Date)], n)
}

#──────────────────────────────────────────────────────────────────────────────
# KOSPI 지수 종가 (진단용). 벤치 정본은 naver_benchmark_update.py — 불변.
#──────────────────────────────────────────────────────────────────────────────
naver_kospi200_close <- function() {
  url <- "https://finance.naver.com/sise/sise_index.naver?code=KOSPI"
  resp <- tryCatch(GET(url, add_headers(`User-Agent` = "Mozilla/5.0")), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) return(NULL)
  txt <- iconv(rawToChar(content(resp, "raw")), from = "EUC-KR", to = "UTF-8")
  now_val <- tryCatch({
    read_html(txt) %>% html_node("#now_value") %>% html_text() %>%
      gsub("[^0-9.]", "", .) %>% as.numeric()
  }, error = function(e) NA_real_)
  if (is.na(now_val)) return(NULL)
  data.table(Date = Sys.Date(), BM_Close = now_val)
}

#──────────────────────────────────────────────────────────────────────────────
# Size 결정 — 소관 분리의 실제 구현
#
# 규칙(설정 _size_backfill_rule):
#   ① 그 (Date,Ticker) 의 **기존 Size** 는, 그날 스냅샷의 가격이 새로 받은 수정주가와
#      일치할 때만 '같은 날·같은 기준' 임이 실증된다 → 그대로 승계.
#   ② 일치하지 않는 날(= 스냅샷이 다른 날 것이거나 장중값)은 승계하지 않고,
#      일치한 날들에서 shares_adj = Size / AdjClose 를 재도출해 중앙값을 곱해 복원한다.
#   ③ shares 가 창 안에서 불안정하거나(유상증자·감자) 일치한 날이 하나도 없으면
#      **NA + 사유**. 부재를 거짓으로 읽지 않는다.
#──────────────────────────────────────────────────────────────────────────────
.naver_resolve_size <- function(new_dt, old_window, cfg = naver_collector_config()) {
  stopifnot(is.data.table(new_dt), all(c("Date", "Ticker", "Close") %in% names(new_dt)))
  tol <- as.numeric(cfg$size_shares_tol)
  key <- function(d, t) paste0(as.character(d), "|", t)
  om <- if (!is.null(old_window) && nrow(old_window))
    old_window[, .(k = key(Date, Ticker), old_close = Close, old_size = Size)] else
      data.table(k = character(0), old_close = numeric(0), old_size = numeric(0))
  x <- copy(new_dt)
  x[, k := key(Date, Ticker)]
  x <- merge(x, om, by = "k", all.x = TRUE, sort = FALSE)
  x[, size_source := NA_character_]     # ★빈 부분집합이어도 열이 생기도록 선초기화

  # ① 가격 일치 = 같은 날·같은 기준 실증
  x[, price_agrees := is.finite(old_close) & is.finite(Close) & abs(old_close - Close) < 1e-6]
  x[, shares_adj := fifelse(price_agrees & is.finite(old_size) & Close > 0, old_size / Close, NA_real_)]

  # ② 종목별 shares 안정성
  st <- x[is.finite(shares_adj), .(sh_med = median(shares_adj), n_sh = .N,
                                   sh_spread = if (.N > 1L) (max(shares_adj) / min(shares_adj) - 1) else 0),
          by = Ticker]
  x <- merge(x, st, by = "Ticker", all.x = TRUE, sort = FALSE)
  # ★shares_stable 은 **벡터**다 — isTRUE() 로 접으면 스칼라 FALSE 가 되어 전 행에
  #   같은 사유가 찍힌다(라벨이 사실을 덮는 자리).
  x[, shares_stable := !is.na(sh_spread) & is.finite(sh_spread) & sh_spread <= tol]

  x[, Size := NA_real_]
  x[price_agrees & is.finite(old_size), `:=`(Size = old_size, size_source = "snapshot_same_day")]
  x[is.na(Size) & shares_stable & is.finite(sh_med) & is.finite(Close),
    `:=`(Size = sh_med * Close, size_source = "reconstructed_shares_x_close")]
  x[is.na(Size) & is.na(size_source) & !shares_stable & !is.na(sh_spread),
    size_source := "unavailable_shares_unstable"]
  x[is.na(Size) & is.na(size_source), size_source := "unavailable_no_matching_day"]
  x[, k := NULL]
  x[]
}

#──────────────────────────────────────────────────────────────────────────────
# 이음매 검증 (seam_mode="verify") — 가드를 '수리'가 아니라 '대조' 로 부른다
#
# 새 경로는 첫 naver 일의 직전 종가도 naver 에서 받아 **같은 조정기준 안에서** Ret 을
# 계산한다. 그래서 seam_scale_guard 의 배율 추정은 더 이상 Ret 을 만들 필요가 없고,
# 대신 **측정된 Ret 과 대조**되는 양성 대조가 된다. 어휘·상수는 가드 정본에서 온다.
#──────────────────────────────────────────────────────────────────────────────
.naver_seam_verify <- function(anchor_close, anchor_ticker, first_dt, cfg = naver_collector_config()) {
  src <- tryCatch({ source(file.path(DATA_DIR, "seam_scale_guard.R")); TRUE },
                  error = function(e) { cat(sprintf(
                    "[naver_seam] ⛔ 가드 로드 실패 (%s) — 검증 미측정\n", conditionMessage(e))); FALSE })
  if (!isTRUE(src)) return(NULL)
  a <- data.table(Ticker = anchor_ticker, anchor_close = anchor_close)
  d <- merge(first_dt[, .(Ticker, seam_close = Close, measured_ret = Ret)], a,
             by = "Ticker", all.x = TRUE)
  cls <- seam_classify_pair(d$anchor_close, d$seam_close, gap = 1L)
  d[, `:=`(canonical_scale = cls$canonical_scale, implied_ret = cls$implied_ret,
           verdict = cls$verdict, action = seam_action_for(cls$verdict))]
  tol <- as.numeric(cfg$seam_verify_tol)
  d[, agrees := is.finite(implied_ret) & is.finite(measured_ret) &
      abs(implied_ret - measured_ret) <= tol]
  d[]
}

#──────────────────────────────────────────────────────────────────────────────
# RAWDATA 병합 / 백필
#
# ★교체는 **행 삭제 후 append 가 아니라 값 갱신**이다. rawdata 에는 이 writer 가
#   만들지 않는 열(K200·KQ150·Float·Sector_Lv2·AdminStock·TradingHalt·UnfaithfulDisc)이
#   있고 그건 apply_universe_mapping 이 채운다 — 삭제 후 append 하면 그 축이 사라진다.
#   (승계 목록에서 빠진 축은 없는 축이 된다)
#──────────────────────────────────────────────────────────────────────────────
NAVER_VALUE_COLS <- c("Open", "High", "Low", "Close", "Vol", "Size", "Ret")

#' rawdata 값 갱신 — **행 삭제 없음**. 이 writer 가 만들지 않는 축(K200·KQ150·Float·
#' Sector_Lv2·AdminStock·TradingHalt·UnfaithfulDisc·Name·Market·Sector·BM_Ret)은
#' 손대지 않고 그대로 승계한다. 삭제 후 append 하면 그 축이 세대마다 리셋된다
#' (승계 목록에서 빠진 축은 없는 축이 된다 — 그 병을 여기서 구조적으로 막는다).
#' ★★원천 우선순위 (2026-09-07 도훈 지시 — 역전 차단 지점)
#'   구판은 (Date,Ticker) 가 맞으면 **incumbent 의 source 를 보지 않고** 값을 덮고 라벨을
#'   'naver' 로 찍었다. 재수집 범위에 퀀티 구간이 한 번 들어가면 정본이 보충 레인에
#'   **조용히** 진다 — 행 수도 날짜도 맞으니 어느 계기도 안 운다. 이 자리가 그 역전을
#'   막는 곳이다. 판정은 06_Registry/rawdata_source_priority.json 이 낸다(부재 = stop).
#'   지는 행은 값·라벨을 **둘 다** 건드리지 않고 보존하며, 몇 행이 왜 스킵됐는지 남긴다.
#'
#' @return list(dt=, n_updated=, n_appended=, n_skipped=, decisions=, preserved_cols=)
.naver_apply_update <- function(raw, upd, value_cols = NAVER_VALUE_COLS,
                                incoming_source = "naver", cfg_pri = NULL) {
  stopifnot(is.data.table(raw), is.data.table(upd))
  if (!exists("rawdata_priority_decide")) {
    # ★DATA_DIR 은 config.R 산출이라 이 함수를 **격리 환경에 꺼내 돌리는 검사**에는 없다.
    #   라이브러리 위치 때문에 계약 검사가 죽으면 그건 계약의 실패가 아니라 배선의 실패다.
    .ddir <- if (exists("DATA_DIR")) DATA_DIR else {
      .rt <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else
        gsub("\\\\", "/", Sys.getenv("QM_ROOT", unset = ""))
      file.path(.rt, "02_Infrastructure/data")
    }
    source(file.path(.ddir, "rawdata_source_priority.R"))
  }
  if (is.null(cfg_pri)) cfg_pri <- rawdata_priority_config()
  raw <- copy(raw); upd <- copy(upd)
  raw[, Date := as.Date(Date)]; upd[, Date := as.Date(Date)]
  before_cols <- names(raw)
  if (!"source" %in% names(raw))
    stop("[naver_apply_update] rawdata 에 source 열이 없다 — 우선순위를 판정할 축이 없다. ",
         "라벨 없는 패널을 덮으면 무엇이 무엇을 이겼는지 영원히 못 재도출한다.")
  kr <- paste0(as.character(raw$Date), "|", raw$Ticker)
  ku <- paste0(as.character(upd$Date), "|", upd$Ticker)
  pos <- match(kr, ku)
  hit <- which(!is.na(pos))

  dec <- rawdata_priority_decide(raw$source[hit], incoming_source, cfg = cfg_pri,
                                 context = "naver_apply_update", has_incumbent = TRUE)
  allow <- dec$allow %in% TRUE
  skipped <- hit[!allow]
  hit <- hit[allow]

  for (cc in intersect(value_cols, names(upd)))
    set(raw, i = hit, j = cc, value = upd[[cc]][pos[hit]])
  set(raw, i = hit, j = "source", value = incoming_source)
  add <- upd[!ku %in% kr]
  n_add <- nrow(add)
  if (n_add) {
    if (!"source" %in% names(add)) add[, source := incoming_source]
    raw <- rbind(raw, add, fill = TRUE)
  }
  setorder(raw, Date, Ticker)
  list(dt = raw, n_updated = length(hit), n_appended = n_add, n_skipped = length(skipped),
       decisions = dec[, .N, by = .(decision, incumbent_source, incoming_source)],
       preserved_cols = setdiff(before_cols, c(value_cols, "source")))
}

naver_backfill_range <- function(start, end, dry_run = TRUE, cfg = naver_collector_config(),
                                 tickers = NULL, out_dir = NULL, label = "naver_adjusted",
                                 size_ref = NULL) {
  start <- as.Date(start); end <- as.Date(end)
  if (!file.exists(RAWDATA_CACHE)) stop("[naver_backfill] RAWDATA 부재: ", RAWDATA_CACHE)
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  raw[, Date := as.Date(Date)]

  anchor_date <- suppressWarnings(max(raw[Date < start]$Date))
  if (!is.finite(as.numeric(anchor_date)))
    stop("[naver_backfill] 앵커 부재 — start 이전 데이터가 없다")
  win_old <- raw[Date >= anchor_date & Date <= end]
  if (is.null(tickers)) tickers <- sort(unique(win_old[Date >= start]$Ticker))
  cat(sprintf("[naver_backfill] 구간 %s~%s · 앵커 %s · 대상 %d종\n",
              start, end, anchor_date, length(tickers)))

  got <- naver_collect_adjusted(tickers, anchor_date, end, cfg = cfg)
  new <- got$data
  if (!nrow(new)) stop("[naver_backfill] 수집 결과 0행 — 병합 불가")
  setorder(new, Ticker, Date)

  # ── Ret: naver 내부에서 측정 (앵커일 포함 → 첫날 Ret 이 추정이 아니라 측정) ──
  new[, Ret := Close / shift(Close) - 1, by = Ticker]
  n_anchor_seen <- new[Date == anchor_date, .N]
  new_win <- new[Date >= start & Date <= end]
  # 거래일 대조 — 캘린더에 없는 날은 싣지 않는다(phantom 세션 차단)
  if (exists("get_trading_days")) {
    td <- as.Date(get_trading_days(start, end))
    dropped <- setdiff(as.character(unique(new_win$Date)), as.character(td))
    if (length(dropped)) cat(sprintf("[naver_backfill] 캘린더 밖 날짜 제외: %s\n",
                                     paste(dropped, collapse = ", ")))
    new_win <- new_win[Date %in% td]
    missing_td <- setdiff(as.character(td), as.character(unique(new_win$Date)))
    if (length(missing_td)) cat(sprintf("[naver_backfill] ⚠ 미수집 거래일: %s\n",
                                        paste(missing_td, collapse = ", ")))
  }

  # ── Size 결정 ──
  #   참조원 = ①rawdata 에 이미 있는 그 날짜의 행(재수집) + ②당일 시세페이지 스냅샷(전진).
  #   둘 다 (Date,Ticker,Close,Size) 모양으로 맞춰 넘긴다. 채택 조건은 하나 —
  #   **그 참조의 가격이 새로 받은 수정주가와 일치할 때만** 같은 날·같은 기준임이 실증된다.
  size_pool <- win_old[Date >= start, .(Date, Ticker, Close, Size)]
  if (!is.null(size_ref) && nrow(size_ref)) {
    sr <- as.data.table(size_ref)
    cl <- if ("snap_close" %in% names(sr)) "snap_close" else "Close"
    size_pool <- rbindlist(list(size_pool,
                                sr[, .(Date = as.Date(Date), Ticker, Close = get(cl), Size)]),
                           fill = TRUE)
    size_pool <- unique(size_pool, by = c("Date", "Ticker"))
  }
  sized <- .naver_resolve_size(new_win, size_pool, cfg)

  # ── 원천 우선순위 미리보기 ────────────────────────────────────────────────
  #   dry-run 에서도 보여야 한다 — 실쓰기에서만 판정하면 "덮을 것인가" 를 미리 못 본다.
  #   창(update 날짜) 안에서만 잰다: 창 밖 행은 (Date,Ticker) 가 맞을 수 없다.
  .pri_cfg <- rawdata_priority_config()
  if (!"source" %in% names(raw))
    stop("[naver_backfill] rawdata 에 source 열이 없다 — 우선순위를 판정할 축이 없다")
  .rawwin <- raw[Date %in% unique(sized$Date), .(Date, Ticker, source)]
  .ku_prev <- paste0(as.character(sized$Date), "|", sized$Ticker)
  .kw_prev <- paste0(as.character(.rawwin$Date), "|", .rawwin$Ticker)
  .hit_prev <- which(.kw_prev %in% .ku_prev)
  pri_dec <- rawdata_priority_decide(.rawwin$source[.hit_prev], "naver", cfg = .pri_cfg,
                                     context = "naver_backfill", has_incumbent = TRUE)
  rawdata_priority_print(pri_dec, "naver_backfill")

  # ── 이음매 검증 ──
  anch <- win_old[Date == anchor_date, .(Ticker, Close)]
  first_day <- min(sized$Date)
  seam <- .naver_seam_verify(anch$Close, anch$Ticker, sized[Date == first_day], cfg)

  # ── 전후 대조 (dry-run 산출물의 본체) ──
  old_win <- win_old[Date >= start, .(Date, Ticker, old_Open = Open, old_Close = Close,
                                      old_Vol = Vol, old_Size = Size, old_Ret = Ret)]
  cmp <- merge(sized[, .(Date, Ticker, Open, High, Low, Close, Vol, Size, Ret,
                         no_trade, size_source)],
               old_win, by = c("Date", "Ticker"), all = TRUE)
  # ★'바뀌었다' 와 '한쪽에 없다' 를 섞지 않는다 — 부분 티커 실행에서 미수집 행이
  #   전부 '변경' 으로 세어져 보고서가 두 가지를 한 숫자로 말하게 된다.
  #   한쪽 부재는 n_old_only / n_new_only 가 따로 센다.
  cmp[, close_changed := is.finite(Close) & is.finite(old_Close) & abs(Close - old_Close) >= 1e-6]

  by_date <- cmp[, .(n = .N,
                     n_old_only = sum(is.na(Close)), n_new_only = sum(is.na(old_Close)),
                     n_close_changed = sum(close_changed, na.rm = TRUE),
                     # ★세지 말고 재라 — 상수 0 을 적으면 보고서가 관측이 아니라 선언이 된다
                     n_open_nonnull_old = sum(is.finite(old_Open)),
                     n_open_nonnull_new = sum(is.finite(Open)),
                     n_no_trade = sum(no_trade, na.rm = TRUE),
                     ret_mean_old = mean(old_Ret, na.rm = TRUE),
                     ret_mean_new = mean(Ret, na.rm = TRUE),
                     ret_sd_old = sd(old_Ret, na.rm = TRUE),
                     ret_sd_new = sd(Ret, na.rm = TRUE),
                     ret_min_new = suppressWarnings(min(Ret, na.rm = TRUE)),
                     ret_max_new = suppressWarnings(max(Ret, na.rm = TRUE)),
                     n_abs_ret_gt_35_old = sum(abs(old_Ret) > 0.35, na.rm = TRUE),
                     n_abs_ret_gt_35_new = sum(abs(Ret) > 0.35, na.rm = TRUE)),
                 by = Date][order(Date)]

  report <- list(
    schema = "naver_adjusted_backfill_report_v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    dry_run = dry_run, label = label,
    start = as.character(start), end = as.character(end),
    anchor_date = as.character(anchor_date),
    anchor_rows_fetched = n_anchor_seen,
    endpoint = got$endpoint, price_basis = "adjusted",
    n_requested = got$n_requested, n_ok = got$n_ok,
    failure_rate = got$failure_rate, over_cap = got$over_cap,
    failures_by_reason = if (nrow(got$failures)) as.list(setNames(
      got$failures[, .N, by = reason]$N, got$failures[, .N, by = reason]$reason)) else list(),
    failures = if (nrow(got$failures)) head(got$failures, 200) else NULL,
    size_source_counts = as.list(setNames(sized[, .N, by = size_source]$N,
                                          sized[, .N, by = size_source]$size_source)),
    priority_config_path = as.character(.pri_cfg$config_path),
    priority_decisions = pri_dec[, .N, by = .(decision, incumbent_source, incoming_source)],
    priority_n_skipped = sum(!(pri_dec$allow %in% TRUE)),
    no_trade_rows = sum(sized$no_trade, na.rm = TRUE),
    ohl_absent_rows = sum(sized$ohl_absent, na.rm = TRUE),
    by_date = by_date,
    seam_verdict_counts = if (!is.null(seam)) as.list(setNames(
      seam[, .N, by = verdict]$N, seam[, .N, by = verdict]$verdict)) else list(),
    seam_guard_agreement = if (!is.null(seam)) list(
      n_break = seam[verdict == "adjustment_basis_break", .N],
      n_agree = seam[verdict == "adjustment_basis_break" & agrees == TRUE, .N],
      rows = seam[verdict != "on_scale"]) else NULL,
    changed_examples = head(cmp[close_changed == TRUE][order(-abs(Close - old_Close))], 30)
  )

  out_dir <- out_dir %||% file.path(CACHE_DIR, "naver_recollect")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  tag <- if (dry_run) "dryrun" else "apply"
  fp <- file.path(out_dir, sprintf("naver_%s_%s_%s.json", tag, gsub("-", "", as.character(start)),
                                   format(Sys.time(), "%Y%m%d_%H%M%S")))
  js <- jsonlite::toJSON(report, auto_unbox = TRUE, digits = 10, na = "null", pretty = TRUE)
  tmp <- paste0(fp, ".tmp", Sys.getpid()); writeLines(js, tmp, useBytes = TRUE)
  if (file.exists(fp)) file.remove(fp); file.rename(tmp, fp)
  lt <- file.path(out_dir, sprintf("latest_%s_%s.json", tag, label))
  tmp2 <- paste0(lt, ".tmp", Sys.getpid()); writeLines(js, tmp2, useBytes = TRUE)
  if (file.exists(lt)) file.remove(lt); file.rename(tmp2, lt)
  cat(sprintf("[naver_backfill] 보고서: %s\n", fp))

  if (dry_run) {
    cat("[naver_backfill] DRY-RUN — RAWDATA 미수정\n")
    return(invisible(list(report = report, new = sized, cmp = cmp, seam = seam, path = fp)))
  }

  # ── 실쓰기 ──────────────────────────────────────────────────────────────
  if (isTRUE(got$over_cap))
    stop(sprintf("[naver_backfill] ⛔ 실패율 %.3f > 상한 %.3f — 병합 차단(부재를 정상으로 읽지 않는다)",
                 got$failure_rate, as.numeric(cfg$max_failure_rate)))

  upd <- sized[, .(Date, Ticker, Open, High, Low, Close, Vol, Size, Ret)]
  applied <- .naver_apply_update(raw, upd, cfg_pri = .pri_cfg)
  if (applied$n_skipped > 0L) {
    cat(sprintf("[naver_backfill] ★우선순위 보존: %s행 미갱신 — 상위 원천을 덮지 않는다\n",
                format(applied$n_skipped, big.mark = ",")))
    print(applied$decisions)
  }
  cat(sprintf("[naver_backfill] [rawdata_priority] 사이드카: %s\n",
              rawdata_priority_sidecar(list(
                merge_point = "naver_data_collector.R::.naver_apply_update",
                incoming_source = "naver",
                start = as.character(start), end = as.character(end),
                n_updated = applied$n_updated, n_appended = applied$n_appended,
                n_skipped = applied$n_skipped, decisions = applied$decisions),
                label = "naver_backfill", cfg = .pri_cfg)))
  # ★허가 검사는 **기존 행 재작성**에만 건다. 일상 전진(신규 거래일 append)까지 막으면
  #   무인 루프가 켜져 있는 동안 daily_refresh 가 매일 죽는다 — 고치려는 병보다 큰 병이다.
  #   재작성은 다르다: 소비 중인 패널의 과거 행을 바꾸는 것이라 루프가 읽는 도중에
  #   하면 같은 tick 안에서 값이 갈린다.
  if (applied$n_updated > 0L) .naver_assert_write_allowed(applied$n_updated)

  bk <- file.path(CACHE_DIR, sprintf("rawdata_pre_naveradj_%s.parquet", format(Sys.Date(), "%Y%m%d")))
  if (!file.exists(bk)) { file.copy(RAWDATA_CACHE, bk); cat(sprintf("[naver_backfill] 백업: %s\n", bk)) }
  raw <- applied$dt
  if (applied$n_appended) cat(sprintf("[naver_backfill] 신규 행 %d 추가\n", applied$n_appended))
  if (exists("qvest_atomic_write_parquet")) {
    qvest_atomic_write_parquet(raw, RAWDATA_CACHE, tag = "naver_backfill")
  } else {
    .tmp <- paste0(RAWDATA_CACHE, ".tmp"); write_parquet(raw, .tmp)
    if (file.exists(RAWDATA_CACHE)) file.remove(RAWDATA_CACHE); file.rename(.tmp, RAWDATA_CACHE)
  }
  cat(sprintf("[naver_backfill] RAWDATA 갱신: %d행 교체 · total %d\n", applied$n_updated, nrow(raw)))
  invisible(list(report = report, new = sized, cmp = cmp, seam = seam, path = fp))
}

#' RAWDATA **과거 행 재작성** 허가 — 무인 루프(Qvest_ReinforceAutoLoop)가 이 파일을
#' 읽는다. 킬스위치가 켜져 있으면 차단한다. 신규 거래일 append 에는 걸지 않는다
#' (일상 전진까지 막으면 루프가 켜진 내내 daily_refresh 가 죽는다).
#' ★판독 실패는 '허용' 이 아니라 '차단' 으로 떨어진다 — 부재를 정상으로 읽지 않는다.
.naver_assert_write_allowed <- function(n_rewrite = NA_integer_) {
  p <- file.path(PROJECT_ROOT, "06_Registry", "reinforce_auto_config.json")
  if (!file.exists(p)) return(invisible(TRUE))
  en <- tryCatch(isTRUE(jsonlite::fromJSON(p)$enabled), error = function(e) TRUE)
  if (en) stop(sprintf(
    "[naver_backfill] ⛔ reinforce_auto_config.json::enabled=true 인데 기존 행 %s 를 재작성하려 한다 — 무인 루프가 RAWDATA 를 읽는 중이다. 킬스위치를 내린 뒤 다시 부를 것.",
    format(n_rewrite, big.mark = ",")))
  invisible(TRUE)
}

#──────────────────────────────────────────────────────────────────────────────
# 일상 T+0 파이프라인 — 수집(수정주가) → Size 스냅샷 → 병합 → 검증
#──────────────────────────────────────────────────────────────────────────────
naver_run_pipeline <- function(target_date = NULL, dry_run = FALSE, cfg = naver_collector_config()) {
  cat("=== Naver Data Pipeline (adjusted) ===\n")
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  raw[, Date := as.Date(Date)]
  last_date <- max(raw$Date)

  # [Track R fix 2026-06-12] target = last_confirmed_trading_day(). 캘린더 부재 시 fail-loud.
  if (is.null(target_date)) {
    if (!exists("last_confirmed_trading_day"))
      stop("[pipeline] trading_calendar not loaded - refuse to stamp Sys.Date() blindly (Track R fix)")
    target <- last_confirmed_trading_day()
  } else target <- as.Date(target_date, "%Y%m%d")

  if (as.POSIXlt(target)$wday %in% c(0L, 6L)) {
    cat(sprintf("[pipeline] BLOCKED: target %s is a weekend\n", target)); return(invisible(NULL))
  }
  if (exists("is_trading_day") && !is_trading_day(target)) {
    cat(sprintf("[pipeline] BLOCKED: target %s not in trading calendar\n", target)); return(invisible(NULL))
  }
  if (target <= last_date) {
    cat(sprintf("[pipeline] RAWDATA (%s) already >= target (%s)\n", last_date, target))
    return(invisible(NULL))
  }
  cat(sprintf("Last RAWDATA: %s | Target: %s\n", last_date, target))

  # Size 는 시세 페이지 스냅샷에서만 온다(가격은 절대 여기서 안 온다 — 소관 분리).
  snap <- tryCatch(naver_collect_size_snapshot(cfg), error = function(e) {
    cat(sprintf("[pipeline][WARN] Size 스냅샷 실패 (%s) — Size 는 미측정(NA)으로 남는다\n",
                conditionMessage(e))); NULL })
  if (!is.null(snap)) snap <- snap[Date == target]     # 다른 날 스냅샷은 이 날의 증거가 아니다

  # ★날짜는 응답 행이 스스로 들고 온다 — 구판의 '현재 화면을 target 으로 스탬프'
  #   경로가 사라졌다. 09-01 오각인(장중 스냅샷을 전일 종가로 적재)의 구조적 차단.
  res <- naver_backfill_range(last_date + 1L, target, dry_run = dry_run, cfg = cfg,
                              tickers = unique(raw[Date == last_date]$Ticker),
                              label = "daily", size_ref = snap)

  # ★T+0 장중 스냅샷 검거: 스냅샷 가격이 그날 확정 종가와 널리 어긋나면 그 스냅샷은
  #   장중값이다(2026-09-01 사고의 지문 — 70종 표본 중 5종만 일치, 거래량이 종일의 55%).
  #   구판은 이 사실을 잴 자리가 아예 없었다. 이제는 Size 출처 분포가 그 계기다.
  if (!is.null(res) && !is.null(res$report)) {
    sc <- res$report$size_source_counts
    n_same <- as.numeric(sc[["snapshot_same_day"]] %||% 0)
    n_tot <- max(1, sum(unlist(sc)))
    if (n_same / n_tot < 0.5)
      cat(sprintf("[pipeline] ⚠ Size 스냅샷 일치율 %.1f%% — 장중 스냅샷 의심(종가 확정 후 재실행 권고)\n",
                  100 * n_same / n_tot))
  }
  invisible(res)
}

cat("[naver_data_collector] Loaded (adjusted-price path). Cache:", NAVER_CACHE_DIR, "\n")
cat("[naver_data_collector] naver_daily_adjusted() / naver_collect_adjusted() / naver_backfill_range() / naver_run_pipeline()\n")
