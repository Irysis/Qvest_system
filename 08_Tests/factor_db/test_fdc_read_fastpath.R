## test_fdc_read_fastpath.R — load_month_factors v2.5 읽기 fast path(2026-10-15) 결과 동일성 + 팩터×월 파티션 캐시 무효화(양방향)
##   ① 회귀 기준 = 구 읽기 경로(open_dataset→filter→collect / read_parquet 전 열)를 이 파일에 고정해 두고 load_month_factors 최종
##      결과를 identical(속성 포함)로 대조 — 표본 월 × 팩터 집합(단일 · 복수 · 부재 · 중복·빈 이름) + 전 팩터 경로 + 최근접 월 fallback
##   ② 파티션 캐시: cold miss = warm hit = 캐시 비활성(identical) · 양성 대조 = 무효화 키가 일치하는 위조 엔트리를 넣으면 그것이
##      반환된다(hit 경로가 실제로 사용됨)
##   ③ 무효화: 월 파일을 재작성하면(크기·mtime 변화) 새 내용이 반환된다 · 뮤테이션 테스트(무효화 키 검사 제거)는 stale 엔트리를
##      반환해 이 단정에 걸린다
suppressPackageStartupMessages({ library(data.table); library(arrow); library(dplyr) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
CONN <- file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R")
invisible(capture.output(source(CONN)))
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
quiet <- function(expr) { r <- NULL; invisible(capture.output(r <- tryCatch(expr, error = function(e) structure(conditionMessage(e), class = "err")))); r }

## 구 읽기 경로(v2.4 원문 그대로 · 회귀 기준 고정)
.ref_read_month <- function(fpath, req_cols, factor_names = NULL) {
  if (!is.null(factor_names) && length(factor_names)) {
    as.data.table(open_dataset(fpath, format = "parquet") %>% select(all_of(req_cols), any_of("Date")) %>%
                    filter(Factor_Name %in% factor_names) %>% collect())
  } else as.data.table(read_parquet(fpath, col_select = c(all_of(req_cols), any_of("Date"))))
}
LIVE_CACHED <- .fdc_read_month_cached; LIVE_PC_DIR <- .fdc_partcache_dir; LIVE_DB <- FACTOR_DB_DIR
lmf_ref <- function(...) {
  assign(".fdc_read_month_cached", .ref_read_month, envir = globalenv())
  on.exit(assign(".fdc_read_month_cached", LIVE_CACHED, envir = globalenv()))
  quiet(load_month_factors(...))
}
lmf_new <- function(...) quiet(load_month_factors(...))
TMP <- normalizePath(tempfile("fdc_fast_"), winslash = "/", mustWork = FALSE); dir.create(TMP)
assign(".fdc_partcache_dir", function() file.path(TMP, "pc1"), envir = globalenv())   # 운영 캐시 디렉터리를 건드리지 않는다

## ① 회귀 대조 — 표본 월(2000~최신, 등간격 10개월 + 최신 + 파일 없는 월의 최근접 fallback)
fs <- sort(list.files(LIVE_DB, pattern = "^factor_db_\\d{6}\\.parquet$"))
ym <- sub("factor_db_(\\d{6})\\.parquet", "\\1", fs); ym <- ym[ym >= "200001"]
pick <- unique(c(ym[round(seq(1, length(ym), length.out = 10))], ym[length(ym)]))
mend <- function(y) { d <- as.Date(sprintf("%s-%s-01", substr(y, 1, 4), substr(y, 5, 6))); seq(d, by = "1 month", length.out = 2)[2] - 1 }
dates <- c(lapply(pick, mend), list(mend(ym[length(ym)]) + 45))    # 마지막 = 파일 없는 월 → 최근접 fallback
sets <- list(one = "D03_RealVol", two = c("Q08_Composite_Quality", "M01_Mom_12_1"), absent = "ZZ_NOT_A_FACTOR",
             dupe = c("D03_RealVol", "D03_RealVol", ""))
n_cmp <- 0L; bad <- character(0)
for (d in dates) for (sn in names(sets)) {
  a <- lmf_ref(d, factor_names = sets[[sn]]); b <- lmf_new(d, factor_names = sets[[sn]]); n_cmp <- n_cmp + 1L
  if (!identical(a, b)) bad <- c(bad, sprintf("%s/%s", format(d), sn))
}
chk(sprintf("팩터 지정 경로 %d건 — 최종 결과 identical(속성 포함 · stale index 무관)", n_cmp), !length(bad), paste(head(bad, 5), collapse = ","))
n_full <- 0L; bad_f <- character(0)
for (d in dates[c(2, 6, length(dates) - 1L)]) {
  a <- lmf_ref(d); b <- lmf_new(d); n_full <- n_full + 1L
  if (!identical(a, b)) bad_f <- c(bad_f, format(d))
}
chk(sprintf("전 팩터 경로 %d건 — identical", n_full), !length(bad_f), paste(bad_f, collapse = ","))
one <- lmf_new(dates[[6]], factor_names = "D03_RealVol")
chk("반환 스키마 유지 — Ticker·Factor_Name·Z_Score_Aligned + as-of·파일 속성", identical(names(one), c("Ticker", "Factor_Name", "Z_Score_Aligned")) &&
      nrow(one) > 100L && !is.na(attr(one, "factor_db_asof_date")) && grepl("^factor_db_\\d{6}\\.parquet$", attr(one, "factor_db_file")))

## ② · ③ 파티션 캐시 — 임시 DB(월 파일 1개 복사본)
DB2 <- file.path(TMP, "db"); dir.create(DB2)
src <- file.path(LIVE_DB, sprintf("factor_db_%s.parquet", pick[6])); dst <- file.path(DB2, basename(src))
invisible(file.copy(src, dst))
assign("FACTOR_DB_DIR", DB2, envir = globalenv())
assign(".fdc_partcache_dir", function() file.path(TMP, "pc2"), envir = globalenv())   # ①이 쓴 엔트리와 분리
d6 <- dates[[6]]; FN <- "D03_RealVol"; REQ <- c("Ticker", "Factor_Name", "Z_Score", "Coverage")
entry <- file.path(TMP, "pc2", FN, sub("\\.parquet$", ".rds", basename(dst)))
Sys.setenv(QVEST_FDB_PARTCACHE = "0"); r_off <- lmf_new(d6, factor_names = FN)
chk("캐시 비활성 → 엔트리를 쓰지 않는다", !file.exists(entry))
Sys.setenv(QVEST_FDB_PARTCACHE = "1"); r_cold <- lmf_new(d6, factor_names = FN)
chk("cold miss → 엔트리 기록", file.exists(entry))
r_warm <- lmf_new(d6, factor_names = FN)
chk("cold = warm = 비활성 (identical)", identical(r_off, r_cold) && identical(r_cold, r_warm))
chk("읽기 계층도 identical — hit 반환 = 원본 읽기", identical(.fdc_read_month(dst, REQ, FN), .fdc_read_month_cached(dst, REQ, FN)))
## 양성 대조 — 무효화 키가 일치하는 위조 엔트리(Z_Score = 0)면 그것이 반환돼야 한다(hit 경로 실재)
h <- readRDS(entry); h_bak <- h; h$dt$Z_Score <- 0; saveRDS(h, entry)
r_forged <- .fdc_read_month_cached(dst, REQ, FN)
chk("양성 대조 — 키 일치 위조 엔트리가 반환된다(hit 경로 사용)", all(r_forged$Z_Score == 0))
saveRDS(h_bak, entry)
## ③ 무효화 — 월 파일 재작성(D03 Z_Score 부호 반전 · mtime·크기 변화)
Sys.sleep(1.1)
full <- as.data.table(read_parquet(dst, mmap = FALSE)); full[Factor_Name == FN, Z_Score := -Z_Score]
invisible(gc())                                     # 앞선 읽기의 Arrow 버퍼(파일 핸들) 해제 뒤 교체
tmpw <- paste0(dst, ".w"); write_parquet(full, tmpw)
chk("월 파일 교체 성공", file.copy(tmpw, dst, overwrite = TRUE)); unlink(tmpw)
Sys.setenv(QVEST_FDB_PARTCACHE = "0"); r_new_off <- lmf_new(d6, factor_names = FN)
Sys.setenv(QVEST_FDB_PARTCACHE = "1")
r_new_on <- lmf_new(d6, factor_names = FN)
chk("월 파일 재작성 → 캐시가 새 내용을 반환(= 비활성 읽기)", identical(r_new_on, r_new_off))
chk("새 내용이 실제로 달라졌다(테스트가 변화를 관측 가능)", !identical(r_new_on$Z_Score_Aligned, r_cold$Z_Score_Aligned))
## 뮤테이션 테스트 — 무효화 키 검사를 제거한 변이체(소스 텍스트 치환 · 치환 성공 단정)는 stale 엔트리를 반환해야 한다
src_txt <- paste(readLines(CONN, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
m_txt <- sub("identical(hit$ikey, ikey) && ", "", src_txt, fixed = TRUE)
chk("뮤테이션 치환 성공(무효화 키 검사 제거)", !identical(m_txt, src_txt))
## stale 엔트리 복원(재작성 전 내용 · 옛 키) → 변이체는 그것을 반환, 정본은 무시
saveRDS(h_bak, entry)
m_exprs <- parse(text = m_txt, encoding = "UTF-8")
m_def <- m_exprs[vapply(m_exprs, function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                          identical(as.character(e[[2]]), ".fdc_read_month_cached"), logical(1))]
menv <- new.env(parent = globalenv()); eval(m_def[[1]], envir = menv)
r_mut <- menv$.fdc_read_month_cached(dst, REQ, FN)
r_live <- .fdc_read_month_cached(dst, REQ, FN)
chk("변이체(키 검사 제거)는 stale 엔트리 반환 — 무효화 단정이 검출", !identical(r_mut$Z_Score, r_live$Z_Score) &&
      identical(r_live$Z_Score, .fdc_read_month(dst, REQ, FN)$Z_Score))
assign("FACTOR_DB_DIR", LIVE_DB, envir = globalenv()); assign(".fdc_partcache_dir", LIVE_PC_DIR, envir = globalenv())
unlink(TMP, recursive = TRUE)
cat(sprintf("\n== fdc_read_fastpath: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"fdc_read_fastpath","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
