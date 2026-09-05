#!/usr/bin/env Rscript
# test_rf_resume_cell_by_code.R — 재개 대상은 위치가 아니라 코드로 찾는다 (2026-09-05 · 실사고 promo2 B4 재시도)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = globalenv()))))
## 픽스처 = 실사고 형태: B1 5 · B5 5 · B2 5 · B3 **4**(설계) · B4 5 = cells 24개, 격자 번호는 25까지
codes <- c(sprintf("B1_%d", 1:5), sprintf("B5_%d", 16:20), sprintf("B2_%d", 6:10), c("B3_12","B3_11","B3_15","B3_14"), sprintf("B4_%d", 21:25))
cells <- lapply(codes, function(c) list(code = c, label = c))
by_code <- function(cd) { k <- which(codes == cd); if (length(k)) cells[[k]] else NULL }
a21 <- list(n = 21L, cell_code = "B4_21", essence = NULL)
a25 <- list(n = 25L, cell_code = "B4_25", essence = NULL)
r21 <- rf_resume_cell(a21, cells, by_code); r25 <- rf_resume_cell(a25, cells, by_code)
if (identical(r21$cell$code, "B4_21") && identical(r21$how, "registered_code")) ok("R1 n=21 → B4_21 (등록 코드)") else ng("R1 n=21 이 다른 칸으로", paste(r21$cell$code, r21$how))
if (identical(r25$cell$code, "B4_25") && identical(r25$how, "registered_code")) ok("R2 n=25 → B4_25 (cells 24개여도) ★실사고") else ng("R2 n=25 unknown/밀림", paste(r25$cell$code, r25$how))
ae <- list(n = 22L, cell_code = "B4_22", essence = list(cell_code = "B4_22"))
re <- rf_resume_cell(ae, cells, by_code)
if (identical(re$cell$code, "B4_22") && identical(re$how, "essence_code")) ok("R3 essence 코드 우선") else ng("R3 essence 코드 무시")
old_map <- function(a) if (a$n <= length(cells)) cells[[a$n]]$code else NA_character_
if (identical(old_map(a21), "B4_22") && is.na(old_map(a25))) ok("R4 구 위치 규칙은 n=21→B4_22 · n=25→NULL — 픽스처가 결함을 가른다") else ng("R4 픽스처 판별력 없음")
leg <- rf_resume_cell(list(n = 3L, essence = NULL), cells, by_code)
if (identical(leg$how, "positional_legacy") && identical(leg$cell$code, "B1_3")) ok("R5 코드 없는 구 entry 는 위치 폴백 + how 표기") else ng("R5 구 entry 폴백 훼손")
unk <- rf_resume_cell(list(n = 9L, cell_code = "B9_99", essence = NULL), cells, by_code)
if (is.null(unk$cell) && identical(unk$how, "unknown")) ok("R6 없는 코드는 unknown (위치로 몰래 떨어지지 않음)") else ng("R6 없는 코드가 위치로 떨어진다")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), encoding = "UTF-8", warn = FALSE)
src <- sub("#.*$", "", src)   # 주석 제외 — 설명 주석이 구 표현을 인용해도 코드가 아니다
if (any(grepl("rf_resume_cell(", src, fixed = TRUE)) && !any(grepl("cells[[a$n]]", src, fixed = TRUE))) ok("R7 러너가 헬퍼를 부르고 위치 줄이 없다") else ng("R7 call site 미교체")
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_resume_cell_by_code","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
