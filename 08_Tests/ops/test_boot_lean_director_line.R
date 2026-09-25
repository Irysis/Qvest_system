#!/usr/bin/env Rscript
#==============================================================================
# test_boot_lean_director_line.R — 부팅 6번째 줄(Director:)은 캐시를 읽기만 한다 (2026-09-21 플랜 Part 3 · D0)
#
# 계약: boot_lean.sh 는 R 0 · 수리 0. Director 줄은 .cache/rf_director_latest.json 의 boot_line 을 옮기고,
#   부재면 '?' + 원인, 30h 초과·stale 표식이면 ★stale 을 붙인다.
# 판정: 배포된 DIRECTOR 블록을 **패턴으로 추출**(좌표 아님)해 샌드박스 캐시 픽스처 3종에 대고 실행. 운영 캐시 무접촉.
#   F1 캐시 부재 → "Director: ?" 로 시작   F2 신선 → boot_line 전재   F3 stale:true → ★stale   F4 30h 초과 mtime → ★stale
#   C  o.append 가 DIRECTOR 를 소비 · 폴백 printf 에 Director: ? 존재 · 출력이 6줄 계약(qvest.md "6줄")
#   ★v10.4 (2026-09-24 · 칩 task_19342c25) 부재 ≠ 파손: F5 한글 중간이 잘린 UTF-8 → 내용 복원 + "파손" 표시(미실행 아님)
#     F6 JSON 판독 불가 → "캐시 파손" · M 돌연변이(파손을 부재로 합침) → F5·F6 red
#   ★DIR-PHASE0 (2026-09-24 도훈): 샌드박스에 config 픽스처를 둔다(기본 director.enabled=true = 종전 경로 양성 대조).
#     F7 enabled=false + 신선 캐시 → "Director: 동결" · 캐시 수치 비노출   F8 config 부재 → '?' + 판독 불가(동결로 접지 않음)
#     F9 director 키 부재 → 종전 경로(캐시 전재)   M2 돌연변이(enabled 검사 제거) → F7 red
#     C qvest.md 에 'Director 권고 = 첫 선택지' 규칙 부재
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
CFG_ON <- '{"enabled":false,"director":{"enabled":true,"act":false}}'
run_dir <- function(block, cache_json = NULL, age_h = 0, cache_raw = NULL, cfg = CFG_ON) {
  S <- file.path(tempdir(), sprintf("boot_dir_%d_%d", Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(S, ".cache"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(S, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  if (!is.null(cfg)) writeLines(enc2utf8(cfg), file.path(S, "06_Registry/reinforce_auto_config.json"), useBytes = TRUE)
  if (!is.null(cache_json)) { p <- file.path(S, ".cache/rf_director_latest.json")
    writeLines(enc2utf8(cache_json), p, useBytes = TRUE)
    if (age_h > 0) Sys.setFileTime(p, Sys.time() - age_h * 3600) }
  if (!is.null(cache_raw)) writeBin(cache_raw, file.path(S, ".cache/rf_director_latest.json"))
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

# F5/F6 — 부재 ≠ 파손 (09-24 실측 형태: boot_line 이 '회'(ED 9A 8C) 두 바이트에서 잘림)
broken <- c(charToRaw('{"schema":"rf_director_v0","boot_line":"Director: calmar(5/5) L2 FR_003_n1 C'),
            as.raw(c(0xc2, 0xb7)), charToRaw("1"), as.raw(c(0xed, 0x9a)), charToRaw('"}'))
g5 <- run_dir(blk, cache_raw = broken)
if (grepl("\ud30c\uc190", g5) && !grepl("\ubbf8\uc2e4\ud589", g5) && grepl("FR_003_n1", g5, fixed = TRUE))
  ok(sprintf("F5 UTF-8 파손 캐시 → 내용 복원 + 파손 표시(미실행 아님): %s", substr(g5, 1, 70))) else ng("F5 UTF-8 파손", g5)
g6 <- run_dir(blk, "{ not json")
if (grepl("\ud30c\uc190", g6) && !grepl("\ubbf8\uc2e4\ud589", g6)) ok("F6 JSON 판독 불가 → 캐시 파손(미실행 아님)") else ng("F6 JSON 파손", g6)
# M — 돌연변이: 파손을 부재로 합친다(구판 동작 = 디코드 실패를 빈 캐시로 · 파손 문구를 미실행 문구로)
mblk <- sub('except UnicodeDecodeError: txt=raw.decode("utf-8-sig","replace"); bad=True', 'except UnicodeDecodeError: txt=""; bad=True', blk, fixed = TRUE)
mblk <- sub("Director: ? (\uce90\uc2dc \ud30c\uc190 \u2014", "Director: ? (rf_director \ubbf8\uc2e4\ud589 \u2014", mblk, fixed = TRUE)
if (!identical(mblk, blk) && !grepl("\ud30c\uc190", run_dir(mblk, cache_raw = broken)) && !grepl("\ud30c\uc190", run_dir(mblk, "{ not json")))
  ok("M 돌연변이(파손을 부재로 합침) → F5·F6 red") else ng("M 돌연변이가 F5·F6 을 뒤집지 못함(검사 무력)")

cat("\n=== DIR-PHASE0 동결 (config 픽스처) ===\n")
FROZEN <- enc2utf8("Director: 동결")
g7 <- run_dir(blk, fresh, cfg = '{"director":{"enabled":false,"act":false}}')
if (startsWith(g7, FROZEN) && !grepl("4.35", g7, fixed = TRUE)) ok(sprintf("F7 enabled=false → 동결 표시 · 캐시 수치 비노출: %s", substr(g7, 1, 60))) else ng("F7 동결", g7)
g8 <- run_dir(blk, fresh, cfg = NULL)
if (startsWith(g8, "Director: ?") && grepl("판독 불가", g8) && !startsWith(g8, FROZEN)) ok("F8 config 부재 → '?' + 판독 불가(동결로 접지 않음)") else ng("F8 config 부재", g8)
g9 <- run_dir(blk, fresh, cfg = '{"enabled":true}')
if (identical(g9, enc2utf8("Director: 구속=calmar(5/5) · 최고 PORT_t 4.35 Calmar 0.50 · B5 dead(0/35) · 권고=2계층 T/S/C"))) ok("F9 director 키 부재 → 종전 경로(캐시 전재)") else ng("F9 키 부재", g9)
m2 <- sub('if isinstance(dc,dict) and dc.get("enabled") is False:', "if False:", blk, fixed = TRUE)
if (!identical(m2, blk) && !startsWith(run_dir(m2, fresh, cfg = '{"director":{"enabled":false}}'), FROZEN)) ok("M2 돌연변이(enabled 검사 제거) → F7 red") else ng("M2 돌연변이가 F7 을 뒤집지 못함(검사 무력)")

cat("\n=== 소비자·계약 ===\n")
if (any(grepl("o.append(S(DIRECTOR", L, fixed = TRUE))) ok("C o.append 가 DIRECTOR 를 소비한다") else ng("C 소비 줄 없음")
if (any(grepl("Director: ?", L[grepl("printf", L)], fixed = TRUE))) ok("C 폴백 printf 에 Director: ? 존재") else ng("C 폴백에 Director 없음")
if (!any(grepl("subprocess|os\\.system|popen|Popen", blk))) ok("C DIRECTOR 블록에 프로세스 실행 없음(읽기만)") else ng("C 블록이 프로세스를 실행한다")
q <- readLines(file.path(ROOT, ".claude/commands/qvest.md"), encoding = "UTF-8", warn = FALSE)
if (any(grepl("출력 7줄", q, fixed = TRUE)) && any(grepl("`Director:`", q, fixed = TRUE))) ok("C qvest.md 7줄 계약 + Director 불릿") else ng("C qvest.md 계약 미갱신")
if (!any(grepl("첫 선택지 = `Director:`", q, fixed = TRUE)) && !any(grepl('rf_record_decision("direction"', q, fixed = TRUE))) ok("C qvest.md 'Director 권고 = 첫 선택지'·human_override 규칙 부재(DIR-PHASE0)") else ng("C qvest.md 에 디렉터 첫 선택지 규칙 잔존")
finish()
