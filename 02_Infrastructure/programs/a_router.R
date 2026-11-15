#!/usr/bin/env Rscript
#==============================================================================
# a_router.R — 권위 등급 A 가 나오면 곧바로 Judge 로 (2026-11-15 · 도훈 "A가 나오면 바로 judge로 가게 배선해줘" · A-ROUTE-IMMEDIATE-JUDGE-20261115)
#
# 왜: 셀 엔진 측정(상설 판 · 강화 사슬 · 프로그램 라운드 칸)은 A 여도 구판 요청 judge_request.json(트리거 아님)만 남긴다
#   (run_paper_replication.R §11 — 관문은 10-13 에 퇴역한 강화 러너가 태웠다). v10.2 round_candidate_gate.R 은 라운드 · 사슬을
#   닫을 때 최종 후보만 관문에 태운다. 그래서 11-15 상설 판 A(P1S03_FVALU_RX0)가 아무 신호 없이 묻혔다.
# 무엇(8분 레인 틱마다 — 02_Infrastructure/ops/a_route_tick.sh):
#   ① 찾기 — 구판 요청만 있고 관문 결과(judge_request.eligible.json · judge_request.held.json · a_route.json)가 없는 A 산출
#   ② 주인 — 상설 판 항목(원장 마지막 판정 qualify) · 강화 사슬 기준 칸 · 걸음(사슬 원장) · 그 밖(프로그램 라운드 칸 · 모름)
#   ③ 후보만 태운다 — 상설 판 통과 항목 · 열린 사슬의 지금 머리. 기각 걸음 · 미통과 항목 · 라운드 칸은 후보가 아니다:
#      사전등록 선택 규칙(보는 창 · τ_D 이전)이 고르지 않은 칸을 전기간 등급으로 골라 올리면 선택 규율(τ_D)을 어긴다 → 기록 · 알림만.
#      라운드 칸의 최종 후보는 라운드 닫기 관문(register.R rc_close_finalize)이 태운다.
#   ④ 스윕이면 선택 현실 점검 재채점(selection_regrade.R::sr_regrade) — 시행 집합은 코어와 같은 계산:
#      사슬 머리 = p4.R rc_p4_close 의 집합(기준 칸 + 판정 걸음 + 같은 기저 다른 사슬 + 원천 시행)
#      상설 판 자체 사양 항목 = 사슬 등록(rc_p4_register)의 원천 시행(원천 라운드의 모든 칸) + 그 항목 산출
#      재채점 뒤 A 면 A 자격 관문(round_candidate_gate.R::rcg_route) → judge_request.eligible.json(Judge 트리거) | judge_request.held.json
#   ⑤ 산출 폴더 a_route.json · 원장 06_Registry/a_route_ledger.jsonl · 텔레그램 [Judge] 1통(산출마다 한 번)
#   Judge 스폰은 a_route_tick.sh → judge_run.sh(무인 · 메모리 관문 · 하루 상한)가 한다.
# 판정 핀 파일 무접촉 — 코어(round_core v5) · 계약 · 재채점 · 관문은 읽기 · 호출만. 쓰기 = 후보 산출 폴더(재채점 · 관문 결과 · a_route.json) · 원장.
# 사용: Rscript 02_Infrastructure/programs/a_router.R [--write] [--dir <산출 폴더>] [--no-tg]
#   기본 드라이런(쓰기 0 · 재채점 write = FALSE · 관문 write = FALSE). --dir = 그 폴더 하나만(설정이 꺼져 있어도).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd()))); setwd(ROOT)
ARGS <- commandArgs(trailingOnly = TRUE)
WRITE <- "--write" %in% ARGS; NO_TG <- "--no-tg" %in% ARGS
ONE <- { i <- match("--dir", ARGS); if (is.na(i) || i == length(ARGS)) NA_character_ else ARGS[i + 1L] }
CFG <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/a_router.json"), simplifyVector = FALSE), error = function(e) NULL)
if (is.null(CFG)) { cat("[a_router] 설정 06_Registry/a_router.json 판독 불가 — 아무것도 하지 않는다\n"); quit(status = 2L) }
if (!isTRUE(CFG$enabled) && is.na(ONE)) { cat("[a_router] 꺼짐(a_router.json enabled = false)\n"); quit(status = 0L) }
SINCE <- as.character(CFG$scan_since %||% "2026-11-10")
LEDGER <- file.path(ROOT, "06_Registry/a_route_ledger.jsonl")
OUTCOME_FILES <- c("judge_request.eligible.json", "judge_request.held.json", "a_route.json")

rd <- function(f) tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
rdl <- function(f) if (!file.exists(f)) list() else Filter(Negate(is.null), lapply(readLines(f, warn = FALSE, encoding = "UTF-8"),
                                                     function(l) tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL)))
bn <- function(p) if (is.null(p) || !length(p) || is.na(p[1])) NA_character_ else basename(sub("/+$", "", gsub("\\\\", "/", as.character(p)[1])))
now_iso <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
s1 <- function(x) if (is.null(x) || !length(x)) NA_character_ else as.character(x)[1]
rel <- function(p) sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", as.character(p)[1]))

## ── 코어 · 재채점 · 관문 적재(읽기 · 호출만) ────────────────────────────────
load_core <- function() {
  if (exists("rc_p4_base_pool", mode = "function")) return(invisible(TRUE))
  invisible(utils::capture.output(suppressMessages(source(file.path(ROOT, "04_Research/programs/_lib/round_core/v5/load.R")))))
}
## 재채점 · 관문은 라우팅할 산출이 있을 때만 적재한다(8분 틱 대부분은 대상 0 — 적재 비용을 매번 내지 않게)
SRE <- new.env(parent = globalenv()); GTE <- new.env(parent = globalenv())
load_gates <- function() {
  if (!exists("sr_regrade", envir = SRE, inherits = FALSE))
    invisible(utils::capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/programs/selection_regrade.R"), envir = SRE, keep.source = FALSE))))
  if (!exists("rcg_route", envir = GTE, inherits = FALSE))
    invisible(utils::capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/programs/round_candidate_gate.R"), envir = GTE, keep.source = FALSE))))
}

## ── ① 찾기 ──────────────────────────────────────────────────────────────
ar_scan <- function() {
  ds <- list.dirs(file.path(ROOT, "stage_artifacts/replication"), recursive = FALSE, full.names = TRUE)
  ds <- ds[grepl("^[0-9]{8}_", basename(ds)) & substr(basename(ds), 1, 8) >= gsub("-", "", SINCE)]
  ds[vapply(ds, function(d) file.exists(file.path(d, "judge_request.json")) && !any(file.exists(file.path(d, OUTCOME_FILES))), TRUE)]
}

## ── ② 주인 ──────────────────────────────────────────────────────────────
ar_boards <- function() {
  out <- list()
  for (f in Sys.glob(file.path(ROOT, "04_Research/programs/*/*/round_spec.json"))) {
    s <- rd(f); if (!isTRUE(s$standing)) next
    d <- dirname(f); rid <- basename(d); prog <- s1(s$program %||% basename(dirname(d)))
    out[[length(out) + 1L]] <- list(dir = d, round_id = rid, program = prog,
                                    ledger = file.path(ROOT, "stage_artifacts/programs", prog, rid, "standing_ledger.jsonl"))
  }
  out
}
ar_find_standing <- function(target) {
  for (b in ar_boards()) for (f in Sys.glob(file.path(b$dir, "results", "*.json"))) {
    r <- rd(f); if (!is.list(r) || !identical(bn(r$artifacts), target)) next
    code <- s1(r$code %||% sub("[.]json$", "", basename(f)))
    v <- Filter(function(x) identical(x$event, "verdict") && identical(s1(x$code), code), rdl(b$ledger))
    return(c(b, list(kind = "standing", code = code, spec = s1(r$spec), qualify = if (length(v)) isTRUE(v[[length(v)]]$qualify) else NA)))
  }
  NULL
}
ar_find_chain <- function(target) {
  for (f in Sys.glob(file.path(ROOT, "04_Research/programs/P4_ASSEMBLY/*/chain_steps.jsonl"))) {
    for (x in rdl(f)) if (s1(x$event) %in% c("base_measured", "step_measured") && identical(bn(x$artifacts), target))
      return(list(kind = "chain", dir = dirname(f), chain_id = basename(dirname(f)), k = as.integer(x$k %||% 0L), event = s1(x$event)))
  }
  NULL
}
ar_find_round_cell <- function(target) {
  for (f in Sys.glob(file.path(ROOT, "04_Research/programs/*/*/results/*.json"))) {
    r <- rd(f); if (is.list(r) && identical(bn(r$artifacts), target)) return(list(kind = "round_cell", round_dir = dirname(dirname(f)), code = s1(r$code)))
  }
  NULL
}

## ── ④ 시행 집합(코어와 같은 계산) ───────────────────────────────────────
ar_trials_chain <- function(ch) {
  load_core()
  st <- .rcp4_state(ch$dir, ROOT)
  if (isTRUE(st$closed)) return(list(not_candidate = sprintf("사슬 %s 은 이미 닫혔다 — 최종 후보는 닫기 관문이 태웠다", ch$chain_id)))
  if (!identical(as.integer(st$head_k), ch$k))
    return(list(not_candidate = sprintf("사슬 %s 의 지금 머리 = k%d · 이 칸 = k%d — 사전등록 채택 규칙(보는 창)이 고르지 않은 칸", ch$chain_id, as.integer(st$head_k), ch$k)))
  ## p4.R rc_p4_close 와 같은 순서 · 같은 함수(기준 칸 + 판정 걸음 → 같은 기저 다른 사슬 → 원천 시행)
  trials <- unique(na.omit(c(.rcp4_abs(.rcs_str(st$base_meas$artifacts), ROOT), vapply(st$results, function(r) .rcp4_abs(.rcs_str(r$artifacts), ROOT), ""))))
  expected <- rc_p4_expected_trials(st$base_meas$artifacts, st$results)
  sb <- .rcp4_same_base_trials(st, ROOT, NULL)
  trials <- unique(c(trials, sb$trials)); expected$n_trials <- expected$n_trials + sb$n; expected$ids <- unique(c(expected$ids, sb$ids))
  sx <- .rcp4_src_expected(st$reg$source_trials, ROOT)
  if (sx$n > 0L) { trials <- unique(c(trials, sx$trials)); expected$n_trials <- expected$n_trials + sx$n; expected$ids <- unique(c(expected$ids, sx$ids)) }
  list(trials = trials, expected = expected, spec = .rcp4_abs(.rcp4_cand_spec(st, ch$k), ROOT), sid = sprintf("%s_k%s", st$spec$chain_id, ch$k),
       basis = "사슬 닫기와 같은 시행 집합(기준 칸 + 판정 걸음 + 같은 기저 다른 사슬 + 원천 시행)")
}
ar_trials_standing <- function(sd, cand_dir, au) {
  load_core()
  key <- sprintf("standing:%s:%s", sd$round_id, sd$code)
  P <- rc_p4_base_pool(ROOT); row <- P[P$key == key]
  if (!nrow(row)) return(list(hold = "trial_set_unknown", why = sprintf("기저 풀에 %s 행이 없다", key)))
  if (!isTRUE(as.logical(row$own_spec_engine[1])))
    return(list(hold = "trial_set_unknown", why = "자체 사양 항목이 아니다 — 원천 시행 집합 기록이 없다(레인 · 등록부 항목은 사슬 닫기에서 재채점)"))
  ## p4.R rc_p4_register(자체 사양 기저)와 같은 원천 시행 계산 — 원천 라운드의 모든 칸 · 검증 불가 · 산출 없음 = 보류(fail-closed)
  fr <- strsplit(.rcs_or(.rcs_str(row$source_rounds[1]), ""), ",", fixed = TRUE)[[1]]
  now <- rc_standing_source_cells("P1_RETURN", ROOT, NULL)
  o <- .rcs_own_source(now, .rcs_str(row$engine_md5[1]), if ("family_root" %in% names(row)) .rcs_str(row$family_root[1]) else NA_character_)
  rids <- sort(unique(c(fr[nzchar(fr)], o$rounds)))
  RNw <- attr(now, "rounds"); nvr <- setdiff(rids, if (is.data.frame(RNw)) RNw$round_id else character(0))
  srt <- rc_p4_source_trials(rids, "P1_RETURN", ROOT, NULL, src = now)
  miss <- c(if (!is.null(o$unverified)) sprintf("%s:검증 불가", o$unverified$round_id), if (length(nvr)) sprintf("%s:검증된 등록 라운드 아님", nvr), srt$missing)
  if (length(miss)) return(list(hold = "source_trials_missing", why = paste(head(miss, 8), collapse = ", ")))
  sx <- .rcp4_src_expected(srt$trials, ROOT)
  list(trials = unique(c(cand_dir, sx$trials)), expected = list(n_trials = 1L + sx$n, ids = unique(c(bn(cand_dir), sx$ids))),
       spec = sd$spec, sid = s1(au$strategy_id), basis = sprintf("원천 라운드 %s 의 모든 칸(사슬 등록과 같은 계산) + 이 항목", paste(rids, collapse = ",")))
}

## ── ⑤ 기록 · 알림 ──────────────────────────────────────────────────────
ar_record <- function(d, rec) {
  rec <- c(list(schema = "a_route_v1", at = now_iso(), artifacts = rel(d), decided = "A-ROUTE-IMMEDIATE-JUDGE-20261115"), rec)
  if (!WRITE) return(invisible(rec))
  tf <- file.path(d, "a_route.json.tmp"); writeLines(toJSON(rec, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), tf, useBytes = TRUE)
  file.rename(tf, file.path(d, "a_route.json"))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null"), "\n", file = LEDGER, append = TRUE, sep = "")
  invisible(rec)
}
ar_tg <- function(rec) {   # 알림 뒤 rec 를 그대로 돌려준다(호출자가 요약 줄을 쓴다)
  if (!WRITE || NO_TG) return(invisible(rec))
  st <- s1(rec$status)
  hd <- switch(st, eligible = "Judge 요청 발행 — 다음 틱에 Judge 스폰(메모리 관문 · 하루 상한)", held = "A 자격 관문 보류 — 스폰 없음",
                 not_a_after = "선택 현실 점검 재채점 뒤 A 아님 — 스폰 없음", not_candidate = "후보 아님(사전등록 선택 규칙이 고르지 않은 칸) — 기록만",
                 sprintf("라우팅 %s", st))
  kv <- list(`대상` = s1(rec$code %||% rec$artifacts), `주인` = s1(rec$owner), `결과` = st)
  if (!is.null(rec$trials_n)) kv$`시행 집합` <- sprintf("%s칸", rec$trials_n)
  if (!is.null(rec$grade_after)) kv$`재채점 등급` <- s1(rec$grade_after)
  if (length(rec$gate_codes)) kv$`관문 사유` <- substr(paste(unlist(rec$gate_codes), collapse = " · "), 1, 60)
  ## 본문 문장(발송기 최소 분량 · text ≥ 30자) — 무엇이 일어났고 다음에 무엇이 되는가
  why <- switch(st,
    eligible = sprintf("시행 %s칸 집합의 선택 현실 점검으로 다시 채점해도 A(%s)라 A 자격 관문을 통과해 Judge 요청을 냈습니다. 메모리 관문이 열리는 첫 8분 틱에 Judge 가 무인으로 뜨고, 판결은 [Judge] PIT 검증 알림으로 옵니다.",
                       s1(rec$trials_n), substr(s1(rec$regrade_reason), 1, 40)),
    held = sprintf("권위 등급 A 지만 Judge 요청을 내지 않았습니다 — %s. 사유를 고치면 다음 틱에 다시 볼 수 있도록 a_route.json 을 지우면 됩니다.", substr(s1(rec$why %||% paste(unlist(rec$gate_codes), collapse = " · ")), 1, 160)),
    not_a_after = sprintf("셀 측정 때는 A 였지만 시행 %s칸 집합의 선택 현실 점검 재채점 뒤 %s 입니다 — Judge 로 보내지 않습니다.", s1(rec$trials_n), s1(rec$grade_after)),
    not_candidate = sprintf("%s. 사전등록 선택 규칙(보는 창 · τ_D 이전)이 고르지 않은 칸을 전기간 등급으로 골라 올리지 않으므로 기록만 남깁니다.", substr(s1(rec$why), 1, 160)),
    sprintf("라우팅 결과 %s — %s", st, substr(s1(rec$why), 1, 160)))
  why <- substr(why, 1, 218)   # 발송기 text 상한 220자
  tryCatch({
    invisible(utils::capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))))
    tg_agent_brief(agent = "Judge", title = sprintf("[Judge] A 라우팅 — %s", s1(rec$code %||% bn(rec$artifacts))),
                   sections = list(list(type = "summary", emoji = "⚖️", body = hd), list(type = "text", heading = "무슨 일", body = why),
                                   list(type = "kv", heading = "라우팅", kv = kv)))
  }, error = function(e) cat("[a_router] 텔레그램 실패(라우팅은 그대로): ", conditionMessage(e), "\n"))
  invisible(rec)
}

## ── 한 산출 ────────────────────────────────────────────────────────────
ar_route <- function(d) {
  load_gates()
  d <- sub("/+$", "", gsub("\\\\", "/", d)); tgt <- bn(d)
  au <- rd(file.path(d, "authoritative_remeasure.json"))
  if (is.null(au)) return(ar_record(d, list(status = "error", why = "권위 기록 판독 불가")))
  if (!identical(s1(au$essence_grade), "A")) return(ar_record(d, list(status = "skip", why = sprintf("권위 등급 %s — A 아님", s1(au$essence_grade)))))
  sd <- ar_find_standing(tgt); ch <- if (is.null(sd)) ar_find_chain(tgt) else NULL
  rc <- if (is.null(sd) && is.null(ch)) ar_find_round_cell(tgt) else NULL
  owner <- if (!is.null(sd)) sprintf("상설 판 %s", sd$round_id) else if (!is.null(ch)) sprintf("강화 사슬 %s k%d", ch$chain_id, ch$k) else
    if (!is.null(rc)) sprintf("라운드 %s", basename(rc$round_dir)) else "모름"
  code <- s1(sd$code %||% (if (!is.null(ch)) sprintf("%s_k%d", ch$chain_id, ch$k) else NULL) %||% rc$code %||% au$strategy_name)
  base <- list(code = code, owner = owner, strategy_id = s1(au$strategy_id), selection_type = s1(au$selection_type))
  if (!is.null(rc)) return(ar_tg(ar_record(d, c(base, list(status = "not_candidate", why = "프로그램 라운드 칸 — 최종 후보는 라운드 닫기 관문(rc_close_finalize)이 태운다")))))
  if (is.null(sd) && is.null(ch)) return(ar_tg(ar_record(d, c(base, list(status = "held", gate_codes = list("owner_unknown"), why = "주인(상설 판 · 사슬 · 라운드)을 찾지 못했다")))))
  if (!is.null(sd) && !isTRUE(sd$qualify))
    return(ar_tg(ar_record(d, c(base, list(status = "not_candidate", why = sprintf("상설 판 판정 qualify = %s — 통과 항목만 후보", s1(sd$qualify)))))))
  sweep <- identical(s1(au$selection_type), "sweep")
  ## 사슬은 스윕 여부와 무관하게 '지금 머리'만 후보다(기각 · 밀려난 걸음 = 후보 아님) — 머리 판정이 시행 집합 계산 안에 있다
  T <- if (!is.null(ch)) ar_trials_chain(ch) else if (sweep) ar_trials_standing(sd, d, au) else NULL
  if (!is.null(T$not_candidate)) return(ar_tg(ar_record(d, c(base, list(status = "not_candidate", why = T$not_candidate)))))
  if (!is.null(T$hold)) return(ar_tg(ar_record(d, c(base, list(status = "held", gate_codes = list(T$hold), why = T$why)))))
  spec <- if (!is.null(T)) T$spec else if (!is.null(sd)) sd$spec else NA_character_
  sid <- if (!is.null(T)) T$sid else s1(au$strategy_id)
  reg <- NULL
  if (sweep) {
    reg <- tryCatch(SRE$sr_regrade(d, T$trials, root = ROOT, write = WRITE, expected = T$expected), error = function(e) list(status = paste0("error: ", conditionMessage(e))))
    base <- c(base, list(trials_n = length(T$trials), expected_n = T$expected$n_trials, trials_basis = T$basis, regrade_status = s1(reg$status),
                         grade_before = s1(reg$grade_before), grade_after = s1(reg$grade_after), regrade_reason = s1(reg$reason)))
    if (!identical(s1(reg$status), "ok")) return(ar_tg(ar_record(d, c(base, list(status = "held", gate_codes = list("regrade_error"), why = s1(reg$status))))))
    if (!identical(s1(reg$grade_after), "A")) {
      if (WRITE && is.function(GTE$rcg_withdraw)) try(GTE$rcg_withdraw(d, s1(reg$grade_after), write = TRUE), silent = TRUE)
      return(ar_tg(ar_record(d, c(base, list(status = "not_a_after", why = sprintf("선택 현실 점검 재채점 뒤 %s", s1(reg$grade_after)))))))
    }
    if (!WRITE) return(ar_record(d, c(base, list(status = "dry_regrade_a", why = "드라이런 — 재채점 A(쓰지 않음) · 관문은 쓰기 실행에서(재채점 기록이 있어야 선택 관문을 넘는다)"))))
  }
  g <- tryCatch(GTE$rcg_route(d, sid, spec, ROOT, WRITE), error = function(e) list(action = "error", codes = list(conditionMessage(e))))
  st <- if (identical(s1(g$action), "publish")) "eligible" else if (identical(s1(g$action), "hold")) "held" else s1(g$action)
  ar_tg(ar_record(d, c(base, list(status = if (WRITE) st else paste0("dry_", st), gate_action = s1(g$action), gate_codes = as.list(unlist(g$codes)),
                                  request = if (is.null(g$path) || all(is.na(g$path))) NA_character_ else rel(g$path), strategy_id_gate = sid))))
}

## ── 실행 ───────────────────────────────────────────────────────────────
## --notify <폴더> — 이미 쓴 a_route.json 으로 알림만 다시 보낸다(발송 실패 뒤 · 라우팅 다시 안 함)
NOTI <- { i <- match("--notify", ARGS); if (is.na(i) || i == length(ARGS)) NA_character_ else ARGS[i + 1L] }
if (!is.na(NOTI)) {
  rec <- rd(file.path(NOTI, "a_route.json")); if (is.null(rec)) { cat("[a_router] a_route.json 없음: ", NOTI, "\n"); quit(status = 2L) }
  WRITE <- TRUE; ar_tg(rec); cat(sprintf("[a_router] 알림 다시 시도 — %s · %s(실패면 바로 위 줄에 사유)\n", s1(rec$code), s1(rec$status))); quit(status = 0L)
}
targets <- if (!is.na(ONE)) ONE else ar_scan()
if (!length(targets)) { cat(sprintf("[a_router] %s 라우팅 대기 A 없음(%s 이후 · 구판 요청만 있는 산출)\n", format(Sys.time(), "%F %T"), SINCE)); quit(status = 0L) }
for (d in targets) {
  r <- tryCatch(ar_route(d), error = function(e) ar_record(d, list(status = "error", why = conditionMessage(e))))
  cat(sprintf("[a_router] %s · %s · %s · %s%s\n", bn(d), s1(r$code %||% "?"), s1(r$owner %||% "?"), s1(r$status),
              if (!is.null(r$why)) paste0(" — ", s1(r$why)) else if (length(r$gate_codes)) paste0(" — ", paste(unlist(r$gate_codes), collapse = " · ")) else ""))
  if (!is.null(r$trials_n)) cat(sprintf("           시행 %s칸(기대 %s) · 재채점 %s → %s · %s\n", r$trials_n, s1(r$expected_n), s1(r$grade_before), s1(r$grade_after),
                                        substr(s1(r$regrade_reason), 1, 160)))
}
