## selftest_measurer.R — 측정기 자가 시험을 따로 돌리는 실행기. 실행: Rscript tests/selftest_measurer.R   (QM_ROOT 필요)
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
source(file.path(D, "R", "aif_common.R")); source(file.path(D, "R", "aif_factor_perf.R")); source(file.path(D, "tests", "selftest_measurer_fn.R"))
root <- aif_root(); cfg <- aif_cfg(root)
M <- aif_market(root, cfg); Rx <- aif_rx(M)
out <- aif_selftest_measurer(M, Rx, cfg, root)
quit(status = if (isTRUE(out$all_pass)) 0L else 1L)
