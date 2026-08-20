# ============================================================================
# helpers.R - shared assertion/reporting utilities for contract regression
# (HYG-06, 2026-07-04). ASCII only. Targets are read-only; tests never modify
# production code. All temp artifacts go to tempdir() sandboxes.
# ============================================================================

.TREG <- new.env(parent = emptyenv())
.TREG$pass <- 0L
.TREG$fail <- 0L
.TREG$defect <- 0L

t_root <- function() {
  p <- Sys.getenv("QVEST_TEST_PROJECT_ROOT", "")
  if (!nzchar(p)) p <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(p)) p <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  normalizePath(p, winslash = "/", mustWork = TRUE)
}

# Standard check: expr must be TRUE -> [PASS], else [FAIL] (runner exits 1).
t_check <- function(id, expr) {
  err <- NULL
  ok <- tryCatch(isTRUE(expr),
                 error = function(e) { err <<- conditionMessage(e); FALSE })
  if (ok) {
    .TREG$pass <- .TREG$pass + 1L
    cat(sprintf("[PASS] %s\n", id))
  } else {
    .TREG$fail <- .TREG$fail + 1L
    cat(sprintf("[FAIL] %s :: %s\n", id,
                if (is.null(err)) "assertion returned FALSE" else err))
  }
  invisible(ok)
}

# Spec check: expr describes SPEC-mandated behavior. If FALSE the target code
# deviates from its documented spec -> [DEFECT] (reported loudly, but does NOT
# flip the regression exit code; the defect is in target code, not the test).
# Per group rule: target code must NOT be fixed by this suite - report only.
t_check_spec <- function(id, expr, note) {
  err <- NULL
  ok <- tryCatch(isTRUE(expr),
                 error = function(e) { err <<- conditionMessage(e); FALSE })
  if (ok) {
    .TREG$pass <- .TREG$pass + 1L
    cat(sprintf("[PASS] %s\n", id))
  } else {
    .TREG$defect <- .TREG$defect + 1L
    cat(sprintf("[DEFECT] %s :: %s%s\n", id, note,
                if (is.null(err)) "" else sprintf(" (error: %s)", err)))
  }
  invisible(ok)
}

t_near <- function(a, b, tol = 1e-10) {
  all(is.finite(a)) && all(is.finite(b)) && length(a) == length(b) &&
    max(abs(a - b)) <= tol
}

t_summary <- function(label) {
  cat(sprintf("TESTSUMMARY %s pass=%d fail=%d defect=%d\n",
              label, .TREG$pass, .TREG$fail, .TREG$defect))
  # 2026-08-20: 배터리(run_all_hooks.sh)는 TESTSUMMARY 를 못 읽는다 — 마지막 줄의
  #   {"test":..,"pass":..,"fail":..} 만 본다. 그래서 이 계약을 쓰는 5건(essence_score·
  #   hurdle_gate·canonical_screen_bt·register_module·required_effect_size = 측정 권위
  #   그 자체)이 배터리에 등재조차 못 된 채 남아 있었다. 두 소비자를 동시에 만족시킨다.
  #   ★spec_defect 는 target 코드 버그라 테스트 실패가 아니다(러너 규약과 동일) —
  #     fail 에 합산하지 않고 total 에만 반영한다.
  cat(sprintf("{\"test\":\"%s\",\"pass\":%d,\"fail\":%d,\"total\":%d}\n",
              label, .TREG$pass, .TREG$fail,
              .TREG$pass + .TREG$fail + .TREG$defect))
  quit(save = "no", status = if (.TREG$fail > 0L) 1L else 0L)
}

t_sandbox <- function(name) {
  sb <- file.path(tempdir(), "qvest_contract_regression", name)
  dir.create(sb, recursive = TRUE, showWarnings = FALSE)
  normalizePath(sb, winslash = "/", mustWork = TRUE)
}
