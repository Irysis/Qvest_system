#==============================================================================
# Quant Module — DART OpenAPI Data Collector
# Version: 1.0.0
#
# 금융감독원 전자공시 DART API를 통해 재무제표 데이터를 수집하여
# 펀더멘털 팩터 계산에 필요한 데이터를 Parquet 캐시로 저장.
#
# 수집 항목:
#   - BS: 자산총계, 부채총계, 자본총계
#   - IS: 매출액, 매출원가, 영업이익, 당기순이익, 이자비용, 감가상각비
#   - CF: 영업활동현금흐름
#
# 계산 팩터:
#   - GPA (Gross Profit / Total Assets)
#   - ROE (Net Income / Total Equity)
#   - Accrual Ratio ((NI - OCF) / Total Assets)
#   - ICR (Operating Profit / Interest Expense)
#   - Asset Growth (YoY Total Assets change)
#   - Debt Ratio (Total Liabilities / Total Equity)
#   - OPM (Operating Profit / Revenue)
#
# 사용법:
#   source("config.R")
#   source("data_collector_dart.R")
#   dart_update_corpcode()                    # corp_code 매핑 테이블 갱신
#   dart_fetch_all(years = 2015:2024)         # 전체 유니버스 재무제표 수집
#   dart_compute_factors()                    # 팩터 계산 + Parquet 저장
#
# API 제한: 일 10,000건 / 분당 ~100건 (안전하게 0.7초 간격)
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(httr)
  library(jsonlite)
  library(xml2)
})

cat("[dart_collector] Loaded.\n")

# ─── Paths ──────────────────────────────────────────────────────────────────
DART_CACHE_DIR  <- file.path(CACHE_DIR, "dart")
DART_CORPCODE   <- file.path(DART_CACHE_DIR, "corpcode_map.parquet")
DART_RAW_CACHE  <- file.path(DART_CACHE_DIR, "dart_raw_financials.parquet")
DART_FACTOR_CACHE <- file.path(CACHE_DIR, "fundamental_dart.parquet")

if (!dir.exists(DART_CACHE_DIR)) dir.create(DART_CACHE_DIR, recursive = TRUE)

# 제출창 지식 + 수집 후보집합 판정 (2026-07-26 P2-01 수리 — 단일 정본)
source(file.path(PROJECT_ROOT, "02_Infrastructure", "data", "dart_submission_window.R"))

# ─── API Key ────────────────────────────────────────────────────────────────
.load_dart_key <- function() {
  env_path <- file.path(PROJECT_ROOT, ".env")
  if (!file.exists(env_path)) stop("[dart] .env file not found at: ", env_path)

  lines <- readLines(env_path, warn = FALSE)
  for (line in lines) {
    if (grepl("^DART_API_KEY=", line)) {
      key <- sub("^DART_API_KEY=", "", trimws(line))
      if (nchar(key) < 10) stop("[dart] DART_API_KEY is empty or too short in .env")
      return(key)
    }
  }
  stop("[dart] DART_API_KEY not found in .env")
}

DART_API_KEY <- .load_dart_key()


#==============================================================================
# 1. Corp Code Mapping — DART corp_code ↔ stock_code
#==============================================================================

dart_update_corpcode <- function(force = FALSE) {
  if (!force && file.exists(DART_CORPCODE)) {
    age <- difftime(Sys.time(), file.mtime(DART_CORPCODE), units = "days")
    if (age < 30) {
      cat("[dart] Corp code map is recent (", round(age, 1), " days). Skipping.\n")
      return(invisible(as.data.table(read_parquet(DART_CORPCODE))))
    }
  }

  cat("[dart] Downloading corp code list from DART...\n")

  # DART API: corpCode.xml → ZIP → CORPCODE.xml
  url <- paste0("https://opendart.fss.or.kr/api/corpCode.xml?crtfc_key=", DART_API_KEY)
  tmp_zip <- tempfile(fileext = ".zip")

  resp <- GET(url, write_disk(tmp_zip, overwrite = TRUE), timeout(60))
  if (status_code(resp) != 200) {
    stop("[dart] Corp code download failed. HTTP ", status_code(resp))
  }

  # ZIP 해제
  tmp_dir <- tempdir()
  unzip(tmp_zip, exdir = tmp_dir)
  xml_path <- file.path(tmp_dir, "CORPCODE.xml")

  if (!file.exists(xml_path)) {
    # ZIP 안의 파일명이 다를 수 있음
    xml_files <- list.files(tmp_dir, pattern = "\\.xml$", full.names = TRUE)
    if (length(xml_files) == 0) stop("[dart] No XML found in ZIP")
    xml_path <- xml_files[1]
  }

  cat("[dart] Parsing CORPCODE.xml...\n")
  doc <- read_xml(xml_path)
  nodes <- xml_find_all(doc, ".//list")

  corp_dt <- data.table(
    corp_code  = xml_text(xml_find_first(nodes, ".//corp_code")),
    corp_name  = xml_text(xml_find_first(nodes, ".//corp_name")),
    stock_code = xml_text(xml_find_first(nodes, ".//stock_code")),
    modify_date = xml_text(xml_find_first(nodes, ".//modify_date"))
  )

  # stock_code가 비어있으면 비상장 → 제거
  corp_dt <- corp_dt[nchar(stock_code) == 6]

  # Ticker 포맷 맞추기 (A + 6자리)
  corp_dt[, Ticker := paste0("A", stock_code)]

  cat(sprintf("[dart] Corp code map: %d listed companies\n", nrow(corp_dt)))

  write_parquet(corp_dt, DART_CORPCODE)
  unlink(tmp_zip)

  invisible(corp_dt)
}


#==============================================================================
# 2. Fetch Financial Statements — 단일회사 주요계정
#==============================================================================

# DART API 호출 (단일 종목, 단일 연도, 단일 보고서)
#
# 반환 규약 (2026-06-11 확장 — resume EMPTY 영속화 수리):
#   data.table (>0행)                      = 데이터 수신
#   data.table (0행, attr "dart_status"="empty")      = 공시 미제출 확정 (status 013 / 빈 list)
#   data.table (0행, attr "dart_status"="rate_limit") = 일일 쿼터 초과 (status 020)
#   NULL                                   = 일시 실패 (HTTP/파싱/기타 status — 재시도 대상)
# 기존 호출부의 `is.null(dt) || nrow(dt) == 0` 체크와 완전 호환 (0행은 종전 NULL과 동일 분기).
.dart_empty_result <- function(status) {
  res <- data.table()
  setattr(res, "dart_status", status)
  res
}

.dart_fetch_single <- function(corp_code, bsns_year, reprt_code = "11011",
                                fs_div = "CFS") {
  url <- "https://opendart.fss.or.kr/api/fnlttSinglAcntAll.json"

  resp <- GET(url, query = list(
    crtfc_key  = DART_API_KEY,
    corp_code  = corp_code,
    bsns_year  = as.character(bsns_year),
    reprt_code = reprt_code,
    fs_div     = fs_div
  ), timeout(30))

  if (status_code(resp) != 200) return(NULL)

  body <- content(resp, "text", encoding = "UTF-8")
  json <- tryCatch(fromJSON(body), error = function(e) NULL)
  if (is.null(json)) return(NULL)

  # DART 응답 코드 확인
  #  "000" = 정상, "013" = 데이터 없음, "020" = 한도 초과
  if (is.null(json$status) || json$status != "000") {
    if (!is.null(json$status) && json$status == "020") {
      warning("[dart] API rate limit exceeded!")
      return(.dart_empty_result("rate_limit"))
    }
    if (!is.null(json$status) && json$status == "013") {
      return(.dart_empty_result("empty"))
    }
    return(NULL)
  }

  if (is.null(json$list) || length(json$list) == 0) return(.dart_empty_result("empty"))

  dt <- as.data.table(json$list)
  dt[, bsns_year := as.integer(bsns_year)]
  dt[, reprt_code := reprt_code]
  dt[, fs_div := fs_div]
  dt
}


# 유니버스 전체 티커에 대해 재무제표 수집
dart_fetch_all <- function(years = 2018:2025,
                            reprt_code = "11011",
                            fs_div = "CFS",
                            delay = 0.7,
                            resume = TRUE) {
  # corp_code 매핑 로드
  if (!file.exists(DART_CORPCODE)) dart_update_corpcode()
  corpmap <- as.data.table(read_parquet(DART_CORPCODE))

  # 유니버스 티커 로드 (RAWDATA에서)
  if (file.exists(RAWDATA_CACHE)) {
    raw_tickers <- unique(as.data.table(read_parquet(RAWDATA_CACHE))$Ticker)
  } else {
    stop("[dart] RAWDATA cache not found. Run build_cache.R first.")
  }

  # 매칭
  matched <- corpmap[Ticker %in% raw_tickers]
  cat(sprintf("[dart] Universe: %d tickers | Matched in DART: %d\n",
              length(raw_tickers), nrow(matched)))

  # 이미 수집된 데이터 로드 (resume 모드)
  existing <- NULL
  if (resume && file.exists(DART_RAW_CACHE)) {
    existing <- as.data.table(read_parquet(DART_RAW_CACHE))
    cat(sprintf("[dart] Resuming: %d existing records loaded\n", nrow(existing)))
  }

  # 수집 대상 목록 생성
  tasks <- CJ(corp_code = matched$corp_code, bsns_year = years, sorted = FALSE)
  tasks <- merge(tasks, matched[, .(corp_code, Ticker, corp_name)], by = "corp_code")

  # 이미 수집된 건 제외
  if (!is.null(existing) && nrow(existing) > 0) {
    existing_keys <- unique(existing[, .(corp_code, bsns_year)])
    tasks <- tasks[!existing_keys, on = c("corp_code", "bsns_year")]
    cat(sprintf("[dart] Remaining tasks after resume: %d\n", nrow(tasks)))
  }

  total <- nrow(tasks)
  if (total == 0) {
    cat("[dart] All data already collected.\n")
    return(invisible(existing))
  }

  cat(sprintf("[dart] Fetching %d company-year combinations (%.0f min estimated)...\n",
              total, total * delay / 60))

  # 수집 루프
  results <- list()
  n_success <- 0
  n_fail    <- 0
  n_empty   <- 0

  for (i in seq_len(total)) {
    task <- tasks[i]

    if (i %% 50 == 0 || i == 1) {
      cat(sprintf("  [%d/%d] %s (%s) %d | OK:%d EMPTY:%d FAIL:%d\n",
                  i, total, task$corp_name, task$Ticker,
                  task$bsns_year, n_success, n_empty, n_fail))
    }

    dt <- tryCatch(
      .dart_fetch_single(task$corp_code, task$bsns_year, reprt_code, fs_div),
      error = function(e) {
        cat(sprintf("    ERROR %s: %s\n", task$Ticker, e$message))
        NULL
      }
    )

    if (is.null(dt) || nrow(dt) == 0) {
      # 연결재무제표 없으면 개별재무제표 시도
      if (fs_div == "CFS") {
        dt <- tryCatch(
          .dart_fetch_single(task$corp_code, task$bsns_year, reprt_code, "OFS"),
          error = function(e) NULL
        )
        if (!is.null(dt) && nrow(dt) > 0) {
          dt[, fs_div := "OFS"]
        }
      }
    }

    if (!is.null(dt) && nrow(dt) > 0) {
      dt[, Ticker := task$Ticker]
      dt[, corp_code := task$corp_code]
      results[[length(results) + 1]] <- dt
      n_success <- n_success + 1
    } else {
      n_empty <- n_empty + 1
    }

    # 중간 저장 (매 200건)
    if (length(results) > 0 && length(results) %% 200 == 0) {
      cat("  > Checkpoint save...\n")
      batch <- rbindlist(results, fill = TRUE)
      if (!is.null(existing)) {
        batch <- rbindlist(list(existing, batch), fill = TRUE)
      }
      # [fix 2026-06-17] Windows arrow mmap(error 1224) — existing이 DART_RAW_CACHE를
      # mmap한 채라 동일 경로 write_parquet halt 회피, temp-rename. (existing은 이후
      # checkpoint·최종저장에 반복 참조되므로 rm 불가 — rename으로 inode 교체)
      .dart_tmp <- paste0(DART_RAW_CACHE, ".tmp")
      write_parquet(batch, .dart_tmp)
      if (file.exists(DART_RAW_CACHE)) file.remove(DART_RAW_CACHE)
      file.rename(.dart_tmp, DART_RAW_CACHE)
    }

    # Rate limit (DART: ~100/min → 0.7초 간격)
    Sys.sleep(delay)
  }

  # 최종 저장
  if (length(results) > 0) {
    all_data <- rbindlist(results, fill = TRUE)
    if (!is.null(existing)) {
      all_data <- rbindlist(list(existing, all_data), fill = TRUE)
    }
    # [fix 2026-06-17] Windows arrow mmap(error 1224) — existing이 DART_RAW_CACHE를 mmap한
    # 채라 동일 경로 write_parquet halt 회피, temp-rename (checkpoint와 동일).
    .dart_tmp <- paste0(DART_RAW_CACHE, ".tmp")
    write_parquet(all_data, .dart_tmp)
    if (file.exists(DART_RAW_CACHE)) file.remove(DART_RAW_CACHE)
    file.rename(.dart_tmp, DART_RAW_CACHE)
    cat(sprintf("\n[dart] DONE. Total records: %d | Success: %d | Empty: %d | Fail: %d\n",
                nrow(all_data), n_success, n_empty, n_fail))
    cat(sprintf("[dart] Saved to: %s\n", DART_RAW_CACHE))
    invisible(all_data)
  } else {
    cat("[dart] No new data fetched.\n")
    invisible(existing)
  }
}


#==============================================================================
# 3. Parse Raw Financials → Clean Accounts Table
#==============================================================================

dart_parse_financials <- function(raw_dt = NULL) {
  if (is.null(raw_dt)) {
    if (!file.exists(DART_RAW_CACHE)) stop("[dart] No raw cache found. Run dart_fetch_all() first.")
    raw_dt <- as.data.table(read_parquet(DART_RAW_CACHE))
  }

  cat(sprintf("[dart] Parsing %d raw records...\n", nrow(raw_dt)))

  # 금액 파싱 (쉼표 제거 → numeric)
  .parse_amount <- function(x) {
    x <- gsub(",", "", as.character(x))
    x <- gsub("\\s+", "", x)
    suppressWarnings(as.numeric(x))
  }

  # 주요 계정 매핑 (DART 계정명 → 표준 변수명)
  # DART는 한글 계정명 사용, 회사마다 미세하게 다름
  account_map <- list(
    # IS (손익계산서)
    Revenue       = c("매출액", "수익(매출액)", "영업수익"),
    COGS          = c("매출원가"),
    GrossProfit   = c("매출총이익"),
    SGAExpense    = c("판매비와관리비", "판매비와 관리비"),
    OperatingProfit = c("영업이익", "영업이익(손실)"),
    PretaxIncome  = c("법인세비용차감전순이익", "법인세비용차감전순이익(손실)",
                       "법인세차감전 순이익", "법인세비용차감전순이익(손실)",
                       "법인세비용차감전 순이익(손실)"),
    TaxExpense    = c("법인세비용"),
    NetIncome     = c("당기순이익", "당기순이익(손실)",
                       "연결당기순이익", "연결당기순이익(손실)",
                       "지배기업소유주지분순이익", "지배기업의 소유주에게 귀속되는 당기순이익"),
    InterestExp   = c("이자비용", "금융비용"),
    InterestIncome = c("이자수익", "금융수익"),
    DepAmort      = c("감가상각비", "감가상각비와상각비", "감가상각비 및 상각비"),
    RandD         = c("경상연구개발비", "연구개발비", "연구 및 개발비"),

    # BS (재무상태표)
    TotalAssets   = c("자산총계"),
    CurrentAssets = c("유동자산"),
    NonCurrentAssets = c("비유동자산"),
    CashAndEquiv  = c("현금및현금성자산", "현금 및 현금성자산"),
    Inventory     = c("재고자산"),
    AccountsRecv  = c("매출채권", "매출채권 및 기타유동채권",
                       "매출채권및기타유동채권"),
    TangibleAssets = c("유형자산"),
    IntangibleAssets = c("무형자산"),
    TotalLiab     = c("부채총계"),
    CurrentLiab   = c("유동부채"),
    NonCurrentLiab = c("비유동부채"),
    ShortTermBorr = c("단기차입금"),
    LongTermBorr  = c("장기차입금", "사채"),
    AccountsPay   = c("매입채무", "매입채무 및 기타유동채무",
                       "매입채무및기타유동채무"),
    TotalEquity   = c("자본총계"),
    CapitalStock  = c("자본금"),
    RetainedEarnings = c("이익잉여금"),

    # CF (현금흐름표)
    OperatingCF   = c("영업활동현금흐름", "영업활동 현금흐름",
                       "영업활동으로인한현금흐름", "영업활동으로 인한 현금흐름"),
    InvestCF      = c("투자활동현금흐름", "투자활동 현금흐름",
                       "투자활동으로인한현금흐름"),
    FinanceCF     = c("재무활동현금흐름", "재무활동 현금흐름",
                       "재무활동으로인한현금흐름"),
    Dividends     = c("배당금지급", "배당금 지급", "배당금")
  )

  # 계정명을 표준 변수명으로 변환
  raw_dt[, amount_clean := .parse_amount(thstrm_amount)]

  # sj_div: BS=재무상태표, IS=손익계산서, CF=현금흐름표, CIS=포괄손익계산서
  # account_nm: DART 계정명

  # sj_div 필터 맵: 계정 유형별 재무제표 구분 제한
  # (SCE 등에서 동일 계정명이 중복 출현하는 것을 방지)
  sj_filter <- list(
    Revenue = c("IS", "CIS"), COGS = c("IS", "CIS"),
    GrossProfit = c("IS", "CIS"), SGAExpense = c("IS", "CIS"),
    OperatingProfit = c("IS", "CIS"),
    PretaxIncome = c("IS", "CIS"), TaxExpense = c("IS", "CIS"),
    NetIncome = c("IS", "CIS"),
    InterestExp = c("IS", "CIS"), InterestIncome = c("IS", "CIS"),
    DepAmort = c("IS", "CIS", "CF"), RandD = c("IS", "CIS"),
    TotalAssets = "BS", CurrentAssets = "BS", NonCurrentAssets = "BS",
    CashAndEquiv = "BS", Inventory = "BS", AccountsRecv = "BS",
    TangibleAssets = "BS", IntangibleAssets = "BS",
    TotalLiab = "BS", CurrentLiab = "BS", NonCurrentLiab = "BS",
    ShortTermBorr = "BS", LongTermBorr = "BS", AccountsPay = "BS",
    TotalEquity = "BS", CapitalStock = "BS", RetainedEarnings = "BS",
    OperatingCF = "CF", InvestCF = "CF", FinanceCF = "CF",
    Dividends = c("CF", "SCE")
  )

  # Wide-format 변환: 각 계정을 컬럼으로
  parsed_list <- list()

  for (var_name in names(account_map)) {
    patterns <- account_map[[var_name]]
    valid_sj <- sj_filter[[var_name]]
    matched_rows <- raw_dt[account_nm %in% patterns]
    if (!is.null(valid_sj)) {
      matched_rows <- matched_rows[sj_div %in% valid_sj]
    }

    if (nrow(matched_rows) > 0) {
      # 동일 기업-연도에 중복 계정 → 첫 번째 사용
      deduped <- matched_rows[, .(value = amount_clean[1]),
                                by = .(Ticker, bsns_year)]
      setnames(deduped, "value", var_name)
      parsed_list[[var_name]] <- deduped
    }
  }

  # Merge all accounts
  if (length(parsed_list) == 0) {
    warning("[dart] No accounts parsed!")
    return(NULL)
  }

  result <- parsed_list[[1]]
  for (i in 2:length(parsed_list)) {
    result <- merge(result, parsed_list[[i]],
                    by = c("Ticker", "bsns_year"), all = TRUE)
  }

  setorder(result, Ticker, bsns_year)
  cat(sprintf("[dart] Parsed: %d company-year records | %d columns\n",
              nrow(result), ncol(result)))

  result
}


#==============================================================================
# 4. Compute Fundamental Factors
#==============================================================================

dart_compute_factors <- function(raw_dt = NULL) {
  parsed <- dart_parse_financials(raw_dt)
  if (is.null(parsed)) return(NULL)

  cat("[dart] Computing fundamental factors...\n")

  # 파싱에서 누락된 컬럼은 NA로 초기화
  expected_cols <- c(
    # IS
    "Revenue", "COGS", "GrossProfit", "SGAExpense", "OperatingProfit",
    "PretaxIncome", "TaxExpense", "NetIncome", "InterestExp", "InterestIncome",
    "DepAmort", "RandD",
    # BS
    "TotalAssets", "CurrentAssets", "NonCurrentAssets", "CashAndEquiv",
    "Inventory", "AccountsRecv", "TangibleAssets", "IntangibleAssets",
    "TotalLiab", "CurrentLiab", "NonCurrentLiab", "ShortTermBorr", "LongTermBorr",
    "AccountsPay", "TotalEquity", "CapitalStock", "RetainedEarnings",
    # CF
    "OperatingCF", "InvestCF", "FinanceCF", "Dividends"
  )
  for (col in expected_cols) {
    if (!col %in% names(parsed)) parsed[, (col) := NA_real_]
  }

  # ══════════════════════════════════════════════════════════════════════════
  # MASSIVE FACTOR EXPANSION: 200+ fundamental indicators
  # ══════════════════════════════════════════════════════════════════════════

  .safe_div <- function(num, denom, min_denom = 0) {
    fifelse(!is.na(num) & !is.na(denom) & denom > min_denom, num / denom, NA_real_)
  }

  # ── Average denominators (유량 계산법: 직전시점과 분석시점 평균) ──
  setorder(parsed, Ticker, bsns_year)
  parsed[, AvgAssets := (TotalAssets + shift(TotalAssets)) / 2, by = Ticker]
  parsed[, AvgEquity := (TotalEquity + shift(TotalEquity)) / 2, by = Ticker]
  parsed[, AvgInventory := (Inventory + shift(Inventory)) / 2, by = Ticker]
  parsed[, AvgRecv := (AccountsRecv + shift(AccountsRecv)) / 2, by = Ticker]
  parsed[, AvgPay := (AccountsPay + shift(AccountsPay)) / 2, by = Ticker]

  # Derived raw items
  parsed[is.na(GrossProfit) & !is.na(Revenue) & !is.na(COGS),
         GrossProfit := Revenue - COGS]
  parsed[, EBITDA := fifelse(!is.na(OperatingProfit),
    OperatingProfit + fifelse(!is.na(DepAmort), DepAmort, 0), NA_real_)]
  parsed[, EBIT := OperatingProfit]  # alias
  parsed[, WorkingCapital := CurrentAssets - CurrentLiab]
  parsed[, TotalDebt := fifelse(!is.na(ShortTermBorr), ShortTermBorr, 0) +
                          fifelse(!is.na(LongTermBorr), LongTermBorr, 0)]
  parsed[, NetDebt := TotalDebt - fifelse(!is.na(CashAndEquiv), CashAndEquiv, 0)]
  parsed[, FCF := fifelse(!is.na(OperatingCF) & !is.na(InvestCF),
                           OperatingCF + InvestCF, NA_real_)]
  parsed[, NetInterest := fifelse(!is.na(InterestIncome), InterestIncome, 0) -
                            fifelse(!is.na(InterestExp), InterestExp, 0)]
  parsed[, NOPAT := fifelse(!is.na(OperatingProfit) & !is.na(TaxExpense) &
                              !is.na(PretaxIncome) & PretaxIncome != 0,
    OperatingProfit * (1 - TaxExpense / PretaxIncome), NA_real_)]

  cat("[dart] Computing 200+ fundamental factors...\n")

  # ═══════════════════════════════════════════════════════════════════════
  # A. PROFITABILITY (수익성) — 15 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, GPA := .safe_div(GrossProfit, AvgAssets)]
  parsed[, ROE := .safe_div(NetIncome, AvgEquity)]
  parsed[, ROA := .safe_div(NetIncome, AvgAssets)]
  parsed[, OPM := .safe_div(OperatingProfit, Revenue)]
  parsed[, GrossMargin := .safe_div(GrossProfit, Revenue)]
  parsed[, NetMargin := .safe_div(NetIncome, Revenue)]
  parsed[, EBITDA_Margin := .safe_div(EBITDA, Revenue)]
  parsed[, ROIC := .safe_div(NOPAT,
    fifelse(!is.na(TotalEquity) & !is.na(TotalDebt),
            TotalEquity + TotalDebt - fifelse(!is.na(CashAndEquiv), CashAndEquiv, 0),
            NA_real_))]
  parsed[, GrossProfit_to_Equity := .safe_div(GrossProfit, AvgEquity)]
  parsed[, EBIT_to_Assets := .safe_div(EBIT, AvgAssets)]  # Altman X3
  parsed[, OperatingROA := .safe_div(OperatingProfit, AvgAssets)]
  parsed[, PreTaxROA := .safe_div(PretaxIncome, AvgAssets)]
  parsed[, OCF_ROA := .safe_div(OperatingCF, AvgAssets)]
  parsed[, FCF_Margin := .safe_div(FCF, Revenue)]
  parsed[, CashEarningsRatio := .safe_div(OperatingCF, NetIncome)]

  # ═══════════════════════════════════════════════════════════════════════
  # B. EFFICIENCY (효율성/회전율) — 12 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, AssetTurnover := .safe_div(Revenue, AvgAssets)]
  parsed[, EquityTurnover := .safe_div(Revenue, AvgEquity)]
  parsed[, InventoryTurnover := .safe_div(COGS, AvgInventory)]
  parsed[, ReceivablesTurnover := .safe_div(Revenue, AvgRecv)]
  parsed[, PayablesTurnover := .safe_div(COGS, AvgPay)]
  parsed[, DaysReceivable := fifelse(!is.na(ReceivablesTurnover) & ReceivablesTurnover > 0,
                                      365 / ReceivablesTurnover, NA_real_)]
  parsed[, DaysInventory := fifelse(!is.na(InventoryTurnover) & InventoryTurnover > 0,
                                     365 / InventoryTurnover, NA_real_)]
  parsed[, DaysPayable := fifelse(!is.na(PayablesTurnover) & PayablesTurnover > 0,
                                   365 / PayablesTurnover, NA_real_)]
  parsed[, CCC := fifelse(!is.na(DaysReceivable) & !is.na(DaysInventory) & !is.na(DaysPayable),
                           DaysReceivable + DaysInventory - DaysPayable, NA_real_)]
  parsed[, FixedAssetTurnover := .safe_div(Revenue, TangibleAssets)]
  parsed[, WCTurnover := fifelse(!is.na(WorkingCapital) & WorkingCapital > 0,
                                  Revenue / WorkingCapital, NA_real_)]
  parsed[, SGAEfficiency := .safe_div(SGAExpense, Revenue)]

  # ═══════════════════════════════════════════════════════════════════════
  # C. LEVERAGE & SOLVENCY (레버리지/안정성) — 18 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, DebtRatio := .safe_div(TotalLiab, TotalEquity)]
  parsed[, DebtToAssets := .safe_div(TotalLiab, TotalAssets)]
  parsed[, LongTermDebtToEquity := .safe_div(LongTermBorr, TotalEquity)]
  parsed[, TotalDebtToAssets := .safe_div(TotalDebt, TotalAssets)]
  parsed[, NetDebtToEBITDA := fifelse(!is.na(NetDebt) & !is.na(EBITDA) & EBITDA > 0,
                                       NetDebt / EBITDA, NA_real_)]
  parsed[, NetDebtToAssets := .safe_div(NetDebt, TotalAssets)]
  parsed[, EquityMultiplier := .safe_div(TotalAssets, TotalEquity)]
  parsed[, InterestBurden := .safe_div(InterestExp, Revenue)]
  parsed[, ICR := fifelse(!is.na(InterestExp) & InterestExp > 0 & !is.na(OperatingProfit),
                           OperatingProfit / InterestExp, NA_real_)]
  parsed[, EBITDA_ICR := fifelse(!is.na(InterestExp) & InterestExp > 0 & !is.na(EBITDA),
                                  EBITDA / InterestExp, NA_real_)]
  parsed[, NetInterestMargin := .safe_div(NetInterest, Revenue)]
  parsed[, FinancialLeverage := .safe_div(AvgAssets, AvgEquity)]
  parsed[, ShortTermDebtRatio := fifelse(!is.na(TotalDebt) & TotalDebt > 0,
    fifelse(!is.na(ShortTermBorr), ShortTermBorr, 0) / TotalDebt, NA_real_)]
  parsed[, LiabToAssets := .safe_div(TotalLiab, TotalAssets)]
  parsed[, DebtServiceCoverage := fifelse(!is.na(EBITDA) & !is.na(InterestExp) &
    InterestExp > 0, EBITDA / InterestExp, NA_real_)]
  parsed[, EquityRatio := .safe_div(TotalEquity, TotalAssets)]
  parsed[, NonCurrentLiabRatio := .safe_div(NonCurrentLiab, TotalAssets)]
  parsed[, BorrowingDependency := .safe_div(TotalDebt, TotalAssets)]

  # ═══════════════════════════════════════════════════════════════════════
  # D. LIQUIDITY (유동성) — 8 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, CurrentRatio := .safe_div(CurrentAssets, CurrentLiab)]
  parsed[, QuickRatio := fifelse(!is.na(CurrentAssets) & !is.na(CurrentLiab) & CurrentLiab > 0,
    (CurrentAssets - fifelse(!is.na(Inventory), Inventory, 0)) / CurrentLiab, NA_real_)]
  parsed[, CashRatio := .safe_div(CashAndEquiv, CurrentLiab)]
  parsed[, CashToAssets := .safe_div(CashAndEquiv, TotalAssets)]
  parsed[, WCToAssets := .safe_div(WorkingCapital, TotalAssets)]  # Altman X1
  parsed[, CurrentAssetRatio := .safe_div(CurrentAssets, TotalAssets)]
  parsed[, DefensiveInterval := fifelse(!is.na(CashAndEquiv) & !is.na(Revenue) & Revenue > 0,
    CashAndEquiv / (Revenue / 365), NA_real_)]
  parsed[, CashBurnRate := fifelse(!is.na(OperatingCF) & OperatingCF < 0 &
    !is.na(CashAndEquiv) & CashAndEquiv > 0,
    CashAndEquiv / abs(OperatingCF), NA_real_)]

  # ═══════════════════════════════════════════════════════════════════════
  # E. CASH FLOW QUALITY (현금흐름 품질) — 10 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, Accrual := fifelse(!is.na(AvgAssets) & AvgAssets > 0 &
    !is.na(NetIncome) & !is.na(OperatingCF),
    (NetIncome - OperatingCF) / AvgAssets, NA_real_)]
  parsed[, OCFToRevenue := .safe_div(OperatingCF, Revenue)]
  parsed[, OCFToNI := .safe_div(OperatingCF, NetIncome)]
  parsed[, FCFToAssets := .safe_div(FCF, AvgAssets)]
  parsed[, FCFToEquity := .safe_div(FCF, AvgEquity)]
  parsed[, InvestIntensity := fifelse(!is.na(InvestCF) & !is.na(Revenue) & Revenue > 0,
                                       abs(InvestCF) / Revenue, NA_real_)]
  parsed[, FinancingIntensity := fifelse(!is.na(FinanceCF) & !is.na(TotalAssets) & TotalAssets > 0,
                                          FinanceCF / TotalAssets, NA_real_)]
  parsed[, ReinvestmentRate := fifelse(!is.na(InvestCF) & !is.na(OperatingCF) & OperatingCF > 0,
                                        abs(InvestCF) / OperatingCF, NA_real_)]
  parsed[, OCFAccrualGap := fifelse(!is.na(OperatingCF) & !is.na(NetIncome),
                                     OperatingCF - NetIncome, NA_real_)]
  parsed[, CashGenerationEff := .safe_div(OperatingCF, EBITDA)]

  # ═══════════════════════════════════════════════════════════════════════
  # F. ASSET STRUCTURE (자산/부채 구조) — 8 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, TangibleAssetRatio := .safe_div(TangibleAssets, TotalAssets)]
  parsed[, IntangibleAssetRatio := .safe_div(IntangibleAssets, TotalAssets)]
  parsed[, InventoryToAssets := .safe_div(Inventory, TotalAssets)]
  parsed[, ReceivableToAssets := .safe_div(AccountsRecv, TotalAssets)]
  parsed[, NonCurrentToTotal := .safe_div(NonCurrentAssets, TotalAssets)]
  parsed[, CashToCurrentAssets := .safe_div(CashAndEquiv, CurrentAssets)]
  parsed[, RetainedToAssets := .safe_div(RetainedEarnings, TotalAssets)]  # Altman X2
  parsed[, CapitalIntensity := .safe_div(TangibleAssets, Revenue)]

  # ═══════════════════════════════════════════════════════════════════════
  # G. R&D & INNOVATION (연구개발) — 4 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, RandDIntensity := .safe_div(RandD, Revenue)]
  parsed[, RandDToAssets := .safe_div(RandD, TotalAssets)]
  parsed[, RandDToOP := .safe_div(RandD, OperatingProfit)]
  parsed[, RandDToGP := .safe_div(RandD, GrossProfit)]

  # ═══════════════════════════════════════════════════════════════════════
  # H. TAX & DISTRIBUTION (세금/배당) — 6 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, EffectiveTaxRate := fifelse(!is.na(TaxExpense) & !is.na(PretaxIncome) & PretaxIncome > 0,
                                       TaxExpense / PretaxIncome, NA_real_)]
  parsed[, PayoutRatio := fifelse(!is.na(Dividends) & !is.na(NetIncome) & NetIncome > 0,
                                   abs(Dividends) / NetIncome, NA_real_)]
  parsed[, RetentionRatio := fifelse(!is.na(PayoutRatio), 1 - PayoutRatio, NA_real_)]
  parsed[, DividendToAssets := fifelse(!is.na(Dividends) & !is.na(TotalAssets) & TotalAssets > 0,
                                        abs(Dividends) / TotalAssets, NA_real_)]
  parsed[, TaxBurden := .safe_div(NetIncome, PretaxIncome)]
  parsed[, SGR := fifelse(!is.na(ROE) & !is.na(RetentionRatio),
                           ROE * RetentionRatio, ROE)]

  # ═══════════════════════════════════════════════════════════════════════
  # I. COST STRUCTURE (비용 구조) — 5 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, COGSToRevenue := .safe_div(COGS, Revenue)]
  parsed[, SGAToGrossProfit := .safe_div(SGAExpense, GrossProfit)]
  parsed[, DepToAssets := .safe_div(DepAmort, AvgAssets)]
  parsed[, DepToRevenue := .safe_div(DepAmort, Revenue)]
  parsed[, TotalCostRatio := fifelse(!is.na(Revenue) & Revenue > 0 & !is.na(NetIncome),
                                      1 - NetIncome / Revenue, NA_real_)]

  # ═══════════════════════════════════════════════════════════════════════
  # J. DUPONT DECOMPOSITION (듀폰 분해) — 3 indicators
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, DuPont_NPM := NetMargin]
  parsed[, DuPont_AT := AssetTurnover]
  parsed[, DuPont_EM := FinancialLeverage]

  # ═══════════════════════════════════════════════════════════════════════
  # K. GROWTH (성장성) — 12 indicators (YoY changes)
  # ═══════════════════════════════════════════════════════════════════════
  setorder(parsed, Ticker, bsns_year)
  parsed[, AssetGrowth := {
    prev <- shift(TotalAssets)
    (TotalAssets - prev) / ((TotalAssets + prev) / 2)
  }, by = Ticker]
  parsed[, RevenueGrowth := Revenue / shift(Revenue) - 1, by = Ticker]
  parsed[, GrossProfitGrowth := GrossProfit / shift(GrossProfit) - 1, by = Ticker]
  parsed[, OPGrowth := OperatingProfit / shift(OperatingProfit) - 1, by = Ticker]
  parsed[, NIGrowth := NetIncome / shift(NetIncome) - 1, by = Ticker]
  parsed[, EBITDAGrowth := EBITDA / shift(EBITDA) - 1, by = Ticker]
  parsed[, EquityGrowth := {
    prev <- shift(TotalEquity)
    (TotalEquity - prev) / ((TotalEquity + prev) / 2)
  }, by = Ticker]
  parsed[, OCFGrowth := OperatingCF / shift(OperatingCF) - 1, by = Ticker]
  parsed[, InventoryGrowth := Inventory / shift(Inventory) - 1, by = Ticker]
  parsed[, ReceivableGrowth := AccountsRecv / shift(AccountsRecv) - 1, by = Ticker]
  parsed[, DebtGrowth := TotalLiab / shift(TotalLiab) - 1, by = Ticker]
  parsed[, SGAGrowth := SGAExpense / shift(SGAExpense) - 1, by = Ticker]

  # ═══════════════════════════════════════════════════════════════════════
  # L. YoY RATIO CHANGES (비율 변화) — 20 indicators
  # ═══════════════════════════════════════════════════════════════════════
  ratio_delta_cols <- c("GPA", "ROE", "ROA", "OPM", "GrossMargin", "NetMargin",
                         "EBITDA_Margin", "Accrual", "ICR", "DebtRatio",
                         "CurrentRatio", "CashToAssets", "AssetTurnover",
                         "EquityMultiplier", "OCFToRevenue", "SGAEfficiency",
                         "RandDIntensity", "TangibleAssetRatio", "DebtToAssets",
                         "PayoutRatio")
  for (rc in ratio_delta_cols) {
    delta_name <- paste0("Delta_", rc)
    if (rc %in% names(parsed)) {
      parsed[, (delta_name) := get(rc) - shift(get(rc)), by = Ticker]
    }
  }

  # ═══════════════════════════════════════════════════════════════════════
  # M. COMPOSITE SCORES (복합 스코어)
  # ═══════════════════════════════════════════════════════════════════════

  # ── M1. Piotroski F-Score (9 components) ──
  # Ref: Piotroski (2000) JAR
  parsed[, F_ROA_pos := fifelse(!is.na(ROA) & ROA > 0, 1L, 0L)]
  parsed[, F_OCF_pos := fifelse(!is.na(OperatingCF) & OperatingCF > 0, 1L, 0L)]
  parsed[, F_ROA_up := fifelse(!is.na(Delta_ROA) & Delta_ROA > 0, 1L, 0L)]
  parsed[, F_Accrual := fifelse(!is.na(Accrual) & Accrual < 0, 1L, 0L)]  # OCF > NI
  parsed[, F_LTDebt_down := {
    prev_dr <- shift(DebtToAssets)
    fifelse(!is.na(DebtToAssets) & !is.na(prev_dr) & DebtToAssets < prev_dr, 1L, 0L)
  }, by = Ticker]
  parsed[, F_CR_up := {
    prev_cr <- shift(CurrentRatio)
    fifelse(!is.na(CurrentRatio) & !is.na(prev_cr) & CurrentRatio > prev_cr, 1L, 0L)
  }, by = Ticker]
  parsed[, F_NoEquityIssue := 1L]  # Assume no equity issuance (DART 발행주식수 미사용)
  parsed[, F_GM_up := fifelse(!is.na(Delta_GrossMargin) & Delta_GrossMargin > 0, 1L, 0L)]
  parsed[, F_AT_up := fifelse(!is.na(Delta_AssetTurnover) & Delta_AssetTurnover > 0, 1L, 0L)]
  parsed[, PiotroskiF := F_ROA_pos + F_OCF_pos + F_ROA_up + F_Accrual +
                           F_LTDebt_down + F_CR_up + F_NoEquityIssue + F_GM_up + F_AT_up]

  # ── M2. Altman Z-Score (manufacturing version) ──
  # Z = 1.2*X1 + 1.4*X2 + 3.3*X3 + 0.6*X4 + 1.0*X5
  # X4 uses book equity / total liabilities (instead of market cap)
  parsed[, AltmanZ := fifelse(
    !is.na(WCToAssets) & !is.na(RetainedToAssets) & !is.na(EBIT_to_Assets) &
      !is.na(TotalEquity) & !is.na(TotalLiab) & TotalLiab > 0 & !is.na(AssetTurnover),
    1.2 * WCToAssets + 1.4 * RetainedToAssets + 3.3 * EBIT_to_Assets +
      0.6 * (TotalEquity / TotalLiab) + 1.0 * AssetTurnover,
    NA_real_)]
  parsed[, AltmanZone := fifelse(!is.na(AltmanZ),
    fifelse(AltmanZ > 2.99, "safe",
      fifelse(AltmanZ > 1.81, "grey", "distress")), NA_character_)]

  # ── M3. Quality Composite (multi-signal) ──
  parsed[, QualityScore := fifelse(
    !is.na(GPA) & !is.na(Accrual) & !is.na(AssetGrowth),
    frank(GPA, ties.method = "average") / .N -
      frank(abs(Accrual), ties.method = "average") / .N -
      frank(AssetGrowth, ties.method = "average") / .N,
    NA_real_), by = bsns_year]

  # ── M4. Distress Score ──
  parsed[, IsZombie := fifelse(!is.na(ICR) & ICR < 1, TRUE, FALSE)]
  parsed[, IsDistressed := fifelse(
    (!is.na(AltmanZ) & AltmanZ < 1.81) |
      (!is.na(ICR) & ICR < 1) |
      (!is.na(CurrentRatio) & CurrentRatio < 0.5),
    TRUE, FALSE)]

  # ═══════════════════════════════════════════════════════════════════════
  # N. WINSORIZE ALL RATIO COLUMNS
  # ═══════════════════════════════════════════════════════════════════════
  .winsorize <- function(x, lo = 0.01, hi = 0.99) {
    if (all(is.na(x))) return(x)
    q <- quantile(x, c(lo, hi), na.rm = TRUE)
    pmin(pmax(x, q[1]), q[2])
  }

  # All numeric factor columns (excluding raw financials, flags, composites)
  winsorize_cols <- c(
    # Profitability
    "GPA", "ROE", "ROA", "OPM", "GrossMargin", "NetMargin", "EBITDA_Margin",
    "ROIC", "GrossProfit_to_Equity", "EBIT_to_Assets", "OperatingROA", "PreTaxROA",
    "OCF_ROA", "FCF_Margin", "CashEarningsRatio",
    # Efficiency
    "AssetTurnover", "EquityTurnover", "InventoryTurnover", "ReceivablesTurnover",
    "PayablesTurnover", "DaysReceivable", "DaysInventory", "DaysPayable", "CCC",
    "FixedAssetTurnover", "WCTurnover", "SGAEfficiency",
    # Leverage
    "DebtRatio", "DebtToAssets", "LongTermDebtToEquity", "TotalDebtToAssets",
    "NetDebtToEBITDA", "NetDebtToAssets", "EquityMultiplier", "InterestBurden",
    "ICR", "EBITDA_ICR", "NetInterestMargin", "FinancialLeverage",
    "ShortTermDebtRatio", "DebtServiceCoverage", "EquityRatio", "BorrowingDependency",
    # Liquidity
    "CurrentRatio", "QuickRatio", "CashRatio", "CashToAssets", "WCToAssets",
    "CurrentAssetRatio", "DefensiveInterval",
    # Cash Flow
    "Accrual", "OCFToRevenue", "OCFToNI", "FCFToAssets", "FCFToEquity",
    "InvestIntensity", "FinancingIntensity", "ReinvestmentRate", "CashGenerationEff",
    # Structure
    "TangibleAssetRatio", "IntangibleAssetRatio", "InventoryToAssets",
    "ReceivableToAssets", "RetainedToAssets", "CapitalIntensity",
    # R&D
    "RandDIntensity", "RandDToAssets",
    # Tax/Distribution
    "EffectiveTaxRate", "PayoutRatio", "TaxBurden", "SGR",
    # Cost
    "COGSToRevenue", "SGAToGrossProfit", "DepToAssets", "DepToRevenue",
    # Growth
    "AssetGrowth", "RevenueGrowth", "GrossProfitGrowth", "OPGrowth",
    "NIGrowth", "EBITDAGrowth", "EquityGrowth", "OCFGrowth",
    "InventoryGrowth", "ReceivableGrowth", "DebtGrowth", "SGAGrowth"
  )
  # Add Delta columns
  for (rc in ratio_delta_cols) {
    dn <- paste0("Delta_", rc)
    if (dn %in% names(parsed)) winsorize_cols <- c(winsorize_cols, dn)
  }

  for (col in winsorize_cols) {
    if (col %in% names(parsed)) {
      parsed[, (col) := .winsorize(get(col)), by = bsns_year]
    }
  }

  # ═══════════════════════════════════════════════════════════════════════
  # O. DATE MAPPING & FINAL OUTPUT
  # ═══════════════════════════════════════════════════════════════════════
  parsed[, Factor_Date := as.Date(paste0(bsns_year + 1, "-03-31"))]

  # Collect all computed columns dynamically
  raw_cols <- c("Ticker", "bsns_year", "Factor_Date",
                "Revenue", "COGS", "GrossProfit", "SGAExpense", "OperatingProfit",
                "PretaxIncome", "TaxExpense", "NetIncome", "InterestExp", "InterestIncome",
                "DepAmort", "RandD", "EBITDA", "EBIT", "NOPAT",
                "TotalAssets", "CurrentAssets", "NonCurrentAssets", "CashAndEquiv",
                "Inventory", "AccountsRecv", "TangibleAssets", "IntangibleAssets",
                "TotalLiab", "CurrentLiab", "NonCurrentLiab", "ShortTermBorr", "LongTermBorr",
                "AccountsPay", "TotalEquity", "CapitalStock", "RetainedEarnings",
                "OperatingCF", "InvestCF", "FinanceCF", "Dividends",
                "WorkingCapital", "TotalDebt", "NetDebt", "FCF")

  ratio_cols <- c(winsorize_cols,
                  "PiotroskiF", "AltmanZ", "AltmanZone", "QualityScore",
                  "IsZombie", "IsDistressed",
                  # F-Score components
                  "F_ROA_pos", "F_OCF_pos", "F_ROA_up", "F_Accrual",
                  "F_LTDebt_down", "F_CR_up", "F_GM_up", "F_AT_up",
                  # DuPont
                  "DuPont_NPM", "DuPont_AT", "DuPont_EM",
                  # Other
                  "RetentionRatio", "CashBurnRate", "LiabToAssets", "NonCurrentLiabRatio",
                  "NonCurrentToTotal", "CashToCurrentAssets", "OCFAccrualGap",
                  "DividendToAssets", "TotalCostRatio", "RandDToOP", "RandDToGP")

  all_out_cols <- unique(c(raw_cols, ratio_cols))
  # Keep only columns that actually exist
  all_out_cols <- all_out_cols[all_out_cols %in% names(parsed)]

  factor_dt <- parsed[, ..all_out_cols]

  # Count indicators
  n_raw <- sum(all_out_cols %in% c("Ticker", "bsns_year", "Factor_Date",
    "Revenue", "COGS", "GrossProfit", "SGAExpense", "OperatingProfit",
    "PretaxIncome", "TaxExpense", "NetIncome", "InterestExp", "InterestIncome",
    "DepAmort", "RandD", "TotalAssets", "CurrentAssets", "NonCurrentAssets",
    "CashAndEquiv", "Inventory", "AccountsRecv", "TangibleAssets", "IntangibleAssets",
    "TotalLiab", "CurrentLiab", "NonCurrentLiab", "ShortTermBorr", "LongTermBorr",
    "AccountsPay", "TotalEquity", "CapitalStock", "RetainedEarnings",
    "OperatingCF", "InvestCF", "FinanceCF", "Dividends"))
  n_derived <- length(all_out_cols) - n_raw

  # Parquet 저장
  write_parquet(factor_dt, DART_FACTOR_CACHE)
  cat(sprintf("[dart] Fundamental factors saved: %d rows | %d tickers | %d years\n",
              nrow(factor_dt), uniqueN(factor_dt$Ticker),
              uniqueN(factor_dt$bsns_year)))
  cat(sprintf("[dart] Total columns: %d (raw: %d, derived indicators: %d)\n",
              length(all_out_cols), n_raw, n_derived))
  cat(sprintf("[dart] Cache: %s\n", DART_FACTOR_CACHE))

  # 커버리지 리포트 (주요 지표만)
  key_factors <- c("GPA", "ROE", "ROA", "OPM", "GrossMargin", "NetMargin",
                    "EBITDA_Margin", "ROIC", "AssetTurnover", "CurrentRatio",
                    "DebtRatio", "ICR", "Accrual", "CashToAssets",
                    "AssetGrowth", "RevenueGrowth", "PiotroskiF", "AltmanZ",
                    "RandDIntensity", "PayoutRatio", "CCC", "FCFToAssets")
  cat("\n[dart] Key Factor Coverage:\n")
  for (col in key_factors) {
    if (col %in% names(factor_dt)) {
      pct <- round(mean(!is.na(factor_dt[[col]])) * 100, 1)
      cat(sprintf("  %-20s: %5.1f%%\n", col, pct))
    }
  }

  invisible(factor_dt)
}


#==============================================================================
# 5. Quick Load — 캐시에서 펀더멘털 팩터 로드
#==============================================================================

load_dart_fundamentals <- function() {
  if (!file.exists(DART_FACTOR_CACHE)) {
    stop("[dart] Fundamental cache not found. Run dart_compute_factors() first.\n",
         "  Or run full pipeline: dart_update_corpcode() → dart_fetch_all() → dart_compute_factors()")
  }
  as.data.table(read_parquet(DART_FACTOR_CACHE))
}


#==============================================================================
# 6. Merge with RAWDATA — 시그널 날짜에 펀더멘털 데이터 붙이기
#==============================================================================

merge_fundamentals_to_signals <- function(FACTORS, fundamental_dt = NULL) {
  if (is.null(fundamental_dt)) fundamental_dt <- load_dart_fundamentals()

  # FACTORS의 Date (월말 시그널)에 가장 최근 사용 가능한 펀더멘털 매칭
  # Factor_Date = 사업연도+1의 3/31 → 이 날짜 이후 시그널부터 사용
  # All columns except raw BS/IS/CF items — keep ratios and composites
  exclude_cols <- c("bsns_year")
  keep_cols <- setdiff(names(fundamental_dt), exclude_cols)
  fund_long <- fundamental_dt[, ..keep_cols]

  # Rolling join: 각 (Ticker, Signal_Date)에 대해
  # Factor_Date <= Signal_Date인 가장 최근 레코드 매칭
  setkey(fund_long, Ticker, Factor_Date)
  setkey(FACTORS, Ticker, Date)

  merged <- fund_long[FACTORS, roll = TRUE, on = .(Ticker, Factor_Date = Date)]
  setnames(merged, "Factor_Date", "Date")

  cat(sprintf("[dart] Merged fundamentals: %d of %d signals matched\n",
              sum(!is.na(merged$GPA)), nrow(merged)))

  merged
}


#==============================================================================
# 7. Master Pipeline — 전체 수집 + 팩터 계산
#==============================================================================

dart_run_pipeline <- function(years = 2018:2025, force_corpcode = FALSE) {
  cat("═══════════════════════════════════════════════\n")
  cat("[dart] Starting full DART data pipeline\n")
  cat("═══════════════════════════════════════════════\n\n")

  # Step 1: Corp code mapping
  cat("── Step 1: Corp code mapping ──\n")
  dart_update_corpcode(force = force_corpcode)

  # Step 2: Fetch financial statements
  cat("\n── Step 2: Fetch financial statements ──\n")
  dart_fetch_all(years = years)

  # Step 3: Compute factors
  cat("\n── Step 3: Compute fundamental factors ──\n")
  dart_compute_factors()

  cat("\n═══════════════════════════════════════════════\n")
  cat("[dart] Pipeline complete!\n")
  cat("═══════════════════════════════════════════════\n")
}
