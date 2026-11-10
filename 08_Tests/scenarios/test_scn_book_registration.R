#!/usr/bin/env Rscript
#==============================================================================
# test_scn_book_registration.R — BOOK 등록 · 트래킹 운영 시나리오 (v10.2 감사 레인 F · 2026-11-10)
#   격리: 임시 루트(계약 · 설정 사본) · 운영 book_registry.json 무쓰기 · 텔레그램 없음.
#   B1 confirm 없는 등록 거부            B2 권위 파일 B 인데 grade="A" 진술 → 거부
#   B3 권위 파일 없음(mandate 아님) 거부  B4 축 기록 없는 산출(구 축) 거부
#   B5 다른 epoch 거부                    B6 팩터 DB 수리 전 측정 거부
#   B7 남의 판결서(strategy_id 불일치) 거부 · B8 schema 불명 판결서 거부
#   B9 정상 등록 → 엔트리에 confirm · 축 기록 · 리밸 사양 대기 신호
#   B10 중복 id 거부 · B11 retired 뒤 재등록 허용(append-only 2건)
#   B12 트래킹 last_nav_date 역행(낡은 자료 재실행) 거부 · 이력 무증가
#   B13 Judge FAIL(pit_pass=false) 거부
#   M1~M3 [돌연변이] 축 비교(B5 · B4 는 축 기록 없음 + 축 비교 두 겹) · 판결서 대상 비교 · 역행 검사를 소스 치환으로 끄면 B4 · B7 · B12 가 통과로 바뀐다
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
CR <- gsub("\\", "/", dirname(dirname(dirname(self))), fixed = TRUE)
if (!file.exists(file.path(CR, "02_Infrastructure/book/book_registry.R"))) stop("코드 루트 해석 실패: ", CR)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(c, m, why = "") if (isTRUE(c)) ok(m) else ng(m, why)
err <- function(expr) tryCatch({ force(expr); "no_stop" }, error = function(e) conditionMessage(e))

S <- gsub("\\", "/", file.path(tempdir(), sprintf("scn_book_%d", Sys.getpid())), fixed = TRUE)
for (f in c("02_Infrastructure/contracts/measurement_axis.R", "02_Infrastructure/contracts/factor_db_vintage.R",
            "02_Infrastructure/worktask/constraint_defaults.json")) {
  dir.create(dirname(file.path(S, f)), recursive = TRUE, showWarnings = FALSE); file.copy(file.path(CR, f), file.path(S, f)) }
writeLines("# marker", file.path(S, "02_Infrastructure/config.R"))
dir.create(file.path(S, "06_Registry"), showWarnings = FALSE)
write_json(list(schema = "factor_db_vintage_v1", entries = list(list(id = "T1", completed_at = "2026-11-10T12:00:00+0900", scope = "all"))),
           file.path(S, "06_Registry/factor_db_vintage.json"), auto_unbox = TRUE)
ACT <- fromJSON(file.path(S, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$measurement_axis$active
auth <- function(run, grade = "A", epoch = ACT) {
  d <- file.path(S, "art", run); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  a <- list(essence_grade = grade, run_id = run); if (!is.null(epoch)) a$measurement_axis <- list(epoch = epoch)
  write_json(a, file.path(d, "authoritative_remeasure.json"), auto_unbox = TRUE); file.path(d, "authoritative_remeasure.json") }
verdict <- function(name, sid, pass = TRUE, schema = "judge_verdict_v2") {
  p <- file.path(S, paste0(name, ".json")); write_json(list(schema = schema, strategy_id = sid, pit_pass = pass), p, auto_unbox = TRUE); p }
load_writer <- function(path) { e <- new.env(); invisible(capture.output(sys.source(path, envir = e))); e }
W <- load_writer(file.path(CR, "02_Infrastructure/book/book_registry.R"))
reg <- function(W, sid, ap, vp, confirm = "도훈 11-10 confirm(테스트)") err(invisible(capture.output(
  W$register_book_entry("factor_strategy", sid, 1L, grade = "A", judge_verdict_path = vp, confirm = confirm, authoritative_path = ap, root = S))))

A_ok <- auth("20261111_000000_1"); V1 <- verdict("v_s1", "S1")
chk(grepl("confirm 필수", reg(W, "S1", A_ok, V1, confirm = NULL)), "B1 confirm 없음 → 거부")
chk(grepl("A 아님", reg(W, "S1", auth("20261111_000000_2", grade = "B"), V1)), "B2 권위 B · 진술 A → 거부(재도출)")
chk(grepl("authoritative_path 필수", reg(W, "S1", NULL, V1)), "B3 권위 파일 없음 → 거부")
chk(grepl("측정 축 기록 없음", reg(W, "S1", auth("20261111_000000_3", epoch = NULL), V1)), "B4 축 기록 없는 산출(구 축) → 거부")
chk(grepl("현 축", reg(W, "S1", auth("20261111_000000_4", epoch = "k200kq150_2005_v1"), V1)), "B5 다른 epoch → 거부")
chk(grepl("판 표식 낡음", reg(W, "S1", auth("20261101_000000_5"), V1)), "B6 팩터 DB 수리 전 측정 → 거부")
chk(grepl("다른 전략의 판결서", reg(W, "S1", A_ok, verdict("v_other", "S9"))), "B7 남의 판결서 → 거부")
chk(grepl("schema", reg(W, "S1", A_ok, verdict("v_schema", "S1", schema = "x"))), "B8 schema 불명 판결서 → 거부")
chk(grepl("pit_pass", reg(W, "S1", A_ok, verdict("v_fail", "S1", pass = FALSE))), "B13 Judge FAIL → 거부")
r9 <- reg(W, "S1", A_ok, V1); b <- fromJSON(file.path(S, "06_Registry/book/book_registry.json"), simplifyVector = FALSE)
e <- b$entries[[1]]
chk(identical(r9, "no_stop") && identical(e$book_id, "BOOK_0001") && nzchar(e$confirm) && identical(e$measurement_axis$epoch, ACT),
    "B9 정상 등록 → BOOK_0001 · confirm · 축 기록", r9)
chk(file.exists(file.path(S, "06_Registry/pending_rebalance_specs.json")), "B9 리밸 사양 미작성 대기 신호")
chk(grepl("이미 등록", reg(W, "S1", A_ok, V1)), "B10 중복 id → 거부")
invisible(capture.output(W$set_book_status("BOOK_0001", "retired", "test", root = S)))
r11 <- reg(W, "S1", A_ok, V1); b <- fromJSON(file.path(S, "06_Registry/book/book_registry.json"), simplifyVector = FALSE)
chk(identical(r11, "no_stop") && length(b$entries) == 2L && identical(b$entries[[1]]$status, "retired"), "B11 retired 뒤 재등록 → BOOK_0002 · 구 항목 보존(append-only)")
invisible(capture.output(W$update_book_tracking("BOOK_0002", list(last_nav_date = "2026-11-05"), root = S)))
r12 <- err(invisible(capture.output(W$update_book_tracking("BOOK_0002", list(last_nav_date = "2026-10-30"), root = S))))
b <- fromJSON(file.path(S, "06_Registry/book/book_registry.json"), simplifyVector = FALSE)
chk(grepl("역행", r12) && length(b$entries[[2]]$tracking$history) == 1L && identical(b$entries[[2]]$tracking$last_nav_date, "2026-11-05"),
    "B12 낡은 자료 트래킹(nav 역행) → 거부 · 이력 1건 유지", r12)

cat("\n=== 돌연변이 ===\n")
src <- readLines(file.path(CR, "02_Infrastructure/book/book_registry.R"), warn = FALSE, encoding = "UTF-8")
mut <- function(tag, pat, rep) {
  n <- sum(grepl(pat, src, fixed = TRUE)); p <- file.path(S, sprintf("mut_%s.R", tag))
  writeLines(gsub(pat, rep, src, fixed = TRUE), p, useBytes = TRUE); chk(n >= 1L, sprintf("%s 치환 성사(%d곳)", tag, n)); load_writer(p) }
unlink(file.path(S, "06_Registry/book"), recursive = TRUE)
W1 <- mut("M1", 'if (!identical(ep, act)) stop(', 'if (FALSE) stop(')
chk(identical(reg(W1, "S2", auth("20261111_000000_6", epoch = "k200kq150_2005_v1"), verdict("v_s2", "S2")), "no_stop"), "M1 축 비교 끄면 구 축(k200kq150) 산출이 등록된다 → 원본이 판별")
W2 <- mut("M2", 'if (!identical(as.character(v$strategy_id %||% ""), as.character(strategy_id)))', 'if (FALSE)')
chk(identical(reg(W2, "S3", A_ok, verdict("v_s3x", "S9")), "no_stop"), "M2 판결서 대상 비교 끄면 남의 판결서로 등록된다 → 원본이 판별")
W3 <- mut("M3", '.new_nav < .old_nav)', 'FALSE)')
invisible(capture.output(W3$update_book_tracking("BOOK_0001", list(last_nav_date = "2026-11-05"), root = S)))
chk(identical(err(invisible(capture.output(W3$update_book_tracking("BOOK_0001", list(last_nav_date = "2026-10-01"), root = S)))), "no_stop"),
    "M3 역행 검사 끄면 낡은 트래킹이 기록된다 → 원본이 판별")
unlink(S, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"scn_book_registration","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
