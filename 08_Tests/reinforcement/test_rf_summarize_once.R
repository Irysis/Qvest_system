## 소진 요약 1회 표식 — rf_is_summarized / rf_mark_summarized (2026-09-04)
## 실사고: 결합 설계 요청이 진행 중이면 handed_off 가 안 서서 exhausted_summary·promote_skipped 가
##   tick 마다 다시 찍혔다(combo_rulefast 3회). 이월은 handed_off 가, 요약은 이 표식이 막는다.
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), local = TRUE))

tmp <- file.path(tempdir(), sprintf("sumonce_%d", Sys.getpid()))
dir.create(file.path(tmp, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
led <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L,
            combination_review = list(papers_since_last_review = 0L),
            entries = list(list(base_id = "X_exh", status = "exhausted", attempts = list(), base_grade = "C"),
                           list(base_id = "Y_act", status = "active", attempts = list(), base_grade = "F")))
write(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(tmp, "06_Registry/reinforce_ledger_l1.json"))

cat("=== A. 표식 전/후 ===\n")
e0 <- rf_load(1L, tmp)$entries[[1]]
if (!isTRUE(rf_is_summarized(e0))) ok("A 표식 전 = FALSE") else ng("A 표식 전이 TRUE")
rf_mark_summarized(1L, "X_exh", tmp)
L1 <- rf_load(1L, tmp); e1 <- L1$entries[[1]]
if (isTRUE(rf_is_summarized(e1)) && nzchar(e1$summarized_at %||% "")) ok(sprintf("A 표식 후 = TRUE (%s)", e1$summarized_at)) else ng("A 표식이 안 남았다")
if (!isTRUE(rf_is_summarized(L1$entries[[2]]))) ok("A 다른 entry 는 그대로") else ng("A 다른 entry 가 오염")
if (is.null(L1$entries[[1]]$handed_off)) ok("A handed_off 는 건드리지 않는다 (이월은 별도)") else ng("A handed_off 변경")

cat("\n=== B. 없는 entry → 오류 (조용한 no-op 금지) ===\n")
r <- tryCatch({ rf_mark_summarized(1L, "NOPE", tmp); "ok" }, error = function(e) "err")
if (identical(r, "err")) ok("B 없는 base_id 는 오류") else ng("B 없는 base_id 가 조용히 통과")

cat("\n=== C. 이월 러너가 표식을 소비하는가 ===\n")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"), warn = FALSE, encoding = "UTF-8")
i_is <- grep(".already <- rf_is_summarized(E)", src, fixed = TRUE)
i_js <- grep('jlog("exhausted_summary"', src, fixed = TRUE)
i_mk <- grep("rf_mark_summarized(1L, E$base_id, ROOT)", src, fixed = TRUE)
i_ps <- grep("if (!isTRUE(PD$ok) && isTRUE(.already))", src, fixed = TRUE)
if (length(i_is) == 1L && length(i_js) == 1L && i_is < i_js) ok("C 요약 jlog 앞에서 표식을 읽는다") else ng("C 표식 읽기 순서", sprintf("is@%s js@%s", paste(i_is, collapse=","), paste(i_js, collapse=",")))
if (length(i_mk) == 1L && i_mk > i_js) ok("C 요약 직후 표식을 남긴다") else ng("C 표식 쓰기 없음")
if (length(i_ps) == 1L) ok("C 승격 판정 로그도 표식 아래에서 1회") else ng("C promote_skipped 반복 가드 없음")
unlink(tmp, recursive = TRUE, force = TRUE)
cat(sprintf("\n== test_rf_summarize_once: %d pass · %d fail ==\n", P, F))
if (F > 0L) quit(status = 1L)
