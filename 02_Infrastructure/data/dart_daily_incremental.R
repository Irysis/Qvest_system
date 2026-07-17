#==============================================================================
# DART Daily Incremental Wrapper
#
# 매일 호출 가능한 안전 wrapper:
#   1. Quarterly: dart_fetch_quarterly(resume=TRUE)로 incremental — 기존 보존
#   2. Insider: 기존 cache load → 현재 연도만 fetch → merge + dedupe → save
#                (insider 원 스크립트는 OVERWRITE policy라 직접 호출 시 history 손실 위험)
#
# 사용:
#   source("config.R")
#   source("02_Infrastructure/data/dart_daily_incremental.R")
#   dart_daily_incremental()
#
# API 부담: 일 10,000건 한도 내 (quarterly resume + insider 현재 연도 12 month list)
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

cat("[dart_daily_incremental] Loaded.\n")

DART_CACHE_DIR     <- file.path(CACHE_DIR, "dart")
INSIDER_CACHE_PATH <- file.path(DART_CACHE_DIR, "insider_trades.parquet")
INSIDER_BACKUP_DIR <- file.path(DART_CACHE_DIR, "insider_backup")
dir.create(INSIDER_BACKUP_DIR, showWarnings = FALSE, recursive = TRUE)

dart_daily_incremental <- function(current_year = as.integer(format(Sys.Date(), "%Y")),
                                   steps = c("quarterly", "insider")) {

  cat(sprintf("\n=== DART Daily Incremental (year=%d, steps=%s) @ %s ===\n",
              current_year, paste(steps, collapse = "+"),
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

  # ─── 1. Quarterly (resume=TRUE 정합) ────────────────────────────────────────
  if ("quarterly" %in% steps) {
  cat("\n[1/2] Quarterly fetch (current year, resume=TRUE)...\n")
  source(file.path(PROJECT_ROOT, "02_Infrastructure", "data", "data_collector_dart.R"))
  source(file.path(PROJECT_ROOT, "02_Infrastructure", "data", "data_collector_dart_quarterly.R"))

  tryCatch({
    dart_fetch_quarterly(years = current_year, resume = TRUE)
    dart_compute_ttm()
    cat("[1/2] Quarterly: PASS\n")
  }, error = function(e) {
    cat(sprintf("[1/2] Quarterly: FAIL — %s\n", e$message))
  })
  } else cat("\n[1/2] Quarterly: skipped (steps)\n")

  # ─── 2. Insider (merge + dedupe wrapper) ────────────────────────────────────
  if ("insider" %in% steps) {
  cat("\n[2/2] Insider fetch (incremental window, merge-then-write)...\n")
  source(file.path(PROJECT_ROOT, "02_Infrastructure", "data", "data_collector_dart_insider.R"))

  tryCatch({
    # Load existing cache (history preservation)
    existing_dt <- if (file.exists(INSIDER_CACHE_PATH)) {
      as.data.table(read_parquet(INSIDER_CACHE_PATH))
    } else {
      NULL
    }
    cat(sprintf("  Existing cache: %s records (history)\n",
                if (is.null(existing_dt)) "0" else format(nrow(existing_dt), big.mark=",")))

    # Backup before any overwrite (safety)
    if (!is.null(existing_dt) && nrow(existing_dt) > 0) {
      backup_path <- file.path(INSIDER_BACKUP_DIR,
                                sprintf("insider_trades_%s.parquet", format(Sys.Date(), "%Y%m%d")))
      if (!file.exists(backup_path)) {
        write_parquet(existing_dt, backup_path)
        cat(sprintf("  Backup saved: %s\n", basename(backup_path)))
      }
    }

    # ── 증분 창 산정 (2026-07-17 재설계) ──────────────────────────────────────
    # 구 로직: 연 전체 재수집 → 연도 치환. corp_code 수리 후에는 창-scoped 수집이므로
    # "기존 전체 + 신규 창" full-merge + dedupe로 교체 (연도 치환은 부분 창과 충돌).
    # lookback 14일: 정정공시/지연접수 커버. 기존 데이터 gap이 크면 그만큼 소급.
    bgn_date <- if (!is.null(existing_dt) && "Date" %in% names(existing_dt) &&
                    any(!is.na(existing_dt$Date))) {
      max(as.Date(existing_dt$Date), na.rm = TRUE) - 14L
    } else {
      as.Date(sprintf("%d-01-01", current_year))
    }
    cat(sprintf("  Incremental window: %s ~ today\n", format(bgn_date)))

    # Fetch window (collector도 창 결과를 INSIDER_CACHE_PATH에 overwrite —
    # 아래 merge가 즉시 재작성하며, 실패 시 backup 복원 경로 존재)
    yrs <- seq.int(as.integer(format(bgn_date, "%Y")), current_year)
    new_dt <- dart_fetch_insider(years = yrs, delay = 0.7, bgn_date = bgn_date)

    if (is.null(new_dt) || nrow(new_dt) == 0) {
      cat("  No new insider details fetched — cache untouched.\n")
      # collector가 NULL 반환 시 파일을 쓰지 않으므로 기존 파일 그대로. 단
      # 만일 부분 write가 있었다면 backup 복원.
      cur <- tryCatch(as.data.table(read_parquet(INSIDER_CACHE_PATH)), error = function(e) NULL)
      if (!is.null(existing_dt) && (is.null(cur) || nrow(cur) < nrow(existing_dt))) {
        .ins_tmp <- paste0(INSIDER_CACHE_PATH, ".tmp")
        write_parquet(existing_dt, .ins_tmp)
        if (file.exists(INSIDER_CACHE_PATH)) file.remove(INSIDER_CACHE_PATH)
        file.rename(.ins_tmp, INSIDER_CACHE_PATH)
        cat("  Restored full history from in-memory copy.\n")
      }
    } else {
      cat(sprintf("  Window fetch: %s records\n", format(nrow(new_dt), big.mark = ",")))

      # Merge: 기존 전체 + 신규 창, dedupe
      merged_dt <- if (!is.null(existing_dt)) {
        rbindlist(list(existing_dt, new_dt), fill = TRUE, use.names = TRUE)
      } else new_dt
      key_cols <- intersect(c("rcept_no", "corp_code", "repror", "Date"), names(merged_dt))
      if (length(key_cols) >= 2) merged_dt <- unique(merged_dt, by = key_cols)

      # [fix 2026-06-17] Windows arrow mmap(error 1224) — 동일 경로 write halt 회피, temp-rename
      .ins_tmp <- paste0(INSIDER_CACHE_PATH, ".tmp")
      write_parquet(merged_dt, .ins_tmp)
      if (file.exists(INSIDER_CACHE_PATH)) file.remove(INSIDER_CACHE_PATH)
      file.rename(.ins_tmp, INSIDER_CACHE_PATH)
      cat(sprintf("  Merged saved: %s records (was %s), max Date %s\n",
                  format(nrow(merged_dt), big.mark = ","),
                  if (is.null(existing_dt)) "0" else format(nrow(existing_dt), big.mark = ","),
                  format(suppressWarnings(max(as.Date(merged_dt$Date), na.rm = TRUE)))))
    }
    cat("[2/2] Insider: PASS\n")
  }, error = function(e) {
    cat(sprintf("[2/2] Insider: FAIL — %s\n", e$message))
    # Restore from backup if write was partial
    backup_path <- file.path(INSIDER_BACKUP_DIR,
                              sprintf("insider_trades_%s.parquet", format(Sys.Date(), "%Y%m%d")))
    if (file.exists(backup_path)) {
      cat(sprintf("  Restoring from backup: %s\n", basename(backup_path)))
      file.copy(backup_path, INSIDER_CACHE_PATH, overwrite = TRUE)
    }
  })
  } else cat("\n[2/2] Insider: skipped (steps)\n")

  cat(sprintf("\n=== DART Daily Incremental DONE @ %s ===\n",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
}

# Auto-run if invoked directly via Rscript
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) == 0L &&
    sys.nframe() == 0L) {
  dart_daily_incremental()
}
