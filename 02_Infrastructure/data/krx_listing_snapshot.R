# ==============================================================================
# krx_listing_snapshot.R — KRX Open API 종목기본정보(KOSPI · KOSDAQ) 하루치 스냅숏
#
# 왜: 퀀티 질의서의 종목 목록(DATA_Key)은 사람이 손으로 붙여 왔다. 그 결과 2026-11-06 기준
#     OHLCVS 목록(3,717)에도 상장 보통주 45종(케이뱅크 · 한화머시너리앤서비스홀딩스 포함)이 없고,
#     나머지 3개 DB(3,668)은 53종이 더 빠져 위생 표식이 NA 였다(PLAN F7). 신규 상장을 놓치지 않으려면
#     '지금 상장된 종목'의 공식 목록이 매일 있어야 한다 — 그 원천이 이 스냅숏이다.
#     (04_Research/01_reports/quantiwise_data_expansion_20261106/BUILD_20261108.md §1)
#
# 사용: cd 02_Infrastructure && Rscript data/krx_listing_snapshot.R [YYYYMMDD]
#       날짜 생략 = .cache/benchmark.parquet 최신일(퀀티 드라이버 Get-Target 과 같은 기준일).
# 출력: .cache/krx/stk_info/stk_info_<d>.parquet · .cache/krx/ksq_info/ksq_info_<d>.parquet
#       (krx_collect_daily() 와 같은 폴더 · 같은 이름 · 같은 열 + Date — 기존 소비자와 호환)
# 종료 코드: 0 저장 · 2 응답 없음(휴장 · API 지연) · 1 오류
# ==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

args <- commandArgs(trailingOnly = TRUE)
main <- function() {
  source("data/krx_data_collector.R")   # PROJECT_ROOT · KRX_CACHE_DIR · krx_stk_info() · krx_ksq_info()
  d <- if (length(args) >= 1 && nzchar(args[1])) args[1] else {
    bp <- file.path(PROJECT_ROOT, ".cache", "benchmark.parquet")
    if (!file.exists(bp)) stop("benchmark.parquet 부재 — 날짜를 인자로 주세요")
    format(max(as.Date(read_parquet(bp, col_select = "Date")$Date)), "%Y%m%d")
  }
  if (!grepl("^\\d{8}$", d)) stop("날짜 형식 오류(YYYYMMDD): ", d)
  stk <- krx_stk_info(d); ksq <- krx_ksq_info(d)
  n_stk <- if (is.null(stk)) 0L else nrow(stk); n_ksq <- if (is.null(ksq)) 0L else nrow(ksq)
  cat(sprintf("[krx_listing_snapshot] %s KOSPI %d · KOSDAQ %d\n", d, n_stk, n_ksq))
  if (n_stk == 0L || n_ksq == 0L) {
    cat("[krx_listing_snapshot] 한쪽 시장 응답 없음 — 저장하지 않음(휴장 · API 지연)\n")
    return(2L)
  }
  for (nm in c("stk_info", "ksq_info")) {
    x <- if (nm == "stk_info") stk else ksq
    x[, Date := d]
    out_dir <- file.path(KRX_CACHE_DIR, nm)
    if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
    out <- file.path(out_dir, sprintf("%s_%s.parquet", nm, d))
    tmp <- paste0(out, ".tmp")
    write_parquet(x, tmp)
    if (!file.rename(tmp, out)) { file.copy(tmp, out, overwrite = TRUE); unlink(tmp) }
    cat(sprintf("  saved %s (%d rows)\n", out, nrow(x)))
  }
  0L
}
rc <- tryCatch(main(), error = function(e) { cat("[krx_listing_snapshot] ERROR:", conditionMessage(e), "\n"); 1L })
quit(save = "no", status = rc)
