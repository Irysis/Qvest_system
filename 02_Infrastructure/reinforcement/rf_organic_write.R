#==============================================================================
# rf_organic_write.R — 유기체 **단일 writer** (O0a · 2026-09-25 · 설계 organic_design_final §5 · §3 G1 write-ahead · G6 롤백)
#
# ★왜: 유기체가 쓰는 곳은 06_Registry/organic/** 하나다. 그 밖(격자·카탈로그·등록부·원장·config·고정 축·문턱)은 쓰기 경로 자체가 없어야
#   한다(결정 ORGANIC-SCOPE "정본 카탈로그·팩터 등록부·격자·원장·config 기계 쓰기 금지"). 이 파일이 유일한 쓰기 함수(rfo_write)를 두고,
#   모든 쓰기 앞에서 ① 경로 allowlist ② 충돌 사본(K1) ③ write-ahead(시행 로그 선행 레코드 · K2) ④ 스키마·값 제약·전이표(K1)를 본다.
#   state.json 은 임시 파일 → 재파싱 검증 → rename(원자) → 재적재 대조. 성공한 쓰기마다 actions.jsonl 에 1행(G6 롤백 원장).
# 계약:
#   · rfo_write(target, value, decision_id, pointer = NULL) — target 은 저장소 상대 경로. state.json 은 pointer("a/b/c") 단위 갱신,
#     *.jsonl 은 append(value = 레코드 1개), 그 밖 허용 경로(*.json)는 통째 쓰기. 반환 = list(ok, target, pointer, before, after).
#   · decision_id 에 선행 시행 레코드(reinforce_ledger.R::rf_trial_log_has)가 없으면 거부(class rfo_k2) — 효과보다 기록이 먼저다.
#   · 경로·스키마·전이표 위반 = class rfo_k1(rf_organic_guard.R::rfo_k1) — 호출자(O1 tick)가 전 층 off + 즉시 경보로 바꾼다.
#   · rfo_rollback(decision_id, rollback_decision_id) — 그 결정의 actions 행을 역순으로 되돌린다(state 포인터만 · 원장·측정은 대상 아님).
#     rollback_decision_id 의 시행 레코드(organic_rollback)가 선행해야 한다. 러너가 실현한 소진은 되돌리지 않는다 → reopen_required 로 알린다.
#   · 이 파일은 원장·측정·등급을 읽지 않는다(시행 로그 판독 함수 1개만 원장 파일에서 정의 추출 · 정적 봉쇄 writer 역할).
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
## `%||%` — 호출자가 이미 둔 판(러너·이월·결합·사람 명령 스크립트 · 원장의 NA 처리판)을 덮지 않는다(O0a s2 · 2026-09-26): 이 파일이 전역에
##   source 되면 정의 한 줄이 호출자 함수 전부의 `%||%` 의미를 바꾼다(pi0 비트 동일 위협 — rf_combination_launch.R 는 전역 source).
##   보이는 판이 없거나 base 판(R ≥ 4.4 · NULL 만 대체)뿐일 때만 길이 0 도 대체하는 판을 이 파일 환경에 둔다.
if (!exists("%||%", mode = "function") || identical(environmentName(environment(`%||%`)), "base"))
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RFO_WRITER_FNS <- c(".rfo_atomic_json", ".rfo_append_line")    # 정적 봉쇄(writer 역할)가 쓰기 호출을 허용하는 함수 — 이 둘뿐

.rfow_env <- new.env(parent = emptyenv())
#' 판독 라이브러리 적재 — 경계 판정(rf_organic_guard.R)과 시행 로그 판독(reinforce_ledger.R::rf_trial_log_has · 사적 env — 쓰기 함수는 부르지 않는다)
.rfow_libs <- function(root) {
  if (!is.null(.rfow_env$root) && identical(.rfow_env$root, root)) return(invisible(TRUE))
  g <- new.env(parent = globalenv())
  sys.source(file.path(root, "02_Infrastructure/reinforcement/rf_organic_guard.R"), envir = g, keep.source = FALSE)
  l <- new.env(parent = globalenv())
  invisible(utils::capture.output(sys.source(file.path(root, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = l, keep.source = FALSE)))
  want <- c("rf_trial_log_path", "rf_trial_log_has")
  if (!all(vapply(want, exists, logical(1), envir = l, inherits = FALSE))) stop("[rf_organic_write] 시행 로그 판독 정의 부재(reinforce_ledger.R 판본 확인)")
  .rfow_env$g <- g; .rfow_env$l <- l; .rfow_env$root <- root
  invisible(TRUE)
}
.rfow_s1 <- function(x) { x <- tryCatch(suppressWarnings(as.character(unlist(x %||% ""))), error = function(e) "")
  if (length(x) < 1L || is.na(x[1])) "" else trimws(x[1]) }
.rfow_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# ── 쓰기 원시(정적 봉쇄가 쓰기 호출을 허용하는 유일한 두 함수) ──────────────────────────────
.rfo_atomic_json <- function(path, obj) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  txt <- toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)
  chk <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk)) stop("[rf_organic_write] 직렬화 재파싱 실패 — 쓰지 않는다")
  tmp <- file.path(dirname(path), sprintf(".%s.tmp%d", basename(path), Sys.getpid()))
  writeLines(txt, tmp, useBytes = TRUE)
  ok <- FALSE
  for (i in 1:8) { if (isTRUE(suppressWarnings(file.rename(tmp, path)))) { ok <- TRUE; break }; Sys.sleep(0.02 * 2^(i - 1)) }
  if (!ok) { suppressWarnings(file.remove(tmp)); stop("[rf_organic_write] 원자 rename 실패 — 쓰지 않았다: ", path) }
  back <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (!identical(back, chk)) stop("[rf_organic_write] 쓰기 뒤 재적재 대조 실패: ", path)
  invisible(path)
}
.rfo_append_line <- function(path, rec) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  txt <- as.character(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
  if (is.null(tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL))) stop("[rf_organic_write] 레코드 재파싱 실패 — 쓰지 않는다")
  con <- file(path, open = "ab"); on.exit(close(con), add = TRUE)
  writeBin(charToRaw(enc2utf8(paste0(txt, "\n"))), con)
  invisible(path)
}

# ── state 포인터 ──────────────────────────────────────────────────────────────────────
.rfo_ptr <- function(p) { s <- strsplit(.rfow_s1(p), "/", fixed = TRUE)[[1]]; s[nzchar(s)] }
.rfo_get <- function(x, keys) { for (k in keys) { if (!is.list(x) || is.null(x[[k]])) return(NULL); x <- x[[k]] }; x }
.rfo_set <- function(x, keys, v) {
  if (!length(keys)) return(v)
  if (!is.list(x)) x <- list()
  x[[keys[1]]] <- .rfo_set(x[[keys[1]]], keys[-1], v)
  x
}
rfo_state_path <- function(root) file.path(root, "06_Registry/organic/state.json")
rfo_state_load <- function(root) {
  p <- rfo_state_path(root)
  if (!file.exists(p)) return(list(schema_version = "rf_organic_state_v1"))
  s <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(s)) stop("[rf_organic_write] state.json 파손 — 빈 상태로 접지 않는다(fail-closed)")
  s
}

#' 단일 writer. actor = "machine"(유기체 tick) | "human"(ops/rf_organic_cmd.R) — 둘 다 같은 관문을 지난다.
rfo_write <- function(target, value, decision_id, pointer = NULL, root, layer = "", policy = NULL, actor = "machine", note = "") {
  .rfow_libs(root); G <- .rfow_env$g; L <- .rfow_env$l
  rel <- G$.rfo_rel(root, target)
  if (is.na(rel) || !G$rfo_path_allowed(root, rel))
    G$rfo_k1("path_denied", sprintf("allowlist 밖 쓰기 시도: %s (유기체는 06_Registry/organic/** 만 쓴다 · schema.json 은 사람 배포)", .rfow_s1(target)))
  cc <- G$rfo_conflict_copies(root)
  if (length(cc)) G$rfo_k1("onedrive_conflict", sprintf("OneDrive 충돌 사본 %s — 쓰지 않는다", paste(cc, collapse = ",")))
  did <- .rfow_s1(decision_id)
  if (!nzchar(did) || !isTRUE(L$rf_trial_log_has(did, root)))
    stop(structure(class = c("rfo_k2", "error", "condition"),
                   list(message = sprintf("[organic·K2] 선행 시행 레코드 없음(write-ahead 위반): decision_id=%s — 효과보다 기록이 먼저다", did), call = NULL)))
  path <- file.path(root, rel); before <- NULL; after <- value
  if (identical(rel, "06_Registry/organic/state.json")) {
    keys <- .rfo_ptr(pointer); if (!length(keys)) G$rfo_k1("pointer_empty", "state.json 은 포인터 단위로만 쓴다(통째 덮어쓰기 금지)")
    S <- G$rfo_schema_load(root); st <- rfo_state_load(root)
    before <- .rfo_get(st, keys)
    if (identical(keys[1], "arms") && length(keys) >= 2L) {                  # 전이표 · 정본 관리 대상 여부
      cs <- G$rfo_canonical_status(keys[2], root, S)
      if (!isTRUE(cs$managed))
        G$rfo_k1("arm_unmanaged", sprintf("arms/%s — 정본 %s(%s)%s: 관리 대상 아님(부활·휴면 금지)", keys[2], cs$status, cs$source, if (cs$quarantined) " · PIT 격리" else ""))
      to <- if (length(keys) == 2L) .rfow_s1(if (is.list(value)) value$status else "") else if (identical(keys[3], "status")) .rfow_s1(value) else ""
      from <- if (length(keys) == 2L) .rfow_s1(if (is.list(before)) before$status else "") else .rfow_s1(.rfo_get(st, c(keys[1:2], "status")))
      if (length(keys) > 3L || (length(keys) == 3L && !(keys[3] %in% c("status", "since", "reason", "decision_id", "probe"))))
        G$rfo_k1("arm_field", sprintf("arms/%s/%s — 허용 필드 밖", keys[2], paste(keys[-(1:2)], collapse = "/")))
      if (nzchar(to) && !G$rfo_arm_transition_ok(from, to, S))
        G$rfo_k1("arm_transition", sprintf("arms/%s 전이 %s → %s 는 전이표 밖", keys[2], if (nzchar(from)) from else "pi0", to))
    }
    st2 <- .rfo_set(st, keys, value); st2$updated_at <- .rfow_now(); st2$schema_version <- st2$schema_version %||% "rf_organic_state_v1"
    chk <- G$rfo_schema_check(st2, S, grid_n = G$rfo_grid_n(root))
    if (!isTRUE(chk$ok)) G$rfo_k1("schema", paste(chk$errors, collapse = " | "))
    .rfo_atomic_json(path, st2)
  } else if (grepl("\\.jsonl$", rel)) {
    .rfo_append_line(path, value)
  } else {
    if (file.exists(path)) before <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    .rfo_atomic_json(path, value)
  }
  if (!identical(rel, "06_Registry/organic/actions.jsonl"))
    .rfo_append_line(file.path(root, "06_Registry/organic/actions.jsonl"),
                     list(decision_id = did, at = .rfow_now(), layer = .rfow_s1(layer), target = rel, pointer = .rfow_s1(pointer),
                          before = before, after = after, policy = policy, actor = .rfow_s1(actor), note = .rfow_s1(note)))
  invisible(list(ok = TRUE, target = rel, pointer = .rfow_s1(pointer), before = before, after = after))
}

#' 롤백 — decision_id 의 state 포인터 쓰기를 역순으로 before 값으로 되돌린다. 원장·측정은 대상이 아니다(애초에 쓰지 않았다).
#' @return list(n_restored, targets, reopen_required = 이 결정 뒤 소진된 entry 가 있으면 사람 호출 rf_reopen_entry 안내 문구)
rfo_rollback <- function(decision_id, rollback_decision_id, root, actor = "human") {
  .rfow_libs(root); G <- .rfow_env$g
  ap <- file.path(root, "06_Registry/organic/actions.jsonl")
  A <- if (file.exists(ap)) Filter(Negate(is.null), lapply(readLines(ap, warn = FALSE, encoding = "UTF-8"),
                                                           function(l) tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL))) else list()
  mine <- Filter(function(a) identical(.rfow_s1(a$decision_id), .rfow_s1(decision_id)), A)
  if (!length(mine)) stop(sprintf("[rf_organic_write] 롤백 대상 결정의 효과 기록 없음: %s", decision_id))
  bad <- Filter(function(a) !G$rfo_path_allowed(root, a$target), mine)
  if (length(bad)) G$rfo_k1("rollback_target", sprintf("롤백 대상이 유기체 경로 밖: %s", paste(vapply(bad, function(a) .rfow_s1(a$target), character(1)), collapse = ",")))
  n <- 0L; tg <- character(0)
  for (a in rev(mine)) {
    if (!identical(.rfow_s1(a$target), "06_Registry/organic/state.json")) next   # append 로그는 되돌리지 않는다(append-only 이력)
    rfo_write("06_Registry/organic/state.json", a$before, rollback_decision_id, pointer = a$pointer, root = root, layer = a$layer,
              actor = actor, note = sprintf("rollback of %s", decision_id))
    n <- n + 1L; tg <- c(tg, .rfow_s1(a$pointer))
  }
  list(n_restored = n, targets = tg,
       reopen_required = "이 결정 뒤 러너가 격자 소진(grid_consumed)으로 닫은 entry 가 있으면 사람 호출: Rscript 02_Infrastructure/ops/rf_organic_cmd.R reopen-entry <base_id> <decision_id> <reason>")
}
