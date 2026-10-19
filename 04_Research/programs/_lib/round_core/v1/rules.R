## round_core v1 · rules — 규칙 단일 출처(선언 하나 → 사전등록 문장 · 판정 실행 · DESIGN 표)
##   왜: P2R04 · P2R05 격리 교차 점검 필수 지적 17건 중 11건이 '같은 규칙이 DESIGN · 사전등록 문장 · evaluate.R 에 따로 적혀 어긋남'이었다.
##   여기서는 규칙을 데이터(목록)로 한 번만 선언하고, 문장 · 표 · 판정을 모두 그 선언에서 만든다 — 어긋날 사본이 없다.
##
## 규칙 선언(목록) 필드
##   id      고유 이름(판정 표의 열 이름이 된다 — 최상위 규칙만)
##   type    threshold | all_of | any_of | report
##   label   사람이 읽는 이름
##   threshold: metric(판정 표의 열) · op(>= > <= < ==) · value(수) 또는 value_ref("<파일>::<키 경로>") · basis(value 가 수일 때 근거 — 필수)
##   all_of / any_of: of = 하위 규칙 목록(Kleene 논리 — 거짓 우선 · 그다음 미측정)
##   report: when(먼저 참이어야 하는 최상위 규칙 id) + threshold 와 같은 비교 — 판정이 아니라 보고(사람 쪽)
##   na      fail(미측정 = 미달) | untested(미측정 = 미시험 · 기본값) — NA 를 통과로 접는 의미는 없다(사전등록 체크리스트 5)

RC_RULE_TYPES <- c("threshold", "all_of", "any_of", "report")
RC_OPS <- c(">=", ">", "<=", "<", "==")
RC_NA_MODES <- c("fail", "untested")

.rc_rule_err <- function(r, msg) stop(sprintf("[round_core rules] %s: %s", r[["id"]] %||% "<id 없음>", msg), call. = FALSE)

## 선언 검사(구조) — 등록 전 check 단계와 판정 시작에서 같은 함수를 쓴다
rc_rule_validate <- function(r, top = TRUE) {
  if (!is.list(r)) stop("[round_core rules] 규칙은 목록이어야 한다")
  if (is.null(r[["id"]]) || !nzchar(r[["id"]]) || !grepl("^[A-Za-z][A-Za-z0-9_]*$", r[["id"]])) .rc_rule_err(r, "id 형식(영문자 시작 · 영숫자 · _)")
  if (!(r[["type"]] %||% "") %in% RC_RULE_TYPES) .rc_rule_err(r, paste("type 은", paste(RC_RULE_TYPES, collapse = "|")))
  if (is.null(r[["label"]]) || !nzchar(r[["label"]])) .rc_rule_err(r, "label 없음")
  if (!(r[["na"]] %||% "untested") %in% RC_NA_MODES) .rc_rule_err(r, "na 는 fail|untested")
  if (r[["type"]] %in% c("threshold", "report")) {
    if (is.null(r[["metric"]]) || !nzchar(r[["metric"]])) .rc_rule_err(r, "metric 없음")
    if (!(r[["op"]] %||% "") %in% RC_OPS) .rc_rule_err(r, paste("op 는", paste(RC_OPS, collapse = " ")))
    has_v <- !is.null(r[["value"]]); has_ref <- !is.null(r[["value_ref"]])
    if (has_v == has_ref) .rc_rule_err(r, "value 와 value_ref 중 정확히 하나")
    if (has_v && (!is.numeric(r[["value"]]) || length(r[["value"]]) != 1L || !is.finite(r[["value"]]))) .rc_rule_err(r, "value 는 유한 수 1개")
    if (has_v && (is.null(r[["basis"]]) || !nzchar(r[["basis"]]))) .rc_rule_err(r, "수치 문턱의 근거(basis)가 없다 — 하드코딩 금지")
  }
  if (identical(r[["type"]], "report") && (is.null(r[["when"]]) || !nzchar(r[["when"]]))) .rc_rule_err(r, "report 는 when(선행 규칙 id)이 필요")
  if (r[["type"]] %in% c("all_of", "any_of")) {
    if (!is.list(r[["of"]]) || length(r[["of"]]) < 1L) .rc_rule_err(r, "of 는 하위 규칙 1개 이상")
    for (k in r[["of"]]) rc_rule_validate(k, top = FALSE)
  }
  invisible(TRUE)
}
rc_rules_validate <- function(rules) {
  if (!is.list(rules) || !length(rules) || !is.null(names(rules))) stop("[round_core rules] rules 는 이름 없는 목록(배열)이어야 한다")
  for (r in rules) rc_rule_validate(r)
  ids <- vapply(rules, function(r) r[["id"]], character(1))
  if (anyDuplicated(ids)) stop("[round_core rules] 최상위 규칙 id 중복: ", paste(ids[duplicated(ids)], collapse = ","))
  for (r in rules) if (identical(r[["type"]], "report") && !(r[["when"]] %in% ids)) .rc_rule_err(r, paste("when 이 최상위 규칙이 아니다:", r[["when"]]))
  invisible(TRUE)
}

## 값 해석 — value_ref 는 정본 설정에서 읽고 출처를 남긴다(사전등록에는 해석된 수와 출처가 함께 실린다)
rc_rules_resolve <- function(rules, root = rc_root()) {
  rc_rules_validate(rules)
  one <- function(r) {
    if (r[["type"]] %in% c("threshold", "report")) {
      if (!is.null(r[["value_ref"]])) {
        v <- rc_ref_value(r[["value_ref"]], root)
        if (!is.numeric(v) || length(v) != 1L || !is.finite(v)) .rc_rule_err(r, paste("value_ref 가 유한 수 1개가 아니다:", r[["value_ref"]]))
        r[["value"]] <- as.numeric(v); r[["value_source"]] <- r[["value_ref"]]
      } else r[["value_source"]] <- paste("근거:", r[["basis"]])
    }
    if (r[["type"]] %in% c("all_of", "any_of")) r[["of"]] <- lapply(r[["of"]], one)
    r[["na"]] <- r[["na"]] %||% "untested"
    r
  }
  lapply(rules, one)
}

## 비교 — 비유한 = NA(그 뒤 na 의미로 처리)
.rc_cmp <- function(x, op, v) {
  x <- suppressWarnings(as.numeric(x)); out <- rep(NA, length(x)); ok <- is.finite(x)
  out[ok] <- switch(op, ">=" = x[ok] >= v, ">" = x[ok] > v, "<=" = x[ok] <= v, "<" = x[ok] < v, "==" = x[ok] == v)
  out
}
.rc_na_apply <- function(v, na) if (identical(na, "fail")) { v[is.na(v)] <- FALSE; v } else v
.rc_and <- function(vs) { n <- length(vs[[1]]); out <- rep(TRUE, n)
  for (v in vs) { out[!is.na(v) & !v] <- FALSE }
  anyna <- Reduce(`|`, lapply(vs, is.na)); out[out & anyna] <- NA; out }
.rc_or <- function(vs) { n <- length(vs[[1]]); out <- rep(FALSE, n)
  for (v in vs) { out[!is.na(v) & v] <- TRUE }
  anyna <- Reduce(`|`, lapply(vs, is.na)); out[!out & anyna] <- NA; out }

## 규칙 1개 판정 — T = 판정 표(data.table) · done = 이미 계산한 최상위 규칙 열 · 반환 = 길이 nrow(T) 논리 벡터
rc_rule_eval <- function(r, T, done = list()) {
  v <- switch(r[["type"]],
    threshold = .rc_cmp(if (r[["metric"]] %in% names(T)) T[[r[["metric"]]]] else rep(NA_real_, nrow(T)), r[["op"]], r[["value"]]),
    all_of = .rc_and(lapply(r[["of"]], rc_rule_eval, T = T, done = done)),
    any_of = .rc_or(lapply(r[["of"]], rc_rule_eval, T = T, done = done)),
    report = {
      w <- done[[r[["when"]]]]; if (is.null(w)) .rc_rule_err(r, paste("when 규칙이 아직 계산되지 않았다:", r[["when"]]))
      x <- .rc_cmp(if (r[["metric"]] %in% names(T)) T[[r[["metric"]]]] else rep(NA_real_, nrow(T)), r[["op"]], r[["value"]])
      ifelse(!is.na(w) & w, x, NA)
    })
  if (identical(r[["type"]], "report")) v else .rc_na_apply(v, r[["na"]])
}

## 판정 — eligible(예: status == "evaluated")이 거짓인 행은 모든 규칙이 NA(미시험) · 최상위 규칙만 열로 붙인다
rc_rules_apply <- function(rules, T, eligible = rep(TRUE, nrow(T))) {
  T <- copy(as.data.table(T)); done <- list()
  for (r in rules) {
    v <- rep(NA, nrow(T))
    if (any(eligible)) v[eligible] <- rc_rule_eval(r, T[eligible], done = lapply(done, function(d) d[eligible]))
    done[[r[["id"]]]] <- v
    set(T, j = r[["id"]], value = v)
  }
  T
}

## 문장 — 사전등록 rules 의 사람 쪽 표기(선언에서 생성 · 손으로 쓰지 않는다)
.rc_val_str <- function(v) format(v, digits = 15, scientific = FALSE, trim = TRUE, drop0trailing = TRUE)
rc_rule_sentence <- function(r) {
  nas <- if (identical(r[["na"]] %||% "untested", "fail")) "미측정 = 미달" else "미측정 = 미시험"
  switch(r[["type"]],
    threshold = sprintf("%s: %s %s %s (%s · %s)", r[["label"]], r[["metric_label"]] %||% r[["metric"]], r[["op"]], .rc_val_str(r[["value"]]), r[["value_source"]] %||% "", nas),
    all_of = sprintf("%s = [%s] 모두 (%s)", r[["label"]], paste(vapply(r[["of"]], rc_rule_sentence, character(1)), collapse = " ∧ "), nas),
    any_of = sprintf("%s = [%s] 하나 이상 (%s)", r[["label"]], paste(vapply(r[["of"]], rc_rule_sentence, character(1)), collapse = " ∨ "), nas),
    report = sprintf("%s(보고 전용 — 판정 아님): '%s' 참인 칸만 %s %s %s (%s)", r[["label"]], r[["when"]], r[["metric_label"]] %||% r[["metric"]], r[["op"]],
                     .rc_val_str(r[["value"]]), r[["value_source"]] %||% ""))
}
rc_rules_sentences <- function(rules) setNames(vapply(rules, rc_rule_sentence, character(1)), vapply(rules, function(r) r[["id"]], character(1)))

## DESIGN 표(markdown) — 같은 선언에서
rc_rules_table_md <- function(rules) {
  rows <- character(0)
  walk <- function(r, depth = 0L) {
    ind <- strrep("· ", depth)
    rows <<- c(rows, sprintf("| %s%s | %s | %s | %s | %s | %s | %s |", ind, r[["id"]], r[["type"]], r[["metric"]] %||% "", r[["op"]] %||% "",
                              if (!is.null(r[["value"]])) .rc_val_str(r[["value"]]) else "", r[["value_source"]] %||% "", r[["na"]] %||% "untested"))
    if (r[["type"]] %in% c("all_of", "any_of")) for (k in r[["of"]]) walk(k, depth + 1L)
  }
  for (r in rules) walk(r)
  c("| 규칙 | 종류 | 지표 | 비교 | 값 | 출처 · 근거 | 미측정 |", "|---|---|---|---|---|---|---|", rows)
}
