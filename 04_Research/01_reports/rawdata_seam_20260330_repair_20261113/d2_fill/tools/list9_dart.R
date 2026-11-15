## 남은 목록 행 — DART 목록 API 로 단절일 앞뒤 공시 제목을 본다(키 출력 없음 · 쓰기 없음 · 11-15)
##   사용: Rscript list9_dart.R <Ticker> <시작 YYYYMMDD> <끝 YYYYMMDD> [...]  (세 개씩 반복)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(httr) })
ROOT <- Sys.getenv("QM_ROOT", "G:/OneDrive/Quant_Module_Moltbot")
key <- NULL
for (ln in readLines(file.path(ROOT, ".env"), warn = FALSE)) if (grepl("^DART_API_KEY=", ln)) key <- sub("^DART_API_KEY=", "", trimws(ln))
stopifnot(!is.null(key), nchar(key) >= 10)
cm <- as.data.table(read_parquet(file.path(ROOT, ".cache/dart/corpcode_map.parquet")))
sc <- intersect(c("stock_code", "Ticker", "ticker"), names(cm))[1]; cc <- intersect(c("corp_code", "corpcode"), names(cm))[1]
a <- commandArgs(TRUE); stopifnot(length(a) >= 3L, length(a) %% 3L == 0L)
any_failed <- FALSE
for (k in seq(1L, length(a), by = 3L)) {
  tk <- a[k]; code <- sub("^A", "", tk)
  corp <- cm[get(sc) == code | get(sc) == tk, get(cc)][1]
  cat(sprintf("\n== %s (corp %s) %s ~ %s\n", tk, if (is.na(corp)) "없음" else "있음", a[k + 1L], a[k + 2L]))
  if (is.na(corp)) next
  page <- 1L; got <- 0L; failed <- FALSE
  repeat {
    rr <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json",
                       query = list(crtfc_key = key, corp_code = corp, bgn_de = a[k + 1L], end_de = a[k + 2L], page_no = page, page_count = 100),
                       timeout(30)), error = function(e) NULL)
    Sys.sleep(0.4)
    j <- if (is.null(rr)) NULL else tryCatch(fromJSON(content(rr, "text", encoding = "UTF-8"), flatten = TRUE), error = function(e) NULL)
    if (is.null(j)) { failed <- TRUE; break }
    if (identical(j$status, "013")) break                     # 조회 결과 없음
    if (!identical(j$status, "000")) { cat("  상태", j$status, j$message, "\n"); failed <- TRUE; break }
    L <- as.data.table(j$list); got <- got + nrow(L)
    for (i in seq_len(nrow(L))) cat(sprintf("  %s  %s\n", L$rcept_dt[i], gsub("\\s+", " ", L$report_nm[i])))
    if (page >= as.integer(j$total_page)) break
    page <- page + 1L
  }
  cat(sprintf("  → 공시 %d건%s\n", got, if (failed) " · ★조회 실패(없음과 다름)" else ""))
  any_failed <- any_failed || failed
}
if (any_failed) quit(status = 2L)   # 조회 실패가 하나라도 있으면 0 으로 끝내지 않는다
