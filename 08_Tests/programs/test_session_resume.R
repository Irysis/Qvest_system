## test_session_resume.R — 세션 재개 저널(programs/session_resume.py · 부팅 Resume 줄 · 2026-10-15) — 임시 상태 파일로만(운영 저널 무접촉)
##   ① 시작 · 단계 · 다음 · 결정 · 종료 왕복 ② 중복 id · 상태 어휘 밖 거부(위반 주입) ③ 깨진 상태 파일 → 부팅 줄 '?(…)'(0 으로 접지 않음 · 크래시 없음)
##   ④ 원자적 교체(임시 파일 잔재 0) ⑤ 부팅 배선(boot_lean.sh 가 도구의 boot_line 을 불러 7번째 줄로 · 실패 대체 줄 포함)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
PY <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"); if (!file.exists(PY)) PY <- Sys.which("python")
TOOL <- file.path(ROOT, "02_Infrastructure/programs/session_resume.py")
TMP <- normalizePath(tempfile("sr_"), winslash = "/", mustWork = FALSE); dir.create(TMP)
ST <- file.path(TMP, "session_resume.json")
Sys.setenv(QVEST_SESSION_RESUME_PATH = ST, PYTHONUTF8 = "1")   # Windows 의 system2(env=) 는 동작하지 않는다 — 프로세스 환경으로 넘긴다
run <- function(...) {
  out <- suppressWarnings(system2(PY, c("-X", "utf8", shQuote(TOOL), ...), stdout = TRUE, stderr = TRUE))
  list(out = out, rc = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}
r <- run("begin", "--id", "OP-T1", "--title", shQuote("검사 작업"), "--goal", shQuote("목표"), "--step", shQuote("S1=첫 단계"),
         "--step", shQuote("S2=둘째 단계"), "--context", "a.md", "--next", shQuote("S1 을 실행"))
chk("① begin rc 0 · 상태 파일 생성", r$rc == 0L && file.exists(ST), paste(r$out, collapse = " | "))
r <- run("begin", "--id", "OP-T1", "--title", "중복")
chk("② 중복 id 거부(위반 주입)", r$rc != 0L)
r <- run("step", "--id", "OP-T1", "--step", "S1", "--status", "weird")
chk("② 상태 어휘 밖 거부(위반 주입)", r$rc != 0L)
r <- run("step", "--id", "OP-T1", "--step", "S1", "--status", "done", "--note", shQuote("완료 메모"), "--artifact", "x.json")
r2 <- run("step", "--id", "OP-T1", "--step", "S2", "--status", "in_progress")
r3 <- run("next", "--id", "OP-T1", "--text", shQuote("S2 측정 띄우기"))
r4 <- run("bg", "--id", "OP-T1", "--what", "pipeline", "--log", "p.log", "--sentinel", "s.done")
r5 <- run("decide", "--id", "OP-T1", "--text", shQuote("P0 안건"))
chk("① step · next · bg · decide rc 0", all(c(r$rc, r2$rc, r3$rc, r4$rc, r5$rc) == 0L))
d <- jsonlite::fromJSON(ST, simplifyVector = FALSE)
o <- d$operations[[1]]
chk("① 저장 내용 — 단계 상태 · 산출물 · 다음 · 백그라운드 · 결정",
    identical(o$steps[[1]]$status, "done") && identical(o$steps[[2]]$status, "in_progress") && identical(unlist(o$steps[[1]]$artifacts), "x.json") &&
      identical(o$next_action, "S2 측정 띄우기") && identical(o$background[[1]]$sentinel, "s.done") && identical(unlist(o$decisions), "P0 안건"))
bl <- run("boot-line")$out
chk("① 부팅 줄 — id · 단계 1/2 · 현재 단계 · 다음", length(bl) == 1L && grepl("OP-T1", bl) && grepl("단계 1/2", bl, fixed = TRUE) &&
      grepl("둘째 단계", bl, fixed = TRUE) && grepl("S2 측정 띄우기", bl, fixed = TRUE), paste(bl, collapse = " | "))
sh <- paste(run("show")$out, collapse = "\n")
chk("① 재개 브리핑 — 다음 할 일 · 먼저 읽을 것 · 결정 대기", grepl("S2 측정 띄우기", sh, fixed = TRUE) && grepl("a.md", sh, fixed = TRUE) && grepl("P0 안건", sh, fixed = TRUE))
r <- run("done", "--id", "OP-T1", "--outcome", shQuote("끝"))
d <- jsonlite::fromJSON(ST, simplifyVector = FALSE)
chk("① done → 진행 목록에서 빠지고 이력에 남는다", r$rc == 0L && length(d$operations) == 0L && identical(d$history[[1]]$id, "OP-T1"))
chk("① 종료 뒤 부팅 줄 = 진행 중 작업 없음", startsWith(run("boot-line")$out[1], "Resume: 진행 중 작업 없음"))
chk("④ 원자적 교체 — 임시 파일 잔재 0", !length(list.files(TMP, pattern = "^\\.session_resume_.*\\.tmp$", all.files = TRUE)))
writeLines("{not json", ST)
bl <- run("boot-line")
chk("③ 깨진 상태 파일 → 부팅 줄 '?(…)' · rc 0(부팅 계속)", bl$rc == 0L && grepl("^Resume: \\?\\(", bl$out[1]), paste(bl$out, collapse = " | "))
B <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/boot_lean.sh"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("⑤ 부팅 배선 — RESUME() 가 도구의 boot_line 을 불러 o.append", grepl("def RESUME():", B, fixed = TRUE) && grepl("_m.boot_line(P)", B, fixed = TRUE) &&
      grepl('o.append(S(RESUME,"Resume: ?(표시 예외)"))', B, fixed = TRUE))
chk("⑤ 부팅 실패 대체 줄에 Resume 포함", grepl("Programs: ?\\nResume: ?\\n'", B, fixed = TRUE))
Sys.unsetenv("QVEST_SESSION_RESUME_PATH"); unlink(TMP, recursive = TRUE)
cat(sprintf("\n== session_resume: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"session_resume","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
