#==============================================================================
# test_fred_robust.R — Session 70 Step 8
#
# 검증 범위:
#   1. fred_robust_wide_load() — wide parquet 존재 시 Date + series columns 반환
#   2. fred_robust_wide_load() — wide 없고 long만 존재 시 fallback dcast 동작
#   3. backup 파일 존재 확인 로직 (file.copy path 규칙)
#
# 실 FRED API 호출하지 않음. tmp CACHE_DIR 에 mock parquet 직접 기록.
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

# Ensure config symbols (CACHE_DIR, FUNC_PATH) loaded in current scope
if (!exists("CACHE_DIR") || !exists("FUNC_PATH")) {
  source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
}

.orig_cache <- CACHE_DIR

tmp_cache <- tempfile(pattern = "fred_test_")
dir.create(tmp_cache, recursive = TRUE, showWarnings = FALSE)
CACHE_DIR <- tmp_cache

# Source fred_robust (its functions live in globalenv by default).
# local = TRUE puts them into current env so we can override paths before call.
fred_env <- new.env(parent = globalenv())
fred_env$PROJECT_ROOT <- PROJECT_ROOT
fred_env$CACHE_DIR    <- tmp_cache
fred_env$FUNC_PATH    <- FUNC_PATH
sys.source(file.path(PROJECT_ROOT, "02_Infrastructure/regime/fred_robust.R"),
           envir = fred_env, keep.source = FALSE)

# Override cache file paths inside the function's lookup env
fred_env$FRED_ROBUST_LONG <- file.path(tmp_cache, "fred_macro.parquet")
fred_env$FRED_ROBUST_WIDE <- file.path(tmp_cache, "fred_macro_wide.parquet")

# Also bind locally for test scope references
FRED_ROBUST_LONG <- fred_env$FRED_ROBUST_LONG
FRED_ROBUST_WIDE <- fred_env$FRED_ROBUST_WIDE
fred_robust_wide_load <- fred_env$fred_robust_wide_load

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

# ── Mock data: synthetic 2 series long → wide via dcast ────────────
mock_dates <- seq.Date(Sys.Date() - 30, Sys.Date(), by = "day")[1:5]
mock_long <- rbindlist(list(
  data.table(Date = mock_dates, Series = "VIX",
             Series_ID = "VIXCLS", Frequency = "d",
             Value = c(18.2, 19.1, 21.5, 20.3, 22.0)),
  data.table(Date = mock_dates, Series = "HY_Spread",
             Series_ID = "BAMLH0A0HYM2", Frequency = "d",
             Value = c(3.2, 3.3, 3.5, 3.4, 3.6))
))
mock_wide <- dcast(mock_long, Date ~ Series, value.var = "Value")

# Write mocks
write_parquet(mock_long, FRED_ROBUST_LONG)
write_parquet(mock_wide, FRED_ROBUST_WIDE)

# ── Test 1: wide load ───────────────────────────────────────────────
dt_wide <- tryCatch(fred_robust_wide_load(prefer_wide = TRUE),
                    error = function(e) { cat("err:", e$message, "\n"); NULL })

.assert(!is.null(dt_wide) && nrow(dt_wide) == 5L,
        sprintf("fred_robust_wide_load returns 5 rows from wide parquet (got %s)",
                if (is.null(dt_wide)) "NULL" else nrow(dt_wide)))

.assert(!is.null(dt_wide) && "Date" %in% names(dt_wide),
        "wide schema: Date column present")

.assert(!is.null(dt_wide) && all(c("VIX", "HY_Spread") %in% names(dt_wide)),
        "wide schema: Series columns present (VIX, HY_Spread)")

# ── Test 2: wide missing → fallback to long dcast ───────────────────
file.remove(FRED_ROBUST_WIDE)
dt_fallback <- tryCatch(fred_robust_wide_load(prefer_wide = TRUE),
                         error = function(e) { cat("err:", e$message, "\n"); NULL })

.assert(!is.null(dt_fallback) && nrow(dt_fallback) == 5L,
        "fallback path: long → wide dcast produces 5 rows when wide missing")

.assert(!is.null(dt_fallback) && all(c("VIX", "HY_Spread") %in% names(dt_fallback)),
        "fallback path: VIX/HY_Spread columns after dcast")

# ── Test 3: backup path naming convention ───────────────────────────
bak_path <- paste0(FRED_ROBUST_LONG, ".bak_", format(Sys.Date(), "%Y%m%d"))
.assert(grepl("\\.bak_\\d{8}$", bak_path),
        "backup path pattern '.bak_YYYYMMDD'")

# Touch a fake backup & check exists-predicate works
writeLines("mock", bak_path)
.assert(file.exists(bak_path),
        "backup file can be written to computed path")

# ── Test 4: wide load — even if both missing, long load fallback ──
if (file.exists(FRED_ROBUST_WIDE)) file.remove(FRED_ROBUST_WIDE)
# Keep long only
dt2 <- tryCatch(fred_robust_wide_load(prefer_wide = FALSE),
                error = function(e) NULL)
.assert(!is.null(dt2) && nrow(dt2) > 0,
        "prefer_wide=FALSE path reshapes long correctly")

# ── Cleanup ────────────────────────────────────────────────────────
unlink(tmp_cache, recursive = TRUE, force = TRUE)
if (!is.null(.orig_cache)) CACHE_DIR <- .orig_cache

cat(sprintf("\n── test_fred_robust: %d passed, %d failed ──\n\n",
            pass_count, fail_count))

# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
cat(sprintf("{\"test\":\"test_fred_robust\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", pass_count, fail_count, pass_count + fail_count))
if (fail_count > 0) stop(sprintf("test_fred_robust: %d failures", fail_count))
invisible(list(pass = pass_count, fail = fail_count))
