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
  # ★perl = TRUE 필수(2026-11-10): 기본 엔진은 BMP 밖 문자 뒤에서 위치가 어긋나 그 뒤 날짜를 가리지 못한다(가림과 누출 검사가 같은 약점을 공유했다)
  m <- gregexpr("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", x, perl = TRUE)
  regmatches(x, m) <- lapply(regmatches(x, m), function(v) { if (!length(v)) return(v); d <- suppressWarnings(as.Date(v))
                                                              ifelse(!is.na(d) & d > tau, RC_REDACT, v) })
  m2 <- gregexpr("(?<![0-9-])(19|20)[0-9]{2}-(0[1-9]|1[0-2])(?![0-9-])", x, perl = TRUE)
  regmatches(x, m2) <- lapply(regmatches(x, m2), function(v) if (!length(v)) v else ifelse(v > tau_ym, RC_REDACT, v))
  for (i in seq_along(x)) for (h in .rc_tau_alt_hits(x[i], tau_ym)) x[i] <- gsub(h, RC_REDACT, x[i], fixed = TRUE)   # 표기 변형도 가린다(검사와 같은 규칙)
  s[ok] <- x; s
}
## 날짜 표기 변형(11-10 · 감사 K P4) — 한국어 연(월) · 슬래시 · 점 · 두 자리 연도(’23년) · 분기(2023Q1 · 1Q23 · 2023년 1분기).
##   반환 = 표기마다 (문자열 · 그 표기가 가리키는 가장 이른 연월 'YYYY-MM') — 연만 있는 표기 = 그 해 1월(τ_D 연도와 같으면 τ_D 뒤 아님 · 다음 해부터 누출).
##   ISO(YYYY-MM[-DD])는 아래 본 규칙이 맡는다(이 함수는 변형만).
RC_TAU_ALT_RX <- c(
  ko_ym  = "(?<![0-9])((?:19|20)[0-9]{2})\\s*년\\s*(?:(0?[1-9]|1[0-2])\\s*월)?",
  slash  = "(?<![0-9])((?:19|20)[0-9]{2})[/.](0?[1-9]|1[0-2])(?![0-9])",
  yy_ko  = "[’'`]([0-9]{2})\\s*년",
  q_a    = "(?<![0-9])((?:19|20)[0-9]{2})\\s*[Qq]([1-4])(?![0-9])",
  q_b    = "(?<![0-9A-Za-z])([1-4])[Qq]\\s*'?([0-9]{2})(?![0-9])",
  q_ko   = "(?<![0-9])((?:19|20)[0-9]{2})\\s*년\\s*([1-4])\\s*분기")
.rc_tau_alt_hits <- function(v, tau_ym) {
  out <- character(0)
  for (nm in names(RC_TAU_ALT_RX)) {
    mm <- regmatches(v, gregexpr(RC_TAU_ALT_RX[[nm]], v, perl = TRUE))
    for (s in unlist(mm)) {
      g <- regmatches(s, regexec(RC_TAU_ALT_RX[[nm]], s, perl = TRUE))[[1]]
      ym <- switch(nm,
        ko_ym = sprintf("%s-%02d", g[2], if (nzchar(g[3])) as.integer(g[3]) else 1L),
        slash = sprintf("%s-%02d", g[2], as.integer(g[3])),
        yy_ko = sprintf("20%s-01", g[2]),
        q_a = sprintf("%s-%02d", g[2], 3L * as.integer(g[3]) - 2L),
        q_b = sprintf("20%s-%02d", g[3], 3L * as.integer(g[2]) - 2L),
        q_ko = sprintf("%s-%02d", g[2], 3L * as.integer(g[3]) - 2L))
      if (!is.na(ym) && ym > tau_ym) out <- c(out, s)
    }
  }
  unique(out)
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
      d <- unlist(regmatches(v, gregexpr("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", v, perl = TRUE)))
      dd <- suppressWarnings(as.Date(d)); out <<- c(out, d[!is.na(dd) & dd > tau])
      ym <- unlist(regmatches(v, gregexpr("(?<![0-9-])(19|20)[0-9]{2}-(0[1-9]|1[0-2])(?![0-9-])", v, perl = TRUE)))
      out <<- c(out, ym[ym > tau_ym])
      out <<- c(out, .rc_tau_alt_hits(v[!is.na(v)], tau_ym))      # 표기 변형(한국어 연월 · 슬래시 · 점 · ’yy년 · 분기)
    } else if (is.list(v)) for (e in v) walk(e)
    else if (inherits(v, "Date")) out <<- c(out, format(v[!is.na(v) & v > tau]))
  }
  walk(x); unique(out)
}

## 처방 입력 글 검사(11-10 · 감사 K P1) — 쓰기(결과 원장 rc_outcome_record)와 읽기(설계 입력 · 생성기 검토 .rcp4_assert_clean)가 같은 함수를 쓴다:
##   받아들인 줄은 반드시 읽힌다(전에는 쓰기가 등급 표기를 안 봐 '등급 C' 교훈 한 줄이 설계 입력을 영구 정지시켰다).
RC_GRADE_MARK_RX <- "(등급|Grade|grade)\\s*[ABCF](?![A-Za-z])"
rc_input_issues <- function(x, tau) {
  txt <- iconv(paste(as.character(unlist(x)), collapse = "\n"), from = "UTF-8", to = "UTF-8", sub = "")
  if (is.na(txt)) return(list(ok = FALSE, leaks = character(0), grades = character(0), why = "인코딩 판독 불가"))
  lk <- rc_after_tau_leaks(txt, tau); gr <- regmatches(txt, gregexpr(RC_GRADE_MARK_RX, txt, perl = TRUE))[[1]]
  list(ok = !length(lk) && !length(gr), leaks = lk, grades = gr,
       why = paste(c(if (length(lk)) paste("τ_D 뒤 날짜", paste(head(lk, 5), collapse = ",")), if (length(gr)) paste("등급 표기", paste(head(gr, 5), collapse = ","))), collapse = " · "))
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
