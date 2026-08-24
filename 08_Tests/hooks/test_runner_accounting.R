# test_runner_accounting.R — 배터리 러너의 **계측 정확성** 시험
#
# 대상: 08_Tests/hooks/run_all_hooks.sh (suite 결과 계상 로직)
#
# 왜 이 시험이 본체인가:
#   러너는 **자기 자신을 재는 코드**다. 여기가 죽으면 아래 172개 suite 가 전부 초록이든
#   빨강이든 그 숫자를 믿을 수 없고, 더 나쁘게는 그 숫자가 **해석 가능해 보인다**.
#   2026-08-24 실측이 정확히 그것이었다:
#     · exit code 를 `$( cmd | filter )` 파이프에서 잃고 다음 줄이 $? 를 덮어써,
#       요약 JSON 을 못 낸 26개 suite 중 **25개가 exit 1 로 실패를 신고하는데 러너가
#       그걸 한 번도 보지 않았다**.
#     · 미보고를 일괄 `TOTAL_FAIL+=1` 로 뭉개, 8건 실패한 suite 도 1건으로 계상됐다
#       (= 과소계상). 동시에 미측정 26 + 실제 실패 10 = 36 이 한 숫자가 되어
#       **신규 실패가 상시 카운트와 구분되지 않았다**.
#   ⇒ 통과만 확인하는 검증은 이 결함의 재판이다. 양방향으로 잰다:
#     [정상]  요약을 제대로 낸 suite 의 pass/fail 이 **정확히** 합산되는지
#     [위반]  요약 없이 exit≠0 / exit=0 두 경우가 **서로 다른 버킷**으로 가는지
#     [원버그] 전 suite 미보고 시 FINAL 0/0/0 이 "ALL PASS" 로 나오지 않는지
#     [돌연변이] 수리를 되돌리면 위 판별이 **실제로 뒤집히는지** — 안 뒤집히면 축이 무의미
#
# 방법 — 샌드박스 사본:
#   러너의 앵커 해석은 self-first(`$_SELF_DIR/../..` 우선, run_all_hooks.sh 자신이 표지)라
#   사본을 `<tmp>/08_Tests/hooks/run_all_hooks.sh` 에 두면 PROJ_DIR 이 샌드박스로 잡힌다.
#   ⇒ 생산 트리를 건드리지 않고, 결과 JSON 도 `<tmp>/.cache/` 에 떨어진다.
#   사본은 **SUITES 배열만** 픽스처로 갈아끼운다. 계상 코드는 원본 그대로여야 하므로
#   축 (G) 가 그 사실을 직접 단언한다 — 사본을 잰 초록이 원본의 초록이 아니면 무의미하다.

suppressPackageStartupMessages(library(jsonlite))

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
SKIPS <- list()
ok  <- function(axis, msg) { PASS <<- PASS + 1L; cat(sprintf("  [PASS] %-34s %s\n", axis, msg)) }
bad <- function(axis, msg) { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %-34s %s\n", axis, msg)) }
skip <- function(axis, reason, missing) {
  SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat(sprintf("  [SKIP] %-34s %s\n", axis, reason))
}

emit <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  j <- sprintf('{"test":"runner_accounting","pass":%d,"fail":%d,"total":%d,"skipped":%d',
               PASS, FAIL, PASS + FAIL, SKIP)
  if (SKIP > 0L) j <- paste0(j, ',"skips":', as.character(toJSON(SKIPS, auto_unbox = TRUE)))
  cat(paste0(j, "}\n"))
  quit(status = if (FAIL > 0L) 1L else 0L)
}

# ── 앵커: 이 파일이 실린 트리 ───────────────────────────────────────────────
# ★코드 루트는 데이터 루트가 아니다 — QM_ROOT 로 잡으면 worktree 에서 main 러너를 잰다
#   ([[feedback-code-root-is-not-data-root]]). 자기 위치에서 올라간다.
self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) normalizePath(dirname(f[1]), winslash = "/") else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(self)) normalizePath(file.path(self, "..", ".."), winslash = "/") else
        normalizePath(getwd(), winslash = "/")
RUNNER <- file.path(ROOT, "08_Tests", "hooks", "run_all_hooks.sh")

cat("=== runner accounting ===\n")
cat(sprintf("ROOT   : %s\n", ROOT))
cat(sprintf("RUNNER : %s\n\n", RUNNER))

if (!file.exists(RUNNER)) {
  skip("anchor", "러너를 이 트리에서 못 찾음", RUNNER); emit()
}
BASH <- Sys.which("bash")
if (!nzchar(BASH)) {
  skip("bash_available", "bash 미탐지 — 샌드박스 실행 불가", "bash"); emit()
}

RUNNER_SRC <- readLines(RUNNER, warn = FALSE, encoding = "UTF-8")

# ── 계상 코드 지문 — 사본이 원본과 같은 코드를 도는지 못박는 축 ─────────────
# 이 문자열들이 사본에 그대로 있어야 "사본을 쟀다"가 "원본을 쟀다"가 된다.
ACCOUNTING_ANCHORS <- c(
  'RAW=$(bash "$PROJ_DIR/$test_script" 2>&1); RC=$?',
  'OUT=$(printf \'%s\\n\' "$RAW" | _last_summary_json)',
  'if [[ "${RC:-1}" -ne 0 ]]; then',
  'TOTAL_UNMEASURED=$((TOTAL_UNMEASURED + 1))'
)

# ── 픽스처 ──────────────────────────────────────────────────────────────────
FX <- list(
  # (1) 요약 JSON 정상 발행 + exit 1 — 요약이 있으면 exit code 가 판정을 가로채면 안 된다
  good = list(file = "fx_good.sh", body = c(
    "#!/usr/bin/env bash",
    "echo 'some noise before the summary'",
    "echo '{\"test\":\"fx_good\",\"pass\":3,\"fail\":1,\"total\":4,\"skipped\":0}'",
    "exit 1")),
  # (2) 요약 없음 + exit 1 — 실패를 신고하고 있으나 러너가 종전엔 못 봤다
  ef = list(file = "fx_exit1_nosummary.sh", body = c(
    "#!/usr/bin/env bash",
    "echo '== t_summary: PASS=8 FAIL=2 =='",
    "exit 1")),
  # (3) 요약 없음 + exit 0 — 측정 안 됨. 통과가 **아니다**
  es = list(file = "fx_exit0_nosummary.sh", body = c(
    "#!/usr/bin/env bash",
    "echo '== t_summary: PASS=8 FAIL=0 =='",
    "exit 0"))
)

#' 샌드박스를 세우고 러너 사본을 돌린 뒤 결과 JSON 을 돌려준다.
#' @param which  FX 의 키 벡터 — SUITES 에 넣을 픽스처
#' @param mutate NULL 또는 "revert_rc" (돌연변이 통제용)
run_sandbox <- function(which, mutate = NULL) {
  sb <- normalizePath(tempfile("qv_runacct_"), winslash = "/", mustWork = FALSE)
  dir.create(file.path(sb, "08_Tests", "hooks"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(sb, "08_Tests", "fixtures"), recursive = TRUE, showWarnings = FALSE)

  rel <- character(0)
  for (k in which) {
    p <- file.path("08_Tests", "fixtures", FX[[k]]$file)
    writeLines(FX[[k]]$body, file.path(sb, p))
    rel <- c(rel, gsub("\\\\", "/", p))
  }

  src <- RUNNER_SRC
  i <- which(src == "SUITES=(")
  if (length(i) != 1L) return(list(err = sprintf("SUITES=( 앵커 %d회", length(i))))
  j <- i + which(src[(i + 1L):length(src)] == ")")[1]
  if (is.na(j)) return(list(err = "SUITES 닫는 괄호 없음"))
  src <- c(src[1:i], sprintf('  "%s"', rel), src[j:length(src)])

  if (identical(mutate, "revert_rc")) {
    # 수리 이전 형태로 되돌린다: 출력을 파이프에서 바로 필터로 넘겨 exit code 를 잃는다.
    src <- sub('^(\\s*)RAW=\\$\\((.*)\\); RC=\\$\\?$', '\\1OUT=$(\\2 | _last_summary_json)', src)
    src <- sub("^\\s*OUT=\\$\\(printf '%s\\\\n' \"\\$RAW\" \\| _last_summary_json\\)$",
               '  RAW=""', src)
  }

  cp <- file.path(sb, "08_Tests", "hooks", "run_all_hooks.sh")
  con <- file(cp, open = "wb"); writeLines(src, con, sep = "\n"); close(con)

  log <- tempfile("qv_runacct_log_")
  rc <- suppressWarnings(system2(BASH, c(cp), stdout = log, stderr = log))
  res <- file.path(sb, ".cache", "test_results", "hook_dryrun_results.json")
  out <- list(sb = sb, rc = rc, log = log, copy_src = src,
              json = if (file.exists(res)) tryCatch(fromJSON(res, simplifyVector = FALSE),
                                                    error = function(e) NULL) else NULL,
              text = if (file.exists(log)) paste(readLines(log, warn = FALSE), collapse = "\n") else "")
  out
}

as_chr <- function(x) if (is.null(x)) character(0) else vapply(x, as.character, character(1))
has_fx <- function(v, name) any(grepl(name, as_chr(v), fixed = TRUE))

# ── 축 G — 사본 충실성 (다른 모든 축의 전제) ────────────────────────────────
cat("── G. 사본 충실성 (조작 선행검증) ─────────────────────────────\n")
r_all <- run_sandbox(c("good", "ef", "es"))
if (!is.null(r_all$err)) {
  bad("G_copy_fidelity", r_all$err)
} else {
  miss <- ACCOUNTING_ANCHORS[!vapply(ACCOUNTING_ANCHORS,
                                     function(a) any(grepl(a, r_all$copy_src, fixed = TRUE)),
                                     logical(1))]
  if (length(miss) == 0L)
    ok("G_copy_fidelity", "계상 코드 4축이 사본에 원본 그대로 존재") else
    bad("G_copy_fidelity", sprintf("사본에서 소실: %s", paste(miss, collapse = " | ")))
}

if (is.null(r_all$json)) {
  bad("R1_results_json", sprintf("샌드박스가 결과 JSON 을 안 냄 (rc=%s). log 앞부분: %s",
                                 r_all$rc, substr(r_all$text, 1, 400)))
  emit()
}
J <- r_all$json

# ── 축 A — 양성 대조 ────────────────────────────────────────────────────────
cat("\n── A. 양성 대조 (요약 발행 suite) ─────────────────────────────\n")
if (identical(as.integer(J$total_pass), 3L) && identical(as.integer(J$total_fail), 2L))
  ok("A_positive_control",
     "fx_good pass=3 정확 합산 + fail=1, 여기에 미측정+failing 1건 = fail 2") else
  bad("A_positive_control", sprintf("total_pass=%s total_fail=%s (기대 3 / 2)",
                                    J$total_pass, J$total_fail))

if (has_fx(J$unmeasured_failing, "fx_good") || has_fx(J$unmeasured_silent, "fx_good"))
  bad("A_summary_beats_exit", "요약을 낸 suite 가 미측정 버킷에 들어갔다 — exit code 가 판정을 가로챘다") else
  ok("A_summary_beats_exit", "요약이 있으면 exit 1 이어도 파싱 결과로 계상된다")

# ── 축 B — 위반 주입 ① 요약 없음 + exit≠0 ──────────────────────────────────
cat("\n── B. 위반 주입 ① 요약 없음 + exit≠0 ──────────────────────────\n")
if (has_fx(J$unmeasured_failing, "fx_exit1_nosummary"))
  ok("B_exit1_to_failing", "unmeasured_failing 에 등재 — exit code 를 실제로 읽었다") else
  bad("B_exit1_to_failing", sprintf("unmeasured_failing=%s",
                                    paste(as_chr(J$unmeasured_failing), collapse = ",")))

if (has_fx(J$unmeasured_silent, "fx_exit1_nosummary"))
  bad("B_not_silent", "exit 1 인데 silent 버킷 — 실패 신고가 다시 삼켜졌다") else
  ok("B_not_silent", "silent 버킷에는 없다")

# ── 축 C — 위반 주입 ② 요약 없음 + exit=0 ──────────────────────────────────
cat("\n── C. 위반 주입 ② 요약 없음 + exit=0 ──────────────────────────\n")
if (has_fx(J$unmeasured_silent, "fx_exit0_nosummary") &&
    identical(as.integer(J$total_unmeasured), 1L))
  ok("C_exit0_to_unmeasured", "unmeasured_silent 1건 — 측정 안 됨이 실패와 분리됐다") else
  bad("C_exit0_to_unmeasured", sprintf("total_unmeasured=%s silent=%s", J$total_unmeasured,
                                       paste(as_chr(J$unmeasured_silent), collapse = ",")))

# ── 축 D — 미측정만 있어도 status 는 FAIL (안전성질) ────────────────────────
cat("\n── D. 미측정 단독 → status FAIL ───────────────────────────────\n")
r_es <- run_sandbox("es")
if (is.null(r_es$json)) {
  bad("D_status_fail", "샌드박스 결과 JSON 없음")
} else {
  Je <- r_es$json
  if (identical(as.integer(Je$total_fail), 0L) &&
      identical(as.integer(Je$total_unmeasured), 1L) &&
      identical(as.character(Je$status), "FAIL"))
    ok("D_status_fail", "단언 실패 0 · 미측정 1 → status FAIL (미측정은 통과가 아니다)") else
    bad("D_status_fail", sprintf("fail=%s unmeasured=%s status=%s (기대 0/1/FAIL)",
                                 Je$total_fail, Je$total_unmeasured, Je$status))
  if (!identical(as.integer(r_es$rc), 0L))
    ok("D_exit_nonzero", sprintf("종료코드 %s — 호출자가 !=0 로 감지 가능", r_es$rc)) else
    bad("D_exit_nonzero", "미측정이 있는데 종료코드 0")
}

# ── 축 E — 원 버그 재현 방어 (전 suite 미보고 → ALL PASS 금지) ─────────────
cat("\n── E. 원 버그(2026-07-25) 재현 방어 ───────────────────────────\n")
r_none <- run_sandbox(c("ef", "es"))
if (is.null(r_none$json)) {
  bad("E_no_false_allpass", "샌드박스 결과 JSON 없음")
} else {
  Jn <- r_none$json
  if (identical(as.integer(Jn$total_pass), 0L) && !identical(as.character(Jn$status), "PASS") &&
      !grepl("ALL PASS", r_none$text, fixed = TRUE))
    ok("E_no_false_allpass", "pass 0 · 요약 0건인데 ALL PASS 로 보고하지 않는다") else
    bad("E_no_false_allpass", sprintf("status=%s / FINAL 에 ALL PASS 출현=%s",
                                      Jn$status, grepl("ALL PASS", r_none$text, fixed = TRUE)))
}

# ── 축 F — 돌연변이 통제 (수리를 되돌리면 판별이 뒤집혀야 한다) ────────────
cat("\n── F. 돌연변이 통제 (RC 포착 되돌림) ──────────────────────────\n")
r_mut <- run_sandbox(c("good", "ef", "es"), mutate = "revert_rc")
if (is.null(r_mut$json)) {
  bad("F_mutation_flips", sprintf("돌연변이 사본이 결과 JSON 을 안 냄 (rc=%s)", r_mut$rc))
} else {
  Jm <- r_mut$json
  # 구판은 RC 를 전혀 세우지 않는다 → ${RC:-1} = 1 → exit 0 픽스처까지 failing 으로 오분류.
  flipped <- has_fx(Jm$unmeasured_failing, "fx_exit0_nosummary") &&
             !has_fx(Jm$unmeasured_silent, "fx_exit0_nosummary")
  if (flipped)
    ok("F_mutation_flips",
       "구판 복원 시 exit0 픽스처가 silent→failing 으로 오분류 — 축 C 가 실제로 수리를 재고 있다") else
    bad("F_mutation_flips",
        sprintf("구판에서도 판별이 그대로 — 축 C 는 수리를 재는 게 아니다. failing=%s silent=%s",
                paste(as_chr(Jm$unmeasured_failing), collapse = ","),
                paste(as_chr(Jm$unmeasured_silent), collapse = ",")))
}

# ── 축 H — 사전 스캔 제거: suite 는 회차당 1회만 실행된다 ──────────────────
cat("\n── H. 이중 실행 제거 ──────────────────────────────────────────\n")
n_run <- length(gregexpr("some noise before the summary", r_all$text, fixed = TRUE)[[1]])
if (!grepl("some noise before the summary", r_all$text, fixed = TRUE)) n_run <- 0L
if (identical(as.integer(n_run), 1L))
  ok("H_single_execution", "fx_good 출력이 로그에 1회 — 사전 스캔 이중 실행이 제거됐다") else
  bad("H_single_execution", sprintf("fx_good 출력이 %d회 — 1회여야 한다", n_run))

emit()
