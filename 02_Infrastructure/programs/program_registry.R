#==============================================================================
# program_registry.R — v10.01 리서치 프로그램 등록부의 단일 writer (2026-10-13)
#
# 왜: v10.01 은 '논문 1편 = 리서치 1단위'가 아니라 '목표 결함 1개 = 리서치 1단위'다. 무엇을 하고 있는지
#   (프로그램 · 선행 조건 · 재료 큐 · 라운드)를 한 곳에서 읽고 써야 세션이 바뀌어도 이어진다.
#   등록부 = 06_Registry/research_programs.json. 이 파일 밖에서 등록부를 쓰지 않는다.
# 원칙: 쓰기 = 검사 통과 후 원자적 교체(임시 파일 → 이름 바꾸기). 검사 실패 = 멈춤(부분 쓰기 없음).
#   큐 중복은 전 프로그램에 걸쳐 key 로 막는다(같은 논문이 두 엔진 큐에 동시에 서지 않는다).
# 공개: pr_path · pr_load · pr_validate · pr_save · pr_get · pr_set_status · pr_enqueue · pr_dequeue ·
#       pr_record_round · pr_mc_set · pr_mc_drop · pr_refresh_blocks · pr_status_lines ·
#       pr_hold_unrouted · pr_route_unrouted(미분류 재료 — 2026-10-14)
# 검사: 08_Tests/programs/test_program_registry.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

PR_STATUS <- c("blocked", "idle", "ready", "active", "paused", "done", "killed")
PR_MC_STATUS <- c("todo", "doing", "done")

.pr_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.pr_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (dir.exists(file.path(p, "06_Registry"))) return(p)
  }
  stop("[program_registry] 프로젝트 루트 해석 실패")
}

pr_path <- function(root = NULL) file.path(.pr_root(root), "06_Registry/research_programs.json")

pr_load <- function(root = NULL, path = NULL) {
  p <- .pr_or(path, pr_path(root))
  reg <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(reg)) stop("[program_registry] 등록부 판독 불가: ", p)
  reg
}

#' 스키마 검사 — 문제 목록(문자열 벡터)을 돌려준다. 빈 벡터 = 통과
pr_validate <- function(reg) {
  e <- character(0)
  if (!identical(reg$schema, "research_programs_v1")) e <- c(e, "schema != research_programs_v1")
  if (is.null(reg$target_spec)) e <- c(e, "target_spec 없음")
  P <- .pr_or(reg$programs, list())
  if (!length(P)) e <- c(e, "programs 비어 있음")
  ids <- vapply(P, function(p) .pr_or(p$id, ""), character(1))
  if (any(!nzchar(ids))) e <- c(e, "id 없는 프로그램")
  if (anyDuplicated(ids)) e <- c(e, paste("중복 프로그램 id:", paste(ids[duplicated(ids)], collapse = ",")))
  mc <- .pr_or(reg$measurement_contract$items, list())
  mc_ids <- vapply(mc, function(m) .pr_or(m$id, ""), character(1))
  for (m in mc) if (!(.pr_or(m$status, "") %in% PR_MC_STATUS)) e <- c(e, paste("측정 계약 상태 어휘 밖:", m$id, m$status))
  keys <- character(0)
  for (p in P) {
    if (!(.pr_or(p$status, "") %in% PR_STATUS)) e <- c(e, paste("상태 어휘 밖:", p$id, .pr_or(p$status, "<없음>")))
    for (b in .pr_or(p$blocked_by, list()))
      if (!(b %in% c(ids, mc_ids))) e <- c(e, paste("blocked_by 대상 없음:", p$id, "→", b))
    for (q in .pr_or(p$queue, list())) {
      k <- .pr_or(q$key, "")
      if (!nzchar(k)) e <- c(e, paste("key 없는 큐 항목:", p$id))
      keys <- c(keys, k)
    }
  }
  for (q in .pr_or(reg$paper_routing$unrouted, list())) {     # 미분류 보류(2026-10-14) — 큐와 같은 key 규약
    k <- .pr_or(q$key, "")
    if (!nzchar(k)) e <- c(e, "key 없는 미분류 보류 항목")
    keys <- c(keys, k)
  }
  if (anyDuplicated(keys)) e <- c(e, paste("큐 key 중복(프로그램 간 · 미분류 보류 포함):", paste(unique(keys[duplicated(keys)]), collapse = ",")))
  e
}

#' 저장 — 검사 통과 후 원자적 교체. version 증가 · updated_at 갱신
pr_save <- function(reg, root = NULL, path = NULL) {
  bad <- pr_validate(reg)
  if (length(bad)) stop("[program_registry] 검사 실패 — 쓰지 않는다:\n  ", paste(bad, collapse = "\n  "))
  reg$version <- as.integer(.pr_or(reg$version, 0L)) + 1L
  reg$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  p <- .pr_or(path, pr_path(root)); tmp <- paste0(p, ".tmp")
  writeLines(toJSON(reg, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA),
             tmp, useBytes = TRUE)
  if (!file.rename(tmp, p)) stop("[program_registry] 원자적 교체 실패: ", p)
  invisible(reg)
}

.pr_idx <- function(reg, id) {
  ids <- vapply(reg$programs, function(p) p$id, character(1))
  i <- match(id, ids)
  if (is.na(i)) stop("[program_registry] 프로그램 없음: ", id)
  i
}

pr_get <- function(reg, id) reg$programs[[.pr_idx(reg, id)]]

pr_set_status <- function(id, status, reason = "", root = NULL, path = NULL) {
  if (!(status %in% PR_STATUS)) stop("[program_registry] 상태 어휘 밖: ", status)
  reg <- pr_load(root, path); i <- .pr_idx(reg, id)
  reg$programs[[i]]$status <- status
  reg$programs[[i]]$status_reason <- reason
  reg$programs[[i]]$status_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  pr_save(reg, root, path)
}

#' 재료 큐에 넣기 — key(예: 논문 paper_key)가 어느 프로그램의 큐나 소비 기록에 이미 있으면 넣지 않고 FALSE
#'   (소비 기록까지 보는 이유: 동기화가 매일 같은 라우팅 산출을 다시 읽어도 이미 쓴 재료가 되살아나지 않게)
pr_enqueue <- function(id, item, root = NULL, path = NULL) {
  if (is.null(item$key) || !nzchar(item$key)) stop("[program_registry] 큐 항목에 key 가 없다")
  reg <- pr_load(root, path)
  for (p in reg$programs) for (q in c(.pr_or(p$queue, list()), .pr_or(p$consumed, list())))
    if (identical(q$key, item$key)) return(invisible(FALSE))
  i <- .pr_idx(reg, id)
  item$enqueued_at <- .pr_or(item$enqueued_at, format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  reg$programs[[i]]$queue <- c(.pr_or(reg$programs[[i]]$queue, list()), list(item))
  pr_save(reg, root, path)
  invisible(TRUE)
}

#' 여러 항목을 한 번에 넣기(한 번 읽고 한 번 쓴다) — items = list(list(program=, item=list(key=, ...)), ...)
#' @return 실제로 들어간 건수(프로그램별 named integer)
pr_enqueue_many <- function(items, root = NULL, path = NULL) {
  reg <- pr_load(root, path)
  seen <- character(0)
  for (p in reg$programs) for (q in c(.pr_or(p$queue, list()), .pr_or(p$consumed, list()))) seen <- c(seen, .pr_or(q$key, ""))
  added <- integer(0)
  for (x in items) {
    k <- .pr_or(x$item$key, "")
    if (!nzchar(k) || k %in% seen) next
    i <- .pr_idx(reg, x$program)
    it <- x$item; it$enqueued_at <- .pr_or(it$enqueued_at, format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
    reg$programs[[i]]$queue <- c(.pr_or(reg$programs[[i]]$queue, list()), list(it))
    seen <- c(seen, k)
    cur <- if (x$program %in% names(added)) added[[x$program]] else 0L
    added[[x$program]] <- cur + 1L
  }
  if (length(added)) pr_save(reg, root, path)
  added
}

#' 큐 맨 앞 항목 꺼내기(소비 기록과 함께) — 비어 있으면 NULL
pr_dequeue <- function(id, consumer = "", root = NULL, path = NULL) {
  reg <- pr_load(root, path); i <- .pr_idx(reg, id)
  q <- .pr_or(reg$programs[[i]]$queue, list())
  if (!length(q)) return(NULL)
  head <- q[[1]]
  reg$programs[[i]]$queue <- q[-1]
  head$consumed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); head$consumer <- consumer
  reg$programs[[i]]$consumed <- c(.pr_or(reg$programs[[i]]$consumed, list()), list(head))
  pr_save(reg, root, path)
  head
}

#' 미분류 재료 보류 — 라우터(v5)가 엔진을 정하지 않은 측정 재료(충실구현 산출)를 프로그램을 추측하지 않고 둔다(2026-10-14).
#'   실측(1810.08384): 구판 검증기는 등록부에 없으면 'P1_RETURN' 을 기본값으로 적어, 구성(P3) 논문이 '수익 엔진'으로 보고됐고
#'   어느 큐에도 들어가지 않았다. 자리 = paper_routing$unrouted · 분류가 생기면 pr_route_unrouted 가 프로그램 큐로 옮긴다.
#' @return 넣었으면 TRUE · 같은 key 가 이미 보류 · 큐 · 소비 기록에 있으면 FALSE
pr_hold_unrouted <- function(item, root = NULL, path = NULL) {
  if (is.null(item$key) || !nzchar(item$key)) stop("[program_registry] 보류 항목에 key 가 없다")
  reg <- pr_load(root, path)
  for (q in .pr_or(reg$paper_routing$unrouted, list())) if (identical(q$key, item$key)) return(invisible(FALSE))
  for (p in reg$programs) for (q in c(.pr_or(p$queue, list()), .pr_or(p$consumed, list())))
    if (identical(q$key, item$key)) return(invisible(FALSE))
  item$held_at <- .pr_or(item$held_at, format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  reg$paper_routing$unrouted <- c(.pr_or(reg$paper_routing$unrouted, list()), list(item))
  pr_save(reg, root, path)
  invisible(TRUE)
}

#' 미분류 재료 → 프로그램 큐(라우터 v5 분류 · 세션 분류 공용). routed_by 를 항목에 남긴다.
#' @return 옮겼으면 TRUE · 보류 목록에 없으면 FALSE
pr_route_unrouted <- function(key, id, routed_by = "session", root = NULL, path = NULL) {
  reg <- pr_load(root, path)
  U <- .pr_or(reg$paper_routing$unrouted, list())
  j <- which(vapply(U, function(x) identical(x$key, key), logical(1)))
  if (!length(j)) return(invisible(FALSE))
  i <- .pr_idx(reg, id)
  it <- U[[j[1]]]; it$routed_by <- routed_by; it$routed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  reg$paper_routing$unrouted <- U[-j[1]]
  reg$programs[[i]]$queue <- c(.pr_or(reg$programs[[i]]$queue, list()), list(it))
  pr_save(reg, root, path)
  invisible(TRUE)
}

#' key 가 어느 프로그램의 큐(또는 소비 기록)에 있는지 — 없으면 NA
pr_find_key <- function(reg, key) {
  for (p in reg$programs) for (q in c(.pr_or(p$queue, list()), .pr_or(p$consumed, list())))
    if (identical(q$key, key)) return(p$id)
  NA_character_
}

#' 특정 key 를 큐에서 소비 기록으로 옮긴다(맨 앞이 아니어도). 큐에 없으면 FALSE
pr_consume_key <- function(id, key, consumer = "", root = NULL, path = NULL) {
  reg <- pr_load(root, path); i <- .pr_idx(reg, id)
  q <- .pr_or(reg$programs[[i]]$queue, list())
  j <- which(vapply(q, function(x) identical(x$key, key), logical(1)))
  if (!length(j)) return(invisible(FALSE))
  it <- q[[j[1]]]; it$consumed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); it$consumer <- consumer
  reg$programs[[i]]$queue <- q[-j[1]]
  reg$programs[[i]]$consumed <- c(.pr_or(reg$programs[[i]]$consumed, list()), list(it))
  pr_save(reg, root, path)
  invisible(TRUE)
}

#' 라운드 기록 — round_id · prereg(사전등록 경로) 필수. 결과는 나중에 같은 round_id 로 덮어 쓴다
#'   ★R2 — 경로만이 아니라 **내용(md5)**도 잰다(2026-10-15 도훈 권고 수용 · 구판은 경로만 비교해 같은 경로의 내용 교체를 못 막았다):
#'   ① 기록된 prereg_md5 와 다른 md5 로 갱신 = 사전등록 교체 — 결과 전(status = registered)이고 round$supersedes$md5 가 옛 md5 와 같을 때만
#'   ② 결과 · 종료 기록(status ≠ registered)은 그 경로 파일의 실제 md5 가 기록된 md5 와 같아야 한다(등록 뒤 파일이 바뀌었으면 거부)
.pr_file_md5 <- function(root, rel) {
  if (is.null(rel) || !nzchar(rel)) return(NA_character_)
  p <- if (grepl("^([A-Za-z]:|/)", rel)) rel else file.path(.pr_root(root), rel)
  if (file.exists(p)) unname(as.character(tools::md5sum(p))) else NA_character_
}
pr_record_round <- function(id, round, root = NULL, path = NULL) {
  if (is.null(round$round_id) || !nzchar(round$round_id)) stop("[program_registry] round_id 없음")
  if (is.null(round$prereg) || !nzchar(round$prereg)) stop("[program_registry] 사전등록 경로(prereg) 없음 — R2: 측정 전 등록")
  reg <- pr_load(root, path); i <- .pr_idx(reg, id)
  R <- .pr_or(reg$programs[[i]]$rounds, list())
  ids <- vapply(R, function(r) .pr_or(r$round_id, ""), character(1))
  j <- match(round$round_id, ids)
  round$recorded_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (is.na(j)) R <- c(R, list(round)) else {
    old <- R[[j]]
    if (!identical(old$prereg, round$prereg)) stop("[program_registry] 사전등록을 결과 뒤에 바꿀 수 없다(R2): ", round$round_id)
    om <- as.character(.pr_or(old$prereg_md5, NA_character_))[1]; nm <- as.character(.pr_or(round$prereg_md5, NA_character_))[1]
    if (!is.na(om) && !is.na(nm) && !identical(om, nm)) {
      has_result <- !identical(as.character(.pr_or(old$status, "registered"))[1], "registered")
      if (has_result) stop("[program_registry] 결과 · 종료가 기록된 라운드의 사전등록 내용(md5)을 바꿀 수 없다(R2): ", round$round_id)
      sp <- as.character(.pr_or(round$supersedes$md5, NA_character_))[1]
      if (!identical(sp, om)) stop("[program_registry] 사전등록 내용(md5)이 바뀌었다 — 결과 전 대체는 supersedes$md5 = 옛 md5 를 적어야 한다(R2): ", round$round_id)
      round$supersede_history <- c(.pr_or(old$supersede_history, list()),
                                   list(list(from_md5 = om, to_md5 = nm, at = round$recorded_at, reason = .pr_or(round$supersedes$reason, ""))))
      round$supersedes <- NULL
    }
    st_new <- as.character(.pr_or(round$status, .pr_or(old$status, "registered")))[1]
    if (!identical(st_new, "registered")) {
      want <- if (!is.na(nm)) nm else om
      have <- .pr_file_md5(root, round$prereg)
      if (!is.na(want) && !is.na(have) && !identical(want, have))
        stop("[program_registry] 사전등록 파일이 등록 뒤 바뀌었다(기록 md5 ", substr(want, 1, 8), " ≠ 파일 ", substr(have, 1, 8), ") — 결과를 기록하지 않는다(R2): ", round$round_id)
    }
    R[[j]] <- modifyList(old, round)
  }
  reg$programs[[i]]$rounds <- R
  pr_save(reg, root, path)
}

#' 측정 계약 항목 상태 갱신 — 끝나면 막혀 있던 프로그램을 다시 계산한다
pr_mc_set <- function(mc_id, status, artifact = NULL, root = NULL, path = NULL) {
  if (!(status %in% PR_MC_STATUS)) stop("[program_registry] 측정 계약 상태 어휘 밖: ", status)
  reg <- pr_load(root, path)
  ids <- vapply(reg$measurement_contract$items, function(m) m$id, character(1))
  j <- match(mc_id, ids); if (is.na(j)) stop("[program_registry] 측정 계약 항목 없음: ", mc_id)
  reg$measurement_contract$items[[j]]$status <- status
  if (!is.null(artifact)) reg$measurement_contract$items[[j]]$artifact <- artifact
  reg <- pr_refresh_blocks(reg)
  pr_save(reg, root, path)
}

#' 측정 계약 항목을 결정으로 뺀다 — 지우지 않고 measurement_contract$dropped 로 옮겨 사유·결정자·시각을 남긴다.
#'   프로그램 blocked_by 에서도 빼고 blocked 판정을 다시 한다. 사유 없는 제외는 거부(결정 기록이 정본).
#'   (10-13 첫 사용: MC2 상장폐지 수익률 규칙 — 도훈 "D14 필요없어")
pr_mc_drop <- function(mc_id, reason, decided_by, root = NULL, path = NULL) {
  if (missing(reason) || !nzchar(.pr_or(reason, ""))) stop("[program_registry] 제외 사유 없음 — 결정 기록 없이 계약 항목을 뺄 수 없다")
  if (missing(decided_by) || !nzchar(.pr_or(decided_by, ""))) stop("[program_registry] 결정자 없음")
  reg <- pr_load(root, path)
  ids <- vapply(reg$measurement_contract$items, function(m) m$id, character(1))
  j <- match(mc_id, ids); if (is.na(j)) stop("[program_registry] 측정 계약 항목 없음: ", mc_id)
  it <- reg$measurement_contract$items[[j]]
  it$dropped_reason <- reason; it$dropped_by <- decided_by
  it$dropped_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); it$status_before <- it$status; it$status <- NULL
  reg$measurement_contract$items[[j]] <- NULL
  reg$measurement_contract$dropped <- c(.pr_or(reg$measurement_contract$dropped, list()), list(it))
  for (i in seq_along(reg$programs)) {
    bb <- unlist(.pr_or(reg$programs[[i]]$blocked_by, list()))
    if (mc_id %in% bb) reg$programs[[i]]$blocked_by <- as.list(setdiff(bb, mc_id))
  }
  reg <- pr_refresh_blocks(reg)
  pr_save(reg, root, path)
}

#' blocked 프로그램 중 선행 조건이 모두 끝난 것을 ready 로 올린다(사람이 정한 paused/killed 는 건드리지 않는다)
pr_refresh_blocks <- function(reg) {
  done_mc <- vapply(reg$measurement_contract$items, function(m) identical(m$status, "done"), logical(1))
  names(done_mc) <- vapply(reg$measurement_contract$items, function(m) m$id, character(1))
  prog_done <- vapply(reg$programs, function(p) p$status %in% c("done"), logical(1))
  names(prog_done) <- vapply(reg$programs, function(p) p$id, character(1))
  ok <- c(done_mc, prog_done)
  for (i in seq_along(reg$programs)) {
    p <- reg$programs[[i]]
    if (!identical(p$status, "blocked")) next
    deps <- unlist(.pr_or(p$blocked_by, list()))
    if (length(deps) && all(ok[deps] %in% TRUE)) {
      reg$programs[[i]]$status <- "ready"
      reg$programs[[i]]$status_reason <- "선행 조건 완료"
      reg$programs[[i]]$status_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    }
  }
  reg
}

#' 사람이 읽는 상태 몇 줄 — 부팅 · 텔레그램 공용
pr_status_lines <- function(reg = NULL, root = NULL) {
  if (is.null(reg)) reg <- pr_load(root)
  mc <- reg$measurement_contract$items
  n_done <- sum(vapply(mc, function(m) identical(m$status, "done"), logical(1)))
  todo <- vapply(Filter(function(m) !identical(m$status, "done"), mc), function(m) m$id, character(1))
  L <- sprintf("측정 계약 %d/%d 완료%s", n_done, length(mc),
               if (length(todo)) paste0(" · 남은 것 ", paste(todo, collapse = " ")) else "")
  done_ids <- c(vapply(Filter(function(m) identical(m$status, "done"), mc), function(m) m$id, character(1)),
                vapply(Filter(function(q) identical(q$status, "done"), reg$programs), function(q) q$id, character(1)))
  for (p in reg$programs) {
    nq <- length(.pr_or(p$queue, list())); nr <- length(.pr_or(p$rounds, list()))
    rem <- setdiff(unlist(p$blocked_by), done_ids)       # 끝난 선행 조건은 표시에서 뺀다(선언 목록 자체는 보존)
    L <- c(L, sprintf("%s %s — %s · 재료 %d · 라운드 %d%s", p$id, p$name, p$status, nq, nr,
                      if (identical(p$status, "blocked") && length(rem)) paste0(" (남은 선행: ", paste(rem, collapse = " "), ")") else ""))
  }
  nu <- length(.pr_or(reg$paper_routing$unrouted, list()))
  if (nu > 0L) L <- c(L, sprintf("미분류 재료 %d — 라우터 v5 분류 또는 세션 분류 대기(paper_routing.unrouted · pr_route_unrouted)", nu))
  L
}
