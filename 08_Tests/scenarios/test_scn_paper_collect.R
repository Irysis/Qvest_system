## test_scn_paper_collect.R — 감사 레인 C 시나리오: 수집 알림 · 라우팅 → 프로그램 재료 큐
## 격리: tempdir 만 쓴다(운영 stage_artifacts · 등록부 무접촉). 네트워크 · 텔레그램 · claude 호출 없음.
##   C1 죽은 기관 링크 — 처음 1회만 소식 · 같은 집합 반복 = 무음 · 되살아나면 집합에서 빠지고 다시 죽으면 다시 소식
##   C2 돌연변이(새로 죽은 것 판정 → 전부)로 바꾸면 C1 반복 무음이 깨진다(발화 실증)
##   C3 program_paper_sync — 깨진 route 파일 · v4 파일이 섞여도 v5 항목만 모은다(조용한 0 아님)
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
