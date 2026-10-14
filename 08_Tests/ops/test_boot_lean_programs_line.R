#!/usr/bin/env Rscript
#==============================================================================
# test_boot_lean_programs_line.R — 부팅 Programs 줄 (v10.01 · 2026-10-13 · 구 Director/Rules 줄 대체)
#
# 대상: 02_Infrastructure/ops/boot_lean.sh::PROGRAMS — 06_Registry/research_programs.json 을 읽기만 해서
#   '측정계약 n/N (남은 id…) | P0 상태 · P1 상태(재료 q·라운드 r) …' 한 줄로 접는다(부팅 계약: R 0 · 쓰기 0).
# 판정: 배포된 PROGRAMS 블록을 **패턴으로 추출**(좌표 아님)해 픽스처 루트에 대고 python 실행 — 결과값으로만 판정.
#   P1 양성 대조(정확한 문자열) · P2 부재 · P3 파손 · P4 schema 불일치 → '?(<원인>)'(0 으로 접지 않음)
#   P5 운영 등록부 — 표시의 완료 수·프로그램 상태가 R writer(program_registry.R::pr_load)가 읽은 값과 같다(재도출)
#   M  위반 주입(블록 사본): done 필터 제거 → P1 red · 파손→빈 값 접기 → P3 red
#   C  소비·계약: o.append 가 S(PROGRAMS 를 소비 · 블록 읽기 전용 · 운영 등록부 무접촉(md5)
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY <- Sys.getenv("QVEST_PY_BIN", Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"boot_lean_programs_line","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L) }
Sys.setenv(PYTHONUTF8 = "1", PYTHONIOENCODING = "utf-8")
REAL <- file.path(ROOT, "06_Registry/research_programs.json")
real_md5 <- if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_

cat("=== 블록 추출 ===\n")
BL <- readLines(file.path(ROOT, "02_Infrastructure/ops/boot_lean.sh"), encoding = "UTF-8", warn = FALSE)
i0 <- which(grepl("^def PROGRAMS\\(\\):", BL))
if (length(i0) != 1L) { ng("PROGRAMS 정의가 정확히 1개여야 한다", as.character(length(i0))); finish() }
j <- i0 + 1L
while (j <= length(BL) && (grepl("^[[:space:]]", BL[j]) || !nzchar(trimws(BL[j])))) j <- j + 1L
blk <- BL[i0:(j - 1L)]
ok(sprintf("PROGRAMS 블록 추출 %d줄", length(blk)))

py_raw <- function(s) sprintf("r'%s'", gsub("'", "", s))
mk_root <- function(tag) { d <- file.path(tempdir(), sprintf("bootprog_%s_%d", tag, Sys.getpid()))
  unlink(d, recursive = TRUE); dir.create(file.path(d, "06_Registry"), recursive = TRUE); d }
run_prog <- function(block, root) {
  f <- file.path(tempdir(), sprintf("prog_probe_%d_%d.py", Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  pre <- c("import json,os,io", sprintf("P=%s", py_raw(root)), "R=lambda *a: os.path.join(P,*a)",
           "def S(f,d=None):", "    try: return f()", "    except Exception: return d")
  writeLines(enc2utf8(c(pre, block, 'print(S(PROGRAMS,"Programs: ?(표시 예외)"))')), f, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, shQuote(f), stdout = TRUE, stderr = TRUE)); unlink(f)
  v <- out[nzchar(out)]; if (length(v)) enc2utf8(v[length(v)]) else "ERR: no output"
}
FIX <- '{"schema":"research_programs_v1","measurement_contract":{"items":[{"id":"MC1","status":"done"},{"id":"MC2","status":"todo"},{"id":"MC3","status":"doing"}]},
"programs":[{"id":"P0_FRONTIER","status":"blocked","queue":[],"rounds":[]},{"id":"P1_RETURN","status":"active","queue":[{"key":"a"},{"key":"b"}],"rounds":[{"round_id":"R1"}]},{"id":"P2_DEFENSE","status":"idle"}]}'
EXP1 <- enc2utf8("Programs: 측정계약 1/3 (남은 MC2 MC3) | P0 blocked · P1 active(재료 2·라운드 1) · P2 idle")

cat("\n=== P 픽스처 ===\n")
SB <- mk_root("p"); writeLines(FIX, file.path(SB, "06_Registry/research_programs.json"))
g <- run_prog(blk, SB)
if (identical(g, EXP1)) ok(sprintf("P1 양성 대조 → '%s'", g)) else ng("P1 양성 대조", g)
SBn <- mk_root("n")
g <- run_prog(blk, SBn)
if (identical(g, enc2utf8("Programs: ?(등록부 부재)"))) ok("P2 등록부 부재 → '?(등록부 부재)'") else ng("P2 부재", g)
SBc <- mk_root("c"); writeLines('{"schema":"research_programs_v1","programs":[', file.path(SBc, "06_Registry/research_programs.json"))
g <- run_prog(blk, SBc)
if (startsWith(g, enc2utf8("Programs: ?(파손 JSON"))) ok(sprintf("P3 파손 JSON → '%s'", g)) else ng("P3 파손", g)
SBs <- mk_root("s"); writeLines('{"schema":"other_v9","measurement_contract":{"items":[]},"programs":[]}', file.path(SBs, "06_Registry/research_programs.json"))
g <- run_prog(blk, SBs)
if (identical(g, enc2utf8("Programs: ?(schema other_v9)"))) ok("P4 schema 불일치 → '?(schema other_v9)'") else ng("P4 schema", g)
## P6 — 미분류 재료(paper_routing.unrouted · 2026-10-14 리뷰 U4: 부팅이 pr_status_lines 를 안 불러 '미분류 수가 뜬다'가 사실이 아니었다)
SBu <- mk_root("u"); fx_u <- sub('"programs":[', '"paper_routing":{"unrouted":[{"key":"engine:A"},{"key":"engine:B"}]},"programs":[', FIX, fixed = TRUE)
writeLines(fx_u, file.path(SBu, "06_Registry/research_programs.json"))
g <- run_prog(blk, SBu)
if (identical(g, enc2utf8(paste0(EXP1, " · 미분류 재료 2")))) ok("P6 미분류 재료 2 → 줄 끝에 '미분류 재료 2' (P1 은 미분류 없음 → 꼬리 없음 · 음성 대조)") else ng("P6 미분류 표시", g)
unlink(SBu, recursive = TRUE)

cat("\n=== P5 운영 등록부 재도출(R writer 판독과 대조 · 읽기만) ===\n")
if (!file.exists(REAL)) ng("P5 운영 등록부 부재", REAL) else {
  source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R"))
  reg <- pr_load(path = REAL)
  nd <- sum(vapply(reg$measurement_contract$items, function(m) identical(m$status, "done"), logical(1)))
  nt <- length(reg$measurement_contract$items)
  g <- run_prog(blk, ROOT)
  want_head <- enc2utf8(sprintf("Programs: 측정계약 %d/%d", nd, nt))
  st_ok <- all(vapply(reg$programs, function(p) grepl(paste0(strsplit(p$id, "_")[[1]][1], " ", p$status), g, fixed = TRUE), logical(1)))
  if (startsWith(g, want_head) && st_ok) ok(sprintf("P5 표시 = R 판독(완료 %d/%d · 프로그램 %d개 상태 일치) → '%s'", nd, nt, length(reg$programs), g))
  else ng("P5 운영 재도출 불일치", g)
}

cat("\n=== M 위반 주입 (블록 사본 · 원본 무접촉) ===\n")
mut1 <- sub(' and m.get("status")=="done"', "", blk, fixed = TRUE)
if (sum(mut1 != blk) == 1L) {
  g <- run_prog(mut1, SB)
  if (!identical(g, EXP1)) ok(sprintf("M1 done 필터 제거 사본 → P1 red ('%s')", g)) else ng("M1 돌연변이를 못 잡는다", g)
} else ng("M1 주입 실패", sprintf("변경 줄 %d", sum(mut1 != blk)))
k2 <- grepl("파손 JSON", blk, fixed = TRUE)
mut2 <- blk; mut2[k2] <- sub('return "Programs: ?(파손 JSON %s)"%type(e).__name__', 'return "Programs: 측정계약 0/0 | 프로그램 0"', blk[k2], fixed = TRUE)
if (sum(mut2 != blk) == 1L) {
  g <- run_prog(mut2, SBc)
  if (!startsWith(g, enc2utf8("Programs: ?(파손 JSON"))) ok(sprintf("M2 파손→빈 값 접기 사본 → P3 red ('%s')", g)) else ng("M2 돌연변이를 못 잡는다", g)
} else ng("M2 주입 실패", sprintf("변경 줄 %d", sum(mut2 != blk)))

cat("\n=== C 소비·계약 ===\n")
ap <- BL[grepl("^o\\.append\\(", BL)]
if (any(grepl("S(PROGRAMS", ap, fixed = TRUE))) ok("C1 o.append 가 S(PROGRAMS 를 소비한다") else ng("C1 소비 줄 없음")
if (!any(grepl("subprocess|os\\.system|Popen|\\.write\\(|['\"][wa]b?['\"]", blk))) ok("C2 PROGRAMS 블록 읽기 전용(프로세스·쓰기 없음)") else ng("C2 블록이 쓰거나 실행한다")
if (!any(grepl("^def (DIRECTOR|RULES)\\(\\):", BL))) ok("C3 퇴역 Director·Rules 정의 없음") else ng("C3 퇴역 줄 잔존")
after <- if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_
if (identical(after, real_md5)) ok("C4 운영 research_programs.json 무접촉(md5 전후 동일)") else ng("C4 운영 등록부가 바뀌었다")
unlink(c(SB, SBn, SBc, SBs), recursive = TRUE)
finish()
