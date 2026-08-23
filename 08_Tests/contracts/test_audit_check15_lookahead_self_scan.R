#!/usr/bin/env Rscript
## ============================================================================
## test_audit_check15_lookahead_self_scan.R — audit_bt_result Check 15 위반 주입
##   (2026-08-24 신설 — Check 15 소생과 한 몸)
##
## 왜 이 파일이 있는가: Check 15 는 2026-04-30 신설(b15e70f5d) 이래 **한 번도 실행된
##   적이 없었다.** `scan_lookahead` 라는 정의되지 않은 이름을 호출했고, 그것도
##   exists(..., inherits = FALSE) 로 감싸 놓아 항상 스킵 WARN 으로 떨어졌다.
##   결과: 모든 bt_result 의 integrity_status 가 상시 "WARNING" — PASS 를 요구하는
##   검사기가 구조적 상시-FAIL 이 되어 아무것도 못 잡았다.
##   ★죽은 체크는 조용하다. 그래서 "통과했다"만 보는 검사로는 재발을 못 잡는다 —
##     이 파일은 규약 "검사기는 양방향으로 재라"대로 **위반 주입**을 1급으로 둔다.
##
## 축:
##   T1        양성 대조 — 깨끗한 엔진 → PASS
##   T2~T6     위반 주입 — C7b / C7a / C1 / C10_LIQ / PY_C7_NEG_SHIFT → FAIL(sev=high)
##   T7~T8     미측정 ≠ 합격 — 경로 부재 / 경로 공란·NA → WARN (PASS 아님)
##   T9~T10    이름 계약 — 감사가 부르는 이름을 검출기가 **실제로 정의**하는가 +
##             죽은 이름(scan_lookahead)·프레임 한정 guard 재유입 차단
##   T11       경로 해석 — cwd 가 프로젝트 루트가 아니어도 스캔에 도달한다
##             (R 실행 규약이 전략 디렉터리로 cd 한다)
##
## 픽스처 무의존: bt_result 를 최소 골격으로 합성한다(*.rds 는 비추적이라 worktree 엔 없다).
##   다른 체크가 FAIL/WARN 이 나는 건 정상 — 이 파일은 Check 15 행만 단언한다.
##
## ★마지막 줄은 반드시 JSON 요약이다 — 러너가 JSON 만 집계한다.
## 실행: Rscript 08_Tests/contracts/test_audit_check15_lookahead_self_scan.R
## ============================================================================
suppressPackageStartupMessages({library(data.table)})

## ── 루트: **자기가 실린 트리 우선** (test_resolve_project_marker.sh 선례) ─────────
##   env 우선으로 잡으면 worktree 에서 돌린 초록이 main 코드를 잰다(2026-08-02 실측).
.t_root <- local({
  ok <- function(d) is.character(d) && length(d) == 1L && !is.na(d) && nzchar(d) &&
    file.exists(file.path(d, "02_Infrastructure/contracts/audit_bt_result.R"))
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  self_root <- if (length(m)) dirname(dirname(dirname(sub("^--file=", "", m[1])))) else NA_character_
  cands <- c(self_root, Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""), getwd())
  hit <- Filter(ok, cands)
  if (!length(hit)) stop("[test_check15] project root 미발견")
  hit[[1]]
})
setwd(.t_root)
cat(sprintf("[root] %s\n", .t_root))
suppressMessages(source("02_Infrastructure/contracts/audit_bt_result.R"))

## ── 채점기 ──────────────────────────────────────────────────────────────────
.RES <- list()
ok <- function(id, desc, cond, detail = "") {
  pass <- isTRUE(cond)
  .RES[[length(.RES) + 1L]] <<- list(id = id, pass = pass, desc = desc, detail = detail)
  cat(sprintf("[%s] %-4s %s%s\n", if (pass) "PASS" else "FAIL", id, desc,
              if (nzchar(detail)) paste0(" — ", detail) else ""))
  invisible(pass)
}
try_case <- function(id, desc, fn) {
  r <- tryCatch(fn(), error = function(e) structure(list(msg = conditionMessage(e)), class = "tcerr"))
  if (inherits(r, "tcerr")) ok(id, desc, FALSE, paste("예외:", r$msg)) else invisible(r)
}

FX <- file.path(tempdir(), "check15_fixtures")
dir.create(FX, showWarnings = FALSE, recursive = TRUE)

## 엔진 파일 1개를 쓰고 경로 반환
.engine <- function(name, lines) {
  p <- file.path(FX, name); writeLines(lines, p); p
}

## Check 15 만 보는 최소 bt_result 골격 — 픽스처(*.rds) 의존 제거
.skeleton <- function(fep) list(
  manifest = data.table(run_id = "CHECK15_TEST", strategy_id = "CHECK15_TEST",
                        strategy_version = "v1", start_date = as.Date("2020-01-01"),
                        end_date = as.Date("2021-12-31"), frequency = "monthly",
                        universe_id = "K200_KQ150", benchmark_ids = "KOSPI200",
                        integrity_status = "PENDING"),
  strategy_spec = data.table(strategy_name = "CHECK15_TEST", factor_engine_path = fep,
                             lookahead_prevention = "detect_lookahead static scan CLEAN (PIT C1-C15)",
                             survivorship_bias_control = "PIT membership"),
  period_returns = data.table(date = seq(as.Date("2020-01-31"), by = "month", length.out = 24L),
                              ret_net = rep(0.01, 24L), frequency = "monthly"),
  nav = data.table(date = seq(as.Date("2020-01-31"), by = "month", length.out = 24L),
                   nav = cumprod(rep(1.01, 24L))),
  metrics = data.table(metric_name = "CAGR", metric_value = 0.12, is_official = TRUE,
                       metric_type = "backtested", annualization_factor = 12)
)

## 골격을 감사한 뒤 Check 15 행만 뽑는다
.c15 <- function(fep) {
  b <- suppressMessages(audit_bt_result(.skeleton(fep)))
  A <- as.data.table(b$audit)
  r <- A[check_name == "lookahead_detector_self_scan"]
  if (!nrow(r)) return(list(status = NA_character_, severity = NA_character_,
                            details = NA_character_, n = 0L))
  list(status = as.character(r$status[1]), severity = as.character(r$severity[1]),
       details = as.character(r$details[1]), n = nrow(r))
}

## ── T1: 양성 대조 — 깨끗한 엔진 → PASS ───────────────────────────────────────
try_case("T1", "깨끗한 엔진 → Check 15 PASS", function() {
  p <- .engine("clean_engine.R", c(
    "# clean factor engine",
    "dt[, AvgTV := shift(frollmean(TradingValue, 20), 1)]",
    "dt <- dt[AvgTV >= 2e8]",
    "dt[, Score := Value_z]",
    "top <- dt[order(-Score)][1:25]"))
  r <- .c15(p)
  ok("T1", "깨끗한 엔진 → Check 15 PASS", identical(r$status, "PASS"),
     sprintf("status=%s | %s", r$status, r$details))
})

## ── T2~T6: 위반 주입 — 실제로 FAIL 을 내는가 ────────────────────────────────
INJ <- list(
  list(id = "T2", code = "C7b",             file = "inj_c7b.R",
       lines = c("# engine", "top <- dt[order(-fwd_ret)][1:25]", "w <- rep(1/25, 25)"),
       what  = "미래수익 정렬"),
  list(id = "T3", code = "C7a",             file = "inj_c7a.R",
       lines = c("# engine", "signal_z <- scale(raw_value)", "dt[, Score := signal_z]"),
       what  = "full-sample scale()"),
  list(id = "T4", code = "C1",              file = "inj_c1.R",
       lines = c("# engine", "vol <- sd(rets) * sqrt(252)", "w <- 1/vol"),
       what  = "full-sample sd()"),
  list(id = "T5", code = "C10_LIQ",         file = "inj_c10.R",
       lines = c("# engine", "dt[, AvgTV := frollmean(TradingValue, 20)]", "dt <- dt[AvgTV >= 2e8]"),
       what  = "당일 거래대금 유동성 필터"),
  list(id = "T6", code = "PY_C7_NEG_SHIFT", file = "inj_py.py",
       lines = c("# engine", "df[\"fwd\"] = df[\"ret\"].shift(-1)", "w = 1"),
       what  = ".py 음수 shift")
)
for (cs in INJ) {
  local({
    x <- cs
    desc <- sprintf("주입 %s(%s) → Check 15 FAIL(sev=high) ∧ 코드 노출", x$code, x$what)
    try_case(x$id, desc, function() {
      r <- .c15(.engine(x$file, x$lines))
      ok(x$id, desc,
         identical(r$status, "FAIL") && identical(r$severity, "high") &&
           grepl(x$code, r$details, fixed = TRUE),
         sprintf("status=%s sev=%s | %s", r$status, r$severity, r$details))
    })
  })
}

## ── T7: 미측정 ≠ 합격 — 경로 부재 → WARN ────────────────────────────────────
try_case("T7", "factor_engine_path 부재 → WARN (PASS 아님)", function() {
  r <- .c15(file.path(FX, "__no_such_engine__.R"))
  ok("T7", "factor_engine_path 부재 → WARN (PASS 아님)", identical(r$status, "WARN"),
     sprintf("status=%s | %s", r$status, r$details))
})

## ── T8: 미측정 ≠ 합격 — 경로 공란/NA → WARN ─────────────────────────────────
try_case("T8", "factor_engine_path 공란·NA → WARN (PASS 아님)", function() {
  r1 <- .c15("")
  r2 <- .c15(NA_character_)
  ok("T8", "factor_engine_path 공란·NA → WARN (PASS 아님)",
     identical(r1$status, "WARN") && identical(r2$status, "WARN"),
     sprintf("empty=%s na=%s", r1$status, r2$status))
})

## ── T9: 이름 계약 — 감사가 부르는 이름을 검출기가 실제로 정의하는가 ─────────
##   구 결함의 본체가 정확히 이것이다(호출 이름 ↔ 정의 이름 불일치). 이름을 못박는다.
try_case("T9", "감사 호출 이름이 lookahead_detector.R 에 실재 정의", function() {
  ld <- new.env(parent = globalenv())
  suppressMessages(sys.source("02_Infrastructure/validation/lookahead_detector.R", envir = ld))
  src <- readLines("02_Infrastructure/contracts/audit_bt_result.R", warn = FALSE)
  ## ★perl = TRUE 필수(r-portability 금칙 ⑥): TRE 는 매치 위치를 UTF-16 코드유닛으로 보고하는데
  ##   regmatches 는 코드포인트로 자른다 — 이 파일처럼 한글 주석이 많은 소스에서 매치 앞에
  ##   non-BMP 가 끼면 추출 창이 밀려 "그럴듯한 쓰레기"가 나온다(값 추출 자리라 무해하지 않다).
  called <- unique(unlist(regmatches(
    src, gregexpr("ld_env\\$[A-Za-z_.][A-Za-z0-9_.]*", src, perl = TRUE))))
  called <- sub("^ld_env\\$", "", called)
  missing <- called[!vapply(called, function(f) exists(f, envir = ld, mode = "function"), logical(1))]
  ok("T9", "감사 호출 이름이 lookahead_detector.R 에 실재 정의",
     length(called) > 0L && length(missing) == 0L,
     sprintf("호출={%s} 미정의={%s}", paste(called, collapse = ","), paste(missing, collapse = ",")))
})

## ── T10: 죽은 이름·프레임 한정 **guard** 재유입 차단 (돌연변이 가드) ────────
##   ★술어를 `exists(... inherits = FALSE)` 로 좁힌다. 구 결함은 "함수를 찾는 guard 가
##     직전 프레임만 봐서 항상 FALSE" 였다. `inherits = FALSE` 자체는 금칙이 아니다 —
##     resolver 의 `get0(nm, envir = fr, inherits = FALSE)` 는 **특정 프레임의 자기 바인딩만**
##     읽으려는 정당한 용법이고, 넓은 술어는 그것까지 잡아 검사기를 시끄럽게 만든다
##     (시끄러운 래칫은 죽은 래칫과 겉보기가 같아진다 — r-portability 금칙 ⑥ 주석과 같은 규율).
try_case("T10", "죽은 이름·exists(inherits=FALSE) guard 재유입 0", function() {
  src  <- readLines("02_Infrastructure/contracts/audit_bt_result.R", warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]                       # 주석(경위 서술)은 제외
  dead  <- grep("scan_lookahead", code, value = TRUE)
  guard <- grep("exists\\s*\\([^)]*inherits\\s*=\\s*FALSE", code, value = TRUE, perl = TRUE)
  ok("T10", "죽은 이름·exists(inherits=FALSE) guard 재유입 0",
     length(dead) == 0L && length(guard) == 0L,
     sprintf("scan_lookahead=%d exists_inherits_FALSE=%d", length(dead), length(guard)))
})

## ── T11: cwd 가 프로젝트 루트가 아니어도 스캔에 도달한다 ────────────────────
##   R 실행 규약은 전략 디렉터리로 cd 한다. 프로젝트-상대 경로가 cwd 로만 해석되면
##   이 체크는 조용히 "부재 WARN" 으로 다시 죽는다.
try_case("T11", "cwd≠루트에서도 프로젝트-상대 엔진 경로 해석 (스캔 도달)", function() {
  owd <- getwd(); on.exit(setwd(owd), add = TRUE)
  setwd(FX)
  r <- .c15("02_Infrastructure/alpha_search/fe_revision_agreement_top25.R")
  ok("T11", "cwd≠루트에서도 프로젝트-상대 엔진 경로 해석 (스캔 도달)",
     r$status %in% c("PASS", "FAIL"),
     sprintf("cwd=%s status=%s | %s", basename(FX), r$status, r$details))
})

## ── T12: 자기 트리 해석 — 적재 방식이 달라도 감사가 *이* 트리를 읽는가 ──────
##   ★T11 만으로는 부족했다. T11 은 "루트를 하나 찾아 스캔에 도달했다"만 보므로
##     **거짓 초록**이 난다(2026-08-24 실측): 초판 resolver 는 `ofile` 만 봐서
##     sys.source(상대·절대)·source(상대) 3종에서 main 을 가리켰는데, main 에도 같은 파일이
##     있어 스캔은 성공했다 — worktree 수리를 main 코드로 검증하는 형태다.
##     그래서 이 축은 "찾았는가"가 아니라 **"어느 트리인가"**를 직접 단언한다.
##     (규약 = feedback-code-root-is-not-data-root ⑤: source→ofile / sys.source→file)
try_case("T12", "적재 4종(sys.source·source × 상대·절대) 모두 자기 트리로 해석", function() {
  canon <- function(p) {
    owd <- getwd(); on.exit(setwd(owd), add = TRUE)
    if (!is.character(p) || length(p) != 1L || is.na(p) || !nzchar(p)) return("")
    tryCatch({ setwd(p); getwd() }, error = function(e) "")
  }
  here <- canon(".")
  rel  <- "02_Infrastructure/contracts/audit_bt_result.R"
  abs  <- file.path(here, rel)
  load1 <- function(f, how) {
    e <- new.env(parent = globalenv())
    invisible(capture.output(
      if (how == "sys") sys.source(f, envir = e) else source(f, local = e)))
    canon(get0(".ABR_ROOT", envir = e, ifnotfound = ""))
  }
  got <- c(sys_rel = load1(rel, "sys"), sys_abs = load1(abs, "sys"),
           src_rel = load1(rel, "src"), src_abs = load1(abs, "src"))
  bad <- names(got)[got != here]
  ok("T12", "적재 4종(sys.source·source × 상대·절대) 모두 자기 트리로 해석",
     nzchar(here) && length(bad) == 0L,
     sprintf("here=%s | 어긋난 적재={%s}", here,
             if (length(bad)) paste(sprintf("%s->%s", bad, got[bad]), collapse = " ") else "없음"))
})

## ── 요약 ────────────────────────────────────────────────────────────────────
n_pass <- sum(vapply(.RES, function(x) isTRUE(x$pass), logical(1)))
n_tot  <- length(.RES)
n_fail <- n_tot - n_pass
cat(sprintf("\n[test_audit_check15_lookahead_self_scan] %d/%d PASS\n", n_pass, n_tot))
if (n_fail > 0L)
  for (x in .RES) if (!isTRUE(x$pass)) cat(sprintf("  x %s %s — %s\n", x$id, x$desc, x$detail))

## ★마지막 줄 = JSON 요약 (러너 집계 대상)
cat(sprintf('{"test":"audit_check15_lookahead_self_scan","pass":%d,"fail":%d,"total":%d}\n',
            n_pass, n_fail, n_tot))
quit(status = if (n_fail > 0L) 1L else 0L)
