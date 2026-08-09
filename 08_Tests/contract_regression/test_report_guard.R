## test_report_guard.R — 보고 줄 무음 증발 가드 (2026-08-09 실사고 재발방지)
## ★실사고: 귀무 창 게이트가 **두 스크립트 연속 침묵**. 원인 = nl$observed 라는 없는 필드 →
##   NULL - NULL = numeric(0) → sprintf = character(0) → cat() 이 줄 전체를 출력 안 함.
##   오류도 경고도 없다. 검사 결과가 "없음" 이 아니라 **"안 쟀음처럼 보임"** 이 된다.
## ★양방향: ①정상 입력은 통과해야 하고 ②길이 0 은 반드시 잡혀야 한다(위반 주입).
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/contracts/report_guard.R")
P <- 0L; F <- 0L
ok <- function(nm, cond) { if (isTRUE(cond)) { P <<- P+1L; cat(sprintf("  PASS  %s\n", nm)) }
                           else { F <<- F+1L; cat(sprintf("  FAIL  %s\n", nm)) } }
cat("=== A. 양성 대조 — 정상 입력은 출력되어야 한다 ===\n")
ok("스칼라 1개",      { o <- capture.output(say_guarded("v=%.2f", 1.5)); length(o)==1 && grepl("1.50", o) })
ok("인자 3개",        { o <- capture.output(say_guarded("%s %d %.1f", "a", 2L, 3.5)); length(o)==1 })
ok("인자 0개",        { o <- capture.output(say_guarded("고정 문구")); length(o)==1 })
ok("prefix 부착",     { o <- capture.output(say_guarded("x=%d", 7L, prefix="[q] ")); grepl("^\\[q\\] ", o) })
ok("반환 TRUE",       { invisible(capture.output(r <- say_guarded("ok=%d", 1L))); isTRUE(r) })
ok("길이2 벡터 허용", { o <- capture.output(say_guarded("v=%d", c(1L,2L))); length(o)==2 })
ok("NA 는 통과",      { o <- capture.output(say_guarded("v=%s", NA)); length(o)==1 })
ok("빈 문자열 통과",  { o <- capture.output(say_guarded("v=[%s]", "")); grepl("\\[\\]", o) })

cat("=== B. 위반 주입 — 길이 0 은 반드시 잡혀야 한다 ===\n")
ok("numeric(0)",        inherits(try(say_guarded("v=%.2f", numeric(0)), silent=TRUE), "try-error"))
ok("character(0)",      inherits(try(say_guarded("v=%s", character(0)), silent=TRUE), "try-error"))
ok("NULL 인자",         inherits(try(say_guarded("v=%s", NULL), silent=TRUE), "try-error"))
ok("integer(0)",        inherits(try(say_guarded("v=%d", integer(0)), silent=TRUE), "try-error"))
ok("logical(0)",        inherits(try(say_guarded("v=%s", logical(0)), silent=TRUE), "try-error"))
ok("2번째만 길이0",     inherits(try(say_guarded("%d %.2f", 1L, numeric(0)), silent=TRUE), "try-error"))
ok("실사고 재현(NULL-NULL)", { z <- list(a=1); inherits(try(say_guarded("d=%.4f", z$observed - z$null_mean), silent=TRUE), "try-error") })
ok("에러문에 위치 표기", { e <- try(say_guarded("%d %s", 1L, character(0)), silent=TRUE)
                           grepl("인자 2", attr(e, "condition")$message) })
ok("strict=FALSE 는 warning + FALSE", {
  r <- withCallingHandlers(say_guarded("v=%.2f", numeric(0), strict=FALSE),
                           warning=function(w) invokeRestart("muffleWarning")); isFALSE(r) })
ok("strict=FALSE 도 출력 안 함", {
  o <- capture.output(suppressWarnings(say_guarded("v=%.2f", numeric(0), strict=FALSE))); length(o)==0 })

cat("=== C. field() — 없는 필드를 NULL 로 흘리지 않는다 ===\n")
NL <- list(stat_window=0.03, delta=0.0176, percentile=55.8, inside=TRUE)
ok("존재 필드 반환",    identical(field(NL, "delta"), 0.0176))
ok("부재 필드 stop",    inherits(try(field(NL, "observed"), silent=TRUE), "try-error"))
ok("에러문에 실제 필드", { e <- try(field(NL, "null_mean"), silent=TRUE)
                           grepl("stat_window", attr(e, "condition")$message) })
ok("실사고 정확 재현",  inherits(try(field(NL,"observed") - field(NL,"null_mean"), silent=TRUE), "try-error"))
ok("논리형 필드 보존",  isTRUE(field(NL, "inside")))
ok("빈 리스트도 stop",  inherits(try(field(list(), "x"), silent=TRUE), "try-error"))

cat(sprintf("\n=== test_report_guard: %d PASS / %d FAIL (총 %d) ===\n", P, F, P+F))
if (F > 0L) quit(status = 1L)
