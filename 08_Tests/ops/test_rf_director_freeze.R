#!/usr/bin/env Rscript
#==============================================================================
# test_rf_director_freeze.R — director.enabled 실배선 (2026-09-24 도훈 DIR-PHASE0 · 플랜 qvest-1-drifting-eclipse '디렉터 흡수')
#
# 왜: 구판 dir_cfg() 는 enabled 를 읽기만 하고 소비자가 0 이었다 — config 를 false 로 바꿔도 아침 체인이 계속 캐시·지도·
#   결정 기록·방향 채점·텔레그램을 썼다(끌 수 없는 스위치). 이 검사는 스위치가 실제로 산출을 막는지 산출물로 재도출한다.
#   Z1 enabled=false 샌드박스 → exit 0 · '동결' 줄 · 산출 5종(캐시·지도·컨텍스트·결정 기록·채점 캐시) 0
#   Z2 양성 대조: 같은 샌드박스 enabled=true → 캐시가 생긴다(샌드박스가 퇴화 입력이 아님)
#   Z3 돌연변이(게이트 제거 사본) → Z1 의 '산출 0' 이 깨진다(검사가 게이트를 실제로 본다)
#   Z4 운영 config: director.enabled=false · 최상위 enabled=false(무인 L1 정지) · l2_auto.enabled=false 유지
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
SCRIPT <- file.path(ROOT, "02_Infrastructure/ops/rf_director.R")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_director_freeze","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }

mk_sandbox <- function(enabled) {
  S <- file.path(tempdir(), sprintf("rf_dir_freeze_%d_%d", Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  for (d in c(".cache", "06_Registry", "02_Infrastructure/worktask")) dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  invisible(file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S, "02_Infrastructure/worktask/constraint_defaults.json")))
  writeLines(toJSON(list(entries = list()), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
  writeLines(toJSON(list(modules = list()), auto_unbox = TRUE), file.path(S, "06_Registry/module_catalog.json"))
  writeLines(toJSON(list(enabled = FALSE, director = list(enabled = enabled, act = FALSE)), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_auto_config.json"))
  gsub("\\", "/", S, fixed = TRUE)
}
OUTS <- c(".cache/rf_director_latest.json", "06_Registry/layer_bottleneck_map.md", ".cache/rf_director_context.json",
          "06_Registry/rf_decisions.jsonl", ".cache/rf_direction_score_latest.json")
run <- function(script, S) {
  o <- suppressWarnings(system2("Rscript", c(shQuote(script), sprintf("--root=%s", S)), stdout = TRUE, stderr = TRUE,
                                env = character(0)))
  list(out = enc2utf8(o), rc = attr(o, "status") %||% 0L)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
FROZEN <- "\ub3d9\uacb0"   # '동결'

cat("=== Z1 enabled=false → 산출 0 ===\n")
S1 <- mk_sandbox(FALSE); r1 <- run(SCRIPT, S1)
if (identical(as.integer(r1$rc), 0L)) ok("Z1 exit 0 (동결은 실패가 아니다)") else ng("Z1 exit", as.character(r1$rc))
if (any(grepl(FROZEN, r1$out, fixed = TRUE))) ok("Z1 '동결' 한 줄 출력") else ng("Z1 동결 줄 없음", paste(tail(r1$out, 3), collapse = " | "))
w1 <- OUTS[file.exists(file.path(S1, OUTS))]
if (!length(w1)) ok("Z1 산출 5종(캐시·지도·컨텍스트·결정 기록·채점 캐시) 전부 0") else ng("Z1 동결인데 쓴 파일", paste(w1, collapse = ","))

cat("\n=== Z2 양성 대조 enabled=true → 캐시 생성 ===\n")
S2 <- mk_sandbox(TRUE); r2 <- run(SCRIPT, S2)
if (file.exists(file.path(S2, ".cache/rf_director_latest.json")) && !any(grepl(FROZEN, r2$out, fixed = TRUE)))
  ok("Z2 enabled=true 샌드박스는 캐시를 쓴다(샌드박스가 퇴화 입력이 아님)") else ng("Z2 양성 대조 실패 — 샌드박스로는 게이트를 판별 못 함", paste(tail(r2$out, 3), collapse = " | "))

cat("\n=== Z3 돌연변이(게이트 제거 사본) ===\n")
src <- readLines(SCRIPT, encoding = "UTF-8", warn = FALSE)
gate <- grep("if (!isTRUE(cfg$enabled)) {", src, fixed = TRUE)
if (length(gate) == 1L) {
  mut <- src; mut[gate] <- sub("if (!isTRUE(cfg$enabled)) {", "if (FALSE) {", mut[gate], fixed = TRUE)
  mdir <- file.path(tempdir(), sprintf("rf_dir_mut_%d", Sys.getpid())); dir.create(file.path(mdir, "02_Infrastructure/ops"), recursive = TRUE, showWarnings = FALSE)
  mf <- file.path(mdir, "02_Infrastructure/ops/rf_director.R"); writeLines(enc2utf8(mut), mf, useBytes = TRUE)
  Sys.setenv(QVEST_DIRECTOR_CODE_ROOT = ROOT)
  S3 <- mk_sandbox(FALSE); r3 <- run(mf, S3)
  Sys.unsetenv("QVEST_DIRECTOR_CODE_ROOT")
  w3 <- OUTS[file.exists(file.path(S3, OUTS))]
  if (length(w3) && !any(grepl(FROZEN, r3$out, fixed = TRUE))) ok(sprintf("Z3 게이트 제거 → enabled=false 인데 %d종 씀 = Z1 red", length(w3)))
  else ng("Z3 돌연변이가 Z1 을 뒤집지 못함(검사 무력)", paste(tail(r3$out, 3), collapse = " | "))
  unlink(c(mdir, S3), recursive = TRUE)
} else ng("Z3 게이트 줄이 정확히 1개여야 한다", as.character(length(gate)))

cat("\n=== Z4 운영 config ===\n")
cf <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE), error = function(e) NULL)
if (is.null(cf)) ng("Z4 운영 config 판독 불가") else {
  if (identical(cf$director$enabled, FALSE)) ok("Z4 director.enabled=false (DIR-PHASE0)") else ng("Z4 director.enabled", as.character(cf$director$enabled))
  if (identical(cf$enabled, FALSE)) ok("Z4 최상위 enabled=false 유지(무인 L1 정지 — 도훈 재개 지시 전)") else ng("Z4 최상위 enabled", as.character(cf$enabled))
  if (identical(cf$l2_auto$enabled, FALSE)) ok("Z4 l2_auto.enabled=false 유지(C11 봉쇄)") else ng("Z4 l2_auto.enabled", as.character(cf$l2_auto$enabled))
}
unlink(c(S1, S2), recursive = TRUE)
finish()
