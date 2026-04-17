#==============================================================================
# parse_investor_quantiwise.R — QuantiWise 거래주체 데이터 파서
#
# 03_Universe/Investor_Act.xlsx → .cache/investor_stock/ (종목별 거래주체 DB)
#
# QT_to_xts 함수 활용: read.xlsx(startRow=8) → QT_to_xts 변환 → long melt → parquet
#
# 4개 시트:
#   외인:     외국인총합계 순매수대금(일간)
#   기관:     기관 순매수대금(일간)
#   개인:     개인 순매수대금(일간)
#   기타법인: 기타법인 순매수수량(일간)
#
# Usage:
#   source("02_Infrastructure/parse_investor_quantiwise.R")
#   parse_investor_act()  # 전체 파싱 (시트 4개 → 통합 parquet)
#   inv <- load_investor_stock("wide")  # 전략에서 사용
#==============================================================================

suppressPackageStartupMessages({
  library(openxlsx)
  library(data.table)
  library(xts)
  library(arrow)
  library(dplyr)
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

source(file.path(PROJECT_ROOT, "02_Infrastructure", "F1. QT_to_xts.r"))

`%||%` <- function(a, b) if (!is.null(a)) a else b

INVESTOR_XLSX  <- file.path(RAWDATA_PATH, "Investor_Act.xlsx")
INVESTOR_CACHE <- if (exists("INVESTOR_CACHE")) INVESTOR_CACHE else file.path(CACHE_DIR, "investor_stock")

#==============================================================================
# QT_to_xts_investor() — Investor_Act 전용 변환 (헤더 6행 제거)
#
# startRow=8 이후 데이터:
#   Row 1: Name (종목명)
#   Row 2: Item Code (U130320 등)
#   Row 3: Unit (Local)
#   Row 4: Base Date
#   Row 5: (empty)
#   Row 6: D A T E header
#   Row 7+: 실제 데이터
#==============================================================================
QT_to_xts_investor <- function(x) {
  # 첫 6행 제거 (Name, ItemCode, Unit, BaseDate, Empty, "D A T E" header)
  x <- x[-1:-6, ]
  x <- x %>% dplyr::rename("DATE" = 'Code')

  x <- apply(x, 2, as.numeric) %>% as.data.frame()
  x$DATE <- as.Date(x$DATE, origin = "1899-12-30")

  rownames(x) <- x$DATE
  x <- x[, -1]
  x <- as.xts(x)
  x
}

#==============================================================================
# parse_one_sheet() — 시트 하나 읽기 → long-format data.table
#==============================================================================
parse_one_sheet <- function(xlsx_path, sheet_name, investor_type) {
  cat(sprintf("[investor_parser] Reading sheet '%s'...\n", sheet_name))
  t0 <- Sys.time()

  # openxlsx::read.xlsx (검증된 QT 파이프라인)
  raw_df <- read.xlsx(xlsx_path, sheet = sheet_name, startRow = 8,
                      skipEmptyCols = TRUE, na.strings = "NA")
  cat(sprintf("  raw: %d rows x %d cols\n", nrow(raw_df), ncol(raw_df)))

  # QT 변환 → xts
  xts_obj <- QT_to_xts_investor(raw_df)
  rm(raw_df); gc()

  cat(sprintf("  xts: %d dates x %d stocks (%s ~ %s)\n",
              nrow(xts_obj), ncol(xts_obj),
              index(xts_obj)[1], tail(index(xts_obj), 1)))

  # data.table 변환
  dt <- as.data.table(xts_obj)
  setnames(dt, "index", "Date")
  dt[, Date := as.Date(Date)]
  rm(xts_obj); gc()

  # Melt wide → long (Ticker = RAWDATA와 동일한 칼럼명)
  cat("  Melting wide → long...\n")
  stock_cols <- setdiff(names(dt), "Date")
  long <- melt(dt, id.vars = "Date",
               measure.vars = stock_cols,
               variable.name = "Ticker",
               value.name = "NetBuy",
               variable.factor = FALSE)
  rm(dt); gc()

  # NA & 0 제거
  long <- long[!is.na(NetBuy) & NetBuy != 0]
  long[, InvestorType := investor_type]

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  cat(sprintf("  완료: %s rows (%.1f분)\n",
              format(nrow(long), big.mark = ","), elapsed))
  long
}

#==============================================================================
# parse_investor_act() — 메인 파서
#==============================================================================
parse_investor_act <- function(
    xlsx_path = INVESTOR_XLSX,
    output_dir = INVESTOR_CACHE,
    start_date = NULL,
    sheets = c("외인", "기관", "개인", "기타법인")
) {
  if (!file.exists(xlsx_path)) {
    stop("[investor_parser] File not found: ", xlsx_path)
  }
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  cat(sprintf("[investor_parser] Parsing %s\n", basename(xlsx_path)))
  cat(sprintf("[investor_parser] Output: %s\n", output_dir))

  sheet_map <- list(
    "외인"     = "Foreign",
    "기관"     = "Institutional",
    "개인"     = "Individual",
    "기타법인" = "OtherCorp"
  )

  all_data <- list()

  for (s in sheets) {
    inv_type <- sheet_map[[s]]
    if (is.null(inv_type)) next

    result <- tryCatch(
      parse_one_sheet(xlsx_path, s, inv_type),
      error = function(e) {
        cat(sprintf("[investor_parser] ERROR on '%s': %s\n", s, e$message))
        NULL
      }
    )

    if (!is.null(result)) {
      if (!is.null(start_date)) result <- result[Date >= as.Date(start_date)]
      all_data[[inv_type]] <- result

      # 시트별 parquet 저장
      pq_path <- file.path(output_dir, sprintf("investor_%s.parquet", tolower(inv_type)))
      write_parquet(result, pq_path)
      cat(sprintf("[investor_parser] Saved: %s (%s bytes)\n",
                  basename(pq_path), format(file.size(pq_path), big.mark = ",")))
    }
    gc()
  }

  if (length(all_data) == 0) {
    cat("[investor_parser] ERROR: No data parsed!\n")
    return(invisible(NULL))
  }

  # 통합 (long format)
  combined <- rbindlist(all_data, use.names = TRUE)
  setkey(combined, Date, Ticker, InvestorType)
  pq_all <- file.path(output_dir, "investor_all.parquet")
  write_parquet(combined, pq_all)
  cat(sprintf("\n[investor_parser] Combined long: %s rows → %s\n",
              format(nrow(combined), big.mark = ","), basename(pq_all)))

  # Wide format (Date, StockCode, Foreign, Institutional, Individual, OtherCorp)
  cat("[investor_parser] Creating wide format...\n")
  wide <- dcast(combined, Date + Ticker ~ InvestorType,
                value.var = "NetBuy", fill = 0)
  pq_wide <- file.path(output_dir, "investor_wide.parquet")
  write_parquet(wide, pq_wide)
  cat(sprintf("[investor_parser] Wide: %s rows → %s (%s bytes)\n",
              format(nrow(wide), big.mark = ","), basename(pq_wide),
              format(file.size(pq_wide), big.mark = ",")))

  # 요약 통계
  cat("\n[investor_parser] === 요약 ===\n")
  cat(sprintf("  기간: %s ~ %s\n", min(combined$Date), max(combined$Date)))
  cat(sprintf("  종목 수: %d\n", uniqueN(combined$Ticker)))
  cat(sprintf("  총 레코드: %s\n", format(nrow(combined), big.mark = ",")))

  type_summary <- combined[, .(
    N = .N,
    Stocks = uniqueN(Ticker),
    From = min(Date),
    To = max(Date)
  ), by = InvestorType]
  print(type_summary)

  # 최근 데이터 샘플
  cat(sprintf("\n[investor_parser] 최근 데이터 샘플 (%s):\n", max(wide$Date)))
  recent <- wide[Date == max(Date)]
  if (nrow(recent) > 0) {
    cat(sprintf("  거래 종목: %d\n", nrow(recent)))
    if ("Foreign" %in% names(recent)) {
      top5 <- head(recent[order(-Foreign)], 5)
      cat("  외국인 순매수 Top 5:\n")
      for (i in 1:nrow(top5)) {
        cat(sprintf("    %s: %s원\n", top5$Ticker[i],
                    format(top5$Foreign[i], big.mark = ",")))
      }
    }
  }

  invisible(list(combined = combined, wide = wide))
}

#==============================================================================
# load_investor_stock() — 파싱된 데이터 로드 (전략에서 사용)
#==============================================================================
load_investor_stock <- function(
    fmt = c("wide", "long", "foreign", "institutional", "individual"),
    start_date = NULL,
    end_date = NULL,
    cache_dir = INVESTOR_CACHE
) {
  fmt <- match.arg(fmt)

  pq_file <- switch(fmt,
    wide = file.path(cache_dir, "investor_wide.parquet"),
    long = file.path(cache_dir, "investor_all.parquet"),
    foreign = file.path(cache_dir, "investor_foreign.parquet"),
    institutional = file.path(cache_dir, "investor_institutional.parquet"),
    individual = file.path(cache_dir, "investor_individual.parquet")
  )

  if (!file.exists(pq_file)) {
    stop("[investor] Parquet not found: ", pq_file,
         "\n  Run parse_investor_act() first.")
  }

  dt <- as.data.table(read_parquet(pq_file))
  if (!is.null(start_date)) dt <- dt[Date >= as.Date(start_date)]
  if (!is.null(end_date)) dt <- dt[Date <= as.Date(end_date)]

  cat(sprintf("[investor] Loaded %s: %s rows (%s ~ %s)\n",
              fmt, format(nrow(dt), big.mark = ","),
              min(dt$Date), max(dt$Date)))
  dt
}

cat("[investor_parser] Loaded.\n")
cat("[investor_parser] Functions: parse_investor_act(), load_investor_stock()\n")
