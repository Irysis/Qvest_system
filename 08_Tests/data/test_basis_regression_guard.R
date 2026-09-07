#!/usr/bin/env Rscript
# test_basis_regression_guard.R — xlsx(원가)가 naver(수정주가) 구간을 덮지 못한다 (2026-09-07)
#
# 왜: `incremental_update_file.R::incremental_ohlcvs()` 의 교체는 **날짜만** 본다
#   (`raw <- raw[!Date %in% update_dates]`). 08-31 이후를 포함한 OHLCVS_update.xlsx 가 한 번
#   들어오면 수정주가 구간이 통째로 원가로 되돌아가고, 행 수도 날짜도 맞으니 **어느 계기도 안 운다**.
#   두 원천이 같은 양이 아니라는 실측: 삼성 2018-05-04 50:1 분할 전날 종가 = 일별시세 2,650,000(원가)
#   vs siseJson 53,000(수정). daily_refresh 가 매일 이 경로를 부르므로 침묵 되돌림은 시간문제였다.
# 양방향: 양성(충돌 없으면 통과 · 명시 허용이면 통과) + 위반 주입(충돌인데 허용 없으면 정지).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressWarnings(suppressMessages(library(data.table)))
SRC <- file.path(ROOT, "02_Infrastructure/data/incremental_update_file.R")

## ── 가드 블록을 소스에서 잘라 **실제로 실행**한다 (문자열 단정이 아니라 행동을 잰다) ──
##   앵커는 의미로 잡는다(변수명·행번호를 못박지 않는다): 조정기준 차단 주석 ~ n_replaced 계산 직전.
ln <- readLines(SRC, encoding = "UTF-8", warn = FALSE)
st <- grep("조정기준 역행 차단", ln, fixed = TRUE)
en <- grep("n_replaced <- raw[Date %in% update_dates, .N]", ln, fixed = TRUE)
if (length(st) && length(en) && en[1] > st[1]) ok(sprintf("A0 가드 블록 추출 (%d줄)", en[1] - st[1])) else {
  ng("A0 가드 블록을 못 찾았다 — 표적 상실"); cat('{"test":"basis_regression_guard","pass":0,"fail":1,"total":1}\n'); quit(status = 1) }
blk <- ln[st[1]:(en[1] - 1L)]

run_guard <- function(raw, update_dates, allow = FALSE) {
  e <- new.env(parent = globalenv())
  assign("raw", raw, envir = e); assign("update_dates", update_dates, envir = e)
  old <- Sys.getenv("QVEST_ALLOW_BASIS_REGRESSION", unset = NA_character_)
  Sys.setenv(QVEST_ALLOW_BASIS_REGRESSION = if (allow) "1" else "0")
  on.exit({ if (is.na(old)) Sys.unsetenv("QVEST_ALLOW_BASIS_REGRESSION") else
              Sys.setenv(QVEST_ALLOW_BASIS_REGRESSION = old) }, add = TRUE)
  tryCatch({ eval(parse(text = paste(blk, collapse = "\n")), envir = e); list(stopped = FALSE, msg = "") },
           error = function(x) list(stopped = TRUE, msg = conditionMessage(x)))
}

D <- function(s) as.Date(s)
mk <- function(src_dates) {
  rbindlist(lapply(names(src_dates), function(s)
    data.table(Date = D(src_dates[[s]]), Ticker = "A000001", Close = 100, source = s)))
}
raw_mixed <- mk(list(quantiwise = c("2026-08-27","2026-08-28"), naver = c("2026-08-31","2026-09-01")))

cat("=== A. 양성 — 충돌이 없으면 통과한다 ===\n")
r <- run_guard(raw_mixed, D(c("2026-08-27","2026-08-28")))
if (!r$stopped) ok("A1 naver 구간을 안 건드리는 xlsx 는 통과(정상 일일 갱신을 안 막는다)") else
  ng("A1 정상 갱신을 막았다 — 과잉 차단", r$msg)
r <- run_guard(mk(list(quantiwise = c("2026-08-27","2026-08-28"))), D("2026-08-28"))
if (!r$stopped) ok("A2 naver 행이 아예 없으면 통과(구 데이터 재빌드 경로 보존)") else ng("A2 naver 부재인데 막았다")

cat("=== B. 위반 주입 — 조정기준 역행 ===\n")
r <- run_guard(raw_mixed, D(c("2026-08-28","2026-08-31")))
if (r$stopped) ok("B1 naver 구간을 덮으려 하면 정지") else ng("B1 원가가 수정주가를 조용히 덮었다")
if (r$stopped && grepl("조정기준 역행", r$msg, fixed = TRUE)) ok("B2 사유가 무엇인지 말한다") else
  ng("B2 정지 사유가 불명", r$msg)
if (r$stopped && grepl("2026-08-31", r$msg, fixed = TRUE)) ok("B3 어느 날짜가 걸렸는지 말한다") else
  ng("B3 충돌 날짜 미표기", r$msg)
## 전 구간을 덮는 경우(가장 위험한 형태)
r <- run_guard(raw_mixed, D(c("2026-08-27","2026-08-28","2026-08-31","2026-09-01")))
if (r$stopped) ok("B4 전 구간 재수출도 막는다") else ng("B4 전 구간 덮어쓰기가 통과")

cat("=== C. 명시 허용 — 되돌림은 의도를 밝혀야 한다 ===\n")
r <- run_guard(raw_mixed, D(c("2026-08-28","2026-08-31")), allow = TRUE)
if (!r$stopped) ok("C1 QVEST_ALLOW_BASIS_REGRESSION=1 이면 진행(막다른 골목 아님)") else
  ng("C1 명시 허용도 막힌다 — 되돌릴 방법이 없다", r$msg)
## 부재는 거부다 — 환경변수가 없을 때 통과하면 안 된다
e <- new.env(parent = globalenv())
assign("raw", raw_mixed, envir = e); assign("update_dates", D(c("2026-08-28","2026-08-31")), envir = e)
oldv <- Sys.getenv("QVEST_ALLOW_BASIS_REGRESSION", unset = NA_character_)
Sys.unsetenv("QVEST_ALLOW_BASIS_REGRESSION")
r2 <- tryCatch({ eval(parse(text = paste(blk, collapse = "\n")), envir = e); FALSE }, error = function(x) TRUE)
if (!is.na(oldv)) Sys.setenv(QVEST_ALLOW_BASIS_REGRESSION = oldv)
if (r2) ok("C2 환경변수 부재 = 거부(부재를 허용으로 읽지 않는다)") else ng("C2 부재가 통과했다")

cat("=== D. 배선 — daily_refresh 가 부르는 그 함수인가 ===\n")
if (any(grepl("QVEST_ALLOW_BASIS_REGRESSION", ln, fixed = TRUE))) ok("D1 가드가 소비 파일 안에 있다") else ng("D1 가드 부재")
## 경로는 재도출한다 — 파일 위치를 못박으면 옮길 때 검사가 죽는다(오늘 다른 검사에서 밟았다)
dr <- Filter(file.exists, file.path(ROOT, c("02_Infrastructure/data/daily_refresh.sh",
                                            "02_Infrastructure/ops/daily_refresh.sh")))[1]
if (is.na(dr)) dr <- ""
if (nzchar(dr) && file.exists(dr)) {
  drl <- readLines(dr, encoding = "UTF-8", warn = FALSE); drl <- sub("#.*$", "", drl)
  if (any(grepl("incremental_update_all", drl, fixed = TRUE)))
    ok("D2 daily_refresh 가 이 경로를 부른다 — 가드가 실제 위험 지점에 있다") else
    ng("D2 daily_refresh 가 이 경로를 안 부른다 — 가드 위치 재검토")
} else ng("D2 daily_refresh.sh 를 못 찾았다")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"basis_regression_guard","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
