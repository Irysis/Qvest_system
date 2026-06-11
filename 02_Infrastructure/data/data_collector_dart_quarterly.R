#==============================================================================
# Quant Module — DART Quarterly Data Collector + TTM Calculator
# Version: 1.0.0
#
# 분기별 재무제표 수집 (사업보고서 외 1Q/반기/3Q 추가)
# DART 누적보고서 → 개별 분기 추출 → TTM (Trailing Twelve Months) 산출
#
# 보고서 코드:
#   "11014" = 1분기 (1Q 누적)
#   "11012" = 반기   (1Q+2Q 누적)
#   "11013" = 3분기  (1Q+2Q+3Q 누적)
#   "11011" = 사업보고서 (연간, 1Q+2Q+3Q+4Q 누적)
#
# TTM 계산:
#   P/L, CF: 최근 4개 분기 합산
#   B/S: 최신 분기말 시점 값
#
# 사용법:
#   source("config.R")
#   source("data_collector_dart.R")  # .dart_fetch_single 필요
#   source("data_collector_dart_quarterly.R")
#   dart_fetch_quarterly(years = 2018:2025)   # 분기 보고서 수집
#   dart_compute_ttm()                         # TTM 계산 + parquet 저장
#
# API 제한: 일 10,000건 (4종 보고서 × 연도 × 종목 → 대량)
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

cat("[dart_quarterly] Loaded.\n")

# ─── Paths ──────────────────────────────────────────────────────────────────
DART_CACHE_DIR  <- file.path(CACHE_DIR, "dart")
DART_CORPCODE   <- file.path(DART_CACHE_DIR, "corpcode_map.parquet")
DART_QUARTERLY_RAW <- file.path(DART_CACHE_DIR, "dart_raw_quarterly.parquet")
DART_TTM_CACHE  <- file.path(CACHE_DIR, "fundamental_dart_quarterly.parquet")

if (!dir.exists(DART_CACHE_DIR)) dir.create(DART_CACHE_DIR, recursive = TRUE)

# Ensure base collector is loaded (for .dart_fetch_single and DART_API_KEY)
if (!exists(".dart_fetch_single")) {
  source(file.path(dirname(sys.frame(1)$ofile %||% "."), "data_collector_dart.R"))
}

# Report code → quarter mapping
REPRT_MAP <- data.table(
  reprt_code = c("11014", "11012", "11013", "11011"),
  quarter    = c(1L, 2L, 3L, 4L),
  label      = c("1Q", "반기", "3Q", "사업보고서")
)


#==============================================================================
# 0. EMPTY 시도 원장 (resume 결함 수리 2026-06-11)
#
# 종전 결함: resume가 성공 레코드(DART_QUARTERLY_RAW)만 보고 EMPTY(공시 미제출)
# 확인은 영속화하지 않아 매 실행 10,905 task 전수 재조회 (~127분, 일 쿼터 절반).
#
# 수리: EMPTY 확정 시도를 (corp_code, Ticker, bsns_year, reprt_code,
# last_attempt_date, n_attempts) 원장으로 영속화하고 재조회 정책 적용.
# 영구 skip 없음 — 늦은 제출 공시가 실제 존재 (수집 레이어, PIT 영향 없음).
#
# 재조회 정책:
#   제출 시즌 내      → 일일 재시도
#   시즌 외           → 주 1회
#   마감 2년 경과 코호트 → 월 1회 (사실상 미제출 확정이나 영구 skip은 금지)
#==============================================================================

DART_QUARTERLY_EMPTY_LEDGER <- file.path(DART_CACHE_DIR, "dart_quarterly_empty_ledger.parquet")

# 보고서 제출 시즌 경계 (12월 결산 기준 — KR 상장사 대다수. 비12월 결산은 주간 재시도로 커버)
#   11014 1Q (3/31 결산, 마감 5/15)        : 4/1 ~ 5/31
#   11012 반기 (6/30 결산, 마감 8/14)       : 7/1 ~ 8/31
#   11013 3Q (9/30 결산, 마감 11/14)        : 10/1 ~ 11/30
#   11011 사업보고서 (12/31 결산, 마감 익년 3/31): 익년 1/1 ~ 4/15
.dart_season_bounds <- function(bsns_year, reprt_code) {
  start <- as.Date(fcase(
    reprt_code == "11014", sprintf("%d-04-01", bsns_year),
    reprt_code == "11012", sprintf("%d-07-01", bsns_year),
    reprt_code == "11013", sprintf("%d-10-01", bsns_year),
    reprt_code == "11011", sprintf("%d-01-01", bsns_year + 1L),
    default = NA_character_
  ))
  end <- as.Date(fcase(
    reprt_code == "11014", sprintf("%d-05-31", bsns_year),
    reprt_code == "11012", sprintf("%d-08-31", bsns_year),
    reprt_code == "11013", sprintf("%d-11-30", bsns_year),
    reprt_code == "11011", sprintf("%d-04-15", bsns_year + 1L),
    default = NA_character_
  ))
  list(start = start, end = end)
}

.dart_load_empty_ledger <- function() {
  if (!file.exists(DART_QUARTERLY_EMPTY_LEDGER)) return(NULL)
  # mmap = FALSE 필수: 같은 실행 내에서 동일 경로에 write_parquet 덮어쓰기 발생.
  # 기본 mmap(TRUE)은 매핑이 살아있는 동안 Windows error 1224로 쓰기 차단 (ktri 사례 동일)
  lg <- tryCatch(as.data.table(read_parquet(DART_QUARTERLY_EMPTY_LEDGER, mmap = FALSE)),
                 error = function(e) NULL)
  if (is.null(lg) || nrow(lg) == 0) return(NULL)
  lg[, last_attempt_date := as.Date(last_attempt_date)]
  lg
}

# 원장 기준 오늘 재시도 차례가 아닌 키 반환 (tasks에서 제외할 대상)
.dart_ledger_skip_keys <- function(ledger, today = Sys.Date()) {
  if (is.null(ledger) || nrow(ledger) == 0) return(NULL)
  se <- .dart_season_bounds(ledger$bsns_year, ledger$reprt_code)
  in_season <- !is.na(se$start) & today >= se$start & today <= se$end
  long_past <- !is.na(se$end) & today > (se$end + 730L)
  interval  <- fifelse(in_season, 1L, fifelse(long_past, 30L, 7L))
  due <- as.integer(today - ledger$last_attempt_date) >= interval
  ledger[!due, .(corp_code, bsns_year, reprt_code)]
}

# 원장 병합 저장: 기존 + 신규 EMPTY 누적 (동일 키 = 시도일 최신화 + 횟수 합산),
# 이번에 성공 수집된 키(ok_keys = 늦은 제출 도착)는 영구 제거
.dart_save_empty_ledger <- function(ledger, empty_new, ok_keys = NULL) {
  new_dt <- if (length(empty_new) > 0) rbindlist(empty_new) else NULL
  merged <- rbindlist(list(ledger, new_dt), fill = TRUE, use.names = TRUE)
  if (is.null(merged) || nrow(merged) == 0) return(invisible(ledger))
  merged <- merged[, .(Ticker = Ticker[.N],
                       last_attempt_date = max(last_attempt_date),
                       n_attempts = sum(n_attempts)),
                   by = .(corp_code, bsns_year, reprt_code)]
  if (!is.null(ok_keys) && nrow(ok_keys) > 0) {
    merged <- merged[!ok_keys, on = c("corp_code", "bsns_year", "reprt_code")]
  }
  write_parquet(merged, DART_QUARTERLY_EMPTY_LEDGER)
  invisible(merged)
}

# .dart_fetch_single 반환 → 상태 분류 ("ok" / "empty" / "rate_limit" / "fail")
.dart_result_status <- function(res) {
  if (is.null(res)) return("fail")
  s <- attr(res, "dart_status", exact = TRUE)
  if (!is.null(s)) return(s)
  if (nrow(res) > 0) "ok" else "fail"
}


#==============================================================================
# 1. Fetch Quarterly Financial Statements
#==============================================================================

dart_fetch_quarterly <- function(years = 2018:2025,
                                  reprt_codes = c("11014", "11012", "11013", "11011"),
                                  fs_div = "CFS",
                                  delay = 0.7,
                                  resume = TRUE) {
  # corp_code 매핑 로드
  if (!file.exists(DART_CORPCODE)) dart_update_corpcode()
  corpmap <- as.data.table(read_parquet(DART_CORPCODE))

  # 유니버스 티커 로드
  if (file.exists(RAWDATA_CACHE)) {
    raw_tickers <- unique(as.data.table(read_parquet(RAWDATA_CACHE))$Ticker)
  } else {
    stop("[dart_quarterly] RAWDATA cache not found.")
  }

  matched <- corpmap[Ticker %in% raw_tickers]
  cat(sprintf("[dart_quarterly] Universe: %d tickers | Matched: %d\n",
              length(raw_tickers), nrow(matched)))

  # 이미 수집된 데이터 (resume)
  # mmap = FALSE: 같은 경로에 checkpoint write_parquet 덮어쓰기 — Windows 1224 차단
  existing <- NULL
  if (resume && file.exists(DART_QUARTERLY_RAW)) {
    existing <- as.data.table(read_parquet(DART_QUARTERLY_RAW, mmap = FALSE))
    cat(sprintf("[dart_quarterly] Resuming: %d existing records\n", nrow(existing)))
  }

  # 수집 대상: 모든 (corp_code, year, reprt_code) 조합
  tasks <- CJ(corp_code = matched$corp_code,
              bsns_year = years,
              reprt_code = reprt_codes,
              sorted = FALSE)
  tasks <- merge(tasks, matched[, .(corp_code, Ticker, corp_name)], by = "corp_code")

  # 이미 수집된 건 제외
  existing_keys <- NULL
  if (!is.null(existing) && nrow(existing) > 0) {
    existing_keys <- unique(existing[, .(corp_code, bsns_year, reprt_code)])
    tasks <- tasks[!existing_keys, on = c("corp_code", "bsns_year", "reprt_code")]
  }

  # EMPTY 원장 제외 — 공시 미제출 확인 영속화 (2026-06-11 resume 결함 수리)
  ledger <- NULL
  if (resume) {
    ledger <- .dart_load_empty_ledger()
    if (!is.null(ledger) && !is.null(existing_keys)) {
      # 뒤늦게 제출돼 수집 완료된 키는 원장에서 영구 제거
      ledger <- ledger[!existing_keys, on = c("corp_code", "bsns_year", "reprt_code")]
    }
    skip_keys <- .dart_ledger_skip_keys(ledger)
    if (!is.null(skip_keys) && nrow(skip_keys) > 0) {
      tasks <- tasks[!skip_keys, on = c("corp_code", "bsns_year", "reprt_code")]
    }
    cat(sprintf("[dart_quarterly] EMPTY ledger: %d entries | skipped today (backoff): %d\n",
                if (is.null(ledger)) 0L else nrow(ledger),
                if (is.null(skip_keys)) 0L else nrow(skip_keys)))
  }
  cat(sprintf("[dart_quarterly] Remaining tasks: %d\n", nrow(tasks)))

  total <- nrow(tasks)
  if (total == 0) {
    cat("[dart_quarterly] Nothing to fetch today (collected or EMPTY-ledger backoff).\n")
    return(invisible(existing))
  }

  cat(sprintf("[dart_quarterly] Fetching %d tasks (~%.0f min)...\n",
              total, total * delay / 60))

  results <- list()
  empty_new <- list()   # 이번 실행에서 EMPTY 확정된 키 (원장 누적분)
  n_success <- 0; n_empty <- 0; n_fail <- 0
  last_data_ckpt <- 0L
  rate_limited <- FALSE

  for (i in seq_len(total)) {
    task <- tasks[i]

    if (i %% 100 == 0 || i == 1) {
      cat(sprintf("  [%d/%d] %s (%s) %d %s | OK:%d EMPTY:%d FAIL:%d\n",
                  i, total, task$corp_name, task$Ticker,
                  task$bsns_year, task$reprt_code,
                  n_success, n_empty, n_fail))
    }

    dt <- tryCatch(
      .dart_fetch_single(task$corp_code, task$bsns_year,
                          task$reprt_code, fs_div),
      error = function(e) NULL
    )
    st_primary  <- .dart_result_status(dt)
    st_fallback <- NA_character_

    # CFS 없으면 OFS 시도 (013 포함 — 비연결 법인은 OFS만 존재)
    if (st_primary %in% c("empty", "fail") && fs_div == "CFS") {
      dt2 <- tryCatch(
        .dart_fetch_single(task$corp_code, task$bsns_year,
                            task$reprt_code, "OFS"),
        error = function(e) NULL
      )
      st_fallback <- .dart_result_status(dt2)
      if (st_fallback == "ok") {
        dt2[, fs_div := "OFS"]
        dt <- dt2
      }
    }

    # 최종 분류: EMPTY는 시도한 fs_div 전부가 '데이터 없음(013)' 확정일 때만.
    # 일시 실패(HTTP/쿼터/파싱)가 섞이면 fail → 원장 미기록 → 다음 실행 재시도.
    st <- if (st_primary == "ok" || identical(st_fallback, "ok")) "ok"
          else if (st_primary == "rate_limit" || identical(st_fallback, "rate_limit")) "rate_limit"
          else if (st_primary == "empty" && (is.na(st_fallback) || st_fallback == "empty")) "empty"
          else "fail"

    if (st == "rate_limit") {
      cat(sprintf("  !! [%d/%d] DART 일일 쿼터 초과(status 020) — 잔여 task 중단, 진행분 저장 후 종료\n",
                  i, total))
      rate_limited <- TRUE
      break
    }

    if (st == "ok") {
      dt[, Ticker := task$Ticker]
      dt[, corp_code := task$corp_code]
      results[[length(results) + 1]] <- dt
      n_success <- n_success + 1
    } else if (st == "empty") {
      n_empty <- n_empty + 1
      empty_new[[length(empty_new) + 1]] <- data.table(
        corp_code = task$corp_code, Ticker = task$Ticker,
        bsns_year = task$bsns_year, reprt_code = task$reprt_code,
        last_attempt_date = Sys.Date(), n_attempts = 1L)
    } else {
      n_fail <- n_fail + 1
    }

    # 중간 저장: 데이터는 신규 500건마다 1회
    if (length(results) > last_data_ckpt && length(results) %% 500 == 0) {
      cat("  > Checkpoint save...\n")
      batch <- rbindlist(results, fill = TRUE)
      if (!is.null(existing)) batch <- rbindlist(list(existing, batch), fill = TRUE)
      write_parquet(batch, DART_QUARTERLY_RAW)
      last_data_ckpt <- length(results)
    }
    # EMPTY 원장은 200 task마다 영속화 (성공 0건 런이 중도 사망해도 진행분 보존)
    if (i %% 200 == 0 && length(empty_new) > 0) {
      ledger <- .dart_save_empty_ledger(ledger, empty_new)
      empty_new <- list()
    }

    Sys.sleep(delay)
  }

  # 최종 저장 — EMPTY 원장은 성공 0건이어도 반드시 영속화 (2026-06-11 수리 핵심)
  ok_keys <- NULL
  out <- existing
  if (length(results) > 0) {
    all_new <- rbindlist(results, fill = TRUE)
    ok_keys <- unique(all_new[, .(corp_code, bsns_year, reprt_code)])
    all_data <- if (!is.null(existing)) rbindlist(list(existing, all_new), fill = TRUE) else all_new
    write_parquet(all_data, DART_QUARTERLY_RAW)
    cat(sprintf("\n[dart_quarterly] DONE. Total: %d | OK: %d | Empty: %d | Fail: %d\n",
                nrow(all_data), n_success, n_empty, n_fail))
    out <- all_data
  } else {
    cat(sprintf("[dart_quarterly] No new data. | OK: 0 | Empty: %d | Fail: %d\n",
                n_empty, n_fail))
  }

  ledger <- .dart_save_empty_ledger(ledger, empty_new, ok_keys = ok_keys)
  cat(sprintf("[dart_quarterly] EMPTY ledger saved: %d entries → %s\n",
              if (is.null(ledger)) 0L else nrow(ledger),
              basename(DART_QUARTERLY_EMPTY_LEDGER)))
  if (rate_limited) {
    cat("[dart_quarterly] 쿼터 초과로 조기 종료 — 잔여 task는 다음 실행에서 자동 재개.\n")
  }

  invisible(out)
}


#==============================================================================
# 2. Parse Quarterly Raw → Individual Quarter Extraction
#==============================================================================

dart_parse_quarterly <- function(raw_dt = NULL) {
  if (is.null(raw_dt)) {
    if (!file.exists(DART_QUARTERLY_RAW))
      stop("[dart_quarterly] No quarterly raw cache. Run dart_fetch_quarterly() first.")
    raw_dt <- as.data.table(read_parquet(DART_QUARTERLY_RAW))
  }

  cat(sprintf("[dart_quarterly] Parsing %d raw quarterly records...\n", nrow(raw_dt)))

  # 금액 파싱
  .parse_amount <- function(x) {
    x <- gsub(",", "", as.character(x))
    x <- gsub("\\s+", "", x)
    suppressWarnings(as.numeric(x))
  }

  # 같은 account_map from data_collector_dart.R
  account_map <- list(
    Revenue       = c("매출액", "수익(매출액)", "영업수익"),
    COGS          = c("매출원가"),
    GrossProfit   = c("매출총이익"),
    SGAExpense    = c("판매비와관리비", "판매비와 관리비"),
    OperatingProfit = c("영업이익", "영업이익(손실)"),
    NetIncome     = c("당기순이익", "당기순이익(손실)",
                       "연결당기순이익", "연결당기순이익(손실)",
                       "지배기업소유주지분순이익", "지배기업의 소유주에게 귀속되는 당기순이익"),
    InterestExp   = c("이자비용", "금융비용"),
    DepAmort      = c("감가상각비", "감가상각비와상각비", "감가상각비 및 상각비"),
    TotalAssets   = c("자산총계"),
    CurrentAssets = c("유동자산"),
    CashAndEquiv  = c("현금및현금성자산", "현금 및 현금성자산"),
    Inventory     = c("재고자산"),
    AccountsRecv  = c("매출채권", "매출채권 및 기타유동채권", "매출채권및기타유동채권"),
    TotalLiab     = c("부채총계"),
    CurrentLiab   = c("유동부채"),
    AccountsPay   = c("매입채무", "매입채무 및 기타유동채무", "매입채무및기타유동채무"),
    TotalEquity   = c("자본총계"),
    OperatingCF   = c("영업활동현금흐름", "영업활동 현금흐름",
                       "영업활동으로인한현금흐름", "영업활동으로 인한 현금흐름"),
    InvestCF      = c("투자활동현금흐름", "투자활동 현금흐름",
                       "투자활동으로인한현금흐름")
  )

  sj_filter <- list(
    Revenue = c("IS", "CIS"), COGS = c("IS", "CIS"),
    GrossProfit = c("IS", "CIS"), SGAExpense = c("IS", "CIS"),
    OperatingProfit = c("IS", "CIS"), NetIncome = c("IS", "CIS"),
    InterestExp = c("IS", "CIS"), DepAmort = c("IS", "CIS", "CF"),
    TotalAssets = "BS", CurrentAssets = "BS", CashAndEquiv = "BS",
    Inventory = "BS", AccountsRecv = "BS",
    TotalLiab = "BS", CurrentLiab = "BS", AccountsPay = "BS",
    TotalEquity = "BS",
    OperatingCF = "CF", InvestCF = "CF"
  )

  raw_dt[, amount_clean := .parse_amount(thstrm_amount)]

  parsed_list <- list()
  for (var_name in names(account_map)) {
    patterns <- account_map[[var_name]]
    valid_sj <- sj_filter[[var_name]]
    matched_rows <- raw_dt[account_nm %in% patterns]
    if (!is.null(valid_sj)) matched_rows <- matched_rows[sj_div %in% valid_sj]
    if (nrow(matched_rows) > 0) {
      deduped <- matched_rows[, .(value = amount_clean[1]),
                                by = .(Ticker, bsns_year, reprt_code)]
      setnames(deduped, "value", var_name)
      parsed_list[[var_name]] <- deduped
    }
  }

  result <- parsed_list[[1]]
  for (i in 2:length(parsed_list)) {
    result <- merge(result, parsed_list[[i]],
                    by = c("Ticker", "bsns_year", "reprt_code"), all = TRUE)
  }

  # Quarter 번호 매핑
  result <- merge(result, REPRT_MAP[, .(reprt_code, quarter)],
                  by = "reprt_code", all.x = TRUE)
  setorder(result, Ticker, bsns_year, quarter)

  cat(sprintf("[dart_quarterly] Parsed: %d records | %d cols | %d tickers\n",
              nrow(result), ncol(result), uniqueN(result$Ticker)))

  result
}


#==============================================================================
# 3. Extract Individual Quarter from Cumulative Reports
#==============================================================================

# DART 누적보고서 → 개별 분기 추출
# 1Q: 그대로 사용
# 2Q: 반기 - 1Q
# 3Q: 3Q누적 - 반기
# 4Q: 연간 - 3Q누적
# B/S 항목은 시점 값이므로 변환 불필요

dart_extract_individual_quarters <- function(parsed_dt) {
  cat("[dart_quarterly] Extracting individual quarters...\n")

  # P/L and CF columns (flow = cumulative → need differencing)
  flow_cols <- c("Revenue", "COGS", "GrossProfit", "SGAExpense",
                 "OperatingProfit", "NetIncome", "InterestExp", "DepAmort",
                 "OperatingCF", "InvestCF")
  # B/S columns (stock = point-in-time → use as-is)
  stock_cols <- c("TotalAssets", "CurrentAssets", "CashAndEquiv", "Inventory",
                  "AccountsRecv", "TotalLiab", "CurrentLiab", "AccountsPay",
                  "TotalEquity")

  flow_cols <- intersect(flow_cols, names(parsed_dt))
  stock_cols <- intersect(stock_cols, names(parsed_dt))

  # Wide format: pivot quarters within same (Ticker, bsns_year)
  setorder(parsed_dt, Ticker, bsns_year, quarter)

  result_list <- list()

  for (tk in unique(parsed_dt$Ticker)) {
    tk_dt <- parsed_dt[Ticker == tk]

    for (yr in unique(tk_dt$bsns_year)) {
      yr_dt <- tk_dt[bsns_year == yr]
      yr_dt <- yr_dt[order(quarter)]

      for (i in seq_len(nrow(yr_dt))) {
        q <- yr_dt$quarter[i]
        row <- copy(yr_dt[i])

        if (q == 1L) {
          # 1Q: use as-is (already single quarter)
          # (flow and stock both fine)
        } else {
          # Need previous cumulative
          prev_q <- q - 1L
          prev_row <- yr_dt[quarter == prev_q]
          if (nrow(prev_row) == 1) {
            for (fc in flow_cols) {
              if (!is.na(row[[fc]]) && !is.na(prev_row[[fc]])) {
                set(row, 1L, fc, row[[fc]] - prev_row[[fc]])
              }
            }
          }
          # B/S: keep current quarter's point-in-time value (no change)
        }

        result_list[[length(result_list) + 1]] <- row
      }
    }
  }

  individual <- rbindlist(result_list)

  # Factor_Date: 분기 보고 후 ~45일
  # 1Q (3월말 결산) → 5/15, 2Q (6월말) → 8/15, 3Q (9월말) → 11/15, 4Q (12월말) → 3/31
  individual[, Factor_Date := as.Date(fifelse(
    quarter == 1L, paste0(bsns_year, "-05-15"),
    fifelse(quarter == 2L, paste0(bsns_year, "-08-15"),
      fifelse(quarter == 3L, paste0(bsns_year, "-11-15"),
              paste0(bsns_year + 1L, "-03-31")))
  ))]

  setorder(individual, Ticker, bsns_year, quarter)

  cat(sprintf("[dart_quarterly] Individual quarters: %d records\n", nrow(individual)))
  individual
}


#==============================================================================
# 4. Compute TTM (Trailing Twelve Months)
#==============================================================================

dart_compute_ttm <- function(raw_dt = NULL) {
  parsed <- dart_parse_quarterly(raw_dt)
  individual <- dart_extract_individual_quarters(parsed)

  cat("[dart_quarterly] Computing TTM factors...\n")

  flow_cols <- c("Revenue", "COGS", "GrossProfit", "SGAExpense",
                 "OperatingProfit", "NetIncome", "InterestExp", "DepAmort",
                 "OperatingCF", "InvestCF")
  stock_cols <- c("TotalAssets", "CurrentAssets", "CashAndEquiv", "Inventory",
                  "AccountsRecv", "TotalLiab", "CurrentLiab", "AccountsPay",
                  "TotalEquity")

  flow_cols <- intersect(flow_cols, names(individual))
  stock_cols <- intersect(stock_cols, names(individual))

  # Sort by Ticker, chronological order
  setorder(individual, Ticker, bsns_year, quarter)
  individual[, seq_id := seq_len(.N), by = Ticker]

  ttm_list <- list()

  for (tk in unique(individual$Ticker)) {
    tk_dt <- individual[Ticker == tk]

    if (nrow(tk_dt) < 4) next  # Need at least 4 quarters

    for (i in 4:nrow(tk_dt)) {
      window <- tk_dt[(i - 3):i]

      # Check: must be 4 consecutive quarters
      # (allow gaps — just sum available)
      row <- data.table(
        Ticker = tk,
        bsns_year = tk_dt$bsns_year[i],
        quarter = tk_dt$quarter[i],
        Factor_Date = tk_dt$Factor_Date[i]
      )

      # Flow: sum last 4 individual quarters
      for (fc in flow_cols) {
        vals <- window[[fc]]
        row[, (fc) := if (sum(!is.na(vals)) >= 3) sum(vals, na.rm = TRUE) else NA_real_]
      }

      # Stock: use latest quarter's value
      for (sc in stock_cols) {
        row[, (sc) := tk_dt[[sc]][i]]
      }

      ttm_list[[length(ttm_list) + 1]] <- row
    }
  }

  ttm_dt <- rbindlist(ttm_list, fill = TRUE)

  cat(sprintf("[dart_quarterly] TTM records: %d | %d tickers\n",
              nrow(ttm_dt), uniqueN(ttm_dt$Ticker)))

  # ── Compute TTM-based factors (same formulas as annual) ──
  .safe_div <- function(num, denom, min_denom = 0) {
    fifelse(!is.na(num) & !is.na(denom) & denom > min_denom, num / denom, NA_real_)
  }

  # Derived items
  ttm_dt[is.na(GrossProfit) & !is.na(Revenue) & !is.na(COGS),
         GrossProfit := Revenue - COGS]
  ttm_dt[, EBITDA := fifelse(!is.na(OperatingProfit),
    OperatingProfit + fifelse(!is.na(DepAmort), DepAmort, 0), NA_real_)]
  ttm_dt[, WorkingCapital := CurrentAssets - CurrentLiab]
  ttm_dt[, FCF := fifelse(!is.na(OperatingCF) & !is.na(InvestCF),
                           OperatingCF + InvestCF, NA_real_)]

  # Key factors (TTM)
  ttm_dt[, GPA := .safe_div(GrossProfit, TotalAssets)]
  ttm_dt[, ROE := .safe_div(NetIncome, TotalEquity)]
  ttm_dt[, ROA := .safe_div(NetIncome, TotalAssets)]
  ttm_dt[, OPM := .safe_div(OperatingProfit, Revenue)]
  ttm_dt[, GrossMargin := .safe_div(GrossProfit, Revenue)]
  ttm_dt[, NetMargin := .safe_div(NetIncome, Revenue)]
  ttm_dt[, EBIT_to_Assets := .safe_div(OperatingProfit, TotalAssets)]
  ttm_dt[, FCF_Margin := .safe_div(FCF, Revenue)]
  ttm_dt[, AssetTurnover := .safe_div(Revenue, TotalAssets)]
  ttm_dt[, Accrual := fifelse(!is.na(TotalAssets) & TotalAssets > 0 &
    !is.na(NetIncome) & !is.na(OperatingCF),
    (NetIncome - OperatingCF) / TotalAssets, NA_real_)]
  ttm_dt[, ICR := fifelse(!is.na(InterestExp) & InterestExp > 0 & !is.na(OperatingProfit),
                           OperatingProfit / InterestExp, NA_real_)]
  ttm_dt[, CurrentRatio := .safe_div(CurrentAssets, CurrentLiab)]
  ttm_dt[, CashToAssets := .safe_div(CashAndEquiv, TotalAssets)]
  ttm_dt[, DebtRatio := .safe_div(TotalLiab, TotalEquity)]

  # Efficiency (TTM)
  ttm_dt[, InventoryTurnover := .safe_div(COGS, Inventory)]
  ttm_dt[, ReceivablesTurnover := .safe_div(Revenue, AccountsRecv)]
  ttm_dt[, PayablesTurnover := .safe_div(COGS, AccountsPay)]
  ttm_dt[, DaysReceivable := fifelse(!is.na(ReceivablesTurnover) & ReceivablesTurnover > 0,
                                      365 / ReceivablesTurnover, NA_real_)]
  ttm_dt[, DaysInventory := fifelse(!is.na(InventoryTurnover) & InventoryTurnover > 0,
                                     365 / InventoryTurnover, NA_real_)]
  ttm_dt[, DaysPayable := fifelse(!is.na(PayablesTurnover) & PayablesTurnover > 0,
                                   365 / PayablesTurnover, NA_real_)]
  ttm_dt[, CCC := fifelse(!is.na(DaysReceivable) & !is.na(DaysInventory) & !is.na(DaysPayable),
                           DaysReceivable + DaysInventory - DaysPayable, NA_real_)]
  ttm_dt[, CashBurnRate := fifelse(!is.na(OperatingCF) & OperatingCF < 0 &
    !is.na(CashAndEquiv) & CashAndEquiv > 0,
    CashAndEquiv / abs(OperatingCF), NA_real_)]
  ttm_dt[, OCFToRevenue := .safe_div(OperatingCF, Revenue)]

  # Growth (vs 4 quarters ago = YoY)
  setorder(ttm_dt, Ticker, Factor_Date)
  growth_cols <- c("Revenue", "GrossProfit", "OperatingProfit", "NetIncome", "TotalAssets")
  for (gc in growth_cols) {
    delta_name <- paste0(gc, "Growth")
    ttm_dt[, (delta_name) := get(gc) / shift(get(gc), 4L) - 1, by = Ticker]
  }

  # Delta ratios (vs 4 quarters ago)
  delta_ratio_cols <- c("GPA", "ROA", "Accrual", "CCC")
  for (dc in delta_ratio_cols) {
    delta_name <- paste0("Delta_", dc)
    ttm_dt[, (delta_name) := get(dc) - shift(get(dc), 4L), by = Ticker]
  }

  # Save
  write_parquet(ttm_dt, DART_TTM_CACHE)
  cat(sprintf("[dart_quarterly] TTM saved: %d rows | %d tickers | %s\n",
              nrow(ttm_dt), uniqueN(ttm_dt$Ticker), DART_TTM_CACHE))

  # Coverage report
  key_cols <- c("GPA", "ROE", "ROA", "CCC", "Accrual", "Delta_GPA", "Delta_ROA",
                "Delta_Accrual", "CashBurnRate", "CurrentRatio")
  cat("\n[dart_quarterly] TTM Key Factor Coverage:\n")
  for (col in key_cols) {
    if (col %in% names(ttm_dt)) {
      pct <- round(mean(!is.na(ttm_dt[[col]])) * 100, 1)
      cat(sprintf("  %-20s: %5.1f%%\n", col, pct))
    }
  }

  invisible(ttm_dt)
}


#==============================================================================
# 5. Master Pipeline
#==============================================================================

dart_quarterly_pipeline <- function(years = 2018:2025) {
  cat("═══════════════════════════════════════════════\n")
  cat("[dart_quarterly] Starting quarterly pipeline\n")
  cat("═══════════════════════════════════════════════\n\n")

  cat("── Step 1: Fetch quarterly reports ──\n")
  dart_fetch_quarterly(years = years)

  cat("\n── Step 2: Compute TTM factors ──\n")
  dart_compute_ttm()

  cat("\n═══════════════════════════════════════════════\n")
  cat("[dart_quarterly] Pipeline complete!\n")
  cat("═══════════════════════════════════════════════\n")
}
