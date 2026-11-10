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
#   B14 남의 A 권위 기록 거부 · B15 식별자 없는 권위 기록 거부 · B16 2계층 fr_id 대조 · B17/B17b 같은 폴더 Judge 요청서 대상 · 폴더 불일치 거부
#   B18 측정보다 앞선 판결서 거부 · B19 판결서 run_id 불일치 거부 (11-10 감사 G4) · M4~M6 [돌연변이] 그 비교들을 끄면 통과로 바뀐다
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
auth <- function(run, grade = "A", epoch = ACT, sid = "S1", extra = list()) {
  d <- file.path(S, "art", run); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  a <- list(essence_grade = grade, run_id = run); if (!is.null(sid)) a$strategy_id <- sid
  if (!is.null(epoch)) a$measurement_axis <- list(epoch = epoch)
  for (k in names(extra)) a[[k]] <- extra[[k]]
  write_json(a, file.path(d, "authoritative_remeasure.json"), auto_unbox = TRUE); file.path(d, "authoritative_remeasure.json") }
verdict <- function(name, sid, pass = TRUE, schema = "judge_verdict_v2", extra = list()) {
  v <- list(schema = schema, strategy_id = sid, pit_pass = pass, reproduction = list(grade_claimed = "A", grade_reproduced = "A", match = TRUE))
  for (k in names(extra)) v[k] <- list(extra[[k]])   # extra 값이 NULL 이면 그 필드를 지운다(v[k] <- list(NULL))
  p <- file.path(S, paste0(name, ".json")); write_json(v, p, auto_unbox = TRUE); p }
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
## (11-10) 재현 일치 — PIT 통과여도 등급 재현이 확인되지 않은 판결서는 거부
chk(grepl("reproduction", reg(W, "S1", A_ok, verdict("v_norep", "S1", extra = list(reproduction = NULL)))), "B20 판결서에 reproduction 없음 → 거부(fail-closed)")
chk(grepl("reproduction", reg(W, "S1", A_ok, verdict("v_nomatch", "S1", extra = list(reproduction = list(grade_claimed = "A", grade_reproduced = "B", match = FALSE))))),
    "B21 재현 불일치(match = false · 재현 등급 B) → 거부")
chk(grepl("reproduction", reg(W, "S1", A_ok, verdict("v_repB", "S1", extra = list(reproduction = list(grade_claimed = "A", grade_reproduced = "B", match = TRUE))))),
    "B22 match = true 인데 재현 등급이 A 아님 → 거부")
## (11-10 감사 G4) 권위 기록이 등록 대상 전략의 것인지
chk(grepl("다른 전략의 권위 기록", reg(W, "S1", auth("20261111_000000_10", sid = "OTHER_STRAT"), V1)), "B14 남의 A 권위 기록 + 내 PASS 판결서 → 거부")
chk(grepl("식별자.*없음", reg(W, "S1", auth("20261111_000000_11", sid = NULL), V1)), "B15 권위 기록에 전략 식별자 없음 → 거부(fail-closed)")
FRD <- file.path(S, "fr", "FR_T1"); dir.create(FRD, recursive = TRUE); FRP <- file.path(FRD, "FR_T1_result.json")
write_json(list(fr_id = "FR_T1", grade = "A"), FRP, auto_unbox = TRUE)
regfr <- function(sid) err(invisible(capture.output(W$register_book_entry("rotation_rule", sid, 2L, grade = "A",
  judge_verdict_path = verdict(paste0("v_", sid), sid), confirm = "t", authoritative_path = FRP, root = S))))
r16a <- regfr("FR_T2"); r16b <- regfr("FR_T1")
chk(grepl("다른 전략의 권위 기록", r16a) && grepl("측정 축 기록 없음", r16b),
    "B16 2계층 fr_id 대조 — 다른 FR 거부 · 같은 FR 은 식별 통과(다음 관문 = 축 기록)", paste(r16a, "|", r16b))
A17 <- auth("20261111_000000_12"); write_json(list(strategy_id = "S9", artifacts = dirname(A17)), file.path(dirname(A17), "judge_request.eligible.json"), auto_unbox = TRUE)
chk(grepl("산출 폴더와 대상 불일치", reg(W, "S1", A17, V1)), "B17 같은 폴더 Judge 요청서 strategy_id 불일치 → 거부")
A17b <- auth("20261111_000000_13"); write_json(list(strategy_id = "S1", artifacts = file.path(S, "art", "20261111_000000_99")), file.path(dirname(A17b), "judge_request.eligible.json"), auto_unbox = TRUE)
chk(grepl("artifacts", reg(W, "S1", A17b, V1)), "B17b Judge 요청서 artifacts 가 다른 산출 폴더 → 거부")
A18 <- auth("20261111_000000_14", extra = list(remeasured_at = "2026-11-11T09:00:00+0900"))
chk(grepl("이 측정 이전의 판결서", reg(W, "S1", A18, verdict("v_old", "S1", extra = list(date = "2026-11-01")))), "B18 측정보다 앞선 판결서(옛 실행 PASS) → 거부")
chk(grepl("다른 실행의 판결서", reg(W, "S1", A18, verdict("v_rid", "S1", extra = list(run_id = "20261101_000000_0")))), "B19 판결서 run_id ≠ 권위 기록 run_id → 거부")
## 정상 경로의 같은 폴더 요청서 — 다른 기계 루트(C:/Users/...)로 적힌 artifacts 도 같은 산출 폴더면 통과해야 한다(B9 가 판정)
write_json(list(strategy_id = "S1", artifacts = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/x/art/20261111_000000_1"),
           file.path(dirname(A_ok), "judge_request.eligible.json"), auto_unbox = TRUE)
r9 <-reg(W, "S1", A_ok, V1); b <- fromJSON(file.path(S, "06_Registry/book/book_registry.json"), simplifyVector = FALSE)
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
chk(identical(reg(W1, "S2", auth("20261111_000000_6", epoch = "k200kq150_2005_v1", sid = "S2"), verdict("v_s2", "S2")), "no_stop"), "M1 축 비교 끄면 구 축(k200kq150) 산출이 등록된다 → 원본이 판별")
W2 <- mut("M2", 'if (is.na(vid) || !identical(vid, as.character(strategy_id)[1]))', 'if (FALSE)')
chk(identical(reg(W2, "S3", auth("20261111_000000_9", sid = "S3"), verdict("v_s3x", "S9")), "no_stop"), "M2 판결서 대상 비교 끄면 남의 판결서로 등록된다 → 원본이 판별")
W4 <- mut("M4", 'if (!(sid %in% ids))', 'if (FALSE)')
chk(identical(reg(W4, "S4", auth("20261111_000000_15", sid = "OTHER_STRAT"), verdict("v_s4", "S4")), "no_stop"), "M4 권위 기록 대상 비교 끄면 남의 A 산출물로 등록된다(B14) → 원본이 판별")
W5 <- mut("M5", 'if (!is.na(jsid) && nzchar(jsid) && !identical(jsid, sid))', 'if (FALSE)')
A5 <- auth("20261111_000000_16", sid = "S5"); write_json(list(strategy_id = "S9"), file.path(dirname(A5), "judge_request.eligible.json"), auto_unbox = TRUE)
chk(identical(reg(W5, "S5", A5, verdict("v_s5", "S5")), "no_stop"), "M5 Judge 요청서 대상 비교 끄면 B17 이 등록된다 → 원본이 판별")
W6 <- mut("M6", '!is.na(md) && vd < md)', 'FALSE)')
chk(identical(reg(W6, "S6", auth("20261111_000000_17", sid = "S6", extra = list(remeasured_at = "2026-11-11T09:00:00+0900")),
                  verdict("v_s6", "S6", extra = list(date = "2026-11-01"))), "no_stop"), "M6 판결 날짜 대조 끄면 옛 PASS 로 등록된다(B18) → 원본이 판별")
W3 <- mut("M3", '.new_nav < .old_nav)', 'FALSE)')
invisible(capture.output(W3$update_book_tracking("BOOK_0001", list(last_nav_date = "2026-11-05"), root = S)))
chk(identical(err(invisible(capture.output(W3$update_book_tracking("BOOK_0001", list(last_nav_date = "2026-10-01"), root = S)))), "no_stop"),
    "M3 역행 검사 끄면 낡은 트래킹이 기록된다 → 원본이 판별")
unlink(S, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"scn_book_registration","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
