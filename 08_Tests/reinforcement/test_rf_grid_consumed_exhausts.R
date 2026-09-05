#!/usr/bin/env Rscript
#==============================================================================
# test_rf_grid_consumed_exhausts.R — 격자가 다 찼으면 예산이 남아도 소진이다 (2026-09-05)
#
# 실사고 20:18~: 첫 Fable entry 가 B1 설계 9칸으로 예산 25→29 인데 B3 설계가 4칸이라 격자 총합 28.
#   used 28 < MAXA 29 → 예산 소진 판정이 영영 안 서고 러너가 매 tick halt_no_jobs — 승격(B4_25 B)·다음 논문 모두 정지.
# 판정(양방향):
#   G1 전 칸에 시도 + 재개 대상 0 → TRUE   G2 빈 칸 1개 → FALSE   G3 전 칸 시도했지만 미측정(재개 대상) 1개 → FALSE
#   G4 terminal 로 닫힌 칸은 찬 칸이다 → TRUE   G5 격자 0칸 → FALSE   G6 승계 칸(essence 만 있고 cell_code 는 essence 안) → 찬 칸
#   R1 러너의 halt_no_jobs 분기가 rf_grid_consumed 를 묻고 소진 루틴으로 나간다 · R2 예산 소진과 격자 소진이 같은 루틴
# 부작용 없음: 순수 함수 + 러너 소스 텍스트만 읽는다.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
if (!exists("rf_grid_consumed")) { ng("rf_grid_consumed 부재(구판)"); cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL)); quit(status = 1) }

cell <- function(code, block) list(code = code, block = block, label = code)
grid <- c(lapply(1:9, function(i) cell(sprintf("B1_%d", i), "B1")), lapply(10:14, function(i) cell(sprintf("B5_%d", i), "B5")),
          lapply(15:19, function(i) cell(sprintf("B2_%d", i), "B2")), lapply(20:23, function(i) cell(sprintf("B3_%d", i), "B3")),
          lapply(24:28, function(i) cell(sprintf("B4_%d", i), "B4")))
measured <- function(n, code) list(n = n, cell_code = code, grade = "C", essence = list(cell_code = code, port_t = 1.0))
att_all <- lapply(seq_along(grid), function(i) measured(i, grid[[i]]$code))

r <- rf_grid_consumed(grid, att_all)
if (isTRUE(r)) ok("G1 28칸 전부 측정 · 예산 29 미달이어도 TRUE ★실사고") else ng("G1 격자 소진을 못 본다")
r <- rf_grid_consumed(grid, att_all[-28])
if (isFALSE(r)) ok("G2 빈 칸 1개(B4_28) → FALSE") else ng("G2 빈 칸을 소진으로 읽음")
att_pend <- att_all; att_pend[[5]] <- list(n = 5L, cell_code = "B1_5")          # 등록만 되고 essence 없음 · terminal 아님
r <- rf_grid_consumed(grid, att_pend)
if (isFALSE(r)) ok("G3 미측정 재개 대상 1개 → FALSE (칸은 찼지만 답이 없다)") else ng("G3 재개 대상을 무시")
att_term <- att_all; att_term[[5]] <- list(n = 5L, cell_code = "B1_5", terminal = TRUE, terminal_reason = "양립 불가")
r <- rf_grid_consumed(grid, att_term)
if (isTRUE(r)) ok("G4 terminal 로 닫힌 칸은 찬 칸 → TRUE") else ng("G4 terminal 칸을 빈 칸으로 읽음")
if (isFALSE(rf_grid_consumed(list(), att_all))) ok("G5 격자 0칸 → FALSE") else ng("G5 빈 격자를 소진으로 읽음")
att_inh <- att_all; att_inh[[26]] <- list(n = 26L, grade = "C", essence = list(cell_code = "B4_26", port_t = 1.588))   # 승계 칸(cell_code 는 essence 안)
if (isTRUE(rf_grid_consumed(grid, att_inh))) ok("G6 승계 칸(essence$cell_code) 도 찬 칸") else ng("G6 승계 칸을 빈 칸으로 읽음")

src <- sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), encoding = "UTF-8", warn = FALSE))
i <- grep('jlog("halt_no_jobs")', src, fixed = TRUE)
blk <- if (length(i)) paste(src[max(1L, i - 12L):i], collapse = "\n") else ""
if (grepl("rf_grid_consumed(cells, E$attempts)", blk, fixed = TRUE) && grepl(".exhaust_and_delegate(", blk, fixed = TRUE))
  ok("R1 halt_no_jobs 앞에서 격자 소진을 묻고 소진 루틴으로 나간다") else ng("R1 러너 분기 미교체 ★실사고")
n_call <- sum(grepl('.exhaust_and_delegate("', src, fixed = TRUE))   # 호출 줄만(정의 줄은 인용 인자가 없다)
if (n_call >= 2L) ok(sprintf("R2 예산 소진·격자 소진이 같은 루틴(호출 %d곳)", n_call)) else ng("R2 소진 루틴 이원화", as.character(n_call))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_grid_consumed_exhausts","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
