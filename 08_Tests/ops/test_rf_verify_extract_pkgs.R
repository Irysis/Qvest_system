#!/usr/bin/env Rscript
#==============================================================================
# test_rf_verify_extract_pkgs.R — 검증기의 의존 패키지 스캐너는 코드만 읽는다 (2026-09-05)
#
# 실사고 18:38: 에이전트 엔진의 cat() 메시지 문자열 "FIDELITY.json::portfolio_spec" 을 `::` 스캐너가 패키지로 읽어
#   install.packages("FIDELITY.json") 실패 → dependency_install_failed → 31분짜리 Fable 산출물이 2초 만에 기각.
#   구판은 주석만 벗겼고 문자열 안 `#` 도 주석으로 잘라 그 뒤 코드를 잃었다.
# 판정(양방향): 문자열·주석 안의 library()/pkg:: 는 0 · 코드의 것은 잡힌다 · 문자열 안 # 뒤 코드는 살아 있다.
# 부작용 없음: 검증기 파일에서 두 함수 정의만 파싱해 평가한다(검증기 본문은 실행하지 않는다).
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }

exprs <- parse(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), keep.source = FALSE)
env <- new.env()
n_def <- 0L
for (e in exprs) {
  if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) &&
      as.character(e[[2]]) %in% c(".strip_strings", ".extract_pkgs")) { eval(e, env); n_def <- n_def + 1L }
}
if (exists(".extract_pkgs", envir = env, inherits = FALSE)) ok("검증기에서 .extract_pkgs 정의 추출") else { ng("정의 추출 실패"); quit(status = 1) }
if (!exists(".strip_strings", envir = env, inherits = FALSE)) ng("S0 .strip_strings 부재(구판) — 문자열 리터럴을 벗기지 않는다")
X <- function(lines) { f <- tempfile(fileext = ".R"); writeLines(lines, f); on.exit(unlink(f)); sort(get(".extract_pkgs", env)(f)) }
DQ <- intToUtf8(34)
q <- function(s) paste0(DQ, s, DQ)

cat("=== 문자열·주석 안 (0이어야) ===\n")
r <- X(c("x <- 1", paste0("cat(", q("  sample = FIDELITY.json::portfolio_spec (top_n_long)"), ")")))
if (!length(r)) ok("S1 문자열 안 FIDELITY.json:: 무시 ★실사고") else ng("S1 문자열 안 토큰을 패키지로 읽음", paste(r, collapse = ","))
r <- X(c("# data.table::fread 를 쓴다", "# library(zoo)", "y <- 2"))
if (!length(r)) ok("S2 주석 안 :: / library() 무시") else ng("S2 주석 토큰 오탐", paste(r, collapse = ","))
r <- X(c(paste0("msg <- ", q("call library(fakepkg) first")), "z <- 3"))
if (!length(r)) ok("S3 문자열 안 library() 무시") else ng("S3 문자열 library 오탐", paste(r, collapse = ","))

cat("=== 코드 (잡혀야 — 양성 대조) ===\n")
r <- X(c("library(zoo)", "dt <- data.table::fread(p)", "suppressMessages(require(xts))"))
if (identical(r, c("data.table", "xts", "zoo"))) ok("S4 코드의 library/require/:: 3종 추출") else ng("S4 코드 추출 결손", paste(r, collapse = ","))
r <- X(c(paste0("sep <- ", q("#"), "; out <- jsonlite::toJSON(x)")))
if (identical(r, "jsonlite")) ok("S5 문자열 안 # 뒤의 코드가 살아 있다") else ng("S5 문자열 안 # 가 줄을 잘랐다", paste(r, collapse = ","))
r <- X(c(paste0("lab <- ", q("a::b"), "  # zoo::x"), "w <- stats::sd(v)"))
if (!length(r)) ok("S6 base 패키지(stats)·문자열·주석만 있으면 0") else ng("S6 오탐", paste(r, collapse = ","))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_verify_extract_pkgs","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
