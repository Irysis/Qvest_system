# =============================================================================
# build_lo_rawdata_cache.R — RAWDATA 의존도 1회 캐시 (★ OOM 근본 fix, 2026-06-06)
# =============================================================================
#   ★ 도훈 mandate: long-only batch OOM 완전 근본 fix (RAWDATA layer).
#
#   ★ 근본 원인:
#     factor 캐시(_factor_cache.rds)로 factor parquet read는 제거했으나, 각 factor run이
#     여전히 load_rawdata(RAWDATA 13.9M행 378MB arrow)를 *매번 반복 read* → arrow
#     메모리맵/read가 layer마다(factor→RAWDATA) 비결정 OOM(batch2 D01 사망: arrow
#     "Cache loaded: 13957686 rows" 직후 crash, json 미생성).
#
#   ★ fix: RAWDATA로 driver가 쓰는 *factor-무관* 산출물 2종을 batch 전체 1회 빌드:
#     ① universe(.mem): K200∪KQ150 멤버십 + 20일 평균거래대금 2e8 월말 (Date, Ticker)
#     ② me_panel: 월말 Close → forward 1M 보유수익 (Date, Ticker, Close, ret_fwd, ret_date)
#     ③ bm: 월간 benchmark 구간복리용 daily BM_Ret (Date, BM_Ret) — 작아서 같이 캐시
#     → 각 factor run은 이 RDS만 로드(arrow read 0회) → load_rawdata 호출 제거 → OOM 제거.
#
#   ★ PIT (캐시에 lookahead 없음, C2/C10):
#     - me_panel ret_fwd = shift(Close, 1L, "lead")/Close - 1 by Ticker
#       (d 편입결정 -> 다음 월말 nd 실현; forward 1M, 동일시점 순환참조 없음). driver와 비트동일.
#     - universe 유동성 = frollmean(Close*Vol, 20L, "right") (과거 윈도우 t-1 PIT). 월말 평가.
#     - 멤버십 K200/KQ150 = 시변 컬럼 (해당 월말 시점 멤버). survivorship 없음.
#     - 캐시 mem 로직은 driver_lo_screen.R lines 72-85와 *동일* → universe 정합 보장.
#
#   ★ 자체합성 금지 정합: 본 스크립트는 측정/백테 수치를 만들지 않음(universe panel + Close
#     forward return raw 산출만). 포트 수익률 구성/score는 driver가 Return.portfolio로 수행.
#
#   출력(stage_artifacts/alpha_search/lo_screen/):
#     _universe_cache.rds  (Date, Ticker)  — mem
#     _me_panel_cache.rds  (Ticker, Date, Close, ret_fwd, ret_date)  setkey(Ticker,Date)
#     _bm_cache.rds        (Date, BM_Ret)
#   호출(PowerShell, BOM 없이):
#     Rscript -e "source('stage_artifacts/alpha_search/build_lo_rawdata_cache.R')"
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(arrow)
}))

PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))   # load_rawdata

OUT_DIR <- file.path(PROJ, "stage_artifacts", "alpha_search", "lo_screen")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
UNI_PATH  <- file.path(OUT_DIR, "_universe_cache.rds")
MEP_PATH  <- file.path(OUT_DIR, "_me_panel_cache.rds")
BM_PATH   <- file.path(OUT_DIR, "_bm_cache.rds")

START_DATE <- as.Date("2005-01-01")
.fdb_min   <- as.Date("2002-08-01")   # factor DB value/fundamental 가용 시작 (driver와 동일)

cat("\n=== [build_lo_rawdata_cache] RAWDATA 의존도 1회 캐시 (arrow read 1회) ===\n")

# ---- RAWDATA arrow read (★ batch 전체에서 단 1회) ----
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date,  "Date")) BM_DT[,  Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
cat(sprintf("[cache] RAWDATA rows=%d | %s ~ %s | tickers=%d\n",
            nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ---- ① universe (.mem): 멤버십 + 유동성 2e8 월말 (driver lines 72-85 동일) ----
.rd_slim <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
setorder(.rd_slim, Ticker, Date)
.rd_slim[, .ym := format(Date, "%Y-%m")]
me_dates <- sort(.rd_slim[, .(Date = max(Date)), by = .ym]$Date)   # 월말일
.rd_slim[, .ym := NULL]
me_dates <- me_dates[me_dates >= .fdb_min]
.rd_slim[, .TV := Close * Vol]
.rd_slim[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]   # 과거 20일 윈도우 (PIT)
mem <- .rd_slim[Date %in% me_dates & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(mem, Date, Ticker)
rm(.rd_slim); gc(FALSE)
cat(sprintf("[cache] universe(.mem): rows=%d | months=%d | %s ~ %s\n",
            nrow(mem), uniqueN(mem$Date), min(mem$Date), max(mem$Date)))

# ---- ② me_panel: 월말 Close -> forward 1M 보유수익 (driver lines 128-134 동일) ----
me_panel <- RAWDATA[Date %in% me_dates, .(Date, Ticker, Close)]
rm(RAWDATA); gc(FALSE)
setorder(me_panel, Ticker, Date)
me_panel[, ret_fwd  := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]   # forward 1M (C2 safe)
me_panel[, ret_date := shift(Date,  1L, type = "lead"), by = Ticker]
setkey(me_panel, Ticker, Date)
cat(sprintf("[cache] me_panel: rows=%d | months=%d | ret_fwd non-NA=%d\n",
            nrow(me_panel), uniqueN(me_panel$Date), sum(is.finite(me_panel$ret_fwd))))

# ---- ③ bm: daily BM_Ret (driver lines 182-191 입력, 작음) ----
setorder(BM_DT, Date)
bm_d <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret)]
rm(BM_DT); gc(FALSE)
cat(sprintf("[cache] bm: rows=%d | %s ~ %s\n", nrow(bm_d), min(bm_d$Date), max(bm_d$Date)))

# ---- save ----
saveRDS(mem,      UNI_PATH, compress = TRUE)
saveRDS(me_panel, MEP_PATH, compress = TRUE)
saveRDS(bm_d,     BM_PATH,  compress = TRUE)
cat(sprintf("\n[SAVED] %s (%.1f KB)\n", basename(UNI_PATH), file.size(UNI_PATH)/1024))
cat(sprintf("[SAVED] %s (%.1f MB)\n",   basename(MEP_PATH), file.size(MEP_PATH)/1024/1024))
cat(sprintf("[SAVED] %s (%.1f KB)\n",   basename(BM_PATH),  file.size(BM_PATH)/1024))
cat("[build_lo_rawdata_cache] DONE — 이후 driver_lo_screen.R는 arrow read 0회.\n")
