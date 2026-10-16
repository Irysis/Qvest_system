## test_qw_updatefile_unattended.R — 02_Infrastructure/data/qw_updatefile_unattended.sh 검사(도훈 결정 QW-UPDATEFILE-UNATTENDED 안 A · 2026-10-16)
##   수급 명령을 스텁으로 바꿔(QWUF_REFRESH_CMD) 운영 퀀티 · .cache 를 건드리지 않는다.
##   1 벤치 수급 rc≠0 → 건너뜀(수급 명령 미호출) · 2 꺼짐 · 3 rc=0 · Universe_Support 낡음 → 세 파일 · -SkipLogin · -MaxRounds 2 · 전진 → 0
##   4 Universe_Support 최신 → 두 파일 · 5 전진 없음 → 10 · 6 시간 상한(멈춘 수급) → 10 · 빨리 끝남 · 7 기록 json · 8 SkipLogin 이 빠질 수 없다(정적)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT); Sys.setenv(QM_ROOT = ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
SH <- file.path(ROOT, "02_Infrastructure/data/qw_updatefile_unattended.sh")
PY <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")
td <- gsub("\\\\", "/", file.path(tempdir(), "qwuf")); unlink(td, recursive = TRUE); dir.create(td)
ux <- function(p) sub("^([A-Za-z]):", "/\\L\\1", p, perl = TRUE)                       # C:/x → /c/x (bash)
st0 <- '{"Investor_Act":{"ymd":"20261002","ts":"x"},"Consensus":{"ymd":"20261002","ts":"x"},"Universe_Support":{"ymd":"20260828","ts":"x"}}'
st1 <- '{"Investor_Act":{"ymd":"20261016","ts":"y"},"Consensus":{"ymd":"20261016","ts":"y"},"Universe_Support":{"ymd":"20260828","ts":"x"}}'
mk_us <- function(maxd) { p <- file.path(td, paste0("us_", maxd, ".parquet")); arrow::write_parquet(data.frame(Date = as.Date(c("2026-07-31", maxd)), Ticker = "A", K200 = 1L), p); p }
stub <- file.path(td, "stub.sh")
writeLines(c("#!/usr/bin/env bash", 'echo "$@" >> "$STUB_CALLS"', '[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"', '[ -n "${STUB_AFTER:-}" ] && cp "$STUB_AFTER" "$QWUF_STATE"', "exit ${STUB_RC:-0}"), stub)
writeLines(st1, file.path(td, "after.json"))
run <- function(bench_rc, us, env = character(0), after = TRUE, sleep = "", tmo = "60") {
  stf <- file.path(td, "state.json"); writeLines(st0, stf); calls <- file.path(td, "calls.txt"); unlink(calls); lg <- file.path(td, "log.json"); unlink(lg)
  e <- c(QWUF_REFRESH_CMD = paste("bash", ux(stub)), QWUF_STATE = stf, QWUF_US_PARQUET = us, QWUF_TODAY = "2026-10-17", QWUF_TIMEOUT = tmo, QWUF_LOG = lg,
         STUB_CALLS = calls, STUB_AFTER = if (after) file.path(td, "after.json") else "", STUB_SLEEP = sleep, QVEST_QW_UPDATEFILE_UNATTENDED = "1", env)
  old <- Sys.getenv(names(e), unset = NA); do.call(Sys.setenv, as.list(e)); on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) })
  t0 <- Sys.time(); o <- suppressWarnings(system2("bash", c(shQuote(ux(SH)), bench_rc, shQuote(ux(PY))), stdout = TRUE, stderr = TRUE))
  list(rc = attr(o, "status") %||% 0L, out = o, calls = if (file.exists(calls)) readLines(calls) else character(0), secs = as.numeric(difftime(Sys.time(), t0, units = "secs")),
       log = if (file.exists(lg)) fromJSON(lg) else NULL, last = tail(grep("^QWUF\t", o, value = TRUE), 1))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
us_old <- mk_us("2026-08-28"); us_new <- mk_us("2026-10-15")

r1 <- run("2", us_old)
if (identical(as.integer(r1$rc), 10L) && !length(r1$calls) && grepl("state=skipped", r1$last)) ok("1 벤치 수급 rc=2(전진 없음) → 건너뜀 · 수급 명령 미호출 · 10") else ng("1", paste(r1$rc, r1$last))
r2 <- run("0", us_old, env = c(QVEST_QW_UPDATEFILE_UNATTENDED = "0"))
if (identical(as.integer(r2$rc), 10L) && !length(r2$calls) && grepl("state=disabled", r2$last)) ok("2 QVEST_QW_UPDATEFILE_UNATTENDED=0 → 꺼짐") else ng("2", paste(r2$rc, r2$last))
r3 <- run("0", us_old)
if (identical(as.integer(r3$rc), 0L) && length(r3$calls) == 1L && grepl("-SkipLogin", r3$calls, fixed = TRUE) && grepl("-MaxRounds 2", r3$calls, fixed = TRUE) &&
    grepl("-Only Universe_Support,Investor_Act,Consensus", r3$calls, fixed = TRUE) && grepl("state=advanced", r3$last) && grepl("advanced=2", r3$last))
  ok("3 rc=0 · Universe_Support 낡음(08-28 < 직전 월말 09-30) → 세 파일 · -SkipLogin · -MaxRounds 2 · 전진 2 → 0(호출부 재적재)") else ng("3", paste(r3$rc, r3$calls, r3$last))
r4 <- run("0", us_new)
if (identical(as.integer(r4$rc), 0L) && grepl("-Only Investor_Act,Consensus", r4$calls, fixed = TRUE) && !grepl("Universe_Support", r4$calls, fixed = TRUE))
  ok("4 Universe_Support 최신(10-15 ≥ 직전 월말) → 두 파일만") else ng("4", paste(r4$calls))
r5 <- run("0", us_new, after = FALSE)
if (identical(as.integer(r5$rc), 10L) && grepl("state=no_advance", r5$last)) ok("5 수급했지만 전진 없음 → 10(재적재 안 함)") else ng("5", paste(r5$rc, r5$last))
## 6 · 9 · 10 — 진행 인지 상한(10-17): 기본 상한 뒤 수급 Excel 이 일하면(CPU 증가) 기다리고, 멈추면(STALL_N) · 절대 상한(HARD)이면 끊고 이 실행의 Excel 을 닫는다
mark <- file.path(td, "cleanup.txt"); ctr <- file.path(td, "cpu.txt")
pa <- function(prog, hard = "60", stall = "2") c(QWUF_POLL_S = "1", QWUF_STALL_N = stall, QWUF_HARD_TIMEOUT = hard, QWUF_PROGRESS_CMD = prog,
                                                  QWUF_CLEANUP_CMD = paste0("echo cleaned >> ", ux(mark)))
grow <- paste0("f=", ux(ctr), "; n=$(cat $f 2>/dev/null || echo 0); n=$((n+10)); echo $n > $f; echo $n")
unlink(mark); r6 <- run("0", us_new, after = TRUE, sleep = "30", tmo = "3", env = pa("true"))
if (identical(as.integer(r6$rc), 10L) && r6$secs < 25 && grepl("rc=124", r6$last) && file.exists(mark))
  ok(sprintf("6 멈춘 수급(CPU 무증가) → 기본 상한 뒤 STALL 2회에서 끊고 이 실행 Excel 정리 · 10 · %.0f초 · 리프레시 계속", r6$secs)) else ng("6", paste(r6$rc, r6$secs, r6$last, file.exists(mark)))
unlink(c(mark, ctr)); r9 <- run("0", us_new, after = TRUE, sleep = "7", tmo = "2", env = pa(grow))
if (identical(as.integer(r9$rc), 0L) && grepl("state=advanced", r9$last) && !file.exists(mark) && r9$secs >= 6 && any(grepl("일하는 중", r9$out)))
  ok(sprintf("9 기본 상한(2초)이 지나도 Excel 이 일하면(CPU 증가) 기다려 끝까지 받는다 · 정리 없음 · %.0f초", r9$secs)) else ng("9", paste(r9$rc, r9$last, file.exists(mark), r9$secs))
unlink(c(mark, ctr)); r10 <- run("0", us_new, after = TRUE, sleep = "30", tmo = "2", env = pa(grow, hard = "5", stall = "9"))
if (identical(as.integer(r10$rc), 10L) && grepl("rc=124", r10$last) && file.exists(mark) && r10$secs < 20 && any(grepl("hard", r10$out)))
  ok(sprintf("10 일하는 중이어도 절대 상한(5초)에서 끊고 정리 · 10 · %.0f초", r10$secs)) else ng("10", paste(r10$rc, r10$last, file.exists(mark), r10$secs))
if (!is.null(r3$log) && identical(r3$log$state, "advanced") && identical(r3$log$bench_rc, "0") && !is.null(r1$log) && identical(r1$log$state, "skipped"))
  ok("7 기록 json — 상태 · 대상 · 전진 · 벤치 rc") else ng("7")
src <- readLines(SH, warn = FALSE, encoding = "UTF-8")
cl <- grep('"\\$\\{CMD\\[@\\]\\}"', src, value = TRUE)
if (length(cl) == 1L && grepl("-SkipLogin", cl, fixed = TRUE) && !any(grepl("Ensure-Login|-SkipLogin:\\$false", src)))
  ok("8 수급 호출 줄은 하나 · -SkipLogin 고정(로그인 클릭 경로 없음)") else ng("8", paste(cl, collapse = " | "))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"qw_updatefile_unattended","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
