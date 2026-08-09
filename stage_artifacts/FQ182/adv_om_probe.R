## FQ-182 적대검증 (other_markets) — STEP 0: 저장소 내 사용 가능한 독립 수익 계열 탐색 (read-only)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[probe] ", fmt, "\n"), ...)); flush.console() }

peek <- function(path) {
  say("=== %s ===", path)
  if (!file.exists(path)) { say("  파일 없음"); return(invisible(NULL)) }
  x <- tryCatch(as.data.table(read_parquet(path)), error = function(e) { say("  read 실패: %s", conditionMessage(e)); NULL })
  if (is.null(x)) return(invisible(NULL))
  say("  행 %d · 열 %d", nrow(x), ncol(x))
  say("  컬럼: %s", paste(names(x), collapse = ", "))
  print(utils::head(x, 3))
  invisible(x)
}

IDX <- peek(".cache/indices.parquet")
KTR <- peek(".cache/ktri_indices.parquet")
FRW <- peek(".cache/fred_macro_wide.parquet")
BM  <- peek(".cache/benchmark.parquet")

if (!is.null(IDX)) {
  cn <- names(IDX)
  say("--- indices.parquet 세부 ---")
  for (c1 in cn) if (is.character(IDX[[c1]]) || is.factor(IDX[[c1]])) {
    u <- unique(as.character(IDX[[c1]])); say("  %s: %d 고유값 -> %s", c1, length(u), paste(utils::head(u, 40), collapse=" | "))
  }
  dtc <- cn[vapply(IDX, function(v) inherits(v, "Date") || inherits(v, "POSIXct"), logical(1))]
  if (length(dtc)) for (c1 in dtc) say("  %s 범위: %s ~ %s", c1, min(IDX[[c1]], na.rm=TRUE), max(IDX[[c1]], na.rm=TRUE))
}
if (!is.null(KTR)) {
  cn <- names(KTR)
  say("--- ktri_indices.parquet 세부 ---")
  for (c1 in cn) if (is.character(KTR[[c1]])) { u <- unique(KTR[[c1]]); say("  %s: %d 고유 -> %s", c1, length(u), paste(utils::head(u,40), collapse=" | ")) }
}
if (!is.null(FRW)) {
  say("--- fred_macro_wide 열 전체 ---")
  say("  %s", paste(names(FRW), collapse = " | "))
  dtc <- names(FRW)[vapply(FRW, function(v) inherits(v, "Date"), logical(1))]
  if (length(dtc)) for (c1 in dtc) say("  %s 범위: %s ~ %s", c1, min(FRW[[c1]], na.rm=TRUE), max(FRW[[c1]], na.rm=TRUE))
}

say("=== krx 인덱스 디렉토리 ===")
for (d in c(".cache/krx/kospi_index", ".cache/krx/kosdaq_index")) {
  f <- list.files(d, recursive = TRUE, full.names = TRUE)
  say("  %s: %d 파일 -> %s", d, length(f), paste(utils::head(basename(f), 6), collapse=" | "))
  if (length(f)) {
    z <- tryCatch(as.data.table(read_parquet(f[1])), error=function(e) NULL)
    if (!is.null(z)) { say("    컬럼: %s · 행 %d", paste(names(z), collapse=", "), nrow(z)); print(utils::head(z,3)) }
  }
}
say("=== 완료 ===")
