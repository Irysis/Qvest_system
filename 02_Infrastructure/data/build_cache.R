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

# ─── 1. Benchmark(코스피200=IKS200) + Indices — Python 빌더 경유 ──────────────
# 2026-07-02 도훈 mandate: 기존 R 경로(read.xlsx startRow=8 + QT_to_xts + [,"IKS200"])가
# Benchmark_price.xlsx에 지수 컬럼이 대폭 추가되며 IKS001(코스피 전체, 수천대)을 잘못 선택,
# benchmark.parquet에 코스피200이 아닌 코스피 전체가 들어가는 버그 발견(북 벤치 전체 오염).
# build_index_cache.py가 Code 행을 명시 매칭해 정확한 IKS200 추출 + 전 18지수 indices.parquet
# 생성. sanity 가드(benchmark.parquet == indices.parquet$kospi200)로 재발 차단.
cat("[1/3] Benchmark(코스피200) + Indices — build_index_cache.py...\n")
PYEXE <- Sys.getenv("QVEST_PY", file.path(PROJECT_ROOT, ".venv_qvest_ml/Scripts/python.exe"))
rc <- system2(PYEXE, args = shQuote(file.path(FUNC_PATH, "data/build_index_cache.py")),
              env = paste0("QM_ROOT=", PROJECT_ROOT))
if (rc != 0) stop("[build_cache] build_index_cache.py 실패 (rc=", rc, ") — 벤치 미갱신")
BM_DT  <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
IDX_DT <- as.data.table(read_parquet(file.path(CACHE_DIR, "indices.parquet")))
if (abs(tail(BM_DT$BM_Close, 1) - tail(IDX_DT$kospi200, 1)) > 1e-6)
  stop("[build_cache] benchmark sanity FAIL: benchmark.parquet != kospi200 (코스피 전체 오선택 의심)")
BM_DT[, Date := as.Date(Date)]
cat(sprintf("  > Benchmark(코스피200): %d rows | 최근 %.1f | Indices %d지수\n",
            nrow(BM_DT), tail(BM_DT$BM_Close, 1), ncol(IDX_DT) - 1L))
rm(IDX_DT); gc()

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

# [guard 2026-07-11] 직접 실행 시 API-tail 소실 방어 — 기존 캐시가 신규 빌드보다 뒤
# 날짜를 보유하면(xlsx 커버리지 < 기존 캐시), 기존 캐시를 백업 후 경고. 표준 경로는
# incremental_cache_update.R::incremental_rawdata() (Date > xlsx_max 꼬리 자동 복원).
# 실사고: 2026-07-02 직접 실행 → 03-28 이후 전체가 base xlsx(~03-27) 내용으로 대체,
# KRX/Naver 실수집 2026-03-30~04-29 소실 (rawdata_april_gap_incident_20260711 참조).
.rawdata_out <- file.path(CACHE_DIR, "RAWDATA.parquet")
if (file.exists(.rawdata_out)) {
  .old_max <- tryCatch(
    max(as.Date(as.data.table(read_parquet(.rawdata_out, col_select = "Date"))$Date), na.rm = TRUE),
    error = function(e) as.Date(NA))
  .new_max <- max(RAWDATA$Date)
  if (!is.na(.old_max) && .old_max > .new_max) {
    .guard_bak <- file.path(CACHE_DIR, "RAWDATA_prebuild_bak.parquet")
    file.copy(.rawdata_out, .guard_bak, overwrite = TRUE)
    cat(sprintf("⚠️ [guard] 기존 캐시 max(%s) > 신규 빌드 max(%s) — API 수집 꼬리가 이 빌드로 유실됨.\n",
                .old_max, .new_max))
    cat(sprintf("   기존 캐시 백업: %s\n", .guard_bak))
    cat("   → incremental_cache_update.R::incremental_rawdata() 경유가 표준(꼬리 자동 복원).\n")
    cat("   → 직접 실행했다면 백업에서 Date > 신규 max 구간을 복원한 뒤 사용할 것.\n")
  }
  gc(verbose = FALSE)
}

# 최종 RAWDATA Parquet 저장 (전체 종목, Sector/Name 없음)
# [fix 2026-07-11] 위 guard가 기존 캐시를 read(mmap)하므로 동일 경로 직접 write 시
# Windows arrow error 1224 위험 — temp-rename 패턴 (krx_build_rawdata 동일)
.raw_tmp <- paste0(.rawdata_out, ".tmp")
write_parquet(RAWDATA, .raw_tmp)
if (file.exists(.rawdata_out)) file.remove(.rawdata_out)
file.rename(.raw_tmp, .rawdata_out)

cat(sprintf("\n=== Cache Build Complete ===\n"))
cat(sprintf("RAWDATA: %d rows | %d tickers | %s ~ %s\n",
            nrow(RAWDATA), uniqueN(RAWDATA$Ticker),
            min(RAWDATA$Date), max(RAWDATA$Date)))
cat(sprintf("Cache dir: %s\n", CACHE_DIR))
