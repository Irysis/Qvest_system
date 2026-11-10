## round_core v1 · outcomes — 결과 원장(라운드가 닫힐 때 남기는 '다음 설계의 입력') · v10.2 사다리 루프의 재귀 고리(2026-11-10)
##
## 왜: 닫힌 10라운드 가운데 교훈 기록은 1건, 다음 탐침의 소비 기록은 0건이었다(전수점검 L8). 라운드가 무엇을 배웠고 다음에 무엇을
##   잴지가 세션의 기억과 긴 보고서에만 남아, 다음 라운드가 앞 라운드에서 출발한다는 보증이 없었다.
## 무엇: 06_Registry/round_outcomes.jsonl — 추가 전용 · 한 줄 한 사건.
##   kind = "round"          라운드 종료(판정 라벨 · 해석 · 다음 탐침 ≥ 2 · 교훈 · 목표 축 판독 r7 · 측정 축 · 시행 수)
##   kind = "probe_consumed" 다음 탐침을 어느 라운드가 이어받았는가(ref = "<round_id>#<번호>")
## 정보 경계: 글 칸(해석 · 탐침 · 교훈 · 라벨)에 τ_D 뒤 날짜가 있으면 쓰지 않고 멈춘다 — 이 원장은 다음 설계의 입력이다(교훈 카드와 같은 규율).
## 판정기와의 관계: 이 원장은 생성기(다음 라운드 설계 · 처방)의 입력일 뿐이다. 판정 규칙 · 등급 · 사전등록은 건드리지 않는다.

RC_OUTCOME_SCHEMA <- "round_outcome_v1"
RC_R7_VOCAB <- c("noise", "signal")          # 목표 축 판독(R7): 개선이 잡음 이내 = noise · 잡음 밖 = signal · 판독 없음 = NA

## 원장 경로 — 격리 등록부(registry_path)를 쓰는 호출은 그 옆에 쓴다(시험이 운영 원장에 닿지 않게)
rc_outcomes_path <- function(root = rc_root(), registry_path = NULL) {
  if (!is.null(registry_path)) file.path(dirname(registry_path), "round_outcomes.jsonl") else file.path(root, "06_Registry", "round_outcomes.jsonl")
}

.rc_outcome_write <- function(rec, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  line <- as.character(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
  con <- file(path, open = "ab"); on.exit(close(con), add = TRUE)
  writeLines(enc2utf8(line), con, useBytes = TRUE)
  invisible(rec)
}

## 읽기 — 못 읽는 줄이 있으면 멈춘다(추가 전용 파일의 손상은 조용히 건너뛰지 않는다)
## 격리(11-10 · 감사 K P6) — 원장은 추가 전용이라 손상 줄을 지우지 않는다. 사람(세션)이 rc_outcomes_quarantine 을 명시적으로 부르면
##   그 줄의 md5 를 담은 kind = "quarantine" 줄이 원장 끝에 붙고, 원본 줄은 옆 파일 <원장>.quarantine.jsonl 에 사본으로 남는다.
##   읽기는 격리된 md5 의 줄을 건너뛴다(경고). 격리되지 않은 손상 줄은 지금처럼 멈춘다(조용히 건너뛰지 않는다).
.rc_outcome_md5 <- function(s) .rcs_md5s(s)
rc_outcomes_quarantined <- function(L) {
  q <- character(0)
  for (s in L) if (grepl("\"kind\":\"quarantine\"", s, fixed = TRUE)) { x <- tryCatch(jsonlite::fromJSON(s, simplifyVector = FALSE), error = function(e) NULL)
    if (identical(x$schema, RC_OUTCOME_SCHEMA) && identical(x$kind, "quarantine")) q <- c(q, as.character(unlist(x$line_md5))) }
  q
}
rc_outcomes_quarantine <- function(path, line, reason) {
  if (!(is.character(reason) && length(reason) == 1L && nzchar(trimws(reason)))) stop("[round_core outcomes] 격리 사유 없음")
  L <- readLines(path, warn = FALSE, encoding = "UTF-8"); ix <- which(nzchar(trimws(L)))
  line <- as.integer(line); if (length(line) != 1L || is.na(line) || line < 1L || line > length(ix)) stop("[round_core outcomes] 그런 줄이 없다(빈 줄 제외 번호): ", line)
  s <- L[ix[line]]; m <- .rc_outcome_md5(s)
  if (m %in% rc_outcomes_quarantined(L)) stop("[round_core outcomes] 이미 격리된 줄이다: ", line)
  side <- paste0(path, ".quarantine.jsonl"); con <- file(side, open = "ab"); writeBin(charToRaw(paste0(s, "\n")), con); close(con)
  .rc_outcome_write(list(schema = RC_OUTCOME_SCHEMA, kind = "quarantine", at = rc_now(), line_no = line, line_md5 = m, reason = reason,
                         copy = basename(side)), path)
  invisible(m)
}
rc_outcomes_read <- function(path, program = NULL, kind = "round", tau_clean = NULL) {
  if (!file.exists(path)) return(list())
  L <- readLines(path, warn = FALSE, encoding = "UTF-8"); L <- L[nzchar(trimws(L))]
  qd <- rc_outcomes_quarantined(L)
  if (length(qd)) { keep <- !(vapply(L, .rc_outcome_md5, "") %in% qd); if (any(!keep)) warning(sprintf("[round_core outcomes] 격리된 줄 %d개를 건너뛴다: %s", sum(!keep), path)); L <- L[keep] }
  out <- lapply(L, function(s) tryCatch(jsonlite::fromJSON(s, simplifyVector = FALSE), error = function(e) NULL))
  bad <- sum(vapply(out, is.null, logical(1)))
  if (bad) stop(sprintf("[round_core outcomes] 원장 %d줄 판독 불가 — 손상(추가 전용 파일 · 격리 = rc_outcomes_quarantine / round.sh - outcomes-quarantine): %s", bad, path))
  out <- Filter(function(x) identical(x$schema, RC_OUTCOME_SCHEMA), out)
  ## 처방 입력 경로(tau_clean 지정) — 검사를 통과하지 못한 옛 줄(쓰기 검사 강화 전에 들어간 등급 표기 · 날짜 변형)은 그 줄만 건너뛴다(경고 · 원장 그대로)
  if (!is.null(tau_clean)) {
    dirty <- vapply(out, function(x) identical(x$kind %||% "round", "round") &&
                      !isTRUE(rc_input_issues(list(x$note, x$probes, x$lessons, x$verdict_label, x$no_probes_reason %||% ""), tau_clean)$ok), logical(1))
    if (any(dirty)) { warning(sprintf("[round_core outcomes] 처방 입력 검사 미통과 줄 %d개를 설계 입력에서 뺀다(%s) — 격리하려면 rc_outcomes_quarantine",
                                      sum(dirty), paste(vapply(out[dirty], function(x) as.character(x$round_id %||% "?"), ""), collapse = ","))); out <- out[!dirty] }
  }
  if (!is.null(kind)) out <- Filter(function(x) identical(x$kind %||% "round", kind), out)
  if (!is.null(program)) out <- Filter(function(x) identical(x$program, program), out)
  out
}

## 종료 기록 만들기 — 다음 탐침 2개 이상(없으면 사유) · r7 어휘 · τ_D 날짜 검사
rc_outcome_record <- function(spec, V, note, probes = character(0), lessons = character(0), r7 = NA_character_,
                              no_probes_reason = NULL, P, root = rc_root()) {
  probes <- trimws(as.character(unlist(probes))); probes <- probes[nzchar(probes)]
  lessons <- trimws(as.character(unlist(lessons))); lessons <- lessons[nzchar(lessons)]
  if (length(probes) < 2L && !(is.character(no_probes_reason) && length(no_probes_reason) == 1L && nzchar(trimws(no_probes_reason))))
    stop("[round_core close] 다음 탐침이 2개 미만이다 — --probe 를 2개 이상 주거나, 이어 갈 것이 없으면 --no-probes \"<사유>\" (lean-loop 교훈 단계)")
  r7 <- as.character(r7)[1]
  if (!is.na(r7) && !(r7 %in% RC_R7_VOCAB)) stop("[round_core close] --r7 어휘 밖: ", r7, " (", paste(RC_R7_VOCAB, collapse = " | "), ")")
  tau <- as.Date(spec[["tau_d"]])
  label <- as.character((V$summary %||% list())$label %||% NA_character_)
  leaks <- rc_after_tau_leaks(list(note, as.list(probes), as.list(lessons), label, no_probes_reason %||% ""), tau)
  if (length(leaks)) stop("[round_core close] 결과 원장 글에 정보 경계 뒤 날짜가 있다 — 쓰지 않는다: ", paste(leaks, collapse = ", "))
  ## 읽기(설계 입력 · 생성기 검토)와 같은 검사(11-10 · 감사 K P1) — 받아들인 줄은 반드시 읽힌다
  ci <- rc_input_issues(list(note, as.list(probes), as.list(lessons), label, no_probes_reason %||% ""), tau)
  if (!isTRUE(ci$ok)) stop("[round_core close] 결과 원장 글에 처방 입력 금지 정보(", ci$why, ") — 쓰지 않는다(다음 설계 입력이 읽는 자리)")
  cells <- spec[["cells"]] %||% list()
  list(schema = RC_OUTCOME_SCHEMA, kind = "round", at = rc_now(), program = spec[["program"]], round_id = spec[["round_id"]],
       template = spec[["template"]], core = RC_VERSION,
       epoch = tryCatch(as.character(rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::measurement_axis.active", root)),
                        error = function(e) NA_character_),
       tau_d = as.character(tau), verdict_label = label,
       n_cells = length(cells), n_variants = sum(vapply(cells, function(c) identical(c[["role"]], "variant"), logical(1))),
       note = note, probes = as.list(probes), no_probes_reason = no_probes_reason, lessons = as.list(lessons), r7 = r7,
       prereg_md5 = rc_md5(P$prereg), report = rc_rel(file.path(P$results, "verdict.json"), root))
}

## 같은 라운드를 두 번 닫아도 원장에는 한 번만(등록부는 덮어 쓰지만 원장은 추가 전용이다)
rc_outcome_append_round <- function(rec, path) {
  ex <- rc_outcomes_read(path, kind = "round")
  if (any(vapply(ex, function(x) identical(x$round_id, rec$round_id) && identical(x$prereg_md5, rec$prereg_md5), logical(1)))) return(invisible(FALSE))
  .rc_outcome_write(rec, path); invisible(TRUE)
}

## 다음 탐침 소비 — ref = "<round_id>#<번호>" 가 원장에 있어야 한다 · 같은 탐침을 두 라운드가 이어받지 않는다
rc_probe_consume <- function(ref, by_round, path) {
  m <- regmatches(ref, regexec("^(.+)#([0-9]+)$", ref, perl = TRUE))[[1]]
  if (length(m) != 3L) stop("[round_core outcomes] 탐침 참조 형식은 '<round_id>#<번호>': ", ref)
  src <- Filter(function(x) identical(x$round_id, m[2]), rc_outcomes_read(path, kind = "round"))
  i <- as.integer(m[3])
  if (!length(src) || i < 1L || i > length(src[[length(src)]]$probes)) stop("[round_core outcomes] 원장에 없는 탐침: ", ref)
  used <- rc_outcomes_read(path, kind = "probe_consumed")
  if (any(vapply(used, function(x) identical(x$ref, ref), logical(1)))) stop("[round_core outcomes] 이미 이어받은 탐침: ", ref)
  .rc_outcome_write(list(schema = RC_OUTCOME_SCHEMA, kind = "probe_consumed", at = rc_now(), ref = ref, by = by_round,
                         program = src[[length(src)]]$program), path)
}

## 아직 아무도 이어받지 않은 탐침(프로그램별) — 다음 라운드 설계의 출발점
rc_open_probes <- function(path, program = NULL, tau_clean = NULL) {
  used <- vapply(rc_outcomes_read(path, kind = "probe_consumed"), function(x) as.character(x$ref), character(1))
  out <- list()
  for (r in rc_outcomes_read(path, program = program, kind = "round", tau_clean = tau_clean)) for (i in seq_along(r$probes)) {
    ref <- sprintf("%s#%d", r$round_id, i)
    if (!(ref %in% used)) out[[length(out) + 1L]] <- list(ref = ref, program = r$program, text = as.character(r$probes[[i]]))
  }
  out
}

## 목표 축 예산(R7) — 프로그램의 최근 라운드가 연속으로 '잡음 이내'였던 수(판독 없는 라운드는 연속을 끊지도 잇지도 않는다)
rc_r7_streak <- function(path, program) {
  rs <- Filter(function(x) !is.null(x$r7) && !is.na(x$r7), rc_outcomes_read(path, program = program, kind = "round"))
  n <- 0L
  for (x in rev(rs)) { if (identical(x$r7, "noise")) n <- n + 1L else break }
  n
}

## 다음 설계의 입력(markdown) — DESIGN 의 '앞선 라운드에서 배운 것' 절에 그대로 붙인다(글은 이미 τ_D 검사를 통과한 것만 원장에 있다)
rc_outcomes_md <- function(path, program = NULL, last = 5L, tau_clean = NULL) {
  rs <- rc_outcomes_read(path, program = program, kind = "round", tau_clean = tau_clean)
  if (!length(rs)) return("(결과 원장에 닫힌 라운드가 없다)")
  rs <- utils::tail(rs, last)
  open <- vapply(rc_open_probes(path, program, tau_clean = tau_clean), function(x) x$ref, character(1))
  L <- character(0)
  for (r in rs) {
    L <- c(L, sprintf("- **%s** (%s · 칸 %d · 변형 %d%s) — %s", r$round_id, r$program, r$n_cells %||% 0L, r$n_variants %||% 0L,
                      if (!is.null(r$r7) && !is.na(r$r7)) paste0(" · 목표 축 판독 ", r$r7) else "", r$verdict_label %||% "판정 라벨 없음"),
           sprintf("  - 해석: %s", r$note %||% ""))
    for (z in r$lessons) L <- c(L, sprintf("  - 교훈: %s", z))
    for (i in seq_along(r$probes)) {
      ref <- sprintf("%s#%d", r$round_id, i)
      L <- c(L, sprintf("  - 다음 탐침 %s%s: %s", ref, if (ref %in% open) "" else " (이어받음)", r$probes[[i]]))
    }
    if (!length(r$probes) && !is.null(r$no_probes_reason)) L <- c(L, sprintf("  - 다음 탐침 없음: %s", r$no_probes_reason))
  }
  if (!is.null(program)) L <- c(L, sprintf("- 목표 축 연속 '잡음 이내' 판독: %d회", rc_r7_streak(path, program)))
  L
}
