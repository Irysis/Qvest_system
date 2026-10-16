## test_rf_verify_pit_preflight.R — 충실구현 검증기의 정적 PIT 사전 점검(2026-10-17)
##   러너는 detect_lookahead 를 엔진 실행 **뒤에** 해서, 1801.01777 재구현판은 DNN 26회 학습 뒤 오탐 1건으로 측정을 버렸다.
##   검증기(rf_replication_verify.R)가 같은 함수를 runner 호출 **전에** 돌리는지 — 위치(정적) + 동작(검증기 소스의 블록을 잘라 구동 · 양방향).
## 실행: Rscript 08_Tests/ops/test_rf_verify_pit_preflight.R
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
chk <- function(cond, m, d = "") if (isTRUE(cond)) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") } else { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
VL <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), warn = FALSE, encoding = "UTF-8")
i_pre <- grep(".pre_pit <- tryCatch(detect_lookahead(eng", VL, fixed = TRUE)
i_end <- grep('jlog("pit_preflight_clean"', VL, fixed = TRUE)
i_run <- grep("res <- tryCatch(do.call(run_paper_replication", VL, fixed = TRUE)
chk(length(i_pre) == 1L && length(i_end) == 1L && length(i_run) == 1L && i_pre < i_end && i_end < i_run,
    "1 위치 — 사전 점검(detect_lookahead) → 통과 기록 → 러너 호출 순서", paste(i_pre, i_end, i_run))
if (length(i_pre) == 1L && length(i_end) == 1L) {
  BLOCK <- parse(text = paste(VL[i_pre:i_end], collapse = "\n"))
  run_block <- function(code) {
    f <- gsub("\\\\", "/", tempfile(fileext = ".R")); writeLines(code, f)
    sb <- new.env(parent = globalenv()); REC <- new.env(); REC$fail <- NULL; REC$ev <- character(0)
    sb$eng <- f
    sb$jlog <- function(event, ...) REC$ev <- c(REC$ev, event)
    sb$fail <- function(why, detail = "") { REC$fail <- list(why = why, detail = detail); stop("fail_called") }
    tryCatch(for (e in BLOCK) eval(e, sb), error = function(e) NULL)
    list(fail = REC$fail, ev = REC$ev)
  }
  r_bad <- run_block("res <- align_factor_direction(z, reg)")
  chk(identical(r_bad$fail$why, "pit_preflight") && grepl("C17_INFRA_PIT_DIRECTION", r_bad$fail$detail) && !("pit_preflight_clean" %in% r_bad$ev),
      "2 양성 대조 — sig_date 없는 호출 엔진 → 러너 전에 fail('pit_preflight') · 통과 기록 없음", paste(r_bad$fail$why %||% "-", substr(r_bad$fail$detail %||% "", 1, 80)))
  r_ok <- run_block("MIN_IC_MONTHS <- 36L      # align_factor_direction() default\nres <- align_factor_direction(z, reg, sig_date = d)")
  chk(is.null(r_ok$fail) && "pit_preflight_clean" %in% r_ok$ev, "3 깨끗한 엔진(주석 언급 + sig_date 호출) → 통과 · 기록 pit_preflight_clean")
}
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_verify_pit_preflight","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
