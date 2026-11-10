#!/usr/bin/env Rscript
#==============================================================================
# test_cleaner_distill_lcode.R — 주간 증류 L-code 발행 (2026-11-10 전수점검 수리 검사)
#
# 지키는 것:
#   주간 증류 레인이 낸 교훈이 실제로 디스크에 닿는다. 09-05 도입 뒤 6주 14건이 '무인 증류 완주' 줄 뒤에서
#   사라졌고(mode "cleaner" → 접두 조회 오류), 10-03 · 10-10 의 '성공' 4건도 디스크에 없었다(NULL 을 성공으로 읽음).
#
# 축:
#   A  lcode_emit 접두 폴백 — 맵에 없는 mode 가 오류 없이 GEN 접두로 간다
#   B  cd_lcode_item_norm — 증류 항목의 mode · 등급 서술 정규화(실제로 유실된 항목 모양)
#   C  발행 → 결과 판독 왕복 — 성공은 파일 · l_code 로 확인, 막힌 것(NULL)은 실패
#   D  위반 주입(돌연변이) — 수리 전 코드로 되돌리면 A · C 가 깨지는 것을 실증
#
# 격리: 발행은 전부 임시 루트(project_root 명시)로만 간다. 운영 원장에 쓰지 않는다.
#==============================================================================
suppressWarnings(suppressMessages(library(jsonlite)))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

pass <- 0L; fail <- 0L
ok  <- function(m) { pass <<- pass + 1L; cat("  PASS ", m, "\n", sep = "") }
bad <- function(m) { fail <<- fail + 1L; cat("  FAIL ", m, "\n", sep = "") }
chk <- function(cond, m) if (isTRUE(cond)) ok(m) else bad(m)

# ── 러너가 실린 트리 = 검사 대상(환경변수보다 스크립트 위치 우선) ──
args <- commandArgs(trailingOnly = FALSE)
fa <- sub("^--file=", "", args[grepl("^--file=", args)])
self <- if (length(fa)) gsub("\\\\", "/", fa[1]) else ""
ROOT <- if (nzchar(self)) dirname(dirname(dirname(self))) else Sys.getenv("QM_ROOT", getwd())
if (!file.exists(file.path(ROOT, "02_Infrastructure", "axiom", "lcode_emit.R"))) ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd()))
EMIT <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_emit.R")
SCHM <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_schema.R")
FWAL <- file.path(ROOT, "02_Infrastructure", "axiom", "constraint_firewall.R")
LIB  <- file.path(ROOT, "02_Infrastructure", "ops", "cleaner_distill_lib.R")
stopifnot(file.exists(EMIT), file.exists(SCHM), file.exists(LIB))

# ── 임시 루트(운영 원장 무접촉) ──
TMP <- gsub("\\\\", "/", file.path(tempdir(), sprintf("cdl_%d", Sys.getpid())))
AX  <- file.path(TMP, "02_Infrastructure", "axiom")
dir.create(AX, recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(c(EMIT, SCHM), AX, overwrite = TRUE))
if (file.exists(FWAL)) invisible(file.copy(FWAL, AX, overwrite = TRUE))
REAL_WD <- file.path(ROOT, "stage_artifacts", "l_code", "weekly_distill")
real_before <- if (dir.exists(REAL_WD)) sort(list.files(REAL_WD)) else character(0)

load_emit <- function(path) { e <- new.env(parent = globalenv()); suppressMessages(sys.source(path, envir = e)); e }
quiet <- function(expr) { r <- NULL; invisible(capture.output(r <- suppressWarnings(expr))); r }

# 라이브러리에서 두 함수만 꺼낸다(파일 전체를 source 하면 서브커맨드 분기가 돈다)
ex <- parse(LIB, keep.source = FALSE)
lib <- new.env(parent = globalenv()); assign("%||%", `%||%`, envir = lib)
for (e in ex) {
  if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) &&
      as.character(e[[2]]) %in% c("cd_lcode_item_norm", "cd_lcode_emit_result")) eval(e, envir = lib)
}
chk(exists("cd_lcode_item_norm", envir = lib) && exists("cd_lcode_emit_result", envir = lib), "0 라이브러리에 두 함수가 있다")
norm <- get("cd_lcode_item_norm", envir = lib); res <- get("cd_lcode_emit_result", envir = lib)

cat("== A 접두 폴백 ==\n")
ee <- load_emit(file.path(AX, "lcode_emit.R"))
pA <- tryCatch(quiet(ee$emit_lcode(mode = "weekly_distill", strategy_id = "CDL_TEST_A", grade = "", lesson_text = "접두 폴백 시험",
                                   metric_type = "estimated", record_type = "process", project_root = TMP)),
               error = function(e) structure(conditionMessage(e), class = "err"))
chk(!inherits(pA, "err"), sprintf("A1 맵에 없는 mode 가 오류 없이 지나간다%s", if (inherits(pA, "err")) paste0(" — ", pA) else ""))
chk(is.character(pA) && length(pA) == 1L && file.exists(pA) && startsWith(gsub("\\\\", "/", pA), TMP), "A2 발행 파일이 임시 루트에 있다")
idA <- tryCatch(fromJSON(pA, simplifyVector = FALSE)$l_code, error = function(e) "")
chk(grepl("^L-GEN-", idA %||% ""), sprintf("A3 접두 GEN(%s)", idA %||% "?"))
pA2 <- tryCatch(quiet(ee$emit_lcode(mode = "zz_no_such_mode", strategy_id = "CDL_TEST_A2", grade = "", lesson_text = "비표준 mode",
                                    metric_type = "estimated", record_type = "process", project_root = TMP)),
                error = function(e) structure(conditionMessage(e), class = "err"))
chk(is.null(pA2), "A4 스키마에 없는 mode 는 오류가 아니라 검증 거부(NULL)")

cat("== B 항목 정규화 ==\n")
vm <- get("LCODE_VALID_MODES", envir = { s <- new.env(); suppressMessages(sys.source(SCHM, envir = s)); s })
chk("weekly_distill" %in% vm, "B0 스키마에 weekly_distill 라벨")
b <- function(mode, grade) norm(list(mode = mode, grade = grade), valid_modes = vm)
x <- b("cleaner", "B");                              chk(x$mode == "weekly_distill" && x$grade == "B" && identical(x$record_type, "summary"), "B1 cleaner + B → weekly_distill · B · summary")
x <- b("cleaner", "F (라운드 판정 — H1 기각)");       chk(x$grade == "F" && identical(x$record_type, "summary"), "B2 서술 붙은 F → F")
x <- b("cleaner", "N/A_process_observation");        chk(x$grade == "" && identical(x$record_type, "process"), "B3 N/A_… → 등급 없음 · process")
x <- b("cleaner", "partial(10/10 평가 · 공통통과 0)"); chk(x$grade == "" && identical(x$record_type, "process"), "B4 partial(…) → 등급 없음")
x <- b("cleaner", "NA (연구 조사 — 성과 측정 아님)");  chk(x$grade == "" && identical(x$record_type, "process"), "B5 NA (…) → 등급 없음")
x <- b("cleaner", "A_DEF");                          chk(x$grade == "", "B6 A_DEF 는 등급 글자로 읽지 않는다")
x <- b(NULL, NULL);                                  chk(x$mode == "weekly_distill" && x$grade == "" && identical(x$record_type, "process"), "B7 mode · 등급 없음")
x <- b("qepm_legacy", "NA");                         chk(x$mode == "qepm_legacy" && identical(x$record_type, "process"), "B8 유효 mode 유지 + 등급 없으면 process")
x <- b("paper_replication", "C");                    chk(x$mode == "paper_replication" && x$grade == "C" && is.null(x$record_type), "B9 유효 mode + 등급 → 손대지 않음")
x <- norm(list(mode = "cleaner", grade = "B"), valid_modes = NULL, schema_src = SCHM)
chk(x$mode == "weekly_distill", "B10 valid_modes 미전달이면 스키마에서 읽는다")

cat("== C 발행 왕복(유실됐던 항목 모양) ==\n")
items <- list(
  list(mode = "cleaner", strategy_id = "CDL_RP_cross_variant",   grade = "B",                             metric_type = "backtested", lesson_text = "시험 교훈 1 — 비중 산식은 성과를 가르지 못했다"),
  list(mode = "cleaner", strategy_id = "CDL_epoch_unrecorded",   grade = "N/A_process_observation",       metric_type = "estimated",  lesson_text = "시험 교훈 2 — 측정 축 표식이 없는 런이 집계에 섞인다"),
  list(mode = "cleaner", strategy_id = "CDL_P1R02_long_leg",     grade = "F (라운드 판정 — H1 기각)",      metric_type = "backtested", lesson_text = "시험 교훈 3 — 등급이 미신고 구현 층에서 나올 수 있다"),
  list(mode = "cleaner", strategy_id = "CDL_P3R03_construction", grade = "partial(10/10 평가 · 공통통과 0)", metric_type = "backtested", lesson_text = "시험 교훈 4 — 구성 레버는 빠른 급락에서 포화한다"),
  list(mode = "qepm_legacy", strategy_id = "CDL_LANE_PROCESS",   grade = "NA",                            metric_type = "unavailable", lesson_text = "시험 교훈 5 — 멈춘 상태를 들고 있는 기록이 없었다"))
n_ok <- 0L
for (l in items) {
  it <- norm(l, valid_modes = vm)
  o <- tryCatch(quiet(ee$emit_lcode(mode = it$mode, strategy_id = l$strategy_id, grade = it$grade, lesson_text = l$lesson_text,
                                    metric_type = l$metric_type, record_type = it$record_type, tags = it$tags, project_root = TMP)),
                error = function(e) NULL)
  r <- res(o, it)
  good <- isTRUE(r$ok) && nzchar(r$l_code %||% "") && file.exists(file.path(TMP, "stage_artifacts", "l_code", it$mode, r$file %||% "_"))
  if (good) n_ok <- n_ok + 1L
  chk(good, sprintf("C %s → %s (%s)", l$strategy_id, r$l_code %||% "발행 안 됨", r$reason %||% "?"))
}
chk(n_ok == length(items), sprintf("C6 %d/%d 발행 · 디스크 확인", n_ok, length(items)))
chk(isFALSE(res(NULL, list(mode = "weekly_distill"))$ok), "C7 막힌 발행(NULL)은 실패로 읽는다")
chk(isFALSE(res(file.path(TMP, "no_such.json"), NULL)$ok), "C8 없는 경로는 실패로 읽는다")
rec <- fromJSON(file.path(TMP, "stage_artifacts", "l_code", "weekly_distill", "l_code_CDL_RP_cross_variant.json"), simplifyVector = FALSE)
chk(identical(rec$record_type, "summary") && identical(rec$research_mode, "weekly_distill") && identical(rec$grade, "B"),
    "C9 종합 교훈은 record_type=summary 로 남는다(성과 기록으로 두 번 세지 않음)")

cat("== D 위반 주입 ==\n")
# D1 접두 줄을 수리 전 식으로 되돌린 사본 — A1 이 깨져야 한다
src <- readLines(file.path(AX, "lcode_emit.R"), warn = FALSE, encoding = "UTF-8")
i <- grep("prefix <- if (isTRUE(as.character(mode)[1] %in% names(.LCODE_MODE_PREFIX)))", src, fixed = TRUE)
chk(length(i) == 1L, "D0 돌연변이 대상 줄이 정확히 한 곳")
if (length(i) == 1L) {
  mut <- src; mut[i] <- '  prefix <- .LCODE_MODE_PREFIX[[mode]] %||% "GEN"'
  MUT <- file.path(TMP, "lcode_emit_mut.R")
  writeLines(mut, MUT, useBytes = TRUE)
  chk(any(grepl('.LCODE_MODE_PREFIX[[mode]] %||% "GEN"', readLines(MUT, warn = FALSE), fixed = TRUE)), "D1 치환이 사본에 들어갔다")
  em <- load_emit(MUT)
  rM <- tryCatch(quiet(em$emit_lcode(mode = "weekly_distill", strategy_id = "CDL_TEST_MUT", grade = "", lesson_text = "돌연변이",
                                     metric_type = "estimated", record_type = "process", project_root = TMP)),
                 error = function(e) structure(conditionMessage(e), class = "err"))
  chk(inherits(rM, "err") && grepl("subscript out of bounds", rM), "D2 수리 전 식이면 'subscript out of bounds' 로 죽는다(검사가 잡는다)")
}
# D3 구판 결과 판독식 — 막힌 발행을 성공으로, 실제 성공을 오류로 읽는다
old_read <- function(o) tryCatch(list(ok = TRUE, l_code = as.character(o$l_code %||% o %||% "발행")), error = function(e) list(ok = FALSE))
chk(isTRUE(old_read(NULL)$ok) && isFALSE(res(NULL, NULL)$ok), "D3 구판은 막힌 발행을 성공으로 읽는다 — 새 판독은 실패")
chk(isFALSE(old_read(pA)$ok) && isTRUE(res(pA, list(mode = "weekly_distill"))$ok), "D4 구판은 실제 성공을 오류로 읽는다 — 새 판독은 성공")

cat("== E 격리 ==\n")
real_after <- if (dir.exists(REAL_WD)) sort(list.files(REAL_WD)) else character(0)
chk(identical(real_before, real_after), "E1 운영 원장(stage_artifacts/l_code/weekly_distill)은 그대로")
unlink(TMP, recursive = TRUE, force = TRUE)

cat(sprintf("== t_summary: PASS=%d FAIL=%d ==\n", pass, fail))
cat(sprintf('{"test":"cleaner_distill_lcode","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
quit(save = "no", status = if (fail > 0L) 1L else 0L)
