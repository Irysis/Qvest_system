## FQ-068b — ECOS 수출물가지수 반도체/장비 인출 (KR 직결·단기지연 재료)
suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[ecosF] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }

get_series <- function(st, item, lab, start="199001", end="202612") {
  u <- sprintf("https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/1/1000/%s/M/%s/%s/%s",
               key, st, start, end, item)
  r <- tryCatch(GET(u, timeout(40)), error=function(e) NULL)
  if (is.null(r) || status_code(r)!=200) { say("%s 실패 (HTTP %s)", lab,
      if (is.null(r)) "NA" else status_code(r)); return(NULL) }
  j <- fromJSON(content(r,"text",encoding="UTF-8"))
  row <- j$StatisticSearch$row
  if (is.null(row) || !length(row)) { say("%s 빈 결과", lab); return(NULL) }
  d <- as.data.table(row)[, .(ym=TIME, Value=as.numeric(DATA_VALUE))][!is.na(Value)]
  d[, `:=`(item=lab, Date=as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01")))]
  say("%-24s %4d개월  %s ~ %s  최신 %.2f", lab, nrow(d), min(d$ym), max(d$ym), tail(d$Value,1))
  d
}
L <- list(
  get_series("402Y014","3091AA",   "수출물가_반도체"),
  get_series("402Y014","309112AA", "수출물가_집적회로"),
  get_series("402Y014","311241AA", "수출물가_반도체장비"),
  get_series("402Y014","31124AA",  "수출물가_반도체디스플레이장비")
)
L <- Filter(Negate(is.null), L)
if (length(L)) {
  A <- rbindlist(L); write_parquet(A, file.path(OUT,"fq068b_ecos_semi.parquet"))
  say("저장: fq068b_ecos_semi.parquet (%d행 · %d계열)", nrow(A), uniqueN(A$item))
} else say("★가용 계열 0")
