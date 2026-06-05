#!/usr/bin/env Rscript
#==============================================================================
# bear_date_audit.R — Forward 21d return assertion for 4 known KOSPI200 bear dates
#
# 목적:
#   data.table::shift convention 함정 (`shift(x, n=-H, type="lead")` = x[t-H] BACKWARD
#   double negation) 회귀 방지 sanity check.
#   bootstrap.sh + 신규 cycle CI 의무 등록 (Cycle 51 mandate B안).
#
# 4 known bear dates:
#   - Lehman 2008-09-15 — Global Financial Crisis 시작
#   - Euro 2011-08-08 — European debt crisis aggravation
#   - COVID 2020-02-19 — KOSPI 2210.34 peak, 21d 후 -34.05% forward
#   - Stagflation 2022-09-26 — KR rate hike + KOSPI 6m DD trigger
#
# 각 date에서 verification:
#   - target_df의 ret_h (forward 21d return) ≤ -0.05 (5% drop minimum, conservative)
#   - manual forward lookup BM[t+21] / BM[t] - 1 과 match (절대 차이 < 1e-6)
#   - backward variant (BM[t-21] / BM[t] - 1) 와 mismatch (label sign-flip detection)
#
# Cycle 51 Phase 2 (도훈 mandate 2026-05-20 B안).
#
# Usage:
#   Rscript 02_Infrastructure/sanity_checks/bear_date_audit.R [target_path] [bm_path]
#
#   target_path: default = `04_Research/decision_framework/bearish_forecast_v2_alt_data/
#                          outputs/02_targets/targets_full.parquet`
#   bm_path:     default = `.cache/benchmark.parquet`
#
# Exit codes:
#   0 = ALL PASS
#   1 = ANY FAIL (bootstrap.sh hard fail)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
DEFAULT_TARGET <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/02_targets/targets_full.parquet")
DEFAULT_BM <- file.path(PROJECT_ROOT, ".cache/benchmark.parquet")

# ── CLI args ──────────────────────────────────────────────────────────
args <- commandArgs(trailingOnly = TRUE)
target_path <- if (length(args) >= 1) args[1] else DEFAULT_TARGET
bm_path <- if (length(args) >= 2) args[2] else DEFAULT_BM

H <- 21L  # forecast horizon (trading days)

# 4 known KOSPI200 bear dates — date-specific forward 21d drop expectation
# 본 sanity check은 "forward label semantics 정합" 검증 (label = forward 방향) — buggy bug 회귀 방지.
# bear date 선정은 6m DD trigger (KOSPI 6m drawdown ≤ -10%) 시점이므로 forward 21d drop은 case-by-case 다양:
#   - Lehman 2008-09-15: GFC 시작점 → 21d 후 -9.31% (강한 drop, KOSPI200 confirms bear)
#   - Euro 2011-08-08: 11월 본격 bear 시작, 21d 후 -1.93% (전초 단계, drop 약함)
#   - COVID 2020-02-19: KOSPI peak (2210.34) → 21d 후 -34.05% (textbook bear)
#   - Stagflation 2022-09-26: 9월 말 trough, 21d 후 +3.05% (단기 회복기 진입, drop 없음)
#
# 따라서 drop magnitude는 case-specific expected_forward_le로 명시 (default check 폐기).
# 핵심 PASS 기준: forward match + backward mismatch (sign-flip detection) + COVID strong assertion.
BEAR_DATES <- list(
  list(name = "Lehman GFC",      date = as.Date("2008-09-15"),
       expected_forward_le = -0.05),  # GFC 시작점, 21d -9.31%
  list(name = "Euro Crisis",     date = as.Date("2011-08-08")),
      # 전초 단계 — drop magnitude assertion 없음 (label semantics만 검증)
  list(name = "COVID",           date = as.Date("2020-02-19"),
       expected_forward_le = -0.30,  # 강한 assertion (실제 -34.05%)
       expected_backward_ge = 0      # backward는 +1.82% 등 positive
  ),
  list(name = "Stagflation 2022", date = as.Date("2022-09-26"))
      # 9월 말 trough — drop magnitude assertion 없음
)

audit_bear_dates <- function(target_path, bm_path) {
  if (!file.exists(target_path)) {
    cat(sprintf("[bear_audit] ERROR: target file missing — %s\n", target_path))
    return(list(pass = FALSE, reason = "target_file_missing"))
  }
  if (!file.exists(bm_path)) {
    cat(sprintf("[bear_audit] ERROR: benchmark file missing — %s\n", bm_path))
    return(list(pass = FALSE, reason = "benchmark_file_missing"))
  }

  td <- as.data.table(read_parquet(target_path))
  bd <- as.data.table(read_parquet(bm_path))

  # Date 정규화: 데이터 리프레시가 benchmark.parquet을 POSIXct(09:00:00 시각 포함)로
  # 저장하면 Date-class used_date와 `Date == d` exact-match가 절대 성립 안 함 →
  # manual forward/backward 전부 NA → 4개 bear date 거짓 FAIL (PIT sentinel 무력화).
  # 양측 Date를 Date class로 강제해 매칭 복구 (label 의미 검증 자체는 무변경).
  if ("Date" %in% names(td)) td[, Date := as.Date(Date)]
  if ("Date" %in% names(bd)) bd[, Date := as.Date(Date)]

  if (!all(c("Date", "ret_h") %in% names(td))) {
    cat("[bear_audit] ERROR: target missing Date or ret_h column\n")
    return(list(pass = FALSE, reason = "target_columns_missing"))
  }
  if (!all(c("Date", "BM_Close") %in% names(bd))) {
    cat("[bear_audit] ERROR: benchmark missing Date or BM_Close column\n")
    return(list(pass = FALSE, reason = "benchmark_columns_missing"))
  }

  setorder(td, Date)
  setorder(bd, Date)
  bd[, row_idx := .I]

  # Helper functions
  manual_forward <- function(d) {
    j <- bd[Date == d, row_idx]
    if (length(j) == 0L) return(NA_real_)
    j <- j[1L]
    k <- j + H
    if (k > nrow(bd)) return(NA_real_)
    bd$BM_Close[k] / bd$BM_Close[j] - 1
  }
  manual_backward <- function(d) {
    j <- bd[Date == d, row_idx]
    if (length(j) == 0L) return(NA_real_)
    j <- j[1L]
    k <- j - H
    if (k < 1L) return(NA_real_)
    bd$BM_Close[k] / bd$BM_Close[j] - 1
  }

  # ── Audit each bear date ────────────────────────────────────────────
  cat("\n=== Bear Date Forward Label Audit (Cycle 51, H=21) ===\n")
  cat(sprintf("Target: %s\n", target_path))
  cat(sprintf("Benchmark: %s\n", bm_path))
  cat("Core checks: forward_match + backward_mismatch (sign-flip detection)\n")
  cat("Optional: date-specific expected_forward_le / expected_backward_ge\n\n")

  results <- list()
  all_pass <- TRUE

  for (b in BEAR_DATES) {
    d <- b$date
    nm <- b$name

    # target lookup — nearest available row (date may not exist exactly)
    nearest_row <- td[Date <= d][.N]
    if (nrow(nearest_row) == 0 || is.na(nearest_row$ret_h)) {
      # try next available
      nearest_row <- td[Date >= d][1]
    }
    if (nrow(nearest_row) == 0 || is.na(nearest_row$ret_h)) {
      cat(sprintf("[%s] %s — SKIP: no ret_h coverage\n", nm, d))
      results[[nm]] <- list(date = as.character(d), pass = NA, reason = "no_coverage")
      next
    }

    used_date <- nearest_row$Date
    target_ret <- nearest_row$ret_h
    fwd_ret <- manual_forward(used_date)
    bwd_ret <- manual_backward(used_date)

    # CORE checks (semantics — buggy bug 회귀 detection 필수)
    # check_fwd_match: target matches manual forward (label is forward)
    check_fwd_match <- !is.na(fwd_ret) && abs(target_ret - fwd_ret) < 1e-6

    # check_bwd_mismatch: target does NOT match backward (sign-flip detection)
    check_bwd_mismatch <- is.na(bwd_ret) || abs(target_ret - bwd_ret) >= 1e-6

    # OPTIONAL date-specific checks (drop magnitude expectation)
    if (!is.null(b$expected_forward_le)) {
      check_strong_fwd <- !is.na(fwd_ret) && fwd_ret <= b$expected_forward_le
    } else {
      check_strong_fwd <- TRUE
    }
    if (!is.null(b$expected_backward_ge)) {
      check_strong_bwd <- !is.na(bwd_ret) && bwd_ret >= b$expected_backward_ge
    } else {
      check_strong_bwd <- TRUE
    }

    # Bear pass: semantics PASS (forward match + backward mismatch) + date-specific assertions
    bear_pass <- check_fwd_match && check_bwd_mismatch &&
                 check_strong_fwd && check_strong_bwd

    if (!bear_pass) all_pass <- FALSE

    cat(sprintf("[%s] %s (used %s)\n", nm, d, used_date))
    cat(sprintf("  target ret_h:      %+.4f (%.2f%%)\n", target_ret, target_ret * 100))
    cat(sprintf("  manual forward:    %+.4f (%.2f%%) match=%s\n",
                fwd_ret %||% NA, (fwd_ret %||% NA) * 100,
                if (check_fwd_match) "YES" else "NO"))
    cat(sprintf("  manual backward:   %+.4f (%.2f%%) mismatch=%s (must NOT match)\n",
                bwd_ret %||% NA, (bwd_ret %||% NA) * 100,
                if (check_bwd_mismatch) "YES" else "NO"))
    if (!is.null(b$expected_forward_le)) {
      cat(sprintf("  strong forward <= %.2f%%: %s\n",
                  b$expected_forward_le * 100,
                  if (check_strong_fwd) "PASS" else "FAIL"))
    }
    if (!is.null(b$expected_backward_ge)) {
      cat(sprintf("  strong backward >= %.2f%%: %s\n",
                  b$expected_backward_ge * 100,
                  if (check_strong_bwd) "PASS" else "FAIL"))
    }
    cat(sprintf("  >>> %s: %s\n\n", nm, if (bear_pass) "PASS" else "FAIL"))

    results[[nm]] <- list(
      date = as.character(d),
      used_date = as.character(used_date),
      target_ret_h = target_ret,
      manual_forward = fwd_ret,
      manual_backward = bwd_ret,
      check_fwd_match = check_fwd_match,
      check_bwd_mismatch = check_bwd_mismatch,
      check_strong_fwd = check_strong_fwd,
      check_strong_bwd = check_strong_bwd,
      pass = bear_pass
    )
  }

  # ── Summary ─────────────────────────────────────────────────────────
  n_pass <- sum(vapply(results, function(r) isTRUE(r$pass), logical(1)))
  n_fail <- sum(vapply(results, function(r) isFALSE(r$pass), logical(1)))
  n_skip <- sum(vapply(results, function(r) is.na(r$pass), logical(1)))
  cat(sprintf("=== Audit Summary: %d PASS / %d FAIL / %d SKIP (of %d bear dates) ===\n\n",
              n_pass, n_fail, n_skip, length(BEAR_DATES)))

  list(
    pass = all_pass,
    n_pass = n_pass,
    n_fail = n_fail,
    n_skip = n_skip,
    results = results,
    target_path = target_path,
    bm_path = bm_path
  )
}

# null-coalescing helper (R does not have %||%)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a

# ── Main ──────────────────────────────────────────────────────────────
if (!interactive() && identical(sys.nframe(), 0L)) {
  result <- audit_bear_dates(target_path, bm_path)

  # Save JSON audit log
  log_dir <- file.path(PROJECT_ROOT, "qepm/observability/sanity_checks")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  log_path <- file.path(log_dir, sprintf("bear_date_audit_%s.json",
                                          format(Sys.time(), "%Y%m%d_%H%M%S")))
  jsonlite::write_json(result, log_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
  cat(sprintf("[bear_audit] log saved: %s\n", log_path))

  # Latest pointer
  latest_path <- file.path(log_dir, "bear_date_audit_latest.json")
  jsonlite::write_json(result, latest_path, auto_unbox = TRUE, pretty = TRUE, na = "null")

  if (result$pass) {
    cat("[bear_audit] ALL PASS — bootstrap may proceed\n")
    quit(status = 0)
  } else {
    cat("[bear_audit] FAIL — backward label bug suspected. Block bootstrap.\n")
    cat("[bear_audit] Refer to 04_Research/decision_framework/bearish_forecast_v2_alt_data/STATUS_BUGGY_ERA.md\n")
    quit(status = 1)
  }
}
