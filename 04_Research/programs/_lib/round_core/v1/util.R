## round_core v1 · util — 공용 도구(경로 · md5 · JSON · 과반 · 안전 호출 · τ_D 가림 · 실행 시간 기록)
##   라운드마다 다시 쓰이던 도우미의 단일 출처(P2R04 evaluate.R · round_kit.R 에서 이관 — 함수 본문은 같은 동작).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RC_VERSION <- "v1"
RC_REDACT  <- "[τ_D 이후 날짜 가림]"

## 프로젝트 루트 — 명시 > QM_ROOT > CLAUDE_PROJECT_DIR > 기본값(대소문자 · 구분자 정규화만)
rc_root <- function(root = NULL) {
  r <- root %||% Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  gsub("\\\\", "/", r)
}
rc_md5 <- function(f) unname(as.character(tools::md5sum(f)))
rc_rel <- function(p, root = rc_root()) {
  p <- gsub("\\\\", "/", p); r <- paste0(sub("/$", "", gsub("\\\\", "/", root)), "/")
  ifelse(startsWith(tolower(p), tolower(r)), substring(p, nchar(r) + 1L), p)
}
rc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
rc_abs <- function(p, root = rc_root()) ifelse(grepl("^([A-Za-z]:|/)", p), p, file.path(root, p))

## JSON — 읽기는 목록 그대로(simplifyVector = FALSE) · 쓰기는 원자적 교체 · 수치 손실 없음(digits = NA)
rc_json_read <- function(path) fromJSON(path, simplifyVector = FALSE)
rc_json_write <- function(x, path, pretty = TRUE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  writeLines(toJSON(x, auto_unbox = TRUE, pretty = pretty, null = "null", na = "null", digits = NA), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}

## 과반 — '비율이 이 값을 넘어야 과반'(엄격 >) · 비유한 = 거짓(P2R04 p2_maj 그대로)
rc_maj <- function(share, maj) {
  s <- suppressWarnings(as.numeric(share)); m <- suppressWarnings(as.numeric(maj))
  length(s) == 1L && length(m) == 1L && is.finite(s) && is.finite(m) && s > m
}

## 안전 호출 — 예기치 않은 오류는 그 단위만 미시험(평가 전체가 멈추지 않게 · 사전등록 체크리스트 5)
rc_safe <- function(f, ..., what = "") {
  tryCatch(list(ok = TRUE, value = f(...)),
           error = function(e) list(ok = FALSE, value = NULL, error = paste0(if (nzchar(what)) paste0(what, ": ") else "", conditionMessage(e))))
}

## τ_D 이후 날짜 가림(보는 창 파일 · P2R04 p2_redact_after_tau 와 같은 규칙) — 일(YYYY-MM-DD) · 월(YYYY-MM) 표기를 모두 본다
.rc_redact_chr <- function(s, tau) {
  tau <- as.Date(tau); ok <- !is.na(s)
  if (!any(ok)) return(s)
  tau_ym <- format(tau, "%Y-%m"); x <- s[ok]
  m <- gregexpr("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", x)
  regmatches(x, m) <- lapply(regmatches(x, m), function(v) { if (!length(v)) return(v); d <- suppressWarnings(as.Date(v))
                                                              ifelse(!is.na(d) & d > tau, RC_REDACT, v) })
  m2 <- gregexpr("(?<![0-9-])(19|20)[0-9]{2}-(0[1-9]|1[0-2])(?![0-9-])", x, perl = TRUE)
  regmatches(x, m2) <- lapply(regmatches(x, m2), function(v) if (!length(v)) v else ifelse(v > tau_ym, RC_REDACT, v))
  s[ok] <- x; s
}
rc_redact_after_tau <- function(x, tau) {
  tau <- as.Date(tau)
  if (is.character(x)) return(.rc_redact_chr(x, tau))
  if (is.data.table(x)) { x <- copy(x); for (cc in names(x)) if (is.character(x[[cc]])) set(x, j = cc, value = .rc_redact_chr(x[[cc]], tau)); return(x) }
  if (is.data.frame(x)) { for (cc in names(x)) if (is.character(x[[cc]])) x[[cc]] <- .rc_redact_chr(x[[cc]], tau); return(x) }
  if (is.list(x) && length(x)) { x[] <- lapply(x, rc_redact_after_tau, tau = tau); return(x) }
  x
}
## 보는 창 파일에 τ_D 이후 날짜가 남았는지 전수 검사(쓰기 전 단정 — 남으면 그 목록)
rc_after_tau_leaks <- function(x, tau) {
  tau <- as.Date(tau); tau_ym <- format(tau, "%Y-%m"); out <- character(0)
  walk <- function(v) {
    if (is.character(v)) {
      d <- unlist(regmatches(v, gregexpr("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", v)))
      dd <- suppressWarnings(as.Date(d)); out <<- c(out, d[!is.na(dd) & dd > tau])
      ym <- unlist(regmatches(v, gregexpr("(?<![0-9-])(19|20)[0-9]{2}-(0[1-9]|1[0-2])(?![0-9-])", v, perl = TRUE)))
      out <<- c(out, ym[ym > tau_ym])
    } else if (is.list(v)) for (e in v) walk(e)
    else if (inherits(v, "Date")) out <<- c(out, format(v[!is.na(v) & v > tau]))
  }
  walk(x); unique(out)
}

## 실행 시간 기록(속도 계획 5-1) — .cache/round_core/perf/<round>.jsonl 한 줄씩(동기화 밖 로컬 정션)
rc_perf_log <- function(round_id, stage, seconds, extra = list(), root = rc_root()) {
  d <- file.path(root, ".cache", "round_core", "perf"); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  rec <- c(list(at = rc_now(), round = round_id, stage = stage, seconds = round(as.numeric(seconds), 3), core = RC_VERSION), extra)
  cat(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null", digits = NA), "\n", sep = "", file = file.path(d, paste0(round_id, ".jsonl")), append = TRUE)
  invisible(rec)
}
rc_timed <- function(round_id, stage, expr, root = rc_root()) {
  t0 <- Sys.time(); v <- force(expr)
  rc_perf_log(round_id, stage, difftime(Sys.time(), t0, units = "secs"), root = root)
  v
}

## JSON 경로 참조 해석 — "<파일>::<a.b.c>" (수치 근거를 정본 설정에서 읽는다 · 하드코딩 금지)
rc_ref_value <- function(ref, root = rc_root()) {
  parts <- strsplit(ref, "::", fixed = TRUE)[[1]]
  if (length(parts) != 2L) stop("[round_core] 참조 형식은 '<파일>::<키 경로>': ", ref)
  x <- rc_json_read(rc_abs(parts[1], root))
  for (k in strsplit(parts[2], ".", fixed = TRUE)[[1]]) {
    if (is.null(x[[k]])) stop("[round_core] 참조 키 없음: ", ref)
    x <- x[[k]]
  }
  x
}
