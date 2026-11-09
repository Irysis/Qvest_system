## test_rebuild_factor_subset.R — 부분 재계산 도구(factor_db/rebuild_factor_subset.R)의 달 처분 · 잃은 쓰기 검사
##   (2026-11-10 · FACTOR-DIRECTION-STORAGE-REPAIR-20261109). 11-09 재계산에서 1990-01~03 은 대상 팩터 행이 옛 파일에도 새 산출에도
##   없었는데 도구가 실패로 셌다(부분 산출 비어 있음 → 기록 없음 · 대상 행 0 → 단정 nrow(new) > 0 실패). 진행기 ④ 가 그 달을 다시 할
##   달로 계속 돌려 '실패'로 끝나고 IC · 결합용 뷰를 건너뛸 뻔했다. 수리 = 쓸 것 없는 달은 성공 · written = FALSE · 지금 지문을 기록.
##   S1 쓸 것 없음 2종(부분 산출 비어 있음 · 대상 행 없음 — 옛 대상 행 0) = 성공 기록 · 파일 그대로 · 실패로 세지 않음
##   S2 옛 대상 행이 있는데 새 산출이 비거나 대상 행이 없음 = 실패 · 기록 없음(고친 코드가 팩터를 잃은 경우를 숨기지 않는다)
##   S3 정상 쓰기 = 대상 행만 새 값 · 대상 밖 행 그대로 · 쓴 지문 기록
##   V1 잃은 쓰기 검사 = 다시 할 달이 정확히 실패한 두 달(쓸 것 없는 달 · 쓴 달은 통과)
##   V2 쓸 것 없는 달도 그 뒤 다른 쓰기가 파일을 바꾸면 검사가 잡는다(지문)
##   M1 돌연변이(쓸 것 없음 가지 제거 = 구판) → S1 이 걸린다
##   M2 돌연변이(옛 대상 행 확인 제거 = 너무 너그러움) → S2 · V1 이 걸린다
##   M3 돌연변이(검사의 수정 시각 비교 제거) → V2 가 걸린다
##   합성 자료 · 임시 폴더만 — 도구의 .rfs_load · build_factor_db 를 가짜로 바꿔 실 빌더 · 실 팩터 DB 를 읽지도 쓰지도 않는다.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
TOOL <- file.path(ROOT, "02_Infrastructure/factor_db/rebuild_factor_subset.R")
stopifnot(file.exists(TOOL))
SRC <- paste(readLines(TOOL, encoding = "UTF-8", warn = FALSE), collapse = "\n")
TMP <- gsub("\\\\", "/", tempdir())
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}

## 함수 정의만(명령줄 블록을 잘라낸 소스 텍스트) — 돌연변이는 이 텍스트를 바꾼다
load_tool <- function(src) {
  cut <- regexpr("\nif (sys.nframe() == 0L) {", src, fixed = TRUE)
  if (cut < 0) return(NULL)
  E <- new.env(parent = globalenv())
  ok <- tryCatch({ eval(parse(text = substr(src, 1L, cut), encoding = "UTF-8"), envir = E); TRUE }, error = function(e) FALSE)
  if (!ok || !exists("rebuild_factor_subset", envir = E, inherits = FALSE)) return(NULL)
  E
}
mutant_src <- function(old, new) {
  n <- lengths(regmatches(SRC, gregexpr(old, SRC, fixed = TRUE)))
  if (n != 1L) return(NULL)
  sub(old, new, SRC, fixed = TRUE)
}

rows <- function(d, tick, f, v) data.table(Date = as.Date(d), Ticker = tick, Factor_Name = f, Raw_Value = v, Z_Score = v,
                                           Z_Sector = v, Rank_Pct = 0.5, Coverage = TRUE)
OLD <- list(
  "199001" = rows("1990-01-31", c("A", "B"), "M01_Mom_12_1", c(0.1, 0.2)),                      # 대상 행 0
  "199002" = rows("1990-02-28", c("A", "B"), "M01_Mom_12_1", c(0.1, 0.2)),                      # 대상 행 0
  "199003" = rbind(rows("1990-03-31", c("A", "B"), "Q05_Accrual", c(-0.1, -0.2)),
                   rows("1990-03-31", "A", "M01_Mom_12_1", 0.1)),                               # 대상 행 2
  "199004" = rbind(rows("1990-04-30", c("A", "B"), "Q05_Accrual", c(-0.1, -0.2)),
                   rows("1990-04-30", "A", "M01_Mom_12_1", 0.1)),                               # 대상 행 2
  "199005" = rbind(rows("1990-05-31", c("A", "B"), "Q05_Accrual", c(-0.1, -0.2)),
                   rows("1990-05-31", c("A", "B"), "V08_PSR", c(2, 3)),
                   rows("1990-05-31", c("A", "B"), "M01_Mom_12_1", c(0.1, 0.2))))
fake_build <- function(sig_d, save = FALSE, force = TRUE, modules = NULL) {
  switch(format(sig_d, "%Y%m"),
         "199001" = NULL,                                                   # 부분 산출 비어 있음
         "199002" = rows(sig_d, "A", "V01_BM", 1),                          # 대상 밖 행만
         "199003" = NULL,
         "199004" = rows(sig_d, "A", "V01_BM", 1),
         "199005" = rbind(rows(sig_d, c("A", "B"), "Q05_Accrual", c(-0.15, -0.25)),
                          rows(sig_d, c("A", "B"), "V08_PSR", c(2.5, 3.5)), rows(sig_d, "A", "V01_BM", 1)))
}

run_case <- function(E) {
  d <- gsub("\\\\", "/", tempfile("rfs_test_", tmpdir = TMP))
  fdir <- file.path(d, "factor_db"); dir.create(fdir, recursive = TRUE)
  for (ym in names(OLD)) write_parquet(OLD[[ym]], file.path(fdir, sprintf("factor_db_%s.parquet", ym)))
  E$FACTOR_DB_DIR <- fdir
  E$.rfs_load <- function(root) invisible(NULL)
  E$build_factor_db <- fake_build
  stopifnot(startsWith(E$FACTOR_DB_DIR, TMP))      # 샌드박스 단정 — 쓰기는 임시 폴더 안뿐
  fp <- function(ym) file.path(fdir, sprintf("factor_db_%s.parquet", ym))
  md5_0 <- tools::md5sum(vapply(names(OLD), fp, ""))
  lg <- file.path(d, "log.jsonl")
  out <- list()
  invisible(capture.output(out$r <- suppressWarnings(E$rebuild_factor_subset(root = d, log_path = lg, verbose = FALSE,
                                                                             write_hash = FALSE, allow_concurrent = TRUE))))
  out$recs <- if (file.exists(lg)) lapply(readLines(lg, warn = FALSE), fromJSON, simplifyVector = FALSE) else list()
  out$md5_same <- unname(tools::md5sum(vapply(names(OLD), fp, "")) == md5_0)
  names(out$md5_same) <- names(OLD)
  out$m5 <- as.data.table(read_parquet(fp("199005"), mmap = FALSE))
  invisible(capture.output(out$redo <- E$verify_subset_writes(lg, root = d)))
  Sys.setFileTime(fp("199001"), Sys.time() + 120)  # 그 뒤 다른 쓰기(내용 같고 수정 시각만 다름)
  invisible(capture.output(out$redo2 <- E$verify_subset_writes(lg, root = d)))
  unlink(d, recursive = TRUE)
  out
}
rec_of <- function(o, ym) Filter(function(r) identical(r$ym, ym), o$recs)
s1 <- function(o) {
  a <- rec_of(o, "199001"); b <- rec_of(o, "199002")
  identical(o$r$none, 2L) && length(a) == 1L && length(b) == 1L &&
    all(vapply(c(a, b), function(r) isTRUE(r$ok) && isFALSE(r$written) && isTRUE(r$nothing_to_write) && !is.null(r$written_mtime), TRUE)) &&
    all(o$md5_same[c("199001", "199002")])
}
s2 <- function(o) identical(o$r$bad, 2L) && !length(Filter(function(r) isTRUE(r$ok), c(rec_of(o, "199003"), rec_of(o, "199004")))) &&
  all(o$md5_same[c("199003", "199004")])
s3 <- function(o) {
  m <- o$m5[order(Factor_Name, Ticker)]
  identical(o$r$done, 1L) && isTRUE(all.equal(m[Factor_Name == "Q05_Accrual", Raw_Value], c(-0.15, -0.25))) &&
    isTRUE(all.equal(m[Factor_Name == "V08_PSR", Raw_Value], c(2.5, 3.5))) &&
    isTRUE(all.equal(m[Factor_Name == "M01_Mom_12_1", Raw_Value], c(0.1, 0.2))) && !nrow(m[Factor_Name == "V01_BM"]) &&
    length(rec_of(o, "199005")) == 1L && !is.null(rec_of(o, "199005")[[1]]$written_mtime)
}
v1 <- function(o) identical(sort(o$redo), c("199003", "199004"))
v2 <- function(o) identical(sort(o$redo2), c("199001", "199003", "199004"))

E0 <- load_tool(SRC)
chk("S0 도구 함수 정의 읽기(명령줄 블록 제외)", is.environment(E0))
if (is.environment(E0)) {
  L <- run_case(E0)
  chk("S1 쓸 것 없는 달 2종 = 성공 기록 · written FALSE · 파일 그대로", s1(L), sprintf("none=%s", L$r$none))
  chk("S2 옛 대상 행이 있는데 새 산출에 없음 = 실패 · 기록 없음", s2(L), sprintf("bad=%s", L$r$bad))
  chk("S3 정상 쓰기 = 대상 행만 새 값 · 대상 밖 그대로", s3(L), sprintf("done=%s", L$r$done))
  chk("V1 검사 = 다시 할 달이 실패한 두 달뿐", v1(L), paste(L$redo, collapse = ","))
  chk("V2 쓸 것 없는 달도 뒤에 바뀌면 검사가 잡는다", v2(L), paste(L$redo2, collapse = ","))
}
M1 <- mutant_src("if (n_old_t > 0L) {", "if (TRUE) {")
M2 <- mutant_src("if (n_old_t > 0L) {", "if (FALSE) {")
M3 <- mutant_src("abs(as.numeric(fi$mtime) - r$written_mtime) > 1e-3", "FALSE")
EM <- lapply(list(M1, M2, M3), function(s) if (is.null(s)) NULL else load_tool(s))
chk("M0 돌연변이 3개 치환 성사 · 사본 단독 로드", all(vapply(EM, is.environment, TRUE)))
if (is.environment(EM[[1]])) chk("M1 쓸 것 없음 가지 제거(구판) → S1 이 걸린다", !s1(run_case(EM[[1]])))
if (is.environment(EM[[2]])) { o <- run_case(EM[[2]]); chk("M2 옛 대상 행 확인 제거 → S2 · V1 이 걸린다", !s2(o) && !v1(o)) }
if (is.environment(EM[[3]])) chk("M3 검사 수정 시각 비교 제거 → V2 가 걸린다", !v2(run_case(EM[[3]])))
cat(sprintf("\n[test_rebuild_factor_subset] %d passed, %d failed\n", PASS, FAIL))
cat(sprintf('{"test":"rebuild_factor_subset","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))  # 배터리 요약 줄(run_all_hooks.sh)
if (FAIL > 0L) quit(save = "no", status = 1L)
