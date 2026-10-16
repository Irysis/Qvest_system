## test_lookahead_c17_comment.R — C17(align_factor_direction 무 sig_date) 판정은 코드 부분으로만(2026-10-17)
##   1801.01777 재구현판에서 `MIN_IC_MONTHS <- 36L  # align_factor_direction() default …` 의 **주석 언급**을 호출로 잡아
##   측정 1회를 통째로 버렸다. 양방향: 주석 · 문자열 언급은 안 잡는다 / 진짜 호출은 주석에 'sig_date =' 를 적어도 잡는다.
## 실행: Rscript 08_Tests/validation/test_lookahead_c17_comment.R
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")))
PASS <- 0L; FAIL <- 0L
chk <- function(cond, m, d = "") if (isTRUE(cond)) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") } else { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
td <- gsub("\\\\", "/", file.path(tempdir(), "la_c17")); unlink(td, recursive = TRUE); dir.create(td)
c17 <- function(code) {
  f <- file.path(td, sprintf("e%d.R", sample.int(1e6, 1L))); writeLines(code, f)
  r <- suppressMessages(detect_lookahead(f, verbose = FALSE))
  sum(vapply(r$violations %||% list(), function(v) identical(v$check, "C17_INFRA_PIT_DIRECTION"), logical(1)))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

chk(c17("MIN_IC_MONTHS <- 36L      # align_factor_direction() default — the") == 0L, "1 뒤붙은 주석 속 함수 이름 = 호출 아님(1801.01777 오탐)")
chk(c17('msg <- "see align_factor_direction(z) docs"') == 0L, "2 문자열 속 함수 이름 = 호출 아님")
chk(c17("res <- align_factor_direction(z, reg, sig_date = d)") == 0L, "3 sig_date 를 넘긴 호출 = 통과")
chk(c17("res <- align_factor_direction(z, reg)") == 1L, "4 양성 대조 — sig_date 없는 호출은 잡는다")
chk(c17("res <- align_factor_direction(z, reg)  # sig_date = d 는 위에서") == 1L, "5 우회 차단 — 주석에 'sig_date =' 를 적어도 잡는다(코드 부분만 본다)")
eng <- file.path(ROOT, "04_Research/strategies/RP_AUTO_CLEAN_1801_01777/engine.R")
if (file.exists(eng)) {
  r <- suppressMessages(detect_lookahead(eng, verbose = FALSE))
  n <- sum(vapply(r$violations %||% list(), function(v) identical(v$check, "C17_INFRA_PIT_DIRECTION"), logical(1)))
  chk(n == 0L, "6 회귀 — 1801.01777 재구현 엔진의 C17 = 0(실제 호출 236줄은 sig_date 를 넘긴다)", paste("C17", n, "· clean", isTRUE(r$clean)))
}
unlink(td, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"lookahead_c17_comment","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
