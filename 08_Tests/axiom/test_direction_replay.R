#!/usr/bin/env Rscript
#==============================================================================
# test_direction_replay.R — 방향 결정 주간 채점 (2026-09-21 플랜 Part 3 · D4)
#   샌드박스 root 에 결정 기록·L2 원장·디렉터 캐시 픽스처를 두고 run_weekly_direction.R 을 돈다(운영 무접촉).
#   ① 행동 결정 3(결과 2) → insufficient · 결과 귀속(L2 attempt 조인) · Δ 산술 ② 양성 대조: 규칙 재현율 1.0
#   ③ 결과 8건 → report ④ --dry-run 쓰기 0 ⑤ 결정 파일 부재 → n=0 insufficient · 오류 없음 ⑥ Cleaner 배선(run_step·pending)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
DRV <- file.path(ROOT, "02_Infrastructure/axiom/replay/run_direction_score.R")   # 2026-09-21 도훈: 일간 채점 드라이버(--archive = 주간 날짜 파일)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"direction_replay","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
S <- gsub("\\", "/", file.path(tempdir(), sprintf("dirrep_%d", Sys.getpid())), fixed = TRUE)
for (d in c("06_Registry", ".cache", "qepm/memory/axioms/review_log")) dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
dec <- function(id, at, acted, action = "open_l2_unit", rule = "rule2_calmar_bound_overlay_dead", best_cal = 0.50)
  list(schema = "rf_decision_v1", decision_id = id, kind = "direction", at = at, scope = list(base_id = "program", binding = "calmar", overlay_status = "dead", l2_attempts = 0, pool_n = 352, program_best_calmar = best_cal, program_best_port_t = 4.3),
       rule = list(src = "t", branch = rule), chosen = list(ids = list(action), units = if (acted) list(list(kind = "l2_unit", base_id = "FR_003")) else list(), executed = acted), candidates = list())
att <- function(n, date, cal, grade = "C") list(n = n, date = date, closed_at = paste0(substr(date, 1, 4), "-", substr(date, 5, 6), "-", substr(date, 7, 8), "T12:00:00+0900"), grade = grade, essence = list(port_t = 1.2, calmar = cal, mdd = 0.4, mc1_delivered = FALSE))
write_all <- function(decs, atts) {
  writeLines(vapply(decs, function(d) as.character(toJSON(d, auto_unbox = TRUE, null = "null")), character(1)), file.path(S, "06_Registry/rf_decisions.jsonl"))
  writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 2, entries = list(list(base_id = "FR_003", status = "active", attempts_used = length(atts), attempts = atts))), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_ledger_l2.json"))
  writeLines(toJSON(list(program_best = list(calmar = 0.55)), auto_unbox = TRUE), file.path(S, ".cache/rf_director_latest.json"))
  writeLines(toJSON(list(director = list(scoring_min_decisions = 8)), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_auto_config.json"))
}
run <- function(extra = character(0)) suppressWarnings(system2("Rscript", c(shQuote(DRV), sprintf("--root=%s", S), extra), stdout = TRUE, stderr = TRUE))
last_json <- function() { fs <- list.files(file.path(S, "qepm/memory/axioms/review_log"), pattern = "^direction_replay_.*\\.json$", full.names = TRUE); if (!length(fs)) NULL else fromJSON(fs[length(fs)], simplifyVector = FALSE) }

cat("=== ① 3결정(행동 3 · 결과 2) ===\n")
write_all(list(dec("d1", "2026-09-01T08:00:00+0900", TRUE), dec("d2", "2026-09-05T08:00:00+0900", TRUE), dec("d3", "2026-09-20T08:00:00+0900", TRUE), dec("d0", "2026-09-02T08:00:00+0900", FALSE, "none", "rule0_budget")),
          list(att(1, "20260902", 0.60), att(2, "20260906", 0.45)))
o <- run("--archive"); J <- last_json()
if (!is.null(J) && identical(J$score$verdict, "insufficient") && J$score$n_decisions == 4 && J$score$n_acted == 3 && J$score$n_measured == 2) ok("① verdict insufficient · 결정 4 · 행동 3 · 측정 2 (--archive 날짜 파일)") else ng("① 집계", paste(tail(o, 4), collapse = " | "))
r1 <- Filter(function(r) identical(r$decision_id, "d1"), J$rows)[[1]]; r3 <- Filter(function(r) identical(r$decision_id, "d3"), J$rows)[[1]]
if (identical(r1$outcome$status, "measured") && isTRUE(abs(r1$unit_calmar - 0.60) < 1e-9) && isTRUE(abs(r1$d_unit_vs_best_calmar - 0.10) < 1e-9) && isTRUE(abs(r1$d_program_calmar_since - 0.05) < 1e-9)) ok("① 결과 귀속: d1 → attempt n1 (Calmar 0.60) · Δ단위 +0.10 · Δ프로그램 +0.05") else ng("① 귀속/산술", paste(r1$outcome$status, r1$unit_calmar, r1$d_unit_vs_best_calmar))
if (identical(r3$outcome$status, "pending")) ok("① 결정 이후 attempt 없음 → pending") else ng("① pending", r3$outcome$status)
rep <- J$score$controls$positive_rule_reproduction
if (isTRUE(rep$n >= 3) && isTRUE(abs(rep$agree - 1) < 1e-9)) ok(sprintf("② 양성 대조: 규칙 재현 %d/%d", rep$n, rep$n)) else ng("② 규칙 재현", paste(rep$n, rep$agree))
if (isTRUE(J$score$controls$negative_always_b5$n_decisions_with_b5_dead == 4)) ok("② 음성 대조: B5 dead 결정 4 계상") else ng("② 음성 대조")
cat("=== ①b 일간 모드(archive 없음): 캐시·latest.md 만 · 날짜 파일 0 · --quiet ===\n")
unlink(list.files(file.path(S, "qepm/memory/axioms/review_log"), full.names = TRUE)); unlink(file.path(S, ".cache/rf_direction_score_latest.json"))
o <- run("--quiet"); LC <- file.path(S, ".cache/rf_direction_score_latest.json")
lj <- if (file.exists(LC)) fromJSON(LC, simplifyVector = FALSE) else NULL
if (!is.null(lj) && identical(lj$verdict, "insufficient") && startsWith(lj$line, "Rules:") && nchar(lj$line, type = "chars") <= 120L && lj$n_measured == 2) ok(sprintf("①b 일간 캐시: %s", lj$line)) else ng("①b 일간 캐시", if (is.null(lj)) "부재" else lj$line)
if (file.exists(file.path(S, "qepm/memory/axioms/review_log/direction_replay_latest.md")) && !length(list.files(file.path(S, "qepm/memory/axioms/review_log"), pattern = "^direction_replay_[0-9]{8}\\.json$"))) ok("①b latest.md 생성 · 날짜 파일 0(review_log 불리지 않음)") else ng("①b 파일 정책")
if (sum(nzchar(o)) <= 3L && any(grepl("^Rules:", o)) && !any(grepl("^# direction_replay", o))) ok("①b --quiet: Rules 줄 + verdict 줄만") else ng("①b quiet 출력", paste(o, collapse = " | "))
cat("=== ③ 결과 8건 ===\n")
write_all(lapply(1:9, function(i) dec(sprintf("e%d", i), sprintf("2026-08-%02dT08:00:00+0900", i), TRUE)), lapply(1:9, function(i) att(i, sprintf("202608%02d", i), 0.50 + i / 100)))
o <- run(); J <- last_json()
if (!is.null(J) && identical(J$score$verdict, "report") && J$score$n_measured == 9) ok("③ 결과 9건 → report (archive 없이도 report 는 날짜 파일 보존)") else ng("③ report", if (is.null(J)) "날짜 파일 없음" else paste(J$score$verdict, J$score$n_measured))
cat("=== ④ dry-run ===\n")
unlink(list.files(file.path(S, "qepm/memory/axioms/review_log"), full.names = TRUE))
o <- run("--dry-run")
if (!length(list.files(file.path(S, "qepm/memory/axioms/review_log"))) && any(grepl("verdict=report .*\\(dry\\)", o))) ok("④ dry-run 쓰기 0 · verdict 줄") else ng("④ dry-run", paste(tail(o, 2), collapse = " | "))
cat("=== ⑤ 결정 파일 부재 ===\n")
unlink(file.path(S, "06_Registry/rf_decisions.jsonl")); o <- run()
if (any(grepl("verdict=insufficient n=0", o))) ok("⑤ 부재 → n=0 insufficient · 오류 없음") else ng("⑤ 부재 처리", paste(tail(o, 3), collapse = " | "))
cat("=== ⑥ Cleaner 배선 ===\n")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/weekly_cleaner_sweep.R"), encoding = "UTF-8", warn = FALSE)
i_step <- grep('run_step("director_policy_replay"', src, fixed = TRUE); i_ax <- grep('run_step("axiom_weekly_cycle"', src, fixed = TRUE); i_ki <- grep('run_step("knowledge_index"', src, fixed = TRUE)
if (length(i_step) == 1L && length(i_ax) && length(i_ki) && i_step > i_ax[1] && i_step < i_ki[1] && any(grepl("direction_replay = direction_replay_summary", src, fixed = TRUE)) && any(grepl("run_direction_score.R", src, fixed = TRUE)) && any(grepl('"--archive"', src, fixed = TRUE))) ok("⑥ run_step 이 axiom 사이클 뒤·knowledge_index 앞 · pending 에 direction_replay · 주간은 --archive") else ng("⑥ 배선", paste(i_ax[1], i_step, i_ki[1]))
dsrc <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_director.R"), encoding = "UTF-8", warn = FALSE)
if (any(grepl("run_direction_score.R", dsrc, fixed = TRUE)) && any(grepl('"--quiet"', dsrc, fixed = TRUE))) ok("⑥b 디렉터가 매일 --quiet 로 채점기를 부른다") else ng("⑥b 디렉터 일간 채점 호출 없음")
unlink(S, recursive = TRUE)
finish()
