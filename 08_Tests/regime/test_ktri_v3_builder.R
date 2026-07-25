#==============================================================================
# test_ktri_v3_builder.R — Session 70 Step 8
#
# 검증 범위:
#   1. build_ktri_v3 (또는 내부 계산 로직) 합성 benchmark 로 호출 → KTRI 범위 [0, 100]
#   2. VEA NA fraction ≤ 10% (Step 2 bugfix 검증; forward-fill working)
#   3. Output schema — DATE, KTRI, VEA, IKS200, Delta_KTRI, Action_v3 모두 존재
#
# 실 RAWDATA 없이도 동작: 임시 CACHE_DIR 에 합성 parquet 저장 후 build_ktri_v3 실행.
#==============================================================================

suppressPackageStartupMessages({
  library(testthat)
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  # [fix 2026-07-25] 구 하드코딩 WSL 폴백 제거. 이 가드는 환경변수를 보지 않아
  # 단독 실행 시 무조건 없는 경로로 가 source(config.R) 가 죽었고,
  # 그 결과 러너가 "0 passed / 0 failed (of 0 total)" 을 성공처럼 냈다.
  # 후보를 **표지 파일 검증**으로 확인한다 — 존재검사로 정체성검사를 대체하지 않는다.
  .qv_marker <- "02_Infrastructure/config.R"
  .qv_argv <- commandArgs(trailingOnly = FALSE)
  .qv_f <- grep("^--file=", .qv_argv, value = TRUE)
  .qv_sd <- if (length(.qv_f)) dirname(sub("^--file=", "", .qv_f[1])) else ""
  for (.qv_c in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                  Sys.getenv("QM_ROOT", unset = ""),
                  if (nzchar(.qv_sd)) file.path(.qv_sd, "..", "..") else "",
                  getwd())) {
    if (nzchar(.qv_c) && file.exists(file.path(.qv_c, .qv_marker))) {
      PROJECT_ROOT <- .qv_c
      break
    }
  }
  if (!exists("PROJECT_ROOT")) {
    stop(sprintf(paste0("[regime] PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보 없음.\n",
                        "  cwd=%s / CLAUDE_PROJECT_DIR='%s' / QM_ROOT='%s'"),
                 .qv_marker, getwd(),
                 Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                 Sys.getenv("QM_ROOT", unset = "")))
  }
  rm(list = intersect(ls(), c(".qv_marker", ".qv_argv", ".qv_f", ".qv_sd", ".qv_c")))
}

if (!exists("CACHE_DIR")) {
  source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
}

.orig_cache <- CACHE_DIR
.orig_project <- PROJECT_ROOT

# ── 임시 cache dir + 합성 데이터 생성 ──────────────────────────────
tmp_cache <- tempfile(pattern = "ktri_test_")
dir.create(tmp_cache, recursive = TRUE, showWarnings = FALSE)

set.seed(42)
n_days <- 1000L
# Start 약 3년 전부터 (build_ktri_v3 는 최근 cutoff_years 기준)
dates <- seq.Date(Sys.Date() - n_days + 1L, Sys.Date(), by = "day")
# 평일만 선택 (approximate trading days)
dates <- dates[!format(dates, "%u") %in% c("6", "7")]
n <- length(dates)

# Synthetic RAWDATA: 50 tickers × n days (KOSPI random walk)
n_tick <- 50L
tickers <- sprintf("T%03d", 1:n_tick)
raw_rows <- vector("list", n_tick)
for (k in seq_along(tickers)) {
  rets <- rnorm(n, mean = 0.0003, sd = 0.015)
  close <- 10000 * cumprod(1 + rets)
  raw_rows[[k]] <- data.table(
    Date   = dates,
    Ticker = tickers[k],
    Close  = close,
    Ret    = rets,
    Market = "KOSPI"
  )
}
rawdata <- rbindlist(raw_rows)

# Synthetic benchmark.parquet — index = mean across tickers scaled
bm_closes <- rawdata[, .(BM_Close = mean(Close, na.rm = TRUE)), by = Date]
setorder(bm_closes, Date)
bm_closes[, BM_Ret := BM_Close / shift(BM_Close, 1L) - 1]

write_parquet(rawdata, file.path(tmp_cache, "RAWDATA.parquet"))
write_parquet(bm_closes, file.path(tmp_cache, "benchmark.parquet"))

cat(sprintf("[test_ktri] synth RAWDATA: %d rows, %d tickers, %d days\n",
            nrow(rawdata), n_tick, n))

# ── Override CACHE_DIR for builder (isolated from real cache) ─────
CACHE_DIR <- tmp_cache

# Override output path (use tmp dir — do not touch real research output)
KTRI_V3_OUT_DIR <- file.path(tmp_cache, "output")
KTRI_V3_CSV <- file.path(KTRI_V3_OUT_DIR, "ktri_v3_signals.csv")

# Source builder (will pick up overridden PROJECT_ROOT/CACHE_DIR)
source(file.path(PROJECT_ROOT, "02_Infrastructure/regime/ktri_v3_builder.R"))

# Re-override after source (source file sets its own defaults if missing)
KTRI_V3_OUT_DIR <- file.path(tmp_cache, "output")
KTRI_V3_CSV <- file.path(KTRI_V3_OUT_DIR, "ktri_v3_signals.csv")

# ── Run builder ────────────────────────────────────────────────────
out <- tryCatch({
  build_ktri_v3(output = KTRI_V3_CSV, cache_cutoff_years = 5L)
}, error = function(e) {
  cat(sprintf("[test_ktri] builder error: %s\n", conditionMessage(e)))
  NULL
})

pass_count <- 0L
fail_count <- 0L
.assert <- function(cond, msg) {
  if (isTRUE(cond)) {
    cat(sprintf("  [PASS] %s\n", msg))
    pass_count <<- pass_count + 1L
  } else {
    cat(sprintf("  [FAIL] %s\n", msg))
    fail_count <<- fail_count + 1L
  }
}

cat("\n── Assertions ──\n")

.assert(!is.null(out) && nrow(out) > 0,
        "build_ktri_v3 returns non-empty data.table")

if (!is.null(out) && nrow(out) > 0) {
  required_cols <- c("DATE", "KTRI", "VEA", "IKS200", "Delta_KTRI", "Action_v3")
  .assert(all(required_cols %in% names(out)),
          sprintf("schema: required columns %s present",
                  paste(required_cols, collapse = ", ")))

  ktri_in_range <- all(out$KTRI >= 0 & out$KTRI <= 100, na.rm = TRUE)
  .assert(ktri_in_range, "KTRI range [0, 100]")

  vea_in_range <- all(out$VEA >= 0 & out$VEA <= 100, na.rm = TRUE)
  .assert(vea_in_range, "VEA range [0, 100]")

  vea_na_frac <- mean(is.na(out$VEA))
  .assert(vea_na_frac <= 0.10,
          sprintf("VEA NA fraction ≤ 10%% (actual: %.2f%%)", 100 * vea_na_frac))

  .assert(all(!is.na(out$DATE)),
          "DATE column has no NAs")

  .assert(length(unique(out$Action_v3)) >= 1,
          sprintf("Action_v3 zones present (unique: %d)",
                  length(unique(out$Action_v3))))
}

# ── Cleanup ────────────────────────────────────────────────────────
unlink(tmp_cache, recursive = TRUE, force = TRUE)
if (!is.null(.orig_cache)) CACHE_DIR <- .orig_cache

cat(sprintf("\n── test_ktri_v3_builder: %d passed, %d failed ──\n\n",
            pass_count, fail_count))

if (fail_count > 0) stop(sprintf("test_ktri_v3_builder: %d failures", fail_count))
invisible(list(pass = pass_count, fail = fail_count))
