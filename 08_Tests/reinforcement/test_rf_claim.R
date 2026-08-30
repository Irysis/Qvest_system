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

writeLines("=== 해제 ===")
r <- rf_claim_release(P)
if (isTRUE(r$ok) && !dir.exists(P)) ok("해제 → 디렉터리 제거") else ng("해제 실패", r$reason)
r2 <- rf_claim_release(P)
if (isTRUE(r2$ok) && identical(r2$reason, "absent")) ok("이미 없으면 성공(멱등)") else ng("멱등성", r2$reason)

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
if (FAIL > 0L) quit(status = 1L)
