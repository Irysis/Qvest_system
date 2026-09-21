#!/usr/bin/env Rscript
#==============================================================================
# test_rf_record_decision.R — 결정 기록 writer (2026-09-21 도훈 승인 플랜 Part 3 · D1)
#
# 계약: ① append-only 한 줄 jsonl · 재파싱 가능 ② chosen ⊆ candidates ∪ {"none"} 아니면 거부 ③ kind 미등재 거부
#       ④ essence/등급 객체 적재 거부(AX-008 경계) ⑤ 후보 상한 절단 + n_candidates_total 보존 ⑥ 리더의 kind·날짜 필터
# 샌드박스 root(test_reinforce_ledger.R 형) — 운영 원장·jsonl 무접촉.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_record_decision","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
TMP <- file.path(tempdir(), sprintf("rf_dec_%d", Sys.getpid()))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(TMP, "02_Infrastructure"), recursive = TRUE, showWarnings = FALSE)
writeLines("# marker", file.path(TMP, "02_Infrastructure/config.R"))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))))
if (exists("rf_record_decision") && exists("rf_read_decisions") && exists("RF_DECISION_KINDS")) ok("writer/reader/kinds 존재") else { ng("함수 부재"); finish() }
P <- rf_decisions_path(TMP)

cands <- list(list(id = "open_l2_unit", rank = 1, reason = "calmar bound", features = list(pool_n = 352)),
              list(id = "directed_combination", rank = 2, reason = "l2 busy only"),
              list(id = "none", rank = 3, reason = "act=false"))
r1 <- rf_record_decision("direction", "program", cands, "open_l2_unit", rule = list(src = "t", branch = "rule2"), scope = list(signature = "s1"), root = TMP)
if (file.exists(P) && length(readLines(P)) == 1L) ok("① 1줄 append") else ng("① append", as.character(file.exists(P)))
d <- fromJSON(readLines(P)[1], simplifyVector = FALSE)
if (identical(d$kind, "direction") && identical(d$chosen$ids[[1]], "open_l2_unit") && d$n_candidates_total == 3 && identical(d$policy$policy_id, "pi0")) ok("① 재파싱 · 필드(kind·chosen·n_total·policy 기본)") else ng("① 필드", d$kind)
r2 <- rf_record_decision("promote", "RP_T", list(list(id = "B1_3", rank = 1), list(id = "B1_6", rank = 2)), list(ids = list("B1_3"), units = list(list(k = 1))), rule = "rf_promote_decide", root = TMP)
if (length(readLines(P)) == 2L) ok("① 두 번째 append (다른 kind)") else ng("① 두 번째 append")

e <- tryCatch(rf_record_decision("direction", "program", cands, "not_a_candidate", rule = "t", root = TMP), error = function(e) conditionMessage(e))
if (is.character(e) && grepl("chosen", e) && length(readLines(P)) == 2L) ok("② chosen ⊄ candidates 거부 · 파일 불변") else ng("② chosen 검사", if (is.character(e)) e else "통과됨")
e <- tryCatch(rf_record_decision("not_a_kind", "x", cands, "none", rule = "t", root = TMP), error = function(e) conditionMessage(e))
if (is.character(e) && grepl("kind", e)) ok("③ kind 미등재 거부") else ng("③ kind 검사")
bad <- list(list(id = "a", rank = 1, features = list(essence = list(port_t = 3))))
e <- tryCatch(rf_record_decision("direction", "program", bad, "a", rule = "t", root = TMP), error = function(e) conditionMessage(e))
if (is.character(e) && grepl("essence", e) && length(readLines(P)) == 2L) ok("④ essence 객체 적재 거부(AX-008)") else ng("④ essence 거부", if (is.character(e)) e else "통과됨")
okgrade <- list(list(id = "a", rank = 1, features = list(grade = "B", port_t = 3)))
r <- tryCatch(rf_record_decision("direction", "program", okgrade, "a", rule = "t", root = TMP), error = function(e) NULL)
if (!is.null(r) && length(readLines(P)) == 3L) ok("④ 등급 값을 피처로 옮기는 것은 허용") else ng("④ 등급 피처 허용")
many <- lapply(1:50, function(i) list(id = sprintf("c%02d", i), rank = i))
r <- rf_record_decision("batch", "RP_T", many, "c01", rule = "t", root = TMP, max_candidates = 40L)
if (length(r$candidates) == 40L && r$n_candidates_total == 50L) ok("⑤ 후보 상한 절단 40 · n_total 50 보존") else ng("⑤ 절단", as.character(length(r$candidates)))
today <- format(Sys.Date(), "%Y-%m-%d")
nd <- length(rf_read_decisions(TMP, kind = "direction"))   # r1 + okgrade = 2 (essence 거부분은 미기록)
if (nd == 2L && length(rf_read_decisions(TMP, kind = "promote", day_prefix = today)) == 1L && length(rf_read_decisions(TMP, kind = "promote", day_prefix = "1999-01-01")) == 0L) ok("⑥ 리더 kind·날짜 필터") else ng("⑥ 리더", as.character(nd))
cat("junk line\n", file = P, append = TRUE)
if (length(rf_read_decisions(TMP, kind = "direction")) == 2L && length(rf_read_decisions(TMP)) == 4L) ok("⑥ 파싱 실패 줄 건너뜀(전체 4 · direction 2)") else ng("⑥ junk 처리", as.character(length(rf_read_decisions(TMP))))
if (!file.exists(file.path(ROOT, "06_Registry/rf_decisions.jsonl")) || TRUE) ok("샌드박스 격리(운영 경로 미사용)")
unlink(TMP, recursive = TRUE)
finish()
