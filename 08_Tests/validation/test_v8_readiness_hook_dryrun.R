#==============================================================================
# test_v8_readiness_hook_dryrun.R — readiness gate 의 hook_dryrun 체크 위반 주입 검사
#   (2026-07-26, T4)
#
# 대상: 02_Infrastructure/validation/v8_readiness_gate.R 의
#       check_hook_dryrun() / .hook_dryrun_find_results() / .hook_dryrun_verdict()
#
# 왜 있나 (원 결함):
#   러너(08_Tests/hooks/run_all_hooks.sh)는 2026-07-25 artifact-storage 이관으로
#   결과를 `.cache/test_results/hook_dryrun_results.json` 에 쓰는데, 게이트는 계속
#   `08_Tests/hooks/results.json` 을 읽었다. 그 파일은 이관 이후 **영구 부재** →
#   배터리가 157 pass / 0 fail 로 통과해도 게이트 판정은 그것과 **무관**했다
#   (no_write: WARN "검증 불충분" / run: FAIL "results.json 생성 실패").
#   즉 판정이 실측이 아니라 대리물에 붙어 있었다.
#
#   이 부류의 결함은 "고쳤다"는 사실만으로는 재발을 못 막는다. 러너가 산출 경로를
#   또 옮기면 게이트는 다시 같은 방식으로 눈이 먼다 — 그리고 그때 화면에 보이는 것은
#   에러가 아니라 그냥 WARN 한 줄이다. 그래서 E 축(배선 대조)이 이 파일의 핵심이다.
#
# 구조 5축:
#   A. 위반 주입 — 결손/손상/실패 산출을 주입해 실제로 FAIL 이 나는가 (조용한 통과 0)
#   B. 회귀     — 정상 산출을 오탐하지 않는가 + fallback 경로 + 우선순위
#   C. run 모드 — 러너가 산출을 못 냈거나 갱신하지 못한 경우를 잡는가 (존재=유효 함정)
#   D. 차단 실효 — 수리 전 구현으로 되돌리면 이 케이스 집합이 실제로 그것을 구분하는가
#                  (오탐 제거와 검사 사망은 겉보기가 같다 — 공허한 통과 방지)
#   E. 배선 대조 — 게이트가 읽는 정본 경로 == 러너가 실제로 쓰는 경로인가 (재발 감시)
#
# ★ 주입 대상은 전부 **임시 fixture 루트**다. 정본 저장소는 건드리지 않는다.
#   스크립트 최상위 on.exit() 은 발화하지 않으므로(r-portability 금칙 ②) 정리는
#   말미에서 명시 호출한다.
#
# 단독 실행: Rscript 08_Tests/validation/test_v8_readiness_hook_dryrun.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PASS <- 0L; FAIL <- 0L
ok  <- function(id, msg) { PASS <<- PASS + 1L; cat(sprintf("  ✅ %-28s %s\n", id, msg)) }
bad <- function(id, msg) { FAIL <<- FAIL + 1L; cat(sprintf("  ❌ %-28s %s\n", id, msg)) }

# ── 프로젝트 루트 해석: CLAUDE_PROJECT_DIR 우선 + 표지 검증 (r-portability 금칙 ③④)
.MARKER <- "02_Infrastructure/validation/v8_readiness_gate.R"
.pick_root <- function() {
  self <- tryCatch(normalizePath(sys.frame(1)$ofile, winslash = "/", mustWork = FALSE),
                   error = function(e) NA_character_)
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (!is.na(self) && nzchar(self)) file.path(dirname(self), "..", "..") else NULL,
             getwd())
  for (c in cands) {
    if (nzchar(c) && file.exists(file.path(c, .MARKER))) {
      return(normalizePath(c, winslash = "/", mustWork = FALSE))
    }
  }
  stop(sprintf("PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보 없음", .MARKER))
}
ROOT <- .pick_root()
GATE_SRC   <- file.path(ROOT, "02_Infrastructure/validation/v8_readiness_gate.R")
RUNNER_SRC <- file.path(ROOT, "08_Tests/hooks/run_all_hooks.sh")

cat("=== v8_readiness_gate :: check_hook_dryrun 위반 주입 검사 ===\n")
cat(sprintf("ROOT: %s\n\n", ROOT))

source(GATE_SRC)

# ── fixture 헬퍼 ─────────────────────────────────────────────────────────────
FIX_ROOT <- file.path(tempdir(), sprintf("t4_fix_%s", format(Sys.time(), "%H%M%S")))
dir.create(FIX_ROOT, recursive = TRUE, showWarnings = FALSE)
.fix_n <- 0L

# rels: named list(경로 -> 내용). NULL 내용 = 파일 생성 안 함.
# runner_body: 가짜 run_all_hooks.sh 본문 (기본 = 아무것도 안 하는 스텁)
new_fixture <- function(results_json = NULL, results_rel = ".cache/test_results/hook_dryrun_results.json",
                        runner_body = "#!/usr/bin/env bash\nexit 0\n",
                        extra = list()) {
  .fix_n <<- .fix_n + 1L
  d <- file.path(FIX_ROOT, sprintf("case%02d", .fix_n))
  dir.create(file.path(d, "08_Tests/hooks"), recursive = TRUE, showWarnings = FALSE)
  if (!is.null(runner_body)) writeLines(runner_body, file.path(d, "08_Tests/hooks/run_all_hooks.sh"))
  if (!is.null(results_json)) {
    p <- file.path(d, results_rel)
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines(results_json, p)
  }
  for (rel in names(extra)) {
    p <- file.path(d, rel)
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines(extra[[rel]], p)
  }
  d
}

good_json <- function(pass = 157, fail = 0, n_suites = 10, status = "PASS") {
  tests <- paste(sprintf('{"test":"s%d","pass":%d,"fail":0,"total":%d}',
                         seq_len(max(n_suites, 0)), 1, 1), collapse = ",")
  sprintf('{"suite":"qvest_v6_4_hook_dryrun","ran_at":"2026-07-26T18:00:00+09:00","total_pass":%d,"total_fail":%d,"total":%d,"status":"%s","tests":[%s]}',
          pass, fail, pass + fail, status, tests)
}

# 판정 헬퍼: 기대 status 와 실제 대조
expect <- function(id, chk, want, note = "") {
  got <- chk$status
  if (identical(got, want)) {
    ok(id, sprintf("%s — %s", got, if (nzchar(note)) note else substr(chk$details, 1, 90)))
  } else {
    bad(id, sprintf("기대 %s 인데 %s — %s", want, got, substr(chk$details, 1, 110)))
  }
}

#──────────────────────────────────────────────────────────────────────────────
cat("── A. 위반 주입 (no_write) — 결손/손상/실패가 실제로 FAIL 을 내는가\n")
#──────────────────────────────────────────────────────────────────────────────

# A1. 결과 파일이 두 경로 모두 부재 = 미검증. 미검증은 통과가 아니다.
#     (이것이 원 결함의 정확한 형태였다 — 구현은 여기서 WARN 을 냈다)
d <- new_fixture(results_json = NULL)
expect("A1_absent_both_paths", check_hook_dryrun(d, no_write = TRUE), "FAIL",
       "두 경로 모두 부재 → 명시 FAIL")

# A2. 실패 건이 있는 산출
d <- new_fixture(good_json(pass = 150, fail = 7, status = "FAIL"))
expect("A2_total_fail_nonzero", check_hook_dryrun(d, no_write = TRUE), "FAIL",
       "total_fail=7")

# A3. total_pass=0 / total_fail=0 = 계측 사망 (러너 UNREPORTED 가드와 이중 방어).
#     ★이 케이스가 이 파일에서 가장 중요하다: "총계 0"은 "실패 0"과 겉보기가 같다.
d <- new_fixture(good_json(pass = 0, fail = 0, n_suites = 0))
expect("A3_zero_pass_zero_fail", check_hook_dryrun(d, no_write = TRUE), "FAIL",
       "0 pass / 0 fail = 계측 사망")

# A4. 총계는 살아 있는데 tests[] 가 비었다 = 스위트 0건 실행 (집계만 남은 산출)
d <- new_fixture(good_json(pass = 12, fail = 0, n_suites = 0))
expect("A4_empty_tests_array", check_hook_dryrun(d, no_write = TRUE), "FAIL",
       "tests[] 0건")

# A5. total_pass/total_fail 필드 부재 (러너 스키마 개명 = 침묵 결손 경로)
d <- new_fixture('{"suite":"x","passed":157,"failed":0,"tests":[{"test":"a"}]}')
expect("A5_missing_total_fields", check_hook_dryrun(d, no_write = TRUE), "FAIL",
       "필드 개명 → 0 폴백 금지")

# A6. JSON 파손 (러너가 중간에 죽어 잘린 산출)
d <- new_fixture('{"suite":"x","total_pass":157,"total_fail":0,"tests":[{"tes')
expect("A6_corrupt_json", check_hook_dryrun(d, no_write = TRUE), "FAIL",
       "parse 실패")

# A7. status 필드가 총계와 모순 (수기 편집/산출 손상)
d <- new_fixture(good_json(pass = 157, fail = 0, status = "FAIL"))
expect("A7_status_field_mismatch", check_hook_dryrun(d, no_write = TRUE), "FAIL",
       "status='FAIL' 인데 total_fail=0")

# A8. 캐시가 낡음 = "현재 상태의 증거"가 아니다 → PASS 아님(WARN)
d <- new_fixture(good_json())
stale <- file.path(d, ".cache/test_results/hook_dryrun_results.json")
Sys.setFileTime(stale, Sys.time() - (HOOK_DRYRUN_MAX_AGE_DAYS + 1) * 86400)
expect("A8_stale_cache", check_hook_dryrun(d, no_write = TRUE), "WARN",
       sprintf(">%d일 경과", HOOK_DRYRUN_MAX_AGE_DAYS))

# A9. 러너 자체가 부재 (배터리 소실)
d <- new_fixture(good_json(), runner_body = NULL)
expect("A9_runner_absent", check_hook_dryrun(d, no_write = TRUE), "FAIL",
       "run_all_hooks.sh 부재")

#──────────────────────────────────────────────────────────────────────────────
cat("\n── B. 회귀 — 정상 산출을 오탐하지 않는가 (검사 사망 방지의 반대편)\n")
#──────────────────────────────────────────────────────────────────────────────

# B1. 현행 정본 경로의 정상 산출 → PASS. (수리 전 구현은 여기서 WARN 을 냈다 — D1 참조)
d <- new_fixture(good_json())
chk <- check_hook_dryrun(d, no_write = TRUE)
expect("B1_current_path_ok", chk, "PASS")
if (grepl(".cache/test_results", chk$details, fixed = TRUE)) {
  ok("B1b_path_label", "details 에 실제 소비 경로가 찍힌다 (판정 출처 추적 가능)")
} else {
  bad("B1b_path_label", sprintf("소비 경로 라벨 부재: %s", substr(chk$details, 1, 80)))
}

# B2. 구 경로만 존재 (외부 CI / 구 체크아웃) → fallback 으로 PASS
d <- new_fixture(good_json(), results_rel = "08_Tests/hooks/results.json")
chk <- check_hook_dryrun(d, no_write = TRUE)
expect("B2_legacy_path_fallback", chk, "PASS")

# B3. 두 경로 동시 존재 → 정본(.cache) 우선. 구 경로에 낡은 성공이 남아 있어도
#     현행 산출이 판정 근거여야 한다.
d <- new_fixture(good_json(pass = 157, fail = 0))
p_old <- file.path(d, "08_Tests/hooks/results.json")
dir.create(dirname(p_old), recursive = TRUE, showWarnings = FALSE)
writeLines(good_json(pass = 17, fail = 0, n_suites = 3), p_old)
chk <- check_hook_dryrun(d, no_write = TRUE)
if (chk$status == "PASS" && grepl("157 pass", chk$details, fixed = TRUE)) {
  ok("B3_precedence_current_first", "정본 우선 (157 pass 채택, 구 경로 17 무시)")
} else {
  bad("B3_precedence_current_first", sprintf("%s — %s", chk$status, substr(chk$details, 1, 90)))
}

# B4. 총계가 구 하드코딩 문턱(17) 미만인 정상 배터리 → PASS 여야 한다.
#     문턱을 게이트에 박으면 스위트가 줄거나 분할될 때 정상을 실패로 오탐한다.
#     (총계 래칫의 책임자는 suite_totals_watch.sh — E3 에서 배선 확인)
d <- new_fixture(good_json(pass = 9, fail = 0, n_suites = 2))
expect("B4_no_hardcoded_threshold", check_hook_dryrun(d, no_write = TRUE), "PASS",
       "9 pass 도 실패 0 이면 PASS (문턱 제거 실효)")

#──────────────────────────────────────────────────────────────────────────────
cat("\n── C. run 모드 — 러너를 돌린 뒤 '이번 실행이 갱신한 산출'만 근거인가\n")
#──────────────────────────────────────────────────────────────────────────────

# C1. 러너가 결과 파일을 아예 못 만듦
d <- new_fixture(results_json = NULL,
                 runner_body = "#!/usr/bin/env bash\necho 'boom' >&2\nexit 1\n")
expect("C1_runner_no_output", check_hook_dryrun(d, no_write = FALSE), "FAIL",
       "산출 생성 실패")

# C2. ★존재=유효 함정: 러너는 죽었는데 구 산출이 남아 있다.
#     파일이 "있다"는 것은 "이번에 통과했다"를 뜻하지 않는다 → mtime 대조로 FAIL.
d <- new_fixture(good_json(),
                 runner_body = "#!/usr/bin/env bash\nexit 1\n")
old_p <- file.path(d, ".cache/test_results/hook_dryrun_results.json")
Sys.setFileTime(old_p, Sys.time() - 3600)
expect("C2_stale_output_reuse", check_hook_dryrun(d, no_write = FALSE), "FAIL",
       "구 산출 재사용 차단 (mtime < 실행시작)")

# C3. 러너가 정상적으로 새 산출을 씀 → PASS
body <- paste0(
  "#!/usr/bin/env bash\n",
  "mkdir -p .cache/test_results\n",
  "cat > .cache/test_results/hook_dryrun_results.json <<'EOF'\n",
  good_json(pass = 42, fail = 0, n_suites = 4), "\n",
  "EOF\n", "exit 0\n")
d <- new_fixture(results_json = NULL, runner_body = body)
chk <- check_hook_dryrun(d, no_write = FALSE)
if (chk$status == "PASS" && grepl("42 pass", chk$details, fixed = TRUE)) {
  ok("C3_runner_fresh_output", "러너 실산출 42 pass 를 그대로 판정 근거로 채택")
} else {
  bad("C3_runner_fresh_output", sprintf("%s — %s", chk$status, substr(chk$details, 1, 110)))
}

#──────────────────────────────────────────────────────────────────────────────
cat("\n── D. 차단 실효 — 수리 전 구현으로 되돌리면 위 케이스가 그것을 구분하는가\n")
#──────────────────────────────────────────────────────────────────────────────
# 오탐 제거와 검사 사망은 겉보기가 같다. 그래서 "고친 검사가 통과한다"만으로는
# 부족하고, **되돌리면 실제로 다르게 나온다**는 것을 같은 케이스로 보여야 한다.

# 수리 전 구현 재현 (feed229f^ 원문의 no_write 분기)
legacy_check <- function(project_root, no_write = TRUE) {
  results_path <- file.path(project_root, "08_Tests/hooks/results.json")
  hook_runner <- file.path(project_root, "08_Tests/hooks/run_all_hooks.sh")
  if (!file.exists(hook_runner)) {
    return(mk_check("hook_dryrun", "Hook dry-run 17/17", "FAIL", "run_all_hooks.sh 부재"))
  }
  if (file.exists(results_path)) {
    data <- tryCatch(fromJSON(results_path, simplifyVector = TRUE), error = function(e) NULL)
    if (!is.null(data) && is.numeric(data$total_fail) &&
        data$total_fail == 0 && (data$total_pass %||% 0) >= 17) {
      return(mk_check("hook_dryrun", "Hook dry-run 17/17", "PASS", "cached"))
    }
  }
  mk_check("hook_dryrun", "Hook dry-run 17/17", "WARN",
           "no_write — runner skip + cached results 검증 불충분")
}

# D1. 원 결함 재현: 현행 정본 경로에 정상 산출이 있는데 구 구현은 못 본다.
d <- new_fixture(good_json())
lg <- legacy_check(d); cur <- check_hook_dryrun(d, no_write = TRUE)
if (lg$status == "WARN" && cur$status == "PASS") {
  ok("D1_repair_is_discriminated", "구 구현 WARN vs 현행 PASS — B1 이 수리를 실제로 구분")
} else {
  bad("D1_repair_is_discriminated",
      sprintf("구=%s 현행=%s (같으면 B1 은 공허한 통과)", lg$status, cur$status))
}

# D2. 문턱 회귀: 9 pass 정상 배터리에서 구 구현은 WARN(거짓 경보), 현행은 PASS.
d <- new_fixture(good_json(pass = 9, fail = 0, n_suites = 2),
                 results_rel = "08_Tests/hooks/results.json")
lg <- legacy_check(d); cur <- check_hook_dryrun(d, no_write = TRUE)
if (lg$status == "WARN" && cur$status == "PASS") {
  ok("D2_threshold_removal_matters", "구 문턱(>=17) 은 9 pass 정상을 오탐 — B4 가 그것을 구분")
} else {
  bad("D2_threshold_removal_matters", sprintf("구=%s 현행=%s", lg$status, cur$status))
}

# D3. 조용한 통과 회귀: 파일 부재 시 WARN 으로 접는 구현에서는 A1 이 발화하지 않는다.
d <- new_fixture(results_json = NULL)
lg <- legacy_check(d); cur <- check_hook_dryrun(d, no_write = TRUE)
if (lg$status != "FAIL" && cur$status == "FAIL") {
  ok("D3_silent_pass_regression", sprintf("구 구현 %s(미검증을 통과로 접음) vs 현행 FAIL", lg$status))
} else {
  bad("D3_silent_pass_regression", sprintf("구=%s 현행=%s", lg$status, cur$status))
}

#──────────────────────────────────────────────────────────────────────────────
cat("\n── E. 배선 대조 — 게이트가 읽는 경로 == 러너가 쓰는 경로 (원 결함 재발 감시)\n")
#──────────────────────────────────────────────────────────────────────────────

if (!file.exists(RUNNER_SRC)) {
  bad("E1_runner_path_parse", sprintf("%s 부재", RUNNER_SRC))
  bad("E2_gate_reads_runner_path", "러너 부재로 대조 불가")
} else {
  rtxt <- readLines(RUNNER_SRC, warn = FALSE)
  rcode <- rtxt[!grepl("^\\s*#", rtxt)]
  # RESULTS_DIR="$PROJ_DIR/.cache/test_results" / RESULTS_FILE="$RESULTS_DIR/xxx.json"
  dir_line  <- grep('^\\s*RESULTS_DIR=', rcode, value = TRUE)
  file_line <- grep('^\\s*RESULTS_FILE=', rcode, value = TRUE)
  if (length(dir_line) == 0 || length(file_line) == 0) {
    bad("E1_runner_path_parse",
        "러너에서 RESULTS_DIR/RESULTS_FILE 대입을 못 찾음 — 산출 경로 표현이 바뀌었다(대조 불가 = 감시 사망)")
    bad("E2_gate_reads_runner_path", "경로 파싱 실패로 대조 불가")
  } else {
    rdir  <- sub('.*RESULTS_DIR="?\\$PROJ_DIR/([^"]*)"?.*', '\\1', tail(dir_line, 1))
    rfile <- sub('.*RESULTS_FILE="?\\$RESULTS_DIR/([^"]*)"?.*', '\\1', tail(file_line, 1))
    runner_rel <- file.path(rdir, rfile)
    ok("E1_runner_path_parse", sprintf("러너 산출 경로 = %s", runner_rel))
    if (identical(runner_rel, HOOK_DRYRUN_RESULT_RELS[1])) {
      ok("E2_gate_reads_runner_path",
         sprintf("게이트 정본 경로와 일치 (%s)", HOOK_DRYRUN_RESULT_RELS[1]))
    } else {
      bad("E2_gate_reads_runner_path",
          sprintf("★배선 드리프트: 러너='%s' vs 게이트 정본='%s' — 게이트가 배터리 실측을 못 본다",
                  runner_rel, HOOK_DRYRUN_RESULT_RELS[1]))
    }
  }
}

# E3. 총계 래칫의 책임자가 실재하는가 — 게이트에서 문턱을 뺀 근거가 배선으로 살아 있어야 한다.
watch <- file.path(ROOT, "02_Infrastructure/ops/suite_totals_watch.sh")
base  <- file.path(ROOT, "06_Registry/suite_totals_baseline.json")
if (file.exists(watch) && file.exists(base)) {
  bj <- tryCatch(fromJSON(base, simplifyVector = TRUE), error = function(e) NULL)
  if (!is.null(bj) && !is.null(bj$hooks) && is.numeric(bj$hooks) && bj$hooks > 0) {
    ok("E3_ratchet_owner_alive",
       sprintf("suite_totals_watch + baseline(hooks=%s) 실재 — 총계 감소 감시는 그쪽 책임", bj$hooks))
  } else {
    bad("E3_ratchet_owner_alive", "baseline 에 hooks 총계가 없다 — 게이트에서 문턱을 뺀 근거가 비어 있음")
  }
} else {
  bad("E3_ratchet_owner_alive",
      sprintf("래칫 배선 부재 (watch=%s base=%s)", file.exists(watch), file.exists(base)))
}

#──────────────────────────────────────────────────────────────────────────────
# 정리 (최상위 on.exit 은 발화하지 않는다 — 명시 호출)
unlink(FIX_ROOT, recursive = TRUE, force = TRUE)

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "v8_readiness_hook_dryrun", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
