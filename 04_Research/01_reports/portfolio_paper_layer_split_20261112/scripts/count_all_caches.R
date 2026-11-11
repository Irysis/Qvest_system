## 개수만 센다 — 엔진별 기저 캐시(.base_sig = 셀 엔진이 기저 신호로 읽는 패널: FACTORS 점수 또는 PORTFOLIO 비중)의
##   신호일당 종목 수 · 신호일 격자(월말 거래일 일치) · 부호 구성. 성과 수치는 읽지 않는다(캐시 열 = Date · Ticker · .base_sig).
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
root <- args[1]; static_json <- args[2]; out <- args[3]
st <- fromJSON(static_json, simplifyVector = FALSE)
cal <- sort(unique(as.Date(arrow::read_parquet(file.path(root, ".cache", "rawdata.parquet"), col_select = "Date")$Date)))
me <- cal[!duplicated(format(cal, "%Y%m"), fromLast = TRUE)]
START <- as.Date("2000-01-01")
cdir <- file.path(root, ".cache", "rf_base_signal")
allc <- list.files(cdir, pattern = "^base_v2_.*\\.rds$", full.names = TRUE)
qs <- function(v) if (!length(v)) c(NA, NA, NA) else c(min(v), stats::median(v), max(v))
rows <- list()
for (r in st) {
  if (!isTRUE(r$has_engine) || !isTRUE(r$parse_ok)) next
  pre <- substr(r$md5, 1, 12)
  fs <- allc[grepl(paste0("^base_v2_", pre, "_"), basename(allc))]
  if (!length(fs)) { rows[[length(rows) + 1L]] <- list(dir = r$dir, cache = NA); next }
  f <- fs[order(file.info(fs)$mtime, decreasing = TRUE)][1]
  b <- tryCatch(as.data.table(readRDS(f)), error = function(e) NULL)
  if (is.null(b) || !all(c("Date", "Ticker", ".base_sig") %in% names(b))) { rows[[length(rows) + 1L]] <- list(dir = r$dir, cache = basename(f), err = "read"); next }
  b[, Date := as.Date(Date)]
  b <- b[!is.na(.base_sig) & Date >= START]
  n <- b[, .(n_all = .N, n_pos = sum(.base_sig > 0), n_neg = sum(.base_sig < 0), n_zero = sum(.base_sig == 0)), by = Date][order(Date)]
  n[, is_me := Date %in% me]
  gap <- diff(match(n$Date, cal)); gap <- as.integer(gap[!is.na(gap)])
  qa <- qs(n$n_all); qm <- qs(n[is_me == TRUE]$n_all); qg <- qs(gap); qp <- qs(n$n_pos)
  rows[[length(rows) + 1L]] <- list(
    dir = r$dir, cache = basename(f), cache_mtime = format(file.info(f)$mtime, "%Y-%m-%d"), n_cache_versions = length(fs),
    n_dates = nrow(n), first = format(min(n$Date)), last = format(max(n$Date)),
    all_min = qa[1], all_med = qa[2], all_max = qa[3], pos_min = qp[1], pos_med = qp[2], pos_max = qp[3],
    n_dates_with_neg = sum(n$n_neg > 0), n_dates_with_zero = sum(n$n_zero > 0),
    gap_min = qg[1], gap_med = qg[2], gap_max = qg[3],
    n_me = sum(n$is_me), me_min = qm[1], me_med = qm[2], me_max = qm[3],
    n_ge50 = sum(n$n_all >= 50), n_me_ge50 = sum(n$is_me & n$n_all >= 50),
    n_me_le25 = sum(n$is_me & n$n_all <= 25))
}
writeLines(toJSON(rows, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), out)
cat("done", length(rows), "\n")
