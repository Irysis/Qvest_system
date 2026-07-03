#!/usr/bin/env Rscript
#==============================================================================
# DART Insider Backfill — 상태 요약 writer (.cache/dart_backfill_status.json)
#
# 2026-07-03 (감사 SC-05 후속, 진행 가시화): dart_insider_backfill.R 의 월별
#   체크포인트(.cache/dart/insider_backfill/<YYYYMM>.csv)를 스캔해
#   최종 체크포인트 월 · 수집 건수 · 잔여 개월을 JSON 1파일로 요약.
#   backfill 실행 직후 wrapper(run_dart_insider_backfill.bat)가 호출.
#   morning brief 등 소비자는 이 JSON만 읽으면 됨 (backfill 스크립트 무수정).
#
# Usage: QM_ROOT=... [BF_START=2005-01 BF_END=2024-02] Rscript dart_backfill_status.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

ROOT  <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
CKDIR <- file.path(ROOT, ".cache/dart/insider_backfill")
START <- Sys.getenv("BF_START", "2005-01"); END <- Sys.getenv("BF_END", "2024-02")
OUT   <- file.path(ROOT, ".cache/dart_backfill_status.json")

months <- format(seq(as.Date(paste0(START, "-01")), as.Date(paste0(END, "-01")), by = "month"), "%Y%m")
cks    <- file.path(CKDIR, paste0(months, ".csv"))
done   <- months[file.exists(cks)]

n_rows <- 0L; n_note <- 0L
for (f in cks[file.exists(cks)]) {
  d <- tryCatch(fread(f, colClasses = "character"), error = function(e) NULL)
  if (is.null(d)) next
  if ("note" %in% names(d) && !("rcept_no" %in% names(d))) n_note <- n_note + 1L
  else n_rows <- n_rows + nrow(d)
}

status <- list(
  asof                  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  range                 = paste0(START, "..", END),
  months_total          = length(months),
  months_done           = length(done),
  months_remaining      = length(months) - length(done),
  last_checkpoint_month = if (length(done)) max(done) else NA_character_,
  first_gap_month       = if (length(done) < length(months)) months[!file.exists(cks)][1] else NA_character_,
  rows_collected        = n_rows,
  months_empty          = n_note,
  checkpoint_dir        = CKDIR
)
write_json(status, OUT, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[bf-status] %d/%d months done (last=%s, gap=%s), rows=%d -> %s\n",
            status$months_done, status$months_total,
            ifelse(is.na(status$last_checkpoint_month), "-", status$last_checkpoint_month),
            ifelse(is.na(status$first_gap_month), "-", status$first_gap_month),
            n_rows, OUT))
