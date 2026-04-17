#==============================================================================
# RAWDATA Sanitize — 비거래일 제거 + 날짜 교정 + 누락일 복원
#
# Phase 1 일회성 정화 + 향후 /data-refresh --sanitize 에서 재사용
#
# 사용법:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/trading_calendar.R")
#   source("02_Infrastructure/rawdata_sanitize.R")
#   sanitize_rawdata()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
if (!exists("is_trading_day")) source(file.path(DATA_DIR, "trading_calendar.R"))

sanitize_rawdata <- function(dry_run = FALSE) {
  cat("=== RAWDATA Sanitize 시작 ===\n\n")

  RAWDATA_CACHE <- file.path(CACHE_DIR, "rawdata.parquet")
  BM_CACHE <- file.path(CACHE_DIR, "benchmark.parquet")
  cal <- .load_calendar()

  # ─── Step 1: 백업 ───────────────────────────────────────────────────────────
  cat("[Step 1] 백업...\n")
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  bm  <- as.data.table(read_parquet(BM_CACHE))

  backup_path <- file.path(CACHE_DIR, sprintf("rawdata_backup_%s.parquet", format(Sys.Date(), "%Y%m%d")))
  bm_backup   <- file.path(CACHE_DIR, sprintf("benchmark_backup_%s.parquet", format(Sys.Date(), "%Y%m%d")))

  if (!file.exists(backup_path)) {
    write_parquet(raw, backup_path)
    cat(sprintf("  RAWDATA 백업: %s (%s rows)\n", backup_path, format(nrow(raw), big.mark=",")))
  } else {
    cat(sprintf("  백업 이미 존재: %s\n", backup_path))
  }
  if (!file.exists(bm_backup)) {
    write_parquet(bm, bm_backup)
    cat(sprintf("  Benchmark 백업: %s\n", bm_backup))
  }

  before_rows <- nrow(raw)
  before_dates <- length(unique(raw$Date))
  before_tickers <- uniqueN(raw$Ticker)

  # ─── Step 2: 04/01 → 03/31 재태깅 (Naver 날짜 버그 교정) ──────────────────
  cat("\n[Step 2] 04/01 → 03/31 재태깅...\n")
  d_0401 <- as.Date("2026-04-01")
  d_0331 <- as.Date("2026-03-31")

  n_0401 <- raw[Date == d_0401, .N]
  if (n_0401 > 0 && d_0331 %in% cal$Date) {
    # 03/31이 이미 RAWDATA에 있으면 04/01 제거 (중복 방지)
    if (d_0331 %in% raw$Date) {
      cat(sprintf("  03/31 이미 존재 (%d종목). 04/01 (%d종목) 제거.\n",
                  raw[Date == d_0331, .N], n_0401))
      raw <- raw[Date != d_0401]
    } else {
      raw[Date == d_0401, Date := d_0331]
      cat(sprintf("  04/01 → 03/31 재태깅: %d종목\n", n_0401))
    }
  } else if (n_0401 > 0) {
    cat(sprintf("  04/01 데이터 %d종목 있으나 03/31이 캘린더에 없음. 제거.\n", n_0401))
    raw <- raw[Date != d_0401]
  } else {
    cat("  04/01 데이터 없음. 스킵.\n")
  }

  # Benchmark도 동일
  if (d_0401 %in% bm$Date) {
    if (d_0331 %in% bm$Date) {
      bm <- bm[Date != d_0401]
    } else {
      bm[Date == d_0401, Date := d_0331]
    }
    cat("  Benchmark도 교정 완료.\n")
  }

  # ─── Step 3: 비거래일 행 제거 ───────────────────────────────────────────────
  cat("\n[Step 3] 비거래일 행 제거...\n")
  all_dates <- sort(unique(raw$Date))
  non_td <- all_dates[!all_dates %in% cal$Date]
  cat(sprintf("  비거래일 수: %d\n", length(non_td)))

  if (length(non_td) > 0) {
    non_td_rows <- raw[Date %in% non_td, .N]
    cat(sprintf("  제거 대상: %s rows (%.1f%%)\n",
                format(non_td_rows, big.mark=","),
                100 * non_td_rows / nrow(raw)))

    # 안전 체크: 너무 많은 비율이면 경고
    pct <- non_td_rows / nrow(raw) * 100
    if (pct > 30) {
      cat("  ⚠️ 경고: 30% 이상 제거 대상. 캘린더 오류 가능성. 중단.\n")
      return(invisible(NULL))
    }
    if (pct > 15) {
      cat(sprintf("  참고: %.1f%% 제거 — 36년간 매주 일요일+공휴일 포함 시 정상 범위.\n", pct))
    }

    if (!dry_run) {
      raw <- raw[!Date %in% non_td]
      cat(sprintf("  제거 완료. 남은: %s rows\n", format(nrow(raw), big.mark=",")))
    }

    # Benchmark도 동일
    bm_non_td <- bm[!Date %in% cal$Date]
    if (nrow(bm_non_td) > 0) {
      cat(sprintf("  Benchmark 비거래일: %d행 제거\n", nrow(bm_non_td)))
      if (!dry_run) bm <- bm[Date %in% cal$Date]
    }
  }

  # ─── Step 4: 누락 거래일 확인 ───────────────────────────────────────────────
  cat("\n[Step 4] 누락 거래일 확인...\n")
  raw_dates <- sort(unique(raw$Date))
  # RAWDATA 범위 내에서 캘린더에 있는데 RAWDATA에 없는 날짜
  expected <- cal[Date >= min(raw_dates) & Date <= max(raw_dates)]$Date
  missing_td <- expected[!expected %in% raw_dates]

  if (length(missing_td) > 0) {
    cat(sprintf("  누락 거래일: %d일\n", length(missing_td)))
    # 최근 60일만 표시
    recent_missing <- missing_td[missing_td >= Sys.Date() - 60]
    if (length(recent_missing) > 0) {
      cat("  최근 60일 내 누락:\n")
      for (d in recent_missing) {
        cat(sprintf("    %s\n", as.Date(d, origin="1970-01-01")))
      }
    }
    cat(sprintf("  (전체 누락 중 대부분은 과거 공휴일 — 정상)\n"))
  } else {
    cat("  누락 없음.\n")
  }

  # ─── Step 5: Ret 재계산 ─────────────────────────────────────────────────────
  cat("\n[Step 5] Ret 재계산...\n")
  if (!dry_run) {
    setorder(raw, Ticker, Date)
    raw[, Ret := Close / shift(Close) - 1, by = Ticker]

    # 각 종목 첫 날 Ret = NA → 제거
    raw <- raw[!is.na(Ret)]

    cat(sprintf("  Ret 재계산 완료. 이상치(|Ret|>0.3): %d건\n", raw[abs(Ret) > 0.3, .N]))
  }

  # ─── Step 6: BM_Ret 재계산 ──────────────────────────────────────────────────
  cat("\n[Step 6] BM_Ret 재계산...\n")
  if (!dry_run) {
    setorder(bm, Date)
    bm[, BM_Ret := BM_Close / shift(BM_Close) - 1]
    bm <- bm[!is.na(BM_Ret)]

    # RAWDATA에 BM_Ret 매핑
    raw[, BM_Ret := NULL]
    raw <- merge(raw, bm[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

    bm_na <- raw[is.na(BM_Ret), .N]
    if (bm_na > 0) cat(sprintf("  BM_Ret NA: %d rows (BM 데이터 없는 날짜)\n", bm_na))

    cat("  BM_Ret 재계산 완료.\n")
  }

  # ─── Step 7: source 컬럼 추가 ───────────────────────────────────────────────
  cat("\n[Step 7] source 컬럼 추가...\n")
  if (!dry_run) {
    if (!"source" %in% names(raw)) {
      raw[, source := "quantiwise"]  # 기본값 (OHLCVS base)
    }
    cat("  source 컬럼 확인 완료.\n")
  }

  # ─── Step 8: 저장 ───────────────────────────────────────────────────────────
  cat("\n[Step 8] 저장...\n")
  if (!dry_run) {
    # 컬럼 순서 정리
    core_cols <- c("Date", "BM_Ret", "Ticker", "Name", "Market", "Sector",
                   "Open", "High", "Low", "Close", "Vol", "Size", "Ret", "source")
    keep <- intersect(core_cols, names(raw))
    raw <- raw[, ..keep]
    setorder(raw, Date, Ticker)

    write_parquet(raw, RAWDATA_CACHE)
    write_parquet(bm, BM_CACHE)
    cat(sprintf("  RAWDATA 저장: %s rows\n", format(nrow(raw), big.mark=",")))
    cat(sprintf("  Benchmark 저장: %d rows\n", nrow(bm)))
  }

  # ─── 검증 요약 ──────────────────────────────────────────────────────────────
  cat("\n=== 검증 요약 ===\n")
  after_rows <- nrow(raw)
  after_dates <- length(unique(raw$Date))
  after_tickers <- uniqueN(raw$Ticker)

  cat(sprintf("  Before: %s rows, %d dates, %d tickers\n",
              format(before_rows, big.mark=","), before_dates, before_tickers))
  cat(sprintf("  After:  %s rows, %d dates, %d tickers\n",
              format(after_rows, big.mark=","), after_dates, after_tickers))
  cat(sprintf("  Removed: %s rows (%d non-trading dates)\n",
              format(before_rows - after_rows, big.mark=","), length(non_td)))

  # 비거래일 체크
  final_non_td <- unique(raw$Date)[!unique(raw$Date) %in% cal$Date]
  cat(sprintf("  비거래일 잔여: %d\n", length(final_non_td)))

  # 연속성 체크 (삼성전자)
  samsung <- raw[Ticker == "A005930" & Date >= as.Date("2026-03-25"), .(Date, Close, Ret)]
  cat("\n  삼성전자 최근:\n")
  print(samsung)

  cat("\n=== RAWDATA Sanitize 완료 ===\n")
  invisible(raw)
}

cat("[rawdata_sanitize] Loaded. Run: sanitize_rawdata() or sanitize_rawdata(dry_run=TRUE)\n")
