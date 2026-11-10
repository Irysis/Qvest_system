## knowledge_loop_metrics.R — '나아지고 있는가'의 계기 (v10.2 재귀적 개선 루프 · 2026-11-10 감사 레인 K)
##
## 왜: v10.2 학습 고리(결과 원장 → 다음 설계 입력 → 생성기 판 개정)는 쓰는 쪽만 있고, 그 고리가 실제로 돌고 있는지·
##   A 등급 기저 · 후보를 내는 능력이 나아지는지를 보는 계기가 없었다. 이 파일은 원장 4개에서 **운영 지표(개수 · 비율)만** 낸다.
## 원천(전부 읽기 전용 · 없으면 0):
##   ① 06_Registry/round_outcomes.jsonl          — 결과 원장(round_core v1/outcomes.R · kind = round | probe_consumed)
##   ② (사슬 걸음 지표는 여기서 세지 않는다 — 걸음 채택률 · 걸음당 개선 · 새 블록 비율 · 되풀이 기각 · 잡음 연속의 정본 =
##      02_Infrastructure/programs/rx_generator_scorecard.R::rxg_scorecard · 중복 구현 금지 · 11-10 총괄 지시. 여기는 닫힌 사슬 수만 결과 원장에서 센다)
##   ③ stage_artifacts/programs/*/*/standing_ledger.jsonl    — 상설 판 판정 원장(verdict.qualify — 기저 풀 상설 경로 자격)
##   ④ .cache/reinforce_auto_log.jsonl            — 충실구현 레인 저널(preaudit rc · fidelity_audit_verdict action/retries)
## ★정보 경계: 이 함수는 성과 수치(CAGR · Sharpe · Calmar · 등급 · dS 값)를 **읽지도 내지도 않는다** — 개수와 비율뿐이다.
##   출력 열은 KLM_COLUMNS 허용목록으로 고정하고 klm_assert_clean() 이 그 밖의 열을 거부한다(아침 면 · 생성기 검토에 실려도 안전).
## 손상 줄: 진단 계기라 멈추지 않는다 — 원천별 bad 줄 수를 결과에 싣고, 형식화 출력 첫 줄에 경고로 올린다(조용히 넘기지 않는다).
##   (판정 경로인 rc_outcomes_read 는 손상 줄에서 멈춘다 — 그 규율은 round_core 쪽이 지킨다.)
## ★결과 원장 읽기 규율(11-10(2) 감사 U11 — 지식 축적은 '사실만 · 한 원장 · 같은 규율'): 결과 원장은 klm_read_outcomes() 하나로만 읽는다.
##   그 함수는 round_core v1/outcomes.R 의 공용 읽기(rc_outcomes_read · rc_open_probes · tau_clean = τ_D)를 그대로 부른다 —
##   격리된 줄 · 처방 입력 검사(rc_input_issues)를 통과하지 못한 줄은 설계 입력과 똑같이 빠지고 건수를 따로 싣는다.
##   반파 줄(JSON 판독 불가 · 격리 안 됨)만 이 함수가 먼저 걸러 개수를 경고로 남긴다(진단 계기라 멈추지 않는다).
##   round_core 를 못 찾으면 멈춘다(규율 없이 읽지 않는다 · fail-closed) — 소비자(색인 · 증류 재료)가 '미측정'으로 처리한다.
##   조회 색인(hypothesis_index.R) · 증류 재료(cleaner_distill_lib.R)도 이 함수를 쓴다(한 구현).
## 사전 감사 1차 통과율(11-10(2) 감사 U11): 분모 = 논문(레인 저널 paper 키)마다 **첫** 사전 감사 사건 · 분자 = 그 첫 사건이
##   rc 0 이면서 result 에 verdict=pass. 보정 뒤 재검사 통과(preaudit_retry_pass) · 회차 소진 진행(why=rounds_exhausted ·
##   preaudit_exhausted) · 논문 키 없는 사건(preaudit_unkeyed · 분모 밖)은 따로 센다. 분모 0 = NA(0 으로 접지 않는다).
##   전에는 사건마다 rc == 0 을 통과로 세어 재시도 · 회차 소진 통과가 '1차 통과'로 들어갔다(실측 0.869 vs 논문 첫 검사 0.632).
## 사용:
##   source("02_Infrastructure/memory/knowledge_loop_metrics.R")
##   ev  <- klm_collect(root)                    # 사건 표 + 손상 줄 수
##   tab <- klm_weekly(ev, weeks = 8)            # 주별 표(ISO 주)
##   cat(klm_format(tab, klm_snapshot(ev, root)), sep = "\n")
##   Rscript 02_Infrastructure/memory/knowledge_loop_metrics.R [--root <dir>] [--weeks 8] [--json]

suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

KLM_P4_PROGRAM <- "P4_ASSEMBLY"   # round_core v1/p4.R::RC_P4_PROGRAM 과 같은 값(사슬 닫기가 결과 원장에 쓰는 program)
KLM_COLUMNS <- c("week", "rounds_closed", "chains_closed", "probes_new", "probes_consumed",
                 "standing_verdicts", "standing_qualified",
                 "preaudit_n", "preaudit_pass", "first_pass_rate",                       # 논문 수 · 첫 검사 통과 논문 수 · 그 비율
                 "preaudit_retry_pass", "preaudit_exhausted", "preaudit_unkeyed", "preaudit_events",
                 "fidelity_n", "fidelity_first_pass")
KLM_RC_REL <- "04_Research/programs/_lib/round_core/v1"
KLM_RC_FILES <- c("util.R", "standing.R", "outcomes.R")   # outcomes.R 이 쓰는 것(rc_input_issues · .rcs_md5s)만

## 이 파일의 코드 루트 — round_core 를 찾는 첫 후보(데이터 루트 root 와 다를 수 있다 · 시험 임시 루트).
##   source(ofile) · sys.source(file) · Rscript --file 순으로 이 파일 경로를 찾는다(경로 정규화 함수 없이 구분자 치환만).
.KLM_SELF_ROOT <- local({
  p <- NULL
  for (i in rev(seq_len(sys.nframe()))) {
    f <- sys.frame(i)
    if (is.character(f$ofile) && length(f$ofile) == 1L) { p <- f$ofile; break }
    if (is.character(f$file) && length(f$file) == 1L && grepl("knowledge_loop_metrics[^/\\\\]*\\.R$", f$file)) { p <- f$file; break }
  }
  if (is.null(p)) { a <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)); if (length(a) && grepl("knowledge_loop_metrics", a[1])) p <- a[1] }
  if (is.null(p)) NA_character_ else {
    p <- gsub("\\\\", "/", p); if (!grepl("^([A-Za-z]:|/)", p)) p <- file.path(gsub("\\\\", "/", getwd()), p)
    dirname(dirname(dirname(p)))
  }
})
.KLM_RC <- new.env(parent = emptyenv())
## round_core v1 의 결과 원장 읽기 함수만 사적 환경에 적재(전역 오염 없음 · 판마다 1회) — 못 찾으면 멈춘다(fail-closed)
.klm_rc_env <- function(root = NULL, rc_dir = NULL) {
  cand <- c(rc_dir, if (!is.na(.KLM_SELF_ROOT)) file.path(.KLM_SELF_ROOT, KLM_RC_REL),
            if (!is.null(root) && nzchar(root)) file.path(gsub("\\\\", "/", root), KLM_RC_REL),
            if (nzchar(Sys.getenv("QM_ROOT", ""))) file.path(gsub("\\\\", "/", Sys.getenv("QM_ROOT")), KLM_RC_REL))
  for (d in unique(cand)) {
    if (!all(file.exists(file.path(d, KLM_RC_FILES)))) next
    if (exists(d, envir = .KLM_RC, inherits = FALSE)) return(get(d, envir = .KLM_RC))
    e <- new.env(parent = globalenv())
    for (f in KLM_RC_FILES) suppressMessages(sys.source(file.path(d, f), envir = e, keep.source = FALSE))
    if (!all(vapply(c("rc_outcomes_read", "rc_open_probes", "rc_outcomes_quarantined", ".rc_outcome_md5"), exists, logical(1), envir = e, inherits = FALSE)))
      stop("[knowledge_loop_metrics] round_core 결과 원장 읽기 함수가 없다: ", d)
    assign(d, e, envir = .KLM_RC); return(e)
  }
  stop("[knowledge_loop_metrics] round_core v1 결과 원장 읽기(", KLM_RC_REL, "/outcomes.R)를 찾지 못했다 — 규율 없이 읽지 않는다(후보: ",
       paste(unique(cand), collapse = " · "), ")")
}
## τ_D — 설계 입력과 같은 출처(round_core v1/p4.R::.rcp4_tau = 06_Registry/behavior_card.json::tau_d). 못 읽으면 NA(→ 모든 라운드 줄이 미통과 = fail-closed)
.klm_tau <- function(root) {
  b <- tryCatch(fromJSON(file.path(root, "06_Registry", "behavior_card.json"), simplifyVector = FALSE), error = function(e) NULL)
  t <- tryCatch(as.Date(as.character(unlist(b$tau_d))[1]), error = function(e) as.Date(NA))
  if (length(t) != 1L) as.Date(NA) else t
}

#' 결과 원장 읽기(진단 소비자 공용) — 설계 입력과 같은 규율. 반환 = recs(통과 줄 · 모든 kind) · open_probes(rc_open_probes 그대로) ·
#'   bad(반파 줄 수 · 경고) · quarantined(격리로 빠진 줄 수) · input_excluded(처방 입력 검사 미통과로 빠진 라운드 줄 수) · input_excluded_ids
klm_read_outcomes <- function(path, root = Sys.getenv("QM_ROOT", getwd()), tau = .klm_tau(root), rc_dir = NULL) {
  out <- list(recs = list(), open_probes = list(), bad = 0L, quarantined = 0L, input_excluded = 0L, input_excluded_ids = character(0),
              tau = as.character(tau))
  if (is.null(path) || !file.exists(path)) return(out)
  E <- .klm_rc_env(root, rc_dir)
  L <- readLines(path, warn = FALSE, encoding = "UTF-8"); L <- L[nzchar(trimws(L))]
  if (!length(L)) return(out)
  isq <- vapply(L, E$.rc_outcome_md5, "", USE.NAMES = FALSE) %in% E$rc_outcomes_quarantined(L)
  okj <- vapply(L, function(s) !is.null(tryCatch(fromJSON(s, simplifyVector = FALSE), error = function(e) NULL)), logical(1), USE.NAMES = FALSE)
  out$bad <- sum(!okj & !isq); out$quarantined <- sum(isq)
  if (out$bad) warning(sprintf("[knowledge_loop_metrics] 결과 원장 반파(판독 불가) 줄 %d개 — 건너뛰고 센다(격리 = rc_outcomes_quarantine): %s", out$bad, path), call. = FALSE)
  ## 공용 읽기에 넘길 사본 = 반파 줄만 뺀 같은 줄(격리 줄 · 격리 기록은 그대로 — 공용 함수가 md5 로 뺀다)
  tf <- tempfile(fileext = ".jsonl"); on.exit(unlink(tf), add = TRUE)
  con <- file(tf, open = "wb"); writeBin(charToRaw(paste0(paste(enc2utf8(L[okj | isq]), collapse = "\n"), "\n")), con); close(con)
  quiet <- function(expr) withCallingHandlers(expr, warning = function(w) invokeRestart("muffleWarning"))
  all_r <- quiet(E$rc_outcomes_read(tf, kind = NULL))
  clean <- quiet(E$rc_outcomes_read(tf, kind = NULL, tau_clean = tau))
  rid <- function(R) vapply(Filter(function(x) identical(x$kind %||% "round", "round"), R), function(x) as.character(x$round_id %||% "?")[1], "")
  ia <- rid(all_r); ic <- rid(clean)
  out$input_excluded <- length(ia) - length(ic); out$input_excluded_ids <- setdiff(unique(ia), unique(ic))
  if (out$input_excluded > 0L)
    warning(sprintf("[knowledge_loop_metrics] 결과 원장 처방 입력 검사 미통과 줄 %d개를 뺀다(설계 입력과 같은 규율 · τ_D %s): %s", out$input_excluded,
                    as.character(tau), paste(utils::head(out$input_excluded_ids, 5), collapse = ",")), call. = FALSE)
  out$recs <- clean
  out$open_probes <- quiet(E$rc_open_probes(tf, tau_clean = tau))
  out
}

## jsonl 한 파일 → list(recs, bad) · 빈 줄 무시
.klm_jsonl <- function(path) {
  if (!file.exists(path)) return(list(recs = list(), bad = 0L))
  L <- readLines(path, warn = FALSE, encoding = "UTF-8"); L <- L[nzchar(trimws(L))]
  R <- lapply(L, function(s) tryCatch(fromJSON(s, simplifyVector = FALSE), error = function(e) NULL))
  list(recs = Filter(Negate(is.null), R), bad = sum(vapply(R, is.null, logical(1))))
}
.klm_ts <- function(x) {
  s <- as.character(x %||% NA_character_)[1]
  if (is.na(s) || !nzchar(s)) return(as.POSIXct(NA))
  s <- sub("([+-][0-9]{2}):?([0-9]{2})$", "", s)          # 시간대 꼬리 제거(로컬 시각으로 읽는다 — 주 경계 판정용)
  suppressWarnings(as.POSIXct(sub("T", " ", s), format = "%Y-%m-%d %H:%M:%S", tz = ""))
}
.klm_row <- function(src, kind, at, ..., tag = NA_character_) data.frame(src = src, kind = kind, at = at, ..., tag = tag, stringsAsFactors = FALSE)

#' 원천 4개 → 사건 표(src · kind · at · n · flag · program · key) + 손상 줄 수
klm_collect <- function(root = Sys.getenv("QM_ROOT", getwd()), outcomes_path = NULL,
                        standing_files = NULL, lane_log = NULL, sa_root = Sys.getenv("RC_SA_ROOT", root), rc_dir = NULL) {
  root <- gsub("\\\\", "/", root)
  op <- outcomes_path %||% file.path(root, "06_Registry", "round_outcomes.jsonl")
  sf <- standing_files %||% unique(c(Sys.glob(file.path(sa_root, "stage_artifacts/programs/*/*/standing_ledger.jsonl")),
                                      Sys.glob(file.path(root, "stage_artifacts/programs/*/*/standing_ledger.jsonl"))))
  ll <- lane_log %||% file.path(root, ".cache", "reinforce_auto_log.jsonl")
  rows <- list(); bad <- c(outcomes = 0L, standing = 0L, lane_log = 0L)
  add <- function(r) rows[[length(rows) + 1L]] <<- r

  o <- klm_read_outcomes(op, root = root, rc_dir = rc_dir); bad["outcomes"] <- o$bad   # 설계 입력과 같은 규율(격리 · 처방 입력 미통과 제외)
  for (r in o$recs) {
    if (!identical(r$schema, "round_outcome_v1")) next
    k <- r$kind %||% "round"
    if (identical(k, "round")) {
      p4 <- identical(r$program, KLM_P4_PROGRAM) || identical(r$template, "p4_chain")
      add(.klm_row("outcomes", if (p4) "chain_closed" else "round_closed", .klm_ts(r$at),
                   n = length(r$probes %||% list()), flag = NA, program = as.character(r$program %||% NA), key = as.character(r$round_id %||% NA)))
    } else if (identical(k, "probe_consumed"))
      add(.klm_row("outcomes", "probe_consumed", .klm_ts(r$at), n = 1L, flag = NA, program = as.character(r$program %||% NA),
                   key = as.character(r$ref %||% NA)))
  }
  for (f in sf) {
    s <- .klm_jsonl(f); bad["standing"] <- bad["standing"] + s$bad
    for (r in s$recs) if (identical(r$event, "verdict"))
      add(.klm_row("standing", "standing_verdict", .klm_ts(r$at), n = 1L, flag = isTRUE(r$qualify),
                   program = basename(dirname(dirname(f))), key = as.character(r$code %||% NA)))
  }
  l <- .klm_jsonl(ll); bad["lane_log"] <- l$bad
  for (r in l$recs) {
    e <- r$event %||% ""
    if (identical(e, "preaudit")) {
      res <- as.character(r$result %||% "")[1]; pk <- as.character(r$paper %||% NA_character_)[1]
      add(.klm_row("lane_log", "preaudit", .klm_ts(r$ts), n = 1L,
                   flag = identical(as.character(r$rc %||% ""), "0") && grepl("(^|\\s)verdict=pass(\\s|$)", res, perl = TRUE),
                   program = NA_character_, key = if (is.na(pk) || !nzchar(trimws(pk))) NA_character_ else pk,
                   tag = if (grepl("(^|\\s)why=rounds_exhausted(\\s|$)", res, perl = TRUE)) "rounds_exhausted" else NA_character_))
    }
    else if (identical(e, "fidelity_audit_verdict"))
      add(.klm_row("lane_log", "fidelity", .klm_ts(r$ts), n = 1L,
                   flag = identical(as.character(r$action %||% ""), "proceed") && identical(as.integer(r$retries %||% -1L), 0L),
                   program = NA_character_, key = NA_character_))
  }
  ev <- if (length(rows)) do.call(rbind, rows) else
    data.frame(src = character(0), kind = character(0), at = as.POSIXct(character(0)), n = integer(0), flag = logical(0),
               program = character(0), key = character(0), tag = character(0), stringsAsFactors = FALSE)
  list(events = ev, bad = bad, outcomes_path = op, outcomes = o)
}

.klm_week <- function(t) format(t, "%G-W%V")

#' 주별 표 — 최근 weeks 개 ISO 주(사건 없는 주도 0 으로 싣는다 · '안 돌았다'가 보이게)
klm_weekly <- function(ev, weeks = 8L, now = Sys.time()) {
  E <- ev$events; E <- E[!is.na(E$at), , drop = FALSE]
  wk <- unique(.klm_week(now - (rev(seq_len(weeks)) - 1L) * 7 * 86400))
  E$week <- .klm_week(E$at)
  cnt <- function(w, k, flag = NULL) { x <- E[E$week == w & E$kind == k, , drop = FALSE]
    if (!is.null(flag)) x <- x[isTRUE(flag) == x$flag & !is.na(x$flag), , drop = FALSE]
    nrow(x) }
  sumn <- function(w, k) sum(E$n[E$week == w & E$kind == k])
  rate <- function(a, b) if (b > 0) round(a / b, 3) else NA_real_
  ## 사전 감사 — 논문(paper 키)마다 첫 사건(저널 전체 기준 · 그 주에 센다) · 재시도 뒤 통과 = 첫 사건 미통과 뒤 verdict=pass 사건이 있는 논문
  P <- E[E$kind == "preaudit", , drop = FALSE]; P <- P[order(P$at), , drop = FALSE]
  Pk <- P[!is.na(P$key), , drop = FALSE]; F1 <- Pk[!duplicated(Pk$key), , drop = FALSE]
  later_pass <- unique(Pk$key[Pk$flag %in% TRUE & duplicated(Pk$key)])
  out <- do.call(rbind, lapply(wk, function(w) {
    f1 <- F1[F1$week == w, , drop = FALSE]
    pn <- nrow(f1); pp <- sum(f1$flag %in% TRUE)
    data.frame(week = w, rounds_closed = cnt(w, "round_closed"), chains_closed = cnt(w, "chain_closed"),
               probes_new = sumn(w, "round_closed") + sumn(w, "chain_closed"), probes_consumed = cnt(w, "probe_consumed"),
               standing_verdicts = cnt(w, "standing_verdict"), standing_qualified = cnt(w, "standing_verdict", TRUE),
               preaudit_n = pn, preaudit_pass = pp, first_pass_rate = rate(pp, pn),
               preaudit_retry_pass = sum(!(f1$flag %in% TRUE) & f1$key %in% later_pass),
               preaudit_exhausted = sum(P$week == w & P$tag %in% "rounds_exhausted"),
               preaudit_unkeyed = sum(P$week == w & is.na(P$key)), preaudit_events = sum(P$week == w),
               fidelity_n = cnt(w, "fidelity"), fidelity_first_pass = cnt(w, "fidelity", TRUE), stringsAsFactors = FALSE)
  }))
  klm_assert_clean(out); out
}

#' 출력 표가 허용 열(개수 · 비율)만 갖는지 — 성과 수치 열이 끼면 멈춘다
klm_assert_clean <- function(tab) {
  extra <- setdiff(names(tab), KLM_COLUMNS)
  if (length(extra)) stop("[knowledge_loop_metrics] 허용 목록 밖 열(성과 수치 금지 계기): ", paste(extra, collapse = ","))
  num <- setdiff(KLM_COLUMNS, "week")
  r <- unlist(tab[, intersect(num, "first_pass_rate"), drop = FALSE])
  if (any(!is.na(r) & (r < 0 | r > 1))) stop("[knowledge_loop_metrics] 비율 열이 [0,1] 밖")
  invisible(TRUE)
}

#' 지금 시점 상태 — 열린 탐침 수(이어받지 않은 것) · 프로그램별 연속 '잡음 이내' · 현 생성기 판 이후 닫혔는데 개정 근거로 아직 안 쓰인 사슬 수
klm_snapshot <- function(ev, root = Sys.getenv("QM_ROOT", getwd()), generator_path = NULL) {
  ## klm_collect 가 공용 규율로 읽은 결과 원장(재판독 없음 · 격리 · 처방 입력 미통과 줄은 이미 빠졌다)
  if (is.null(ev$outcomes)) stop("[knowledge_loop_metrics] klm_snapshot 은 klm_collect 결과(ev$outcomes)를 받는다")
  o <- Filter(function(r) identical(r$schema, "round_outcome_v1"), ev$outcomes$recs)
  rounds <- Filter(function(r) identical(r$kind %||% "round", "round"), o)
  open_n <- length(ev$outcomes$open_probes)   # = rc_open_probes(tau_clean = τ_D)
  streak <- list()
  for (p in unique(vapply(rounds, function(r) as.character(r$program %||% "?"), ""))) {
    rs <- Filter(function(r) identical(as.character(r$program %||% "?"), p) && !is.null(r$r7) && !is.na(r$r7), rounds)
    n <- 0L; for (x in rev(rs)) { if (identical(x$r7, "noise")) n <- n + 1L else break }
    streak[[p]] <- n
  }
  gp <- generator_path %||% file.path(root, "06_Registry", "rx_generator.json")
  G <- tryCatch(fromJSON(gp, simplifyVector = FALSE), error = function(e) NULL)
  cited <- unique(unlist(lapply(G$versions %||% list(), function(v) unlist(v$evidence))))
  cur <- Filter(function(v) identical(v$id, G$current), G$versions %||% list())
  cur_at <- if (length(cur)) .klm_ts(cur[[1]]$created_at) else as.POSIXct(NA)
  chains <- Filter(function(r) identical(r$program, KLM_P4_PROGRAM) || identical(r$template, "p4_chain"), rounds)
  unrev <- Filter(function(r) !(as.character(r$round_id) %in% cited) && (is.na(cur_at) || isTRUE(.klm_ts(r$at) >= cur_at)), chains)
  list(open_probes = open_n, closed_rounds_total = length(rounds), r7_noise_streak = streak,
       generator_current = as.character(G$current %||% NA), unreviewed_closed_chains = length(unrev),
       bad_lines = as.list(ev$bad),
       excluded = list(quarantined = as.integer(ev$outcomes$quarantined), input_check = as.integer(ev$outcomes$input_excluded),
                       input_check_ids = as.list(ev$outcomes$input_excluded_ids)))
}

#' 사람이 읽는 줄(아침 면 · 생성기 검토용) — 수치는 개수 · 비율뿐
klm_format <- function(tab, snap = NULL) {
  L <- character(0)
  if (!is.null(snap)) {
    b <- unlist(snap$bad_lines); b <- b[b > 0]
    if (length(b)) L <- c(L, sprintf("⚠ 원장 손상 줄: %s", paste(sprintf("%s %d", names(b), b), collapse = " · ")))
    xq <- snap$excluded$quarantined %||% 0L; xi <- snap$excluded$input_check %||% 0L
    if (xq > 0L || xi > 0L)
      L <- c(L, sprintf("⚠ 결과 원장에서 뺀 줄(설계 입력과 같은 규율): 격리 %d · 처방 입력 검사 미통과 %d%s", xq, xi,
                        if (xi > 0L) paste0("(", paste(utils::head(unlist(snap$excluded$input_check_ids), 5), collapse = ","), ")") else ""))
    st <- unlist(snap$r7_noise_streak)
    L <- c(L, sprintf("학습 고리: 닫힌 라운드 누계 %d · 열린 탐침 %d · 생성기 %s · 개정 근거로 안 쓴 닫힌 사슬 %d%s",
                      snap$closed_rounds_total, snap$open_probes, snap$generator_current, snap$unreviewed_closed_chains,
                      if (length(st)) paste0(" · 연속 잡음 ", paste(sprintf("%s %d", names(st), st), collapse = " · ")) else ""))
  }
  f <- function(x) if (is.na(x)) "—" else formatC(x, format = "f", digits = 2)
  L <- c(L, paste0("주 | 라운드 닫힘 | 사슬 닫힘 | 새 탐침/이어받음 | 상설 자격/판정 | 사전 감사(논문별 첫 검사 통과/논문 수 · 재시도 뒤 통과 · 회차 소진 · 사건 · 논문 키 없음)",
                   " | 충실도 1회 통과/전체 (걸음 지표 = rxg_scorecard · 이 표에 없다)"))
  for (i in seq_len(nrow(tab))) {
    t <- tab[i, ]
    L <- c(L, sprintf("%s | %d | %d | %d/%d | %d/%d | 1차 통과 %d/%d(%s) · 재시도 뒤 통과 %d · 회차 소진 %d · 사건 %d · 키 없음 %d | %d/%d",
                      t$week, t$rounds_closed, t$chains_closed, t$probes_new, t$probes_consumed,
                      t$standing_qualified, t$standing_verdicts, t$preaudit_pass, t$preaudit_n, f(t$first_pass_rate),
                      t$preaudit_retry_pass, t$preaudit_exhausted, t$preaudit_events, t$preaudit_unkeyed,
                      t$fidelity_first_pass, t$fidelity_n))
  }
  L
}

if (sys.nframe() == 0L && !interactive()) {
  a <- commandArgs(trailingOnly = TRUE)
  opt <- function(f, d = NULL) { i <- match(f, a); if (!is.na(i) && length(a) > i) a[i + 1L] else d }
  root <- opt("--root", Sys.getenv("QM_ROOT", getwd())); weeks <- as.integer(opt("--weeks", "8"))
  ev <- klm_collect(root); tab <- klm_weekly(ev, weeks); sn <- klm_snapshot(ev, root)
  if ("--json" %in% a) cat(toJSON(list(weekly = tab, snapshot = sn), auto_unbox = TRUE, pretty = TRUE, na = "null"), "\n")
  else cat(klm_format(tab, sn), sep = "\n")
}
