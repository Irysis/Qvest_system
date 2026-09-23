#!/usr/bin/env Rscript
#==============================================================================
# test_decision_register.R — 결정 대기 레지스터 writer 3종 + 부팅 Director 줄 부기 (P3-07 · 2026-09-23)
#
# 계약:
#   writer(reinforce_ledger.R) — dr_open/dr_resolve/dr_list. owner 만 resolve · 재결정 거부(새 id) · 부재·파손은 명시 오류.
#   부팅(boot_lean.sh::DECISIONS) — 레지스터를 읽기만, status=="open" 만 세고 ' · 대기결정 N · 최고령 id(일수d) · 차단 레인'.
#     읽기 실패는 ' · 대기결정 ?(<원인>)' — 0 으로 접지 않는다. 새 줄 없이 Director 줄 끝에 붙는다.
# 판정: 격리 root(임시 디렉터리)만 쓴다 — 운영 06_Registry/decision_register.json 은 md5 전후 대조로 무접촉 확인.
#   W  writer 양방향(정상 경로 + 거부 경로 · owner 검사 제거 돌연변이 red)
#   D  배포된 DECISIONS 블록을 **패턴으로 추출**(좌표 아님)해 R writer 가 쓴 픽스처에 대고 python 실행
#      양성 대조(open 2 · 더 오래된 resolved 1) + 위반 주입(사본 블록에서 status 필터 제거 · '?'→0 접기) → 검사가 red 여야 한다
#   C  소비 줄·줄 수 불변·읽기 전용
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY <- Sys.getenv("QVEST_PY_BIN", Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"decision_register","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L) }
Sys.setenv(PYTHONUTF8 = "1", PYTHONIOENCODING = "utf-8")
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))

REAL <- file.path(ROOT, "06_Registry/decision_register.json")
real_md5 <- if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_
invisible(capture.output(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"))))
mk_root <- function(tag) { d <- file.path(tempdir(), sprintf("dr_%s_%d_%d", tag, Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  dir.create(d, recursive = TRUE, showWarnings = FALSE); normalizePath(d, winslash = "/") }
day <- function(k) format(Sys.Date() - k, "%Y-%m-%d")

cat("=== W writer (격리 root) ===\n")
SB <- mk_root("w")
m <- err_of(dr_list(root = SB))
if (!is.na(m) && grepl("부재", m)) ok("W0 레지스터 부재 → dr_list 명시 오류(빈 목록으로 접지 않음)") else ng("W0 부재", m)
dr_open("DR-OLD", "오래된 결정", c("가", "나"), "가", "현행", c("lane:z"), source = "test",
        root = SB, opened_at = day(30), opened_at_basis = "픽스처")
dr_open("DR-A", "결정 A", c("가", "나"), "가", "현행", c("lane:x", "lane:y"), source = "test",
        root = SB, opened_at = day(10), opened_at_basis = "픽스처")
dr_open("DR-B", "결정 B", list("가"), "", "현행", c("lane:x", "decision:DR-A", "item:P0-01"), source = "test", root = SB)
L <- dr_list(root = SB); ids <- vapply(L, function(x) x$id, character(1))
if (identical(ids, c("DR-OLD", "DR-A", "DR-B"))) ok("W1 open 3 → dr_list 에 보임(오래된 순)") else ng("W1 open→list", paste(ids, collapse = ","))
it <- L[[3]]
if (identical(it$status, "open") && identical(it$owner, "dohoon") && is.null(it$decision) && nzchar(it$registered_at %||% "") &&
    identical(unlist(it$options), "가") && identical(unlist(it$blocks), c("lane:x", "decision:DR-A", "item:P0-01")))
  ok("W1b 스키마 필드(owner 기본 dohoon · decision null · options/blocks 배열 · registered_at)") else ng("W1b 스키마", paste(names(it), collapse = ","))
m <- err_of(dr_open("DR-C", "t", "가", "", "현행", character(0), source = "test", root = SB, opened_at = day(3)))
if (!is.na(m) && grepl("근거", m)) ok("W2 소급 opened_at 근거 없음 → 거부") else ng("W2 소급 근거", m)
m <- err_of(dr_open("DR-A", "t", "가", "", "현행", character(0), source = "test", root = SB))
if (!is.na(m) && grepl("이미 있는 id", m)) ok("W3 중복 id → 거부") else ng("W3 중복", m)
m1 <- err_of(dr_open("DR-D", "t", "가", "", "현행", "자유 문자열", source = "test", root = SB))
m2 <- err_of(dr_open("DR-D", "t", "가", "", "현행", "decision:NOPE", source = "test", root = SB))
if (!is.na(m1) && grepl("접두", m1) && !is.na(m2) && grepl("미등록", m2)) ok("W4 blocks 접두 없음·decision 대상 미등록 → 거부") else ng("W4 blocks", paste(m1, m2))
P <- dr_path(SB); md5_0 <- unname(tools::md5sum(P))
m <- err_of(dr_resolve("DR-OLD", "가", decided_by = "q", root = SB))
if (!is.na(m) && grepl("owner", m) && identical(unname(tools::md5sum(P)), md5_0)) ok("W5 owner≠decided_by → 거부 · 파일 불변") else ng("W5 owner", m)
dr_resolve("DR-OLD", "가 채택", decided_by = "dohoon", note = "픽스처", root = SB)
ids_o <- vapply(dr_list(root = SB), function(x) x$id, character(1))
R0 <- dr_list("resolved", root = SB)
if (identical(ids_o, c("DR-A", "DR-B")) && length(R0) == 1L && identical(R0[[1]]$decision, "가 채택") &&
    identical(R0[[1]]$decided_by, "dohoon") && nzchar(R0[[1]]$decided_at %||% ""))
  ok("W6 resolve → open 목록에서 사라지고 resolved 에 decision/decided_by/decided_at") else ng("W6 resolve", paste(ids_o, collapse = ","))
m <- err_of(dr_resolve("DR-OLD", "나", decided_by = "dohoon", root = SB))
if (!is.na(m) && grepl("재결정 거부", m)) ok("W7 resolved 재결정 → 거부(새 항목으로)") else ng("W7 재결정", m)
m <- err_of(dr_resolve("NOPE", "나", decided_by = "dohoon", root = SB))
if (!is.na(m) && grepl("항목 부재", m)) ok("W8 없는 id resolve → 거부") else ng("W8 부재 id", m)
res <- list.files(dirname(P), all.files = TRUE, no.. = TRUE)
if (identical(res, "decision_register.json")) ok("W9 원자 쓰기 잔재(tmp) 0") else ng("W9 잔재", paste(res, collapse = ","))
# 돌연변이 — owner 검사를 지운 dr_resolve 사본 → W5 의 거부 단정이 red 여야 한다(원본 파일 무접촉)
src <- deparse(dr_resolve); mut <- sub("!identical(decided_by, own)", "FALSE", src, fixed = TRUE)
if (sum(src != mut) == 1L) {
  f_mut <- eval(parse(text = mut)); environment(f_mut) <- environment(dr_resolve)
  SBm <- mk_root("wm"); dr_open("DR-M", "t", "가", "", "현행", character(0), source = "test", root = SBm)
  mm <- err_of(f_mut("DR-M", "가", decided_by = "q", root = SBm))
  if (is.na(mm)) ok("W10 owner 검사 제거 돌연변이 → 비owner resolve 통과 = W5 단정 red(검사가 잡는다)") else ng("W10 돌연변이가 여전히 거부됨", mm)
} else ng("W10 돌연변이 주입 실패", sprintf("변경 줄 %d", sum(src != mut)))

cat("\n=== D 부팅 표시 (배포 DECISIONS 블록) ===\n")
BL <- readLines(file.path(ROOT, "02_Infrastructure/ops/boot_lean.sh"), encoding = "UTF-8", warn = FALSE)
i0 <- which(grepl("^def DECISIONS\\(\\):", BL))
if (length(i0) != 1L) { ng("DECISIONS 정의가 정확히 1개여야 한다", as.character(length(i0))); finish() }
j <- i0 + 1L
while (j <= length(BL) && (grepl("^[[:space:]]", BL[j]) || !nzchar(trimws(BL[j])))) j <- j + 1L
blk <- BL[i0:(j - 1L)]
ok(sprintf("DECISIONS 블록 추출 %d줄", length(blk)))
py_raw <- function(s) sprintf("r'%s'", gsub("'", "", s))
run_dec <- function(block, root) {
  f <- file.path(tempdir(), sprintf("dec_probe_%d_%d.py", Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  pre <- c("import json,os,io,time", sprintf("P=%s", py_raw(root)), "R=lambda *a: os.path.join(P,*a)",
           "def S(f,d=None):", "    try: return f()", "    except Exception: return d")
  writeLines(enc2utf8(c(pre, block, 'print(S(DECISIONS," · 대기결정 ?(표시 예외)"))')), f, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, shQuote(f), stdout = TRUE, stderr = TRUE)); unlink(f)
  v <- out[nzchar(out)]; if (length(v)) enc2utf8(v[length(v)]) else "ERR: no output"
}
# 양성 대조 — SB 는 W 단계 결과: open DR-A(10d · lane x,y) · DR-B(0d · lane x) + resolved DR-OLD(30d · lane z)
chk_pos <- function(o) identical(o, enc2utf8(" · 대기결정 2 · 최고령 DR-A(10d) · 차단 x·y"))
g <- run_dec(blk, SB)
n_r <- length(dr_list(root = SB))
if (chk_pos(g) && n_r == 2L) ok(sprintf("D1 양성 대조 N=2 · 최고령 DR-A(10d) · 차단 x·y (R dr_list 와 일치) → '%s'", g)) else ng("D1 양성 대조", g)
chk_q <- function(o, why) startsWith(o, enc2utf8(paste0(" · 대기결정 ?(", why)))
SBc <- mk_root("c"); dir.create(file.path(SBc, "06_Registry"))
writeLines('{"schema":"decision_register_v1","items":[', file.path(SBc, "06_Registry/decision_register.json"))
g <- run_dec(blk, SBc); m <- err_of(dr_list(root = SBc))
if (chk_q(g, "파손 JSON") && !is.na(m) && grepl("파손 JSON", m)) ok(sprintf("D2 파손 JSON → dr_list 명시 오류 · 표시 '%s'", g)) else ng("D2 파손", paste(g, m))
invisible(file.create(file.path(SBc, "06_Registry/decision_register.json")))   # 0바이트
g <- run_dec(blk, SBc); m <- err_of(dr_list(root = SBc))
if (chk_q(g, "파손 JSON") && !is.na(m)) ok("D2b 0바이트 파일 → 명시 오류 · '?'") else ng("D2b 0바이트", paste(g, m))
SBn <- mk_root("n")
g <- run_dec(blk, SBn)
if (chk_q(g, "레지스터 부재")) ok("D3 레지스터 부재 → '?(레지스터 부재)'") else ng("D3 부재", g)
SBs <- mk_root("s"); dir.create(file.path(SBs, "06_Registry"))
writeLines('{"schema":"other_v9","items":[]}', file.path(SBs, "06_Registry/decision_register.json"))
g <- run_dec(blk, SBs); m <- err_of(dr_list(root = SBs))
if (chk_q(g, "schema") && !is.na(m) && grepl("schema", m)) ok("D4 schema 불일치 → 양쪽 명시 실패") else ng("D4 schema", paste(g, m))
SBz <- mk_root("z")
dr_open("DR-Z", "t", "가", "", "현행", "lane:x", source = "test", root = SBz)
dr_resolve("DR-Z", "가", decided_by = "dohoon", root = SBz)
g <- run_dec(blk, SBz)
if (identical(g, enc2utf8(" · 대기결정 0"))) ok("D5 전부 resolved → '대기결정 0'(부재·파손의 '?' 와 구별)") else ng("D5 0건", g)

cat("\n=== M 위반 주입 (블록 사본 · 원본 무접촉) ===\n")
mut1 <- sub('and x.get("status")=="open"', "", blk, fixed = TRUE)
if (sum(mut1 != blk) == 1L) {
  g <- run_dec(mut1, SB)
  if (!chk_pos(g)) ok(sprintf("M1 status 필터 제거 사본 → D1 양성 대조 red ('%s')", g)) else ng("M1 돌연변이를 못 잡는다", g)
} else ng("M1 주입 실패", sprintf("변경 줄 %d", sum(mut1 != blk)))
k2 <- grepl("파손 JSON", blk, fixed = TRUE)
mut2 <- blk; mut2[k2] <- sub('return " · 대기결정 ?(파손 JSON %s)"%type(e).__name__', 'return " · 대기결정 0"', blk[k2], fixed = TRUE)
if (sum(mut2 != blk) == 1L) {
  writeLines('{"schema":"decision_register_v1","items":[', file.path(SBc, "06_Registry/decision_register.json"))
  g <- run_dec(mut2, SBc)
  if (!chk_q(g, "파손 JSON")) ok(sprintf("M2 파손→0 접기 사본 → D2 단정 red ('%s')", g)) else ng("M2 돌연변이를 못 잡는다", g)
} else ng("M2 주입 실패", sprintf("변경 줄 %d", sum(mut2 != blk)))

cat("\n=== C 소비·계약 ===\n")
ap <- BL[grepl("^o\\.append\\(", BL)]
if (any(grepl("S(DIRECTOR", ap, fixed = TRUE) & grepl("S(DECISIONS", ap, fixed = TRUE)))
  ok("C1 Director 줄 한 o.append 에 DECISIONS 부기(새 줄 아님)") else ng("C1 소비 줄 없음")
if (length(ap) == 7L) ok("C2 부팅 o.append 7개 불변(줄 수 계약)") else ng("C2 줄 수 변경", as.character(length(ap)))
if (!any(grepl("subprocess|os\\.system|Popen|\\.write\\(|['\"][wa]b?['\"]", blk))) ok("C3 DECISIONS 블록 읽기 전용(프로세스·쓰기 없음)") else ng("C3 블록이 쓰거나 실행한다")
after <- if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_
if (identical(after, real_md5)) ok("C4 운영 06_Registry/decision_register.json 무접촉(md5 전후 동일)") else ng("C4 운영 레지스터가 바뀌었다")
unlink(c(SB, SBc, SBn, SBs, SBz), recursive = TRUE)
finish()
