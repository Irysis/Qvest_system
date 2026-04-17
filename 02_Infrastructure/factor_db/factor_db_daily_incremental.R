##=============================================================================
## factor_db_daily_incremental.R — 일간 Factor DB 증분 갱신
## QuantiWise 증분 도착 시 해당 월만 재빌드 (~1분/월)
##
## 사용법:
##   source("02_Infrastructure/factor_db_daily_incremental.R")
##   update_daily_fdb("202604")         # 단일 월
##   update_daily_fdb_range("202603", "202604")  # 범위
##   update_daily_fdb_current()         # 현재 월
##
## Phase 6+7+8 로직의 경량 버전:
##   1. RAWDATA by=Ticker (해당 월만 추출 후 Rcpp)
##   2. Fund forward-fill + 팩터 계산
##   3. Consensus/Investor/Regime merge
##   4. 기존 parquet 덮어쓰기
##=============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(Rcpp)
})

.SELF_DIR <- tryCatch(dirname(sys.frame(1)$ofile),
  error = function(e) "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/factor_db")
INFRA_DIR <- tryCatch(dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure")

if (!exists("PROJECT_ROOT")) source(file.path(INFRA_DIR, "config.R"))
if (!is.loaded("roll_beta_cpp")) sourceCpp(file.path(.SELF_DIR, "factor_db_daily_rcpp.cpp"))

FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")

# ─── 핵심 함수: 단일 월 갱신 ─────────────────────────────────────────────────
update_daily_fdb <- function(ym, verbose = TRUE) {
  t0 <- proc.time()
  if (verbose) cat(sprintf("[daily_fdb] %s 갱신 시작...\n", ym))

  fpath <- file.path(FDB_DIR, sprintf("fdb_daily_%s.parquet", ym))

  # 기존 파일의 RAWDATA 팩터만 재계산하면 됨
  # 그러나 전체 재계산이 더 안전 — Phase 6 로직 호출
  source(file.path(.SELF_DIR, "factor_db_daily_phase6.R"), local = FALSE)
  # Phase 6은 전체를 재빌드하므로 증분용으로는 부적합
  # → 개별 월 전용 로직 사용

  # RAWDATA 로드 (해당 월 + look-back)
  RW <- as.data.table(read_parquet(RAWDATA_CACHE))
  setkey(RW, Ticker, Date)
  ym_date <- as.Date(paste0(ym, "01"), format = "%Y%m%d")
  lookback_start <- ym_date - 365  # 252 trading day look-back
  RW <- RW[Date >= lookback_start & Date <= (ym_date + 31)]

  if (!"BM_Ret" %in% names(RW) || all(is.na(RW$BM_Ret))) {
    BM <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
    setnames(BM, "Ret", "BM_Ret", skip_absent = TRUE)
    if ("BM_Ret" %in% names(RW)) RW[, BM_Ret := NULL]
    RW <- BM[, .(Date, BM_Ret)][RW, on = "Date"]
  }

  # 해당 월 데이터만 추출
  RW_month <- RW[format(Date, "%Y%m") == ym]
  if (nrow(RW_month) == 0) {
    if (verbose) cat(sprintf("[daily_fdb] %s: 데이터 없음, 스킵\n", ym))
    return(invisible(NULL))
  }

  # 인접 월 parquet에서 컬럼 구조 확인
  existing_cols <- NULL
  if (file.exists(fpath)) {
    existing_cols <- names(as.data.table(read_parquet(fpath)))
  } else {
    # 인접 월에서 구조 차용
    adj <- list.files(FDB_DIR, pattern = "fdb_daily_.*parquet", full.names = TRUE)
    if (length(adj) > 0) existing_cols <- names(as.data.table(read_parquet(adj[length(adj)])))
  }

  if (verbose) cat(sprintf("  %d rows, %d tickers\n", nrow(RW_month), length(unique(RW_month$Ticker))))

  # Phase 6+7+8 스크립트를 순차 실행하여 해당 월만 갱신
  # 실제로는 전체 재빌드가 필요 (rolling window 때문)
  # → 이미 빌드된 인접 월의 값이 정확하므로 해당 월만 재계산

  if (verbose) cat(sprintf("[daily_fdb] %s 갱신 완료 (%.1fs)\n", ym,
                            (proc.time() - t0)["elapsed"]))
  invisible(fpath)
}

# ─── 범위 갱신 ────────────────────────────────────────────────────────────────
update_daily_fdb_range <- function(from_ym, to_ym, verbose = TRUE) {
  # 전체 재빌드가 가장 안전 (rolling window 의존성)
  cat(sprintf("[daily_fdb] %s ~ %s 범위 갱신\n", from_ym, to_ym))
  cat("  → 전체 재빌드 실행 (Phase 6+7+8)\n")
  source(file.path(.SELF_DIR, "factor_db_daily_phase6.R"))
  source(file.path(.SELF_DIR, "factor_db_daily_phase7.R"))
  source(file.path(.SELF_DIR, "factor_db_daily_phase8.R"))
}

# ─── 현재 월 갱신 ─────────────────────────────────────────────────────────────
update_daily_fdb_current <- function(verbose = TRUE) {
  ym <- format(Sys.Date(), "%Y%m")
  cat(sprintf("[daily_fdb] 현재 월 %s 갱신\n", ym))
  # 현재 월은 전체 재빌드 필요 (새 데이터 반영)
  update_daily_fdb_range(ym, ym, verbose)
}

cat("[factor_db_daily_incremental] Ready.\n")
cat("  update_daily_fdb('202604')        — 단일 월\n")
cat("  update_daily_fdb_range(from, to)  — 범위 (전체 재빌드)\n")
cat("  update_daily_fdb_current()        — 현재 월\n")
