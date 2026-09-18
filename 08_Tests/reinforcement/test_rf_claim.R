#==============================================================================
# test_rf_claim.R — claim 소유권 양방향 검사 (2026-08-30)
#
# 왜: 고아 claim 은 **정상 대기와 로그가 같다**(halt_claimed 반복). 그래서 조용히 6시간씩
#   무인 루프를 세운다(2026-08-30 실사고 2회 + 부팅 때 본 1.5h 공백). 회귀하면 또 조용하다.
#   양방향으로 건다 — ①살아있는 소유자는 지켜야 하고 ②죽은 소유자는 즉시 회수해야 한다.
#   한쪽만 맞으면 각각 "동시 배치 2개" 와 "6시간 봉쇄" 라는 반대 방향 사고가 된다.
#
# 부작용 없음: tempdir 안에서만 논다.
#==============================================================================
suppressMessages(library(jsonlite))
source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/ops/rf_claim.R"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }
P <- file.path(tempdir(), "rf_claim_test")
reset <- function() unlink(P, recursive = TRUE)
set_owner <- function(pid) writeLines(toJSON(list(pid = pid, started_at = "x", host = "y"),
                                             auto_unbox = TRUE), file.path(P, "owner.json"))

writeLines("=== 획득 (양성 대조) ===")
reset(); a <- rf_claim_acquire(P)
if (isTRUE(a$ok) && identical(a$reason, "acquired")) ok("빈 경로 → 획득") else ng("빈 경로 획득", a$reason)
if (file.exists(file.path(P, "owner.json"))) ok("owner.json 기록(후속 실행이 판단할 근거)") else
  ng("owner.json 부재", "고아 회수가 시간 폴백으로만 남는다")

writeLines("=== 차단 (살아있는 소유자를 지킨다) ===")
b <- rf_claim_acquire(P)
if (!isTRUE(b$ok) && identical(b$reason, "claimed")) ok("살아있는 소유자 → 차단") else
  ng("살아있는 claim 을 빼앗았다", paste(b$reason, "— 동시 배치 2개 위험"))

writeLines("=== 회수 (죽은 소유자는 즉시) ===")
set_owner(999999L)                                   # 존재할 수 없는 pid
c1 <- rf_claim_acquire(P, stale_hours = 999)         # 나이로는 절대 안 풀리는 조건
if (isTRUE(c1$ok) && grepl("사망", c1$note %||% "")) ok("죽은 소유자 → 나이 무관 즉시 회수") else
  ng("죽은 소유자 미회수", paste(c1$reason, c1$note))

writeLines("=== 시간 폴백 (owner.json 없는 구판 claim) ===")
reset(); dir.create(P, recursive = TRUE)             # owner 없이 남은 옛 claim
d1 <- rf_claim_acquire(P, stale_hours = 999)
if (!isTRUE(d1$ok)) ok("owner 없음 + 나이 미달 → 차단(보수적)") else ng("owner 없는 claim 을 즉시 빼앗았다")
reset(); dir.create(P, recursive = TRUE)
d2 <- rf_claim_acquire(P, stale_hours = -1)
if (isTRUE(d2$ok) && grepl("시간 폴백", d2$note %||% "")) ok("owner 없음 + 나이 초과 → 시간 폴백 회수") else
  ng("시간 폴백 미작동", paste(d2$reason, d2$note))

writeLines("=== 빈 고아 · 해제 표식 (2026-08-30 실측 경로) ===")
# unlink 이 owner.json 만 지우고 디렉터리를 남기는 경우가 실재한다. 그러면 후속 실행이
# 소유자를 못 읽어 6시간 폴백으로 떨어진다 — pid 수리만으로는 안 덮였다.
reset(); dir.create(P, recursive = TRUE)
Sys.setFileTime(P, Sys.time() - 300)                 # 5분 전 = 60초 유예 초과
e1 <- rf_claim_acquire(P, stale_hours = 999)
if (isTRUE(e1$ok) && grepl("빈 고아", e1$note %||% "")) {
  ok("owner 없는 빈 claim(60초 경과) → 회수")
} else ng("빈 고아 미회수", paste(e1$reason, e1$note))

reset(); dir.create(P, recursive = TRUE)             # 갓 만든 빈 claim = 경합 창
e2 <- rf_claim_acquire(P, stale_hours = 999)
if (!isTRUE(e2$ok)) {
  ok("갓 만든 빈 claim 은 지킨다(dir.create~owner 기록 사이 경합 보호)")
} else ng("경합 창 미보호", "밀리초 창에서 살아있는 claim 을 빼앗는다")

reset(); dir.create(P, recursive = TRUE)
writeLines(toJSON(list(released_at = "x", by_pid = 1L), auto_unbox = TRUE),
           file.path(P, "released.json"))
e3 <- rf_claim_acquire(P, stale_hours = 999)
if (isTRUE(e3$ok) && grepl("해제 표식", e3$note %||% "")) {
  ok("해제 표식 → 나이 무관 즉시 회수")
} else ng("해제 표식 무시", paste(e3$reason, e3$note))

# ★제자리 인수 — 디렉터리를 못 지우는 환경에서도 회수되는가(2026-08-30 halt_claim_race 실사고)
reset(); dir.create(P, recursive = TRUE)
Sys.setFileTime(P, Sys.time() - 300)
e4 <- rf_claim_acquire(P, stale_hours = 999)
o4 <- tryCatch(jsonlite::fromJSON(file.path(P, "owner.json"), simplifyVector = TRUE), error = function(z) NULL)
if (isTRUE(e4$ok) && dir.exists(P) && !is.null(o4) && identical(as.integer(o4$pid), as.integer(Sys.getpid()))) {
  ok("고아를 지우지 않고 제자리 인수(owner.json 이 소유권 정의)")
} else ng("제자리 인수 실패", paste(e4$reason, "| owner", if (is.null(o4)) "NA" else o4$pid))

writeLines("=== 해제 ===")
r <- rf_claim_release(P)
if (isTRUE(r$ok) && !dir.exists(P)) ok("해제 → 디렉터리 제거") else ng("해제 실패", r$reason)
r2 <- rf_claim_release(P)
if (isTRUE(r2$ok) && identical(r2$reason, "absent")) ok("이미 없으면 성공(멱등)") else ng("멱등성", r2$reason)

writeLines("=== 해제 판정 = 사실 (2026-09-19 · 디렉터리 실물 잠금) ===")
# 왜: 표식을 남긴 해제가 unlink_failed 로 찍혀 claim_release_failed 가 상시 오탐이 됐다(병렬 러너 09-13~17 19건 ·
#   B5 레인 09-18 23:53 정상 완주). 판정 = "다음 획득이 즉시 인수할 수 있는가"(디렉터리 부재 ∨ 표식 존재).
#   잠금은 흉내가 아니라 **실물**이다(08_Tests/lib/dir_hold.R — 다른 프로세스의 작업 디렉터리는 지워지지 않는다).
#   표식 쓰기 실패만 rf_claim_write_marker 를 덮어 주입한다 — 실물로 만들 길이 없다(ACL 변경은 하지 않는다).
HOLD <- file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), "08_Tests/lib/dir_hold.R")
H_READY <- paste0(P, "_hold.ready"); H_STOP <- paste0(P, "_hold.stop")
hold_start <- function(dir) {
  unlink(c(H_READY, H_STOP)); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(HOLD)) return(FALSE)
  system2("Rscript", c(shQuote(HOLD), shQuote(dir), shQuote(H_READY), shQuote(H_STOP), "120"),
          wait = FALSE, stdout = FALSE, stderr = FALSE)
  for (i in 1:200) {
    if (file.exists(H_READY) && length(suppressWarnings(tryCatch(readLines(H_READY, warn = FALSE), error = function(e) character(0))))) return(TRUE)
    Sys.sleep(0.05)
  }
  FALSE
}
hold_stop <- function(dir) {   # 붙잡은 프로세스를 내보내고 디렉터리가 실제로 지워질 때까지 기다린다
  writeLines("x", H_STOP)
  for (i in 1:100) { unlink(dir, recursive = TRUE); if (!dir.exists(dir)) break; Sys.sleep(0.1) }
  unlink(c(H_READY, H_STOP)); !dir.exists(dir)
}
has <- function(f) file.exists(file.path(P, f))
.orig_wm <- get0("rf_claim_write_marker", mode = "function")          # 부재(구판) = 주입 지점이 없다 → (c)(d) 는 FAIL 로 남긴다
if (is.null(.orig_wm)) ng("주입 지점 rf_claim_write_marker 부재 — 표식 쓰기 실패를 주입할 수 없다", "구판 rf_claim.R?")

# (a) 정상 — 잠금 없음: 지워지고 표식은 필요 없다
reset(); a0 <- rf_claim_acquire(P, stale_hours = 999); r0 <- rf_claim_release(P)
if (isTRUE(a0$ok) && isTRUE(r0$ok) && identical(r0$reason, "removed") && !dir.exists(P)) ok("(a) 잠금 없음 → ok · removed · 디렉터리 제거") else
  ng("(a) 정상 해제", paste(a0$reason, r0$reason, dir.exists(P)))

reset(); a5 <- rf_claim_acquire(P, stale_hours = 999)
if (!isTRUE(a5$ok) || !hold_start(P)) {
  ng("잠금 픽스처 준비 실패 — 이하 (b)(c) 판정 없음", paste(a5$reason, "| holder", HOLD))
} else {
  # (b) 실물 잠금 — unlink 이 owner.json 만 지우고 디렉터리를 남긴다 → 표식을 남기면 해제된 것이다
  r5 <- rf_claim_release(P)
  if (isTRUE(r5$ok) && identical(r5$reason, "marker_left")) ok("(b) 잠긴 디렉터리 + 표식 기록 → ok=TRUE · reason=marker_left") else
    ng("(b) 표식이 남았는데 실패로 판정", paste(r5$ok, r5$reason, r5$err %||% ""))
  if (dir.exists(P) && has("released.json") && !has("owner.json")) ok("(b) 사실: 디렉터리 존치 · released.json 있음 · owner.json 없음(09-18 23:53 실측 모양)") else
    ng("(b) 잠금 모양이 실사고와 다르다", sprintf("dir=%s marker=%s owner=%s", dir.exists(P), has("released.json"), has("owner.json")))
  a6 <- rf_claim_acquire(P, stale_hours = 999)                       # 나이로는 절대 안 풀리는 조건
  o6 <- tryCatch(jsonlite::fromJSON(file.path(P, "owner.json"), simplifyVector = TRUE), error = function(z) NULL)
  if (isTRUE(a6$ok) && grepl("해제 표식", a6$note %||% "") && !is.null(o6) && identical(as.integer(o6$pid), as.integer(Sys.getpid())) && !has("released.json"))
    ok("(b) 다음 획득이 표식을 보고 나이 무관 즉시 제자리 인수(표식 소비 · owner 교체)") else
    ng("(b) 표식을 남겼는데 다음 획득이 인수 못 한다", paste(a6$reason, a6$note))

  # (c) 음성 대조 — 표식 쓰기까지 막히면 진짜 실패다(디렉터리도 표식도 그대로)
  rf_claim_write_marker <- function(claim) "주입: 표식 쓰기 차단"
  r7 <- rf_claim_release(P)
  if (is.null(.orig_wm)) rm(rf_claim_write_marker) else rf_claim_write_marker <- .orig_wm
  if (!isTRUE(r7$ok) && identical(r7$reason, "unlink_failed") && identical(r7$err, "주입: 표식 쓰기 차단"))
    ok("(c) 잠금 + 표식 쓰기 실패 → ok=FALSE · unlink_failed · err 에 원인") else
    ng("(c) 진짜 실패를 못 잡는다", paste(r7$ok, r7$reason, r7$err %||% ""))
  if (dir.exists(P) && !has("released.json")) ok("(c) 사실: 디렉터리 존치 · 표식 없음") else
    ng("(c) 상태", sprintf("dir=%s marker=%s", dir.exists(P), has("released.json")))
  a8 <- rf_claim_acquire(P, stale_hours = 999)
  if (!isTRUE(a8$ok) && identical(a8$reason, "claimed"))
    ok("(c) 표식 없는 잔존 claim → 다음 획득 즉시 불가(claimed · 빈 고아 60초 유예) — 그래서 이것만 실패로 남긴다") else
    ng("(c) 표식 없는 claim 을 즉시 인수했다 — 실패/정보 구분의 전제가 틀렸다", paste(a8$reason, a8$note))

  # (d) 표식은 못 썼지만 그 사이 디렉터리가 사라졌다 → 해제됨(removed_late) — 사실 판정이지 쓰기 호출의 성패가 아니다
  rf_claim_write_marker <- function(claim) { hold_stop(claim); "주입: 표식 쓰기 실패 — 그 사이 디렉터리 소멸" }
  r9 <- rf_claim_release(P)
  if (is.null(.orig_wm)) rm(rf_claim_write_marker) else rf_claim_write_marker <- .orig_wm
  if (isTRUE(r9$ok) && identical(r9$reason, "removed_late") && !dir.exists(P)) ok("(d) 표식 실패 + 디렉터리 소멸 → ok · removed_late") else
    ng("(d) 사라진 디렉터리를 실패로 판정", paste(r9$ok, r9$reason, dir.exists(P)))
}
if (hold_stop(P)) ok("잠금 해제 · 픽스처 정리") else ng("잠금 픽스처가 안 풀린다", P)
if (identical(get0("rf_claim_write_marker", mode = "function"), .orig_wm)) ok("주입 원복(rf_claim_write_marker 정본)") else ng("주입이 남았다")

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_claim","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
