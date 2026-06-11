#==============================================================================
# KTRI Index Collector
#
# KTRI v3가 필요로 하는 지수 데이터를 .cache/ktri_indices.parquet에 통합 저장.
#
# 데이터 소스:
#   1. 과거분: 기존 Benchmark_price_sheet1_start8.parquet에서 1회 마이그레이션
#   2. 신규분: .cache/krx/kospi_index/ + kosdaq_index/ + krx_derivatives/ 에서 추가
#   3. VKOSPI: .cache/regime_derivatives.parquet에서 (krx_derivatives_collector.R 산출)
#
# 출력: .cache/ktri_indices.parquet
#   Columns: Date, IKS200, IKS001, IKS002, IKS003, IKS004,
#            IKQ001, IKQ002, IKQ003, IKQ004, IKQ150, IKS221(VKOSPI)
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/ktri_index_collector.R")
#   ktri_collect_indices()          # 전체 빌드 (migration + update)
#   ktri_update_indices()           # 증분 업데이트만
#   ktri_update_from_api(date_str)  # 특정일 KRX API 직접 수집 + 추가
#==============================================================================
cat("[ktri_index_collector] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))

KTRI_INDEX_CACHE <- file.path(CACHE_DIR, "ktri_indices.parquet")
# KTRI_INDEX_CACHE read는 mmap = FALSE 필수: 같은 프로세스가 직후 같은 경로에 write하는데,
# Windows에서 mmap이 살아있으면 write_parquet이 error 1224로 전부 실패 (2026-06-11 실증)

# ── KRX IDX_NM → KTRI code mapping ──
.KOSPI_MAP <- list(
  IKS200 = "^코스피 200$",
  IKS001 = "코스피 대형주",
  IKS002 = "코스피 중형주",
  IKS003 = "코스피 소형주",
  IKS004 = "^코스피$"
)
.KOSDAQ_MAP <- list(
  IKQ001 = "코스닥 대형주",
  IKQ002 = "코스닥 중형주",
  IKQ003 = "코스닥 소형주",
  IKQ004 = "^코스닥$",
  IKQ150 = "^코스닥 150$"
)

.krx_num_clean <- function(x) suppressWarnings(as.numeric(gsub(",", "", x)))

#──────────────────────────────────────────────────────────────────────────────
# 1. Migration: Benchmark parquet → ktri_indices.parquet (1회만)
#──────────────────────────────────────────────────────────────────────────────
.ktri_migrate_from_benchmark <- function() {
  bm_path <- file.path(PROJECT_ROOT, "03_Universe", "raw", "arrow",
                        "Benchmark_price_sheet1_start8.parquet")
  if (!file.exists(bm_path)) {
    cat("[ktri_index_collector] Benchmark parquet not found — skipping migration.\n")
    return(data.table())
  }

  cat("[ktri_index_collector] Migrating from Benchmark parquet...\n")
  raw_pq <- as.data.frame(arrow::read_parquet(bm_path))
  names(raw_pq)[1] <- "DATE"

  # Excel serial date → Date
  raw_pq$DATE <- suppressWarnings(as.Date(as.numeric(raw_pq$DATE), origin = "1899-12-30"))
  raw_pq <- raw_pq[!is.na(raw_pq$DATE), ]

  # 필요한 컬럼만 추출
  need_cols <- c("IKS200", "IKS001", "IKS002", "IKS003", "IKS004",
                 "IKQ001", "IKQ002", "IKQ003", "IKQ004", "IKQ150", "IKS221")
  avail_cols <- intersect(need_cols, names(raw_pq))

  dt <- as.data.table(raw_pq)[, c("DATE", avail_cols), with = FALSE]
  setnames(dt, "DATE", "Date")

  # 숫자 변환
  for (col in avail_cols) {
    dt[, (col) := suppressWarnings(as.numeric(get(col)))]
  }

  # 결측 컬럼 추가
  for (col in setdiff(need_cols, avail_cols)) {
    dt[, (col) := NA_real_]
  }

  dt <- dt[order(Date)]
  dt <- unique(dt, by = "Date")

  cat(sprintf("  Migrated: %d rows (%s ~ %s)\n", nrow(dt), min(dt$Date), max(dt$Date)))
  dt
}

#──────────────────────────────────────────────────────────────────────────────
# 2. KRX API 캐시에서 인덱스 추가분 수집
#──────────────────────────────────────────────────────────────────────────────
.ktri_from_krx_cache <- function(after_date = NULL) {
  kospi_dir <- file.path(CACHE_DIR, "krx", "kospi_index")
  kosdaq_dir <- file.path(CACHE_DIR, "krx", "kosdaq_index")

  if (!dir.exists(kospi_dir)) return(data.table())

  files_kospi <- list.files(kospi_dir, pattern = "\\.parquet$", full.names = TRUE)
  files_kosdaq <- list.files(kosdaq_dir, pattern = "\\.parquet$", full.names = TRUE)

  if (length(files_kospi) == 0) return(data.table())

  results <- list()

  for (f in files_kospi) {
    # Extract date from filename
    date_str <- sub(".*kospi_index_(\\d{8})\\.parquet$", "\\1", basename(f))
    d <- as.Date(date_str, "%Y%m%d")
    if (!is.na(after_date) && d <= after_date) next

    idx <- as.data.table(arrow::read_parquet(f))
    if (nrow(idx) == 0) next

    row <- data.table(Date = d)

    # KOSPI indices
    for (col_code in names(.KOSPI_MAP)) {
      pattern <- .KOSPI_MAP[[col_code]]
      matched <- idx[grepl(pattern, IDX_NM)]
      if (nrow(matched) > 0) {
        row[, (col_code) := .krx_num_clean(matched$CLSPRC_IDX[1])]
      }
    }

    # KOSDAQ indices (same date)
    kq_file <- file.path(kosdaq_dir, sprintf("kosdaq_index_%s.parquet", date_str))
    if (file.exists(kq_file)) {
      kq <- as.data.table(arrow::read_parquet(kq_file))
      if (nrow(kq) > 0) {
        for (col_code in names(.KOSDAQ_MAP)) {
          pattern <- .KOSDAQ_MAP[[col_code]]
          matched <- kq[grepl(pattern, IDX_NM)]
          if (nrow(matched) > 0) {
            row[, (col_code) := .krx_num_clean(matched$CLSPRC_IDX[1])]
          }
        }
      }
    }

    # VKOSPI — from regime_derivatives cache
    row[, IKS221 := NA_real_]

    results[[date_str]] <- row
  }

  if (length(results) == 0) return(data.table())
  dt <- rbindlist(results, fill = TRUE)
  dt[order(Date)]
}

#──────────────────────────────────────────────────────────────────────────────
# 3. VKOSPI 채우기: regime_derivatives.parquet에서
#──────────────────────────────────────────────────────────────────────────────
.ktri_fill_vkospi <- function(dt) {
  drv_path <- file.path(CACHE_DIR, "regime_derivatives.parquet")
  if (!file.exists(drv_path)) return(dt)

  drv <- as.data.table(arrow::read_parquet(drv_path))
  if (!"VKOSPI_raw" %in% names(drv)) return(dt)

  # Date 컬럼 정규화
  if ("Date" %in% names(drv)) {
    drv[, Date := as.Date(Date)]
  } else if ("DATE" %in% names(drv)) {
    setnames(drv, "DATE", "Date")
    drv[, Date := as.Date(Date)]
  } else {
    return(dt)
  }

  vk <- drv[!is.na(VKOSPI_raw), .(Date, VKOSPI_raw)]

  # IKS221이 NA인 행만 채움
  dt <- merge(dt, vk, by = "Date", all.x = TRUE)
  dt[is.na(IKS221) & !is.na(VKOSPI_raw), IKS221 := VKOSPI_raw]
  dt[, VKOSPI_raw := NULL]

  dt
}

#──────────────────────────────────────────────────────────────────────────────
# 4. KRX API 직접 호출: 특정일 수집 + 추가
#──────────────────────────────────────────────────────────────────────────────
#──────────────────────────────────────────────────────────────────────────────
# Naver fallback fetch (도훈 mandate 2026-05-12 — KRX API fail 시 secondary path)
#──────────────────────────────────────────────────────────────────────────────
.ktri_fetch_naver_close <- function(symbol, target_date) {
  # symbol: "KPI200" / "KOSDAQ" / "KOSPI"
  # target_date: Date object — fetch close on this date from Naver
  url <- sprintf("https://m.stock.naver.com/api/index/%s/price?pageSize=20&page=1", symbol)
  r <- tryCatch(httr::GET(url,
                          httr::add_headers(`User-Agent` = "Mozilla/5.0",
                                            Referer = "https://m.stock.naver.com")),
                error = function(e) NULL)
  if (is.null(r) || httr::status_code(r) != 200) return(NA_real_)
  d <- tryCatch(jsonlite::fromJSON(httr::content(r, "text", encoding = "UTF-8")),
                error = function(e) NULL)
  if (is.null(d) || !is.data.frame(d) || nrow(d) == 0) return(NA_real_)
  d <- as.data.table(d)
  d[, Date := as.Date(localTradedAt)]
  matched <- d[Date == target_date]
  if (nrow(matched) == 0) return(NA_real_)
  as.numeric(gsub(",", "", matched$closePrice[1]))
}

ktri_update_from_api <- function(date_str) {
  # krx_data_collector.R 함수 필요
  if (!exists("krx_kospi_index")) {
    collector_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "data", "krx_data_collector.R")
    if (file.exists(collector_path)) source(collector_path) else {
      cat("[ktri_index_collector] krx_data_collector.R not loaded. Cannot call API.\n")
      return(invisible(NULL))
    }
  }

  cat(sprintf("[ktri_index_collector] Collecting %s from KRX API...\n", date_str))

  row <- data.table(Date = as.Date(date_str, "%Y%m%d"))

  # KOSPI indices
  idx <- tryCatch(krx_kospi_index(date_str), error = function(e) NULL)
  if (!is.null(idx) && nrow(idx) > 0) {
    idx <- as.data.table(idx)
    for (col_code in names(.KOSPI_MAP)) {
      matched <- idx[grepl(.KOSPI_MAP[[col_code]], IDX_NM)]
      if (nrow(matched) > 0) row[, (col_code) := .krx_num_clean(matched$CLSPRC_IDX[1])]
    }
  }

  # KOSDAQ indices
  kq <- tryCatch(krx_kosdaq_index(date_str), error = function(e) NULL)
  if (!is.null(kq) && nrow(kq) > 0) {
    kq <- as.data.table(kq)
    for (col_code in names(.KOSDAQ_MAP)) {
      matched <- kq[grepl(.KOSDAQ_MAP[[col_code]], IDX_NM)]
      if (nrow(matched) > 0) row[, (col_code) := .krx_num_clean(matched$CLSPRC_IDX[1])]
    }
  }

  # VKOSPI — from derivatives
  if (exists("krx_vkospi")) {
    vk <- tryCatch(krx_vkospi(date_str), error = function(e) NULL)
    if (!is.null(vk) && !is.na(vk$VKOSPI)) {
      row[, IKS221 := vk$VKOSPI]
    }
  }

  # KRX API에서 IKS200 못 가져왔으면 네이버 fallback (도훈 mandate 2026-05-12)
  if (!"IKS200" %in% names(row) || is.na(row$IKS200)) {
    naver_close <- .ktri_fetch_naver_close("KPI200", as.Date(date_str, "%Y%m%d"))
    if (!is.na(naver_close)) {
      row[, IKS200 := naver_close]
      cat(sprintf("  [naver_fallback] IKS200 = %.2f (KPI200 close from Naver)\n", naver_close))
    }
  }

  # 핵심 데이터(IKS200)가 없으면 추가하지 않음 (API 지연/휴일)
  if (is.na(row$IKS200) %||% TRUE) {
    # IKS200 없으면 다른 지수로도 확인
    has_any <- any(!is.na(unlist(row[, -"Date", with = FALSE])))
    if (!has_any) {
      cat(sprintf("  %s: no data from API or Naver fallback (holiday or delay). Skipping.\n", date_str))
      return(invisible(NULL))
    }
  }

  # 기존 파일에 추가
  if (file.exists(KTRI_INDEX_CACHE)) {
    existing <- as.data.table(arrow::read_parquet(KTRI_INDEX_CACHE, mmap = FALSE))
    existing[, Date := as.Date(Date)]
    # 중복 제거: 같은 날짜가 있으면 새 데이터로 교체
    existing <- existing[Date != row$Date]
    combined <- rbindlist(list(existing, row), fill = TRUE)
    combined <- combined[order(Date)]
  } else {
    combined <- row
  }

  arrow::write_parquet(combined, KTRI_INDEX_CACHE)
  cat(sprintf("  Added %s → %d total rows\n", date_str, nrow(combined)))
  invisible(combined)
}

#──────────────────────────────────────────────────────────────────────────────
# 5. Main: 전체 빌드 (migration + KRX cache + VKOSPI + API gap-fill)
#──────────────────────────────────────────────────────────────────────────────
ktri_collect_indices <- function(fill_api_gap = TRUE) {
  cat("[ktri_index_collector] Building ktri_indices.parquet...\n")

  # Step 1: Migration from benchmark parquet
  dt_legacy <- .ktri_migrate_from_benchmark()

  # Step 2: KRX API cache 추가
  if (nrow(dt_legacy) > 0) {
    after_date <- max(dt_legacy$Date, na.rm = TRUE)
  } else {
    after_date <- as.Date("1990-01-01")
  }
  dt_krx <- .ktri_from_krx_cache(after_date)

  # Step 3: 합치기
  if (nrow(dt_krx) > 0) {
    dt <- rbindlist(list(dt_legacy, dt_krx), fill = TRUE)
    cat(sprintf("  KRX cache added: %d new rows\n", nrow(dt_krx)))
  } else {
    dt <- dt_legacy
    cat("  No additional KRX cache data.\n")
  }

  dt <- unique(dt, by = "Date")
  dt <- dt[order(Date)]

  # Step 4: VKOSPI 채우기
  dt <- .ktri_fill_vkospi(dt)

  # Step 5: KRX API로 gap 채우기 (benchmark 이후 ~ 오늘)
  if (fill_api_gap && nrow(dt) > 0) {
    last_date <- max(dt$Date, na.rm = TRUE)
    today <- Sys.Date()

    # 벤치마크와 RAWDATA 사이 gap 확인
    bm <- tryCatch({
      bm_dt <- as.data.table(arrow::read_parquet(BM_CACHE))
      if (!"Date" %in% names(bm_dt)) setnames(bm_dt, "DATE", "Date", skip_absent = TRUE)
      bm_dt[, Date := as.Date(Date)]
      max(bm_dt$Date, na.rm = TRUE)
    }, error = function(e) last_date)

    if (bm > last_date) {
      gap_dates <- seq(last_date + 1, bm, by = "day")
      gap_dates <- gap_dates[!weekdays(gap_dates) %in% c("Saturday", "Sunday")]

      if (length(gap_dates) > 0) {
        cat(sprintf("  Filling gap: %s ~ %s (%d business days) from KRX API...\n",
                    min(gap_dates), max(gap_dates), length(gap_dates)))

        # krx_data_collector 로드 (아직 안 됐으면)
        if (!exists("krx_kospi_index")) {
          collector_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "data", "krx_data_collector.R")
          if (file.exists(collector_path)) source(collector_path)
        }

        gap_rows <- list()
        for (i in seq_along(gap_dates)) {
          gd <- as.Date(gap_dates[i], origin = "1970-01-01")
          ds <- format(gd, "%Y%m%d")
          row <- data.table(Date = gd)

          # 캐시 먼저 확인
          ki_file <- file.path(CACHE_DIR, "krx", "kospi_index",
                               sprintf("kospi_index_%s.parquet", ds))
          kq_file <- file.path(CACHE_DIR, "krx", "kosdaq_index",
                               sprintf("kosdaq_index_%s.parquet", ds))

          got_data <- FALSE

          # KOSPI
          if (file.exists(ki_file)) {
            idx <- as.data.table(arrow::read_parquet(ki_file))
          } else if (exists("krx_kospi_index")) {
            idx <- tryCatch(as.data.table(krx_kospi_index(ds)), error = function(e) NULL)
          } else {
            idx <- NULL
          }
          if (!is.null(idx) && nrow(idx) > 0) {
            got_data <- TRUE
            for (cc in names(.KOSPI_MAP)) {
              m <- idx[grepl(.KOSPI_MAP[[cc]], IDX_NM)]
              if (nrow(m) > 0) row[, (cc) := .krx_num_clean(m$CLSPRC_IDX[1])]
            }
          }

          # KOSDAQ
          if (file.exists(kq_file)) {
            kq <- as.data.table(arrow::read_parquet(kq_file))
          } else if (exists("krx_kosdaq_index")) {
            kq <- tryCatch(as.data.table(krx_kosdaq_index(ds)), error = function(e) NULL)
          } else {
            kq <- NULL
          }
          if (!is.null(kq) && nrow(kq) > 0) {
            got_data <- TRUE
            for (cc in names(.KOSDAQ_MAP)) {
              m <- kq[grepl(.KOSDAQ_MAP[[cc]], IDX_NM)]
              if (nrow(m) > 0) row[, (cc) := .krx_num_clean(m$CLSPRC_IDX[1])]
            }
          }

          if (got_data) gap_rows[[ds]] <- row
        }

        if (length(gap_rows) > 0) {
          dt_gap <- rbindlist(gap_rows, fill = TRUE)
          dt_gap <- .ktri_fill_vkospi(dt_gap)
          dt <- rbindlist(list(dt, dt_gap), fill = TRUE)
          dt <- unique(dt, by = "Date")
          dt <- dt[order(Date)]
          cat(sprintf("  Gap filled: %d rows added\n", nrow(dt_gap)))
        }
      }
    }
  }

  # Save
  arrow::write_parquet(dt, KTRI_INDEX_CACHE)
  cat(sprintf("[ktri_index_collector] Saved: %s\n", KTRI_INDEX_CACHE))
  cat(sprintf("  Total: %d rows (%s ~ %s)\n", nrow(dt), min(dt$Date), max(dt$Date)))
  cat(sprintf("  IKS200 non-NA: %d | IKS221(VKOSPI) non-NA: %d\n",
              sum(!is.na(dt$IKS200)), sum(!is.na(dt$IKS221))))

  invisible(dt)
}

#──────────────────────────────────────────────────────────────────────────────
# 6. Incremental update: 기존 ktri_indices.parquet에 신규분만 추가
#──────────────────────────────────────────────────────────────────────────────
ktri_update_indices <- function() {
  if (!file.exists(KTRI_INDEX_CACHE)) {
    cat("[ktri_index_collector] No existing cache — running full build.\n")
    return(ktri_collect_indices())
  }

  existing <- as.data.table(arrow::read_parquet(KTRI_INDEX_CACHE, mmap = FALSE))
  existing[, Date := as.Date(Date)]
  last_date <- max(existing$Date, na.rm = TRUE)
  cat(sprintf("[ktri_index_collector] Existing: %d rows up to %s\n",
              nrow(existing), last_date))

  # KRX cache에서 새 데이터
  dt_new <- .ktri_from_krx_cache(last_date)

  if (nrow(dt_new) > 0) {
    dt_new <- .ktri_fill_vkospi(dt_new)
    combined <- rbindlist(list(existing, dt_new), fill = TRUE)
    combined <- unique(combined, by = "Date")
    combined <- combined[order(Date)]
    arrow::write_parquet(combined, KTRI_INDEX_CACHE)
    cat(sprintf("  Updated: +%d rows → %d total (%s ~ %s)\n",
                nrow(dt_new), nrow(combined), min(combined$Date), max(combined$Date)))
    invisible(combined)
  } else {
    # API 직접 호출로 gap-fill 시도
    bm_max <- tryCatch({
      bm_dt <- as.data.table(arrow::read_parquet(BM_CACHE))
      if (!"Date" %in% names(bm_dt)) setnames(bm_dt, "DATE", "Date", skip_absent = TRUE)
      bm_dt[, Date := as.Date(Date)]
      max(bm_dt$Date, na.rm = TRUE)
    }, error = function(e) last_date)

    if (bm_max > last_date) {
      gap_dates <- seq(last_date + 1, bm_max, by = "day")
      gap_dates <- gap_dates[!weekdays(gap_dates) %in% c("Saturday", "Sunday")]

      if (length(gap_dates) > 0) {
        cat(sprintf("  API gap-fill: %d dates (%s ~ %s)\n",
                    length(gap_dates), min(gap_dates), max(gap_dates)))
        for (j in seq_along(gap_dates)) {
          gd <- as.Date(gap_dates[j], origin = "1970-01-01")
          tryCatch(
            ktri_update_from_api(format(gd, "%Y%m%d")),
            error = function(e) cat(sprintf("  [SKIP] %s: %s\n", gd, e$message))
          )
        }
      }
    } else {
      cat("  Already up to date.\n")
    }
    invisible(existing)
  }
}

cat(sprintf("[ktri_index_collector] Loaded. Cache: %s\n", KTRI_INDEX_CACHE))
