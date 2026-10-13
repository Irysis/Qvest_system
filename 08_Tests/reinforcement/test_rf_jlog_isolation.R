## jlog 싱크 격리 — QVEST_RP_JLOG (2026-09-04)
## 실사고: 검사 픽스처(NO_SUCH_FACTOR_XYZ·looks_fine 등)가 운영 이벤트 로그에 design_rejected 60·audit_rejected 44건을
##   박아 기각률 계기를 죽였다. 레인 스크립트·라이브러리의 싱크가 하드코딩이라 격리 변수 자체가 없었다.
## (v10.01 2026-10-13) A/B 의 동적 대상 rf_b1_design_lib.R(B1 설계 검증기)이 고정 격자 강화와 함께 퇴역(코드 삭제) —
##   같은 실사고의 다른 절반(audit_rejected 44건)을 낸 살아 있는 검증기 rf_fidelity_audit_lib.R verify 로 옮겼다
##   (위반 주입 = 허용값 밖 verdict "looks_fine" → audit_rejected). C 절 목록에서 퇴역 레인 3종·라이브러리 1종
##   (rf_b1_design.sh · rf_lcode_mechanism.sh · rf_overlay_propose.sh · rf_b1_design_lib.R)을 빼고, 같은 싱크를 쓰는
##   살아 있는 2계층 레인 짝(rf_l2_auto.sh · rf_l2_lib.R)을 넣었다. + C-M 돌연변이(하드코딩 사본을 판정기가 잡는다) + 요약 JSON 줄.
##   롤백 태그 pre-v10.01-prescription-20261013
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
LIB  <- file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R")
PROD <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
sz0  <- if (file.exists(PROD)) file.size(PROD) else 0

## 자식 Rscript 가 검증기 CLI(verify <audit.json>)를 돈다 — 싱크는 그 프로세스가 물려받은 QVEST_RP_JLOG 하나뿐이다.
run_verify <- function(sink) {
  Sys.setenv(QVEST_RP_JLOG = sink)
  AUD <- file.path(tempdir(), sprintf("TEST_ISO_%d.json", Sys.getpid()))
  write(toJSON(list(verdict = "looks_fine", note = "jlog 격리 검사 — 허용값 밖 verdict 위반 주입"),
               auto_unbox = TRUE, null = "null"), AUD)
  r <- suppressWarnings(system2("Rscript", c(shQuote(LIB), "verify", shQuote(AUD)), stdout = TRUE, stderr = TRUE))
  unlink(AUD, force = TRUE)
  invisible(r)
}
has_evt <- function(f, ev) file.exists(f) && any(grepl(sprintf('"event": *"%s"', ev), readLines(f, warn = FALSE, encoding = "UTF-8")))
n_lines <- function(f) if (file.exists(f)) length(readLines(f, warn = FALSE)) else NA_integer_

cat("=== A. 위반 주입이 지정 싱크로 간다 · 운영 로그는 불변 ===\n")
s1 <- file.path(tempdir(), sprintf("iso1_%d.jsonl", Sys.getpid()))
run_verify(s1)
if (has_evt(s1, "audit_rejected")) ok("A audit_rejected 가 QVEST_RP_JLOG 싱크에 기록") else
  ng("A 싱크에 기록 없음", if (file.exists(s1)) substr(paste(readLines(s1, warn = FALSE), collapse = " "), 1, 120) else "파일 없음")
sz1 <- if (file.exists(PROD)) file.size(PROD) else 0
if (identical(sz1, sz0)) ok(sprintf("A 운영 로그 크기 불변 (%d)", sz0)) else ng("A ★운영 로그가 커졌다", sprintf("%d → %d", sz0, sz1))

cat("\n=== B. 싱크를 바꾸면 따라간다 (고정 경로가 아니다) ===\n")
s2 <- file.path(tempdir(), sprintf("iso2_%d.jsonl", Sys.getpid()))
run_verify(s2)
if (has_evt(s2, "audit_rejected") && !has_evt(s1, "audit_verified")) ok("B 두 번째 싱크에도 기록 — env 를 읽는다") else ng("B 싱크 전환 실패")
n1 <- n_lines(s1); run_verify(s2); n1b <- n_lines(s1)
if (!is.na(n1) && identical(n1, n1b)) ok("B 이전 싱크는 더 안 자란다") else ng("B 이전 싱크가 자랐다", sprintf("%s → %s", n1, n1b))
unlink(c(s1, s2), force = TRUE)

cat("\n=== C. 모든 레인 싱크가 환경변수를 읽는가 (재도출) ===\n")
## 셸 레인 판정기 — 환경변수 기본값 문법이 있고 운영 경로 하드코딩이 없다
sh_sink_ok <- function(s) {
  hard <- grepl('JLOG="$ROOT/.cache/reinforce_auto_log.jsonl"', s, fixed = TRUE)
  envd <- grepl("QVEST_RP_JLOG:-", s, fixed = TRUE)
  any(envd) && !any(hard)
}
for (f in c("02_Infrastructure/ops/rf_fidelity_audit.sh", "02_Infrastructure/ops/rf_fidelity_fanout.sh",
            "02_Infrastructure/ops/rf_replication_auto.sh", "02_Infrastructure/ops/rf_l2_auto.sh")) {
  s <- readLines(file.path(ROOT, f), warn = FALSE, encoding = "UTF-8")
  if (sh_sink_ok(s)) ok(sprintf("C %s", basename(f))) else ng(sprintf("C %s 하드코딩", basename(f)))
}
for (f in c("02_Infrastructure/ops/rf_fidelity_audit_lib.R", "02_Infrastructure/ops/rf_replication_verify.R",
            "02_Infrastructure/ops/rf_l2_lib.R")) {
  s <- paste(readLines(file.path(ROOT, f), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (grepl('Sys.getenv("QVEST_RP_JLOG"', s, fixed = TRUE)) ok(sprintf("C %s", basename(f))) else ng(sprintf("C %s 하드코딩", basename(f)))
}
## C-M 돌연변이 — 판정기가 하드코딩 사본을 실제로 잡는가(판별력 · 사본은 메모리에서만 만든다)
.mut <- gsub("${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}", "$ROOT/.cache/reinforce_auto_log.jsonl",
             readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh"), warn = FALSE, encoding = "UTF-8"), fixed = TRUE)
if (!sh_sink_ok(.mut)) ok("C-M [돌연변이] 레인 싱크를 운영 경로 하드코딩으로 바꾸면 판정기가 잡는다") else
  ng("C-M 판별력 없음", "하드코딩 사본이 통과했다")
hk <- paste(readLines(file.path(ROOT, "08_Tests/hooks/run_all_hooks.sh"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl("export QVEST_RP_JLOG=", hk, fixed = TRUE)) ok("C 배터리 러너가 전역 싱크를 임시 파일로 돌린다") else ng("C 배터리 전역 격리 없음")
cat(sprintf("\n== test_rf_jlog_isolation: %d pass · %d fail ==\n", P, F))
cat(sprintf('{"test":"rf_jlog_isolation","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
