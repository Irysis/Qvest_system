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
                 "preaudit_n", "preaudit_pass", "first_pass_rate",
                 "fidelity_n", "fidelity_first_pass")

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
.klm_row <- function(src, kind, at, ...) data.frame(src = src, kind = kind, at = at, ..., stringsAsFactors = FALSE)

#' 원천 4개 → 사건 표(src · kind · at · n · flag · program · key) + 손상 줄 수
klm_collect <- function(root = Sys.getenv("QM_ROOT", getwd()), outcomes_path = NULL,
                        standing_files = NULL, lane_log = NULL, sa_root = Sys.getenv("RC_SA_ROOT", root)) {
  root <- gsub("\\\\", "/", root)
  op <- outcomes_path %||% file.path(root, "06_Registry", "round_outcomes.jsonl")
  sf <- standing_files %||% unique(c(Sys.glob(file.path(sa_root, "stage_artifacts/programs/*/*/standing_ledger.jsonl")),
                                      Sys.glob(file.path(root, "stage_artifacts/programs/*/*/standing_ledger.jsonl"))))
  ll <- lane_log %||% file.path(root, ".cache", "reinforce_auto_log.jsonl")
  rows <- list(); bad <- c(outcomes = 0L, standing = 0L, lane_log = 0L)
  add <- function(r) rows[[length(rows) + 1L]] <<- r

  o <- .klm_jsonl(op); bad["outcomes"] <- o$bad
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
    if (identical(e, "preaudit"))
      add(.klm_row("lane_log", "preaudit", .klm_ts(r$ts), n = 1L, flag = identical(as.character(r$rc %||% ""), "0"),
                   program = NA_character_, key = as.character(r$paper %||% NA)))
    else if (identical(e, "fidelity_audit_verdict"))
      add(.klm_row("lane_log", "fidelity", .klm_ts(r$ts), n = 1L,
                   flag = identical(as.character(r$action %||% ""), "proceed") && identical(as.integer(r$retries %||% -1L), 0L),
                   program = NA_character_, key = NA_character_))
  }
  ev <- if (length(rows)) do.call(rbind, rows) else
    data.frame(src = character(0), kind = character(0), at = as.POSIXct(character(0)), n = integer(0), flag = logical(0),
               program = character(0), key = character(0), stringsAsFactors = FALSE)
  list(events = ev, bad = bad, outcomes_path = op)
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
  out <- do.call(rbind, lapply(wk, function(w) {
    pn <- cnt(w, "preaudit"); pp <- cnt(w, "preaudit", TRUE)
    data.frame(week = w, rounds_closed = cnt(w, "round_closed"), chains_closed = cnt(w, "chain_closed"),
               probes_new = sumn(w, "round_closed") + sumn(w, "chain_closed"), probes_consumed = cnt(w, "probe_consumed"),
               standing_verdicts = cnt(w, "standing_verdict"), standing_qualified = cnt(w, "standing_verdict", TRUE),
               preaudit_n = pn, preaudit_pass = pp, first_pass_rate = rate(pp, pn),
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
  o <- .klm_jsonl(ev$outcomes_path)$recs
  o <- Filter(function(r) identical(r$schema, "round_outcome_v1"), o)
  rounds <- Filter(function(r) identical(r$kind %||% "round", "round"), o)
  used <- vapply(Filter(function(r) identical(r$kind, "probe_consumed"), o), function(r) as.character(r$ref %||% ""), "")
  refs <- unlist(lapply(rounds, function(r) if (length(r$probes)) sprintf("%s#%d", r$round_id, seq_along(r$probes)) else character(0)))
  open_n <- length(setdiff(refs, used))
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
       bad_lines = as.list(ev$bad))
}

#' 사람이 읽는 줄(아침 면 · 생성기 검토용) — 수치는 개수 · 비율뿐
klm_format <- function(tab, snap = NULL) {
  L <- character(0)
  if (!is.null(snap)) {
    b <- unlist(snap$bad_lines); b <- b[b > 0]
    if (length(b)) L <- c(L, sprintf("⚠ 원장 손상 줄: %s", paste(sprintf("%s %d", names(b), b), collapse = " · ")))
    st <- unlist(snap$r7_noise_streak)
    L <- c(L, sprintf("학습 고리: 닫힌 라운드 누계 %d · 열린 탐침 %d · 생성기 %s · 개정 근거로 안 쓴 닫힌 사슬 %d%s",
                      snap$closed_rounds_total, snap$open_probes, snap$generator_current, snap$unreviewed_closed_chains,
                      if (length(st)) paste0(" · 연속 잡음 ", paste(sprintf("%s %d", names(st), st), collapse = " · ")) else ""))
  }
  f <- function(x) if (is.na(x)) "—" else formatC(x, format = "f", digits = 2)
  L <- c(L, "주 | 라운드 닫힘 | 사슬 닫힘 | 새 탐침/이어받음 | 상설 자격/판정 | 사전 감사 통과/전체(1차 통과율) | 충실도 1회 통과/전체 (걸음 지표 = rxg_scorecard)")
  for (i in seq_len(nrow(tab))) {
    t <- tab[i, ]
    L <- c(L, sprintf("%s | %d | %d | %d/%d | %d/%d | %d/%d (%s) | %d/%d", t$week, t$rounds_closed, t$chains_closed,
                      t$probes_new, t$probes_consumed,
                      t$standing_qualified, t$standing_verdicts, t$preaudit_pass, t$preaudit_n, f(t$first_pass_rate),
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
