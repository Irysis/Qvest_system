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

dart_daily_incremental <- function(current_year = as.integer(format(Sys.Date(), "%Y"))) {

  cat(sprintf("\n=== DART Daily Incremental (year=%d) @ %s ===\n",
              current_year, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

  # ─── 1. Quarterly (resume=TRUE 정합) ────────────────────────────────────────
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

  # ─── 2. Insider (merge + dedupe wrapper) ────────────────────────────────────
  cat("\n[2/2] Insider fetch (current year, merge-then-write)...\n")
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

    # Fetch current year (this OVERWRITES INSIDER_CACHE_PATH with current_year only data)
    new_dt <- dart_fetch_insider(years = current_year, delay = 0.7)

    # Re-load (file was overwritten by dart_fetch_insider)
    current_year_dt <- as.data.table(read_parquet(INSIDER_CACHE_PATH))
    cat(sprintf("  Current year fetch: %s records\n",
                format(nrow(current_year_dt), big.mark=",")))

    # Merge: keep all years from existing + replace current_year with new
    if (!is.null(existing_dt) && "Date" %in% names(existing_dt)) {
      pre_year_dt <- existing_dt[year(Date) < current_year]
      merged_dt <- rbindlist(list(pre_year_dt, current_year_dt), fill = TRUE, use.names = TRUE)

      # Dedupe on (Date, corp_code, rcept_no) if available
      key_cols <- intersect(c("Date", "corp_code", "rcept_no"), names(merged_dt))
      if (length(key_cols) >= 2) {
        merged_dt <- unique(merged_dt, by = key_cols)
      }

      # [fix 2026-06-17] Windows arrow mmap(error 1224) — existing_dt/current_year_dt가
      # INSIDER_CACHE_PATH를 mmap한 채라 동일 경로 write_parquet halt 회피, temp-rename.
      # (existing_dt는 아래 로그에 nrow 참조되므로 rm 불가 — rename으로 inode 교체)
      .ins_tmp <- paste0(INSIDER_CACHE_PATH, ".tmp")
      write_parquet(merged_dt, .ins_tmp)
      if (file.exists(INSIDER_CACHE_PATH)) file.remove(INSIDER_CACHE_PATH)
      file.rename(.ins_tmp, INSIDER_CACHE_PATH)
      cat(sprintf("  Merged saved: %s records (was %s)\n",
                  format(nrow(merged_dt), big.mark=","),
                  format(nrow(existing_dt), big.mark=",")))
    } else {
      cat(sprintf("  No existing history to merge. Current year only retained.\n"))
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

  cat(sprintf("\n=== DART Daily Incremental DONE @ %s ===\n",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
}

# Auto-run if invoked directly via Rscript
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) == 0L &&
    sys.nframe() == 0L) {
  dart_daily_incremental()
}
