#!/usr/bin/env Rscript
#==============================================================================
# test_boot_lean_rules_line.R — 부팅 7번째 줄(Rules:)은 일간 채점 캐시를 읽기만 한다 (도훈 2026-09-21 "데일리로 · Qvest 실행 시점에")
#   배포된 RULES 블록을 패턴 추출해 샌드박스 캐시 픽스처에 대고 실행. 운영 캐시 무접촉.
#   F1 부재 → "Rules: ?"  F2 신선 → line 전재  F3 30h 초과 → ★stale  C 소비 줄·폴백·qvest.md(7줄 · Rules 불릿)
#   ★DIR-DIRECTION-SCORE (2026-09-24 도훈 '폐기'): 샌드박스 config 픽스처(기본 director.enabled=true = 종전 경로 양성 대조).
#     F4 enabled=false → "Rules: 폐기" · 낡은 캐시 비전재   M 돌연변이(검사 제거) → F4 red   F5 config 부재 → 종전 경로
#     C qvest.md 1a 채점 단계 부재
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY <- Sys.getenv("QVEST_PY_BIN", Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"boot_lean_rules_line","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
Sys.setenv(PYTHONUTF8 = "1", PYTHONIOENCODING = "utf-8")
L <- readLines(file.path(ROOT, "02_Infrastructure/ops/boot_lean.sh"), encoding = "UTF-8", warn = FALSE)
i0 <- which(grepl("^def RULES\\(\\):", L)); if (length(i0) != 1L) { ng("RULES 정의 1개", as.character(length(i0))); finish() }
j <- i0 + 1L; while (j <= length(L) && (grepl("^[[:space:]]", L[j]) || !nzchar(trimws(L[j])))) j <- j + 1L
blk <- L[i0:(j - 1L)]; ok(sprintf("RULES 블록 추출 %d줄", length(blk)))
py_raw <- function(s) sprintf("r'%s'", gsub("'", "", s))
run_r <- function(block, cache_json = NULL, age_h = 0, cfg = '{"director":{"enabled":true}}') {
  S <- file.path(tempdir(), sprintf("boot_rules_%d_%d", Sys.getpid(), as.integer(runif(1, 1, 1e6)))); dir.create(file.path(S, ".cache"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(S, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  if (!is.null(cfg)) writeLines(enc2utf8(cfg), file.path(S, "06_Registry/reinforce_auto_config.json"), useBytes = TRUE)
  if (!is.null(cache_json)) { p <- file.path(S, ".cache/rf_direction_score_latest.json"); writeLines(enc2utf8(cache_json), p, useBytes = TRUE); if (age_h > 0) Sys.setFileTime(p, Sys.time() - age_h * 3600) }
  f <- file.path(S, "probe.py")
  pre <- c("import json,os,io,time", sprintf("P=%s", py_raw(S)), "R=lambda *a: os.path.join(P,*a)", "def S(f,d=None):", "    try: return f()", "    except Exception: return d",
           'J=lambda p,d=None: S(lambda: json.load(open(p if os.path.isabs(p) else R(p),encoding="utf-8-sig")),d)', "AG=lambda p: S(lambda: (time.time()-os.path.getmtime(R(p)))/3600.0)",
           'HH=lambda h: "?" if h is None else ("%.0fh"%h if h<72 else "%.0fd"%(h/24))')
  writeLines(enc2utf8(c(pre, block, 'print(S(RULES,"Rules: ?"))')), f, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, shQuote(f), stdout = TRUE, stderr = TRUE)); unlink(S, recursive = TRUE)
  v <- out[nzchar(out)]; if (length(v)) enc2utf8(trimws(v[length(v)])) else "ERR: no output"
}
fresh <- '{"schema":"direction_score_v0","verdict":"insufficient","line":"Rules: 채점 보류 · 결정 1/행동 0/결과 0(최소 8) · Δ단위 NA · Δ프로그램 NA · 재현 1/1"}'
g <- run_r(blk, NULL); if (startsWith(g, "Rules: ?")) ok("F1 캐시 부재 → Rules: ?") else ng("F1", g)
g <- run_r(blk, fresh); if (identical(g, enc2utf8("Rules: 채점 보류 · 결정 1/행동 0/결과 0(최소 8) · Δ단위 NA · Δ프로그램 NA · 재현 1/1"))) ok("F2 신선 → line 전재") else ng("F2", g)
g <- run_r(blk, fresh, age_h = 40); if (grepl("★stale", g, fixed = TRUE)) ok("F3 40h → ★stale") else ng("F3", g)
RETIRED <- enc2utf8("Rules: 폐기")
g4 <- run_r(blk, fresh, cfg = '{"director":{"enabled":false}}')
if (startsWith(g4, RETIRED) && !grepl("채점 보류", g4)) ok("F4 director 동결 → Rules: 폐기 · 낡은 캐시 비전재") else ng("F4 폐기 표식", g4)
m <- sub('if isinstance(dc,dict) and dc.get("enabled") is False:', "if False:", blk, fixed = TRUE)
if (!identical(m, blk) && !startsWith(run_r(m, fresh, cfg = '{"director":{"enabled":false}}'), RETIRED)) ok("M 돌연변이(동결 검사 제거) → F4 red") else ng("M 돌연변이가 F4 를 뒤집지 못함")
g5 <- run_r(blk, fresh, cfg = NULL)
if (identical(g5, enc2utf8("Rules: 채점 보류 · 결정 1/행동 0/결과 0(최소 8) · Δ단위 NA · Δ프로그램 NA · 재현 1/1"))) ok("F5 config 부재 → 종전 경로(판독 불가는 Director 줄이 보고)") else ng("F5 config 부재", g5)
if (any(grepl("o.append(S(RULES", L, fixed = TRUE))) ok("C o.append 가 RULES 를 소비") else ng("C 소비 줄 없음")
if (any(grepl("Rules: ?", L[grepl("printf", L)], fixed = TRUE))) ok("C 폴백 printf 에 Rules: ?") else ng("C 폴백")
if (!any(grepl("subprocess|os\\.system|popen|Popen", blk))) ok("C RULES 블록에 프로세스 실행 없음(읽기만)") else ng("C 블록 실행")
q <- readLines(file.path(ROOT, ".claude/commands/qvest.md"), encoding = "UTF-8", warn = FALSE)
if (!any(grepl("^1a[.]", q)) && any(grepl("출력 7줄", q, fixed = TRUE)) && any(grepl("`Rules:`", q, fixed = TRUE))) ok("C qvest.md: 1a 채점 단계 부재(폐기) · 7줄 · Rules 불릿") else ng("C qvest.md 계약")
finish()
