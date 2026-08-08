suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[ecos2] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }

fetch_items <- function(st) {
  out <- list(); i <- 1L
  repeat {
    u <- sprintf("https://ecos.bok.or.kr/api/StatisticItemList/%s/json/kr/%d/%d/%s", key, i, i+299L, st)
    r <- tryCatch(GET(u, timeout(30)), error=function(e) NULL)
    if (is.null(r) || status_code(r)!=200) break
    j <- fromJSON(content(r,"text",encoding="UTF-8"))
    row <- j$StatisticItemList$row
    if (is.null(row) || !length(row)) break
    d <- as.data.table(row); out[[length(out)+1L]] <- d
    if (nrow(d) < 300) break
    i <- i + 300L; if (i > 3000L) break
  }
  if (length(out)) rbindlist(out, fill=TRUE) else NULL
}
for (st in c("402Y014","402Y015")) {
  d <- fetch_items(st)
  if (is.null(d)) { say("%s 실패", st); next }
  say("=== %s : 전체 %d 항목 ===", st, nrow(d))
  hit <- d[grepl("반도체|메모리|D램|디램|집적", ITEM_NAME)]
  if (nrow(hit)) print(unique(hit[, .(ITEM_CODE, ITEM_NAME, CYCLE, START_TIME, END_TIME)]))
  else {
    say("  반도체 직접 항목 없음. 전자·IT 계열 후보:")
    print(unique(d[grepl("전자|정보통신|컴퓨터|전기", ITEM_NAME), .(ITEM_CODE, ITEM_NAME)])[1:min(10,.N)])
  }
}
