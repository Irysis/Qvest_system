#!/usr/bin/env Rscript
#==============================================================================
# test_rf_notify_grade_a_disposition.R — Q14 (QEPM 감사 2026-09-25 · 도훈 QEPM-IMMEDIATE-FIXES)
#
# 대상: 02_Infrastructure/ops/rf_auto_notify.R 의 Grade A 텔레그램 문구.
#   구판 = 고정 문자열 "무인 정지, 확인 요망" · "러너가 스스로 멈췄습니다" · "처분: 자동 진행 정지" ·
#          "요청 파일: qepm/mailbox/judge_request.json"(단일) — 현행 운영과 반대.
#   현행(P0-12 · reinforce_auto_parallel.R::.grade_a_enqueue · .a_hold_record) = 러너는 멈추지 않는다 ·
#          A 자격 관문 통과분만 후보별 qepm/mailbox/judge_request_<BID>_<n>.json 발행(grade_a_queue awaiting_judge) ·
#          보류 = status held:<코드> · entry active 유지.
#   신판 = rf_grade_a_disposition(base_id, n, root) — 문구를 그 칸의 대기열 기록에서 재도출.
#
# ★정본 무접촉: 입력은 전부 tempdir 샌드박스(대기열·원장 합성). 렌더 축(W)은 샌드박스 루트에 **텔레그램 스텁**을
#   두고 rf_auto_notify 를 돌린다 — 실제 발송 경로(telegram_notify.R)는 로드하지 않는다. 차트 함수도 스텁.
# 축:
#   U1 발행(awaiting_judge · 절대경로 기록) → 후보별 상대경로 · "요청 발행"
#   U2 발행(백슬래시 경로 기록) → 같은 상대경로로 정규화
#   U3 보류(held:<코드>) → 코드 사유 · entry active 유지 · 발행 주장 없음
#   U4 기록 없음 → unrecorded · "없습니다" · 발행 주장 없음
#   U5 비정형 status → "비정형(status=…)"
#   U6 대기열 파일 부재 → unrecorded · 오류 없음
#   U7 파일명 규칙 = 발행자(reinforce_auto_parallel.R::.grade_a_enqueue 의 sprintf)와 동일 — AST 에서 재도출해 평가
#   U8 전 출력에 구 문구(정지·멈췄·단일 judge_request.json) 0
#   U9 요약 길이 ∈ [SUMMARY_MIN, SUMMARY_MAX](telegram_notify.R .TG_CONFIG 재도출) — 최악 입력 4상태
#       (초판 드라이런: 보류 코드를 요약에 넣어 128자 → tg_format_summary stop · A 알림 전체 결정론적 실패)
#   U10 다른 루트에서 기록된 절대경로 → qepm/mailbox/… 상대 표기
#   U11 대기열 비정형 줄(리스트 아닌 원소) 혼입 → 오류 없이 정상 줄 판정
#   S1 정적: rf_auto_notify.R 실행 코드(주석 제외)에 구 문구 0
#   W1~W3 렌더: rf_auto_notify(kind="grade_a") 의 표제·요약·'다음' 이 처분 판정과 같은 값(발행·보류 두 칸)
#   W4 block 경로는 처분 문구를 쓰지 않는다(음성 대조)
# 돌연변이(수동 · 보고서): 구판 파일 → U*/S1/W* red · 파일명 규칙 변경 → U7 red · 다음 항목 고정 문자열 → W red
#
# 요약 규약: 마지막 줄 {"test":"rf_notify_grade_a_disposition","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.MARKER <- "02_Infrastructure/ops/rf_auto_notify.R"
.PRODUCER <- "02_Infrastructure/ops/reinforce_auto_parallel.R"
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE); m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return(""); dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJ <- ""
for (.c in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (nzchar(.sd)) file.path(.sd, "..", "..") else "", getwd())) {
  if (nzchar(.c) && file.exists(file.path(.c, .MARKER))) { PROJ <- .c; break }
}
if (!nzchar(PROJ)) stop("[test_rf_notify_grade_a_disposition] PROJECT_ROOT 해석 실패 — 표지 부재")

PASS <- 0L; FAIL <- 0L
ok  <- function(n) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", n)) }
bad <- function(n, d) { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s  (%s)\n", n, d)) }
STALE <- c("자동 진행 정지", "무인 정지", "스스로 멈췄", "qepm/mailbox/judge_request.json")
has_stale <- function(txt) any(vapply(STALE, function(s) grepl(s, txt, fixed = TRUE), logical(1)))
flat <- function(d) paste(c(d$title, d$summary, d$items), collapse = "\n")

BASE <- file.path(tempdir(), paste0("rfgad_", Sys.getpid()))
unlink(BASE, recursive = TRUE); dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
.cleanup <- function() unlink(BASE, recursive = TRUE)   # top-level on.exit 금지(금칙②)
fwd <- function(p) gsub("\\\\", "/", p)

cat("=== test_rf_notify_grade_a_disposition (Q14 · 샌드박스) ===\n")

#──────────────────────────────────────────────────────────────────────────────
# U — 처분 판정 함수 단위 (정본 파일에서 정의식만 파싱해 격리 환경에 평가 — 파일 최상위 source 부작용 없음)
#──────────────────────────────────────────────────────────────────────────────
EX <- tryCatch(parse(file.path(PROJ, .MARKER), keep.source = FALSE), error = function(e) NULL)
.def <- if (is.null(EX)) NULL else Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                                            identical(e[[2]], as.name("rf_grade_a_disposition")), as.list(EX))
UE <- new.env(parent = globalenv())
if (length(.def) != 1L) {
  bad("U0 정의", "rf_grade_a_disposition 정의가 정확히 1개가 아니다(구판이면 0)")
  gad <- NULL
} else {
  assign("ROOT", fwd(BASE), envir = UE); assign("fromJSON", jsonlite::fromJSON, envir = UE)
  eval(.def[[1]], envir = UE); gad <- get("rf_grade_a_disposition", envir = UE)
  ok("U0 정의 — rf_grade_a_disposition 1개")
}

SB <- fwd(file.path(BASE, "root_u"))
dir.create(file.path(SB, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
Q <- list(schema = "grade_a_queue_v1", entries = list(
  list(base_id = "RP_T_1", attempt = 7L, cell = "B5_7", status = "awaiting_judge",
       judge_request = file.path(SB, "qepm/mailbox/judge_request_RP_T_1_7.json")),
  list(base_id = "RP_T_1", attempt = 8L, cell = "B2_8", status = "awaiting_judge",
       judge_request = gsub("/", "\\\\", file.path(SB, "qepm/mailbox/judge_request_RP_T_1_8.json"))),
  list(base_id = "RP_T_1", attempt = 6L, cell = "B5_6", status = "held:legacy_regime+adversary_unverified"),
  list(base_id = "RP_T_1", attempt = 10L, cell = "B2_10", status = "weird"),
  list(base_id = "RP a/b", attempt = 3L, cell = "B1_3", status = "awaiting_judge")))
writeLines(toJSON(Q, auto_unbox = TRUE, pretty = TRUE), file.path(SB, "06_Registry/grade_a_queue.json"))

if (!is.null(gad)) {
  d1 <- tryCatch(gad("RP_T_1", 7L, root = SB), error = function(e) list(err = conditionMessage(e)))
  if (identical(d1$state, "published") && any(grepl("qepm/mailbox/judge_request_RP_T_1_7.json", d1$items, fixed = TRUE)) &&
      !any(grepl(SB, d1$items, fixed = TRUE)) && grepl("요청 발행", d1$title, fixed = TRUE))
    ok("U1 발행 → 후보별 상대경로 · '요청 발행'") else bad("U1 발행", paste(unlist(d1), collapse = " | "))

  d2 <- tryCatch(gad("RP_T_1", 8L, root = SB), error = function(e) list(err = conditionMessage(e)))
  if (identical(d2$request, "qepm/mailbox/judge_request_RP_T_1_8.json")) ok("U2 백슬래시 기록 → 같은 상대경로")
  else bad("U2 백슬래시 정규화", as.character(d2$request %||% d2$err))

  d3 <- tryCatch(gad("RP_T_1", 6L, root = SB), error = function(e) list(err = conditionMessage(e)))
  if (identical(d3$state, "held") && grepl("보류", d3$title, fixed = TRUE) &&
      any(grepl("held:legacy_regime+adversary_unverified", d3$items, fixed = TRUE)) &&
      any(grepl("active 유지", d3$items, fixed = TRUE)) && !grepl("발행했습니다", d3$summary, fixed = TRUE) &&
      !any(grepl("^요청 파일", d3$items)))
    ok("U3 보류 → held 코드 사유 · entry active 유지 · 발행 주장 없음") else bad("U3 보류", paste(unlist(d3), collapse = " | "))

  d4 <- tryCatch(gad("RP_T_1", 11L, root = SB), error = function(e) list(err = conditionMessage(e)))
  if (identical(d4$state, "unrecorded") && grepl("없습니다", d4$summary, fixed = TRUE) &&
      !grepl("발행했습니다", d4$summary, fixed = TRUE) &&
      any(grepl("qepm/mailbox/judge_request_RP_T_1_11.json", d4$items, fixed = TRUE)))
    ok("U4 기록 없음 → unrecorded · 발행 주장 없음") else bad("U4 기록 없음", paste(unlist(d4), collapse = " | "))

  d5 <- tryCatch(gad("RP_T_1", 10L, root = SB), error = function(e) list(err = conditionMessage(e)))
  if (identical(d5$state, "unrecorded") && grepl("비정형", d5$summary, fixed = TRUE) &&
      any(grepl("status=비정형(weird)", d5$items, fixed = TRUE)))
    ok("U5 비정형 status → unrecorded · 요약 '비정형' · 항목 status=비정형(weird)") else bad("U5 비정형", paste(unlist(d5), collapse = " | "))

  d6 <- tryCatch(gad("RP_T_1", 7L, root = fwd(file.path(BASE, "no_such_root"))), error = function(e) list(err = conditionMessage(e)))
  if (identical(d6$state, "unrecorded") && is.null(d6$err)) ok("U6 대기열 파일 부재 → unrecorded · 오류 없음")
  else bad("U6 대기열 부재", paste(unlist(d6), collapse = " | "))

  # U7 — 발행자 파일명 규칙을 AST 에서 재도출해 같은 BID·n 으로 평가 (문자열 사본 금지)
  PX <- tryCatch(parse(file.path(PROJ, .PRODUCER), keep.source = FALSE), error = function(e) NULL)
  hits <- list()
  walk <- function(e) {
    if (is.call(e)) {
      if (identical(e[[1]], as.name("sprintf")) && length(e) >= 2L && is.character(e[[2]]) &&
          grepl("^judge_request_", e[[2]])) hits[[length(hits) + 1L]] <<- e
      el <- as.list(e)
      for (i in seq_along(el)[-1]) {
        if (is.pairlist(el[[i]]) || (is.symbol(el[[i]]) && !nzchar(as.character(el[[i]])))) next   # formals · 빈 인자
        walk(el[[i]])
      }
    } else if (is.expression(e)) for (i in seq_along(e)) walk(e[[i]])
  }
  if (!is.null(PX)) walk(PX)
  if (length(hits) != 1L) bad("U7 발행자 규칙", sprintf("reinforce_auto_parallel.R 의 judge_request_ sprintf 가 %d개 — 발행 경로가 바뀌었으면 옮겨라", length(hits)))
  else {
    pe <- new.env(); assign("BID", "RP a/b.c+d", envir = pe); assign("n", 3L, envir = pe)
    want <- tryCatch(eval(hits[[1]], envir = pe), error = function(e) NA_character_)
    got <- basename(gad("RP a/b.c+d", 3L, root = fwd(file.path(BASE, "no_such_root")))$request)
    if (identical(want, got)) ok(sprintf("U7 파일명 규칙 = 발행자 규칙 (%s)", got))
    else bad("U7 파일명 규칙 불일치", sprintf("발행자=%s 알림=%s", want, got))
  }

  outs <- list(d1, d2, d3, d4, d5, d6)
  if (!any(vapply(outs, function(d) has_stale(flat(d)), logical(1)))) ok("U8 전 출력에 구 문구 0")
  else bad("U8 구 문구 잔존", "정지/멈췄/단일 judge_request.json")

  # U9 — 요약 길이 = 발신기 계약(tg_format_summary 의 [SUMMARY_MIN, SUMMARY_MAX]) — 상수는 telegram_notify.R 에서 재도출.
  #   최악 입력(보류 코드 전부 · 긴 비정형 status · 긴 BID)에서도 넘으면 A 알림 전체가 결정론적으로 실패한다(드라이런 실측 128자).
  TX <- tryCatch(parse(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"), keep.source = FALSE), error = function(e) NULL)
  cdef <- if (is.null(TX)) list() else Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                                                identical(e[[2]], as.name(".TG_CONFIG")), as.list(TX))
  CFG <- if (length(cdef) == 1L) tryCatch(eval(cdef[[1]][[3]], envir = new.env(parent = baseenv())), error = function(e) NULL) else NULL
  if (is.null(CFG$SUMMARY_MIN) || is.null(CFG$SUMMARY_MAX)) bad("U9 요약 길이 계약", ".TG_CONFIG SUMMARY_MIN/MAX 재도출 실패")
  else {
    SB9 <- fwd(file.path(BASE, "root_u9")); dir.create(file.path(SB9, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
    LB <- paste0("RP_", strrep("X", 120))
    allc <- "held:legacy_regime+adversary_unverified+window_deviation+n_trials_missing+accounting_fail+vintage_flag+sigma_w_lt_1+gate_error"
    writeLines(toJSON(list(entries = list(
      list(base_id = LB, attempt = 1L, status = "awaiting_judge", judge_request = file.path(SB9, "qepm/mailbox", paste0("judge_request_", LB, "_1.json"))),
      list(base_id = LB, attempt = 2L, status = allc),
      list(base_id = LB, attempt = 3L, status = strrep("weird_status_", 20)))), auto_unbox = TRUE),
      file.path(SB9, "06_Registry/grade_a_queue.json"))
    lens <- vapply(1:4, function(k) nchar(gad(LB, k, root = SB9)$summary), integer(1))
    if (all(lens >= CFG$SUMMARY_MIN & lens <= CFG$SUMMARY_MAX))
      ok(sprintf("U9 요약 길이 %s ∈ [%d, %d] (최악 입력 4상태)", paste(lens, collapse = "/"), CFG$SUMMARY_MIN, CFG$SUMMARY_MAX))
    else bad("U9 요약 길이 계약 위반", sprintf("%s ∉ [%d, %d]", paste(lens, collapse = "/"), CFG$SUMMARY_MIN, CFG$SUMMARY_MAX))
  }

  # U10 — 다른 루트(worktree 등)에서 기록된 절대경로도 qepm/mailbox/… 상대 표기
  SB10 <- fwd(file.path(BASE, "root_u10")); dir.create(file.path(SB10, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(list(entries = list(list(base_id = "RP_T_1", attempt = 7L, status = "awaiting_judge",
    judge_request = "D:/elsewhere/wt/qepm/mailbox/judge_request_RP_T_1_7.json"))), auto_unbox = TRUE),
    file.path(SB10, "06_Registry/grade_a_queue.json"))
  d10 <- gad("RP_T_1", 7L, root = SB10)
  if (identical(d10$request, "qepm/mailbox/judge_request_RP_T_1_7.json")) ok("U10 타 루트 기록 경로 → 상대 표기")
  else bad("U10 타 루트 기록 경로", as.character(d10$request))

  # U11 — 대기열에 비정형 줄(리스트 아닌 원소)이 섞여도 A 알림이 죽지 않고 정상 줄을 찾는다
  SB11 <- fwd(file.path(BASE, "root_u11")); dir.create(file.path(SB11, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  writeLines('{"entries": ["garbage-line", 42, {"base_id": "RP_T_1", "attempt": 7, "status": "awaiting_judge"}]}',
             file.path(SB11, "06_Registry/grade_a_queue.json"))
  d11 <- tryCatch(gad("RP_T_1", 7L, root = SB11), error = function(e) list(err = conditionMessage(e)))
  if (identical(d11$state, "published")) ok("U11 비정형 줄 혼입 → 오류 없이 정상 줄 판정(published)")
  else bad("U11 비정형 줄 혼입", as.character(d11$err %||% d11$state))
}

#──────────────────────────────────────────────────────────────────────────────
# S1 — 정적: 실행 코드(주석 줄 제외)에 구 문구 0
#──────────────────────────────────────────────────────────────────────────────
src <- readLines(file.path(PROJ, .MARKER), warn = FALSE, encoding = "UTF-8")
code <- src[!grepl("^\\s*#", src)]
hit_s <- STALE[vapply(STALE, function(s) any(grepl(s, code, fixed = TRUE)), logical(1))]
if (!length(hit_s)) ok("S1 실행 코드에 구 문구 0") else bad("S1 구 문구 잔존(실행 코드)", paste(hit_s, collapse = ", "))

#──────────────────────────────────────────────────────────────────────────────
# W — 렌더 배선: 샌드박스 루트(텔레그램 스텁 · 합성 원장·대기열)에서 rf_auto_notify 를 실제로 돌린다
#──────────────────────────────────────────────────────────────────────────────
SB2 <- fwd(file.path(BASE, "root_w"))
for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "02_Infrastructure/telegram", "06_Registry"))
  dir.create(file.path(SB2, d), recursive = TRUE, showWarnings = FALSE)
.deps <- c("02_Infrastructure/ops/rf_perf_summary.R", "02_Infrastructure/ops/rf_block_insights.R",
           "02_Infrastructure/reinforcement/rf_spec_sig.R")
.dep_ok <- all(vapply(.deps, function(p) isTRUE(file.copy(file.path(PROJ, p), file.path(SB2, p), overwrite = TRUE)), logical(1)))
writeLines(c(
  "## 테스트 스텁 — 실제 발송 경로 대체(샌드박스 전용)",
  "tg_agent_brief <- function(agent, title, sections = list(), ...) {",
  "  cap <- if (exists('.TG_CAP', envir = globalenv())) get('.TG_CAP', envir = globalenv()) else list()",
  "  cap[[length(cap) + 1L]] <- list(agent = agent, title = title, sections = sections)",
  "  assign('.TG_CAP', cap, envir = globalenv()); invisible(list(ok = TRUE, dry_run = TRUE, msg = ''))",
  "}",
  "tg_pass_analysis <- function(...) invisible(NULL)"), file.path(SB2, "02_Infrastructure/telegram/telegram_notify.R"))
mk_att <- function(n, code, grade, pt, cal) list(n = n, cell_code = code, grade = grade,
  essence = list(cell_code = code, block = sub("_.*$", "", code), port_t = pt, net_sharpe = 0.9, cagr = 0.18,
                 mdd = 0.30, calmar = cal, oos_retention = 0.8, spec = "", source = "authoritative_remeasure.json"))
ENT <- list(base_id = "RP_T_1", base_grade = "B", paper_key = "0000.00000", status = "active",
            attempts_used = 7L, max_attempts = 25L, block_order = list("B1", "B5", "B2", "B3", "B4"),
            attempts = list(mk_att(1L, "B1_1", "B", 2.10, 0.40), mk_att(2L, "B1_2", "B", 2.20, 0.42),
                            mk_att(3L, "B1_3", "C", 1.50, 0.30), mk_att(4L, "B1_4", "B", 2.30, 0.45),
                            mk_att(5L, "B1_5", "B", 2.40, 0.50), mk_att(6L, "B5_6", "A", 3.05, 0.70),
                            mk_att(7L, "B5_7", "A", 3.10, 0.72)))
writeLines(toJSON(list(schema_version = "test", layer = 1L, max_attempts = 25L, entries = list(ENT)),
                  auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(SB2, "06_Registry/reinforce_ledger_l1.json"))
Q2 <- list(schema = "grade_a_queue_v1", entries = list(
  list(base_id = "RP_T_1", attempt = 7L, cell = "B5_7", status = "awaiting_judge",
       judge_request = file.path(SB2, "qepm/mailbox/judge_request_RP_T_1_7.json")),
  list(base_id = "RP_T_1", attempt = 6L, cell = "B5_6", status = "held:adversary_unverified")))
writeLines(toJSON(Q2, auto_unbox = TRUE, pretty = TRUE), file.path(SB2, "06_Registry/grade_a_queue.json"))

render <- function(n, kind) {
  if (exists(".TG_CAP", envir = globalenv())) rm(".TG_CAP", envir = globalenv())
  r <- tryCatch(capture.output(suppressWarnings(suppressMessages(rf_auto_notify("RP_T_1", n, kind = kind)))),
                error = function(e) structure(conditionMessage(e), class = "rerr"))
  cap <- if (exists(".TG_CAP", envir = globalenv())) get(".TG_CAP", envir = globalenv()) else list()
  list(err = if (inherits(r, "rerr")) as.character(r) else NULL, cap = cap)
}
sec_of <- function(m, pred) Filter(pred, m$sections %||% list())

.qm0 <- Sys.getenv("QM_ROOT", unset = NA_character_)
Sys.setenv(QM_ROOT = SB2)
.loaded <- .dep_ok && isTRUE(tryCatch({
  invisible(capture.output(suppressMessages(source(file.path(PROJ, .MARKER), local = globalenv()))))
  TRUE }, error = function(e) { cat("  (rf_auto_notify.R 로드 실패: ", conditionMessage(e), ")\n", sep = ""); FALSE }))
if (!.loaded) {
  bad("W0 렌더 준비", "의존 파일 복제 또는 rf_auto_notify.R 로드 실패")
} else if (!identical(fwd(get("ROOT", envir = globalenv())), SB2)) {
  bad("W0 렌더 준비", sprintf("ROOT 가 샌드박스가 아니다(%s) — 운영 루트로 렌더하지 않는다", get("ROOT", envir = globalenv())))
} else {
  assign("rf_notify_charts", function(...) character(0), envir = globalenv())   # 차트 파일 쓰기 차단
  have_gad <- exists("rf_grade_a_disposition", envir = globalenv(), inherits = FALSE)
  for (cs in list(list(n = 7L, tag = "W1 발행"), list(n = 6L, tag = "W2 보류"))) {
    R <- render(cs$n, "grade_a")
    m <- if (length(R$cap)) R$cap[[1]] else NULL
    if (!is.null(R$err) || is.null(m)) { bad(cs$tag, sprintf("렌더 실패 — %s", R$err %||% "tg_agent_brief 미호출")); next }
    exp <- if (have_gad) rf_grade_a_disposition("RP_T_1", cs$n) else NULL
    # 섹션 문자열은 발송 전 .rf_axname_deep(블록 코드 → 축 이름)을 지난다 — 기대값도 같은 변환을 거친다
    ax <- if (exists(".rf_axname", envir = globalenv())) get(".rf_axname", envir = globalenv()) else identity
    nx <- sec_of(m, function(s) identical(as.character(s$heading %||% ""), "다음"))
    sm <- sec_of(m, function(s) identical(as.character(s$type %||% ""), "summary"))
    all_txt <- paste(c(m$title, unlist(lapply(m$sections, function(s) c(s$body, s$items)))), collapse = "\n")
    cond <- !is.null(exp) && length(nx) == 1L && length(sm) == 1L &&
      identical(m$title, sprintf("[1계층·강화 %d/%d] %s", cs$n, 25L, exp$title)) &&
      identical(as.character(nx[[1]]$items), as.character(ax(exp$items))) &&
      identical(as.character(sm[[1]]$body), as.character(ax(exp$summary))) && !has_stale(all_txt)
    if (cond) ok(sprintf("%s → 표제·요약·다음 = 처분 판정(%s) · 구 문구 0", cs$tag, exp$state))
    else bad(cs$tag, sprintf("title=%s | 다음=%s", m$title, paste(unlist(lapply(nx, `[[`, "items")), collapse = " / ")))
  }
  # W3 — 발행 칸 '다음' 에 후보별 요청 파일이 실제로 실린다(렌더 결과만으로 확인)
  R <- render(7L, "grade_a"); m <- if (length(R$cap)) R$cap[[1]] else NULL
  nx <- if (is.null(m)) list() else sec_of(m, function(s) identical(as.character(s$heading %||% ""), "다음"))
  if (length(nx) == 1L && any(grepl("qepm/mailbox/judge_request_RP_T_1_7.json", nx[[1]]$items, fixed = TRUE)))
    ok("W3 발행 렌더 '다음' 에 후보별 요청 파일") else bad("W3 발행 렌더", "후보별 요청 파일 없음")
  # W4 — 음성 대조: block 경로는 처분 문구를 쓰지 않는다
  R <- render(5L, "block"); m <- if (length(R$cap)) R$cap[[1]] else NULL
  if (!is.null(m) && is.null(R$err) && !grepl("Grade A", m$title, fixed = TRUE) &&
      !any(grepl("judge_request_", unlist(lapply(m$sections, function(s) s$items)), fixed = TRUE)))
    ok("W4 block 렌더는 처분 문구 미사용(음성 대조)") else bad("W4 block 렌더", R$err %||% (m$title %||% "미호출"))
}
if (is.na(.qm0)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = .qm0)

.cleanup()
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_notify_grade_a_disposition","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
