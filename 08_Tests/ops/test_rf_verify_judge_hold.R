## test_rf_verify_judge_hold.R — 검증기가 받지 않은 측정의 Judge 트리거를 보류한다(2026-10-17 · 1801.01777 실측)
##   측정(러너 §11)은 A 자격 관문을 태워 judge_request.eligible.json(pending)을 낸다. 구판은 감사가 측정 **뒤**라 감사 기각 때 트리거가
##   남았다(감사 자리 보류로 수리). 같은 날 감사가 측정 **앞**으로 옮겨져 감사 기각에는 트리거가 생기지 않고, 남은 자리 =
##   측정 뒤 검증 실패(fail() — 축 · PIT 구조 · 충실도 꼬리표). fail() 이 트리거를 judge_request.held.json(status held:<코드>)으로 옮긴다.
##   검증기(02_Infrastructure/ops/rf_replication_verify.R)의 함수 정의만 격리 환경에 올린다(본문 미실행).
## 실행: Rscript 08_Tests/ops/test_rf_verify_judge_hold.R
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(cond, m, d = "") if (isTRUE(cond)) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") } else { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
VERIFY_R <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R")
VL <- readLines(VERIFY_R, warn = FALSE, encoding = "UTF-8")

## 함수 정의 텍스트를 소스에서 잘라 격리 환경에 싣는다(돌연변이는 이 텍스트를 치환 — deparse 아님)
.def_text <- function(nm) {
  i <- which(startsWith(VL, paste0(nm, " <- function(")))
  if (!length(i)) return(NULL)
  for (j in i[1]:length(VL)) {
    t <- paste(VL[i[1]:j], collapse = "\n")
    if (!inherits(tryCatch(parse(text = t), error = function(e) e), "error")) return(t)
  }
  NULL
}
HOLD <- .def_text(".v1001_hold_judge")
.load <- function(txt) {
  e <- new.env(parent = globalenv()); e$EV <- character(0)
  e$jlog <- function(event, ...) assign("EV", c(get("EV", envir = e), event), envir = e)
  eval(parse(text = txt), envir = e); e
}
.fixture <- function(tag) {
  td <- gsub("\\\\", "/", file.path(tempdir(), paste0("jh_", tag))); unlink(td, recursive = TRUE); dir.create(td)
  write_json(list(schema = "judge_request_v2", status = "pending", grade = "A", strategy_id = "RP_FIXTURE",
                  engine_path = "x/engine.R", a_eligibility = list(eligible = TRUE, codes = list())),
             file.path(td, "judge_request.eligible.json"), auto_unbox = TRUE, pretty = TRUE)
  td
}

cat("\n[1] 보류 함수 — 트리거를 옮기고 원 필드를 지킨다\n")
chk(!is.null(HOLD), "1a 검증기에 .v1001_hold_judge 정의가 있다")
if (!is.null(HOLD)) {
  e <- .load(HOLD); td <- .fixture("a")
  r <- e$.v1001_hold_judge(td, code = "fidelity_reimplement", verdict = "misdeclared")
  h <- tryCatch(fromJSON(file.path(td, "judge_request.held.json"), simplifyVector = FALSE), error = function(err) list())
  chk(isTRUE(r) && !file.exists(file.path(td, "judge_request.eligible.json")), "1b eligible 트리거가 사라진다(Judge 스폰 대상 아님)")
  chk(identical(h$status, "held:fidelity_reimplement") && identical(h$held_after_publish$code, "fidelity_reimplement") &&
        identical(h$held_after_publish$verdict, "misdeclared"), "1c held 파일 = status held:<코드> · 사유 블록(코드 · 감사 판정)", h$status %||% "-")
  chk(identical(h$grade, "A") && identical(h$strategy_id, "RP_FIXTURE") && isTRUE(h$a_eligibility$eligible),
      "1d 원 요청 필드(등급 · 전략 · 관문 판정)는 그대로 남는다")
  chk("judge_request_held" %in% e$EV, "1e 저널 judge_request_held", paste(e$EV, collapse = ","))
  td2 <- gsub("\\\\", "/", file.path(tempdir(), "jh_none")); unlink(td2, recursive = TRUE); dir.create(td2)
  chk(identical(e$.v1001_hold_judge(td2, code = "fidelity_reimplement"), FALSE) && !length(list.files(td2)),
      "1f 트리거가 없으면 아무것도 만들지 않는다(A 아닌 측정)")

  cat("\n[2] 양성 대조 — 트리거를 지우지 않는 돌연변이를 1b 가 잡는다\n")
  mut <- sub("    file.remove(src)\n", "    TRUE\n", HOLD, fixed = TRUE)
  chk(!identical(mut, HOLD), "2a 돌연변이 치환 성사(소스 텍스트)")
  em <- .load(mut); tdm <- .fixture("m")
  em$.v1001_hold_judge(tdm, code = "fidelity_reimplement")
  chk(file.exists(file.path(tdm, "judge_request.eligible.json")), "2b 돌연변이판은 eligible 이 남는다 → 1b 가 빨개진다(검출력 있음)")
}

cat("\n[3] 배선 — 감사는 측정 앞(10-17)이라 감사 자리엔 보류가 없고, 측정 뒤 검증 실패(fail())가 보류를 부른다\n")
CODE <- sub("#.*$", "", VL)
chk(!any(grepl(".v1001_hold_judge(dirname(ar)", CODE, fixed = TRUE)), "3a 감사 자리 호출 없음 — 감사 시점엔 측정도 트리거도 없다")
FAIL_TXT <- .def_text("fail")
chk(!is.null(FAIL_TXT) && grepl(".v1001_hold_judge(", FAIL_TXT, fixed = TRUE) && grepl('exists("ar", envir = .home', FAIL_TXT, fixed = TRUE),
    "3b fail() 가 산출물 경로(ar)가 있을 때만 보류를 부른다")

cat("\n[4] fail() 구동 — 측정 뒤 실패면 트리거 보류 · 측정 전 실패면 손대지 않음 (양방향 + 뮤테이션)\n")
.fail_env <- function(fail_txt, td, with_ar) {
  e <- .load(paste(HOLD, fail_txt, sep = "\n"))
  e$REQ <- file.path(td, "req.json"); writeLines('{"status":"in_progress"}', e$REQ)
  e$TITLE <- "픽스처"; e$PKEY <- "9999.00002"
  e$.v1001_report <- function(...) invisible(TRUE); e$.tg_target_label <- function(t, k) t; e$.v1001_clip_words <- function(x, n) x
  e$quit <- function(...) stop(structure(class = c("quit_called", "condition"), list(message = "quit", call = NULL)))
  if (with_ar) e$ar <- file.path(td, "authoritative_remeasure.json")
  e
}
.call_fail <- function(e) tryCatch({ e$fail("pit_structural", "C1 위반 픽스처"); FALSE }, quit_called = function(q) TRUE)
if (!is.null(FAIL_TXT) && !is.null(HOLD)) {
  t4 <- .fixture("f"); e4 <- .fail_env(FAIL_TXT, t4, with_ar = TRUE); q4 <- .call_fail(e4)
  h4 <- tryCatch(fromJSON(file.path(t4, "judge_request.held.json"), simplifyVector = FALSE), error = function(err) list())
  chk(isTRUE(q4) && !file.exists(file.path(t4, "judge_request.eligible.json")) && identical(h4$status, "held:verify_pit_structural") &&
        identical(fromJSON(e4$REQ)$status, "failed_needs_session"),
      "4a 측정 뒤 실패(ar 있음) → 트리거 held:verify_<사유> · 요청 failed_needs_session · 종료", h4$status %||% "-")
  t5 <- .fixture("g"); e5 <- .fail_env(FAIL_TXT, t5, with_ar = FALSE); q5 <- .call_fail(e5)
  chk(isTRUE(q5) && file.exists(file.path(t5, "judge_request.eligible.json")) && !file.exists(file.path(t5, "judge_request.held.json")),
      "4b 측정 전 실패(ar 없음 — 예: pit_preflight) → 트리거 파일을 건드리지 않는다 ★음성")
  mutf <- sub('  if (exists("ar", envir = .home, inherits = FALSE))\n', "  if (FALSE)\n", FAIL_TXT, fixed = TRUE)
  chk(!identical(mutf, FAIL_TXT), "4c 뮤테이션 치환 성사(소스 텍스트)")
  t6 <- .fixture("h"); .call_fail(.fail_env(mutf, t6, with_ar = TRUE))
  chk(file.exists(file.path(t6, "judge_request.eligible.json")), "4d 보류를 끈 뮤테이션판은 eligible 이 남는다 → 4a 가 빨개진다(검출력)")
}

unlink(file.path(tempdir(), c("jh_a", "jh_m", "jh_none", "jh_f", "jh_g", "jh_h")), recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_verify_judge_hold","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
