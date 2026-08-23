#!/usr/bin/env Rscript
#==============================================================================
# refresh_screen_queues.R — 스크린 큐 빌더 3종의 단일 진입점 (v9.1 §7-S2c)
#
# 왜 있나: 큐 빌더 3종이 전부 수동 실행이라 lean 라운드가 만든 라벨이 큐 어디에도
#   도달하지 않는다(2026-08-23 실측: 당일 라벨 3건 · 큐 등재 0건). 라벨을 *생산*만 하고
#   소비자가 0인 배선은 이 저장소의 반복 실패 계통이라 진입점을 하나로 묶는다.
#
# ★순서가 하드 요건 — overlay → standalone → auto_spawn.
#   auto_spawn_queue.R:97-98 이 overlay 큐를 **입력으로 읽고 부재 시 stop** 한다
#   ("빈 결과 = 합격 아님"). 순서를 바꾸면 auto_spawn 이 죽거나 낡은 입력으로 돈다.
#
# 격리: 세 빌더는 각각 CLI 스크립트(자체 main-guard·전역 오염·setwd)라 **별도 Rscript
#   프로세스**로 돌린다. source() 로 한 세션에 합치면 %||%/QUEUE_PATH/root 헬퍼가 서로를
#   덮어쓴다. 각 호출은 독립 tryCatch — 하나가 실패해도 나머지는 진행하고, 실패는
#   stderr + .cache/screen_queue_refresh.log 양쪽에 남긴다(침묵 실패 금지).
#
# 뮤텍스: .cache/screen_queue_refresh.lock 을 dir.create 원자 선점(cleaner_claim.R:83-93 ·
#   run_alpha_search.R:.with_alpha_search_tg_lock 전례). stale 15분 회수.
#   ★한계 고지: overlay_candidate_queue.R:253 은 비원자적 write_json 이다. 이 뮤텍스는
#   *러너 경로*의 동시 실행만 막고, 사람이 빌더를 직접 돌리면 여전히 노출된다
#   (tmp→rename 적용은 후속 태스크 — v9.1 위험표 R10).
#
# ★부팅·모닝브리핑에 넣지 말 것: bootstrap.sh:993 이 "상태라인은 읽기 전용 — 큐 build 는
#   여기서 하지 않는다(8j 규약)"를 선언한다. 호출자는 무인 러너와 러너 완주 시점뿐이다.
#
# Usage:
#   Rscript 02_Infrastructure/ops/refresh_screen_queues.R                  # 전량 재생성
#   Rscript 02_Infrastructure/ops/refresh_screen_queues.R --if-stale 10    # 10분 디바운스
#   Rscript 02_Infrastructure/ops/refresh_screen_queues.R --status-line    # 읽기 전용 요약
# Kill switch: QVEST_SCREEN_QUEUE_NORUN=1
# Exit: 0 = 전건 성공/스킵/락점유중 · 1 = 하나 이상 실패
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || all(is.na(a))) b else a

.rsq_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[dir.exists(file.path(cands, "02_Infrastructure")) &
               dir.exists(file.path(cands, "06_Registry"))]
  if (!length(hit)) stop("[refresh_screen_queues] project root 미발견 (QM_ROOT 확인)")
  hit[1]
}

# 순서 고정 — 이 벡터의 순서가 곧 실행 순서다(위 헤더 ★ 참조).
RSQ_STEPS <- list(
  list(name = "overlay",    script = "02_Infrastructure/regime/overlay_candidate_queue.R",
       queue = "06_Registry/overlay_candidate_queue.json"),
  list(name = "standalone", script = "02_Infrastructure/portfolio/standalone_track_queue.R",
       queue = "06_Registry/standalone_track_queue.json"),
  list(name = "auto_spawn", script = "02_Infrastructure/ops/auto_spawn_queue.R",
       queue = "06_Registry/auto_spawn_queue.json")
)
RSQ_LOG_REL   <- ".cache/screen_queue_refresh.log"
RSQ_LOCK_REL  <- ".cache/screen_queue_refresh.lock"
RSQ_STALE_SEC <- 900   # 15분 — 락 회수 문턱

# 내구 로그 + stderr 동시 기록. 무인 런의 stdout 은 아무도 읽지 않는다.
.rsq_log <- function(root, ...) {
  msg <- sprintf("%s [refresh_screen_queues] %s",
                 format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), paste0(...))
  lp <- file.path(root, RSQ_LOG_REL)
  dir.create(dirname(lp), recursive = TRUE, showWarnings = FALSE)
  try(cat(msg, "\n", file = lp, append = TRUE, sep = ""), silent = TRUE)
  cat(msg, "\n", file = stderr(), sep = "")
}

.rsq_generated_at <- function(path) {
  if (!file.exists(path)) return(NA)
  g <- tryCatch(fromJSON(path, simplifyVector = TRUE)$generated_at, error = function(e) NULL)
  if (is.null(g) || !length(g) || is.na(g[1])) return(NA)
  suppressWarnings(as.POSIXct(substr(as.character(g[1]), 1, 19),
                              format = "%Y-%m-%dT%H:%M:%S"))
}

.rsq_age_min <- function(path) {
  ts <- .rsq_generated_at(path)
  if (length(ts) != 1L || is.na(ts)) return(NA_real_)
  as.numeric(difftime(Sys.time(), ts, units = "mins"))
}

# ── 뮤텍스 (dir.create 원자성 + stale 회수) ───────────────────────────────────
.rsq_acquire <- function(lock, wait_s = 20, stale_s = RSQ_STALE_SEC) {
  dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  deadline <- Sys.time() + wait_s
  repeat {
    if (isTRUE(suppressWarnings(dir.create(lock, showWarnings = FALSE)))) {
      try(writeLines(c(sprintf("pid=%s", Sys.getpid()),
                       sprintf("started=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))),
                     file.path(lock, "owner.txt")), silent = TRUE)
      return(TRUE)
    }
    info <- suppressWarnings(file.info(lock))
    age  <- suppressWarnings(as.numeric(difftime(Sys.time(), info$mtime, units = "secs")))
    if (length(age) == 1L && !is.na(age) && age > stale_s) {
      suppressWarnings(unlink(lock, recursive = TRUE, force = TRUE)); next
    }
    if (Sys.time() > deadline) return(FALSE)
    Sys.sleep(0.5)
  }
}
.rsq_release <- function(lock) suppressWarnings(unlink(lock, recursive = TRUE, force = TRUE))

# ── 빌더 1건 실행 (별도 Rscript 프로세스 — 전역 오염 격리) ────────────────────
.rsq_run_one <- function(step, root, rscript, if_stale_min = NA_real_) {
  qp  <- file.path(root, step$queue)
  age <- .rsq_age_min(qp)
  if (!is.na(if_stale_min) && !is.na(age) && age < if_stale_min) {
    .rsq_log(root, sprintf("SKIP  %-11s — generated_at %.1f분 전 < --if-stale %.0f분(디바운스)",
                           step$name, age, if_stale_min))
    return(list(name = step$name, status = "skipped", ok = TRUE))
  }
  sp <- file.path(root, step$script)
  if (!file.exists(sp)) {
    .rsq_log(root, sprintf("FAIL  %-11s — 빌더 스크립트 부재: %s", step$name, step$script))
    return(list(name = step$name, status = "missing_script", ok = FALSE))
  }
  t0 <- Sys.time()
  res <- tryCatch({
    out <- suppressWarnings(system2(rscript, c("--no-save", shQuote(sp)),
                                    stdout = TRUE, stderr = TRUE,
                                    timeout = as.numeric(Sys.getenv("QVEST_SCREEN_QUEUE_TIMEOUT", "900"))))
    st <- attr(out, "status") %||% 0L
    list(code = as.integer(st[1]), out = out)
  }, error = function(e) list(code = -1L, out = conditionMessage(e)))
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  tail_txt <- paste(utils::tail(as.character(res$out %||% character(0)), 4L), collapse = " | ")
  if (identical(res$code, 0L)) {
    .rsq_log(root, sprintf("OK    %-11s — %.1fs · %s", step$name, el, tail_txt))
    return(list(name = step$name, status = "ok", ok = TRUE))
  }
  .rsq_log(root, sprintf("FAIL  %-11s — exit=%s · %.1fs · %s", step$name, res$code, el, tail_txt))
  list(name = step$name, status = sprintf("exit_%s", res$code), ok = FALSE)
}

# ── 읽기 전용 상태라인 (build 하지 않는다) ────────────────────────────────────
refresh_screen_queues_status_line <- function(root = .rsq_root()) {
  parts <- vapply(RSQ_STEPS, function(s) {
    qp <- file.path(root, s$queue)
    if (!file.exists(qp)) return(sprintf("%s: 미생성", s$name))
    a <- .rsq_age_min(qp)
    n <- tryCatch({
      d <- fromJSON(qp, simplifyVector = FALSE)
      length(d$candidates %||% d$unconsumed %||% d$entries %||% list())
    }, error = function(e) NA_integer_)
    sprintf("%s: n=%s · %s", s$name, ifelse(is.na(n), "?", n),
            if (is.na(a)) "age ?" else sprintf("age %.0fm", a))
  }, character(1))
  paste0("ScreenQueues: ", paste(parts, collapse = " | "))
}

refresh_screen_queues <- function(root = .rsq_root(), if_stale_min = NA_real_) {
  rscript <- file.path(R.home("bin"), "Rscript")
  Sys.setenv(QM_ROOT = root)   # 자식 프로세스 root 고정 (Windows 는 system2(env=) 미지원)
  lock <- file.path(root, RSQ_LOCK_REL)
  if (!.rsq_acquire(lock)) {
    .rsq_log(root, "SKIP  전체 — 다른 리프레시가 락 점유중(정상 동시성). 이번 호출은 건너뛴다.")
    return(invisible(list(locked = FALSE, results = list())))
  }
  on.exit(.rsq_release(lock), add = TRUE)
  results <- lapply(RSQ_STEPS, .rsq_run_one, root = root, rscript = rscript,
                    if_stale_min = if_stale_min)
  nfail <- sum(!vapply(results, function(r) isTRUE(r$ok), logical(1)))
  .rsq_log(root, sprintf("DONE  %s (실패 %d)", refresh_screen_queues_status_line(root), nfail))
  invisible(list(locked = TRUE, results = results, n_fail = nfail))
}

# ── CLI ───────────────────────────────────────────────────────────────────────
.rsq_invoked_directly <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  length(f) > 0L && identical(basename(f[1]), "refresh_screen_queues.R")
}

if (.rsq_invoked_directly()) {
  args <- commandArgs(trailingOnly = TRUE)
  root <- .rsq_root()
  if ("--status-line" %in% args) {
    cat(refresh_screen_queues_status_line(root), "\n", sep = ""); quit(save = "no", status = 0L)
  }
  if (identical(Sys.getenv("QVEST_SCREEN_QUEUE_NORUN"), "1")) {
    .rsq_log(root, "SKIP  전체 — QVEST_SCREEN_QUEUE_NORUN=1 (kill switch)")
    quit(save = "no", status = 0L)
  }
  stale <- NA_real_
  ix <- which(args == "--if-stale")
  if (length(ix) && length(args) >= ix[1] + 1L) stale <- suppressWarnings(as.numeric(args[ix[1] + 1L]))
  eqf <- grep("^--if-stale=", args, value = TRUE)
  if (length(eqf)) stale <- suppressWarnings(as.numeric(sub("^--if-stale=", "", eqf[1])))
  r <- refresh_screen_queues(root, if_stale_min = stale)
  cat(refresh_screen_queues_status_line(root), "\n", sep = "")
  quit(save = "no", status = if (isTRUE((r$n_fail %||% 0L) > 0L)) 1L else 0L)
}
