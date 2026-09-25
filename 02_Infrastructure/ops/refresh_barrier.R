#==============================================================================
# refresh_barrier.R — 리프레시 배리어 R 래퍼 (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24)
#
# ★판정은 하지 않는다 — refresh_barrier.sh(단일 정본)를 부르고 그 한 줄을 파싱할 뿐이다. 이유 두 가지:
#   ① R 의 "/tmp" 는 C:\tmp 다(Git Bash 의 /tmp = %TEMP%). R 이 잠금 경로를 직접 풀면 **없는 잠금**을 본다.
#   ② 잠금 pid 는 MSYS pid 다. Sys.getpid()·tasklist 와 공간이 달라 R 에서는 대조할 수 없다.
#   그래서 bash 에 위임하고, 패리티(bash 가 본 경로 = R 이 넘긴 경로)는 rb_paths() 로 잰다.
#
# 상태(state): free · held · stale · self · error
#   진행 = free · stale · self    /    막음 = held · error (error = 판정기를 못 불렀다 → fail-closed)
#
# 함수: rb_status(root) · rb_wait(max_wait_s, poll_s, root) · rb_paths(root) · rb_cell_wait_s()
#==============================================================================

.RB_DEFAULT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"   # 러너들의 QM_ROOT 기본값과 같은 값
# ★셀 시작 대기 상한 = 600초. 근거:
#   · 대기를 틱 주기(Qvest_ReinforceAutoLoop PT8M = 480초)보다 길게 잡아도 얻는 것이 없다 — 대기 만료는
#     **미측정 종료**라 시도 예산(fail_count·attempts_used)을 안 태우고, 다음 틱이 그 칸을 그대로 재개한다.
#   · 긴 보유(daily_refresh 완주 ≈47분 · ensure_data_current.sh 주석 실측)는 틱 수준 배리어가 틱 전체를 건너뛰어 막는다.
#     셀 대기는 짧은 보유(아침 writer 잠금 · 리프레시 꼬리)만 덮으면 된다.
#   · 상한은 부모의 worker_timeout_sec(기본 5400초) 안에 대기 + 셀 실행이 들어가야 한다 — 넘으면 부모가 cell_missing 으로
#     실패 계상(fail_count +1)해 버린다. 600 + 셀 p95(≈15~30분) ≪ 5400.
#   덮어쓰기: env QVEST_RB_CELL_WAIT_S (검사·운영 조정용).
RB_CELL_WAIT_S_DEFAULT <- 600L
RB_POLL_S_DEFAULT      <- 20L    # ensure_data_current.sh 의 리프레시 대기 폴링 간격과 같은 값

.rb_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

rb_cell_wait_s <- function() {
  v <- suppressWarnings(as.integer(Sys.getenv("QVEST_RB_CELL_WAIT_S", "")))
  if (length(v) == 1L && is.finite(v) && v >= 0L) v else RB_CELL_WAIT_S_DEFAULT
}

# 판정기 경로 — 검사 주입 → 데이터 루트 → 코드 기본 루트. 샌드박스 ROOT(검사)는 .sh 를 안 뜨는 경우가 있어
#   기본 루트의 정본으로 떨어진다(판정 대상 잠금 경로는 env 로만 바뀐다 — 경로 해석과 무관).
rb_sh_path <- function(root = Sys.getenv("QM_ROOT", .RB_DEFAULT_ROOT)) {
  cands <- c(Sys.getenv("QVEST_RB_SH", ""),
             file.path(root, "02_Infrastructure/ops/refresh_barrier.sh"),
             file.path(.RB_DEFAULT_ROOT, "02_Infrastructure/ops/refresh_barrier.sh"))
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(cands)]
  if (length(hit)) hit[1] else ""
}

# Git Bash — WSL 의 System32\bash.exe 를 집으면 /proc·MSYS pid 공간이 전혀 다르다(배제).
rb_bash_path <- function() {
  cands <- c(Sys.getenv("QVEST_RB_BASH", ""),
             "C:/Program Files/Git/usr/bin/bash.exe", "C:/Program Files/Git/bin/bash.exe",
             unname(Sys.which("bash")))
  cands <- cands[nzchar(cands)]
  cands <- cands[file.exists(cands) & !grepl("system32", cands, ignore.case = TRUE)]
  if (length(cands)) cands[1] else ""
}

.rb_parse <- function(lines, tag = "RB") {
  l <- grep(paste0("^", tag, "\t"), lines, value = TRUE)
  if (!length(l)) return(NULL)
  kv <- strsplit(sub(paste0("^", tag, "\t"), "", l[length(l)]), "\t", fixed = TRUE)[[1]]
  stats::setNames(as.list(sub("^[^=]*=", "", kv)), sub("=.*$", "", kv))
}

.rb_call <- function(args, root) {
  sh <- rb_sh_path(root); bs <- rb_bash_path()
  if (!nzchar(sh)) return(list(err = "helper_missing"))
  if (!nzchar(bs)) return(list(err = "bash_missing"))
  out <- tryCatch(suppressWarnings(system2(bs, c("--noprofile", "--norc", shQuote(sh), args),
                                           stdout = TRUE, stderr = FALSE)),
                  error = function(e) structure(character(0), err = conditionMessage(e)))
  list(out = out, rc = as.integer(.rb_or(attr(out, "status"), 0L)), err = attr(out, "err"))
}

rb_status <- function(root = Sys.getenv("QM_ROOT", .RB_DEFAULT_ROOT)) {
  r <- .rb_call("status", root)
  p <- if (is.null(r$out)) NULL else .rb_parse(r$out)
  if (is.null(p) || is.null(p$state) || !p$state %in% c("free", "held", "stale", "self"))
    return(list(state = "error", reason = .rb_or(r$err, "no_status_line"), lock = "", path = "", pid = "",
                rc = .rb_or(r$rc, NA_integer_), blocking = TRUE))
  p$rc <- r$rc
  p$blocking <- identical(p$state, "held")
  p
}

# held(또는 error)인 동안 대기 — 상한은 벽시계. 반환: list(proceed, status, waited_s)
rb_wait <- function(max_wait_s = rb_cell_wait_s(), poll_s = RB_POLL_S_DEFAULT,
                    root = Sys.getenv("QM_ROOT", .RB_DEFAULT_ROOT)) {
  t0 <- Sys.time()
  repeat {
    s <- rb_status(root)
    w <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    if (!isTRUE(s$blocking)) return(list(proceed = TRUE, status = s, waited_s = round(w)))
    if (w >= max_wait_s) return(list(proceed = FALSE, status = s, waited_s = round(w)))
    Sys.sleep(max(1, min(poll_s, max_wait_s - w)))
  }
}

# bash 가 판정에 쓰는 잠금 경로(윈도 혼합형) — R 쪽 패리티 검사용
rb_paths <- function(root = Sys.getenv("QM_ROOT", .RB_DEFAULT_ROOT)) {
  r <- .rb_call("paths", root)
  p <- if (is.null(r$out)) NULL else .rb_parse(r$out, "RB_PATHS")
  if (is.null(p)) list(refresh = NA_character_, writer = NA_character_) else p
}

# 로그용 요약 — jlog(...) 인자로 펼친다
rb_fields <- function(s) list(state = .rb_or(s$state, ""), lock = .rb_or(s$lock, ""), pid = .rb_or(s$pid, ""),
                              reason = .rb_or(s$reason, ""), path = .rb_or(s$path, ""))
