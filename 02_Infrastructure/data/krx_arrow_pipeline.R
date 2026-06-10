#==============================================================================
# KRX → Arrow Format Pipeline
# KRX API 데이터를 03_Universe/raw/arrow/ 포맷에 맞춰 변환
#
# 기존 OHLCVS_sheet*_start8.parquet + Benchmark_price_sheet1_start8.parquet 연장
# 구조:
#   Sheet1: 수정시가(Open)     | Sheet2: 수정고가(High)
#   Sheet3: 수정저가(Low)      | Sheet4: 수정주가(Close)
#   Sheet5: 수정거래량(Volume)  | Sheet6: 시가총액(MarketCap)
#   Benchmark: IKS200, IKS221 등 지수 종가
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/krx_data_collector.R")
#   source("02_Infrastructure/krx_arrow_pipeline.R")
#   krx_extend_arrow("20260207", "20260305")
#==============================================================================
cat("[krx_arrow_pipeline] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(nanoparquet)
  library(arrow)
})

ARROW_DIR <- file.path(PROJECT_ROOT, "03_Universe", "raw", "arrow")

# ── KRX API field → OHLCVS sheet mapping ──
# KRX API returns: ISU_SRT_CD(ticker), TDD_OPNPRC(Open), TDD_HGPRC(High),
#   TDD_LWPRC(Low), TDD_CLSPRC(Close), ACC_TRDVOL(Vol), MKTCAP(MarketCap)
# Arrow sheets: wide format (Date=Code col, tickers as columns)

.krx_num_clean <- function(x) {
  suppressWarnings(as.numeric(gsub(",", "", x)))
}

# Date → Excel serial number (origin 1899-12-30)
.date_to_excel <- function(d) {
  as.numeric(as.Date(d) - as.Date("1899-12-30"))
}

#──────────────────────────────────────────────────────────────────────────────
# 1. Read existing arrow file structure
#──────────────────────────────────────────────────────────────────────────────
.read_arrow_meta <- function(sheet_num = 1) {
  fn <- sprintf("OHLCVS_sheet%d_start8.parquet", sheet_num)
  fp <- file.path(ARROW_DIR, fn)
  if (!file.exists(fp)) stop("Arrow file not found: ", fp)

  pq <- nanoparquet::read_parquet(fp)
  # Extract header rows (1-5) and ticker column names
  list(
    header = pq[1:5, ],          # Name, Item Code, Unit, Base Date, D A T E/field name
    tickers = names(pq)[-1],     # All ticker columns (A000010, etc.)
    n_meta_rows = 5,             # Number of header/meta rows
    code_col = names(pq)[1],     # "Code"
    last_date_serial = {
      d <- suppressWarnings(as.numeric(pq[nrow(pq), 1, drop = TRUE]))
      d
    },
    last_date = {
      d <- suppressWarnings(as.numeric(pq[nrow(pq), 1, drop = TRUE]))
      as.Date(d, origin = "1899-12-30")
    },
    nrow_total = nrow(pq)
  )
}

#──────────────────────────────────────────────────────────────────────────────
# 2. Collect KRX data for a date range and transform to wide format
#──────────────────────────────────────────────────────────────────────────────
.krx_collect_ohlcvs_wide <- function(date_strs, existing_tickers) {
  # For each date, collect KOSPI + KOSDAQ stocks, pivot to wide
  results <- list()

  for (ds in date_strs) {
    cat(sprintf("  [arrow] Collecting %s...\n", ds))

    # Check cached KRX data first
    stk_file <- file.path(KRX_CACHE_DIR, "stk_ohlcv", sprintf("stk_ohlcv_%s.parquet", ds))
    ksq_file <- file.path(KRX_CACHE_DIR, "ksq_ohlcv", sprintf("ksq_ohlcv_%s.parquet", ds))

    stk <- if (file.exists(stk_file)) as.data.table(arrow::read_parquet(stk_file)) else krx_stk_ohlcv(ds)
    ksq <- if (file.exists(ksq_file)) as.data.table(arrow::read_parquet(ksq_file)) else krx_ksq_ohlcv(ds)

    if (is.null(stk) && is.null(ksq)) {
      cat(sprintf("  [arrow] %s — no data (holiday?)\n", ds))
      next
    }

    # Combine KOSPI + KOSDAQ
    combined <- rbindlist(list(stk, ksq), fill = TRUE)
    if (nrow(combined) == 0) next

    # Detect ticker column name (ISU_SRT_CD or similar)
    ticker_col <- intersect(c("ISU_SRT_CD", "ISU_CD"), names(combined))
    if (length(ticker_col) == 0) {
      cat(sprintf("  [arrow] %s — no ticker column found\n", ds))
      next
    }
    ticker_col <- ticker_col[1]

    # Map KRX ticker format to Arrow format (add 'A' prefix if needed)
    combined[, Ticker_Arrow := {
      tc <- get(ticker_col)
      # Remove leading 'A' or other prefix, get numeric part
      num_part <- gsub("^[A-Z]", "", tc)
      paste0("A", num_part)
    }]

    # Filter to only tickers that exist in the arrow files
    combined <- combined[Ticker_Arrow %in% existing_tickers]

    if (nrow(combined) == 0) {
      cat(sprintf("  [arrow] %s — no matching tickers\n", ds))
      next
    }

    # Detect field names
    open_col  <- intersect(c("TDD_OPNPRC", "시가"), names(combined))[1]
    high_col  <- intersect(c("TDD_HGPRC", "고가"), names(combined))[1]
    low_col   <- intersect(c("TDD_LWPRC", "저가"), names(combined))[1]
    close_col <- intersect(c("TDD_CLSPRC", "종가"), names(combined))[1]
    vol_col   <- intersect(c("ACC_TRDVOL", "거래량"), names(combined))[1]
    mktcap_col <- intersect(c("MKTCAP", "시가총액", "LIST_SHRS"), names(combined))[1]

    # Extract values
    excel_date <- as.character(.date_to_excel(as.Date(ds, "%Y%m%d")))

    # Build one row per sheet
    row_data <- list()
    for (field_name in c("open", "high", "low", "close", "vol", "mktcap")) {
      col <- switch(field_name,
                    open = open_col, high = high_col, low = low_col,
                    close = close_col, vol = vol_col, mktcap = mktcap_col)
      if (is.na(col)) next

      vals <- combined[, .(Ticker_Arrow, Val = .krx_num_clean(get(col)))]
      # Pivot wide: one row with date + ticker columns
      wide_row <- dcast(vals, . ~ Ticker_Arrow, value.var = "Val")[, -1]  # remove '.' column
      wide_row <- cbind(data.table(Code = excel_date), wide_row)
      row_data[[field_name]] <- wide_row
    }

    results[[ds]] <- row_data
    cat(sprintf("  [arrow] %s — %d tickers mapped\n", ds, nrow(combined)))
  }

  results
}

#──────────────────────────────────────────────────────────────────────────────
# 3. Collect benchmark index data for date range
#──────────────────────────────────────────────────────────────────────────────
.krx_collect_benchmark <- function(date_strs) {
  results <- list()

  # Full mapping: benchmark column code → KRX index name pattern
  kospi_map <- list(
    IKS001 = "^코스피$",
    IKS002 = "코스피 대형주",
    IKS003 = "코스피 중형주",
    IKS004 = "코스피 소형주",
    IKS200 = "^코스피 200$"
  )
  kosdaq_map <- list(
    IKQ001 = "^코스닥$",
    IKQ002 = "코스닥 대형주",
    IKQ003 = "코스닥 중형주",
    IKQ004 = "코스닥 소형주",
    IKQ150 = "^코스닥 150$"
  )

  for (ds in date_strs) {
    # Check cache — KOSPI
    idx_file <- file.path(KRX_CACHE_DIR, "kospi_index", sprintf("kospi_index_%s.parquet", ds))
    idx <- if (file.exists(idx_file)) as.data.table(arrow::read_parquet(idx_file)) else krx_kospi_index(ds)

    if (is.null(idx) || nrow(idx) == 0) next

    excel_date <- as.character(.date_to_excel(as.Date(ds, "%Y%m%d")))
    row_data <- data.table(Code = excel_date)

    # KOSPI indices
    for (col_code in names(kospi_map)) {
      pattern <- kospi_map[[col_code]]
      matched <- idx[grepl(pattern, IDX_NM)]
      if (nrow(matched) > 0) {
        row_data[, (col_code) := .krx_num_clean(matched$CLSPRC_IDX[1])]
      }
    }

    # KOSDAQ indices
    kq_file <- file.path(KRX_CACHE_DIR, "kosdaq_index", sprintf("kosdaq_index_%s.parquet", ds))
    kq <- if (file.exists(kq_file)) as.data.table(arrow::read_parquet(kq_file)) else {
      tryCatch(krx_kosdaq_index(ds), error = function(e) NULL)
    }
    if (!is.null(kq) && nrow(kq) > 0) {
      for (col_code in names(kosdaq_map)) {
        pattern <- kosdaq_map[[col_code]]
        matched <- kq[grepl(pattern, IDX_NM)]
        if (nrow(matched) > 0) {
          row_data[, (col_code) := .krx_num_clean(matched$CLSPRC_IDX[1])]
        }
      }
    }

    results[[ds]] <- row_data
  }

  if (length(results) > 0) rbindlist(results, fill = TRUE) else data.table()
}

#──────────────────────────────────────────────────────────────────────────────
# 4. Append new rows to existing parquet files
#    v2: WSL 로컬 캐시에서 작업 → OneDrive로 복사 (I/O 10x 개선)
#    백업: 업데이트 성공 후 기존 백업 파일 삭제
#──────────────────────────────────────────────────────────────────────────────
LOCAL_ARROW_CACHE <- file.path(Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), ".cache", "arrow_work")  # 2026-06-10 fix: 구 WSL 경로가 Windows에서 C:home 오염 유발
if (!dir.exists(LOCAL_ARROW_CACHE)) dir.create(LOCAL_ARROW_CACHE, recursive = TRUE)

.append_to_arrow <- function(sheet_num, new_rows, field_name) {
  fn <- sprintf("OHLCVS_sheet%d_start8.parquet", sheet_num)
  fp_remote <- file.path(ARROW_DIR, fn)
  fp_local  <- file.path(LOCAL_ARROW_CACHE, fn)

  # Step 1: Copy from OneDrive to local (1회 읽기)
  if (!file.exists(fp_local) ||
      file.info(fp_remote)$mtime > file.info(fp_local)$mtime) {
    file.copy(fp_remote, fp_local, overwrite = TRUE)
  }

  # Step 2: Read from LOCAL (fast)
  pq <- nanoparquet::read_parquet(fp_local)
  existing_cols <- names(pq)
  n_before <- nrow(pq)

  # Ensure new_rows have all existing columns (fill missing with NA)
  for (col in existing_cols) {
    if (!col %in% names(new_rows)) new_rows[, (col) := NA_character_]
  }
  new_rows <- new_rows[, ..existing_cols]

  # Convert all to character (matching existing format)
  for (col in names(new_rows)) {
    new_rows[, (col) := as.character(get(col))]
  }

  # Append
  combined <- rbind(as.data.table(pq), new_rows, fill = TRUE)

  # Step 3: Write to LOCAL (fast)
  nanoparquet::write_parquet(combined, fp_local)

  # Step 4: Copy back to OneDrive (1회 쓰기)
  file.copy(fp_local, fp_remote, overwrite = TRUE)

  # Step 5: Delete old backup files (keep only current file, no daily backups)
  old_backups <- list.files(ARROW_DIR,
    pattern = sprintf("OHLCVS_sheet%d_start8_backup_.*\\.parquet", sheet_num),
    full.names = TRUE)
  if (length(old_backups) > 0) {
    file.remove(old_backups)
    cat(sprintf("  [cleanup] Removed %d old backup(s) for sheet %d\n",
                length(old_backups), sheet_num))
  }

  cat(sprintf("  [arrow] Sheet %d (%s): %d → %d rows (local cache)\n",
              sheet_num, field_name, n_before, nrow(combined)))
}

#──────────────────────────────────────────────────────────────────────────────
# 5. Main pipeline: extend arrow files from KRX API
#──────────────────────────────────────────────────────────────────────────────
krx_extend_arrow <- function(start_str = NULL, end_str = NULL) {
  cat("[krx_arrow_pipeline] Starting arrow extension...\n")

  # Get existing metadata
  meta <- .read_arrow_meta(1)
  cat(sprintf("  Existing data: %s ~ %s (%d rows, %d tickers)\n",
              "1990-01-03", as.character(meta$last_date),
              meta$nrow_total, length(meta$tickers)))

  # Auto-detect start date if not specified
  if (is.null(start_str)) {
    start_date <- meta$last_date + 1
    start_str <- format(start_date, "%Y%m%d")
  }
  if (is.null(end_str)) {
    end_str <- format(Sys.Date() - 1, "%Y%m%d")  # yesterday
  }

  # Generate business days
  dates <- seq(as.Date(start_str, "%Y%m%d"), as.Date(end_str, "%Y%m%d"), by = "day")
  dates <- dates[!weekdays(dates) %in% c("Saturday", "Sunday")]
  date_strs <- format(dates, "%Y%m%d")

  if (length(date_strs) == 0) {
    cat("[krx_arrow_pipeline] No new dates to collect.\n")
    return(invisible(NULL))
  }

  cat(sprintf("  Dates to extend: %s ~ %s (%d business days)\n",
              date_strs[1], tail(date_strs, 1), length(date_strs)))

  # Collect OHLCVS data
  cat("\n--- Phase 1: Collect OHLCVS ---\n")
  ohlcvs_data <- .krx_collect_ohlcvs_wide(date_strs, meta$tickers)

  if (length(ohlcvs_data) == 0) {
    cat("[krx_arrow_pipeline] No new OHLCVS data collected.\n")
    return(invisible(NULL))
  }

  # Build sheet-specific row collections
  sheet_map <- list(
    "1" = "open", "2" = "high", "3" = "low",
    "4" = "close", "5" = "vol", "6" = "mktcap"
  )

  cat("\n--- Phase 2: Append to Arrow sheets ---\n")
  for (sheet_num in 1:6) {
    field <- sheet_map[[as.character(sheet_num)]]
    new_rows_list <- list()

    for (ds in names(ohlcvs_data)) {
      rd <- ohlcvs_data[[ds]]
      if (field %in% names(rd)) {
        new_rows_list[[ds]] <- rd[[field]]
      }
    }

    if (length(new_rows_list) > 0) {
      new_rows <- rbindlist(new_rows_list, fill = TRUE)
      .append_to_arrow(sheet_num, new_rows, field)
    } else {
      cat(sprintf("  [arrow] Sheet %d (%s): no data\n", sheet_num, field))
    }
  }

  # Collect and append benchmark data
  cat("\n--- Phase 3: Extend Benchmark ---\n")
  bm_new <- .krx_collect_benchmark(date_strs)
  if (nrow(bm_new) > 0) {
    bm_fp <- file.path(ARROW_DIR, "Benchmark_price_sheet1_start8.parquet")
    bm_old <- nanoparquet::read_parquet(bm_fp)
    existing_bm_cols <- names(bm_old)

    # Ensure columns match
    for (col in existing_bm_cols) {
      if (!col %in% names(bm_new)) bm_new[, (col) := NA_character_]
    }
    bm_new <- bm_new[, ..existing_bm_cols]
    for (col in names(bm_new)) bm_new[, (col) := as.character(get(col))]

    # Backup
    backup_fn <- sprintf("Benchmark_price_sheet1_start8_backup_%s.parquet",
                          format(Sys.Date(), "%Y%m%d"))
    backup_fp <- file.path(ARROW_DIR, backup_fn)
    if (!file.exists(backup_fp)) file.copy(bm_fp, backup_fp)

    combined <- rbind(as.data.table(bm_old), bm_new, fill = TRUE)
    nanoparquet::write_parquet(combined, bm_fp)
    cat(sprintf("  [benchmark] %d → %d rows, %d new dates\n",
                nrow(bm_old), nrow(combined), nrow(bm_new)))
  } else {
    cat("  [benchmark] No new data\n")
  }

  # Verification
  cat("\n--- Verification ---\n")
  meta_new <- .read_arrow_meta(1)
  cat(sprintf("  Updated: %s ~ %s (%d rows)\n",
              "1990-01-03", as.character(meta_new$last_date), meta_new$nrow_total))
  cat(sprintf("  Added: %d new dates\n", meta_new$nrow_total - meta$nrow_total))
  cat("[krx_arrow_pipeline] Extension complete.\n")
}

cat("[krx_arrow_pipeline] Loaded. Use: krx_extend_arrow()\n")
