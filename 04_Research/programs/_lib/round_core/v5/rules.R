## round_core v4 · rules — 규칙 단일 출처(선언 하나 → 사전등록 문장 · 판정 실행 · DESIGN 표)
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
## 규칙 종류 확장(WP1-b · 2026-10-20) — 템플릿 모듈이 종류를 등록한다(rules_p2.R: 위기 과반 · β 짝 승 · 비열등 알파 · 상승 포착 · 축 감사).
##   등록 = list(validate(r) · resolve(r, root) → r · eval(r, T) → 논리 벡터(NA = 미측정) · sentence(r) · cols(r) → 읽는 판정 표 열). 기본 종류의 의미는 그대로다.
RC_RULE_EXT <- new.env(parent = emptyenv())
rc_rule_kind_register <- function(type, validate, resolve, eval, sentence, cols) {
  if (type %in% RC_RULE_TYPES) stop("[round_core rules] 기본 종류는 다시 등록하지 않는다: ", type)
  assign(type, list(validate = validate, resolve = resolve, eval = eval, sentence = sentence, cols = cols), envir = RC_RULE_EXT)
  invisible(type)
}
.rc_rule_ext <- function(type) if (is.character(type) && length(type) == 1L && exists(type, envir = RC_RULE_EXT, inherits = FALSE)) get(type, envir = RC_RULE_EXT) else NULL

.rc_rule_err <- function(r, msg) stop(sprintf("[round_core rules] %s: %s", r[["id"]] %||% "<id 없음>", msg), call. = FALSE)

## 선언 검사(구조) — 등록 전 check 단계와 판정 시작에서 같은 함수를 쓴다
rc_rule_validate <- function(r, top = TRUE) {
  if (!is.list(r)) stop("[round_core rules] 규칙은 목록이어야 한다")
  if (is.null(r[["id"]]) || !nzchar(r[["id"]]) || !grepl("^[A-Za-z][A-Za-z0-9_]*$", r[["id"]])) .rc_rule_err(r, "id 형식(영문자 시작 · 영숫자 · _)")
  if (!(r[["type"]] %||% "") %in% c(RC_RULE_TYPES, ls(RC_RULE_EXT))) .rc_rule_err(r, paste("type 은", paste(c(RC_RULE_TYPES, ls(RC_RULE_EXT)), collapse = "|")))
  if (is.null(r[["label"]]) || !nzchar(r[["label"]])) .rc_rule_err(r, "label 없음")
  if (!(r[["na"]] %||% "untested") %in% RC_NA_MODES) .rc_rule_err(r, "na 는 fail|untested")
  ext <- .rc_rule_ext(r[["type"]])
  if (!is.null(ext)) { ext[["validate"]](r); return(invisible(TRUE)) }
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
    ext <- .rc_rule_ext(r[["type"]])
    if (!is.null(ext)) { r <- ext[["resolve"]](r, root); r[["na"]] <- r[["na"]] %||% "untested"; return(r) }
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
  ext <- .rc_rule_ext(r[["type"]])
  if (!is.null(ext)) return(.rc_na_apply(ext[["eval"]](r, T), r[["na"]]))
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

## 시험 창 규칙 열(v4 · 2026-11-13 보는 창 파일 누출 수리) — 판정 표에 붙는 규칙 열(최상위 규칙 id) 가운데 값이 시험 창(τ_D 뒤) 열에서 나오는 것.
##   v3 까지 보는 창 파일(driver.R rc_evaluate)은 '_test$' 이름의 열만 뺐다 → P1 보고 규칙 test_hold(metric = alpha_ann_test · 시험 창 연 알파 > 0 여부)
##   열이 '보는 창 전용' 파일에 남았다(P1R03 results/evaluation_visible.json). 반환 = 선언(재귀 — all_of · any_of 의 of · report 포함)에서
##   지표가 rx(기본 '_test$')에 맞는 규칙의 id + 그런 규칙을 하위에 둔 상위 규칙의 id(그 열 값도 시험 창 값에서 나온다 — 판정 규칙이 시험 창 열을
##   쓰는 일은 rc_rules_test_window_use 가 이미 막지만, 막힌 선언이 들어와도 보는 창 파일에서는 빠진다). 확장 종류는 cols(r)(읽는 판정 표 열)로 본다.
##   출시 전 수리(격리 점검 S1 · 판단 T4 C-20261113-042): report 의 when 이 시험 창 규칙이면 그 report 열도 시험 창 규칙이다(when 이 거짓 · 미측정인 칸은 NA —
##   그 열의 NA 모양에 시험 창 정보가 실린다) · when 의존은 고정점까지 따라간다(report → report 사슬). cols 판독 실패는 시험 창으로 센다(fail-closed).
##   변경분 점검 2 수리(isolation_review_v4_diff2.md R-B): 앞 규칙의 열(최상위 id — rc_rules_apply 가 판정 표에 붙인다)을 뒤 규칙이 metric · cols 로 읽는 길도
##   닫힘에 든다(예: metric = "test_hold"). 판별과 판정 규칙 τ_D 검사(p1.R rc_rules_test_window_use)가 같은 고정점(.rc_rules_test_closure)을 쓴다.
## 규칙 하나(자기 자신만 — 하위 제외)가 읽는 판정 표 열 · 기다리는 규칙(report 의 when). 확장 종류 = cols(r) · 판독 실패 = NA(닿는 것으로 센다 — fail-closed)
.rc_rule_reads <- function(r) {
  ext <- .rc_rule_ext(r[["type"]])
  m <- if (!is.null(ext)) tryCatch(as.character(unlist(ext[["cols"]](r))), error = function(e) NA_character_) else as.character(unlist(r[["metric"]]))
  c(m, if (identical(r[["type"]], "report")) as.character(unlist(r[["when"]])) else character(0))
}
.rc_rules_top_ids <- function(rules) unique(as.character(unlist(lapply(rules %||% list(), function(r) if (is.list(r)) r[["id"]] else NULL))))
## 규칙 하나가 시험 창 정보에 닿는가 — 읽는 열이 rx(시험 창 이름)에 맞거나, 닿는 집합 S 안의 최상위 규칙 열을 읽거나 기다린다
.rc_rule_touch <- function(r, S, top, rx = "_test$") {
  m <- .rc_rule_reads(r)
  any(is.na(m)) || any(grepl(rx, m[!is.na(m)], perl = TRUE)) || any(m %in% intersect(S, top))
}
## 시험 창 닫힘 — 씨앗(시험 창 열을 읽는 규칙) ∪ 닫힘 안 최상위 규칙 열을 읽거나 기다리는 규칙 · 하위가 닿는 상위를 고정점까지. 반환 = 닿는 규칙 id(최상위 · 하위)
.rc_rules_test_closure <- function(rules, rx = "_test$") {
  R <- rules %||% list(); top <- .rc_rules_top_ids(R); S <- character(0)
  walk <- function(r, S) {
    if (!is.list(r)) return(character(0))
    out <- character(0); h <- .rc_rule_touch(r, S, top, rx)
    if ((r[["type"]] %||% "") %in% c("all_of", "any_of")) for (k in r[["of"]] %||% list()) { o <- walk(k, S); if (length(o)) { out <- c(out, o); h <- TRUE } }   # 하위를 모두 훑는다(단락 없음)
    if (h) out <- c(out, as.character(unlist(r[["id"]])))
    out
  }
  repeat {
    S1 <- unique(c(S, unlist(lapply(R, walk, S = S))))
    if (length(S1) == length(S)) break
    S <- S1
  }
  S[!is.na(S) & nzchar(S)]
}
rc_rules_test_ids <- function(rules, rx = "_test$") .rc_rules_test_closure(rules, rx)
## 보는 창 판정 표 — 시험 창 이름 열(_test$)과 시험 창 규칙 열(rc_rules_test_ids)을 함께 뺀다(v4 · driver.R rc_evaluate 가 부른다)
rc_rules_visible_table <- function(T, rules) {
  if (is.null(T) || !is.data.frame(T)) return(T)
  T <- as.data.table(T)
  drop <- names(T)[grepl("_test$", names(T)) | names(T) %in% rc_rules_test_ids(rules)]
  if (length(drop)) T[, setdiff(names(T), drop), with = FALSE] else T
}

## 문장 — 사전등록 rules 의 사람 쪽 표기(선언에서 생성 · 손으로 쓰지 않는다)
.rc_val_str <- function(v) format(v, digits = 15, scientific = FALSE, trim = TRUE, drop0trailing = TRUE)
rc_rule_sentence <- function(r) {
  nas <- if (identical(r[["na"]] %||% "untested", "fail")) "미측정 = 미달" else "미측정 = 미시험"
  ext <- .rc_rule_ext(r[["type"]])
  if (!is.null(ext)) return(sprintf("%s (%s)", ext[["sentence"]](r), nas))
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
