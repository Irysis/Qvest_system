## =============================================================================
## run_all_tests.R — DT_2002_06975 등록 전 리허설 시험 묶음 실행기(CPU 전용 · GPU 미사용 · 실제 데이터 미사용)
##   순서: ① template_diff_check(차분 · RX0S · 매니페스트) ② 차분 검사기 양방향 ③ 규칙 스모크 ④ 정적 PIT ⑤ 공통 난수 사실 · RX0S 양성 대조
##         ⑥ 양성 대조 + 뮤테이션 4종(정답 통과 · 뮤턴트 실패) ⑦ 파이썬 전 경로 ⑧ 엔진 통째 리허설(가짜 루트 · 합성 12개월)
##   --fast = ①~④만(수십 초). 전부 = 약 15~20분(⑥ 약 5분 · ⑦ 약 3분 · ⑧ 약 7분).
##   산출 = tests/_out/test_summary.json(시험별 종료 코드 · 소요 · 시험 시점 파일 md5 — 템플릿 · 생성 7개 · RX0S · 원본 engine.R)
##   종료 코드 0 = 실행한 시험 전부 통과.
## =============================================================================
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
for (p in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""))) if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) { ROOT <- gsub("\\\\", "/", p); break }
DT <- file.path(ROOT, "04_Research/strategies/DT_2002_06975")
PY <- file.path(ROOT, ".venv_qvest_ml", "Scripts", "python.exe")
RS <- file.path(R.home("bin"), "Rscript")
fast <- "--fast" %in% commandArgs(trailingOnly = TRUE)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")                                   # 하위 프로세스 전부 GPU 비가시
dir.create(file.path(DT, "tests", "_out"), recursive = TRUE, showWarnings = FALSE)
md5f <- function(p) unname(as.character(tools::md5sum(p)))
files <- c(file.path(DT, c("engine_template.R", sprintf("engine_%s.R", c("Q50", "V1", "V2", "N1", "N2", "S1", "S2")), "rx0s/engine_RX0S.R",
                           "make_engines.R", "template_diff_check.R")),
           file.path(ROOT, "04_Research/strategies/RP_AUTO_2002_06975/engine.R"))
md5_before <- setNames(vapply(files, md5f, ""), sub(paste0("^", ROOT, "/"), "", files))
TESTS <- list(
  list(id = "template_diff_check", cmd = RS, args = c(shQuote(file.path(DT, "template_diff_check.R")), "--json", shQuote(file.path(DT, "tests/_out/template_diff_check.json")))),
  list(id = "diff_check_mutation", cmd = RS, args = shQuote(file.path(DT, "tests/diff_check_mutation_test.R"))),
  list(id = "rule_smoke",          cmd = RS, args = shQuote(file.path(DT, "tests/rule_smoke_test.R"))),
  list(id = "static_pit",          cmd = RS, args = shQuote(file.path(DT, "tests/static_pit_check.R"))),
  list(id = "rng_stream_facts",    cmd = PY, args = shQuote(file.path(DT, "tests/rng_stream_check.py")), slow = TRUE),
  list(id = "pc_mutation",         cmd = PY, args = c(shQuote(file.path(DT, "tests/pc_mutation_test.py")), "--jobs", "6"), slow = TRUE),
  list(id = "py_e2e",              cmd = PY, args = shQuote(file.path(DT, "tests/py_e2e_test.py")), slow = TRUE),
  list(id = "engine_dryrun",       cmd = RS, args = shQuote(file.path(DT, "tests/engine_dryrun_test.R")), slow = TRUE))
res <- list()
for (t in TESTS) {
  if (fast && isTRUE(t$slow)) { res[[t$id]] <- list(rc = NA_integer_, skipped = TRUE); next }
  lg <- file.path(DT, "tests", "_out", paste0("log_", t$id, ".txt")); t0 <- Sys.time()
  rc <- suppressWarnings(system2(t$cmd, t$args, stdout = lg, stderr = lg))
  secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  last <- tail(readLines(lg, encoding = "UTF-8", warn = FALSE), 1L)
  res[[t$id]] <- list(rc = as.integer(rc), secs = secs, last_line = last, log = basename(lg))
  cat(sprintf("[run_all_tests] %-20s rc %d · %6.1fs · %s\n", t$id, as.integer(rc), secs, substr(last, 1L, 150L)))
}
md5_after <- setNames(vapply(files, md5f, ""), names(md5_before))
ran <- Filter(function(z) !isTRUE(z$skipped), res)
ok <- length(ran) > 0L && all(vapply(ran, function(z) identical(z$rc, 0L), logical(1))) && identical(md5_before, md5_after)
writeLines(toJSON(list(ok = ok, fast = fast, tests = res, files_md5 = as.list(md5_after), files_unchanged_during_tests = identical(md5_before, md5_after),
                       device = "cpu (CUDA_VISIBLE_DEVICES=-1)", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")), auto_unbox = TRUE, pretty = TRUE, na = "null"),
           file.path(DT, "tests", "_out", "test_summary.json"))
cat(sprintf("[run_all_tests] %s — 실행 %d · 통과 %d · 시험 중 파일 md5 불변 %s\n", if (ok) "OK" else "FAIL", length(ran),
            sum(vapply(ran, function(z) identical(z$rc, 0L), logical(1))), identical(md5_before, md5_after)))
quit(status = if (ok) 0L else 1L)
