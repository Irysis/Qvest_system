## test_qw_updatefile_unattended.R — 02_Infrastructure/data/qw_updatefile_unattended.sh 검사(도훈 결정 QW-UPDATEFILE-UNATTENDED 안 A · 2026-10-16)
##   수급 명령을 스텁으로 바꿔(QWUF_REFRESH_CMD) 운영 퀀티 · .cache 를 건드리지 않는다.
##   (10-17 RAWDATA 퀀티 단일 · 결정 RAWDATA-QW-ONLY-20261017) 1 벤치 수급 rc=3(전제 부재)만 건너뜀 · 1b rc=1 · 1c rc=2 여도 시도 · 2 꺼짐 ·
##   3 4종 매일(OHLCVS → Universe_Support → Investor_Act → Consensus) · -SkipLogin · -MaxRounds 2 · 전진 → 0 · 4 Universe_Support 가 최신이어도 4종(월말 조건 퇴역) ·
##   5 전진 없음 → 10 · 6 시간 상한(멈춘 수급) → 10 · 빨리 끝남 · 7 기록 json · 8 SkipLogin 이 빠질 수 없다(정적) · 11 완료 수(done D/N) · 미완료 표식 · 13 진행 계측 = Excel 별 누적 CPU(책 전환은 정체가 아니다 · 11-09)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT); Sys.setenv(QM_ROOT = ROOT)
source(file.path(ROOT, "02_Infrastructure/ops/qv_bash.R"))   # bare "bash" 금지(금칙 ⑦ · 11-07) — WSL 있는 PC 에선 System32 bash 가 PATH 보다 먼저 잡힌다
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
writeLines(c("#!/usr/bin/env bash", 'echo "$@" >> "$STUB_CALLS"', '[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"', '[ -n "${STUB_AFTER:-}" ] && cp "$STUB_AFTER" "$QWUF_STATE"',
             '[ -n "${STUB_END:-}" ] && echo "===== END 00:00:00 / done ${STUB_END} (target 20261016) ====="', "exit ${STUB_RC:-0}"), stub)
writeLines(st1, file.path(td, "after.json"))
run <- function(bench_rc, us, env = character(0), after = TRUE, sleep = "", tmo = "60") {
  stf <- file.path(td, "state.json"); writeLines(st0, stf); calls <- file.path(td, "calls.txt"); unlink(calls); lg <- file.path(td, "log.json"); unlink(lg)
  e <- c(QWUF_REFRESH_CMD = paste("bash", ux(stub)), QWUF_STATE = stf, QWUF_US_PARQUET = us, QWUF_TODAY = "2026-10-17", QWUF_TIMEOUT = tmo, QWUF_LOG = lg,
         STUB_CALLS = calls, STUB_AFTER = if (after) file.path(td, "after.json") else "", STUB_SLEEP = sleep, QVEST_QW_UPDATEFILE_UNATTENDED = "1", env)
  old <- Sys.getenv(names(e), unset = NA); do.call(Sys.setenv, as.list(e)); on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) })
  t0 <- Sys.time(); o <- suppressWarnings(system2(qv_bash(), c(shQuote(ux(SH)), bench_rc, shQuote(ux(PY))), stdout = TRUE, stderr = TRUE))
  list(rc = attr(o, "status") %||% 0L, out = o, calls = if (file.exists(calls)) readLines(calls) else character(0), secs = as.numeric(difftime(Sys.time(), t0, units = "secs")),
       log = if (file.exists(lg)) fromJSON(lg) else NULL, last = tail(grep("^QWUF\t", o, value = TRUE), 1))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
us_old <- mk_us("2026-08-28"); us_new <- mk_us("2026-10-15")

r1 <- run("3", us_old)
if (identical(as.integer(r1$rc), 10L) && !length(r1$calls) && grepl("state=skipped", r1$last)) ok("1 벤치 수급 rc=3(전제 부재 — 로그인 창) → 건너뜀 · 수급 명령 미호출 · 10") else ng("1", paste(r1$rc, r1$last))
r1b <- run("1", us_new); r1c <- run("2", us_new)
if (length(r1b$calls) == 1L && length(r1c$calls) == 1L && grepl("state=advanced", r1b$last) && grepl("state=advanced", r1c$last))
  ok("1b rc=1(일시 오류 — 10-17 RPC 실패) · 1c rc=2(벤치 변화 없음)여도 시도한다 — 퀀티 단일 원천(10-17)") else ng("1b/1c", paste(r1b$last, r1c$last))
r2 <- run("0", us_old, env = c(QVEST_QW_UPDATEFILE_UNATTENDED = "0"))
if (identical(as.integer(r2$rc), 10L) && !length(r2$calls) && grepl("state=disabled", r2$last)) ok("2 QVEST_QW_UPDATEFILE_UNATTENDED=0 → 꺼짐") else ng("2", paste(r2$rc, r2$last))
r3 <- run("0", us_old)
if (identical(as.integer(r3$rc), 0L) && length(r3$calls) == 1L && grepl("-SkipLogin", r3$calls, fixed = TRUE) && grepl("-MaxRounds 2", r3$calls, fixed = TRUE) &&
    grepl("-Only OHLCVS,Universe_Support,Investor_Act,Consensus", r3$calls, fixed = TRUE) && grepl("state=advanced", r3$last) && grepl("advanced=2", r3$last))
  ok("3 rc=0 → 4종(주가 · 위생 먼저) · -SkipLogin · -MaxRounds 2 · 전진 2 → 0(호출부 재적재)") else ng("3", paste(r3$rc, r3$calls, r3$last))
r4 <- run("0", us_new)
if (identical(as.integer(r4$rc), 0L) && grepl("-Only OHLCVS,Universe_Support,Investor_Act,Consensus", r4$calls, fixed = TRUE))
  ok("4 Universe_Support 가 최신(10-15)이어도 4종 매일 — 월말 조건 퇴역(위생 플래그도 매일)") else ng("4", paste(r4$calls))
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
## 12 기본값(10-20 도훈 '제한시간 없애' · '정체 감지 제거') — 절대 상한 · 정체 끊기 주입 없음 = CPU 가 늘지 않아도 끊지 않고 드라이버 끝까지 기다린다(정체는 로그만)
unlink(c(mark, ctr)); r12 <- run("0", us_new, after = TRUE, sleep = "8", tmo = "2",
                                 env = c(QWUF_POLL_S = "1", QWUF_PROGRESS_CMD = "true", QWUF_CLEANUP_CMD = paste0("echo cleaned >> ", ux(mark))))
if (identical(as.integer(r12$rc), 0L) && grepl("state=advanced", r12$last) && grepl("\trc=0\t", r12$last, fixed = TRUE) && !file.exists(mark) &&
    r12$secs >= 7 && any(grepl("끊지 않고 기다린다", r12$out)) && !any(grepl("수급 종료", r12$out)))
  ok(sprintf("12 기본값 = 절대 상한 · 정체 끊기 없음 — CPU 무증가여도 끝까지 받는다 · 정리 없음 · 정체는 로그만 · %.0f초", r12$secs)) else ng("12", paste(r12$rc, r12$last, file.exists(mark), r12$secs))
## 13 진행 계측 = 이 실행이 띄운 Excel 마다의 누적 CPU 합(11-09) — 책 하나가 끝나 그 Excel 이 닫혀도 진행 값이 줄지 않는다
##   13a 책 전환: A(50 → 100)가 닫히고 B(5 · 10 · …)가 일한다. 구 계측(살아 있는 Excel 의 합)은 5 < 100 이라 '증가 없음'으로 찍고 STALL 2 에서 끊었다
##   13b 진짜 정체: A · B 둘 다 늘지 않는다 → 누적도 그대로 → STALL 2 에서 끊는다(계측이 늘 '일하는 중'만 내는 게 아니라는 대조)
trans <- paste0("f=", ux(ctr), "; n=$(cat $f 2>/dev/null || echo 0); n=$((n+1)); echo $n > $f; ",
                "if [ $n -le 2 ]; then echo \"A_1 $((n*50))\"; else echo \"B_2 $(( (n-2)*5 ))\"; fi")
unlink(c(mark, ctr)); r13a <- run("0", us_new, after = TRUE, sleep = "8", tmo = "2", env = pa(trans))
if (identical(as.integer(r13a$rc), 0L) && grepl("state=advanced", r13a$last) && !file.exists(mark) && !any(grepl("수급 종료", r13a$out)) &&
    !any(grepl("증가 없음", r13a$out)) && any(grepl("일하는 중", r13a$out)))
  ok(sprintf("13a 책 전환(앞 Excel 닫힘 · 새 Excel 일함) = 진행 — '증가 없음' 없이 끝까지 받는다 · 정리 없음 · %.0f초", r13a$secs)) else
  ng("13a", paste(c(r13a$rc, r13a$last, file.exists(mark), grep("qwuf", r13a$out, value = TRUE)), collapse = " | "))
flat <- "printf 'A_1 100\\nB_2 50\\n'"
unlink(c(mark, ctr)); r13b <- run("0", us_new, after = TRUE, sleep = "30", tmo = "2", env = pa(flat))
if (identical(as.integer(r13b$rc), 10L) && grepl("rc=124", r13b$last) && file.exists(mark) && r13b$secs < 25)
  ok(sprintf("13b Excel 둘 다 일하지 않으면 누적도 그대로 → STALL 2 에서 끊고 정리 · 10 · %.0f초", r13b$secs)) else
  ng("13b", paste(c(r13b$rc, r13b$last, file.exists(mark), r13b$secs), collapse = " | "))
if (!is.null(r3$log) && identical(r3$log$state, "advanced") && identical(r3$log$bench_rc, "0") && !is.null(r1$log) && identical(r1$log$state, "skipped"))
  ok("7 기록 json — 상태 · 대상 · 전진 · 벤치 rc") else ng("7")
## 11 완료 수 · 미완료 표식(10-17) — 드라이버 END 줄의 done D/N 을 마지막 줄에 싣는다 · D<N 또는 rc≠0 = incomplete=1(호출부 DR_FAILED)
r11a <- run("0", us_new, env = c(STUB_END = "4/4")); r11b <- run("0", us_new, env = c(STUB_END = "3/4")); r11c <- run("0", us_new, env = c(STUB_RC = "1"))
if (grepl("done=4/4\tincomplete=0", r11a$last, fixed = TRUE) && grepl("done=3/4\tincomplete=1", r11b$last, fixed = TRUE) &&
    grepl("incomplete=1", r11c$last, fixed = TRUE) && identical(r11b$log$done, "3/4") && identical(r11b$log$incomplete, "1"))
  ok("11 done D/N · 미완료(D<N · rc≠0) 표식 = 마지막 줄 · 기록 json") else ng("11", paste(r11a$last, r11b$last, r11c$last))
src <- readLines(SH, warn = FALSE, encoding = "UTF-8")
cl <- grep('"\\$\\{CMD\\[@\\]\\}"', src, value = TRUE)
if (length(cl) == 1L && grepl("-SkipLogin", cl, fixed = TRUE) && !any(grepl("Ensure-Login|-SkipLogin:\\$false", src)))
  ok("8 수급 호출 줄은 하나 · -SkipLogin 고정(로그인 클릭 경로 없음)") else ng("8", paste(cl, collapse = " | "))

## B — 신규 상장 보충 대기열(2026-11-08 · BUILD_20261108.md §1 · data/qw_backfill_pending.py)
##   B1 대기열의 Time Series DB → 수급 호출에 -FromOverride <DB>=<시작일> · Peer DB(Fundamental)은 넘기지 않는다 · 끝낸 DB(ts ≥ 시작)은 지운다
##   B2 수급이 그 DB를 끝내지 못하면(ts 그대로) 대기열에 남긴다(다음 밤 다시)
##   B3 가짜 수급 명령(QWUF_REFRESH_CMD)만 주고 대기열 경로를 안 주면 실제 .cache 대기열을 읽지 않는다(-FromOverride 없음)
pend <- file.path(td, "pending.json")
mk_pend <- function() writeLines('{"Investor_Act":{"from":"20250617","codes":["A0001A0"],"layout":"ts"},"Fundamental":{"from":"20250617","layout":"peer"}}', pend)
writeLines('{"Investor_Act":{"ymd":"20261016","ts":"2099-01-01T00:00:00"},"Consensus":{"ymd":"20261016","ts":"2099-01-01T00:00:00"},"Universe_Support":{"ymd":"20260828","ts":"x"}}', file.path(td, "after_new.json"))
writeLines('{"Investor_Act":{"ymd":"20261002","ts":"2000-01-01T00:00:00"},"Consensus":{"ymd":"20261016","ts":"2099-01-01T00:00:00"},"Universe_Support":{"ymd":"20260828","ts":"x"}}', file.path(td, "after_old.json"))
mk_pend(); rb1 <- run("0", us_new, env = c(QWUF_BACKFILL_PENDING = pend, STUB_AFTER = file.path(td, "after_new.json")))
pb1 <- tryCatch(fromJSON(pend), error = function(e) list(err = TRUE))
if (length(rb1$calls) == 1L && grepl("-FromOverride Investor_Act=20250617", rb1$calls, fixed = TRUE) && !grepl("Fundamental=", rb1$calls, fixed = TRUE) &&
    is.null(pb1$Investor_Act) && !is.null(pb1$Fundamental))
  ok("B1 보충 대기열 → -FromOverride Investor_Act=20250617(Peer DB 제외) · 끝낸 DB는 대기열에서 지움") else ng("B1", paste(rb1$calls, toJSON(pb1, auto_unbox = TRUE)))
mk_pend(); rb2 <- run("0", us_new, env = c(QWUF_BACKFILL_PENDING = pend, STUB_AFTER = file.path(td, "after_old.json")))
pb2 <- tryCatch(fromJSON(pend), error = function(e) list(err = TRUE))
if (length(rb2$calls) == 1L && grepl("-FromOverride Investor_Act=20250617", rb2$calls, fixed = TRUE) && identical(pb2$Investor_Act$from, "20250617"))
  ok("B2 수급이 그 DB를 못 끝내면(ts 그대로) 대기열에 남긴다") else ng("B2", paste(rb2$calls, toJSON(pb2, auto_unbox = TRUE)))
rb3 <- run("0", us_new)
if (length(rb3$calls) == 1L && !grepl("-FromOverride", rb3$calls, fixed = TRUE))
  ok("B3 가짜 수급 명령 + 대기열 경로 없음 → 실제 .cache 대기열 무접촉(-FromOverride 없음)") else ng("B3", paste(rb3$calls))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"qw_updatefile_unattended","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
