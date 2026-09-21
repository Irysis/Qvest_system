#!/usr/bin/env Rscript
#==============================================================================
# test_boot_lean_director_line.R — 부팅 6번째 줄(Director:)은 캐시를 읽기만 한다 (2026-09-21 플랜 Part 3 · D0)
#
# 계약: boot_lean.sh 는 R 0 · 수리 0. Director 줄은 .cache/rf_director_latest.json 의 boot_line 을 옮기고,
#   부재면 '?' + 원인, 30h 초과·stale 표식이면 ★stale 을 붙인다.
# 판정: 배포된 DIRECTOR 블록을 **패턴으로 추출**(좌표 아님)해 샌드박스 캐시 픽스처 3종에 대고 실행. 운영 캐시 무접촉.
#   F1 캐시 부재 → "Director: ?" 로 시작   F2 신선 → boot_line 전재   F3 stale:true → ★stale   F4 30h 초과 mtime → ★stale
#   C  o.append 가 DIRECTOR 를 소비 · 폴백 printf 에 Director: ? 존재 · 출력이 6줄 계약(qvest.md "6줄")
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY <- Sys.getenv("QVEST_PY_BIN", Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"boot_lean_director_line","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
Sys.setenv(PYTHONUTF8 = "1", PYTHONIOENCODING = "utf-8")

L <- readLines(file.path(ROOT, "02_Infrastructure/ops/boot_lean.sh"), encoding = "UTF-8", warn = FALSE)
i0 <- which(grepl("^def DIRECTOR\\(\\):", L))
if (length(i0) != 1L) { ng("DIRECTOR 정의가 정확히 1개여야 한다", as.character(length(i0))); finish() }
j <- i0 + 1L
while (j <= length(L) && (grepl("^[[:space:]]", L[j]) || !nzchar(trimws(L[j])))) j <- j + 1L
blk <- L[i0:(j - 1L)]
ok(sprintf("DIRECTOR 블록 추출 %d줄", length(blk)))

py_raw <- function(s) sprintf("r'%s'", gsub("'", "", s))
run_dir <- function(block, cache_json = NULL, age_h = 0) {
  S <- file.path(tempdir(), sprintf("boot_dir_%d_%d", Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(S, ".cache"), recursive = TRUE, showWarnings = FALSE)
  if (!is.null(cache_json)) { p <- file.path(S, ".cache/rf_director_latest.json")
    writeLines(enc2utf8(cache_json), p, useBytes = TRUE)
    if (age_h > 0) Sys.setFileTime(p, Sys.time() - age_h * 3600) }
  f <- file.path(S, "boot_probe.py")
  pre <- c("import json,os,io,time", sprintf("P=%s", py_raw(S)), "R=lambda *a: os.path.join(P,*a)",
           "def S(f,d=None):", "    try: return f()", "    except Exception: return d",
           'J=lambda p,d=None: S(lambda: json.load(open(p if os.path.isabs(p) else R(p),encoding="utf-8-sig")),d)',
           "AG=lambda p: S(lambda: (time.time()-os.path.getmtime(R(p)))/3600.0)",
           'HH=lambda h: "?" if h is None else ("%.0fh"%h if h<72 else "%.0fd"%(h/24))')
  writeLines(enc2utf8(c(pre, block, 'print(S(DIRECTOR,"Director: ?"))')), f, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, shQuote(f), stdout = TRUE, stderr = TRUE))
  unlink(S, recursive = TRUE)
  v <- out[nzchar(out)]; if (length(v)) enc2utf8(trimws(v[length(v)])) else "ERR: no output"
}
fresh <- '{"schema":"rf_director_v0","boot_line":"Director: 구속=calmar(5/5) · 최고 PORT_t 4.35 Calmar 0.50 · B5 dead(0/35) · 권고=2계층 T/S/C"}'
stale <- '{"schema":"rf_director_v0","stale":true,"stale_reason":"t","boot_line":"Director: 구속=calmar(5/5)"}'

cat("=== 픽스처 3종 (배포 블록) ===\n")
g <- run_dir(blk, NULL)
if (startsWith(g, "Director: ?")) ok(sprintf("F1 캐시 부재 → %s", substr(g, 1, 60))) else ng("F1 캐시 부재", g)
g <- run_dir(blk, fresh)
if (identical(g, enc2utf8("Director: 구속=calmar(5/5) · 최고 PORT_t 4.35 Calmar 0.50 · B5 dead(0/35) · 권고=2계층 T/S/C"))) ok("F2 신선 캐시 → boot_line 전재(중복 접두 없음)") else ng("F2 신선", g)
g <- run_dir(blk, stale)
if (grepl("★stale", g, fixed = TRUE)) ok("F3 stale:true → ★stale") else ng("F3 stale 표식", g)
g <- run_dir(blk, fresh, age_h = 40)
if (grepl("★stale", g, fixed = TRUE)) ok("F4 mtime 40h → ★stale") else ng("F4 30h 초과", g)

cat("\n=== 소비자·계약 ===\n")
if (any(grepl("o.append(S(DIRECTOR", L, fixed = TRUE))) ok("C o.append 가 DIRECTOR 를 소비한다") else ng("C 소비 줄 없음")
if (any(grepl("Director: ?", L[grepl("printf", L)], fixed = TRUE))) ok("C 폴백 printf 에 Director: ? 존재") else ng("C 폴백에 Director 없음")
if (!any(grepl("subprocess|os\\.system|popen|Popen", blk))) ok("C DIRECTOR 블록에 프로세스 실행 없음(읽기만)") else ng("C 블록이 프로세스를 실행한다")
q <- readLines(file.path(ROOT, ".claude/commands/qvest.md"), encoding = "UTF-8", warn = FALSE)
if (any(grepl("출력 6줄", q, fixed = TRUE)) && any(grepl("`Director:`", q, fixed = TRUE))) ok("C qvest.md 6줄 계약 + Director 불릿") else ng("C qvest.md 계약 미갱신")
finish()
