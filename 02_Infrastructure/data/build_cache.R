#==============================================================================
# Quant Module — Parquet Cache Builder
# Version: 1.0.0
#
# OHLCVS.xlsx (890MB)를 시트 1장씩 읽어서 Parquet로 변환.
# 이후 backtest_harness.R에서 Parquet 캐시로 초고속 로딩.
#
# Usage: Rscript 02_Infrastructure/build_cache.R
#==============================================================================

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

library(openxlsx)
library(readxl)
library(data.table)
library(xts)
library(arrow)
library(dplyr)

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
RAWDATA_PATH <- file.path(PROJECT_ROOT, "03_Universe")
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")

dir.create(CACHE_DIR, recursive = TRUE, showWarnings = FALSE)

source(file.path(FUNC_PATH, "F1. QT_to_xts.r"))

cat("=== Parquet Cache Builder (v2 — Universe 독립) ===\n\n")
# Universe는 krx_update_universe.R + apply_universe_mapping.R에서 별도 관리.
# build_cache.R은 OHLCVS 수정주가 + Benchmark만 담당.

# ─── 1. Benchmark ───────────────────────────────────────────────────────────

cat("[1/3] Benchmark...\n")
BM_price <- read.xlsx(file.path(RAWDATA_PATH, "Benchmark_price.xlsx"),
                       sheet = 1, startRow = 8,
                       skipEmptyCols = TRUE, na.strings = "NA")
BM_price_xts <- QT_to_xts(BM_price)
BM_DT <- as.data.table(BM_price_xts[, "IKS200"])
setnames(BM_DT, c("index", "IKS200"), c("Date", "BM_Close"))
BM_DT[, Date := as.Date(Date)]
BM_DT[, BM_Ret := BM_Close / shift(BM_Close) - 1]
setkey(BM_DT, Date)

write_parquet(BM_DT, file.path(CACHE_DIR, "benchmark.parquet"))
cat(sprintf("  > Benchmark: %d rows saved\n", nrow(BM_DT)))
rm(BM_price, BM_price_xts)
gc()

# ─── 3. OHLCVS (시트 1장씩 → 개별 Parquet) ─────────────────────────────────

var_names <- c("Open", "High", "Low", "Close", "Vol", "Size")
ohlcvs_path <- file.path(RAWDATA_PATH, "OHLCVS.xlsx")

cat("[2/3] OHLCVS (sheet-by-sheet)...\n")
for (i in seq_along(var_names)) {
  cat(sprintf("  > Sheet %d/6: %s...\n", i, var_names[i]))

  raw_df <- read.xlsx(ohlcvs_path, sheet = i, startRow = 8,
                       skipEmptyCols = TRUE, na.strings = "NA")
  xts_obj <- QT_to_xts(raw_df)
  rm(raw_df); gc()

  dt <- as.data.table(xts_obj)
  setnames(dt, "index", "Date")
  rm(xts_obj); gc()

  # Wide → Long
  long_dt <- melt(dt, id.vars = "Date",
                   variable.name = "Ticker", value.name = var_names[i],
                   variable.factor = FALSE)
  rm(dt); gc()

  write_parquet(long_dt, file.path(CACHE_DIR, paste0("ohlcvs_", var_names[i], ".parquet")))
  cat(sprintf("    saved: %d rows\n", nrow(long_dt)))
  rm(long_dt); gc()
}

# ─── 4. RAWDATA 조립 ────────────────────────────────────────────────────────

cat("[3/3] Assembling RAWDATA from Parquet...\n")

# 첫 번째 시트 로드
RAWDATA_long <- as.data.table(read_parquet(file.path(CACHE_DIR, "ohlcvs_Open.parquet")))
RAWDATA_long[, Date := as.Date(Date)]

# 나머지 시트 병합
for (v in var_names[-1]) {
  tmp <- as.data.table(read_parquet(file.path(CACHE_DIR, paste0("ohlcvs_", v, ".parquet"))))
  tmp[, Date := as.Date(Date)]
  RAWDATA_long <- merge(RAWDATA_long, tmp, by = c("Date", "Ticker"), all = TRUE)
  rm(tmp); gc()
}

setkey(RAWDATA_long, Ticker, Date)

# Universe 조인 없이 RAWDATA 조립 (메타 매핑은 apply_universe_mapping()에서 별도 처리)
RAWDATA <- RAWDATA_long
rm(RAWDATA_long); gc()

# 수익률 계산
RAWDATA[, Ret := Close / shift(Close) - 1, by = Ticker]

# BM 수익률 병합
BM_DT <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
BM_DT[, Date := as.Date(Date)]
RAWDATA <- BM_DT[, .(Date, BM_Ret)][RAWDATA, on = "Date"]
RAWDATA <- RAWDATA[!is.na(Ret) & !is.na(BM_Ret)]
setorder(RAWDATA, Date, Ticker)

# 최종 RAWDATA Parquet 저장 (전체 종목, Sector/Name 없음)
write_parquet(RAWDATA, file.path(CACHE_DIR, "RAWDATA.parquet"))

cat(sprintf("\n=== Cache Build Complete ===\n"))
cat(sprintf("RAWDATA: %d rows | %d tickers | %s ~ %s\n",
            nrow(RAWDATA), uniqueN(RAWDATA$Ticker),
            min(RAWDATA$Date), max(RAWDATA$Date)))
cat(sprintf("Cache dir: %s\n", CACHE_DIR))
