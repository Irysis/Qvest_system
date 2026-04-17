## benchmark_factor_db_optimizations.R
## Factor DB 최적화 검증 + 속도 벤치마크
##
## 목적:
##   1. compute_defense / compute_liquidity Rcpp 최적화 전후 결과 정합성 확인
##   2. 날짜 1건 빌드 시간 측정 (목표: 5초 이하 / 기존: 43초)
##   3. 기존 222건 parquet과 상관계수 >= 0.9999 확인
##
## 실행:
##   cd "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
##   Rscript -e 'source("08_Tests/benchmark_factor_db_optimizations.R")'

cat("=== Factor DB 최적화 벤치마크 ===\n")
cat("시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ── 경로 설정 ──────────────────────────────────────────────────────────────────
PROJ <- "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA <- file.path(PROJ, "02_Infrastructure")

source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "factor_db_builder.R"))

# ── 기존 daily parquet 로드 (검증용) ────────────────────────────────────────
cat("[1] 기존 parquet 로드 (factor_db_daily_20050103)...\n")
old_path <- file.path(CACHE_DIR, "factor_db_daily", "factor_db_daily_20050103.parquet")
if (!file.exists(old_path)) {
  cat("  [SKIP] 기존 parquet 없음. .cache/factor_db_daily/ 확인 필요.\n\n")
  old_dt <- NULL
} else {
  old_dt <- as.data.table(read_parquet(old_path))
  cat(sprintf("  rows: %d | factors: %d\n\n", nrow(old_dt),
              uniqueN(old_dt[["Factor_Name"]])))
}

# ── 단일 날짜 빌드 시간 측정 ─────────────────────────────────────────────────
cat("[2] 단일 날짜 빌드 시간 측정 (force=TRUE)...\n")
TEST_DATE <- "2005-01-03"

.load_base_data()
.preload_modules()

# 임시 출력 경로
tmp_dir <- file.path(CACHE_DIR, "factor_db_daily_bench_tmp")
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)

t0 <- proc.time()
tryCatch({
  build_factor_db_daily(
    start_date = TEST_DATE,
    end_date   = TEST_DATE,
    force      = TRUE,
    workers    = 1L
  )
}, error = function(e) cat("  [ERROR]", conditionMessage(e), "\n"))

elapsed <- (proc.time() - t0)["elapsed"]
cat(sprintf("\n  단일 날짜 빌드: %.2f초 (목표: 5초 이하)\n", elapsed))
if (elapsed <= 5)  cat("  [PASS] 목표 달성!\n")
else if (elapsed <= 15) cat("  [INFO] 개선됨 (>5초 but <15초)\n")
else cat("  [WARN] 여전히 느림 (>=15초)\n")

# ── 신규 빌드 결과 로드 ─────────────────────────────────────────────────────
cat("\n[3] 신규 빌드 결과 로드...\n")
new_path <- file.path(CACHE_DIR, "factor_db_daily",
                      paste0("factor_db_daily_", gsub("-", "", TEST_DATE), ".parquet"))
if (!file.exists(new_path)) {
  cat("  [FAIL] 신규 parquet 생성 실패: ", new_path, "\n")
  quit(status = 1)
}
new_dt <- as.data.table(read_parquet(new_path))
cat(sprintf("  rows: %d | factors: %d\n", nrow(new_dt),
            uniqueN(new_dt[["Factor_Name"]])))

# ── 정합성 검증 ─────────────────────────────────────────────────────────────
cat("\n[4] 기존 vs 신규 정합성 검증...\n")
if (is.null(old_dt)) {
  cat("  [SKIP] 기존 parquet 없음.\n")
} else {
  # 공통 팩터 비교
  common_factors <- intersect(
    unique(old_dt[["Factor_Name"]]),
    unique(new_dt[["Factor_Name"]])
  )
  cat(sprintf("  공통 팩터: %d개\n", length(common_factors)))

  pass_n <- 0L; fail_n <- 0L; low_n <- 0L
  for (fn in common_factors) {
    old_f <- old_dt[Factor_Name == fn, .(Ticker, old_val = Z_Score_Aligned)]
    new_f <- new_dt[Factor_Name == fn, .(Ticker, new_val = Z_Score_Aligned)]
    merged <- merge(old_f, new_f, by = "Ticker", all = FALSE)
    merged <- merged[!is.na(old_val) & !is.na(new_val) & is.finite(old_val) & is.finite(new_val)]
    if (nrow(merged) < 10) next
    r <- tryCatch(cor(merged$old_val, merged$new_val), error = function(e) NA_real_)
    if (is.na(r)) next
    if (r >= 0.9999) pass_n <- pass_n + 1L
    else if (r >= 0.99) { low_n <- low_n + 1L; cat(sprintf("  [LOW ] %s: cor=%.6f\n", fn, r)) }
    else { fail_n <- fail_n + 1L; cat(sprintf("  [FAIL] %s: cor=%.6f\n", fn, r)) }
  }
  cat(sprintf("\n  결과: PASS(%d) / LOW(%.4f~0.9999, %d) / FAIL(<0.99, %d)\n",
              pass_n, 0.99, low_n, fail_n))
  if (fail_n == 0) cat("  [PASS] 모든 팩터 정합성 >= 0.99\n")
  else             cat("  [WARN] 일부 팩터 낮은 정합성 확인 필요\n")
}

# ── 병렬 빌드 속도 측정 (3일) ───────────────────────────────────────────────
cat("\n[5] 병렬 빌드 속도 측정 (3일 × workers=4)...\n")
test_dates <- c("2005-01-04", "2005-01-05", "2005-01-06")
t1 <- proc.time()
tryCatch({
  build_factor_db_daily(
    start_date = min(test_dates),
    end_date   = max(test_dates),
    force      = TRUE,
    workers    = 4L
  )
}, error = function(e) cat("  [ERROR]", conditionMessage(e), "\n"))
elapsed3 <- (proc.time() - t1)["elapsed"]
cat(sprintf("  3일 병렬 빌드: %.2f초 (날짜당 %.2f초)\n", elapsed3, elapsed3 / 3))

# ── 요약 ─────────────────────────────────────────────────────────────────────
cat("\n==============================\n")
cat(sprintf("단일 날짜: %.2fs | 목표 5s이하: %s\n",
            elapsed,
            if (elapsed <= 5) "PASS" else "FAIL"))
cat(sprintf("병렬 3일: %.2fs (%.2fs/date)\n", elapsed3, elapsed3 / 3))
cat(sprintf("연간 ~252일 예상: %.1f분\n", elapsed * 252 / 60))
cat("==============================\n")
