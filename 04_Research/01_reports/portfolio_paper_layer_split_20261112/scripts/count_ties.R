## 개수만 센다 — 포트폴리오만 내는 엔진의 기저 캐시(.base_sig = 비중)에서 롱 다리의 '서로 다른 비중 값 개수'(신호일 중앙값).
##   1 이면 롱 다리 전원 동점 → 표준 구성의 상위 25종은 동점 규칙(20일 거래대금 순)으로 뽑힌다. 성과 수치는 읽지 않는다.
suppressMessages({ library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
root <- args[1]; static_json <- args[2]
st <- fromJSON(static_json, simplifyVector = FALSE)
cdir <- file.path(root, ".cache", "rf_base_signal")
allc <- list.files(cdir, pattern = "^base_v2_.*\\.rds$", full.names = TRUE)
for (r in st) {
  if (!isTRUE(r$has_engine) || !identical(r$outputs, "PORTFOLIO")) next
  fs <- allc[grepl(paste0("^base_v2_", substr(r$md5, 1, 12), "_"), basename(allc))]
  if (!length(fs)) next
  for (f in fs[order(file.info(fs)$mtime)]) {
    b <- as.data.table(readRDS(f)); b[, Date := as.Date(Date)]
    b <- b[!is.na(.base_sig) & Date >= as.Date("2000-01-01")]
    d <- sort(unique(b$Date))
    n <- b[.base_sig > 0, .(n_long = .N, n_distinct = uniqueN(signif(.base_sig, 10))), by = Date]
    cat(sprintf("%-34s %s | 신호일 %d (%s ~ %s) | 롱 종목 중앙 %s | 롱 비중의 서로 다른 값 수 중앙 %s (최소 %d · 최대 %d)\n",
                sub("RP_AUTO_", "", r$dir), substr(basename(f), 21, 28), length(d), format(min(d)), format(max(d)),
                format(stats::median(n$n_long)), format(stats::median(n$n_distinct)), min(n$n_distinct), max(n$n_distinct)))
  }
}
