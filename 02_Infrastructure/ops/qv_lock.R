#==============================================================================
# qv_lock.R — 쓰기 잠금(mkdir + 소유자 pid + stale 판정 + 시간 제한)의 R 판 · GPU 임대 R API (2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020)
#
# 정본 = qv_lock.py 머리 주석(왜 · 판정 순서 · 위치 규칙 · 임대 의미). 이 파일은 같은 디스크 형식을 R 에서 읽고 쓴다 —
#   R 이 잡은 잠금을 파이썬이 '살아 있음'으로, 파이썬이 잡은 잠금을 R 이 '살아 있음'으로 본다(검사 08_Tests/ops/test_qv_lock_cross.R).
#   잠금은 R 본판(원장 writer 의 경로 · 파이썬 기동 비용 없음) · GPU 임대는 파이썬 CLI 위임(의미 한 벌 — 서명 고정):
#     gpu_lease_acquire(holder, purpose, cap_hours = NULL, holder_pid = NULL) → list(ok, reason, lease, note)
#     gpu_lease_release(holder) → list(ok, reason)
#     gpu_lease_status() → list(state = free|held|expired|holder_dead|unreadable, holder, purpose, started_at, cap_hours, expires_at, remaining_h, ...)
# 쓰기 원칙: 난수 상태(.Random.seed)를 건드리지 않는다(토큰 = pid · 시각 · 계수) · 한글 경로를 깨는 경로 정규화 함수를 쓰지 않는다(훅).
# 생존 판정: ps 패키지(ps_handle · ps_is_running · ps_create_time — Windows GetProcessTimes 와 같은 값) · 없으면 tasklist(시작 시각 비교 생략).
#   pid 를 판독할 수 없으면 살아 있다고 본다(rf_claim.R 원칙).
# 사용:
#   source(file.path(<코드 루트>, "02_Infrastructure/ops/qv_lock.R"))
#   h <- qv_lock_acquire(qv_lock_dir_for(target = path)); on.exit(qv_lock_release(h), add = TRUE)
#   ... 읽기 → 고치기 → qv_lock_assert_mine(h, "쓰기") → 원자적 교체
#   또는 qv_with_lock(target = path, { ... })
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))

QV_LOCK_SCHEMA <- "qv_lock_v1"
QV_DEFAULT_WAIT_S <- 60          # qv_lock.py 와 같은 값(근거는 그 파일)
QV_DEFAULT_STALE_S <- 600
QV_NO_OWNER_GRACE_S <- 30
QV_RECLAIM_STALE_S <- 60
QV_START_TOL_S <- 2

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.qv_env <- function() {
  e <- getOption("qv_lock.env")
  if (!is.environment(e)) { e <- new.env(parent = emptyenv()); e$held <- list(); e$ctr <- 0L; options(qv_lock.env = e) }
  e
}

.qv_code_root <- function() {
  for (k in c("QVEST_CODE_ROOT", "QM_ROOT", "CLAUDE_PROJECT_DIR")) {
    v <- gsub("\\\\", "/", Sys.getenv(k, ""))
    if (nzchar(v) && file.exists(file.path(v, "02_Infrastructure/ops/qv_lock.py"))) return(sub("/+$", "", v))
  }
  w <- gsub("\\\\", "/", getwd())
  if (file.exists(file.path(w, "02_Infrastructure/ops/qv_lock.py"))) return(w)
  NA_character_
}

.qv_now_iso <- function(t = Sys.time()) format(t, "%Y-%m-%dT%H:%M:%S%z")

.qv_token <- function() {
  e <- .qv_env(); e$ctr <- e$ctr + 1L
  sprintf("%08x%08x%04x", as.integer(Sys.getpid()) %% .Machine$integer.max,
          as.integer((as.numeric(Sys.time()) * 1e6) %% .Machine$integer.max), e$ctr %% 65536L)
}

.qv_has_ps <- function() isTRUE(requireNamespace("ps", quietly = TRUE))

#' pid 생존 — TRUE/FALSE. 판독 불가 = TRUE.
qv_pid_alive <- function(pid) {
  pid <- suppressWarnings(as.integer(pid))
  if (!length(pid) || is.na(pid[1]) || pid[1] <= 0L) return(TRUE)
  pid <- pid[1]
  if (.qv_has_ps()) {
    h <- tryCatch(ps::ps_handle(pid), error = function(e) e)
    if (inherits(h, "no_such_process")) return(FALSE)
    if (inherits(h, "error")) return(TRUE)                         # 권한 거부(os_error 5) 등 = 있다
    r <- tryCatch(ps::ps_is_running(h), error = function(e) NA)
    return(!identical(r, FALSE))
  }
  if (identical(.Platform$OS.type, "windows")) {
    out <- tryCatch(suppressWarnings(system2("tasklist", c("/FI", shQuote(sprintf("PID eq %d", pid)), "/NH"),
                                             stdout = TRUE, stderr = FALSE)), error = function(e) NULL)
    if (is.null(out) || !length(out)) return(TRUE)
    return(any(grepl(sprintf("\\b%d\\b", pid), out)))
  }
  dir.exists(file.path("/proc", pid))
}

#' 프로세스 시작 시각(epoch 초) — 모르면 NA
qv_proc_start <- function(pid) {
  pid <- suppressWarnings(as.integer(pid))
  if (!length(pid) || is.na(pid[1]) || pid[1] <= 0L || !.qv_has_ps()) return(NA_real_)
  h <- tryCatch(ps::ps_handle(pid[1]), error = function(e) NULL)
  if (is.null(h)) return(NA_real_)
  v <- tryCatch(as.numeric(ps::ps_create_time(h)), error = function(e) NA_real_)
  if (length(v) == 1L && is.finite(v)) v else NA_real_
}

#' 생존 + 시작 시각 일치 — list(alive, why)
qv_owner_alive <- function(pid, recorded_start = NULL) {
  if (!qv_pid_alive(pid)) return(list(alive = FALSE, why = "dead_owner"))
  rs <- suppressWarnings(as.numeric(recorded_start %||% NA_real_))
  if (!length(rs) || !is.finite(rs[1])) return(list(alive = TRUE, why = "alive"))
  cur <- qv_proc_start(pid)
  if (is.finite(cur) && abs(cur - rs[1]) > QV_START_TOL_S) return(list(alive = FALSE, why = "pid_reused"))
  list(alive = TRUE, why = "alive")
}

#' 잠금 디렉터리 — qv_lock.py lock_dir_for 와 같은 규칙(경로 문자열만)
qv_lock_dir_for <- function(target = NULL, name = NULL, root = NULL) {
  base_env <- Sys.getenv("QVEST_LOCK_DIR", "")
  if (!is.null(name) && nzchar(name)) {
    base <- if (nzchar(base_env)) base_env else file.path(root %||% (.qv_code_root() %||% getwd()), ".cache", "qv_locks")
    return(file.path(base, paste0(name, ".qvlock")))
  }
  if (is.null(target) || !nzchar(target)) stop("[qv_lock] qv_lock_dir_for: target 또는 name 필요")
  t <- gsub("\\\\", "/", target)
  if (!grepl("^([A-Za-z]:|/)", t)) t <- file.path(gsub("\\\\", "/", getwd()), t)
  if (nzchar(base_env)) return(file.path(base_env, paste0(basename(t), ".qvlock")))
  d <- dirname(t)
  if (identical(tolower(basename(d)), "06_registry"))
    return(file.path(dirname(d), ".cache", "registry_locks", paste0(basename(t), ".qvlock")))
  file.path(d, ".qvlocks", paste0(basename(t), ".qvlock"))
}

.qv_read_owner <- function(lockdir) {
  p <- file.path(lockdir, "owner.json")
  if (!file.exists(p)) return(NULL)
  o <- tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.list(o) && length(o$token) == 1L && nzchar(as.character(o$token))) o else NULL
}

.qv_mtime <- function(p) { m <- suppressWarnings(file.info(p)$mtime); if (length(m) && !is.na(m)) as.numeric(m) else as.numeric(Sys.time()) }

#' 판정 — list(state = free|held|stale, why, age_s, owner)
qv_lock_state <- function(lockdir, stale_s = QV_DEFAULT_STALE_S, now = as.numeric(Sys.time())) {
  if (!dir.exists(lockdir)) return(list(state = "free", why = "absent"))
  if (file.exists(file.path(lockdir, "released.json"))) return(list(state = "stale", why = "released", owner = .qv_read_owner(lockdir)))
  o <- .qv_read_owner(lockdir)
  if (is.null(o)) {
    age <- now - .qv_mtime(lockdir)
    return(if (age > QV_NO_OWNER_GRACE_S) list(state = "stale", why = "no_owner", age_s = age, owner = NULL)
           else list(state = "held", why = "no_owner_yet", age_s = age, owner = NULL))
  }
  ae <- suppressWarnings(as.numeric(o$acquired_epoch %||% NA))
  age <- if (length(ae) && is.finite(ae[1])) now - ae[1] else now - .qv_mtime(lockdir)
  al <- qv_owner_alive(o$pid, o$proc_start)
  if (!isTRUE(al$alive)) return(list(state = "stale", why = al$why, age_s = age, owner = o))
  if (is.finite(stale_s) && stale_s > 0 && age > stale_s) return(list(state = "stale", why = "too_old", age_s = age, owner = o))
  list(state = "held", why = "alive", age_s = age, owner = o)
}

.qv_reclaim <- function(lockdir, judged) {
  rc <- paste0(lockdir, ".reclaim")
  if (!isTRUE(suppressWarnings(dir.create(rc, showWarnings = FALSE)))) {
    if (dir.exists(rc) && as.numeric(Sys.time()) - .qv_mtime(rc) > QV_RECLAIM_STALE_S) unlink(rc, recursive = TRUE, force = TRUE)
    return(FALSE)
  }
  on.exit(unlink(rc, recursive = TRUE, force = TRUE), add = TRUE)
  if (!dir.exists(lockdir)) return(TRUE)
  cur <- .qv_read_owner(lockdir)
  jt <- judged$owner$token %||% NULL
  ct <- cur$token %||% NULL
  if (!identical(as.character(ct %||% ""), as.character(jt %||% ""))) return(FALSE)
  tomb <- sprintf("%s.dead.%d.%s", lockdir, Sys.getpid(), substr(.qv_token(), 9, 16))
  ok <- FALSE
  for (k in 1:5) {
    if (!dir.exists(lockdir)) return(TRUE)
    if (isTRUE(suppressWarnings(file.rename(lockdir, tomb)))) { ok <- TRUE; break }
    Sys.sleep(0.05 * k)
  }
  if (!ok) return(FALSE)
  unlink(tomb, recursive = TRUE, force = TRUE)
  TRUE
}

.qv_key <- function(lockdir) tolower(gsub("\\\\", "/", lockdir))

.qv_write_owner <- function(lockdir, rec) {
  p <- file.path(lockdir, "owner.json"); tmp <- sprintf("%s/.owner.json.%d.tmp", lockdir, Sys.getpid())
  writeLines(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null", digits = NA), tmp, useBytes = TRUE)
  if (!isTRUE(suppressWarnings(file.rename(tmp, p)))) { unlink(tmp); stop("[qv_lock] owner.json 기록 실패: ", p) }
}

#' 획득 — 시간 안에 못 잡으면 stop(class qv_lock_timeout). 같은 프로세스 재진입 = 깊이 +1.
qv_lock_acquire <- function(lockdir, wait_s = QV_DEFAULT_WAIT_S, stale_s = QV_DEFAULT_STALE_S, purpose = "") {
  e <- .qv_env(); k <- .qv_key(lockdir)
  h0 <- e$held[[k]]
  if (!is.null(h0)) {
    if (isTRUE(qv_lock_is_mine(h0))) { h0$depth <- h0$depth + 1L; e$held[[k]] <- h0; return(invisible(h0)) }
    e$held[[k]] <- NULL
  }
  dir.create(dirname(lockdir), recursive = TRUE, showWarnings = FALSE)
  deadline <- as.numeric(Sys.time()) + max(0, as.numeric(wait_s))
  delay <- 0.05
  repeat {
    if (isTRUE(suppressWarnings(dir.create(lockdir, showWarnings = FALSE)))) break
    st <- qv_lock_state(lockdir, stale_s)
    if (identical(st$state, "free")) next
    if (identical(st$state, "stale") && isTRUE(.qv_reclaim(lockdir, st))) next
    if (as.numeric(Sys.time()) >= deadline)
      stop(structure(class = c("qv_lock_timeout", "error", "condition"), list(
        message = sprintf("[qv_lock] 잠금 획득 실패(%.0f초 대기): %s · 상태 %s/%s · 소유 pid %s · 용도 %s", as.numeric(wait_s), lockdir,
                          st$state, st$why, as.character(st$owner$pid %||% "?"), as.character(st$owner$purpose %||% "?")), call = NULL)))
    Sys.sleep(delay); delay <- min(delay * 1.6, 0.5)
  }
  pid <- Sys.getpid()
  ps0 <- qv_proc_start(pid)
  rec <- list(schema = QV_LOCK_SCHEMA, pid = pid, proc_start = if (is.finite(ps0)) ps0 else NULL, token = .qv_token(),
              host = unname(Sys.info()[["nodename"]]), acquired_at = .qv_now_iso(), acquired_epoch = as.numeric(Sys.time()),
              purpose = as.character(purpose %||% ""), lang = "R")
  tryCatch(.qv_write_owner(lockdir, rec), error = function(err) { unlink(lockdir, recursive = TRUE, force = TRUE); stop(err) })
  h <- list(lockdir = lockdir, token = rec$token, depth = 1L, purpose = rec$purpose)
  e$held[[k]] <- h
  invisible(h)
}

qv_lock_is_mine <- function(h) {
  if (is.null(h) || is.null(h$lockdir)) return(FALSE)
  o <- .qv_read_owner(h$lockdir)
  !is.null(o) && identical(as.character(o$token), as.character(h$token)) && !file.exists(file.path(h$lockdir, "released.json"))
}

qv_lock_assert_mine <- function(h, what = "쓰기") {
  if (!isTRUE(qv_lock_is_mine(h)))
    stop(structure(class = c("qv_lock_lost", "error", "condition"), list(
      message = sprintf("[qv_lock] 잠금을 잃었다(%s) — %s 를 하지 않는다: %s", h$purpose %||% "?", what, h$lockdir %||% "?"), call = NULL)))
  invisible(TRUE)
}

#' 해제 — "released" | "nested" | "lost" | "marker_left"
qv_lock_release <- function(h) {
  if (is.null(h) || is.null(h$lockdir)) return(invisible("lost"))
  e <- .qv_env(); k <- .qv_key(h$lockdir)
  cur <- e$held[[k]]
  if (!is.null(cur) && identical(cur$token, h$token) && cur$depth > 1L) { cur$depth <- cur$depth - 1L; e$held[[k]] <- cur; return(invisible("nested")) }
  e$held[[k]] <- NULL
  o <- .qv_read_owner(h$lockdir)
  if (is.null(o) || !identical(as.character(o$token), as.character(h$token))) return(invisible("lost"))
  tomb <- sprintf("%s.dead.%d.%s", h$lockdir, Sys.getpid(), substr(.qv_token(), 9, 16))
  for (i in 1:5) {
    if (!dir.exists(h$lockdir)) return(invisible("lost"))
    if (isTRUE(suppressWarnings(file.rename(h$lockdir, tomb)))) { unlink(tomb, recursive = TRUE, force = TRUE); return(invisible("released")) }
    Sys.sleep(0.05 * i)
  }
  ok <- tryCatch({ writeLines(toJSON(list(released_at = .qv_now_iso(), by_pid = Sys.getpid(), token = h$token), auto_unbox = TRUE),
                              file.path(h$lockdir, "released.json")); TRUE }, error = function(err) FALSE)
  invisible(if (ok) "marker_left" else "lost")
}

#' 임계구역 — 예외가 나도 놓는다(함수 안 on.exit)
qv_with_lock <- function(target = NULL, expr, name = NULL, wait_s = QV_DEFAULT_WAIT_S, stale_s = QV_DEFAULT_STALE_S, purpose = "") {
  h <- qv_lock_acquire(qv_lock_dir_for(target = target, name = name), wait_s = wait_s, stale_s = stale_s,
                       purpose = if (nzchar(purpose)) purpose else basename(target %||% name %||% "lock"))
  on.exit(qv_lock_release(h), add = TRUE)
  force(expr)
}

# ── GPU 임대 — 파이썬 CLI 위임(의미 한 벌) ─────────────────────────────────────
.qv_py <- function() {
  v <- Sys.getenv("QVEST_PY", "")
  if (nzchar(v) && file.exists(v)) return(v)
  r <- .qv_code_root()
  cand <- if (!is.na(r)) file.path(r, ".venv_qvest_ml/Scripts/python.exe") else ""
  if (nzchar(cand) && file.exists(cand)) return(cand)
  for (m in c("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe")) if (file.exists(m)) return(m)
  "python"
}

.qv_lease_cli <- function(args) {
  r <- .qv_code_root()
  if (is.na(r)) stop("[qv_lock] 코드 루트(QM_ROOT)에서 qv_lock.py 를 찾지 못했다 — GPU 임대를 판정하지 않는다")
  out <- tryCatch(suppressWarnings(system2(.qv_py(), c("-X", "utf8", shQuote(file.path(r, "02_Infrastructure/ops/qv_lock.py")), "lease", args, "--json"),
                                           stdout = TRUE, stderr = FALSE)), error = function(e) character(0))
  out <- out[nzchar(trimws(out))]
  if (!length(out)) stop("[qv_lock] GPU 임대 CLI 무응답")
  fromJSON(out[length(out)], simplifyVector = TRUE)
}

gpu_lease_acquire <- function(holder, purpose, cap_hours = NULL, holder_pid = NULL) {
  a <- c("acquire", "--holder", shQuote(holder), "--purpose", shQuote(purpose))
  if (!is.null(cap_hours)) a <- c(a, "--cap-hours", format(as.numeric(cap_hours), scientific = FALSE))
  if (!is.null(holder_pid)) a <- c(a, "--holder-pid", as.character(as.integer(holder_pid)))
  .qv_lease_cli(a)
}
gpu_lease_release <- function(holder) .qv_lease_cli(c("release", "--holder", shQuote(holder)))
gpu_lease_status  <- function() .qv_lease_cli("status")
