suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[069b] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }
for (st in c("512Y007","512Y008")) {
  out <- list(); i <- 1L
  repeat {
    u <- sprintf("https://ecos.bok.or.kr/api/StatisticItemList/%s/json/kr/%d/%d/%s", key, i, i+299L, st)
    r <- tryCatch(GET(u, timeout(30)), error=function(e) NULL)
    if (is.null(r) || status_code(r)!=200) break
    j <- fromJSON(content(r,"text",encoding="UTF-8")); row <- j$StatisticItemList$row
    if (is.null(row) || !length(row)) break
    d <- as.data.table(row); out[[length(out)+1L]] <- d
    if (nrow(d) < 300) break
    i <- i + 300L; if (i > 2000L) break
  }
  if (!length(out)) { say("%s 실패", st); next }
  D <- rbindlist(out, fill=TRUE)
  say("=== %s : 항목 %d (컬럼 %s) ===", st, nrow(D), paste(head(names(D),6), collapse=","))
  lv <- unique(D[, .(GRP_CODE=if("GRP_CODE" %in% names(D)) GRP_CODE else NA,
                     ITEM_CODE, ITEM_NAME, CYCLE, START_TIME, END_TIME)])
  say("업종 항목 %d개 (샘플 24):", nrow(lv))
  print(head(lv[, .(ITEM_CODE, ITEM_NAME, START_TIME, END_TIME)], 24))
}
