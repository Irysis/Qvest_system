## test_scn_paper_query_failcheck.R — 전 질의 실패 판정(pr_mcp_all_queries_failed)이 질의별 정렬 호출(질의 × 정렬)에서도 맞는가
##   (도훈 11-10 PAPER-QUERY-AND-ORDER-REDESIGN-20261110 — 표적 질의 10개는 relevance + date 두 번 돈다)
## 격리: 판정 함수 · 마커 블록만 paper_recharge_daily.R 에서 parse 로 떼어 tempdir 에서 돈다. 네트워크 · 수집기 · 텔레그램 없음.
##   F1 50호출 전부 실패 → 강등(n=질의 수, calls=호출 수) · F2 relevance 40 실패 + date 10 성공(0건) → 강등 안 함(질의 이름만 보면 강등됐을 자리)
##   F3 errors · calls 에 sort_by 가 없으면 obj$sort_by 로 보충 · F4 calls 없는 옛 보고서 = 종전 결과 · F5 mcp_ok 그대로
##   F6 강등 상태 → 마커 이름 paper_recharge_arxiv_mcp_all_queries_failed_<D> 1개
##   F7 도중 서버 사망 status(mcp_partial_transport_failure) → 판정 통과 · 마커 1개(침묵 실패 회귀 방지)
##   M  돌연변이 'all(ck %in% fk)' → FALSE(치환 성사 단정)면 F1 이 숨는다 · 종전 리터럴 'all(qs %in% failed_q)' 존재
suppressPackageStartupMessages({ library(jsonlite) })
.self <- function() { a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)]); if (length(f)) dirname(f[1]) else "." }
ROOT <- dirname(dirname(.self()))
if (!file.exists(file.path(ROOT, "02_Infrastructure/tools/paper_recharge_daily.R"))) ROOT <- Sys.getenv("QM_ROOT")
stopifnot(file.exists(file.path(ROOT, "02_Infrastructure/tools/paper_recharge_daily.R")))
PASS <- 0L; FAIL <- 0L
chk <- function(n, ok, d = "") { if (isTRUE(ok)) { PASS <<- PASS + 1L; cat("  [ok]  ", n, "\n") } else { FAIL <<- FAIL + 1L; cat("  [FAIL]", n, d, "\n") } }

main_src <- paste(readLines(file.path(ROOT, "02_Infrastructure/tools/paper_recharge_daily.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
fn_expr <- function(txt, name) {
  ex <- parse(text = txt, keep.source = FALSE)
  hit <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(name)), as.list(ex))
  if (length(hit)) hit[[1]] else NULL
}
load_fn <- function(txt) {
  e <- new.env(parent = globalenv())
  e$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  fe <- fn_expr(txt, "pr_mcp_all_queries_failed"); if (is.null(fe)) return(NULL)
  eval(fe, e); e$pr_mcp_all_queries_failed
}
f <- load_fn(main_src)
chk("F0 판정 함수 추출", is.function(f))

old_q <- sprintf("old query %02d", 1:30); new_q <- sprintf("target query %02d", 1:10); qs <- c(old_q, new_q)
calls <- c(lapply(old_q, function(q) list(query = q, sort_by = "relevance", ok = FALSE)),
           unlist(lapply(new_q, function(q) list(list(query = q, sort_by = "relevance", ok = FALSE), list(query = q, sort_by = "date", ok = FALSE))), recursive = FALSE))
err_of <- function(cl) lapply(cl, function(c) list(query = c$query, sort_by = c$sort_by, response = list(error = "rate limited")))
rep <- function(status = "mcp_ok_no_candidates", calls_ = calls, errors = err_of(calls)) {
  r <- list(status = status, sort_by = "relevance", queries = as.list(qs), errors = errors, candidates = list())
  if (!is.null(calls_)) r$calls <- calls_
  ## JSON 왕복(실제 보고서와 같은 모양으로)
  fromJSON(toJSON(r, auto_unbox = TRUE, null = "null"), simplifyVector = FALSE)
}
if (is.function(f)) {
  s1 <- f(rep())
  chk("F1 50호출 전부 실패 → mcp_all_queries_failed(n=40,calls=50)", identical(s1, "mcp_all_queries_failed(n=40,calls=50)"), s1)
  rel_only <- Filter(function(c) identical(c$sort_by, "relevance"), calls)
  s2 <- f(rep(errors = err_of(rel_only)))
  chk("F2 relevance 40 실패 + date 10 성공(0건) → 강등 안 함(mcp_ok_no_candidates)", identical(s2, "mcp_ok_no_candidates"), s2)
  ## F3 sort_by 결측 → obj$sort_by 보충(옛 생산자 · 부분 기록)
  c3 <- lapply(old_q, function(q) list(query = q))
  e3 <- lapply(old_q, function(q) list(query = q, kind = "text_block_parse_error"))
  r3 <- rep(calls_ = c3, errors = e3); r3$queries <- as.list(old_q)
  s3 <- f(r3)
  chk("F3 sort_by 결측 → obj$sort_by 로 보충해 대조(강등)", identical(s3, "mcp_all_queries_failed(n=30,calls=30)"), s3)
  r3b <- r3; r3b$errors <- lapply(old_q, function(q) list(query = q, sort_by = "date"))
  chk("F3b 정렬이 다른 실패는 그 호출의 실패가 아니다(강등 안 함)", identical(f(r3b), "mcp_ok_no_candidates"), f(r3b))
  ## F4 calls 없는 옛 보고서 = 종전 본문
  r4 <- rep(calls_ = NULL, errors = lapply(qs, function(q) list(query = q, response = list(error = "x"))))
  s4 <- f(r4)
  chk("F4 calls 없는 옛 보고서 전부 실패 = 종전 결과(mcp_all_queries_failed(n=40))", identical(s4, "mcp_all_queries_failed(n=40)"), s4)
  r4b <- r4; r4b$errors <- r4$errors[1:5]
  chk("F4b 옛 보고서 일부 실패 = 그대로", identical(f(r4b), "mcp_ok_no_candidates"))
  chk("F5 mcp_ok · mcp_suspect_empty 는 그대로", identical(f(rep(status = "mcp_ok")), "mcp_ok") && identical(f(rep(status = "mcp_suspect_empty")), "mcp_suspect_empty"))
}

## F6 마커 블록 — 강등 상태가 마커 이름을 바꾸지 않는다
arx_block <- function(txt) {
  ex <- parse(text = txt, keep.source = TRUE)
  hit <- Filter(function(e) grepl('^if \\(!grepl\\("\\^mcp_ok"', paste(deparse(e)[1], collapse = "")), as.list(ex))
  if (length(hit)) hit[[1]] else NULL
}
blk <- arx_block(main_src)
if (!is.null(blk) && is.function(f)) {
  pr <- tempfile("f6_"); dir.create(pr)
  e <- new.env()
  e$PROJECT_ROOT <- pr; e$today <- "20261110"; e$dry_run <- FALSE
  e$mcp <- list(status = f(rep()), out = file.path(pr, "mcp.json"), candidates = 0L)
  e$relative_path <- function(p) basename(p); e$log_line <- function(...) invisible(NULL)
  e$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  eval(blk, e); eval(blk, e)
  mk <- list.files(file.path(pr, ".cache", "scheduler_alerts"), pattern = "\\.alert$")
  chk("F6 강등 상태 → 마커 1개 · 이름 paper_recharge_arxiv_mcp_all_queries_failed_20261110", identical(mk, "paper_recharge_arxiv_mcp_all_queries_failed_20261110.alert"), paste(mk, collapse = ","))
  unlink(pr, recursive = TRUE)
  ## F7 (재수리 11-10) 도중 서버 사망 = 수집기 status 'mcp_partial_transport_failure(skipped=k/n)' — 판정 함수는 그대로 통과시키고
  ##    마커 조건(^mcp_ok 제외)이 서서 마커 1개(이름 = 괄호 앞 · 소문자 영문 · _ 만). 후보가 있어도(부분 수확) 경보는 선다.
  st7 <- "mcp_partial_transport_failure(skipped=43/50)"
  pr7 <- tempfile("f7_"); dir.create(pr7)
  e7 <- new.env()
  e7$PROJECT_ROOT <- pr7; e7$today <- "20261110"; e7$dry_run <- FALSE
  e7$mcp <- list(status = f(rep(status = st7)), out = file.path(pr7, "mcp.json"), candidates = 12L)
  e7$relative_path <- function(p) basename(p); e7$log_line <- function(...) invisible(NULL)
  e7$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  eval(blk, e7)
  mk7 <- list.files(file.path(pr7, ".cache", "scheduler_alerts"), pattern = "\\.alert$")
  chk("F7 도중 사망 status 는 판정 함수를 그대로 통과 · 마커 paper_recharge_arxiv_mcp_partial_transport_failure_20261110 1개",
      identical(e7$mcp$status, st7) && identical(mk7, "paper_recharge_arxiv_mcp_partial_transport_failure_20261110.alert"),
      paste(e7$mcp$status, paste(mk7, collapse = ",")))
  unlink(pr7, recursive = TRUE)
} else chk("F6 마커 블록 추출", FALSE)

## M 돌연변이
chk("M0 종전 리터럴 'all(qs %in% failed_q)' 보존(옛 보고서 경로 · test_scn_paper_collect C6f 치환 대상)", grepl("all(qs %in% failed_q)", main_src, fixed = TRUE))
mt <- sub("all(ck %in% fk)", "FALSE", main_src, fixed = TRUE)
chk("M1 돌연변이 치환 성사(호출 단위 판정 끔)", !identical(mt, main_src))
fm <- load_fn(mt)
chk("M2 돌연변이 사본에선 50호출 전부 실패가 mcp_ok_no_candidates 로 숨는다(검사가 수리를 잡는다)", is.function(fm) && identical(fm(rep()), "mcp_ok_no_candidates"), if (is.function(fm)) fm(rep()) else "추출 실패")

cat(sprintf('{"test":"scn_paper_query_failcheck","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
