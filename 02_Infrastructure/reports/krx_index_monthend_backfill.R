##=============================================================================
## krx_index_monthend_backfill.R — KRX 실지수 월말 백필 (지수-팩터 베타용)
## 대상: 코스피 / 코스피 200 / 코스닥 / 코스닥 150 (IDX_NM 정확 일치)
## 정책: 캐시 우선(.cache/krx/{board}_index/ — 일별 수집기와 동일 네이밍 재사용·기여),
##       부재 시 API 호출(krx_api 내장 0.5s 스로틀). 최근 N_M 완결월 월말만.
##=============================================================================
suppressMessages({ library(arrow); library(data.table) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/data/krx_data_collector.R")
OUT_DIR <- "outputs/ff5_kr"
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")
N_M <- 50L
TARGETS <- c("코스피", "코스피 200", "코스닥", "코스닥 150")

ud <- sort(unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)))
mgrid <- seq(as.Date("2004-12-01"), max(ud), by = "1 month")
me <- unique(as.Date(vapply(mgrid, function(d) { m0 <- as.Date(cut(d, "month")); e <- seq(m0, by = "1 month", length.out = 2)[2] - 1
  v <- ud[ud <= e & ud >= m0]; if (length(v)) as.character(max(v)) else NA_character_ }, character(1))))
me <- sort(me[!is.na(me)])
me <- me[format(me, "%Y-%m") < format(max(ud), "%Y-%m")]     # 완결월 월말만
me <- tail(me, N_M)
wf("backfill 대상 월말 %d개 (%s..%s)", length(me), format(min(me)), format(max(me)))

get_board <- function(d, board) {
  ds <- format(d, "%Y%m%d")
  cdir <- file.path(".cache/krx", sprintf("%s_index", board))
  dir.create(cdir, recursive = TRUE, showWarnings = FALSE)
  cf <- file.path(cdir, sprintf("%s_index_%s.parquet", board, ds))
  if (file.exists(cf)) return(as.data.table(read_parquet(cf)))
  x <- if (board == "kospi") krx_kospi_index(ds) else krx_kosdaq_index(ds)
  if (!is.null(x) && nrow(x)) { x <- as.data.table(x); write_parquet(x, cf); return(x) }
  NULL
}

rows <- list(); n_api <- 0L
for (d in me) {
  d <- as.Date(d, origin = "1970-01-01")
  for (bd in c("kospi", "kosdaq")) {
    cf_exists <- file.exists(file.path(".cache/krx", sprintf("%s_index", bd), sprintf("%s_index_%s.parquet", bd, format(d, "%Y%m%d"))))
    x <- tryCatch(get_board(d, bd), error = function(e) NULL)
    if (!cf_exists && !is.null(x)) n_api <- n_api + 1L
    if (is.null(x) || !nrow(x)) next
    x <- x[IDX_NM %in% TARGETS]
    if (!nrow(x)) next
    x[, close := as.numeric(gsub(",", "", CLSPRC_IDX))]
    rows[[paste(format(d), bd)]] <- x[, .(Date = d, idx = IDX_NM, close)]
  }
}
IX <- rbindlist(rows)
wf("수집: %d행 | API 신규호출 %d | 지수별 월수:", nrow(IX), n_api)
print(IX[, .N, by = idx])
write_parquet(IX, file.path(OUT_DIR, "krx_index_monthend.parquet"))
wf("[krx_index_backfill] done -> %s", file.path(OUT_DIR, "krx_index_monthend.parquet"))
