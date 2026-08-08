## FQ-068 — 반도체 PPI 인출 (공유 캐시 미변형, stage_artifacts 로컬 저장)
suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[fq068] ",fmt,"\n"),...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/data/data_collector_fred.R")

cands <- c(
  PCU334413334413 = "반도체 PPI (Semiconductor & related device mfg)",
  PCU33443344     = "반도체·전자부품 PPI (상위 카테고리)",
  WPU117403       = "반도체 WPI (구계열)",
  IPG3344S        = "반도체 산업생산 (Industrial Production: Semiconductor)"
)
got <- list()
for (id in names(cands)) {
  x <- tryCatch(.fred_fetch_series(id, start_date="2000-01-01"), error=function(e) NULL)
  if (is.null(x) || !nrow(x)) { say("%-16s 실패/빈결과", id); next }
  say("%-16s %4d행  %s ~ %s  최신값 %.2f", id, nrow(x), min(x$Date), max(x$Date), tail(x$Value,1))
  x[, Series_ID := id]; got[[id]] <- x
}
if (length(got)) {
  A <- rbindlist(got)
  write_parquet(A, file.path(OUT,"fq068_ppi_raw.parquet"))
  say("저장: fq068_ppi_raw.parquet (%d행, %d시리즈)", nrow(A), uniqueN(A$Series_ID))
} else say("★가용 시리즈 0 — 데이터 게이트 실재")
