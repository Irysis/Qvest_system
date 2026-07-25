###############################################################################
# parse_fundamental_xlsx.R
# QuantiWise Fundamental.xlsx → Parquet DB 변환
#
# 출력:
#   .cache/fundamental_xlsx.parquet      — 전 시트 long-format (분기)
#   .cache/fundamental_xlsx_ttm.parquet  — TTM 변환 (P/L,CF=4Q합산, B/S=최신값)
#   .cache/shares_issued.parquet         — ISSD (보통주수정기말발행주식수)
#   .cache/stock_buyback.parquet         — SBB  (보통주기중취득자기주식수)
#   .cache/fundamental_merged.parquet    — DART(연간 2015~) + XLSX(분기 1998~) 병합
###############################################################################

suppressPackageStartupMessages({
  library(data.table)
  library(openxlsx)
  library(arrow)
  library(lubridate)
})

# ─── 한글→영문 매핑 ──────────────────────────────────────────────────────────
KR_EN_MAP <- c(
  "매출액"           = "Revenue",

"매출원가"         = "COGS",
  "매출총이익"       = "GrossProfit",
  "판관비"           = "SGAExpense",
  "영업이익"         = "OperatingProfit",
  "세전이익"         = "PretaxIncome",
  "법인세비용"       = "TaxExpense",
  "이자비용"         = "InterestExp",
  "순이자비용"       = "NetInterestExp",
  "총순이자비용"     = "TotalNetInterestExp",
  "이자수익"         = "InterestIncome",
  "감가상각비"       = "DepAmort",
  "연구개발비"       = "RandD",
  "경상연구개발비"   = "OrdRandD",
  "자산총계"         = "TotalAssets",
  "유동자산"         = "CurrentAssets",
  "비유동자산"       = "NonCurrentAssets",
  "현금및현금성자산" = "CashAndEquiv",
  "재고자산"         = "Inventory",
  "매출채권"         = "AccountsRecv",
  "장기매출채권"     = "LongTermRecv",
  "유형자산"         = "TangibleAssets",
  "무형자산"         = "IntangibleAssets",
  "부채총계"         = "TotalLiab",
  "유동부채"         = "CurrentLiab",
  "비유동부채"       = "NonCurrentLiab",
  "단기차입금"       = "ShortTermBorr",
  "장기차입금"       = "LongTermBorr",
  "매입채무"         = "AccountsPay",
  "장기매입채무"     = "LongTermPay",
  "자본총계"         = "TotalEquity",
  "자본금"           = "CapitalStock",
  "이익잉여금"       = "RetainedEarnings",
  "영업활동현금흐름" = "OperatingCF",
  "투자활동현금흐름" = "InvestCF",
  "재무활동현금흐름" = "FinanceCF",
  "배당금지급액"     = "Dividends",
  "FCF1"             = "FCF1",
  "FCF2"             = "FCF2",
  "ISSD"             = "ISSD",
  "SBB"              = "SBB"
)

# ─── P/L, CF 항목 (TTM = 4분기 합산) vs B/S 항목 (TTM = 최신값) ─────────────
PL_CF_ITEMS <- c(
  "Revenue", "COGS", "GrossProfit", "SGAExpense", "OperatingProfit",
  "PretaxIncome", "TaxExpense", "InterestExp", "NetInterestExp",
  "TotalNetInterestExp", "InterestIncome", "DepAmort", "RandD", "OrdRandD",
  "OperatingCF", "InvestCF", "FinanceCF", "Dividends", "FCF1", "FCF2"
)

BS_ITEMS <- c(
  "TotalAssets", "CurrentAssets", "NonCurrentAssets", "CashAndEquiv",
  "Inventory", "AccountsRecv", "LongTermRecv", "TangibleAssets",
  "IntangibleAssets", "TotalLiab", "CurrentLiab", "NonCurrentLiab",
  "ShortTermBorr", "LongTermBorr", "AccountsPay", "LongTermPay",
  "TotalEquity", "CapitalStock", "RetainedEarnings"
)

# ─── YYYYMM → 분기말 Date 변환 ──────────────────────────────────────────────
yyyymm_to_qtr_end <- function(yyyymm) {
  # yyyymm: character or numeric "199803"
  ym <- as.character(yyyymm)
  yr <- as.integer(substr(ym, 1, 4))
  mn <- as.integer(substr(ym, 5, 6))
  # 분기 마지막 달로 매핑 (03→03, 06→06, 09→09, 12→12)
  # 이미 분기말이므로 그대로 사용
  dt <- as.Date(paste0(yr, "-", sprintf("%02d", mn), "-01"))
  # 해당 월의 말일
  ceiling_date(dt, "month") - days(1)
}

# ─── 단일 시트 파싱 함수 ─────────────────────────────────────────────────────
parse_one_sheet <- function(wb_path, sheet_name) {
  cat("  Parsing:", sheet_name, "...")

  # 전체 읽기 (colNames=FALSE, skipEmptyRows=FALSE)
  raw <- read.xlsx(wb_path, sheet = sheet_name, colNames = FALSE,
                   skipEmptyRows = FALSE)

  # Row 10: Period 헤더 (YYYYMM)
  period_row <- as.character(unlist(raw[10, ]))
  # Row 13: 컬럼 라벨 (항목명 반복)
  # Row 14~: 데이터

  # 데이터 컬럼 시작: col 4부터 (col1=Code, col2=Name, col3=결산월)
  data_col_start <- 4

  # Period 추출 (col 4~)
  periods <- period_row[data_col_start:length(period_row)]
  valid_idx <- which(!is.na(periods) & periods != "")
  if (length(valid_idx) == 0) {
    cat(" SKIP (no periods)\n")
    return(NULL)
  }
  periods <- periods[valid_idx]
  data_cols <- (data_col_start - 1) + valid_idx  # 원본 컬럼 인덱스

  # 데이터 행: row 14~ (row index in raw = 14~)
  data_start_row <- 14
  if (nrow(raw) < data_start_row) {
    cat(" SKIP (no data rows)\n")
    return(NULL)
  }

  # Ticker, Name 추출
  tickers <- as.character(raw[data_start_row:nrow(raw), 1])
  names_col <- as.character(raw[data_start_row:nrow(raw), 2])

  # 유효한 ticker만 (A로 시작하는 행)
  valid_rows <- which(grepl("^A[0-9]", tickers))
  if (length(valid_rows) == 0) {
    cat(" SKIP (no valid tickers)\n")
    return(NULL)
  }

  tickers <- tickers[valid_rows]
  names_col <- names_col[valid_rows]
  data_row_idx <- (data_start_row - 1) + valid_rows  # 원본 행 인덱스

  # 데이터 추출
  data_mat <- as.matrix(raw[data_row_idx, data_cols, drop = FALSE])

  # 영문명 변환
  en_name <- KR_EN_MAP[sheet_name]
  if (is.na(en_name)) en_name <- sheet_name  # 매핑 없으면 원본 사용

  # Wide → Long 변환
  dt_list <- vector("list", length(periods))
  for (j in seq_along(periods)) {
    vals <- suppressWarnings(as.numeric(data_mat[, j]))
    dt_list[[j]] <- data.table(
      Ticker   = tickers,
      Period   = periods[j],
      Item     = en_name,
      Value    = vals
    )
  }

  result <- rbindlist(dt_list)
  # NA 값 제거 (빈 셀)
  result <- result[!is.na(Value)]

  cat(" ", format(nrow(result), big.mark = ","), "rows\n")
  return(result)
}

# ─── 메인 파싱 함수 ──────────────────────────────────────────────────────────
parse_fundamental_xlsx <- function(
    xlsx_path = "03_Universe/Fundamental.xlsx",
    cache_dir = ".cache"
) {
  cat("========================================\n")
  cat("Parsing Fundamental.xlsx\n")
  cat("========================================\n\n")

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

  # 시트 목록 (DATA_Key 제외)
  wb <- loadWorkbook(xlsx_path)
  sheets <- names(wb)
  sheets <- setdiff(sheets, "DATA_Key")

  cat("Total sheets to parse:", length(sheets), "\n\n")

  # 모든 시트 파싱
  all_data <- vector("list", length(sheets))
  for (i in seq_along(sheets)) {
    all_data[[i]] <- parse_one_sheet(xlsx_path, sheets[i])
  }

  dt <- rbindlist(all_data, use.names = TRUE)

  # Period → Date 변환
  dt[, Period_Date := yyyymm_to_qtr_end(Period)]
  # Factor_Date (PIT compliance — Q4 lag repair 2026-07-25, 도훈 승인):
  #   Q1~Q3 (Period 말월 != 12): 분기말 + 45일 (분기보고서 법정기한 45일)
  #   Q4    (Period 말월 == 12): 익년 3/31 명시 고정 (사업보고서 법정기한 90일 —
  #     +90d 산식은 윤년에 3/30~3/31로 흔들리므로 명시 3/31. DART 파이프라인
  #     90/91d와 규약 정합. 근거: 04_Research/01_reports/q4_lag_repair_plan_20260725.md §2(a))
  #   12월 외 결산(Period 말월=3/6/9 연간) semantics: 계획서 caveat ② — 본 수리는
  #     Period 말월=12만 대상(변경 없음 = 기존 +45d 유지, 신규 공격성 미도입).
  dt[, Factor_Date := fifelse(
    month(Period_Date) == 12L,
    as.Date(paste0(year(Period_Date) + 1L, "-03-31")),
    Period_Date + 45L
  )]

  cat("\n========================================\n")
  cat("Total rows:", format(nrow(dt), big.mark = ","), "\n")
  cat("Unique tickers:", uniqueN(dt$Ticker), "\n")
  cat("Unique items:", uniqueN(dt$Item), "\n")
  cat("Period range:", as.character(range(dt$Period_Date)), "\n")
  cat("Items:", paste(unique(dt$Item), collapse = ", "), "\n")
  cat("========================================\n\n")

  # ─── 전체 저장 ───────────────────────────────────────────────────────────
  out_path <- file.path(cache_dir, "fundamental_xlsx.parquet")
  write_parquet(dt, out_path)
  cat("Saved:", out_path,
      "(", format(file.size(out_path), big.mark = ","), "bytes)\n")

  # ─── ISSD 별도 저장 ──────────────────────────────────────────────────────
  dt_issd <- dt[Item == "ISSD"]
  if (nrow(dt_issd) > 0) {
    issd_path <- file.path(cache_dir, "shares_issued.parquet")
    write_parquet(dt_issd, issd_path)
    cat("Saved:", issd_path,
        "(", format(file.size(issd_path), big.mark = ","), "bytes,",
        format(nrow(dt_issd), big.mark = ","), "rows)\n")
  }

  # ─── SBB 별도 저장 ───────────────────────────────────────────────────────
  dt_sbb <- dt[Item == "SBB"]
  if (nrow(dt_sbb) > 0) {
    sbb_path <- file.path(cache_dir, "stock_buyback.parquet")
    write_parquet(dt_sbb, sbb_path)
    cat("Saved:", sbb_path,
        "(", format(file.size(sbb_path), big.mark = ","), "bytes,",
        format(nrow(dt_sbb), big.mark = ","), "rows)\n")
  }

  # ─── TTM 변환 ────────────────────────────────────────────────────────────
  cat("\n--- Computing TTM ---\n")
  dt_ttm <- compute_ttm(dt)
  ttm_path <- file.path(cache_dir, "fundamental_xlsx_ttm.parquet")
  write_parquet(dt_ttm, ttm_path)
  cat("Saved:", ttm_path,
      "(", format(file.size(ttm_path), big.mark = ","), "bytes,",
      format(nrow(dt_ttm), big.mark = ","), "rows)\n")

  invisible(dt)
}

# ─── TTM 계산 함수 ───────────────────────────────────────────────────────────
compute_ttm <- function(dt) {
  # P/L, CF → 4분기 rolling sum
  # B/S → 최신 분기 값 그대로

  # Item 분류
  dt[, item_type := fifelse(Item %in% PL_CF_ITEMS, "PL_CF",
                    fifelse(Item %in% BS_ITEMS, "BS", "OTHER"))]

  # B/S 항목: 그대로 (이미 시점값)
  dt_bs <- dt[item_type == "BS", .(Ticker, Period, Period_Date, Factor_Date,
                                    Item, Value)]
  dt_bs[, TTM_Value := Value]

  # P/L, CF 항목: 4분기 rolling sum
  dt_pl <- dt[item_type == "PL_CF"]
  setorder(dt_pl, Ticker, Item, Period_Date)
  dt_pl[, TTM_Value := frollsum(Value, n = 4, align = "right"),
        by = .(Ticker, Item)]
  dt_pl <- dt_pl[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, TTM_Value)]

  # ISSD, SBB 등 기타: 그대로
  dt_other <- dt[item_type == "OTHER", .(Ticker, Period, Period_Date, Factor_Date,
                                          Item, Value)]
  dt_other[, TTM_Value := Value]

  # 합치기
  result <- rbindlist(list(
    dt_bs[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, TTM_Value)],
    dt_pl[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, TTM_Value)],
    dt_other[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, TTM_Value)]
  ))

  # item_type 임시컬럼 정리
  dt[, item_type := NULL]

  cat("TTM rows:", format(nrow(result), big.mark = ","), "\n")
  cat("TTM non-NA:", format(sum(!is.na(result$TTM_Value)), big.mark = ","), "\n")

  return(result)
}

# ─── 병합 함수: DART(연간) + XLSX(분기) ─────────────────────────────────────
merge_fundamental_all <- function(cache_dir = ".cache") {
  cat("\n========================================\n")
  cat("Merging DART + XLSX fundamentals\n")
  cat("========================================\n")

  dart_path <- file.path(cache_dir, "fundamental_dart.parquet")
  xlsx_path <- file.path(cache_dir, "fundamental_xlsx.parquet")

  if (!file.exists(dart_path)) {
    cat("WARNING: DART parquet not found:", dart_path, "\n")
    return(NULL)
  }
  if (!file.exists(xlsx_path)) {
    cat("WARNING: XLSX parquet not found:", xlsx_path, "\n")
    return(NULL)
  }

  # DART 로드 (연간, wide format → long으로 변환)
  dt_dart <- as.data.table(read_parquet(dart_path))
  cat("DART loaded:", format(nrow(dt_dart), big.mark = ","), "rows x",
      ncol(dt_dart), "cols\n")
  cat("DART years:", paste(range(dt_dart$bsns_year, na.rm = TRUE), collapse = "~"), "\n")

  # DART: wide → long (Ticker, bsns_year, Factor_Date, ... → Ticker, Item, Value)
  id_cols <- c("Ticker", "bsns_year", "Factor_Date")
  val_cols <- setdiff(names(dt_dart), id_cols)
  # numeric 컬럼만 melt (AltmanZone 등 character 컬럼 제외)
  num_cols <- val_cols[sapply(val_cols, function(x) is.numeric(dt_dart[[x]]))]
  cat("DART numeric columns:", length(num_cols), "of", length(val_cols), "\n")

  dart_long <- melt(dt_dart, id.vars = id_cols, measure.vars = num_cols,
                    variable.name = "Item", value.name = "Value",
                    variable.factor = FALSE)
  dart_long <- dart_long[!is.na(Value)]
  dart_long[, Source := "DART"]
  # DART는 연간: Period = 12월(bsns_year * 100 + 12)
  dart_long[, Period := paste0(bsns_year, "12")]
  dart_long[, Period_Date := as.Date(paste0(bsns_year, "-12-31"))]

  cat("DART long:", format(nrow(dart_long), big.mark = ","), "rows\n")

  # XLSX 로드 (분기)
  dt_xlsx <- as.data.table(read_parquet(xlsx_path))
  dt_xlsx[, Source := "XLSX"]
  cat("XLSX loaded:", format(nrow(dt_xlsx), big.mark = ","), "rows\n")

  # XLSX에서 DART와 겹치는 항목만 필터 (공통 Item)
  common_items <- intersect(unique(dart_long$Item), unique(dt_xlsx$Item))
  cat("Common items:", length(common_items), "\n")
  cat("  ", paste(common_items, collapse = ", "), "\n")

  # XLSX 전체 + DART 전체 합치기
  cols_keep <- c("Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value", "Source")

  dart_out <- dart_long[, ..cols_keep]
  xlsx_out <- dt_xlsx[, ..cols_keep]

  merged <- rbindlist(list(xlsx_out, dart_out), use.names = TRUE)

  # 중복 제거: 같은 Ticker + Period + Item → DART 우선
  setorder(merged, Ticker, Period, Item, -Source)  # XLSX < DART 알파벳순 → DART가 뒤
  # Source 우선순위: DART > XLSX
  merged[, rank := seq_len(.N), by = .(Ticker, Period, Item)]
  # DART가 있으면 DART, 없으면 XLSX
  # Source="DART"이 "XLSX"보다 알파벳순 먼저 → -Source로 정렬하면 XLSX가 먼저
  # 다시 정렬: DART 우선
  setorder(merged, Ticker, Period, Item, Source)  # DART < XLSX
  merged[, rank := seq_len(.N), by = .(Ticker, Period, Item)]
  merged <- merged[rank == 1]
  merged[, rank := NULL]

  cat("\nMerged total:", format(nrow(merged), big.mark = ","), "rows\n")
  cat("Tickers:", uniqueN(merged$Ticker), "\n")
  cat("Items:", uniqueN(merged$Item), "\n")
  cat("Period range:", as.character(range(merged$Period_Date, na.rm = TRUE)), "\n")
  cat("Source breakdown:\n")
  print(merged[, .N, by = Source])

  # 저장
  out_path <- file.path(cache_dir, "fundamental_merged.parquet")
  write_parquet(merged, out_path)
  cat("\nSaved:", out_path,
      "(", format(file.size(out_path), big.mark = ","), "bytes)\n")

  invisible(merged)
}

# ─── 실행 ────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0 || !interactive()) {
  # 독립 실행 시
  dt <- parse_fundamental_xlsx()
  merge_fundamental_all()
}
