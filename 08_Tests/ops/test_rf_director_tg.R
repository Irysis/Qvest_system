#!/usr/bin/env Rscript
#==============================================================================
# test_rf_director_tg.R — 디렉터 D1: 결정 기록 1일 1회(서명 중복 억제) + 텔레그램 [무인] 헤더 · on_change (2026-09-21 플랜 Part 3)
#
# 샌드박스 root 에서 --notify + QVEST_TG_DRY_RUN=1 로 두 번 돈다.
#   1회: rf_decisions.jsonl 에 direction 1건 · dry 본문에 "[무인] 디렉터" · telegram.reason=changed
#   2회: 같은 서명 → 기록 추가 0 · telegram.reason=unchanged(월요일이면 monday_summary 허용)
# 운영 캐시·원장·텔레그램 무접촉(dry run).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
SCRIPT <- file.path(ROOT, "02_Infrastructure/ops/rf_director.R")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_director_tg","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
S <- gsub("\\", "/", file.path(tempdir(), sprintf("rf_dir_tg_%d", Sys.getpid())), fixed = TRUE)
for (d in c("06_Registry", "02_Infrastructure/worktask", ".cache")) dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S, "02_Infrastructure/worktask/constraint_defaults.json")))
led1 <- list(schema_version = "reinforce_ledger_v2", layer = 1, max_attempts = 25, entries = list(
  list(base_id = "RP_T_ONE", status = "active", attempts_used = 1, attempts = list(
    list(n = 1, cell_code = "B1_1", grade = "B", artifacts = "", essence = list(cell_code = "B1_1", block = "B1", port_t = 3.5, calmar = 0.5, cagr = 0.2, mdd = 0.4, net_sharpe = 1.0, oos_retention = 0.8))))),
  combination_review = list(papers_since_last_review = 0, last_review_date = "", history = list()))
writeLines(toJSON(led1, auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 2, entries = list(list(base_id = "FR_003", status = "active", attempts_used = 0, attempts = list()))), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_ledger_l2.json"))
writeLines('{"modules":{}}', file.path(S, "06_Registry/module_catalog.json"))
writeLines(toJSON(list(schema_version = "v3.1", generated = format(Sys.Date(), "%Y-%m-%d"), grade_floor = "B", n_modules = 0, modules = list()), auto_unbox = TRUE), file.path(S, "06_Registry/module_performance.json"))
writeLines(toJSON(list(factor_rotations = list(list(fr_id = "FR_003", grade = "C", n_modules = 89, essence = list(calmar = 0.399, port_t = 0.853)))), auto_unbox = TRUE), file.path(S, "06_Registry/factor_rotation_registry.json"))
writeLines(toJSON(list(enabled = TRUE, director = list(enabled = TRUE, act = FALSE, telegram = "on_change")), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_auto_config.json"))
Sys.setenv(QVEST_TG_DRY_RUN = "1", QVEST_DIRECTOR_NO_MAIN = "")
run <- function() suppressWarnings(system2("Rscript", c(shQuote(SCRIPT), sprintf("--root=%s", S), "--notify"), stdout = TRUE, stderr = TRUE))
o1 <- run(); P <- file.path(S, "06_Registry/rf_decisions.jsonl"); C <- file.path(S, ".cache/rf_director_latest.json")
if (file.exists(C)) ok("1회: 캐시 생성") else { ng("1회: 캐시 부재", paste(tail(o1, 6), collapse = " | ")); finish() }
c1 <- fromJSON(C, simplifyVector = FALSE)
if (file.exists(P) && length(readLines(P)) == 1L) ok("1회: rf_decisions.jsonl direction 1건") else ng("1회: 결정 기록", if (file.exists(P)) as.character(length(readLines(P))) else "파일 없음")
d <- if (file.exists(P)) fromJSON(readLines(P)[1], simplifyVector = FALSE) else list()
if (identical(d$kind, "direction") && identical(d$policy$policy_id, "pi_dir_v0") && nzchar(.chr <- as.character(d$scope$signature %||% ""))) ok("1회: kind=direction · policy pi_dir_v0 · 서명 기록") else ng("1회: 레코드 내용")
if (isTRUE(c1$decision$recorded)) ok("1회: 캐시 decision.recorded=TRUE") else ng("1회: decision 필드", as.character(c1$decision$reason))
if (identical(c1$telegram$reason, "changed") && isTRUE(c1$telegram$dry_run) && isTRUE(c1$telegram$sent)) ok("1회: telegram reason=changed · dry_run · sent=TRUE(본문 생성 성공)") else ng("1회: telegram", paste(c1$telegram$reason, c1$telegram$sent))
body <- o1[cumsum(grepl("dry_run output", o1, fixed = TRUE)) > 0]      # ★오류 메시지가 아니라 dry 본문 안에서만 찾는다 (실측: 오류문에 절 이름이 들어 있어 검사가 속았다)
if (length(body) && any(grepl("[무인] 디렉터", body, fixed = TRUE))) ok("1회: dry 본문에 [무인] 디렉터 헤더") else ng("1회: 헤더/본문", paste(head(grep("무인|텔레그램|rror", o1, value = TRUE), 4), collapse = " | "))
if (length(body) && any(grepl("현재 리서치 상황", body, fixed = TRUE)) && !any(grepl("텔레그램 실패", o1, fixed = TRUE))) ok("1회: '현재 리서치 상황' 절이 본문에 있고 실패 로그 없음") else ng("1회: 상황 절/실패 로그")
o2 <- run(); c2 <- fromJSON(C, simplifyVector = FALSE)
if (length(readLines(P)) == 1L && identical(c2$decision$reason, "same_signature_today")) ok("2회: 같은 서명 → 기록 추가 0") else ng("2회: 중복 기록", paste(length(readLines(P)), c2$decision$reason))
if (c2$telegram$reason %in% c("unchanged", "monday_summary")) ok(sprintf("2회: telegram %s", c2$telegram$reason)) else ng("2회: telegram", c2$telegram$reason)
unlink(S, recursive = TRUE)
finish()
