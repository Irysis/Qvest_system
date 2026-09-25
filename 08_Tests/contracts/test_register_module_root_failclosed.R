#!/usr/bin/env Rscript
#==============================================================================
# test_register_module_root_failclosed.R — register_module.R::.RM_ROOT() 루트 해석 fail-closed 양방향 검사 (P0-14 · 2026-09-25)
#
# 사고: 2026-09-25 15:59 샌드박스 검사(QM_ROOT·CLAUDE_PROJECT_DIR = 샌드박스)에서 샌드박스에 04_Research 가 없자 구판 .RM_ROOT() 가
#   getwd()·운영 리터럴 경로로 폴백해 04_Research/strategies/RP_FIX_* 4개를 운영에 썼다(4번째 샌드박스 오염).
# 재는 것(자식 Rscript --no-environ · R_ENVIRON_USER=빈 파일 — ~/.Renviron 의 QM_ROOT 역류 차단):
#   C1 [주입] QM_ROOT·CLAUDE_PROJECT_DIR = 요건 미충족 루트(04_Research 없음) → source 단계에서 stop(fail-closed) · 쓰기 0
#   C2 [주입] QM_ROOT = 요건 미충족 · CLAUDE_PROJECT_DIR = 요건 충족 루트 → stop(QM_ROOT 가 데이터 루트 정본 — 구판은 CPD 로 샜다)
#   C3 [양성] QM_ROOT = 요건 충족 샌드박스 · CLAUDE_PROJECT_DIR = 다른 루트 → QM_ROOT(알림 1줄)
#   C4 [양성] 둘 다 미설정 · cwd = 요건 충족 루트 → 구판 폴백(getwd) 그대로
#   C5 [양성] QM_ROOT 충족(또는 없음) + PROJECT_ROOT 전역 → 그대로(검사들이 쓰는 경로 — test_register_module · test_module_registry_exclusivity)
#   C6 [주입 · 수리 2판] QM_ROOT = 없는 경로(오타)·요건 미충족 + PROJECT_ROOT 전역 → stop / C6b 실경로 = config.R 루트 해석(운영 리터럴 폴백 ·
#      리터럴은 가짜 '운영' GOOD 으로 치환) 뒤 source → stop · C6c 양성(QM_ROOT 충족 → 그대로)
#   M1 [돌연변이] 구판 .RM_ROOT() 로 되돌린 사본은 C1 에서 설정 루트 밖(리터럴/작업 디렉터리)으로 샌다 = C1 이 잡는다
#   M2 [돌연변이] 수리 2판 ⓪ 검사를 끈 사본은 C6b 실경로에서 '운영' 대역으로 샌다 = C6b 가 잡는다
#   Z  루트(원천) 04_Research/strategies 목록 · module_catalog.json md5 불변
# 쓰기: tempdir 만(가짜 루트 · 자식 스크립트). 자식은 source 와 경로 출력만 한다 — register_module() 호출 없음.
# 실행: QM_ROOT=<루트> Rscript --no-environ 08_Tests/contracts/test_register_module_root_failclosed.R
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)   # 백슬래시 루트(파이썬 미러 등) — 자식 스크립트 문자열 속 \U 즉사 방지(다른 검사들과 같은 처리)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (length(why) && any(nzchar(why))) paste0(" — ", paste(why, collapse = " | ")) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
RM <- file.path(ROOT, "02_Infrastructure/contracts/register_module.R")
if (!file.exists(RM)) { ng("register_module.R 부재", RM); quit(status = 1L) }
TMP <- normalizePath(tempdir(), winslash = "/")
T <- file.path(TMP, sprintf("p14_rm_%d", Sys.getpid())); unlink(T, recursive = TRUE)
BAD  <- file.path(T, "bad_root");  dir.create(file.path(BAD, "02_Infrastructure"), recursive = TRUE)          # 04_Research 없음
GOOD <- file.path(T, "good_root"); for (d in c("02_Infrastructure", "04_Research/strategies", "06_Registry")) dir.create(file.path(GOOD, d), recursive = TRUE)
OTHER <- file.path(T, "other_root"); for (d in c("02_Infrastructure", "04_Research/strategies")) dir.create(file.path(OTHER, d), recursive = TRUE)
EMPTY <- file.path(T, "empty.Renviron"); writeLines(character(0), EMPTY)
snap <- function() list(root = sort(list.files(file.path(ROOT, "04_Research/strategies"))),
                        cat = if (file.exists(file.path(ROOT, "06_Registry/module_catalog.json"))) unname(tools::md5sum(file.path(ROOT, "06_Registry/module_catalog.json"))) else "absent")
S0 <- snap()
RSCRIPT <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

#' 자식 Rscript — rm_path 를 source 하고 .RM_ROOT()·MODULE_CATALOG_PATH 를 찍는다. env = 이름 있는 벡터(NA = 해제). 반환 list(rc, out)
child <- function(rm_path, env, cwd = T, project_root = NULL) {
  f <- file.path(T, sprintf("child_%d.R", sample.int(1e6, 1)))
  writeLines(c(if (!is.null(project_root)) sprintf('PROJECT_ROOT <- "%s"', project_root),
               sprintf('r <- tryCatch({ source("%s", encoding = "UTF-8"); cat("ROOT=", .RM_ROOT(), "\\n", sep = ""); cat("CAT=", MODULE_CATALOG_PATH, "\\n", sep = ""); 0L },', rm_path),
               '  error = function(e) { cat("STOP=", conditionMessage(e), "\\n", sep = ""); 3L })', 'quit(status = r)'), f)
  keys <- c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER")
  old <- Sys.getenv(keys, unset = NA_character_, names = TRUE)
  on.exit({ for (k in keys) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)) }, add = TRUE)
  env <- c(env, R_ENVIRON_USER = EMPTY)
  for (k in names(env)) if (is.na(env[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(env[[k]]), k))
  owd <- setwd(cwd); on.exit(setwd(owd), add = TRUE)
  out <- suppressWarnings(system2(RSCRIPT, c("--no-environ", shQuote(f)), stdout = TRUE, stderr = TRUE))
  list(rc = as.integer(attr(out, "status") %||% 0L), out = paste(out, collapse = "\n"))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
# 자식 출력의 'ROOT=' **줄**만 본다(STOP 메시지 안의 'QM_ROOT=' 를 집지 않게 — 줄 머리 일치)
out_lines <- function(x) strsplit(x, "\n", fixed = TRUE)[[1]]
has_root <- function(x) any(startsWith(out_lines(x), "ROOT="))
root_of <- function(r) { l <- out_lines(r$out); l <- l[startsWith(l, "ROOT=")]; if (length(l)) sub("^ROOT=", "", l[1]) else character(0) }
same <- function(a, b) length(a) == 1L && identical(tolower(normalizePath(a, winslash = "/", mustWork = FALSE)), tolower(normalizePath(b, winslash = "/", mustWork = FALSE)))

cat("=== C. .RM_ROOT() 루트 해석 ===\n")
c1 <- child(RM, c(QM_ROOT = BAD, CLAUDE_PROJECT_DIR = BAD), cwd = BAD)
chk(c1$rc != 0L && grepl("STOP=", c1$out) && grepl("04_Research", c1$out) && !has_root(c1$out) && !dir.exists(file.path(BAD, "04_Research")),
    "C1 [주입] QM_ROOT·CLAUDE_PROJECT_DIR = 04_Research 없는 루트 → source 단계 stop · 다른 루트로 폴백 없음 · 쓰기 0", c1$out)
c2 <- child(RM, c(QM_ROOT = BAD, CLAUDE_PROJECT_DIR = GOOD), cwd = GOOD)
chk(c2$rc != 0L && grepl("QM_ROOT", c2$out) && !has_root(c2$out),
    "C2 [주입] QM_ROOT 미충족 + CLAUDE_PROJECT_DIR 충족 → stop(데이터 루트 정본 QM_ROOT — CPD 로 새지 않는다)", c2$out)
c3 <- child(RM, c(QM_ROOT = GOOD, CLAUDE_PROJECT_DIR = OTHER), cwd = OTHER)
chk(c3$rc == 0L && same(root_of(c3), GOOD) && grepl("CLAUDE_PROJECT_DIR", c3$out),
    "C3 [양성] QM_ROOT 충족 · CLAUDE_PROJECT_DIR 다른 루트 → QM_ROOT 사용 + 알림 1줄", c3$out)
c3b <- child(RM, c(QM_ROOT = NA, CLAUDE_PROJECT_DIR = GOOD), cwd = OTHER)
chk(c3b$rc == 0L && same(root_of(c3b), GOOD), "C3b [양성] QM_ROOT 없음 · CLAUDE_PROJECT_DIR 충족 → CLAUDE_PROJECT_DIR", c3b$out)
c3c <- child(RM, c(QM_ROOT = NA, CLAUDE_PROJECT_DIR = BAD), cwd = GOOD)
chk(c3c$rc != 0L && grepl("CLAUDE_PROJECT_DIR", c3c$out) && !has_root(c3c$out),
    "C3c [주입] QM_ROOT 없음 · CLAUDE_PROJECT_DIR 미충족 → stop(작업 디렉터리가 충족이어도 폴백 없음)", c3c$out)
c4 <- child(RM, c(QM_ROOT = NA, CLAUDE_PROJECT_DIR = NA), cwd = GOOD)
chk(c4$rc == 0L && same(root_of(c4), GOOD), "C4 [양성] 둘 다 미설정 → 구판 폴백(getwd = 충족 루트) 그대로", c4$out)
c5 <- child(RM, c(QM_ROOT = OTHER, CLAUDE_PROJECT_DIR = BAD), cwd = BAD, project_root = GOOD)
chk(c5$rc == 0L && same(root_of(c5), GOOD), "C5 [양성] QM_ROOT 충족 + PROJECT_ROOT 전역 → PROJECT_ROOT 그대로(검사 샌드박스 경로 불변)", c5$out)
c5b <- child(RM, c(QM_ROOT = NA, CLAUDE_PROJECT_DIR = BAD), cwd = BAD, project_root = GOOD)
chk(c5b$rc == 0L && same(root_of(c5b), GOOD), "C5b [양성] QM_ROOT 없음 + PROJECT_ROOT 전역 → PROJECT_ROOT 그대로(구판과 같다)", c5b$out)
# ★수리 2판 — 적대검증 ① 우회: QM_ROOT 가 없는 경로(오타)면 config.R 이 운영 리터럴로 PROJECT_ROOT 를 세운다. GOOD = '운영' 대역.
NOPE <- file.path(T, "no_such_root")
c6 <- child(RM, c(QM_ROOT = NOPE, CLAUDE_PROJECT_DIR = NA), cwd = GOOD, project_root = GOOD)
chk(c6$rc != 0L && grepl("QM_ROOT", c6$out) && !has_root(c6$out),
    "C6 [주입] QM_ROOT = 없는 경로 + PROJECT_ROOT 전역('운영' 대역) → stop(PROJECT_ROOT 로 새지 않는다)", c6$out)
c6q <- child(RM, c(QM_ROOT = BAD, CLAUDE_PROJECT_DIR = NA), cwd = GOOD, project_root = GOOD)
chk(c6q$rc != 0L && !has_root(c6q$out), "C6q [주입] QM_ROOT = 요건 미충족 + PROJECT_ROOT 전역 → stop", c6q$out)
# C6b 실경로 — config.R 의 루트 해석 식(rm(.root_candidates) 까지 · 쓰기 없음)을 먼저 평가한 뒤 source. 운영 리터럴은 GOOD 로 바꿔 둔다.
CFG <- file.path(ROOT, "02_Infrastructure/config.R")
cfg_child <- function(rm_path, env) {
  ex <- parse(CFG, keep.source = FALSE, encoding = "UTF-8")
  k <- which(vapply(ex, function(e) grepl("^rm\\(\\.root_candidates", paste(deparse(e), collapse = "")), logical(1)))[1]
  lines <- vapply(ex[seq_len(k)], function(e) paste(deparse(e, width.cutoff = 500L), collapse = "\n"), character(1))
  lines <- gsub("C:/Users/99922/OneDrive/Quant_Module_Moltbot", GOOD, lines, fixed = TRUE)
  lines <- gsub("/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot", GOOD, lines, fixed = TRUE)
  f <- file.path(T, sprintf("cfgpre_%d.R", sample.int(1e6, 1))); writeLines(c(lines, 'cat("CFG_PROJECT_ROOT=", PROJECT_ROOT, "\\n", sep = "")'), f)
  pr <- sprintf('source("%s")', f)
  g <- file.path(T, sprintf("child_cfg_%d.R", sample.int(1e6, 1)))
  writeLines(c(pr, sprintf('r <- tryCatch({ source("%s", encoding = "UTF-8"); cat("ROOT=", .RM_ROOT(), "\\n", sep = ""); 0L },', rm_path),
               '  error = function(e) { cat("STOP=", conditionMessage(e), "\\n", sep = ""); 3L })', 'quit(status = r)'), g)
  keys <- c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER"); old <- Sys.getenv(keys, unset = NA_character_, names = TRUE)
  on.exit({ for (kk in keys) if (is.na(old[[kk]])) Sys.unsetenv(kk) else do.call(Sys.setenv, stats::setNames(list(old[[kk]]), kk)) }, add = TRUE)
  env <- c(env, R_ENVIRON_USER = EMPTY)
  for (kk in names(env)) if (is.na(env[[kk]])) Sys.unsetenv(kk) else do.call(Sys.setenv, stats::setNames(list(env[[kk]]), kk))
  owd <- setwd(T); on.exit(setwd(owd), add = TRUE)
  out <- suppressWarnings(system2(RSCRIPT, c("--no-environ", shQuote(g)), stdout = TRUE, stderr = TRUE))
  list(rc = as.integer(attr(out, "status") %||% 0L), out = paste(out, collapse = "\n"))
}
if (!file.exists(CFG)) ng("C6b config.R 부재", CFG) else {
  c6b <- cfg_child(RM, c(QM_ROOT = NOPE, CLAUDE_PROJECT_DIR = NA))
  chk(c6b$rc != 0L && grepl(paste0("CFG_PROJECT_ROOT=", GOOD), c6b$out, fixed = TRUE) && !has_root(c6b$out),
      "C6b [주입·실경로] QM_ROOT 오타 → config.R 이 PROJECT_ROOT = 운영 리터럴('운영' 대역)로 폴백 → register_module source 단계 stop", c6b$out)
  c6c <- cfg_child(RM, c(QM_ROOT = GOOD, CLAUDE_PROJECT_DIR = NA))
  chk(c6c$rc == 0L && same(root_of(c6c), GOOD), "C6c [양성·실경로] QM_ROOT 충족 → config.R PROJECT_ROOT = QM_ROOT → 그대로", c6c$out)
}

cat("\n=== M. 돌연변이 — 구판 .RM_ROOT() ===\n")
src <- readLines(RM, warn = FALSE, encoding = "UTF-8")
i0 <- grep("^\\.RM_ROOT <- function\\(\\) \\{", src); i1 <- if (length(i0)) i0 + which(src[(i0 + 1L):length(src)] == "}")[1] else NA
if (length(i0) != 1L || is.na(i1)) ng("M1 돌연변이 적용(.RM_ROOT 정의 위치)", "정의 없음") else {
  OLD <- c('.RM_ROOT <- function() {', '  if (exists("PROJECT_ROOT")) return(get("PROJECT_ROOT"))',
           '  cand <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""), getwd(),',
           sprintf('            "%s", "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot")', GOOD),
           '  for (p in cand[nzchar(cand)]) { p <- normalizePath(p, winslash = "/", mustWork = FALSE)',
           '    if (dir.exists(file.path(p, "02_Infrastructure")) && dir.exists(file.path(p, "04_Research"))) return(p) }',
           '  stop("[register_module] project root not found.") }')
  # ★구판의 운영 리터럴 자리는 GOOD(가짜 '운영')로 바꿔 둔다 — 돌연변이 실행도 진짜 운영 경로를 루트로 쥐지 않게.
  MUT <- file.path(T, "register_module_mut.R"); writeLines(c(src[seq_len(i0 - 1L)], OLD, src[(i1 + 1L):length(src)]), MUT, useBytes = TRUE)
  m1 <- child(MUT, c(QM_ROOT = BAD, CLAUDE_PROJECT_DIR = BAD), cwd = BAD)
  chk(m1$rc == 0L && same(root_of(m1), GOOD),
      "M1 [돌연변이] 구판 .RM_ROOT 사본 → C1 조건에서 설정 루트 밖('운영' 대역 GOOD)으로 샌다 = C1 이 잡는다(사고 재현)", m1$out)
}
# M2 — 수리 2판 ⓪(QM_ROOT 요건 검사가 PROJECT_ROOT 앞)을 끈 사본 → C6b 실경로에서 '운영' 대역으로 샌다
m2src <- sub("if (nzchar(qm) && !okp(nrm(qm)))", "if (FALSE)", paste(src, collapse = "\n"), fixed = TRUE)
if (identical(m2src, paste(src, collapse = "\n")) || !file.exists(CFG)) ng("M2 돌연변이 적용(⓪ 검사 줄)", "치환 대상 없음 — 수리 2판 이전 판") else {
  MUT2 <- file.path(T, "register_module_mut2.R"); writeLines(m2src, MUT2, useBytes = TRUE)
  m2 <- cfg_child(MUT2, c(QM_ROOT = NOPE, CLAUDE_PROJECT_DIR = NA))
  chk(m2$rc == 0L && same(root_of(m2), GOOD),
      "M2 [돌연변이] ⓪ 제거 사본 → QM_ROOT 오타 + config.R 폴백 PROJECT_ROOT 로 '운영' 대역에 샌다 = C6b 가 잡는다(적대검증 재현)", m2$out)
}

cat("\n=== Z. 원천 무접촉 ===\n")
S1 <- snap()
chk(identical(S0, S1), "Z1 루트 04_Research/strategies 목록 · module_catalog.json md5 불변")
unlink(T, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"register_module_root_failclosed","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
