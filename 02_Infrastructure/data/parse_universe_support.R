#==============================================================================
# parse_universe_support.R — QuantiWise Universe_Support 파서
#
# 03_Universe/Universe_Support.xlsx → .cache/universe_support/ (시트별 parquet)
#
# QT_to_xts 함수 활용: read.xlsx(startRow=8) → QT_to_xts 변환 → long melt → parquet
#
# 8개 시트:
#   Sector_Lv1    — WI26 대분류 (character)
#   Sector_Lv2    — WI26 중분류 (character)
#   Float         — 유동비율 (numeric, 0~1)
#   K200          — KOSPI 200 멤버십 (0/1)
#   KQ150         — KOSDAQ 150 멤버십 (0/1)
#   거래정지      — 거래 정지 여부 (0/1)
#   관리종목      — 관리종목 여부 (0/1)
#   불성실공시    — 불성실공시 여부 (0/1)
#
# QT 레이아웃 (startRow=8 기준):
#   Row 1 (sheet row 8): 종목코드 행 (A000010 포맷)
#   Row 1~5 이전: 헤더/메타 — QT_to_xts()가 내부적으로 [-1:-5] 제거
#   Columns: 영업일 월말 날짜 (Excel 직렬 숫자 → Date 변환)
#
# Usage:
#   source("02_Infrastructure/parse_universe_support.R")
#   parse_universe_support()          # 전체 8시트 파싱
#   us <- load_universe_support()     # wide format data.table 로드
#==============================================================================

suppressPackageStartupMessages({
  library(openxlsx)
  library(data.table)
  library(xts)
  library(arrow)
  library(dplyr)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

if (!exists("PROJECT_ROOT")) {
  tryCatch(
    source(file.path(dirname(dirname(sys.frame(1)$ofile)), "config.R")),
    error = function(e) {
      source(file.path(
        Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
        "02_Infrastructure", "config.R"
      ))
    }
  )
}

source(file.path(FUNC_PATH, "F1. QT_to_xts.r"))

#==============================================================================
# 시트 메타데이터 정의
#   cache_name  : 저장 파일명 (parquet suffix)
#   value_type  : "character" 또는 "numeric"
#   value_col   : 출력 data.table의 Value 컬럼 의미 (문서화용)
#==============================================================================
UNIVERSE_SUPPORT_SHEET_META <- list(
  Sector_Lv1 = list(
    cache_name = "sector_lv1",
    value_type = "character",
    value_col  = "Sector_Lv1"
  ),
  Sector_Lv2 = list(
    cache_name = "sector_lv2",
    value_type = "character",
    value_col  = "Sector_Lv2"
  ),
  `유동주식비율` = list(
    cache_name = "float",
    value_type = "numeric",
    value_col  = "Float"
  ),
  K200 = list(
    cache_name = "k200",
    value_type = "numeric",
    value_col  = "K200"
  ),
  KQ150 = list(
    cache_name = "kq150",
    value_type = "numeric",
    value_col  = "KQ150"
  ),
  `거래정지` = list(
    cache_name = "trading_halt",
    value_type = "numeric",
    value_col  = "TradingHalt"
  ),
  `관리종목` = list(
    cache_name = "admin_stock",
    value_type = "numeric",
    value_col  = "AdminStock"
  ),
  `불성실공시법인` = list(
    cache_name = "unfaithful_disc",
    value_type = "numeric",
    value_col  = "UnfaithfulDisc"
  )
)

#==============================================================================
# QT_to_xts_char() — 문자형 시트 전용 변환 (sector 등)
#
# QT_to_xts()는 apply(x, 2, as.numeric)으로 모두 숫자 변환 → 문자값 소실.
# 문자형 시트는 숫자 변환 없이 DATE 열만 처리.
#==============================================================================
QT_to_dt_char <- function(x) {
  # 첫 5행 제거 (QT_to_xts와 동일한 오프셋)
  x <- x[-1:-5, ]

  # 첫 번째 컬럼 → DATE
  date_col <- names(x)[1]
  dates <- suppressWarnings(as.numeric(x[[date_col]]))
  dates <- as.Date(dates, origin = "1899-12-30")

  # data.table 변환 (xts 우회 — character 데이터 보존)
  dt <- as.data.table(x[, -1, drop = FALSE])
  dt[, Date := dates]

  # 컬럼명을 Ticker로 유지
  dt
}

#==============================================================================
# parse_one_us_sheet() — 시트 하나 읽기 → long-format data.table
#
#   sheet_name  : Excel 시트명
#   meta        : UNIVERSE_SUPPORT_SHEET_META[[sheet_name]]
#   xlsx_path   : Universe_Support.xlsx 경로
#==============================================================================
parse_one_us_sheet <- function(xlsx_path, sheet_name, meta) {
  cat(sprintf("[universe_support] Reading sheet '%s' (%s)...\n",
              sheet_name, meta$value_type))
  t0 <- Sys.time()

  # openxlsx read (startRow=8: QT 표준 — Row 1~7 = 헤더/메타)
  raw_df <- tryCatch(
    read.xlsx(xlsx_path, sheet = sheet_name, startRow = 8,
              skipEmptyCols = TRUE, na.strings = c("NA", "")),
    error = function(e) {
      cat(sprintf("[universe_support] ERROR reading '%s': %s\n",
                  sheet_name, e$message))
      return(NULL)
    }
  )
  if (is.null(raw_df) || nrow(raw_df) == 0) return(NULL)

  cat(sprintf("  raw: %d rows x %d cols\n", nrow(raw_df), ncol(raw_df)))

  # QT 변환
  if (meta$value_type == "character") {
    # character 시트: xts 우회 → 직접 data.table
    dt <- QT_to_dt_char(raw_df)
    rm(raw_df); gc()
    n_dates <- uniqueN(dt$Date)
    stock_cols <- setdiff(names(dt), "Date")
    cat(sprintf("  dt: %d dates x %d stocks (%s ~ %s)\n",
                n_dates, length(stock_cols), min(dt$Date), max(dt$Date)))
  } else {
    # numeric 시트: 기존 QT_to_xts 사용
    xts_obj <- QT_to_xts(raw_df)
    rm(raw_df); gc()
    n_dates <- nrow(xts_obj)
    n_stocks <- ncol(xts_obj)
    date_rng <- paste(index(xts_obj)[1], "~", tail(index(xts_obj), 1))
    cat(sprintf("  xts: %d dates x %d stocks (%s)\n",
                n_dates, n_stocks, date_rng))
    dt <- as.data.table(xts_obj)
    setnames(dt, "index", "Date")
    dt[, Date := as.Date(Date)]
  }

  # Melt wide → long: (Date, Ticker, Value)
  cat("  Melting wide → long...\n")
  stock_cols <- setdiff(names(dt), "Date")

  long <- melt(
    dt,
    id.vars      = "Date",
    measure.vars = stock_cols,
    variable.name = "Ticker",
    value.name    = "Value",
    variable.factor = FALSE
  )
  rm(dt); gc()

  # 타입 강제
  if (meta$value_type == "numeric") {
    long[, Value := suppressWarnings(as.numeric(Value))]
    # NA 및 무효값 제거
    long <- long[!is.na(Value)]
  } else {
    long[, Value := as.character(Value)]
    # NA-유사 문자값 제거
    long <- long[!is.na(Value) & Value != "" & Value != "NA"]
  }

  setkey(long, Date, Ticker)

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  cat(sprintf("  완료: %s rows (%.1f분)\n",
              format(nrow(long), big.mark = ","), elapsed))
  long
}

#==============================================================================
# parse_universe_support() — 메인 파서
#
#   xlsx_path  : Universe_Support.xlsx 경로 (기본값: config.R 경로)
#   output_dir : 캐시 저장 디렉토리
#   sheets     : 파싱할 시트명 벡터 (기본값: 전체 8시트)
#   force      : TRUE면 기존 캐시 무시 후 재파싱
#==============================================================================
parse_universe_support <- function(
    xlsx_path  = UNIVERSE_SUPPORT_XLSX,
    output_dir = UNIVERSE_SUPPORT_CACHE,
    sheets     = names(UNIVERSE_SUPPORT_SHEET_META),
    force      = FALSE
) {
  # 파일 존재 확인 (defensive)
  if (!file.exists(xlsx_path)) {
    cat(sprintf(
      "[universe_support] XLSX not found: %s\n",
      xlsx_path
    ))
    cat("[universe_support] Place Universe_Support.xlsx in 03_Universe/ and re-run.\n")
    return(invisible(NULL))
  }

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat(sprintf("[universe_support] Created cache dir: %s\n", output_dir))
  }

  cat(sprintf("[universe_support] Parsing: %s\n", basename(xlsx_path)))
  cat(sprintf("[universe_support] Output:  %s\n", output_dir))
  cat(sprintf("[universe_support] Sheets:  %s\n", paste(sheets, collapse = ", ")))
  cat("\n")

  results <- list()

  for (s in sheets) {
    meta <- UNIVERSE_SUPPORT_SHEET_META[[s]]
    if (is.null(meta)) {
      cat(sprintf("[universe_support] WARN: '%s' not in meta, skipping.\n", s))
      next
    }

    pq_path <- file.path(output_dir,
                         sprintf("us_%s.parquet", meta$cache_name))

    # 캐시 히트 확인
    if (!force && file.exists(pq_path)) {
      cat(sprintf("[universe_support] Cache hit: %s — skipping.\n",
                  basename(pq_path)))
      next
    }

    result <- tryCatch(
      parse_one_us_sheet(xlsx_path, s, meta),
      error = function(e) {
        cat(sprintf("[universe_support] ERROR on '%s': %s\n", s, e$message))
        NULL
      }
    )

    if (!is.null(result) && nrow(result) > 0) {
      write_parquet(result, pq_path)
      cat(sprintf("[universe_support] Saved: %s (%s bytes)\n",
                  basename(pq_path),
                  format(file.size(pq_path), big.mark = ",")))
      results[[meta$cache_name]] <- result
    }

    gc()
  }

  if (length(results) == 0) {
    cached <- list.files(output_dir, pattern = "^us_.*\\.parquet$")
    if (length(cached) > 0) {
      cat(sprintf("[universe_support] All %d sheets served from cache.\n",
                  length(cached)))
    } else {
      cat("[universe_support] WARNING: No data parsed and no cache found.\n")
    }
    return(invisible(NULL))
  }

  # 요약 출력
  cat("\n[universe_support] === 파싱 완료 요약 ===\n")
  for (nm in names(results)) {
    dt <- results[[nm]]
    cat(sprintf("  %-20s %s rows | %d tickers | %s ~ %s\n",
                nm,
                format(nrow(dt), big.mark = ","),
                uniqueN(dt$Ticker),
                min(dt$Date),
                max(dt$Date)))
  }

  invisible(results)
}

#==============================================================================
# load_universe_support() — 파싱된 데이터 wide-format 로드
#
# 전체 8개 parquet을 로드 후 (Date, Ticker) 기준으로 wide join.
# 컬럼명: Date, Ticker, Sector_Lv1, Sector_Lv2, Float, K200, KQ150,
#          TradingHalt, AdminStock, UnfaithfulDisc
#
#   start_date  : 로드 시작일 (NULL = 전체)
#   end_date    : 로드 종료일 (NULL = 전체)
#   cache_dir   : 캐시 디렉토리 (기본값: UNIVERSE_SUPPORT_CACHE)
#   sheets      : 로드할 시트 key 목록 (기본값: 전체)
#   fill_char   : 문자열 NA 대체값 (기본값: NA_character_)
#   fill_num    : 숫자 NA 대체값 (기본값: NA_real_)
#==============================================================================
load_universe_support <- function(
    start_date = NULL,
    end_date   = NULL,
    cache_dir  = UNIVERSE_SUPPORT_CACHE,
    sheets     = names(UNIVERSE_SUPPORT_SHEET_META),
    fill_char  = NA_character_,
    fill_num   = NA_real_
) {
  meta_list <- UNIVERSE_SUPPORT_SHEET_META[sheets]

  loaded <- list()

  for (s in sheets) {
    meta <- UNIVERSE_SUPPORT_SHEET_META[[s]]
    if (is.null(meta)) next

    pq_path <- file.path(cache_dir,
                         sprintf("us_%s.parquet", meta$cache_name))

    if (!file.exists(pq_path)) {
      cat(sprintf("[universe_support] Parquet missing: %s\n",
                  basename(pq_path)))
      cat("[universe_support] Run parse_universe_support() first.\n")
      next
    }

    dt <- tryCatch(
      as.data.table(read_parquet(pq_path)),
      error = function(e) {
        cat(sprintf("[universe_support] ERROR loading %s: %s\n",
                    basename(pq_path), e$message))
        NULL
      }
    )
    if (is.null(dt)) next

    dt[, Date := as.Date(Date)]

    # 날짜 필터
    if (!is.null(start_date)) dt <- dt[Date >= as.Date(start_date)]
    if (!is.null(end_date))   dt <- dt[Date <= as.Date(end_date)]

    # Value 컬럼을 의미있는 이름으로 변경
    setnames(dt, "Value", meta$value_col)

    loaded[[meta$value_col]] <- dt
    cat(sprintf("[universe_support] Loaded %-20s : %s rows\n",
                meta$value_col,
                format(nrow(dt), big.mark = ",")))
  }

  if (length(loaded) == 0) {
    cat("[universe_support] No data loaded. Returning NULL.\n")
    return(invisible(NULL))
  }

  # (Date, Ticker) 기준 full outer join으로 wide format 조립
  cat("[universe_support] Joining to wide format...\n")
  wide <- Reduce(
    function(a, b) merge(a, b, by = c("Date", "Ticker"), all = TRUE),
    loaded
  )
  setkey(wide, Date, Ticker)

  # 컬럼 순서 정렬: Date, Ticker, 나머지
  col_order <- c(
    "Date", "Ticker",
    intersect(
      c("Sector_Lv1", "Sector_Lv2", "Float",
        "K200", "KQ150", "TradingHalt", "AdminStock", "UnfaithfulDisc"),
      names(wide)
    )
  )
  setcolorder(wide, col_order)

  cat(sprintf("[universe_support] Wide: %s rows x %d cols | %d tickers\n",
              format(nrow(wide), big.mark = ","),
              ncol(wide),
              uniqueN(wide$Ticker)))

  if (!is.null(start_date) || !is.null(end_date)) {
    cat(sprintf("[universe_support] Date range: %s ~ %s\n",
                min(wide$Date), max(wide$Date)))
  }

  wide
}

#==============================================================================
# load_us_sheet() — 단일 시트 long-format 로드 (경량 접근)
#
#   sheet_key   : UNIVERSE_SUPPORT_SHEET_META의 키명 (예: "K200", "Float")
#==============================================================================
load_us_sheet <- function(
    sheet_key,
    start_date = NULL,
    end_date   = NULL,
    cache_dir  = UNIVERSE_SUPPORT_CACHE
) {
  meta <- UNIVERSE_SUPPORT_SHEET_META[[sheet_key]]
  if (is.null(meta)) {
    stop("[universe_support] Unknown sheet_key: ", sheet_key,
         "\n  Valid keys: ", paste(names(UNIVERSE_SUPPORT_SHEET_META),
                                   collapse = ", "))
  }

  pq_path <- file.path(cache_dir, sprintf("us_%s.parquet", meta$cache_name))

  if (!file.exists(pq_path)) {
    stop("[universe_support] Parquet not found: ", pq_path,
         "\n  Run parse_universe_support() first.")
  }

  dt <- as.data.table(read_parquet(pq_path))
  dt[, Date := as.Date(Date)]

  if (!is.null(start_date)) dt <- dt[Date >= as.Date(start_date)]
  if (!is.null(end_date))   dt <- dt[Date <= as.Date(end_date)]

  setnames(dt, "Value", meta$value_col)
  setkey(dt, Date, Ticker)

  cat(sprintf("[universe_support] Loaded %s: %s rows (%s ~ %s)\n",
              sheet_key,
              format(nrow(dt), big.mark = ","),
              min(dt$Date), max(dt$Date)))
  dt
}

cat("[universe_support] Loaded.\n")
cat("[universe_support] Functions:\n")
cat("  parse_universe_support()  — XLSX → parquet (8 sheets)\n")
cat("  load_universe_support()   — wide data.table (all sheets joined)\n")
cat("  load_us_sheet(sheet_key)  — single sheet long data.table\n")
cat("  Sheet keys: ",
    paste(names(UNIVERSE_SUPPORT_SHEET_META), collapse = ", "), "\n")
