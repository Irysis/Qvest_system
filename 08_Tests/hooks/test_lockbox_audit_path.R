# ★RETIRED (v10 2026-08-29): lockbox 제도 폐지 — 이 검사의 대상(경로 리터럴 동조)이 소멸.
#   run_all_hooks.sh 배선 제거됨. 파일은 사료 존치. 재열람 = git pre-v10-2layer.
#==============================================================================
# test_lockbox_audit_path.R — P2 Data Separation 감사의 **차단 실효** 검사
# 2026-08-02 신설
#
# ─── 왜 이 검사기가 필요한가 ────────────────────────────────────────────────
# `v61_compliance_audit.R` 의 P2 는 2026-08-02 실측 시점까지 **구조적으로 실패할 수
# 없었다**. 기전:
#   - 기록자 = bash 훅(`lockbox_audit_trail.sh`) → MSYS `/tmp` = AppData\Local\Temp
#   - 감사자 = Windows R                          → 같은 리터럴을 `C:/tmp` 로 해석
#   → 접근기록 4건이 감사자가 안 보는 디렉토리에 쌓였고, `!file.exists()` 가 항상 참이라
#     237/237 WT 가 `pass=TRUE, "no_lockbox_access (clean)"`. **PASS 에 정보가 0이었다.**
#
# 그래서 이 검사기의 축은 "경로 문자열이 같은가"가 아니라 **"P2 가 실제로 FAIL 을 낼 수
# 있는가"** 다. 위반을 주입해 FAIL 이 나오는 것까지 봐야 한다 —
# 오탐 제거와 검사 사망은 겉보기가 같다(r-portability.md 강제 절).
#
# ─── 돌연변이 축 ────────────────────────────────────────────────────────────
# 같은 주입 상태에서 **구판 로직 재현본**이 PASS 로 뒤집히는지 확인한다. 안 뒤집히면
# 이 suite 의 초록은 계측 사망이다(주입이 애초에 무해했다는 뜻).
#
# 격리: 임시 fake root(marker 포함)를 만들고 CLAUDE_PROJECT_DIR 로 가리킨다.
#       실제 훅 코드·실제 감사 코드를 그대로 돌리되, 쓰기는 전부 임시 트리로 간다.
#       (bash 훅과 R 감사가 **같은 루트 해석에 도달하는지**가 결함의 핵심이므로,
#        루트 해석 자체를 우회하는 stub 테스트는 이 결함을 못 본다.)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  [PASS] %-32s %s\n", n, m)) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %-32s %s\n", n, m)) }

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── 리포지토리 루트 ────────────────────────────────────────────────────────
# ★검사기의 앵커 1순위는 **자기 파일 위치**다(env 가 아니라).
#   근거(2026-08-02 실측): Bash 툴 실행에는 CLAUDE_PROJECT_DIR 이 없고 QM_ROOT 는 main 에
#   핀돼 있다. env-우선으로 해석하면 worktree 에서 돌린 검사기가 **조용히 main 의 소스를
#   검사**한다 — 수리가 worktree 에 있는 동안 "초록"이 나오고 그 초록이 거짓이 된다.
#   (같은 함정 선례: run_all_hooks.sh 가 worktree 에서 main 의 suite 를 검사)
#   그래서 여기서는 CLAUDE_PROJECT_DIR / QM_ROOT 보다 self 를 먼저 본다. 일반 모듈의
#   표준 계열(금칙 ④, CPD-first)과 다른 이유가 이것이며, 그 차이가 의도적임을 명시한다.
find_repo_root <- function() {
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  norm <- function(p) normalizePath(gsub("\\\\", "/", p), winslash = "/", mustWork = FALSE)

  # tier 0: 자기 파일 위치 (08_Tests/hooks/ → 2단계 위가 루트)
  ca <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", ca, value = TRUE)
  if (length(fa)) {
    self <- norm(sub("^--file=", "", fa[1]))
    cand <- dirname(dirname(dirname(self)))
    if (file.exists(file.path(cand, marker))) return(cand)
  }
  # tier 1~2: env (marker 게이트 통과분만)
  for (cand in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                 Sys.getenv("QM_ROOT", unset = ""))) {
    if (!nzchar(cand)) next
    p <- norm(cand)
    if (file.exists(file.path(p, marker))) return(p)
  }
  # tier 3: cwd 상향 탐색
  here <- norm(getwd())
  repeat {
    if (file.exists(file.path(here, marker))) return(here)
    parent <- dirname(here); if (identical(parent, here)) break; here <- parent
  }
  stop("[test_lockbox_audit_path] repo root 미발견")
}
REPO <- find_repo_root()
cat(sprintf("=== test_lockbox_audit_path.R (repo=%s) ===\n", REPO))

PATHS_R  <- file.path(REPO, "02_Infrastructure/worktask/lockbox_paths.R")
PATHS_SH <- file.path(REPO, "02_Infrastructure/hooks/lockbox_paths.sh")
AUDIT_R  <- file.path(REPO, "02_Infrastructure/worktask/v61_compliance_audit.R")
HOOK_SH  <- file.path(REPO, "02_Infrastructure/hooks/lockbox_audit_trail.sh")

#=============================================================================
# 축 1 — 교차언어 리터럴 동기화
#   두 곳에서 같은 값을 만들면서 정합 검사를 안 만든 것이 이 계통의 재발 기전이다.
#=============================================================================
subdir_from_sh <- local({
  L <- readLines(PATHS_SH, warn = FALSE)
  hit <- grep('^QVEST_LOCKBOX_SUBDIR=', L, value = TRUE)
  if (!length(hit)) NA_character_ else gsub('^QVEST_LOCKBOX_SUBDIR="?([^"]*)"?.*$', "\\1", hit[1])
})
source(PATHS_R)
if (!is.na(subdir_from_sh) && identical(subdir_from_sh, QVEST_LOCKBOX_SUBDIR)) {
  ok("subdir_literal_sync", sprintf("R == sh == '%s'", QVEST_LOCKBOX_SUBDIR))
} else {
  bad("subdir_literal_sync",
      sprintf("R='%s' vs sh='%s' — 교차언어 경로 계약 드리프트",
              QVEST_LOCKBOX_SUBDIR, subdir_from_sh %||% "NA"))
}

#=============================================================================
# 축 2 — 구 리터럴 회귀 방지
#   수리 대상 4파일에 `qvest_lockbox_access` 를 담은 선행 `/` tmp 경로가 남아 있으면 회귀.
#   (검출 문자열 자체를 소스에 박으면 이 파일이 r_portability 금칙 ③ 에 걸리므로 조립한다)
#=============================================================================
legacy_tok <- paste0("\"", "/", "tmp/qvest_lockbox_access")
regressed <- character(0)
for (f in c(PATHS_R, PATHS_SH, AUDIT_R, HOOK_SH,
            file.path(REPO, "02_Infrastructure/worktask/windowing.R"),
            file.path(REPO, "02_Infrastructure/validation/judge_oos_helper.R"))) {
  if (!file.exists(f)) next
  if (any(grepl(legacy_tok, readLines(f, warn = FALSE), fixed = TRUE))) {
    regressed <- c(regressed, basename(f))
  }
}
if (length(regressed) == 0) {
  ok("no_legacy_tmp_literal", "수리 6파일에 구 /tmp 리터럴 0건")
} else {
  bad("no_legacy_tmp_literal", paste(regressed, collapse = ", "))
}

#=============================================================================
# fake root 구성 (격리)
#=============================================================================
FAKE <- normalizePath(tempfile("qvest_lbtest_"), winslash = "/", mustWork = FALSE)
WT   <- "WT-D29990101_001"
dir.create(file.path(FAKE, "02_Infrastructure/hooks"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(FAKE, "02_Infrastructure/worktask"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(FAKE, "qepm/mailbox/worktask", WT), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(FAKE, "qepm/mailbox/governor"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(FAKE, "qepm/mailbox/monitoring/reports"), recursive = TRUE, showWarnings = FALSE)
# marker (정체성 검사 대상) + 감사가 source 하는 경로 계약 파일
invisible(file.create(file.path(FAKE, "02_Infrastructure/hooks/qvest_hook_router.py")))
file.copy(PATHS_R, file.path(FAKE, "02_Infrastructure/worktask/lockbox_paths.R"), overwrite = TRUE)

cleanup <- function() unlink(FAKE, recursive = TRUE, force = TRUE)
# ★함수 프레임이 아닌 최상위이므로 on.exit 은 no-op 이다 (r-portability 금칙 ②)
invisible(reg.finalizer(globalenv(), function(e) cleanup(), onexit = TRUE))

# 실제 감사 코드를 fake root 로 해석시켜 로드
old_cpd <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = NA)
Sys.setenv(CLAUDE_PROJECT_DIR = FAKE)
suppressMessages(source(AUDIT_R))
if (identical(normalizePath(V61_ROOT, winslash = "/", mustWork = FALSE),
              normalizePath(FAKE, winslash = "/", mustWork = FALSE))) {
  ok("audit_resolves_to_fake_root", V61_ROOT)
} else {
  bad("audit_resolves_to_fake_root", sprintf("V61_ROOT=%s (기대 %s)", V61_ROOT, FAKE))
}

#=============================================================================
# 축 3 — 미측정 ≠ 통과
#   heartbeat 없음(트레일 발화 기록 0) 상태에서 P2 가 TRUE 면 구 결함 그대로다.
#=============================================================================
r0 <- audit_p2_data_separation(WT)
if (is.na(r0$pass)) {
  ok("unmeasured_is_not_pass", r0$reason)
} else {
  bad("unmeasured_is_not_pass",
      sprintf("pass=%s (기대 NA) — '기록 없음'을 '위반 없음'으로 내려앉힘", r0$pass))
}

#=============================================================================
# 축 4 — bash 훅이 쓴 곳을 R 감사가 읽는가 (교차언어 도달성 = 결함의 핵심)
#   실제 훅을 그대로 실행한다. 루트 해석은 CLAUDE_PROJECT_DIR(=FAKE) 경유.
#=============================================================================
lockbox_file <- sprintf("stage_artifacts/%s/lockbox/holdout.csv", WT)

# ★agent 귀속 marker 는 훅과 **같은 bash 런타임의** 임시 디렉토리에 있어야 한다.
#   2026-08-02 실측 — 이 환경에서 `/tmp` 는 **세 갈래**다:
#       Git Bash (settings.json 이 훅을 띄우는 셸) → C:/Users/<u>/AppData/Local/Temp
#       Rtools bash (R 이 system2 로 띄우는 셸)    → C:/rtools45/tmp
#       Windows R                                   → C:/tmp
#   R 의 TEMP 를 넘기면 Rtools bash 가 보는 /tmp 와 어긋나 marker 를 못 찾고,
#   훅은 agent="unknown" 으로 기록한다 → **주입이 무해해져 축 5 가 거짓 빨강**이 된다.
#   그래서 디렉토리를 넘기지 않고 드라이버가 자기 런타임에서 알아낸다.
#   (원 결함이 2갈래 분기였는데 실제로는 3갈래였다 — 계약을 프로젝트-상대로 옮긴 이유가 강화된다)

# bash 훅 1회 실행. agent 귀속 marker 를 같은 bash 계층에서 심는다
# ($PPID = 바깥 bash 의 $$ — ops/hook_e2e_battery.py:76 이 쓰는 검증된 idiom).
# ★드라이버를 `bash -c '<script>'` 로 넘기지 않고 **파일**로 넘긴다.
#   Windows R 의 system2 는 인자를 명령줄 문자열로 재조립하므로, 따옴표가 박힌 -c 스크립트가
#   전달 과정에서 깨진다 — 실측: rc=0 인데 아무것도 실행되지 않아 "훅이 안 쓴다"로 오독됐다.
#   (금칙 ⑤ 와 같은 부류 — 셸 문법을 argv 로 밀어 넣으면 조용히 다른 것이 실행된다)
run_hook <- function(agent) {
  payload <- tempfile(fileext = ".json")
  write_json(list(tool_name = "Read", tool_input = list(file_path = lockbox_file)),
             payload, auto_unbox = TRUE)
  driver <- tempfile(fileext = ".sh")
  # ★반드시 binary 연결 — Windows R 의 text 연결은 \n 을 \r\n 으로 바꾼다.
  #   실측: CRLF 로 쓰면 bash 가 `M="$1"` 뒤의 CR 까지 값에 넣어 marker 파일명이 어긋나고,
  #   훅은 marker 를 못 찾아 agent="unknown" 으로 기록한다 → 위반 주입이 무해해진다.
  #   (구 P2 와 같은 형태의 침묵 실패 — 주입이 안 먹은 걸 "위반 없음"으로 읽게 만든다)
  con <- file(driver, open = "wb")
  writeLines(c(
    'A="$1"; H="$2"; P="$3"',
    'M=$(dirname "$(mktemp -u)")          # 이 bash 런타임이 부르는 임시 디렉토리',
    'echo "$A" > "$M/qvest_current_agent_$$"',
    'bash "$H" < "$P"; rc=$?',
    'rm -f "$M/qvest_current_agent_$$"',
    'exit $rc'
  ), con, sep = "\n")
  close(con)
  out <- suppressWarnings(system2("bash", c(driver, agent, HOOK_SH, payload),
                                  stdout = TRUE, stderr = TRUE))
  unlink(c(payload, driver))
  st <- attr(out, "status"); if (is.null(st)) 0L else as.integer(st)
}

hook_rc <- run_hook("alpha-research")
log_path <- qvest_lockbox_log(WT, root = FAKE)
if (file.exists(log_path)) {
  ok("bash_writes_where_r_reads",
     sprintf("%s (%d행, hook rc=%d)", basename(log_path), length(readLines(log_path, warn = FALSE)), hook_rc))
} else {
  bad("bash_writes_where_r_reads",
      sprintf("훅 실행 후에도 감사자 경로에 파일 없음: %s (hook rc=%d)", log_path, hook_rc))
}

#=============================================================================
# 축 5 — 위반 주입 → P2 가 실제로 FAIL 을 내는가 (본 검사기의 존재 이유)
#   alpha-research(정규 리서치 단계)의 lockbox 접근 = lockbox-scope mandate 위반.
#=============================================================================
r1 <- audit_p2_data_separation(WT)
if (isTRUE(r1$pass) || is.na(r1$pass)) {
  # 실패 시 실제 기록을 같이 뱉는다 — "주입이 안 먹었다"와 "감사가 못 잡았다"는 원인이 다르고,
  # 그 둘을 구별 못 하면 이 검사기 자체가 정보 없는 빨강이 된다.
  actual <- if (file.exists(log_path)) paste(readLines(log_path, warn = FALSE), collapse = " / ") else "(로그 없음)"
  bad("violation_injection_fails",
      sprintf("주입했는데 pass=%s (%s) | 기록=%s", r1$pass, r1$reason, actual))
} else {
  ok("violation_injection_fails", r1$reason)
}

#=============================================================================
# 축 6 — 돌연변이(구판 로직 재현본)는 같은 주입에서 PASS 로 뒤집히는가
#   구판의 정의적 성질 = ① 기록자가 쓰지 않는 디렉토리를 읽고 ② 부재를 clean 으로 본다.
#   ①의 디렉토리 = Windows R 이 선행 `/` 를 해석하던 그 자리(legacy dirs 첫 후보).
#   안 뒤집히면 주입이 애초에 무해했다는 뜻 = 축 5 의 초록이 계측 사망.
#=============================================================================
legacy_reader <- function(wt_id) {
  dirs <- qvest_lockbox_legacy_dirs()
  lp <- file.path(if (length(dirs)) dirs[1] else tempdir(),
                  sprintf("qvest_lockbox_access_%s.log", wt_id))
  if (!file.exists(lp)) return(list(pass = TRUE, reason = "no_lockbox_access (clean)"))
  lines <- readLines(lp, warn = FALSE)
  v <- grep(P2_VIOLATION_PATTERN, lines, value = TRUE)
  list(pass = length(v) == 0, reason = sprintf("entries=%d violations=%d", length(lines), length(v)))
}
m1 <- legacy_reader(WT)
if (isTRUE(m1$pass)) {
  ok("mutation_old_reader_passes",
     sprintf("구판 재현본은 같은 주입에서 PASS('%s') — 축 5 의 검출력 실증", m1$reason))
} else {
  bad("mutation_old_reader_passes",
      "구판 재현본까지 FAIL — 주입 위치가 구 결함을 재현하지 못함(축 5 의 초록이 무의미)")
}

#=============================================================================
# 축 7 — 오검출 통제: judge 접근만 있으면 위반 아님
#   lockbox-scope mandate(도훈 2026-05-09): judge 는 유일 접근권, forge/monitoring/
#   execution 은 lockbox 폐기. 이들을 위반으로 세면 감사가 정상 운용을 막는다.
#=============================================================================
# 기록은 **R 측 production writer**(windowing.R::log_lockbox_access)로 남긴다 —
# judge_oos_helper.R 가 실제로 쓰는 경로이고, 이번 수리로 경로가 바뀐 함수이므로
# bash writer(축 4)와 별개로 R writer 도 감사자 경로에 도달하는지 함께 못박는다.
suppressMessages(source(file.path(REPO, "02_Infrastructure/worktask/windowing.R")))
WT2 <- "WT-D29990101_002"
dir.create(file.path(FAKE, "qepm/mailbox/worktask", WT2), recursive = TRUE, showWarnings = FALSE)
log_lockbox_access(WT2, "judge", lockbox_file)
log_lockbox_access(WT2, "forge", lockbox_file)
lp2 <- qvest_lockbox_log(WT2, root = FAKE)
if (!file.exists(lp2)) {
  bad("r_writer_reaches_auditor", sprintf("log_lockbox_access() 기록이 감사자 경로에 없음: %s", lp2))
} else {
  ok("r_writer_reaches_auditor", sprintf("%s (%d행)", basename(lp2), length(readLines(lp2, warn = FALSE))))
}
r2 <- audit_p2_data_separation(WT2)
if (isTRUE(r2$pass)) {
  ok("judge_forge_not_flagged", r2$reason)
} else {
  bad("judge_forge_not_flagged",
      sprintf("pass=%s (%s) — mandate 상 면제 역할을 위반으로 계상", r2$pass, r2$reason))
}

#=============================================================================
# 축 8 — 트레일 가동 + 해당 WT 기록 없음 → 진짜 PASS
#   (축 3 의 NA 와 구별되어야 한다. 둘이 같은 값이면 정보량이 다시 0 이다.)
#=============================================================================
WT3 <- "WT-D29990101_003"
dir.create(file.path(FAKE, "qepm/mailbox/worktask", WT3), recursive = TRUE, showWarnings = FALSE)
r3 <- audit_p2_data_separation(WT3)
if (isTRUE(r3$pass) && grepl("trail live", r3$reason)) {
  ok("trail_live_no_entry_passes", r3$reason)
} else {
  bad("trail_live_no_entry_passes", sprintf("pass=%s reason=%s", r3$pass, r3$reason))
}

#=============================================================================
# 축 9 — P8 이 cwd 에 독립인가 (구판 BOOK_STATE 상대경로 결함)
#=============================================================================
write_json(list(admitted_ids = list("STR_TEST_ADMITTED")),
           file.path(FAKE, "qepm/mailbox/governor/book_state.json"), auto_unbox = TRUE)
rep_month <- format(Sys.Date(), "%Y%m")
invisible(file.create(file.path(FAKE, sprintf("qepm/mailbox/monitoring/reports/monitoring_report_%s.json", rep_month))))

old_wd <- getwd()
setwd(dirname(FAKE))          # cwd 를 루트 밖으로
p8_out <- audit_p8_monitoring()
book_seen <- !grepl("no_book_state_yet", p8_out$reason)
setwd(old_wd)
if (isTRUE(p8_out$pass) && book_seen) {
  ok("p8_cwd_independent", p8_out$reason)
} else {
  bad("p8_cwd_independent",
      sprintf("cwd 밖에서 pass=%s reason=%s — 상대경로 결함 잔존", p8_out$pass, p8_out$reason))
}

#=============================================================================
# 축 10 — P8 도 실제로 FAIL 을 낼 수 있는가
#   admitted 존재 + monitoring 리포트 0건 → FAIL 이어야 한다.
#=============================================================================
unlink(list.files(file.path(FAKE, "qepm/mailbox/monitoring/reports"), full.names = TRUE))
p8_fail <- audit_p8_monitoring()
if (isFALSE(p8_fail$pass)) {
  ok("p8_can_fail", p8_fail$reason)
} else {
  bad("p8_can_fail", sprintf("pass=%s (%s) — P8 도 실패 불가 상태", p8_fail$pass, p8_fail$reason))
}

#=============================================================================
# 축 11 — 돌연변이: 구판 상대경로는 같은 상태에서 PASS 로 뒤집히는가
#=============================================================================
setwd(dirname(FAKE))
legacy_p8_pass <- !file.exists("qepm/mailbox/governor/book_state.json")   # 구판 첫 분기 그대로
setwd(old_wd)
if (isTRUE(legacy_p8_pass)) {
  ok("mutation_old_p8_passes",
     "구판 상대경로는 cwd 밖에서 book_state 를 못 봐 'no_book_state_yet' PASS — 축 9 의 검출력 실증")
} else {
  bad("mutation_old_p8_passes", "구판 재현본이 안 뒤집힘 — 축 9 의 초록이 무의미")
}

# ─── 정리 + 요약 ────────────────────────────────────────────────────────────
if (is.na(old_cpd)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = old_cpd)
cleanup()

cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "lockbox_audit_path", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
