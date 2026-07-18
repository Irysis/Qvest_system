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
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/factor_db")
INFRA_DIR <- tryCatch(dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure")

if (!exists("PROJECT_ROOT")) source(file.path(INFRA_DIR, "config.R"))
if (!is.loaded("roll_beta_cpp")) sourceCpp(file.path(.SELF_DIR, "factor_db_daily_rcpp.cpp"))

FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")

# ─── 핵심 함수: 단일 월 갱신 ─────────────────────────────────────────────────
update_daily_fdb <- function(ym, verbose = TRUE) {
  # ⚠ PARITY-PENDING (2026-07-18): 구조 parity는 통과(318col·행·키·registry 보존)하나 값 parity 미달 —
  #   6년 룩백 창이 β/vol/고차모멘트 42/316 팩터를 full-build와 미재현(D08_Tail_Beta의 full-series
  #   sd(bm)·Coskewness/Skewness·CR05 등 비율/모멘트 blowup). 대부분 부동소수(~1e-9)이나 일부 대폭.
  #   → 자동경로(update_daily_fdb_current)는 full-rebuild 유지. 이 함수는 실험/후속(task_bfa91032)용.
  #   parity 확정 경로: 영향 42팩터의 full-series 의존 규명 → 해당 팩터만 full-history 또는 창 확대.
  # 진짜 단일월 증분 (2026-07-18 task#5). phase6+7+8을 FDB_INCR_YM=ym으로 각 별도 R 프로세스 실행:
  #   삭제 없음 · 단일월 additive merge · RW 룩백창 ≥1300 거래일(M12=1260d) · 글로벌 registry 보존.
  #   ~2-4분(전량 48분 아님). 셸 드라이버 경유 = arrow Windows 1224(read→write 같은경로) 회피 위해
  #   phase당 별도 프로세스 필수. phase 스크립트의 FDB_INCR_YM 가드가 없으면 full-rebuild 동작(무해).
  #   [구 stub 폐기: source(phase6)로 전량 재빌드+전파일삭제를 유발했음 — 2026-06-10 검증된 결함.]
  stopifnot(grepl("^[0-9]{6}$", ym))
  sh <- file.path(.SELF_DIR, "run_fdb_incremental.sh")
  if (!file.exists(sh)) stop("run_fdb_incremental.sh 없음: ", sh)
  if (verbose) cat(sprintf("[daily_fdb] 단일월 증분 %s 실행 (%s)\n", ym, basename(sh)))
  rc <- system2("bash", c(shQuote(sh), ym))
  if (!identical(as.integer(rc), 0L)) stop(sprintf("update_daily_fdb(%s) FAILED rc=%s", ym, rc))
  fpath <- file.path(FDB_DIR, sprintf("fdb_daily_%s.parquet", ym))
  if (verbose) cat(sprintf("[daily_fdb] %s 완료 → %s\n", ym, fpath))
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
  # 2026-07-18(task#5): 자동경로는 **검증된 full-rebuild 드라이버**(phase당 별도 프로세스) 유지.
  #   update_daily_fdb(증분)은 parity-pending(6년 창이 β/vol/고차모멘트 42팩터 미재현 — 예: D08_Tail_Beta
  #   의 full-series sd(bm), 비율/모멘트 blowup). parity 확정(차기 세션) 후 증분으로 전환.
  #   구 one-process source(phase6,7,8)는 arrow 1224 회피 위해 드라이버로 대체.
  sh <- file.path(.SELF_DIR, "run_fdb_rebuild.sh")
  cat(sprintf("[daily_fdb] 전량 재빌드(검증 full path, phase당 별도 프로세스, ~48분) — %s\n", basename(sh)))
  rc <- system2("bash", shQuote(sh))
  if (!identical(as.integer(rc), 0L)) stop(sprintf("full rebuild FAILED rc=%s", rc))
  invisible(TRUE)
}

cat("[factor_db_daily_incremental] Ready.\n")
cat("  update_daily_fdb('202604')        — 단일 월\n")
cat("  update_daily_fdb_range(from, to)  — 범위 (전체 재빌드)\n")
cat("  update_daily_fdb_current()        — 현재 월\n")
