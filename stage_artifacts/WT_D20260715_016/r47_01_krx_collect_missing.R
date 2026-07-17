#==============================================================================
# R47 STEP 01: KRX 캐시 없는 8 거래일 live 수집 (캐시-only write, rawdata 무변경)
#   reachability gate: 첫 날 실패 시 즉시 STOP
#   대상 = diagnostic이 특정한 06-18,19,23,24,25,26,29,30 (universe엔 있으나 KRX캐시 부재)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
try(arrow::set_io_thread_count(2), silent = TRUE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "krx_data_collector.R"))
WT <- file.path(ROOT, "stage_artifacts", "WT_D20260715_016")
log <- function(...) cat(sprintf(...), "\n")

missing_days <- c("20260618","20260619","20260623","20260624","20260625","20260626","20260629","20260630")

# ── reachability gate ────────────────────────────────────────────────────────
log("[gate] KRX API reachability test on %s ...", missing_days[1])
test <- krx_stk_ohlcv(missing_days[1])
if (is.null(test) || nrow(test) == 0) {
  log("[gate][FAIL] KRX API returned NULL/empty. live 수집 불가 — STOP. (56/64 캐시일만 채움 가능, 8일 잔여)")
  writeLines(jsonlite::toJSON(list(api_reachable=FALSE, tested=missing_days[1]), auto_unbox=TRUE, pretty=TRUE),
             file.path(WT, "r47_krx_collect_result.json"))
  quit(status = 0)
}
log("[gate][PASS] KRX API OK — %s returned %d KOSPI rows. 8일 수집 진행.", missing_days[1], nrow(test))

# ── collect all 8 (krx_collect_daily writes cache parquets only) ─────────────
res <- list()
for (ds in missing_days) {
  ok <- tryCatch({
    krx_collect_daily(ds)
    stkf <- file.path(KRX_CACHE_DIR, "stk_ohlcv", sprintf("stk_ohlcv_%s.parquet", ds))
    ksqf <- file.path(KRX_CACHE_DIR, "ksq_ohlcv", sprintf("ksq_ohlcv_%s.parquet", ds))
    list(ds=ds, stk=file.exists(stkf), ksq=file.exists(ksqf))
  }, error = function(e) { log("[ERR] %s: %s", ds, e$message); list(ds=ds, stk=FALSE, ksq=FALSE) })
  res[[ds]] <- ok
}
resdt <- rbindlist(lapply(res, as.data.table))
log("\n[collect] 결과:")
print(resdt)
log("[collect] stk 확보 %d/8 | ksq 확보 %d/8", sum(resdt$stk), sum(resdt$ksq))

writeLines(jsonlite::toJSON(list(api_reachable=TRUE, days=resdt,
           stk_ok=sum(resdt$stk), ksq_ok=sum(resdt$ksq)), auto_unbox=TRUE, pretty=TRUE),
           file.path(WT, "r47_krx_collect_result.json"))
log("[done] collect result written.")
