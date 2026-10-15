## 팩터×월 파티션 캐시 프리페치(cache warming · 2026-10-15) — 측정 전에 load_month_factors 를 월 파일마다 1회 호출해
##   캐시 엔트리(factor_db_connector.R::.fdc_read_month_cached)를 채운다. 측정 셀은 같은 (팩터, 월 파일) 키로 hit 한다.
##   반환값은 버린다 — 부수효과는 캐시 엔트리(+ IC 방향 캐시)뿐이며, 엔트리 내용은 원본 읽기와 identical(test_fdc_read_fastpath.R).
## 실행: Rscript fdb_partcache_prefetch.R <factor_id> [from_ym=200001]
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
invisible(capture.output(source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))))
a <- commandArgs(trailingOnly = TRUE)
fn <- a[1]; from <- if (length(a) >= 2L) a[2] else "200001"
if (is.na(fn) || !nzchar(fn)) stop("usage: fdb_partcache_prefetch.R <factor_id> [from_ym]")
ym <- sub("factor_db_(\\d{6})\\.parquet", "\\1", list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$"))
ym <- sort(ym[ym >= from])
t0 <- proc.time()[["elapsed"]]; n_ok <- 0L
for (y in ym) {
  d <- as.Date(sprintf("%s-%s-15", substr(y, 1, 4), substr(y, 5, 6)))
  r <- NULL
  invisible(capture.output(r <- tryCatch(load_month_factors(d, factor_names = fn), error = function(e) NULL)))
  if (!is.null(r)) n_ok <- n_ok + 1L
}
cat(sprintf("[prefetch] %s · %d/%d개월 · %.0fs\n", fn, n_ok, length(ym), proc.time()[["elapsed"]] - t0))
