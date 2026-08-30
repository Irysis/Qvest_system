#==============================================================================
# rf_claim.R — 강화 무인 러너 claim(mutex) 획득·해제 (2026-08-30)
#
# 왜 생겼나 (실사고 2회 · 같은 날):
#   배치가 끝난 뒤 unlink(CLAIM) 이 **조용히 실패**해 빈 디렉터리가 남았다(15:37 · 16:28).
#   그러면 claim_stale_hours(6h) 가 지날 때까지 모든 tick 이 halt_claimed 로 물러난다 —
#   그런데 그 로그는 **정상 대기와 글자 그대로 같다**. 부팅 때 본 13:54~15:29 공백(1.5h)도
#   같은 사건이었다. 무인 루프의 전제가 6시간씩 조용히 무너지고 있었다.
#
# 설계: OS 와 싸우지 않는다. 지우는 데 실패할 수 있다고 **가정**하고, 후속 실행이
#   스스로 판단할 수 있게 만든다 —
#     ① 획득 시 claim 안에 owner.json(pid·시작시각)을 남긴다
#     ② 다음 실행은 그 pid 가 살아있는지 본다. 죽었으면 나이와 무관하게 즉시 회수한다
#     ③ 해제 실패는 조용히 넘기지 않는다(claim_release_failed)
#   시간 문턱(stale_hours)은 owner.json 을 못 읽는 구판 claim 을 위한 폴백으로 남는다.
#
# ★pid 를 모르면 "살아있다" 로 본다 — 살아있는 배치의 mutex 를 빼앗는 것이 반대 실수보다 나쁘다.
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

rf_claim_pid_alive <- function(pid) {
  pid <- suppressWarnings(as.integer(pid))
  if (!length(pid) || is.na(pid) || pid <= 0L) return(TRUE)          # 모르면 보수적
  if (identical(.Platform$OS.type, "windows")) {
    out <- tryCatch(suppressWarnings(system2("tasklist",
             c("/FI", shQuote(sprintf("PID eq %d", pid)), "/NH"), stdout = TRUE, stderr = FALSE)),
           error = function(e) NULL)
    if (is.null(out) || !length(out)) return(TRUE)                   # 조회 실패 = 판단 불가 = 보수적
    return(any(grepl(as.character(pid), paste(out, collapse = " "), fixed = TRUE)))
  }
  dir.exists(file.path("/proc", as.character(pid)))
}

#' @return list(ok, reason, age_h, owner_pid, note)
#'   reason: acquired | claimed | race
rf_claim_acquire <- function(claim, stale_hours = 6) {
  note <- ""
  if (dir.exists(claim)) {
    age_h <- suppressWarnings(as.numeric(
      difftime(Sys.time(), file.info(claim)$mtime, units = "hours")))
    op <- file.path(claim, "owner.json")
    pid <- if (file.exists(op)) {
      o <- tryCatch(jsonlite::fromJSON(op, simplifyVector = TRUE), error = function(e) NULL)
      suppressWarnings(as.integer(o$pid %||% NA))
    } else NA_integer_

    if (!is.na(pid) && !rf_claim_pid_alive(pid)) {
      unlink(claim, recursive = TRUE)
      note <- sprintf("owner pid %d 사망 — 나이(%s h) 무관 즉시 회수", pid,
                      if (is.finite(age_h)) sprintf("%.2f", age_h) else "?")
    } else if (is.finite(age_h) && age_h > stale_hours) {
      unlink(claim, recursive = TRUE)
      note <- sprintf("나이 %.2f h > 상한 %.2f h — 시간 폴백 회수", age_h, stale_hours)
    } else {
      return(list(ok = FALSE, reason = "claimed", age_h = age_h, owner_pid = pid, note = ""))
    }
  }
  if (!dir.create(claim, showWarnings = FALSE))
    return(list(ok = FALSE, reason = "race", age_h = NA_real_, owner_pid = NA_integer_, note = ""))
  tryCatch(writeLines(jsonlite::toJSON(list(
      pid = Sys.getpid(), started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      host = Sys.info()[["nodename"]]), auto_unbox = TRUE), file.path(claim, "owner.json")),
    error = function(e) NULL)   # owner 기록 실패는 치명 아님 — 시간 폴백이 남는다
  list(ok = TRUE, reason = "acquired", age_h = NA_real_, owner_pid = Sys.getpid(), note = note)
}

#' @return list(ok, reason)  — 실패해도 예외를 던지지 않는다(호출자가 로그로 남긴다)
rf_claim_release <- function(claim) {
  if (!dir.exists(claim)) return(list(ok = TRUE, reason = "absent"))
  unlink(claim, recursive = TRUE)
  if (!dir.exists(claim)) return(list(ok = TRUE, reason = "removed"))
  Sys.sleep(0.3); unlink(claim, recursive = TRUE)                     # 일시적 핸들 점유 1회 재시도
  if (!dir.exists(claim)) return(list(ok = TRUE, reason = "removed_retry"))
  # 마지막 수단: owner.json 만이라도 지워 후속 실행이 시간 폴백으로 떨어지게 한다.
  # (owner 가 남아 있으면 이 프로세스 pid 가 죽은 뒤 다음 실행이 즉시 회수하므로 그대로 둬도 된다)
  list(ok = FALSE, reason = "unlink_failed")
}
