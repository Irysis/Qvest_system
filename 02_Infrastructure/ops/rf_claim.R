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
#     ① 획득 시 claim 안에 owner.json(pid·시작시각·**프로세스 시작시각 proc_start**)을 남긴다
#     ② 다음 실행은 그 pid 가 살아있는지 본다. 죽었으면 나이와 무관하게 즉시 회수한다
#        ★pid 만으로는 부족하다 (2026-09-06 실사고): 절전으로 죽은 owner pid 12816 을 Windows 가 시스템 프로세스
#          Widgets 에 재사용해 alive=TRUE 로 읽혔고, 6시간 시간 폴백(claim_stale_reclaim … 18.53 h > 6.00 h)으로만
#          풀렸다. 절전이 6시간보다 짧았다면 루프가 최대 6시간 halt_claimed 로 섰다. 그래서 pid 가 살아있어도
#          그 프로세스의 **시작시각이 기록과 다르면 죽은 owner** 로 본다(pid 재사용 = 남의 프로세스).
#          기록에 proc_start 가 없으면(구판 claim) 종전 규칙 그대로 · 시작시각 조회 실패 = 모른다 = 살아있다.
#     ③ 해제 실패는 조용히 넘기지 않는다(claim_release_failed)
#   시간 문턱(stale_hours)은 owner.json 을 못 읽는 구판 claim 을 위한 폴백으로 남는다.
#
# ★pid 를 모르면 "살아있다" 로 본다 — 살아있는 배치의 mutex 를 빼앗는 것이 반대 실수보다 나쁘다.
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' 프로세스 **시작시각**(epoch 초). 모르면 NA — 호출자는 NA 를 "판단 불가 = 살아있다" 로 본다.
#'   Windows: CIM Win32_Process.CreationDate — Get-Process.StartTime 은 SYSTEM 프로세스에 접근 거부(실측 pid 4)라
#'   재사용 상대가 시스템 프로세스면 바로 판단 불가로 떨어진다. CIM 은 권한 없이도 전 프로세스를 준다(실측 2026-09-07).
#'   POSIX: /proc/<pid>/stat 22번 필드(부팅 후 틱) + /proc/stat btime · 폴백 ps -o etimes=.
rf_claim_proc_start <- function(pid) {
  pid <- suppressWarnings(as.integer(pid))
  if (!length(pid) || is.na(pid) || pid <= 0L) return(NA_real_)
  if (identical(.Platform$OS.type, "windows")) {
    # 안쪽은 작은따옴표만 — shQuote(큰따옴표) 와 섞이지 않는다. 출력 = 정수 1줄 또는 빈 출력(없는 pid).
    cmd <- sprintf("$p = Get-CimInstance Win32_Process -Filter 'ProcessId=%d'; if ($p) { [DateTimeOffset]::new($p.CreationDate).ToUnixTimeSeconds() }", pid)
    out <- tryCatch(suppressWarnings(system2("powershell", c("-NoProfile", "-NonInteractive", "-Command", shQuote(cmd)),
                                             stdout = TRUE, stderr = FALSE)), error = function(e) NULL)
    v <- suppressWarnings(as.numeric(trimws(as.character(out %||% character(0)))))
    v <- v[is.finite(v)]
    return(if (length(v)) v[1] else NA_real_)
  }
  st <- tryCatch(readLines(file.path("/proc", as.character(pid), "stat"), warn = FALSE), error = function(e) NULL)
  if (length(st)) {
    f <- strsplit(sub("^.*\\) ", "", st[1]), " ", fixed = TRUE)[[1]]   # comm 에 공백이 올 수 있어 마지막 ')' 뒤에서 자른다
    ticks <- suppressWarnings(as.numeric(f[20]))                        # 22번 필드 starttime (pid·comm 제거 후 20번째)
    bt <- tryCatch({ l <- readLines("/proc/stat", warn = FALSE)
                     as.numeric(sub("^btime ", "", grep("^btime ", l, value = TRUE)[1])) }, error = function(e) NA_real_)
    hz <- suppressWarnings(as.numeric(tryCatch(system2("getconf", "CLK_TCK", stdout = TRUE, stderr = FALSE),
                                               error = function(e) NA_character_)))
    if (!length(hz) || !is.finite(hz[1])) hz <- 100
    if (is.finite(ticks) && is.finite(bt)) return(bt + ticks / hz[1])
  }
  et <- tryCatch(suppressWarnings(system2("ps", c("-o", "etimes=", "-p", as.character(pid)), stdout = TRUE, stderr = FALSE)),
                 error = function(e) NULL)
  et <- suppressWarnings(as.numeric(trimws(as.character(et %||% character(0)))))
  if (length(et) && is.finite(et[1])) return(as.numeric(Sys.time()) - et[1])
  NA_real_
}

#' 기록된 시작시각(recorded)과 현재 프로세스의 시작시각(current)이 같은 프로세스를 가리키는가.
#'   ★양쪽 어느 하나라도 모르면 TRUE — 구판 claim(기록 없음)과 조회 실패는 종전 규칙(pid 생존만)으로 떨어진다.
rf_claim_start_matches <- function(recorded, current, tol_sec = 5) {
  r <- suppressWarnings(as.numeric(recorded %||% NA_real_))
  cu <- suppressWarnings(as.numeric(current %||% NA_real_))
  if (!length(r) || !is.finite(r[1])) return(TRUE)
  if (!length(cu) || !is.finite(cu[1])) return(TRUE)
  abs(cu[1] - r[1]) <= tol_sec
}

#' @param proc_start owner.json 의 기록 시작시각(epoch 초). NULL/NA 면 종전 규칙(pid 생존만) — 구판 호환.
#'   pid 가 살아있어도 그 프로세스의 시작시각이 기록과 tol_sec 넘게 다르면 **남의 프로세스** = FALSE (pid 재사용).
rf_claim_pid_alive <- function(pid, proc_start = NULL, tol_sec = 5) {
  pid <- suppressWarnings(as.integer(pid))
  if (!length(pid) || is.na(pid) || pid <= 0L) return(TRUE)          # 모르면 보수적
  raw <- if (identical(.Platform$OS.type, "windows")) {
    out <- tryCatch(suppressWarnings(system2("tasklist",
             c("/FI", shQuote(sprintf("PID eq %d", pid)), "/NH"), stdout = TRUE, stderr = FALSE)),
           error = function(e) NULL)
    if (is.null(out) || !length(out)) TRUE                            # 조회 실패 = 판단 불가 = 보수적
    else any(grepl(as.character(pid), paste(out, collapse = " "), fixed = TRUE))
  } else dir.exists(file.path("/proc", as.character(pid)))
  if (!isTRUE(raw)) return(FALSE)
  ps <- suppressWarnings(as.numeric(proc_start %||% NA_real_))
  if (!length(ps) || !is.finite(ps[1])) return(TRUE)                 # 기록 없음(구판 claim) — 종전 규칙
  rf_claim_start_matches(ps[1], rf_claim_proc_start(pid), tol_sec)
}

#' owner.json 레코드 — pid·시각·host + proc_start(조회되면). 조회 실패면 필드를 **안 쓴다**(다음 실행이 구판 규칙으로 읽는다).
.rf_claim_owner_record <- function() {
  rec <- list(pid = Sys.getpid(), started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
              host = Sys.info()[["nodename"]])
  ps <- rf_claim_proc_start(Sys.getpid())
  if (length(ps) == 1L && is.finite(ps)) {
    rec$proc_start <- ps
    rec$proc_start_iso <- format(as.POSIXct(ps, origin = "1970-01-01", tz = ""), "%Y-%m-%dT%H:%M:%S%z")
  }
  rec
}

#' @return list(ok, reason, age_h, owner_pid, note)
#'   reason: acquired | claimed | race
rf_claim_acquire <- function(claim, stale_hours = 6) {
  note <- ""
  .take <- function(why) {
    # ★제자리 인수 — 디렉터리를 지우지 않는다. 2026-08-30 실측: 고아를 회수하려고 unlink 한 뒤
    #   dir.create 가 실패해(같은 지울 수 없는 디렉터리) halt_claim_race 로 튕겼다. 삭제에 성공해야만
    #   회수되는 설계는 삭제가 실패하는 환경에서 자가회수를 통째로 무력화한다.
    #   소유권의 정의를 "디렉터리 존재" 에서 **owner.json 내용**으로 옮긴다.
    unlink(file.path(claim, "released.json"))
    ok <- tryCatch({ writeLines(jsonlite::toJSON(.rf_claim_owner_record(), auto_unbox = TRUE),
                                file.path(claim, "owner.json")); TRUE },
      error = function(e) FALSE)
    if (!ok) return(list(ok = FALSE, reason = "owner_write_failed", age_h = NA_real_,
                         owner_pid = NA_integer_, note = ""))
    # 경합 확인 — 쓴 직후 되읽어 내 pid 가 맞는지 본다(둘이 동시에 고아 판정했을 수 있다)
    o2 <- tryCatch(jsonlite::fromJSON(file.path(claim, "owner.json"), simplifyVector = TRUE),
                   error = function(e) NULL)
    if (is.null(o2) || !identical(as.integer(o2$pid %||% NA), as.integer(Sys.getpid())))
      return(list(ok = FALSE, reason = "race", age_h = NA_real_, owner_pid = NA_integer_, note = ""))
    list(ok = TRUE, reason = "acquired", age_h = NA_real_, owner_pid = Sys.getpid(), note = why)
  }

  if (dir.exists(claim)) {
    age_h <- suppressWarnings(as.numeric(
      difftime(Sys.time(), file.info(claim)$mtime, units = "hours")))
    op <- file.path(claim, "owner.json")
    rp <- file.path(claim, "released.json")
    o <- if (file.exists(op)) tryCatch(jsonlite::fromJSON(op, simplifyVector = TRUE), error = function(e) NULL) else NULL
    pid <- suppressWarnings(as.integer(o$pid %||% NA))
    pst <- suppressWarnings(as.numeric(o$proc_start %||% NA))       # 구판 owner.json 엔 없다 → NA → 종전 규칙
    .cur <- NA_real_
    # pid 는 살아있는데 시작시각이 기록과 다른가 = 남의 프로세스(pid 재사용). 조회는 이 분기에서만(지연).
    .reused <- function() { .cur <<- rf_claim_proc_start(pid); !rf_claim_start_matches(pst, .cur) }

    if (file.exists(rp)) {
      return(.take("해제 표식(released.json) 존재 — 제자리 인수"))
    } else if (is.na(pid) && is.finite(age_h) && age_h * 3600 > 60) {
      # 빈 고아: unlink 이 owner.json 만 지우고 디렉터리를 남긴 경우. 60초 유예는
      # dir.create 와 owner 기록 사이의 밀리초 경합 창을 덮는다.
      return(.take(sprintf("owner.json 부재 + %.0f초 경과 — 빈 고아 제자리 인수", age_h * 3600)))
    } else if (!is.na(pid) && !rf_claim_pid_alive(pid)) {
      return(.take(sprintf("owner pid %d 사망 — 나이(%s h) 무관 제자리 인수", pid,
                           if (is.finite(age_h)) sprintf("%.2f", age_h) else "?")))
    } else if (!is.na(pid) && is.finite(pst) && .reused()) {
      # 2026-09-06 Widgets 재사용 사고 — pid 는 있지만 그 프로세스는 owner 가 아니다. 나이와 무관하게 즉시 회수.
      return(.take(sprintf("owner pid %d 재사용 감지(기록 proc_start %.0f ≠ 현재 프로세스 %.0f) — 나이(%s h) 무관 제자리 인수",
                           pid, pst, .cur, if (is.finite(age_h)) sprintf("%.2f", age_h) else "?")))
    } else if (is.finite(age_h) && age_h > stale_hours) {
      return(.take(sprintf("나이 %.2f h > 상한 %.2f h — 시간 폴백 인수", age_h, stale_hours)))
    } else {
      return(list(ok = FALSE, reason = "claimed", age_h = age_h, owner_pid = pid, note = ""))
    }
  }
  if (!dir.create(claim, showWarnings = FALSE))
    return(list(ok = FALSE, reason = "race", age_h = NA_real_, owner_pid = NA_integer_, note = ""))
  tryCatch(writeLines(jsonlite::toJSON(.rf_claim_owner_record(), auto_unbox = TRUE), file.path(claim, "owner.json")),
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
  # ★디렉터리를 못 지웠다면 **해제 표식**을 남긴다. unlink 이 owner.json 만 지우고
  #   디렉터리를 남기는 경우가 실재하고(2026-08-30), 그러면 후속 실행이 소유자를 못 읽어
  #   6시간 폴백으로 떨어진다. 표식이 있으면 다음 실행이 즉시 회수한다.
  tryCatch(writeLines(jsonlite::toJSON(list(
      released_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), by_pid = Sys.getpid()),
      auto_unbox = TRUE), file.path(claim, "released.json")), error = function(e) NULL)
  list(ok = FALSE, reason = "unlink_failed")
}
