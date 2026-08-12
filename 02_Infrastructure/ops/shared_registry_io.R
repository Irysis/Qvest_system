#==============================================================================
# shared_registry_io.R — 공유 원장 동시쓰기 보호 (범용 primitive)
#
# 2026-08-08 신설. 사건: FQ-122 라운드에서 `06_Registry/alpha_frontier_queue.json`
#   의 갱신이 **두 번 유실**됐다. numstat 3403/3333 = 전체 파일 재작성.
#
#------------------------------------------------------------------------------
# ★왜 기존 가드가 이걸 못 잡았나 (이 파일의 존재 이유)
#------------------------------------------------------------------------------
# `frontier_queue_io.R`(같은 날 신설)에는 이미 가드 2종이 있었다:
#     가드1 = 항목 **소실** 검거 (id setdiff)
#     가드2 = 고정밀 리터럴 **반올림** 검거 (digits=4 사고)
# 그런데 FQ-122 유실은 **둘 다 아니다**:
#     · 항목 수 불변 (167 → 167). 가드1 통과.
#     · 정밀도 불변 (양쪽 다 digits=NA). 가드2 통과.
#     · 유실된 것은 **다른 실행이 그 사이 넣은 필드 편집**이다.
#       A 가 읽고 → B 가 읽고 → B 가 쓰고 → A 가 **자기가 읽은 옛 판본** 위에 썼다.
#       A 의 판본도 완전한 167항목 유효 JSON 이라 **모든 형상 검사를 통과한다.**
#
# ⇒ 형상(shape) 검사로는 원리적으로 못 잡는다. 필요한 것은 **기준 판본(base) 검사**다:
#    "내가 읽은 그 판본이 아직 디스크에 있는가?" (compare-and-swap / 낙관적 동시성)
#    이 파일이 그것을 제공한다.
#
#------------------------------------------------------------------------------
# 3층 방어
#------------------------------------------------------------------------------
#  ① sr_mutex_*   — 임계구역 직렬화. dir.create 원자성(Git Bash 에 flock 부재).
#                    read-modify-write 를 감싸면 경합 자체가 사라진다.
#  ② sr_assert_base_unchanged — CAS. 뮤텍스를 안 쓴 경로(다른 세션·다른 도구·수기
#                    편집)까지 커버한다. **뮤텍스는 협조적이라 이것 없이는 못 믿는다.**
#  ③ sr_churn_guard — 전체 재직렬화 검거. 변경한 항목 수에서 **예산**을 도출해
#                    실제 줄 이동량과 대조한다. 형식(pretty) 드리프트든 전량
#                    재작성이든 예산을 수십 배 넘기므로 걸린다.
#
# ★①이 있는데 ②가 왜 필요한가 = 뮤텍스는 **모두가 쓸 때만** 유효하다. 이 저장소의
#   원장 writer 는 stage_artifacts 일회용 스크립트가 다수이고 그들이 뮤텍스를 부를
#   보장이 없다. ②는 상대가 협조하지 않아도 **내 쪽에서** 사고를 검거한다.
#   (같은 이유로 ②만 있고 ①이 없으면, 정직한 두 실행이 서로를 계속 거부하며
#    아무도 진전하지 못한다 — ①은 성능이 아니라 **진행성**을 위한 층이다.)
#
# 사용:
#   source("02_Infrastructure/ops/shared_registry_io.R")
#   sr_with_lock(path, {
#     st  <- sr_read(path)                       # 판본 지문 포착
#     obj <- st$data; obj$entries[[3]]$x <- 1
#     txt <- my_serialize(obj)
#     sr_guard_write(path, txt, base = st, budget_lines = 60)
#   })
#==============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("shared_registry_io: jsonlite 필요")
})

if (!exists("%||%")) `%||%` <- function(a, b)
  if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

.sr_norm <- function(p) gsub("\\\\", "/", p)

.sr_root <- function(root = NULL) {
  if (!is.null(root) && nzchar(root)) { r <- sub("/+$", "", .sr_norm(root)); if (dir.exists(r)) return(r) }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v)) { v <- sub("/+$", "", .sr_norm(v)); if (dir.exists(v)) return(v) }
  }
  sub("/+$", "", .sr_norm(getwd()))
}

# =============================================================================
# 지문 — 바이트 md5. tools 는 base R 배포분이라 의존성 추가가 아니다.
# =============================================================================
sr_fingerprint <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  unname(tools::md5sum(path))
}

# =============================================================================
# sr_read — 파싱 + **판본 지문 포착**. write 는 이 지문을 요구한다.
#   반환 list(data, fingerprint, text, path, n_lines)
#   ★지문을 반환 객체의 attribute 로 달지 않는 이유: R 에서 리스트를 편집하다 보면
#     attribute 가 조용히 떨어지는 경로가 흔하다(lapply/rapply/재구성). 지문이 조용히
#     사라지면 CAS 가 **조용히 꺼진다** = 이 저장소가 반복해 온 "검사 사망" 형태.
#     그래서 지문은 별도 필드로 명시 전달한다.
# =============================================================================
sr_read <- function(path, parser = NULL) {
  if (!file.exists(path)) stop("[sr] 원장 부재: ", path)
  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  dat <- if (is.null(parser)) jsonlite::fromJSON(path, simplifyVector = FALSE) else parser(path)
  list(data = dat, fingerprint = sr_fingerprint(path), text = txt,
       path = path, n_lines = length(strsplit(txt, "\n", fixed = TRUE)[[1]]))
}

# =============================================================================
# sr_assert_base_unchanged — CAS. **이 파일의 핵심 한 줄.**
# =============================================================================
sr_assert_base_unchanged <- function(path, base_fingerprint, what = "원장") {
  if (is.null(base_fingerprint) || is.na(base_fingerprint))
    stop(sprintf(paste0("[sr] 기준 판본 지문이 없다 — %s 에 눈감고 쓰려 한다.\n",
                        "  sr_read() 로 읽어 그 fingerprint 를 넘길 것. 지문 없는 쓰기는 ",
                        "병행 세션 갱신을 덮어써도 아무도 모른다."), path))
  cur <- sr_fingerprint(path)
  if (identical(as.character(cur), as.character(base_fingerprint))) return(invisible(TRUE))
  stop(sprintf(paste0(
    "[sr] ★기준 판본이 바뀌었다 — %s 를 덮어쓰면 병행 세션의 갱신이 유실된다.\n",
    "  내가 읽은 판본 : %s\n",
    "  지금 디스크    : %s\n",
    "  ── 조치: **재-read 후 편집을 다시 적용**할 것(내 판본을 그냥 쓰면 안 된다).\n",
    "     경합이 잦으면 sr_with_lock() 안에서 read-modify-write 를 감쌀 것.\n",
    "  ★2026-08-08 FQ-122 실사고가 정확히 이 지점이다 — 항목 수도 정밀도도 정상이라\n",
    "    형상 검사는 전부 통과했고, 유실은 조용했다."),
    what, substr(as.character(base_fingerprint), 1, 12), substr(as.character(cur), 1, 12)))
}

# =============================================================================
# sr_line_churn — 줄 다중집합 차분. 순서 변경에 둔감하고 내용 변경에 민감하다.
#   (정본 직렬화를 쓰는 원장에선 "안 바뀐 항목 = 바이트 동일 줄" 이므로 좋은 대용치.)
# =============================================================================
sr_line_churn <- function(old_txt, new_txt) {
  o <- strsplit(old_txt %||% "", "\n", fixed = TRUE)[[1]]
  n <- strsplit(new_txt %||% "", "\n", fixed = TRUE)[[1]]
  to <- table(o); tn <- table(n)
  keys <- union(names(to), names(tn))
  co <- as.integer(to[keys]); co[is.na(co)] <- 0L
  cn <- as.integer(tn[keys]); cn[is.na(cn)] <- 0L
  list(removed = sum(pmax(co - cn, 0L)), added = sum(pmax(cn - co, 0L)),
       old_lines = length(o), new_lines = length(n))
}

# =============================================================================
# sr_churn_guard — 전체 재직렬화 금지 강제.
#   budget_lines = "이번 편집이 정당하게 건드릴 수 있는 줄 수" 상한.
#   호출자가 **변경 항목으로부터 도출**해 넘긴다(임의 상수 금지 — 도출식을 남길 것).
# =============================================================================
sr_churn_guard <- function(old_txt, new_txt, budget_lines, path = "", allow_reformat = NULL) {
  ch <- sr_line_churn(old_txt, new_txt)
  if (!is.null(allow_reformat) && nzchar(as.character(allow_reformat))) {
    message(sprintf("[sr] 재직렬화 허용됨 (사유: %s) — 이동 %d줄 삭제 / %d줄 추가",
                    allow_reformat, ch$removed, ch$added))
    return(invisible(ch))
  }
  if (ch$removed > budget_lines)
    stop(sprintf(paste0(
      "[sr] ★전체 재직렬화 의심 — %s\n",
      "  삭제되는 줄 %d 이 예산 %d 을 초과한다 (추가 %d · 파일 %d줄).\n",
      "  ── 이 형태가 2026-08-08 FQ-122 사고다: 한쪽이 파일 전체를 다시 써서\n",
      "     다른 쪽의 targeted edit 을 되돌렸고(numstat 3403/3333), 그 결과\n",
      "     **diff 를 읽을 수 없게 되어** '순수 추가 확인' 규약까지 함께 무력해졌다.\n",
      "  ── 원인 대개: ①정본 직렬화 설정(pretty/digits) 불일치 ②디스크 판본이 이미\n",
      "     비정본 형식 ③객체를 통째로 재구성. 정본 writer 경유인지 확인할 것.\n",
      "  ── 의도한 형식 수렴이면 allow_reformat=<사유> 를 넘길 것(기록에 남는다)."),
      path, ch$removed, budget_lines, ch$added, ch$old_lines))
  invisible(ch)
}

# =============================================================================
# sr_numstat — `git diff --numstat` 관측.
#
#  ⚠ **정직 표기**: 이것은 HEAD 대비 **누적** 변경이지 "이번 쓰기" 가 아니다.
#     세션이 앞서 같은 파일을 정당하게 고쳤다면 그 변경도 함께 계상된다.
#     ⇒ 판정(게이트)은 sr_churn_guard(프로세스 내 old→new 실측)가 하고,
#       이 함수는 **보고·사후 확인용**이다. 도훈 요청("쓰기 후 numstat 으로 순수추가
#       확인")의 기계화는 churn_guard 가 담당하고, 여기서는 그 결과를 사람이 읽는
#       형태로 병기한다.
#  ⚠ system2 는 셸을 경유하지 않는다 — 리다이렉션/&& 를 문자열에 넣지 말 것
#     (r-portability.md 금칙⑤: 리터럴 argv 로 전달돼 빈 출력이 '변경 없음' 으로 위장).
# =============================================================================
sr_numstat <- function(path, root = NULL) {
  rt <- .sr_root(root)
  rel <- .sr_norm(path)
  if (startsWith(rel, paste0(rt, "/"))) rel <- substring(rel, nchar(rt) + 2L)
  out <- tryCatch(
    suppressWarnings(system2("git", c("-C", rt, "diff", "--numstat", "--", rel),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character(0))
  if (!length(out)) return(list(added = 0L, removed = 0L, tracked_change = FALSE, raw = ""))
  f <- strsplit(out[1], "\t", fixed = TRUE)[[1]]
  a <- suppressWarnings(as.integer(f[1])); r <- suppressWarnings(as.integer(f[2]))
  list(added = if (is.na(a)) 0L else a, removed = if (is.na(r)) 0L else r,
       tracked_change = TRUE, raw = out[1])
}

# =============================================================================
# 뮤텍스 — read-modify-write 직렬화. cleaner_claim.R `.cc_acquire_mutex` 동형.
# =============================================================================
.sr_mutex_path <- function(path, root = NULL)
  file.path(.sr_root(root), ".cache", "registry_locks",
            paste0(gsub("[^A-Za-z0-9._-]", "_", basename(path)), ".writelock"))

sr_mutex_acquire <- function(path, wait_s = 20, stale_s = 300, root = NULL) {
  mp <- .sr_mutex_path(path, root)
  dir.create(dirname(mp), recursive = TRUE, showWarnings = FALSE)
  deadline <- Sys.time() + wait_s
  repeat {
    if (isTRUE(suppressWarnings(dir.create(mp, showWarnings = FALSE)))) return(mp)
    info <- suppressWarnings(file.info(mp))
    age  <- suppressWarnings(as.numeric(difftime(Sys.time(), info$mtime[1], units = "secs")))
    if (!is.na(age) && age > stale_s) { suppressWarnings(unlink(mp, recursive = TRUE)); next }
    if (Sys.time() > deadline)
      stop(sprintf(paste0("[sr] 원장 뮤텍스 취득 실패(%ds 대기): %s\n",
                          "  다른 실행이 %s 를 쓰는 중이다 — 기다렸다 재시도할 것."),
                   wait_s, mp, basename(path)))
    Sys.sleep(0.15)
  }
}

sr_mutex_release <- function(mp) invisible(suppressWarnings(unlink(mp, recursive = TRUE)))

#' 임계구역 실행 — 예외가 나도 뮤텍스를 놓는다.
sr_with_lock <- function(path, expr, wait_s = 20, stale_s = 300, root = NULL) {
  mp <- sr_mutex_acquire(path, wait_s = wait_s, stale_s = stale_s, root = root)
  on.exit(sr_mutex_release(mp), add = TRUE)     # 함수 내부 on.exit — 정상 발화
  force(expr)
}

# =============================================================================
# sr_guard_write — ②③ 를 함께 걸고 쓴다. (뮤텍스는 호출자가 sr_with_lock 으로)
#   base = sr_read() 반환 객체.
# =============================================================================
sr_guard_write <- function(path, new_txt, base, budget_lines,
                           allow_reformat = NULL, what = basename(path)) {
  if (is.null(base) || is.null(base$fingerprint))
    stop("[sr] base 는 sr_read() 반환 객체여야 한다 (fingerprint 필요).")
  sr_assert_base_unchanged(path, base$fingerprint, what = what)             # ②
  ch <- sr_churn_guard(base$text, new_txt, budget_lines, path = path,
                       allow_reformat = allow_reformat)                     # ③
  writeLines(new_txt, path, useBytes = TRUE)

  # 기록 후 재읽기 — 쓴 것이 실제로 읽히는가 (침묵 실패 차단)
  back <- tryCatch(paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
                   error = function(e) NULL)
  if (is.null(back)) stop("[sr] ★기록 후 재읽기 실패: ", path)
  invisible(list(churn = ch, fingerprint = sr_fingerprint(path)))
}
