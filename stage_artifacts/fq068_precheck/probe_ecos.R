## ECOS 수출물가지수(반도체) 가용성 확인 — 통계표 목록 조회
suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/data/data_collector_ecos.R")
say <- function(fmt,...) cat(sprintf(paste0("[ecos] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY"); if (!nzchar(key)) key <- ECOS_API_KEY

## 수출입물가지수 통계표: 402Y014(수출물가지수) / 402Y015 등. 항목 목록 조회
for (st in c("402Y014","402Y015","404Y014")) {
  u <- sprintf("https://ecos.bok.or.kr/api/StatisticItemList/%s/json/kr/1/300/%s", key, st)
  r <- tryCatch(GET(u, timeout(30)), error=function(e) NULL)
  if (is.null(r) || status_code(r)!=200) { say("%s 조회 실패", st); next }
  j <- fromJSON(content(r,"text",encoding="UTF-8"))
  if (is.null(j$StatisticItemList$row)) { say("%s 항목 없음 (%s)", st,
      paste(names(j), collapse=",")); next }
  d <- as.data.table(j$StatisticItemList$row)
  say("=== %s : %d 항목 ===", st, nrow(d))
  hit <- d[grepl("반도체|메모리|전자", ITEM_NAME)]
  if (nrow(hit)) print(hit[, .(ITEM_CODE, ITEM_NAME, CYCLE, START_TIME, END_TIME)])
  else say("  반도체 항목 없음 — 상위 5: %s", paste(head(d$ITEM_NAME,5), collapse=" / "))
}
