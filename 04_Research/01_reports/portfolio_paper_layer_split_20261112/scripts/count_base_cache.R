## 개수만 센다 — 기저 캐시(.base_sig)의 신호일당 종목 수 · 신호일 격자가 월말 거래일인지.
## 성과 수치(수익 · 등급 · PORT_t · 위기 방어)는 읽지 않는다. 읽는 열 = Date · Ticker · .base_sig 부호(양/음/0) 뿐.
suppressMessages({ library(data.table); library(arrow) })
args <- commandArgs(trailingOnly = TRUE)
root <- args[1]; cache <- args[2]
b <- readRDS(cache)
b <- as.data.table(b)
cat("cols:", paste(names(b), collapse = ","), " rows:", nrow(b), "\n")
b[, Date := as.Date(Date)]
n <- b[, .(n_all = .N, n_pos = sum(.base_sig > 0, na.rm = TRUE), n_neg = sum(.base_sig < 0, na.rm = TRUE),
           n_zero = sum(.base_sig == 0, na.rm = TRUE), n_na = sum(is.na(.base_sig))), by = Date][order(Date)]
q <- function(v) sprintf("min %d · 중앙 %s · 최대 %d", min(v), format(stats::median(v)), max(v))
cat("신호일 수:", nrow(n), " 기간:", format(min(n$Date)), "~", format(max(n$Date)), "\n")
cat("신호일당 종목(전체):", q(n$n_all), "\n")
cat("신호일당 종목(양수):", q(n$n_pos), " 음수 있는 날:", sum(n$n_neg > 0), " 0 있는 날:", sum(n$n_zero > 0), "\n")
## 거래일 달력 — rawdata.parquet 의 Date 열만
rp <- file.path(root, ".cache", "rawdata.parquet")
cal <- sort(unique(as.Date(arrow::read_parquet(rp, col_select = "Date")$Date)))
cat("거래일 달력:", length(cal), "일", format(min(cal)), "~", format(max(cal)), "\n")
me <- cal[!duplicated(format(cal, "%Y%m"), fromLast = TRUE)]
n[, is_me := Date %in% me]
cat("월말 거래일인 신호일:", sum(n$is_me), "/", nrow(n), "\n")
gap <- diff(match(n$Date, cal))
cat("신호일 간격(거래일):", q(as.integer(gap[!is.na(gap)])), "\n")
if (sum(n$is_me)) cat("월말 신호일의 종목 수:", q(n[is_me == TRUE]$n_all), "\n")
cat("전체 폭 ≥ 50 인 신호일:", sum(n$n_all >= 50), " · 월말이면서 ≥ 50:", sum(n$is_me & n$n_all >= 50), "\n")
