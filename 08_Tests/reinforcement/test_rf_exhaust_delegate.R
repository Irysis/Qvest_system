#!/usr/bin/env Rscript
# test_rf_exhaust_delegate.R — 소진 처리는 살아있는 경로로 (2026-09-05 · 실사고 promo2 소진 → 승격 무발화)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), local = globalenv()))))
## 격리 root 에 원장 사본 — 운영 원장 미접근
TMP <- file.path(tempdir(), paste0("rf_exh_", Sys.getpid())); dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), file.path(TMP, "06_Registry/reinforce_ledger_l1.json"))
L <- rf_load(1L, TMP); act <- Filter(function(e) identical(e$status, "active"), L$entries)
## ★active entry 가 없으면 합성한다 — 운영 상태(소진/이월)에 따라 건너뛰면 그 건너뜀이 초록으로 보인다.
##   격리 사본이라 운영 원장은 안 건드린다.
if (!length(act)) {
  L$entries[[length(L$entries) + 1L]] <- list(base_id = "T_FIXTURE_ACTIVE", status = "active",
    base_grade = "B", attempts = list(), attempts_used = 0L,
    opened_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  .rf_write(L, 1L, TMP)
  L <- rf_load(1L, TMP); act <- Filter(function(e) identical(e$status, "active"), L$entries)
}
BID <- act[[1]]$base_id
e1 <- rf_exhaust_entry(1L, BID, root = TMP)
L2 <- rf_load(1L, TMP); k <- .rf_find(L2, BID)
if (identical(L2$entries[[k]]$status, "exhausted") && nzchar(L2$entries[[k]]$exhausted_at %||% "")) ok("E1 status=exhausted + exhausted_at") else ng("E1 소진 표기 실패")
others <- vapply(seq_along(L$entries)[-k], function(i) identical(L$entries[[i]]$status, L2$entries[[i]]$status), logical(1))
if (all(others)) ok("E2 다른 entry 의 status 불변") else ng("E2 다른 entry 가 바뀌었다")
t1 <- L2$entries[[k]]$exhausted_at; Sys.sleep(1); rf_exhaust_entry(1L, BID, root = TMP); L3 <- rf_load(1L, TMP)
if (identical(L3$entries[[k]]$exhausted_at, t1)) ok("E3 멱등 — 재호출이 시각을 안 바꾼다") else ng("E3 재호출이 덮어쓴다")
if (file.exists(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"))) {
  Lp <- rf_load(1L, ROOT); kp <- .rf_find(Lp, BID)
  if (is.na(kp)) ok("E4 합성 픽스처 — 운영 원장에 없음(격리 확인)") else
  if (identical(Lp$entries[[kp]]$status, "active")) ok("E4 운영 원장은 건드리지 않았다(격리 확인)") else ng("E4 운영 원장이 바뀌었다 ★검사 오염")
}
src <- sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), encoding = "UTF-8", warn = FALSE))
if (!any(grepl("reinforce_auto_run.R", src, fixed = TRUE))) ok("E5 러너 코드에 퇴역 러너 호출 없음") else ng("E5 퇴역 러너 호출 잔존 ★실사고")
if (any(grepl("rf_exhaust_entry(1L, BID", src, fixed = TRUE)) && any(grepl("reinforce_auto_next_paper.R", src, fixed = TRUE)))
  ok("E6 소진 위임 = writer 소진 표기 + next_paper 동기 호출") else ng("E6 위임 경로 미교체")
unlink(TMP, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_exhaust_delegate","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
