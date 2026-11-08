#==============================================================================
# test_qv_bash.R — bash 실행 파일 해석기(qv_bash.R · qv_bash.py) 검사 (2026-11-07)
#
# 계약: 02_Infrastructure/docs/rules/r-portability.md 금칙 ⑦ (bare "bash" 금지 → qv_bash())
# 전제(메인 PC 실측 11-07): WSL 이 있으면 C:\Windows\System32\bash.exe 가 PATH 보다 먼저 잡힌다.
#
# 축: ① 합성 트리(가짜 System32 · Rtools · Git · WindowsApps)에서 해석 순서 — System32 건너뜀 ·
#     PATH 순서 보존 · 덮어쓰기 · 없으면 오류(조용히 WSL 로 떨어지지 않음) · 비 Windows
#   ② Python 짝이 같은 합성 입력에 같은 답 ③ 실물: 이 PC 의 해석 결과가 System32 가 아니고 실제로
#   돈다 · 함정 전제 재현 여부 기록 ④ 돌연변이 통제: System32 제외를 지운 사본은 ① 에서 잡혀야 한다
#   (소스 텍스트 치환 · 치환 성사 확인 — deparse 사본은 줄바꿈에서 조용히 빗나간다).
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

.self <- tryCatch(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]),
                                winslash = "/", mustWork = TRUE), error = function(e) NA_character_)
.cands <- c(if (!is.na(.self)) dirname(dirname(dirname(.self))),
            Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))
.cands <- gsub("\\\\", "/", .cands[nzchar(.cands)])
ROOT <- .cands[file.exists(file.path(.cands, "02_Infrastructure/ops/qv_bash.R"))][1]
if (is.na(ROOT)) stop("프로젝트 루트 미발견(02_Infrastructure/ops/qv_bash.R 표지)")
SRC_R  <- file.path(ROOT, "02_Infrastructure/ops/qv_bash.R")
SRC_PY <- file.path(ROOT, "02_Infrastructure/ops/qv_bash.py")

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)

cat("=== qv_bash resolver ===\n")
E <- new.env(parent = globalenv()); sys.source(SRC_R, envir = E)

# ─── ① 합성 트리 ────────────────────────────────────────────────────────────
T0 <- gsub("\\\\", "/", tempfile("qvbash_"))
mk <- function(...) { d <- file.path(T0, ...); dir.create(d, recursive = TRUE, showWarnings = FALSE); f <- file.path(d, "bash.exe"); writeLines("", f); d }
d_sys  <- mk("Windows", "System32")
d_wow  <- mk("Windows", "SysWOW64")
d_app  <- mk("Users", "u", "AppData", "Local", "Microsoft", "WindowsApps")
d_rt   <- mk("rtools45", "usr", "bin")
d_git  <- mk("Git", "usr", "bin")
d_none <- file.path(T0, "nothing"); dir.create(d_none, showWarnings = FALSE)
ov_f   <- file.path(T0, "custom", "bash.exe"); dir.create(dirname(ov_f), showWarnings = FALSE); writeLines("", ov_f)
P <- function(...) paste(c(...), collapse = ";")

CASES <- list(
  list(name = "system32_first_is_skipped", path = P(d_sys, d_rt, d_git), want = file.path(d_rt, "bash.exe")),
  list(name = "path_order_preserved_git_first", path = P(d_none, d_git, d_rt), want = file.path(d_git, "bash.exe")),
  list(name = "syswow64_and_windowsapps_skipped", path = P(d_wow, d_app, d_git), want = file.path(d_git, "bash.exe")),
  list(name = "backslash_and_quotes_in_path", path = P(paste0('"', gsub("/", "\\\\", d_sys), '"'), paste0(gsub("/", "\\\\", d_rt), "\\")),
       want = file.path(d_rt, "bash.exe")),
  list(name = "fixed_fallback_when_path_has_only_system32", path = P(d_sys), fixed = file.path(d_git, "bash.exe"),
       want = file.path(d_git, "bash.exe")),
  list(name = "override_wins", path = P(d_rt), override = ov_f, want = ov_f)
)
res_r <- list()
for (cs in CASES) {
  got <- tryCatch(E$qv_bash(path = cs$path, override = cs$override %||% "", fixed = cs$fixed %||% character(0),
                            windows = TRUE), error = function(e) paste("ERROR:", conditionMessage(e)))
  res_r[[cs$name]] <- got
  chk(paste0("r_", cs$name), identical(got, cs$want), sprintf("got=%s", got))
}
e1 <- tryCatch({ E$qv_bash(path = P(d_sys, d_app), override = "", fixed = character(0), windows = TRUE); "no error" },
               error = function(e) conditionMessage(e))
chk("r_only_system32_raises_not_wsl", grepl("찾지 못했다", e1), e1)
e2 <- tryCatch({ E$qv_bash(path = P(d_rt), override = file.path(T0, "missing.exe"), windows = TRUE); "no error" },
               error = function(e) conditionMessage(e))
chk("r_missing_override_raises", grepl("QVEST_BASH", e2), e2)
chk("r_non_windows_is_bare_bash", identical(E$qv_bash(path = P(d_sys), windows = FALSE), "bash"))

# ─── ② Python 짝 — 같은 합성 입력에 같은 답 ─────────────────────────────────
py <- c(Sys.getenv("QVEST_PY", ""), "C:/Users/99922/AppData/Local/Programs/Python/Python315/python.exe",
        file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"))
py <- py[nzchar(py) & file.exists(py)][1]
if (is.na(py)) {
  bad("py_interpreter_found", "Python 없음 — QVEST_PY 확인(짝 검사 불가 = 실패로 센다)")
} else {
  spec <- lapply(CASES, function(cs) list(name = cs$name, path = cs$path, override = cs$override %||% "",
                                         fixed = as.list(cs$fixed %||% character(0))))
  jf <- tempfile(fileext = ".json"); write_json(spec, jf, auto_unbox = TRUE)
  code <- paste(
    "import json,sys; sys.path.insert(0, sys.argv[1]); from qv_bash import qv_bash",
    "out = {}",
    "for c in json.load(open(sys.argv[2], encoding='utf-8')):",
    "    try: out[c['name']] = qv_bash(path=c['path'], override=c['override'], fixed=tuple(c['fixed']), windows=True)",
    "    except Exception as e: out[c['name']] = 'ERROR: ' + str(e)",
    "try: qv_bash(path=sys.argv[3], override='', fixed=(), windows=True); out['_only_sys'] = 'no error'",
    "except FileNotFoundError: out['_only_sys'] = 'raised'",
    "out['_nonwin'] = qv_bash(path=sys.argv[3], windows=False)",
    "print(json.dumps(out, ensure_ascii=True))", sep = "\n")
  pf <- tempfile(fileext = ".py"); writeLines(code, pf, useBytes = TRUE)
  o <- suppressWarnings(system2(py, c("-I", shQuote(pf), shQuote(dirname(SRC_PY)), shQuote(jf), shQuote(P(d_sys, d_app))),
                                stdout = TRUE, stderr = TRUE))
  st <- attr(o, "status")
  pr <- tryCatch(fromJSON(paste(o, collapse = "")), error = function(e) NULL)
  if (is.null(pr) || (!is.null(st) && st != 0)) {
    bad("py_runs", sprintf("Python 짝 실행 실패 rc=%s: %s", st %||% 0, paste(utils::tail(o, 3), collapse = " | ")))
  } else {
    for (cs in CASES) chk(paste0("py_same_as_r_", cs$name), identical(pr[[cs$name]], res_r[[cs$name]]),
                          sprintf("py=%s", pr[[cs$name]]))
    chk("py_only_system32_raises", identical(pr[["_only_sys"]], "raised"), pr[["_only_sys"]])
    chk("py_non_windows_is_bare_bash", identical(pr[["_nonwin"]], "bash"))
  }
}

# ─── ③ 실물(이 PC) ──────────────────────────────────────────────────────────
if (.Platform$OS.type == "windows") {
  live <- tryCatch(E$qv_bash(), error = function(e) paste("ERROR:", conditionMessage(e)))
  chk("live_resolves_to_existing_non_system32", file.exists(live) && !grepl("system32", live, ignore.case = TRUE),
      sprintf("qv_bash() = %s", live))
  if (file.exists(live)) {
    o <- suppressWarnings(system2(live, c("-c", shQuote("echo qv_bash_ok:$(uname -s)")), stdout = TRUE, stderr = TRUE))
    chk("live_bash_executes_msys_not_linux", any(grepl("^qv_bash_ok:(MSYS|MINGW)", o)), paste(o, collapse = " | "))
  }
  sw <- unname(Sys.which("bash"))
  if (grepl("system32", sw, ignore.case = TRUE)) {
    ok("trap_premise_reproduced", sprintf("Sys.which(\"bash\") = %s — bare \"bash\" 는 이 PC 에서 WSL 을 띄운다(금칙 ⑦ 근거 실재)", sw))
  } else {
    ok("trap_premise_platform_note", sprintf("Sys.which(\"bash\") = %s — 이 PC 엔 WSL 가로챔 없음(금칙 ⑦ 은 WSL 있는 PC 전제)", sw))
  }
}

# ─── ④ 돌연변이 통제 — System32 제외를 지운 사본은 ① 에서 잡혀야 한다 ─────────
src <- readLines(SRC_R, warn = FALSE, encoding = "UTF-8")
pat_line <- grep('^\\.QV_BASH_SKIP <- paste0\\(', src)
mut <- src
if (length(pat_line) == 1L) {
  mut[pat_line] <- '.QV_BASH_SKIP <- paste0("(?!x)x"'
  nxt <- pat_line + 1L
  while (nxt <= length(mut) && grepl('^\\s+"', mut[nxt])) { mut[nxt] <- ""; nxt <- nxt + 1L }
  mut[nxt - 1L] <- paste0(mut[nxt - 1L], ")")
}
applied <- length(pat_line) == 1L && !identical(mut, src)
chk("mutation_applied", applied, "System32 제외 패턴 치환 성사(치환이 빗나가면 이 통제는 가짜다)")
if (applied) {
  M <- new.env(parent = globalenv())
  ld <- tryCatch({ eval(parse(text = mut), envir = M); TRUE }, error = function(e) conditionMessage(e))
  if (!isTRUE(ld)) bad("mutant_loads", ld) else {
    mg <- M$qv_bash(path = CASES[[1]]$path, override = "", fixed = character(0), windows = TRUE)
    chk("mutant_killed_by_case1", !identical(mg, CASES[[1]]$want) && grepl("System32", mg),
        sprintf("돌연변이 답 = %s (System32 를 집어야 검사가 살아 있다)", mg))
  }
}

# ─── ⑤ Python bare bash 스캔 — subprocess 인자 목록 첫 칸 "bash"(R 쪽은 test_r_portability.R 금칙 ⑦) ───
PY_BARE <- "\\[\\s*[\"'](bash|bash\\.exe)[\"']\\s*[,\\]]"
scan_py <- function(lines) { L <- lines[!grepl("^\\s*#", lines)]; sum(grepl(PY_BARE, L, perl = TRUE, ignore.case = TRUE)) }
chk("py_scan_catches_injected",
    scan_py(c('r = subprocess.run(["bash", "-n", tmp])', "p = subprocess.Popen(['bash', '-c', s])", '    ["bash.exe"],')) == 3L,
    "합성 위반 3건 검출(못 잡으면 아래 0건은 계측 사망)")
chk("py_scan_clean_control",
    scan_py(c('r = subprocess.run([qv_bash(), "-n", tmp])', 'x = ["bashful", 1]', '# subprocess.run(["bash", x])',
              'r = subprocess.run(["C:/Program Files/Git/usr/bin/bash.exe", x])')) == 0L, "정본 · 주석 · 전체 경로 오검출 0")
py_files <- unlist(lapply(c("02_Infrastructure", "08_Tests", "qepm/scripts"), function(d) {
  d <- file.path(ROOT, d)
  if (dir.exists(d)) list.files(d, pattern = "\\.py$", recursive = TRUE, full.names = TRUE) else character(0)
}))
py_files <- py_files[!grepl("/(_archive[^/]*|__pycache__|\\.venv[^/]*)/", py_files)]
off <- character(0)
for (f in py_files) {
  n <- scan_py(tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0)))
  if (n > 0L) off <- c(off, sprintf("%s(%d)", sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", f)), n))
}
chk("py_no_bare_bash_argv", length(off) == 0L,
    if (length(off)) paste("bare bash:", paste(off, collapse = ", ")) else sprintf("%d .py 스캔 · 0건", length(py_files)))

unlink(T0, recursive = TRUE)
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "qv_bash", pass = PASS, fail = FAIL, total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
