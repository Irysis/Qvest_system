#==============================================================================
# R47 STEP 02: seam 경계 실측 (READ-ONLY) — Ret 계산·parity 설계 근거
#   타깃 티커의 rawdata 시퀀스(04-27~07-03) + KRX 캐시 07-01 Close 대조
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RAWDATA_CACHE <- file.path(ROOT, ".cache", "RAWDATA.parquet")
KRX_CACHE_DIR <- file.path(ROOT, ".cache", "krx")
log <- function(...) cat(sprintf(...), "\n")

# KRX transform (krx_build_rawdata.R::krx_transform_daily 축약 — Close만)
krx_close_on <- function(ds, tickers) {
  out <- list()
  for (mk in c("stk_ohlcv","ksq_ohlcv")) {
    f <- file.path(KRX_CACHE_DIR, mk, sprintf("%s_%s.parquet", mk, ds))
    if (file.exists(f)) {
      d <- as.data.table(read_parquet(f))
      d[, Ticker := paste0("A", ISU_CD)]
      d[, Close := as.numeric(gsub(",", "", TDD_CLSPRC))]
      out[[mk]] <- d[Ticker %in% tickers, .(Ticker, Close)]
    }
  }
  rbindlist(out, fill=TRUE)
}

raw <- as.data.table(read_parquet(RAWDATA_CACHE,
        col_select=c("Date","Ticker","Close","Ret","source")))
raw[, Date := as.Date(Date)]

samples <- c("A004415","A000087","A002995","A005935","A279570")  # 큰점프/일반/preferred/케뱅
for (tk in samples) {
  log("\n===== %s =====", tk)
  seq <- raw[Ticker==tk & Date>=as.Date("2026-04-27") & Date<=as.Date("2026-07-03")][order(Date)]
  print(seq)
  # KRX 07-01 Close for this ticker
  k0701 <- krx_close_on("20260701", tk)
  k0630 <- krx_close_on("20260630", tk)
  log("[KRX] %s 07-01 Close=%s | 06-30 Close=%s", tk,
      ifelse(nrow(k0701), as.character(k0701$Close[1]), "MISSING"),
      ifelse(nrow(k0630), as.character(k0630$Close[1]), "MISSING"))
  # 07-02 stored Ret vs implied Close(07-01) from stored
  r0702 <- seq[Date==as.Date("2026-07-02")]
  if (nrow(r0702) && nrow(k0701)) {
    implied_prev <- r0702$Close[1] / (1 + r0702$Ret[1])
    log("[check] 07-02 stored Ret=%.4f → implied prevClose=%.1f | KRX 07-01=%.1f | match=%s",
        r0702$Ret[1], implied_prev, k0701$Close[1],
        ifelse(abs(implied_prev-k0701$Close[1])<1, "YES", "NO"))
  }
}
