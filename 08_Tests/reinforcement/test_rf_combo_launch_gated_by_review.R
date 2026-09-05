#!/usr/bin/env Rscript
# test_rf_combo_launch_gated_by_review.R — 결합 착수는 결합 검토가 due 일 때만 (도훈 2026-09-05 "새 논문 우선")
# 실사고: 검토 not_due(0/3)인데 착수기가 무조건 불려 재료 풀 미시도 부분집합이 큐 상단 논문보다 먼저 열림.
# 판정(정적·양방향): G1 검토 출력을 잡아 .review_due 를 만든다 · G2 착수는 .review_due 조건 안 · G3 skip 로그 ·
#                    G4 구 무조건 호출(tryCatch 직결) 부재 · G5 검토기가 not_due 를 실제로 찍는 코드가 있다(게이트 신호 실재)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
np <- sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"), encoding = "UTF-8", warn = FALSE))
txt <- paste(np, collapse = "\n")
if (grepl('.rev <- tryCatch(system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_combination_review.R"))', txt, fixed = TRUE) &&
    grepl('.review_due <- !any(grepl("not_due"', txt, fixed = TRUE)) ok("G1 검토 출력 → .review_due") else ng("G1 검토 출력을 안 잡는다")
if (grepl('if (!isTRUE(.review_due)) {', txt, fixed = TRUE) && grepl('} else tryCatch({', txt, fixed = TRUE)) ok("G2 착수가 due 조건 안") else ng("G2 착수가 무조건 ★실사고")
if (grepl('combination_launch_skipped', txt, fixed = TRUE)) ok("G3 skip 로그(조용한 생략 아님)") else ng("G3 skip 로그 없음")
old <- paste0(".combo_opened <- FALSE\n", "tryCatch({\n", "  .out <- system2")
if (!grepl(old, txt, fixed = TRUE)) ok("G4 구 무조건 호출 부재") else ng("G4 구판 잔존")
rv <- sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/rf_combination_review.R"), encoding = "UTF-8", warn = FALSE))
if (any(grepl("not_due", rv, fixed = TRUE))) ok("G5 검토기가 not_due 를 찍는다(게이트 신호 실재)") else ng("G5 검토기에 not_due 없음 — 게이트가 영원히 due")
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_combo_launch_gated_by_review","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
