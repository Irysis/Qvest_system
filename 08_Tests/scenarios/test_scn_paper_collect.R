## test_scn_paper_collect.R — 감사 레인 C 시나리오: 수집 알림 · 라우팅 → 프로그램 재료 큐
## 격리: tempdir 만 쓴다(운영 stage_artifacts · 등록부 무접촉). 네트워크 · 텔레그램 · claude 호출 없음.
##   C1 죽은 기관 링크 — 처음 1회만 소식 · 같은 집합 반복 = 무음 · 되살아나면 집합에서 빠지고 다시 죽으면 다시 소식
##   C2 돌연변이(새로 죽은 것 판정 → 전부)로 바꾸면 C1 반복 무음이 깨진다(발화 실증)
##   C3 program_paper_sync — 깨진 route 파일 · v4 파일이 섞여도 v5 항목만 모은다(조용한 0 아님)
##   C6 arXiv 질의 전부 실패 — lookback 7 소진 뒤 Python 이 mcp_ok_no_candidates 를 내도 실패 상태로 강등 · 마커 1개
##   C7 죽은 링크 알린 집합 — 발송 성공 뒤에만 저장(발송 실패 · --no-telegram 이면 다음 실행이 다시 알린다 · 모의 발송기)
##   C4 (특성 고정) 같은 논문이 뒤 실행에서 엔진이 바뀌어도 프로그램 큐 항목은 처음 판정 그대로 — 알려진 한계(패치 제안 P-C4)
suppressPackageStartupMessages({ library(jsonlite) })
.self <- function() { a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)]); if (length(f)) dirname(f[1]) else "." }
ROOT <- dirname(dirname(.self()))
if (!file.exists(file.path(ROOT, "02_Infrastructure/tools/paper_recharge_dead_links.R"))) ROOT <- Sys.getenv("QM_ROOT")
stopifnot(file.exists(file.path(ROOT, "02_Infrastructure/tools/paper_recharge_dead_links.R")))
PASS <- 0L; FAIL <- 0L
chk <- function(n, ok, d = "") { if (isTRUE(ok)) { PASS <<- PASS + 1L; cat("  [ok]  ", n, "\n") } else { FAIL <<- FAIL + 1L; cat("  [FAIL]", n, d, "\n") } }

dl_src <- file.path(ROOT, "02_Infrastructure/tools/paper_recharge_dead_links.R")
run_c1 <- function(src_file) {
  e <- new.env(); sys.source(src_file, envir = e)
  sp <- tempfile(fileext = ".json")
  r1 <- e$pr_dead_link_news(c("WINTON.pdf", "AQR.pdf"), sp)
  r2 <- e$pr_dead_link_news(c("AQR.pdf", "WINTON.pdf"), sp)
  r3 <- e$pr_dead_link_news(c("WINTON.pdf"), sp)              # AQR 되살아남
  r4 <- e$pr_dead_link_news(c("WINTON.pdf", "AQR.pdf"), sp)   # AQR 다시 죽음
  r5 <- e$pr_dead_link_news(character(0), sp)
  r6 <- e$pr_dead_link_news(c("X.pdf"), sp, write = FALSE)
  r7 <- e$pr_dead_link_news(c("X.pdf"), sp)
  list(r1 = r1, r2 = r2, r3 = r3, r4 = r4, r5 = r5, r6 = r6, r7 = r7)
}
c1 <- run_c1(dl_src)
chk("C1a 처음 본 죽은 링크 2개 = 소식", isTRUE(c1$r1$news) && length(c1$r1$new_dead) == 2L)
chk("C1b 같은 집합(순서만 다름) 반복 = 무음", identical(c1$r2$news, FALSE))
chk("C1c 하나 되살아남 = 무음 · 알린 집합에서 빠짐", identical(c1$r3$news, FALSE) && identical(c1$r3$alerted, "WINTON.pdf"))
chk("C1d 되살아난 링크가 다시 죽음 = 소식(그 1개만)", isTRUE(c1$r4$news) && identical(c1$r4$new_dead, "AQR.pdf"))
chk("C1e 전부 정상 = 무음", identical(c1$r5$news, FALSE))
chk("C1f dry-run(write=FALSE)은 상태를 안 바꾼다 → 다음 실제 실행도 소식", isTRUE(c1$r6$news) && isTRUE(c1$r7$news))

## C2 돌연변이 — 소스 텍스트 치환
src <- readLines(dl_src, warn = FALSE, encoding = "UTF-8")
mut <- sub("new_dead <- setdiff(dead, prev)", "new_dead <- dead", src, fixed = TRUE)
chk("C2a 치환 성사", sum(mut != src) >= 1L)
mf <- tempfile(fileext = ".R"); writeLines(mut, mf, useBytes = TRUE)
c2 <- run_c1(mf)
chk("C2b 돌연변이 사본에선 반복이 소식이 된다(검사가 수리를 잡는다)", isTRUE(c2$r2$news))

## 본 스크립트 배선 — 판정 함수를 실제로 부르고 발송 조건이 그 결과를 쓴다
main_src <- paste(readLines(file.path(ROOT, "02_Infrastructure/tools/paper_recharge_daily.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("C1g 배선 — paper_recharge_daily.R 이 pr_dead_link_news 를 부르고 발송 조건이 .dead_news 를 쓴다",
    grepl("pr_dead_link_news(", main_src, fixed = TRUE) && grepl("isTRUE(.dead_news)", main_src, fixed = TRUE) &&
      !grepl("|| (n_curated_dead > 0L) ||", main_src, fixed = TRUE))

## C5 arXiv 원천 사망 → 마커 1개(하루 1회) · 정상이면 없음 · 돌연변이로 끄면 잡힌다
arx_block <- function(txt) {
  ex <- parse(text = txt, keep.source = TRUE)
  hit <- Filter(function(e) grepl('^if \\(!grepl\\("\\^mcp_ok"', paste(deparse(e)[1], collapse = "")), as.list(ex))
  if (length(hit)) hit[[1]] else NULL
}
run_c5 <- function(blk, status) {
  pr <- tempfile("c5_"); dir.create(pr)
  e <- new.env()
  e$PROJECT_ROOT <- pr; e$today <- "20261110"; e$dry_run <- FALSE
  e$mcp <- list(status = status, out = file.path(pr, "mcp.json"), candidates = 0L)
  e$relative_path <- function(p) basename(p); e$log_line <- function(...) invisible(NULL)
  e$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  eval(blk, e); eval(blk, e)
  list.files(file.path(pr, ".cache", "scheduler_alerts"), pattern = "\\.alert$")
}
blk <- arx_block(main_src)
chk("C5a 블록 추출", !is.null(blk))
if (!is.null(blk)) {
  m1 <- run_c5(blk, "read_failed(py=python.exe,exit=143,out_exists=FALSE)")
  chk("C5b read_failed → 마커 1개(두 번 불러도 1개)", length(m1) == 1L && grepl("^paper_recharge_arxiv_read_failed_20261110", m1[1]), paste(m1, collapse = ","))
  chk("C5c mcp_ok · mcp_ok_no_candidates · mcp_suspect_empty → 마커 없음",
      length(run_c5(blk, "mcp_ok")) == 0L && length(run_c5(blk, "mcp_ok_no_candidates")) == 0L && length(run_c5(blk, "mcp_suspect_empty")) == 0L)
  mtxt <- sub('if (!grepl("^mcp_ok"', 'if (FALSE && !grepl("^mcp_ok"', main_src, fixed = TRUE)
  chk("C5d 돌연변이 치환 성사", !identical(mtxt, main_src))
  mblk <- parse(text = sub("^if \\(!grepl", "if (FALSE && !grepl", paste(deparse(blk), collapse = "\n")))[[1]]
  chk("C5e 돌연변이 블록에선 read_failed 에도 마커가 없다(검사가 수리를 잡는다)", length(run_c5(mblk, "read_failed(x)")) == 0L)
}

## C6 arXiv 질의 전부 실패 → 7일 lookback 이 소진돼 Python 이 mcp_ok_no_candidates 를 내도 실패로 표식
##   run_mcp_probe 를 본 스크립트에서 떼어 임시 루트에서 돌린다. 가짜 paper_recharge_mcp.py 가 고정 보고서를 --out 에 쓴다.
fn_expr <- function(txt, name) {
  ex <- parse(text = txt, keep.source = FALSE)
  hit <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(name)), as.list(ex))
  if (length(hit)) hit[[1]] else NULL
}
.py_real <- c(file.path(ROOT, ".venv_qvest_ml", "Scripts", "python.exe"), Sys.getenv("QVEST_PY", ""), Sys.which("python"))
.py_real <- .py_real[nzchar(.py_real) & file.exists(.py_real)][1]
fake_py <- c("import sys, shutil, os",
             "a = sys.argv; out = a[a.index('--out') + 1]",
             "shutil.copyfile(os.environ['QVEST_TEST_MCP_FIXTURE'], out)")
run_c6 <- function(txt, report) {
  pr <- tempfile("c6_"); dir.create(file.path(pr, "02_Infrastructure", "tools"), recursive = TRUE)
  sr <- file.path(pr, "stage"); dir.create(sr)
  writeLines(fake_py, file.path(pr, "02_Infrastructure", "tools", "paper_recharge_mcp.py"))
  fx <- file.path(pr, "fixture.json"); writeLines(toJSON(report, auto_unbox = TRUE, null = "null"), fx, useBytes = TRUE)
  old <- Sys.getenv(c("QVEST_PY", "QVEST_TEST_MCP_FIXTURE"), unset = NA)
  Sys.setenv(QVEST_PY = .py_real, QVEST_TEST_MCP_FIXTURE = fx)
  e <- new.env(parent = globalenv())
  e$PROJECT_ROOT <- pr; e$stage_root <- sr; e$today <- "20261110"; e$dry_run <- FALSE
  e$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  e$fromJSON <- jsonlite::fromJSON; e$toJSON <- jsonlite::toJSON
  for (nm in c("pr_mcp_all_queries_failed")) { fe <- fn_expr(txt, nm); if (!is.null(fe)) eval(fe, e) }
  eval(fn_expr(txt, "run_mcp_probe"), e)
  r <- e$run_mcp_probe()
  for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k))
  r
}
qs <- c("cross-sectional momentum", "low volatility anomaly")
rep_allfail <- list(status = "mcp_ok_no_candidates", queries = qs, candidates = list(), candidates_prefilter = 0L,
                    prev_prefilter = 0L, errors = lapply(qs, function(q) list(query = q, response = list(error = "rate limited"))))
rep_partfail <- rep_allfail; rep_partfail$errors <- rep_allfail$errors[1]
rep_ok <- list(status = "mcp_ok", queries = qs, candidates = list(list(title = "t", arxiv_id = "2611.00001")),
               candidates_prefilter = 1L, errors = list())
chk("C6a 파이썬 실행기 확보", !is.na(.py_real), "venv · QVEST_PY · PATH 모두 없음")
if (!is.na(.py_real)) {
  s_all <- run_c6(main_src, rep_allfail)$status
  chk("C6b 질의 전부 실패 + mcp_ok_no_candidates → 실패 상태로 강등(^mcp_ok 아님)", !grepl("^mcp_ok", s_all) && grepl("all_queries_failed", s_all), s_all)
  if (!is.null(blk)) {
    mk6 <- run_c5(blk, s_all)
    chk("C6c 강등된 상태 → 마커 1개(하루 1개)", length(mk6) == 1L && grepl("^paper_recharge_arxiv_mcp_all_queries_failed_20261110", mk6[1]), paste(mk6, collapse = ","))
  }
  s_part <- run_c6(main_src, rep_partfail)$status
  chk("C6d 질의 일부만 실패 = 정상 '신규 없음' 그대로(mcp_ok_no_candidates)", identical(s_part, "mcp_ok_no_candidates"), s_part)
  s_ok <- run_c6(main_src, rep_ok)$status
  chk("C6e 정상 후보 = mcp_ok 그대로", identical(s_ok, "mcp_ok"), s_ok)
  mt6 <- sub("all(qs %in% failed_q)", "FALSE", main_src, fixed = TRUE)
  chk("C6f 돌연변이 치환 성사(전 질의 실패 판정 끔)", !identical(mt6, main_src))
  s_mut <- run_c6(mt6, rep_allfail)$status
  chk("C6g 돌연변이 사본에선 전 질의 실패가 다시 mcp_ok_no_candidates 로 숨는다(검사가 수리를 잡는다)", identical(s_mut, "mcp_ok_no_candidates"), s_mut)
}

## C7 죽은 링크 '알린 집합'은 발송이 실제로 성공한 뒤에만 저장 — 모의 발송기(가짜 telegram_notify.R)로 발송 구간 전체를 돌린다
send_region <- function(txt) {
  ex <- as.list(parse(text = txt, keep.source = FALSE))
  hd <- vapply(ex, function(e) paste(deparse(e, width.cutoff = 500L)[1], collapse = ""), "")
  i0 <- which(startsWith(hd, ".n_new_dl <-"))[1]
  i1 <- which(grepl('^log_line\\("\\[paper-recharge\\] done', hd))[1]
  if (is.na(i0) || is.na(i1) || i1 <= i0) return(NULL)
  ex[i0:(i1 - 1L)]
}
mock_tg <- c("tg_agent_brief <- function(...) {",
             "  f <- Sys.getenv('QVEST_TEST_TG_CALLS'); cat('call\\n', file = f, append = TRUE)",
             "  if (identical(Sys.getenv('QVEST_TEST_TG_OK'), '1')) invisible(list(ok = TRUE)) else invisible(list(ok = FALSE, error = 'mock http_error'))",
             "}")
new_c7_root <- function(dl_file) {
  pr <- tempfile("c7_")
  dir.create(file.path(pr, "02_Infrastructure", "tools"), recursive = TRUE)
  dir.create(file.path(pr, "02_Infrastructure", "telegram"), recursive = TRUE)
  dir.create(file.path(pr, "stage"))
  file.copy(dl_file, file.path(pr, "02_Infrastructure", "tools", "paper_recharge_dead_links.R"))
  writeLines(mock_tg, file.path(pr, "02_Infrastructure", "telegram", "telegram_notify.R"))
  pr
}
run_day <- function(region, pr, dead, tg_ok = TRUE, no_tg = FALSE, dry_run = FALSE, all_files = c("WINTON.pdf", "AQR.pdf")) {
  calls <- file.path(pr, "calls.txt"); if (file.exists(calls)) unlink(calls)
  Sys.setenv(QVEST_TEST_TG_CALLS = calls, QVEST_TEST_TG_OK = if (tg_ok) "1" else "0")
  e <- new.env(parent = globalenv())
  e$PROJECT_ROOT <- pr; e$stage_root <- file.path(pr, "stage"); e$today <- "20261110"
  e$no_tg <- no_tg; e$dry_run <- dry_run
  e$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  e$log_line <- function(...) invisible(NULL)
  e$paper_summary_ko <- function(title, ko = NULL) "요약"
  e$summary_df <- data.frame(status = "already_present", title = "t", provider = "p", summary_ko = "", stringsAsFactors = FALSE)
  e$success_rows <- e$summary_df; e$triage_df <- data.frame()
  e$skip_count <- 0L; e$registry_added_total <- 0L
  e$curated_health <- data.frame(file_name = all_files, ok = !(all_files %in% dead), stringsAsFactors = FALSE)
  e$n_curated <- nrow(e$curated_health); e$n_curated_dead <- sum(!e$curated_health$ok)
  e$mcp <- list(status = "mcp_ok", candidates = 0L, out = "x")
  for (x in region) eval(x, e)
  sp <- file.path(pr, "stage", "curated_dead_alerted.json")
  list(sent = file.exists(calls) && length(readLines(calls)) > 0L,
       alerted = if (file.exists(sp)) sort(as.character(unlist(jsonlite::fromJSON(sp)$alerted))) else NULL)
}
run_c7 <- function(txt, dl_file) {
  reg <- send_region(txt); if (is.null(reg)) return(NULL)
  out <- list()
  p <- new_c7_root(dl_file)   # (a) 발송 실패 → 다음 날 다시 알린다
  out$a1 <- run_day(reg, p, "WINTON.pdf", tg_ok = FALSE); out$a2 <- run_day(reg, p, "WINTON.pdf", tg_ok = TRUE)
  out$a3 <- run_day(reg, p, "WINTON.pdf", tg_ok = TRUE)
  p <- new_c7_root(dl_file)   # (b) --no-telegram 수동 실행은 흡수하지 않는다
  out$b1 <- run_day(reg, p, "WINTON.pdf", no_tg = TRUE); out$b2 <- run_day(reg, p, "WINTON.pdf")
  p <- new_c7_root(dl_file)   # (c) 되살아난 링크는 발송 없는 날에도 집합에서 빠진다 → 다시 죽으면 다시 소식
  out$c1 <- run_day(reg, p, c("WINTON.pdf", "AQR.pdf")); out$c2 <- run_day(reg, p, "WINTON.pdf")
  out$c3 <- run_day(reg, p, c("WINTON.pdf", "AQR.pdf"))
  p <- new_c7_root(dl_file)   # (d) dry-run 은 상태를 안 쓴다
  out$d1 <- run_day(reg, p, "WINTON.pdf", dry_run = TRUE)
  out
}
c7 <- run_c7(main_src, dl_src)
chk("C7a 발송 구간 추출", !is.null(c7))
if (!is.null(c7)) {
  chk("C7b 발송 실패한 날 = 시도는 했고 알린 집합에 안 들어감", isTRUE(c7$a1$sent) && length(c7$a1$alerted) == 0L, paste(c7$a1$alerted, collapse = ","))
  chk("C7c 발송 실패 다음 날 = 같은 죽은 링크를 다시 알린다", isTRUE(c7$a2$sent) && identical(c7$a2$alerted, "WINTON.pdf"))
  chk("C7d 발송 성공 뒤 같은 집합 = 무음(반복 억제 유지)", identical(c7$a3$sent, FALSE))
  chk("C7e --no-telegram 실행은 알린 집합을 늘리지 않는다 → 다음 무인 실행이 알린다", identical(c7$b1$sent, FALSE) && length(c7$b1$alerted) == 0L && isTRUE(c7$b2$sent))
  chk("C7f 되살아남(발송 없음) = 집합에서 빠지고 다시 죽으면 소식", identical(c7$c2$sent, FALSE) && identical(c7$c2$alerted, "WINTON.pdf") && isTRUE(c7$c3$sent))
  chk("C7g dry-run = 상태 파일 없음 · 발송 없음", is.null(c7$d1$alerted) && identical(c7$d1$sent, FALSE))
  mt7 <- sub("delivered = .tg_main_ok", "delivered = TRUE", main_src, fixed = TRUE)
  chk("C7h 돌연변이 치환 성사(발송 성공 여부 무시)", !identical(mt7, main_src))
  c7m <- run_c7(mt7, dl_src)
  chk("C7i 돌연변이 사본에선 발송 실패 다음 날이 무음이 된다(검사가 수리를 잡는다)", !is.null(c7m) && identical(c7m$a2$sent, FALSE))
}

## C3 / C4 program_paper_sync 순수 함수
source(file.path(ROOT, "02_Infrastructure/programs/program_paper_sync.R"))
sd <- file.path(tempfile("pps_"), "stage"); dir.create(sd, recursive = TRUE)
mk <- function(k, eng, v) list(title = k, id = k, paper_key = paste0("axv:", k), source = "arxiv", engine = eng, verdict = v, reason = "r")
w <- function(n, o) writeLines(if (is.character(o)) o else toJSON(o, auto_unbox = TRUE), file.path(sd, n), useBytes = TRUE)
w("alpha_search_route_20261015.json", list(date = "20261015", schema_version = "paper_router_v5",
  papers = list(mk("2699.1", "return", "testable"), mk("2699.2", "defense", "data_pipeline_required"))))
w("alpha_search_route_20261016.json", "{ broken")
w("alpha_search_route_20261012.json", list(date = "20261012", schema_version = "paper_router_v4", papers = list(mk("2699.9", "", "testable"))))
w("alpha_search_route_20261017.json", list(date = "20261017", schema_version = "paper_router_v5",
  papers = list(mk("2699.1", "not_relevant", "skip"))))
files <- sort(Sys.glob(file.path(sd, "alpha_search_route_*.json")))
items <- pps_collect(files)
keys <- vapply(items, function(x) x$item$key, "")
chk("C3 깨진 파일 · v4 파일이 섞여도 v5 재료는 모인다", all(c("axv:2699.1", "axv:2699.2") %in% keys) && !("axv:2699.9" %in% keys), paste(keys, collapse = ","))
em <- pps_engine_map(files)
chk("C4 (특성) 엔진 지도는 마지막 판정(NOT_RELEVANT) · 재료 수집은 첫 판정(P1) — 둘이 갈린다(P-C4)",
    identical(unname(em[["2699.1"]]), "NOT_RELEVANT") && "axv:2699.1" %in% keys)

cat(sprintf('{"test":"scn_paper_collect","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
