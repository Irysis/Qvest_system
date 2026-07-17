#==============================================================================
# R47 — 4월 이음매 microcap Close 구멍 KRX 백필 리빌드
# STEP 00: READ-ONLY DIAGNOSTIC (백필 착수 전 실측 — 아무것도 쓰지 않음)
#   - 현 rawdata 상태 (rows / date range / max Ret)
#   - 218 source-seam 타깃 hole 잔존 확인
#   - 채울 (Ticker, Date) 집합 정확 산출 (append-only 대상)
#   - KRX 일별 캐시 coverage (gap 거래일별 stk/ksq parquet 존재 여부)
#   - 타깃 티커가 캐시 일별파일에 실재하는지 sample 검증
#   - 유니버스 침투 재확인 (독립)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
try(arrow::set_io_thread_count(2), silent = TRUE)   # io(1)은 parquet read HANG (RAMP 실사고) → io(2)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RAWDATA_CACHE <- file.path(ROOT, ".cache", "RAWDATA.parquet")
KRX_CACHE_DIR <- file.path(ROOT, ".cache", "krx")
WT <- file.path(ROOT, "stage_artifacts", "WT_D20260715_016")
holes_csv <- file.path(ROOT, "stage_artifacts", "WT_D20260715_015", "close_continuity_holes_r46.csv")

log <- function(...) cat(sprintf(...), "\n")

# ── 1. 타깃 hole 목록 ────────────────────────────────────────────────────────
holes <- fread(holes_csv)
log("[holes] total rows in R46 CSV: %d", nrow(holes))
log("[holes] source_seam=TRUE: %d | in_universe=TRUE: %d", sum(holes$source_seam), sum(holes$in_universe))
target <- holes[source_seam == TRUE]        # 218 = 실제 백필 표적
log("[target] source_seam holes: %d | unique tickers: %d", nrow(target), uniqueN(target$Ticker))
log("[target] universe rows in target: %d (MUST be 0)", sum(target$in_universe))
# 그룹: 04-29->07-02 April cluster vs 03-27->04-30 seam
target[, grp := fifelse(prevDate=="2026-04-29" & Date=="2026-07-02", "aprilcluster",
                 fifelse(Date=="2026-04-30", "aprilseam", "other"))]
print(target[, .N, by=grp])

# ── 2. 현 rawdata 상태 (col_select로 경량 로드) ──────────────────────────────
raw <- as.data.table(read_parquet(RAWDATA_CACHE,
        col_select = c("Date","Ticker","Close","Ret","source")))
raw[, Date := as.Date(Date)]
log("\n[rawdata] total rows: %d", nrow(raw))
log("[rawdata] date range: %s ~ %s", as.character(min(raw$Date)), as.character(max(raw$Date)))
log("[rawdata] unique tickers: %d", uniqueN(raw$Ticker))
log("[rawdata] max |Ret|: %.2f (R43 census=66999 expected)", max(abs(raw$Ret), na.rm=TRUE))

# ── 3. 채울 (Ticker, Date) 집합 산출 ─────────────────────────────────────────
# 거래일 = rawdata에 존재하는 distinct Date (유니버스 완전커버 → 이 window의 캘린더)
all_dates <- sort(unique(raw$Date))
# 각 타깃 티커의 gap [prevDate, Date] 내부의 거래일 중 rawdata에 (T,d) 부재인 것
fill_set <- rbindlist(lapply(seq_len(nrow(target)), function(i) {
  tk <- target$Ticker[i]; pd <- as.Date(target$prevDate[i]); nd <- as.Date(target$Date[i])
  gap_days <- all_dates[all_dates > pd & all_dates < nd]
  if (length(gap_days) == 0) return(NULL)
  have <- raw[Ticker == tk & Date %in% gap_days, Date]
  need <- setdiff(as.character(gap_days), as.character(have))
  if (length(need) == 0) return(NULL)
  data.table(Ticker = tk, Date = as.Date(need))
}))
log("\n[fill_set] total (Ticker,Date) to fill: %d", nrow(fill_set))
log("[fill_set] unique tickers: %d | unique dates: %d", uniqueN(fill_set$Ticker), uniqueN(fill_set$Date))
log("[fill_set] date range: %s ~ %s", as.character(min(fill_set$Date)), as.character(max(fill_set$Date)))
# 안전 재확인: fill_set의 (T,d)가 정말 rawdata에 부재인가
mrg <- merge(fill_set, raw[, .(Ticker, Date, exists=TRUE)], by=c("Ticker","Date"), all.x=TRUE)
log("[fill_set] SANITY — already-present (must be 0): %d", sum(!is.na(mrg$exists)))

# ── 4. KRX 캐시 coverage (gap 거래일별) ──────────────────────────────────────
need_dates <- sort(unique(fill_set$Date))
cov <- rbindlist(lapply(need_dates, function(d) {
  ds <- format(d, "%Y%m%d")
  stkf <- file.path(KRX_CACHE_DIR, "stk_ohlcv", sprintf("stk_ohlcv_%s.parquet", ds))
  ksqf <- file.path(KRX_CACHE_DIR, "ksq_ohlcv", sprintf("ksq_ohlcv_%s.parquet", ds))
  data.table(Date=d, ds=ds, has_stk=file.exists(stkf), has_ksq=file.exists(ksqf))
}))
log("\n[cache] gap 거래일 %d개 | stk 존재 %d | ksq 존재 %d | 양쪽부재 %d",
    nrow(cov), sum(cov$has_stk), sum(cov$has_ksq), sum(!cov$has_stk & !cov$has_ksq))
missing_cache <- cov[!has_stk | !has_ksq]
if (nrow(missing_cache) > 0) {
  log("[cache] 캐시 없는 거래일 (live API 필요):")
  print(missing_cache)
}

# ── 5. 타깃 티커가 캐시 일별파일에 실재? (첫 available 캐시일로 sample) ───────
sample_ds <- cov[has_stk == TRUE][1]$ds
if (!is.na(sample_ds)) {
  stk <- as.data.table(read_parquet(file.path(KRX_CACHE_DIR,"stk_ohlcv",sprintf("stk_ohlcv_%s.parquet",sample_ds))))
  ksq_f <- file.path(KRX_CACHE_DIR,"ksq_ohlcv",sprintf("ksq_ohlcv_%s.parquet",sample_ds))
  ksq <- if (file.exists(ksq_f)) as.data.table(read_parquet(ksq_f)) else data.table()
  cache_tickers <- unique(paste0("A", c(stk$ISU_CD, if(nrow(ksq)) ksq$ISU_CD else character(0))))
  tgt_on_day <- fill_set[Date == as.Date(sample_ds, "%Y%m%d"), unique(Ticker)]
  present <- intersect(tgt_on_day, cache_tickers)
  log("\n[cache-sample %s] 그날 채울 티커 %d개 중 캐시에 실재 %d개 (%.0f%%)",
      sample_ds, length(tgt_on_day), length(present), 100*length(present)/max(1,length(tgt_on_day)))
  log("[cache-sample] KRX 캐시 컬럼: %s", paste(head(names(stk),20), collapse=", "))
  absent <- setdiff(tgt_on_day, cache_tickers)
  if (length(absent)>0) log("[cache-sample] 캐시에 없는 타깃(그날 미거래 가능): %s",
                            paste(head(absent,15), collapse=", "))
}

# ── 6. per-ticker gap 요약 (top by n_fill) ──────────────────────────────────
perT <- fill_set[, .(n_fill=.N, first=min(Date), last=max(Date)), by=Ticker][order(-n_fill)]
log("\n[per-ticker] n_fill 분포: min=%d median=%d max=%d", min(perT$n_fill), as.integer(median(perT$n_fill)), max(perT$n_fill))
log("[per-ticker] top 5 by n_fill:")
print(head(perT,5))

# ── save ────────────────────────────────────────────────────────────────────
fwrite(fill_set, file.path(WT, "r47_fill_set.csv"))
fwrite(cov, file.path(WT, "r47_cache_coverage.csv"))
fwrite(perT, file.path(WT, "r47_per_ticker_gap.csv"))
diag <- list(
  rawdata_rows = nrow(raw),
  rawdata_min = as.character(min(raw$Date)), rawdata_max = as.character(max(raw$Date)),
  rawdata_tickers = uniqueN(raw$Ticker), rawdata_max_abs_ret = max(abs(raw$Ret), na.rm=TRUE),
  target_holes = nrow(target), target_tickers = uniqueN(target$Ticker),
  target_universe_rows = sum(target$in_universe),
  fill_rows = nrow(fill_set), fill_tickers = uniqueN(fill_set$Ticker),
  fill_dates = uniqueN(fill_set$Date),
  fill_already_present = sum(!is.na(mrg$exists)),
  gap_trading_days = nrow(cov), cache_stk = sum(cov$has_stk), cache_ksq = sum(cov$has_ksq),
  cache_missing_days = nrow(missing_cache),
  cache_missing_ds = if(nrow(missing_cache)) missing_cache$ds else character(0)
)
writeLines(jsonlite::toJSON(diag, auto_unbox=TRUE, pretty=TRUE), file.path(WT, "r47_diagnose.json"))
log("\n[done] diagnostic written to %s", WT)
