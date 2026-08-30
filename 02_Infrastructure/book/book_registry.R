# =============================================================================
# book_registry.R — BOOK 등록·트래킹 writer (v10 2026-08-29 신설, governor 승계)
# =============================================================================
# 도훈 지시: "Governor 삭제. A등급 달성한 팩터 전략 / 전략 로테이션 규칙을 BOOK 에
#   등록해둘 것. 언제든지 호출하여 결과 트래킹 할 수 있게끔. Qvest 는 실투자 시스템이
#   아니라 리서치 시스템 — BOOK 등록 + 사후 관리 과정만 필요."
#
# 정본: 06_Registry/book/book_registry.json (schema book_registry_v1)
# 쓰기 계약: **이 writer 경유만** — 직접 편집은 book_write_guard.sh 훅이 차단.
#   등록은 append-only(엔트리 삭제 금지 — 상태 변경은 status 필드만).
#   등록 자격 = essence Grade A + judge_verdict(pit_pass=true). 예외 = 도훈 mandate
#   (grade_basis 에 "dohoon_mandate_YYYYMMDD" 명시 — PG2 이관이 1호 선례).
# 구 book_state.json(qepm/mailbox/governor/)은 legacy 동결·읽기전용 사료.
# =============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.bk_root <- function() {
  cands <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in cands) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[book_registry] project root 미발견")
}

BOOK_KINDS <- c("factor_strategy", "rotation_rule")
BOOK_STATUS <- c("active", "suspended", "retired")

.bk_path <- function(root = .bk_root()) file.path(root, "06_Registry", "book", "book_registry.json")

.bk_skeleton <- function() list(
  schema_version = "book_registry_v1",
  note = paste0("Qvest BOOK — A등급 팩터전략·전략로테이션 규칙의 등록·사후 트래킹 정본 ",
                "(v10 2026-08-29, governor/book_state 승계). 쓰기 = book_registry.R writer 경유만",
                "(직접 편집은 book_write_guard.sh 차단). 등록 = append-only + 도훈 confirm. ",
                "Qvest 는 리서치 시스템 — 실투자 집행 개념 없음."),
  entries = list(),
  last_updated = "")

read_book <- function(root = .bk_root()) {
  p <- .bk_path(root)
  if (!file.exists(p)) return(.bk_skeleton())
  obj <- fromJSON(p, simplifyVector = FALSE)
  if (!identical(obj$schema_version, "book_registry_v1"))
    stop(sprintf("[book_registry] schema_version 불일치: %s", obj$schema_version))
  obj
}

.bk_write <- function(obj, root = .bk_root()) {
  obj$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  txt <- toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
  chk <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk) || length(chk$entries) != length(obj$entries))
    stop("[book_registry] 쓰기 직전 재파싱 검증 실패 — 원본 불변")
  p <- .bk_path(root)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(p, ".tmp")
  write(txt, tmp)
  ok <- suppressWarnings(file.rename(tmp, p))
  if (!ok) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
  invisible(p)
}

.bk_next_id <- function(obj) {
  ids <- vapply(obj$entries, function(e) as.character(e$book_id %||% ""), character(1))
  nums <- suppressWarnings(as.integer(gsub("[^0-9]", "", ids)))
  n <- if (length(nums) && any(is.finite(nums))) max(nums, na.rm = TRUE) else 0L
  sprintf("BOOK_%04d", n + 1L)
}

#' BOOK 등록 — Grade A + Judge PASS 검증 후 append (도훈 confirm 은 호출 전 세션 책임)
#' @param kind "factor_strategy" | "rotation_rule"
#' @param strategy_id 전략 id (rotation_rule 이면 fr_id)
#' @param grade_basis 등급 출처. mandate 예외("dohoon_mandate_*")가 아니면
#'   judge_verdict_path 의 pit_pass=true 를 실제로 읽어 검증한다(진술 아님 — 재도출).
register_book_entry <- function(kind, strategy_id, layer, grade = "A",
                                grade_basis = "essence_score(authoritative_remeasure.json)",
                                judge_verdict_path = NULL,
                                source_papers = list(), code_path = "",
                                official_metrics = list(), registered_by = "dohoon",
                                root = .bk_root()) {
  stopifnot(kind %in% BOOK_KINDS)
  if (!identical(as.character(grade), "A"))
    stop("[book_registry] BOOK 은 A등급만 등록한다 (도훈 지시) — B 이하는 강화 프로세스로")
  is_mandate <- grepl("^dohoon_mandate", as.character(grade_basis))
  if (!is_mandate) {
    if (is.null(judge_verdict_path) || !file.exists(file.path(root, judge_verdict_path)) &&
        !file.exists(judge_verdict_path))
      stop("[book_registry] judge_verdict_path 필수 (mandate 예외 아님) — Judge(PIT) PASS 없이 등록 불가")
    vp <- if (file.exists(judge_verdict_path)) judge_verdict_path else file.path(root, judge_verdict_path)
    v <- tryCatch(fromJSON(vp, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(v) || !isTRUE(v$pit_pass))
      stop("[book_registry] judge_verdict pit_pass != true — PIT 미통과 전략은 등록 불가")
  }
  obj <- read_book(root)
  dup <- vapply(obj$entries, function(e) identical(e$strategy_id, strategy_id) &&
                  !identical(e$status, "retired"), logical(1))
  if (any(dup)) stop(sprintf("[book_registry] %s 는 이미 등록돼 있음 (retired 아님)", strategy_id))

  entry <- list(
    book_id = .bk_next_id(obj), kind = kind, strategy_id = strategy_id,
    layer = as.integer(layer), grade = "A", grade_basis = as.character(grade_basis),
    judge_verdict_path = judge_verdict_path,
    registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    registered_by = registered_by,
    source_papers = source_papers, code_path = as.character(code_path),
    official_metrics = official_metrics,
    tracking = list(last_run = NULL, last_nav_date = NULL, artifacts = list(), history = list()),
    status = "active")
  obj$entries[[length(obj$entries) + 1L]] <- entry
  .bk_write(obj, root)
  cat(sprintf("[book_registry] 등록: %s = %s (%s · L%d · %s)\n",
              entry$book_id, strategy_id, kind, as.integer(layer), grade_basis))
  .bk_signal_rebalance_spec(entry$book_id, strategy_id, root)
  invisible(entry)
}

#' 리밸 사양 미작성 신호 (도훈 지시 2026-08-30)
#'
#' **왜**: BOOK 등재와 리밸 사양(02_Infrastructure/book/rebalance_spec.json)은 따로 논다.
#'   등재해도 사양이 없으면 `/book-rebalance` 사전점검이 rc=2 로 막지만, 그건 **리밸을
#'   시도한 뒤에야** 드러난다. 등재 시점에 신호를 내지 않으면 "등재는 됐는데 돌릴 수 없는
#'   전략"이 조용히 쌓인다. 전략마다 소비 데이터·오버레이 축이 달라 사양은 기계가 못 채운다
#'   — 그래서 **자동 생성이 아니라 신호**다(도훈: "자동으로 스킬을 생성하라는 시그널 정도").
#' **어디에 남기나**: 콘솔은 흘러가므로 `06_Registry/pending_rebalance_specs.json` 에
#'   적재하고 부팅 Book 줄이 계속 보여준다. 사양이 생기면 다음 호출에서 자동으로 빠진다.
.bk_signal_rebalance_spec <- function(book_id, strategy_id, root = .bk_root()) {
  spec_path <- file.path(root, "02_Infrastructure", "book", "rebalance_spec.json")
  pend_path <- file.path(root, "06_Registry", "pending_rebalance_specs.json")
  have <- tryCatch({
    s <- jsonlite::fromJSON(spec_path, simplifyVector = FALSE)
    vapply(s$specs, function(x) as.character(x$book_id), character(1))
  }, error = function(e) character(0))
  if (book_id %in% have) return(invisible(FALSE))

  cat(strrep("=", 78), "\n", sep = "")
  cat(sprintf("★ 리밸 사양 필요 — %s (%s)\n", book_id, strategy_id))
  cat("  BOOK 에 등재됐으나 리밸런싱 사양이 없다. 사양 없이는 /book-rebalance 가\n")
  cat("  사전점검에서 rc=2 로 막는다(설계대로 — 표준화되지 않은 리밸을 돌리지 않는다).\n")
  cat("  작성: 02_Infrastructure/book/rebalance_spec.json · 규약 = .claude/skills/book-rebalance/SKILL.md\n")
  cat("  채울 것: runner(cmd·산출·게이트) · inputs(소비면 경로·mode·max_lag_days·refresh_owner)\n")
  cat("           · overlays(panel·fire_expr·expect_alive) · post_checks\n")
  cat("  ※ max_lag_days 와 오버레이 발화식은 **실측으로 재단**한다 — 기계가 못 채운다.\n")
  cat(strrep("=", 78), "\n", sep = "")

  pend <- tryCatch(jsonlite::fromJSON(pend_path, simplifyVector = FALSE),
                   error = function(e) list(schema = "pending_rebalance_specs_v1", items = list()))
  if (is.null(pend$items)) pend$items <- list()
  seen <- vapply(pend$items, function(x) as.character(x$book_id), character(1))
  if (!(book_id %in% seen)) {
    pend$items[[length(pend$items) + 1L]] <- list(
      book_id = book_id, strategy_id = strategy_id,
      signaled_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      note = "리밸 사양 미작성 — rebalance_spec.json 에 추가하면 자동 해소")
    pend$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    tmp <- paste0(pend_path, ".tmp")
    writeLines(jsonlite::toJSON(pend, auto_unbox = TRUE, pretty = TRUE), tmp, useBytes = TRUE)
    if (file.exists(pend_path)) file.remove(pend_path)
    file.rename(tmp, pend_path)
    cat(sprintf("[book_registry] 대기 목록 적재: %s\n", pend_path))
  }
  invisible(TRUE)
}

#' 트래킹 결과 기록 (온디맨드 — /book 이 재실행한 최신 NAV 결과)
update_book_tracking <- function(book_id, run_result, root = .bk_root()) {
  obj <- read_book(root)
  i <- which(vapply(obj$entries, function(e) identical(e$book_id, book_id), logical(1)))
  if (!length(i)) stop(sprintf("[book_registry] book_id 부재: %s", book_id))
  i <- i[1]
  tr <- obj$entries[[i]]$tracking
  rec <- c(list(ran_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), run_result)
  tr$history[[length(tr$history) + 1L]] <- rec   # append-only
  tr$last_run <- rec$ran_at
  tr$last_nav_date <- run_result$last_nav_date %||% tr$last_nav_date
  if (!is.null(run_result$artifacts)) tr$artifacts <- unique(c(unlist(tr$artifacts), run_result$artifacts))
  obj$entries[[i]]$tracking <- tr
  .bk_write(obj, root)
  cat(sprintf("[book_registry] 트래킹 갱신: %s (nav %s)\n", book_id, tr$last_nav_date %||% "?"))
  invisible(obj$entries[[i]])
}

#' 상태 변경 (active/suspended/retired — 엔트리 삭제 금지)
set_book_status <- function(book_id, status, reason = "", root = .bk_root()) {
  stopifnot(status %in% BOOK_STATUS)
  obj <- read_book(root)
  i <- which(vapply(obj$entries, function(e) identical(e$book_id, book_id), logical(1)))
  if (!length(i)) stop(sprintf("[book_registry] book_id 부재: %s", book_id))
  i <- i[1]
  obj$entries[[i]]$status <- status
  obj$entries[[i]]$status_history <- c(obj$entries[[i]]$status_history %||% list(),
    list(list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), status = status, reason = reason)))
  .bk_write(obj, root)
  invisible(obj$entries[[i]])
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

cat("[book_registry.R] Loaded (v10) — read_book / register_book_entry(A+Judge PASS 검증) / update_book_tracking / set_book_status\n")
