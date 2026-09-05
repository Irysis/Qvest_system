#!/usr/bin/env Rscript
# test_rf_no_active_delegates_next_paper.R — active entry 가 없으면 러너가 next_paper 에 위임한다 (2026-09-05)
# 실사고: combo entry 를 park(소진 아님)로 닫자 active 0 → 러너 halt_no_active_entry → 소진 위임 미도달 →
#   next_paper 미호출 → replication_request 미생성 → rp_auto no_pending_request. 8분마다 침묵 반복(정지가 근면으로 보임).
# 판정: N1 no-active 분기가 next_paper 를 동기 호출 · N2 CLAIM_HELD 상속(소진 위임과 동일 규약) · N3 구 한 줄 부재(돌연변이)
#       N4 next_paper 자체 가드 존재(active_exists · queue_empty) — 위임이 중복 개설을 못 만든다
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), encoding = "UTF-8", warn = FALSE)
code <- sub("#.*$", "", src)
i <- grep('jlog("halt_no_active_entry"', code, fixed = TRUE)
if (length(i) == 1L) ok("분기 1곳") else ng("halt_no_active_entry 분기 수", as.character(length(i)))
blk <- if (length(i)) paste(code[i:min(length(code), i + 6L)], collapse = "\n") else ""
if (grepl("reinforce_auto_next_paper.R", blk, fixed = TRUE) && grepl("wait = TRUE", blk, fixed = TRUE)) ok("N1 next_paper 동기 위임") else ng("N1 위임 없음 ★실사고")
if (grepl('QVEST_RF_CLAIM_HELD = "1"', blk, fixed = TRUE)) ok("N2 CLAIM_HELD 상속") else ng("N2 claim 규약 불일치")
if (!any(grepl('if (!length(act)) { jlog("halt_no_active_entry"); return(0L) }', code, fixed = TRUE))) ok("N3 구 한 줄(정지 전용) 부재") else ng("N3 구판 잔존")
np <- sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"), encoding = "UTF-8", warn = FALSE))
if (any(grepl("halt_active_exists", np, fixed = TRUE)) && any(grepl("halt_queue_empty", np, fixed = TRUE))) ok("N4 next_paper 가드 2종 존재") else ng("N4 next_paper 가드 부재 — 위임이 중복 개설 위험")
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_no_active_delegates_next_paper","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
