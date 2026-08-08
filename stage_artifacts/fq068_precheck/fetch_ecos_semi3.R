suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck"); source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[ecosF3] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }
get_all <- function(st, item, lab) {
  out <- list(); i <- 1L
  repeat {
    u <- sprintf("https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/%d/%d/%s/M/199001/202612/%s",
                 key, i, i+999L, st, item)
    r <- tryCatch(GET(u, timeout(40)), error=function(e) NULL)
    if (is.null(r) || status_code(r)!=200) break
    j <- fromJSON(content(r,"text",encoding="UTF-8")); row <- j$StatisticSearch$row
    if (is.null(row) || !length(row)) break
    d <- as.data.table(row); out[[length(out)+1L]] <- d
    if (nrow(d) < 1000) break
    i <- i + 1000L; if (i > 8000L) break
  }
  if (!length(out)) return(NULL)
  D <- rbindlist(out, fill=TRUE)
  D <- D[, .(ym=TIME, ccy=ITEM_CODE2, ccy_name=ITEM_NAME2, Value=as.numeric(DATA_VALUE))]
  D <- unique(D)[!is.na(Value)][order(ccy, ym)]
  D[, item := lab]
  for (c in unique(D$ccy)) {
    s <- D[ccy==c]
    say("%-22s [%s %-10s] %4d개월 %s~%s 최신 %.2f", lab, c, s$ccy_name[1], nrow(s), min(s$ym), max(s$ym), tail(s$Value,1))
  }
  D
}
L <- Filter(Negate(is.null), list(
  get_all("402Y014","3091AA","반도체"),
  get_all("402Y014","311241AA","반도체장비"),
  get_all("402Y014","31124AA","반도체디스플레이장비")))
A <- rbindlist(L, fill=TRUE); write_parquet(A, file.path(OUT,"fq068b_ecos_semi.parquet"))
say("저장 %d행 · item %d · ccy %s", nrow(A), uniqueN(A$item), paste(unique(A$ccy), collapse=","))
