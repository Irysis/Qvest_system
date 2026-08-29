# test_book_registry.R — v10 BOOK writer 의 양방향 검증 (임시 루트 — 실장부 불변)
# 계약: ①A등급만 등록 ②mandate 예외 아니면 judge_verdict(pit_pass=true) 실제 재도출
#       ③pit_pass=false verdict 거부 ④중복 등록 거부 ⑤tracking append-only ⑥왕복 파싱
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(jsonlite))
pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
TMP <- file.path(tempdir(), sprintf("bk_test_%d", Sys.getpid()))
dir.create(file.path(TMP, "02_Infrastructure"), recursive = TRUE, showWarnings = FALSE)
file.create(file.path(TMP, "02_Infrastructure", "config.R"))
source("02_Infrastructure/book/book_registry.R")
R <- TMP

# ① B등급 거부
r1 <- tryCatch({ register_book_entry("factor_strategy", "S1", 1L, grade = "B", root = R); "no_stop" },
               error = function(e) conditionMessage(e))
if (grepl("A등급만", r1)) ok("① B등급 등록 거부") else ng(sprintf("① B 통과됨: %s", r1))

# ② verdict 부재 거부 (mandate 아님)
r2 <- tryCatch({ register_book_entry("factor_strategy", "S1", 1L, grade = "A",
                                     judge_verdict_path = NULL, root = R); "no_stop" },
               error = function(e) conditionMessage(e))
if (grepl("judge_verdict_path 필수", r2)) ok("② verdict 없는 A 등록 거부") else ng(sprintf("② 통과됨: %s", r2))

# ③ pit_pass=false verdict 거부 (재도출 — 파일을 실제로 읽는다)
vf <- file.path(TMP, "verdict_fail.json")
write(toJSON(list(schema = "judge_verdict_v2", pit_pass = FALSE), auto_unbox = TRUE), vf)
r3 <- tryCatch({ register_book_entry("factor_strategy", "S1", 1L, grade = "A",
                                     judge_verdict_path = vf, root = R); "no_stop" },
               error = function(e) conditionMessage(e))
if (grepl("pit_pass", r3)) ok("③ pit_pass=false verdict 거부 (재도출)") else ng(sprintf("③ 통과됨: %s", r3))

# 정상 등록 (pit_pass=true)
vt <- file.path(TMP, "verdict_pass.json")
write(toJSON(list(schema = "judge_verdict_v2", pit_pass = TRUE), auto_unbox = TRUE), vt)
e1 <- register_book_entry("factor_strategy", "S1", 1L, grade = "A",
                          judge_verdict_path = vt, root = R)
if (identical(e1$book_id, "BOOK_0001")) ok("정상 등록 BOOK_0001") else ng("등록 실패")

# mandate 예외
e2 <- register_book_entry("rotation_rule", "FR_X", 2L, grade = "A",
                          grade_basis = "dohoon_mandate_20260829", root = R)
if (identical(e2$book_id, "BOOK_0002")) ok("mandate 예외 등록 (verdict 불요)") else ng("mandate 예외 실패")

# ④ 중복 거부
r4 <- tryCatch({ register_book_entry("factor_strategy", "S1", 1L, grade = "A",
                                     judge_verdict_path = vt, root = R); "no_stop" },
               error = function(e) conditionMessage(e))
if (grepl("이미 등록", r4)) ok("④ 중복 등록 거부") else ng(sprintf("④ 중복 통과: %s", r4))

# ⑤ tracking append-only
invisible(update_book_tracking("BOOK_0001", list(last_nav_date = "2026-08-29", sharpe = 1.2), root = R))
invisible(update_book_tracking("BOOK_0001", list(last_nav_date = "2026-08-30", sharpe = 1.3), root = R))
b <- read_book(R)
h <- b$entries[[1]]$tracking$history
if (length(h) == 2L && identical(b$entries[[1]]$tracking$last_nav_date, "2026-08-30"))
  ok("⑤ tracking history append-only (2건 누적)") else ng("⑤ tracking 기록 이상")

# ⑥ 왕복
chk <- tryCatch(fromJSON(file.path(TMP, "06_Registry", "book", "book_registry.json"),
                         simplifyVector = FALSE), error = function(e) NULL)
if (!is.null(chk) && length(chk$entries) == 2L) ok("⑥ 왕복 파싱 (2 entries)") else ng("⑥ 파싱 실패")

unlink(TMP, recursive = TRUE, force = TRUE)
cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
if (fail > 0L) quit(status = 1L)
