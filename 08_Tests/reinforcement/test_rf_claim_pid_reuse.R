#!/usr/bin/env Rscript
#==============================================================================
# test_rf_claim_pid_reuse.R — claim 생존 판정이 **pid 재사용**에 속지 않는가 (2026-09-07 · 실사고 2026-09-06)
#
# 왜: 절전으로 죽은 owner pid 12816 을 Windows 가 시스템 프로세스 Widgets 에 재사용해 alive=TRUE 로 읽혔고,
#   6시간 시간 폴백(claim_stale_reclaim … 18.53 h > 6.00 h)으로만 풀렸다. 절전이 6시간보다 짧았다면 루프가
#   최대 6시간 halt_claimed 로 섰다 — 그리고 그 로그는 정상 대기와 글자 그대로 같다.
# 양방향:
#   A 살아있는 진짜 owner(현재 프로세스 · 실제 시작시각)는 지킨다
#   B 위반 주입 1 — pid 는 살아있는 무관 프로세스인데 기록 시작시각이 다름 → 즉시 회수(시간 폴백 전)
#   C 위반 주입 2 — 죽은 pid → 회수(종전 규칙 유지)
#   D 구판 호환 — proc_start 없는 owner.json + 살아있는 pid → 시간 폴백 전엔 회수 안 함
#   E 시작시각 조회 실패 = 모른다 = 살아있다(살아있는 배치를 빼앗지 않는다)
#   F 획득이 proc_start 를 기록한다(다음 실행이 판단할 근거)
# 부작용 없음: tempdir 격리 claim · 운영 .cache/reinforce_auto.claim 은 안 건드린다. 위반 주입 B 의 무관 프로세스는
#   숨김 PowerShell 슬리퍼(진짜 Windows pid — MSYS sleep 의 pid 는 tasklist 에 없다)이고 함수 안 on.exit 으로 죽인다.
#==============================================================================
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/ops/rf_claim.R"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }
P <- file.path(tempdir(), sprintf("rf_claim_reuse_%d", Sys.getpid()))
reset <- function() { unlink(P, recursive = TRUE, force = TRUE); dir.create(P, recursive = TRUE, showWarnings = FALSE) }
set_owner <- function(pid, proc_start = NULL) {
  rec <- list(pid = pid, started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), host = "fixture")
  if (!is.null(proc_start)) rec$proc_start <- proc_start
  writeLines(toJSON(rec, auto_unbox = TRUE), file.path(P, "owner.json"))
}
self <- Sys.getpid(); DEAD <- 999999L
WIN <- identical(.Platform$OS.type, "windows")
for (fn in c("rf_claim_proc_start", "rf_claim_start_matches", "rf_claim_pid_alive", "rf_claim_acquire")) {
  if (!exists(fn)) { cat(sprintf("  FAIL %s 부재\n", fn))
    cat('{"test":"rf_claim_pid_reuse","pass":0,"fail":1,"total":1}\n'); quit(status = 1L) }
}

writeLines("=== 계기 — 프로세스 시작시각 조회 ===")
st_self <- rf_claim_proc_start(self)
if (length(st_self) == 1L && is.finite(st_self) && abs(st_self - as.numeric(Sys.time())) < 86400)
  ok(sprintf("자기 프로세스 시작시각 조회 — epoch %.0f (지금과 %.0f초 차)", st_self, as.numeric(Sys.time()) - st_self)) else
  ng("자기 프로세스 시작시각 조회 실패 — 아래 판정 전부 구판 규칙으로 떨어진다", paste(st_self))
if (!is.finite(rf_claim_proc_start(DEAD))) ok("없는 pid → NA(판단 불가)") else ng("없는 pid 에 시작시각이 나왔다")
if (isTRUE(rf_claim_start_matches(st_self, st_self + 2)) && !isTRUE(rf_claim_start_matches(st_self, st_self + 60)))
  ok("허용 오차 — 2초 차는 같은 프로세스 · 60초 차는 남") else ng("허용 오차 판정")
if (isTRUE(rf_claim_start_matches(NA_real_, st_self)) && isTRUE(rf_claim_start_matches(st_self, NA_real_)))
  ok("기록 없음·조회 실패 → 일치로 본다(보수적)") else ng("NA 를 불일치로 읽는다 — 살아있는 배치를 빼앗을 위험")

writeLines("=== A. 양성 대조 — 진짜 owner(현재 프로세스 · 실제 시작시각) ===")
reset(); set_owner(self, st_self)
a <- rf_claim_acquire(P, stale_hours = 999)
if (!isTRUE(a$ok) && identical(a$reason, "claimed")) ok("살아있는 진짜 owner → 차단(회수 안 함)") else
  ng("진짜 owner 의 claim 을 빼앗았다 — 동시 배치 2개", paste(a$reason, a$note))
if (isTRUE(rf_claim_pid_alive(self, proc_start = st_self))) ok("rf_claim_pid_alive(자기 pid, 실제 시작시각) = TRUE") else ng("자기 pid 를 죽었다고 한다")

writeLines("=== B. 위반 주입 1 — 살아있는 무관 프로세스인데 기록 시작시각이 다름(pid 재사용) ===")
spawn_sleeper <- function() {
  out <- if (WIN) {
    cmd <- "(Start-Process -FilePath powershell -ArgumentList '-NoProfile','-NonInteractive','-Command','Start-Sleep 120' -WindowStyle Hidden -PassThru).Id"
    tryCatch(suppressWarnings(system2("powershell", c("-NoProfile", "-NonInteractive", "-Command", shQuote(cmd)),
                                      stdout = TRUE, stderr = FALSE)), error = function(e) NULL)
  } else {
    # ★POSIX 는 슬리퍼를 안 띄운다 — pid 를 받으려면 argv 에 셸 문법(리다이렉트·`&`·`$!`)이 들어가고
    #   그건 r-portability 금칙 5 다(스캐너가 텍스트로 잡는다 · 실측 2026-09-07 배터리). 아래 폴백이
    #   자기 pid 로 **같은 술어**(pid 생존 + 기록 시작시각 불일치)를 재므로 검사력은 그대로다.
    NULL
  }
  v <- suppressWarnings(as.integer(trimws(as.character(out %||% character(0))))); v <- v[!is.na(v)]
  if (length(v)) v[1] else NA_integer_
}
kill_pid <- function(pid) {
  if (is.na(pid) || identical(as.integer(pid), as.integer(self))) return(invisible(NULL))
  if (WIN) suppressWarnings(system2("taskkill", c("/PID", pid, "/F"), stdout = FALSE, stderr = FALSE))
  else suppressWarnings(system2("kill", c("-9", pid), stdout = FALSE, stderr = FALSE))
  invisible(NULL)
}
run_B <- function() {
  sl <- spawn_sleeper(); on.exit(kill_pid(sl), add = TRUE)      # ★함수 안 on.exit — 최상위 on.exit 은 no-op
  st_sl <- if (!is.na(sl)) rf_claim_proc_start(sl) else NA_real_
  if (is.na(sl) || !is.finite(st_sl) || !isTRUE(rf_claim_pid_alive(sl))) {
    # 슬리퍼를 못 띄우면 자기 pid 로 같은 술어(pid 생존 + 시작시각 불일치)를 잰다 — 대체를 숨기지 않는다
    writeLines(sprintf("  (note) 무관 프로세스 스폰 실패(pid=%s) — 자기 pid 로 대체", as.character(sl)))
    sl <- self; st_sl <- st_self
  } else writeLines(sprintf("  (fixture) 무관 프로세스 pid=%d 시작 %.0f — tasklist 생존 확인", sl, st_sl))
  if (!isTRUE(rf_claim_pid_alive(sl, proc_start = st_sl - 3600)))
    ok("계기: 살아있는 pid + 시작시각 1h 불일치 → FALSE(남의 프로세스)") else
    ng("계기: 시작시각 불일치를 살아있다고 읽는다 ★실사고(Widgets 재사용)")
  if (isTRUE(rf_claim_pid_alive(sl, proc_start = st_sl))) ok("계기: 같은 프로세스 + 같은 시작시각 → TRUE") else ng("계기: 진짜 owner 를 죽었다고 한다")
  reset(); set_owner(sl, st_sl - 3600)
  b <- rf_claim_acquire(P, stale_hours = 999)                       # 나이로는 절대 안 풀리는 조건
  if (isTRUE(b$ok) && grepl("재사용", b$note %||% "", fixed = TRUE))
    ok("pid 재사용 owner → 나이 무관 즉시 회수(시간 폴백 전)") else
    ng("pid 재사용 owner 미회수 — 6시간 폴백까지 halt_claimed ★실사고", paste(b$reason, b$note))
  o <- tryCatch(fromJSON(file.path(P, "owner.json"), simplifyVector = TRUE), error = function(z) NULL)
  if (!is.null(o) && identical(as.integer(o$pid), as.integer(self))) ok("회수 후 owner = 나(제자리 인수)") else ng("회수 후 owner 가 내가 아니다")
}
run_B()

writeLines("=== C. 위반 주입 2 — 죽은 pid(+proc_start 기록) → 회수 ===")
reset(); set_owner(DEAD, st_self)
c1 <- rf_claim_acquire(P, stale_hours = 999)
if (isTRUE(c1$ok) && grepl("사망", c1$note %||% "", fixed = TRUE)) ok("죽은 pid → 나이 무관 즉시 회수(종전 규칙 유지)") else ng("죽은 pid 미회수", paste(c1$reason, c1$note))

writeLines("=== D. 구판 호환 — proc_start 없는 owner.json + 살아있는 pid ===")
reset(); set_owner(self)                                            # proc_start 없음 = 구판 claim
d1 <- rf_claim_acquire(P, stale_hours = 999)
if (!isTRUE(d1$ok) && identical(d1$reason, "claimed")) ok("구판 owner(살아있는 pid) → 시간 폴백 전엔 회수 안 함") else ng("구판 owner 를 즉시 빼앗았다", paste(d1$reason, d1$note))
d2 <- rf_claim_acquire(P, stale_hours = -1)
if (isTRUE(d2$ok) && grepl("시간 폴백", d2$note %||% "", fixed = TRUE)) ok("구판 owner → 시간 폴백은 그대로 작동") else ng("시간 폴백 훼손", paste(d2$reason, d2$note))

writeLines("=== E. 조회 실패 = 모른다 = 살아있다 (계기 대체 주입) ===")
.orig <- rf_claim_proc_start
rf_claim_proc_start <- function(pid) NA_real_                        # 전역 정의를 덮어 조회 실패를 흉내낸다
e1 <- isTRUE(rf_claim_pid_alive(self, proc_start = 12345))
reset(); set_owner(self, 12345)
e2 <- rf_claim_acquire(P, stale_hours = 999)
rf_claim_proc_start <- .orig
if (e1 && !isTRUE(e2$ok) && identical(e2$reason, "claimed"))
  ok("시작시각 조회 실패 → 살아있다(차단) — 살아있는 배치를 빼앗지 않는다") else ng("조회 실패를 죽음으로 읽는다", paste(e1, e2$reason))

writeLines("=== F. 획득이 proc_start 를 기록한다 ===")
unlink(P, recursive = TRUE, force = TRUE)
f <- rf_claim_acquire(P, stale_hours = 999)
o <- tryCatch(fromJSON(file.path(P, "owner.json"), simplifyVector = TRUE), error = function(z) NULL)
ps_rec <- suppressWarnings(as.numeric(o$proc_start %||% NA))
if (isTRUE(f$ok) && !is.null(o) && is.finite(ps_rec) && abs(ps_rec - st_self) <= 5)
  ok(sprintf("owner.json 에 proc_start=%.0f 기록(실측 %.0f · ISO %s)", ps_rec, st_self, as.character(o$proc_start_iso %||% "?"))) else
  ng("proc_start 미기록 — 다음 실행이 재사용을 못 가린다", paste(f$reason, if (is.null(o)) "NA" else paste(names(o), collapse = ",")))
g <- rf_claim_acquire(P, stale_hours = 999)                          # 방금 기록한 나 = 살아있는 owner
if (!isTRUE(g$ok) && identical(g$reason, "claimed")) ok("기록 직후 재획득 → 차단(기록·판정이 같은 계기를 쓴다)") else ng("자기 claim 을 스스로 회수", paste(g$reason, g$note))
unlink(P, recursive = TRUE, force = TRUE)

writeLines(""); writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_claim_pid_reuse","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
