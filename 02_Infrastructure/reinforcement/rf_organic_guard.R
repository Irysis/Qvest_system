#==============================================================================
# rf_organic_guard.R — 유기체 헌법 경계 봉쇄 (O0a · 2026-09-25 · 설계 organic_design_final §5 · §3 G2 · 결정 ORGANIC-SCOPE ·
#   REINFORCE-ORGANIC-AUTONOMY "헌법 권한은 불변")
#
# ★왜: 유기체는 자기 파일(06_Registry/organic/**)만 쓰고, 고정 축·문턱·카탈로그·격자·원장·config 에는 쓰기 경로가 없어야 한다.
#   "쓰지 않는다"는 약속이 아니라 여기의 판정(순수 함수 · 쓰기 0)과 rf_organic_write.R::rfo_write(단일 writer)가 막는다.
# 제공(전부 순수 판정 — 부작용 없음 · 위반은 class rfo_k1 조건으로 stop):
#   rfo_schema_load / rfo_schema_check      state.json deny-by-default(허용 최상위 키 · 금지 키 어느 깊이든 · enum · posterior_ref 포인터만 ·
#                                            plan 값 제약 n ∈ [max(n_min, 시도 코드 수), n_cap] · n_cap ≥ 격자 n · B1 절단 금지)
#   rfo_path_allowed                         쓰기 경로 allowlist(schema.json 제외 — 사람 배포) · OneDrive 충돌 사본 탐지
#   rfo_arm_transition_ok / rfo_canonical_status   전이표 · 정본 status(카탈로그 3종 · factor_registry · pit_quarantine active)
#   rfo_snapshot / rfo_snapshot_diff         denylist md5(파일)·stat(트리) 전후 대조(K1 원천)
#   rfo_static_scan                          유기체 R 파일 정적 봉쇄(getParseData 토큰 정확 일치 · 우회 3종: 문자열 결합 · do.call · eval(parse))
# 원칙(설계 §5 끝): 모든 장치는 양성 대조 + 위반 주입 + 돌연변이를 통과해야 방어선에 오른다 — 08_Tests/reinforcement/test_rf_organic_boundary.R.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
## `%||%` — 호출자가 이미 둔 판(러너·이월·결합·사람 명령 스크립트 · 원장의 NA 처리판)을 덮지 않는다(O0a s2 · 2026-09-26): 이 파일이 전역에
##   source 되면 정의 한 줄이 호출자 함수 전부의 `%||%` 의미를 바꾼다(pi0 비트 동일 위협 — rf_combination_launch.R 는 전역 source).
##   보이는 판이 없거나 base 판(R ≥ 4.4 · NULL 만 대체)뿐일 때만 길이 0 도 대체하는 판을 이 파일 환경에 둔다.
if (!exists("%||%", mode = "function") || identical(environmentName(environment(`%||%`)), "base"))
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RFO_DIR_REL    <- "06_Registry/organic"
RFO_SCHEMA_REL <- "06_Registry/organic/schema.json"
# 쓰기 allowlist — 설계 §5 단일 writer 경로 중 rfo_write 몫(시행 로그·결정 기록·레지스터·사전등록은 각자의 writer 가 쓴다).
#   schema.json 은 목록에 없다(사람 배포 · 기계가 자기 스키마를 고치지 못한다).
RFO_WRITE_ALLOW_RE <- c("^06_Registry/organic/state\\.json$", "^06_Registry/organic/actions\\.jsonl$", "^06_Registry/organic/decisions\\.jsonl$",
                        "^06_Registry/organic/(asof|lever_book|scorecard|selftest|flags|runs|report_sent|snapshots)(/[A-Za-z0-9][A-Za-z0-9_.@=-]*)+$")
# denylist — 설계 §5 표(유기체 실행 전후 스냅샷 · 불일치 = K1). kind: file = md5 · glob = 파일별 md5 · tree = (size,mtime) 목록(대형 트리)
RFO_DENYLIST <- list(
  list(kind = "file", path = "02_Infrastructure/worktask/constraint_defaults.json"),
  list(kind = "file", path = "06_Registry/reinforce_program.json"),
  list(kind = "file", path = "06_Registry/a_eligibility_gate.json"),
  list(kind = "file", path = "06_Registry/pit_quarantine.json"),
  list(kind = "file", path = "06_Registry/grade_a_queue.json"),
  list(kind = "file", path = "06_Registry/overlay_catalog.json"),
  list(kind = "file", path = "06_Registry/weight_catalog.json"),
  list(kind = "file", path = "02_Infrastructure/factor_db/factor_registry.json"),
  list(kind = "file", path = ".cache/factor_db/factor_registry.json"),
  list(kind = "file", path = "06_Registry/reinforce_auto_config.json"),
  list(kind = "file", path = "06_Registry/reinforce_ledger_l1.json"),
  list(kind = "file", path = "06_Registry/reinforce_ledger_l2.json"),
  list(kind = "file", path = RFO_SCHEMA_REL),
  list(kind = "glob", path = "qepm/mailbox", pattern = "^judge_request"),
  list(kind = "tree", path = "06_Registry/book"),
  list(kind = "tree", path = "05_Production"),
  list(kind = "tree", path = "01_Literature"),
  list(kind = "tree", path = ".claude"),
  list(kind = "tree", path = "02_Infrastructure/hooks"),
  list(kind = "tree", path = "02_Infrastructure/contracts"))
# 정적 봉쇄 토큰 — 설계 §3 G2(판정 입력 금지) · §5(쓰기 호출 · 권한 밖 writer) · 우회(동적 평가)
RFO_TOK_G2 <- c("essence", "authoritative_remeasure", "essence_grade", "grade", "adversary", "verdict", "oos_retention", "dsr",
                "selection_accounting", "selection_dossier", "rf_load", "reinforce_ledger_l1.json", "reinforce_ledger_l2.json", ".ESSENCE_OOS_SPLITS")
RFO_TOK_WRITE <- c("writeLines", "write", "writeBin", "saveRDS", "save", "fwrite", "write_json", "write.csv", "write.table", "file.rename",
                   "file.copy", "file.create", "unlink", "file.remove", "dir.create", "sink", "cat")
RFO_TOK_AUTHORITY <- c("dr_open", "dr_resolve", "rf_reopen_entry", "register_book_entry", "promote_to_production", "rf_append_attempt",
                       "rf_record_result", "rf_open_entry", "rf_exhaust_entry", "qvest_atomic_write_json", ".rf_write", ".dr_write")
RFO_TOK_DYNAMIC <- c("eval", "evalq", "parse", "str2lang", "str2expression", "get", "get0", "mget", "match.fun", "do.call", "assign",
                     "source", "sys.source", "getFromNamespace", "body<-", "environment<-", "Recall", "system", "system2", "shell")
RFO_CONCAT_FN <- c("paste", "paste0", "sprintf", "file.path", "c", "gsub", "sub", "rev", "toupper", "tolower")

.rfog_s1 <- function(x) { x <- tryCatch(suppressWarnings(as.character(unlist(x %||% ""))), error = function(e) "")
  if (length(x) < 1L || is.na(x[1])) "" else trimws(x[1]) }
rfo_k1 <- function(code, msg) stop(structure(class = c("rfo_k1", "error", "condition"),
                                             list(message = sprintf("[organic·K1 %s] %s", code, msg), call = NULL, code = code)))

# ── 스키마 ───────────────────────────────────────────────────────────────────────────
rfo_schema_load <- function(root) {
  p <- file.path(root, RFO_SCHEMA_REL)
  if (!file.exists(p)) rfo_k1("schema_absent", sprintf("스키마 부재(fail-closed): %s", p))
  s <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(s) || !identical(s$schema, "rf_organic_schema_v1")) rfo_k1("schema_invalid", sprintf("스키마 판독 불가·형식 불일치: %s", p))
  s
}
.rfo_keys_deep <- function(x) { if (!is.list(x)) return(character(0))
  c(names(x)[nzchar(names(x) %||% character(0))], unlist(lapply(x, .rfo_keys_deep), use.names = FALSE)) }
#' 격자 블록 칸 수(n) — reinforce_program.json(읽기만). n_cap 하한 대조용.
rfo_grid_n <- function(root) {
  p <- file.path(root, "06_Registry/reinforce_program.json")
  j <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j)) return(integer(0))
  v <- vapply(j$blocks %||% list(), function(b) as.integer(b$n %||% length(b$cells %||% list())), integer(1))
  names(v) <- vapply(j$blocks %||% list(), function(b) .rfog_s1(b$id), character(1)); v
}
#' state 전체 검사 — list(ok, errors). grid_n 이 주어지면 plan 의 n_cap 하한(격자 n)도 본다.
rfo_schema_check <- function(state, schema, grid_n = NULL) {
  E <- character(0); add <- function(...) E <<- c(E, sprintf(...))
  if (!is.list(state)) return(list(ok = FALSE, errors = "state 가 객체가 아니다"))
  top <- names(state) %||% character(0)
  bad_top <- setdiff(top, unlist(schema$state_top_keys))
  if (length(bad_top)) add("허용 밖 최상위 키: %s", paste(bad_top, collapse = ","))
  fk <- intersect(unique(.rfo_keys_deep(state)), unlist(schema$forbidden_keys))
  if (length(fk)) add("금지 키(고정 축·문턱·N·보류·격리·등급): %s", paste(fk, collapse = ","))
  for (id in names(state$arms %||% list())) {
    st <- .rfog_s1(state$arms[[id]]$status)
    if (!(st %in% unlist(schema$arm_status_enum))) add("arms/%s/status 어휘 밖: %s", id, st)
  }
  for (b in names(state$structure$blocks %||% list())) {
    st <- .rfog_s1(state$structure$blocks[[b]]$state)
    if (!(st %in% unlist(schema$block_state_enum))) add("structure/blocks/%s/state 어휘 밖: %s", b, st)
  }
  pr <- state$posterior_ref
  if (!is.null(pr) && length(setdiff(names(pr) %||% "", unlist(schema$posterior_ref_keys)))) add("posterior_ref 는 포인터·해시만(%s)", paste(unlist(schema$posterior_ref_keys), collapse = ","))
  for (bid in names(state$plan %||% list())) for (blk in names(state$plan[[bid]] %||% list())) {
    v <- state$plan[[bid]][[blk]]; w <- sprintf("plan/%s/%s", bid, blk)
    xk <- setdiff(names(v) %||% character(0), unlist(schema$plan_value_keys))
    if (length(xk)) { add("%s 허용 밖 키: %s", w, paste(xk, collapse = ",")); next }
    n <- suppressWarnings(as.integer(v$n)); cap <- suppressWarnings(as.integer(v$n_cap))
    mn <- suppressWarnings(as.integer(v$n_min %||% 0L)); na <- suppressWarnings(as.integer(v$n_attempted %||% 0L))
    if (!length(n) || is.na(n) || !length(cap) || is.na(cap)) { add("%s n·n_cap 필수", w); next }
    if (n > cap) add("%s n=%d > n_cap=%d(줄이기·복원만 · 칸을 늘리지 못한다)", w, n, cap)
    if (n < max(mn, na, na.rm = TRUE)) add("%s n=%d < max(n_min, 시도 코드 수)=%d(불변식 ① — 시도가 있는 칸을 지우지 않는다)", w, n, max(mn, na, na.rm = TRUE))
    if (!is.null(grid_n) && blk %in% names(grid_n) && cap < grid_n[[blk]]) add("%s n_cap=%d < 격자 n=%d(설계 칸·격자 칸 아래로 상한을 잡지 않는다)", w, cap, grid_n[[blk]])
    if (identical(blk, "B1") && n < cap) add("%s B1 절단 금지(도훈 09-04 '칸 수 제한을 두지 마라')", w)
  }
  list(ok = !length(E), errors = E)
}

# ── 경로 allowlist · 충돌 사본 ─────────────────────────────────────────────────────────
.rfo_rel <- function(root, target) {
  t <- gsub("\\\\", "/", .rfog_s1(target)); r <- gsub("\\\\", "/", normalizePath(root, winslash = "/", mustWork = FALSE))
  if (grepl("^([A-Za-z]:)?/", t)) { tn <- normalizePath(t, winslash = "/", mustWork = FALSE)
    if (!startsWith(tolower(tn), tolower(paste0(r, "/")))) return(NA_character_); t <- substring(tn, nchar(r) + 2L) }
  if (grepl("(^|/)\\.\\.(/|$)", t) || grepl("(^|/)\\./", t)) return(NA_character_)
  t
}
rfo_path_allowed <- function(root, target) {
  rel <- .rfo_rel(root, target)
  !is.na(rel) && any(vapply(RFO_WRITE_ALLOW_RE, function(rx) grepl(rx, rel), logical(1)))
}
#' OneDrive 충돌 사본(*-<PC명>[-n].json/jsonl) — 유기체 디렉터리 안에 있으면 K1(설계 §5 완R11)
rfo_conflict_copies <- function(root, host = Sys.info()[["nodename"]]) {
  d <- file.path(root, RFO_DIR_REL); if (!dir.exists(d)) return(character(0))
  f <- list.files(d, recursive = TRUE, all.files = TRUE)
  h <- tolower(paste0("-", host))   # 고정 문자열 대조(PC 명의 정규식 특수문자 이스케이프 불필요)
  f[vapply(f, function(x) { b <- tolower(basename(x)); grepl("\\.(json|jsonl)$", b) && grepl(h, b, fixed = TRUE) }, logical(1))]
}

# ── 전이표 · 정본 status ───────────────────────────────────────────────────────────────
rfo_arm_transition_ok <- function(from, to, schema) {
  from <- .rfog_s1(from); if (!nzchar(from)) from <- "pi0"
  any(vapply(schema$arm_transitions, function(p) identical(unlist(p), c(from, .rfog_s1(to))), logical(1)))
}
#' 정본 status — 오버레이·비중 카탈로그 · factor_registry(두 벌 중 git 원본) · pit_quarantine(active 항목의 factors·overlay_arms id).
#' @return list(found, status, source, quarantined, managed) — managed = 정본 active 이고 격리·비관리 어휘가 아님
rfo_canonical_status <- function(catalog_id, root, schema) {
  id <- .rfog_s1(catalog_id); rd <- function(p) tryCatch(fromJSON(file.path(root, p), simplifyVector = FALSE), error = function(e) NULL)
  st <- NA_character_; src <- ""
  ov <- rd("06_Registry/overlay_catalog.json")
  for (a in ov$arms %||% list()) if (identical(.rfog_s1(a$id), id)) { st <- .rfog_s1(a$status); src <- "overlay_catalog" }
  if (is.na(st)) { wc <- rd("06_Registry/weight_catalog.json")
    for (a in wc$entries %||% list()) if (identical(.rfog_s1(a$catalog_id), id)) { st <- .rfog_s1(a$status); src <- "weight_catalog" } }
  if (is.na(st)) { fr <- rd("02_Infrastructure/factor_db/factor_registry.json")
    if (is.list(fr) && !is.null(fr[[id]])) { st <- .rfog_s1(fr[[id]]$lifecycle$status %||% fr[[id]]$status); src <- "factor_registry" } }
  q <- rd("06_Registry/pit_quarantine.json"); quar <- FALSE
  for (x in q$quarantines %||% list()) if (identical(.rfog_s1(x$status), "active")) {
    ids <- unlist(lapply(c(x$factors %||% list(), x$overlay_arms %||% list()), function(z) .rfog_s1(if (is.list(z)) z$id else z)))
    if (id %in% ids) quar <- TRUE
  }
  found <- !is.na(st)
  list(found = found, status = if (found) st else "absent", source = src, quarantined = quar,
       managed = found && identical(st, "active") && !quar && !(st %in% unlist(schema$unmanaged_canonical_status)))
}

# ── denylist 스냅샷 ───────────────────────────────────────────────────────────────────
rfo_snapshot <- function(root, spec = RFO_DENYLIST) {
  out <- character(0)
  for (s in spec) {
    p <- file.path(root, s$path)
    if (identical(s$kind, "file")) { out[s$path] <- if (file.exists(p)) paste0("md5:", unname(tools::md5sum(p))) else "absent"; next }
    if (!dir.exists(p)) { out[s$path] <- "absent"; next }
    f <- list.files(p, recursive = identical(s$kind, "tree"), all.files = TRUE, full.names = TRUE, no.. = TRUE)
    f <- f[!dir.exists(f)]
    if (identical(s$kind, "glob")) f <- f[grepl(s$pattern, basename(f))]
    if (!length(f)) { out[paste0(s$path, "/")] <- "empty"; next }
    rel <- substring(gsub("\\\\", "/", f), nchar(gsub("\\\\", "/", root)) + 2L)
    v <- if (identical(s$kind, "glob")) paste0("md5:", unname(tools::md5sum(f))) else {
      fi <- file.info(f); sprintf("stat:%s:%s", fi$size, format(as.numeric(fi$mtime), digits = 15)) }
    out[rel] <- v
  }
  out
}
rfo_snapshot_diff <- function(a, b) {
  k <- union(names(a), names(b))
  ch <- k[vapply(k, function(x) !identical(unname(a[x]), unname(b[x])), logical(1))]
  list(changed = ch, same = !length(ch))
}

# ── 정적 봉쇄 ─────────────────────────────────────────────────────────────────────────
#' 유기체 R 파일 정적 검사. role:
#'   decision — view·model·policy·replay: G2 토큰 · 쓰기 호출 · 권한 밖 writer · 동적 평가 · 문자열 결합 우회 전부 금지
#'   adapter  — rf_organic_ledger_adapter.R: G2 토큰 면제(유일한 원장 판독 파일 · 대신 열 허용목록) · 나머지 금지
#'   writer   — rf_organic_write.R: 쓰기 호출은 writer_fns 안에서만 · 권한 밖 writer·동적 평가·결합 우회 금지 · G2 토큰 금지
#'   guard    — rf_organic_guard.R: denylist·금지 토큰 목록 자체를 담으므로 G2 면제 · 쓰기 0 · 동적 평가 금지(자기 검사 제외 규칙은 없다)
#' @return list(ok, violations = data.frame(file, line, kind, token))
rfo_static_scan <- function(file, role = c("decision", "adapter", "writer", "guard"), writer_fns = character(0)) {
  role <- match.arg(role)
  pd <- tryCatch(utils::getParseData(parse(file, encoding = "UTF-8", keep.source = TRUE), includeText = TRUE), error = function(e) NULL)
  V <- list(); addv <- function(line, kind, token) V[[length(V) + 1L]] <<- data.frame(file = basename(file), line = line, kind = kind, token = token, stringsAsFactors = FALSE)
  if (is.null(pd)) { addv(NA_integer_, "parse_error", ""); return(list(ok = FALSE, violations = do.call(rbind, V))) }
  unq <- function(s) gsub('^["\']|["\']$', "", s)
  tok <- pd[pd$terminal, c("id", "parent", "line1", "token", "text")]
  sym <- tok[tok$token %in% c("SYMBOL", "SYMBOL_FUNCTION_CALL", "SLOT"), ]
  str <- tok[tok$token == "STR_CONST", ]; str$val <- unq(str$text)
  # 쓰기 호출의 소속 함수(최상위 `name <- function`) — 행 범위로 판정
  tops <- pd[pd$parent == 0 & pd$token == "expr", c("id", "line1", "line2", "text")]
  owner_of <- function(line) { k <- which(tops$line1 <= line & tops$line2 >= line)
    if (!length(k)) return(""); m <- regmatches(tops$text[k[1]], regexpr("^[`]?[.A-Za-z_][.A-Za-z0-9_]*[`]?\\s*(<-|=)\\s*function", tops$text[k[1]]))
    if (length(m)) gsub("[` ]|(<-|=)\\s*function$", "", sub("\\s*(<-|=)\\s*function$", "", m)) else "" }
  g2 <- if (role %in% c("decision", "writer")) RFO_TOK_G2 else character(0)
  kids <- function(pid) { k <- pd$id[pd$parent == pid]; c(k, unlist(lapply(k, kids))) }
  call_of <- function(tid) pd$parent[pd$id == pd$parent[pd$id == tid]]          # SYMBOL_FUNCTION_CALL → expr(이름) → expr(호출)
  has_arg <- function(tid, nm) { cid <- call_of(tid); any(pd$token[pd$parent == cid] == "SYMBOL_SUB" & pd$text[pd$parent == cid] == nm) }
  # 코드 적재(source·sys.source)는 원장·관문 판독 라이브러리를 사적 env 로 싣는 판독 파일(adapter·writer·guard)에만 허용 — 결정 파일은 금지
  dyn <- if (identical(role, "decision")) RFO_TOK_DYNAMIC else setdiff(RFO_TOK_DYNAMIC, c("source", "sys.source"))
  # do.call 의 첫 인자가 무해한 결합 함수 기호(rbind 등)면 동적 호출이 아니다 — 문자열·계산된 함수만 위반
  benign_fn <- c("rbind", "cbind", "c", "rbind.data.frame", "list", "paste", "paste0", "data.frame", "mapply", "Map", "sum", "max", "min")
  first_arg_sym <- function(tid) { cid <- call_of(tid); d <- pd[pd$id %in% kids(cid) & pd$terminal, c("line1", "col1", "token", "text")]
    d <- d[order(d$line1, d$col1), ]; k <- which(d$token == "'('")[1]
    if (is.na(k) || k + 2L > nrow(d)) return("")
    if (identical(d$token[k + 1L], "SYMBOL") && d$token[k + 2L] %in% c("','", "')'")) d$text[k + 1L] else "" }
  for (i in seq_len(nrow(sym))) {
    t <- sym$text[i]; is_call <- identical(sym$token[i], "SYMBOL_FUNCTION_CALL")
    if (t %in% g2) addv(sym$line1[i], "g2_token", t)
    if (t %in% RFO_TOK_AUTHORITY) addv(sym$line1[i], "authority_writer", t)
    if (is_call && identical(t, "do.call") && first_arg_sym(sym$id[i]) %in% benign_fn) next
    if (is_call && t %in% dyn && !identical(t, "parse")) addv(sym$line1[i], "dynamic_eval", t)
    if (is_call && identical(t, "parse") && has_arg(sym$id[i], "text")) addv(sym$line1[i], "dynamic_eval", "parse(text=)")   # 파일 판독용 parse(file) 는 허용
    if (is_call && t %in% RFO_TOK_WRITE && !(identical(t, "cat") && !has_arg(sym$id[i], "file"))) {   # cat 은 file= 일 때만 쓰기
      ow <- owner_of(sym$line1[i])
      if (!(identical(role, "writer") && ow %in% writer_fns)) addv(sym$line1[i], "write_call", sprintf("%s@%s", t, if (nzchar(ow)) ow else "top"))
    }
  }
  for (i in seq_len(nrow(str))) {
    v <- str$val[i]
    if (v %in% g2) addv(str$line1[i], "g2_string", v)
    # do.call("dr_resolve") · match.fun("eval") 류 — guard 는 금지 토큰 목록 자체를 문자열로 담으므로 제외(대신 동적 평가 호출 0 이 검사된다)
    if (!identical(role, "guard") && v %in% c(RFO_TOK_AUTHORITY, dyn)) addv(str$line1[i], "string_call_name", v)
  }
  # 문자열 결합 우회 — 결합 함수 호출의 문자열 인자를 이어 붙였을 때 금지 토큰이 **새로** 생기면 위반(한 인자에 이미 있으면 위에서 잡힌다).
  #   동적 평가 이름은 오탐이 적은 긴 것만(eval·parse·get 은 평문 단어 안에 흔하다 — 그 호출 자체는 위 토큰 검사가 잡는다).
  fc <- tok[tok$token == "SYMBOL_FUNCTION_CALL" & tok$text %in% RFO_CONCAT_FN, ]
  banned <- unique(c(g2, RFO_TOK_AUTHORITY, intersect(dyn, c("do.call", "match.fun", "getFromNamespace", "str2lang", "str2expression", "sys.source"))))
  for (i in seq_len(nrow(fc))) {
    call_id <- call_of(fc$id[i])
    ss <- str[str$id %in% kids(call_id), ]; if (nrow(ss) < 2L) next
    joined <- tolower(paste(ss$val[order(ss$id)], collapse = ""))
    for (b in banned) if (grepl(tolower(b), joined, fixed = TRUE) && !any(grepl(tolower(b), tolower(ss$val), fixed = TRUE)))
      addv(fc$line1[i], "concat_bypass", b)
  }
  vv <- if (length(V)) do.call(rbind, V) else data.frame(file = character(0), line = integer(0), kind = character(0), token = character(0))
  list(ok = !nrow(vv), violations = vv)
}
