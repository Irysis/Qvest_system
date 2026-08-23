## test_promote_crash_exit.R — promote 자식 프로세스 crash 검출의 행동 검사 (양방향)
## 대상: 02_Infrastructure/ops/weekly_cleaner_sweep.R :: .promote_crash_verdict()
##
## 왜: 2026-08-16 폐쇄루프 감사의 뿌리 = "정체를 재는 계기가 전부 **대리 지표**".
##     구 crash 판정은 `grep("\\[promote\\].*(PASS|FAIL)", out)` 한 축뿐이었다
##     ⇒ 자식이 exit≠0 으로 죽어도 **죽기 전에 verdict 한 줄만 찍으면 crash 0**.
##     실사고: MAX_PATH 초과로 죽은 후보 1건이 'promote crash 0' 으로 보고됨.
##     stdout 문자열은 append 만으로 초록이 되므로, 그 자체가 계기를 끄는 스위치다.
##
## ★검사 규율: 대리 지표를 내용 기반으로 바꾸는 수리는 **검출력을 죽이기 쉽다**.
##   검사 사망과 정상은 겉보기가 같다(둘 다 초록). 따라서 양방향이어야 한다:
##     [정상]  진짜 정상 종료에서 경보가 **안 뜨는지**
##     [위반]  일부러 만든 진짜 crash 에서 경보가 **뜨는지**
##   그리고 ★조작 선행검증: 가짜 스크립트가 **실제로** 의도한 exit code 를 냈는지 먼저
##   독립 채널(system2(stdout=FALSE) 반환값)로 증명해야 "안 잡혔다/잡혔다" 결론을 낼 자격이 생긴다.
##   (조작이 실패했는데 '변화 없음'을 '전파 안 됨'으로 오귀속한 사고가 2026-08-20 있었다.)
##
## 실행: Rscript 08_Tests/hooks/test_promote_crash_exit.R
## 상태 쓰기: 기본 OFF. QVEST_TEST_PROMOTE_LIVE=1 일 때만 실제 promote.R 1건을 돌린다
##            (review_log 신규 파일은 검사 말미에 원상복구).

## ── 자기 위치 우선(r-portability 금칙④-b: 러너는 self-first) ────────────────
.args <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .args, value = TRUE)
.here <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]), winslash = "/", mustWork = FALSE)) else getwd()
.root <- normalizePath(file.path(.here, "..", ".."), winslash = "/", mustWork = FALSE)
REL <- "02_Infrastructure/ops/weekly_cleaner_sweep.R"
if (!file.exists(file.path(.root, REL))) {
  cand <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
  if (nzchar(cand) && file.exists(file.path(cand, REL))) .root <- gsub("\\\\", "/", cand)
}
SRC <- file.path(.root, REL)
if (!file.exists(SRC)) stop(sprintf("대상 파일을 못 찾음: %s (러너 위치 문제이지 검사 실패가 아님)", SRC))

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
.msg1 <- function(x) { x <- as.character(x); if (!length(x)) "(빈 메시지)" else x[1] }
ok   <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(.msg1(m))) paste0(" — ", .msg1(m)) else "")) }
bad  <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(.msg1(m))) paste0(" — ", .msg1(m)) else "")) }
skip <- function(n, m = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s%s\n", n, if (nzchar(.msg1(m))) paste0(" — ", .msg1(m)) else "")) }
chk  <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)

## ── [0] 원본 함수 추출 — 복제 아님 ──────────────────────────────────────────
## weekly_cleaner_sweep.R 는 source 하면 스윕 전체가 돈다(파일 삭제·텔레그램 포함).
## 따라서 파일을 **파싱해 해당 정의 표현식만** 골라 eval 한다 = 원본 정의 그 자체를 호출.
cat("\n[0] 원본 정의 추출 (복제 검증 금지 — 파일을 파싱해 그 표현식만 eval)\n")
exprs <- parse(SRC)
is_def <- vapply(exprs, function(e) {
  is.call(e) && length(e) >= 3L &&
    as.character(e[[1]]) %in% c("<-", "=", "<<-") &&
    identical(as.character(e[[2]]), ".promote_crash_verdict")
}, logical(1))
chk("T0a_definition_found_exactly_once", sum(is_def) == 1L,
    sprintf("`.promote_crash_verdict` 최상위 정의 %d건 (0 = 수리 미적용 / 2+ = 중복정의)", sum(is_def)))
if (sum(is_def) != 1L) { cat(sprintf("\nTOTAL: %d pass / %d fail / %d skip\n", PASS, FAIL, SKIP)); quit(status = 1L) }
ENV <- new.env(parent = globalenv())
eval(exprs[[which(is_def)]], envir = ENV)
verdict <- get(".promote_crash_verdict", envir = ENV)
chk("T0b_is_function", is.function(verdict), "추출물이 함수")

## 구 로직 재현 (비교 기준선 — 이것이 무엇을 놓쳤는지 보이기 위해서만 존재)
old_logic_crash <- function(out) length(grep("\\[promote\\].*(PASS|FAIL)", out, value = TRUE)) == 0L

## ── 가짜 promote 스크립트 제조기 ────────────────────────────────────────────
TD <- file.path(tempdir(), sprintf("promote_crash_%d", Sys.getpid()))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
mk <- function(name, lines) { p <- file.path(TD, name); writeLines(lines, p); p }

VERDICT_LINE <- '[promote] CAND_fake (AS/mode_local mode=alpha_search metric=proxy) weighted=0.512 hurdles=FALSE -> FAIL'

FAKE <- list(
  ## A: exit≠0 인데 죽기 **전에** verdict 를 찍는다 = 이 수리의 본체
  exit3_with_verdict = mk("fake_exit3_verdict.R", c(
    sprintf('cat(%s, "\\n", sep = "")', deparse(VERDICT_LINE)),
    'cat("[promote] ... 중략 ...\\n")',
    'quit(status = 3L)')),
  ## B: 조용히 정상 종료하지만 verdict 가 없다 = 기존 축 (유지 확인)
  exit0_no_verdict = mk("fake_exit0_silent.R", c(
    'cat("[promote] Loaded (v8.0 r7-복원 + 2-tier).\\n")',
    'quit(status = 0L)')),
  ## C: 둘 다 — exit≠0 ∧ verdict 없음
  exit1_no_verdict = mk("fake_exit1_silent.R", c(
    'cat("Error in promote_to_axiom(...) : MAX_PATH 초과\\n")',
    'quit(status = 1L)')),
  ## D: 정상 — exit 0 ∧ verdict 있음 (양성 대조: 여기서 경보가 뜨면 오탐)
  exit0_with_verdict = mk("fake_exit0_verdict.R", c(
    sprintf('cat(%s, "\\n", sep = "")', deparse(VERDICT_LINE)),
    'quit(status = 0L)'))
)

run_fake <- function(p) suppressWarnings(system2("Rscript", shQuote(p), stdout = TRUE, stderr = TRUE))
## 독립 채널 exit code (attr() 과 다른 경로 — 조작 선행검증용)
exit_of <- function(p) suppressWarnings(system2("Rscript", shQuote(p), stdout = FALSE, stderr = FALSE))

## ── [1] ★조작 선행검증 — 가짜가 실제로 의도한 exit/출력을 내는가 ────────────
## 이게 통과하기 전에는 아래 결론을 낼 자격이 없다.
cat("\n[1] 조작 선행검증 (가짜 스크립트가 실제로 의도한 exit code·출력을 내는지 독립 확인)\n")
INTENT <- list(exit3_with_verdict = 3L, exit0_no_verdict = 0L,
               exit1_no_verdict = 1L, exit0_with_verdict = 0L)
OUT <- list(); MANIP_OK <- TRUE
for (nm in names(FAKE)) {
  ec_indep <- as.integer(exit_of(FAKE[[nm]]))
  o <- run_fake(FAKE[[nm]]); OUT[[nm]] <- o
  st <- attr(o, "status"); ec_attr <- if (is.null(st)) 0L else as.integer(st)
  want <- INTENT[[nm]]
  good <- identical(ec_indep, want) && identical(ec_attr, want)
  if (!good) MANIP_OK <- FALSE
  chk(sprintf("T1_%s_exit_took", nm), good,
      sprintf("의도 exit=%d / 독립측정=%d / attr(status)=%s — 두 채널 일치해야 조작이 먹은 것",
              want, ec_indep, if (is.null(st)) "NULL(=0)" else as.character(st)))
}
has_v <- function(o) length(grep("\\[promote\\].*(PASS|FAIL)", o)) > 0L
chk("T1_stdout_shape", has_v(OUT$exit3_with_verdict) && !has_v(OUT$exit0_no_verdict) &&
      !has_v(OUT$exit1_no_verdict) && has_v(OUT$exit0_with_verdict),
    "verdict 줄 유무도 의도대로 (A·D 있음 / B·C 없음)")
if (!MANIP_OK) {
  cat("\n[중단] 조작이 먹지 않았다 — 아래 '검출/미검출' 은 해석 불가.\n")
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skip\n", PASS, FAIL, SKIP)); quit(status = 1L)
}

## ── [2] 위반 주입 A — exit≠0 ∧ verdict 있음 (구 로직이 놓치던 축) ───────────
cat("\n[2] 위반 주입 A: exit≠0 인데 verdict 를 찍는 자식 (★이 수리의 본체)\n")
vA <- verdict(OUT$exit3_with_verdict)
chk("T2a_new_detects", isTRUE(vA$crash), "신 판정 = CRASH")
chk("T2b_reason_exit_nonzero", identical(vA$reason, "exit_nonzero"),
    sprintf("검출 축 = %s (verdict 는 있었으니 exit 축으로만 잡혀야 한다)", vA$reason))
chk("T2c_exit_recorded", identical(vA$exit, 3L), sprintf("exit=%s 기록", vA$exit))
chk("T2d_verdict_line_kept", !is.na(vA$verdict_line) && grepl("FAIL", vA$verdict_line),
    "죽기 전 찍힌 verdict 줄을 보존 — 다음 감사가 '초록처럼 보인 줄' 을 볼 수 있어야 한다")
chk("T2e_OLD_logic_missed_it", isFALSE(old_logic_crash(OUT$exit3_with_verdict)),
    "★구 로직은 이 입력을 crash 0 으로 집계했다 = 이 검사가 재는 검출력의 근거")

## ── [3] 위반 주입 B/C — 기존 축 유지 ────────────────────────────────────────
cat("\n[3] 위반 주입 B/C: verdict 부재 축이 살아 있는가 (회귀 방지)\n")
vB <- verdict(OUT$exit0_no_verdict)
chk("T3a_B_detects", isTRUE(vB$crash), "exit 0 이어도 verdict 없으면 CRASH")
chk("T3b_B_reason", identical(vB$reason, "no_verdict_line"), sprintf("검출 축 = %s", vB$reason))
chk("T3c_B_exit_zero", identical(vB$exit, 0L), "exit 은 0 으로 정직하게 기록")
chk("T3d_B_old_agrees", isTRUE(old_logic_crash(OUT$exit0_no_verdict)),
    "구 로직도 잡던 축 — 신 판정이 이를 잃지 않았다(회귀 없음)")
vC <- verdict(OUT$exit1_no_verdict)
chk("T3e_C_detects", isTRUE(vC$crash), "exit≠0 ∧ verdict 부재")
chk("T3f_C_reason_both", identical(vC$reason, "both"), sprintf("검출 축 = %s (두 축 동시)", vC$reason))

## ── [4] 양성 대조 — 정상에서 경보가 안 떠야 한다 (오탐 = 검사 신뢰 붕괴) ────
cat("\n[4] 양성 대조: 정상 종료(exit 0 ∧ verdict 있음)에서 오탐 없음\n")
vD <- verdict(OUT$exit0_with_verdict)
chk("T4a_no_false_alarm", isFALSE(vD$crash), "CRASH 아님")
chk("T4b_reason_na", is.na(vD$reason), "사유 NA")
chk("T4c_verdict_surfaced", identical(vD$verdict_line, VERDICT_LINE),
    "verdict 줄을 그대로 반환 — 로그 출력 경로가 구 동작과 동일")

## ── [5] 폴백 — status 속성이 없거나 해석 불가일 때 ──────────────────────────
cat("\n[5] 폴백: status 속성 부재/비수치 (입력 결손을 조용히 삼키지 않는가)\n")
plain <- c("[promote] x (AS/mode_local) weighted=0.5 hurdles=FALSE -> FAIL")  # attr 없음
vN <- verdict(plain)
chk("T5a_null_status_is_zero", isFALSE(vN$crash) && identical(vN$exit, 0L) && isTRUE(vN$exit_parsed),
    "status 속성 부재 = 정상종료(R system2 규약) — 오탐 없음")
noverd <- c("무슨 일이 있었는지 모를 출력")
vN2 <- verdict(noverd)
chk("T5b_null_status_no_verdict", isTRUE(vN2$crash) && identical(vN2$reason, "no_verdict_line"),
    "status 부재 + verdict 부재 = 기존 축으로 여전히 CRASH")
weird <- structure(plain, status = "boom")   # 비수치 status
vW <- verdict(weird)
chk("T5c_unparseable_status_conservative", isTRUE(vW$crash) && identical(vW$reason, "exit_nonzero") &&
      isFALSE(vW$exit_parsed),
    "status 해석 불가 = 보수적으로 비정상 처리 + exit_parsed=FALSE 로 그 사실을 남긴다(0 위장 금지)")
vE <- verdict(structure(character(0), status = 7L))
chk("T5d_empty_output_with_exit", isTRUE(vE$crash) && identical(vE$reason, "both") && identical(vE$exit, 7L),
    "출력 0줄 + exit 7 = both (빈 출력을 '변경 없음' 으로 읽지 않는다)")

## ── [6] 라이브 대조 — 실제 promote.R 1건 (기본 OFF: 상태 쓰기 때문) ─────────
cat("\n[6] 라이브 대조: 실제 promote.R + 실제 candidate (QVEST_TEST_PROMOTE_LIVE=1 일 때만)\n")
if (!identical(Sys.getenv("QVEST_TEST_PROMOTE_LIVE", "0"), "1")) {
  skip("T6_live_promote", "QVEST_TEST_PROMOTE_LIVE!=1 — 실제 promote.R 은 review_log 를 쓰므로 기본 비활성")
} else {
  promote_r <- file.path(.root, "02_Infrastructure/axiom/promote.R")
  cdir <- file.path(.root, "qepm/memory/axioms/candidates")
  ld <- file.path(.root, "qepm/memory/axioms/review_log")
  cands <- list.files(cdir, pattern = "^CAND_.*\\.json$", full.names = TRUE)
  if (!file.exists(promote_r) || !length(cands)) {
    skip("T6_live_promote", sprintf("promote.R 존재=%s / candidate %d건", file.exists(promote_r), length(cands)))
  } else {
    before <- list.files(ld)
    Sys.setenv(CLAUDE_PROJECT_DIR = .root)
    o <- suppressWarnings(system2("Rscript", c(shQuote(promote_r), shQuote(cands[1])),
                                  stdout = TRUE, stderr = TRUE))
    vL <- verdict(o)
    chk("T6a_live_no_false_alarm", isFALSE(vL$crash),
        sprintf("실제 정상 후보 → CRASH 아님 (exit=%s, verdict=%s)", vL$exit,
                substr(as.character(vL$verdict_line), 1, 60)))
    chk("T6b_live_matches_old", identical(vL$crash, old_logic_crash(o)),
        "정상 경로에서는 신·구 판정이 일치 — 이 수리는 정상 집계를 흔들지 않는다")
    for (f in setdiff(list.files(ld), before)) try(unlink(file.path(ld, f)), silent = TRUE)
  }
}

## ── [7] 배선 검사 — 스윕의 **실제 루프 본문**이 이 판정을 쓰는가 ───────────
## 함수만 고치고 호출부가 구 로직을 남겨두면 검사는 초록인데 운영은 그대로다.
## 그래서 파일에서 `for (cand in cands)` 표현식 자체를 꺼내 stub 환경에서 돌린다(복제 아님).
cat("\n[7] 배선: weekly_cleaner_sweep.R 의 promote 순회 루프 본문 직접 실행\n")
find_for <- function(e) {
  if (is.call(e)) {
    if (identical(as.character(e[[1]]), "for") && identical(as.character(e[[2]]), "cand")) return(e)
    for (i in seq_along(e)) {
      s <- tryCatch(e[[i]], error = function(...) NULL)
      if (!is.null(s)) { r <- find_for(s); if (!is.null(r)) return(r) }
    }
  }
  NULL
}
loop_expr <- NULL
for (e in exprs) { loop_expr <- find_for(e); if (!is.null(loop_expr)) break }
if (is.null(loop_expr)) {
  bad("T7a_loop_found", "`for (cand in cands)` 루프를 파일에서 못 찾음 — 구조가 바뀌었으면 이 검사를 갱신할 것")
} else {
  ok("T7a_loop_found", "promote 순회 루프 표현식 추출")
  run_loop <- function(fake_path) {
    LE <- new.env(parent = globalenv())
    assign(".promote_crash_verdict", verdict, envir = LE)
    assign("cands", file.path(TD, "dummy_candidate.json"), envir = LE)
    assign("promote_r", fake_path, envir = LE)
    assign("promote_n_crash", 0L, envir = LE)
    assign("promote_failures", list(), envir = LE)
    ## v9 (2026-08-23) 사전 SKIP 상태 스텁 — 루프 본문 첫 줄이 promote_skip 을 조회한다.
    ##   빈 목록 = "제외 대상 없음" → 아래 crash 축 판정은 종전과 동일 경로를 탄다.
    assign("promote_skip", list(), envir = LE)
    assign("promote_skips", list(), envir = LE)
    assign("promote_n_skip", 0L, envir = LE)
    invisible(capture.output(eval(loop_expr, envir = LE)))
    list(n = get("promote_n_crash", envir = LE), f = get("promote_failures", envir = LE),
         log = capture.output(eval(loop_expr, envir = LE)))
  }
  rA <- run_loop(FAKE$exit3_with_verdict)
  chk("T7b_loop_counts_exit_nonzero", identical(rA$n, 1L),
      sprintf("exit≠0 ∧ verdict 있음 → promote_n_crash=%s (구 배선이면 0)", rA$n))
  chk("T7c_loop_records_reason",
      length(rA$f) == 1L && identical(rA$f[[1]]$detected_by, "exit_nonzero") &&
        identical(rA$f[[1]]$exit, 3L),
      sprintf("promote_failures 레코드에 detected_by=%s exit=%s 기록 — '무엇이 0인가' 를 다음 감사가 알 수 있어야 한다",
              if (length(rA$f)) rA$f[[1]]$detected_by else "(없음)",
              if (length(rA$f)) rA$f[[1]]$exit else "(없음)"))
  chk("T7d_loop_log_says_crash", any(grepl("CRASH\\(exit_nonzero\\)", rA$log)),
      "콘솔 로그도 CRASH 로 말한다 — 초록으로 보이는 줄이 남지 않는다")
  rD <- run_loop(FAKE$exit0_with_verdict)
  chk("T7e_loop_no_false_alarm", identical(rD$n, 0L) && length(rD$f) == 0L,
      "정상 종료에서는 루프도 crash 0 (오탐 없음)")
  chk("T7f_loop_log_verdict", any(grepl("hurdles", rD$log)) && !any(grepl("CRASH", rD$log)),
      "정상 경로 로그는 구 동작대로 verdict 줄을 출력")
}

try(unlink(TD, recursive = TRUE), silent = TRUE)

cat(sprintf("\nTOTAL: %d pass / %d fail / %d skip\n", PASS, FAIL, SKIP))
cat(sprintf('{"test":"promote_crash_exit","pass":%d,"fail":%d,"skip":%d,"total":%d}\n',
            PASS, FAIL, SKIP, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
