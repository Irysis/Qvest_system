## test_rf_verify_judge_hold.R — 감사가 측정을 받지 않으면 Judge 트리거를 보류한다(2026-10-17 · 1801.01777 실측)
##   측정(러너 §11)은 감사 **전에** A 자격 관문을 태워 judge_request.eligible.json(pending)을 낸다. 감사가 미실행 · 상충 · 재구현이면
##   그 엔진은 재측정 · 보류 · 교체되므로 트리거를 judge_request.held.json(status held:<코드>)으로 옮겨야 한다.
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

cat("\n[3] 배선 — 감사 처분 3종(미실행 · 상충 · 재구현)이 분기 전에 보류를 부른다\n")
i_call <- grep(".v1001_hold_judge(dirname(ar)", VL, fixed = TRUE)
i_cond <- if (length(i_call)) i_call[1] - 1L else NA_integer_
i_req  <- grep('if (identical(.disp$action, "audit_required"))', VL, fixed = TRUE)
i_vrd  <- grep('jlog("fidelity_audit_verdict"', VL, fixed = TRUE)
chk(length(i_call) == 1L, "3a 호출 지점 1곳", length(i_call))
chk(length(i_call) == 1L && all(vapply(c('"audit_required"', '"audit_conflict"', '"reimplement"'), grepl, logical(1), x = VL[i_cond], fixed = TRUE)),
    "3b 조건 = audit_required · audit_conflict · reimplement", if (is.finite(i_cond)) VL[i_cond] else "-")
chk(length(i_call) == 1L && length(i_req) == 1L && length(i_vrd) == 1L && i_vrd[1] < i_call[1] && i_call[1] < i_req[1],
    "3c 위치 = 감사 판정 기록 뒤 · 첫 처분 분기(audit_required) 앞 — 세 분기 모두 quit 전에 지난다")
chk(!any(grepl('"proceed_suspect"', VL[i_cond], fixed = TRUE)), "3d 구현 의심 소비(proceed_suspect)는 보류하지 않는다 — 측정을 받는 처분")

unlink(file.path(tempdir(), c("jh_a", "jh_m", "jh_none")), recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_verify_judge_hold","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
