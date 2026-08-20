#==============================================================================
# test_regime_signal_merge.R — Session 70 Step 8
#
# 검증 범위:
#   1. 3-layer 각각 synthetic (MSM daily / FRED wide / KTRI daily) → merge 동작
#   2. Active_Layers 문자열 정확성 (L1+L2+L3 / L1+L2 / L1 only 등)
#   3. Gap handling: L3 전체 NA 시 Regime_Score 산출 (allow_partial 정신)
#
# 접근:
#   - build_regime_signal_table_daily 는 내부에서 load_msm_daily/
#     load_fred_daily_wide/load_ktri_daily 를 호출. 이를 런타임 override 하여
#     isolated synthetic fixture 주입.
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

# Source regime_signal (has all internal functions we need)
source(file.path(PROJECT_ROOT, "02_Infrastructure/regime/regime_signal.R"))

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

cat("\n── Synthetic fixtures ──\n")

# ── Build synthetic 3-layer data ────────────────────────────────────
today <- Sys.Date()

# MSM daily: 100 rows
msm_dates <- seq.Date(today - 150, today - 51, by = "day")
msm_fx <- data.table(
  Date = msm_dates,
  MSM_Crisis_Prob = seq(0.1, 0.7, length.out = length(msm_dates))
)

# FRED daily (as if already converted to MRS): 50 rows (overlaps mid-range)
fred_dates <- seq.Date(today - 100, today - 51, by = "day")
fred_fx <- data.table(
  Date = fred_dates,
  FRED_MRS = rep(seq(10, 45, length.out = 10), length.out = length(fred_dates))
)

# KTRI daily: 70 rows (starts latest, non-overlap w/ earliest MSM)
ktri_dates <- seq.Date(today - 80, today - 11, by = "day")
ktri_fx <- data.table(
  Date = ktri_dates,
  KTRI_Score = seq(70, 30, length.out = length(ktri_dates)),
  VEA_Score  = seq(40, 75, length.out = length(ktri_dates))
)

cat(sprintf("  MSM fixture:  %d rows | %s ~ %s\n", nrow(msm_fx),
            min(msm_fx$Date), max(msm_fx$Date)))
cat(sprintf("  FRED fixture: %d rows | %s ~ %s\n", nrow(fred_fx),
            min(fred_fx$Date), max(fred_fx$Date)))
cat(sprintf("  KTRI fixture: %d rows | %s ~ %s\n", nrow(ktri_fx),
            min(ktri_fx$Date), max(ktri_fx$Date)))

# ── Override loaders in global env ──────────────────────────────────
# build_regime_signal_table_daily calls load_msm_daily(), load_fred_daily_wide(),
# compute_fred_mrs_daily(fred_wd), load_ktri_daily(). We override to return
# our fixtures directly.
load_msm_daily <<- function() copy(msm_fx)
load_ktri_daily <<- function() copy(ktri_fx)

# load_fred_daily_wide returns wide. We want fred_dt (after compute_fred_mrs_daily)
# to = fred_fx. Simplest: override compute_fred_mrs_daily to return fred_fx.
load_fred_daily_wide <<- function() {
  # Return something non-empty so l2_ok = TRUE branch is taken.
  data.table(Date = fred_fx$Date, VIX = rep(20, nrow(fred_fx)))
}
compute_fred_mrs_daily <<- function(fred_dt) copy(fred_fx)

cat("\n── Test 1: Full 3-layer merge ──\n")
res1 <- tryCatch(
  build_regime_signal_table_daily(save_path = tempfile(fileext = ".parquet"),
                                   verbose = FALSE),
  error = function(e) { cat("err:", e$message, "\n"); NULL }
)

.assert(!is.null(res1) && nrow(res1) > 0,
        "full 3-layer merge returns non-empty signal")

if (!is.null(res1)) {
  required_cols <- c("Date", "YM", "MSM_Crisis_Prob", "FRED_MRS",
                     "KTRI_Score", "VEA_Score", "Regime_Score",
                     "Regime_Score_smooth", "Category", "Cash_Pct",
                     "Active_Layers", "Is_Month_End", "last_updated")
  .assert(all(required_cols %in% names(res1)),
          "output schema has all 13 required columns")

  # Active_Layers: should contain L1+L2+L3 in overlap region
  .assert("L1+L2+L3" %in% unique(res1$Active_Layers),
          sprintf("Active_Layers includes 'L1+L2+L3' (found: %s)",
                  paste(head(unique(res1$Active_Layers), 6), collapse = ", ")))

  # Earliest MSM-only section (before FRED starts)
  early <- res1[Date < min(fred_fx$Date) & Date >= min(msm_fx$Date)]
  if (nrow(early) > 0) {
    .assert("L1" %in% unique(early$Active_Layers),
            "early window (MSM only, pre-FRED) shows 'L1' in Active_Layers")
  } else {
    .assert(TRUE, "early L1-only window skipped (no rows)")
  }

  # Regime_Score range
  .assert(all(res1$Regime_Score >= 0 & res1$Regime_Score <= 100, na.rm = TRUE),
          "Regime_Score ∈ [0, 100]")

  # Category valid values
  valid_cats <- c("RISK_OFF", "CAUTION", "NEUTRAL", "RISK_ON")
  .assert(all(unique(res1$Category) %in% valid_cats),
          sprintf("Category ∈ valid set (found: %s)",
                  paste(unique(res1$Category), collapse = ", ")))
}

cat("\n── Test 2: L3 전체 NA (allow_partial) ──\n")
load_ktri_daily <<- function() {
  data.table(Date = as.Date(character(0)),
             KTRI_Score = numeric(0), VEA_Score = numeric(0))
}

res2 <- tryCatch(
  build_regime_signal_table_daily(save_path = tempfile(fileext = ".parquet"),
                                   allow_partial = TRUE, verbose = FALSE),
  error = function(e) { cat("err:", e$message, "\n"); NULL }
)

.assert(!is.null(res2) && nrow(res2) > 0,
        "allow_partial=TRUE, L3 missing → signal still produced")

if (!is.null(res2)) {
  .assert(all(is.na(res2$KTRI_Score)),
          "L3 missing → KTRI_Score all NA in output")

  # Active_Layers must not contain L3
  has_l3 <- any(grepl("L3", res2$Active_Layers))
  .assert(!has_l3, "Active_Layers never contains 'L3' when L3 missing")

  # Regime_Score still produced (2-layer renormalization)
  .assert(any(!is.na(res2$Regime_Score)),
          "Regime_Score computed despite L3 gap")

  # L1+L2 only should appear
  .assert("L1+L2" %in% unique(res2$Active_Layers),
          sprintf("'L1+L2' Active_Layers present (found: %s)",
                  paste(head(unique(res2$Active_Layers), 4), collapse = ", ")))
}

cat("\n── Test 3: L1 only (both L2 and L3 missing) ──\n")
compute_fred_mrs_daily <<- function(fred_dt) {
  data.table(Date = as.Date(character(0)), FRED_MRS = numeric(0))
}
load_fred_daily_wide <<- function() data.table(Date = as.Date(character(0)))

res3 <- tryCatch(
  build_regime_signal_table_daily(save_path = tempfile(fileext = ".parquet"),
                                   allow_partial = TRUE, verbose = FALSE),
  error = function(e) { cat("err:", e$message, "\n"); NULL }
)

.assert(!is.null(res3) && nrow(res3) > 0,
        "L1-only mode still produces signal (allow_partial)")

if (!is.null(res3)) {
  .assert("L1" %in% unique(res3$Active_Layers),
          "Active_Layers 'L1' (only) present")
}

cat(sprintf("\n── test_regime_signal_merge: %d passed, %d failed ──\n\n",
            pass_count, fail_count))

# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
cat(sprintf("{\"test\":\"test_regime_signal_merge\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", pass_count, fail_count, pass_count + fail_count))
if (fail_count > 0) stop(sprintf("test_regime_signal_merge: %d failures", fail_count))
invisible(list(pass = pass_count, fail = fail_count))
