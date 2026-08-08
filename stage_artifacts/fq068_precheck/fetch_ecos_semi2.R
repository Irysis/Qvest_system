suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck"); source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[ecosF2] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }

get_all <- function(st, item, lab, start="199001", end="202612") {
  out <- list(); i <- 1L
  repeat {
    u <- sprintf("https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/%d/%d/%s/M/%s/%s/%s",
                 key, i, i+999L, st, start, end, item)
    r <- tryCatch(GET(u, timeout(40)), error=function(e) NULL)
    if (is.null(r) || status_code(r)!=200) break
    j <- fromJSON(content(r,"text",encoding="UTF-8")); row <- j$StatisticSearch$row
    if (is.null(row) || !length(row)) break
    d <- as.data.table(row); out[[length(out)+1L]] <- d
    if (nrow(d) < 1000) break
    i <- i + 1000L; if (i > 8000L) break
  }
  if (!length(out)) { say("%s 실패", lab); return(NULL) }
  D <- rbindlist(out, fill=TRUE)
  ## ★중복 확인: 같은 TIME 이 여러 행이면 하위 항목이 섞인 것
  cols <- intersect(c("ITEM_CODE1","ITEM_NAME1","ITEM_CODE2","ITEM_NAME2"), names(D))
  dup <- D[, .N, by=TIME][N > 1]
  if (nrow(dup)) {
    say("%s ★중복 %d개월 — 하위항목 혼입. 조합: %s", lab, nrow(dup),
        paste(unique(D[, do.call(paste, c(.SD, sep="|")), .SDcols=cols])[1:min(4,.N)], collapse=" / "))
    D <- D[get(cols[1]) == item]   # 정확히 요청한 코드만
  }
  d <- unique(D[, .(ym=TIME, Value=as.numeric(DATA_VALUE))])[!is.na(Value)][order(ym)]
  d[, `:=`(item=lab, Date=as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01")))]
  say("%-28s %4d개월  %s ~ %s  최신 %.2f", lab, nrow(d), min(d$ym), max(d$ym), tail(d$Value,1))
  d
}
L <- Filter(Negate(is.null), list(
  get_all("402Y014","3091AA",   "수출물가_반도체"),
  get_all("402Y014","311241AA", "수출물가_반도체장비"),
  get_all("402Y014","31124AA",  "수출물가_반도체디스플레이장비")))
if (length(L)) { A <- rbindlist(L); write_parquet(A, file.path(OUT,"fq068b_ecos_semi.parquet"))
  say("저장 %d행 · %d계열", nrow(A), uniqueN(A$item)) }
